# Selfblox

一个文件、一个面板、八个模块。Delta（安卓）为目标，纯触屏。

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
| `only` | 全部 | 只装这些模块 `{"moc","gun","sibs","drift","hud","log","plane","brick"}` |
| `spd` / `spdmode` | 16 / `"root"` | 速度值 / 模式 `root` `walk` `cframe` |
| `flyspd` `jump` `spin` `promptdist` | 50 50 50 1000 | 飞行速度 / 跳力 / 转速(负数反向) / 秒互动距离 |
| `ammo` `pierce` | 999 16 | 弹药回填值 / 单发最多穿透次数 |
| `acc` `grip` `turn` `carfly` | 500 5 2.2 60 | 车: 加速度 / 抓地 / 转向速率 / 飞车速度 |
| `turncap` `carmaxstuds` | 1 150 | 转向速率上限倍率(0–5) / 准星锁车最大装配体尺寸(格) |
| `hornkey` `carclip` | `"H"` false | 喇叭键 / 车穿墙默认关 |
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
| 枪 | gun | 无限子弹(手持/背包 Tool 与 leaderstats 的弹药 Value/属性自动回填，`getgc` 深改含 ammo 键的配置表，关闭即还原) / 子弹穿墙(钩 `workspace.Raycast` 续射至角色，白名单射线不改) / 探针报告写 `gun_debug.txt` + 剪贴板。弹药若只在服务器扣，本地回填无效，需按报告定向适配 |
| 车 | sibs | 上车即控；没上车对准载具按「换车」准星锁定。加速·减速·定速·急刹·穿墙悬浮·飞车·翻转·灯·喇叭；屏幕底部滑条转向(按实际尺寸计算)，游戏自带油门/方向盘同时生效 |
| 漂 | drift | 人物 VectorForce 推进，自动绑 `MobilePedals`(左刹右油)，没有就用面板按钮 |
| 显 | hud | 顶部数据条(延迟/帧率/内存/时间/人数/坐标) / 速度箭头 / 玩家 ESP(原生 Highlight + 名牌距离) |
| 志 | log | 各模块状态定时追加 `Selfblox_log.txt`，超上限重写 |
| 机 | plane | 找飞机、判队伍、列 Remote、发/收侦听(共享 `__namecall` 钩子)、高亮、报告写 `plane_debug.txt` + 剪贴板 |
| 砖 | brick | BitFarmer 刷砖，开关式 |

## 必要限制

- 子弹穿墙与发侦听需要执行器提供 `hookmetamethod`/`getnamecallmethod`；多模块共用一个钩子，最后一个关闭才还原。
- 无限子弹的 `getgc` 深改需要执行器提供 `getgc`；没有时只回填 Value/属性。
- 服务器权威弹药/命中的游戏，本地改写不生效；用「枪」页探针报告 + 「机」页发侦听取样后定向适配。
- 运行时文件 `Selfblox.json`、`Selfblox_log.txt`、`plane_debug.txt`、`gun_debug.txt` 不入仓。

规范指针：[Sumicya/selfs GLOBAL.md](https://github.com/Sumicya/selfs/blob/2b16d68ad7e03c1f5fc8320ff8760a449ac8c8da/GLOBAL.md)（生效提交 PR #15 head `2b16d68ad7e03c1f5fc8320ff8760a449ac8c8da`）
