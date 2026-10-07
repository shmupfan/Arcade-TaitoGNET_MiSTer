#!/usr/bin/env python3
"""Read MAME CHD (version 5) hard-disk images in pure Python.

Standard library only (zlib, lzma), so it can also run under Pyodide (where
lzma is a separate package to load). Written from MAME 0.288
src/lib/util/chd.cpp, chdcodec.cpp, huffman.cpp, bitstream.h and flac.cpp.
Supports what MAME's hard-disk CHDs use: the compressed v5 map (and the plain
uncompressed map), hunks stored with the zlib, lzma, huff and flac codecs
(chdman's defaults for hard disks), uncompressed hunks, copies of other hunks
in the same file, and the metadata chain. Every hunk is checked against its
CRC16 in the map. Parent CHDs (diff files), v3/v4 files and the zstd, CD and
A/V codecs are not supported and raise ChdError.

  c = chd.open("shikigam.chd")
  c.logical_bytes, c.hunk_bytes, c.sha1     # c.sha1 is the header SHA1 field
  c.read_hunk(0)                            # one hunk, bytes
  c.metadata("IDNT")                        # metadata entry by tag (and index)
  for block in c.iter_raw(): ...            # the raw image, hunk by hunk

  python3 chd.py <file.chd> [<out.raw>]     # print info, optionally extract
"""
import lzma
import struct
import sys
import zlib

V5_HEADER_SIZE = 124

# v5 compressed map entry types (chd.cpp)
COMPRESSION_TYPE_0, COMPRESSION_TYPE_1, COMPRESSION_TYPE_2, COMPRESSION_TYPE_3 = 0, 1, 2, 3
COMPRESSION_NONE = 4
COMPRESSION_SELF = 5
COMPRESSION_PARENT = 6
COMPRESSION_RLE_SMALL = 7
COMPRESSION_RLE_LARGE = 8
COMPRESSION_SELF_0 = 9
COMPRESSION_SELF_1 = 10
COMPRESSION_PARENT_SELF = 11
COMPRESSION_PARENT_0 = 12
COMPRESSION_PARENT_1 = 13

CODEC_NAMES = {b"zlib": "Deflate", b"lzma": "LZMA", b"huff": "Huffman", b"flac": "FLAC",
               b"zstd": "Zstandard", b"cdzl": "CD Deflate", b"cdlz": "CD LZMA",
               b"cdfl": "CD FLAC", b"cdzs": "CD Zstandard", b"avhu": "A/V Huffman"}


class ChdError(Exception):
    pass


# ---------------------------------------------------------------- CRC16

def _crc16_table():
    t = []
    for i in range(256):
        c = i << 8
        for _ in range(8):
            c = ((c << 1) ^ 0x1021) if c & 0x8000 else (c << 1)
        t.append(c & 0xffff)
    return t


_CRC16 = _crc16_table()


def crc16(data):
    """CRC-16-CCITT (polynomial 1021h, start FFFFh), MAME's crc16_creator"""
    crc = 0xffff
    t = _CRC16
    for b in data:
        crc = ((crc << 8) & 0xff00) ^ t[(crc >> 8) ^ b]
    return crc


# ---------------------------------------------------------------- bit reader

class BitReader:
    """MSB-first bit reader (bitstream_in); reads past the end return zeros"""

    def __init__(self, data):
        self.data = data
        self.pos = 0                 # bit position

    def read(self, n):
        if n == 0:
            return 0
        p = self.pos
        i = p >> 3
        chunk = self.data[i:i + 5]
        if len(chunk) < 5:
            chunk = chunk + bytes(5 - len(chunk))
        v = int.from_bytes(chunk, "big")
        self.pos = p + n
        return (v >> (40 - (p & 7) - n)) & ((1 << n) - 1)


# ---------------------------------------------------------------- Huffman

