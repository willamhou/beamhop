import {
  ChunkAssembler,
  encodeLogicalMessage,
  makeControl,
  makeLogicalMessage
} from "./protocol.js";

const HOST_NAME = "com.beamhop.bridge";
const CAPTURE_ORIGINS = ["http://*/*", "https://*/*"];
const ACK_TIMEOUT_MS = 2_000;
const MAX_RETRIES = 2;
const incoming = new ChunkAssembler();
const pendingTransfers = new Map();
let nativePort = null;
let nativeState = { connected: false, delivery: "unavailable", error: null, connectedAt: null };

function broadcastState() {
  chrome.runtime.sendMessage({ kind: "nativeStateChanged", state: nativeState }).catch(() => {});
}

function updateState(patch) {
  nativeState = { ...nativeState, ...patch };
  broadcastState();
}

function settlePending(transferId, result, error) {
  const pending = pendingTransfers.get(transferId);
  if (!pending) return;
  clearTimeout(pending.timer);
  pendingTransfers.delete(transferId);
  if (error) pending.reject(error);
  else pending.resolve(result);
}

function armRetry(transferId) {
  const pending = pendingTransfers.get(transferId);
  if (!pending) return;
  clearTimeout(pending.timer);
  pending.timer = setTimeout(() => {
    if (!nativePort) {
      settlePending(transferId, null, new Error("Native host disconnected"));
      return;
    }
    if (pending.retries >= MAX_RETRIES) {
      settlePending(transferId, null, new Error("Native host did not acknowledge the transfer"));
      return;
    }
    pending.retries += 1;
    for (const [index, chunk] of pending.unacked) nativePort.postMessage(chunk);
    armRetry(transferId);
  }, ACK_TIMEOUT_MS);
}

function connectNative() {
  if (nativePort) return nativePort;
  try {
    const port = chrome.runtime.connectNative(HOST_NAME);
    nativePort = port;
    updateState({ connected: true, error: null, connectedAt: new Date().toISOString() });
    port.onMessage.addListener(handleNativeMessage);
    port.onDisconnect.addListener(() => {
      const error = chrome.runtime.lastError?.message || "Native host disconnected";
      if (nativePort === port) nativePort = null;
      updateState({ connected: false, delivery: "unavailable", error });
      for (const transferId of [...pendingTransfers.keys()]) {
        settlePending(transferId, null, new Error(error));
      }
    });
    return port;
  } catch (error) {
    updateState({ connected: false, delivery: "unavailable", error: String(error?.message || error) });
    return null;
  }
}

async function sendLogical(message) {
  const port = connectNative();
  if (!port) throw new Error(nativeState.error || "Native host is unavailable");
  const chunks = encodeLogicalMessage(message);
  const transferId = chunks[0].transferId;
  return new Promise((resolve, reject) => {
    pendingTransfers.set(transferId, {
      resolve,
      reject,
      retries: 0,
      unacked: new Map(chunks.map((chunk) => [chunk.index, chunk])),
      timer: null
    });
    for (const chunk of chunks) port.postMessage(chunk);
    armRetry(transferId);
  });
}

async function captureCurrentTab() {
  const hasAccess = await chrome.permissions.contains({ origins: CAPTURE_ORIGINS });
  if (!hasAccess) {
    const error = new Error("Allow page access from the Beamhop popup before desktop capture");
    error.code = "PERMISSION_REQUIRED";
    throw error;
  }
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) throw new Error("No active tab");
  if (!/^https?:/i.test(tab.url || "")) {
    throw new Error("Chrome does not allow capture on this page");
  }
  await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["readability.js"] });
  const results = await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["capture-page.js"] });
  const capture = results?.[0]?.result;
  if (!capture || capture.captureError) throw new Error(capture?.captureError || "The page returned no capture");
  return {
    ...capture,
    tabId: tab.id,
    windowId: tab.windowId,
    isPrivate: Boolean(tab.incognito),
    extensionVersion: chrome.runtime.getManifest().version
  };
}

async function handleLogical(message) {
  if (message.route === "browser.captureCurrentTab") {
    try {
      const capture = await captureCurrentTab();
      await sendLogical(makeLogicalMessage("browser.captureResult", { ok: true, capture }, message.requestId));
    } catch (error) {
      await sendLogical(makeLogicalMessage("browser.captureResult", {
        ok: false,
        error: { code: error?.code || "CAPTURE_FAILED", message: String(error?.message || error) }
      }, message.requestId));
    }
  }
}

function handleNativeMessage(message) {
  if (message?.type === "chunkAck") {
    const pending = pendingTransfers.get(message.transferId);
    if (pending) pending.unacked.delete(message.index);
    return;
  }
  if (message?.type === "transferComplete") {
    updateState({ delivery: message.delivery || nativeState.delivery, error: null });
    settlePending(message.transferId, message);
    return;
  }
  if (message?.type === "transferError") {
    settlePending(message.transferId, null, new Error(`${message.code}: ${message.message || "transfer failed"}`));
    return;
  }
  if (message?.type === "bridgeStatus") {
    updateState({ delivery: message.delivery || "unavailable", error: message.error || null });
    return;
  }
  if (message?.type === "chunk") {
    const result = incoming.accept(message);
    nativePort?.postMessage(makeControl("chunkAck", {
      transferId: message.transferId,
      index: message.index,
      received: result.received ?? message.total,
      total: message.total
    }));
    if (result.status === "complete") {
      nativePort?.postMessage(makeControl("transferComplete", { transferId: result.transferId, requestId: result.requestId }));
      handleLogical(result.message).catch((error) => {
        nativePort?.postMessage(makeControl("transferError", {
          transferId: result.transferId,
          requestId: result.requestId,
          code: "ROUTE_FAILED",
          message: String(error?.message || error)
        }));
      });
    } else if (result.status === "error") {
      nativePort?.postMessage(makeControl("transferError", {
        transferId: message.transferId,
        requestId: message.requestId,
        code: result.code,
        message: "Browser could not reassemble native-host chunks"
      }));
    }
  }
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.kind === "getNativeState") {
    connectNative();
    chrome.permissions.contains({ origins: CAPTURE_ORIGINS })
      .then((pageAccess) => {
        nativeState = { ...nativeState, pageAccess };
        sendResponse(nativeState);
      });
    return true;
  }
  if (message?.kind === "reconnectNative") {
    nativePort?.disconnect();
    nativePort = null;
    connectNative();
    sendResponse(nativeState);
    return false;
  }
  if (message?.kind === "captureCurrentTab") {
    (async () => {
      const capture = await captureCurrentTab();
      const receipt = await sendLogical(makeLogicalMessage("browser.captureResult", { ok: true, capture }));
      sendResponse({ ok: true, capture, receipt });
    })().catch((error) => sendResponse({
      ok: false,
      code: error?.code || "CAPTURE_FAILED",
      error: String(error?.message || error)
    }));
    return true;
  }
  return false;
});

connectNative();
setInterval(() => {
  const expired = incoming.cleanup();
  for (const item of expired) {
    nativePort?.postMessage(makeControl("transferError", {
      ...item,
      message: "Host-to-browser reassembly timed out; resend with a new transferId"
    }));
  }
}, 5_000);
