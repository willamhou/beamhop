// Auto-test page: drives the full native-messaging sequence with NO user clicks, then
// reports results back through the native host (which writes /tmp/beamhop_s4_result.json).
// Each call uses a FRESH native port so an oversized-message disconnect doesn't break the
// next test.

const out = document.getElementById('out');
const lines = [];
const log = (s) => { lines.push(s); out.textContent = lines.join('\n'); console.log('S4', s); };
console.log('S4 auto.js loaded, runtime.id =', chrome?.runtime?.id);

const HOST = 'com.beamhop.bridge';

function nativeCall(msg, timeoutMs = 8000) {
  return new Promise((resolve) => {
    let port, settled = false;
    const done = (r) => { if (settled) return; settled = true; clearTimeout(timer); try { port.disconnect(); } catch {} resolve(r); };
    const timer = setTimeout(() => done({ error: 'timeout' }), timeoutMs);
    try {
      port = chrome.runtime.connectNative(HOST);
    } catch (e) { clearTimeout(timer); return resolve({ error: 'connectNative threw: ' + e.message }); }
    port.onMessage.addListener((resp) => done({ resp }));
    port.onDisconnect.addListener(() => done({ error: chrome.runtime.lastError?.message || 'disconnected' }));
    try { port.postMessage(msg); } catch (e) { done({ error: 'postMessage threw: ' + e.message }); }
  });
}

async function run() {
  const result = { ts: new Date().toISOString(), ua: navigator.userAgent, tests: {} };

  // 1) ping
  const ping = await nativeCall({ id: 1, kind: 'ping' });
  result.tests.ping = ping.resp || ping;
  log('ping -> ' + JSON.stringify(result.tests.ping));

  // 2) 900KB round-trip benchmark (10 runs, fresh port each — includes host spawn overhead)
  const times = [];
  let benchOk = true;
  for (let i = 0; i < 10; i++) {
    const t0 = performance.now();
    const r = await nativeCall({ id: 100 + i, kind: 'echo', size: 900 * 1024 });
    const dt = performance.now() - t0;
    if (r.error || (r.resp?.body?.length !== 900 * 1024)) { benchOk = false; }
    times.push(dt);
  }
  times.sort((a, b) => a - b);
  result.tests.bench_900kb = {
    ok: benchOk, median_ms: +times[5].toFixed(1), p95_ms: +times[9].toFixed(1),
    all_ms: times.map(t => +t.toFixed(0)), note: 'fresh host process per call (includes spawn overhead)'
  };
  log(`bench 900KB: ok=${benchOk} median=${times[5].toFixed(1)}ms p95=${times[9].toFixed(1)}ms`);

  // 3) host->extension size-limit boundary probe
  result.tests.boundary = {};
  for (const size of [921600, 1153434, 2097152]) {
    const r = await nativeCall({ id: 200, kind: 'echo', size });
    const got = r.resp?.body?.length ?? 0;
    const entry = { requested: size, got, match: got === size, error: r.error || null };
    result.tests.boundary[size] = entry;
    log(`echo ${(size/1024).toFixed(0)}KB -> got=${got} match=${entry.match} err=${entry.error || '—'}`);
  }

  // 4) report back to host (fresh port) so it writes the result file
  log('reporting results to host…');
  const rep = await nativeCall({ id: 999, kind: 'report', data: result });
  log('report -> ' + JSON.stringify(rep.resp || rep));
  out.textContent += '\n\nDONE.';
}

run().catch((e) => { log('FATAL: ' + e.message); });