def _canonical_codes(lengths, maxbits):
    """assign_canonical_codes: code value for each symbol (None if unused)"""
    histo = [0] * 33
    for n in lengths:
        if n > maxbits:
            raise ChdError("huffman: code length above maximum")
        histo[n] += 1
    start = 0
    for codelen in range(32, 0, -1):
        nxt = (start + histo[codelen]) >> 1
        if codelen != 1 and nxt * 2 != start + histo[codelen]:
            raise ChdError("huffman: inconsistent code lengths")
        histo[codelen] = start
        start = nxt
    codes = []
    for n in lengths:
        if n > 0:
            codes.append(histo[n])
            histo[n] += 1
        else:
            codes.append(None)
    return codes


def _lookup(lengths, maxbits):
    """build_lookup_table, as two flat lists indexed by maxbits of input:
    the symbol and its code length. Unfilled entries decode as symbol 0 with
    length 0, as in MAME."""
    codes = _canonical_codes(lengths, maxbits)
    size = 1 << maxbits
    sym = [0] * size
    ln = [0] * size
    for s, (n, c) in enumerate(zip(lengths, codes)):
        if n > 0:
            shift = maxbits - n
            lo, hi = c << shift, (c + 1) << shift
            sym[lo:hi] = [s] * (hi - lo)
            ln[lo:hi] = [n] * (hi - lo)
    return sym, ln


class HuffmanDecoder:
    """huffman_decoder<numcodes, maxbits>. The lookup table is indexed by the
    longest code length in use (tablebits) rather than maxbits: the codes are
    prefix-free, so the symbols decoded are the same as MAME's maxbits peek,
    and the table is smaller."""

    def __init__(self, numcodes, maxbits):
        self.numcodes = numcodes
        self.maxbits = maxbits
        self.sym = self.len = None
        self.tablebits = 0

    def _set_lengths(self, lengths):
        _canonical_codes(lengths, self.maxbits)        # MAME's consistency checks
        self.tablebits = max(1, max(lengths))
        self.sym, self.len = _lookup(lengths, self.tablebits)

    def decode_one(self, bits):
        v = bits.read(self.tablebits)
        bits.pos -= self.tablebits - self.len[v]
        return self.sym[v]

    def import_tree_rle(self, bits):
        numbits = 5 if self.maxbits >= 16 else 4 if self.maxbits >= 8 else 3
        lengths = []
        while len(lengths) < self.numcodes:
            nodebits = bits.read(numbits)
            if nodebits != 1:
                lengths.append(nodebits)
            else:
                nodebits = bits.read(numbits)
                if nodebits == 1:
                    lengths.append(1)
                else:
                    lengths.extend([nodebits] * (bits.read(numbits) + 3))
        if len(lengths) != self.numcodes:
            raise ChdError("huffman: bad RLE tree")
        self._set_lengths(lengths)

    def import_tree_huffman(self, bits):
        small = HuffmanDecoder(24, 6)
        sl = [0] * 24
        sl[0] = bits.read(3)
        start = bits.read(3) + 1
        count = 0
        for index in range(1, 24):
            if index < start or count == 7:
                sl[index] = 0
            else:
                count = bits.read(3)
                sl[index] = 0 if count == 7 else count
        small._set_lengths(sl)
        temp = self.numcodes - 9
        rlefullbits = 0
        while temp:
            temp >>= 1
            rlefullbits += 1
        lengths = []
        last = 0
        while len(lengths) < self.numcodes:
            value = small.decode_one(bits)
            if value != 0:
                last = value - 1
                lengths.append(last)
            else:
                count = bits.read(3) + 2
                if count == 7 + 2:
                    count += bits.read(rlefullbits)
                lengths.extend([last] * min(count, self.numcodes - len(lengths)))
        self._set_lengths(lengths)


