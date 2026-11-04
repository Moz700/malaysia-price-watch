// Run from dashboard/tests: npm install, then npm test (set CHROME_PATH to use a Chrome that is already installed).
//
// Browser checks for the web dashboard (dashboard/index.html):
// - serves the repo root with python3 -m http.server on port 8731, or on PORT if set (reuses one already running there)
// - at 1440x900, 1920x1080 and 390x844, in the light and the dark theme: scrolls the whole page so every
//   section and chart draws, and fails on any console error, page error, failed request, a chart that did
//   not draw, text contrast below 4.5:1, or a page wider than the screen (sideways scrolling)
// - checks the 6 KPI values, the "All states" shop-type index (q12), festive staples (q21), the state
//   basket costs (q09), 78 spike weeks in December 2025 and q23's 11 tested months, q12 state values,
//   the 30-shop rule for risers and fallers and the 8-week average start
// - drives every filter (state, shop type, item group, item search), a click on the map, a click on a
//   federal territory marker, a click on the heatmap, the three tools (where is it cheapest, compare
//   two states, price trends), the stakeholder tabs (also with the keyboard), the theme toggle, the PNG
//   buttons, reset and copy link, and reloads a shared URL to check the view comes back the same
// - opens dashboard/index.html through file:// and checks the same page and explorer work there
// - saves 7 screenshots (each under 500 KB) to dashboard/screenshots/

import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, statSync, unlinkSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import puppeteer from 'puppeteer';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');
const PORT = Number(process.env.PORT) || 8731;
const BASE = `http://127.0.0.1:${PORT}/dashboard/index.html`;
const FILE_URL = pathToFileURL(path.join(REPO, 'dashboard', 'index.html')).href;
const SHOTS = path.join(REPO, 'dashboard', 'screenshots');
const MAX_SHOT_BYTES = 500 * 1024;

const EXPECTED_KPIS = { 1: '9.9%', 2: '12.0%', 3: '99.95%', 4: '58%', 5: '12.1 points', 6: '78' };
const EXPECTED_SHOP_TYPES = { Hypermarket: '98.4', Supermarket: '101.4', 'Mini market': '103.4', 'Sundry shop': '106.8', 'Wet market': '108.2' };
const EXPECTED_FESTIVE = { 'Chinese New Year': '-2.42', 'Hari Raya Aidilfitri': '-4.98' };
const EXPECTED_BASKET = { 'W.P. Kuala Lumpur': '4,349.65', Kedah: '3,959.53' };
const VIEWPORTS = [
  { label: '1440x900', width: 1440, height: 900 },
  { label: '1920x1080', width: 1920, height: 1080 },
  { label: '390x844', width: 390, height: 844, isMobile: true, hasTouch: true, scale: 2 }
];

