// Small helpers shared by the converter modules: errors, CRC16, CRC32, SHA1
// and the Python string and bytearray behaviour that build_flash.py relies on.

export class ConvertError extends Error {}

// ---------------------------------------------------------------- CRC16

const CRC16_TABLE = (() => {
  const t = new Uint16Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i << 8;
    for (let k = 0; k < 8; k++) c = (c & 0x8000) ? ((c << 1) ^ 0x1021) : (c << 1);
    t[i] = c & 0xffff;
  }
  return t;
})();

// CRC-16-CCITT (polynomial 1021h, start FFFFh), MAME's crc16_creator (chd.py crc16)
export function crc16(data) {
  let crc = 0xffff;
  const t = CRC16_TABLE;
  for (let i = 0, n = data.length; i < n; i++) crc = ((crc << 8) & 0xff00) ^ t[(crc >> 8) ^ data[i]];
  return crc;
}

// ---------------------------------------------------------------- CRC32 (zip)

const CRC32_TABLES = (() => {
  const t = new Int32Array(256 * 4);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    t[i] = c;
  }
  for (let i = 0; i < 256; i++) {
    for (let s = 1; s < 4; s++) {
      const p = t[(s - 1) * 256 + i];
      t[s * 256 + i] = t[p & 0xff] ^ (p >>> 8);
    }
  }
  return t;
})();

// crc32(data[, previous crc]) as zlib.crc32
export function crc32(data, prev = 0) {
  const t = CRC32_TABLES;
  let c = ~prev;
  let i = 0;
  const n = data.length;
  const n4 = n - (n & 3);
  for (; i < n4; i += 4) {
    c ^= data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24);
    c = t[768 + (c & 0xff)] ^ t[512 + ((c >>> 8) & 0xff)] ^ t[256 + ((c >>> 16) & 0xff)] ^ t[c >>> 24];
  }
  for (; i < n; i++) c = t[(c ^ data[i]) & 0xff] ^ (c >>> 8);
  return (~c) >>> 0;
}

// ---------------------------------------------------------------- SHA1

// SHA1 hex digest of a Uint8Array (own implementation: crypto.subtle is not
// available to pages opened from file:// in every browser)
export function sha1hex(data) {
  let h0 = 0x67452301, h1 = 0xefcdab89, h2 = 0x98badcfe, h3 = 0x10325476, h4 = 0xc3d2e1f0;
  const w = new Int32Array(80);
  const n = data.length;
  const full = n - (n % 64);
  const tail = new Uint8Array(((n % 64) + 9 > 64) ? 128 : 64);
  tail.set(data.subarray(full));
  tail[n % 64] = 0x80;
  const bits = n * 8;
  const tl = tail.length;
  tail[tl - 1] = bits & 0xff;
  tail[tl - 2] = (bits >>> 8) & 0xff;
  tail[tl - 3] = (bits >>> 16) & 0xff;
  tail[tl - 4] = (bits >>> 24) & 0xff;
  const hi = Math.floor(bits / 0x100000000);
  tail[tl - 5] = hi & 0xff;
  tail[tl - 6] = (hi >>> 8) & 0xff;
  tail[tl - 7] = (hi >>> 16) & 0xff;
  tail[tl - 8] = (hi >>> 24) & 0xff;
  const block = (buf, off) => {
    for (let i = 0; i < 16; i++) {
      const o = off + i * 4;
      w[i] = (buf[o] << 24) | (buf[o + 1] << 16) | (buf[o + 2] << 8) | buf[o + 3];
    }
    for (let i = 16; i < 80; i++) {
      const x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
      w[i] = (x << 1) | (x >>> 31);
    }
    let a = h0, b = h1, c = h2, d = h3, e = h4;
    for (let i = 0; i < 80; i++) {
      let f, k;
      if (i < 20) { f = (b & c) | (~b & d); k = 0x5a827999; }
      else if (i < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
      else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc; }
      else { f = b ^ c ^ d; k = 0xca62c1d6; }
      const t = (((a << 5) | (a >>> 27)) + f + e + k + w[i]) | 0;
      e = d; d = c; c = (b << 30) | (b >>> 2); b = a; a = t;
    }
    h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0; h4 = (h4 + e) | 0;
  };
  for (let off = 0; off < full; off += 64) block(data, off);
  for (let off = 0; off < tl; off += 64) block(tail, off);
  return [h0, h1, h2, h3, h4].map((v) => (v >>> 0).toString(16).padStart(8, "0")).join("");
}

// ---------------------------------------------------------------- streams

