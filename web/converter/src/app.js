// Page logic: pick files, identify CHDs by header SHA1, convert in a worker.
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const el = (tag, text, cls) => {
    const e = document.createElement(tag);
    if (text !== undefined) e.textContent = text;
    if (cls) e.className = cls;
    return e;
  };
  const mb = (n) => (n / 1048576).toFixed(1) + " MB";
  const ALL_LIMIT = 2 * 1024 ** 3;       // offer one combined zip up to this total

  const state = {
    bios: null,          // ArrayBuffer of coh3002t.zip, once it passed the check
    games: new Map(),    // set -> File
    results: new Map(),  // set -> {name, blob, size, crc}
    running: false,
  };

  // ---------------------------------------------------------------- worker

  let worker = null;
  let local = null;      // fallback: the handler on this thread
  const listeners = new Set();
  const dispatch = (m) => listeners.forEach((f) => f(m));

  function startWorker() {
    try {
      const src = $("gnet-lib").textContent + "\n" + $("gnet-worker").textContent;
      const url = URL.createObjectURL(new Blob([src], { type: "text/javascript" }));
      worker = new Worker(url);
      worker.onmessage = (e) => dispatch(e.data);
      worker.onerror = (e) => {
        e.preventDefault();
        useLocal(e.message || "worker error");
      };
    } catch (e) {
      useLocal(e.message);
    }
  }

  function useLocal(why) {
    if (local) return;
    console.warn("converting on the page thread:", why);
    if (worker) worker.terminate();
    worker = null;
    local = gnetHandler(dispatch);
    if (state.bios) local({ type: "init", bios: state.bios });
  }

  function send(msg, transfer) {
    if (worker) worker.postMessage(msg, transfer || []);
    else local(msg);
  }

  // ---------------------------------------------------------------- step 1

  async function setBios(file) {
    const st = $("bios-status");
    st.className = "status";
    st.textContent = "Checking " + file.name + " ...";
    try {
      const buf = await file.arrayBuffer();
      await GNET.checkBios(new Uint8Array(buf), file.name);
      state.bios = buf;
      send({ type: "init", bios: buf.slice(0) });
      st.className = "status ok";
      st.textContent = file.name + ": OK.";
    } catch (e) {
      state.bios = null;
      st.className = "status bad";
      st.textContent = e instanceof GNET.ConvertError ? e.message +
        ". This page needs an unchanged coh3002t.zip from MAME 0.288 or later." : file.name + ": could not be read (" + e.message + ").";
    }
    refresh();
  }

  $("bios").addEventListener("change", (e) => {
    if (e.target.files[0]) setBios(e.target.files[0]);
  });

  // ---------------------------------------------------------------- step 2

  async function identify(files) {
    const st = $("chd-status");
    st.className = "status";
    st.textContent = "Reading " + files.length + " file(s) ...";
    const notes = [];
    let others = 0;
    let biosFile = null;
    const known = new Map();      // chd base name -> set
    for (const [s, v] of Object.entries(GNET.SETS)) known.set(v.chd.toLowerCase(), s);
    for (const f of files) {
      const label = f.webkitRelativePath || f.name;
      const lower = f.name.toLowerCase();
      if (lower === "coh3002t.zip") biosFile = biosFile || f;
      let info;
      try {
        info = GNET.chdHeaderInfo(new Uint8Array(await f.slice(0, 124).arrayBuffer()));
      } catch (e) {
        notes.push([label, "could not be read (" + e.message + ")"]);
        continue;
      }
      const isChdName = lower.endsWith(".chd");
      if (!info.ok && info.error === "not a CHD file") {
        if (isChdName) notes.push([label, "not a CHD file"]);
        else others++;
        continue;
      }
      if (!info.ok) {
        notes.push([label, `CHD version ${info.version}: an older MAME format, not the expected file`]);
        continue;
      }
      const s = GNET.setForSha1(info.sha1);
      if (!s) {
        const base = lower.replace(/\.chd$/, "");
        const hint = known.get(base);
        notes.push([label, hint
          ? `named like the ${hint} CHD, but it is not the expected file (another dump or a changed file; SHA1 ${info.sha1})`
          : `unknown CHD: not a MAME G-NET game on a Taito card (SHA1 ${info.sha1})`]);
        continue;
      }
      if (state.games.has(s) && state.games.get(s) !== f) {
        const prev = state.games.get(s);
        notes.push([label, `same game as ${prev.webkitRelativePath || prev.name} (${s}), already listed`]);
        continue;
      }
      state.games.set(s, f);
    }
    const parts = [`${state.games.size} game(s) ready.`];
    if (others) parts.push(`${others} other file(s) ignored.`);
    st.textContent = parts.join(" ");
    showMatched();
    const ul = $("unmatched").querySelector("ul");
    ul.textContent = "";
    for (const [name, why] of notes) {
      const li = el("li");
      li.append(el("code", name), document.createTextNode(": " + why));
      ul.append(li);
    }
    $("unmatched").hidden = notes.length === 0;
    if (biosFile && !state.bios) await setBios(biosFile);
    refresh();
  }

  function showMatched() {
    const body = $("matched").querySelector("tbody");
    body.textContent = "";
    const order = Object.keys(GNET.SETS);
    const sets = [...state.games.keys()].sort((a, b) => order.indexOf(a) - order.indexOf(b));
    for (const s of sets) {
      const v = GNET.SETS[s];
      const f = state.games.get(s);
      const tr = el("tr");
      tr.append(el("td", s), el("td", v.title), el("td", GNET.CARD_TYPE_NAME[v.card_type]),
        el("td", f.webkitRelativePath || f.name));
      body.append(tr);
    }
    $("matched").hidden = sets.length === 0;
  }

  $("chds").addEventListener("change", (e) => identify([...e.target.files]));
  $("folder").addEventListener("change", (e) => identify([...e.target.files]));

  // ---------------------------------------------------------------- step 3

  function refresh() {
    $("convert").disabled = state.running || !state.bios || state.games.size === 0;
  }

  const PHASES = { read: "reading the CHD", card: "decoding the card", check: "checking the SHA1",
    flash: "building the flash data", zip: "writing the zip" };

  function convertOne(s, file, row) {
    return new Promise((resolve) => {
      const id = Math.random().toString(36).slice(2);
      const bar = row.querySelector("progress"), phase = row.querySelector(".phase"), result = row.cells[2];
      const t0 = performance.now();
      const on = (m) => {
        if (m.id !== id && m.type !== "fatal") return;
        if (m.type === "progress") {
          const base = { read: 0, card: 0.02, check: 0.8, flash: 0.83, zip: 0.86 }[m.phase];
          const span = { read: 0.02, card: 0.78, check: 0.03, flash: 0.03, zip: 0.14 }[m.phase];
          bar.value = base + span * (m.frac || 0);
          phase.textContent = PHASES[m.phase] || m.phase;
          return;
        }
        listeners.delete(on);
        if (m.type === "done") {
          bar.value = 1;
          const secs = ((performance.now() - t0) / 1000).toFixed(1);
          phase.textContent = `done in ${secs} s`;
          const blob = new Blob(m.parts, { type: "application/zip" });
          const url = URL.createObjectURL(blob);
          state.results.set(s, { name: m.name, blob, size: m.size, crc: m.crc, url });
          const a = el("a", m.name);
          a.href = url;
          a.download = m.name;
          result.textContent = "";
          result.append(a, el("span", " " + mb(blob.size), "note"));
        } else {
          phase.textContent = "failed";
          result.textContent = m.message;
          result.className = "bad";
        }
        resolve();
      };
      listeners.add(on);
      on({ type: "progress", id, phase: "read", frac: 0 });
      file.arrayBuffer().then(
        (bytes) => send({ type: "convert", id, set: s, bytes }, [bytes]),
        (e) => on({ type: "error", id, message: `${file.name}: could not be read (${e.message})` }));
    });
  }

  $("convert").addEventListener("click", async () => {
    state.running = true;
    refresh();
    for (const r of state.results.values()) URL.revokeObjectURL(r.url);
    state.results.clear();
    $("all").hidden = true;
    const body = $("jobs").querySelector("tbody");
    body.textContent = "";
    $("jobs").hidden = false;
    const order = Object.keys(GNET.SETS);
    const sets = [...state.games.keys()].sort((a, b) => order.indexOf(a) - order.indexOf(b));
    const rows = new Map();
    for (const s of sets) {
      const tr = el("tr");
      const td = el("td");
      const bar = el("progress");
      bar.max = 1;
      bar.value = 0;
      td.append(bar, el("div", "waiting", "phase"));
      tr.append(el("td", s), td, el("td"));
      body.append(tr);
      rows.set(s, tr);
    }
    for (const s of sets) await convertOne(s, state.games.get(s), rows.get(s));
    state.running = false;
    refresh();
    showAll();
  });

  function showAll() {
    const done = [...state.results.values()];
    if (done.length < 2) return;
    const total = done.reduce((n, r) => n + r.size, 0);
    $("all").hidden = false;
    if (total > ALL_LIMIT) {
      $("save-all").disabled = true;
      $("all-note").textContent = `The zips add up to ${mb(total)}, too much for one download here. Save them one by one.`;
    } else {
      $("save-all").disabled = false;
      $("all-note").textContent = `${done.length} zips, ${mb(total)}`;
    }
  }

  $("save-all").addEventListener("click", () => {
    const z = new GNET.ZipWriter();
    for (const r of state.results.values()) z.addStored(r.name, r.blob, r.crc, r.size);
    const blob = new Blob(z.finish(), { type: "application/zip" });
    const a = el("a");
    a.href = URL.createObjectURL(blob);
    a.download = "gnet_games.zip";
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 60000);
  });

  startWorker();
  refresh();
})();
