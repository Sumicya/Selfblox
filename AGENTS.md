# Selfblox 项目规则

按规范第0版，本文件只记项目事实、必要限制和规范指针，不复制全局规则。

## 项目事实

- 用途：Roblox 执行器脚本 Selfblox 的源码、离线自检与文档；目标环境 Delta（安卓）最新版，纯触屏。
- 唯一入口 `selfblox.lua`：一次 `loadstring` 装七个模块（`moc` `sibs` `drift` `hud` `log` `plane` `brick`），重跑自动先卸载，手动卸载调 `_G.SB_UNLOAD()`。远程加载走 `raw.githubusercontent.com/Sumicya/Selfblox/<分支>/selfblox.lua`。
- 版本单一来源是 `selfblox.lua` 顶部的 `VERSION`，面板标题、诊断快照、启动打印都读它。
- 语法基线是 **Luau**（目标运行环境就是它）：`selfblox.lua` 用了字符串插值、复合赋值、if 表达式，`smoke.lua` 同样按 Luau 写。本地 `lua5.4` / fengari 解析不了这两个文件，别拿它们的结果当数。
- 脚本运行时写 `Selfblox.json`、`Selfblox_log.txt`、`selfblox_dump.txt`、`plane_debug.txt`，已在 `.gitignore` 里。

## 计数口径

本仓库无产物、无 CI，规范第0版修订的取数锚是 CI 的 `run_number`，这里没有，按「基线切换时定死，写入各仓 AGENTS.md」在本地定死等价锚：

- 五段 `yy.m.d.当日序号.总序号`，日界线按 **UTC+8**；年份两位，月日不补零。
- 一次本地构建 = 一轮交付：改代码或文档 → 跑 `tools/luau-driver/run_smoke.sh` → 出一个提交、一个版本。同一轮里为定位问题反复跑自检算同一次构建。
- 当日序号：本提交在会话分支**当日（UTC+8）提交序列中的位次**，当天所有提交都算。
- 总序号：本提交在会话分支**提交序列中的位次 − 基线 12**。基线定死于 `26.10.13.11.52`：分支第 63 号提交 `8268cf5` = 总序号 51。
- 旧锚「只数历史上自检通过并出了版本的构建数」已被第0版修订停用，不再使用。
- 位次可追溯：`git rev-list --count origin/arena/01a10a41-selfblox`。

## 必要限制

- **无可下载产物，不出包不发版**：主人 2026-10-05 裁定「lua 不需要下载不需要发版」「把你 ci 去掉」。脚本是单文件、从 raw 现拉现跑，打成 artifact 只会得到一份逐字节重复、还要额外养清理的副本。出包或发版前先报主人。
- **CI 现状按规范第0版核对过，本分支合规**：本分支树里没有 `.github/`——`git ls-tree origin/arena/01a10a41-selfblox -- .github` 输出为空，API 查 `.github/workflows?ref=arena/01a10a41-selfblox` 回 404，符合「无产物/无 CI 仓清零、禁止新增工作流」和「CI 只服务构建与清理，不设规范检查等冗余流程」。`main` 上还留着主人 `fed6bb7e` 加的 `spec-check.yml`（API 查 `?ref=main` 有），合并 PR 时随之消失。
- **分支保留 0 已满足**：仓库只剩 `main` 和本分支（PR #4 open）。PR #1/#2/#3 的会话分支都已不存在。按第0版修订「PR 合并或关闭后删除对应会话分支」，PR #4 合并或关闭后本分支该删；删 ref 权限实测有（对不存在的 ref 发 `DELETE /git/refs/heads/...` 回 `422`，不是 `403`）。
- **运行记录 / artifact / 工作流注册现均为 0**：主人 2026-10-13 手动跑完清理，54 条 run 全删，`Build`/`smoke`/`spec-check` 三条工作流注册随之消失，原有 2 个 `Selfblox-26.10.5.32.32` artifact 也已删。
- **这类清理沙箱做不了，每次得交主人跑**：`DELETE /actions/runs/<id>` 和 `DELETE /actions/artifacts/<id>` 实测都回 `403 Forbidden`，令牌没有 `actions: write`（仓库 `permissions` 显示 `admin: true`，但令牌本身没这个 scope）。删 ref 不一样，那个有权限。
- **离线自检的唯一权威跑法是本地 `tools/luau-driver/`**：`bash build.sh` 编一次 Luau 0.741（约 40 秒），之后每次改完 `bash run_smoke.sh`（约 0.3 秒）。最后一行「全部通过 ✓」才算过；有断言没过时 `smoke.lua` 会 `error` 退出、退出码非零，所以别只看退出码不看输出。换 Luau 版本要连 `smoke.lua` 一起复跑。
- 假引擎为「Luau 与真引擎的差异」做的两处适配**不要当 bug 改回去**：① `smoke.lua` 的 `mt.__newindex` 写 `CFrame` 时就地更新旧对象——经 `loadstring` 装载的 chunk 里，全常量且不超过 3 段的键链首次求值后会被冻住，第二次读返回旧对象、`__index` 不再触发；真引擎的属性不是 Lua 表链，没这回事。② `FireServer` 参数断言按引擎分判——`typeof` 在 Luau 里是内建函数、假引擎盖不住，假 `Vector3` 只会被认成 `table`；真引擎里就是 `"Vector3"`。
- 批量改写的坑：`x = x - a + b` **不能**写成 `x -= a + b`（右边有多个顶层项时符号会变），`smoke.lua` 的 `FIXED` 那行被这样写坏过、由 12/24 小时制两条断言抓出来。
- 降级取舍：关闭 PR#2 里那套「删兜底」的改法**没有采纳**，本仓库保留兜底。要删任何一条兜底前先确认最坏失败模式不是不可恢复（宁可功能不生效，不要弄坏系统），并先报主人。
- **未验证**：Delta 内置的 Luau 版本号（插值需要 2023 年之后的版本才有，真机报语法错就是这条）；真机手感。

规范指针：全局规则唯一权威是 `Sumicya/selfs` 默认分支的 `GLOBAL.md`，按其最新版执行。

- 本仓库上次同步 = 第0版（含 `1984b03a` 修订：计数改锚 run_number、分支保留 0、清理默认授权）。