const results = [];
function record(ok, label) {
  results.push({ ok, label });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${label}`);
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function serverUp() {
  try { return (await fetch(BASE)).ok; } catch { return false; }
}
async function startServer() {
  if (await serverUp()) return null;
  const python = process.env.PYTHON || (process.platform === 'win32' ? 'python' : 'python3');
  const child = spawn(python, ['-m', 'http.server', String(PORT), '--bind', '127.0.0.1'], { cwd: REPO, stdio: 'ignore' });
  for (let i = 0; i < 50; i++) {
    if (await serverUp()) return child;
    await sleep(200);
  }
  child.kill();
  throw new Error(`python http.server did not start on port ${PORT}`);
}

function watchConsole(page, label, errors) {
  page.on('console', msg => { if (msg.type() === 'error') errors.push(`${label}: console error: ${msg.text()}`); });
  page.on('pageerror', err => errors.push(`${label}: page error: ${err.message}`));
  page.on('requestfailed', req => errors.push(`${label}: request failed: ${req.url()} ${req.failure()?.errorText}`));
  page.on('response', res => { if (res.status() >= 400) errors.push(`${label}: HTTP ${res.status()} for ${res.url()}`); });
}

async function openPage(browser, url, vp, theme, label, errors) {
  const page = await browser.newPage();
  watchConsole(page, label, errors);
  await page.setViewport({ width: vp.width, height: vp.height, deviceScaleFactor: vp.scale || 1, isMobile: !!vp.isMobile, hasTouch: !!vp.hasTouch });
  await page.emulateMediaFeatures([{ name: 'prefers-reduced-motion', value: 'reduce' }, { name: 'prefers-color-scheme', value: theme }]);
  await page.goto(url, { waitUntil: 'load' });
  // start from the system theme: forget a theme saved by an earlier run
  const saved = await page.evaluate(() => { try { const v = localStorage.getItem('mpw-theme'); localStorage.removeItem('mpw-theme'); return v; } catch (e) { return null; } });
  if (saved) await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('body[data-ready="true"]', { timeout: 15000 });
  return page;
}

// Page must never be wider than the screen.
async function checkWidth(page, label, quiet) {
  const screen = page.viewport().width;
  const w = await page.evaluate(() => ({ scroll: document.documentElement.scrollWidth, body: document.body.scrollWidth, inner: window.innerWidth }));
  const ok = w.scroll <= screen && w.body <= screen && w.inner <= screen;
  if (!ok || !quiet) record(ok, `${label}: no sideways scrolling (page ${w.scroll}px on a ${screen}px screen)`);
  return ok;
}

// Scroll the whole page in steps so every lazy section loads and every visible chart draws.
async function scrollAll(page) {
  let h = await page.evaluate(() => document.documentElement.scrollHeight);
  const step = Math.round(page.viewport().height * 0.7);
  for (let y = 0; y <= h; y += step) {
    await page.evaluate(v => window.scrollTo(0, v), y);
    await sleep(60);
    h = await page.evaluate(() => document.documentElement.scrollHeight);
  }
  await page.waitForSelector('body[data-explorer="ready"]', { timeout: 20000 });
  h = await page.evaluate(() => document.documentElement.scrollHeight);
  for (let y = 0; y <= h; y += step) {
    await page.evaluate(v => window.scrollTo(0, v), y);
    await sleep(60);
  }
  await sleep(200);
}

// Every chart that is on the page (not in a hidden tab) has drawn: a canvas, or an empty-data message.
async function checkCharts(page, label) {
  const ids = await page.$$eval('.chart', els => els.filter(e => e.offsetParent !== null).map(e => e.id));
  for (const id of ids) {
    await page.$eval('#' + id, el => el.scrollIntoView({ block: 'center' }));
    await sleep(40);
  }
  await sleep(150);
  const bad = await page.evaluate(() => Array.from(document.querySelectorAll('.chart')).filter(el => el.offsetParent !== null).filter(el => {
    if (el.querySelector('.chart-empty')) return false;
    const c = el.querySelector('canvas');
    return !c || c.width === 0 || c.height === 0;
  }).map(el => el.id));
  record(bad.length === 0, `${label}: all ${ids.length} visible charts drew (${bad.length ? 'not drawn: ' + bad.join(', ') : 'ok'})`);
}

async function checkContrast(page, label) {
  const low = await page.evaluate(() => {
    const parse = c => {
      let m = c.match(/rgba?\(([^)]+)\)/);
      if (m) { const p = m[1].split(/[\s,/]+/).filter(Boolean).map(Number); return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 }; }
      m = c.match(/color\(srgb ([^)]+)\)/);
      if (m) { const p = m[1].split(/[\s/]+/).filter(Boolean).map(Number); return { r: p[0] * 255, g: p[1] * 255, b: p[2] * 255, a: p.length > 3 ? p[3] : 1 }; }
      return null;
    };
    const lum = ({ r, g, b }) => { const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
    const bgOf = el => {
      for (let e = el; e; e = e.parentElement) {
        const c = parse(getComputedStyle(e).backgroundColor);
        if (c && c.a > 0.5) return c;
      }
      return parse(getComputedStyle(document.body).backgroundColor);
    };
    const out = [];
    for (const el of document.querySelectorAll('body *')) {
      if (el.closest('.sr-only, .chart, [hidden], script, style, svg')) continue;
      const own = Array.from(el.childNodes).some(n => n.nodeType === 3 && n.textContent.trim());
      if (!own || (!el.offsetParent && getComputedStyle(el).position !== 'fixed' && getComputedStyle(el).position !== 'sticky')) continue;
      const fg = parse(getComputedStyle(el).color);
      const bg = bgOf(el);
      if (!fg || !bg) continue;
      const L1 = lum(fg), L2 = lum(bg);
      const ratio = (Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05);
      if (ratio < 4.5) out.push(`${el.tagName.toLowerCase()}.${el.className} "${el.textContent.trim().slice(0, 30)}" ${ratio.toFixed(2)}`);
    }
    return out;
  });
  record(low.length === 0, `${label}: text contrast at least 4.5:1 (${low.length ? low.slice(0, 5).join('; ') : 'ok'})`);
}

async function srRows(page, id) {
  return page.$$eval(`#${id} tbody tr`, trs => trs.map(tr => Array.from(tr.cells).map(td => td.textContent.trim())));
}
const text = (page, sel) => page.$eval(sel, e => e.textContent.trim());
const appState = page => page.evaluate(() => window.MPW_APP.state());
const query = page => page.evaluate(() => Object.fromEntries(new URLSearchParams(location.search)));

