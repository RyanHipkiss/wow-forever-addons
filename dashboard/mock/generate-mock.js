// Writes mock/CraftProfit.mock.lua: ~60 days of fake scan history in the same
// SavedVariables format the addon produces, so the dashboard can be previewed.
//   node mock/generate-mock.js && node server.js mock/CraftProfit.mock.lua
'use strict';
const fs = require('fs');
const path = require('path');

const DAYS = 60;
let seed = 7;
const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
const noise = (amp) => (rand() - 0.5) * 2 * amp;

const items = {
  14046: ['Runecloth Bag', 1], 14048: ['Bolt of Runecloth', 1], 14047: ['Runecloth', 1],
  8170: ['Rugged Leather', 1], 14341: ['Rune Thread', 1], 10050: ['Mageweave Bag', 1],
  4339: ['Bolt of Mageweave', 1], 8343: ['Heavy Silken Thread', 1],
  13510: ['Flask of the Titans', 1], 13468: ['Black Lotus', 2], 8846: ['Gromsblood', 1],
  13423: ['Stonescale Oil', 1], 18256: ['Imbued Vial', 1],
  13446: ['Major Healing Potion', 1], 13464: ['Golden Sansam', 1], 13465: ['Mountain Silversage', 1],
  8925: ['Crystal Vial', 1], 13452: ['Elixir of the Mongoose', 1], 13466: ['Plaguebloom', 1],
  13457: ['Greater Fire Protection Potion', 1], 7068: ['Elemental Fire', 1], 13463: ['Dreamfoil', 1],
  12404: ['Dense Sharpening Stone', 1], 12365: ['Dense Stone', 1],
  13931: ['Nightfin Soup', 1], 13757: ['Raw Nightfin Snapper', 1], 159: ['Refreshing Spring Water', 1],
};

// profit(d): d = 0 (oldest) .. DAYS-1 (today), in copper per craft
const recipes = [
  { id: 17635, item: 13510, prof: 'Alchemy', char: 'Ryan', cost: 1150000,
    mats: [[13468, 1, 'ah', 980000], [8846, 30, 'ah', 4200], [13423, 10, 'ah', 1600], [18256, 1, 'vendor', 4000]],
    profit: (d) => 210000 + 90000 * Math.sin(d / 7) + d * 2500 + (d === DAYS - 1 ? 120000 : 0) + noise(25000) },
  { id: 18630, item: 14046, prof: 'Tailoring', char: 'Ryan', cost: 52000,
    mats: [[14048, 5, 'craft', 8200], [8170, 2, 'ah', 2900], [14341, 1, 'vendor', 2500]],
    profit: (d) => d < 12 ? -6000 + d * 300 : 14000 + 6000 * Math.sin(d / 5) - (d === DAYS - 1 ? 7000 : 0) + noise(1500) },
  { id: 18401, item: 14048, prof: 'Tailoring', char: 'Ryan', cost: 8200, outQty: 1,
    mats: [[14047, 5, 'ah', 1640]],
    profit: () => 3100 },
  { id: 17556, item: 13446, prof: 'Alchemy', char: 'Ryan', cost: 7900,
    mats: [[13464, 2, 'ah', 2400], [13465, 1, 'ah', 2700], [8925, 1, 'vendor', 400]],
    profit: (d) => d < DAYS - 21 ? -1200 + noise(600) : 1800 + (d - (DAYS - 21)) * 90 + noise(300) + (d === DAYS - 1 ? 900 : 0) },
  { id: 17571, item: 13452, prof: 'Alchemy', char: 'Ryan', cost: 16500,
    mats: [[13465, 2, 'ah', 2700], [13466, 2, 'ah', 5300], [8925, 1, 'vendor', 400]],
    profit: (d) => d < DAYS - 1 ? -3500 + noise(1500) : 2600 },
  { id: 17574, item: 13457, prof: 'Alchemy', char: 'Ryan', cost: 11200,
    mats: [[7068, 1, 'ah', 6100], [13463, 1, 'ah', 4700], [8925, 1, 'vendor', 400]],
    profit: (d) => d < DAYS - 3 ? -900 + noise(800) : 2200 + (d - (DAYS - 3)) * 400 },
  { id: 16641, item: 12404, prof: 'Blacksmithing', char: 'Brakka', cost: 1400, outQty: 1,
    mats: [[12365, 1, 'ah', 1400]],
    profit: (d) => d < DAYS - 5 ? 600 + noise(150) : -250 + noise(80) },
  { id: 18245, item: 13931, prof: 'Cooking', char: 'Brakka', cost: 1900,
    mats: [[13757, 1, 'ah', 1850], [159, 1, 'vendor', 50]],
    profit: (d) => 900 + 400 * Math.sin(d / 9) + d * 15 + (d === DAYS - 1 ? 350 : 0) + noise(120) },
  { id: 12065, item: 10050, prof: 'Tailoring', char: 'Ryan', cost: 31000,
    mats: [[4339, 4, 'craft', 7000], [8343, 2, 'vendor', 1500]],
    profit: (d) => -4500 + noise(1200) },
];

