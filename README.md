# Selfblox

Roblox 执行器脚本：单文件、单面板、七个模块，面向 Delta（安卓）的纯触屏操作。适合在手机上调试移动、载具和显示类功能，并且希望脚本本身可以离线自检的用户。

## 使用

前置条件：安卓设备已安装 Delta 执行器，并允许它读写自己的工作目录（脚本会在该目录写配置、日志和诊断快照，Delta 通常是 `/storage/emulated/0/Delta/workspace/`）。

在执行器里运行：

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Sumicya/Selfblox/HEAD/selfblox.lua"))()
```

地址里的 `HEAD` 跟随仓库默认分支，改默认分支的名字或换默认分支都不用改这一行。重复执行会先自动卸载上一份，手动卸载调用 `_G.SB_UNLOAD()`。执行前可以用 `_G.SB` 覆盖配置，优先级为 `_G.SB` > `Selfblox.json`（面板里改过的值）> 默认值：

```lua
_G.SB = { spd = 60, flyspd = 120, hornkey = "H", only = { "moc", "sibs" } }
```

可覆盖的是数值键、带存盘键的开关和只读配置键（见下表）；速度、飞行、穿墙、秒互动这类没有存盘键的开关，每次执行都从关闭开始。面板里的改动立即生效并写进 `Selfblox.json`，面板位置和上次页签也存在同一个文件里。

想在手机上留一份副本（断网也能用、方便回滚），下载到 Download 目录，备份名用「项目名-版本」：

```bash
cd /sdcard/Download
curl -fLO https://raw.githubusercontent.com/Sumicya/Selfblox/HEAD/selfblox.lua
mv selfblox.lua Selfblox-26.10.5.9.9.lua
ls -l Selfblox-26.10.5.9.9.lua   # 有字节数才是真的下来了
```

`readfile` 只读 Delta 的工作目录，所以离线加载前要把副本放进去（Termux 需要存储权限，先跑 `termux-setup-storage`），再在执行器里用 `loadstring(readfile("Selfblox-26.10.5.9.9.lua"))()` 加载：

```bash
cp /sdcard/Download/Selfblox-26.10.5.9.9.lua /storage/emulated/0/Delta/workspace/
```

不用了按名字前缀清掉本次下载和工作目录里的副本，不删别的东西：

```bash
rm -f /sdcard/Download/Selfblox-*.lua
rm -f /storage/emulated/0/Delta/workspace/Selfblox-*.lua
```

使用执行器违反 Roblox 使用条款，可能导致账号受限。脚本按「原样」提供，不作任何保证，风险自负。

## 适用环境与限制

- 目标是 Delta 最新版：`hookmetamethod`、`newcclosure`、`UIDragDetector`、原生 `Highlight` 按一定存在处理；`gethui`、`isfile`、`writefile` 缺失时退回 `CoreGui` 并跳过存盘，面板仍能起来。
- 只有触屏路径，不含键盘和手柄输入。
- 车、漂移、飞机侦察依赖具体游戏的结构（座位、`MobilePedals`、Remote 命名），换游戏可能绑不上。此时用「志」页的「诊断打包」取整机快照，里面已经有 PlaceId、地图名、全部配置、执行器能力、车辆与踏板结构，贴出来即可，不必另外描述环境。
- 车穿墙只保留轮子碰撞：零件名含 `wheel` / `tire` / `tyre` / `轮` 才算轮子。整车一个轮子名都认不到时，退回保留最低的几块（否则车会掉出世界），车页状态行会写明「穿墙没认到轮子」。作用范围只有本车装配体，不会波及同一个 Model 容器里的其他车或地图件；轮子没有焊接到车身的游戏会漏穿，漏掉的那块仍然碰撞。
- 飞机侦察只做侦察：`__namecall` 钩子记录完就原样转发，不拦截也不改参数，脚本本身不发任何飞机 Remote。「收」是拿扫出来的 Remote 列表挂 `OnClientEvent` 的，所以要先点「重扫」，否则「收」永远是 0，看着像服务器没回。收发记录按「同一个 Remote 打同一个目标」折叠成一组并保留首末两条 payload，上限 400 组；不折叠时飞行中每秒约 20 条复制包，200 条只装得下 10 秒，`RequestPlane` 这种一局只发一次的必被挤掉。
- 参数不设人为上限，填错数值可能让角色或载具失控。
- 过弯：弯半径约为速度除以转向速率，速度越高弯越宽。要提高过弯能力就调高 `grip` 和 `turn`，或用 `_G.SB = { turncap = 3 }` 让转向随速度放大（2~4 合适，5 以上会像陀螺）。

## 模块与配置键

| 页签 | 模块 | 内容 |
|---|---|---|
| 动 | `moc` | 速度（`root` / `walk` / `cframe` 三种模式）、飞行、高跳、旋转、无限跳、穿墙、夜视、秒互动（普通 / 强制）与秒互动距离 |
| 车 | `sibs` | 上车即控；未上车时对准载具按「换车」，按座位锁定所在装配体，打中地图或超大装配体时拒绝绑定（提示里带实测外径和质量，误拒时一眼看得出为什么），进游戏或下车后自动绑最近的空座位。加速、抓地、转向、减速、定速、急刹、穿墙（只保留轮子碰撞，范围限本车装配体）、飞车、翻转、灯、喇叭；屏幕底部滑条转向，与游戏自带油门和方向盘同时生效 |
| 漂 | `drift` | 人物 `VectorForce` 推进，自动绑定 `MobilePedals`（左刹右油），找不到就用面板按钮 |
| 显 | `hud` | 顶部数据条（延迟、帧率、内存、时间、人数、坐标）、速度箭头、玩家 ESP（原生 `Highlight` 加名牌距离） |
| 志 | `log` | 配置与各模块状态定时追加 `Selfblox_log.txt`，超过上限重写；「诊断打包」把整机快照写进 `selfblox_dump.txt` 并复制到剪贴板 |
| 机 | `plane` | 查找飞机（有座位的、以及只认到机翼名的都算，没座位的残留机也列得出来）、判定队伍、列出 Remote、收发侦听（`__namecall` 钩子）、高亮；报告写 `plane_debug.txt` 并复制到剪贴板，没重扫过就点「写报告」会自动先扫一遍，没过门槛的候选列进「疑似」名单 |
| 砖 | `brick` | BitFarmer 刷砖，开关式 |

配置键与默认值：

| 键 | 默认 | 说明 |
|---|---|---|
| `only` | 全部 | 只装这些页：`moc` `sibs` `drift` `hud` `log` `plane` `brick` |
| `spd` / `spdmode` | 16 / `root` | 速度值 / 模式 `root` `walk` `cframe` |
| `flyspd` `jump` `spin` `promptdist` | 50 50 50 1000 | 飞行速度 / 跳力 / 转速（负数反向）/ 秒互动距离 |
| `acc` `grip` `turn` `carfly` | 500 5 2.2 60 | 车：加速度 / 抓地 / 转向速率 / 飞车速度 |
| `turncap` | 1 | 转向速率随速度放大的上限倍数，1 为原样，2~4 用于过弯 |
| `carmaxstuds` | 150 | 装配体外径超过这个数就不当作载具，`换车` 打中这种大件直接拒绝，避免绑到整个街区或地图容器。量的是装配体不是 Model 容器，所以车直接挂在超大容器（整条街）里也照样绑得上 |
| `carauto` | true | 进游戏或下车后自动绑最近的空载具座位，手动「换车」锁定优先 |
| `carswap` | true | 锁到没有座位的锚定件时，自动改绑附近最重的自由零件 |
| `carclip` / `hornkey` | false / `H` | 车穿墙 / 喇叭键。`hornkey` 没有面板控件，只在「常声」按钮标题里显示 |
| `steeropen` | false | 面板开着也能拖转向滑条，默认是折起来才能拖 |
| `dacc` `dbrake` `drift` | 5 10 true | 漂移推进：加速 / 刹车 / 开关 |
| `stats` `arrow` `esp` | true | 数据条 / 速度箭头 / 玩家 ESP |
| `clock` | `12` | 时钟制式，填 `24` 切 24 小时制，数据条和日志都受影响 |
| `logint` `logmax` | 2 512 | 日志间隔秒 / 上限 KB |
| `pall` | false | 飞机侦察全录 Remote |
| `bbatch` `bint` `bdrain` `bmult` `blevel` | 4 0.08 0.6 99999 9999 | 刷砖参数 |

## 开发

清单驱动：一个功能等于一个顶层函数加对应页 `do` 块里的一行 `feature{}`，建页、存盘、每帧连接、卸载和诊断快照都由清单生成，核心代码不为新功能改动。控件类型和可用字段见 `selfblox.lua` 里的注册表注释与 `KIND` 表；开关状态在 `F[key]`，数值在 `S[key]`，控件在 `W[key]`。

改完先离线自检，不必上手机：

```bash
lua5.4 smoke.lua   # Termux: pkg install lua54
```

`smoke.lua` 用一个假 Roblox 引擎加载 `selfblox.lua`：建面板、翻每个开关、坐进假车、跑帧、卸载，然后断言状态确实改变、没有报错、卸载后不留实例和连接，并注入一个玩具功能验证清单的扩展性。假引擎对没有核对过官方文档的成员一律抛错，白名单是 `smoke.lua` 里的 `VERIFIED`，逐个对照 create.roblox.com 的引擎 API 参考核对。脚本本体不依赖 `smoke.lua`。

Termux 是设备本地的终端环境，`pkg install lua54` 只安装解释器，不需要 Root，也不改动游戏或系统分区。

CI 跑的是同一份自检：`.github/workflows/spec-check.yml`（全程 `contents: read`）在 push 与 pull request 上用 Lua 5.4 执行 `smoke.lua`，另一个 job 校验 `AGENTS.md` 的规范指针与版本戳、与 `Sumicya/selfs` 的 `GLOBAL.md` 比对版本，并确认没有工作流声明写权限或自动创建 Release。

## 版本

版本号是五段 `yy.m.d.当日序号.总序号`：两位年份、不补零的月份和日期（Asia/Shanghai 时区），第四段是当天第几个版本，第五段是该仓库累计第几个版本，两个序号都从 1 起。日期版本不是 SemVer，本仓库不使用 SemVer 字段。

单一来源是 `selfblox.lua` 顶部的 `VERSION`，面板标题、诊断快照和启动打印都读它；展示时不带 `v`，标签为 `v` 加版本号。`smoke.lua` 会检查格式是否合法、序号是否从 1 起、三处展示是否一致。

本仓库没有发布工作流，两个序号手工维护：当日序号只数当天改过 `VERSION` 的提交，总序号在上一版基础上加 1。改之前查一次最新标签，避免撞号（当前远程没有标签，输出为空）：

```bash
gh api repos/Sumicya/Selfblox/tags --jq '.[0].name'
```

没有发行需求时不打标签、不建 Release。获准发版后再打 `v` 加版本号的标签（下例仅为格式示例，不代表已经发行）：

```bash
git tag v26.10.5.9.9
```

## 许可

GPL-3.0，全文见 [LICENSE](LICENSE)。