def huffman_8bit_decode(src, destlen):
    """huffman_8bit_decoder::decode (codec 'huff'): a Huffman-coded tree of
    code lengths, then destlen 8-bit symbols, maximum code length 16"""
    bits = BitReader(src)
    dec = HuffmanDecoder(256, 16)
    dec.import_tree_huffman(bits)
    sym, ln, maxlen = dec.sym, dec.len, dec.tablebits
    mask = (1 << maxlen) - 1
    data = src
    n = len(data)
    i = bits.pos >> 3
    acc = data[i] & (0xff >> (bits.pos & 7)) if i < n else 0
    have = 8 - (bits.pos & 7)
    i += 1
    out = bytearray(destlen)
    for k in range(destlen):
        while have < maxlen:
            acc = (acc << 8) | (data[i] if i < n else 0)
            i += 1
            have += 8
        v = (acc >> (have - maxlen)) & mask
        out[k] = sym[v]
        have -= ln[v]
        acc &= (1 << have) - 1
    if (i * 8 - have + 7) >> 3 > n:
        raise ChdError("huffman: input too short")
    return bytes(out)


# ---------------------------------------------------------------- FLAC

class _Bits:
    """FLAC bit reader over a '0'/'1' string (fast slicing and find in C)"""

    def __init__(self, data):
        self.s = format(int.from_bytes(data, "big"), "0%db" % (len(data) * 8)) if data else ""
        self.p = 0

    def u(self, n):
        if n == 0:
            return 0
        p = self.p
        self.p = p + n
        if self.p > len(self.s):
            raise ChdError("flac: data ends early")
        return int(self.s[p:p + n], 2)

    def s_(self, n):
        v = self.u(n)
        return v - (1 << n) if n and v >> (n - 1) else v

    def unary(self):
        """count of 0 bits before the next 1"""
        q = self.s.find("1", self.p)
        if q < 0:
            raise ChdError("flac: data ends early")
        n = q - self.p
        self.p = q + 1
        return n

    def align(self):
        self.p = (self.p + 7) & ~7


def _flac_residual(b, blocksize, order):
    method = b.u(2)
    if method > 1:
        raise ChdError("flac: bad residual coding method")
    pbits, escape = (4, 15) if method == 0 else (5, 31)
    porder = b.u(4)
    out = []
    s = b.s
    for part in range(1 << porder):
        n = (blocksize >> porder) - (order if part == 0 else 0)
        k = b.u(pbits)
        if k == escape:
            nb = b.u(5)
            out.extend(b.s_(nb) for _ in range(n))
            continue
        p = b.p
        find = s.find
        app = out.append
        if k == 0:
            for _ in range(n):
                q = find("1", p)
                u = q - p
                p = q + 1
                app((u >> 1) ^ -(u & 1))
        else:
            for _ in range(n):
                q = find("1", p)
                u = ((q - p) << k) | int(s[q + 1:q + 1 + k], 2)
                p = q + 1 + k
                app((u >> 1) ^ -(u & 1))
        if p > len(s):
            raise ChdError("flac: data ends early")
        b.p = p
    return out


