const out = document.getElementById('out');
const log = (s) => { out.textContent += s + '\n'; };

document.getElementById('ping').onclick = () => {
  chrome.runtime.sendMessage({ kind: 'ping' }, (resp) => {
    log('ping -> ' + JSON.stringify(resp));
  });
};

document.getElementById('big').onclick = () => {
  const payload = 'A'.repeat(900 * 1024);
  const t0 = performance.now();
  chrome.runtime.sendMessage({ kind: 'echo', body: payload }, (resp) => {
    const t1 = performance.now();
    log(`big roundtrip ${(t1 - t0).toFixed(1)} ms, echo len=${resp?.body?.length}`);
  });
};

document.getElementById('bench').onclick = async () => {
  const times = [];
  for (let i = 0; i < 10; i++) {
    const t0 = performance.now();
    await new Promise(r => chrome.runtime.sendMessage({ kind: 'echo', body: 'x'.repeat(900*1024) }, r));
    times.push(performance.now() - t0);
  }
  times.sort((a,b)=>a-b);
  log(`bench median=${times[5].toFixed(1)} p95=${times[9].toFixed(1)} all=${times.map(t=>t.toFixed(0)).join(',')}`);
};
