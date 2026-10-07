// MAME CHD version 5 hard-disk reader, ported from tools/gnet/chd.py (which
// is written from MAME 0.288 chd.cpp, chdcodec.cpp, huffman.cpp, bitstream.h
// and flac.cpp). Same scope: the compressed v5 map (and the plain map), hunks
// stored with zlib, lzma, huff and flac, uncompressed hunks, copies of other
// hunks in the same file, and the metadata chain. Every hunk is checked against
// its CRC16 in the map.

import { ConvertError, crc16, transform } from "./util.js";
import { makeLzmaDecoder } from "./lzma.js";
import { flacDecode } from "./flac.js";

export const V5_HEADER_SIZE = 124;

const COMPRESSION_TYPE_3 = 3;
const COMPRESSION_NONE = 4;
const COMPRESSION_SELF = 5;
const COMPRESSION_PARENT = 6;
const COMPRESSION_RLE_SMALL = 7;
const COMPRESSION_RLE_LARGE = 8;
const COMPRESSION_SELF_0 = 9;
const COMPRESSION_SELF_1 = 10;
const COMPRESSION_PARENT_SELF = 11;
const COMPRESSION_PARENT_0 = 12;
const COMPRESSION_PARENT_1 = 13;

const CODEC_NAMES = {
  zlib: "Deflate", lzma: "LZMA", huff: "Huffman", flac: "FLAC", zstd: "Zstandard",
  cdzl: "CD Deflate", cdlz: "CD LZMA", cdfl: "CD FLAC", cdzs: "CD Zstandard", avhu: "A/V Huffman",
};

const tagStr = (b) => String.fromCharCode(...b);
const hexOf = (b) => Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");

// ---------------------------------------------------------------- bit reader

// MSB-first bit reader (bitstream_in); reads past the end return zeros
class BitReader {
  constructor(data) {
    this.data = data;
    this.pos = 0;
  }

  read(n) {
    let v = 0;
    const d = this.data;
    let p = this.pos;
    this.pos = p + n;
    while (n > 0) {
      const i = p >> 3;
      const byte = i < d.length ? d[i] : 0;
      const avail = 8 - (p & 7);
      const take = avail < n ? avail : n;
      v = v * (1 << take) + ((byte >> (avail - take)) & ((1 << take) - 1));
      p += take;
      n -= take;
    }
    return v;
  }
}

// ---------------------------------------------------------------- Huffman

// assign_canonical_codes: code value for each symbol (-1 if unused)
function canonicalCodes(lengths, maxbits) {
  const histo = new Array(33).fill(0);
  for (const n of lengths) {
    if (n > maxbits) throw new ConvertError("huffman: code length above maximum");
    histo[n]++;
  }
  let start = 0;
  for (let codelen = 32; codelen > 0; codelen--) {
    const nxt = (start + histo[codelen]) >> 1;
    if (codelen !== 1 && nxt * 2 !== start + histo[codelen]) throw new ConvertError("huffman: inconsistent code lengths");
    histo[codelen] = start;
    start = nxt;
  }
  return lengths.map((n) => (n > 0 ? histo[n]++ : -1));
}

class HuffmanDecoder {
  constructor(numcodes, maxbits) {
    this.numcodes = numcodes;
    this.maxbits = maxbits;
    this.tablebits = 0;
  }

  setLengths(lengths) {
    const codes = canonicalCodes(lengths, this.maxbits);
    let tb = 1;
    for (const n of lengths) if (n > tb) tb = n;
    this.tablebits = tb;
    const size = 1 << tb;
    this.sym = new Uint16Array(size);
    this.len = new Uint8Array(size);
    for (let s = 0; s < lengths.length; s++) {
      const n = lengths[s];
      if (n > 0) {
        const shift = tb - n;
        const lo = codes[s] << shift, hi = Math.min((codes[s] + 1) << shift, size);
        this.sym.fill(s, lo, hi);
        this.len.fill(n, lo, hi);
      }
    }
  }

  decodeOne(bits) {
    const v = bits.read(this.tablebits);
    bits.pos -= this.tablebits - this.len[v];
    return this.sym[v];
  }

  importTreeRle(bits) {
    const numbits = this.maxbits >= 16 ? 5 : this.maxbits >= 8 ? 4 : 3;
    const lengths = [];
    while (lengths.length < this.numcodes) {
      let nodebits = bits.read(numbits);
      if (nodebits !== 1) {
        lengths.push(nodebits);
      } else {
        nodebits = bits.read(numbits);
        if (nodebits === 1) {
          lengths.push(1);
        } else {
          const rep = bits.read(numbits) + 3;
          for (let i = 0; i < rep; i++) lengths.push(nodebits);
        }
      }
    }
    if (lengths.length !== this.numcodes) throw new ConvertError("huffman: bad RLE tree");
    this.setLengths(lengths);
  }

