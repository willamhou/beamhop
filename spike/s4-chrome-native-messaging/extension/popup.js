const out = document.getElementById('out');
const log = (s) => { out.textContent += s + '\n'; };

// send a message to the background, which relays to the native host; resolves with the
// response or rejects on timeout / runtime error (so the UI never hangs silently).
function call(msg, timeoutMs = 8000) {
  return new Promise((resolve, reject) => {
    let done = false;
    const t = setTimeout(() => { if (!done) { done = true; reject(new Error('timeout')); } }, timeoutMs);
    chrome.runtime.sendMessage(msg, (resp) => {
      if (done) return;
      done = true; clearTimeout(t);
      if (chrome.runtime.lastError) return reject(new Error(chrome.runtime.lastError.message));
      if (resp && resp.error) return reject(new Error('host error: ' + resp.error));
      resolve(resp);
    });
  });
}

document.getElementById('ping').onclick = async () => {
  try { log('ping -> ' + JSON.stringify(await call({ kind: 'ping' }))); }
  catch (e) { log('ping FAILED: ' + e.message); }
};

document.getElementById('bench').onclick = async () => {
  const times = [];
  try {
    for (let i = 0; i < 10; i++) {
      const t0 = performance.now();
      await call({ kind: 'echo', size: 900 * 1024 });
      times.push(performance.now() - t0);
    }
    times.sort((a, b) => a - b);
    log(`bench median=${times[5].toFixed(1)}ms p95=${times[9].toFixed(1)}ms all=${times.map(t=>t.toFixed(0)).join(',')}`);
  } catch (e) { log('bench FAILED: ' + e.message); }
};

// boundary probes: host generates `size` bytes so the extension->host msg stays tiny;
// this isolates the host->extension ~1MB limit.
for (const btn of document.querySelectorAll('button[data-size]')) {
  btn.onclick = async () => {
    const size = parseInt(btn.dataset.size, 10);
    const t0 = performance.now();
    try {
      const resp = await call({ kind: 'echo', size });
      const dt = (performance.now() - t0).toFixed(1);
      const got = resp?.body?.length ?? 0;
      log(`echo ${(size/1024).toFixed(0)}KB -> got ${got} bytes, match=${got === size}, ${dt}ms`);
    } catch (e) {
      log(`echo ${(size/1024).toFixed(0)}KB -> FAILED (${e.message}) — likely Chrome's host->extension limit`);
    }
  };
}
