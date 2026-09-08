/* Runs the OQV2 Lua test-suite on a real Lua 5.3 VM (fengari) with stubbed natives. */
const fs = require('fs'), path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

const RES  = require('./resource-path').resolveResource(process.argv[2]);
const ROOT = path.dirname(RES);

function run(file, label) {
  const src = fs.readFileSync(file, 'utf8');
  let status = lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring('@' + (label || file)));
  if (status !== lua.LUA_OK) {
    console.error('LOAD ERROR ' + file + ': ' + lua.lua_tojsstring(L, -1));
    process.exit(1);
  }
  status = lua.lua_pcall(L, 0, 0, 0);
  if (status !== lua.LUA_OK) {
    console.error('RUNTIME ERROR ' + file + ':\n  ' + lua.lua_tojsstring(L, -1));
    process.exit(1);
  }
}

// 1. stubs
run(path.join(__dirname, 'lua-stubs.lua'), 'stubs');

// expose resource files to LoadResourceFile (fengari has no io.open)
lua.lua_getglobal(L, to_luastring('TEST'));
lua.lua_pushstring(L, to_luastring(RES));
lua.lua_setfield(L, -2, to_luastring('resourcePath'));
lua.lua_newtable(L);
for (const f of fs.readdirSync(path.join(RES, 'locales'))) {
  lua.lua_pushstring(L, to_luastring(fs.readFileSync(path.join(RES, 'locales', f), 'utf8')));
  lua.lua_setfield(L, -2, to_luastring('locales/' + f));
}
lua.lua_setfield(L, -2, to_luastring('files'));
lua.lua_pop(L, 1);

// 2. resource files, in fxmanifest order
const ORDER = [
  'config/config.lua', 'config/missions.lua', 'config/locations.lua', 'config/npcs.lua',
  'shared/utils.lua', 'shared/schema.lua',
  'server/sv_database.lua', 'server/sv_core.lua', 'server/sv_progression.lua',
  'server/sv_missions.lua', 'server/sv_npcs.lua', 'server/sv_admin.lua', 'server/sv_commands.lua',
];
for (const f of ORDER) run(path.join(RES, f), 'oqv2_quests/' + f);

// 3. tests
run(path.join(__dirname, 'lua-test.lua'), 'lua-test');

lua.lua_getglobal(L, to_luastring('TEST'));
lua.lua_getfield(L, -1, to_luastring('exitCode'));
const code = lua.lua_tointeger(L, -1);
process.exit(Number(code) || 0);
