// Fully automated S4: owns an isolated Chrome over CDP *pipe* transport (the Extensions
// domain — loadUnpacked — is gated to pipe, not port). Loads the unpacked extension, writes
// the native-messaging host manifest with the returned id, opens auto.html to run the test,
// and waits for the host to write /tmp/beamhop_s4_result.json.
const { spawn } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');

const HERE = __dirname;
const EXTDIR = path.join(HERE, 'extension');
const HOST_BIN = path.join(HERE, 'host', 'beamhop-bridge');
const PROFILE = '/tmp/beamhop_s4_profile';
const RESULT = '/tmp/beamhop_s4_result.json';
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

for (const f of [RESULT, '/tmp/beamhop_s4_host_alive.txt']) { try { fs.unlinkSync(f); } catch {} }
fs.rmSync(PROFILE, { recursive: true, force: true });

// CDP pipe: JSON messages on fd3 (write) / fd4 (read), NUL-delimited.
const chrome = spawn(CHROME, [
  `--user-data-dir=${PROFILE}`,
  '--no-first-run', '--no-default-browser-check',
  '--enable-unsafe-extension-debugging',
  '--remote-debugging-pipe',

  'about:blank',
], { stdio: ['ignore', 'ignore', 'inherit', 'pipe', 'pipe'] });

const writePipe = chrome.stdio[3];
const readPipe = chrome.stdio[4];

let nextId = 1; const pending = new Map();
function send(method, params = {}, sessionId) {
  const id = nextId++;
  const obj = { id, method, params }; if (sessionId) obj.sessionId = sessionId;
  writePipe.write(JSON.stringify(obj) + '\0');
  return new Promise((res, rej) => pending.set(id, { res, rej }));
}
let buf = Buffer.alloc(0);
readPipe.on('data', (chunk) => {
  buf = Buffer.concat([buf, chunk]);
  let i;
  while ((i = buf.indexOf(0)) !== -1) {
    const msg = buf.slice(0, i).toString('utf8'); buf = buf.slice(i + 1);
    if (!msg) continue;
    let m; try { m = JSON.parse(msg); } catch { continue; }
    if (m.id && pending.has(m.id)) {
      const { res, rej } = pending.get(m.id); pending.delete(m.id);
      m.error ? rej(new Error(JSON.stringify(m.error))) : res(m.result);
    } else if (m.method === 'Runtime.consoleAPICalled') {
      const args = (m.params.args || []).map(a => a.value ?? a.description ?? '').join(' ');
      console.error('[page]', args);
    } else if (m.method === 'Runtime.exceptionThrown') {
      console.error('[page-exception]', JSON.stringify(m.params.exceptionDetails?.exception?.description || m.params.exceptionDetails?.text));
    }
  }
});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  try {
    await sleep(1500); // let Chrome come up
    const { id: extId } = await send('Extensions.loadUnpacked', { path: EXTDIR });
    console.error('loaded extension id =', extId);

    const manifest = JSON.stringify({
      name: 'com.beamhop.bridge', description: 'Beamhop spike S4 native host',
      path: HOST_BIN, type: 'stdio', allowed_origins: [`chrome-extension://${extId}/`],
    }, null, 2);
    // write to BOTH the standard user location and the custom profile dir
    for (const dir of [
      path.join(os.homedir(), 'Library/Application Support/Google/Chrome/NativeMessagingHosts'),
      path.join(PROFILE, 'NativeMessagingHosts'),
    ]) {
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, 'com.beamhop.bridge.json'), manifest);
    }
    console.error('wrote native host manifest (both locations)');

    // open a blank target, attach, enable Runtime/Page to capture console, then navigate
    const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
    await send('Runtime.enable', {}, sessionId);
    await send('Page.enable', {}, sessionId);
    await send('Page.navigate', { url: `chrome-extension://${extId}/auto.html` }, sessionId);
    console.error('opened auto.html — running test, polling result…');

    for (let i = 0; i < 40; i++) { if (fs.existsSync(RESULT)) break; await sleep(1000); }
    if (fs.existsSync(RESULT)) { console.error('RESULT_READY'); process.stdout.write(fs.readFileSync(RESULT)); }
    else console.error('NO_RESULT');
  } catch (e) {
    console.error('ERROR:', e.message);
  } finally {
    try { chrome.kill('SIGTERM'); } catch {}
    try { fs.unlinkSync(path.join(os.homedir(), 'Library/Application Support/Google/Chrome/NativeMessagingHosts/com.beamhop.bridge.json')); } catch {}
    setTimeout(() => process.exit(0), 500);
  }
})();