async function showTab(page, id) {
  await page.click(`#tab-${id}`);
  await page.waitForFunction(t => !document.getElementById('panel-' + t).hidden, {}, id);
  await sleep(120);
}
async function selectedTab(page) {
  return page.evaluate(() => document.querySelector('[role="tab"][aria-selected="true"]').id);
}
async function cycleSelect(page, id, label, limit) {
  const values = await page.$$eval(`#${id} option`, os => os.map(o => o.value));
  const original = await page.$eval(`#${id}`, e => e.value);
  const list = limit ? values.slice(0, limit) : values;
  let ok = true;
  for (const v of list) {
    await page.select(`#${id}`, v);
    await sleep(30);
    ok = (await checkWidth(page, `${label} ${id}=${v}`, true)) && ok;
  }
  await page.select(`#${id}`, original);
  return { ok, count: list.length };
}
// Pixel position of a longitude/latitude, or of a heatmap cell, inside a chart, in page coordinates.
async function chartPoint(page, id, finder, value) {
  await page.$eval('#' + id, el => el.scrollIntoView({ block: 'center' }));
  await sleep(150);
  return page.evaluate((cid, f, v) => {
    const el = document.getElementById(cid);
    const chart = echarts.getInstanceByDom(el);
    const [x, y] = chart.convertToPixel(f, v);
    const r = el.getBoundingClientRect();
    return { x: r.left + x, y: r.top + y };
  }, id, finder, value);
}
async function pickItem(page, inputId, words) {
  await page.click('#' + inputId, { clickCount: 3 });
  await page.keyboard.press('Backspace');
  await page.type('#' + inputId, words);
  await sleep(60);
  await page.keyboard.press('Enter');
  await sleep(120);
}

async function shot(page, file, selector, opts = {}) {
  const out = path.join(SHOTS, file);
  await page.evaluate(() => { const s = document.getElementById('filter-status'); if (s) s.textContent = ''; document.activeElement && document.activeElement.blur(); });
  if (selector) {
    await page.$eval(selector, (el, offset) => { window.scrollTo(0, window.scrollY + el.getBoundingClientRect().top - offset); }, opts.offset ?? 72);
  } else {
    await page.evaluate(() => window.scrollTo(0, 0));
  }
  await sleep(400);
  await page.screenshot({ path: out, type: 'png' });
  const size = statSync(out).size;
  record(size < MAX_SHOT_BYTES, `screenshot ${file} saved (${Math.round(size / 1024)} KB, limit 500 KB)`);
}

