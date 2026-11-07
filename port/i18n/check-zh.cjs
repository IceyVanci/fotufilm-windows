
// Invariants the Chinese interface must keep: the engine reads some literals back as keys.
//   node tools/check-zh.cjs [--root <dir>]
const fs = require('fs'), path = require('path');
const argv = process.argv.slice(2);
const at = argv.indexOf('--root');
const REPO = at >= 0 ? argv[at + 1] : 'F:/Futo/work/115';
const LIB = path.join(REPO, 'flutter/lib');
const CJK = /[\u3400-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]/;
function walk(d, out = []) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p, out); else if (e.name.endsWith('.dart')) out.push(p);
  }
  return out;
}
const bad = [];
const note = (f, src, idx, what) => {
  const line = src.slice(0, idx).split('\n').length;
  bad.push(path.relative(REPO, f).replace(/\\/g, '/') + ':' + line + '  ' + what);
};
// 1. keys the engine reads back must stay ASCII
const KEY_CALLS = [
  [/\.sliders\(\s*'([^'\n]*)'/g, 'sliders group'],
  [/\.profileControls\(\s*const\s*\[([^\]]*)\]/g, 'profileControls fields'],
  [/catalogue\.(?:control|detail)\(\s*'([^'\n]*)'/g, 'catalogue lookup'],
  [/\.editSwitch\(\s*'([^'\n]*)'/g, 'editSwitch id'],
  [/module\[\s*'([^'\n]*)'\s*\]/g, 'module key'],
  [/\.edit\[\s*'([^'\n]*)'\s*\]/g, 'edit key'],
  [/\.params\[\s*'([^'\n]*)'\s*\]/g, 'param key'],
];
for (const f of walk(LIB)) {
  const src = fs.readFileSync(f, 'utf8');
  for (const [re, what] of KEY_CALLS) {
    for (const m of src.matchAll(re)) {
      if (CJK.test(m[1])) note(f, src, m.index, what + ' ' + JSON.stringify(m[1]));
    }
  }
  // glyph colour tokens are looked up by name
  for (const m of src.matchAll(/'([^'\n]*)'\s*:\s*(?:const\s+)?Color\(/g)) {
    if (CJK.test(m[1])) note(f, src, m.index, 'colour token ' + JSON.stringify(m[1]));
  }
  // catalogue band and axis names build engine parameter keys
  for (const m of src.matchAll(/(?:bands|axes)\s*=\s*\[([^\]]*)\]/g)) {
    if (CJK.test(m[1])) note(f, src, m.index, 'band/axis name');
  }
}
console.log('key literals that contain Chinese:', bad.length);
console.log(bad.join('\n') || '(none)');
// 2. every slider group a panel asks for must exist in the catalogue
const cat = fs.readFileSync(path.join(LIB, 'model/catalogue.dart'), 'utf8');
const groups = new Set();
for (const m of cat.matchAll(/catalogueSlider\('([^']*)',\s*'([^']+)'/g)) groups.add(m[2]);
for (const m of cat.matchAll(/group:\s*'([^']+)'/g)) groups.add(m[1]);
const miss = [];
for (const f of walk(LIB)) {
  const src = fs.readFileSync(f, 'utf8');
  for (const m of src.matchAll(/\.sliders\('([^']+)'/g)) {
    if (!groups.has(m[1])) miss.push(path.relative(LIB, f).replace(/\\/g, '/') + ':' + (src.slice(0, m.index).split('\n').length) + '  ' + m[1]);
  }
}
console.log('\nslider groups asked for but not declared:', miss.length);
console.log(miss.join('\n') || '(none)');
process.exit(bad.length || miss.length ? 1 : 0);
