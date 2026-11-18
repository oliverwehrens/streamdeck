// Browser checks for the web editor against a running streamdeckd with no deck attached.
// Run with ./scripts/test-web-e2e.sh, which starts the daemon and this script in Docker.
// Environment: BASE (daemon URL), TOKEN (a dev token, see scripts/dev-web-token.sh), BROWSER (chromium or firefox).
// The daemon's config directory is mounted at /cfg, screenshots go to /out.
import { chromium, firefox } from 'playwright';
import { readFileSync, writeFileSync, renameSync } from 'node:fs';
const writeConfig = (text) => { writeFileSync('/cfg/.tmp.yaml', text); renameSync('/cfg/.tmp.yaml', '/cfg/config.yaml'); };

const BASE = process.env.BASE ?? 'http://sdd:3325';
const TOKEN = process.env.TOKEN;
const OUT = '/out';
const results = [];
const ok = (name, pass, detail = '') => {
  results.push({ name, pass, detail });
  console.log(`${pass ? 'PASS' : 'FAIL'} ${name}${detail ? ` — ${detail}` : ''}`);
};

async function state(page) {
  return page.evaluate(async () => (await fetch('/api/state')).json());
}
const keyOf = (s, pageName, index) => s.draft.pages.find((p) => p.name === pageName)?.keys?.[String(index)];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function run(browserType, label) {
  const browser = await browserType.launch();
  const host = new URL(BASE).hostname;
  const consoleErrors = [];
  const watch = (page) => {
    page.on('console', (m) => { if (m.type() === 'error' && !m.text().startsWith('Failed to load resource')) consoleErrors.push(m.text()); });
    page.on('pageerror', (e) => consoleErrors.push(String(e)));
  };

  // Unpaired browser sees only pairing.
  const anon = await browser.newContext();
  const anonPage = await anon.newPage();
  watch(anonPage);
  await anonPage.goto(BASE);
  await anonPage.waitForSelector('#pairing:not([hidden])');
  ok(`${label}: unpaired shows pairing`, await anonPage.isHidden('#editor'));
  await anonPage.click('#pair-start');
  await anonPage.waitForFunction(() => document.getElementById('pair-message').textContent.length > 0);
  ok(`${label}: pairing without deck explains`, (await anonPage.textContent('#pair-message')).includes('Connect the deck'));
  ok(`${label}: guessed browser name`, (await anonPage.inputValue('#pair-name')).length > 0, await anonPage.inputValue('#pair-name'));
  await anon.close();

  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  await context.addCookies([{ name: 'streamdeck_token', value: TOKEN, domain: host, path: '/', httpOnly: true, sameSite: 'Strict' }]);
  const page = await context.newPage();
  watch(page);
  await page.goto(BASE);
  await page.waitForSelector('#editor:not([hidden])');
  await page.waitForFunction(() => [...document.querySelectorAll('.key img')].every((img) => img.src.startsWith('data:image/jpeg')));
  ok(`${label}: grid shows 15 deck images`, (await page.$$('.key img')).length === 15);
  const pagesListed = await page.$$eval('#page-list li', (items) => items.map((i) => i.textContent));
  ok(`${label}: page list`, pagesListed.length >= 2, pagesListed.join(', '));
  await page.screenshot({ path: `${OUT}/${label}-desktop.png`, fullPage: true });

  // Edit a label; debounced, then in the draft, file unchanged.
  await page.click('.key[data-index="0"]');
  const labelInput = page.getByLabel('Label', { exact: true });
  await labelInput.fill('Term');
  await sleep(800);
  let s = await state(page);
  ok(`${label}: label edit reaches the draft`, keyOf(s, s.draft.defaultPage, 0)?.label === 'Term');
  ok(`${label}: unsaved marker`, await page.isVisible('#dirty'));
  const img0 = await page.getAttribute('.key[data-index="0"] img', 'src');
  ok(`${label}: grid image follows the draft`, img0 !== null && img0.length > 100);

  // Second tab sees the edit.
  const page2 = await context.newPage();
  watch(page2);
  await page2.goto(BASE);
  await page2.waitForSelector('#editor:not([hidden])');
  await page2.click('.key[data-index="0"]');
  ok(`${label}: other tab shows the edit`, (await page2.getByLabel('Label', { exact: true }).inputValue()) === 'Term');
  await page.getByLabel('Label', { exact: true }).fill('Term2');
  await sleep(1200);
  ok(`${label}: other tab updates live`, (await page2.getByLabel('Label', { exact: true }).inputValue()) === 'Term2');
  await page2.close();

  // Reload keeps the unsaved draft.
  page.once('dialog', (d) => d.accept());
  await page.reload();
  await page.waitForSelector('#editor:not([hidden])');
  s = await state(page);
  ok(`${label}: reload keeps the draft`, keyOf(s, s.draft.defaultPage, 0)?.label === 'Term2' && s.isDirty);

  // Validation: an invalid combination marks the key and disables Save.
  await page.click('.key[data-index="0"]');
  await page.locator('#inspector label:has-text("Action") > select').selectOption('keys');
  await page.waitForSelector('text=Edit as text');
  await page.click('text=Edit as text');
  await page.locator('#inspector input.mono[placeholder="ctrl+shift+m"]').fill('cmd+');
  await sleep(800);
  ok(`${label}: invalid key marked`, await page.locator('.key[data-index="0"]').evaluate((e) => e.classList.contains('invalid')));
  ok(`${label}: save disabled with errors`, await page.isDisabled('#save'));
  ok(`${label}: inspector shows the error`, (await page.locator('#inspector .errors').count()) > 0);
  await page.click('text=Done');

  // Record a keystroke.
  await page.click('.recorder');
  await page.keyboard.press('Control+Shift+KeyM');
  await sleep(600);
  s = await state(page);
  ok(`${label}: recorded ctrl+shift+m`, keyOf(s, s.draft.defaultPage, 0)?.action?.value === 'ctrl+shift+m', JSON.stringify(keyOf(s, s.draft.defaultPage, 0)?.action));
  await page.click('.recorder');
  await page.keyboard.press('Escape');
  await sleep(400);
  s = await state(page);
  ok(`${label}: Esc keeps the value`, keyOf(s, s.draft.defaultPage, 0)?.action?.value === 'ctrl+shift+m');
  await page.click('.recorder');
  await page.keyboard.press('Control+KeyS');
  await sleep(600);
  s = await state(page);
  ok(`${label}: Ctrl-S is recorded, not saved`, keyOf(s, s.draft.defaultPage, 0)?.action?.value === 'ctrl+s' && s.isDirty);

  // Material Symbols picker.
  await page.locator('#inspector label:has-text("Icon") > select').selectOption('material');
  await page.click('text=Browse…');
  await page.waitForSelector('#picker[open]');
  await page.fill('#picker input[type=search]', 'home');
  await page.check('#picker input[type=checkbox]');
  await page.click('#picker button[title="home"]');
  await sleep(600);
  s = await state(page);
  ok(`${label}: picker sets ms:home.fill`, keyOf(s, s.draft.defaultPage, 0)?.icon === 'ms:home.fill', keyOf(s, s.draft.defaultPage, 0)?.icon);
  await page.getByLabel('Name', { exact: true }).fill('hoem');
  await sleep(800);
  ok(`${label}: unknown symbol marked`, (await page.textContent('#inspector')).includes('Unknown Material Symbol'));
  await page.getByLabel('Name', { exact: true }).fill('home');
  await sleep(600);

  // Pages: reserved name, add, delete referenced.
  page.once('dialog', () => {});
  await page.click('#add-page');
  await page.fill('#dialog input', 'back');
  await page.click('#dialog .primary');
  await page.waitForSelector('#dialog[open] >> text=reserved');
  ok(`${label}: reserved page name refused`, true);
  await page.click('#dialog .primary');

  // Save with the overwrite confirmation.
  await page.click('#save');
  await page.waitForSelector('#dialog[open] >> text=Replace the hand-edited config?');
  await page.click('#dialog .primary');
  await sleep(800);
  s = await state(page);
  ok(`${label}: saved`, !s.isDirty && !(await page.isVisible('#dirty')));

  // Settings and paired browsers.
  await page.click('#settings-button');
  await page.waitForSelector('text=Paired browsers');
  await page.waitForSelector('.clients li');
  ok(`${label}: paired browsers listed`, (await page.locator('.clients li').count()) >= 1);
  await page.screenshot({ path: `${OUT}/${label}-settings.png`, fullPage: true });

  // Delete a referenced page: refused with the reference.
  await page.click('#settings-button');
  await page.click('#page-list >> text=media');
  await page.click('#page-header >> text=Delete');
  await page.click('#dialog .primary');
  await page.waitForSelector('#dialog[open] >> text=still in use');
  ok(`${label}: referenced page delete names the reference`, (await page.textContent('#dialog')).includes("page 'home', key 4"));
  await page.click('#dialog .primary');

  // Another visible tab takes the deck; this one says so.
  const other = await context.newPage();
  await other.goto(BASE);
  await other.waitForSelector('#editor:not([hidden])');
  await other.click('#page-list >> text=home');
  await page.waitForSelector('#holder-note:not([hidden])', { timeout: 3000 }).catch(() => {});
  ok(`${label}: notice when another editor has the deck`, await page.isVisible('#holder-note'), await page.textContent('#holder-note'));
  await page.click('#holder-note button');
  await page.waitForSelector('#holder-note', { state: 'hidden', timeout: 3000 }).catch(() => {});
  ok(`${label}: taking the deck back`, await page.isHidden('#holder-note'));
  await other.close();

  // External changes: clean draft follows the file.
  await page.click('#page-list >> text=home');
  const saved = readFileSync('/cfg/config.yaml', 'utf8');
  writeConfig(saved.replace('label: Library', 'label: Games'));
  await page.waitForFunction(() => true);
  await sleep(1500);
  s = await state(page);
  ok(`${label}: clean draft follows the file`, keyOf(s, 'home', 1)?.label === 'Games' && !s.isDirty);

  // Dirty draft asks; keep the draft.
  await page.click('.key[data-index="2"]');
  await page.getByLabel('Label', { exact: true }).fill('Mine');
  await sleep(800);
  writeConfig(readFileSync('/cfg/config.yaml', 'utf8').replace('label: Games', 'label: Disk'));
  await page.waitForSelector('text=config.yaml changed on disk', { timeout: 3000 }).catch(() => {});
  ok(`${label}: dirty draft asks about the file`, await page.isVisible('text=config.yaml changed on disk'));
  await page.click('text=Keep my draft');
  await sleep(600);
  s = await state(page);
  ok(`${label}: keep my draft`, keyOf(s, 'home', 2)?.label === 'Mine' && s.isDirty && !s.pendingDisk);

  // Invalid file on disk: draft kept, errors shown.
  writeConfig('pages: [\n');
  await page.waitForSelector('text=The file on disk has errors', { timeout: 3000 }).catch(() => {});
  ok(`${label}: invalid file on disk shown`, await page.isVisible('text=The file on disk has errors'));
  s = await state(page);
  ok(`${label}: invalid file keeps the draft`, keyOf(s, 'home', 2)?.label === 'Mine');
  await page.screenshot({ path: `${OUT}/${label}-banners.png`, fullPage: true });

  // Mobile layout.
  const phone = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: browserType !== firefox, hasTouch: true });
  await phone.addCookies([{ name: 'streamdeck_token', value: TOKEN, domain: host, path: '/', httpOnly: true, sameSite: 'Strict' }]);
  const mobile = await phone.newPage();
  watch(mobile);
  await mobile.goto(BASE);
  await mobile.waitForSelector('#editor:not([hidden])');
  await mobile.click('.key[data-index="3"]');
  const width = await mobile.evaluate(() => document.documentElement.scrollWidth);
  ok(`${label}: phone has no sideways scroll`, width <= 390, `scrollWidth ${width}`);
  ok(`${label}: phone uses the page menu`, await mobile.isVisible('#page-select'));
  ok(`${label}: phone save button visible`, await mobile.isVisible('#save'));
  await mobile.screenshot({ path: `${OUT}/${label}-phone.png`, fullPage: true });
  await phone.close();

  ok(`${label}: no console errors`, consoleErrors.length === 0, consoleErrors.slice(0, 3).join(' | '));
  await browser.close();
}

const which = process.env.BROWSER ?? 'chromium';
await run(which === 'firefox' ? firefox : chromium, which);
const failed = results.filter((r) => !r.pass);
console.log(`\n${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