// Local calendar days, today last. Some days had no scan.
const pad = (v) => String(v).padStart(2, '0');
const dayStr = (date) => `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
const days = [];
for (let i = DAYS - 1; i >= 0; i--) {
  const dt = new Date();
  dt.setHours(19, 30, 0, 0);
  dt.setDate(dt.getDate() - i);
  days.push(dt);
}
const skipped = new Set([5, 6, 17, 30, 31, 32, 44]);

// Lua writer ------------------------------------------------------------------------
const q = (s) => JSON.stringify(String(s));
function lua(v, ind = '') {
  if (v === null || v === undefined) return 'nil';
  if (typeof v === 'number') return String(Math.round(v * 1000) / 1000);
  if (typeof v === 'boolean') return String(v);
  if (typeof v === 'string') return q(v);
  const inner = ind + '\t';
  if (Array.isArray(v)) {
    return '{\n' + v.map((x, i) => `${inner}${lua(x, inner)}, -- [${i + 1}]\n`).join('') + ind + '}';
  }
  return '{\n' + Object.entries(v).map(([k, x]) =>
    `${inner}[${/^\d+$/.test(k) ? k : q(k)}] = ${lua(x, inner)},\n`).join('') + ind + '}';
}

const h = { recipes: {}, days: {}, prices: {}, items: {}, scans: [] };
for (const [id, [name, quality]] of Object.entries(items)) h.items[id] = { name, quality };

for (const r of recipes) {
  h.recipes[r.id] = {
    name: items[r.item][0], item: r.item, outQty: r.outQty || 1, char: r.char, prof: r.prof,
    sellSource: 'ah', mats: r.mats.map(([id, qty, source, unit]) => ({ id, qty, source, unit })),
  };
  h.days[r.id] = {};
  days.forEach((dt, d) => {
    if (skipped.has(d)) return;
    const cost = Math.round(r.cost * (1 + noise(0.04)));
    const profit = Math.round(r.profit(d));
    h.days[r.id][dayStr(dt)] = {
      profit, cost, revenue: cost + profit, listed: Math.max(1, Math.round(12 + noise(9))),
      ahMin: Math.round((cost + profit) / 0.95), t: Math.floor(dt.getTime() / 1000),
    };
  });
}
days.forEach((dt, d) => {
  if (!skipped.has(d)) h.scans.push({ t: Math.floor(dt.getTime() / 1000), auctions: Math.round(31000 + noise(4000)), items: 4200 });
});
// Make "today" look like a scan from a few minutes ago.
h.scans[h.scans.length - 1].t = Math.floor(Date.now() / 1000) - 300;

const db = { settings: { ahCut: 0.05, marketDepth: 0.15, useCraftedMats: true, profitableOnly: true },
  history: { 'Forever-Alliance': h } };
const out = path.join(__dirname, 'CraftProfit.mock.lua');
fs.writeFileSync(out, '\nCraftProfitDB = ' + lua(db) + '\n');
console.log('Wrote ' + out);