def _flac_subframe(b, blocksize, bps):
    if b.u(1):
        raise ChdError("flac: bad subframe padding")
    t = b.u(6)
    wasted = 0
    if b.u(1):
        wasted = b.unary() + 1
        bps -= wasted
    if t == 0:                                    # CONSTANT
        x = [b.s_(bps)] * blocksize
    elif t == 1:                                  # VERBATIM
        x = [b.s_(bps) for _ in range(blocksize)]
    elif 8 <= t <= 12:                            # FIXED, order 0 to 4
        order = t - 8
        x = [b.s_(bps) for _ in range(order)]
        res = _flac_residual(b, blocksize, order)
        app = x.append
        if order == 0:
            x = res
        elif order == 1:
            a = x[-1]
            for r in res:
                a += r
                app(a)
        elif order == 2:
            for r in res:
                app(r + 2 * x[-1] - x[-2])
        elif order == 3:
            for r in res:
                app(r + 3 * x[-1] - 3 * x[-2] + x[-3])
        else:
            for r in res:
                app(r + 4 * x[-1] - 6 * x[-2] + 4 * x[-3] - x[-4])
    elif t >= 32:                                 # LPC, order 1 to 32
        order = t - 31
        x = [b.s_(bps) for _ in range(order)]
        precision = b.u(4) + 1
        if precision == 16:
            raise ChdError("flac: bad LPC precision")
        shift = b.s_(5)
        if shift < 0:
            raise ChdError("flac: negative LPC shift")
        coefs = [b.s_(precision) for _ in range(order)]
        res = _flac_residual(b, blocksize, order)
        rc = coefs[::-1]                          # oldest sample first
        app = x.append
        i = 0
        for r in res:
            w = x[i:i + order]
            app(r + (sum([c * v for c, v in zip(rc, w)]) >> shift))
            i += 1
    else:
        raise ChdError(f"flac: reserved subframe type {t}")
    if wasted:
        x = [v << wasted for v in x]
    return x


def flac_decode(src, destlen):
    """chd_flac_decompressor: 'L' or 'B' (byte order of the output words),
    then FLAC frames for 2 channels of 16-bit samples, without the stream
    header. MAME gives libFLAC a STREAMINFO of 44100 Hz, 2 channels, 16 bits
    and a block size from the hunk size; the frame headers here carry their
    own block size, and a "from STREAMINFO" sample size means 16 bits."""
    if src[:1] == b"L":
        order = "<"
    elif src[:1] == b"B":
        order = ">"
    else:
        raise ChdError("flac: bad byte order marker")
    want = destlen // 4                          # stereo sample pairs
    b = _Bits(src[1:])
    left, right = [], []
    while len(left) < want:
        b.align()
        if b.u(14) != 0x3ffe:
            raise ChdError("flac: frame sync not found")
        b.u(2)                                    # reserved, blocking strategy
        bscode, srcode = b.u(4), b.u(4)
        chan, sscode = b.u(4), b.u(3)
        b.u(1)
        lead = b.u(8)                             # UTF-8 style frame number
        extra = 0
        while lead & (0x80 >> extra):
            extra += 1
        for _ in range(max(extra - 1, 0)):
            b.u(8)
        if bscode == 0:
            raise ChdError("flac: reserved block size")
        elif bscode == 1:
            blocksize = 192
        elif bscode <= 5:
            blocksize = 576 << (bscode - 2)
        elif bscode == 6:
            blocksize = b.u(8) + 1
        elif bscode == 7:
            blocksize = b.u(16) + 1
        else:
            blocksize = 256 << (bscode - 8)
        if srcode == 12:
            b.u(8)
        elif srcode in (13, 14):
            b.u(16)
        elif srcode == 15:
            raise ChdError("flac: bad sample rate code")
        bps = {0: 16, 1: 8, 2: 12, 4: 16, 5: 20, 6: 24, 7: 32}.get(sscode)
        if bps is None:
            raise ChdError("flac: bad sample size")
        b.u(8)                                    # header CRC-8
        if chan == 1:                             # independent stereo
            a = _flac_subframe(b, blocksize, bps)
            c = _flac_subframe(b, blocksize, bps)
        elif chan == 8:                           # left, side
            a = _flac_subframe(b, blocksize, bps)
            sd = _flac_subframe(b, blocksize, bps + 1)
            c = [x - y for x, y in zip(a, sd)]
        elif chan == 9:                           # side, right
            sd = _flac_subframe(b, blocksize, bps + 1)
            c = _flac_subframe(b, blocksize, bps)
            a = [x + y for x, y in zip(sd, c)]
        elif chan == 10:                          # mid, side
            m = _flac_subframe(b, blocksize, bps)
            sd = _flac_subframe(b, blocksize, bps + 1)
            a, c = [], []
            for x, y in zip(m, sd):
                x = (x << 1) | (y & 1)
                a.append((x + y) >> 1)
                c.append((x - y) >> 1)
        else:
            raise ChdError(f"flac: channel layout {chan} is not 2-channel")
        if bps != 16:
            raise ChdError(f"flac: {bps}-bit samples (only 16-bit is supported)")
        b.align()
        b.u(16)                                   # frame CRC-16 (the hunk CRC is checked)
        left += a
        right += c
    inter = [0] * (2 * want)
    inter[0::2] = [v & 0xffff for v in left[:want]]
    inter[1::2] = [v & 0xffff for v in right[:want]]
    return struct.pack(order + "%dH" % (2 * want), *inter)