  importTreeHuffman(bits) {
    const small = new HuffmanDecoder(24, 6);
    const sl = new Array(24).fill(0);
    sl[0] = bits.read(3);
    const start = bits.read(3) + 1;
    let count = 0;
    for (let index = 1; index < 24; index++) {
      if (index < start || count === 7) {
        sl[index] = 0;
      } else {
        count = bits.read(3);
        sl[index] = count === 7 ? 0 : count;
      }
    }
    small.setLengths(sl);
    let temp = this.numcodes - 9;
    let rlefullbits = 0;
    while (temp) {
      temp >>= 1;
      rlefullbits++;
    }
    const lengths = [];
    let last = 0;
    while (lengths.length < this.numcodes) {
      const value = small.decodeOne(bits);
      if (value !== 0) {
        last = value - 1;
        lengths.push(last);
      } else {
        let c = bits.read(3) + 2;
        if (c === 7 + 2) c += bits.read(rlefullbits);
        c = Math.min(c, this.numcodes - lengths.length);
        for (let i = 0; i < c; i++) lengths.push(last);
      }
    }
    this.setLengths(lengths);
  }
}

// huffman_8bit_decoder::decode (codec 'huff')
export function huffman8bitDecode(src, destlen) {
  const bits = new BitReader(src);
  const dec = new HuffmanDecoder(256, 16);
  dec.importTreeHuffman(bits);
  const sym = dec.sym, ln = dec.len, maxlen = dec.tablebits;
  const mask = (1 << maxlen) - 1;
  const n = src.length;
  let i = bits.pos >> 3;
  let acc = i < n ? src[i] & (0xff >> (bits.pos & 7)) : 0;
  let have = 8 - (bits.pos & 7);
  i++;
  const out = new Uint8Array(destlen);
  for (let k = 0; k < destlen; k++) {
    while (have < maxlen) {
      acc = (acc << 8) | (i < n ? src[i] : 0);
      i++;
      have += 8;
    }
    const v = (acc >> (have - maxlen)) & mask;
    out[k] = sym[v];
    have -= ln[v];
    acc &= (1 << have) - 1;
  }
  if ((i * 8 - have + 7) >> 3 > n) throw new ConvertError("huffman: input too short");
  return out;
}

// ---------------------------------------------------------------- codecs

const inflateRaw = (src) => transform(new DecompressionStream("deflate-raw"), src);

async function decompressZlib(src, hunkbytes) {
  let out;
  try {
    out = await inflateRaw(src);
  } catch (e) {
    throw new ConvertError(`zlib: ${e.message}`);
  }
  if (out.length < hunkbytes) throw new ConvertError("zlib: wrong output length");
  return out.length === hunkbytes ? out : out.subarray(0, hunkbytes);
}

// LzmaEncProps_Normalize for level 8 with reduceSize = hunkbytes
function lzmaDictSize(hunkbytes) {
  const dictSize = 1 << 26;
  if (dictSize > hunkbytes) {
    for (let i = 11; i < 31; i++) {
      if (hunkbytes <= 2 * 2 ** i) return 2 * 2 ** i;
      if (hunkbytes <= 3 * 2 ** i) return 3 * 2 ** i;
    }
  }
  return dictSize;
}

// ---------------------------------------------------------------- the file

