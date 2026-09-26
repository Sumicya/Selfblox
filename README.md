# Selfblox v11

Roblox 客户端脚本套件，**激进重写**（ponytail 标准）：

- **无框架**：没有 kit/core。每个文件自包含，直接 `loadstring` 执行，互不依赖。
- **无构建**：仓库里的 `.lua` 文件本身就是最终产物。没有 build、没有 dist、没有冒烟 harness。
- **现代 Luau**：`Instance.new(cls, props)`、`+=`、`continue`、泛型 for、`task.*`、`table.clear`。
- **原生化**：只碰原生 API 与执行器原生 API（`Drawing` / `gethui` / `writefile` / `keypress` / `hookmetamethod` …），不再有包装层。

> 从 v10 升级：旧文件不需要清理（重跑同名脚本会自动替换旧 GUI）；
> 旧配置 `KIT_Config.txt` 首次加载时自动并入新文件 `Selfblox_cfg.txt`。

## 文件

| 文件 | 功能 |
|---|---|
| `moc.lua` | 移动：速度（RootVelocity / WalkSpeed / CFrame 三档）、飞行（含碰撞防穿模）、高跳、无限跳、穿墙、角色旋转、夜视、秒互动（off/普通/强制） |
| `sibs.lua` | 载具：扫描/锁定/换车/车列表、加速/减速/抓地、转向滑条、定速、急刹、穿墙（+悬浮）、飞车、翻转 180°、灯光（常亮/闪/O 键）、喇叭（探测/常声/声/H 键）、引擎音调、无角色自动锁定与重连 |
| `plane.lua` | 飞机侦察：模型体检评分、队伍推断（属性/Value/乘员/名字/涂装）、Remote 清单、FireServer 发送间谍（`hookmetamethod`）、OnClientEvent 接收监听、报告写 `plane_debug.txt`/剪贴板、队伍高亮、自动扫描+自动写 |
| `drift.lua` | 漂移：W/S（或手机踏板）推进力、自适应增推、失速补偿、MobilePedals 自动绑定 |
| `log.lua` | 连续日志：每 N 秒采样所有模块调试块 → `KIT_Log.txt`（512KB × 3 归档滚动） |
| `brick.lua` | BitFarmer 刷砖：事件驱动即时收集 + 高频刷砖 + 倍率锁定。**再次执行 = 停止** |
| `hud.lua` | 显示层：数据条（ping/fps/内存/时间/人数/坐标）+ 速度箭头（原生 GUI）+ 玩家 ESP（Drawing 直绘；执行器没有 Drawing 时 ESP 静默关闭，数据条照常） |

## 使用

```lua
loadstring(game:HttpGet(".../moc.lua"))()    -- 各文件独立，按需执行
loadstring(game:HttpGet(".../sibs.lua"))()
-- brick.lua 再执行一次 = 停止
```

- **重跑即替换**：每个文件开头先卸载旧实例（`_G.SB_<模块>` 句柄），重复执行安全。
- **面板**：标题栏拖动移动（松手存位置）、点按折叠。SIBS 的**转向滑条仅在主面板折叠时响应**（展开时拖动会干扰转向）。
- **配置持久化**：执行器有 `writefile`/`readfile` 时写 `Selfblox_cfg.txt`（0.5s 防抖，卸载时立即落盘）；没有则仅内存。
- **调试采样**：各模块在 `_G.SB_DEBUG` 注册调试块，`log.lua` 采样进日志。

## 键位

| 动作 | 键 |
|---|---|
| 飞行/飞车升降 | 空格/E 上 · Shift/Q 下（或面板按住键） |
| 移动输入 | WASD / 方向键 / 手柄左摇杆 |
| 车灯切换 | O |
| 喇叭 | H（首次点「常声/声」自动探测） |
| 漂移推进 | W/S 或手机 MobilePedals 最左两键 |

## 备注

- 执行器 API（`Drawing`、`hookmetamethod` 等）全部 pcall 防护：缺失对应功能静默降级，不炸整个脚本。
- 无框架 = 无全局一键卸载。单模块卸载：重跑同文件前先执行对应 `_G.SB_<MOC/SIBS/...>()`（或直接重启客户端）。
- 真机行为以游戏内为准；本仓库不做任何本地模拟。
