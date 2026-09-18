// Beamhop Bridge — MV3 service worker. Keeps a persistent connectNative port to the native host
// (com.beamhop.bridge), which relays to the Beamhop app. The APP initiates requests; we answer.
//
// Chunking note: Chrome caps host→extension messages at ~1MB but allows extension→host up to
// 4GB, so the big Readability body (extension→app) needs no chunking. We do NOT implement
// response chunking today — replies always go out as a single frame; the app-side reassembly
// in BrowserBridgeServer is a defensive path for future app→extension >1MB chunking.

const HOST = 'com.beamhop.bridge';
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
  const ext_version = chrome.runtime.getManifest().version;
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!tab || !tab.id) return { error: 'no active tab', ext_version };
  const target = { tabId: tab.id };
  try {
    // 1) load Readability into the isolated world, 2) extract.
    await chrome.scripting.executeScript({ target, files: ['vendor/readability.js'] });
    const [{ result } = {}] = await chrome.scripting.executeScript({ target, func: extractInPage });
    return { ...(result || { url: tab.url, title: tab.title }), ext_version };
  } catch (e) {
    // chrome:// pages, PDFs, blocked tabs → fall back to tab metadata only.
    return { url: tab.url, title: tab.title, selection: '', body: '', error: e?.message, ext_version };
  }
}

// Runs in the page (isolated world). Uses Readability (injected above) for the article body,
// plus light GitHub structured extraction.
function extractInPage() {
  const sel = String(window.getSelection?.() || '');
  const meta = document.querySelector('meta[name="description"]')?.content || '';

  let body = '';
  try {
    const R = window.__BeamhopReadability?.Readability;
    if (R) {
      const article = new R(document.cloneNode(true)).parse();
      if (article && article.textContent) body = article.textContent.trim();
    }
  } catch (e) { /* Readability can throw on odd DOMs; body stays empty */ }

  let github = null;
  if (location.hostname.endsWith('github.com')) {
    // priority order — .js-issue-title is the canonical PR/issue title; a bare h1 (search header)
    // appears earlier in the DOM so must NOT win.
    const titleEl = document.querySelector('.js-issue-title')
      || document.querySelector('[data-testid="issue-title"]')
      || document.querySelector('.markdown-title')
      || document.querySelector('article h1, .repository-content h1');
    const kind = location.pathname.includes('/pull/') ? 'pr'
      : location.pathname.includes('/issues/') ? 'issue'
      : (location.pathname.match(/\/blob\/|\/tree\//) ? 'code' : 'repo');
    github = { kind, title: titleEl ? titleEl.textContent.trim() : '' };
  }

  return { url: location.href, title: document.title, meta, selection: sel, body, github };
}

// keep the service worker alive + connected
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
chrome.alarms.create('keepalive', { periodInMinutes: 0.4 });
chrome.alarms.onAlarm.addListener(() => { if (!port) connect(); });
connect();
