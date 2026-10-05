# Selfblox 项目规则

- 本仓库用途：Roblox 执行器脚本 Selfblox 的源码、离线自检与文档，面向 Delta（安卓）最新版，纯触屏。
- 唯一入口 `selfblox.lua`：一次 `loadstring` 装七个模块（`moc` `sibs` `drift` `hud` `log` `plane` `brick`），重跑自动先卸载，手动卸载调用 `_G.SB_UNLOAD()`。
- 版本单一来源：`selfblox.lua` 顶部的 `VERSION`，五段 `yy.m.d.当日序号.总序号`，展示不带 `v`，标签为 `v` 加版本号；本仓库无发布工作流，两个序号手工计数，口径写在 README「版本」。
- 产物不是 APK：远程加载入口是 `raw.githubusercontent.com` 上的 `selfblox.lua`；不发 Release，文档里不写 Release 下载入口。脚本运行时写 `Selfblox.json`、`Selfblox_log.txt`、`selfblox_dump.txt`、`plane_debug.txt`，已在 `.gitignore` 里。
- 离线自检：`smoke.lua`（假 Roblox 引擎，不连游戏）。**权威跑法是 CI 的 `smoke` 作业：下载官方 Luau 0.741 跑同一份**（版本钉死在工作流里，换版本要连 `smoke.lua` 一起复跑）；本地沙箱装不了 Luau，`lua5.4 smoke.lua` 只能当代码还是 5.4 子集时的补充手段，两个 VM 结果不一致时以 Luau 为准。CI 只读权限。
- 语法基线是 **Luau**（目标运行环境就是它）：主人已明确允许使用 `+=` / `continue` / 字符串插值等 Luau 专属写法，前提是自检在 CI 的 Luau 上跑通。改成 Luau 专属语法后本地 `lua5.4` 就解析不了了，别再拿本地 5.4 的结果当数。
- 降级路径的取舍按主人裁决办：关闭 PR#2 里那套「删兜底」的改法**没有采纳**，本仓库保留兜底。按规范第十七版「不做冗余降级」，要删任何一条兜底前先确认最坏失败模式不是不可恢复（宁可功能不生效，不要弄坏系统），并先报主人。
- 本仓库上次同步 = 第十七版。

规范指针：全局规则唯一权威是 `Sumicya/selfs` 的 `GLOBAL.md`，按其最新版执行；本文件只保留本仓库专属条目，不复制全局规则。
