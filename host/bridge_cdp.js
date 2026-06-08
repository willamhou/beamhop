// Loads the Beamhop extension into an isolated Chrome (CDP pipe — Chrome 137+ removed
// --load-extension) and opens a real page so capture_active_tab has content. Keeps Chrome alive
// long enough for the --bridge-test harness (separate process) to ping + capture, then exits.
const { spawn } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');

const EXTDIR = path.join(__dirname, '..', 'extension');
const HOSTBIN = process.argv[2] || path.join(__dirname, 'beamhop-bridge');
const EXTID = process.argv[3];   // precomputed (path-hash); same id CDP will assign
const PROFILE = '/tmp/beamhop_bridge_profile';
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

fs.rmSync(PROFILE, { recursive: true, force: true });

// Write the native-messaging host manifest BEFORE launching, to both the default location and
// the profile dir (custom --user-data-dir reads from the profile — S4). Using the precomputed
// ext id means the SW's first connect() (single load) finds the manifest → one clean host.
if (EXTID) {
  const manifest = JSON.stringify({
    name: 'com.beamhop.bridge', description: 'Beamhop bridge host',
    path: HOSTBIN, type: 'stdio', allowed_origins: [`chrome-extension://${EXTID}/`],
  }, null, 2);
  for (const dir of [
    path.join(os.homedir(), 'Library/Application Support/Google/Chrome/NativeMessagingHosts'),
    path.join(PROFILE, 'NativeMessagingHosts'),
  ]) {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'com.beamhop.bridge.json'), manifest);
  }
}

const chrome = spawn(CHROME, [
  `--user-data-dir=${PROFILE}`,
  '--no-first-run', '--no-default-browser-check',
  '--enable-unsafe-extension-debugging', '--remote-debugging-pipe',
  'about:blank',
], { stdio: ['ignore', 'ignore', 'inherit', 'pipe', 'pipe'] });

const wp = chrome.stdio[3], rp = chrome.stdio[4];
let nextId = 1; const pending = new Map();
function send(method, params = {}) {
  const id = nextId++;
  wp.write(JSON.stringify({ id, method, params }) + '\0');
  return new Promise((res, rej) => pending.set(id, { res, rej }));
}
let buf = Buffer.alloc(0);
rp.on('data', (c) => {
  buf = Buffer.concat([buf, c]); let i;
  while ((i = buf.indexOf(0)) !== -1) {
    const m = buf.slice(0, i).toString('utf8'); buf = buf.slice(i + 1);
    if (!m) continue; let o; try { o = JSON.parse(m); } catch { continue; }
    if (o.id && pending.has(o.id)) { const { res, rej } = pending.get(o.id); pending.delete(o.id); o.error ? rej(new Error(JSON.stringify(o.error))) : res(o.result); }
  }
});
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

(async () => {
  try {
    await sleep(1500);
    const { id: extId } = await send('Extensions.loadUnpacked', { path: EXTDIR });
    console.error('loaded extension', extId, EXTID && extId !== EXTID ? '(WARN: != precomputed)' : '');
    // open a real page so capture_active_tab has content
    await send('Target.createTarget', { url: 'https://example.com' });
    console.error('opened example.com; holding Chrome for harness…');
    await sleep(14000);
  } catch (e) { console.error('CDP error', e.message); }
  finally { try { chrome.kill('SIGTERM'); } catch {} setTimeout(() => process.exit(0), 300); }
})();
