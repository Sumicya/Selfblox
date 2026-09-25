# Selfblox · KIT v10

Roblox 客户端脚本套件：**1 个核心框架 + 6 个功能模块**，构建产物仍是**单文件可执行**（executor `loadstring` 工作流不变）。

> v10 重构：原 7 个 ~6,900 行的 `.md.txt` 大文件改为 `src/` 分片目录 + 统一框架 + 构建/校验/冒烟工具。
> 功能等价（实现自由重写）；公共 API 统一到 `_G.KIT`；版本号 v9 → v10（破坏性升级允许）。

## 目录结构

| 路径 | 说明 |
|---|---|
| `src/kit/` | 核心框架（12 分片，按文件名前缀序拼接）：环境探测、配置持久化、连接袋、力/约束工厂、context 角色状态、UI 工厂、toast、生命周期、绘制封装（Drawing 优先 / Frame 降级）、HUD 状态格 + 速度箭头、ESP |
| `src/modules/moc.lua` | 移动：速度（RootVelocity / WalkSpeed / CFrame 三档）、飞行、高跳/无限跳、noclip、旋转、夜视、即时交互 |
| `src/modules/sibs/` | 车辆（6 分片）：锁车/扫描/评分、驾驶物理、定速、穿墙、飞车、灯光/喇叭、引擎音调、转向/旋转滑条、车辆列表 |
| `src/modules/plane.lua` | 飞机侦察：模型评分、队伍推断、远程扫描、namecall 间谍、报告写入 `plane_debug.txt`、高亮 |
| `src/modules/drift.lua` | 漂移：W/S 力驱动 + 自适应增益 + 停采样 + MobilePedals 绑定 |
| `src/modules/log.lua` | KITLOG：调试注册表采样 → `KIT_Log.txt`（512KB × 3 归档滚动） |
| `src/modules/brick.lua` | BitFarmer：自动收砖（**可独立运行**，再次执行即停止） |
| `dist/` | 构建产物（单文件 bundle，直接执行，勿手改） |
| `tools/smoke.luau` | 冒烟 harness（stub Roblox 环境 + 场景驱动） |
| `build.py` | 打包 / 语法校验 / 冒烟 |

## 构建

```bash
python3 build.py            # 打包 dist/*.lua
python3 build.py --check    # + luau-compile 语法校验（--luau 指定路径）
python3 build.py --smoke    # + 逻辑冒烟（luau CLI，见下文）
python3 build.py kit sibs   # 只构建指定 bundle
```

## 使用

```lua
loadstring(game:HttpGet(".../dist/kit.lua"))()   -- 核心（必装，除 brick 外都依赖它）
loadstring(game:HttpGet(".../dist/moc.lua"))()   -- 其余模块同理
-- brick 可单独执行；再次执行 = 停止
```

- **一键卸载**：`KIT_CLEAN_ALL()`（清理全部模块、连接、GUI，核心保留在 0 个模块状态）。
- **配置持久化**：存在 executor 文件 API（`writefile`/`readfile`）时写入 `KIT_Config.txt`；否则仅内存。
- **模块协议**：每个模块 `K.mod(name)` 占槽 → `M.reg(conn)` 挂连接 → `M.panel()` 建面板 → `M.done(fn)` 注册清理 → `M.debug(fn)` 注册调试取数。

## `_G.KIT` API 速览（v10）

| 分类 | 接口 |
|---|---|
| 模块生命周期 | `K.mod(name, cfgOverrides?)` → `M.panel / M.done / M.debug / M.reg / M.bag / M.cfg` |
| 配置 | `K.cfg.get / K.cfg.set / K.loadPrefixed / K.savePrefixed(Num)` |
| 环境 | `K.env`（hasWritefile / hasIsfile / hasGethui …）、`K.isP / K.getRoot / K.isTyping / K.keyDown` |
| 状态 | `K.context.set / K.context.changed`、`K.watchCharacter(bag, {ready, waiting, removed})` |
| UI 工厂 | `K.mk / K.btn / K.panel / K.toast / K.halfButton / K.fullInput / K.numBox / K.makeToggleRow / K.holdButton / K.drag / K.titleBar` |
| 力/物理 | `K.force`（VectorForce / Attachment 工厂 + 引用计数回收）、`K.dtTracker / K.heartbeat` |
| 调试 | `K.registerDebug / K.runDebug / K.debugDump / K.debugAll / K.getErrors / K.countTable / K.safeFullName` |
| 绘制 | `K.label`、`K.font`、绘制封装（80-draw：Square / Line / Label） |
| 卸载 | `KIT_CLEAN_ALL()`（`K.cleanAll`） |

## 冒烟测试（`--smoke`）

`build.py --smoke` 把 7 个 dist 源码内嵌进 `tools/.smoke_run.lua`（约 250KB），用 **luau CLI** 在 stub Roblox 环境中全链路执行：

1. **stub**：Instance（父子/事件/属性/IsA）、Enum 懒表、Vector2/3 + 算术、CFrame、UDim/UDim2、Color3、`task`（wait 必须 yield）、RunService/UIS/Players/ReplicatedStorage/Lighting 等服务、`writefile`/`appendfile` 内存文件系统；
2. **场景**：加载 7 模块 → 注入角色（CharacterAdded）→ 脉冲 Heartbeat / PreSimulation / PreRender ×40（真实时钟推进，触发 fps 分层）→ WindowFocusReleased / InputEnded(touch) / JumpRequest → 全模块 debug 采集 → `KIT_CLEAN_ALL` → kit+moc 热重载 → 再清理；
3. **判定**：任何加载/处理器/调试错误都记为 FAIL，结束打印 `SMOKE OK`（退出码 0）或 `SMOKE FAILED (n)`（退出码 1）。

CLI 适配说明：CLI 的 `_G` 是冻结表 → 打包时剥离 `_G.` 前缀改走裸全局（语义等价）；CLI 无 `io` → 源码内嵌而非读盘。

## 从 v9 迁移

- 旧 7 文件已删除，内容全部移入 `src/`；`dist/` 为唯一可执行产物。
- 公共入口只有 `_G.KIT`（含 `KIT_CLEAN_ALL`）；模块间不再互相 hack 全局。
- 行为细节可能与 v9 不同（重构允许），功能范围等价。
