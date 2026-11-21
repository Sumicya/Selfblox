# 变更记录

现行决定 + 历史记录。黑历史不删，更正加新条。

- 本仓不出包，产物命名与版本号规则没有适用对象；不新增构建工作流。

## 2026-11-21

- 对齐 `Sumicya/selfs` PR #15 最新生效提交 `ccb9aebad23519b2a0d5ae597d349c7eda822092`：
  - `tools/deadscan.py` 新增仓库根目录（`.`）及越界路径拦截（§12 `path` 可指目录但不许指仓根）与 Markdown 相对链接（死引用）检查，并将 `num`/`key` 注册纳入 `save()` 配对校验；
  - 重整 `README.md` 满足 §19 四大节结构（`是什么`/`从哪下`/`怎么装`/`怎么删`，将必要限制与许可证并入「是什么」下级），清除「志」行中文分号（`ste80` 禁分号），并将末行规范指针更新至 `ccb9aebad23519b2a0d5ae597d349c7eda822092`；
  - 其余文件（`selfblox.lua`、`tools/blindspots.json`、`LICENSE`、`.gitignore`）未动；按 §16 本轮为纯文档与检查工具对齐，脚本 `VERSION` 保持 `26.11.16.1.118`。

## 2026-11-16

- 按主人裁决合并两条分叉工作：以 PR #6（`arena/2a114e80-selfblox` @ `89d6a02`，106 提交）表驱动主线为底，合入 `arena/708dd342-selfblox`（`c63a1bf`）工作，不保留 `brick`（砖页）。
- 在 `selfblox.lua` 表驱动注册表中新增 `gun`（枪页：`ginf` 无限子弹 + `gwall` 子弹穿墙 + 重扫字段 + `gun_debug.txt` 探针报告 + `DUMP` 注册）；提升共享 `__namecall` 钩子（`ncAdd`/`ncDel`）与公共辅助（`hint`/`idx`/`fmt`），让 `gun` 与 `plane` 共用同一元方法钩子不再互相覆盖；将 `sibs` 准星射线改为点调用（`workspace.Raycast`）避免被 `gun` 钩子改写并补充相机为空保护；补齐 `hold` 多指 `InputObject` 配对、`WindowFocusReleased` 释放与按下回调 `pcall`；补齐 `log`/`plane`/`dumpNow` 的文件读写与剪贴板 `pcall` 守卫；清理 `aim` 未使用局部变量与 `BUILT` 赋值警告；脚本内 `VERSION` 更新为 `26.11.16.1.118`。
- 删除 `.github/workflows/pr-check.yml`（冗余 PR 检查工作流，符合 `Sumicya/selfs` §14/§18 要求）。
- 引入 `tools/deadscan.py` 并修复其对 Luau 反引号插值字符串的词法剥离（解决 `--` 在反引号内被误判为注释导致截断后续代码的问题），同时检查 Python 未使用 `import`、只写不读配置键，并校验新增的 `tools/blindspots.json`（按 `Sumicya/selfs` §12 分三类记录 `有意排除`/`延期未审`/`待答问题` 与剩余限制）。
- 按 `Sumicya/selfs` PR #15 `8a68a96` 重整 `README.md`（聚焦是什么/从哪下/怎么装/怎么删 + 必要限制 + GPL-3.0 + `/storage/emulated/0/Download` 完整路径 + 最新规范指针，移除版本号与构建流程段落）。
- 验证：官方 Luau 0.747 `luau-compile` 编译通过、`luau-analyze` 无未使用变量/赋值失衡告警、`python3 tools/deadscan.py` 退出码 0（且在 `/tmp` 构造反例可正确报红退出码 1）；Android Delta 与 Roblox 真机运行时行为未验证。
- 对齐 `Sumicya/selfs` `30ddbc3` 新 §12：将 `tools/blindspots.json` 键名与字段统一为 `excluded`/`deferred`/`open_questions` 及 `path`/`why`/`limit`，更新 `tools/deadscan.py` 校验三类非空、真实存在路径及两栏字段，更新 `README.md` 规范指针至 `30ddbc3`，并按主人指示关闭 PR #6（不合并）与删除前分支 `arena/2a114e80-selfblox`、`arena/708dd342-selfblox`。

## 2026-11-08（来自 `arena/708dd342-selfblox`）

- 新增 `gun` 模块（枪页）：无限子弹（Tool/leaderstats 弹药 Value/属性自动回填 + `getgc` 配置表深改，关闭还原）；子弹穿墙（共享 `__namecall` 钩子拦 `workspace.Raycast`，排除列表续射至角色，白名单射线与 Include 语义不改，`checkcaller` 滤执行器自身调用，内部点调用防递归）；探针报告 `gun_debug.txt` + 剪贴板。新键 `ammo`(999)、`pierce`(16)。
- `plane` 发侦听改用共享 `__namecall` 钩子（`ncAdd`/`ncDel`），修复与 gun 钩子互相覆盖/卸载错还原的问题；`fmt`/`args`/`push`/`hint` 提升为公共函数。
- `hold` 按钮按 InputObject 配对释放，多指不再互相串；窗口失焦兜底释放；按下回调加 pcall。
- 载具滑条转向按实际尺寸计算并钳位，替换写死的 82；无 `UIDragDetector` 的老客户端不显示死滑条。
- sibs 探地/准星射线改点调用，不被 gun 穿墙钩子改写。
- 新增 `tools/deadscan.py`；补 GPL-3.0 LICENSE。

## 2026-10-31（来自 `arena/2a114e80-selfblox`）

- 补充项目变更记录与脚本修改说明，明确版本手动计数和验证边界。
- 统一 GPL-3.0 许可证全文，与 Qself 版本一致。

## 2026-10-26（来自 `arena/2a114e80-selfblox`）

- 新增「弹」页：以可调的转向速率、视角、距离和提前量追踪实体弹丸。
- 继承单文件脚本版本及其 GPL-3.0 许可证。
- 移除假引擎自检、临时驱动与旧图；版本序号改为随功能交付手动计数。

## 历史（自早期 `README.md` 迁入）

- 生命周期修复：卸载时释放长按输入；提示延时回调检查卸载状态；相机初始化允许暂时缺失。
- 任务清理：刷砖循环使用 generation token 防止开关快速切换造成重入，并在异常后执行清理；旧循环不会覆盖新循环状态。
- 状态恢复：速度与跳跃独立恢复；夜视只恢复原先记录的 Atmosphere 实例。
- 侦察与 IO：自动扫描不再每 5 秒自动写报告；Remote 监听按差异更新；配置与报告文件写入增加错误处理。
- 文档：修正 `carclip` 默认值说明。
- v11 → v12 砍掉的：7 个文件 → 1 个；每文件自带的配置/拖拽/输入样板全删，UI 拖拽用原生 `UIDragDetector`；sibs 的自动锁车/所有权嗅探/车辆列表/学习缓存 → 只剩「坐着」和「准星换车」；各种人为上限（换车距离、扫描数量、飞行防穿减速、转向门槛、速度地板）全没了，参数随便填；键盘/手柄输入路径（纯触屏）；日志归档、KITCFG2 配置格式、v10 迁移；引擎音调、边缘计数、Drawing 库 ESP。