# ---------------------------------------------------------------- codecs

def _decompress_zlib(src, hunkbytes):
    d = zlib.decompressobj(-15)
    out = d.decompress(src, hunkbytes)
    if len(out) != hunkbytes:
        raise ChdError("zlib: wrong output length")
    return out


def _lzma_dict_size(hunkbytes):
    """LzmaEncProps_Normalize for level 8 with reduceSize = hunkbytes, as
    chd_lzma_compressor::configure_properties sets it up"""
    dict_size = 1 << 26
    if dict_size > hunkbytes:
        for i in range(11, 31):
            if hunkbytes <= (2 << i):
                return 2 << i
            if hunkbytes <= (3 << i):
                return 3 << i
    return dict_size


def _make_lzma(hunkbytes):
    filters = [{"id": lzma.FILTER_LZMA1, "dict_size": _lzma_dict_size(hunkbytes),
                "lc": 3, "lp": 0, "pb": 2}]

    def decompress(src, n):
        # MAME's LZMA hunks are raw LZMA1 without an end marker
        d = lzma.LZMADecompressor(lzma.FORMAT_RAW, filters=filters)
        out = d.decompress(src, n)
        if len(out) != n:
            raise ChdError("lzma: wrong output length")
        return out
    return decompress


# ---------------------------------------------------------------- the file

