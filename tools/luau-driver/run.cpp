// 与官方 luau CLI 行为一致的最小驱动 (照抄 CLI/src/Repl.cpp 的 setupState + runFile):
//   luaL_openlibs -> 注册同实现的 loadstring -> luaL_sandbox -> lua_newthread + luaL_sandboxthread -> lua_resume
// 少了 luaL_sandboxthread 那步, 全局表会是只读, smoke.lua 直接起不来。
#include "lua.h"
#include "luacode.h"
#include "lualib.h"
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>

static int lua_loadstring(lua_State* L)
{
    size_t l = 0;
    const char* s = luaL_checklstring(L, 1, &l);
    const char* chunkname = luaL_optstring(L, 2, s);
    lua_setsafeenv(L, LUA_ENVIRONINDEX, false);
    size_t bl = 0;
    char* b = luau_compile(s, l, nullptr, &bl);
    if (bl > 0 && b && b[0] != 0 && luau_load(L, chunkname, b, bl, 0) == 0)
        return 1;
    lua_pushnil(L);
    lua_pushlstring(L, b ? b : "compile failed", bl);
    return 2;
}

int main(int argc, char** argv)
{
    if (argc < 2) { printf("用法: luau <file.lua>\n"); return 2; }
    lua_State* L = luaL_newstate();
    luaL_openlibs(L);
    lua_pushcfunction(L, lua_loadstring, "loadstring");
    lua_setglobal(L, "loadstring");
    luaL_sandbox(L);
    std::ifstream f(argv[1], std::ios::binary);
    if (!f) { printf("打不开 %s\n", argv[1]); return 2; }
    std::stringstream ss; ss << f.rdbuf();
    std::string src = ss.str();
    size_t bcs = 0;
    char* bc = luau_compile(src.data(), src.size(), nullptr, &bcs);
    if (bcs == 0 || bc[0] == 0) { printf("编译失败: %s\n", (bc && bc[0] == 0) ? bc + 1 : "(空)"); return 1; }
    lua_State* GL = L;
    L = lua_newthread(GL);
    luaL_sandboxthread(L);
    std::string name = std::string("=") + argv[1];
    if (luau_load(L, name.c_str(), bc, bcs, 0) != 0) { printf("%s\n", lua_tostring(L, -1)); return 1; }
    if (lua_resume(L, nullptr, 0) != 0) { printf("%s\n", lua_tostring(L, -1)); return 1; }
    return 0;
}
