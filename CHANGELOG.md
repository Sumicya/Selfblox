# Changelog

现行决定 + 历史记录。黑历史不删，更正加新条。

## 2026-11-08

- 新增 `gun` 模块（枪页）：无限子弹（Tool/leaderstats 弹药 Value/属性自动回填 + `getgc` 配置表深改，关闭还原）；子弹穿墙（共享 `__namecall` 钩子拦 `workspace.Raycast`，排除列表续射至角色，白名单射线与 Include 语义不改，`checkcaller` 滤执行器自身调用，内部点调用防递归）；探针报告 `gun_debug.txt` + 剪贴板。新键 `ammo`(999)、`pierce`(16)。
- `plane` 发侦听改用共享 `__namecall` 钩子（`ncAdd`/`ncDel`），修复与 gun 钩子互相覆盖/卸载错还原的问题；`fmt`/`args`/`push`/`hint` 提升为公共函数。
- `hold` 按钮按 InputObject 配对释放，多指不再互相串；窗口失焦兜底释放；按下回调加 pcall。
- 载具滑条转向按实际尺寸计算并钳位，替换写死的 82；无 `UIDragDetector` 的老客户端不显示死滑条。
- sibs 探地/准星射线改点调用，不被 gun 穿墙钩子改写。
- 文档整改：README 去版本号、维护记录迁本文件、补 `turncap`/`carmaxstuds` 行、末行加规范指针；补 GPL-3.0 LICENSE（全文取自 selfs 生效提交）。
- 新增 `tools/deadscan.py`（local 死标识符扫描，盲区写在文件头）。
- 验证：Luau WASM `loadstring` 编译通过；deadscan 0；真机未验证（无 Roblox 环境）。

## 历史（自 README 迁入）

- 生命周期修复：卸载时释放长按输入；提示延时回调检查卸载状态；相机初始化允许暂时缺失。
- 任务清理：刷砖循环使用 generation token 防止开关快速切换造成重入，并在异常后执行清理；旧循环不会覆盖新循环状态。
- 状态恢复：速度与跳跃独立恢复；夜视只恢复原先记录的 Atmosphere 实例。
- 侦察与 IO：自动扫描不再每 5 秒自动写报告；Remote 监听按差异更新；配置与报告文件写入增加错误处理。
- 文档：修正 `carclip` 默认值说明。
- v11 → v12 砍掉的：7 个文件 → 1 个；每文件自带的配置/拖拽/输入样板全删，UI 拖拽用原生 `UIDragDetector`；sibs 的自动锁车/所有权嗅探/车辆列表/学习缓存 → 只剩「坐着」和「准星换车」；各种人为上限（换车距离、扫描数量、飞行防穿减速、转向门槛、速度地板）全没了，参数随便填；键盘/手柄输入路径（纯触屏）；日志归档、KITCFG2 配置格式、v10 迁移；引擎音调、边缘计数、Drawing 库 ESP。