/* Full functional run */
async function desktopRun(browser, errors) {
  const label = '1440x900 light';
  const page = await openPage(browser, BASE, VIEWPORTS[0], 'light', label, errors);

  // KPI values, before any scrolling (the hero renders without ECharts or data.js)
  const kpis = await page.$$eval('.kpi', els => Object.fromEntries(els.map(e => [e.dataset.kpi, e.querySelector('.kpi-value').textContent.trim()])));
  for (const [k, v] of Object.entries(EXPECTED_KPIS)) record(kpis[k] === v, `KPI ${k} shows ${v} (found ${kpis[k]})`);
  record(Object.keys(kpis).length === 6, `6 KPI figures (found ${Object.keys(kpis).length})`);
  // index.html carries the same figures before any script runs, so the first paint does not shift
  const raw = await (await fetch(BASE)).text();
  record(Object.values(EXPECTED_KPIS).every(v => raw.includes(`data-final="${v}"`)), 'index.html has the 6 KPI values before scripts run');
  const early = await page.evaluate(() => ({ data: !!window.MPW_DATA }));
  record(!early.data, 'first view loads without data.js (it loads when the explorer comes near)');
  await shot(page, 'hero.png');

  // Findings
  await page.$eval('#findings', el => el.scrollIntoView());
  await page.waitForFunction(() => !!window.echarts, { timeout: 15000 });
  const findingTitles = await page.$$eval('.finding-title', els => els.length);
  record(findingTitles === 5, `five findings shown (${findingTitles})`);
  const f5 = await text(page, '#h-f5a');
  record(f5.includes('2.42%') && f5.includes('4.98%'), `finding 5 states the festive changes ("${f5}")`);
  await shot(page, 'findings.png', '#finding-1', { offset: 80 });

  await scrollAll(page);
  await checkCharts(page, label);
  await checkWidth(page, label);
  await checkContrast(page, label);

  // Stakeholder views: key figures
  await showTab(page, 'households');
  const basket = Object.fromEntries((await srRows(page, 't-state')).map(r => [r[0], r[2]]));
  for (const [s, v] of Object.entries(EXPECTED_BASKET)) record(basket[s] === v, `state basket ${s} RM ${v} (found ${basket[s]})`);
  const fest = Object.fromEntries((await srRows(page, 't-festive')).map(r => [r[0], r[2]]));
  for (const [f, v] of Object.entries(EXPECTED_FESTIVE)) record(fest[f] === v, `festive staples, all states, ${f} ${v}% (found ${fest[f]})`);
  const dist = await text(page, '#h-district');
  record(dist.includes('91.4') && dist.includes('Bagan Datuk') && dist.includes('113.9') && dist.includes('Limbang'), `district view, all states: Bagan Datuk 91.4 to Limbang 113.9 (q10) ("${dist}")`);
  await showTab(page, 'retail');
  await checkCharts(page, `${label} retail tab`);
  const types = Object.fromEntries((await srRows(page, 't-type')).map(row => [row[0], row[1]]));
  for (const [t, v] of Object.entries(EXPECTED_SHOP_TYPES)) record(types[t] === v, `All states shop-type index ${t} ${v} (found ${types[t]})`);
  record((await page.$$('#t-cheap tbody tr')).length === 10 && (await page.$$('#t-dear tbody tr')).length === 10, '10 cheapest and 10 dearest shops listed');
  await showTab(page, 'cost-risk');
  await checkCharts(page, `${label} cost-risk tab`);
  const spikeTable = await srRows(page, 't-spikes');
  const dec = spikeTable.find(row => row[0] === 'December 2025');
  record(dec && dec[3] === '78', `December 2025 shows 78 spike weeks (found ${dec && dec[3]})`);
  const nov = spikeTable[0] || [];
  record(spikeTable.length === 11 && nov[0] === 'November 2025' && nov[3] === '12' && nov[5] === '21.82' && dec[5] === '8.60',
    `spike chart has q23's 11 months; spike rate November 21.82%, December 8.60% (found ${spikeTable.length} months, ${nov[5]}%)`);
  const avg = await page.evaluate(() => {
    const d = echarts.getInstanceByDom(document.getElementById('c-weekly')).getOption().series[1].data;
    return { early: d.slice(0, 8).every(x => x[1] === null || x[1] === undefined || x[1] === '-'), ninth: d[8] && d[8][1] };
  });
  record(avg.early && typeof avg.ninth === 'number', `weekly 8-week average starts at the 9th week (9th: ${avg.ninth})`);
  record((await text(page, '#h-risers')) === 'TOMATO rose the most: +60.00%', `default risers title ("${await text(page, '#h-risers')}")`);
  record((await text(page, '#h-fallers')) === 'TEMBIKAI MERAH TANPA BIJI fell the most: -33.41%', `default fallers title ("${await text(page, '#h-fallers')}")`);
  const moverRows = (await srRows(page, 't-risers')).concat(await srRows(page, 't-fallers'));
  record(moverRows.length === 20 && moverRows.every(row => Number(row[5]) >= 30 && Number(row[6]) >= 30), `all 20 risers and fallers have 30 or more shops in both months`);

  // Compare two states: default W.P. Kuala Lumpur and Kedah
  const cmp = await text(page, '#h-compare');
  record(cmp.includes('9.9%') && cmp.includes('RM 390.12') && cmp.includes('W.P. Kuala Lumpur') && cmp.includes('Kedah'), `compare tool: KL vs Kedah 9.9%, RM 390.12 ("${cmp}")`);
  const cmpGrid = await text(page, '#compare-grid');
  record(cmpGrid.includes('RM 4,349.65') && cmpGrid.includes('RM 3,959.53'), 'compare tool shows both basket costs');

  // Map click: Kedah (on the outline), then the Kuala Lumpur marker
  let pt = await chartPoint(page, 'c-map', { geoIndex: 0 }, [100.65, 5.95]);
  await page.mouse.click(pt.x, pt.y);
  await sleep(200);
  let st = await appState(page);
  record(st.state === 'Kedah' && (await page.$eval('#f-state', e => e.value)) === 'Kedah' && (await query(page)).state === 'Kedah',
    `map click on Kedah filters the explorer and the URL (state ${st.state})`);
  record((await text(page, '#h-profile')) === 'Kedah' && (await text(page, '#h-heat')).startsWith('In Kedah'), 'state profile and heatmap follow the map click');
  record((await text(page, '#h-district')).startsWith('In Kedah'), 'district view follows the map click');
  pt = await chartPoint(page, 'c-map', { geoIndex: 0 }, [100.55, 3.75]);
  await page.mouse.click(pt.x, pt.y);
  await sleep(200);
  st = await appState(page);
  record(st.state === 'W.P. Kuala Lumpur', `map marker click selects W.P. Kuala Lumpur (state ${st.state})`);
  record(st.compare[0] === 'W.P. Kuala Lumpur', `compare tool follows the selected state (${st.compare.join(' vs ')})`);
  // clicking the selected state again clears the filter
  await page.mouse.click(pt.x, pt.y);
  await sleep(200);
  record((await appState(page)).state === 'All states', 'clicking the selected state again clears the state filter');

  // Heatmap click: Johor x Hypermarket (rows are sorted; find Johor's row)
  const johorRow = await page.evaluate(() => {
    const chart = echarts.getInstanceByDom(document.getElementById('c-heat'));
    return chart.getOption().yAxis[0].data.indexOf('Johor');
  });
  pt = await chartPoint(page, 'c-heat', { seriesIndex: 0 }, [0, johorRow]);
  await page.mouse.click(pt.x, pt.y);
  await sleep(200);
  st = await appState(page);
  record(st.state === 'Johor' && st.type === 'Hypermarket', `heatmap click filters state and shop type (${st.state}, ${st.type})`);
  await showTab(page, 'retail');
  const johor = Object.fromEntries((await srRows(page, 't-type')).map(row => [row[0], row[1]]));
  record(johor.Hypermarket === '97.5' && johor['Mini market'] === '105.7', `Johor shop-type index matches q12: 97.5, 105.7 (found ${johor.Hypermarket}, ${johor['Mini market']})`);
  const shopTypes = await page.$$eval('#t-cheap tbody .cell-meta', els => els.map(e => e.textContent.split(',')[0]));
  record(shopTypes.length > 0 && shopTypes.every(t => t === 'Hypermarket'), `shop lists follow the shop-type filter (${shopTypes.length} hypermarkets)`);
  const mapTitle = await text(page, '#h-map');
  record(mapTitle.startsWith('Hypermarkets in Johor average 97.5'), `map switches to the shop-type index ("${mapTitle}")`);
  await page.select('#f-state', 'W.P. Putrajaya');
  await sleep(100);
  const putra = Object.fromEntries((await srRows(page, 't-type')).map(row => [row[0], row[1]]));
  record(putra['Mini market'] === '111.8', `W.P. Putrajaya Mini market index matches q12: 111.8 (found ${putra['Mini market']})`);

  // Every state and shop type through the filter bar
  let r = await cycleSelect(page, 'f-state', label);
  record(r.ok, `${label}: state filter, ${r.count} options, page fits`);
  r = await cycleSelect(page, 'f-type', label);
  record(r.ok, `${label}: shop type filter, ${r.count} options, page fits`);
  r = await cycleSelect(page, 'f-group', label);
  record(r.ok, `${label}: item group filter, ${r.count} options, page fits`);
  await page.select('#f-group', 'Fresh produce');
  await showTab(page, 'cost-risk');
  record((await text(page, '#h-risers')).startsWith('In fresh produce,'), `item group filters risers ("${await text(page, '#h-risers')}")`);
  await page.click('#item-search', { clickCount: 3 });
  await page.type('#item-search', 'SABUN');
  await sleep(80);
  const groupList = await page.$$eval('#item-search-list li[data-code]', ls => ls.length);
  record(groupList === 0, `item search only lists items in the chosen group (${groupList} soap items in fresh produce)`);
  await page.keyboard.press('Escape');
  await page.select('#f-group', 'All item groups');

  // Item search in the filter bar
  await pickItem(page, 'item-search', 'TELUR AYAM GRED A');
  st = await appState(page);
  const cheapTitle = await text(page, '#h-cheap-tool');
  record(cheapTitle.includes('TELUR AYAM GRED A'), `item search + Enter picks an item for the tools ("${cheapTitle.slice(0, 70)}")`);
  const lowestRows = await page.$$eval('#t-cheap-tool tbody tr', trs => trs.length);
  const example = await text(page, '#t-cheap-tool');
  record(lowestRows > 0 && example.includes('Example shop'), `where-is-it-cheapest table lists ${lowestRows} states with an example shop`);
  record((await text(page, '#h-monthly')).startsWith('TELUR AYAM GRED A'), 'item search drives the monthly chart');
  // Keyboard: arrow down then Enter
  await page.click('#cheap-search', { clickCount: 3 });
  await page.type('#cheap-search', 'TOMATO');
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Enter');
  await sleep(120);
  record((await text(page, '#h-cheap-tool')).startsWith('TOMATO'), `tool item search works with the keyboard ("${(await text(page, '#h-cheap-tool')).slice(0, 50)}")`);
  pt = await chartPoint(page, 'c-cheap-map', { geoIndex: 0 }, [102.3, 3.8]);
  await page.mouse.click(pt.x, pt.y);
  await sleep(200);
  record((await appState(page)).state === 'Pahang' && (await page.$eval('#t-cheap-tool tr.is-chosen', e => e.textContent)).includes('Pahang'),
    'clicking the cheapest-price map filters the state and marks its row');

  // Compare: change the second state, swap
  await page.select('#cmp-b', 'Selangor');
  await sleep(100);
  st = await appState(page);
  record(st.compare[1] === 'Selangor' && (await text(page, '#h-compare')).includes('Selangor'), `compare tool second state changes (${st.compare.join(' vs ')})`);
  await page.click('#cmp-swap');
  await sleep(100);
  st = await appState(page);
  record(st.compare[0] === 'Selangor', `swap button swaps the two states (${st.compare.join(' vs ')})`);

  // Trends: 3 default items, add a 4th, the search turns off, remove one, monthly change
  await page.click('#btn-reset');
  await sleep(150);
  record((await page.$$('#trend-chips li')).length === 3, 'price trends start with 3 items');
  await pickItem(page, 'trend-search', 'BAWANG BESAR IMPORT (INDIA)');
  record((await page.$$('#trend-chips li')).length === 4, 'adding an item gives 4 items');
  record(await page.$eval('#trend-search', e => e.disabled), 'the add-item search turns off at 4 items');
  const series = await page.evaluate(() => {
    const opt = echarts.getInstanceByDom(document.getElementById('c-trend')).getOption();
    return { lines: opt.series.filter(s => s.type === 'line').length, spikes: opt.series.filter(s => s.type === 'scatter').reduce((a, s) => a + s.data.length, 0), festive: (opt.series[0].markArea || {}).data?.length || 0 };
  });
  record(series.lines === 4 && series.spikes > 0 && series.festive >= 4, `trend chart: 4 lines, ${series.spikes} spike weeks marked, ${series.festive} festive periods shaded`);
  await page.click('#trend-chips li:first-child button');
  await sleep(100);
  record((await page.$$('#trend-chips li')).length === 3 && !(await page.$eval('#trend-search', e => e.disabled)), 'removing an item turns the search back on');
  await page.click('#trend-monthly');
  await sleep(100);
  record((await appState(page)).mode === 'monthly' && (await query(page)).measure === 'change', 'trend measure switches to the change since October 2025');
  await page.click('#trend-weekly');

  // Copy link and PNG buttons
  await page.click('#btn-copy');
  await sleep(200);
  record((await text(page, '#filter-status')).length > 0, `copy link reports back ("${await text(page, '#filter-status')}")`);
  const png = await page.evaluate(async () => {
    const hrefs = [];
    const orig = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function () { hrefs.push([this.download, this.href.slice(0, 21)]); };
    for (const b of document.querySelectorAll('.png-btn')) { if (b.offsetParent) b.click(); }
    HTMLAnchorElement.prototype.click = orig;
    return { buttons: document.querySelectorAll('.png-btn').length, hrefs };
  });
  record(png.hrefs.length > 10 && png.hrefs.every(h => h[1] === 'data:image/png;base64' && h[0].endsWith('.png')), `PNG buttons export charts (${png.hrefs.length} visible of ${png.buttons})`);

  // Tabs work with the keyboard
  await page.focus('#tab-cost-risk');
  await page.keyboard.press('ArrowRight');
  const k1 = await selectedTab(page);
  await page.keyboard.press('End');
  const k2 = await selectedTab(page);
  await page.keyboard.press('Home');
  const k3 = await selectedTab(page);
  record(k1 === 'tab-households' && k2 === 'tab-cost-risk' && k3 === 'tab-households', `tabs work with the keyboard (${k1}, ${k2}, ${k3})`);
  record((await page.evaluate(() => document.activeElement.id)) === 'tab-households', 'keyboard focus follows the selected tab');
  const focusOutline = await page.evaluate(() => { const s = getComputedStyle(document.activeElement); return s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) >= 2; });
  record(focusOutline, 'focused controls show a visible outline');

  // About
  const about = await text(page, '#about');
  record(about.includes('in Malay') && about.includes('q03') && about.includes('q12') && about.includes('CPI') && about.includes('DOSM Open Data Licence'),
    'About explains Malay item names, the q12 vs q03 index, the CPI caveat and the map licence');

  // Shared URL: set a full view, reload, and check it comes back
  await page.select('#f-state', 'Sabah');
  await page.select('#f-type', 'Wet market');
  await page.select('#f-group', 'Fresh produce');
  await pickItem(page, 'item-search', 'TOMATO');
  await page.select('#cmp-b', 'Perlis');
  await showTab(page, 'retail');
  const before = await appState(page);
  const url = await page.evaluate(() => location.href);
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('body[data-explorer="ready"]', { timeout: 20000 });
  const after = await appState(page);
  const same = ['state', 'type', 'group', 'item', 'view'].every(k => before[k] === after[k]) && before.compare.join() === after.compare.join() && before.trend.join() === after.trend.join();
  record(same && (await page.$eval('#f-type', e => e.value)) === 'Wet market' && (await selectedTab(page)) === 'tab-retail',
    `reloading a shared URL restores the view (${url.split('?')[1]})`);
  await checkWidth(page, `${label} after reload`);
  await page.click('#btn-reset');
  await sleep(150);
  record(Object.keys(await query(page)).length === 0 && (await appState(page)).state === 'All states', 'reset clears the filters and the URL');

  // Screenshots of the explorer and tools, in a clean state
  await page.select('#f-state', 'Kedah');
  await sleep(300);
  await shot(page, 'map_explorer.png', '.grid-map', { offset: 168 });
  await page.select('#f-state', 'All states');
  await pickItem(page, 'cheap-search', 'AYAM BERSIH - STANDARD');
  await shot(page, 'cheapest_tool.png', '#tool-cheapest', { offset: 168 });
  await shot(page, 'trends.png', '#tool-trends', { offset: 168 });

  // Theme toggle persists
  await page.click('#theme-toggle');
  await sleep(150);
  const dark = await page.evaluate(() => [document.documentElement.dataset.theme, document.getElementById('theme-toggle').getAttribute('aria-pressed')]);
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('body[data-ready="true"]');
  const kept = await page.evaluate(() => document.documentElement.dataset.theme);
  record(dark[0] === 'dark' && dark[1] === 'true' && kept === 'dark', `theme toggle switches to dark and is kept after a reload (${dark.join(', ')}, ${kept})`);
  await page.close();
}

