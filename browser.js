// Kevin'in kendi tarayicisi (Playwright).
//
// Neden ayri bir tarayici: kullanicinin kendi penceresini surmek riskli
// (sekmeleri karisir, oturumu bozulur). Kevin kendi profilinde calisiyor,
// oturumlari kaliciyor ve PENCERE GORUNUR aciliyor - ne yaptigi canli izlenebiliyor.
//
// Platformdan bagimsiz: Playwright Windows, Linux ve macOS'ta ayni calisiyor.

let chromium = null;
try {
  ({ chromium } = require('playwright'));
} catch {
  chromium = null;
}

let context = null;
let page = null;

function available() {
  return Boolean(chromium);
}

async function ensurePage(profileDir) {
  if (!chromium) throw new Error('playwright kurulu degil');

  if (context && page && !page.isClosed()) return page;

  context = await chromium.launchPersistentContext(profileDir, {
    headless: false,
    viewport: { width: 1280, height: 800 },
    args: ['--no-first-run', '--no-default-browser-check'],
  });

  context.on('close', () => {
    context = null;
    page = null;
  });

  page = context.pages()[0] || (await context.newPage());
  return page;
}

async function goto(profileDir, url) {
  const target = /^https?:\/\//i.test(url) ? url : `https://${url}`;
  const p = await ensurePage(profileDir);
  await p.goto(target, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await p.waitForTimeout(700);
  return `acildi: ${p.url()} (baslik: ${await p.title()})`;
}

async function readPage(profileDir, maxChars = 3000) {
  const p = await ensurePage(profileDir);
  const text = await p.evaluate(() => {
    const drop = ['script', 'style', 'noscript', 'svg'];
    drop.forEach((tag) => document.querySelectorAll(tag).forEach((el) => el.remove()));
    return (document.body?.innerText || '').replace(/\n{3,}/g, '\n\n').trim();
  });
  const title = await p.title();
  const body = text.slice(0, maxChars);
  return `${p.url()}\nBaslik: ${title}\n\n${body}${text.length > maxChars ? '\n... (kisaltildi)' : ''}`;
}

// Gorunen metne gore tiklama: LLM'in CSS secici uydurmasindansa
// kullanicinin gordugu yaziyi kullanmasi daha guvenilir.
async function clickText(profileDir, text) {
  const p = await ensurePage(profileDir);
  const candidates = [
    p.getByRole('button', { name: text, exact: false }),
    p.getByRole('link', { name: text, exact: false }),
    p.getByText(text, { exact: false }),
  ];
  for (const locator of candidates) {
    const count = await locator.count().catch(() => 0);
    if (count > 0) {
      await locator.first().click({ timeout: 8000 });
      await p.waitForTimeout(900);
      return `tiklandi: "${text}" -> ${p.url()}`;
    }
  }
  return `"${text}" diye tiklanabilir bir sey bulamadim`;
}

async function typeText(profileDir, value, label) {
  const p = await ensurePage(profileDir);
  let target;
  if (label) {
    target = p.getByPlaceholder(label, { exact: false });
    if (!(await target.count().catch(() => 0))) {
      target = p.getByLabel(label, { exact: false });
    }
  }
  if (!target || !(await target.count().catch(() => 0))) {
    target = p.locator('input:visible, textarea:visible').first();
  }
  await target.first().fill(value, { timeout: 8000 });
  await p.keyboard.press('Enter');
  await p.waitForTimeout(1200);
  return `yazildi: "${value}" -> ${p.url()}`;
}

async function screenshot(profileDir, outPath) {
  const p = await ensurePage(profileDir);
  await p.screenshot({ path: outPath, fullPage: false });
  return outPath;
}

async function close() {
  if (context) {
    await context.close().catch(() => {});
    context = null;
    page = null;
  }
}

module.exports = { available, goto, readPage, clickText, typeText, screenshot, close };
