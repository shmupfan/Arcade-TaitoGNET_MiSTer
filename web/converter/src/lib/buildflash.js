// The five G-NET flash images from a PC card image and the BIOS files, ported
// from tools/build_flash.py (what the BIOS writes on its first-boot copy; see
// that file for the details). Python's slice and string behaviour is kept
// (util.js) so odd inputs fail or pass the same way.

import {
  ConvertError, concatBytes, encodeLatin1, latin1, ljust, pyInt, pyRstrip, pySplit, pySplitlines, pyStrip,
  sliceAssign, swap16,
} from "./util.js";

const SECTOR = 512;

export class Fat16 {
  constructor(img) {
    this.img = img;
    const dv = new DataView(img.buffer, img.byteOffset, img.byteLength);
    const plba = dv.getUint32(0x1be + 8, true);
    const bs = plba * SECTOR;
    const bps = dv.getUint16(bs + 11, true), spc = img[bs + 13], rsv = dv.getUint16(bs + 14, true);
    const nfats = img[bs + 16], nroot = dv.getUint16(bs + 17, true), spf = dv.getUint16(bs + 22, true);
    this.fat = img.subarray(bs + rsv * bps, bs + rsv * bps + spf * bps);
    this.root = bs + (rsv + nfats * spf) * bps;
    this.nroot = nroot;
    this.data = this.root + nroot * 32;
    this.clus = spc * bps;
  }

  *chain(c) {
    const f = this.fat;
    let guard = 0;
    while (c >= 2 && c < 0xfff8) {
      yield c;
      if (c * 2 + 2 > f.length) throw new ConvertError("FAT: cluster chain runs past the FAT");
      c = f[c * 2] | (f[c * 2 + 1] << 8);
      if (++guard > 0x10000) throw new ConvertError("FAT: cluster chain loops");
    }
  }

  // a file from the root directory (case-insensitive 8.3 name)
  read(name) {
    const want = name.toUpperCase();
    const img = this.img;
    const raw = img.subarray(this.root, this.root + this.nroot * 32);
    for (let i = 0; i < raw.length; i += 32) {
      const e = raw.subarray(i, i + 32);
      if (e[0] === 0) break;
      if (e[0] === 0xe5 || e[11] & 0x18) continue;
      const n = pyRstrip(latin1(e.subarray(0, 8)));
      const x = pyRstrip(latin1(e.subarray(8, 11)));
      if ((n + (x ? "." + x : "")).toUpperCase() === want) {
        const start = e[26] | (e[27] << 8);
        const size = (e[28] | (e[29] << 8) | (e[30] << 16) | (e[31] << 24)) >>> 0;
        const parts = [];
        let total = 0;
        for (const c of this.chain(start)) {
          if (total >= size) break;            // the rest is cut off by [:size] anyway
          const p = img.subarray(this.data + (c - 2) * this.clus, this.data + (c - 1) * this.clus);
          parts.push(p);
          total += p.length;
        }
        const b = concatBytes(parts);
        return b.length > size ? b.slice(0, size) : b;
      }
    }
    throw new ConvertError(`${name} not found on the card`);
  }
}

// SDH: Huffman then LZSS (build_flash.sdh_decode)
export function sdhDecode(sdh) {
  const u16 = (k) => sdh[k] | (sdh[k + 1] << 8);
  const u32 = (b, k) => (b[k] | (b[k + 1] << 8) | (b[k + 2] << 16) | (b[k + 3] << 24)) >>> 0;
  const nodes = [];
  for (let k = 0; k < 1020; k += 4) nodes.push([u16(k), u16(k + 2)]);
  if (!(sdh[1020] === 0xff && sdh[1021] === 0xff && sdh[1022] === 0xff && sdh[1023] === 0xff)) throw new ConvertError("SDH marker");
  const hlen = u32(sdh, 1024);
  const out = new Uint8Array(hlen);
  let olen0 = 0;
  let n = 0x100;
  outer:
  for (let i = 1028; i < sdh.length; i++) {
    const byte = sdh[i];
    for (let b = 7; b >= 0; b--) {
      const node = nodes[n - 0x100];
      if (!node) throw new ConvertError("SDH: bad Huffman tree");
      n = node[(byte >> b) & 1];
      if (n < 0x100) {
        out[olen0++] = n;
        n = 0x100;
        if (olen0 === hlen) break outer;
      }
    }
  }
  const huff = out.subarray(0, olen0);
  if (huff.length < 4) throw new ConvertError("SDH: data ends early");
  const olen = u32(huff, 0);
  const src = huff.subarray(4);
  const N = 4096, F = 18;
  const ring = new Uint8Array(N);
  let r = N - F;
  let res = new Uint8Array(Math.max(olen + 18, 64));
  let rl = 0;
  const push = (c) => {
    if (rl === res.length) {
      const g = new Uint8Array(res.length * 2);
      g.set(res);
      res = g;
    }
    res[rl++] = c;
  };
  const at = (k) => {
    if (k >= src.length) throw new ConvertError("SDH: data ends early");
    return src[k];
  };
  let i = 0;
  while (rl < olen) {
    const flags = at(i++);
    for (let b = 0; b < 8; b++) {
      if (rl >= olen) break;
      if ((flags >> b) & 1) {
        const c = at(i++);
        push(c);
        ring[r] = c;
        r = (r + 1) % N;
      } else {
        const b1 = at(i), b2 = at(i + 1);
        i += 2;
        const off = b1 | ((b2 & 0xf0) << 4);
        for (let k = 0; k < (b2 & 0x0f) + 3; k++) {
          const c = ring[(off + k) % N];
          push(c);
          ring[r] = c;
          r = (r + 1) % N;
        }
      }
    }
  }
  return res.slice(0, rl);
}

