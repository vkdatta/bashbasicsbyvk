// The resilient transfer tool, ux pipeline + signals, against a tiny fake server (no worker needed).
//   node tests/xfer_ux.mjs
import http from "node:http"; import fs from "node:fs"; import os from "node:os"; import path from "node:path"; import { spawn } from "node:child_process"; import assert from "node:assert/strict";
const XFER = path.resolve("script/file/staging/!buffer/fileapi/6 pending/bashbasicsbyvk_staging_pending_xfer");
const got = new Map(); let failNext = 0, slow = 0, tokenBad = false;
const srv = http.createServer(async (req, res) => {
  const chunks = []; for await (const c of req) chunks.push(c);
  if (tokenBad) { res.statusCode = 401; res.setHeader("content-type", "application/json"); return res.end('{"error":"invalid_upload_token"}'); }
  if (slow) await new Promise((r) => setTimeout(r, slow));
  if (failNext > 0) { failNext--; return req.socket.destroy(); }
  got.set(req.url, Buffer.concat(chunks).length); res.end("{}");
});
await new Promise((r) => srv.listen(0, r)); const base = `http://127.0.0.1:${srv.address().port}`;
const ID = "A".repeat(43), tmp = fs.mkdtempSync(path.join(os.tmpdir(), "xf-")), state = path.join(tmp, "st"); fs.mkdirSync(state);
const items = [{ k: "f", i: "I".repeat(22), c: 4 }, { k: "d", i: "D".repeat(22), c: 0 }];
fs.writeFileSync(path.join(tmp, "commit.json"), JSON.stringify({ items }));
for (let i = 0; i < 4; i++) fs.writeFileSync(path.join(tmp, `${items[0].i}.${i}`), Buffer.alloc(1000 + i, i));
const run = (env, onSpawn) => new Promise((res) => { const p = spawn("node", [XFER, "ux", base, ID, tmp], { env: { ...process.env, BB_UTOKEN: "t", BB_STATE: state, BB_OFFLINE_MAX: "20", ...env } }); let out = ""; p.stdout.on("data", (d) => out += d); onSpawn?.(p); p.on("close", () => res(out.trim().split("\n").pop())); });
const sizes = { [`${items[0].i}.0`]: 1000, [`${items[0].i}.1`]: 1001, [`${items[0].i}.2`]: 9 /* truncated on the server */ };
fs.writeFileSync(path.join(tmp, "server.json"), JSON.stringify({ doneItems: { [items[0].i]: "0-2" }, sizes }));
assert.equal(await run({ BB_DONEFILE: path.join(tmp, "server.json") }), "OK");
const sent = [...got.keys()].map((u) => u.split("/").pop()).sort();
assert.deepEqual(sent, ["2", "3"], "blobs 0-1 skipped; blob 2 re-sent because its stored size was wrong; blob 3 missing");
console.log("  ✓ ux: only the missing / truncated chunks are sent");
got.clear(); failNext = 3;
assert.equal(await run({ BB_DONEFILE: "" }), "OK"); assert.equal(got.size, 4);
console.log("  ✓ ux: dropped connections are waited out and retried (3 failures, then all 4 chunks arrive)");
got.clear(); tokenBad = true; assert.equal(await run({ BB_DONEFILE: "" }), "TOKEN"); tokenBad = false;
console.log("  ✓ expired token → verdict TOKEN (the caller mints a new one)");
fs.writeFileSync(path.join(state, "pause.flag"), ""); got.clear();
assert.equal(await run({ BB_DONEFILE: "" }), "PAUSED"); fs.rmSync(path.join(state, "pause.flag"));
console.log("  ✓ pause.flag from another terminal → PAUSED");
slow = 1500; got.clear();
assert.equal(await run({ BB_DONEFILE: "" }, (p) => setTimeout(() => p.kill("SIGINT"), 600)), "INTERRUPTED");
console.log("  ✓ SIGINT (Ctrl-C) → INTERRUPTED, nothing thrown away"); slow = 0;
fs.writeFileSync(path.join(state, "stop.flag"), ""); assert.equal(await run({ BB_DONEFILE: "" }), "STOPPED"); fs.rmSync(path.join(state, "stop.flag"));
console.log("  ✓ stop.flag → STOPPED");
assert.match(fs.readFileSync(path.join(state, "progress"), "utf8"), /^\d+ 4 /);
console.log("  ✓ progress bookmark written");
srv.close(); fs.rmSync(tmp, { recursive: true }); console.log("xfer ux tests passed");
