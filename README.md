# Selfblox v12.1

一个文件、一个面板、七个模块。Delta（安卓）为目标，纯触屏。

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Sumicya/Selfblox/main/selfblox.lua"))()
```

重跑会自动先卸载；手动卸载 `_G.SB_UNLOAD()`。

## 覆盖参数

执行前设 `_G.SB`，任何键都能覆盖（优先级 `_G.SB` > `Selfblox.json`(面板里改过的) > 默认）：

```lua
_G.SB = { spd = 60, flyspd = 120, hornkey = "H", only = {"moc", "sibs"} }
```

| 键 | 默认 | 说明 |
|---|---|---|
| `only` | 全部 | 只装这些模块 `{"moc","sibs","drift","hud","log","plane","brick"}` |
| `spd` / `spdmode` | 16 / `"root"` | 速度值 / 模式 `root` `walk` `cframe` |
| `flyspd` `jump` `spin` `promptdist` | 50 50 50 1000 | 飞行速度 / 跳力 / 转速(负数反向) / 秒互动距离 |
| `acc` `grip` `turn` `carfly` | 500 5 2.2 60 | 车: 加速度 / 抓地 / 转向速率 / 飞车速度 |
| `hornkey` `carclip` | `"H"` false | 喇叭键 / 车穿墙默认开 |
| `dacc` `dbrake` `drift` | 5 10 true | 漂移推进: 加速 / 刹车 / 开关 |
| `stats` `arrow` `esp` | true | 数据条 / 速度箭头 / 玩家 ESP |
| `logint` `logmax` | 2 512 | 日志间隔秒 / 上限 KB |
| `pall` | false | 飞机侦察全录 Remote |
| `bbatch` `bint` `bdrain` `bmult` `blevel` | 4 0.08 0.6 99999 9999 | 刷砖参数 |

面板里改的数值直接生效并写进 `Selfblox.json`（面板位置、上次页签也在里面）。

## 模块

| 页签 | 模块 | 内容 |
|---|---|---|
| 动 | moc | 速度(3 模式) / 飞行 / 高跳 / 旋转 / 无限跳 / 穿墙 / 夜视 / 秒互动(普通·强制) |
| 车 | sibs | 上车即控；没上车对准载具按「换车」准星锁定。加速·减速·定速·急刹·穿墙悬浮·飞车·翻转·灯·喇叭；屏幕底部滑条转向，游戏自带油门/方向盘同时生效 |
| 漂 | drift | 人物 VectorForce 推进，自动绑 `MobilePedals`(左刹右油)，没有就用面板按钮 |
| 显 | hud | 顶部数据条(延迟/帧率/内存/时间/人数/坐标) / 速度箭头 / 玩家 ESP(原生 Highlight + 名牌距离) |
| 志 | log | 各模块状态定时追加 `Selfblox_log.txt`，超上限重写 |
| 机 | plane | 找飞机、判队伍、列 Remote、发/收侦听(`__namecall` 钩子)、高亮、报告写 `plane_debug.txt` + 剪贴板 |
| 砖 | brick | BitFarmer 刷砖，开关式 |

## v12 → v12.1

功能一个没动，只拆重复：

- `num()` 直接绑状态表 `num(行, "加速", S, "acc", 500, 0.5)`，读写 + 落盘一步到位，干掉 14 对 get/set 闭包
- 字段名统一成 json 键名（`S.fly`→`S.carfly`、`S.mode`→`S.spdmode`…），**`Selfblox.json` 键集一个没变**，老配置照读
- 穿墙还原 moc/sibs 两份一样的 → 一个 `reclipAll(col)`
- sibs 每物理步原来要 `part()` 两次、`model()` 一次、`facing()` 一次，各自都往上爬一遍祖先链 → 现在只解析一次 `host`
- 剩下的猜的门槛（飞机 55 分、收发各 200 条、dump 一层 8 个字段）都打上 `ponytail:` 标记写清上限

## 本地检查

不用开 Roblox 就能把脚本整个跑一遍：

```bash
npm i fengari   # 纯 JS 的 Lua VM
node check.js
```

`stub.lua` 是最小的 Roblox/执行器 API 桩，`check.lua` 装面板 → 点每个按钮 → 跑物理帧 → 坐下开车 → 准星换车 → 卸载。
`check.js` 起三个干净 VM：默认 / `_G.SB` 覆盖 / 已有 `Selfblox.json`，顺带验证配置优先级还活着。

改坏了会被抓住（负向验证过：改坏 `doFly`、删掉 brick 模块、让 `num()` 无视 `_G.SB` 都会 FAIL）。

## v11 → v12 砍掉的

- 7 个文件 → 1 个；每文件自带的配置/拖拽/输入样板全删，UI 拖拽用原生 `UIDragDetector`
- sibs 的自动锁车/所有权嗅探/车辆列表/学习缓存 → 只剩「坐着」和「准星换车」
- 各种人为上限（换车距离、扫描数量、飞行防穿减速、转向门槛、速度地板）全没了，参数随便填
- 键盘/手柄输入路径（纯触屏；要 PC 说一声）
- 日志归档、KITCFG2 配置格式、v10 迁移
- 引擎音调、边缘计数、Drawing 库 ESP
