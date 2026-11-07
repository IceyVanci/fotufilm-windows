// Re-applies the port's Chinese interface to a Flutter tree.
//   node tools/apply-zh.cjs [--root <dir>] [--apply]
// The tree defaults to F:/Futo/upstream. A string literal is rewritten only when that exact text
// has a Chinese entry, and never where the engine reads it back as a key: tools/check-cjk-guard.cjs
// asserts that invariant afterwards.
const fs = require('fs'), path = require('path');

const argv = process.argv.slice(2);
const APPLY = argv.includes('--apply');
const rootAt = argv.indexOf('--root');
const REPO = rootAt >= 0 ? argv[rootAt + 1] : 'F:/Futo/upstream';
const LIB = path.join(REPO, 'flutter/lib');
const ZH = path.join(LIB, 'i18n/zh.dart');

// ---- 1. the map: zh.dart as it stands, then the two tables on top -------------------------------
const zhSrc = fs.readFileSync(ZH, 'utf8');
const map = new Map([...zhSrc.matchAll(/"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"/g)]
  .map((m) => [m[1], m[2]]));
const catalogue = JSON.parse(fs.readFileSync('F:/Futo/tools/zh-catalogue.json', 'utf8'));
for (const [k, v] of Object.entries(catalogue)) map.set(k, v);
const ui = JSON.parse(fs.readFileSync('F:/Futo/tools/zh-ui.json', 'utf8'));

// zh.dart is generated from the two tables: the catalogue half is applied when the control
// catalogue loads (Catalogue.load), so the engine's generated sources stay untouched.
const esc = (s) => s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\$/g, '\\$');
const tail = zhSrc.slice(zhSrc.indexOf('/// The Chinese for'));
const head = "// Chinese strings for the Windows port's editor. The catalogue half is applied when the control\n"
  + '// catalogue loads (Catalogue.load), so the generated sources stay untouched; the rest are matched\n'
  + '// against literals in the interface (tools/apply-zh.cjs).\n\n'
  + '/// Every English term the interface shows, mapped to Chinese.\n';
let zhOut = head + 'const Map<String, String> zhStrings = <String, String>{\n';
for (const [k, v] of [...map.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
  zhOut += '  "' + esc(k) + '": "' + esc(v) + '",\n';
}
zhOut += '};\n\n' + tail;
if (APPLY) fs.writeFileSync(ZH, zhOut, 'utf8');
console.log('map entries:', map.size);

// ---- 2. lexer ----------------------------------------------------------------------------------
function lex(src) {
  const toks = [];
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    if (c === '/' && src[i + 1] === '/') { while (i < n && src[i] !== '\n') i++; continue; }
    if (c === '/' && src[i + 1] === '*') { i += 2; while (i < n && !(src[i] === '*' && src[i + 1] === '/')) i++; i += 2; continue; }
    if (/\s/.test(c)) { i++; continue; }
    let j = i, raw = false;
    if (c === 'r' && (src[i + 1] === '"' || src[i + 1] === "'") && !/[A-Za-z0-9_]/.test(src[i - 1] || '')) { raw = true; j = i + 1; }
    const q = src[j];
    if (q === '"' || q === "'") {
      let delim = q.repeat(3);
      if (!src.startsWith(delim, j)) delim = q;
      let k = j + delim.length;
      const bodyStart = k;
      while (k < n) {
        if (!raw && src[k] === '\\') { k += 2; continue; }
        if (src.startsWith(delim, k)) break;
        k++;
      }
      const body = src.slice(bodyStart, k).replace(/\\(.)/g, (m, ch) => (ch === 'n' ? '\n' : ch === 't' ? '\t' : ch));
      toks.push({ t: 'str', v: body, start: i, end: k + delim.length, raw });
      i = k + delim.length;
      continue;
    }
    if (/[A-Za-z_$]/.test(c)) { let k = i + 1; while (k < n && /[A-Za-z0-9_$]/.test(src[k])) k++; toks.push({ t: 'id', v: src.slice(i, k), start: i, end: k }); i = k; continue; }
    if (/[0-9]/.test(c)) { let k = i + 1; while (k < n && /[0-9A-Za-z_.]/.test(src[k])) k++; toks.push({ t: 'num', v: src.slice(i, k), start: i, end: k }); i = k; continue; }
    toks.push({ t: 'p', v: c, start: i, end: i + 1 });
    i++;
  }
  return toks;
}

// ---- 3. the arguments the engine reads back as keys ---------------------------------------------
const PROTECT = {
  'c.sliders': [0],
  'c.profileControls': 'all',
  'c.editSwitch': [0],
  'c.catalogue.control': [0],
  'c.catalogue.detail': [0],
  'c.control': [0],
  'PickerOption': [0],
  'catalogueSlider': [1],
  '[': 'all',
};
// A named argument whose value the engine compares or looks up, anywhere: group: 'Light'.
const PROTECT_NAME = new Set(['group', 'field', 'id', 'key', 'glyph', 'unit', 'section', 'scale',
  'restingOn', 'defaultMedium', 'availability', 'route', 'aspect', 'tool']);

