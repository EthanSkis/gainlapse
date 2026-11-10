#!/usr/bin/env node
// Gainlapse slideshow maker.
// Turns a slideshow file (JSON) into branded slide images for TikTok or Instagram.
//
//   node make.js examples/progress-pic.json
//   node make.js examples/*.json
//
// Output goes to out/<file name>/ as slide-01.jpg, slide-02.jpg, ... plus a .zip.

const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const SIZES = { tiktok: [1080, 1920], instagram: [1080, 1350] };
const ROOT = path.resolve(__dirname, '..', '..');
const LOGO = path.join(ROOT, 'Gainlapse/Assets.xcassets/AppIcon.appiconset/icon.png');

const esc = (s = '') => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
// [[words]] become the orange accent; blank lines split paragraphs; single newlines become line breaks.
const rich = (s = '') => esc(s).replace(/\[\[(.+?)\]\]/g, '<em>$1</em>').replace(/\n/g, '<br>');
const paras = (s = '') => String(s).split(/\n\s*\n/).map((p) => `<p>${rich(p.trim())}</p>`).join('');

function src(value, baseDir) {
  if (!value) return '';
  if (/^https?:\/\//.test(value)) return value;
  const p = path.isAbsolute(value) ? value : path.resolve(baseDir, value);
  if (!fs.existsSync(p)) throw new Error(`Image not found: ${p}`);
  return pathToFileURL(p).href;
}

function slideHtml(slide, i, total, show, baseDir) {
  const brand = esc(show.brand || 'GAINLAPSE');
  switch (slide.type) {
    case 'cover':
      return `<section class="slide cover">
        ${slide.photo ? `<img class="bg" src="${src(slide.photo, baseDir)}" style="object-position:50% ${slide.focus ?? 35}%">` : ''}
        <div class="fade"></div>
        <div class="stack end">
          <div class="stamp accent">${brand}</div>
          <h1 class="fit" style="--max:${slide.size || 170}px">${rich(slide.headline)}</h1>
          ${slide.sub ? `<div class="sub">${rich(slide.sub)}</div>` : ''}
        </div></section>`;
    case 'tip':
      return `<section class="slide glow">
        <div class="stack top">
          <div class="num">${rich(slide.number || String(i).padStart(2, '0'))}</div>
          <h2 class="fit" style="--max:${slide.size || 130}px">${rich(slide.heading)}</h2>
          <div class="body">${paras(slide.body)}</div>
          <div class="footer stamp accent">${brand}</div>
        </div></section>`;
    case 'statement':
      return `<section class="slide statement ${slide.background === 'dark' ? 'glow' : 'orange'}">
        <div class="stack center">
          ${slide.stamp ? `<div class="stamp">${rich(slide.stamp)}</div>` : ''}
          <h1 class="fit" style="--max:${slide.size || 260}px">${rich(slide.headline)}</h1>
          ${slide.sub ? `<div class="sub strong">${rich(slide.sub)}</div>` : ''}
        </div></section>`;
    case 'app':
      return `<section class="slide glow">
        <div class="stack app">
          <h2 class="fit center-text" style="--max:${slide.size || 120}px">${rich(slide.heading)}</h2>
          ${slide.body ? `<div class="sub center-text">${rich(slide.body)}</div>` : ''}
          <div class="phone"><img src="${src(slide.screenshot, baseDir)}"></div>
        </div></section>`;
    case 'cta':
      return `<section class="slide glow strong-glow">
        <div class="stack center middle">
          <img class="logo" src="${src(slide.logo || LOGO, baseDir)}">
          <h1 class="fit center-text" style="--max:${slide.size || 150}px">${rich(slide.headline || 'Search [[Gainlapse]] on the App Store')}</h1>
          ${slide.body ? `<div class="sub center-text">${rich(slide.body)}</div>` : ''}
          ${slide.pill ? `<div class="pill">${rich(slide.pill)}</div>` : ''}
        </div></section>`;
    default:
      throw new Error(`Slide ${i}: unknown type "${slide.type}" (use cover, tip, statement, app or cta)`);
  }
}

function pageHtml(slideMarkup, w, h) {
  const s = w / 1080; // every size below is designed at 1080 wide
  return `<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Anton&family=Courier+Prime:wght@700&family=Inter:wght@500;600;700&display=swap" rel="stylesheet">
<style>
:root{--bg:#0e0c0b;--accent:#ff5a1f;--ink:#fff;--muted:rgba(255,255,255,.72)}
*{box-sizing:border-box;margin:0}
body{background:#000}
.slide{width:${w}px;height:${h}px;position:relative;overflow:hidden;background:var(--bg);color:var(--ink);font-family:Inter,-apple-system,system-ui,sans-serif}
.glow{background:radial-gradient(${1300 * s}px ${1000 * s}px at 50% 0%,rgba(255,90,31,.24),rgba(255,90,31,0) 70%),var(--bg)}
.strong-glow{background:radial-gradient(${1300 * s}px ${1100 * s}px at 50% 0%,rgba(255,90,31,.34),rgba(255,90,31,0) 72%),var(--bg)}
.orange{background:linear-gradient(150deg,#ff7329,#ff5a1f 45%,#ed450f);color:var(--bg)}
.bg{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;filter:saturate(.85) contrast(1.05)}
.fade{position:absolute;inset:0;background:linear-gradient(180deg,rgba(14,12,11,0) 0%,rgba(14,12,11,.15) 38%,rgba(14,12,11,.92) 62%,var(--bg) 100%)}
.stack{position:absolute;inset:0;padding:${h * 0.08}px ${96 * s}px ${h * 0.08}px;display:flex;flex-direction:column;gap:${28 * s}px}
.stack.end{justify-content:flex-end;padding-bottom:${h * 0.1}px}
.stack.top{padding-top:${h * 0.15}px}
.stack.center{justify-content:center}
.stack.middle{align-items:center}
.stack.app{padding-top:${h * 0.06}px;align-items:center}
h1,h2,.num{font-family:Anton,Impact,sans-serif;font-weight:400;text-transform:uppercase;line-height:1;letter-spacing:-.005em}
h1,h2{font-size:calc(var(--max) * ${s});flex:none}
.cover h1{--maxh:${h * 0.42}px}
.statement h1{--maxh:${h * 0.45}px}
.stack.top h2{--maxh:${h * 0.24}px}
.stack.app h2{--maxh:${h * 0.16}px}
.stack.middle h1{--maxh:${h * 0.3}px}
em{font-style:normal;color:var(--accent)}
.orange em{color:#fff}
.num{font-size:${(h > 1500 ? 240 : 200) * s}px;color:var(--accent);margin-bottom:${-4 * s}px}
.stamp{font-family:"Courier Prime",ui-monospace,monospace;font-weight:700;letter-spacing:.16em;text-transform:uppercase;font-size:${30 * s}px}
.accent{color:var(--accent)}
.sub{font-size:${46 * s}px;line-height:1.3;font-weight:600;color:var(--muted)}
.sub.strong{color:inherit;font-weight:700;font-size:${52 * s}px}
.center-text{text-align:center}
.body{display:flex;flex-direction:column;gap:${36 * s}px;font-size:${46 * s}px;line-height:1.4;font-weight:500;color:var(--muted)}
.footer{margin-top:auto}
.phone{flex:1 1 0;min-height:0;aspect-ratio:1206/2622;max-width:${600 * s}px;margin-top:${12 * s}px;background:#000;border-radius:${76 * s}px;padding:${12 * s}px;box-shadow:inset 0 0 0 ${3 * s}px rgba(255,255,255,.15),0 ${40 * s}px ${120 * s}px rgba(255,90,31,.22)}
.phone img{width:100%;height:100%;object-fit:cover;object-position:top;border-radius:${64 * s}px;display:block}
.logo{width:${240 * s}px;height:${240 * s}px;border-radius:${56 * s}px;object-fit:cover}
.pill{font-family:"Courier Prime",ui-monospace,monospace;font-weight:700;letter-spacing:.12em;text-transform:uppercase;font-size:${32 * s}px;background:var(--accent);color:var(--bg);padding:${20 * s}px ${40 * s}px;border-radius:999px;margin-top:${24 * s}px;text-align:center}
</style></head><body>${slideMarkup}</body></html>`;
}

// Shrinks every headline until it fits its box, so long text can never spill onto other text.
async function fitText(page) {
  await page.evaluate(() => {
    for (const el of document.querySelectorAll('.fit')) {
      const maxh = parseFloat(getComputedStyle(el).getPropertyValue('--maxh')) || Infinity;
      let size = parseFloat(getComputedStyle(el).fontSize);
      while ((el.offsetHeight > maxh || el.scrollWidth > el.clientWidth + 4) && size > 24) {
        size -= 2;
        el.style.fontSize = size + 'px';
      }
    }
  });
}

async function make(file, browser) {
  const show = JSON.parse(fs.readFileSync(file, 'utf8'));
  const format = show.format || 'tiktok';
  if (!SIZES[format]) throw new Error(`${file}: format must be "tiktok" or "instagram"`);
  if (!Array.isArray(show.slides) || !show.slides.length) throw new Error(`${file}: needs a "slides" list`);
  const [w, h] = SIZES[format];
  const baseDir = path.dirname(path.resolve(file));
  const name = path.basename(file, '.json') + (format === 'instagram' ? '-instagram' : '');
  const outDir = path.join(__dirname, 'out', name);
  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });

  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  const files = [];
  for (const [n, slide] of show.slides.entries()) {
    const html = pageHtml(slideHtml(slide, n, show.slides.length, show, baseDir), w, h);
    const tmp = path.join(outDir, `.slide-${n + 1}.html`);
    fs.writeFileSync(tmp, html);
    await page.goto(pathToFileURL(tmp).href, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    await fitText(page);
    const out = path.join(outDir, `slide-${String(n + 1).padStart(2, '0')}.jpg`);
    await page.screenshot({ path: out, type: 'jpeg', quality: 92 });
    fs.unlinkSync(tmp);
    files.push(path.basename(out));
  }
  await page.close();

  if (show.caption) fs.writeFileSync(path.join(outDir, 'caption.txt'), show.caption + '\n');
  try {
    execFileSync('zip', ['-q', '-j', path.join(__dirname, 'out', `${name}.zip`), ...files.map((f) => path.join(outDir, f))]);
  } catch {
    console.warn('  (zip not found, skipped the .zip; the images are in the folder)');
  }
  console.log(`✓ ${name}: ${files.length} slides → out/${name}/`);
}

(async () => {
  const files = process.argv.slice(2);
  if (!files.length) {
    console.log('Usage: node make.js <slideshow.json> [more.json ...]\nExample: node make.js examples/progress-pic.json');
    process.exit(1);
  }
  const browser = await chromium.launch();
  try {
    for (const f of files) await make(f, browser);
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error('✗ ' + e.message);
  process.exit(1);
});
