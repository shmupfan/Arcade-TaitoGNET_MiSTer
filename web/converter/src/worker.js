// Conversion worker. build.py places the bundled library (GNET) in front of
// this code; the page starts it from a Blob, so the single HTML file needs no
// other files. The page runs the same handler on its own thread if a worker
// cannot be started.

function gnetHandler(post) {
  let bios = null;
  return async function onMessage(msg) {
    if (msg.type === "init") {
      bios = await GNET.checkBios(new Uint8Array(msg.bios));
      return;
    }
    if (msg.type !== "convert") return;
    // the CHD comes in and the zip goes out as ArrayBuffers, not File or Blob
    // objects: Safari cannot read a page's File in a Blob worker on file://
    const { id, set, bytes } = msg;
    const t0 = Date.now();
    try {
      const r = await GNET.convert(new Uint8Array(bytes), bios, set, {
        progress: (phase, frac) => post({ type: "progress", id, phase, frac }),
      });
      const parts = r.parts;
      const buffers = [...new Set(parts.map((p) => p.buffer))];
      post({ type: "done", id, set, name: r.name, parts, size: r.size, crc: r.crc, log: r.log, ms: Date.now() - t0 },
        buffers);
    } catch (e) {
      post({ type: "error", id, set, message: e && e.message ? e.message : String(e) });
    }
  };
}

if (typeof WorkerGlobalScope !== "undefined" && self instanceof WorkerGlobalScope) {
  const handle = gnetHandler((m, transfer) => self.postMessage(m, transfer || []));
  let queue = Promise.resolve();
  self.onmessage = (e) => {
    queue = queue.then(() => handle(e.data)).catch((err) => self.postMessage({ type: "fatal", message: String(err && err.message || err) }));
  };
}