function calleeOf(toks, open) {
  const prev = toks[open - 1];
  if (!prev || prev.t !== 'id') return '';
  const dot = toks[open - 2];
  if (dot && dot.t === 'p' && dot.v === '.') {
    const qual = toks[open - 3];
    if (qual && qual.t === 'id') return qual.v + '.' + prev.v;
  }
  return prev.v;
}

// ---- 4. the rewrite ----------------------------------------------------------------------------
const RE = /\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*/g;
function normalize(t) {
  const ph = [];
  return { norm: t.replace(RE, (m) => { ph.push(m); return '{' + (ph.length - 1) + '}'; }), ph };
}
function render(text, ph, value) {
  let v = value;
  for (const i of [...v.matchAll(/\{(\d+)\}/g)].map((m) => +m[1]).sort((a, b) => b - a)) {
    if (ph[i] !== undefined) v = v.split('{' + i + '}').join(ph[i]);
  }
  return v;
}
const dartLiteral = (s) => "'" + s.replace(/\\/g, '\\\\').replace(/'/g, "\\'") + "'";

// Files the port itself authored are overlaid after the replay, so the rewriter leaves them alone.
const overlayFile = 'F:/Futo/tools/overlay.txt';
const overlay = new Set(fs.existsSync(overlayFile)
  ? fs.readFileSync(overlayFile, 'utf8').split('\n').filter(Boolean)
      .map((p) => p.replace(/^flutter\//, 'flutter/'))
  : []);

function walk(d, out = []) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) { if (e.name !== 'i18n') walk(p, out); }
    else if (e.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

let replaced = 0, filesTouched = 0, protectedSkips = 0;
const keptEnglish = [];
for (const file of walk(LIB)) {
  const rel = path.relative(path.dirname(LIB), file).replace(/\\/g, '/');
  if (overlay.has(rel)) continue;
  const src = fs.readFileSync(file, 'utf8');
  const toks = lex(src);
  const stack = [];
  const edits = [];
  for (let i = 0; i < toks.length; i++) {
    const tk = toks[i];
    if (tk.t === 'p') {
      if (tk.v === '(') stack.push({ callee: calleeOf(toks, i), arg: 0 });
      else if (tk.v === '{') stack.push({ callee: '', arg: 0 });
      else if (tk.v === '[') {
        // an index reads a key back; a list literal does not, and must not shadow its call
        const prev = toks[i - 1];
        const index = prev && ((prev.t === 'id' && !/^(const|final|var|return|case|in|of|new|yield|await)$/.test(prev.v))
          || prev.v === ')' || prev.v === ']');
        // for (final band in const ['Shadows', ...]) builds engine keys (grade$band$axis): leave it
        const iterated = !!(prev && prev.t === 'id' && prev.v === 'const' && toks[i - 2] && toks[i - 2].v === 'in');
        stack.push({ callee: index || iterated ? '[' : '', arg: 0, iterated });
      }
      else if (tk.v === ')' || tk.v === ']' || tk.v === '}') stack.pop();
      else if (tk.v === ',' && stack.length) stack[stack.length - 1].arg++;
      else if (tk.v === ';') stack.length = 0;
      continue;
    }
    if (tk.t !== 'str') continue;
    let j = i, text = '', end = tk.end, anyRaw = tk.raw;
    while (j < toks.length && toks[j].t === 'str') { text += toks[j].v; end = toks[j].end; anyRaw = anyRaw || toks[j].raw; j++; }
    i = j - 1;
    const frame = stack[stack.length - 1];
    const rule = frame ? PROTECT[frame.callee] : undefined;
    const named = toks[i - 1] && toks[i - 1].v === ':' && toks[i - 2] && toks[i - 2].t === 'id' ? toks[i - 2].v : null;
    if (rule === 'all' || (Array.isArray(rule) && rule.includes(frame.arg))
        || (frame && frame.iterated) || (named && PROTECT_NAME.has(named))) {
      protectedSkips++;
      const { norm } = normalize(text);
      if (map.has(norm)) keptEnglish.push(file.split(/[\\/]/).slice(-1)[0] + ': ' + JSON.stringify(text));
      continue;
    }
    if (anyRaw) continue;
    const { norm, ph } = normalize(text);
    if (!map.has(norm)) continue;
    if (/^[A-Z][A-Z0-9_]{2,}$/.test(text)) continue;
    if (/^\s*:\s*(Color|const\s+Color)\(/.test(src.slice(end, end + 24))) continue;
    const zh = render(text, ph, map.get(norm));
    if (zh === text) continue;
    edits.push({ start: tk.start, end, text: dartLiteral(zh) });
  }
  if (!edits.length) continue;
  edits.sort((a, b) => b.start - a.start);
  let outSrc = src;
  for (const e of edits) outSrc = outSrc.slice(0, e.start) + e.text + outSrc.slice(e.end);
  filesTouched++;
  replaced += edits.length;
  if (APPLY) fs.writeFileSync(file, outSrc, 'utf8');
}
console.log('root', REPO, APPLY ? '(written)' : '(dry run)');
console.log('literal replacements:', replaced, 'files:', filesTouched, 'protected skips:', protectedSkips);
const uniq = [...new Set(keptEnglish)];
if (uniq.length) console.log('-- protected literals that have a Chinese entry, kept English --\n' + uniq.join('\n'));
