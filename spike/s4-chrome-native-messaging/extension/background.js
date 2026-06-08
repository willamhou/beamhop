// MV3 service worker. On install/startup it auto-runs the native-messaging test and reports
// results back through the native host (which writes /tmp/beamhop_s4_result.json). Also keeps
// a relay listener for the manual popup. Hardened per codex review (timeouts, lastError,
// listener cleanup).

const HOST = 'com.beamhop.bridge';

// One message over a FRESH native port; resolves {resp} or {error}. Fresh port per call means
// an oversized-message disconnect doesn't break the next test.
function nativeCall(msg, timeoutMs = 8000) {
  return new Promise((resolve) => {
    let port, settled = false;
    const done = (r) => { if (settled) return; settled = true; clearTimeout(timer); try { port.disconnect(); } catch {} resolve(r); };
    const timer = setTimeout(() => done({ error: 'timeout' }), timeoutMs);
    try { port = chrome.runtime.connectNative(HOST); }
    catch (e) { clearTimeout(timer); return resolve({ error: 'connectNative threw: ' + e.message }); }
    port.onMessage.addListener((resp) => done({ resp }));
    port.onDisconnect.addListener(() => done({ error: chrome.runtime.lastError?.message || 'disconnected' }));
    try { port.postMessage(msg); } catch (e) { done({ error: 'postMessage threw: ' + e.message }); }
  });
}

async function runAutoTest(trigger) {
  const result = { ts: new Date().toISOString(), trigger, ua: navigator.userAgent, tests: {} };

  const ping = await nativeCall({ id: 1, kind: 'ping' });
  result.tests.ping = ping.resp || ping;

  const times = []; let benchOk = true;
  for (let i = 0; i < 10; i++) {
    const t0 = performance.now();
    const r = await nativeCall({ id: 100 + i, kind: 'echo', size: 900 * 1024 });
    if (r.error || r.resp?.body?.length !== 900 * 1024) benchOk = false;
    times.push(performance.now() - t0);
  }
  times.sort((a, b) => a - b);
  result.tests.bench_900kb = {
    ok: benchOk, median_ms: +times[5].toFixed(1), p95_ms: +times[9].toFixed(1),
    all_ms: times.map(t => +t.toFixed(0)), note: 'fresh host process per call (includes spawn overhead)'
  };

  result.tests.boundary = {};
  for (const size of [921600, 1153434, 2097152]) {
    const r = await nativeCall({ id: 200, kind: 'echo', size });
    const got = r.resp?.body?.length ?? 0;
    result.tests.boundary[size] = { requested: size, got, match: got === size, error: r.error || null };
  }

  await nativeCall({ id: 999, kind: 'report', data: result });
}

chrome.runtime.onInstalled.addListener(() => { runAutoTest('onInstalled'); });
chrome.runtime.onStartup.addListener(() => { runAutoTest('onStartup'); });

// manual popup relay (optional)
let seq = 0;
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  const id = ++seq;
  nativeCall({ id, ...msg }).then((r) => sendResponse(r.resp || r));
  return true;
});
