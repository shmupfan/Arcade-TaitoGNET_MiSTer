// gnet_tester_zips.py make() and check_bios() in JavaScript: one CHD and the
// BIOS zip in, gnet_<set>.zip out (<set>.img, <set>.meta, <set>.flash).
// SETS, BIOS_PARTS, CARD_MAX and CARD_TYPE_NAME come from tables.js, which
// the build generates from gnet_tester_zips.py.

import { ConvertError, crc32, sha1hex, swap16 } from "./util.js";
import { Chd } from "./chd.js";
import { readZipDirectory, readZipEntry, ZipWriter } from "./zip.js";
import { buildFlash } from "./buildflash.js";
import { SETS, BIOS_PARTS, CARD_MAX, CARD_TYPE_NAME } from "./tables.js";

// the set whose MAME 0.288 CHD has this header SHA1, or null
export function setForSha1(sha1) {
  for (const [s, v] of Object.entries(SETS)) if (v.sha1 === sha1) return s;
  return null;
}

// check_bios: every file the MRAs load is there with its MAME 0.288 CRC32.
// Returns the BIOS files build_flash needs; throws ConvertError otherwise.
export async function checkBios(zipBytes, label = "coh3002t.zip") {
  let dir;
  try {
    dir = readZipDirectory(zipBytes);
  } catch (e) {
    throw new ConvertError(`${label}: ${e.message}`);
  }
  for (const [name, crc] of Object.entries(BIOS_PARTS)) {
    const got = dir[name] ? dir[name].crc : 0;
    if (!dir[name] || got !== crc) {
      throw new ConvertError(`${label}: ${name} missing or not the expected file ` +
        `(CRC ${got.toString(16).padStart(8, "0")}, want ${crc.toString(16).padStart(8, "0")})`);
    }
  }
  return {
    zip: zipBytes,
    dir,
    async file(name) {
      return readZipEntry(zipBytes, dir, name);
    },
  };
}

const FLASH_AREAS = [["firm", 0x000000, 0x200000], ["zoomprog", 0x200000, 0x80000],
  ["wave0", 0x400000, 0x200000], ["wave1", 0x600000, 0x200000], ["wave2", 0x800000, 0x200000]];

// make(): returns { name, parts (for a Blob), size, crc (of the zip), log }.
// progress(phase, fraction) is optional.
export async function convert(chdBytes, bios, s, { quick = true, progress = null, date = new Date() } = {}) {
  const fail = (m) => { throw new ConvertError(`${s}: ${m}`); };
  if (!SETS[s]) fail("unknown set");
  const { title, sha1, card_type: ctype } = SETS[s];
  const c = new Chd(chdBytes);
  if (c.sha1 !== sha1) fail(`CHD SHA1 ${c.sha1} is not the expected ${sha1}`);
  const cardBytes = c.logicalBytes;
  if (!cardBytes || cardBytes > CARD_MAX || cardBytes % 512) {
    fail(`card size ${cardBytes} bytes is not a whole number of sectors up to ${CARD_MAX}`);
  }
  const img = await c.readAll(progress ? (done, total) => progress("card", done / total) : null);
  if (progress) progress("check", 0);
  const got = sha1hex(img);
  if (got !== c.rawSha1) fail(`card image SHA1 ${got} is not the CHD's data SHA1 ${c.rawSha1}`);
  if (img.length !== cardBytes) fail(`card image is ${img.length} bytes, the CHD says ${cardBytes}`);
  const idnt = c.metadata("IDNT"), key = c.metadata("KEY "), cis = c.metadata("CIS ");
  if (idnt.length !== 512 || key.length !== 5 || cis.length > 256) {
    fail(`unexpected card metadata sizes [${idnt.length}, ${key.length}, ${cis.length}]`);
  }
  const meta = new Uint8Array(1024);
  meta.set(idnt, 0);
  meta.set(cis, 0x200);
  meta.set(key, 0x300);
  meta[0x3f0] = ctype;
  const lba = (idnt[120] | (idnt[121] << 8) | (idnt[122] << 16) | (idnt[123] << 24)) >>> 0;
  if (lba * 512 !== cardBytes) fail(`IDENTIFY gives ${lba} sectors, the card has ${cardBytes / 512}`);
  let area = null;
  if (quick) {
    if (progress) progress("flash", 0);
    const biosFiles = { "flash.u30": await bios.file("flash.u30") };
    if (ctype === 3) biosFiles["f35-01_m27c800.bin"] = await bios.file("f35-01_m27c800.bin");
    const { images } = buildFlash(img, biosFiles, ctype === 3);
    area = new Uint8Array(0xa00000).fill(0xff);
    for (const [name, off, size] of FLASH_AREAS) {
      if (images[name]) {
        const d = swap16(images[name]);       // MAME NVRAM words -> the core's order
        if (d.length !== size) fail(`${name} is ${d.length} bytes, expected ${size}`);
        area.set(d, off);
      }
    }
  }
  if (progress) progress("zip", 0);
  const z = new ZipWriter(date);
  await z.add(s + ".img", img);
  await z.add(s + ".meta", meta);
  if (area) await z.add(s + ".flash", area);
  const parts = z.finish();
  let crc = 0, size = 0;
  for (const p of parts) {
    crc = crc32(p, crc);
    size += p.length;
  }
  return {
    name: `gnet_${s}.zip`,
    parts,
    size,
    crc,
    log: `${s}: ${title}, ${CARD_TYPE_NAME[ctype]} card, ${cardBytes.toLocaleString("en")} bytes`,
    files: { img, meta, flash: area },
  };
}
