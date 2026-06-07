let port = null;
function ensurePort() {
  if (port) return port;
  port = chrome.runtime.connectNative('com.beamhop.bridge');
  port.onDisconnect.addListener(() => {
    console.warn('host disconnected', chrome.runtime.lastError);
    port = null;
  });
  return port;
}

let seq = 0;

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  const id = ++seq;
  const p = ensurePort();
  const handler = (resp) => {
    if (resp.id === id) { p.onMessage.removeListener(handler); sendResponse(resp); }
  };
  p.onMessage.addListener(handler);
  p.postMessage({ id, ...msg });
  return true; // keep sendResponse alive for async reply
});