class Chd:
    def __init__(self, data):
        self.data = data
        h = data[:V5_HEADER_SIZE]
        if h[:8] != b"MComprHD":
            raise ChdError("not a CHD file")
        length, version = struct.unpack(">II", h[8:16])
        if version != 5:
            raise ChdError(f"CHD version {version}: only version 5 is supported "
                           "(chdman copy converts older files)")
        if length != V5_HEADER_SIZE:
            raise ChdError("bad v5 header length")
        self.compressors = [h[16 + 4 * k:20 + 4 * k] for k in range(4)]
        (self.logical_bytes, self.map_offset, self.meta_offset, self.hunk_bytes,
         self.unit_bytes) = struct.unpack(">QQQII", h[32:64])
        self.raw_sha1 = h[64:84].hex()
        self.sha1 = h[84:104].hex()
        self.parent_sha1 = h[104:124].hex()
        if self.hunk_bytes == 0:
            raise ChdError("hunk size is 0")
        self.hunk_count = (self.logical_bytes + self.hunk_bytes - 1) // self.hunk_bytes
        self.compressed = self.compressors[0] != b"\0\0\0\0"
        if int(self.parent_sha1, 16):
            raise ChdError("this CHD needs a parent CHD, which is not supported")
        self._codecs = []
        for tag in self.compressors:
            if tag == b"zlib":
                self._codecs.append(_decompress_zlib)
            elif tag == b"lzma":
                self._codecs.append(_make_lzma(self.hunk_bytes))
            elif tag == b"huff":
                self._codecs.append(huffman_8bit_decode)
            elif tag == b"flac":
                self._codecs.append(flac_decode)
            elif tag == b"\0\0\0\0":
                self._codecs.append(None)
            else:
                self._codecs.append(self._unsupported(tag))
        if self.compressed:
            self._read_compressed_map()
        else:
            self._map = struct.unpack_from(">%dI" % self.hunk_count, data, self.map_offset)

    @staticmethod
    def _unsupported(tag):
        name = CODEC_NAMES.get(tag, tag.decode("latin-1"))

        def f(src, n):
            raise ChdError(f"codec {tag.decode('latin-1')} ({name}) is not supported")
        return f

    def _read_compressed_map(self):
        """decompress_v5_map: one (type, length, offset, crc16) per hunk"""
        d = self.data
        mapbytes, = struct.unpack(">I", d[self.map_offset:self.map_offset + 4])
        firstoffs = int.from_bytes(d[self.map_offset + 4:self.map_offset + 10], "big")
        mapcrc, = struct.unpack(">H", d[self.map_offset + 10:self.map_offset + 12])
        lengthbits, selfbits, parentbits = d[self.map_offset + 12:self.map_offset + 15]
        bits = BitReader(d[self.map_offset + 16:self.map_offset + 16 + mapbytes])
        dec = HuffmanDecoder(16, 8)
        dec.import_tree_rle(bits)
        types = []
        lastcomp = 0
        rep = 0
        for _ in range(self.hunk_count):
            if rep > 0:
                types.append(lastcomp)
                rep -= 1
                continue
            val = dec.decode_one(bits)
            if val == COMPRESSION_RLE_SMALL:
                rep = 2 + dec.decode_one(bits)
                types.append(lastcomp)
            elif val == COMPRESSION_RLE_LARGE:
                rep = 2 + 16 + (dec.decode_one(bits) << 4)
                rep += dec.decode_one(bits)
                types.append(lastcomp)
            else:
                lastcomp = val
                types.append(val)
        entries = []
        raw = bytearray()
        cur = firstoffs
        last_self = 0
        last_parent = 0
        hb, ub = self.hunk_bytes, self.unit_bytes
        for hunk, t in enumerate(types):
            offset, length, crc = cur, 0, 0
            if t <= COMPRESSION_TYPE_3:
                length = bits.read(lengthbits)
                cur += length
                crc = bits.read(16)
            elif t == COMPRESSION_NONE:
                length = hb
                cur += length
                crc = bits.read(16)
            elif t == COMPRESSION_SELF:
                last_self = offset = bits.read(selfbits)
            elif t == COMPRESSION_PARENT:
                last_parent = offset = bits.read(parentbits)
            elif t in (COMPRESSION_SELF_0, COMPRESSION_SELF_1):
                if t == COMPRESSION_SELF_1:
                    last_self += 1
                t, offset = COMPRESSION_SELF, last_self
            elif t == COMPRESSION_PARENT_SELF:
                t = COMPRESSION_PARENT
                last_parent = offset = hunk * hb // ub
            elif t in (COMPRESSION_PARENT_0, COMPRESSION_PARENT_1):
                if t == COMPRESSION_PARENT_1:
                    last_parent += hb // ub
                t, offset = COMPRESSION_PARENT, last_parent
            else:
                raise ChdError(f"map: unknown entry type {t} at hunk {hunk}")
            entries.append((t, length, offset, crc))
            raw += bytes([t]) + length.to_bytes(3, "big") + offset.to_bytes(6, "big") + \
                crc.to_bytes(2, "big")
        if crc16(raw) != mapcrc:
            raise ChdError("map CRC mismatch (damaged file?)")
        self._map = entries

    def hunk_type_counts(self):
        """{codec or entry name: hunk count}, like chdman info -v"""
        names = {COMPRESSION_NONE: "uncompressed", COMPRESSION_SELF: "self",
                 COMPRESSION_PARENT: "parent"}
        out = {}
        if not self.compressed:
            return {"uncompressed": self.hunk_count}
        for t, _, _, _ in self._map:
            k = self.compressors[t].decode("latin-1") if t <= 3 else names[t]
            out[k] = out.get(k, 0) + 1
        return out

    def read_hunk(self, hunk, _depth=0):
        if not 0 <= hunk < self.hunk_count:
            raise ChdError(f"hunk {hunk} out of range")
        hb = self.hunk_bytes
        d = self.data
        if not self.compressed:
            off = self._map[hunk] * hb
            return bytes(d[off:off + hb]) if off else bytes(hb)
        t, length, offset, crc = self._map[hunk]
        if t <= COMPRESSION_TYPE_3:
            try:
                out = self._codecs[t](bytes(d[offset:offset + length]), hb)
            except (zlib.error, lzma.LZMAError, ValueError, IndexError, ChdError) as e:
                raise ChdError(f"hunk {hunk}: {self.compressors[t].decode('latin-1')} data is damaged ({e})")
        elif t == COMPRESSION_NONE:
            out = bytes(d[offset:offset + hb])
        elif t == COMPRESSION_SELF:
            if _depth > 16:
                raise ChdError(f"hunk {hunk}: self reference loop")
            return self.read_hunk(offset, _depth + 1)
        else:
            raise ChdError(f"hunk {hunk} is stored in a parent CHD, which is not supported")
        if len(out) != hb or crc16(out) != crc:
            raise ChdError(f"hunk {hunk}: CRC mismatch (damaged file?)")
        return out

    def iter_raw(self):
        """the logical image, one hunk at a time (last one trimmed)"""
        left = self.logical_bytes
        # keep the hunks that later hunks copy, so each is decoded once
        wanted = set()
        if self.compressed:
            wanted = {e[2] for e in self._map if e[0] == COMPRESSION_SELF}
        cache = {}
        for h in range(self.hunk_count):
            e = self._map[h] if self.compressed else None
            if e and e[0] == COMPRESSION_SELF and e[2] in cache:
                b = cache[e[2]]
            else:
                b = self.read_hunk(h)
            if h in wanted:
                cache[h] = b
            yield b[:left] if left < len(b) else b
            left -= len(b)

    def read_all(self):
        return b"".join(self.iter_raw())

    def metadata(self, tag, index=0):
        """metadata entry data by 4-character tag (e.g. 'IDNT', 'KEY ',
        'CIS '), the index-th match; ChdError if absent"""
        want = tag.encode("latin-1") if isinstance(tag, str) else tag
        if len(want) != 4:
            raise ChdError("metadata tag must be 4 characters")
        off = self.meta_offset
        seen = 0
        while off:
            mtag = self.data[off:off + 4]
            length = int.from_bytes(self.data[off + 5:off + 8], "big")
            nxt, = struct.unpack(">Q", self.data[off + 8:off + 16])
            if mtag == want:
                if seen == index:
                    return bytes(self.data[off + 16:off + 16 + length])
                seen += 1
            off = nxt
        raise ChdError(f"metadata {want.decode('latin-1')!r} index {index} not found")


def open(path_or_data):   # noqa: A001  (chd.open, like the built-in for files)
    """a Chd from a file path or from the file's bytes"""
    if isinstance(path_or_data, (bytes, bytearray, memoryview)):
        return Chd(path_or_data)
    import builtins
    with builtins.open(path_or_data, "rb") as f:
        return Chd(f.read())


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    c = open(sys.argv[1])
    print(f"Logical size: {c.logical_bytes:,} bytes")
    print(f"Hunk size:    {c.hunk_bytes:,} bytes ({c.hunk_count:,} hunks)")
    print("Compression: ", ", ".join(t.decode("latin-1") for t in c.compressors if t != b"\0\0\0\0") or "none")
    print("Hunks:       ", ", ".join(f"{k} {v:,}" for k, v in sorted(c.hunk_type_counts().items())))
    print(f"SHA1:         {c.sha1}")
    print(f"Data SHA1:    {c.raw_sha1}")
    if len(sys.argv) == 3:
        import builtins
        with builtins.open(sys.argv[2], "wb") as f:
            for b in c.iter_raw():
                f.write(b)


if __name__ == "__main__":
    main()
