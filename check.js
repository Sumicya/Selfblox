// 跑 selfblox.lua 的检查: node check.js
// 需要 fengari (纯 JS 的 Lua VM):  npm i fengari
// 三个场景各起一个干净的 VM: 默认 / _G.SB 覆盖 / 已有 Selfblox.json
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const ROOT = __dirname;
const read = (f) => fs.readFileSync(path.join(ROOT, f), 'utf8');

const SCENARIOS = {
  default: null,
  override: `_G.SB = { spd = 60, flyspd = 120, spdmode = "cframe", only = { "moc", "sibs", "hud" } }`,
  json: `_G._SB.FILES["Selfblox.json"] = '{"spd":99,"tab":"sibs","pos":[120,340],"logint":1}'`,
};

function run(name, setup) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const die = (what) => {
    let msg;
    try { msg = to_jsstring(lua.lua_tostring(L, -1)); }
    catch (_) { msg = Buffer.from(lua.lua_tostring(L, -1)).toString('utf8'); } // 错误信息里可能有半个多字节字符
    throw new Error(what + ': ' + msg);
  };
  const chunk = (src, label) => {
    if (lauxlib.luaL_loadstring(L, to_luastring(src), to_luastring('@' + label)) !== lua.LUA_OK) die('语法 ' + label);
    if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) die('运行 ' + label);
  };
  lua.lua_pushstring(L, to_luastring(name));
  lua.lua_setglobal(L, to_luastring('_SCENARIO'));
  chunk(read('stub.lua'), 'stub.lua');
  if (setup) chunk(setup, 'setup(' + name + ')');
  chunk(read('selfblox.lua'), 'selfblox.lua');
  chunk(read('check.lua'), 'check.lua');

  lua.lua_getglobal(L, to_luastring('_CHECK'));
  const n = lua.lua_rawlen(L, -1);
  lua.lua_pop(L, 1);
  lua.lua_close(L);
  return { n };
}

let bad = 0;
for (const [name, setup] of Object.entries(SCENARIOS)) {
  try {
    const { n } = run(name, setup); // 报告由 check.lua 直接 io.write, 这里不再重复打一遍
    if (n !== 0) bad++;
  } catch (e) {
    console.log('FAIL  场景=' + name + '  炸了: ' + e.message.split('\n')[0]); if (process.env.VERBOSE) console.log(e.stack);
    bad++;
  }
}
console.log(bad === 0 ? '\n全部场景通过' : `\n${bad} 个场景没过`);
process.exit(bad === 0 ? 0 : 1);
