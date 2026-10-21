// Run with Playwright installed; optionally set PLAYWRIGHT_MODULE and CHROMIUM_EXECUTABLE.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '..');
const screenshots = process.env.SCREENSHOT_DIR;

(async () => {
  const browser = await chromium.launch({
    headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {})
  });
  try {
    for (const lang of ['zh', 'en']) {
      const context = await browser.newContext({ viewport: { width: 1000, height: 1100 } });
      const page = await context.newPage(), errors = [];
      page.on('pageerror', error => errors.push(error.message));
      const url = pathToFileURL(path.join(root, lang === 'zh' ? 'quiet-panel.html' : 'quiet-panel.en.html')).href;
      const act = name => page.locator('[data-action="' + name + '"]');
      await page.goto(url);
      await page.locator('#bh-instruction').waitFor();
      if (screenshots) await page.locator('#beamhop-inline').screenshot({ path: path.join(screenshots, lang + '-default.png') });
      const original = await page.locator('#bh-items textarea').inputValue();
      // A pasted image and a dropped file remain actual typed materials.
      await page.locator('#bh-instruction').evaluate(el => {
        const data = new DataTransfer();
        data.items.add(new File([new Uint8Array([137,80,78,71])], 'pasted.png', { type: 'image/png' }));
        el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
      });
      assert.equal(await page.locator('.bh-image-button').count(), 1);
      await act('preview').click();
      assert.equal(await page.locator('.bh-image-preview').isVisible(), true);
      await page.locator('#bh-items [data-id]').filter({ hasText: 'pasted.png' }).locator('[data-action="remove"]').click();
      await page.locator('.bh-window').evaluate(el => {
        const data = new DataTransfer();
        data.items.add(new File(['literal file body'], 'dropped.txt', { type: 'text/plain' }));
        el.dispatchEvent(new DragEvent('drop', { dataTransfer: data, bubbles: true, cancelable: true }));
      });
      assert.equal(await page.locator('#bh-count').textContent(), '2');
      await page.locator('#bh-items [data-id]').filter({ hasText: 'dropped.txt' }).locator('[data-action="remove"]').click();
      const prompt = '/review 保留原文 <>&';
      await page.locator('#bh-items textarea').fill('Changed <literal> & original stays local');
      await page.locator('#bh-additions textarea').last().fill('Another independent material');
      await page.locator('#bh-instruction').fill(prompt);
      await act('original').click();
      assert.equal(await page.locator('.bh-original p').textContent(), original);
      await act('original').click();
      assert.equal(await page.locator('#bh-command-help').isVisible(), true);
      await act('hop').click();
      assert.match(await page.locator('#bh-result-title').textContent(), lang === 'zh' ? /准备草稿/ : /Draft prepared/);
      await act('inspect-packet').click();
      const packet = await page.locator('#bh-packet').textContent();
      assert.ok(packet.includes(prompt) && packet.includes('<literal>') && !packet.includes(original));
      await act('return-edit').click();
      assert.equal(await page.locator('#bh-instruction').inputValue(), prompt);
      await act('destination').click();
      await act('new-project').click();
      await page.locator('#bh-project-name').fill('Project <>&');
      await page.locator('#bh-agent-select').selectOption('Claude');
      await page.locator('#bh-session-name').fill('New session <>&');
      assert.equal(await act('hop').isDisabled(), true);
      await act('confirm-create').click();
      assert.equal(await page.locator('#bh-instruction').inputValue(), prompt);
      assert.equal(await page.locator('#bh-route-project').textContent(), 'Project <>&');
      await act('hold').click();
      assert.equal(await page.locator('#bh-pocket-count').textContent(), '1');
      assert.equal(await page.locator('.bh-window').isVisible(), false);
      await act('capture').click();
      await page.locator('#bh-additions textarea').last().fill('Unsaved material with no instruction');
      await act('destination').click();
      await page.locator('[data-route="local-b"]').click();
      await act('pocket').click();
      await act('restore-batch').click();
      assert.equal(await page.locator('#bh-instruction').inputValue(), prompt);
      assert.equal(await page.locator('#bh-pocket-count').textContent(), '1');
      await act('pocket').click();
      await act('add-batch-materials').click();
      assert.equal(await page.locator('#bh-count').textContent(), '3');
      assert.equal(await page.locator('#bh-instruction').inputValue(), prompt);
      assert.equal(await page.locator('#bh-route-project').textContent(), 'Project <>&');
      await act('destination').click();
      await page.locator('[data-route="local-b"]').click();
      await page.locator('#bh-files').setInputFiles([{ name: 'report.pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF-test') }]);
      assert.equal(await act('hop').isDisabled(), true);
      assert.ok((await page.locator('#bh-warning').textContent()).includes('report.pdf'));
      await page.locator('#bh-items [data-id]').filter({ hasText: 'report.pdf' }).locator('[data-action="remove"]').click();
      assert.equal(await act('hop').isDisabled(), true); // slash command isn't background-dispatched
      assert.equal(await act('native-edit').isDisabled(), false);
      await page.locator('#bh-instruction').fill('Review these materials');
      await act('hop').click();
      assert.equal(await page.locator('.bh-window').isVisible(), false);
      await act('last-record').click();
      assert.match(await page.locator('#bh-result-description').textContent(), lang === 'zh' ? /不代表任务已完成/ : /does not mean the task is complete/);
      await act('new').click();
      await page.locator('#bh-instruction').fill('New work must not be overwritten');
      await act('pocket').click();
      const history = page.locator('[data-record]').filter({ hasText: 'Codex' }).first();
      await history.locator('[data-action="view-record"]').click();
      assert.equal(await page.locator('#bh-instruction').inputValue(), 'New work must not be overwritten');
      await history.locator('[data-action="recover-record"]').click();
      assert.equal(await page.locator('#bh-instruction').inputValue(), prompt);
      await act('pocket').click();
      assert.ok((await page.locator('#bh-pocket-panel').textContent()).includes('New work must not be overwritten'));
      if (screenshots) await page.locator('#beamhop-inline').screenshot({ path: path.join(screenshots, lang + '-pocket.png') });
      await act('close-pocket').click();
      await page.setViewportSize({ width: 320, height: 1100 });
      await page.emulateMedia({ colorScheme: 'dark' });
      await act('destination').click();
      await act('new-session').click();
      if (screenshots) await page.locator('#beamhop-inline').screenshot({ path: path.join(screenshots, lang + '-narrow-create.png') });
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), true);
      await act('cancel-create').click();
      await page.setViewportSize({ width: 1000, height: 1100 });
      await page.locator('#receiver-unavailable').check();
      await page.locator('#bh-files').setInputFiles([{ name: 'report.pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF-test') }]);
      await act('hop').click();
      assert.match(await page.locator('#bh-result-title').textContent(), lang === 'zh' ? /未能打开/ : /Could not open/);
      await page.evaluate(() => Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async text => { window.copied = text; } } }));
      await act('copy-text').click();
      assert.ok((await page.evaluate(() => window.copied)).includes('report.pdf'));
      assert.match(await page.locator('#bh-feedback').textContent(), lang === 'zh' ? /附件尚未带入/ : /Attachments have not been transferred/);
      await page.evaluate(() => Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async () => { throw Error('denied'); } } }));
      await act('copy-text').click();
      assert.match(await page.locator('#bh-feedback').textContent(), lang === 'zh' ? /未能写入剪贴板/ : /Could not write to the clipboard/);
      await act('return-edit').click();
      await page.reload();
      assert.equal(await page.locator('#bh-instruction').inputValue(), prompt);
      assert.equal(await act('hop').isDisabled(), true);
      assert.match(await page.locator('#bh-warning').textContent(), lang === 'zh' ? /附件已失效/ : /no longer available/);
      assert.deepEqual(errors, []);
      for (const file of ['quiet-panel.html', 'quiet-panel.en.html']) {
        const html = fs.readFileSync(path.join(root, file), 'utf8');
        for (const [, href] of html.matchAll(/(?:src|href)="(\.\/[^"#]+)(?:#[^"]*)?"/g)) {
          assert.ok(fs.existsSync(path.resolve(root, href)), href);
        }
      }
      console.log(lang + ': inline edits, literal prompt, creation, Pocket, history, attachments, recovery and narrow layout passed');
      await context.close();
    }
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