// SYSTEM.INF: one key per line, fields separated by tabs or spaces
export function parseInf(text) {
  const inf = { wave: [] };
  for (const line of pySplitlines(text.replace(/\x1a/g, ""))) {
    const parts = pySplit(pyStrip(line), 1);
    if (!parts.length) continue;
    const k = parts[0], rest = parts.length > 1 ? parts[1] : "";
    if (k === "title") inf[k] = [pyStrip(pyStrip(rest), '"')];
    else if (k === "wave") inf.wave.push(pySplit(rest));
    else inf[k] = pySplit(rest);
  }
  return inf;
}

const need = (arr, i, what) => {
  if (!arr || arr.length <= i) throw new ConvertError(`SYSTEM.INF: ${what} missing`);
  return arr[i];
};

// build(card image, {"flash.u30": bytes, "f35-01_m27c800.bin": bytes}, cf)
// -> { images: {name: bytes (MAME NVRAM word order)}, inf }
export function buildFlash(img, bios, cf = false) {
  const fs = new Fat16(img);
  const inf = parseInf(latin1(fs.read("SYSTEM.INF")));
  const out = {};
  inf.wave.forEach((w, n) => {
    const data = fs.read(need(w, 0, "wave file name"));
    out["wave" + n] = swap16(ljust(data, 0x200000, 0xff));
  });
  if ("zoomprog" in inf) {
    const zname = need(inf.zoomprog, 0, "zoomprog file name");
    let z = fs.read(zname);
    if (zname.toUpperCase().endsWith(".SDH")) z = sdhDecode(z);
    out.zoomprog = swap16(ljust(z, 0x80000, 0xff));
  }
  if (!bios["flash.u30"]) throw new ConvertError("flash.u30 missing from the BIOS");
  const firm = swap16(bios["flash.u30"]);
  const gname = need(inf.gameprog, 0, "gameprog"), gver = need(inf.gameprog, 1, "gameprog version");
  const game = fs.read(gname);
  const ver = gver.split(".");
  if (ver.length !== 2) throw new ConvertError(`SYSTEM.INF: gameprog version ${gver} is not major.minor`);
  const [major, minor] = ver.map(pyInt);
  const title = ljust(encodeLatin1(need(inf.title, 0, "title").toUpperCase()).slice(0, 16), 16, 0);
  const gparts = gname.toUpperCase().split(".");
  if (gparts.length < 2) throw new ConvertError(`SYSTEM.INF: gameprog ${gname} has no extension`);
  const ext = encodeLatin1(gparts[1]).slice(0, 3);
  const area = encodeLatin1(need(inf.area, 0, "area")).slice(0, 1);
  const lotno = pyInt(need(inf.lotno, 0, "lotno"));
  const mask = 2 ** inf.wave.length - 1;
  for (const [v, what] of [[major, "major version"], [minor, "minor version"], [mask, "wave count"]]) {
    if (v < 0 || v > 255) throw new ConvertError(`SYSTEM.INF: ${what} out of range`);
  }
  if (lotno < 0 || lotno > 0xffffffff) throw new ConvertError("SYSTEM.INF: lotno out of range");
  const head = new Uint8Array(8);
  const hv = new DataView(head.buffer);
  hv.setUint32(0, lotno, true);
  hv.setUint32(4, game.length, true);
  const header = concatBytes([head, title, ext, area, Uint8Array.of(major, minor, mask)]);
  const hl = header.length;
  // file view (unswapped) of the firm chip, patched, then swapped back
  let fv = swap16(firm);
  fv = sliceAssign(fv, 0x50000, 0x50000 + hl, header);
  fv = sliceAssign(fv, 0x50000 + hl, 0x50000 + hl + 5, Uint8Array.of(0xff, 0xff, 0, 0, 0));
  let tim = fs.read("SYSTEM.TIM");
  tim = sliceAssign(tim, 12, 16, Uint8Array.of(0x00, 0x03, 0xfe, 0x00));
  tim = sliceAssign(tim, 56, 60, Uint8Array.of(0x00, 0x03, 0x00, 0x00));
  tim = concatBytes([tim, new Uint8Array((0x100 - (tim.length % 0x100)) % 0x100)]);
  fv = sliceAssign(fv, 0x54000, 0x54000 + tim.length, tim);
  const gamePadded = concatBytes([game, new Uint8Array((0x10000 - (game.length % 0x10000)) % 0x10000)]);
  fv = sliceAssign(fv, 0x60000, 0x60000 + gamePadded.length, gamePadded);
  if (cf) {
    const b = bios["f35-01_m27c800.bin"];
    if (!b) throw new ConvertError("f35-01_m27c800.bin missing from the BIOS");
    fv = sliceAssign(fv, 0x00000, 0x50000, new Uint8Array(0x50000));
    fv = sliceAssign(fv, 0x00000, 0x03000, b.subarray(0x2c000, 0x2f000));
    fv = sliceAssign(fv, 0x10000, 0x40000, b.subarray(0x30000, 0x60000));
    fv = sliceAssign(fv, 0x50000 + hl, 0x50000 + hl + 2, Uint8Array.of(0x01, 0x00));
  }
  out.firm = swap16(fv);
  return { images: out, inf };
}
