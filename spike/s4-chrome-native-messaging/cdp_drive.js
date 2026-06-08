// Drives the S4 test over CDP (Chrome 137+ removed --load-extension; this is the supported
// replacement, gated by --enable-unsafe-extension-debugging).
//  1) Extensions.loadUnpacked -> real extension id
//  2) write the native-messaging host manifest with that id
//  3) open chrome-extension://<id>/auto.html -> the page auto-runs the test
//  4) the native host writes /tmp/beamhop_s4_result.json (polled by the shell)
const fs = require('fs'), os = require('os'), path = require('path');

const EXTDIR = process.argv[2];
const HOST_BIN = process.argv[3];
const WS = process.argv[4];

const ws = new WebSocket(WS);
let nextId = 1;
const pending = new Map();
function send(method, params = {}) {
  const id = nextId++;
  ws.send(JSON.stringify({ id, method, params }));
  return new Promise((res, rej) => pending.set(id, { res, rej }));
}

ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) {
    const { res, rej } = pending.get(m.id); pending.delete(m.id);
    m.error ? rej(new Error(JSON.stringify(m.error))) : res(m.result);
  }
};

ws.onopen = async () => {
  try {
    const { id: extId } = await send('Extensions.loadUnpacked', { path: EXTDIR });
    console.error('loaded extension id =', extId);

    const target = path.join(os.homedir(), 'Library/Application Support/Google/Chrome/NativeMessagingHosts');
    fs.mkdirSync(target, { recursive: true });
    fs.writeFileSync(path.join(target, 'com.beamhop.bridge.json'), JSON.stringify({
      name: 'com.beamhop.bridge',
      description: 'Beamhop spike S4 native host',
      path: HOST_BIN,
      type: 'stdio',
      allowed_origins: [`chrome-extension://${extId}/`],
    }, null, 2));
    console.error('wrote native host manifest for', extId);

    await send('Target.createTarget', { url: `chrome-extension://${extId}/auto.html` });
    console.error('opened auto.html — test running');
    setTimeout(() => { ws.close(); process.exit(0); }, 3000);
  } catch (e) {
    console.error('CDP error:', e.message); process.exit(1);
  }
};
ws.onerror = (e) => { console.error('ws error', e.message || e); process.exit(1); };
