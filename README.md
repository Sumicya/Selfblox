# Selfblox

单文件、单面板、九个模块的 Roblox 执行器脚本，面向安卓 Delta 纯触屏操作。

## 是什么

一个独立运行脚本，包含九个模块页签，全部配置支持执行前通过 `_G.SB` 覆盖（优先级：`_G.SB` > `Selfblox.json` > 默认值）。

### 模块

| 页签 | 模块 | 内容 |
|---|---|---|
| 动 | `moc` | 速度（`root` / `walk` / `cframe`）、飞行、高跳、旋转、无限跳、穿墙、夜视、秒互动（普通 / 强制）与秒互动距离 |
| 枪 | `gun` | 无限子弹（手持与背包 Tool 及 `leaderstats` 的弹药 Value/属性自动回填，`getgc` 深改含 `ammo` 键的配置表，关闭还原）、子弹穿墙（共享 `__namecall` 钩子拦 `workspace.Raycast` 续射至角色，不改白名单射线）、探针报告写 `gun_debug.txt` 并复制剪贴板 |
| 车 | `sibs` | 上车即控，未上车对准载具按「换车」准星锁定（拒绝地图与超大装配体），进游戏或下车自动绑最近空座位。加速、抓地、转向、定速、穿墙（保留轮胎碰撞）、全穿（本车非锚定件全关闭碰撞）、飞车、翻转、常亮灯、按住闪灯、喇叭与屏幕底部滑条转向 |
| 漂 | `drift` | 人物 `VectorForce` 持续前推，自动读取当前朝向 |
| 显 | `hud` | 顶部数据条（延迟、帧率、内存、时间、人数、坐标）、速度箭头、玩家 ESP（原生 `Highlight` + 名牌距离） |
| 志 | `log` | 配置与各模块状态定时追加 `Selfblox_log.txt`，超上限重写；「诊断打包」将整机快照写进 `selfblox_dump.txt` 并复制剪贴板 |
| 机 | `plane` | 查找飞机（含无座位机翼残骸）、判队伍、列 Remote、收发侦听（共享 `__namecall` 钩子）、高亮与报告写 `plane_debug.txt` 并复制剪贴板 |
| 抓 | `grab` | 按范围三档（散件 / 带属性 / 全部）与推法三档（自动 / 只写速度 / 只搬位）拉近周边部件，支持批量触发启用中的 `ProximityPrompt` 与按关键字点击界面按钮 |
| 弹 | `aim` | 对刚生成的实体弹丸做方向偏转追踪，可调转向速率、视角锥、射程、同时追踪数量、寿命、最低速度、生成半径、提前量、目标部位与队友过滤 |

### 覆盖参数

```lua
_G.SB = { spd = 60, flyspd = 120, hornkey = "H", only = { "moc", "gun", "sibs" } }
```

| 键 | 默认 | 说明 |
|---|---|---|
| `only` | 全部 | 只装指定模块：`moc` `gun` `sibs` `drift` `hud` `log` `plane` `grab` `aim` |
| `spd` / `spdmode` | 16 / `root` | 速度值 / 模式 `root` `walk` `cframe` |
| `flyspd` `jump` `spin` `promptdist` | 50 50 50 1000 | 飞行速度 / 跳力 / 转速（负数反向）/ 秒互动距离 |
| `ammo` `pierce` | 999 16 | 弹药回填值 / 单发最多穿透次数 |
| `acc` `grip` `turn` `carfly` | 500 5 2.2 60 | 车：加速度 / 抓地 / 转向速率 / 飞车速度 |
| `turncap` `carmaxstuds` | 1 150 | 转向随速度放大上限（0–5）/ 准星锁车最大装配体尺寸（格） |
| `carauto` `carswap` | true true | 自动绑最近空载具座位 / 锁到锚定件时改绑附近最重自由件 |
| `carclip` `carclipall` `hornkey` | false false `H` | 车穿墙 / 车全穿 / 喇叭键 |
| `dacc` `drift` | 5 true | 漂移推进加速度 / 开关 |
| `stats` `arrow` `esp` | true | 数据条 / 速度箭头 / 玩家 ESP |
| `clock` | `12` | 时钟制式（填 `24` 切 24 小时制） |
| `logint` `logmax` | 2 512 | 日志间隔秒 / 上限 KB |
| `pall` | false | 飞机侦察全录 Remote |
| `gradius` `gspeed` `gscan` | 40 60 300 | 抓取半径 / 拉力 / 诊断扫描半径 |
| `grange` `gmode` `gkey` | `loose` `auto` 空 | 抓取范围 `loose` `attr` `all` / 推法 `auto` `vel` `frame` / 点按钮关键字 |
| `bhome` `bteam` `bpart` | false true `core` | 弹丸追踪开关 / 忽略队友 / 瞄 `core` 身体或 `head` 头 |
| `bturn` `bfov` `brange` `bmax` | 90 60 500 3 | 每秒转向角 / 视角锥 / 最远距 / 同时追几颗 |
| `blife` `bspdmin` `bradius` `blead` | 2 10 300 0.5 | 最长追几秒 / 最低弹速 / 认弹半径 / 提前量（0–1） |

