// Parses a WoW SavedVariables file (a restricted Lua subset) into plain JS values.
// Tables whose keys are exactly 1..n become arrays; everything else becomes objects.
'use strict';

function parseSavedVariables(src) {
  let i = 0;
  const n = src.length;

  function fail(msg) {
    const line = src.slice(0, i).split('\n').length;
    throw new Error(`SavedVariables parse error on line ${line}: ${msg}`);
  }

  function skip() {
    for (;;) {
      while (i < n && /\s/.test(src[i])) i++;
      if (src.startsWith('--', i)) {
        if (src.startsWith('--[[', i)) {
          const end = src.indexOf(']]', i + 4);
          i = end < 0 ? n : end + 2;
        } else {
          while (i < n && src[i] !== '\n') i++;
        }
        continue;
      }
      return;
    }
  }

  function parseString() {
    const quote = src[i++];
    let out = '';
    while (i < n && src[i] !== quote) {
      let ch = src[i++];
      if (ch === '\\') {
        const e = src[i++];
        if (e === 'n') ch = '\n';
        else if (e === 't') ch = '\t';
        else if (e === 'r') ch = '\r';
        else if (e === '\n') ch = '\n';
        else if (/\d/.test(e)) {
          let digits = e;
          while (digits.length < 3 && /\d/.test(src[i])) digits += src[i++];
          ch = String.fromCharCode(parseInt(digits, 10));
        } else ch = e; // \\ \" \'
      }
      out += ch;
    }
    if (src[i] !== quote) fail('unterminated string');
    i++;
    return out;
  }

  function parseLongString() {
    const m = /^\[(=*)\[/.exec(src.slice(i, i + 64));
    const close = ']' + m[1] + ']';
    const start = i + m[0].length;
    const end = src.indexOf(close, start);
    if (end < 0) fail('unterminated long string');
    i = end + close.length;
    return src.slice(start, end).replace(/^\n/, '');
  }

  function parseNumber() {
    const m = /^-?(0x[0-9a-fA-F]+|(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?)/.exec(src.slice(i, i + 64));
    if (!m) fail('bad number');
    i += m[0].length;
    return Number(m[0]);
  }

  function parseValue() {
    skip();
    const ch = src[i];
    if (ch === '{') return parseTable();
    if (ch === '"' || ch === "'") return parseString();
    if (ch === '[' && /^\[=*\[/.test(src.slice(i, i + 64))) return parseLongString();
    if (ch === '-' || ch === '.' || /\d/.test(ch)) return parseNumber();
    const word = /^[A-Za-z_][\w.]*/.exec(src.slice(i, i + 64));
    if (word) {
      i += word[0].length;
      if (word[0] === 'true') return true;
      if (word[0] === 'false') return false;
      if (word[0] === 'nil') return null;
      if (word[0] === 'math.huge') return Infinity;
    }
    fail(`unexpected ${JSON.stringify(src.slice(i, i + 20))}`);
  }

  function parseTable() {
    i++; // {
    const entries = [];
    let arrayIndex = 1;
    for (;;) {
      skip();
      if (src[i] === '}') { i++; break; }
      let key;
      if (src[i] === '[' && !/^\[=*\[/.test(src.slice(i, i + 64))) {
        i++;
        key = parseValue();
        skip();
        if (src[i] !== ']') fail('expected ]');
        i++;
        skip();
        if (src[i] !== '=') fail('expected =');
        i++;
      } else {
        const ident = /^([A-Za-z_]\w*)\s*=(?!=)/.exec(src.slice(i, i + 128));
        if (ident) {
          key = ident[1];
          i += ident[0].length;
        } else {
          key = arrayIndex++;
        }
      }
      const value = parseValue();
      if (value !== null) entries.push([key, value]);
      skip();
      if (src[i] === ',' || src[i] === ';') i++;
    }
    const isArray = entries.length > 0 && entries.every(([k], idx) => k === idx + 1);
    if (isArray) return entries.map(([, v]) => v);
    const obj = {};
    for (const [k, v] of entries) obj[String(k)] = v;
    return obj;
  }

  const result = {};
  for (;;) {
    skip();
    if (i >= n) break;
    const ident = /^([A-Za-z_]\w*)\s*=/.exec(src.slice(i, i + 256));
    if (!ident) fail('expected a variable assignment');
    i += ident[0].length;
    result[ident[1]] = parseValue();
  }
  return result;
}

module.exports = { parseSavedVariables };
