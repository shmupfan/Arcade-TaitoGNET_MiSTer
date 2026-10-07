// Minimal zip reading (central directory, stored and deflated entries) and
// writing (deflated with the browser's CompressionStream, or stored).

import { ConvertError, crc32, transform } from "./util.js";

const CP437_HIGH =
  "ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀" +
  "αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ";

function decodeName(b, utf8) {
  if (utf8) return new TextDecoder().decode(b);
  let s = "";
  for (const c of b) s += c < 0x80 ? String.fromCharCode(c) : CP437_HIGH[c - 0x80];
  return s;
}

// { name: {crc, method, compSize, size, offset} }, the last entry of a name
// winning, as in Python's zipfile
export function readZipDirectory(z) {
  const dv = new DataView(z.buffer, z.byteOffset, z.byteLength);
  let eocd = -1;
  for (let i = z.length - 22; i >= Math.max(0, z.length - 22 - 65535); i--) {
    if (dv.getUint32(i, true) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new ConvertError("not a zip file");
  const count = dv.getUint16(eocd + 10, true);
  const cdSize = dv.getUint32(eocd + 12, true);
  let cdOff = dv.getUint32(eocd + 16, true);
  if (cdOff === 0xffffffff || count === 0xffff) throw new ConvertError("zip64 files are not supported");
  // data in front of the zip (self-extractors): shift offsets like zipfile does
  const concat = eocd - cdSize - cdOff;
  cdOff += concat;
  const out = {};
  let p = cdOff;
  for (let k = 0; k < count; k++) {
    if (p + 46 > z.length || dv.getUint32(p, true) !== 0x02014b50) throw new ConvertError("bad zip central directory");
    const flags = dv.getUint16(p + 8, true);
    const method = dv.getUint16(p + 10, true);
    const crc = dv.getUint32(p + 16, true);
    const compSize = dv.getUint32(p + 20, true);
    const size = dv.getUint32(p + 24, true);
    const nlen = dv.getUint16(p + 28, true), xlen = dv.getUint16(p + 30, true), clen = dv.getUint16(p + 32, true);
    const offset = dv.getUint32(p + 42, true) + concat;
    const name = decodeName(z.subarray(p + 46, p + 46 + nlen), flags & 0x800);
    out[name] = { crc, method, compSize, size, offset };
    p += 46 + nlen + xlen + clen;
  }
  return out;
}

const inflateRaw = (data) => transform(new DecompressionStream("deflate-raw"), data);

// an entry's data, checked against its CRC (ZipFile.read)
export async function readZipEntry(z, dir, name) {
  const e = dir[name];
  if (!e) throw new ConvertError(`There is no item named '${name}' in the archive`);
  const dv = new DataView(z.buffer, z.byteOffset, z.byteLength);
  const p = e.offset;
  if (p + 30 > z.length || dv.getUint32(p, true) !== 0x04034b50) throw new ConvertError(`${name}: bad local header`);
  const start = p + 30 + dv.getUint16(p + 26, true) + dv.getUint16(p + 28, true);
  const comp = z.subarray(start, start + e.compSize);
  let data;
  if (e.method === 0) data = comp.slice();
  else if (e.method === 8) data = await inflateRaw(comp);
  else throw new ConvertError(`${name}: zip compression method ${e.method} is not supported`);
  if (data.length !== e.size || crc32(data) !== e.crc) throw new ConvertError(`Bad CRC-32 for file '${name}'`);
  return data;
}

// ---------------------------------------------------------------- writing

function dosDateTime(d) {
  const time = (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1);
  const date = ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate();
  return [time, date];
}

const deflateRaw = (data) => transform(new CompressionStream("deflate-raw"), data);

// A zip writer that collects its parts (Uint8Array or Blob) in memory.
// add(name, data) deflates; addStored(name, blobOrBytes, crc, size) stores.
export class ZipWriter {
  constructor(date = new Date()) {
    this.parts = [];
    this.central = [];
    this.offset = 0;
    this.count = 0;
    [this.time, this.date] = dosDateTime(date);
  }

  _entry(name, method, crc, compSize, size, body) {
    const nb = new TextEncoder().encode(name);
    const utf8 = /[^\x00-\x7f]/.test(name) ? 0x800 : 0;
    if (this.offset + 30 + nb.length + compSize > 0xffffffff) throw new ConvertError("zip larger than 4 GB");
    const lh = new Uint8Array(30 + nb.length);
    const l = new DataView(lh.buffer);
    l.setUint32(0, 0x04034b50, true);
    l.setUint16(4, 20, true);
    l.setUint16(6, utf8, true);
    l.setUint16(8, method, true);
    l.setUint16(10, this.time, true);
    l.setUint16(12, this.date, true);
    l.setUint32(14, crc, true);
    l.setUint32(18, compSize, true);
    l.setUint32(22, size, true);
    l.setUint16(26, nb.length, true);
    lh.set(nb, 30);
    const ch = new Uint8Array(46 + nb.length);
    const c = new DataView(ch.buffer);
    c.setUint32(0, 0x02014b50, true);
    c.setUint16(4, 20, true);
    c.setUint16(6, 20, true);
    c.setUint16(8, utf8, true);
    c.setUint16(10, method, true);
    c.setUint16(12, this.time, true);
    c.setUint16(14, this.date, true);
    c.setUint32(16, crc, true);
    c.setUint32(20, compSize, true);
    c.setUint32(24, size, true);
    c.setUint16(28, nb.length, true);
    c.setUint32(38, 0x81a40000, true);    // external attributes: -rw-r--r--
    c.setUint32(42, this.offset, true);
    ch.set(nb, 46);
    this.parts.push(lh, body);
    this.central.push(ch);
    this.offset += lh.length + compSize;
    this.count++;
  }

  async add(name, data) {
    const comp = await deflateRaw(data);
    this._entry(name, 8, crc32(data), comp.length, data.length, comp);
  }

  addStored(name, body, crc, size) {
    this._entry(name, 0, crc, size, size, body);
  }

  // the zip as a list of parts (for new Blob(parts))
  finish() {
    let cdSize = 0;
    for (const c of this.central) cdSize += c.length;
    const end = new Uint8Array(22);
    const e = new DataView(end.buffer);
    e.setUint32(0, 0x06054b50, true);
    e.setUint16(8, this.count, true);
    e.setUint16(10, this.count, true);
    e.setUint32(12, cdSize, true);
    e.setUint32(16, this.offset, true);
    return [...this.parts, ...this.central, end];
  }
}
