# Selfblox v13

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

`grip` `turn` `hornkey` 没有面板控件（v13 从车上撤了，抓地/转向固定值在多数车里够用），要调就写在 `_G.SB` 里。
面板里改的数值直接生效并写进 `Selfblox.json`（面板位置、上次页签也在里面）；`显` 页的「复制状态」按钮一键复制整份配置。

## 模块

| 页签 | 模块 | 内容 |
|---|---|---|
| 动 | moc | 速度(3 模式) / 飞行 / 高跳 / 旋转 / 无限跳 / 穿墙 / 夜视 / 秒互动(普通·强制) / 秒互动距离 |
| 车 | sibs | 上车即控；没上车对准载具按「换车」准星锁定。加速·减速·定速·急刹·穿墙悬浮·飞车·翻转·灯·喇叭；屏幕底部滑条转向，游戏自带油门/方向盘同时生效 |
| 漂 | drift | 人物 VectorForce 推进，自动绑 `MobilePedals`(左刹右油)，没有就用面板按钮 |
| 显 | hud | 顶部数据条(延迟/帧率/内存/时间/人数/坐标) / 速度箭头 / 玩家 ESP(原生 Highlight + 名牌距离) / 复制配置 |
| 志 | log | 配置 + 各模块状态定时追加 `Selfblox_log.txt`，超上限重写 |
| 机 | plane | 找飞机、判队伍、列 Remote、发/收侦听(`__namecall` 钩子)、高亮、报告写 `plane_debug.txt` + 剪贴板 |
| 砖 | brick | BitFarmer 刷砖，开关式 |

## 自检

改完代码不用上手机试，离线假引擎跑一遍：

```
lua5.4 smoke.lua        # Termux: pkg install lua54 ; 或用 luajit / lua5.1 / luau
```

它加载 `selfblox.lua`，建面板、翻每个开关、坐进假车、跑 60 帧、卸载，然后断言：开关真的改了状态（速度写进 root、飞行挂了原生约束、车限速抬到无穷、急刹清水平速度）、没报错、**卸载后一个实例一条连接都不剩**，还带一轮 `_G.SB = {only={"moc"}, spd=99}` 的覆盖测试。脚本本体不依赖它。

## v12 → v13

- 只保 Delta 最新版：执行器能力探测（`isfile` `gethui` `newcclosure` `hookmetamethod` `UIDragDetector`）全删，不留兜底；只剩 3 处故意留的 `pcall`（模块隔离、卸载清理、钩子里的记录），以及读 `Selfblox.json` 时防配置损坏
- 车：急刹从"反推力"改成直接把水平速度清零（立刻停，不吃质量）；滑条转向只转游戏自己没转的那部分（`Steer` 相减），不再重复转两次
- 数值控件直接绑表、改完自动存盘，模块不用再各写一份 dump
- `志` 不再让各模块自己拼配置字符串：配置整份 dump，模块只报运行时状态
- UI 加圆角；`秒互动距离`、`排空间隔` 提到面板上；`显` 页加「复制状态」
- 新增 `smoke.lua`（见上），改代码有个东西能兜着
- 保持 Lua 5.4 可解析子集（不用 `+=` / `continue` / 字符串插值），这样自检能离线跑
