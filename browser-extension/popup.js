const statusDot = document.querySelector("#status-dot");
const statusTitle = document.querySelector("#status-title");
const statusDetail = document.querySelector("#status-detail");
const reconnectButton = document.querySelector("#reconnect");
const captureButton = document.querySelector("#capture");
const result = document.querySelector("#result");
const themeButton = document.querySelector("#theme");
const CAPTURE_ORIGINS = ["http://*/*", "https://*/*"];

const savedTheme = localStorage.getItem("beamhop-theme");
if (savedTheme) document.documentElement.dataset.theme = savedTheme;

function renderState(state) {
  statusDot.className = `status-dot ${state.connected ? "connected" : state.error ? "error" : ""}`;
  statusTitle.textContent = state.connected
    ? state.delivery === "socket" ? "Beamhop app connected" : "Browser bridge ready"
    : "Browser bridge unavailable";
  statusDetail.textContent = state.connected
    ? state.pageAccess === false ? "Page access is off. Capture once to grant it."
      : state.delivery === "socket" ? "Ready to deliver to the Beamhop app."
      : state.delivery === "queue" ? "Captures are saved to the secure local browser inbox."
      : "Native host connected."
    : state.error || "Install or reconnect the native messaging host.";
}

async function refresh() {
  const state = await chrome.runtime.sendMessage({ kind: "getNativeState" });
  renderState(state);
}

chrome.runtime.onMessage.addListener((message) => {
  if (message?.kind === "nativeStateChanged") renderState(message.state);
});

reconnectButton.addEventListener("click", async () => {
  result.textContent = "";
  renderState(await chrome.runtime.sendMessage({ kind: "reconnectNative" }));
});

captureButton.addEventListener("click", async () => {
  captureButton.disabled = true;
  result.className = "result";
  result.textContent = "Reading this page...";
  try {
    const granted = await chrome.permissions.request({ origins: CAPTURE_ORIGINS });
    if (!granted) throw new Error("Page access was not granted");
    const response = await chrome.runtime.sendMessage({ kind: "captureCurrentTab" });
    if (!response?.ok) throw new Error(response?.error || "Capture failed");
    result.className = "result success";
    result.textContent = response.receipt?.delivery === "queue"
      ? "Captured and saved to the Beamhop browser inbox."
      : "Captured and sent to Beamhop.";
  } catch (error) {
    result.className = "result error";
    result.textContent = String(error?.message || error);
  } finally {
    captureButton.disabled = false;
  }
});

themeButton.addEventListener("click", () => {
  const current = document.documentElement.dataset.theme ||
    (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  const next = current === "dark" ? "light" : "dark";
  document.documentElement.dataset.theme = next;
  localStorage.setItem("beamhop-theme", next);
});

refresh().catch((error) => renderState({ connected: false, error: String(error?.message || error) }));
