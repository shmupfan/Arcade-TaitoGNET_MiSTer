// CHD 'flac' hunk decoder, ported from chd.py flac_decode (itself written
// from MAME 0.288 flac.cpp and chdcodec.cpp).

import { ConvertError } from "./util.js";

const err = (m) => new ConvertError("flac: " + m);

class Bits {
  constructor(d) {
    this.d = d;
    this.p = 0;
    this.n = d.length * 8;
  }

  u(n) {
    if (n === 0) return 0;
    let p = this.p;
    if (p + n > this.n) throw err("data ends early");
    this.p = p + n;
    const d = this.d;
    let v = 0;
    while (n > 0) {
      const avail = 8 - (p & 7);
      const take = avail < n ? avail : n;
      v = v * (1 << take) + ((d[p >> 3] >> (avail - take)) & ((1 << take) - 1));
      p += take;
      n -= take;
    }
    return v;
  }

  s(n) {
    const v = this.u(n);
    return n && v >= 2 ** (n - 1) ? v - 2 ** n : v;
  }

  // count of 0 bits before the next 1, which is consumed
  unary() {
    const d = this.d;
    let p = this.p;
    let i = p >> 3;
    let byte = (d[i] << (p & 7)) & 0xff;
    let count = 0;
    if (byte === 0) {
      count = 8 - (p & 7);
      i++;
      while (i < d.length && d[i] === 0) {
        count += 8;
        i++;
      }
      if (i >= d.length) throw err("data ends early");
      byte = d[i];
    }
    const z = Math.clz32(byte) - 24;
    count += z;
    this.p = p + count + 1;
    return count;
  }

  align() {
    this.p = (this.p + 7) & ~7;
  }
}

function residual(b, blocksize, order) {
  const method = b.u(2);
  if (method > 1) throw err("bad residual coding method");
  const pbits = method === 0 ? 4 : 5;
  const escape = method === 0 ? 15 : 31;
  const porder = b.u(4);
  const out = [];
  for (let part = 0; part < 1 << porder; part++) {
    const n = (blocksize >> porder) - (part === 0 ? order : 0);
    const k = b.u(pbits);
    if (k === escape) {
      const nb = b.u(5);
      for (let j = 0; j < n; j++) out.push(b.s(nb));
      continue;
    }
    for (let j = 0; j < n; j++) {
      const q = b.unary();
      const u = k ? q * 2 ** k + b.u(k) : q;
      // zigzag: (u >> 1) ^ -(u & 1)
      out.push(u % 2 ? -(u - 1) / 2 - 1 : u / 2);
    }
    if (b.p > b.n) throw err("data ends early");
  }
  return out;
}

function subframe(b, blocksize, bps) {
  if (b.u(1)) throw err("bad subframe padding");
  const t = b.u(6);
  let wasted = 0;
  if (b.u(1)) {
    wasted = b.unary() + 1;
    bps -= wasted;
  }
  let x;
  if (t === 0) {
    x = new Array(blocksize).fill(b.s(bps));
  } else if (t === 1) {
    x = [];
    for (let i = 0; i < blocksize; i++) x.push(b.s(bps));
  } else if (t >= 8 && t <= 12) {
    const order = t - 8;
    x = [];
    for (let i = 0; i < order; i++) x.push(b.s(bps));
    const res = residual(b, blocksize, order);
    if (order === 0) {
      x = res;
    } else {
      let i = x.length;
      for (const r of res) {
        let v;
        if (order === 1) v = r + x[i - 1];
        else if (order === 2) v = r + 2 * x[i - 1] - x[i - 2];
        else if (order === 3) v = r + 3 * x[i - 1] - 3 * x[i - 2] + x[i - 3];
        else v = r + 4 * x[i - 1] - 6 * x[i - 2] + 4 * x[i - 3] - x[i - 4];
        x.push(v);
        i++;
      }
    }
  } else if (t >= 32) {
    const order = t - 31;
    x = [];
    for (let i = 0; i < order; i++) x.push(b.s(bps));
    const precision = b.u(4) + 1;
    if (precision === 16) throw err("bad LPC precision");
    const shift = b.s(5);
    if (shift < 0) throw err("negative LPC shift");
    const coefs = [];
    for (let i = 0; i < order; i++) coefs.push(b.s(precision));
    const res = residual(b, blocksize, order);
    const div = 2 ** shift;
    let i = 0;
    for (const r of res) {
      // coefs[0] applies to the newest sample
      let sum = 0;
      for (let j = 0; j < order; j++) sum += coefs[j] * x[i + order - 1 - j];
      x.push(r + Math.floor(sum / div));
      i++;
    }
  } else {
    throw err(`reserved subframe type ${t}`);
  }
  if (wasted) {
    const m = 2 ** wasted;
    x = x.map((v) => v * m);
  }
  return x;
}