// bytes through a CompressionStream or DecompressionStream. Written to the
// stream directly, not through a Blob: Safari cannot read Blobs in a page
// opened from file://.
export async function transform(stream, data) {
  const writer = stream.writable.getWriter();
  const done = writer.write(data).then(() => writer.close());
  done.catch(() => {});
  const reader = stream.readable.getReader();
  const chunks = [];
  for (;;) {
    const { value, done: end } = await reader.read();
    if (end) break;
    chunks.push(value);
  }
  await done;
  return chunks.length === 1 ? chunks[0] : concatBytes(chunks);
}

// ---------------------------------------------------------------- bytes

export function hex(b) {
  let s = "";
  for (let i = 0; i < b.length; i++) s += b[i].toString(16).padStart(2, "0");
  return s;
}

export function concatBytes(parts) {
  let n = 0;
  for (const p of parts) n += p.length;
  const out = new Uint8Array(n);
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}

// Python bytes.ljust(width, fill): pad, never truncate
export function ljust(b, width, fill) {
  if (b.length >= width) return b;
  const out = new Uint8Array(width).fill(fill);
  out.set(b);
  return out;
}

// Python bytearray slice assignment a[lo:hi] = v (the length may change)
export function sliceAssign(a, lo, hi, v) {
  lo = Math.min(lo, a.length);
  hi = Math.max(lo, Math.min(hi, a.length));
  if (hi - lo === v.length) {
    a.set(v, lo);
    return a;
  }
  return concatBytes([a.subarray(0, lo), v, a.subarray(hi)]);
}

// build_flash.swap16: exchange the bytes of each 16-bit word (Python raises
// ValueError on an odd length)
export function swap16(b) {
  if (b.length & 1) throw new ConvertError("swap16: odd length");
  const a = new Uint8Array(b.length);
  for (let i = 0; i < b.length; i += 2) {
    a[i] = b[i + 1];
    a[i + 1] = b[i];
  }
  return a;
}

// ---------------------------------------------------------------- Python str (latin-1 range)

export function latin1(b) {
  let s = "";
  for (let i = 0; i < b.length; i += 8192) s += String.fromCharCode.apply(null, b.subarray(i, i + 8192));
  return s;
}

export function encodeLatin1(s) {
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c > 0xff) throw new ConvertError("'latin-1' codec can't encode character");
    out[i] = c;
  }
  return out;
}

// str.isspace for the characters latin-1 text can hold
const PY_SPACE = new Set([0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x85, 0xa0]);
const isSpace = (s, i) => PY_SPACE.has(s.charCodeAt(i));

export function pyStrip(s, chars) {
  const drop = chars === undefined ? (i) => isSpace(s, i) : (i) => chars.includes(s[i]);
  let a = 0, b = s.length;
  while (a < b && drop(a)) a++;
  while (b > a && drop(b - 1)) b--;
  return s.slice(a, b);
}

export function pyRstrip(s) {
  let b = s.length;
  while (b > 0 && isSpace(s, b - 1)) b--;
  return s.slice(0, b);
}

// str.split() / str.split(None, maxsplit)
export function pySplit(s, maxsplit = -1) {
  const out = [];
  let i = 0;
  const n = s.length;
  while (true) {
    while (i < n && isSpace(s, i)) i++;
    if (i >= n) break;
    if (maxsplit >= 0 && out.length === maxsplit) {
      let e = n;
      while (e > i && isSpace(s, e - 1)) e--;
      out.push(s.slice(i, e));
      break;
    }
    let j = i;
    while (j < n && !isSpace(s, j)) j++;
    out.push(s.slice(i, j));
    i = j;
  }
  return out;
}

// str.splitlines() (no line ends kept)
export function pySplitlines(s) {
  const out = [];
  let start = 0;
  let i = 0;
  const n = s.length;
  while (i < n) {
    const c = s.charCodeAt(i);
    if (c === 0x0a || c === 0x0b || c === 0x0c || c === 0x0d || c === 0x1c || c === 0x1d || c === 0x1e || c === 0x85) {
      out.push(s.slice(start, i));
      if (c === 0x0d && i + 1 < n && s.charCodeAt(i + 1) === 0x0a) i++;
      i++;
      start = i;
    } else {
      i++;
    }
  }
  if (start < n) out.push(s.slice(start));
  return out;
}

// int(x) / int(x, 10) for a decimal string
export function pyInt(s) {
  const t = pyStrip(s);
  if (!/^[+-]?\d+(_\d+)*$/.test(t)) throw new ConvertError(`invalid literal for int() with base 10: '${s}'`);
  return Number(t.replace(/_/g, ""));
}
