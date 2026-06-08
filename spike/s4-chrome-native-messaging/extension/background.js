// MV3 service worker. Relays popup messages to the native host over a persistent port,
// matching responses by id. Hardened per codex review: surfaces disconnect/lastError,
// times out pending requests, and cleans up listeners.

let port = null;
const pending = new Map(); // id -> { sendResponse, timer }
let seq = 0;

function teardown(reason) {
  for (const [, p] of pending) { clearTimeout(p.timer); try { p.sendResponse({ error: reason }); } catch {} }
  pending.clear();
  port = null;
}

function ensurePort() {
  if (port) return port;
  port = chrome.runtime.connectNative('com.beamhop.bridge');
  port.onMessage.addListener((resp) => {
    const p = pending.get(resp.id);
    if (p) { clearTimeout(p.timer); pending.delete(resp.id); p.sendResponse(resp); }
  });
  port.onDisconnect.addListener(() => {
    const err = chrome.runtime.lastError?.message || 'host disconnected';
    console.warn('native host disconnected:', err);
    teardown(err);
  });
  return port;
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  const id = ++seq;
  let p;
  try { p = ensurePort(); } catch (e) { sendResponse({ error: 'connectNative failed: ' + e.message }); return false; }
  const timer = setTimeout(() => {
    if (pending.has(id)) { pending.delete(id); sendResponse({ error: 'host timeout' }); }
  }, 8000);
  pending.set(id, { sendResponse, timer });
  try {
    p.postMessage({ id, ...msg });
  } catch (e) {
    clearTimeout(timer); pending.delete(id);
    sendResponse({ error: 'postMessage failed: ' + e.message });
    return false;
  }
  return true; // keep sendResponse alive for the async reply
});
