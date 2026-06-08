// Beamhop Bridge — MV3 service worker. Keeps a persistent connectNative port to the native host
// (com.beamhop.bridge), which relays to the Beamhop app. The APP initiates requests; we answer.
//
// Chunking note: Chrome caps host→extension messages at ~1MB but allows extension→host up to 4GB,
// so the big Readability body (extension→app) needs no chunking; we only chunk our RESPONSE if it
// somehow exceeds the safe size, and the app reassembles.

const HOST = 'com.beamhop.bridge';
const MAX_RESP = 900 * 1024;   // stay under the 1MB host→extension limit for any host→app... (n/a here, but safe)
let port = null;
let connecting = false;
let backoff = 500;

function connect() {
  if (port || connecting) return;   // idempotent: avoid duplicate ports/host processes
  connecting = true;
  try {
    port = chrome.runtime.connectNative(HOST);
  } catch (e) {
    console.warn('connectNative threw', e);
    connecting = false;
    scheduleReconnect();
    return;
  }
  connecting = false;
  port.onMessage.addListener(onRequest);
  port.onDisconnect.addListener(() => {
    console.warn('host disconnected', chrome.runtime.lastError?.message);
    port = null;
    scheduleReconnect();
  });
  backoff = 500;
  console.log('connected to native host');
}

function scheduleReconnect() {
  const delay = Math.min(backoff, 10000);
  backoff *= 2;
  setTimeout(connect, delay);
}

function reply(reqID, ok, payload) {
  if (!port) return;
  const msg = ok ? { reqID, ok: true, result: payload } : { reqID, ok: false, error: String(payload) };
  port.postMessage(msg);
}

async function onRequest(req) {
  const { reqID, type } = req || {};
  if (reqID == null) return;
  try {
    if (type === 'ping') {
      reply(reqID, true, { pong: true, ext_version: chrome.runtime.getManifest().version });
    } else if (type === 'capture_active_tab') {
      const data = await captureActiveTab();
      reply(reqID, true, data);
    } else {
      reply(reqID, false, 'unknown type ' + type);
    }
  } catch (e) {
    reply(reqID, false, e?.message || String(e));
  }
}

async function captureActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!tab || !tab.id) return { error: 'no active tab' };
  const [{ result } = {}] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: extractInPage,
  });
  return result || { url: tab.url, title: tab.title };
}

// Runs in the page (injected). Readability is added in a later step; for now: url/title/meta/selection.
function extractInPage() {
  const sel = String(window.getSelection?.() || '');
  const meta = document.querySelector('meta[name="description"]')?.content || '';
  return { url: location.href, title: document.title, meta, selection: sel };
}

// keep the service worker alive + connected
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
chrome.alarms.create('keepalive', { periodInMinutes: 0.4 });
chrome.alarms.onAlarm.addListener(() => { if (!port) connect(); });
connect();