export class Chd {
  constructor(data) {
    this.data = data;
    if (data.length < V5_HEADER_SIZE || tagStr(data.subarray(0, 8)) !== "MComprHD") throw new ConvertError("not a CHD file");
    const dv = new DataView(data.buffer, data.byteOffset, data.byteLength);
    this.dv = dv;
    const length = dv.getUint32(8), version = dv.getUint32(12);
    if (version !== 5) throw new ConvertError(`CHD version ${version}: only version 5 is supported (chdman copy converts older files)`);
    if (length !== V5_HEADER_SIZE) throw new ConvertError("bad v5 header length");
    this.compressors = [0, 1, 2, 3].map((k) => data.subarray(16 + 4 * k, 20 + 4 * k));
    this.logicalBytes = Number(dv.getBigUint64(32));
    this.mapOffset = Number(dv.getBigUint64(40));
    this.metaOffset = Number(dv.getBigUint64(48));
    this.hunkBytes = dv.getUint32(56);
    this.unitBytes = dv.getUint32(60);
    this.rawSha1 = hexOf(data.subarray(64, 84));
    this.sha1 = hexOf(data.subarray(84, 104));
    this.parentSha1 = hexOf(data.subarray(104, 124));
    if (this.hunkBytes === 0) throw new ConvertError("hunk size is 0");
    this.hunkCount = Math.ceil(this.logicalBytes / this.hunkBytes);
    this.compressed = this.compressors[0].some((x) => x !== 0);
    if (/[^0]/.test(this.parentSha1)) throw new ConvertError("this CHD needs a parent CHD, which is not supported");
    this.codecs = this.compressors.map((t) => {
      const tag = tagStr(t);
      if (tag === "zlib") return decompressZlib;
      if (tag === "lzma") {
        const dec = makeLzmaDecoder(lzmaDictSize(this.hunkBytes));
        return (src, n) => dec(src, n);
      }
      if (tag === "huff") return huffman8bitDecode;
      if (tag === "flac") return flacDecode;
      if (tag === "\0\0\0\0") return null;
      const name = CODEC_NAMES[tag] || tag;
      return () => { throw new ConvertError(`codec ${tag} (${name}) is not supported`); };
    });
    if (this.compressed) this.readCompressedMap();
    else {
      this.map = new Array(this.hunkCount);
      for (let h = 0; h < this.hunkCount; h++) this.map[h] = dv.getUint32(this.mapOffset + 4 * h);
    }
  }

  // decompress_v5_map: [type, length, offset, crc16] per hunk
  readCompressedMap() {
    const d = this.data, dv = this.dv, mo = this.mapOffset;
    const mapbytes = dv.getUint32(mo);
    const firstoffs = dv.getUint16(mo + 4) * 2 ** 32 + dv.getUint32(mo + 6);
    const mapcrc = dv.getUint16(mo + 10);
    const lengthbits = d[mo + 12], selfbits = d[mo + 13], parentbits = d[mo + 14];
    const bits = new BitReader(d.subarray(mo + 16, mo + 16 + mapbytes));
    const dec = new HuffmanDecoder(16, 8);
    dec.importTreeRle(bits);
    const n = this.hunkCount;
    const types = new Uint8Array(n);
    let lastcomp = 0, rep = 0;
    for (let h = 0; h < n; h++) {
      if (rep > 0) {
        types[h] = lastcomp;
        rep--;
        continue;
      }
      const val = dec.decodeOne(bits);
      if (val === COMPRESSION_RLE_SMALL) {
        rep = 2 + dec.decodeOne(bits);
        types[h] = lastcomp;
      } else if (val === COMPRESSION_RLE_LARGE) {
        rep = 2 + 16 + (dec.decodeOne(bits) << 4);
        rep += dec.decodeOne(bits);
        types[h] = lastcomp;
      } else {
        lastcomp = val;
        types[h] = val;
      }
    }
    const entries = new Array(n);
    const raw = new Uint8Array(n * 12);
    let cur = firstoffs, lastSelf = 0, lastParent = 0;
    const hb = this.hunkBytes, ub = this.unitBytes;
    for (let h = 0; h < n; h++) {
      let t = types[h];
      let offset = cur, length = 0, crc = 0;
      if (t <= COMPRESSION_TYPE_3) {
        length = bits.read(lengthbits);
        cur += length;
        crc = bits.read(16);
      } else if (t === COMPRESSION_NONE) {
        length = hb;
        cur += length;
        crc = bits.read(16);
      } else if (t === COMPRESSION_SELF) {
        lastSelf = offset = bits.read(selfbits);
      } else if (t === COMPRESSION_PARENT) {
        lastParent = offset = bits.read(parentbits);
      } else if (t === COMPRESSION_SELF_0 || t === COMPRESSION_SELF_1) {
        if (t === COMPRESSION_SELF_1) lastSelf += 1;
        t = COMPRESSION_SELF;
        offset = lastSelf;
      } else if (t === COMPRESSION_PARENT_SELF) {
        t = COMPRESSION_PARENT;
        lastParent = offset = Math.floor((h * hb) / ub);
      } else if (t === COMPRESSION_PARENT_0 || t === COMPRESSION_PARENT_1) {
        if (t === COMPRESSION_PARENT_1) lastParent += Math.floor(hb / ub);
        t = COMPRESSION_PARENT;
        offset = lastParent;
      } else {
        throw new ConvertError(`map: unknown entry type ${t} at hunk ${h}`);
      }
      entries[h] = [t, length, offset, crc];
      const o = h * 12;
      raw[o] = t;
      raw[o + 1] = (length >>> 16) & 0xff;
      raw[o + 2] = (length >>> 8) & 0xff;
      raw[o + 3] = length & 0xff;
      let off = offset;
      for (let k = 5; k >= 0; k--) {
        raw[o + 4 + k] = off % 256;
        off = Math.floor(off / 256);
      }
      raw[o + 10] = crc >> 8;
      raw[o + 11] = crc & 0xff;
    }
    if (crc16(raw) !== mapcrc) throw new ConvertError("map CRC mismatch (damaged file?)");
    this.map = entries;
  }