## 从哪下

直接从本仓库主线拉取 `selfblox.lua`，或下载到本地手机存储目录 `/storage/emulated/0/Download`：

```bash
curl -fL "https://raw.githubusercontent.com/Sumicya/Selfblox/HEAD/selfblox.lua" -o "/storage/emulated/0/Download/selfblox.lua" && ls -l "/storage/emulated/0/Download/selfblox.lua"
```

## 怎么装

### 在线加载

在 Delta 执行器内直接运行：

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Sumicya/Selfblox/HEAD/selfblox.lua"))()
```

### 离线副本加载

在 Termux（需先授予存储权限 `termux-setup-storage`）将文件复制到 Delta 工作目录：

```bash
cp "/storage/emulated/0/Download/selfblox.lua" "/storage/emulated/0/Delta/workspace/selfblox.lua"
```

随后在 Delta 执行器内运行：

```lua
loadstring(readfile("selfblox.lua"))()
```

重复执行会自动先卸载旧实例。面板内修改的数值、位置与当前页签自动存入工作目录下的 `Selfblox.json`。

## 怎么删

游戏内立即卸载（停止循环、断开连接、还原穿墙/弹药/钩子并销毁界面）：

```lua
_G.SB_UNLOAD()
```

删除手机本地副本与执行器工作目录中的运行时文件：

```bash
rm -f "/storage/emulated/0/Download/selfblox.lua"
rm -f "/storage/emulated/0/Delta/workspace/selfblox.lua" "/storage/emulated/0/Delta/workspace/Selfblox.json" "/storage/emulated/0/Delta/workspace/Selfblox_log.txt" "/storage/emulated/0/Delta/workspace/selfblox_dump.txt" "/storage/emulated/0/Delta/workspace/plane_debug.txt" "/storage/emulated/0/Delta/workspace/gun_debug.txt"
```

## 必要限制

- 目标环境为安卓 Delta 最新版，依赖 `hookmetamethod`、`newcclosure`、`getnamecallmethod`、`UIDragDetector` 与原生 `Highlight`。缺失 `gethui`、`isfile`、`writefile` 时自动退回 `CoreGui` 并跳过存盘。
- 仅提供触屏界面，不含键盘或手柄路径。
- `gun` 子弹穿墙与 `plane` 发侦听共用单一 `__namecall` 钩子，最后一个模块关闭后才还原原元方法。`gun` 的 `getgc` 深改依赖执行器提供 `getgc`，缺失时只回填 Value 与属性。
- 服务端权威弹药或服务端判定命中的游戏中，本地弹药回填、射线穿墙与弹丸速度改写不会改变服务端裁决。射线武器没有实体弹丸，需使用 `gun` 页探针报告与 `plane` 页发侦听定向分析。
- 车、漂移与飞机侦察依赖目标游戏的座位、`Root` 命名与 Remote 结构。车「穿墙」仅按零件名识别轮子，全车未匹配到轮名时退回保留最低处碰撞块。
- 仓库不带假引擎替身，功能行为以 Delta 真机实测为准。使用执行器违反 Roblox 服务条款，脚本按原样提供，风险由使用者自行承担。

## 许可证

Copyright (C) 2026 Sumicya

本程序按 GNU 通用公共许可证第 3 版（GPL-3.0-or-later）分发，不含任何担保，全文见 [LICENSE](LICENSE)。

规范指针：[Sumicya/selfs GLOBAL.md](https://github.com/Sumicya/selfs/blob/30ddbc3bee03b8a9d0604cacafaf3c7e788d994b/GLOBAL.md)（生效提交 PR #15 head `30ddbc3bee03b8a9d0604cacafaf3c7e788d994b`）