const BPS = { 0: 16, 1: 8, 2: 12, 4: 16, 5: 20, 6: 24, 7: 32 };

// chd_flac_decompressor: 'L' or 'B' (byte order of the output words), then
// FLAC frames for 2 channels of 16-bit samples, without the stream header
export function flacDecode(src, destlen) {
  let little;
  if (src[0] === 0x4c) little = true;
  else if (src[0] === 0x42) little = false;
  else throw err("bad byte order marker");
  const want = Math.floor(destlen / 4);
  const b = new Bits(src.subarray(1));
  let left = [], right = [];
  while (left.length < want) {
    b.align();
    if (b.u(14) !== 0x3ffe) throw err("frame sync not found");
    b.u(2);
    const bscode = b.u(4), srcode = b.u(4);
    const chan = b.u(4), sscode = b.u(3);
    b.u(1);
    const lead = b.u(8);
    let extra = 0;
    while (lead & (0x80 >> extra)) extra++;
    for (let i = 0; i < extra - 1; i++) b.u(8);
    let blocksize;
    if (bscode === 0) throw err("reserved block size");
    else if (bscode === 1) blocksize = 192;
    else if (bscode <= 5) blocksize = 576 << (bscode - 2);
    else if (bscode === 6) blocksize = b.u(8) + 1;
    else if (bscode === 7) blocksize = b.u(16) + 1;
    else blocksize = 256 << (bscode - 8);
    if (srcode === 12) b.u(8);
    else if (srcode === 13 || srcode === 14) b.u(16);
    else if (srcode === 15) throw err("bad sample rate code");
    const bps = BPS[sscode];
    if (bps === undefined) throw err("bad sample size");
    b.u(8);
    let a, c;
    if (chan === 1) {
      a = subframe(b, blocksize, bps);
      c = subframe(b, blocksize, bps);
    } else if (chan === 8) {
      a = subframe(b, blocksize, bps);
      const sd = subframe(b, blocksize, bps + 1);
      c = a.map((x, i) => x - sd[i]);
      if (sd.length < a.length) c.length = sd.length;
    } else if (chan === 9) {
      const sd = subframe(b, blocksize, bps + 1);
      c = subframe(b, blocksize, bps);
      a = sd.map((x, i) => x + c[i]);
      if (c.length < sd.length) a.length = c.length;
    } else if (chan === 10) {
      const m = subframe(b, blocksize, bps);
      const sd = subframe(b, blocksize, bps + 1);
      const n = Math.min(m.length, sd.length);
      a = new Array(n);
      c = new Array(n);
      for (let i = 0; i < n; i++) {
        const y = sd[i];
        const x = m[i] * 2 + (y & 1);
        a[i] = Math.floor((x + y) / 2);
        c[i] = Math.floor((x - y) / 2);
      }
    } else {
      throw err(`channel layout ${chan} is not 2-channel`);
    }
    if (bps !== 16) throw err(`${bps}-bit samples (only 16-bit is supported)`);
    b.align();
    b.u(16);
    for (const v of a) left.push(v);
    for (const v of c) right.push(v);
  }
  const out = new Uint8Array(4 * want);
  const put = (o, v) => {
    v &= 0xffff;
    if (little) {
      out[o] = v & 0xff;
      out[o + 1] = v >> 8;
    } else {
      out[o] = v >> 8;
      out[o + 1] = v & 0xff;
    }
  };
  for (let i = 0; i < want; i++) {
    put(4 * i, left[i]);
    put(4 * i + 2, right[i]);
  }
  return out;
}
