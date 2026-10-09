// CraftProfit dashboard: reads the addon's SavedVariables file and serves a
// local web page with profitable recipes, profit history and today's alerts.
//
//   node dashboard/server.js                       (auto-finds CraftProfit.lua)
//   node dashboard/server.js "<path to CraftProfit.lua>"
//   set CRAFTPROFIT_WOW=E:\Games\World of Warcraft\_classic_beta_   (other install)
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const { parseSavedVariables } = require('./sv-parser');

const PORT = Number(process.env.PORT) || 4747;
const WOW_DIRS = [
  process.env.CRAFTPROFIT_WOW,
  'E:\\BattleNet\\World of Warcraft\\_classic_beta_',
  'C:\\Program Files (x86)\\World of Warcraft\\_classic_beta_',
  'C:\\Program Files\\World of Warcraft\\_classic_beta_',
].filter(Boolean);

// Finding the file ------------------------------------------------------------

function findSavedVariables() {
  const explicit = process.argv[2] || process.env.CRAFTPROFIT_SV;
  if (explicit) return fs.existsSync(explicit) ? explicit : null;
  let best = null;
  for (const dir of WOW_DIRS) {
    const accounts = path.join(dir, 'WTF', 'Account');
    if (!fs.existsSync(accounts)) continue;
    for (const acct of fs.readdirSync(accounts)) {
      const file = path.join(accounts, acct, 'SavedVariables', 'CraftProfit.lua');
      if (!fs.existsSync(file)) continue;
      const mtime = fs.statSync(file).mtimeMs;
      if (!best || mtime > best.mtime) best = { file, mtime };
    }
  }
  return best && best.file;
}

// Building the view model ---------------------------------------------------------

const DAY_MS = 86400000;
const dayNumber = (d) => Math.round(Date.parse(d + 'T00:00:00Z') / DAY_MS);

function localToday() {
  const now = new Date();
  const p = (v) => String(v).padStart(2, '0');
  return `${now.getFullYear()}-${p(now.getMonth() + 1)}-${p(now.getDate())}`;
}

function buildRealm(h, today, sales = [], ahCut = 0.05) {
  const items = h.items || {};
  const itemName = (id) => (items[id] && items[id].name) || `Item ${id}`;
  const recipes = [];
  const alerts = [];

  for (const [id, r] of Object.entries(h.recipes || {})) {
    const byDay = (h.days || {})[id] || {};
    const series = Object.keys(byDay).sort().map((d) => ({
      d,
      profit: byDay[d].profit ?? null,
      cost: byDay[d].cost ?? null,
      revenue: byDay[d].revenue ?? null,
      listed: byDay[d].listed ?? 0,
      ahMin: byDay[d].ahMin ?? null,
    }));
    if (!series.length) continue;
    const latest = series[series.length - 1];
    const prev = series.length > 1 ? series[series.length - 2] : null;

    // Profitable streak: the run of recorded days, ending at the latest, with profit > 0.
    let streak = null;
    if (latest.profit > 0) {
      let k = series.length - 1;
      while (k > 0 && series[k - 1].profit > 0) k--;
      streak = {
        since: series[k].d,
        days: dayNumber(latest.d) - dayNumber(series[k].d) + 1,
        scannedDays: series.length - k,
      };
    }

    let todayChange = null;
    if (latest.d === today && prev && latest.profit != null && prev.profit != null) {
      todayChange = { amount: latest.profit - prev.profit, prevDay: prev.d, prevProfit: prev.profit };
      todayChange.pct = prev.profit > 0 ? todayChange.amount / prev.profit : null;
    }

    const item = items[r.item] || {};
    const outName = item.name || r.name;
    // "At that price": the lowest AH buyout per item that today's profit is based on.
    const outQty = r.outQty || 1;
    const priceThreshold = latest.ahMin != null ? latest.ahMin
      : latest.revenue != null ? latest.revenue / outQty / (1 - ahCut) : null;
    const mySales = sales
      .filter((s) => (s.item != null && Number(s.item) === Number(r.item)) || s.name === outName)
      .map((s) => ({ t: s.t, count: s.count || 1, unit: s.price / (s.count || 1) }))
      .sort((a, b) => b.t - a.t);
    const recipe = {
      id,
      name: item.name || r.name || `Recipe ${id}`,
      itemId: r.item,
      quality: item.quality ?? 1,
      char: r.char,
      prof: r.prof,
      outQty: r.outQty,
      sellSource: r.sellSource,
      latest: { ...latest, margin: latest.cost > 0 && latest.profit != null ? latest.profit / latest.cost : null },
      isCurrent: latest.d === today,
      streak,
      todayChange,
      series,
      mats: (r.mats || []).map((m) => ({ ...m, name: itemName(m.id) })),
      priceThreshold,
      sales: mySales,
    };
    recipes.push(recipe);

    if (todayChange && todayChange.amount > 0 && latest.profit > 0) {
      alerts.push({
        id,
        name: recipe.name,
        quality: recipe.quality,
        profit: latest.profit,
        ...todayChange,
        newlyProfitable: todayChange.prevProfit <= 0,
      });
    }
  }

  alerts.sort((a, b) => b.amount - a.amount);
  recipes.sort((a, b) => (b.latest.profit ?? -Infinity) - (a.latest.profit ?? -Infinity));
  const scans = h.scans || [];
  return { recipes, alerts, lastScan: scans[scans.length - 1] || null, scanCount: scans.length };
}

let cache = { file: null, mtime: 0, model: null, error: null };

function loadModel() {
  const file = findSavedVariables();
  if (!file) {
    return { error: 'notFound', searched: WOW_DIRS };
  }
  const mtime = fs.statSync(file).mtimeMs;
  if (cache.file === file && cache.mtime === mtime && cache.model) return cache.model;
  try {
    const sv = parseSavedVariables(fs.readFileSync(file, 'utf8'));
    const db = sv.CraftProfitDB || {};
    const today = localToday();
    const realms = {};
    const cut = (db.settings && db.settings.ahCut) ?? 0.05;
    for (const [key, h] of Object.entries(db.history || {})) {
      const sales = (db.sales || {})[key];
      realms[key] = buildRealm(h, today, Array.isArray(sales) ? sales : [], cut);
    }
    const model = {
      file,
      fileUpdated: new Date(mtime).toISOString(),
      today,
      ahCut: db.settings && db.settings.ahCut,
      realms,
    };
    cache = { file, mtime, model };
    return model;
  } catch (err) {
    return { error: 'parse', message: err.message, file };
  }
}

// Server -----------------------------------------------------------------------------

const INDEX = path.join(__dirname, 'index.html');

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/api/data') {
    const model = loadModel();
    res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify(model));
  } else if (url.pathname === '/' || url.pathname === '/index.html') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    fs.createReadStream(INDEX).pipe(res);
  } else {
    res.writeHead(404);
    res.end('Not found');
  }
});

if (require.main === module) {
  server.listen(PORT, '127.0.0.1', () => {
    const file = findSavedVariables();
    console.log(`CraftProfit dashboard: http://localhost:${PORT}`);
    console.log(file ? `Reading ${file}` : 'CraftProfit.lua not found yet - scan the AH in game, then /reload.');
  });
}

module.exports = { buildRealm, loadModel };
