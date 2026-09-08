/* Locates the oqv2_quests resource folder no matter where the tools live
   (repo root `tools/`, or `_dev/tools/` inside the distributed bundle). */
const fs = require('fs'), path = require('path');

function resolveResource(explicit) {
  if (explicit) return path.resolve(explicit);

  const seen = [];
  let dir = __dirname;
  for (let i = 0; i < 6; i++) {
    const candidate = path.join(dir, 'oqv2_quests');
    seen.push(candidate);
    if (fs.existsSync(path.join(candidate, 'fxmanifest.lua'))) return candidate;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  throw new Error(
    'Could not find the oqv2_quests resource folder. Looked in:\n  ' + seen.join('\n  ') +
    '\nPass the path explicitly, e.g. `node tools/lualint.js ../oqv2_quests`.'
  );
}

module.exports = { resolveResource };
