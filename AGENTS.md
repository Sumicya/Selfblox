# Selfblox 项目规则

- 本仓库用途：Roblox 执行器脚本 Selfblox 的源码、离线自检与文档，面向 Delta（安卓）最新版，纯触屏。
- 唯一入口 `selfblox.lua`：一次 `loadstring` 装七个模块（`moc` `sibs` `drift` `hud` `log` `plane` `brick`），重跑自动先卸载，手动卸载调用 `_G.SB_UNLOAD()`。
- 版本单一来源：`selfblox.lua` 顶部的 `VERSION`，五段 `yy.m.d.当日序号.总序号`，展示不带 `v`，标签为 `v` 加版本号；本仓库无发布工作流，两个序号手工计数，口径写在 README「版本」。
- 产物不是 APK：远程加载入口是 `raw.githubusercontent.com` 上的 `selfblox.lua`；不发 Release，文档里不写 Release 下载入口。脚本运行时写 `Selfblox.json`、`Selfblox_log.txt`、`selfblox_dump.txt`、`plane_debug.txt`，已在 `.gitignore` 里。
- 离线自检：`lua5.4 smoke.lua`（假 Roblox 引擎，不连游戏）；CI 里跑同一份，保持只读权限。
- 代码保持 Lua 5.4 可解析子集（不用 `+=` / `continue` / 字符串插值），否则离线自检跑不起来；要用 Luau 专属语法先改自检方案。
- 本仓库上次同步 = 第十五版。

规范指针：全局规则唯一权威是 `Sumicya/selfs` 的 `GLOBAL.md`，按其最新版执行；本文件只保留本仓库专属条目，不复制全局规则。
