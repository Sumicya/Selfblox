# Selfblox 项目规则

- 本仓库用途：Roblox 执行器脚本 Selfblox 的源码、离线自检与文档，面向 Delta（安卓）最新版，纯触屏。
- 唯一入口 `selfblox.lua`：一次 `loadstring` 装七个模块（`moc` `sibs` `drift` `hud` `log` `plane` `brick`），重跑自动先卸载，手动卸载调用 `_G.SB_UNLOAD()`。
- 版本单一来源：`selfblox.lua` 顶部的 `VERSION`，五段 `yy.m.d.当日序号.总序号`，展示不带 `v`，标签为 `v` 加版本号；本仓库无发布工作流，两个序号手工计数，口径写在 README「版本」。
- 产物不是 APK：远程加载入口是 `raw.githubusercontent.com` 上的 `selfblox.lua`；不发 Release，文档里不写 Release 下载入口。脚本运行时写 `Selfblox.json`、`Selfblox_log.txt`、`selfblox_dump.txt`、`plane_debug.txt`，已在 `.gitignore` 里。
- 离线自检：`smoke.lua`（假 Roblox 引擎，不连游戏）。**权威跑法是 CI 的 `smoke` 作业：下载官方 Luau 0.741 跑同一份**（版本钉死在工作流里，换版本要连 `smoke.lua` 一起复跑）。本地也能跑同版本 Luau（旧记录「本地沙箱装不了 Luau」已作废）：官方 release 的资源域名在沙箱里下不动（回 0 字节），但 `codeload.github.com` 通，取 0.741 源码后自建一个约 30 行驱动、用 `g++ -O1 -std=c++17 -ICommon/include -IVM/include -ICompiler/include -IAst/include -IBytecode/include <驱动> Ast/src/*.cpp Common/src/*.cpp VM/src/*.cpp Compiler/src/*.cpp Bytecode/src/*.cpp` 就能编出与 CI 行为一致的解释器。驱动必须照抄官方 CLI 的 `setupState` + `runFile`：`luaL_openlibs` → 注册同实现的 `loadstring` → `luaL_sandbox` → `lua_newthread` + `luaL_sandboxthread` → `lua_resume`；少了 `luaL_sandboxthread` 那步，全局表会变成只读、`smoke.lua` 直接跑不起来。跑法与 CI 一致：把 `selfblox.lua` 用 `[====[ … ]====]` 注入成 `SB_SRC_INJECTED` 再接上 `smoke.lua`。CI 只读权限。
- 语法基线是 **Luau**（目标运行环境就是它）：`selfblox.lua` 从 `26.10.5.28` 起确实用上了 Luau 专属写法——字符串插值（`` `a{x}b` ``，63 处）与复合赋值（`+=`，4 处）。因此本地 `lua5.4` / fengari **已解析不了本文件**，别再拿它们的结果当数；本地要验就用上面那条自编的 Luau。**未验证**：Delta 内置的 Luau 版本号我拿不到证据，插值需要较新的 Luau（2023 年之后的版本才有），若真机上报语法错就是这条，回退方式是把该次改写单独 revert。
- 假引擎为「Luau 与真引擎的差异」做的两处适配，都带上游出处，别当成 bug 改回去：① `smoke.lua` 的 `mt.__newindex` 写 `CFrame` 时会就地更新旧对象——Luau 把 `a.b.c` 这种全常量键链编译成 `GETIMPORT`，本地实测：经 `loadstring` 装载的 chunk 里，同一条链首次求值后就被冻住（第二次读返回旧对象、`__index` 一次都不再触发），而主 chunk 里直接读每次都新鲜。相关上游：`VM/src/lvmexecute.cpp:489-508`（`LOP_GETIMPORT` 的常量池快路径）、`VM/src/lvmload.cpp:91`（`luaV_getimport` 自身不缓存、且最多 3 段）。真引擎的属性不是 Lua 表链，没这回事。② `FireServer` 参数断言按引擎分判——`typeof` 在 Luau 里是内建函数（`VM/src/lbuiltins.cpp:887`，编译器还按名字认它：`Compiler/src/Builtins.cpp:78`），假引擎盖不住，假 `Vector3` 只会被认成 `table`；真引擎里 `typeof(Vector3)` 就是 `"Vector3"`，所以只在 Lua 5.4 下严判 `(1,2,3)`。
- 降级路径的取舍按主人裁决办：关闭 PR#2 里那套「删兜底」的改法**没有采纳**，本仓库保留兜底。按规范第十七版「不做冗余降级」，要删任何一条兜底前先确认最坏失败模式不是不可恢复（宁可功能不生效，不要弄坏系统），并先报主人。
- 本仓库上次同步 = 第十七版。

规范指针：全局规则唯一权威是 `Sumicya/selfs` 的 `GLOBAL.md`，按其最新版执行；本文件只保留本仓库专属条目，不复制全局规则。
