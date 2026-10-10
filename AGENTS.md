# Selfblox 项目规则

按规范第二十三版，本文件只记项目事实、计数口径、必要限制和规范指针，不复制全局规则。

## 项目事实

- 用途：Roblox 执行器脚本 Selfblox 的源码、离线自检与文档；目标环境 Delta（安卓）最新版，纯触屏。
- 唯一入口 `selfblox.lua`：一次 `loadstring` 装七个模块（`moc` `sibs` `drift` `hud` `log` `plane` `brick`），重跑自动先卸载，手动卸载调 `_G.SB_UNLOAD()`。远程加载走 `raw.githubusercontent.com/Sumicya/Selfblox/<分支>/selfblox.lua`。
- 版本单一来源是 `selfblox.lua` 顶部的 `VERSION`，面板标题、诊断快照、启动打印都读它。
- 语法基线是 **Luau**（目标运行环境就是它）：`selfblox.lua` 用了字符串插值、复合赋值、if 表达式，`smoke.lua` 同样按 Luau 写。本地 `lua5.4` / fengari 解析不了这两个文件，别拿它们的结果当数。
- 脚本运行时写 `Selfblox.json`、`Selfblox_log.txt`、`selfblox_dump.txt`、`plane_debug.txt`，已在 `.gitignore` 里。

## 计数口径

- 五段 `yy.m.d.当日序号.总序号`，日界线按 **UTC+8**；年份两位，月日不补零。
- **一次构建 = 一轮完整交付**：改了代码或文档 → 本地 `tools/luau-driver/run_smoke.sh` 跑到「全部通过 ✓」→ 提交并推送。触发事件是「自检通过并交付」，不是 git 推送这个动作本身。
- 同一轮里重复跑自检只算一次；自检没过、没有交付的不占号；推送被拒后把同一版重推也不占号。
- 本仓库无 CI，平台侧没有构建运行记录可依据，所以两个序号由 agent 按上述触发事件递增，并在每轮汇报里写明本次是当天第几次、累计第几次。缺的是平台侧可追溯记录这一点，如实标注，不伪造序号。

## 必要限制

- **无可下载产物，无 CI**：不出包、不发版、无任何工作流（`.github/` 已删）。原因是主人 2026-10-05 裁定「lua 不需要下载不需要发版」「把你 ci 去掉」；脚本是单文件、从 raw 现拉现跑，打成 artifact 只会得到一份逐字节重复、还要额外养清理的副本。恢复 CI 或出包前先报主人。规范「只读是权限原则，不是删除测试的理由」与本裁定的关系已报过主人，按「用户明确指示优先于本规范」维持现状。
- **离线自检的唯一权威跑法是本地 `tools/luau-driver/`**：`bash build.sh` 编一次 Luau 0.741（约 40 秒），之后每次改完 `bash run_smoke.sh`（约 0.3 秒）。最后一行「全部通过 ✓」才算过；有断言没过时 `smoke.lua` 会 `error` 退出、退出码非零，所以别只看退出码不看输出。换 Luau 版本要连 `smoke.lua` 一起复跑。
- 假引擎为「Luau 与真引擎的差异」做的两处适配**不要当 bug 改回去**：① `smoke.lua` 的 `mt.__newindex` 写 `CFrame` 时就地更新旧对象——经 `loadstring` 装载的 chunk 里，全常量且不超过 3 段的键链首次求值后会被冻住，第二次读返回旧对象、`__index` 不再触发；真引擎的属性不是 Lua 表链，没这回事。② `FireServer` 参数断言按引擎分判——`typeof` 在 Luau 里是内建函数、假引擎盖不住，假 `Vector3` 只会被认成 `table`；真引擎里就是 `"Vector3"`。
- 批量改写的坑：`x = x - a + b` **不能**写成 `x -= a + b`（右边有多个顶层项时符号会变），`smoke.lua` 的 `FIXED` 那行被这样写坏过、由 12/24 小时制两条断言抓出来。
- 降级取舍：关闭 PR#2 里那套「删兜底」的改法**没有采纳**，本仓库保留兜底。要删任何一条兜底前先确认最坏失败模式不是不可恢复（宁可功能不生效，不要弄坏系统），并先报主人。
- 遗留 2 个 `Selfblox-26.10.5.32.32` artifact：沙箱里的 gh 令牌没有 `actions: write`，`DELETE /actions/artifacts/<id>` 回 403 删不掉，删除命令已交主人自己跑。
- **未验证**：Delta 内置的 Luau 版本号（插值需要 2023 年之后的版本才有，真机报语法错就是这条）；真机手感。

规范指针：全局规则唯一权威是 `Sumicya/selfs` 默认分支的 `GLOBAL.md`，按其最新版执行。

- 本仓库上次同步 = 第二十三版。