/* Every viewport, in both themes */
async function viewportRun(browser, vp, theme, errors) {
  const label = `${vp.label} ${theme}`;
  const page = await openPage(browser, BASE, vp, theme, label, errors);
  const themeNow = await page.evaluate(() => document.documentElement.dataset.theme);
  record(themeNow === theme, `${label}: page starts in the ${theme} theme`);
  const kpis = await page.$$eval('.kpi-value', els => els.map(e => e.textContent.trim()).join(' | '));
  record(kpis === Object.values(EXPECTED_KPIS).join(' | '), `${label}: KPI values ${kpis}`);
  await scrollAll(page);
  for (const tab of ['households', 'retail', 'cost-risk']) {
    await showTab(page, tab);
    await checkCharts(page, `${label} ${tab} tab`);
  }
  await checkWidth(page, label);
  await checkContrast(page, label);
  // filters, a map click and the tools on this screen size
  let fits = (await cycleSelect(page, 'f-state', label, vp.isMobile ? 5 : 17)).ok;
  fits = (await cycleSelect(page, 'f-type', label)).ok && fits;
  // East Malaysia is drawn 3.2 degrees west of its true position
  const pt = await chartPoint(page, 'c-map', { geoIndex: 0 }, [113.5 - 3.2, 2.5]);
  await page.mouse.click(pt.x, pt.y);
  await sleep(200);
  record((await appState(page)).state === 'Sarawak', `${label}: map click selects Sarawak`);
  await pickItem(page, 'trend-search', 'BAWANG BESAR IMPORT (INDIA)');
  await pickItem(page, 'item-search', 'TELUR AYAM GRED B');
  await showTab(page, 'retail');
  await checkCharts(page, `${label} after filters`);
  fits = (await checkWidth(page, `${label} after filters`, true)) && fits;
  record(fits, `${label}: every filter value fits the screen (no sideways scrolling)`);
  if (vp.isMobile && theme === 'light') {
    await page.click('#btn-reset');
    await shot(page, 'phone.png');
  }
  if (vp.width === 1440 && theme === 'dark') {
    await page.click('#btn-reset');
    await sleep(200);
    await shot(page, 'dark_mode.png', '.grid-map', { offset: 168 });
  }
  await page.close();
}

