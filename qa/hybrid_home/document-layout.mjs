import assert from 'node:assert/strict';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { chromium } from 'playwright';

const out = path.resolve(process.argv[2]);
const assets = path.resolve(process.argv[3] ?? 'flutter_app/android/app/src/main/assets/hybrid_home');
const captureOnly = process.argv.includes('--capture-only');
const browser = await chromium.launch({ executablePath: process.env.CHROME_BIN });
const results = [];
fs.mkdirSync(out, { recursive: true });

try {
  for (const width of [320, 393, 427]) {
    for (const fontScale of [1, 1.3]) {
      const context = await browser.newContext({ viewport: { width, height: 852 }, isMobile: true, hasTouch: true, locale: 'ar', offline: true });
      try {
        const page = await context.newPage();
        await page.route('https://nasqo.test/**', route => {
          const name = new URL(route.request().url()).pathname.slice(1);
          const file = name === 'logo.png' ? 'flutter_app/assets/nasqo_logo.png' : path.join(assets, name);
          return fs.existsSync(file) ? route.fulfill({ path: file }) : route.abort();
        });
        await page.addInitScript(() => {
          window.events = [];
          window.NasqoHome = { postMessage: raw => window.events.push(JSON.parse(raw)) };
        });
        await page.goto('https://nasqo.test/index.html');
        await page.evaluate(scale => {
          document.documentElement.style.fontSize = `${scale * 100}%`;
          window.nasqoPresent({ screen: 'document', company: 'مختبر المطابقة', generatedAt: '2026-11-21T09:30:00',
            entry: { id: 'invoice', entryNumber: 9041, documentNumber: 'QA-41', accountName: 'مورد الاختبار',
              entryDate: '2026-11-21', typeLabel: 'فاتورة اختبار', amount: 25.5, currency: 'دولار' },
            lines: [{ id: 0, itemName: 'خيط تجريبي', unit: 'حبة', price: 8.5, quantity: 3, total: 25.5 }] });
        }, fontScale);
        await page.getByRole('table', { name: 'بنود المستند' }).waitFor();
        await page.evaluate(() => document.fonts.ready);
        const back = page.getByRole('button', { name: 'رجوع', exact: true });
        const toolbar = page.getByRole('group', { name: 'تكبير الفاتورة وتنزيل PDF' });
        const preview = page.locator('.cash-invoice-scroll');
        const measure = () => toolbar.getByRole('button').evaluateAll(buttons => buttons.map(button => {
          const { left, top, width, height, right, bottom } = button.getBoundingClientRect();
          const receivesTouch = [0.1, 0.5, 0.9].every(x => [0.1, 0.5, 0.9].every(y =>
            button.contains(document.elementFromPoint(left + width * x, top + height * y))));
          return { name: button.getAttribute('aria-label') ?? button.textContent.trim(), left, top, width, height, right, bottom, receivesTouch };
        }));
        const bounds = await measure();
        await page.screenshot({ path: path.join(out, `document-${width}-font-${fontScale}.png`) });
        if (!captureOnly) {
          assert.equal(await toolbar.evaluate(el => getComputedStyle(el).direction), 'rtl');
          assert.equal(bounds.length, 7);
          const header = await page.locator('.hybrid-document > .flow-fixed-header').boundingBox();
          const toolbarBox = await toolbar.boundingBox();
          const previewBox = await preview.boundingBox();
          assert.ok(toolbarBox.y >= header.y + header.height - 1);
          assert.ok(previewBox.y >= toolbarBox.y + toolbarBox.height - 1 && previewBox.height >= 200);
          for (const box of bounds) {
            assert.ok(box.width >= 48 && box.height >= 48 && box.left >= 0 && box.right <= width + 1 &&
              box.top >= toolbarBox.y && box.bottom <= previewBox.y && box.receivesTouch, JSON.stringify(box));
          }
          const zoom = page.getByTestId('cash-invoice-zoom-value');
          const readZoom = async () => parseInt(await zoom.innerText(), 10);
          const fit = await readZoom();
          await page.getByTestId('cash-invoice-zoom-in').tap();
          assert.ok(await readZoom() > fit);
          await page.getByTestId('cash-invoice-zoom-out').tap();
          assert.equal(await readZoom(), fit);
          await page.getByTestId('cash-invoice-actual-size').tap();
          assert.equal(await readZoom(), 100);
          const pan = page.getByTestId('cash-invoice-pan');
          const position = () => pan.evaluate(el => el.scrollLeft);
          const before = await position();
          await page.getByRole('button', { name: 'تحريك الفاتورة إلى اليسار' }).tap();
          await pan.evaluate((el, start) => new Promise((resolve, reject) => {
            const timer = setTimeout(() => reject(Error('Document did not scroll')), 1600);
            const check = () => {
              if (el.scrollLeft === start) requestAnimationFrame(check);
              else { clearTimeout(timer); resolve(); }
            };
            check();
          }), before);
          await page.getByTestId('cash-invoice-reset').tap();
          assert.equal(await readZoom(), fit);
          await page.getByRole('button', { name: 'طباعة الفاتورة' }).tap();
          await page.getByRole('button', { name: 'حفظ المستند PDF عبر Android' }).tap();
          if (width === 393 && fontScale === 1.3) {
            for (const format of ['Letter', 'A4']) {
              const pdf = path.join(out, `browser-print-${format}.pdf`);
              await page.pdf({ path: pdf, format });
              const content = execFileSync('pdftotext', ['-layout', pdf, '-'], {encoding: 'utf8'})
                .replace(/\p{Cf}/gu, '');
              for (const field of ['QA-41', '9041', 'خيط', 'تجريبي', '8.5', '25.5']) {
                assert.ok(content.includes(field), `Missing printable field ${field} on ${format}`);
              }
            }
          }
          await back.tap();
          assert.deepEqual(await page.evaluate(() => window.events.filter(e => ['documentOutput', 'documentClose'].includes(e.action))),
            [{ action: 'documentOutput', op: 'print' }, { action: 'documentOutput', op: 'pdf' }, { action: 'documentClose' }]);
        }
        results.push({ width, fontScale, bounds });
      } finally {
        await context.close();
      }
    }
  }
} finally {
  await browser.close();
  fs.writeFileSync(path.join(out, 'layout-results.json'), JSON.stringify(results, null, 2));
}
console.log(`${captureOnly ? 'Captured' : 'Passed'} ${results.length} RTL document layouts`);
