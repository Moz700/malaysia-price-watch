/* Malaysia Price Watch dashboard.
   Reads window.MPW_SUMMARY (assets/summary.js) for the hero and the five
   findings, then loads ECharts, window.MPW_DATA (assets/data.js) and the state
   outlines (assets/geo/malaysia_states.js) only when the charts are needed.
   Every file is loaded with a script tag, so the page also works from disk
   (file://), where fetch() is blocked. All numbers come from the CSV files in
   dashboard/data or from results/build_run, via dashboard/build_data.py. */
(function () {
  'use strict';

  const S = window.MPW_SUMMARY;
  const $ = id => document.getElementById(id);
  const reduceMotion = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);

  /* Constants */
  const SHOP_TYPES = ['Hypermarket', 'Supermarket', 'Mini market', 'Sundry shop', 'Wet market'];
  const ALL_STATES = 'All states';
  const ALL_TYPES = 'All shop types';
  const ALL_GROUPS = 'All item groups';
  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'];
  const FIRST_MONTH = '2025-10-01';
  const LAST_MONTH = '2026-09-01';
  const MIN_MOVER_SHOPS = 30;   // q13 keeps items with 30 or more shops
  const MIN_TITLE_SHOPS = 5;    // the quartile title ignores shop types with fewer shops
  const SPIKE_WINDOW = 8;       // a spike test needs 8 earlier kept weeks (q23)
  const MAX_TREND = 4;
  const CATEGORY_EN = {
    'SAYUR-SAYURAN': 'Vegetables', BAWANG: 'Onions and garlic', DAGING: 'Meat', 'BUAH-BUAHAN': 'Fruit',
    AYAM: 'Chicken', 'BAHAN LAUT': 'Seafood', TELUR: 'Eggs', 'CILI KERING': 'Dried chillies'
  };
  // Marker positions for the three federal territories, which are too small to click on the outline.
  // [marker longitude, marker latitude, true longitude, true latitude, label position]; East Malaysia is shifted 3.2 degrees west.
  const FT_MARKERS = {
    'W.P. Kuala Lumpur': [100.35, 3.65, 101.69, 3.15, 'left'],
    'W.P. Putrajaya': [100.6, 2.55, 101.69, 2.93, 'left'],
    'W.P. Labuan': [111.15, 6.1, 112.03, 5.31, 'top']
  };
  const FT_SHORT = { 'W.P. Kuala Lumpur': 'Kuala Lumpur', 'W.P. Putrajaya': 'Putrajaya', 'W.P. Labuan': 'Labuan' };

  /* Formatting */
  const nf0 = new Intl.NumberFormat('en-US');
  const nf2 = new Intl.NumberFormat('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const rm = v => 'RM ' + nf2.format(v);
  const signed = (v, d) => (v > 0 ? '+' : '') + v.toFixed(d);
  const pct = (v, d) => signed(v, d === undefined ? 2 : d) + '%';
  // Round half away from zero, like PostgreSQL ROUND(numeric).
  const roundTo = (x, d) => { const f = Math.pow(10, d); return Math.sign(x) * Math.round(Math.abs(x) * f + 1e-9) / f; };
  const parts = iso => iso.split('-').map(Number);
  const monthName = iso => { const p = parts(iso); return MONTHS[p[1] - 1] + ' ' + p[0]; };
  const monthShort = iso => { const p = parts(iso); return MONTHS[p[1] - 1].slice(0, 3) + ' ' + p[0]; };
  const dayName = iso => { const p = parts(iso); return p[2] + ' ' + MONTHS[p[1] - 1] + ' ' + p[0]; };
  const localTime = iso => { const p = parts(iso); return new Date(p[0], p[1] - 1, p[2]).getTime(); };
  const plural = type => type.toLowerCase() + 's';
  const cap = s => s.charAt(0).toUpperCase() + s.slice(1);
  const joinAnd = list => list.length < 2 ? list.join('') : list.slice(0, -1).join(', ') + ' and ' + list[list.length - 1];
  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const setText = (id, text) => { const el = $(id); if (el) el.textContent = text; };
  const placeName = s => s === ALL_STATES ? 'Malaysia' : s;
  const shortState = s => FT_SHORT[s] || s;
  const markerName = s => markerNarrow && s === 'W.P. Kuala Lumpur' ? 'KL' : shortState(s);
  const slug = s => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 80) || 'chart';

  function extremes(rows, value, dir) {
    let best = null;
    for (const r of rows) {
      const v = value(r);
      if (v === null || v === undefined) continue;
      if (best === null || (v - best) * dir < 0) best = v;
    }
    return { value: best, rows: rows.filter(r => value(r) === best) };
  }
  function groupBy(rows, key) {
    const map = new Map();
    for (const r of rows) {
      const k = typeof key === 'function' ? key(r) : r[key];
      if (!map.has(k)) map.set(k, []);
      map.get(k).push(r);
    }
    return map;
  }

  /* Theme */
  let C = {};
  function readColors() {
    const cs = getComputedStyle(document.documentElement);
    const v = n => cs.getPropertyValue(n).trim();
    C = {
      ink: v('--ink'), muted: v('--muted'), rule: v('--rule'), ruleStrong: v('--rule-strong'), surface: v('--surface'),
      surface2: v('--surface-2'), blue: v('--blue'), blueInk: v('--blue-ink'), orange: v('--orange'), orangeInk: v('--orange-ink'),
      green: v('--green'), purple: v('--purple'), neutral: v('--neutral'), nodata: v('--nodata'),
      dark: document.documentElement.getAttribute('data-theme') === 'dark'
    };
    C.series = [C.blue, C.orange, C.green, C.purple];
    C.types = { Hypermarket: C.blue, Supermarket: C.green, 'Mini market': C.purple, 'Sundry shop': C.muted, 'Wet market': C.orange };
  }
  function hexRgb(h) {
    h = h.replace('#', '');
    if (h.length === 3) h = h.split('').map(c => c + c).join('');
    const n = parseInt(h, 16);
    return [n >> 16 & 255, n >> 8 & 255, n & 255];
  }
  function mix(a, b, t) {
    const A = hexRgb(a), B = hexRgb(b);
    return '#' + A.map((x, i) => Math.round(x + (B[i] - x) * t).toString(16).padStart(2, '0')).join('');
  }
  // Blue below 100, neutral at 100, orange above; span = distance from 100 to the strongest colour.
  function divColor(v, span) {
    if (v === null || v === undefined) return C.nodata;
    const t = Math.max(-1, Math.min(1, (v - 100) / span));
    return t < 0 ? mix(C.neutral, C.blue, -t) : mix(C.neutral, C.orange, t);
  }
  function seqColor(t) { // 0 = highest price (pale), 1 = lowest price (strong blue)
    const pale = C.dark ? '#22364f' : '#dbe8f7';
    const strong = C.dark ? '#7fb3f0' : '#174f96';
    return mix(pale, strong, Math.max(0, Math.min(1, t)));
  }
  function luminance(hex) {
    const f = x => { x /= 255; return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); };
    const [r, g, b] = hexRgb(hex);
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
  }
  // a lighter version of a colour for items outside the current filter; text on it stays readable
  const dimColor = hex => mix(hex, C.surface, 0.65);
  const textOn = hex => luminance(hex) > 0.36 ? '#15243a' : '#ffffff';

  function applyTheme(theme, save) {
    document.documentElement.setAttribute('data-theme', theme);
    if (save) { try { localStorage.setItem('mpw-theme', theme); } catch (e) { /* storage blocked */ } }
    const btn = $('theme-toggle');
    btn.setAttribute('aria-pressed', theme === 'dark' ? 'true' : 'false');
    btn.querySelector('.theme-label').textContent = theme === 'dark' ? 'Light theme' : 'Dark theme';
    btn.setAttribute('aria-label', theme === 'dark' ? 'Switch to the light theme' : 'Switch to the dark theme');
    readColors();
  }

  /* Script loads */
  function loadScript(src) {
    return new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = src;
      s.onload = () => resolve();
      s.onerror = () => reject(new Error('Could not load ' + src));
      document.body.appendChild(s);
    });
  }
  let chartsPromise = null;
  function needCharts() {
    if (!chartsPromise) {
      chartsPromise = (window.echarts ? Promise.resolve() : loadScript('assets/vendor/echarts.min.js'))
        .then(() => document.fonts && document.fonts.ready ? document.fonts.ready : null)
        .then(() => { flushVisible(); });
    }
    return chartsPromise;
  }
  let dataPromise = null;
  function needData() {
    if (!dataPromise) {
      dataPromise = Promise.all([needCharts(), loadScript('assets/data.js'), loadScript('assets/geo/malaysia_states.js')])
        .then(() => startExplorer())
        .catch(err => {
          setText('explore-loading', 'The explorer could not load its data files (' + err.message + '). Reload the page to try again.');
          throw err;
        });
    }
    return dataPromise;
  }

  /* Charts */
  const charts = {};
  const pending = {};
  const near = new Set();
  const handlers = {};
  const io = 'IntersectionObserver' in window ? new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (e.isIntersecting) { near.add(e.target.id); flush(e.target.id); } else near.delete(e.target.id);
    });
  }, { rootMargin: '500px 0px' }) : null;

  const axisText = () => ({ color: C.muted, fontSize: 12, fontFamily: 'Inter, system-ui, sans-serif' });
  const splitLine = () => ({ lineStyle: { color: C.rule } });
  const chartWidth = id => { const el = $(id); return (el && el.clientWidth) || 600; };

  function baseOption(option) {
    const full = Object.assign({
      animation: !reduceMotion,
      animationDuration: 500,
      animationDurationUpdate: 350,
      textStyle: { fontFamily: 'Inter, system-ui, sans-serif', color: C.ink }
    }, option);
    full.tooltip = Object.assign({
      confine: true,
      backgroundColor: C.surface,
      borderColor: C.ruleStrong,
      borderWidth: 1,
      padding: [10, 12],
      textStyle: { color: C.ink, fontSize: 13, fontFamily: 'Inter, system-ui, sans-serif' },
      extraCssText: 'box-shadow:0 8px 24px rgba(16,36,64,.18);border-radius:8px;max-width:320px;white-space:normal;line-height:1.5;'
    }, option.tooltip || {});
    return full;
  }

  // Store the option and draw it when the chart is near the screen.
  function draw(id, option, height) {
    const el = $(id);
    if (!el) return;
    if (height) el.style.height = height + 'px';
    pending[id] = option;
    if (!io || near.has(id)) flush(id);
    else io.observe(el);
  }
  function flush(id) {
    const option = pending[id];
    if (!option || !window.echarts) return;
    delete pending[id];
    const el = $(id);
    let chart = charts[id];
    if (!chart) {
      el.innerHTML = '';
      chart = charts[id] = echarts.init(el, null, { renderer: 'canvas' });
      if (handlers[id]) chart.on('click', handlers[id]);
    }
    chart.setOption(baseOption(option), { notMerge: true });
    chart.resize();
    el.setAttribute('data-drawn', 'true');
  }
  function flushVisible() { Object.keys(pending).forEach(id => { if (!io || near.has(id)) flush(id); }); }
  function showEmpty(id, message, height) {
    delete pending[id];
    if (charts[id]) { charts[id].dispose(); delete charts[id]; }
    const el = $(id);
    if (height) el.style.height = height + 'px';
    el.innerHTML = '<div class="chart-empty">' + esc(message) + '</div>';
    el.setAttribute('data-drawn', 'true');
  }
  function srTable(id, caption, head, rows) {
    const el = $(id);
    if (!el) return;
    el.innerHTML = '<caption>' + esc(caption) + '</caption><thead><tr>' +
      head.map(h => '<th scope="col">' + esc(h) + '</th>').join('') + '</tr></thead><tbody>' +
      rows.map(r => '<tr>' + r.map(c => '<td>' + esc(c) + '</td>').join('') + '</tr>').join('') + '</tbody>';
  }

  function downloadPng(id) {
    if (pending[id]) flush(id);
    const chart = charts[id];
    if (!chart) return;
    const card = $(id).closest('.card');
    const title = card && card.querySelector('.chart-title') ? card.querySelector('.chart-title').textContent : id;
    const url = chart.getDataURL({ type: 'png', pixelRatio: 2, backgroundColor: C.surface });
    const a = document.createElement('a');
    a.href = url;
    a.download = 'malaysia-price-watch-' + slug(title) + '.png';
    document.body.appendChild(a);
    a.click();
    a.remove();
  }

  // Horizontal bars drawn from 100, so cheaper than national points left.
  function indexBarOption(categories, values, opts) {
    const span = opts.span || 10;
    const narrow = opts.id ? chartWidth(opts.id) < 480 : false;
    const data = values.map((v, i) => {
      const extra = (opts.itemFor && opts.itemFor(i)) || {};
      if (v === null || v === undefined) {
        return { value: 0, label: { show: true, position: 'right', formatter: extra.emptyLabel || 'no data', color: C.muted } };
      }
      const off = roundTo(v - 100, 1);
      return {
        value: off,
        itemStyle: Object.assign({ color: extra.dim ? dimColor(divColor(v, span)) : divColor(v, span), borderRadius: off < 0 ? [3, 0, 0, 3] : [0, 3, 3, 0] }, extra.item || {}),
        label: { show: true, position: off < 0 ? 'left' : 'right', formatter: extra.labelText || v.toFixed(1), color: C.ink, fontSize: 12, fontWeight: extra.bold ? 700 : 400 }
      };
    });
    return {
      grid: { left: 8, right: opts.right || 48, top: 8, bottom: 36, containLabel: true },
      xAxis: {
        type: 'value',
        min: v => v.min < 0 ? Math.floor(v.min - (v.max - Math.min(v.min, 0)) * (narrow ? 0.4 : 0.22)) : 0,
        max: v => v.max > 0 ? Math.ceil(v.max + (v.max - Math.min(v.min, 0)) * (narrow ? 0.15 : 0.08)) : 1,
        axisLabel: Object.assign({ formatter: v => String(roundTo(v + 100, 1)), hideOverlap: true }, axisText()),
        splitLine: splitLine(),
        name: narrow ? '' : opts.xName !== undefined ? opts.xName : 'index (100 = national)', nameLocation: 'middle', nameGap: 26, nameTextStyle: axisText()
      },
      yAxis: {
        type: 'category', data: categories, inverse: true,
        axisLine: { show: false }, axisTick: { show: false },
        axisLabel: Object.assign({}, axisText(), { color: C.ink, fontSize: 12, formatter: opts.labelFormatter, rich: { b: { fontWeight: 700, color: C.ink, fontSize: 12 } } })
      },
      tooltip: { trigger: 'item', formatter: opts.tooltip },
      series: [{
        type: 'bar', data: data, barMaxWidth: 20,
        markLine: { silent: true, symbol: 'none', label: { show: false }, lineStyle: { color: C.muted, type: 'solid', width: 1 }, data: [{ xAxis: 0 }] }
      }]
    };
  }

  /* Hero */
  const SVGNS = 'http://www.w3.org/2000/svg';
  function sparkSvg(spark) {
    const W = 148, H = 44;
    const parts = [];
    const grey = 'var(--spark-grey)', blue = 'var(--spark-blue)', orange = 'var(--spark-orange)';
    const rect = (x, y, w, h, fill) => '<rect x="' + x.toFixed(1) + '" y="' + y.toFixed(1) + '" width="' + Math.max(0.5, w).toFixed(1) + '" height="' + Math.max(0.5, h).toFixed(1) + '" rx="1.5" fill="' + fill + '"/>';
    const text = (x, y, t, anchor) => '<text x="' + x + '" y="' + y + '"' + (anchor ? ' text-anchor="' + anchor + '"' : '') + '>' + esc(t) + '</text>';
    if (spark.kind === 'states') {
      const rows = S.state_basket.slice().sort((a, b) => b.basket_index - a.basket_index);
      const bw = W / rows.length;
      const mid = 20;
      rows.forEach((r, i) => {
        const d = r.basket_index - 100;
        const h = Math.abs(d) / 6 * 18;
        const fill = r.state === spark.highlight[0] ? orange : r.state === spark.highlight[1] ? blue : grey;
        parts.push(rect(i * bw + 1, d > 0 ? mid - h : mid, bw - 2.5, h, fill));
      });
      parts.push('<line x1="0" x2="' + W + '" y1="' + mid + '" y2="' + mid + '" stroke="rgba(255,255,255,.45)" stroke-width="1"/>');
      parts.push(text(0, H - 1, 'KL') + text(W, H - 1, 'Kedah', 'end'));
    } else if (spark.kind === 'pair') {
      const max = Math.max(...spark.items.map(x => x.value));
      spark.items.forEach((it, i) => {
        const y = 4 + i * 20;
        parts.push(text(0, y + 10, i === 0 ? 'Wet' : 'Hyper'));
        parts.push(rect(40, y + 1, (W - 40) * it.value / max, 11, i === 0 ? orange : blue));
      });
    } else if (spark.kind === 'meter') {
      parts.push(rect(0, 10, W, 10, grey));
      parts.push(rect(0, 10, W * spark.value / 100, 10, blue));
      parts.push(text(0, 38, nf0.format(spark.above) + ' of ' + nf0.format(spark.total) + ' above'));
    } else if (spark.kind === 'share') {
      [['Rises', spark.share, orange], ['Items', spark.items, blue]].forEach((r, i) => {
        const y = 4 + i * 20;
        parts.push(text(0, y + 10, r[0]));
        parts.push(rect(40, y + 1, W - 40, 11, grey));
        parts.push(rect(40, y + 1, (W - 40) * r[1] / 100, 11, r[2]));
      });
    } else if (spark.kind === 'gap') {
      const x = v => 6 + (v - 85) / 20 * (W - 12);
      const y = 14;
      parts.push('<line x1="6" x2="' + (W - 6) + '" y1="' + y + '" y2="' + y + '" stroke="rgba(255,255,255,.28)" stroke-width="1"/>');
      parts.push('<line x1="' + x(spark.from.value) + '" x2="' + x(spark.to.value) + '" y1="' + y + '" y2="' + y + '" stroke="rgba(255,255,255,.75)" stroke-width="2"/>');
      parts.push('<circle cx="' + x(spark.from.value) + '" cy="' + y + '" r="5" fill="' + blue + '"/>');
      parts.push('<circle cx="' + x(spark.to.value) + '" cy="' + y + '" r="5" fill="' + orange + '"/>');
      parts.push(text(0, 38, 'Tesco ' + spark.from.value.toFixed(1)));
      parts.push(text(W, 38, 'Average ' + spark.to.value.toFixed(1), 'end'));
    } else if (spark.kind === 'months') {
      const rows = S.spikes_by_month;
      const max = Math.max(...rows.map(r => r.spike_weeks));
      const bw = W / rows.length;
      rows.forEach((r, i) => {
        const h = r.spike_weeks / max * 30;
        parts.push(rect(i * bw + 1, 32 - h, bw - 3, h, r.spike_weeks === max ? orange : grey));
      });
      parts.push(text(0, H - 1, 'Nov 2025') + text(W, H - 1, 'Sep 2026', 'end'));
    }
    return '<svg class="kpi-spark" viewBox="0 0 ' + W + ' ' + H + '" xmlns="' + SVGNS + '" aria-hidden="true" focusable="false">' + parts.join('') + '</svg>';
  }

  // "12.1 points" -> big "12.1" and a smaller " points"; the text stays the exact KPI value.
  function kpiValueHtml(value) {
    const m = value.match(/^([\d.,]+)(%?)(.*)$/);
    if (!m) return esc(value);
    return '<span class="kpi-num">' + esc(m[1]) + '</span>' + esc(m[2]) + (m[3] ? '<span class="kpi-unit">' + esc(m[3]) + '</span>' : '');
  }
  function renderHero() {
    $('kpi-grid').innerHTML = S.kpis.map((k, i) =>
      '<li class="kpi" data-kpi="' + (i + 1) + '">' +
      '<p class="kpi-value" data-final="' + esc(k.value) + '">' + kpiValueHtml(k.value) + '</p>' +
      sparkSvg(k.spark || {}) +
      '<p class="kpi-label">' + esc(k.label) + '</p>' +
      '<p class="kpi-meaning">' + esc(k.meaning) + '</p>' +
      '<p class="kpi-source">Source: ' + esc(k.source) + '</p></li>').join('');
    if (reduceMotion) return;
    // Count each figure up from zero once; the final text is the exact KPI value.
    const els = Array.from(document.querySelectorAll('.kpi-num'));
    const targets = els.map(el => {
      const txt = el.textContent;
      const num = Number(txt.replace(/,/g, ''));
      const dec = (txt.split('.')[1] || '').length;
      return { el, num, dec, final: txt };
    });
    const start = performance.now();
    const dur = 1100;
    function step(now) {
      const t = Math.min(1, (now - start) / dur);
      const e = 1 - Math.pow(1 - t, 3);
      targets.forEach(x => { x.el.textContent = (x.num * e).toFixed(x.dec); });
      if (t < 1) requestAnimationFrame(step);
      else targets.forEach(x => { x.el.textContent = x.final; });
    }
    requestAnimationFrame(step);
  }

  /* Findings */
  function renderF1() {
    const rows = S.q03_type_index;
    draw('c-f1', indexBarOption(rows.map(r => r.type), rows.map(r => r.index), {
      id: 'c-f1', span: 8, xName: 'price index on the same 181 items (100 = national median)',
      tooltip: p => {
        const r = rows[p.dataIndex];
        return '<b>' + esc(r.type) + '</b><br>Price index: ' + r.index.toFixed(1) + ' (100 = national median)' +
          '<br>Items compared: ' + r.items + '<br>Priced below the national median: ' + r.below + ' items' +
          '<br>Priced above it: ' + r.above + ' items';
      }
    }), 280);
  }
  function renderF2() {
    const rows = SHOP_TYPES.map(t => ({ type: t, index: S.q12_fresh_index[t], q: S.q19_quarters[t] }))
      .sort((a, b) => a.index - b.index);
    draw('c-f2', indexBarOption(rows.map(r => r.type), rows.map(r => r.index), {
      id: 'c-f2', span: 14, xName: "average shop's fresh-produce index (100 = national median)",
      itemFor: i => rows[i].type === 'Wet market' ? { bold: true } : null,
      labelFormatter: v => v === 'Wet market' ? '{b|' + v + '}' : v,
      tooltip: p => {
        const r = rows[p.dataIndex];
        return '<b>' + esc(r.type) + '</b><br>Fresh-produce price index: ' + r.index.toFixed(1) + ' (100 = national median)' +
          '<br>Shops in their state\'s dearest quarter: ' + r.q.dearest.toFixed(1) + '% of ' + nf0.format(r.q.shops) +
          '<br>Shops in the cheapest quarter: ' + r.q.cheapest.toFixed(1) + '%';
      }
    }), 280);
  }
  function renderF3() {
    const rows = S.state_basket.slice().sort((a, b) => b.basket_cost_rm - a.basket_cost_rm);
    const narrow = chartWidth('c-f3') < 520;
    const hl = ['W.P. Kuala Lumpur', 'Kedah'];
    draw('c-f3', {
      grid: { left: 8, right: narrow ? 96 : 88, top: 8, bottom: 36, containLabel: true },
      xAxis: {
        type: 'value', min: 3900, max: 4400, interval: 100,
        axisLabel: Object.assign({ formatter: v => 'RM ' + nf0.format(v), hideOverlap: true }, axisText()),
        splitLine: splitLine(), name: narrow ? 'RM, axis starts at 3,900' : 'basket cost, RM (axis starts at RM 3,900)', nameLocation: 'middle', nameGap: 26, nameTextStyle: axisText()
      },
      yAxis: {
        type: 'category', data: rows.map(r => shortState(r.state)), inverse: true, axisTick: { show: false }, axisLine: { show: false },
        axisLabel: Object.assign({}, axisText(), { color: C.ink })
      },
      tooltip: {
        trigger: 'item',
        formatter: p => {
          const r = rows[p.dataIndex];
          return '<b>' + esc(r.state) + '</b><br>Basket cost: ' + rm(r.basket_cost_rm) + ' for ' + r.basket_items + ' items' +
            '<br>Basket index: ' + r.basket_index.toFixed(1) + ' (100 = national)' +
            '<br>Items filled with the national median: ' + r.items_filled_with_national;
        }
      },
      series: [
        {
          type: 'bar', barWidth: 2, silent: true, itemStyle: { color: C.ruleStrong },
          data: rows.map(r => r.basket_cost_rm), tooltip: { show: false }
        },
        {
          type: 'scatter', symbolSize: r => 12, z: 3,
          data: rows.map(r => ({
            value: [r.basket_cost_rm, shortState(r.state)],
            symbolSize: hl.indexOf(r.state) >= 0 ? 16 : 11,
            itemStyle: { color: divColor(r.basket_index, 6), borderColor: C.surface, borderWidth: 1.5 },
            label: {
              show: true, position: 'right', distance: 8, color: C.ink, fontSize: 12, fontWeight: hl.indexOf(r.state) >= 0 ? 700 : 400,
              formatter: () => hl.indexOf(r.state) >= 0 || !narrow ? rm(r.basket_cost_rm) : ''
            }
          }))
        }
      ]
    }, narrow ? 520 : 460);
  }
  function renderF4() {
    const rows = S.q14_categories.slice(0, 8);
    const narrow = chartWidth('c-f4') < 560;
    const name = r => CATEGORY_EN[r.category] || r.category;
    const color = (r, i) => i < 3 ? C.orange : (C.dark ? '#4a6488' : '#9fb3cc');
    const tip = r => '<b>' + esc(name(r)) + '</b> (' + esc(r.category) + ')<br>Share of all price increases: ' + r.share.toFixed(1) + '%' +
      '<br>Running total: ' + r.cumulative.toFixed(1) + '%<br>Items in the category: ' + r.items + ' (' + r.share_of_items.toFixed(1) + '% of items)';
    if (narrow) {
      draw('c-f4', {
        grid: { left: 8, right: 56, top: 8, bottom: 36, containLabel: true },
        xAxis: { type: 'value', axisLabel: Object.assign({ formatter: v => v + '%' }, axisText()), splitLine: splitLine(), name: 'share of all increases', nameLocation: 'middle', nameGap: 26, nameTextStyle: axisText() },
        yAxis: { type: 'category', inverse: true, data: rows.map(name), axisTick: { show: false }, axisLine: { show: false }, axisLabel: Object.assign({}, axisText(), { color: C.ink }) },
        tooltip: { trigger: 'item', formatter: p => tip(rows[p.dataIndex]) },
        series: [{
          type: 'bar', barMaxWidth: 18,
          data: rows.map((r, i) => ({ value: r.share, itemStyle: { color: color(r, i), borderRadius: [0, 3, 3, 0] } })),
          label: { show: true, position: 'right', color: C.ink, fontSize: 12, formatter: p => p.value.toFixed(1) + '%' }
        }]
      }, 340);
      return;
    }
    draw('c-f4', {
      grid: { left: 8, right: 8, top: 44, bottom: 8, containLabel: true },
      xAxis: {
        type: 'category', data: rows.map(name), axisTick: { show: false }, axisLine: { lineStyle: { color: C.ruleStrong } },
        axisLabel: Object.assign({}, axisText(), { color: C.ink, interval: 0, width: Math.max(60, chartWidth('c-f4') / 8 - 10), overflow: 'break', lineHeight: 15 })
      },
      yAxis: { type: 'value', max: 30, axisLabel: Object.assign({ formatter: v => v + '%' }, axisText()), splitLine: splitLine() },
      tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' }, formatter: ps => tip(rows[ps[0].dataIndex]) },
      graphic: [{
        type: 'text', left: 8, top: 4,
        style: { text: 'The 3 shaded categories: ' + rows[2].cumulative.toFixed(1) + '% of all increases and ' +
          roundTo(rows[0].share_of_items + rows[1].share_of_items + rows[2].share_of_items, 1).toFixed(1) + '% of the items',
          fill: C.ink, font: '600 12.5px Inter, system-ui, sans-serif' }
      }],
      series: [{
        type: 'bar', barMaxWidth: 44,
        data: rows.map((r, i) => ({ value: r.share, itemStyle: { color: color(r, i), borderRadius: [3, 3, 0, 0] } })),
        label: { show: true, position: 'top', color: C.ink, fontSize: 12, formatter: p => p.value.toFixed(1) + '%' },
        markArea: {
          silent: true, itemStyle: { color: C.dark ? 'rgba(240,122,72,0.10)' : 'rgba(235,104,52,0.07)' },
          data: [[{ xAxis: name(rows[0]) }, { xAxis: name(rows[2]) }]]
        }
      }]
    }, 340);
  }
  function festiveOption(rows, place, narrow) {
    const barData = key => rows.map(r => {
      const v = r[key].mean;
      return { value: v, label: { position: v === null ? 'top' : v < 0 ? (narrow ? 'left' : 'bottom') : (narrow ? 'right' : 'top') } };
    });
    const label = { show: true, fontSize: 12, color: C.ink, formatter: p => p.value === null || p.value === undefined ? '' : pct(p.value) };
    const catAxis = {
      type: 'category', data: rows.map(r => r.festival), axisTick: { show: false }, inverse: narrow,
      axisLine: { onZero: false, lineStyle: { color: C.ruleStrong } },
      axisLabel: Object.assign({}, axisText(), { color: C.ink, interval: 0, width: narrow ? 84 : 120, overflow: 'break', lineHeight: 15 })
    };
    const valAxis = {
      type: 'value', splitLine: splitLine(),
      min: v => v.min < 0 ? Math.floor(v.min - (v.max - Math.min(v.min, 0)) * (narrow ? 0.4 : 0.18)) : 0,
      max: v => v.max > 0 ? Math.ceil(v.max + (v.max - Math.min(v.min, 0)) * (narrow ? 0.35 : 0.12)) : 1,
      axisLabel: Object.assign({ formatter: v => v + '%' }, axisText())
    };
    return {
      grid: { left: 8, right: 16, top: 40, bottom: 8, containLabel: true },
      legend: { top: 0, left: 0, itemWidth: 14, itemHeight: 10, textStyle: axisText(), data: ['Festive staples', 'Other items (control)'] },
      xAxis: narrow ? valAxis : catAxis,
      yAxis: narrow ? catAxis : valAxis,
      tooltip: {
        trigger: 'axis', axisPointer: { type: 'shadow' },
        formatter: ps => {
          const r = rows[ps[0].dataIndex];
          const line = (name, s) => name + ': ' + (s.mean === null ? 'no data' : pct(s.mean)) +
            ' (' + nf0.format(s.pairs) + ' matched pairs' + (s.up === null || s.up === undefined ? '' : ', ' + s.up.toFixed(1) + '% of pairs up') + ')';
          return '<b>' + esc(r.festival) + '</b>, ' + dayName(r.date) + '<br>' + esc(place) + '<br>' +
            line('Festive staples', r.staples) + '<br>' + line('Other items', r.other);
        }
      },
      series: [
        {
          name: 'Festive staples', type: 'bar', barMaxWidth: 30, itemStyle: { color: C.blue, borderRadius: 2 }, label: label, data: barData('staples'),
          markLine: { silent: true, symbol: 'none', label: { show: false }, lineStyle: { color: C.muted, type: 'solid', width: 1 }, data: [narrow ? { xAxis: 0 } : { yAxis: 0 }] }
        },
        { name: 'Other items (control)', type: 'bar', barMaxWidth: 30, itemStyle: { color: C.orange, borderRadius: 2 }, label: label, data: barData('other') }
      ]
    };
  }
  function renderF5() {
    const narrow = chartWidth('c-f5a') < 560;
    draw('c-f5a', festiveOption(S.festive_national, 'All states', narrow), narrow ? 440 : 330);
    const rows = S.spikes_by_month;
    const max = Math.max(...rows.map(r => r.spike_weeks));
    const small = chartWidth('c-f5b') < 520;
    draw('c-f5b', {
      grid: { left: 8, right: 8, top: 36, bottom: 8, containLabel: true },
      legend: { top: 0, left: 0, itemWidth: 14, itemHeight: 10, textStyle: axisText(), data: ['Fresh produce', 'Other items'] },
      xAxis: {
        type: 'category', data: rows.map(r => small ? MONTHS[parts(r.month + '-01')[1] - 1].slice(0, 1) : monthShort(r.month + '-01').replace(' 20', " '")),
        axisTick: { show: false }, axisLine: { lineStyle: { color: C.ruleStrong } }, axisLabel: Object.assign({ interval: 0 }, axisText())
      },
      yAxis: { type: 'value', minInterval: 1, axisLabel: axisText(), splitLine: splitLine() },
      tooltip: {
        trigger: 'axis', axisPointer: { type: 'shadow' },
        formatter: ps => {
          const r = rows[ps[0].dataIndex];
          return '<b>' + monthName(r.month + '-01') + '</b><br>Spike weeks: ' + r.spike_weeks + ' (' + r.fresh + ' fresh produce, ' +
            (r.spike_weeks - r.fresh) + ' other items)<br>Share of tested item-weeks that were spikes: ' + r.rate.toFixed(2) + '%';
        }
      },
      series: [
        { name: 'Fresh produce', type: 'bar', stack: 's', barMaxWidth: 34, itemStyle: { color: C.blue }, data: rows.map(r => r.fresh) },
        {
          name: 'Other items', type: 'bar', stack: 's', barMaxWidth: 34, itemStyle: { color: C.orange, borderRadius: [2, 2, 0, 0] }, data: rows.map(r => r.spike_weeks - r.fresh),
          label: { show: true, position: 'top', fontSize: small ? 10 : 12, color: C.ink, formatter: p => { const v = rows[p.dataIndex].spike_weeks; return v === max ? '{b|' + v + '}' : String(v); }, rich: { b: { fontWeight: 700, fontSize: small ? 11 : 13, color: C.ink } } }
        }
      ]
    }, 260);
  }
  function renderFindings() { renderF1(); renderF2(); renderF3(); renderF4(); renderF5(); }

  function setupReveal() {
    const items = Array.from(document.querySelectorAll('.finding'));
    if (reduceMotion || !io) return;
    document.body.classList.add('reveal-ready');
    const rio = new IntersectionObserver(entries => {
      entries.forEach(e => { if (e.isIntersecting) { e.target.classList.add('is-visible'); rio.unobserve(e.target); } });
    }, { rootMargin: '0px 0px -10% 0px', threshold: 0.05 });
    items.forEach(el => {
      // anything already above the fold appears at once
      if (el.getBoundingClientRect().top < window.innerHeight) el.classList.add('is-visible');
      else rio.observe(el);
    });
  }

  /* Explorer */
  let D, T, ITEMS, stateBasket, districts, premises, festive, monthly, weekly, priceByType, cheapest;
  let STATES, GROUPS, monthlyByItem, weeklyByItem, typeByItem, cheapestByItem, movers, FESTIVE_WEEKS, Q12;
  let defaultItem, defaultTrend;
  let explorerReady = false;

  function rowsOf(name) {
    const table = T[name];
    const cols = Object.keys(table);
    const n = table[cols[0]].length;
    const out = new Array(n);
    for (let i = 0; i < n; i++) {
      const row = {};
      for (const c of cols) row[c] = table[c][i];
      out[i] = row;
    }
    return out;
  }
  const itemLabel = code => { const it = ITEMS.get(code); return it ? it.item + (it.unit ? ' (' + it.unit + ')' : '') : String(code); };
  const itemName = code => { const it = ITEMS.get(code); return it ? it.item : String(code); };
  function codeOf(name) { for (const [code, it] of ITEMS) if (it.item === name) return code; return null; }

  function prepareData() {
    D = window.MPW_DATA;
    T = D.tables;
    ITEMS = new Map(rowsOf('items').map(r => [r.item_code, r]));
    const withItem = rows => rows.map(r => Object.assign({}, ITEMS.get(r.item_code), r));
    stateBasket = rowsOf('state_basket');
    districts = rowsOf('district_basket');
    premises = rowsOf('premise_index');
    festive = rowsOf('festive_effect');
    monthly = withItem(rowsOf('item_monthly'));
    weekly = withItem(rowsOf('weekly_spikes'));
    priceByType = rowsOf('item_price_by_state_type');
    cheapest = rowsOf('cheapest_by_item_state');
    Q12 = D.q12_state_index;
    STATES = stateBasket.map(r => r.state).sort((a, b) => a.localeCompare(b));
    GROUPS = Array.from(new Set(Array.from(ITEMS.values()).map(r => r.item_group).filter(Boolean))).sort();
    monthlyByItem = groupBy(monthly, 'item_code');
    weeklyByItem = groupBy(weekly, 'item_code');
    weeklyByItem.forEach(list => list.sort((a, b) => a.week_start.localeCompare(b.week_start)));
    monthlyByItem.forEach(list => list.sort((a, b) => a.month.localeCompare(b.month)));
    typeByItem = groupBy(priceByType, 'item_code');
    cheapestByItem = groupBy(cheapest, 'item_code');
    // festive weeks: the same calendar for every item
    const fw = new Map();
    weekly.forEach(r => { if (r.festive_period) fw.set(r.week_start, r.festive_period); });
    FESTIVE_WEEKS = [];
    Array.from(fw.keys()).sort().forEach(w => {
      const label = fw.get(w);
      const prev = FESTIVE_WEEKS[FESTIVE_WEEKS.length - 1];
      if (prev && prev.label === label && localTime(w) - localTime(prev.end) <= 7 * 864e5) prev.end = w;
      else FESTIVE_WEEKS.push({ label: label, start: w, end: w });
    });
    // Items priced by at least 30 shops in both October 2025 and September 2026 (q13's 30-shop rule).
    movers = [];
    monthlyByItem.forEach((rows, code) => {
      const first = rows.find(r => r.month === FIRST_MONTH);
      const last = rows.find(r => r.month === LAST_MONTH);
      if (first && last && last.change_since_first_month_pct !== null && first.premises >= MIN_MOVER_SHOPS && last.premises >= MIN_MOVER_SHOPS) {
        movers.push({ code: code, item: last.item, unit: last.unit, group: last.item_group, from: first.median_price_rm, to: last.median_price_rm,
          fromShops: first.premises, toShops: last.premises, change: last.change_since_first_month_pct });
      }
    });
    defaultItem = codeOf('AYAM BERSIH - STANDARD') || ITEMS.keys().next().value;
    defaultTrend = [defaultItem, codeOf('TOMATO'), codeOf('CILI AKAR MERAH')].filter(c => c !== null);
  }

  /* Filter state */
  const VIEWS = ['households', 'retail', 'cost-risk'];
  let F = null;
  function defaults() {
    return { state: ALL_STATES, type: ALL_TYPES, group: ALL_GROUPS, item: defaultItem, trend: defaultTrend.slice(),
      compare: ['W.P. Kuala Lumpur', 'Kedah'], view: 'households', mode: 'weekly' };
  }
  function readUrl() {
    const f = defaults();
    let q;
    try { q = new URLSearchParams(location.search); } catch (e) { return f; }
    const st = q.get('state');
    if (st && STATES.indexOf(st) >= 0) f.state = st;
    const ty = q.get('type');
    if (ty && SHOP_TYPES.indexOf(ty) >= 0) f.type = ty;
    const gr = q.get('group');
    if (gr && GROUPS.indexOf(gr) >= 0) f.group = gr;
    const it = Number(q.get('item'));
    if (ITEMS.has(it)) f.item = it;
    if (q.has('trend')) {
      f.trend = Array.from(new Set((q.get('trend') || '').split(',').map(Number).filter(c => ITEMS.has(c)))).slice(0, MAX_TREND);
    }
    const cmp = (q.get('compare') || '').split('|').filter(s => STATES.indexOf(s) >= 0);
    if (cmp.length === 2 && cmp[0] !== cmp[1]) f.compare = cmp;
    const view = q.get('view');
    if (VIEWS.indexOf(view) >= 0) f.view = view;
    if (q.get('measure') === 'change') f.mode = 'monthly';
    return f;
  }
  function urlQuery() {
    const d = defaults();
    const q = new URLSearchParams();
    if (F.state !== d.state) q.set('state', F.state);
    if (F.type !== d.type) q.set('type', F.type);
    if (F.group !== d.group) q.set('group', F.group);
    if (F.item !== d.item) q.set('item', String(F.item));
    if (F.trend.join(',') !== d.trend.join(',')) q.set('trend', F.trend.join(','));
    if (F.compare.join('|') !== d.compare.join('|')) q.set('compare', F.compare.join('|'));
    if (F.view !== d.view) q.set('view', F.view);
    if (F.mode !== d.mode) q.set('measure', 'change');
    return q.toString();
  }
  function writeUrl() {
    const qs = urlQuery();
    try { history.replaceState(null, '', location.pathname + (qs ? '?' + qs : '') + location.hash); } catch (e) { /* some file:// setups block this */ }
  }
  function hasUrlState() {
    try { const q = new URLSearchParams(location.search); return ['state', 'type', 'group', 'item', 'trend', 'compare', 'view', 'measure'].some(k => q.has(k)); } catch (e) { return false; }
  }

  function setFilter(patch) {
    const before = Object.assign({}, F);
    Object.assign(F, patch);
    if (patch.state && patch.state !== ALL_STATES && patch.state !== before.state && !patch.compare) {
      // the compare tool follows the chosen state as its first state
      if (F.compare[1] === patch.state) F.compare = [patch.state, F.compare[0]];
      else F.compare = [patch.state, F.compare[1]];
    }
    syncControls();
    writeUrl();
    updateAll();
  }

  /* Controls */
  function fillSelect(id, values, selected, labels) {
    const el = $(id);
    el.innerHTML = values.map((v, i) => '<option value="' + esc(v) + '"' + (v === selected ? ' selected' : '') + '>' + esc(labels ? labels[i] : v) + '</option>').join('');
  }
  function syncControls() {
    $('f-state').value = F.state;
    $('f-type').value = F.type;
    $('f-group').value = F.group;
    $('f-state').classList.toggle('is-active', F.state !== ALL_STATES);
    $('f-type').classList.toggle('is-active', F.type !== ALL_TYPES);
    $('f-group').classList.toggle('is-active', F.group !== ALL_GROUPS);
    $('cmp-a').value = F.compare[0];
    $('cmp-b').value = F.compare[1];
    combos.forEach(c => c.refresh());
    $('trend-weekly').setAttribute('aria-checked', F.mode === 'weekly' ? 'true' : 'false');
    $('trend-monthly').setAttribute('aria-checked', F.mode === 'monthly' ? 'true' : 'false');
    if (activeView !== F.view) showTab(F.view, false);
  }

  // Accessible item search: a text box with a list of matches (ARIA combobox pattern).
  const combos = [];
  let comboCount = 0;
  function makeCombo(container, opts) {
    const n = ++comboCount;
    const inputId = opts.id;
    const listId = inputId + '-list';
    container.innerHTML = '<label for="' + inputId + '">' + esc(opts.label) + '</label>' +
      '<div class="combo"><input type="text" class="combo-input" id="' + inputId + '" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="' + listId + '" autocomplete="off" spellcheck="false">' +
      '<ul class="combo-list" id="' + listId + '" role="listbox" aria-label="' + esc(opts.label) + ' results" hidden></ul></div>';
    const input = container.querySelector('input');
    const list = container.querySelector('ul');
    let matches = [];
    let active = -1;
    let open = false;
    function pool() {
      return opts.codes().map(c => ({ code: c, label: itemLabel(c), search: itemLabel(c).toUpperCase() }));
    }
    function shownValue() { const c = opts.current ? opts.current() : null; return c === null || c === undefined ? '' : itemLabel(c); }
    function refresh() {
      if (document.activeElement !== input) input.value = shownValue();
      input.placeholder = opts.placeholder();
      input.disabled = !!(opts.disabled && opts.disabled());
    }
    function render() {
      const words = input.value.trim().toUpperCase().split(/\s+/).filter(Boolean);
      const first = words.join(' ');
      const all = pool();
      matches = all.filter(it => words.every(w => it.search.indexOf(w) >= 0))
        .sort((a, b) => (b.search.startsWith(first) - a.search.startsWith(first)) || a.label.localeCompare(b.label));
      const shown = matches.slice(0, 60);
      list.innerHTML = shown.length ? shown.map((it, i) => '<li role="option" id="' + inputId + '-o' + i + '" data-code="' + it.code + '" aria-selected="' + (i === active) + '">' +
        esc(it.label) + '<small>' + esc(ITEMS.get(it.code).item_group || '') + '</small></li>').join('') +
        (matches.length > shown.length ? '<li class="combo-empty" role="presentation">' + (matches.length - shown.length) + ' more; type more of the name</li>' : '')
        : '<li class="combo-empty" role="presentation">No item matches "' + esc(input.value.trim()) + '"</li>';
      if (active >= 0) input.setAttribute('aria-activedescendant', inputId + '-o' + active); else input.removeAttribute('aria-activedescendant');
    }
    function show() { open = true; list.hidden = false; input.setAttribute('aria-expanded', 'true'); render(); }
    function hide() { open = false; list.hidden = true; active = -1; input.setAttribute('aria-expanded', 'false'); input.removeAttribute('aria-activedescendant'); }
    function pick(code) {
      hide();
      opts.onPick(code);
      input.value = opts.clearAfter ? '' : itemLabel(code);
      if (!opts.clearAfter) input.select();
    }
    input.addEventListener('focus', () => { if (!opts.clearAfter) input.select(); });
    input.addEventListener('input', () => { active = -1; show(); });
    input.addEventListener('keydown', e => {
      if (e.key === 'ArrowDown') { e.preventDefault(); if (!open) show(); active = Math.min(active + 1, Math.min(matches.length, 60) - 1); render(); scrollActive(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); active = Math.max(active - 1, 0); render(); scrollActive(); }
      else if (e.key === 'Enter') {
        if (!open && !input.value.trim()) return;
        e.preventDefault();
        if (!open) render();
        const m = matches[active >= 0 ? active : 0];
        if (m) pick(m.code);
      } else if (e.key === 'Escape') { if (open) { e.preventDefault(); hide(); input.value = opts.clearAfter ? '' : shownValue(); } }
    });
    function scrollActive() { const el = $(inputId + '-o' + active); if (el) el.scrollIntoView({ block: 'nearest' }); }
    list.addEventListener('mousedown', e => e.preventDefault());
    list.addEventListener('click', e => { const li = e.target.closest('li[data-code]'); if (li) pick(Number(li.dataset.code)); });
    input.addEventListener('blur', () => { setTimeout(() => { hide(); refresh(); }, 120); });
    const api = { refresh: refresh, input: input, n: n };
    combos.push(api);
    refresh();
    return api;
  }
  const groupItems = codes => F.group === ALL_GROUPS ? codes : codes.filter(c => (ITEMS.get(c) || {}).item_group === F.group);

  function setupControls() {
    fillSelect('f-state', [ALL_STATES].concat(STATES), F.state);
    fillSelect('f-type', [ALL_TYPES].concat(SHOP_TYPES), F.type);
    fillSelect('f-group', [ALL_GROUPS].concat(GROUPS), F.group);
    fillSelect('cmp-a', STATES, F.compare[0]);
    fillSelect('cmp-b', STATES, F.compare[1]);
    $('f-state').addEventListener('change', e => setFilter({ state: e.target.value }));
    $('f-type').addEventListener('change', e => setFilter({ type: e.target.value }));
    $('f-group').addEventListener('change', e => setFilter({ group: e.target.value }));
    $('cmp-a').addEventListener('change', e => {
      const a = e.target.value;
      setFilter({ compare: a === F.compare[1] ? [a, F.compare[0]] : [a, F.compare[1]] });
    });
    $('cmp-b').addEventListener('change', e => {
      const b = e.target.value;
      setFilter({ compare: b === F.compare[0] ? [F.compare[1], b] : [F.compare[0], b] });
    });
    $('cmp-swap').addEventListener('click', () => setFilter({ compare: [F.compare[1], F.compare[0]] }));
    $('btn-reset').addEventListener('click', () => { F = defaults(); syncControls(); writeUrl(); updateAll(); status('Filters reset'); });
    $('btn-copy').addEventListener('click', copyLink);
    const allCodes = Array.from(ITEMS.keys());
    makeCombo($('combo-global'), {
      id: 'item-search', label: 'Item', codes: () => groupItems(allCodes),
      current: () => F.item, placeholder: () => 'Search items, for example TELUR', onPick: c => setFilter({ item: c })
    });
    makeCombo($('combo-cheap'), {
      id: 'cheap-search', label: 'Item for this tool', codes: () => groupItems(Array.from(cheapestByItem.keys())),
      current: () => F.item, placeholder: () => 'Search items', onPick: c => setFilter({ item: c })
    });
    makeCombo($('combo-trend'), {
      id: 'trend-search', label: 'Add an item', codes: () => groupItems(Array.from(monthlyByItem.keys())).filter(c => F.trend.indexOf(c) < 0),
      current: () => null, clearAfter: true,
      placeholder: () => F.trend.length >= MAX_TREND ? 'Up to 4 items: remove one to add another' : 'Search items to add',
      disabled: () => F.trend.length >= MAX_TREND,
      onPick: c => { if (F.trend.length < MAX_TREND && F.trend.indexOf(c) < 0) setFilter({ trend: F.trend.concat([c]) }); }
    });
    $('trend-chips').addEventListener('click', e => {
      const b = e.target.closest('button[data-remove]');
      if (!b) return;
      const code = Number(b.dataset.remove);
      setFilter({ trend: F.trend.filter(c => c !== code) });
      const next = document.querySelector('#trend-chips button[data-remove]') || $('trend-search');
      next.focus();
    });
    $('trend-weekly').addEventListener('click', () => setFilter({ mode: 'weekly' }));
    $('trend-monthly').addEventListener('click', () => setFilter({ mode: 'monthly' }));
    $('trend-weekly').closest('.segmented').addEventListener('keydown', e => {
      if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].indexOf(e.key) < 0) return;
      e.preventDefault();
      const mode = F.mode === 'weekly' ? 'monthly' : 'weekly';
      setFilter({ mode: mode });
      $(mode === 'weekly' ? 'trend-weekly' : 'trend-monthly').focus();
    });
    setupTabs();
  }
  function status(msg) {
    const el = $('filter-status');
    el.textContent = msg;
    clearTimeout(status.t);
    status.t = setTimeout(() => { el.textContent = ''; }, 2500);
  }
  function copyLink() {
    const url = location.href.split('#')[0] + '#explore';
    const done = () => status('Link copied');
    const fallback = () => {
      const ta = document.createElement('textarea');
      ta.value = url; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.opacity = '0';
      document.body.appendChild(ta); ta.select();
      let ok = false;
      try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
      ta.remove();
      status(ok ? 'Link copied' : 'Copy the address bar to share this view');
    };
    if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(url).then(done, fallback);
    else fallback();
  }

  /* Map views */
  function mapBase(id) {
    markerNarrow = chartWidth(id) < 640;
    return {
      geo: {
        map: 'MY', roam: false, left: markerNarrow ? 48 : 150, right: 12, top: 24, bottom: 64, silent: false, selectedMode: false,
        itemStyle: { borderColor: C.surface, borderWidth: 0.8 },
        emphasis: { label: { show: false }, itemStyle: { borderColor: C.ink, borderWidth: 1.5 } },
        label: { show: false }
      },
      series: []
    };
  }
  function regionsFor(colorOf, selected) {
    return STATES.map(s => {
      const col = colorOf(s);
      return {
        name: s,
        itemStyle: { areaColor: col, borderColor: s === selected ? C.ink : C.surface, borderWidth: s === selected ? 2 : 0.8 },
        emphasis: { itemStyle: { areaColor: col, borderColor: C.ink, borderWidth: 2 } }
      };
    });
  }
  let markerNarrow = false;
  const FT_NARROW = { 'W.P. Kuala Lumpur': 'top', 'W.P. Putrajaya': 'bottom', 'W.P. Labuan': 'top' };
  function markerSeries(colorOf, labelOf, selected) {
    const names = Object.keys(FT_MARKERS);
    return [
      {
        type: 'lines', coordinateSystem: 'geo', silent: true, z: 3, polyline: false,
        lineStyle: { color: C.muted, width: 1, opacity: 0.8 },
        data: names.map(n => ({ coords: [[FT_MARKERS[n][0], FT_MARKERS[n][1]], [FT_MARKERS[n][2], FT_MARKERS[n][3]]] }))
      },
      {
        type: 'scatter', coordinateSystem: 'geo', z: 4, cursor: 'pointer',
        data: names.map(n => ({
          name: n, value: [FT_MARKERS[n][0], FT_MARKERS[n][1]],
          symbolSize: n === selected ? 22 : 16,
          itemStyle: { color: colorOf(n), borderColor: n === selected ? C.ink : C.muted, borderWidth: n === selected ? 2.5 : 1 },
          label: { show: true, position: markerNarrow ? FT_NARROW[n] : FT_MARKERS[n][4], distance: 6,
            backgroundColor: C.surface, padding: [2, 5], borderRadius: 4, borderColor: C.rule, borderWidth: 1, color: C.ink, fontSize: 11.5, fontWeight: n === selected ? 700 : 500, formatter: labelOf(n) }
        }))
      }
    ];
  }
  // Colour legend drawn inside the chart, so it is part of the PNG download.
  function legendGraphic(stops, leftLabel, rightLabel, title) {
    const font = '12px Inter, system-ui, sans-serif';
    return [{
      type: 'group', left: 0, bottom: 0,
      children: [
        { type: 'text', x: 0, y: 0, style: { text: title, fill: C.muted, font: font } },
        { type: 'rect', x: 0, y: 20, shape: { width: 176, height: 10, r: 5 },
          style: { fill: new echarts.graphic.LinearGradient(0, 0, 1, 0, stops.map((c, i) => ({ offset: i / (stops.length - 1), color: c }))) } },
        { type: 'text', x: 0, y: 36, style: { text: leftLabel, fill: C.muted, font: font } },
        { type: 'text', x: 176, y: 36, style: { text: rightLabel, fill: C.muted, font: font, align: 'right' } }
      ]
    }];
  }

  function updateMap() {
    const byType = F.type !== ALL_TYPES;
    const basket = new Map(stateBasket.map(r => [r.state, r]));
    const ranked = stateBasket.slice().sort((a, b) => b.basket_index - a.basket_index);
    const rank = s => ranked.findIndex(r => r.state === s) + 1;
    const valueOf = s => byType ? Q12[s][F.type] : basket.get(s).basket_index;
    const span = byType ? 24 : 6;
    const colorOf = s => divColor(valueOf(s), span);
    const sel = F.state === ALL_STATES ? null : F.state;
    if (!byType) {
      const top = ranked[0], low = ranked[ranked.length - 1];
      setText('h-map', sel
        ? sel + "'s basket index is " + basket.get(sel).basket_index.toFixed(1) + ', ' + (rank(sel) === 1 ? 'the dearest of 16 states' : rank(sel) === 16 ? 'the cheapest of 16 states' : 'number ' + rank(sel) + ' of 16 from the dearest')
        : top.state + ' has the dearest basket (' + top.basket_index.toFixed(1) + '), ' + low.state + ' the cheapest (' + low.basket_index.toFixed(1) + ')');
      setText('s-map', 'Basket index by state, September 2026: the cost of the same 265-item basket, 100 = national. Click a state to filter.');
      setText('src-map', 'Source: state_basket.csv (q09). Boundaries: DOSM, simplified.');
    } else {
      const vals = STATES.map(s => ({ state: s, v: valueOf(s) })).filter(x => x.v !== null && x.v !== undefined);
      const hi = extremes(vals, x => x.v, -1), lo = extremes(vals, x => x.v, 1);
      setText('h-map', sel
        ? (valueOf(sel) === null ? sel + ' has no ' + plural(F.type) + ' in the data'
          : cap(plural(F.type)) + ' in ' + sel + ' average ' + valueOf(sel).toFixed(1) + '; the range across states is ' + lo.value.toFixed(1) + ' to ' + hi.value.toFixed(1))
        : cap(plural(F.type)) + ' are dearest in ' + joinAnd(hi.rows.map(x => x.state)) + ' (' + hi.value.toFixed(1) + ') and cheapest in ' + joinAnd(lo.rows.map(x => x.state)) + ' (' + lo.value.toFixed(1) + ')');
      setText('s-map', "Average " + F.type.toLowerCase() + "'s price index by state, September 2026. 100 = national median of the same items. Click a state to filter.");
      setText('src-map', 'Source: premise_index.csv and q12. Boundaries: DOSM, simplified.');
    }
    const opt = mapBase('c-map');
    opt.geo.regions = regionsFor(colorOf, sel);
    const fmt = v => v === null || v === undefined ? 'no shops' : v.toFixed(1);
    opt.series.push({
      type: 'map', geoIndex: 0, name: 'states',
      data: STATES.map(s => ({ name: s, value: valueOf(s) }))
    });
    opt.series = opt.series.concat(markerSeries(colorOf, n => markerName(n) + ' ' + fmt(valueOf(n)), sel));
    opt.tooltip = {
      trigger: 'item',
      formatter: p => {
        const s = p.name;
        if (!basket.has(s)) return '';
        const b = basket.get(s);
        let html = '<b>' + esc(s) + '</b><br>Basket index: ' + b.basket_index.toFixed(1) + ' (rank ' + rank(s) + ' of 16, 1 = dearest)' +
          '<br>Basket cost: ' + rm(b.basket_cost_rm);
        if (byType) html += '<br>Average ' + esc(F.type.toLowerCase()) + "'s price index: " + fmt(valueOf(s));
        return html + '<br><span style="color:' + C.muted + '">Click to ' + (s === sel ? 'clear the state filter' : 'filter by this state') + '</span>';
      }
    };
    const lo = 100 - span, hi = 100 + span;
    opt.graphic = legendGraphic([C.blue, C.neutral, C.orange], 'Cheaper ' + lo, 'Dearer ' + hi, byType ? 'Average shop index (100 = national)' : 'Basket index (100 = national)');
    draw('c-map', opt);
    srTable('t-map', byType ? 'Average ' + F.type.toLowerCase() + "'s price index by state" : 'Basket index by state',
      ['State', byType ? 'Index' : 'Basket index', 'Basket cost (RM)'],
      STATES.map(s => [s, fmt(valueOf(s)), nf2.format(basket.get(s).basket_cost_rm)]));
  }
  function onMapClick(p) {
    const s = p.name;
    if (STATES.indexOf(s) < 0) return;
    setFilter({ state: F.state === s ? ALL_STATES : s });
  }

  function updateProfile() {
    const sel = F.state;
    const stats = [];
    const stat = (label, value, note) => stats.push('<div><dt>' + esc(label) + '</dt><dd>' + esc(value) + (note ? '<small>' + esc(note) + '</small>' : '') + '</dd></div>');
    const ranked = stateBasket.slice().sort((a, b) => b.basket_index - a.basket_index);
    let typeVals;
    if (sel === ALL_STATES) {
      const top = ranked[0], low = ranked[ranked.length - 1];
      setText('h-profile', 'Malaysia');
      setText('s-profile', 'All 16 states. Choose a state on the map, or in the filters, to see its profile.');
      stat('Dearest basket', rm(top.basket_cost_rm), top.state);
      stat('Cheapest basket', rm(low.basket_cost_rm), low.state);
      const gap = roundTo((top.basket_cost_rm / low.basket_cost_rm - 1) * 100, 1);
      stat('Gap', gap.toFixed(1) + '%', rm(roundTo(top.basket_cost_rm - low.basket_cost_rm, 2)) + ' more');
      stat('Shops with a price index', nf0.format(premises.length), 'September 2026');
      typeVals = SHOP_TYPES.map(t => ({ type: t, v: S.q12_type_index[t] }));
      setText('h-profile-chart', "Average shop's price index by shop type, all states");
    } else {
      const b = stateBasket.find(r => r.state === sel);
      const rank = ranked.findIndex(r => r.state === sel) + 1;
      const ds = districts.filter(r => r.state === sel);
      const scored = ds.filter(r => r.enough_items_to_score).sort((a, c) => a.basket_index - c.basket_index);
      setText('h-profile', sel);
      setText('s-profile', 'Number ' + rank + ' of 16 by basket cost, from the dearest.');
      stat('Basket cost', rm(b.basket_cost_rm), b.basket_items + ' items, September 2026');
      stat('Basket index', b.basket_index.toFixed(1), '100 = national');
      stat('Districts scored', scored.length + ' of ' + ds.length, scored.length >= 2 ? 'index ' + scored[0].basket_index.toFixed(1) + ' to ' + scored[scored.length - 1].basket_index.toFixed(1) : 'too few items priced elsewhere');
      stat('Shops with a price index', nf0.format(premises.filter(r => r.state === sel).length), 'September 2026');
      typeVals = SHOP_TYPES.map(t => ({ type: t, v: Q12[sel][t] }));
      setText('h-profile-chart', "Average shop's price index by shop type in " + sel);
    }
    $('profile-stats').innerHTML = stats.join('');
    draw('c-profile', Object.assign(indexBarOption(typeVals.map(x => x.type), typeVals.map(x => x.v), {
      span: 12, xName: '',
      itemFor: i => {
        const x = typeVals[i];
        if (x.v === null || x.v === undefined) return { emptyLabel: 'no shops' };
        return F.type !== ALL_TYPES && x.type !== F.type ? { dim: true } : { bold: F.type === x.type };
      },
      tooltip: p => {
        const x = typeVals[p.dataIndex];
        return '<b>' + esc(x.type) + '</b>, ' + esc(placeName(sel)) + '<br>' + (x.v === null || x.v === undefined ? 'No shops of this type' : "Average shop's price index: " + x.v.toFixed(1));
      }
    }), { grid: { left: 4, right: 40, top: 4, bottom: 8, containLabel: true } }));
  }

  function updateHeat() {
    const rows = [ALL_STATES].concat(Object.keys(Q12).sort((a, b) => Q12[b]['All shop types'] - Q12[a]['All shop types']));
    const val = (s, t) => s === ALL_STATES ? S.q12_type_index[t] : Q12[s][t];
    const narrow = chartWidth('c-heat') < 640;
    const data = [];
    rows.forEach((s, y) => SHOP_TYPES.forEach((t, x) => {
      const v = val(s, t);
      const col = divColor(v, 24);
      const on = (F.state === ALL_STATES || F.state === s) && (F.type === ALL_TYPES || F.type === t);
      const exact = F.state === s && F.type === t;
      data.push({
        value: [x, y, v === null || v === undefined ? 0 : v], empty: v === null || v === undefined,
        itemStyle: { color: on ? col : dimColor(col), borderColor: exact ? C.ink : C.surface, borderWidth: exact ? 3 : 2 },
        label: { color: on ? textOn(col) : C.muted, fontWeight: (F.state === s || F.type === t) ? 700 : 500 }
      });
    }));
    // title: which shop type is dearest and cheapest in the most states (printed q12 values)
    if (F.state === ALL_STATES) {
      const dear = {}, cheap = {};
      Object.keys(Q12).forEach(s => {
        const vals = SHOP_TYPES.map(t => ({ t: t, v: Q12[s][t] })).filter(x => x.v !== null);
        extremes(vals, x => x.v, -1).rows.forEach(x => { dear[x.t] = (dear[x.t] || 0) + 1; });
        extremes(vals, x => x.v, 1).rows.forEach(x => { cheap[x.t] = (cheap[x.t] || 0) + 1; });
      });
      const topD = Object.keys(dear).sort((a, b) => dear[b] - dear[a])[0];
      const topC = Object.keys(cheap).sort((a, b) => cheap[b] - cheap[a])[0];
      setText('h-heat', cap(plural(topD)) + ' are the dearest shop type in ' + dear[topD] + ' of 16 states; ' + plural(topC) + ' are the cheapest in ' + cheap[topC]);
    } else {
      const vals = SHOP_TYPES.map(t => ({ t: t, v: Q12[F.state][t] })).filter(x => x.v !== null);
      const lo = extremes(vals, x => x.v, 1), hi = extremes(vals, x => x.v, -1);
      setText('h-heat', 'In ' + F.state + ', ' + joinAnd(lo.rows.map(x => plural(x.t))) + ' average ' + lo.value.toFixed(1) + ' and ' + joinAnd(hi.rows.map(x => plural(x.t))) + ' ' + hi.value.toFixed(1));
    }
    const typeLabel = t => narrow ? { Hypermarket: 'Hyper', Supermarket: 'Super', 'Mini market': 'Mini', 'Sundry shop': 'Sundry', 'Wet market': 'Wet' }[t] : t;
    draw('c-heat', {
      grid: { left: 8, right: 8, top: 36, bottom: 8, containLabel: true },
      xAxis: {
        type: 'category', position: 'top', data: SHOP_TYPES.map(typeLabel), axisTick: { show: false }, axisLine: { show: false }, splitArea: { show: false },
        axisLabel: Object.assign({}, axisText(), { color: C.ink, fontWeight: 600, interval: 0, formatter: (v, i) => SHOP_TYPES[i] === F.type ? '{b|' + v + '}' : v, rich: { b: { fontWeight: 800, color: C.blueInk, fontSize: 12 } } })
      },
      yAxis: {
        type: 'category', data: rows.map(shortState), inverse: true, axisTick: { show: false }, axisLine: { show: false },
        axisLabel: Object.assign({}, axisText(), { color: C.ink, formatter: (v, i) => rows[i] === ALL_STATES ? '{a|' + v + '}' : rows[i] === F.state ? '{b|' + v + '}' : v, rich: { b: { fontWeight: 800, color: C.blueInk, fontSize: 12 }, a: { fontWeight: 700, color: C.ink, fontSize: 12 } } })
      },
      tooltip: {
        trigger: 'item',
        formatter: p => {
          const s = rows[p.value[1]], t = SHOP_TYPES[p.value[0]], v = val(s, t);
          const n = s === ALL_STATES ? premises.filter(r => r.premise_type === t).length : premises.filter(r => r.state === s && r.premise_type === t).length;
          return '<b>' + esc(t) + ', ' + esc(placeName(s)) + '</b><br>' + (v === null || v === undefined ? 'No shops of this type' : "Average shop's price index: " + v.toFixed(1) + ' (100 = national median)<br>Shops: ' + nf0.format(n)) +
            '<br><span style="color:' + C.muted + '">Click to filter</span>';
        }
      },
      series: [{
        type: 'heatmap', data: data, cursor: 'pointer',
        label: { show: true, fontSize: narrow ? 11 : 12.5, formatter: p => p.data.empty ? 'no shops' : Number(p.value[2]).toFixed(1) },
        emphasis: { itemStyle: { borderColor: C.ink, borderWidth: 2 } }
      }]
    }, rows.length * (narrow ? 34 : 32) + 56);
    srTable('t-heat', "Average shop's price index by state and shop type (q12)", ['State'].concat(SHOP_TYPES),
      rows.map(s => [s].concat(SHOP_TYPES.map(t => { const v = val(s, t); return v === null || v === undefined ? '' : v.toFixed(1); }))));
  }
  function onHeatClick(p) {
    const rows = [ALL_STATES].concat(Object.keys(Q12).sort((a, b) => Q12[b]['All shop types'] - Q12[a]['All shop types']));
    const s = rows[p.value[1]], t = SHOP_TYPES[p.value[0]];
    const same = F.state === s && F.type === t;
    setFilter(same ? { state: ALL_STATES, type: ALL_TYPES } : { state: s, type: t });
  }

  /* Tool: cheapest */
  function updateCheapest() {
    const code = F.item;
    const name = itemLabel(code);
    const rows = (cheapestByItem.get(code) || []).slice().sort((a, b) => a.lowest_price_rm - b.lowest_price_rm || a.state.localeCompare(b.state));
    if (!rows.length) {
      setText('h-cheap-tool', name + ': no shop price in September 2026');
      showEmpty('c-cheap-map', 'This item has no September 2026 prices in cheapest_by_item_state.csv. Choose another item.', 360);
      $('t-cheap-tool').innerHTML = '';
      return;
    }
    const best = extremes(rows, r => r.lowest_price_rm, 1);
    const national = rows[0].national_median_rm;
    setText('h-cheap-tool', best.rows.length === 1
      ? name + ' was cheapest in ' + best.rows[0].state + ': ' + rm(best.value) + ', against a national median of ' + rm(national)
      : name + ' was cheapest, at ' + rm(best.value) + ', in ' + best.rows.length + ' states; the national median was ' + rm(national));
    const byState = new Map(rows.map(r => [r.state, r]));
    const lo = rows[0].lowest_price_rm, hi = rows[rows.length - 1].lowest_price_rm;
    const colorOf = s => { const r = byState.get(s); return r ? seqColor(hi === lo ? 1 : (hi - r.lowest_price_rm) / (hi - lo)) : C.nodata; };
    const sel = F.state === ALL_STATES ? null : F.state;
    const opt = mapBase('c-cheap-map');
    opt.geo.regions = regionsFor(colorOf, sel);
    opt.series.push({ type: 'map', geoIndex: 0, data: STATES.map(s => ({ name: s, value: byState.has(s) ? byState.get(s).lowest_price_rm : null })) });
    opt.series = opt.series.concat(markerSeries(colorOf, n => markerName(n) + (byState.has(n) ? ' ' + rm(byState.get(n).lowest_price_rm) : ''), sel));
    opt.tooltip = {
      trigger: 'item',
      formatter: p => {
        const r = byState.get(p.name);
        if (!r) return STATES.indexOf(p.name) >= 0 ? '<b>' + esc(p.name) + '</b><br>No shop priced this item' : '';
        return '<b>' + esc(r.state) + '</b><br>' + esc(name) + '<br>Lowest price: ' + rm(r.lowest_price_rm) +
          '<br>Shops at this price: ' + r.shops_at_lowest_price + ' of ' + r.shops_compared +
          '<br>Example shop: ' + esc(r.example_shop) + ', ' + esc(r.example_shop_type) + ', ' + esc(r.example_shop_district) +
          '<br>National median: ' + rm(r.national_median_rm);
      }
    };
    opt.graphic = legendGraphic([seqColor(0), seqColor(0.5), seqColor(1)], rm(hi), rm(lo), 'Lowest price in the state');
    draw('c-cheap-map', opt, $('c-cheap-map').clientWidth < 500 ? 300 : 440);
    $('t-cheap-tool').innerHTML = '<caption class="sr-only">Lowest price of ' + esc(name) + ' in each state, September 2026</caption>' +
      '<thead><tr><th scope="col">State and example shop</th><th scope="col" class="num">Lowest price</th><th scope="col" class="num">Shops at this price</th></tr></thead><tbody>' +
      rows.map(r => '<tr class="' + (r.state === F.state ? 'is-chosen ' : '') + (r.lowest_price_rm === best.value ? 'is-best' : '') + '"><td><span class="cell-main">' + esc(r.state) +
        '</span><span class="cell-meta">Example shop: ' + esc(r.example_shop + ', ' + r.example_shop_type + ', ' + r.example_shop_district) + '</span></td>' +
        '<td class="num">' + rm(r.lowest_price_rm) + '</td><td class="num">' + r.shops_at_lowest_price + ' of ' + r.shops_compared + '</td></tr>').join('') + '</tbody>';
  }

  /* Tool: compare */
  function updateCompare() {
    const [a, b] = F.compare;
    const ranked = stateBasket.slice().sort((x, y) => y.basket_index - x.basket_index);
    const info = s => {
      const r = stateBasket.find(x => x.state === s);
      const ds = districts.filter(x => x.state === s);
      const scored = ds.filter(x => x.enough_items_to_score).sort((x, y) => x.basket_index - y.basket_index);
      return { s: s, r: r, rank: ranked.findIndex(x => x.state === s) + 1, ds: ds, scored: scored, shops: premises.filter(x => x.state === s).length };
    };
    const A = info(a), B = info(b);
    const dearer = A.r.basket_cost_rm >= B.r.basket_cost_rm ? A : B;
    const cheaper = dearer === A ? B : A;
    const gap = roundTo((dearer.r.basket_cost_rm / cheaper.r.basket_cost_rm - 1) * 100, 1);
    const diff = roundTo(dearer.r.basket_cost_rm - cheaper.r.basket_cost_rm, 2);
    setText('h-compare', A.r.basket_cost_rm === B.r.basket_cost_rm ? a + ' and ' + b + ' have the same basket cost'
      : 'The basket costs ' + gap.toFixed(1) + '% more in ' + dearer.s + ' than in ' + cheaper.s + ': ' + rm(diff) + ' more');
    const col = (X, cls) => {
      const range = X.scored.length >= 2 ? X.scored[0].basket_index.toFixed(1) + ' (' + X.scored[0].district + ') to ' + X.scored[X.scored.length - 1].basket_index.toFixed(1) + ' (' + X.scored[X.scored.length - 1].district + ')'
        : X.scored.length === 1 ? X.scored[0].basket_index.toFixed(1) + ' (' + X.scored[0].district + ')' : 'none scored';
      const typeRows = SHOP_TYPES.map(t => '<dt>' + esc(t) + ' index</dt><dd>' + (Q12[X.s][t] === null ? 'no shops' : Q12[X.s][t].toFixed(1)) + '</dd>').join('');
      return '<div class="compare-col ' + cls + '"><h4>' + esc(X.s) + '</h4><dl>' +
        '<dt>Basket cost</dt><dd>' + rm(X.r.basket_cost_rm) + '</dd>' +
        '<dt>Basket index</dt><dd>' + X.r.basket_index.toFixed(1) + '</dd>' +
        '<dt>Rank, dearest first</dt><dd>' + X.rank + ' of 16</dd>' +
        '<dt>Basket items with no local price</dt><dd>' + X.r.items_filled_with_national + ' of ' + X.r.basket_items + '</dd>' +
        '<dt>Districts scored</dt><dd>' + X.scored.length + ' of ' + X.ds.length + '</dd>' +
        '<dt>District index range</dt><dd>' + esc(range) + '</dd>' +
        '<dt>Shops with a price index</dt><dd>' + nf0.format(X.shops) + '</dd>' + typeRows + '</dl></div>';
    };
    $('compare-grid').innerHTML = col(A, 'is-a') + col(B, 'is-b');
    setText('h-compare-chart', 'Basket index of each scored district in ' + a + ' and ' + b);
    const pts = [];
    [A, B].forEach((X, yi) => X.ds.forEach(d => pts.push({ d: d, y: yi })));
    const colr = [C.blue, C.orange];
    draw('c-compare', {
      grid: { left: 8, right: 24, top: 8, bottom: 32, containLabel: true },
      xAxis: { type: 'value', scale: true, axisLabel: axisText(), splitLine: splitLine(), name: 'district basket index (100 = national)', nameLocation: 'middle', nameGap: 24, nameTextStyle: axisText() },
      yAxis: { type: 'category', data: [shortState(a), shortState(b)], inverse: true, axisTick: { show: false }, axisLine: { show: false }, axisLabel: Object.assign({}, axisText(), { color: C.ink, fontWeight: 600 }) },
      tooltip: {
        trigger: 'item',
        formatter: p => {
          const x = pts[p.dataIndex].d;
          return '<b>' + esc(x.district) + '</b>, ' + esc(x.state) + '<br>Basket index: ' + x.basket_index.toFixed(1) +
            (x.enough_items_to_score ? '' : ' (not scored: not enough items)') + '<br>Basket items priced: ' + x.basket_items_priced;
        }
      },
      series: [{
        type: 'scatter', data: pts.map(p => ({
          value: [p.d.basket_index, p.y], symbolSize: 13,
          itemStyle: p.d.enough_items_to_score ? { color: colr[p.y], opacity: 0.85, borderColor: C.surface, borderWidth: 1 } : { color: 'transparent', borderColor: C.muted, borderWidth: 1.5 }
        })),
        markLine: { silent: true, symbol: 'none', label: { show: false }, lineStyle: { color: C.muted, type: 'dashed' }, data: [{ xAxis: 100 }] }
      }]
    }, 170);
    srTable('t-compare', 'District basket index, ' + a + ' and ' + b, ['State', 'District', 'Basket index', 'Scored'],
      pts.map(p => [p.d.state, p.d.district, p.d.basket_index.toFixed(1), p.d.enough_items_to_score ? 'yes' : 'no, not enough items']));
  }

  /* Tool: trends */
  function updateTrends() {
    const codes = F.trend;
    $('trend-chips').innerHTML = codes.map((c, i) => '<li class="chip"><span class="chip-dot" style="background:' + C.series[i] + '"></span><span class="chip-name" title="' + esc(itemLabel(c)) + '">' + esc(itemLabel(c)) +
      '</span><button type="button" data-remove="' + c + '" aria-label="Remove ' + esc(itemLabel(c)) + '">&times;</button></li>').join('');
    combos.forEach(cb => cb.refresh());
    if (!codes.length) {
      setText('h-trend', 'Add up to 4 items to compare their prices');
      setText('s-trend', 'Search for an item below. Weekly prices show spike weeks and festive periods.');
      setText('n-trend', '');
      showEmpty('c-trend', 'No items chosen. Search for an item above to draw its price over the year.', 360);
      srTable('t-trend', 'Price trends', ['Item'], []);
      return;
    }
    if (F.mode === 'weekly') {
      setText('s-trend', 'Weekly national median price in RM, October 2025 to September 2026. Diamonds: spike weeks (more than 2 standard deviations and 2% above the previous 8 weeks). Shaded: the weeks before a festival.');
      const withSeries = codes.filter(c => weeklyByItem.has(c));
      const without = codes.filter(c => !weeklyByItem.has(c));
      const spikesOf = c => (weeklyByItem.get(c) || []).filter(r => r.is_spike);
      if (withSeries.length) {
        const most = extremes(withSeries.map(c => ({ c: c, n: spikesOf(c).length })), x => x.n, -1);
        setText('h-trend', withSeries.length === 1
          ? itemLabel(withSeries[0]) + ': ' + (most.value === 1 ? '1 spike week' : most.value + ' spike weeks') + ' in the year'
          : (most.rows.length === 1 ? itemLabel(most.rows[0].c) + ' had the most spike weeks of these items: ' + most.value
            : joinAnd(most.rows.map(x => itemName(x.c))) + ' had the most spike weeks of these items: ' + most.value + ' each'));
      } else {
        setText('h-trend', 'None of these items has a weekly series; switch to the change since October 2025');
      }
      setText('n-trend', without.length ? joinAnd(without.map(itemLabel)) + (without.length > 1 ? ' have' : ' has') +
        ' no weekly series: spike tests cover only items sold in enough shops every week. The change since October 2025 includes ' + (without.length > 1 ? 'them' : 'it') + '.' : '');
      const series = [];
      codes.forEach((c, i) => {
        const rows = weeklyByItem.get(c);
        if (!rows) return;
        series.push({
          name: itemName(c), type: 'line', showSymbol: false, smooth: false, data: rows.map(r => [localTime(r.week_start), r.median_price_rm]),
          lineStyle: { color: C.series[i], width: 2.25 }, itemStyle: { color: C.series[i] }, emphasis: { focus: 'series' }
        });
        series.push({
          name: itemName(c) + ' spike weeks', type: 'scatter', symbol: 'diamond', symbolSize: 12, z: 5,
          itemStyle: { color: C.series[i], borderColor: C.surface, borderWidth: 1.5 },
          data: rows.filter(r => r.is_spike).map(r => [localTime(r.week_start), r.median_price_rm]), tooltip: { show: false }
        });
      });
      if (series.length) {
        series[0].markArea = {
          silent: true, label: { show: false }, itemStyle: { color: C.dark ? 'rgba(141,188,242,0.10)' : 'rgba(42,120,214,0.08)' },
          data: FESTIVE_WEEKS.map(f => [{ xAxis: localTime(f.start) }, { xAxis: localTime(f.end) + 7 * 864e5 }])
        };
      }
      const names = withSeries.map(itemName);
      draw('c-trend', {
        grid: { left: 8, right: 24, top: 44, bottom: 8, containLabel: true },
        legend: { top: 0, left: 0, type: 'scroll', itemWidth: 16, itemHeight: 10, textStyle: axisText(), data: names },
        xAxis: {
          type: 'time', axisLine: { lineStyle: { color: C.ruleStrong } }, splitLine: { show: false },
          axisLabel: Object.assign({ hideOverlap: true, formatter: { year: '{yyyy}', month: '{MMM}', day: '{d} {MMM}' } }, axisText())
        },
        yAxis: { type: 'value', scale: true, axisLabel: Object.assign({ formatter: v => 'RM ' + v.toFixed(2) }, axisText()), splitLine: splitLine() },
        tooltip: {
          trigger: 'axis',
          formatter: ps => {
            const t = ps[0].value[0];
            const iso = new Date(t);
            const wk = iso.getFullYear() + '-' + String(iso.getMonth() + 1).padStart(2, '0') + '-' + String(iso.getDate()).padStart(2, '0');
            let html = '<b>Week of ' + dayName(wk) + '</b>';
            const fest = FESTIVE_WEEKS.find(f => wk >= f.start && wk <= f.end);
            if (fest) html += '<br>' + esc(fest.label.replace('Pre-', 'Before '));
            withSeries.forEach(c => {
              const r = weeklyByItem.get(c).find(x => x.week_start === wk);
              if (!r) return;
              const i = codes.indexOf(c);
              html += '<br><span style="display:inline-block;width:9px;height:9px;border-radius:50%;background:' + C.series[i] + ';margin-right:6px"></span>' +
                esc(itemName(c)) + ': ' + rm(r.median_price_rm) + (r.is_spike ? ' <b>(spike week)</b>' : '');
            });
            return html;
          }
        },
        series: series
      }, chartWidth('c-trend') < 600 ? 360 : 420);
      const spikeRows = [];
      withSeries.forEach(c => spikesOf(c).forEach(r => spikeRows.push([itemLabel(c), r.week_start, nf2.format(r.median_price_rm)])));
      srTable('t-trend', 'Spike weeks of the chosen items', ['Item', 'Week starting', 'Median (RM)'], spikeRows);
    } else {
      setText('s-trend', 'Change in the national median price since October 2025, by month (one price per shop). Weekly spikes are shown on the weekly view.');
      setText('n-trend', '');
      const last = codes.map(c => { const rows = monthlyByItem.get(c) || []; const r = rows[rows.length - 1]; return { c: c, v: r ? r.change_since_first_month_pct : null, m: r ? r.month : null }; }).filter(x => x.v !== null);
      if (last.length) {
        const top = extremes(last, x => x.v, -1);
        const x0 = top.rows[0];
        setText('h-trend', codes.length === 1
          ? itemLabel(x0.c) + ': ' + (x0.v === 0 ? 'no change' : (x0.v > 0 ? 'up ' : 'down ') + Math.abs(x0.v).toFixed(2) + '%') + ' from October 2025 to ' + monthName(x0.m)
          : itemName(x0.c) + ' moved up the most of these items: ' + pct(x0.v) + ' from October 2025 to ' + monthName(x0.m));
      } else setText('h-trend', 'These items have no monthly change since October 2025');
      const months = [];
      for (let i = 0; i < 12; i++) { const y = 2025 + Math.floor((9 + i) / 12); const m = (9 + i) % 12 + 1; months.push(y + '-' + String(m).padStart(2, '0') + '-01'); }
      draw('c-trend', {
        grid: { left: 8, right: 24, top: 44, bottom: 8, containLabel: true },
        legend: { top: 0, left: 0, type: 'scroll', itemWidth: 16, itemHeight: 10, textStyle: axisText(), data: codes.map(itemName) },
        xAxis: { type: 'category', data: months.map(monthShort), boundaryGap: false, axisTick: { show: false }, axisLine: { lineStyle: { color: C.ruleStrong } }, axisLabel: Object.assign({ hideOverlap: true }, axisText()) },
        yAxis: { type: 'value', axisLabel: Object.assign({ formatter: v => v + '%' }, axisText()), splitLine: splitLine(), name: 'change since October 2025', nameTextStyle: axisText() },
        tooltip: {
          trigger: 'axis',
          formatter: ps => '<b>' + monthName(months[ps[0].dataIndex]) + '</b>' + ps.map(p => {
            const c = codes[p.seriesIndex];
            const r = (monthlyByItem.get(c) || []).find(x => x.month === months[p.dataIndex]);
            return r ? '<br><span style="display:inline-block;width:9px;height:9px;border-radius:50%;background:' + C.series[p.seriesIndex] + ';margin-right:6px"></span>' +
              esc(itemName(c)) + ': ' + (r.change_since_first_month_pct === null ? 'n/a' : pct(r.change_since_first_month_pct)) + ' (' + rm(r.median_price_rm) + ')' : '';
          }).join('')
        },
        series: codes.map((c, i) => ({
          name: itemName(c), type: 'line', symbol: 'circle', symbolSize: 6, connectNulls: false,
          data: months.map(m => { const r = (monthlyByItem.get(c) || []).find(x => x.month === m); return r && r.change_since_first_month_pct !== null ? r.change_since_first_month_pct : null; }),
          lineStyle: { color: C.series[i], width: 2.25 }, itemStyle: { color: C.series[i] },
          markLine: i === 0 ? { silent: true, symbol: 'none', label: { show: false }, lineStyle: { color: C.muted, type: 'solid' }, data: [{ yAxis: 0 }] } : undefined
        }))
      }, chartWidth('c-trend') < 600 ? 360 : 420);
      srTable('t-trend', 'Change since October 2025', ['Item', 'Month', 'Change %'],
        [].concat.apply([], codes.map(c => (monthlyByItem.get(c) || []).map(r => [itemLabel(c), monthName(r.month), r.change_since_first_month_pct === null ? '' : r.change_since_first_month_pct.toFixed(2)]))));
    }
  }

  /* Stakeholder: households */
  function renderState() {
    const rows = stateBasket.slice().sort((a, b) => b.basket_index - a.basket_index || a.state.localeCompare(b.state));
    const top = rows[0], bottom = rows[rows.length - 1];
    setText('h-state', top.state + ' has the dearest basket and ' + bottom.state + ' the cheapest');
    const most = rows.reduce((m, r) => r.items_filled_with_national > m.items_filled_with_national ? r : m);
    setText('n-state', 'Read ' + most.state + ' with care: ' + most.items_filled_with_national + ' of its ' + most.basket_items +
      ' basket items use the national median, because no shop there priced them.');
    draw('c-state', indexBarOption(rows.map(r => r.state), rows.map(r => r.basket_index), {
      id: 'c-state', span: 6, xName: 'basket index (100 = national)',
      itemFor: i => F.state !== ALL_STATES && rows[i].state !== F.state ? { dim: true } : { bold: rows[i].state === F.state },
      labelFormatter: v => v === F.state ? '{b|' + v + '}' : v,
      tooltip: p => {
        const r = rows[p.dataIndex];
        return '<b>' + esc(r.state) + '</b><br>Basket index: ' + r.basket_index.toFixed(1) + '<br>Basket cost: ' + rm(r.basket_cost_rm) +
          '<br>Items filled with the national median: ' + r.items_filled_with_national + ' of ' + r.basket_items;
      }
    }), rows.length * 26 + 50);
    srTable('t-state', 'Basket index by state, September 2026', ['State', 'Basket index', 'Basket cost (RM)', 'Items filled with national median'],
      rows.map(r => [r.state, r.basket_index.toFixed(1), nf2.format(r.basket_cost_rm), r.items_filled_with_national]));
  }
  function renderDistrict() {
    const st = F.state;
    const byIndex = (a, b) => b.basket_index - a.basket_index || a.district.localeCompare(b.district);
    let rows, unscored = [];
    if (st === ALL_STATES) {
      const scored = districts.filter(r => r.enough_items_to_score).sort(byIndex);
      const hi = scored[0], lo = scored[scored.length - 1];
      setText('h-district', 'Across Malaysia, scored districts run from ' + lo.basket_index.toFixed(1) + ' in ' + lo.district + ' (' + lo.state + ') to ' +
        hi.basket_index.toFixed(1) + ' in ' + hi.district + ' (' + hi.state + ')');
      setText('s-district', 'The 8 dearest and 8 cheapest of ' + scored.length + ' scored districts, September 2026 (100 = national). Choose a state to see all its districts.');
      rows = scored.slice(0, 8).concat(scored.slice(-8));
    } else {
      const all = districts.filter(r => r.state === st);
      const scored = all.filter(r => r.enough_items_to_score).sort(byIndex);
      unscored = all.filter(r => !r.enough_items_to_score).sort(byIndex);
      rows = scored.concat(unscored);
      setText('s-district', 'Basket index by district, September 2026 (100 = national). Grey bars: not enough items priced to compare fairly.');
      if (scored.length >= 2) {
        const hi = scored[0], lo = scored[scored.length - 1];
        setText('h-district', 'In ' + st + ', the district basket index runs from ' + lo.basket_index.toFixed(1) + ' in ' + lo.district + ' to ' + hi.basket_index.toFixed(1) + ' in ' + hi.district);
      } else if (scored.length === 1) setText('h-district', 'In ' + st + ', only ' + scored[0].district + ' has enough items priced to score');
      else setText('h-district', 'In ' + st + ', no district has enough items priced to score');
      if (!rows.length) { showEmpty('c-district', 'No district rows for ' + st + ' in district_basket.csv.', 200); return; }
    }
    const label = r => st === ALL_STATES ? r.district + ', ' + shortState(r.state) : r.district;
    draw('c-district', indexBarOption(rows.map(label), rows.map(r => r.basket_index), {
      id: 'c-district', span: 12, xName: 'basket index (100 = national)', right: unscored.length ? 120 : 48,
      itemFor: i => rows[i].enough_items_to_score ? null : { item: { color: C.nodata }, labelText: 'not enough items' },
      tooltip: p => {
        const r = rows[p.dataIndex];
        return '<b>' + esc(r.district) + '</b>, ' + esc(r.state) + '<br>Basket index: ' + r.basket_index.toFixed(1) +
          (r.enough_items_to_score ? '' : ' (not scored: not enough items)') + '<br>Basket items priced: ' + r.basket_items_priced +
          '<br>Most shops pricing one item: ' + r.max_shops_per_item;
      }
    }), rows.length * 24 + 50);
    srTable('t-district', 'Basket index by district, ' + placeName(st), ['District', 'State', 'Basket index', 'Enough items to score', 'Basket items priced'],
      rows.map(r => [r.district, r.state, r.basket_index.toFixed(1), r.enough_items_to_score ? 'yes' : 'no, not enough items', r.basket_items_priced]));
  }
  function festiveRows(st) {
    const sets = ['Festive staples', 'Other items (control)'];
    const byFest = groupBy(festive, 'festival');
    const fests = Array.from(byFest.keys()).sort((a, b) => byFest.get(a)[0].festival_date.localeCompare(byFest.get(b)[0].festival_date));
    return fests.map(f => {
      const rows = byFest.get(f);
      const out = { festival: f, date: rows[0].festival_date };
      sets.forEach((s, i) => {
        const part = rows.filter(r => r.item_set === s && (st === ALL_STATES || r.state === st));
        const pairs = part.reduce((a, r) => a + r.matched_pairs, 0);
        let mean = null;
        if (pairs > 0) {
          // weighted by matched_pairs, in whole hundredths so the rounding is exact
          const hundredths = part.reduce((a, r) => a + r.matched_pairs * Math.round(r.mean_change_pct * 100), 0);
          mean = roundTo(hundredths / pairs, 0) / 100;
        }
        out[i ? 'other' : 'staples'] = { mean: mean, pairs: pairs, up: st === ALL_STATES || !part.length ? null : part[0].pct_pairs_up };
      });
      return out;
    });
  }
  function renderFestive() {
    const st = F.state;
    const rows = festiveRows(st);
    const valid = rows.filter(r => r.staples.mean !== null && r.other.mean !== null);
    const better = valid.filter(r => r.staples.mean < r.other.mean).length;
    const worse = valid.filter(r => r.staples.mean > r.other.mean).length;
    const lead = st === ALL_STATES ? 'Festive staples' : 'In ' + st + ', festive staples';
    setText('h-festive', better >= worse
      ? lead + ' rose less, or fell more, than other items before ' + better + ' of ' + valid.length + ' festivals'
      : lead + ' rose more, or fell less, than other items before ' + worse + ' of ' + valid.length + ' festivals');
    const narrow = chartWidth('c-festive') < 560;
    draw('c-festive', festiveOption(rows, placeName(st), narrow), narrow ? 460 : 340);
    srTable('t-festive', 'Festive price effect, ' + st,
      ['Festival', 'Date', 'Festive staples, mean change %', 'Other items, mean change %', 'Festive staples, matched pairs'],
      rows.map(r => [r.festival, r.date, r.staples.mean === null ? '' : r.staples.mean.toFixed(2), r.other.mean === null ? '' : r.other.mean.toFixed(2), r.staples.pairs]));
  }

  /* Stakeholder: retail */
  const retailShops = () => F.state === ALL_STATES ? premises : premises.filter(r => r.state === F.state);
  function renderType() {
    const shops = retailShops();
    const byType = groupBy(shops, 'premise_type');
    // For one state, use q12's printed table: the CSV rounds each shop's index (build_data.py checks this).
    const printed = F.state === ALL_STATES ? null : Q12[F.state];
    const rows = SHOP_TYPES.map(t => {
      const list = byType.get(t) || [];
      if (printed) return { type: t, shops: list.length, mean: list.length ? printed[t] : null };
      const tenths = list.reduce((a, r) => a + Math.round(r.price_index * 10), 0);
      return { type: t, shops: list.length, mean: list.length ? roundTo(tenths / list.length, 0) / 10 : null };
    });
    const lo = extremes(rows, r => r.mean, 1);
    const hi = extremes(rows, r => r.mean, -1);
    const where = F.state === ALL_STATES ? '' : 'In ' + F.state + ', ';
    const loNames = joinAnd(lo.rows.map(r => plural(r.type)));
    const hiNames = joinAnd(hi.rows.map(r => plural(r.type)));
    setText('h-type', (where ? where + loNames : cap(loNames)) + ' have the lowest average shop index (' + lo.value.toFixed(1) + '), ' + hiNames + ' the highest (' + hi.value.toFixed(1) + ')');
    draw('c-type', indexBarOption(rows.map(r => r.type), rows.map(r => r.mean), {
      id: 'c-type', span: 12, xName: "average shop's price index (100 = national)",
      itemFor: i => rows[i].mean === null ? { emptyLabel: 'no shops' } : F.type !== ALL_TYPES && rows[i].type !== F.type ? { dim: true } : { bold: rows[i].type === F.type },
      tooltip: p => {
        const r = rows[p.dataIndex];
        return '<b>' + esc(r.type) + '</b>, ' + esc(placeName(F.state)) + '<br>' + (r.mean === null ? 'No shops of this type' : "Average shop's price index: " + r.mean.toFixed(1) + '<br>Shops: ' + nf0.format(r.shops));
      }
    }), 280);
    srTable('t-type', "Average shop's price index by shop type, " + F.state, ['Shop type', "Average shop's price index", 'Shops'],
      rows.map(r => [r.type, r.mean === null ? '' : r.mean.toFixed(1), r.shops]));
  }
  function renderQuartile() {
    const byType = groupBy(retailShops(), 'premise_type');
    const rows = SHOP_TYPES.map(t => {
      const list = byType.get(t) || [];
      const q1 = list.filter(r => r.price_quartile_in_state === 1).length;
      const q4 = list.filter(r => r.price_quartile_in_state === 4).length;
      return { type: t, shops: list.length, q1: q1, q4: q4, s1: list.length ? roundTo(q1 / list.length * 100, 1) : null, s4: list.length ? roundTo(q4 / list.length * 100, 1) : null };
    });
    const named = rows.filter(r => r.shops >= MIN_TITLE_SHOPS);
    const top1 = extremes(named, r => r.s1, -1);
    const top4 = extremes(named, r => r.s4, -1);
    const n1 = joinAnd(top1.rows.map(r => plural(r.type)));
    const n4 = joinAnd(top4.rows.map(r => plural(r.type)));
    const where = F.state === ALL_STATES ? '' : 'In ' + F.state + ', ';
    if (!top1.rows.length || !top4.rows.length || top1.rows.some(r => top4.rows.indexOf(r) >= 0)) {
      setText('h-quartile', 'Shops in the cheapest and the dearest quarter of ' + placeName(F.state) + ', by shop type');
    } else {
      setText('h-quartile', (where ? where + n1 : cap(n1)) + ' are most often in the cheapest quarter (' + top1.value.toFixed(1) + '%), ' + n4 + ' in the dearest (' + top4.value.toFixed(1) + '%)');
    }
    const dim = (i, col) => F.type !== ALL_TYPES && rows[i].type !== F.type ? dimColor(col) : col;
    const label = { show: true, position: 'right', fontSize: 12, color: C.ink, formatter: p => p.value === null || p.value === undefined ? '' : p.value.toFixed(1) + '%' };
    draw('c-quartile', {
      grid: { left: 8, right: 52, top: 32, bottom: 36, containLabel: true },
      legend: { top: 0, left: 0, itemWidth: 14, itemHeight: 10, textStyle: axisText(), data: ['Cheapest quarter', 'Dearest quarter'] },
      xAxis: { type: 'value', min: 0, axisLabel: Object.assign({ formatter: v => v + '%' }, axisText()), splitLine: splitLine(), name: "share of the type's shops", nameLocation: 'middle', nameGap: 26, nameTextStyle: axisText() },
      yAxis: { type: 'category', data: SHOP_TYPES, inverse: true, axisTick: { show: false }, axisLine: { lineStyle: { color: C.ruleStrong } }, axisLabel: Object.assign({}, axisText(), { color: C.ink }) },
      tooltip: {
        trigger: 'axis', axisPointer: { type: 'shadow' },
        formatter: ps => {
          const r = rows[ps[0].dataIndex];
          if (!r.shops) return '<b>' + esc(r.type) + '</b><br>No shops of this type';
          return '<b>' + esc(r.type) + '</b>, ' + esc(placeName(F.state)) + '<br>Cheapest quarter: ' + r.q1 + ' of ' + r.shops + ' shops (' + r.s1.toFixed(1) + '%)' +
            '<br>Dearest quarter: ' + r.q4 + ' of ' + r.shops + ' shops (' + r.s4.toFixed(1) + '%)';
        }
      },
      series: [
        { name: 'Cheapest quarter', type: 'bar', barMaxWidth: 14, itemStyle: { color: C.blue, borderRadius: [0, 2, 2, 0] }, label: label, data: rows.map((r, i) => ({ value: r.s1, itemStyle: { color: dim(i, C.blue) } })) },
        { name: 'Dearest quarter', type: 'bar', barMaxWidth: 14, itemStyle: { color: C.orange, borderRadius: [0, 2, 2, 0] }, label: label, data: rows.map((r, i) => ({ value: r.s4, itemStyle: { color: dim(i, C.orange) } })) }
      ]
    }, 320);
    srTable('t-quartile', 'Share of shops in the cheapest and dearest quarter, ' + F.state, ['Shop type', 'Shops', 'Cheapest quarter %', 'Dearest quarter %'],
      rows.map(r => [r.type, r.shops, r.s1 === null ? '' : r.s1.toFixed(1), r.s4 === null ? '' : r.s4.toFixed(1)]));
  }
  function shopTable(id, rows, showState) {
    $(id).innerHTML = '<thead><tr><th scope="col" class="num">#</th><th scope="col">Shop, type and district</th><th scope="col" class="num">Items priced</th><th scope="col" class="num">Index</th></tr></thead><tbody>' +
      (rows.length ? rows.map((r, i) => '<tr><td class="num">' + (i + 1) + '</td><td><span class="cell-main">' + esc(r.premise) + '</span><span class="cell-meta">' +
        esc(r.premise_type + ', ' + r.district + (showState ? ', ' + r.state : '')) + '</span></td><td class="num">' + r.items_priced + '</td><td class="num">' + r.price_index.toFixed(1) + '</td></tr>').join('')
        : '<tr><td colspan="4">No shops match the filters.</td></tr>') + '</tbody>';
  }
  function renderShops() {
    let shops = retailShops();
    if (F.type !== ALL_TYPES) shops = shops.filter(r => r.premise_type === F.type);
    const place = placeName(F.state) + (F.type === ALL_TYPES ? '' : ' among ' + plural(F.type));
    const asc = shops.slice().sort((a, b) => a.price_index - b.price_index || a.premise_code - b.premise_code);
    const desc = shops.slice().sort((a, b) => b.price_index - a.price_index || a.premise_code - b.premise_code);
    const cheap = asc.slice(0, 10), dear = desc.slice(0, 10);
    setText('h-cheap', cheap.length ? cheap[0].premise + ' is the cheapest shop in ' + place + ' (' + cheap[0].price_index.toFixed(1) + ')' : 'No shops in ' + place);
    setText('h-dear', dear.length ? dear[0].premise + ' is the dearest shop in ' + place + ' (' + dear[0].price_index.toFixed(1) + ')' : 'No shops in ' + place);
    shopTable('t-cheap', cheap, F.state === ALL_STATES);
    shopTable('t-dear', dear, F.state === ALL_STATES);
  }
  function renderItemType() {
    const code = F.item;
    const name = itemLabel(code);
    const all = typeByItem.get(code) || [];
    if (!all.length) {
      setText('h-item-type', name + ': no shop prices by shop type in September 2026');
      setText('s-item-type', 'Median price by state and shop type, September 2026.');
      showEmpty('c-item-type', 'This item has no rows in item_price_by_state_type.csv. Choose another item in the filter bar.', 280);
      srTable('t-item-type', 'Median price by shop type', ['Shop type', 'Median (RM)'], []);
      return;
    }
    const national = all[0].national_median_rm;
    if (F.state === ALL_STATES) {
      const lo = extremes(all, r => r.median_price_rm, 1);
      const where = joinAnd(lo.rows.slice(0, 3).map(r => plural(r.premise_type) + ' in ' + r.state)) + (lo.rows.length > 3 ? ' and ' + (lo.rows.length - 3) + ' more' : '');
      setText('h-item-type', name + ': the lowest median, ' + rm(lo.value) + ', was at ' + where + ' (national median ' + rm(national) + ')');
      setText('s-item-type', 'Median price in each state by shop type, September 2026. Dashed line: national median. Choose a state to see its shop types as bars.');
      const states = Array.from(new Set(all.map(r => r.state))).sort((a, b) => a.localeCompare(b));
      draw('c-item-type', {
        grid: { left: 8, right: 24, top: 36, bottom: 36, containLabel: true },
        legend: { top: 0, left: 0, itemWidth: 10, itemHeight: 10, textStyle: axisText(), data: SHOP_TYPES.map(t => ({ name: t, icon: 'circle' })) },
        xAxis: { type: 'value', scale: true, axisLabel: Object.assign({ formatter: v => 'RM ' + v.toFixed(2), hideOverlap: true }, axisText()), splitLine: splitLine(), name: 'median price (RM)', nameLocation: 'middle', nameGap: 26, nameTextStyle: axisText() },
        yAxis: { type: 'category', data: states.map(shortState), inverse: true, axisTick: { show: false }, axisLine: { show: false }, axisLabel: Object.assign({}, axisText(), { color: C.ink }), splitLine: { show: true, lineStyle: { color: C.rule, type: 'dotted' } } },
        tooltip: {
          trigger: 'item',
          formatter: p => {
            const r = all.find(x => x.state === states[p.value[1]] && x.premise_type === p.seriesName);
            return r ? '<b>' + esc(r.premise_type) + ', ' + esc(r.state) + '</b><br>' + esc(name) + '<br>Median: ' + rm(r.median_price_rm) + '<br>Lowest to highest: ' + rm(r.min_price_rm) + ' to ' + rm(r.max_price_rm) + '<br>Shops: ' + r.shops + '<br>National median: ' + rm(r.national_median_rm) : '';
          }
        },
        series: SHOP_TYPES.map((t, ti) => ({
          name: t, type: 'scatter', symbolSize: 10,
          itemStyle: { color: C.types[t], opacity: F.type === ALL_TYPES || F.type === t ? 0.9 : 0.15, borderColor: C.surface, borderWidth: 1 },
          data: all.filter(r => r.premise_type === t).map(r => [r.median_price_rm, states.indexOf(r.state)]),
          markLine: ti === 0 ? { silent: true, symbol: 'none', lineStyle: { color: C.muted, type: 'dashed', width: 1.5 }, label: { show: true, position: 'end', formatter: 'National ' + rm(national), color: C.ink, fontSize: 11 }, data: [{ xAxis: national }] } : undefined
        }))
      }, states.length * 28 + 90);
      srTable('t-item-type', 'Median price by state and shop type for ' + name, ['State', 'Shop type', 'Median (RM)', 'Shops'],
        all.map(r => [r.state, r.premise_type, nf2.format(r.median_price_rm), r.shops]));
      return;
    }
    const st = F.state;
    const rows = all.filter(r => r.state === st);
    const byType = new Map(rows.map(r => [r.premise_type, r]));
    setText('s-item-type', 'Median price by shop type in ' + st + ', September 2026. Dashed line: national median.');
    if (!rows.length) {
      setText('h-item-type', name + ': no shop in ' + st + ' priced it in September 2026');
      showEmpty('c-item-type', 'No prices for this item in ' + st + ' in item_price_by_state_type.csv.', 280);
      srTable('t-item-type', 'Median price by shop type', ['Shop type', 'Median (RM)'], []);
      return;
    }
    const lo = extremes(rows, r => r.median_price_rm, 1);
    const names = joinAnd(SHOP_TYPES.filter(t => lo.rows.some(r => r.premise_type === t)).map(plural));
    setText('h-item-type', 'In ' + st + ', ' + names + ' had the lowest median for ' + name + ': ' + rm(lo.value) + ', against ' + rm(national) + ' nationally');
    const narrow = chartWidth('c-item-type') < 420;
    draw('c-item-type', {
      grid: { left: 8, right: 72, top: 24, bottom: 36, containLabel: true },
      xAxis: { type: 'value', min: 0, axisLabel: Object.assign({ formatter: v => 'RM ' + v }, axisText()), splitLine: splitLine(), name: 'median price (RM)', nameLocation: 'middle', nameGap: 26, nameTextStyle: axisText() },
      yAxis: { type: 'category', data: SHOP_TYPES, inverse: true, axisTick: { show: false }, axisLine: { lineStyle: { color: C.ruleStrong } }, axisLabel: Object.assign({}, axisText(), { color: C.ink }) },
      tooltip: {
        trigger: 'item',
        formatter: p => {
          const r = byType.get(SHOP_TYPES[p.dataIndex]);
          if (!r) return '<b>' + esc(SHOP_TYPES[p.dataIndex]) + '</b><br>No shops of this type priced it';
          return '<b>' + esc(r.premise_type) + '</b>, ' + esc(st) + '<br>' + esc(name) + '<br>Median: ' + rm(r.median_price_rm) + '<br>Lowest to highest: ' + rm(r.min_price_rm) + ' to ' + rm(r.max_price_rm) +
            '<br>Shops: ' + r.shops + '<br>National median: ' + rm(r.national_median_rm);
        }
      },
      series: [{
        type: 'bar', barMaxWidth: 20,
        data: SHOP_TYPES.map(t => byType.has(t)
          ? { value: byType.get(t).median_price_rm, itemStyle: { color: F.type === ALL_TYPES || F.type === t ? C.types[t] : dimColor(C.types[t]), borderRadius: [0, 3, 3, 0] }, label: { show: true, position: 'right', formatter: p => rm(p.value), color: C.ink, fontSize: 12 } }
          : { value: 0, label: { show: true, position: 'right', formatter: 'no shops', color: C.muted, fontSize: 12 } }),
        markLine: { silent: true, symbol: 'none', lineStyle: { color: C.ink, type: 'dashed', width: 1.5 }, label: { show: true, position: 'end', formatter: (narrow ? 'National\n' : 'National ') + rm(national), color: C.ink, fontSize: 11 }, data: [{ xAxis: national }] }
      }]
    }, 290);
    srTable('t-item-type', 'Median price by shop type for ' + name + ' in ' + st, ['Shop type', 'Median (RM)', 'Lowest (RM)', 'Highest (RM)', 'Shops'],
      SHOP_TYPES.filter(t => byType.has(t)).map(t => { const r = byType.get(t); return [t, nf2.format(r.median_price_rm), nf2.format(r.min_price_rm), nf2.format(r.max_price_rm), r.shops]; }));
  }

  /* Stakeholder: cost risk */
  function renderMonthly() {
    const code = F.item;
    const name = itemLabel(code);
    const rows = monthlyByItem.get(code) || [];
    if (!rows.length) {
      setText('h-monthly', name + ': no monthly prices');
      showEmpty('c-monthly', 'No monthly prices for this item in item_monthly.csv.', 320);
      srTable('t-monthly', 'Monthly national median price, ' + name, ['Month', 'Median (RM)'], []);
      return;
    }
    const first = rows[0], last = rows[rows.length - 1];
    const ch = last.change_since_first_month_pct;
    const span = ' from ' + monthName(first.month) + ' to ' + monthName(last.month);
    setText('h-monthly', ch === null || rows.length === 1 ? name + ': ' + monthName(first.month) + ' only'
      : ch === 0 ? name + ': no change' + span : name + ': ' + (ch > 0 ? 'up ' : 'down ') + Math.abs(ch).toFixed(2) + '%' + span);
    draw('c-monthly', {
      grid: { left: 8, right: 20, top: 16, bottom: 8, containLabel: true },
      xAxis: { type: 'category', data: rows.map(r => monthShort(r.month)), boundaryGap: false, axisLine: { lineStyle: { color: C.ruleStrong } }, axisTick: { show: false }, axisLabel: Object.assign({ hideOverlap: true }, axisText()) },
      yAxis: { type: 'value', scale: true, axisLabel: Object.assign({ formatter: v => 'RM ' + v.toFixed(2) }, axisText()), splitLine: splitLine() },
      tooltip: {
        trigger: 'axis',
        formatter: ps => {
          const r = rows[ps[0].dataIndex];
          return '<b>' + monthName(r.month) + '</b><br>' + esc(name) + '<br>National median: ' + rm(r.median_price_rm) + '<br>Shops: ' + nf0.format(r.premises) +
            (r.mom_change_pct === null ? '' : '<br>Change on previous month: ' + pct(r.mom_change_pct)) +
            (r.change_since_first_month_pct === null ? '' : '<br>Change since ' + monthName(first.month) + ': ' + pct(r.change_since_first_month_pct));
        }
      },
      series: [{
        type: 'line', data: rows.map(r => r.median_price_rm), symbol: 'circle', symbolSize: 7, lineStyle: { color: C.blue, width: 2.5 }, itemStyle: { color: C.blue },
        areaStyle: { color: C.dark ? 'rgba(79,147,230,0.12)' : 'rgba(42,120,214,0.08)' }
      }]
    }, 320);
    srTable('t-monthly', 'Monthly national median price, ' + name, ['Month', 'Median (RM)', 'Change since first month %'],
      rows.map(r => [monthName(r.month), nf2.format(r.median_price_rm), r.change_since_first_month_pct === null ? '' : r.change_since_first_month_pct.toFixed(2)]));
  }
  function renderWeekly() {
    const code = F.item;
    const name = itemLabel(code);
    const rows = weeklyByItem.get(code) || [];
    if (!rows.length) {
      setText('h-weekly', name + ': no weekly series');
      showEmpty('c-weekly', 'This item has no weekly series in weekly_spikes.csv. Spike tests only cover items sold in enough shops each week.', 320);
      srTable('t-weekly', 'Spike weeks, ' + name, ['Week starting', 'Median (RM)'], []);
      return;
    }
    const spikes = rows.filter(r => r.is_spike);
    setText('h-weekly', spikes.length === 0 ? name + ': no spike weeks in the year'
      : spikes.length === 1 ? name + ': 1 spike week, the week of ' + dayName(spikes[0].week_start) : name + ': ' + spikes.length + ' spike weeks in the year');
    const areas = [];
    rows.forEach((r, i) => {
      if (!r.festive_period) return;
      const prev = areas[areas.length - 1];
      if (prev && prev.label === r.festive_period && prev.end === i - 1) prev.end = i;
      else areas.push({ label: r.festive_period, start: i, end: i });
    });
    const WEEK = 7 * 864e5;
    draw('c-weekly', {
      grid: { left: 8, right: 20, top: 36, bottom: 8, containLabel: true },
      legend: { top: 0, left: 0, itemWidth: 16, itemHeight: 10, textStyle: axisText(), data: ['Weekly median', '8-week average', 'Spike week'] },
      xAxis: { type: 'time', axisLine: { lineStyle: { color: C.ruleStrong } }, axisLabel: Object.assign({ hideOverlap: true, formatter: { year: '{yyyy}', month: '{MMM}', day: '{d} {MMM}' } }, axisText()), splitLine: { show: false } },
      yAxis: { type: 'value', scale: true, axisLabel: Object.assign({ formatter: v => 'RM ' + v.toFixed(2) }, axisText()), splitLine: splitLine() },
      tooltip: {
        trigger: 'axis',
        formatter: ps => {
          const p = ps.find(x => x.seriesIndex === 0) || ps[0];
          const r = rows[p.dataIndex];
          return '<b>Week of ' + dayName(r.week_start) + '</b><br>' + esc(name) + '<br>Weekly median: ' + rm(r.median_price_rm) +
            (p.dataIndex < SPIKE_WINDOW ? '<br>Not tested: fewer than 8 earlier weeks' : r.rolling_8wk_mean_rm === null ? '' : '<br>Average of the previous 8 weeks: ' + rm(r.rolling_8wk_mean_rm)) +
            '<br>Shops: ' + nf0.format(r.premises) + (r.is_spike ? '<br><b>Spike week</b>' : '') + (r.festive_period ? '<br>Festive period: ' + esc(r.festive_period) : '');
        }
      },
      series: [
        {
          name: 'Weekly median', type: 'line', showSymbol: false, data: rows.map(r => [localTime(r.week_start), r.median_price_rm]),
          lineStyle: { color: C.blue, width: 2.5 }, itemStyle: { color: C.blue },
          markArea: { silent: true, itemStyle: { color: C.dark ? 'rgba(141,188,242,0.10)' : 'rgba(42,120,214,0.08)' }, data: areas.map(a => [{ xAxis: localTime(rows[a.start].week_start) }, { xAxis: localTime(rows[a.end].week_start) + WEEK }]) }
        },
        {
          // drawn only once 8 earlier weeks exist; before that the CSV averages 1 to 7 weeks
          name: '8-week average', type: 'line', showSymbol: false, data: rows.map((r, i) => [localTime(r.week_start), i < SPIKE_WINDOW ? null : r.rolling_8wk_mean_rm]),
          lineStyle: { color: C.orange, width: 1.5, type: 'dashed' }, itemStyle: { color: C.orange }
        },
        { name: 'Spike week', type: 'scatter', symbol: 'diamond', symbolSize: 12, itemStyle: { color: C.orange, borderColor: C.surface, borderWidth: 1.5 }, data: spikes.map(r => [localTime(r.week_start), r.median_price_rm]), tooltip: { show: false } }
      ]
    }, 320);
    srTable('t-weekly', 'Spike weeks, ' + name, ['Week starting', 'Median (RM)', 'Average of previous 8 weeks (RM)'],
      spikes.map(r => [r.week_start, nf2.format(r.median_price_rm), r.rolling_8wk_mean_rm === null ? '' : nf2.format(r.rolling_8wk_mean_rm)]));
  }
  function moverChart(id, list, color, verb) {
    const where = F.group === ALL_GROUPS ? '' : 'In ' + F.group.toLowerCase() + ', ';
    const hId = id === 'c-risers' ? 'h-risers' : 'h-fallers';
    const tId = id === 'c-risers' ? 't-risers' : 't-fallers';
    if (!list.length) {
      setText(hId, (where || 'Overall, ') + 'no item ' + verb);
      showEmpty(id, 'No item in this group with ' + MIN_MOVER_SHOPS + ' or more shops ' + verb + ' from October 2025 to September 2026.', 300);
      srTable(tId, 'Top 10 ' + (verb === 'rose' ? 'risers' : 'fallers'), ['Item'], []);
      return;
    }
    const top = list[0];
    setText(hId, (where ? where + top.item : top.item) + ' ' + verb + ' the most: ' + pct(top.change));
    const labelWidth = Math.max(110, Math.min(280, Math.round(chartWidth(id) * 0.42)));
    draw(id, {
      grid: { left: 8, right: 64, top: 8, bottom: 36, containLabel: true },
      xAxis: {
        type: 'value', axisLabel: Object.assign({ formatter: v => v + '%', hideOverlap: true }, axisText()), splitLine: splitLine(),
        min: verb === 'fell' ? v => Math.floor(v.min * (chartWidth(id) < 560 ? 1.6 : 1.35) / 10) * 10 : undefined,
        name: 'change in national median', nameLocation: 'middle', nameGap: 26, nameTextStyle: axisText()
      },
      yAxis: { type: 'category', data: list.map(r => r.item), inverse: true, axisTick: { show: false }, axisLine: { onZero: false, lineStyle: { color: C.ruleStrong } }, axisLabel: Object.assign({}, axisText(), { color: C.ink, width: labelWidth, overflow: 'truncate', ellipsis: '...' }) },
      tooltip: {
        trigger: 'item',
        formatter: p => {
          const r = list[p.dataIndex];
          return '<b>' + esc(r.item) + '</b>' + (r.unit ? ' (' + esc(r.unit) + ')' : '') + '<br>' + esc(r.group) + '<br>October 2025: ' + rm(r.from) + ' (' + nf0.format(r.fromShops) + ' shops)' +
            '<br>September 2026: ' + rm(r.to) + ' (' + nf0.format(r.toShops) + ' shops)<br>Change: ' + pct(r.change);
        }
      },
      series: [{
        type: 'bar', barMaxWidth: 16, itemStyle: { color: color, borderRadius: verb === 'rose' ? [0, 3, 3, 0] : [3, 0, 0, 3] },
        label: { show: true, position: verb === 'rose' ? 'right' : 'left', formatter: p => pct(p.value), color: C.ink, fontSize: 12 },
        data: list.map(r => r.change)
      }]
    }, list.length * 28 + 60);
    srTable(tId, 'Top 10 ' + (verb === 'rose' ? 'risers' : 'fallers'), ['Item', 'Group', 'October 2025 (RM)', 'September 2026 (RM)', 'Change %', 'Shops, October 2025', 'Shops, September 2026'],
      list.map(r => [r.item + (r.unit ? ' (' + r.unit + ')' : ''), r.group, nf2.format(r.from), nf2.format(r.to), r.change.toFixed(2), r.fromShops, r.toShops]));
  }
  function renderMovers() {
    const pool = F.group === ALL_GROUPS ? movers : movers.filter(r => r.group === F.group);
    const risers = pool.filter(r => r.change > 0).sort((a, b) => b.change - a.change || a.item.localeCompare(b.item)).slice(0, 10);
    const fallers = pool.filter(r => r.change < 0).sort((a, b) => a.change - b.change || a.item.localeCompare(b.item)).slice(0, 10);
    moverChart('c-risers', risers, C.orange, 'rose');
    moverChart('c-fallers', fallers, C.blue, 'fell');
  }
  function renderSpikes() {
    const months = [];
    for (let i = 0; i < 12; i++) { const y = 2025 + Math.floor((9 + i) / 12); const m = (9 + i) % 12 + 1; months.push(y + '-' + String(m).padStart(2, '0')); }
    const counts = new Map(months.map(m => [m, { fresh: 0, other: 0, tested: 0, weeks: new Set(), testedWeeks: new Set() }]));
    const inGroup = r => F.group === ALL_GROUPS || r.item_group === F.group;
    // A week is tested only from an item's 9th kept week on (8 earlier weeks, as in q23).
    weeklyByItem.forEach(list => {
      list.forEach((r, i) => {
        const c = counts.get(r.week_start.slice(0, 7));
        if (!c) return;
        c.weeks.add(r.week_start);
        if (i < SPIKE_WINDOW) return;
        c.testedWeeks.add(r.week_start);
        if (!inGroup(r)) return;
        c.tested++;
        if (r.is_spike) { if (r.item_group === 'Fresh produce') c.fresh++; else c.other++; }
      });
    });
    const shown = months.filter(m => counts.get(m).testedWeeks.size > 0);
    const left = months.filter(m => counts.get(m).testedWeeks.size === 0);
    const rows = shown.map(m => {
      const c = counts.get(m);
      return { month: m + '-01', fresh: c.fresh, other: c.other, total: c.fresh + c.other, tested: c.tested, weeks: c.weeks.size, testedWeeks: c.testedWeeks.size, rate: c.tested ? roundTo((c.fresh + c.other) / c.tested * 100, 2) : 0 };
    });
    const peak = rows.reduce((a, r) => r.total > a.total ? r : a);
    const grp = F.group === ALL_GROUPS ? '' : ' in ' + F.group.toLowerCase();
    setText('h-spikes', peak.total === 0 ? 'No spike weeks' + grp + ' in the year'
      : 'Spike weeks' + grp + ' peaked in ' + monthName(peak.month) + ' (' + peak.total + ')' + (F.group === ALL_GROUPS ? ', ' + peak.fresh + ' of them in fresh produce' : ''));
    const partial = rows.filter(r => r.testedWeeks < r.weeks);
    const peakAll = rows.reduce((a, r) => r.tested > a.tested ? r : a);
    setText('n-spikes', 'Each test needs 8 earlier weeks' +
      (left.length ? ', so ' + joinAnd(left.map(m => monthName(m + '-01'))) + (left.length > 1 ? ' are' : ' is') + ' left out (no week could be tested)' : '') +
      (partial.length ? (left.length ? ' and ' : ', so ') + joinAnd(partial.map(r => monthName(r.month) + ' covers only ' + r.testedWeeks + ' of its ' + r.weeks + ' weeks (' +
        nf0.format(r.tested) + ' item-weeks tested, against ' + nf0.format(F.group === ALL_GROUPS ? peak.tested : peakAll.tested) + ' in ' + monthName(F.group === ALL_GROUPS ? peak.month : peakAll.month) + ')')) : '') + '.');
    const narrow = chartWidth('c-spikes') < 560;
    draw('c-spikes', {
      grid: { left: 8, right: 16, top: 52, bottom: 8, containLabel: true },
      legend: { top: 0, left: 0, itemWidth: 14, itemHeight: 10, textStyle: axisText(), data: ['Fresh produce', 'Other items'] },
      xAxis: { type: 'category', data: rows.map(r => narrow ? MONTHS[parts(r.month)[1] - 1].slice(0, 3) : monthShort(r.month)), axisTick: { show: false }, axisLine: { lineStyle: { color: C.ruleStrong } }, axisLabel: Object.assign({ interval: 0 }, axisText(), { fontSize: narrow ? 10 : 12 }) },
      yAxis: { type: 'value', minInterval: 1, axisLabel: axisText(), splitLine: splitLine(), name: 'spike weeks', nameTextStyle: axisText() },
      tooltip: {
        trigger: 'axis', axisPointer: { type: 'shadow' },
        formatter: ps => {
          const r = rows[ps[0].dataIndex];
          return '<b>' + monthName(r.month) + '</b><br>Fresh produce: ' + r.fresh + ' spike weeks<br>Other items: ' + r.other + ' spike weeks<br>Total: ' + r.total +
            ' spike weeks<br>Item-weeks tested: ' + nf0.format(r.tested) + ' (' + r.rate.toFixed(2) + '% were spikes)' + (r.testedWeeks < r.weeks ? '<br>Only ' + r.testedWeeks + ' of ' + r.weeks + ' weeks could be tested' : '');
        }
      },
      series: [
        { name: 'Fresh produce', type: 'bar', stack: 'spikes', barMaxWidth: 40, itemStyle: { color: C.blue }, data: rows.map(r => r.fresh) },
        { name: 'Other items', type: 'bar', stack: 'spikes', barMaxWidth: 40, itemStyle: { color: C.orange, borderRadius: [2, 2, 0, 0] }, data: rows.map(r => r.other),
          label: { show: true, position: 'top', color: C.ink, fontSize: narrow ? 10 : 12, formatter: p => String(rows[p.dataIndex].total) } }
      ]
    }, 340);
    srTable('t-spikes', 'Spike weeks per month', ['Month', 'Fresh produce', 'Other items', 'Total', 'Item-weeks tested', 'Spike rate %'],
      rows.map(r => [monthName(r.month), r.fresh, r.other, r.total, r.tested, r.rate.toFixed(2)]));
  }

  /* Tabs */
  let activeView = null;
  const VIEW_RENDER = {
    households: () => { renderState(); renderDistrict(); renderFestive(); },
    retail: () => { renderType(); renderQuartile(); renderShops(); renderItemType(); },
    'cost-risk': () => { renderMonthly(); renderWeekly(); renderMovers(); renderSpikes(); }
  };
  function showTab(id, focus) {
    if (VIEWS.indexOf(id) < 0) id = VIEWS[0];
    VIEWS.forEach(t => {
      const on = t === id;
      const tab = $('tab-' + t);
      tab.setAttribute('aria-selected', on ? 'true' : 'false');
      tab.tabIndex = on ? 0 : -1;
      $('panel-' + t).hidden = !on;
    });
    if (focus) $('tab-' + id).focus();
    const changed = activeView !== id;
    activeView = id;
    if (changed && explorerReady) VIEW_RENDER[id]();
    if (F && F.view !== id) { F.view = id; writeUrl(); }
  }
  function setupTabs() {
    const list = document.querySelector('[role="tablist"]');
    list.addEventListener('click', e => { const tab = e.target.closest('[role="tab"]'); if (tab) showTab(tab.id.replace('tab-', ''), false); });
    list.addEventListener('keydown', e => {
      const tab = e.target.closest('[role="tab"]');
      const i = VIEWS.indexOf(tab ? tab.id.replace('tab-', '') : activeView);
      let next = null;
      if (e.key === 'ArrowRight') next = VIEWS[(i + 1) % VIEWS.length];
      else if (e.key === 'ArrowLeft') next = VIEWS[(i - 1 + VIEWS.length) % VIEWS.length];
      else if (e.key === 'Home') next = VIEWS[0];
      else if (e.key === 'End') next = VIEWS[VIEWS.length - 1];
      if (next) { e.preventDefault(); showTab(next, true); }
    });
  }

  function updateAll() {
    if (!explorerReady) return;
    updateMap();
    updateProfile();
    updateHeat();
    updateCheapest();
    updateCompare();
    updateTrends();
    // every view updates its titles and tables; charts in hidden tabs draw when shown
    VIEWS.forEach(v => VIEW_RENDER[v]());
  }

  function startExplorer() {
    prepareData();
    echarts.registerMap('MY', window.MPW_GEO);
    F = readUrl();
    handlers['c-map'] = onMapClick;
    handlers['c-cheap-map'] = onMapClick;
    handlers['c-heat'] = onHeatClick;
    setupControls();
    $('explore-loading').hidden = true;
    $('explore-body').hidden = false;
    explorerReady = true;
    syncControls();
    showTab(F.view, false);
    updateAll();
    document.body.setAttribute('data-explorer', 'ready');
    // a shared link that points into the explorer: scroll there now that it has its full height
    const target = location.hash && document.getElementById(location.hash.slice(1));
    if (target && target.closest('#explore')) target.scrollIntoView({ block: 'start' });
  }

  /* Boot */
  function init() {
    readColors();
    applyTheme(document.documentElement.getAttribute('data-theme') || 'light', false);
    $('theme-toggle').addEventListener('click', () => {
      applyTheme(document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark', true);
      redrawAll();
    });
    renderHero();
    setupReveal();
    document.addEventListener('click', e => { const b = e.target.closest('[data-png]'); if (b) downloadPng(b.dataset.png); });

    // Load ECharts when the findings come close; load the explorer data when the explorer does.
    const wantCharts = () => needCharts().then(() => renderFindings());
    if (io) {
      const lazy = new IntersectionObserver(entries => {
        entries.forEach(e => {
          if (!e.isIntersecting) return;
          lazy.unobserve(e.target);
          if (e.target.id === 'findings') wantCharts();
          else needData();
        });
      }, { rootMargin: '300px 0px' });
      lazy.observe($('findings'));
      lazy.observe($('explore'));
      document.querySelectorAll('.findings .chart').forEach(el => io.observe(el));
    } else { wantCharts(); needData(); }
    // Interaction with the filters, or a link that carries a view, loads the data straight away.
    $('filterbar').addEventListener('focusin', () => needData(), { once: true });
    $('filterbar').addEventListener('pointerdown', () => needData(), { once: true });
    if (hasUrlState() || /^#(explore|tools|views|tool-|profile)/.test(location.hash)) { wantCharts(); needData(); }
    window.addEventListener('hashchange', () => { if (/^#(explore|tools|views)/.test(location.hash)) needData(); });

    let timer = null;
    let lastW = window.innerWidth;
    window.addEventListener('resize', () => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        Object.keys(charts).forEach(id => charts[id].resize());
        if (window.innerWidth !== lastW) { lastW = window.innerWidth; redrawAll(); }
      }, 160);
    });
    document.body.setAttribute('data-ready', 'true');
  }
  function redrawAll() {
    if (window.echarts) renderFindings();
    updateAll();
  }
  // Exposed for the browser tests only.
  window.MPW_APP = { needData: needData, needCharts: needCharts, charts: charts, state: () => F };

  init();
})();