async function fileRun(browser, errors) {
  const before = errors.length;
  const page = await openPage(browser, FILE_URL, VIEWPORTS[0], 'light', 'file://', errors);
  const tiles = await page.$$eval('.kpi', els => els.length);
  await scrollAll(page);
  await checkCharts(page, 'file://');
  const pt = await chartPoint(page, 'c-map', { geoIndex: 0 }, [100.65, 5.95]);
  await page.mouse.click(pt.x, pt.y);
  await sleep(200);
  const state = (await appState(page)).state;
  const q = await page.evaluate(() => location.search);
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('body[data-explorer="ready"]', { timeout: 20000 });
  const back = (await appState(page)).state;
  record(tiles === 6 && state === 'Kedah' && q.includes('state=Kedah') && back === 'Kedah' && errors.length === before,
    `file:// opens, loads the explorer, filters from the map and restores the URL view, with no console errors (${state}, ${q}, ${back})`);
  await page.close();
}

async function main() {
  if (!existsSync(SHOTS)) mkdirSync(SHOTS, { recursive: true });
  // the screenshots are rebuilt by this run
  for (const f of readdirSync(SHOTS)) if (f.endsWith('.png')) unlinkSync(path.join(SHOTS, f));
  const server = await startServer();
  const args = [];
  if (process.platform === 'linux' && process.getuid && process.getuid() === 0) args.push('--no-sandbox');
  const browser = await puppeteer.launch({ headless: true, executablePath: process.env.CHROME_PATH || undefined, args });
  console.log(`Browser: ${await browser.version()} (${process.env.CHROME_PATH || 'Puppeteer default'})`);
  const errors = [];
  try {
    await desktopRun(browser, errors);
    for (const vp of VIEWPORTS) for (const theme of ['light', 'dark']) await viewportRun(browser, vp, theme, errors);
    await fileRun(browser, errors);
  } finally {
    await browser.close();
    if (server) server.kill();
  }
  record(errors.length === 0, `no console errors, page errors or failed requests${errors.length ? ':\n  ' + errors.slice(0, 20).join('\n  ') : ''}`);
  const failed = results.filter(x => !x.ok);
  console.log(`\n${results.length - failed.length} passed, ${failed.length} failed.`);
  process.exit(failed.length ? 1 : 0);
}

main().catch(err => { console.error(err); process.exit(1); });
