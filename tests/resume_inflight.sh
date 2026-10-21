#!/usr/bin/env bash
# Resume after a lost connection keeps the blobs that were COMPLETE.  A PUT is all-or-nothing, so with many blobs in flight an outage at
# 80 MB of 115 MB leaves almost nothing stored (the 201020260630 bug).  Mock worker, no real server needed.   bash tests/resume_inflight.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
X="$ROOT/script/file/staging/!buffer/fileapi/6 pending/bashbasicsbyvk_staging_pending_xfer"
T=$(mktemp -d); trap 'kill $MP 2>/dev/null; rm -rf "$T"' EXIT; MP=""
cat > "$T/mock.js" <<'JS'
// mock worker: stores a blob ONLY when its whole PUT body arrived (like R2 put). Shared 30 MB/s bandwidth.
const http=require("http"),fs=require("fs");
const RATE=(+process.env.RATE_MB||30)*1048576; let nextFree=Date.now();
const store=new Map(); let wire=0;
let cut=false; const socks=new Set();
const srv=http.createServer((req,res)=>{
  if(req.url==="/_cut"){cut=true;for(const k of socks)k.destroy();res.end("ok");return;}
  if(cut&&req.url!=="/_state"){req.socket.destroy();return;}
  const m=/^\/upload\/[^/]+\/blob\/(\d+)$/.exec(req.url);
  if(req.url==="/_state"){res.end(JSON.stringify({wireMB:+(wire/1048576).toFixed(1),done:[...store.keys()].sort((a,b)=>a-b).join(","),sizes:Object.fromEntries(store),doneMB:+([...store.values()].reduce((a,b)=>a+b,0)/1048576).toFixed(1)}));return;}
  if(!m){res.statusCode=404;res.end("{}");return;}
  let n=0;
  req.on("data",async c=>{ req.pause(); const now=Date.now(); nextFree=Math.max(now,nextFree)+c.length/RATE*1000; n+=c.length; wire+=c.length;
    const w=nextFree-now; setTimeout(()=>req.resume(),Math.max(0,w)); });
  req.on("end",()=>{store.set(m[1],n);res.statusCode=200;res.end("{}");});
  req.on("error",()=>{});
});
srv.on("connection",k=>{socks.add(k);k.on("close",()=>socks.delete(k));k.on("error",()=>{});});
srv.listen(+process.env.PORT||8799,()=>console.log("up"));
JS
ID=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA; PORT=${PORT:-8799}
for i in 0 1 2 3 4 5 6; do head -c 16777216 /dev/urandom > "$T/blob$i"; done; head -c 3000000 /dev/urandom > "$T/blob7"
kept_mb() {   # $1 = concurrency → MB stored on the mock after the connection is cut at ~80 MB on the wire
  PORT=$PORT node "$T/mock.js" >/dev/null & MP=$!; sleep 0.5
  BB_UTOKEN=t BB_EMAIL=e BB_N=8 BB_CHUNK=94371840 BB_CONC=$1 BB_STATE="$T" BB_DONEFILE=/nonexistent node "$X" upload "http://127.0.0.1:$PORT" $ID "$T" >/dev/null 2>&1 & local xp=$!
  local w; while :; do w=$(curl -s 127.0.0.1:$PORT/_state | sed -n 's/.*"wireMB":\([0-9.]*\).*/\1/p'); [ "${w%.*}" -ge 80 ] && break; sleep 0.2; done
  curl -s 127.0.0.1:$PORT/_cut >/dev/null; sleep 1.5
  curl -s 127.0.0.1:$PORT/_state | sed -n 's/.*"doneMB":\([0-9.]*\).*/\1/p'
  kill -TERM $xp 2>/dev/null; wait $xp 2>/dev/null; kill $MP; wait $MP 2>/dev/null
}
fail=0
a=$(kept_mb 16); b=$(kept_mb 4)   # (16 × 16 MB blobs-in-flight = old behaviour; 4 = what 16 MB blobs get now)
echo "  16 blobs in flight: ${a} MB kept   ·   4 in flight (the default now): ${b} MB kept   (cut at ~80 MB sent)"
[ "${b%.*}" -ge 50 ] && echo "  ok   default concurrency keeps >= 50 MB" || { echo "  FAIL default concurrency keeps too little"; fail=1; }
exit $fail
