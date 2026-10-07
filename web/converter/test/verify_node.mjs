// Run the web converter's JavaScript (the ES modules build.py writes) under
// Node on a MAME roms folder, write gnet_<set>.zip files and print timings.
// Compare them with the command-line converter's zips using compare_zips.py.
//
//   python3 web/converter/build.py
//   node web/converter/test/verify_node.mjs <roms folder> <out folder> [set ...]
//
// The CHDs are found the way the page finds them: by header SHA1, wherever
// they are under the roms folder. Needs Node 18 or later.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const mod = (n) => import(path.join(here, "..", "build", "modules", n + ".js"));
const { checkBios, convert, setForSha1 } = await mod("convert");
const { chdHeaderInfo } = await mod("chd");
const { SETS } = await mod("tables");

const [roms, out, ...want] = process.argv.slice(2);
if (!roms || !out) {
  console.error("usage: verify_node.mjs <roms folder> <out folder> [set ...]");
  process.exit(2);
}
fs.mkdirSync(out, { recursive: true });

const bios = await checkBios(new Uint8Array(fs.readFileSync(path.join(roms, "coh3002t.zip"))));
console.log("coh3002t.zip OK");

const found = {};
const walk = (d) => {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p);
    else if (e.name.toLowerCase().endsWith(".chd")) {
      const fd = fs.openSync(p, "r");
      const head = Buffer.alloc(124);
      fs.readSync(fd, head, 0, 124, 0);
      fs.closeSync(fd);
      const info = chdHeaderInfo(new Uint8Array(head));
      const s = info.ok ? setForSha1(info.sha1) : null;
      if (s) found[s] = p;
      else console.log(`  ${p}: not matched (${info.ok ? "unknown SHA1 " + info.sha1 : info.error})`);
    }
  }
};
walk(roms);

const sets = want.length ? want : Object.keys(SETS).filter((s) => found[s]);
let peak = 0;
const rows = [];
for (const s of sets) {
  if (!found[s]) {
    console.log(`  ${s}: no CHD found`);
    continue;
  }
  const t0 = performance.now();
  const chdBytes = new Uint8Array(fs.readFileSync(found[s]));
  const t1 = performance.now();
  const phases = {};
  let last = t1, lastPhase = "card";
  const r = await convert(chdBytes, bios, s, {
    progress(phase) {
      if (phase !== lastPhase) {
        const now = performance.now();
        phases[lastPhase] = (phases[lastPhase] || 0) + now - last;
        last = now;
        lastPhase = phase;
      }
    },
  });
  const t2 = performance.now();
  phases[lastPhase] = (phases[lastPhase] || 0) + t2 - last;
  fs.writeFileSync(path.join(out, r.name), Buffer.concat(r.parts));
  const rss = process.memoryUsage().rss;
  peak = Math.max(peak, rss);
  const ms = (x) => (x / 1000).toFixed(2);
  rows.push([s, (chdBytes.length / 1e6).toFixed(1), ms(t2 - t1), ms(phases.card || 0), ms(phases.check || 0),
    ms(phases.flash || 0), ms(phases.zip || 0), (rss / 1e6).toFixed(0)]);
  console.log(`  ${r.log}: ${ms(t2 - t1)} s (card ${ms(phases.card || 0)}, sha1 ${ms(phases.check || 0)}, ` +
    `flash ${ms(phases.flash || 0)}, zip ${ms(phases.zip || 0)}), rss ${(rss / 1e6).toFixed(0)} MB`);
}
console.log("\nset\tCHD MB\ttotal s\tcard s\tsha1 s\tflash s\tzip s\tRSS MB");
for (const r of rows) console.log(r.join("\t"));
console.log(`peak RSS ${(peak / 1e6).toFixed(0)} MB`);
