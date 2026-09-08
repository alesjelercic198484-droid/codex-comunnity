const fs = require('fs'), path = require('path');
const luaparse = require('luaparse');
const root = process.argv[2] || 'oqv2_quests';
let files = [];
(function walk(d){ for (const f of fs.readdirSync(d)) { const p = path.join(d,f); const s = fs.statSync(p);
  if (s.isDirectory()) walk(p); else if (f.endsWith('.lua')) files.push(p); } })(root);
let errors = 0;
for (const f of files.sort()) {
  const src = fs.readFileSync(f,'utf8');
  try {
    luaparse.parse(src, { luaVersion: '5.3', comments: false, locations: true });
    console.log('  OK   ' + f);
  } catch (e) {
    errors++;
    console.log('  FAIL ' + f + '  -> ' + e.message);
  }
}
console.log('\n' + files.length + ' lua files, ' + errors + ' syntax error(s)');
process.exit(errors ? 1 : 0);