  hunkTypeCounts() {
    if (!this.compressed) return { uncompressed: this.hunkCount };
    const names = { [COMPRESSION_NONE]: "uncompressed", [COMPRESSION_SELF]: "self", [COMPRESSION_PARENT]: "parent" };
    const out = {};
    for (const [t] of this.map) {
      const k = t <= 3 ? tagStr(this.compressors[t]) : names[t];
      out[k] = (out[k] || 0) + 1;
    }
    return out;
  }

  async readHunk(hunk, depth = 0) {
    if (!(hunk >= 0 && hunk < this.hunkCount)) throw new ConvertError(`hunk ${hunk} out of range`);
    const hb = this.hunkBytes, d = this.data;
    if (!this.compressed) {
      const off = this.map[hunk] * hb;
      return off ? d.slice(off, off + hb) : new Uint8Array(hb);
    }
    const [t, length, offset, crc] = this.map[hunk];
    let out;
    if (t <= COMPRESSION_TYPE_3) {
      try {
        out = await this.codecs[t](d.subarray(offset, offset + length), hb);
      } catch (e) {
        if (!(e instanceof ConvertError || e instanceof RangeError || e instanceof TypeError)) throw e;
        throw new ConvertError(`hunk ${hunk}: ${tagStr(this.compressors[t])} data is damaged (${e.message})`);
      }
    } else if (t === COMPRESSION_NONE) {
      out = d.slice(offset, offset + hb);
    } else if (t === COMPRESSION_SELF) {
      if (depth > 16) throw new ConvertError(`hunk ${hunk}: self reference loop`);
      return this.readHunk(offset, depth + 1);
    } else {
      throw new ConvertError(`hunk ${hunk} is stored in a parent CHD, which is not supported`);
    }
    if (out.length !== hb || crc16(out) !== crc) throw new ConvertError(`hunk ${hunk}: CRC mismatch (damaged file?)`);
    return out;
  }

  // the whole logical image as one Uint8Array; progress(done, total) is
  // called every 256 hunks
  async readAll(progress) {
    const hb = this.hunkBytes, n = this.hunkCount;
    const img = new Uint8Array(n * hb);
    for (let h = 0; h < n; h++) {
      const e = this.compressed ? this.map[h] : null;
      if (e && e[0] === COMPRESSION_SELF && e[2] < h) {
        img.copyWithin(h * hb, e[2] * hb, e[2] * hb + hb);   // an earlier hunk, already checked
      } else {
        img.set(await this.readHunk(h), h * hb);
      }
      if (progress && (h & 255) === 255) progress(h + 1, n);
    }
    if (progress) progress(n, n);
    return img.length === this.logicalBytes ? img : img.subarray(0, this.logicalBytes);
  }

  // metadata entry data by 4-character tag, the index-th match
  metadata(tag, index = 0) {
    if (tag.length !== 4) throw new ConvertError("metadata tag must be 4 characters");
    const d = this.data, dv = this.dv;
    let off = this.metaOffset;
    let seen = 0;
    while (off) {
      if (off + 16 > d.length) throw new ConvertError("metadata chain points past the end of the file");
      const mtag = tagStr(d.subarray(off, off + 4));
      const length = (d[off + 5] << 16) | (d[off + 6] << 8) | d[off + 7];
      const nxt = Number(dv.getBigUint64(off + 8));
      if (mtag === tag) {
        if (seen === index) return d.slice(off + 16, off + 16 + length);
        seen++;
      }
      off = nxt;
    }
    throw new ConvertError(`metadata '${tag}' index ${index} not found`);
  }
}

// identify a CHD from its first 124 bytes without reading the rest:
// { ok, version, sha1, rawSha1, logicalBytes, error }
export function chdHeaderInfo(head) {
  if (head.length < 16 || tagStr(head.subarray(0, 8)) !== "MComprHD") return { ok: false, error: "not a CHD file" };
  const dv = new DataView(head.buffer, head.byteOffset, head.byteLength);
  const version = dv.getUint32(12);
  if (version !== 5 || head.length < V5_HEADER_SIZE) return { ok: false, version, error: `CHD version ${version}` };
  return {
    ok: true,
    version,
    logicalBytes: Number(dv.getBigUint64(32)),
    rawSha1: hexOf(head.subarray(64, 84)),
    sha1: hexOf(head.subarray(84, 104)),
  };
}
