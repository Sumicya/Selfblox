# Selfblox 项目规则

按规范第二十三版，本文件只记项目事实、计数口径、必要限制和规范指针，不复制全局规则。

## 项目事实

- 用途：Roblox 执行器脚本 Selfblox 的源码、离线自检与文档；目标环境 Delta（安卓）最新版，纯触屏。
- 唯一入口 `selfblox.lua`：一次 `loadstring` 装七个模块，重跑自动先卸载。远程加载走 `raw.githubusercontent.com/Sumicya/Selfblox/<分支>/selfblox.lua`。
- 版本单一来源是 `selfblox.lua` 顶部的 `VERSION`。

## 计数口径

- 五段 `yy.m.d.当日序号.总序号`，日界线按 UTC+8。

## 必要限制

- 无可下载产物，无 CI：不出包、不发版。用户明确指示优先。

规范指针：全局规则唯一权威是 `Sumicya/selfs` 默认分支的 `GLOBAL.md`，按其最新版执行。

- 本仓库上次同步 = 第二十三版。
