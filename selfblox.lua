-- Selfblox · 单文件 · 一次 loadstring · 一个面板 · 八页清单
--
-- Copyright (C) 2026 Sumicya
-- SPDX-License-Identifier: GPL-3.0-or-later
-- 本程序是自由软件: 你可以按自由软件基金会发布的 GNU 通用公共许可证第 3 版(或你选择的更高版本)重新分发和/或修改它。
-- 本程序的发布是希望它有用, 但不含任何担保; 甚至不含对适销性或特定用途适用性的默示担保。详见 GNU 通用公共许可证。
-- 你应当随本程序收到一份 GNU 通用公共许可证副本(仓库里的 LICENSE); 如果没有, 见 <https://www.gnu.org/licenses/>。
-- 单文件被单独转走时, 这几行是唯一还跟着走的声明, 别删。
-- 版本: 下面的 VERSION 是唯一来源(五段 yy.m.d.当日序号.总序号, 序号按实际交付手动计数; 口径见 README「版本」); 面板标题 / 诊断快照 / 启动打印都读它
-- 用法:  loadstring(game:HttpGet("https://raw.githubusercontent.com/Sumicya/Selfblox/HEAD/selfblox.lua"))()
-- 覆盖:  执行前 _G.SB = { spd = 50, flyspd = 80, only = {"moc", "sibs"} }
-- 优先级: _G.SB > Selfblox.json(面板里改过的值) > 默认值
-- 卸载:  _G.SB_UNLOAD()   重跑会自动先卸载
-- 检查:  提交前用官方 Luau 0.741 在 /tmp 里编一遍查语法 (编译器与假引擎替身都不入库); 真机行为以实测为准
--
-- 设计约定:
--   表驱动 —— 一个功能 = 一个顶层函数 + 清单里一行 feature{}; 建页 / 存盘 / 每帧连接 / 卸载 / 诊断都从清单生成,
--            核心不为新功能改一个字 (见下面「注册表」)。加功能三步: 写函数 → 在对应页的块里追加一行 → 上真机验
--   原生优先 —— 刹车 / 灯 / 秒互动 / ESP 走引擎原生属性, 拖拽走 UIDragDetector, 不自己造轮子
--   面向 Delta 最新版 —— hookmetamethod / newcclosure / UIDragDetector 当它一定有;
--            gethui / isfile / writefile 缺失时退回 CoreGui 并跳过存盘, 面板照样起得来
--   语法基线就是 Luau(运行环境就是它): 26.10.5.28 起用了字符串插值(`{}`)、复合赋值(+= 等)与 if 表达式(if c then a else b),
--            Lua 5.4 / fengari 都解析不了; 语法检查用官方 Luau 0.741 在 /tmp 里临时编, 不入库

local VERSION = "26.10.26.3.117" -- 单一版本来源: 五段 yy.m.d.当日序号.总序号 (日期按 UTC+8); 标签是 v<VERSION>, 打标签要先获主人授权

if rawget(_G, "SB_UNLOAD") then _G.SB_UNLOAD() end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Http = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Stats = game:GetService("Stats")
local Teams = game:GetService("Teams")
local RS = game:GetService("ReplicatedStorage")
local VIM = game:GetService("VirtualInputManager")
local me = Players.LocalPlayer
local ROOT = (pcall(gethui) and gethui()) or game:GetService("CoreGui") -- gethui 没有/报错都得能起面板, 退回 CoreGui

-- ───────── 配置: _G.SB 覆盖 > JSON > 默认 ─────────
local O = type(rawget(_G, "SB")) == "table" and _G.SB or {}
local FILE, saved = "Selfblox.json", {}
if isfile and isfile(FILE) then local okf, d = pcall(Http.JSONDecode, Http, readfile(FILE)); if okf and type(d) == "table" then saved = d end end -- 配置文件坏了不能连面板一起死
local function opt(k, d) local v = O[k]; if v == nil then v = saved[k] end; if v == nil then v = d end; return v end
local function save(k, v)
	saved[k] = v
	if writefile then -- 存盘炸了不能连累调用它的那个功能 (改一个数值就整个面板报错)
		local okw, errw = pcall(function() writefile(FILE, Http:JSONEncode(saved)) end)
		if not okw then warn(`[Selfblox] 配置保存失败: {tostring(errw)}`) end
	end
end
local CLOCK12 = opt("clock", "12") ~= "24" -- 12 小时制默认; _G.SB = { clock = "24" } 切 24
local function clock(sec) return os.date(((if CLOCK12 then "%I" else "%H")) .. ((if sec then ":%M:%S" else ":%M"))) end

-- ───────── 公共 ─────────
local alive, conns, DUMP = true, {}, {}
local function on(sig, fn) local c = sig:Connect(fn); conns[#conns + 1] = c; return c end
local function mk(cls, props, parent) local i = Instance.new(cls); for k, v in pairs(props) do i[k] = v end; i.Parent = parent; return i end
local function tap(i) return i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 end
local function hum() local c = me.Character; return c and c:FindFirstChildOfClass("Humanoid") end
local function mine(d) local c = me.Character; return c ~= nil and (d == c or d:IsDescendantOf(c)) end -- 零件是不是我人物的: 重生那几秒 Character 是 nil, 直接 IsDescendantOf(nil) 在真引擎里会抛错
local function root() local c = me.Character; return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Root")) end
local function flat(v) v = Vector3.new(v.X, 0, v.Z); if v.Magnitude > 1e-3 then return v.Unit end end
local function reclipAll(col) for d in pairs(col) do if d.Parent then d.CanCollide = true end end; table.clear(col) end -- 穿墙还原: moc/sibs 原来各写了一份一模一样的
local function nn(v) return tonumber(v) or 0 end -- 诊断/日志里的引擎数字: 拿不到就 0, 不能因为一个属性缺失把整份 dump 弄炸

-- ───────── UI: 一个 ScreenGui, 标题条(原生 UIDragDetector 拖) + 页签 + 每模块一页 ─────────
local FONT, WHITE = Enum.Font.GothamBold, Color3.new(1, 1, 1)
local BG, ON, OFF = Color3.fromRGB(20, 22, 28), Color3.fromRGB(38, 125, 85), Color3.fromRGB(48, 50, 60)
local LIT, CLEAR = Color3.fromRGB(150, 235, 170), 0.9 -- CLEAR = 面板底色透明度
local function lit(b, on) b.BackgroundColor3 = on and ON or OFF; b.TextColor3 = on and LIT or WHITE end -- 开着/按着/当前页: 底色只剩 10%, 看不出颜色了, 状态靠字色
local PW, ROW = 184, 26 -- 面板宽 200 → 184: 半行按钮 100 → 92, 一行两个左右更靠近。名字避开下面的控件表 W (自查发现的撞名: 174 行以后 W 是表不是数, 谁在后面拿它当宽度用就静默出错)
local FOLDW = 18 -- 折叠钮占宽 (原 26)。标题栏现在只放五段版本: 15 字符 × 最保守 7px @12 号 = 105, 折叠钮两侧各让 18 共 36, 合计 141 < 面板 184, 余 43px。原先带 "Selfblox " 前缀时 24 字符要 186px, 总序号一上三位数就撑爆 —— 面板宽度是主人定的 184, 所以动的是标题
local gui = mk("ScreenGui", { Name = "Selfblox", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99999 }, ROOT)
local FX = mk("Folder", { Name = "Selfblox_FX" }, ROOT) -- Highlight / BillboardGui 放这里, 卸载一起删

local BASE = { BackgroundColor3 = OFF, BackgroundTransparency = CLEAR, BorderSizePixel = 0, Font = FONT, TextSize = 12, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center }
local ORD = 0
local function ord() ORD = ORD + 1; return ORD end -- UIListLayout 按创建顺序排
local function ui(cls, parent, w, props) -- w=nil 整行, w=0.5 半行
	local i = Instance.new(cls)
	for k, v in pairs(BASE) do i[k] = v end
	i.Size, i.LayoutOrder = w and UDim2.new(w, 0, 1, 0) or UDim2.new(1, 0, 0, ROW), ord()
	for k, v in pairs(props or {}) do i[k] = v end
	i.Parent = parent
	return i
end
local function row(parent, h)
	local f = mk("Frame", { Size = UDim2.new(1, 0, 0, h or ROW), BackgroundTransparency = 1, LayoutOrder = ord() }, parent)
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 0) }, f)
	return f
end
-- 帮助行要能自己长高: 184px 宽里放不下的会换行, 而 ui() 给的是固定 26px 高, 第二行等于写了看不见
-- (自查量出来两条帮助文字估 195px / 191px, 都超 184)。AutomaticSize.Y 让高度跟着换行走, 不用逐条数字数。
local function text(parent, s, w) return ui("TextLabel", parent, w, { Text = s, BackgroundTransparency = 1, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y }) end
local function btn(parent, s, fn, w)
	local b = ui("TextButton", parent, w, { Text = s })
	on(b.Activated, function() fn(b) end)
	return b
end
local function toggle(parent, s, init, fn, w) -- 返回 set(v): 代码里也能翻状态
	local b, st = ui("TextButton", parent, w), nil
	local function set(v, quiet) st = v; b.Text = s .. ((if v then " 开" else " 关")); lit(b, v); if not quiet then fn(v) end end
	set(init, true)
	on(b.Activated, function() set(not st) end)
	return set
end
local heldReleases = {} -- 还按着的按住钮; 卸载时逐个松开
local function hold(parent, s, fn, w) -- 按住 fn(true) 松开 fn(false)
	-- 按钮自己的 InputEnded 只在指针还在按钮上时才来: 滑出去松手 / 按住途中卸载, fn(false) 永远不会到 = 功能卡在"按着"
	local b, held = ui("TextButton", parent, w, { Text = s, AutoButtonColor = false }), false
	local function release() if held then held = false; if b.Parent then lit(b, false) end; pcall(fn, false) end end
	heldReleases[#heldReleases + 1] = release
	on(b.InputBegan, function(i) if tap(i) and not held then held = true; lit(b, true); fn(true) end end)
	on(b.InputEnded, function(i) if tap(i) then release() end end)
	on(UIS.InputEnded, function(i) if tap(i) then release() end end) -- 全局兜底: 指针在哪儿松手都算
end
local function num(parent, s, S, k, w, savek) -- 直接绑 S[k], 改完自动存盘; savek 缺省 = k
	local f = mk("Frame", { Size = w and UDim2.new(w, 0, 1, 0) or UDim2.new(1, 0, 0, ROW), LayoutOrder = ord(), BackgroundColor3 = OFF, BackgroundTransparency = CLEAR, BorderSizePixel = 0 }, parent) -- 一行分两半: 左半标签, 右半输入框, 文字各在自己那半格里居中 (原来标签靠左 + 前面垫个空格, 和居中的按钮/输入框对不齐)
	if s then ui("TextLabel", f, nil, { Text = s, BackgroundTransparency = 1, Size = UDim2.fromScale(0.5, 1) }) end
	local tb = mk("TextBox", { Size = UDim2.fromScale((if s then 0.5 else 1), 1), Position = UDim2.fromScale((if s then 0.5 else 0), 0), BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = Color3.fromRGB(255, 225, 140), Text = tostring(S[k]), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, ClearTextOnFocus = false }, f)
	on(tb.FocusLost, function() local v = tonumber(tb.Text); if v and v == v and v ~= math.huge and v ~= -math.huge then S[k] = v; save(savek or k, v) end; tb.Text = tostring(S[k]) end) -- nan/inf 存进配置会让 JSONEncode 抛错, 之后每次改设置都失败
end

local cam0 = workspace.CurrentCamera
local vp = (cam0 and cam0.ViewportSize) or Vector2.new(800, 600) -- 相机还没就绪时读 ViewportSize 直接抛错, 面板一个都建不出来
local pos = opt("pos", { vp.X / 2 - PW / 2, vp.Y * 0.3 })
local title = mk("TextLabel", { Name = "SB_Title", Size = UDim2.fromOffset(PW, ROW), Position = UDim2.fromOffset(math.clamp(pos[1], 0, math.max(vp.X - PW, 0)), math.clamp(pos[2], 0, math.max(vp.Y - ROW, 0))), BackgroundColor3 = BG, BackgroundTransparency = CLEAR, BorderSizePixel = 0, Font = FONT, TextSize = 12, TextColor3 = WHITE, Text = VERSION }, gui) -- 13 → 12: 跟面板里其它文字同号。原来写的是 `Selfblox {VERSION}`, 总序号进到三位数后
-- 24 字符 × 最保守 7px = 168 + 折叠钮 18 = 186 > 面板 184, 撑爆了。名字在这一栏是多余的(面板只有这一个,
-- 启动打印、日志头、诊断包里都带 [Selfblox] <版本>), 去掉它换来 61px 余量, 面板宽度一个字没动
local body = mk("Frame", { Name = "SB_Body", Size = UDim2.new(0, PW, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = title.Position + UDim2.fromOffset(0, ROW), BackgroundColor3 = BG, BackgroundTransparency = CLEAR, BorderSizePixel = 0 }, gui)
mk("UIListLayout", { Padding = UDim.new(0, 0) }, body)
on(title:GetPropertyChangedSignal("Position"), function() body.Position = title.Position + UDim2.fromOffset(0, ROW) end)
local fitActivePage -- 页面/视口变动时, 按当前页真实高度把整块面板留在屏内
if cam0 then -- vp 只在上面读一次. 转屏、顶栏收放、窗口改大小都会改 ViewportSize, 不重夹就可能整块留在屏外,
	-- 而唯一能把它拖回来的热区就在标题自己身上 —— 出不去, 只能重进游戏. 重夹后 Position 的监听会把 body 一起带过去
	local function reclamp()
		local v = cam0.ViewportSize
		if v.X <= 0 or v.Y <= 0 then return end -- 相机交接时会瞬时读到 0, 那一下别把面板夹到左上角钉死
		local p = title.Position
		title.Position = UDim2.fromOffset(math.clamp(p.X.Offset, 0, math.max(v.X - PW, 0)), math.clamp(p.Y.Offset, 0, math.max(v.Y - ROW, 0)))
		if fitActivePage then fitActivePage() end
	end
	on(cam0:GetPropertyChangedSignal("ViewportSize"), reclamp)
end
local fold = mk("TextButton", { Size = UDim2.fromOffset(FOLDW, ROW), Position = UDim2.new(1, -FOLDW, 0, 0), BackgroundTransparency = 1, Font = FONT, TextSize = 16, TextColor3 = WHITE, Text = "–" }, title)
local foldHooks = {} -- 想知道"面板是折着还是开着"的模块挂这里
local function setFold(v) body.Visible = v; fold.Text = (if v then "–" else "+"); for _, f in ipairs(foldHooks) do f(v) end end
local drag = mk("UIDragDetector", { BoundingUI = gui }, title)
local flipT, down = -math.huge, nil
local function flip() -- 一次点按可能同时走下面三条路(拖拽器 / +按钮 / 标签自己的输入), 0.2 秒内只认第一条, 不然翻两次等于没翻. ponytail: 0.2 秒内连点两下会被当成一下
	if os.clock() - flipT > 0.2 then flipT = os.clock(); setFold(not body.Visible) end
end
on(drag.DragStart, function(p) down = p end) -- 事件名: 官方文档里 UIDragDetector 只有 DragStart / DragContinue / DragEnd, 没有 DragBegin (写错 = 真引擎直接抛错, 脚本死在这一行, 后面一个页签都没建)
on(drag.DragEnd, function(p) -- 抬手: 挪动 <8px = 点击 = 折叠, 否则是拖动 = 存位置. 手指必然会抖, 所以不能拿"有没有收到 DragContinue"来判
	if down and (p - down).Magnitude < 8 then flip() else
		if fitActivePage then fitActivePage() end
		save("pos", { title.Position.X.Offset, title.Position.Y.Offset })
	end
	down = nil
end)
on(fold.Activated, flip)
local pressPos -- 备用: 万一拖拽器不为纯点按发事件, 标签自己的输入也认"没挪动=点击"
on(title.InputBegan, function(i) if tap(i) then pressPos = title.AbsolutePosition end end)
on(title.InputEnded, function(i)
	if pressPos and tap(i) then
		local p = title.AbsolutePosition
		if math.abs(p.X - pressPos.X) + math.abs(p.Y - pressPos.Y) < 8 then flip() end
	end
	pressPos = nil
end)
local tabs = row(body)

local toastL = mk("TextLabel", { Name = "SB_Toast", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = BG, BackgroundTransparency = 0.2, BorderSizePixel = 0, Font = FONT, TextSize = 13, TextColor3 = WHITE, Visible = false }, gui)
mk("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, toastL)
local toastN = 0
local function toast(s) -- 卸载后 / 面板已销毁: 直接丢弃, 不往死标签上写字
	if not alive or not toastL.Parent then return end
	toastN = toastN + 1; local n = toastN
	local inset = GuiService:GetGuiInset()
	toastL.Position = UDim2.new(0.5, 0, 0, inset.Y + 8) -- ScreenGui 忽略安全区, 提示手动避开 Roblox 顶栏
	toastL.Text, toastL.Visible = s, true
	task.delay(2, function() if alive and toastN == n and toastL.Parent then toastL.Visible = false end end)
end
local dumpNow -- 启动完再赋值; 模块里的按钮闭包先引用这个局部变量

-- ═════════ 注册表 (表驱动): 一个功能 = 一个顶层函数 + 这里追加一行 feature{...} ═════════
-- 建页 / 存盘 / 每帧连接 / 卸载 / 诊断全从这张表生成, 核心不为新功能改一个字. 清单顺序 = 页内控件顺序.
-- 行字段 (按 kind 取用): id 页名 · kind 控件种类 (KIND 表, 缺省 toggle) · key 状态键 · label 文字 · w 宽 (缺省半行) · h 行高
--   save 存盘键 · def 默认值 · num={键, 默认} 紧跟的数字框 · set(v) 变了调 · tick(dt) 开着每帧调 (sig="render" 走 PreRender) · off() 关掉/卸载调
--   init(page) 建好后调一次 (接事件) · fn 按钮回调 · build(p) 自定义控件 · dump 诊断提供者 · info() 页状态追加
local F, S, W, FEATURES, ACTIVE = {}, {}, {}, {}, {} -- F 开关 / S 数值 / W 控件 (开关存 set(v) 句柄, 文字行存 TextLabel) / 清单 / 装上的页
local pageInfos -- 启动完再赋值 (日志模块先引用)
local function say(key, s) local w = W[key]; if w then w.Text = s end end
local function feature(e)
	local k = e.kind or "toggle"
	if k == "toggle" or k == "cycle" then
		local v = e.def
		if e.save then v = opt(e.save, e.def) end
		if v == nil then if k == "toggle" then v = false else v = e.cycle[1] end end
		F[e.key] = v
	elseif k == "num" or k == "str" then S[e.key] = opt(e.key, e.def) end -- str 是文本框 (num 只收数字)
	local n = e.num
	e.num = nil
	FEATURES[#FEATURES + 1] = e
	if n then feature({ kind = "num", key = n[1], def = n[2], label = n.label }) end
end
local KIND = {
	toggle = function(e, p, w)
		W[e.key] = toggle(p, e.label, F[e.key], function(v)
			F[e.key] = v
			if e.save then save(e.save, v) end
			if e.set then e.set(v) end
			if not v and e.off then e.off() end
		end, w)
	end,
	hold = function(e, p, w) hold(p, e.label, function(v) if e.key then F[e.key] = v end; if e.set then e.set(v) end end, w) end,
	btn = function(e, p, w) btn(p, e.label, e.fn, w) end,
	cycle = function(e, p, w) -- 一个按钮循环 e.cycle 里的值; e.text 是 值→文字 的表或函数; e.lit = 不在第一个值时亮
		local list = e.cycle
		local function txt(v) if type(e.text) == "function" then return e.text(v) end; return e.text[v] end
		btn(p, txt(F[e.key]), function(b)
			local v = list[(table.find(list, F[e.key]) or 0) % #list + 1]
			F[e.key] = v
			if e.save then save(e.save, v) end
			if e.set then e.set(v) end
			b.Text = txt(v)
			if e.lit then lit(b, v ~= list[1]) end
		end, w)
	end,
	num = function(e, p, w) num(p, e.label, S, e.key, w, e.key) end,
	str = function(e, p, w) -- 文本输入框 (num 只收数字): 存进 S[k], 空串就是没填, 不做数字校验
		local f = mk("Frame", { Size = w and UDim2.new(w, 0, 1, 0) or UDim2.new(1, 0, 0, ROW), LayoutOrder = ord(), BackgroundColor3 = OFF, BackgroundTransparency = CLEAR, BorderSizePixel = 0 }, p)
		ui("TextLabel", f, nil, { Text = e.label, BackgroundTransparency = 1, Size = UDim2.fromScale(0.5, 1) })
		local tb = mk("TextBox", { Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromScale(0.5, 0), BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = Color3.fromRGB(255, 225, 140), Text = tostring(S[e.key] or ""), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, ClearTextOnFocus = false }, f)
		on(tb.FocusLost, function() S[e.key] = tb.Text; save(e.key, tb.Text) end) -- 文本不做数字校验, 空串照存
		W[e.key] = tb
	end,
	text = function(e, p, w) W[e.key] = text(p, e.label, w) end,
	custom = function(e, p) e.build(p) end,
	tick = function() end, dump = function() end, -- 没有控件的行: 只挂每帧 / 诊断
}
local NOUI = { tick = true, dump = true }

do -- ═════════ 动: 角色 (速度 / 飞行 / 高跳 / 旋转 / 无限跳 / 穿墙 / 夜视 / 秒互动) ═════════
	local moving, nvT = false, 0
	local pushN, tickN = 0, 0 -- 诊断: cframe 真推了几帧 / doSpeed 跑了几帧 (摇杆值在 info() 里现读, 不缓存: 缓存的话速度关着就一直是旧值, 上一版就是这么把 20 个初始零当成了证据)
	local lastPos, gateOpen, gateSpd, netSpd = nil, false, 0, 0 -- cframe 门: 上一帧推完时人在哪 / 门开没开 / 游戏自己这一步 / 加完的净速度
	local att, flyLV, flyAO, spinAV, cc, nvSaved
	local base = setmetatable({}, { __mode = "k" }) -- humanoid -> 原始 WalkSpeed/JumpPower/JumpHeight
	local col = setmetatable({}, { __mode = "k" }) -- 穿墙前 CanCollide=true 的部件
	local prompts = setmetatable({}, { __mode = "k" }) -- prompt -> 原始属性
	local function body() -- 角色在场才干活: 返回 character, humanoid, root
		local c, h, r = me.Character, hum(), root()
		if c and h and r and r:IsDescendantOf(workspace) then return c, h, r end
	end

	local function baseOf(h) local b = base[h]; if not b then b = { h.WalkSpeed, h.JumpPower, h.JumpHeight }; base[h] = b end; return b end
	-- 分开还原: 原来一个 restore() 三样一起写回, 关「高跳」会把速度也重置掉, 关「速度」会把跳跃也重置掉
	local function restoreSpeed() local h = hum(); local b = h and base[h]; if b then h.WalkSpeed = b[1] end end
	local function restoreJump() local h = hum(); local b = h and base[h]; if b then h.JumpPower, h.JumpHeight = b[2], b[3] end end
	local function attach(r) -- 飞行/旋转的约束都挂在这一个 Attachment 下, 删它就全删
		if not att or att.Parent ~= r then if att then att:Destroy() end; att = mk("Attachment", { Name = "SB_MOC" }, r); flyLV, flyAO, spinAV = nil, nil, nil end
		return att
	end
	local function stopFly() if flyLV then flyLV:Destroy(); flyAO:Destroy(); flyLV, flyAO = nil, nil end; local h = hum(); if h then h.PlatformStand = false end end
	local function doFly(r, h)
		local a = attach(r)
		if not flyLV then
			flyLV = mk("LinearVelocity", { Attachment0 = a, MaxForce = math.huge, VectorVelocity = Vector3.zero, RelativeTo = Enum.ActuatorRelativeTo.World }, a)
			flyAO = mk("AlignOrientation", { Attachment0 = a, Mode = Enum.OrientationAlignmentMode.OneAttachment, MaxTorque = math.huge, Responsiveness = 200 }, a)
			h.PlatformStand = true
		end
		local cam, md = workspace.CurrentCamera.CFrame, h.MoveDirection
		local look = flat(cam.LookVector) or Vector3.zAxis
		-- 水平跟摇杆, 前后分量带上相机俯仰, 上升/下降按钮叠加
		flyLV.VectorVelocity = md * S.flyspd + Vector3.yAxis * (S.flyspd * (cam.LookVector.Y * md:Dot(look) + ((if F.up then 1 else 0)) - ((if F.down then 1 else 0))))
		flyAO.CFrame = CFrame.lookAt(Vector3.zero, look)
	end
	local ctrl, ctrlT, stickFrom, stickRaw = nil, -1e9, false, Vector3.zero
	local ctrlWhy = "还没探过" -- 探不到控制模块时记下"为什么", 打进日志; 只报「模块=无」等于没报
	local ctrlPath = "" -- 认出来的是哪一路 (GetControls 直调 / GetModule 再一层), 打进日志
	-- 摇杆方向。两份真机日志把「哪个源能判松手」这个问题问到底了, 答案是: 这个游戏里两个都不能。
	--   26.10.15.5.63(287 条): Humanoid.MoveDirection 模长全是 1.00, 其中 #172–#286 连续 115 条(23.0 秒)
	--     人不动而摇杆满偏 ⟹ 它永不归零, 拿它当"有输入"就是永久推。
	--   26.10.15.6.89(162 条): ControlModule:GetMoveVector() 全是 0, 而同期人一直在动(相邻样本水平中位
	--     14.1 格/秒), 推=0/跑=489 ⟹ 它恒为零, 拿它当唯一源等于把功能整个关掉。
	-- 所以这里只管方向, 谁有输入用谁(模块活着的普通游戏两个源一起归零, 不会误判); 判"松手"交给 doSpeed
	-- 里那道量游戏自己挪了多少的门 —— 那是唯一一个不依赖输入源、游戏怎么改控制都还成立的信号。
	local function stick()
		if not ctrl and os.clock() - ctrlT > 1 then -- 控制模块可能还没起来, 每秒重试; require 不能每帧调
			ctrlT = os.clock()
			local ps = me:FindFirstChildOfClass("PlayerScripts")
			local pm = ps and ps:FindFirstChild("PlayerModule")
			-- 真机两份日志 (26.10.14.5.58 的 367 条 + 26.10.15.3.61 的 140 条) 全是「模块=无」,
			-- 但"没找到"分不清是 PlayerScripts 整个不在, 还是它在、里头换了名字 —— 两种的修法完全不同。
			-- 所以把底下实际有什么打出来, 让下一份日志自己给答案, 不再猜第七次。
			if not ps then
				ctrlWhy = "角色下没有 PlayerScripts"
			elseif not pm then
				local names = {}
				for _, c in ipairs(ps:GetChildren()) do names[#names + 1] = `{c.Name}:{c.ClassName}` end
				table.sort(names)
				local shown = {}
				for i = 1, math.min(#names, 8) do shown[#shown + 1] = names[i] end
				ctrlWhy = `PlayerScripts 在, 但没有 PlayerModule; 底下 {#names} 个: {(#shown > 0 and table.concat(shown, " ") or "(空)")}{(#names > 8 and " …" or "")}`
			elseif not ctrl then
				-- 26.10.15.5.63 真机日志给出了确切错误串: "…:278: attempt to call missing method 'GetModule' of tab"。
				-- 那个 :278 就是本文件这一行 —— 执行器把 chunk 名换成了乱码, 行号没换。也就是说 require 成功了、
				-- 拿回来一张表, 是这张表上没有 GetModule。对照官方 PlayerModule 源码, require 出来的表公开方法只有
				-- GetCameras / GetControls / GetClickToMoveController, 压根没有 GetModule: 上一版凭空多插了一层,
				-- 于是六版以来每次都在这儿抛错, 每次都退回会冻的 Humanoid.MoveDirection —— 「停不下来」的真正来源。
				local okR, errR = pcall(function()
					local t = require(pm)
					local c = t and t.GetControls and t:GetControls() -- 官方就这一层, 不需要 GetModule
					local how = "GetControls"
					if not (c and c.GetMoveVector) then -- roblox-ts 生成的那套才多一层 GetModule, 留作第二路
						local m = t and t.GetModule and t:GetModule()
						c = m and m.GetControls and m:GetControls()
						how = "GetModule"
					end
					if c and c.GetMoveVector then ctrl, ctrlPath = c, how end
				end)
				if not ctrl then
					if okR then
						ctrlWhy = "PlayerModule 在, 但两条路都没给出 GetMoveVector"
					else
						local e = tostring(errR)
						local nl = e:find("\n", 1, true) -- 错误串常跟一长串 traceback, 只留第一行
						ctrlWhy = `PlayerModule 在, 但抛错: {(nl and e:sub(1, nl - 1) or e):sub(1, 80)}`
					end
				end
			end
		end
		if ctrl then
			local okM, mv = pcall(function() return ctrl:GetMoveVector() end)
			if not okM then -- pcall 失败时第二个返回值是错误字符串, 不能当向量用; 丢掉缓存下一秒重探, 这一帧走下面的退回
				-- stickFrom / ctrlPath / ctrlWhy 得跟着一起清: 只清 ctrl 的话下一份日志照样打「路=GetControls」,
				-- 而 ctrl 已经是 nil —— 自相矛盾的读数比没读数更坏。stickFrom 尤其不能漏: info() 是靠它决定
				-- 打「路=」还是打「无(...)」的, 不清它就永远走不到「无」那一支。
				ctrl, ctrlT = nil, os.clock()
				stickFrom, ctrlPath = false, ""
				local es = tostring(mv)
				local nl2 = es:find("\n", 1, true)
				ctrlWhy = `GetMoveVector 抛错, 一秒后重探: {(nl2 and es:sub(1, nl2 - 1) or es):sub(1, 80)}`
			else
				stickFrom, stickRaw = true, mv or Vector3.zero
				if stickRaw.Magnitude > 1e-4 then
					local cf = workspace.CurrentCamera.CFrame -- 相机相对 → 世界。归一化: 推一半仍旧全速, 手感不变
					local w = cf.RightVector * stickRaw.X + cf.UpVector * stickRaw.Y - cf.LookVector * stickRaw.Z
					if w.Magnitude > 1e-4 then return w.Unit end
				end
				-- 模块报 0 不再直接当"松手": 26.10.15.6.89 的真机日志里它 162 条全是 0 而人一直在动, 这个 0 是
				-- "源在这个游戏里是死的", 不是"手离开了摇杆"。所以再看一眼 MoveDirection —— 模块活着的普通
				-- 游戏里, MoveDirection 就是控制模块每帧从 moveVector 写过去的, 两个一起归零, 不会因此误判。
				local h = hum()
				local md = h and h.MoveDirection
				return (md and md.Magnitude > 1e-4 and md.Unit) or Vector3.zero
			end
		end
		local h = hum() -- 取不到控制模块(游戏改过 PlayerScripts)才退回原路
		local md = h and h.MoveDirection
		stickFrom, stickRaw = false, Vector3.zero
		return (md and md.Magnitude > 1e-4 and md.Unit) or Vector3.zero
	end

	-- ── 游戏自己的输入物件探针 ─────────────────────────────────────────────
	-- 主人说这游戏有自己的跳跃和趴下滑竿(右边上下), 控制不走 Roblox 那套 ⟹ 真值不在 Humanoid 上;
	-- 而两份真机日志已经把两个官方源都排除了(见上面 stick() 的注释), 所以要认的是游戏自己的控件。
	-- 叫什么名字还不知道, 所以先扫不问: 每秒一次, 认「Position 变过」的子物件当滑块, 顺带把右半屏 Active
	-- 方块的父名/坐标/尺寸/子物件数报出来。
	-- 26.10.15.6.89(162 条)的实测: 「没认出滑块」, 右半屏 6 个 Unlocked/ImageIcon, 父名/类名/尺寸/子物件数
	-- 6 个全一样, 只有坐标能分 —— #0–#139 排成一行 y=109 60x60 (x 329/421/514/606/698/791, 间距 ~92),
	-- #140 起同一排变成 y=183 63x63 (x 1121…1611, 间距 98), Active 方块 54 → 64。是横排的一排图标, 还没认出来。
	local uiFound, uiSeen, uiInv, uiInvN, uiSent, uiDone, uiT = {}, {}, "", 0, nil, false, -1e9
	local uiFull = {} -- 没截断的那份: 日志行有字节护栏, 诊断打包里没有, 全清单在打包里
	local function sbOwn(p) while p do if p == gui or p == FX then return true end; p = p.Parent end; return false end
	local function halfW() return ((vp and vp.X) or 800) / 2 end
	-- 滑块相对底座几何中心的偏移, 归一到 -1..1。不认「静止位置」: 那得等松手才知道, 而松手正是分不清的时候
	local function knobVal(base, knob)
		local bs, bp, ks, kp = base.AbsoluteSize, base.AbsolutePosition, knob.AbsoluteSize, knob.AbsolutePosition
		if not bs or not bp or not ks or not kp or bs.X < 1 or bs.Y < 1 then return end
		return ((kp.X + ks.X / 2) - (bp.X + bs.X / 2)) / (bs.X / 2), ((kp.Y + ks.Y / 2) - (bp.Y + bs.Y / 2)) / (bs.Y / 2), bp.X + bs.X / 2
	end
	local function px(v) return v and tostring(math.floor(v)) or "?" end -- 真机上位置尺寸是小数, 取整; 读不到就打 ?
	local function uiProbe()
		if os.clock() - uiT < 1 then return end -- 跟控制模块探针同一节流: 扫全树不便宜, 一秒一次够看
		uiT = os.clock()
		local nFound = 0
		-- 先清掉已经不存在的: 游戏切场景/换 UI 会销毁重建控件, 死物件留着不光报假数据,
		-- 在真引擎上读它的 AbsoluteSize 还会抛。pairs 遍历中把已有键置 nil 是 Lua 明确允许的。
		for c, b in pairs(uiFound) do if not c.Parent or not b.Parent then uiFound[c] = nil end end
		for _ in pairs(uiFound) do nFound += 1 end
		-- 全清单: 一个筛选条件都不留。以前按 尺寸 / 屏幕区 / Active 层层筛, 还只留 6 个名额,
		-- 三份真机日志报出来的就全是顶部菜单条 —— 被筛掉的正好是要找的那个。现在树里每个不是自家的
		-- GuiObject 都列: 父名/名字/类名/位置/尺寸/可见/Active/子物件数, 排序保证日志可复现。
		local inv, trees = {}, {}
		local pg = me:FindFirstChildOfClass("PlayerGui")
		if pg then trees[#trees + 1] = pg end
		if ROOT and ROOT ~= pg then trees[#trees + 1] = ROOT end
		for _, tree in ipairs(trees) do
			local okD, list = pcall(function() return tree:GetDescendants() end)
			if okD and type(list) == "table" then
				for _, g in ipairs(list) do
					-- 逐个包 pcall: 有些物件读 Active/Visible 本身就会抛(不是 GuiObject 却混在树里), 不能因为一个坏物件丢掉整棵树
					pcall(function()
						if not g:IsA("GuiObject") or sbOwn(g) then return end
						local sz, ap, par, nc = g.AbsoluteSize, g.AbsolutePosition, g.Parent, 0
						for _, c in ipairs(g:GetChildren()) do if c:IsA("GuiObject") then nc += 1 end end
						-- 标志两位: 可见 V/v, Active A/-。隐的和 Active=false 的一起列 —— 触屏控件常常
						-- 是 Active=false 靠 InputBegan 自己收事件, 只收 Active 的会把真控件整个漏掉。
						inv[#inv + 1] = string.format("%s/%s:%s@%s,%s %sx%s %s%s 子%d", (par and par.Name) or "?", g.Name, g.ClassName,
							px(ap and ap.X), px(ap and ap.Y), px(sz and sz.X), px(sz and sz.Y),
							g.Visible ~= false and "V" or "v", g.Active == true and "A" or "-", nc)
						-- 认滑块仍然要求底座是方的: knobVal 拿底座尺寸当分母, 尺寸不对会算出鬼值。
						if g.Active ~= true or not sz or sz.X < 24 or sz.X > 320 or sz.Y < 24 or sz.Y > 480 then return end
						for _, c in ipairs(g:GetChildren()) do
							if c:IsA("GuiObject") then
								local p0, p1 = uiSeen[c], c.Position
								uiSeen[c] = p1
								-- 认出来的滑块永久记住, 不只比相邻两秒: 松手时它不动, 只比相邻就永远认不出来
								if p0 and nFound < 8 and (p0.X.Scale ~= p1.X.Scale or p0.X.Offset ~= p1.X.Offset
									or p0.Y.Scale ~= p1.Y.Scale or p0.Y.Offset ~= p1.Y.Offset) then uiFound[c] = g; nFound += 1 end
							end
						end
					end)
				end
			end
		end
		table.sort(inv) -- pairs/GetDescendants 的顺序不保证, 排一下日志才可复现
		-- 16KB 是护栏不是筛选: 日志超 S.logmax 就整个重写, 上千物件的清单会把速度样本全冲掉。砍了几个明写出来。
		local parts, used, cut = {}, 0, 0
		for i, s in ipairs(inv) do
			if used + #s > 16384 then cut = #inv - i + 1 break end
			parts[#parts + 1] = s
			used += #s + 1
		end
		uiInvN = #inv
		uiFull = inv
		uiInv = table.concat(parts, " ") .. (cut > 0 and `…还有 {cut} 个没列(超16KB, 全清单在「诊断打包」里)` or "")
		uiDone = true
	end
	local function uiTxt()
		local o = {}
		for knob, base in pairs(uiFound) do
			local nx, ny, bcx = knobVal(base, knob)
			if nx then o[#o + 1] = string.format("%s/%s@%s=(%.2f,%.2f)", base.Name, knob.Name, bcx >= halfW() and "右" or "左", nx, ny) end
		end
		if #o > 0 then table.sort(o); return table.concat(o, " ") end
		if not uiDone then return "还没探过" end
		-- 同一份清单不重打: info 每 S.logint 秒进一次日志, 一秒没变也打五遍, 十来秒就把 logmax 顶爆重写。
		if uiInv == uiSent then return `没认出滑块 (视口 {vp.X}x{vp.Y}; 物件 {uiInvN} 个, 清单同上)` end
		uiSent = uiInv
		return `没认出滑块 (视口 {vp.X}x{vp.Y}; 物件 {uiInvN} 个; 全清单: {uiInv})`
	end

	local function doSpeed(r, h, dt)
		local md = stick()
		tickN += 1
		gateOpen, gateSpd = false, 0
		if F.spdmode == "walk" then baseOf(h); h.WalkSpeed = S.spd
		elseif F.spdmode == "cframe" then
			-- 水平速度每帧钉死: 逐帧写 CFrame 会让引擎给装配体攒出速度, 那点动量能带着人一直滑。
			local v = r.AssemblyLinearVelocity
			r.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
			-- "什么时候推"不看输入源了, 改成量游戏自己挪了多少: lastPos 记的是上一帧我们推完的位置, 到这一帧
			-- 开始, 中间那段水平位移只有游戏/物理能造成。没挪 = 手已经离开摇杆 = 一帧都不推; 挪了就把这一步
			-- 换成 spd*dt。出来的速度就是 spd, 游戏是靠速度挪人还是靠写位置挪人都一样, 也不用挑输入源。
			local p = r.CFrame.Position
			local d = lastPos and Vector3.new(p.X - lastPos.X, 0, p.Z - lastPos.Z) or nil
			if d then
				gateSpd = d.Magnitude / math.max(dt, 1e-6)
				-- 下限: 水平不到 1 格/秒当没动 (阈值跟 dt 走, 掉帧不误判)。
				-- 上限: 传送/重生那种一步几十格不算走路。这种帧要是当走路, 那个 -d 会照着原路把人拽回去, 所以只重新对位。
				gateOpen = d.Magnitude > dt and d.Magnitude < 60 * dt
				-- spd 是绝对速度, 不是加成: 尾巴那个 -d 把游戏自己挪的那一步抵掉, 再按 d 的方向补 spd*dt,
				-- 净出来就是 spd。26.10.16.2.92 一度改成相加(净 = 游戏自己 + spd), 主人当场否了: 加法语义下
				-- 滑杆低于游戏自身速度就一点作用都没有, 想慢下来没有任何办法。旧游戏自己跑 22 格/秒, 所以
				-- 16 档会比原版慢 —— 那正是要的, 慢速档本来就该能要。
				-- 方向用 d.Unit 不用 md, 图的是不挑输入源。原先这里写的是「md 在这游戏冻住不归零」——
				-- 26.10.16.7.97 真机 641 条把它否了: 摇杆模长 0.00 有 468 条、1.00 有 173 条, 松手是归零的,
				-- 只是从来没有中间值。用 d.Unit 仍然对, 但别再拿那条被否掉的读数当依据。
				netSpd = 0
				if gateOpen then r.CFrame = r.CFrame + d.Unit * (S.spd * dt) - d; pushN += 1; netSpd = S.spd end
			end
			-- 基准必须记推完之后的位置: 记推之前的话, 下一帧量到的差里会混进自己刚才那一下, 推一帧停一帧地摆。
			lastPos = r.CFrame.Position
		else -- root: 直接写水平速度, 松摇杆归零一次
			local v = r.AssemblyLinearVelocity
			if md.Magnitude > 0 then r.AssemblyLinearVelocity = Vector3.new(md.X * S.spd, v.Y, md.Z * S.spd); moving = true
			elseif moving then r.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0); moving = false end
		end
	end
	local function noclip(c) for _, p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then col[p] = true; p.CanCollide = false end end end
	local function doSpin(r)
		local a = attach(r)
		if not spinAV then spinAV = mk("AngularVelocity", { Attachment0 = a, MaxTorque = math.huge, RelativeTo = Enum.ActuatorRelativeTo.World }, a) end
		spinAV.AngularVelocity = Vector3.yAxis * S.spin
	end
	local function stopSpin() if spinAV then spinAV:Destroy(); spinAV = nil end end
	local function nvOn()
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		nvSaved = nvSaved or { Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.Brightness, Lighting.FogEnd, Lighting.GlobalShadows, atm and atm.Density }
		Lighting.Ambient, Lighting.OutdoorAmbient = Color3.fromRGB(160, 160, 160), Color3.fromRGB(160, 160, 160)
		Lighting.Brightness, Lighting.FogEnd, Lighting.GlobalShadows = math.max(Lighting.Brightness, 2), 1e6, false
		if atm then atm.Density = 0 end
		if not cc or not cc.Parent then cc = mk("ColorCorrectionEffect", { Name = "SB_NV", Brightness = 0.1, Contrast = 0.16, Saturation = 0.15 }, Lighting) end
	end
	local function nvOff()
		if cc then cc:Destroy(); cc = nil end
		if not nvSaved then return end
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.Brightness, Lighting.FogEnd, Lighting.GlobalShadows = nvSaved[1], nvSaved[2], nvSaved[3], nvSaved[4], nvSaved[5]
		if atm and nvSaved[6] then atm.Density = nvSaved[6] end
		nvSaved = nil
	end
	local function patch(p) -- 秒互动: 0 长按 / 超远距离 / 不要视线; 强制模式连 Enabled=false 的也打开
		if not p:IsA("ProximityPrompt") or prompts[p] or (F.nocd == "normal" and not p.Enabled) then return end
		prompts[p] = { p.HoldDuration, p.MaxActivationDistance, p.RequiresLineOfSight, p.Enabled }
		p.HoldDuration, p.MaxActivationDistance, p.RequiresLineOfSight, p.Enabled = 0, math.max(p.MaxActivationDistance, S.promptdist), false, true
	end
	local function setNocd(m)
		F.nocd = m
		for p, s in pairs(prompts) do if p.Parent then p.HoldDuration, p.MaxActivationDistance, p.RequiresLineOfSight, p.Enabled = s[1], s[2], s[3], s[4] end end
		table.clear(prompts)
		if m ~= "off" then for _, p in ipairs(workspace:GetDescendants()) do patch(p) end end
	end

	local function stopMove() -- 关速度 / 切模式时收尾: doSpeed 的一次性归零靠 moving, 而 set 里把 moving 清了它就再也不会跑, 残余速度得在这里自己清
		local _, _, r = body(); if r then local v = r.AssemblyLinearVelocity; r.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0) end
		moving = false
		lastPos = nil -- cframe 门的位置基准也作废: 不清的话重开那一刻会拿旧位置算出一大步位移, 照着 -d 把人拽回去
	end
	local function speedTick(dt) local _, h, r = body(); if h and not h.SeatPart and h.Health > 0 then doSpeed(r, h, dt) end end
	local function flyTick() local _, h, r = body(); if h then if h.SeatPart then W.fly(false) else doFly(r, h) end end end
	local function jumpTick() local _, h = body(); if h then baseOf(h); if h.UseJumpPower then h.JumpPower = S.jump else h.JumpHeight = S.jump end end end
	local function spinTick() local _, h, r = body(); if h then if h.SeatPart then if spinAV then stopSpin() end else doSpin(r) end end end
	local function clipTick() local c = body(); if c then noclip(c) end end
	local function nvTick() if body() and os.clock() - nvT > 0.5 then nvT = os.clock(); nvOn() end end -- 游戏会重置光照, 半秒补一次
	feature{ kind = "page", id = "moc", tab = "动", info = function() -- 摇杆在这里现读, 不在 doSpeed 里缓存: 速度关着也要能看出摇杆到底回没回中
		-- stick() 必须在这儿也调一次。上一版 info 只读 doSpeed 留下的 stickFrom/stickRaw, 而 doSpeed 只在速度开着时跑,
		-- 于是 26.10.15.4.62 那份日志前 90 条全是「模块=无(还没探过)」—— 探针根本没跑, 白等 18 秒才看到真成因。
		stick(); uiProbe()
		local h, r = hum(), root()
		local md = (h and h.MoveDirection) or Vector3.zero
		local okS, st = pcall(function() return h and h:GetState() end)
		local q = r and r.Position or Vector3.zero
		-- 三个数并排打: 摇杆=Humanoid.MoveDirection(真机 26.10.15.5.63 的 287 条全是 1.00, 会冻),
		-- 模块=ControlModule:GetMoveVector(真机 26.10.15.6.89 的 162 条全是 0, 这游戏的控制不走 PlayerModule),
		-- 门=cframe 推不推的唯一依据(量游戏自己这一步的水平位移), 游=量出来的游戏自身速度。
		-- 源已经不再决定推不推了, 所以不打"谁在驱动", 打门开没开 —— 下一份日志一眼就能对账。
		local modTxt = stickFrom and string.format("(%.2f,%.2f,%.2f)|%.2f 路=%s", stickRaw.X, stickRaw.Y, stickRaw.Z, stickRaw.Magnitude, ctrlPath) or `无({ctrlWhy})`
		local gateTxt = (F.spdmode == "cframe") and (gateOpen and "开" or "关") or "—"
		-- 游=游戏自己这一步, 净=换成 spd 之后实际该有的速度。两个并排打, 真机上一眼看得出换没换成。
		return string.format("摇杆=(%.2f,%.2f,%.2f)|%.2f 模块=%s 门=%s 游=%.1f 净=%.1f格/秒 推=%d/跑=%d 态=%s 位=(%.0f,%.0f,%.0f) 游戏=%s", md.X, md.Y, md.Z, md.Magnitude, modTxt, gateTxt, gateSpd, netSpd, pushN, tickN, (okS and st and tostring(st.Name)) or "?", q.X, q.Y, q.Z, uiTxt())
	end }
	feature{ key = "speed", label = "速度", num = { "spd", 16 }, tick = speedTick, set = function(v) if v then moving, lastPos = false, nil end end, off = function() stopMove(); restoreSpeed() end }
	feature{ kind = "cycle", key = "spdmode", save = "spdmode", def = "root", cycle = { "root", "walk", "cframe" }, text = function(v) return "模式 " .. v end, set = function() stopMove(); restoreSpeed() end, w = 1 }
	feature{ key = "fly", label = "飞行", num = { "flyspd", 50 }, tick = flyTick, off = stopFly }
	feature{ key = "jump", label = "高跳", num = { "jump", 50 }, tick = jumpTick, off = restoreJump }
	feature{ key = "spin", label = "旋转", num = { "spin", 50 }, tick = spinTick, off = stopSpin }
	feature{ key = "infjump", label = "无限跳", init = function() on(UIS.JumpRequest, function() local h = hum(); if F.infjump and h then h:ChangeState(Enum.HumanoidStateType.Jumping) end end) end }
	feature{ key = "clip", label = "穿墙", tick = clipTick, off = function() reclipAll(col) end }
	feature{ key = "nv", label = "夜视", tick = nvTick, set = function(v) if v then nvOn() end end, off = nvOff }
	feature{ kind = "cycle", key = "nocd", def = "off", cycle = { "off", "normal", "force" }, text = { off = "秒互动 关", normal = "秒互动 普通", force = "秒互动 强制" }, lit = true, set = setNocd, off = function() setNocd("off") end,
		init = function() on(workspace.DescendantAdded, function(p) if F.nocd ~= "off" then patch(p) end end) end }
	feature{ kind = "hold", key = "up", label = "▲ 上升", h = 36 }
	feature{ kind = "hold", key = "down", label = "▼ 下降", h = 36 }
	feature{ kind = "num", key = "promptdist", def = 1000, label = "秒互动距离", w = 1 }
	feature{ kind = "tick", off = function() if att then att:Destroy(); att = nil end end } -- 只在卸载时: 飞行 / 旋转共用的 Attachment
	feature{ kind = "dump", key = "ui", dump = function()
		-- 日志行 16KB 护栏砍掉的那部分在这里补全: 3699 个物件砍掉 3381 个, 等于没列。
		if #uiFull == 0 then return { "还没扫过界面 (先让「动」页跑一轮再点诊断打包)" } end
		local L = { `-- 界面物件全清单 {#uiFull} 个 (一个不筛、一个不砍, 按字符串排)` }
		for _, x in ipairs(uiFull) do L[#L + 1] = "  " .. x end
		return L
	end }
end

do -- ═════════ 车: 载具 (坐着 = 控制座位所在装配体; 没坐 = 准星"换车"锁定 / 自动绑最近的空座位) ═════════
	S.turncap, S.hornkey, S.carmaxstuds, S.carswap = opt("turncap", 1), opt("hornkey", "H"), opt("carmaxstuds", 150), opt("carswap", true) -- 只读配置 (没有面板控件) -- maxstuds: 装配体外径超过这个数就不当成车(是地图/大容器). 量装配体不量 Model 容器: 车直接挂在超大容器里也认得出来
	local picked, pickSeat, pickPath, autoPick, curSeat, curMax, att, vf, lv, clipCar, lastCar, lastAnch
	local target, statT, autoT, swapT = 0, 0, 0, 0
	local lamps, lampSaved, col = {}, setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
	local lampGen = 0 -- 闪灯按住循环的代号: 松手/卸载时让旧循环当场作废
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local track, knob, kd, kdk, dragX -- 方向盘控件 (init 里建)
	local TRACK_W, TRACK_H, KNOB_R = 200, 36, 18 -- 轨道宽/高、圆点直径: 圆心行程 = TRACK_W/2 - KNOB_R = ±82, 建控件和算转向共用这一处
	local CENTER = UDim2.new(0.5, 0, 0.5, 0) -- 圆点的家: 正中
	local function seat() local h = hum(); return h and h.SeatPart end
	local function seatIn(m) return m:FindFirstChildWhichIsA("VehicleSeat", true) or m:FindFirstChildWhichIsA("Seat", true) end -- 官方继承链: VehicleSeat 和 Seat 互不相干 (都挂在 BasePart 下), 只查 "Seat" 会把带 VehicleSeat 的车当成"没座位"
	local function findByPath(path) -- 锁的那件被游戏换掉后按路径捞回来 (只在 workspace 底下找)
		local node = workspace
		for seg in tostring(path):gmatch("[^.]+") do
			node = (seg == "Workspace") and workspace or (node and node:FindFirstChild(seg))
			if not node then return nil end
		end
		return node
	end
	local swapParams = OverlapParams.new()
	swapParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterChar -- 过滤表只在换人时重设, 不每次查询都新建一个 table
	local function setFilter() if filterChar ~= me.Character then filterChar = me.Character; swapParams.FilterDescendantsInstances = { filterChar } end end
	local function asmDims(r) -- 装配体的粗略外径(格) + 质量. 判"这是车还是地图"量装配体, 不量 Model 容器: 容器可能装着整条街而车只是里面一件; 反过来整块路面自己就是一个超大装配体
		local span, rp = 0, r.Position -- r.Position 是属性读, 原来内层每件都读一次
		for _, d in ipairs(r:GetConnectedParts(true)) do
			local m = (d.Position - rp).Magnitude + 0.5 * d.Size.Magnitude -- 加半件尺寸: 单件的装配体(一整块路面)也能算出来
			if m > span then span = m end
		end
		return span * 2, nn(r.AssemblyMass)
	end
	local function heavyNear(p) -- 附近最重的"没锚定"零件: 锁到装饰件时, 真身往往是它
		setFilter()
		local best, bm, dims = nil, nil, {}
		local pp = p.Position
		for _, d in ipairs(workspace:GetPartBoundsInRadius(pp, 30, swapParams)) do
			if d:IsA("BasePart") and not d.Anchored then
				local r = d.AssemblyRootPart
				local mass = (if r then nn(d.AssemblyMass) else 0) -- 原来同一件要读两遍 AssemblyMass
				if r and mass > (bm or 0) then
					local span = dims[r]
					if span == nil then span = asmDims(r); dims[r] = span end -- 一个装配体的几十个零件只量一次外径, 不逐件重算
					if span <= S.carmaxstuds then best, bm = r, mass end -- 就近改绑也不能改绑到整条街: 30 格里最重的那件往往就是地图
				end
			end
		end
		return best
	end
	local function part() -- 控制部件, 座位
		local s = seat()
		if s then return s.AssemblyRootPart, s end
		if picked and not picked.Parent and pickPath then -- 车被换掉了: 按路径找回
			local node = findByPath(pickPath)
			if node and node:IsA("BasePart") then picked = node; toast(`车被换掉, 自动更到 {node.Name}`) end
		end
		if picked and picked:IsDescendantOf(workspace) then return picked, pickSeat end
	end
	local function scopeOf(p) -- 载具范围: 往上第一个"带座位"的 Model; 没有就取最近一个"尺寸像载具"的 Model; 绝不爬到整个街区
		if not p then return nil end
		local best, node = nil, p:FindFirstAncestorOfClass("Model")
		while node do
			if seatIn(node) then return node end
			if not best then
				local sz = node:GetExtentsSize()
				if math.max(sz.X, sz.Y, sz.Z) <= S.carmaxstuds then best = node end
			end
			node = node:FindFirstAncestorOfClass("Model")
		end
		return best
	end
	local cacheP, cacheM
	local function model() -- 缓存: 只有换部件时才重算, 不然每帧扫祖先太贵
		local p = part()
		if p ~= cacheP then cacheP, cacheM = p, scopeOf(p) end
		return cacheM
	end
	local function facing() local p, s = part(); return p and (flat((s or p).CFrame.LookVector) or Vector3.zAxis) end
	local function attach(p)
		if att and att.Parent == p then return end
		if att then att:Destroy() end
		att = mk("Attachment", { Name = "SB_SIBS" }, p)
		vf = mk("VectorForce", { Attachment0 = att, Force = Vector3.zero, RelativeTo = Enum.ActuatorRelativeTo.World, ApplyAtCenterOfMass = true }, att)
		lv = nil
	end
	local function detach() if att then att:Destroy(); att, vf, lv = nil, nil, nil end end
	local clipList, clipSeen, clipKeep, clipBottom, clipLow, clipT, clipWheels, clipFull = {}, {}, {}, {}, nil, -1, false, false
	local function wheelish(d) local nm = d.Name:lower(); return (nm:find("wheel") or nm:find("tire") or nm:find("tyre") or nm:find("轮")) ~= nil end
	local function reclip() reclipAll(col); clipCar, clipList, clipSeen, clipKeep, clipBottom, clipLow, clipT, clipWheels, clipFull = nil, {}, {}, {}, {}, nil, -1, false, false end
	local function bottomY(d) -- 零件在世界坐标里的最低点 (按旋转后的包围盒算)
		local c, z = d.CFrame, d.Size
		return d.Position.Y - 0.5 * (math.abs(c.RightVector.Y) * z.X + math.abs(c.UpVector.Y) * z.Y + math.abs(c.LookVector.Y) * z.Z)
	end
	local function keepRule(d) -- 只留轮胎碰撞; 一个轮子名都认不到时才退回"整车最低 0.5 格内"兜底, 不然车直接掉出世界
		if clipWheels then return wheelish(d) end
		return (clipBottom[d] or math.huge) <= (clipLow or math.huge) + 0.5
	end
	local function rejudge() for _, d in ipairs(clipList) do clipKeep[d] = keepRule(d) or nil end end -- 高度用第一次看到时的值: 悬挂压缩 / 车翻身都不改判, 不然轮子会被自己穿掉
	local function noclip(p, full) -- 只改本车装配体里的非锚定件, 绝不碰地面/别的车/人物; 全穿与轮胎穿墙切换时先还原再重判
		if p ~= clipCar or full ~= clipFull then reclip(); clipCar, clipFull = p, full end
		if os.clock() - clipT > 0.5 then -- 半秒补一批新零件
			clipT = os.clock()
			local fresh = {}
			for _, d in ipairs(p:GetConnectedParts(true)) do
				if d:IsA("BasePart") and not clipSeen[d] and not d.Anchored and not mine(d) then
					clipSeen[d] = true; clipList[#clipList + 1] = d; fresh[#fresh + 1] = d
					if not full then
						clipBottom[d] = bottomY(d)
						if d.CanCollide then clipLow = math.min(clipLow or math.huge, clipBottom[d]) end -- 本来就不碰撞的(影子/玻璃)不参与"最低"
						if wheelish(d) then clipWheels = true end -- 轮子可能晚一批才出现: 认到就整车重判一次
					end
				end
			end
			if not full and #fresh > 0 then rejudge() end
		end
		for _, d in ipairs(clipList) do if d.Parent and d.CanCollide and (full or not clipKeep[d]) then col[d] = true; d.CanCollide = false end end
	end
	local function dropLamps() for _, l in ipairs(lamps) do if lampSaved[l] ~= nil then l.Enabled = lampSaved[l] else l:Destroy() end end; table.clear(lamps) end
	local function asm(p) return p:GetConnectedParts(true) end -- 本车装配体的所有部件 (不是整个 Model 容器, 免得动到别人的车)
	local function setLamps(v)
		local p = part()
		if not p then return end
		local fwd = facing()
		if v and #lamps == 0 then
			for _, d in ipairs(asm(p)) do -- 先接车自己带的灯 (SpotLight/PointLight/SurfaceLight)
				if not mine(d) then
					for _, c in ipairs(d:GetChildren()) do if c:IsA("Light") then lampSaved[c] = c.Enabled; lamps[#lamps + 1] = c end end
				end
			end
			if #lamps == 0 then -- 车上本来没灯: 装到车头/车尾部件上, 不装座位; 车头朝向和车相反就照背面
				local head, tail, big, vol = nil, nil, nil, 0
				for _, d in ipairs(asm(p)) do
					if not mine(d) then
						local n = d.Name:lower()
						if not head and (n:find("head") or n:find("front") or n:find("lamp")) then head = d
						elseif not tail and (n:find("tail") or n:find("rear") or n:find("brake") or n:find("back")) then tail = d end
						local dvol = d.Size.X * d.Size.Y * d.Size.Z
						if dvol > vol then big, vol = d, dvol end
					end
				end
				head, tail = head or big, tail or big
				local hf = Enum.NormalId.Front
				if head and flat(head.CFrame.LookVector) and flat(head.CFrame.LookVector):Dot(fwd) < 0 then hf = Enum.NormalId.Back end
				lamps[1] = mk("SpotLight", { Name = "SB_Head", Brightness = 14, Range = 160, Angle = 85, Face = hf }, head)
				lamps[2] = mk("SpotLight", { Name = "SB_Tail", Brightness = 8, Range = 80, Angle = 75, Face = hf == Enum.NormalId.Front and Enum.NormalId.Back or Enum.NormalId.Front, Color = Color3.fromRGB(255, 40, 40) }, tail)
			end
		end
		for _, l in ipairs(lamps) do l.Enabled = v end
	end
	local okHorn, HORN = pcall(function() return Enum.KeyCode[S.hornkey] end) -- 存档里 hornkey 大小写写错时 Enum 索引直接抛错; horn 在卸载路径上, 不能让它炸
	if not okHorn or not HORN then HORN = Enum.KeyCode.H end
	local function horn(v) VIM:SendKeyEvent(v, HORN, false, game) end
	local function pick()
		local cam = workspace.CurrentCamera
		rp.FilterDescendantsInstances = { me.Character }
		local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 5000, rp)
		if not hit then toast("准星前面没东西"); return end
		local inst = hit.Instance
		if inst:FindFirstAncestorOfClass("Model") == nil and not inst:IsA("BasePart") then toast("打中的不是部件"); return end
		local node, seatM, s = inst:FindFirstAncestorOfClass("Model"), nil, nil
		while node do -- 往上找最近一个"里面真的有座位"的 Model: 那才是载具. 座位 = 一辆车的共同点: 不管瞄到哪个零件, 绑的都是座位所在装配体的根
			s = seatIn(node)
			if s then seatM = node; break end
			node = node:FindFirstAncestorOfClass("Model")
		end
		local r = (s or inst).AssemblyRootPart
		if inst:FindFirstAncestorOfClass("Model") and inst:FindFirstAncestorOfClass("Model"):FindFirstChildOfClass("Humanoid") then toast("打中的是人, 不是车"); return end
		if not s then -- 没座位才要判"是不是地图". 量将要绑的那个装配体, 不量祖先 Model: 车直接挂在超大容器 Model 里时, 量容器会把真车一起拒掉 (= "新构建绑不上车")
			local span, mass = asmDims(r)
			if span > S.carmaxstuds then toast(string.format("打中的是地图/大容器, 不是车 (装配体外径 %.0f 格 > 上限 %d, 质量 %.0f)", span, S.carmaxstuds, mass)); return end -- 数字打进提示: 下次误拒/漏拒, 报告自己就能说明为什么
		end
		if r.Anchored then toast("这个还锁着(锚定), 等游戏解锁"); return end
		picked, pickSeat, pickPath, autoPick = r, s, r:GetFullName(), false
		dropLamps()
		if s then toast(`锁定 {seatM.Name} · 座位 {s.Name}`)
		else toast(`锁定 {inst.Name} · 没座位(只能推/飞/翻转, 没油门)`) end
	end
	local function autoBind() -- 没坐没锁: 找最近的"空载具座位"绑上. ponytail: 每秒一次 150 格球查询; 极稠密的地图可改成 DescendantAdded 注册表
		local r = root()
		if not r then return end
		setFilter()
		local best, bd, bv
		local rp = r.Position
		for _, d in ipairs(workspace:GetPartBoundsInRadius(rp, 150, swapParams)) do
			local isV = d:IsA("VehicleSeat")
			if (isV or d:IsA("Seat")) and not d.Occupant then
				local ar = d.AssemblyRootPart -- 原来同一件要读两遍 AssemblyRootPart
				if ar and (isV or not ar.Anchored) then -- 锚定的普通 Seat 是长椅/椅子, 不是车
					local dist = (d.Position - rp).Magnitude
					if not best or (isV and not bv) or (isV == bv and dist < bd) then best, bd, bv = d, dist, isV end -- VehicleSeat 优先, 同类取最近
				end
			end
		end
		if not best then return end
		picked, pickSeat, pickPath, autoPick = best.AssemblyRootPart, best, best.AssemblyRootPart:GetFullName(), true
		dropLamps()
		toast(`自动绑定 {(best:FindFirstAncestorOfClass("Model") or best).Name} · 座位 {best.Name}`)
	end
	local function flipCar()
		local p, m = part(), model()
		if not p then toast("没有载具"); return end
		local cf = CFrame.new(p.Position + Vector3.yAxis * 2) * CFrame.fromAxisAngle(p.CFrame.LookVector, math.pi)
		if m then m:PivotTo(cf * m:GetPivot().Rotation) else p.CFrame = cf * p.CFrame.Rotation end -- 没有 Model 也能翻
		p.AssemblyAngularVelocity = Vector3.zero
	end
	local function brakeNow(p, v) p.AssemblyLinearVelocity = Vector3.yAxis * v.Y end -- 急刹: 水平速度直接归零, 比推力快且不吃质量

	local function applyDrag() -- 面板折叠才允许拖整条背景; 展开时只有圆点转向, 背景不接管触摸
		track.Active = not body.Visible
	end
	local REACH = TRACK_W / 2 - KNOB_R -- 圆心能走的单侧行程 (82)
	local function steer()
		local cx = track.AbsolutePosition.X + TRACK_W / 2
		local s = math.clamp((dragX or cx) - cx, -REACH, REACH)
		knob.Position = UDim2.new(0.5, s, 0.5, 0) -- 圆点是纯显示, 只跟手指
		return s / REACH
	end
	local function moveVec() -- 摇杆原始输入 (前推 Z=-1, 右推 X=1). 官方 UserInputService 没有 GetMoveVector (那是 PlayerModule.ControlModule 的方法), 真引擎里一调就抛错; 这里把 Humanoid.MoveDirection (相机相对的世界方向) 换回相机坐标
		local h, md = hum(), nil
		md = h and h.MoveDirection
		if not md or md.Magnitude < 1e-3 then return Vector3.zero end
		local r = flat(workspace.CurrentCamera.CFrame.RightVector) or Vector3.xAxis
		return Vector3.new(md:Dot(r), 0, -md:Dot(Vector3.yAxis:Cross(r)))
	end
	local function wheelInit() -- 建好页之后: 钉在屏幕底部的方向盘 (有副作用, 不能放块级)
		local sp = opt("steerpos", nil) -- 上次搬到的位置: 跟面板位置同一套做法, 存绝对像素、读回来夹回屏幕内
		local homeX, homeY = 0.25 * vp.X - TRACK_W / 2, vp.Y - 10 - TRACK_H -- 默认: 左下正中(左半幅的水平中点), 离底边 10px
		local sx = (if type(sp) == "table" and sp[1] then math.clamp(sp[1], 0, math.max(vp.X - TRACK_W, 0)) else homeX)
		local sy = (if type(sp) == "table" and sp[2] then math.clamp(sp[2], 0, math.max(vp.Y - TRACK_H, 0)) else homeY)
		track = mk("Frame", { Name = "SB_Steer", AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(sx, sy), Size = UDim2.fromOffset(TRACK_W, TRACK_H), BackgroundColor3 = BG, BackgroundTransparency = 0.4, BorderSizePixel = 0, Visible = false, ZIndex = 10 }, gui)
		mk("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
		knob = mk("Frame", { Name = "SB_Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = CENTER, Size = UDim2.fromOffset(KNOB_R * 2, KNOB_R * 2), BackgroundColor3 = Color3.fromRGB(95, 65, 135), BorderSizePixel = 0, Active = true, ZIndex = 11 }, track) -- 圆点任何时候都能拖(转向)
		mk("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
		-- 拖背景 = 搬整条滑条(横竖都行), 照抄标题条那套: 检测器只报手指坐标, 位置自己算并夹在屏幕内, 松手存盘
		kd = mk("UIDragDetector", { BoundingUI = gui }, track)
		local dragOff
		on(kd.DragStart, function(p) if body.Visible then return end -- 面板开着不许搬背景: 不只靠 track.Active, 处理函数自己也挡一道
			dragOff = Vector2.new(p.X - track.AbsolutePosition.X, p.Y - track.AbsolutePosition.Y)
		end)
		on(kd.DragContinue, function(p) -- DragContinue 给的是 inputPosition: Vector2(屏幕坐标), 不是 InputObject
			if not dragOff or body.Visible then return end
			track.Position = UDim2.fromOffset(math.clamp(p.X - dragOff.X, 0, math.max(vp.X - TRACK_W, 0)), math.clamp(p.Y - dragOff.Y, 0, math.max(vp.Y - TRACK_H, 0)))
		end)
		on(kd.DragEnd, function() if not dragOff then return end; dragOff = nil; save("steerpos", { track.AbsolutePosition.X, track.AbsolutePosition.Y }) end) -- 没真拖动过就不写盘
		local function release() dragX = nil; knob.Position = CENTER end -- 拖圆点松手即刻回正, 不等下一帧 steer()
		kdk = mk("UIDragDetector", { DragStyle = Enum.UIDragDetectorDragStyle.TranslateLine, DragAxis = Vector2.new(1, 0), BoundingUI = track }, knob) -- 拖圆点 = 转向(只横); 必须以轨道为边界: 圆点 36 / 轨道 200 → 行程正好 ±82, 拖不出去。上一版凭猜测把这个 BoundingUI 删了, 真机上圆点就能被拖出轨道
		on(kdk.DragContinue, function(p) dragX = p.X end)
		on(kdk.DragEnd, release)
		foldHooks[#foldHooks + 1] = applyDrag -- 折叠状态一变就重算可拖区
		applyDrag()
	end

	local function carTick(dt)
		local s = seat()
		if s ~= curSeat then -- 换座: 还原旧座限速, 新座解限速, 灯重挂
			if curSeat and curMax then curSeat.MaxSpeed = curMax end
			curSeat, curMax = s, s and s:IsA("VehicleSeat") and s.MaxSpeed or nil
			if curMax then s.MaxSpeed = math.huge end
			dropLamps()
			if F.lamp then setLamps(true) end
		end
		if s and autoPick then picked, pickSeat, pickPath, autoPick = nil, nil, nil, false end -- 坐下了: 座位优先, 自动绑的作废; 下车后再找最近的
		local p, sp = part()
		if not p and not s and F.carauto and os.clock() - autoT > 1 then autoT = os.clock(); autoBind(); p, sp = part() end -- 一进游戏就绑: 没坐没锁时每秒找一次
		if p and not sp and p.Anchored and S.carswap and os.clock() - swapT > 1 then swapT = os.clock() -- 改绑跟 autoBind 一样每秒一次: 原来每帧都做一次 30 格球查询 + 逐件量装配体, 而锚定件一锚就是好几秒, 白烧帧. 代价是改绑最多晚 1 秒
			-- 没座位的锚定件(还没解锁/装饰件): 就近改绑到能推的那件. 有座位的车不改绑: 座位所在装配体就是车, 锚着就等游戏解锁
			local cand = heavyNear(p)
			if cand and cand ~= p then
				picked, pickSeat, pickPath = cand, nil, cand:GetFullName()
				toast(`锚定件改用 {(cand.Name)}`)
				p, sp = cand, nil
			end
		end
		track.Visible = p ~= nil
		if not p then detach(); if clipCar then reclip() end; return end
		attach(p) -- 锚定的车照样绑: 早先的实现一锚定就直接 return, 所以"要动一会(等游戏解锁)才能绑上"
		local anch = p.Anchored -- 锚定 = 引擎不让推, 只能等游戏自己解锁; 滑条转向走 CFrame 照样有效
		if anch ~= lastAnch then
			if lastAnch and not anch then toast("车解锁了, 推力生效") end -- 之前锚着现在放开 = 游戏把车交出来了
			lastAnch = anch
		end
		local m = model()
		if lastCar then lastCar.p, lastCar.s, lastCar.m, lastCar.path = p, s, m, p:GetFullName() else lastCar = { p = p, s = s, m = m, path = p:GetFullName() } end -- 诊断打包用: 哪怕打包时已经下车
		local v = p.AssemblyLinearVelocity
		local hv = Vector3.new(v.X, 0, v.Z)
		local spd, mass, fwd = hv.Magnitude, p.AssemblyMass, facing()
		local gst, thr, st = 0, 0, steer()
		if sp and sp:IsA("VehicleSeat") then gst, thr, st = sp.Steer, sp.Throttle, math.clamp(st + sp.Steer, -1, 1) end -- 游戏自带的手机油门/方向盘也吃
		local acc, dec = F.accel or thr > 0, F.decel or thr < 0
		if os.clock() - statT > 0.2 then statT = os.clock(); say("car_status", `{(m and m.Name or p.Name)} · {(math.floor(spd + 0.5))}{((if s then "" else " · 准星锁定"))}{((if anch then " · 锚定(等游戏解锁)" else ""))}{(F.carclip and not F.carclipall and #clipList > 0 and not clipWheels and " · 穿墙没认到轮子(按最低块兜底)" or "")}`) end
		if F.carclipall then noclip(p, true) elseif F.carclip then noclip(p, false) elseif clipCar then reclip() end
		if F.cfly then -- 飞车: 摇杆(前后左右) + 面板按钮都吃; 松手悬停
			if not lv then lv = mk("LinearVelocity", { Attachment0 = att, MaxForce = math.huge, VectorVelocity = Vector3.zero, RelativeTo = Enum.ActuatorRelativeTo.World }, att) end
			local mv = moveVec() -- 摇杆: 前推 Z=-1, 右推 X=1
			local dir = fwd * math.clamp(-mv.Z + ((if acc then 1 else 0)) - ((if dec then 1 else 0)), -1, 1) + (flat(p.CFrame.RightVector) or Vector3.xAxis) * math.clamp(mv.X, -1, 1)
			if dir.Magnitude > 1 then dir = dir.Unit end
			lv.VectorVelocity = anch and Vector3.zero or (dir * S.carfly + Vector3.yAxis * (S.carfly * (((if F.cup then 1 else 0)) - ((if F.cdown then 1 else 0)))))
			vf.Force = Vector3.zero
			return
		elseif lv then lv:Destroy(); lv = nil end
		-- 转向: 游戏自己的 Steer 那部分让它自己转, 我们只转滑条多出来的部分, 不重复
		local mine = st - gst
		if math.abs(mine) > 0.02 then -- 停着也能转(原地打方向), 不再等车动起来
			p.CFrame = CFrame.fromAxisAngle(Vector3.yAxis, -mine * S.turn * math.clamp(spd / 25, 0.2, S.turncap) * dt) * p.CFrame.Rotation + p.Position -- turncap = 转向速率随速度放大的上限
			if spd > 1 then
				local dir = hv:Dot(fwd) < 0 and -fwd or fwd
				p.AssemblyLinearVelocity = hv.Unit:Lerp(dir, math.min(dt * S.grip, 1)).Unit * spd + Vector3.yAxis * v.Y
			end
		end
		local f, push = mass * S.acc, Vector3.zero
		if F.brake then -- 急刹: 刹到停, 再踩油门自动解除
			if acc then W.brake(false) else brakeNow(p, v) end
		elseif acc and dec then brakeNow(p, v)
		elseif acc then push = fwd * f
		elseif dec then push = -fwd * (f * ((if hv:Dot(fwd) > 3 then 2 else 1))) -- 前进中双倍刹, 停了就倒车
		elseif F.cruise then push = fwd * math.clamp((target - hv:Dot(fwd)) * mass * 2, -f, f) end
		if not F.cruise then target = hv:Dot(fwd) end -- 定速一开就锁当前车速
		if anch then vf.Force = Vector3.zero else vf.Force = push end -- 锚定: 力无效, 清零等着
	end

	local function carLines()
		local p, s, cached = part()
		if not p and lastCar then p, s, cached = lastCar.p, lastCar.s, true end -- 打包时没车也能带出最近一辆的结构
		if not p then return { "没有载具 (先用 换车 锁定或坐上去, 再点诊断打包)" } end
		if cached and not (p:IsDescendantOf(workspace)) then
			return { `最近一辆: {tostring(lastCar.path)}`, "  已经不在 workspace 里了(被游戏销毁/回收) → 结构拿不到, 只能在车还在的时候点诊断打包" }
		end
		local m = cached and lastCar.m or model()
		local L = { "==== CAR " .. os.date("%Y-%m-%d ") .. clock(true) .. " place=" .. game.PlaceId .. ((if cached then " (缓存的最近一辆)" else "")) .. " ====",
			`座位: {(s and s:GetFullName() or "-")}   根部件: {p:GetFullName()}   Model: {(m and m:GetFullName() or "-")}`,
			string.format("根部件 质量=%.0f 锚定=%s 速度=%.1f 尺寸=(%.0f,%.0f,%.0f)", p.AssemblyMass, tostring(p.Anchored), p.AssemblyLinearVelocity.Magnitude, p.Size.X, p.Size.Y, p.Size.Z) }
		if s and s:IsA("VehicleSeat") then
			L[#L + 1] = string.format("座位: MaxSpeed=%s Torque=%.0f Throttle=%.2f Steer=%.2f 乘员=%s", tostring(s.MaxSpeed), nn(s.Torque), nn(s.Throttle), nn(s.Steer), s.Occupant and (s.Occupant.Parent and s.Occupant.Parent.Name or "?") or "无")
		end
		if clipCar then
			local kept, off = 0, 0
			for _, d in ipairs(clipList) do if clipKeep[d] then kept = kept + 1 elseif d.Parent and not d.CanCollide then off = off + 1 end end
			L[#L + 1] = string.format("穿墙: 认到轮子=%s 保留碰撞=%d 块 已穿=%d 块 (范围=本车装配体, 不是整个 Model 容器)", tostring(clipWheels), kept, off)
		end
		L[#L + 1] = "-- 装配体部件 (含游戏自己的约束/灯/脚本钩子)"
		for _, d in ipairs(p:GetConnectedParts(true)) do
			if not mine(d) then
				L[#L + 1] = string.format("  %-26s %-14s 锚=%-5s 质量=%.0f 尺寸=(%.0f,%.0f,%.0f)", d.Name, d.ClassName, tostring(d.Anchored), d.AssemblyMass, d.Size.X, d.Size.Y, d.Size.Z)
				for _, c in ipairs(d:GetChildren()) do
					if c:IsA("Light") then L[#L + 1] = `        灯 {c.ClassName} {c.Name} Enabled={tostring(c.Enabled)}`
					elseif c:IsA("Constraint") or c:IsA("BodyMover") or c:IsA("Attachment") then L[#L + 1] = `        {c.ClassName} {c.Name}`end
				end
			end
		end
		-- 准星现在打到什么: 车不听话时这一条最有用
		local cam = workspace.CurrentCamera
		rp.FilterDescendantsInstances = { me.Character }
		local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 5000, rp)
		L[#L + 1] = `-- 准星射线: {(hit and (hit.Instance.ClassName .. " " .. hit.Instance:GetFullName()) or "没打到东西")}`
		if hit then
			local chain, x = {}, hit.Instance
			while x and x ~= workspace do chain[#chain + 1] = `{x.Name}({x.ClassName})`; x = x.Parent end
			L[#L + 1] = `    祖先: {table.concat(chain, " ← ")}`
		end
		L[#L + 1] = "-- 周围的座位 (以车为圆心 150 格内, 半径扫描, 不看场景多大)"
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Exclude
		op.FilterDescendantsInstances = { me.Character }
		local center = p.Position
		local found = {}
		for _, d in ipairs(workspace:GetPartBoundsInRadius(center, 150, op)) do if d:IsA("Seat") or d:IsA("VehicleSeat") then found[#found + 1] = d end end
		if #found == 0 then L[#L + 1] = "    车周围 150 格没有 Seat/VehicleSeat → 这辆车没有座位"
		else
			for _, d in ipairs(found) do
				L[#L + 1] = string.format("    %-34s %-12s 距离=%.0f 乘员=%s", d:GetFullName(), d.ClassName, (d.Position - center).Magnitude, d.Occupant and (d.Occupant.Parent and d.Occupant.Parent.Name or "?") or "空")
			end
		end
		L[#L + 1] = "-- 车周围 25 格里的部件 (车的真身, 不依赖 Model 层级)"
		local near = 0
		for _, d in ipairs(workspace:GetPartBoundsInRadius(center, 25, op)) do
			if d:IsA("BasePart") and near < 24 then
				near += 1
				L[#L + 1] = string.format("    %-30s %-14s 距离=%.0f 质量=%.0f 尺寸=(%.0f,%.0f,%.0f)", d.Name, d.ClassName, (d.Position - center).Magnitude, nn(d.AssemblyMass), d.Size.X, d.Size.Y, d.Size.Z)
			end
		end
		return L
	end
	local function seatInfo(s)
		if not s then return " 没坐(准星锁定)"
		elseif s:IsA("VehicleSeat") then return string.format(" 座=%s 油门=%.2f 方向=%.2f", s.Name, nn(s.Throttle), nn(s.Steer))
		else return " 座=" .. s.Name .. "(普通座, 无油门/方向)" end
	end
	local function holdInfo() return ((if F.accel then " 按加速" else "")) .. ((if F.decel then " 按减速" else "")) .. ((if F.cup then " 按升" else "")) .. ((if F.cdown then " 按降" else "")) end
	local function carInfo()
		local p, s = part()
		if p and vf then
			return string.format("抓地=%s/转向=%s/过弯上限=%s 部件=%s%s 推力=%.0f(%.1f/kg) 质量=%.0f 速度=%.0f%s 定速=%s@%.0f 飞车=%s 穿墙=%s 全穿=%s 急刹=%s%s",
				S.grip, S.turn, S.turncap, p:GetFullName(), seatInfo(s), vf.Force.Magnitude, vf.Force.Magnitude / math.max(p.AssemblyMass, 1), p.AssemblyMass,
				p.AssemblyLinearVelocity.Magnitude, (if p.Anchored then " 锚定(引擎不让推)" else ""), tostring(F.cruise), target, tostring(F.cfly), tostring(F.carclip), tostring(F.carclipall), tostring(F.brake), holdInfo())
		end
		return "抓地=" .. S.grip .. "/转向=" .. S.turn .. "/过弯上限=" .. S.turncap .. " 部件=-" .. seatInfo(nil) .. " 定速=" .. tostring(F.cruise) .. "@" .. math.floor(target) .. " 飞车=" .. tostring(F.cfly) .. " 穿墙=" .. tostring(F.carclip) .. " 全穿=" .. tostring(F.carclipall) .. " 急刹=" .. tostring(F.brake) .. holdInfo()
	end
	local function carStop() detach(); reclip(); dropLamps(); horn(false); if curSeat and curMax then curSeat.MaxSpeed = curMax end end
	feature{ kind = "page", id = "sibs", tab = "车", info = carInfo }
	feature{ kind = "num", key = "acc", def = 500, label = "加速" }
	feature{ kind = "num", key = "carfly", def = 60, label = "飞速" }
	feature{ kind = "num", key = "grip", def = 5, label = "抓地" }
	feature{ kind = "num", key = "turn", def = 2.2, label = "转向" }
	feature{ kind = "btn", label = "换车(准星)", fn = pick }
	feature{ key = "carclip", save = "carclip", label = "穿墙" }
	feature{ key = "carclipall", save = "carclipall", label = "全穿" }
	feature{ key = "cruise", label = "定速" }
	feature{ key = "cfly", label = "飞车" }
	feature{ kind = "btn", label = "翻转 180°", fn = flipCar }
	feature{ key = "lamp", label = "常亮", set = function(v) if v then setLamps(true) else dropLamps() end end }
	local function flash(v) -- 按住就持续闪, 松手还原常亮开关之前的灯状态
		lampGen += 1; local gen = lampGen
		if not v then if F.lamp then setLamps(true) else dropLamps() end; return end
		task.spawn(function()
			while alive and gen == lampGen and F.flash do
				if not alive or gen ~= lampGen then return end
				setLamps(true); task.wait(0.12)
				if not alive or gen ~= lampGen then return end
				setLamps(false); task.wait(0.12)
			end
			if alive and gen == lampGen then if F.lamp then setLamps(true) else dropLamps() end end
		end)
	end
	feature{ kind = "hold", key = "flash", label = "闪", set = flash }
	feature{ key = "carauto", save = "carauto", def = true, label = "自动绑车", w = 1 }
	feature{ key = "hornon", label = `常声({S.hornkey})`, set = horn }
	feature{ kind = "hold", label = "声", set = horn }
	feature{ key = "brake", label = "急刹", w = 1, h = 36 } -- 单占一行, 加高方便触屏急停
	feature{ kind = "hold", key = "accel", label = "▲ 加速", h = 36 }
	feature{ kind = "hold", key = "decel", label = "▼ 减速", h = 36 }
	feature{ kind = "hold", key = "cup", label = "飞 ↑", h = 36 }
	feature{ kind = "hold", key = "cdown", label = "飞 ↓", h = 36 }
	feature{ kind = "text", key = "car_status", label = "上车即控; 没车就对准它按 换车" }
	feature{ kind = "dump", key = "car", dump = carLines }
	feature{ kind = "tick", tick = carTick, init = wheelInit, off = carStop }
end

do -- ═════════ 漂: 人物推进 (开着就一直沿车头方向推, 不需要油门/刹车) ═════════
	local att, vf
	local function driftTick()
		local c = me.Character
		local r = c and c:FindFirstChild("Root") or root() -- 漂移游戏的车体叫 Root
		if not (r and r:IsDescendantOf(workspace)) or r.Anchored then if att then att:Destroy(); att = nil end; return end
		if not att or att.Parent ~= r then
			if att then att:Destroy() end
			att = mk("Attachment", { Name = "SB_DRIFT" }, r)
			vf = mk("VectorForce", { Attachment0 = att, Force = Vector3.zero, RelativeTo = Enum.ActuatorRelativeTo.World, ApplyAtCenterOfMass = true }, att)
		end
		local look = flat(r.CFrame.LookVector) or Vector3.zAxis
		vf.Force = look * (S.dacc * r.AssemblyMass) -- 力按质量给, 换车体不用重调数字
	end
	local function driftOff() if att then att:Destroy(); att = nil end end
	feature{ kind = "page", id = "drift", tab = "漂", info = function()
		local c = me.Character
		local r = c and c:FindFirstChild("Root") or root()
		if not (r and r:IsDescendantOf(workspace)) then return "加速=" .. tostring(S.dacc) .. " 无车体" end
		local look = flat(r.CFrame.LookVector) or Vector3.zAxis
		return string.format("加速=%s 前向速度=%.1f 质量=%.0f 锚=%s", tostring(S.dacc), r.AssemblyLinearVelocity:Dot(look), nn(r.AssemblyMass), tostring(r.Anchored))
	end }
	feature{ kind = "num", key = "dacc", def = 5, label = "加速" }
	feature{ key = "drift", save = "drift", def = true, label = "推进", tick = driftTick, off = driftOff }
end

do -- ═════════ 显: 数据条 / 速度箭头 / 玩家 ESP (原生 Highlight + BillboardGui) ═════════
	local bar, arrow, arrowTxt
	local esp, frames, fps, tick = {}, 0, 0, os.clock()
	local function espAdd(pl)
		if pl == me or esp[pl] then return end
		local hl = mk("Highlight", { FillTransparency = 0.6, OutlineTransparency = 0.2, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Enabled = false }, FX) -- ponytail: 引擎同时只画 31 个 Highlight, 更多人时超出的不显示
		local bb = mk("BillboardGui", { Size = UDim2.fromOffset(160, 16), StudsOffsetWorldSpace = Vector3.yAxis * 3.2, AlwaysOnTop = true, Enabled = false }, FX)
		esp[pl] = { hl, bb, mk("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextStrokeTransparency = 0.5 }, bb) }
	end
	local function espDrop(pl) local e = esp[pl]; if e then e[1]:Destroy(); e[2]:Destroy(); esp[pl] = nil end end
	local function hudInit() -- 建好页之后: 盖在游戏画面上的三个控件 + 接玩家进出 (有副作用, 不能放块级: _G.SB.only 没装的页不该建)
		bar = mk("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, RichText = true, Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = WHITE, TextStrokeTransparency = 0.6 }, gui)
		arrow = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(0, 3), BackgroundColor3 = Color3.fromRGB(150, 225, 200), BackgroundTransparency = 0.3, BorderSizePixel = 0, Visible = false }, gui)
		arrowTxt = mk("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(90, 14), BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = Color3.fromRGB(150, 225, 200), TextStrokeTransparency = 0.5, Visible = false }, gui)
		for _, pl in ipairs(Players:GetPlayers()) do espAdd(pl) end
		on(Players.PlayerAdded, espAdd)
		on(Players.PlayerRemoving, espDrop)
	end
	local function hudRender()
		frames += 1
		local cam, r, now = workspace.CurrentCamera, root(), os.clock()
		local shown = false
		if F.arrow and cam then
			local h = hum()
			local a = h and h.SeatPart and h.SeatPart.AssemblyRootPart or r
			local v = a and a.AssemblyLinearVelocity
			if v and v.Magnitude > 0.5 then
				local from = a.Position + Vector3.yAxis * (a.Size.Y / 2 + 2)
				local p1, ok1 = cam:WorldToViewportPoint(from)
				local p2, ok2 = cam:WorldToViewportPoint(from + v.Unit * math.clamp(v.Magnitude * 0.16, 3, 8))
				if ok1 and ok2 then
					local d, cx, cy = Vector2.new(p2.X - p1.X, p2.Y - p1.Y), (p1.X + p2.X) / 2, (p1.Y + p2.Y) / 2
					arrow.Position, arrow.Size, arrow.Rotation = UDim2.fromOffset(cx, cy), UDim2.fromOffset(d.Magnitude, 3), math.deg(math.atan2(d.Y, d.X))
					arrowTxt.Position, arrowTxt.Text = UDim2.fromOffset(cx, cy - 4), string.format("%.0f", Vector3.new(v.X, 0, v.Z).Magnitude) .. (math.abs(v.Y) > 0.5 and string.format(" %+.0f", v.Y) or "")
					shown = true
				end
			end
		end
		arrow.Visible, arrowTxt.Visible = shown, shown
		if now - tick < 0.2 then return end
		fps, frames, tick = frames / (now - tick), 0, now
		bar.Visible = F.stats
		if F.stats then
			local pos = r and string.format("%.0f %.0f %.0f", r.Position.X, r.Position.Y, r.Position.Z) or "-"
			bar.Text = string.format("<font color='#89dceb'>%.0f</font>  <font color='%s'>%.0f</font>  <font color='#c8b4eb'>%.0f</font>  <font color='#ebc896'>%s</font>  <font color='#eb96aa'>%d/%d</font>  <font color='#d2d4de'>%s</font>",
				me:GetNetworkPing() * 1000, (if fps >= 50 then "#aae696" else "#eb7878"), fps, Stats:GetTotalMemoryUsageMb(), clock(), #Players:GetPlayers(), Players.MaxPlayers, pos) -- 数字后面不带单位, 靠颜色认: 青=延迟 绿/红=帧率 紫=内存 黄=时间 粉=人数 灰=坐标
		end
		for pl, e in pairs(esp) do
			local c = pl.Character
			local h, hr = c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
			local show = F.esp and h ~= nil and hr ~= nil and h.Health > 0
			e[1].Enabled, e[2].Enabled = show, show
			if show then
				local colr = pl.Team and pl.TeamColor.Color or Color3.fromHSV((pl.UserId * 0.618) % 1, 0.65, 1)
				e[1].Adornee, e[1].FillColor, e[1].OutlineColor = c, colr, colr
				e[2].Adornee, e[3].TextColor3 = hr, colr
				e[3].Text = pl.DisplayName .. (r and string.format(" %.0f", (hr.Position - r.Position).Magnitude) or "")
			end
		end
	end
	feature{ kind = "page", id = "hud", tab = "显" }
	feature{ kind = "tick", sig = "render", tick = hudRender, init = hudInit, off = function() for pl in pairs(esp) do espDrop(pl) end end }
	feature{ key = "stats", save = "stats", def = true, label = "数据条" }
	feature{ key = "arrow", save = "arrow", def = true, label = "速度箭头" }
	feature{ key = "esp", save = "esp", def = true, label = "玩家 ESP", w = 1 }
end

do -- ═════════ 志: 周期记录 / 诊断打包 ═════════
	local LOGFILE, count, written = "Selfblox_log.txt", 0, 0
	local function head() local h = `---- Selfblox {VERSION} {os.date("%Y-%m-%d ")}{clock(true)} ----\n`; writefile(LOGFILE, h); written = #h end -- 文件头带版本: 日志文件会跨会话留着, 不带版本就分不清这一份是哪个构建录的
	local function logTick() -- 每 S.logint 秒一轮 (清单的 loop 每轮 pcall: 某个页的状态函数 / 序列化 / 写盘抛错, 记录也不会永久停)
		local L = { `[{clock(true)}] #{count}`, `配置 {Http:JSONEncode(saved)}` } -- 数值不用各模块自己拼, 这里全有
		for _, line in ipairs(pageInfos()) do L[#L + 1] = line end
		local txt = `{table.concat(L, "\n")}\n`
		if written == 0 or written + #txt > S.logmax * 1024 then head() end -- ponytail: 超限直接重写, 不归档; 要历史自己复制文件
		appendfile(LOGFILE, txt)
		count, written = count + 1, written + #txt
		say("log_status", `#{count} · {(math.floor(written / 1024))}KB / {S.logmax}KB`)
	end
	feature{ kind = "page", id = "log", tab = "志" }
	feature{ kind = "text", key = "log_status", label = `开 录制 后写 {LOGFILE}` }
	feature{ kind = "btn", label = "诊断打包 (快照→剪贴板)", w = 1, fn = function() if dumpNow then dumpNow() end end }
	feature{ kind = "num", key = "logint", def = 2, label = "间隔s" }
	feature{ kind = "num", key = "logmax", def = 512, label = "上限KB" }
	feature{ key = "rec", label = "录制", w = 1, loop = logTick, every = function() return S.logint end,
		onerr = function(err) say("log_status", `记录出错 (下一轮再试): {tostring(err)}`) end }
end

do -- ═════════ 机: 飞机侦察 (找飞机 / 判队伍 / 列 Remote / 收发侦听 / 写报告) ═════════
	local HINT = { "plane", "jet", "aircraft", "fighter", "bomber", "heli", "glider", "warbird", "biplane", "gunship", "blimp" }
	local WING = { "wing", "aileron", "rudder", "elevator", "propeller", "rotor", "flap", "stabilizer", "tailfin" }
	local TEAMK = { "team", "faction", "side", "country", "nation" }
	local OWNK = { "owner", "pilot" } -- OldOwner/Owner/Pilot 这类属性: 被服务器接管的飞机座位是空的, 只剩属性还写着你的名字
	local RHINT = { "fire", "shoot", "shot", "bullet", "gun", "weapon", "attack", "damage", "hit", "kill", "launch", "missile", "rocket", "bomb", "plane", "spawn", "team", "seat", "pilot" }
	local function hint(name, list) name = name:lower(); for _, h in ipairs(list) do if name:find(h, 1, true) then return h end end end
	local planes, remotes, sent, got, hls, watch = {}, {}, {}, {}, {}, {}
	local oldNC
	local function fmt(v, depth)
		local t = typeof(v)
		if t == "Instance" then return v:GetFullName()
		elseif t == "Vector3" then return string.format("(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z)
		elseif t == "CFrame" then return fmt(v.Position)
		elseif t == "string" then return '"' .. v:sub(1, 60) .. '"'
		elseif t == "table" then
			if (depth or 0) >= 2 then return "{…}" end
			local o = {}
			for k, x in pairs(v) do o[#o + 1] = `{tostring(k)}={fmt(x, (depth or 0) + 1)}`; if #o >= 8 then break end end
			return "{" .. table.concat(o, ",") .. "}"
		end
		return tostring(v)
	end
	local function args(a) local o = {}; for i = 1, a.n do o[i] = fmt(a[i]) end; return table.concat(o, ", ") end
	local CAP = 400 -- 组数上限. 原来 200 条不折叠: 飞行中 EngineSync+VehicleReplication 每秒 ~20 条, 200 条只装得下 10 秒, 一生只发一次的 RequestPlane/SpawnHangarPlane 必被挤掉
	local function keyOf(a) local v = a[1]; return typeof(v) == "Instance" and v:GetFullName() or "" end -- 折叠键: 同一个 Remote 打同一个目标算一组
	local function push(log, k, s) -- 连续同键的只累加次数, 并留下首末两条 payload: 刷屏的复制包不再吃掉整个窗口
		local e = log[#log]
		if e and e.k == k then e.n, e.t1, e.s1 = e.n + 1, clock(true), s; return end
		local t = clock(true)
		log[#log + 1] = { k = k, n = 1, t0 = t, t1 = t, s0 = s, s1 = s }
		if #log > CAP then table.remove(log, 1) end
	end
	local function tot(log) local n = 0; for _, e in ipairs(log) do n = n + e.n end; return n end -- 折叠前的真实条数
	local function dump(log) -- 报告行: 一组一行 (时间跨度 + ×N + 首条), 首末不同再补一行「末」→ EngineSync 从 0.64 衰减到 0 这种趋势还看得见
		local o = {}
		for _, e in ipairs(log) do
			o[#o + 1] = `  {(e.n > 1 and e.t0 .. "→" .. e.t1 .. " ×" .. e.n .. " " or e.t0 .. " ")}{e.s0}`
			if e.n > 1 and e.s1 ~= e.s0 then o[#o + 1] = `      末 {e.s1}`end
		end
		return o
	end
	local function team(p) -- 属性 → Value → 乘员队伍 → 名字 → 最大部件颜色最接近的 Team
		for k, v in pairs(p.model:GetAttributes()) do if hint(k, TEAMK) then return tostring(v), "attr:" .. k end end
		if p.teamVal then return p.teamVal, "value" end
		if p.occ and p.occ.Team then return p.occ.Team.Name, "乘员", p.occ.Team end
		local n = hint(p.model.Name, { "red", "blue", "axis", "allied", "ally" })
		if n then return n, "名字" end
		if p.big then
			local best, bd, c0 = nil, 0.5, p.big.Color
			for _, t in ipairs(Teams:GetTeams()) do
				local c = t.TeamColor.Color
				local d = (Vector3.new(c0.R, c0.G, c0.B) - Vector3.new(c.R, c.G, c.B)).Magnitude
				if d < bd then best, bd = t, d end
			end
			if best then return best.Name, "涂装≈", best end
		end
		return "?", "-"
	end
	local function isRemote(d) return d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") end
	local function inspect(m)
		local p = { model = m, path = m:GetFullName(), hint = hint(m.Name, HINT), seat = false, wings = 0, parts = 0, remotes = {}, vol = 0 }
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("Seat") or d:IsA("VehicleSeat") then
				p.seat = true
				local o = d.Occupant
				p.occ = p.occ or (o and Players:GetPlayerFromCharacter(o.Parent))
			elseif isRemote(d) then p.remotes[#p.remotes + 1] = d
			elseif d:IsA("BasePart") then
				p.parts += 1
				if hint(d.Name, WING) then p.wings = p.wings + 1 end
				local vol = d.Size.X * d.Size.Y * d.Size.Z
				if vol > p.vol then p.big, p.vol = d, vol end
			elseif d:IsA("ValueBase") and hint(d.Name, TEAMK) then p.teamVal = p.teamVal or (`{d.Name}={fmt(d.Value)}`) end
		end
		p.score = ((if p.hint then 40 else 0)) + ((if p.seat then 35 else 0)) + math.min(p.wings, 2) * 12 + ((if p.parts >= 8 then 10 else 0)) + ((if p.occ then 5 else 0))
		p.team, p.src, p.teamObj = team(p)
		p.mine = p.occ == me
		if not p.mine then -- 被服务器接管的自家飞机: 座位空着, 只剩 OldOwner 这类属性还写着你 → 只看乘员会把它算成别人的残留机
			for k, v in pairs(m:GetAttributes()) do
				if hint(k, OWNK) and (v == me or v == me.Name) then p.mine, p.ownBy = true, k; break end
			end
		end
		return p
	end
	local function highlight()
		for _, h in ipairs(hls) do h:Destroy() end
		table.clear(hls)
		if not F.hl then return end
		for _, p in ipairs(planes) do
			local c = p.mine and Color3.fromRGB(80, 255, 80) or (p.teamObj and me.Team and (p.teamObj == me.Team and Color3.fromRGB(80, 140, 255) or Color3.fromRGB(255, 70, 70))) or Color3.fromRGB(170, 170, 170)
			hls[#hls + 1] = mk("Highlight", { Adornee = p.model, FillColor = c, OutlineColor = c, FillTransparency = 0.75 }, FX)
		end
	end
	local function setWatch(v)
		for _, c in ipairs(watch) do c:Disconnect() end
		table.clear(watch)
		if not v then return end
		if #remotes == 0 then say("plane_status", "收侦听开着但一个都没挂上: 先点 重扫 (收 是拿扫出来的 Remote 列表挂 OnClientEvent 的)"); return end -- 没扫描过 → remotes 是空的 → 收 永远 0, 看着像"服务器没发"
		for _, r in ipairs(remotes) do
			if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") then
				watch[#watch + 1] = r.OnClientEvent:Connect(function(...) local a = table.pack(...); push(got, `{r:GetFullName()} <- {keyOf(a)}`, `{r:GetFullName()} <- {args(a)}`) end)
			end
		end
	end
	local function setSpy(v)
		if v and not oldNC then
			oldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
				local m = getnamecallmethod()
				if F.spy and (m == "FireServer" or m == "InvokeServer") then
					local a = table.pack(...)
					pcall(function() local path = self:GetFullName(); if F.pall or hint(path, RHINT) then push(sent, `{path}:{m} {keyOf(a)}`, `{path}:{m} {args(a)}`) end end) -- 记录失败不能拦住游戏自己的调用
				end
				return oldNC(self, ...)
			end))
		end
		return true
	end
	local scanAt, rejects = nil, {} -- rejects: 扫到但没过门槛的, 报告里列出来 → 下次该把门槛调到哪, 报告自己会说
	local function outerModel(d) local m = d:FindFirstAncestorOfClass("Model"); while m and m.Parent and m.Parent:IsA("Model") do m = m.Parent end; return m end -- ponytail: 全部飞机套在一个 Model 里会被并成一架
	local function scan()
		table.clear(planes)
		table.clear(remotes)
		table.clear(rejects)
		local cand = {}
		local function remote(d) if isRemote(d) and (F.pall or hint(d:GetFullName(), RHINT)) then remotes[#remotes + 1] = d end end
		for _, d in ipairs(workspace:GetDescendants()) do
			remote(d)
			if d:IsA("Seat") or d:IsA("VehicleSeat") then -- 候选一: 有座位的最外层 Model
				local m = outerModel(d); if m then cand[m] = "座" end
			elseif d:IsA("BasePart") and hint(d.Name, WING) then -- 候选二: 没座位的飞机(机库/菜单/刚落地的残留机)只能靠机翼名认: 只从座位出发会把自己那架整个漏掉
				local m = outerModel(d); if m and not cand[m] then cand[m] = "翼" end
			end
		end
		for m, why in pairs(cand) do
			if not m:FindFirstChildOfClass("Humanoid") then
				local p = inspect(m)
				-- 门槛 55 是"有座位"那条路. 机型名(M21/P51/BF109/Gloster/Ki10)一个都不在 HINT 里 → hint 那 40 分永远拿不到, 没座位时只剩 24+10=34 分, 所以再给一条实机路子: 2 个机翼名 + 12 件以上
				if p.score >= 55 or (p.wings >= 2 and p.parts >= 12) then planes[#planes + 1] = p
				elseif #rejects < 20 then p.why = why; rejects[#rejects + 1] = p end
			end
		end
		for _, d in ipairs(RS:GetDescendants()) do remote(d) end
		table.sort(planes, function(a, b) if a.score ~= b.score then return a.score > b.score end; return a.path < b.path end) -- 同分按路径: pairs 顺序不定, 两次报告要能对着看
		scanAt = clock(true)
		if F.watch then setWatch(true) end
		highlight()
		say("plane_status", `飞机 {#planes} · Remote {#remotes} · 发 {tot(sent)}/{#sent}组 收 {tot(got)}/{#got}组`)
	end
	local function report()
		if #planes == 0 and #remotes == 0 then scan() end -- 只点「写报告」会得到"飞机 0 Remote 0"的假象: 两个表都只有 scan() 会填 (实测过: 人在飞, 报告却是 0 架 0 个 Remote)
		local L = { `==== PLANE {os.date("%Y-%m-%d ")}{clock(true)} place={game.PlaceId} me={me.Name} team={(me.Team and me.Team.Name or "-")} ====`, `-- 飞机 {#planes} · 重扫于 {(scanAt or "从未")}` }
		for _, p in ipairs(planes) do
			L[#L + 1] = `[{p.score}] {p.path}{(p.mine and " ★我" .. (p.ownBy and "(" .. p.ownBy .. ")" or "") or "")} | 座:{((if p.seat then "有" else "无"))} 翼:{p.wings} 件:{p.parts} | 队:{p.team}({p.src}){(p.occ and " 乘员:" .. p.occ.Name or "")}`
			for k, v in pairs(p.model:GetAttributes()) do L[#L + 1] = `    attr {k}={fmt(v)}`end
			for _, r in ipairs(p.remotes) do L[#L + 1] = `    {r.ClassName} {r:GetFullName()}`end
		end
		if #rejects > 0 then
			L[#L + 1] = `-- 疑似 {#rejects} (扫到但没过门槛; 靠「座」=有座位, 靠「翼」=只认到机翼名)`
			for _, p in ipairs(rejects) do L[#L + 1] = `[{p.score}] {p.path} | 靠{p.why} 座:{((if p.seat then "有" else "无"))} 翼:{p.wings} 件:{p.parts}`end
		end
		L[#L + 1] = `-- Remote {#remotes}`
		for _, r in ipairs(remotes) do L[#L + 1] = `  {r.ClassName} {r:GetFullName()}`end
		L[#L + 1] = `-- 发 {tot(sent)} 条 / {#sent} 组 (上限 {CAP} 组; 连续同 Remote 同目标折叠成一组, 首末 payload 都留着)`
		for _, s in ipairs(dump(sent)) do L[#L + 1] = s end
		L[#L + 1] = `-- 收 {tot(got)} 条 / {#got} 组{(F.watch and #watch == 0 and " ← 收侦听开着却一个都没挂上 (要先点 重扫)" or "")}`
		for _, s in ipairs(dump(got)) do L[#L + 1] = s end
		local txt = table.concat(L, "\n")
		writefile("plane_debug.txt", txt)
		setclipboard(txt)
		toast(`报告 {#L} 行 → plane_debug.txt / 剪贴板`)
	end

	feature{ kind = "page", id = "plane", tab = "机", info = function() return "飞机=" .. #planes .. " Remote=" .. #remotes .. " 发=" .. tot(sent) .. "/" .. #sent .. "组 收=" .. tot(got) .. "/" .. #got .. "组 侦听=" .. tostring(F.spy) .. (F.watch and #watch == 0 and " 收没挂上(先重扫)" or "") end }
	feature{ kind = "btn", label = "重扫", fn = scan }
	feature{ kind = "btn", label = "写报告", fn = report }
	feature{ key = "spy", label = "发侦听", set = setSpy }
	feature{ key = "watch", label = "收侦听", set = setWatch, off = function() setWatch(false) end }
	feature{ key = "hl", label = "高亮", set = highlight, off = function() F.hl = false; highlight() end }
	feature{ key = "autoscan", label = "自动 5s", loop = function() scan(); report() end, every = 5 }
	feature{ key = "pall", save = "pall", label = "全录" }
	feature{ kind = "btn", label = "清空记录", fn = function() table.clear(sent); table.clear(got) end }
	feature{ kind = "text", key = "plane_status", label = "上机 → 发侦听 → 开几枪 → 写报告" }
	feature{ kind = "tick", off = function() if oldNC then hookmetamethod(game, "__namecall", oldNC) end end } -- 只在卸载时: 发侦听装的钩子还原 (关开关只停记录, 钩子留着照常放行)
end

do -- ═════════ 抓: 抓部件 + 抓界面 (物件名一个都不认) ═════════
	-- 真机 26.10.16.6.96 那份日志 (place=133363783004873 地图=Ugc) 给的事实:
	--   · 能卖的东西是未锚定部件, 身上带 SellReadyAt + SellToken 两个属性 (JellyFish / Revolver / Gem …);
	--     地图上的 Metal / Body / Black 这类装饰件同样未锚定, 但一个属性都没有。
	--     ⟹ 分得开的那条线是「有没有属性」, 不是名字。
	--   · 半径 40 内 84 个, 扫描半径 300 内 936 个 —— 东西不缺, 缺的是挑。
	--   · 界面 3693 个物件, 上一版 16KB 护栏砍掉 3375 个, 报出来的 318 个几乎全是 Label, 按钮反而没露头。
	-- 所以这版: 抓取分三档 (散 / 属 / 全), 锚定的改成直接搬 CFrame; 界面单独一段, 只列可点的, 且能按名字点。
	-- dead = 「速度写进去了但读回来没吃」的件数; pp/btns 为 nil 表示还没清过点 (0 和 没数过 不能混成一个 0)
	local st = { n = 0, pulled = 0, moved = 0, dead = 0, clicked = 0, btns = nil, pp = nil }
	local ppAcc = 0 -- 自动触发的节流: 半秒一轮, 每帧遍历 workspace 一遍不值当

	local function attrCnt(o) -- 属性个数: 「属」这一档就靠它挑, 这游戏的可卖件全带 SellReadyAt/SellToken
		local ok, a = pcall(function() return o:GetAttributes() end)
		if not ok or type(a) ~= "table" then return 0 end
		local n = 0
		for _ in pairs(a) do n += 1 end
		return n
	end
	local function attrTxt(o) -- 属性常常是 Owner / ItemId / SellToken 这类关键信息, 一个不漏地带上
		local ok, a = pcall(function() return o:GetAttributes() end)
		if not ok or type(a) ~= "table" then return "" end
		local t = {}
		for k, v in pairs(a) do t[#t + 1] = `{k}={tostring(v)}` end
		table.sort(t) -- pairs 顺序不保证, 排一下日志才可复现
		return #t > 0 and (" 属:" .. table.concat(t, ",")) or ""
	end
	local function chars() local o = {}; for _, pl in ipairs(Players:GetPlayers()) do local c = pl.Character; if c then o[#o + 1] = c end end; return o end
	local function someones(p, cs) -- 别人身上的零件也是没锚定的部件, 不排掉就会把玩家拽过来
		for _, c in ipairs(cs) do if p:IsDescendantOf(c) then return true end end
		return false
	end
	local function inRadius(radius)
		local r = root()
		if not r then return {}, nil end
		local ok, hit = pcall(function() return workspace:GetPartBoundsInRadius(r.Position, radius) end)
		if not ok or type(hit) ~= "table" then return {}, r end
		local cs, o = chars(), {}
		for _, p in ipairs(hit) do
			pcall(function()
				if p:IsA("BasePart") then o[#o + 1] = { p = p, mine = mine(p), who = someones(p, cs), na = attrCnt(p) } end
			end)
		end
		return o, r
	end
	-- 三档范围。「人物身上的」哪一档都不抓 —— 那是把玩家拽过来, 不是抓东西。
	local RANGE = {
		loose = function(x) return not x.p.Anchored end, -- 散: 没锚定的 (默认; 这游戏的可卖件都在这一档里)
		attr = function(x) return x.na > 0 end,          -- 属: 带属性的 (可卖件带 SellToken, 地图装饰件一个属性都没有)
		all = function() return true end,                -- 全: 连锚定的一起搬 (会把地图件也拖过来, 自己掂量)
	}
	local function targets(radius)
		local all, r = inRadius(radius)
		local keep = RANGE[F.grange] or RANGE.loose -- cycle 存的是 F 不是 S (读错表就永远停在第一档)
		local o = {}
		for _, x in ipairs(all) do if not x.mine and not x.who and keep(x) then o[#o + 1] = x.p end end
		return o, r
	end
	-- 「速度写进去有没有被吃」这件事只能在机器上问出来, 所以写完当场读回来对一遍。
	-- 26.10.16.7.97 真机 641 条: 散件档每帧写 65 个; 半径 400 那 49 条里 272 个件每帧都在写,
	-- 却没有一个进过 1 格以内 (写入/在半径内 = 1.00) —— 客户端写的速度一个都没生效的味儿很足
	-- (所有权在服务端 / 装配体根是锚定的)。所以推法留三档: 自动 = 先写速度, 读回来发现没吃就改搬
	-- CFrame; 只写速度 / 只搬位 是把这两条路分开验的开关, 别再靠猜。
	local function nudge(p, d, dt) -- 直接搬 CFrame: 锚定不锚定、谁握着所有权, 客户端这一侧都认
		local step = math.min(S.gspeed * math.max(dt or 1 / 60, 1 / 240), d.Magnitude - 0.5)
		p.CFrame = p.CFrame + d.Unit * step
		st.moved += 1
	end
	local function pull(dt)
		local list, r = targets(S.gradius)
		st.n = #list
		if not r then return end
		local mode = F.gmode or "auto"
		for _, p in ipairs(list) do
			pcall(function()
				local d = Vector3.new(r.Position.X - p.Position.X, 0, r.Position.Z - p.Position.Z)
				if d.Magnitude < 1 then return end -- 已经到手边, 再推就从人身上穿过去了
				if mode ~= "frame" and not p.Anchored then
					-- 只写水平速度, Y 留给引擎: 三个分量全写死会把地上的东西顶上天
					local v = p.AssemblyLinearVelocity
					local want = Vector3.new(d.Unit.X * S.gspeed, v.Y, d.Unit.Z * S.gspeed)
					p.AssemblyLinearVelocity = want
					st.pulled += 1
					if mode == "auto" then
						local got = p.AssemblyLinearVelocity
						-- 读回来的水平分量对不上 = 这个件不认客户端写的速度, 改搬位置
						if (Vector3.new(got.X, 0, got.Z) - Vector3.new(want.X, 0, want.Z)).Magnitude > S.gspeed * 0.5 then
							st.dead += 1
							nudge(p, d, dt)
						end
					end
				else
					nudge(p, d, dt)
				end
			end)
		end
	end

	-- ── 界面: 3693 个物件里绝大多数是 Label, 真正点得着的是 GuiButton ──
	local function ownGui(g) local p = g; while p do if p == gui or p == FX then return true end; p = p.Parent end; return false end
	local function btnText(b) -- ImageButton 自己没有文字, 名字常常是无意义的图, 得去子物件里找一行字
		local ok, t = pcall(function()
			if b:IsA("TextButton") and type(b.Text) == "string" and b.Text ~= "" then return b.Text end
			for _, c in ipairs(b:GetDescendants()) do
				if c:IsA("TextLabel") and type(c.Text) == "string" and c.Text ~= "" then return c.Text end
			end
		end)
		return (ok and t) or ""
	end
	local function guiBtns() -- 全部可点按钮: 不筛可见、不筛尺寸、不设名额 (上一版按可见性筛, 隐着的按钮整个漏掉)
		local o, trees = {}, {}
		local pg = me:FindFirstChildOfClass("PlayerGui")
		if pg then trees[#trees + 1] = pg end
		if ROOT and ROOT ~= pg then trees[#trees + 1] = ROOT end
		for _, tree in ipairs(trees) do
			local okD, list = pcall(function() return tree:GetDescendants() end)
			if okD and type(list) == "table" then
				for _, g in ipairs(list) do
					pcall(function()
						if not g:IsA("GuiButton") or ownGui(g) then return end
						local sz, ap = g.AbsoluteSize, g.AbsolutePosition
						o[#o + 1] = { g = g, s = string.format("%s:%s@%s,%s %sx%s %s%s 「%s」",
							g:GetFullName(), g.ClassName,
							(ap and tostring(math.floor(ap.X))) or "?", (ap and tostring(math.floor(ap.Y))) or "?",
							(sz and tostring(math.floor(sz.X))) or "?", (sz and tostring(math.floor(sz.Y))) or "?",
							g.Visible ~= false and "V" or "v", g.Active == true and "A" or "-", btnText(g)) }
					end)
				end
			end
		end
		table.sort(o, function(a, b) return a.s < b.s end) -- 按全路径排: 同一个菜单的按钮挨在一起, 好扫
		st.btns = #o
		return o
	end
	local function clickAt(b) -- 客户端点不了别人的 Activated, 只能让执行器发一次真鼠标事件
		local sz, ap = b.AbsoluteSize, b.AbsolutePosition
		if not sz or not ap then return false end
		local cx, cy = ap.X + sz.X / 2, ap.Y + sz.Y / 2
		local ok = pcall(function()
			VIM:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
			VIM:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
		end)
		return ok
	end
	local function clickMatched()
		local k = tostring(S.gkey or "")
		if k == "" then toast("先在「按钮名」里填一段字, 空着不点"); return end
		local hit = 0
		for _, x in ipairs(guiBtns()) do
			pcall(function()
				local nm, tx = x.g.Name, btnText(x.g)
				if nm:lower():find(k:lower(), 1, true) or tx:lower():find(k:lower(), 1, true) then
					if clickAt(x.g) then hit += 1 end
				end
			end)
		end
		st.clicked = hit
		toast(`按钮名「{k}」: 点了 {hit} 个`)
	end

	-- ── 收纳槽: 抓到手边只是第一步, 还得替主人按下去 ──
	-- 26.10.16.7.97 真机清单: 全场只有 4 个 ProximityPrompt (Workspace.1.Prompt / MailPart /
	-- Portal.EventInteract / VIPModel.Handle.Prompt), 「秒互动」已经把长按时长改 0、距离拉到 1000,
	-- 剩下的就是发一次触发。键不猜 E —— 问提示自己要 KeyboardKeyCode, 跟不猜物件名一个道理。
	local function firePrompt(pp)
		if type(fireproximityprompt) == "function" then -- 执行器直发 (Delta 有): 不挑键、不挑距离、不挑朝向
			if pcall(fireproximityprompt, pp) then return true end
		end
		return pcall(function() -- 退回发一次真键盘 (按下 + 抬起, 只按不抬下一次就不认了)
			local k = pp.KeyboardKeyCode
			VIM:SendKeyEvent(true, k, false, game)
			VIM:SendKeyEvent(false, k, false, game)
		end)
	end
	local ppList, ppListT = nil, -1e9
	local function promptsNear(force)
		-- 缓存 1 秒: 自动档半秒一轮, 每轮都全树遍历一次, 真机大地图几万个物件是能感知的卡顿。
		-- 代价是新冒出来的提示最多晚 1 秒才被看见; 手动按「触发提示」传 force 拿当场的新清单。
		if not force and ppList and os.clock() - ppListT < 1 then return ppList end
		local r = root()
		local o = {}
		local okD, list = pcall(function() return workspace:GetDescendants() end)
		if not okD or type(list) ~= "table" then ppList, ppListT = o, os.clock() return o end
		for _, d in ipairs(list) do
			pcall(function()
				if not d:IsA("ProximityPrompt") or not d.Enabled then return end
				local par = d.Parent
				if not par or not par:IsA("BasePart") then return end
				if r and (par.Position - r.Position).Magnitude > S.promptdist then return end
				o[#o + 1] = d
			end)
		end
		ppList, ppListT = o, os.clock()
		return o
	end
	local function firePrompts(quiet, force)
		local o, sent = promptsNear(force), 0
		for _, pp in ipairs(o) do if firePrompt(pp) then sent += 1 end end
		st.pp = #o
		if not quiet then toast(`提示: 范围内 {#o} 个, 发出去 {sent} 个`) end
	end

	local function grabLines() -- 现场清单: 不筛、不猜、不设名额, 按距离从近到远排, 截断只砍最远的
		local r = root()
		local L = { `==== GRAB {os.date("%Y-%m-%d ")}{clock(true)} place={game.PlaceId} 地图={tostring(game.Name)} ====` }
		if not r then L[#L + 1] = "没有角色 (进游戏再点诊断打包)"; return L end
		L[#L + 1] = string.format("角色位置=(%.0f,%.0f,%.0f) 范围=%s 抓取半径=%s 拉力=%s 扫描半径=%s 按钮名=%s",
			r.Position.X, r.Position.Y, r.Position.Z, tostring(F.grange), tostring(S.gradius), tostring(S.gspeed), tostring(S.gscan), tostring(S.gkey))
		local all = inRadius(S.gscan)
		local nA, nL, nAt = 0, 0, 0
		local rows = {}
		for _, x in ipairs(all) do
			nA += 1
			if not x.mine and not x.who then
				if not x.p.Anchored then nL += 1 end
				if x.na > 0 then nAt += 1 end
			end
			pcall(function()
				local p = x.p
				rows[#rows + 1] = { d = (p.Position - r.Position).Magnitude, s = string.format("%s/%s 锚%s (%.0f,%.0f,%.0f) 尺寸(%.0f,%.0f,%.0f) 速%.1f%s%s",
					p.Name, p.ClassName, p.Anchored and "A" or "a", p.Position.X, p.Position.Y, p.Position.Z,
					p.Size.X, p.Size.Y, p.Size.Z, p.AssemblyLinearVelocity.Magnitude,
					(if x.mine then " 我" elseif x.who then " 人" else ""), attrTxt(p)) }
			end)
		end
		table.sort(rows, function(a, b) return a.d < b.d end) -- 近的排前面: 32KB 砍掉的是最远的地图件, 手边一个不丢
		L[#L + 1] = `-- 扫描半径内部件 {nA} 个, 其中 未锚定非人物 {nL} 个 / 带属性非人物 {nAt} 个 (近 → 远, 全列)`
		local used, cut = 0, 0
		for i, x in ipairs(rows) do
			local line = string.format("  %6.1f %s", x.d, x.s)
			if used + #line > 32768 then cut = #rows - i + 1 break end
			L[#L + 1] = line
			used += #line
		end
		if cut > 0 then L[#L + 1] = `  …还有 {cut} 个没列(超32KB)` end
		-- 收纳槽要么是 ProximityPrompt, 要么是某个名字的触发块; Remote 是「推进去怎么算数」的另一条路。两样都全列。
		local pr = {}
		local okD, list = pcall(function() return workspace:GetDescendants() end)
		local nAll = 0
		if okD and type(list) == "table" then
			for _, d in ipairs(list) do
				pcall(function()
					nAll += 1
					if d:IsA("ProximityPrompt") then
						local par = d.Parent
						pr[#pr + 1] = string.format("  提示 %s 长按=%.1f 距离=%.0f 视线=%s 开=%s 离角色=%.0f", (par and par:GetFullName()) or "?",
							d.HoldDuration, d.MaxActivationDistance, tostring(d.RequiresLineOfSight), tostring(d.Enabled),
							(par and par:IsA("BasePart")) and (par.Position - r.Position).Magnitude or -1)
					end
				end)
			end
		end
		table.sort(pr)
		L[#L + 1] = `-- workspace 共 {nAll} 个物件, 其中 ProximityPrompt {#pr} 个 (全列)`
		for _, x in ipairs(pr) do L[#L + 1] = x end
		local rem = {}
		for _, tree in ipairs({ RS, workspace }) do
			local okR, rl = pcall(function() return tree:GetDescendants() end)
			if okR and type(rl) == "table" then
				for _, d in ipairs(rl) do pcall(function() if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then rem[#rem + 1] = `  {d.ClassName} {d:GetFullName()}` end end) end
			end
		end
		table.sort(rem)
		L[#L + 1] = `-- Remote {#rem} 个 (全列)`
		for _, x in ipairs(rem) do L[#L + 1] = x end
		-- 界面: 整棵树几万个物件, 全列会把上面三段全冲掉, 所以这一段只收可点的 ——
		-- 但「可点」不是筛选出来的猜测, 是 GuiButton 这个类; 隐着的、Active=false 的一个不落。
		local gb = guiBtns()
		L[#L + 1] = `-- 界面可点按钮 {#gb} 个 (全列, 按全路径排; 「」里是它自己或子物件上的文字)`
		local u2, cut2 = 0, 0
		for i, x in ipairs(gb) do
			local line = "  " .. x.s
			if u2 + #line > 32768 then cut2 = #gb - i + 1 break end
			L[#L + 1] = line
			u2 += #line
		end
		if cut2 > 0 then L[#L + 1] = `  …还有 {cut2} 个没列(超32KB)` end
		return L
	end
	feature{ kind = "page", id = "grab", tab = "抓", info = function()
		-- info 里只数不推: 关着也报半径内有几个, 才知道是半径小了还是这游戏根本没散件; 推的动作只在开关/按住时发生
		local list = targets(S.gradius)
		st.n = #list
		-- 「没吃」是这次真机最缺的那个数: 速度写进去但读回来对不上, 说明这个件不认客户端写的速度。
		-- 界面按钮/提示 没清点过就写「未清点」, 不写 0 —— 0 和 没数过 混成一个 0 会当成「这游戏没按钮」。
		return string.format("按住=%s 自动=%s 范围=%s 推法=%s 半径内=%d 速度写=%d 没吃=%d 搬位=%d 累计=%d 提示=%s 界面按钮=%s",
			tostring(F.pull == true), tostring(F.autopull), tostring(F.grange), tostring(F.gmode or "auto"), st.n,
			st.pulled, st.dead, st.moved, st.pulled + st.moved,
			tostring(st.pp or "未清点"), tostring(st.btns or "未清点"))
	end }
	feature{ kind = "hold", key = "pull", label = "抓取", h = 36 } -- 页签已经叫「抓」, 同名会让 findBtn 抓错按钮
	feature{ key = "autopull", label = "自动抓" }
	feature{ kind = "cycle", key = "grange", save = "grange", def = "loose", cycle = { "loose", "attr", "all" },
		text = { loose = "范围 散件", attr = "范围 带属性", all = "范围 全部" }, lit = true }
	feature{ kind = "cycle", key = "gmode", save = "gmode", def = "auto", cycle = { "auto", "vel", "frame" },
		text = { auto = "推法 自动", vel = "推法 只写速度", frame = "推法 只搬位" }, lit = true }
	feature{ kind = "num", key = "gradius", def = 40, label = "半径" } -- 原写「抓取半径」: 4 汉字≈48px, 半行标签槽只有 46px, 末字被切
	feature{ kind = "num", key = "gspeed", def = 60, label = "拉力" }
	feature{ kind = "num", key = "gscan", def = 300, label = "扫描半径", w = 1 }
	feature{ kind = "str", key = "gkey", def = "", label = "按钮名" }
	feature{ kind = "btn", label = "点按钮", fn = clickMatched, w = 1 }
	feature{ kind = "btn", label = "触发提示", fn = function() firePrompts(false, true) end, w = 1 }
	feature{ key = "autoprompt", label = "自动触发" } -- 默认关: 半秒发一次全场提示, 主人没要求就别自己按
	feature{ kind = "tick", tick = function(dt)
		if F.pull or F.autopull then pull(dt) end
		if F.autoprompt then
			ppAcc += dt or 1 / 60
			if ppAcc >= 0.5 then ppAcc = 0; firePrompts(true) end -- 自动的不出提示音, 不然半秒一条把日志冲掉
		end
	end }
	feature{ kind = "dump", key = "grab", dump = grabLines }
	feature{ kind = "text", key = "grab_status", label = "散=未锚定 属=带属性 全=连锚定搬" }
end

do -- ═════════ 弹: 子弹追踪 (自己刚打出去的弹丸, 每帧朝目标拐一点; 参数全在页里) ═════════
	-- 认弹丸不认名字: 各家游戏的弹丸叫 Bullet / Projectile / 随机 GUID / 空名字都有, 认名字等于绑定某一张图。
	-- 能认的只有三件事 —— 这几帧刚出现在 workspace 里、没锚定、速度够快; 再加一条离自己不远 (弹是从自己枪口出来的)。
	-- 人物身上的零件一律不算 (那是人, 不是弹)。
	-- 拐弯只改方向、不改大小: 弹丸的命中判定多半看速度或者靠 Touched, 速度一改小就落地或者根本不触发。
	local cand, live = {}, {} -- 这一帧新出现的零件 / 正在追的 { p = 零件, lv = LinearVelocity 约束, born = 认下来的时刻 }
	local stat = { seen = 0, lock = 0, noTgt = 0 } -- 诊断: 认下来几颗 / 拐了几次 / 有弹没目标几帧
	local lastTgt, statT = nil, 0
	local function rot(v, axis, rad) -- 罗德里格斯: v 绕 axis 转 rad 弧度。只做向量运算, 不建 CFrame —— 每帧每颗弹一次, 少一份垃圾
		local c, s = math.cos(rad), math.sin(rad)
		return v * c + axis:Cross(v) * s + axis * (axis:Dot(v) * (1 - c))
	end
	local function charPart(p) -- 挂在人物 (玩家或 NPC) 身上的零件不是弹
		local m = p:FindFirstAncestorOfClass("Model")
		return m ~= nil and m:FindFirstChildOfClass("Humanoid") ~= nil
	end
	local function spawn(d) -- 只排进候选, 重活留到每帧去做: 地图流式加载会一口气灌进来几千个零件
		if not F.bhome or not d:IsA("BasePart") then return end
		if #cand >= 256 then table.clear(cand) end -- 一帧里灌进太多时整批丢掉重来: 弹丸总是刚生成的, 老的候选本来也来不及认
		cand[#cand + 1] = d
	end
	local function targets() -- 每帧一次 (不是每颗弹一次): 活着的敌对目标
		local o, myTeam = {}, me.Team
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl ~= me and not (F.bteam and myTeam ~= nil and pl.Team == myTeam) then
				local c = pl.Character
				local h = c and c:FindFirstChildOfClass("Humanoid")
				local core = c and c:FindFirstChild("HumanoidRootPart")
				if h and core and h.Health > 0 then
					local part = core
					if F.bpart == "head" then part = c:FindFirstChild("Head") or core end -- 没有 Head 就退回根件, 别整个目标丢掉
					o[#o + 1] = { pos = part.Position, vel = part.AssemblyLinearVelocity, name = pl.DisplayName or pl.Name }
				end
			end
		end
		return o
	end
	local function aimTick(dt) -- 每帧: 候选转正 → 逐颗拐向目标
		local now, r, step = os.clock(), root(), math.max(dt or 0, 0)
		-- 1) 候选转正。只判这一帧新出现的零件, 判完就清空: 地上那些不动的散件不该每帧重判一遍
		if r then
			local max = math.max(1, math.floor(nn(S.bmax) + 0.5)) -- nn: _G.SB 里手抄成字符串也别让整页每帧抛错
			local o = {}
			for _, p in ipairs(cand) do
				if #o >= max - #live then break end
				local ok = pcall(function()
					if not p.Parent or p.Anchored then return end
					if (p.Position - r.Position).Magnitude > S.bradius then return end -- 别人的弹 / 远处的零件: 半径按「自己枪口能打到哪」给
					if p.AssemblyLinearVelocity.Magnitude < S.bspdmin then return end -- 站着不动的零件不是弹
					if mine(p) or charPart(p) then return end
					o[#o + 1] = { p = p, lv = p:FindFirstChildOfClass("LinearVelocity"), born = now }
				end)
			end
			for _, e in ipairs(o) do live[#live + 1] = e; stat.seen += 1 end
		end
		table.clear(cand)
		-- 2) 逐颗拐弯。任何一颗出问题 (零件被删、属性读到 nil) 只丢它自己, 不连累别的
		local tg = nil
		for i = #live, 1, -1 do
			local e = live[i]
			local keep = false
			local ok = pcall(function()
				local p = e.p
				if not p.Parent or p.Anchored or now - e.born > S.blife then return end -- 到时间没打中就当它飞丢了, 别一直追着算
				local v = p.AssemblyLinearVelocity
				local sp = v.Magnitude
				if sp < 1 then return end
				if not tg then tg = targets() end
				local dir, best, bestAng = v.Unit, nil, nil
				for _, t in ipairs(tg) do
					local d = t.pos - p.Position
					local dist = d.Magnitude
					if dist > 0.5 and dist <= S.brange then -- 超出射程的不算目标
						local ang = math.deg(math.acos(math.clamp(dir:Dot(d.Unit), -1, 1)))
						if ang <= S.bfov and (bestAng == nil or ang < bestAng) then best, bestAng = t, ang end -- 同一颗弹只咬最正对的那个
					end
				end
				if not best then stat.noTgt += 1; keep = true; return end -- 没目标不算失败: 弹还在飞, 下一帧说不定就进射角了
				local fly = (best.pos - p.Position).Magnitude / sp -- 飞过去还要多久
				local want = best.pos + best.vel * (fly * S.blead) - p.Position -- 提前量: 按飞行时间推到目标届时的位置
				if want.Magnitude < 0.5 then keep = true; return end
				local wdir = want.Unit
				local maxRad = math.rad(S.bturn) * step -- 每帧最多拐这么多: 这就是「转向速度」, 调大 = 拐得急
				local ang = math.acos(math.clamp(dir:Dot(wdir), -1, 1))
				local ndir = wdir
				if ang > maxRad then
					local axis = dir:Cross(wdir)
					ndir = axis.Magnitude < 1e-4 and wdir or rot(dir, axis.Unit, maxRad) -- 正对着或者正背着时叉积为零, 直接给目标方向
				end
				if e.lv then -- 用 LinearVelocity 驱动的弹: 游戏每帧按约束重算速度, 只写零件速度会被立刻盖回去, 得改约束本身
					pcall(function()
						if e.lv.RelativeTo == Enum.ActuatorRelativeTo.World and e.lv.Parent then e.lv.VectorVelocity = ndir * e.lv.VectorVelocity.Magnitude end
					end)
				end
				p.AssemblyLinearVelocity = ndir * sp -- 方向换成新的, 大小原样保留
				stat.lock += 1
				lastTgt = best.name
				keep = true
			end)
			if not ok or not keep then table.remove(live, i) end
		end
		statT += step -- 页上那行状态: 四分之一秒刷一次就够, 每帧写字反而看不清
		if statT >= 0.25 then statT = 0; say("aim_status", `追 {#live} · 目标 {tostring(lastTgt)} · 认 {stat.seen} · 无目标 {stat.noTgt} · 偏转 {stat.lock}`) end
	end
	local function aimOff() table.clear(cand); table.clear(live); lastTgt, statT = nil, 0 end
	local function aimLines()
		local L = { `==== AIM ==== 追={#live} 认={stat.seen} 偏转={stat.lock} 无目标={stat.noTgt} 目标={tostring(lastTgt)}` }
		if #live == 0 then L[#L + 1] = "  没有在追的弹丸: 开着「追踪」打一发再看 (射线类武器没有实体弹丸, 这页认不到)" end
		for _, e in ipairs(live) do
			local p = e.p
			L[#L + 1] = string.format("  %s 速=%.0f 龄=%.1fs%s", p:GetFullName(), nn(p.AssemblyLinearVelocity.Magnitude), os.clock() - e.born, e.lv and " (LinearVelocity)" or "")
		end
		return L
	end
	feature{ kind = "page", id = "aim", tab = "弹", info = function() -- info 只读不写: 打包诊断时不能顺手拐一下弹
		return `追={#live} 目标={tostring(lastTgt)} 认={stat.seen} 偏转={stat.lock} 无目标={stat.noTgt} 转向={S.bturn}°/s 视角={S.bfov}°`
	end }
	-- 每帧连接挂在开关本身上 (和漂移那条一样): 关着就一帧都不跑, 不用在 tick 里自己判一遍
	feature{ key = "bhome", save = "bhome", label = "追踪", w = 1, init = function() on(workspace.DescendantAdded, spawn) end, tick = aimTick, off = aimOff }
	feature{ key = "bteam", save = "bteam", def = true, label = "忽略队友" }
	feature{ kind = "cycle", key = "bpart", save = "bpart", def = "core", cycle = { "core", "head" },
		text = { core = "瞄 身体", head = "瞄 头" }, lit = true }
	feature{ kind = "num", key = "bturn", def = 90, label = "转向°/s" } -- 每帧最多拐多少: 60 以下像导弹, 180 以上基本是贴脸拐
	feature{ kind = "num", key = "bfov", def = 60, label = "视角°" }     -- 目标要在弹丸前进方向的这个锥体内才算
	feature{ kind = "num", key = "brange", def = 500, label = "目标距" }
	feature{ kind = "num", key = "bmax", def = 3, label = "个数" }       -- 同时追几颗, 多了会互相抢目标
	feature{ kind = "num", key = "blife", def = 2, label = "秒" }        -- 一颗弹最多追多久, 追不上就放掉
	feature{ kind = "num", key = "bspdmin", def = 10, label = "最低速" } -- 低于这个速度的不认成弹 (地上的散件)
	feature{ kind = "num", key = "bradius", def = 300, label = "弹半径" } -- 只认离自己这么近的弹, 免得替别人拐
	feature{ kind = "num", key = "blead", def = 0.5, label = "提前量" }   -- 0 = 打目标当前位置, 1 = 全按飞行时间预判
	feature{ kind = "text", key = "aim_status", label = "开着「追踪」打一发再看这行; 射线武器没有实弹, 认不到弹丸" }
	feature{ kind = "dump", key = "aim", dump = aimLines }
end

-- ───────── 启动: 按清单建页 / 控件 / 每帧连接; 一个功能装不上不拖累别的 (记下来, 页里写一行) ─────────
local only = opt("only", nil) -- _G.SB.only = {"moc","sibs"} 只装一部分
local function wanted(id) return type(only) ~= "table" or table.find(only, id) ~= nil end
for _, e in ipairs(FEATURES) do if e.kind == "page" and wanted(e.id) then ACTIVE[#ACTIVE + 1] = e end end
local pages, tabBtns, BUILT, FAILED = {}, {}, {}, {}
local activePage
local function pageHeight(pg)
	local h = 0
	for _, child in ipairs(pg:GetChildren()) do
		if child.ClassName ~= "UIListLayout" then
			local y = child.Size and child.Size.Y
			local n = y and y.Offset or 0
			if child.AutomaticSize == Enum.AutomaticSize.Y then n = math.max(n, child.AbsoluteSize.Y) end
			h += n
		end
	end
	return h
end
fitActivePage = function()
	local pg = pages[activePage]
	local v = cam0 and cam0.ViewportSize or vp
	if not pg or v.Y <= 0 then return end
	local maxY = math.max(v.Y - ROW * 2 - pageHeight(pg) - 8, 0) -- 标题+页签+当前页+8px 底边距
	local p = title.Position
	local y = math.clamp(p.Y.Offset, 0, maxY)
	if y ~= p.Y.Offset then title.Position = UDim2.fromOffset(p.X.Offset, y); save("pos", { p.X.Offset, y }) end
end
local function show(name)
	for n, pg in pairs(pages) do pg.Visible = n == name; lit(tabBtns[n], n == name) end
	activePage = name
	fitActivePage()
	save("tab", name)
end
do
	local page, pid, cur, used, curH
	for _, e in ipairs(FEATURES) do
		local k = e.kind or "toggle"
		if k == "page" then
			page, pid, cur = nil, e.id, nil
			if wanted(e.id) then
				page = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = false, LayoutOrder = ord() }, body)
				mk("UIListLayout", { Padding = UDim.new(0, 0) }, page)
				pages[e.id] = page
				tabBtns[e.id] = btn(tabs, e.tab, function() show(e.id) end, 1 / #ACTIVE)
			end
		elseif page then
			local parent, w, controlW = page, e.w or ((if k == "text" then 1 else 0.5))
			if NOUI[k] then w = 1
			elseif w < 1 then -- 半行控件两两并一行; 行高变了或装不下就另起一行
				local h = e.h or ROW
				if not cur or used + w > 1.001 or curH ~= h then cur, used, curH = row(page, e.h), 0, h end
				used, parent, controlW = used + w, cur, w
			elseif e.h then
				cur, used, curH = row(page, e.h), 0, nil -- 全宽控件也按声明高度填满单独一行; 后续半行另起行
				parent, controlW = cur, 1
			else cur = nil end
			local ok, err = pcall(function()
				KIND[k](e, parent, controlW)
				if e.init then e.init(page) end
			end)
			if ok then
				e._page = pid
				BUILT[#BUILT + 1] = e
				if e.dump then DUMP[e.key] = e.dump end
				if e.tick then on(e.sig == "render" and RunService.PreRender or RunService.PreSimulation, function(dt) if not e.key or F[e.key] then e.tick(dt) end end) end
				if e.loop then task.spawn(function() -- 慢循环: 每 every 秒一轮, 开关开着才跑; 每一轮 pcall (task.spawn 里的错不会自己恢复, 一次出错不能让它永久死掉)
					while alive do
						task.wait(type(e.every) == "function" and e.every() or e.every or 1)
						if alive and (not e.key or F[e.key]) then
							local ok2, err2 = pcall(e.loop)
							if not ok2 then if e.onerr then e.onerr(err2) else warn(`[Selfblox] {(e.label or e.key)}: {tostring(err2)}`) end end
						end
					end
				end) end
			else
				local what = e.label or e.key or k
				FAILED[#FAILED + 1] = `{pid} {what}: {tostring(err)}`
				warn(`[Selfblox] {FAILED[#FAILED]}`)
				text(page, `✗ {what}`)
			end
		end
	end
end
if #ACTIVE > 0 then show(pages[opt("tab", "moc")] and opt("tab", "moc") or ACTIVE[1].id) end

pageInfos = function() -- 各页状态, 一页一行 (给日志 / 诊断快照用): 清单行按 开关=值 生成, 页自己的 info() 追加详细状态
	local o = {}
	for _, p in ipairs(ACTIVE) do
		local ok, v = pcall(function()
			local t = {}
			for _, e in ipairs(BUILT) do
				if e._page == p.id then
					local k = e.kind or "toggle"
					if k == "toggle" then t[#t + 1] = `{e.label}={tostring(F[e.key])}`
					elseif k == "num" then t[#t + 1] = `{e.key}={tostring(S[e.key])}`
					elseif k == "cycle" then t[#t + 1] = `{e.key}={tostring(F[e.key])}`end
				end
			end
			if p.info then t[#t + 1] = p.info() end
			return table.concat(t, " ")
		end)
		o[#o + 1] = `{p.id} {(ok and tostring(v) or ("INFO 报错: " .. tostring(v)))}`
	end
	return o
end

local function dumpLines()
	local L = { "==== Selfblox 诊断 " .. os.date("%Y-%m-%d ") .. clock(true) .. " ====",
		`脚本={VERSION} 页签={tostring(saved.tab)} place={game.PlaceId} 地图={tostring(game.Name)}`,
		`配置 {Http:JSONEncode(saved)}`,
		`执行器 isfile={tostring(isfile ~= nil)} writefile={tostring(writefile ~= nil)} appendfile={tostring(appendfile ~= nil)} setclipboard={tostring(setclipboard ~= nil)} gethui={tostring(gethui ~= nil)} hookmetamethod={tostring(hookmetamethod ~= nil)} newcclosure={tostring(newcclosure ~= nil)} getnamecallmethod={tostring(getnamecallmethod ~= nil)}`,
		"角色 " .. tostring(me.Name) .. " 队=" .. tostring(me.Team and me.Team.Name) .. " 坐=" .. tostring(hum() and hum().SeatPart and (hum().SeatPart:GetFullName())) .. " 根=" .. tostring(root() and root().Anchored) }
	local r = root()
	if r then L[#L + 1] = string.format("角色 位置=(%.0f,%.0f,%.0f) 速度=%.0f 血=%s", r.Position.X, r.Position.Y, r.Position.Z, r.AssemblyLinearVelocity.Magnitude, tostring(hum() and hum().Health)) end
	L[#L + 1] = "-- 模块状态"
	for _, line in ipairs(pageInfos()) do L[#L + 1] = `  {line}`end
	for _, f in ipairs(FAILED) do L[#L + 1] = `  ✗ {f}`end
	for k, f in pairs(DUMP) do local o, lines = pcall(f); L[#L + 1] = `-- {k} dump`; if o then for _, x in ipairs(lines) do L[#L + 1] = "  " .. tostring(x) end else L[#L + 1] = "  dump 报错: " .. tostring(lines) end end
	if isfile("Selfblox_log.txt") then local t = readfile("Selfblox_log.txt") or ""; L[#L + 1] = "-- 日志尾部"; L[#L + 1] = t:sub(-1500) end
	return L
end
dumpNow = function()
	local txt = table.concat(dumpLines(), "\n")
	writefile("selfblox_dump.txt", txt)
	setclipboard(txt)
	toast(`诊断 {#txt} 字节 → selfblox_dump.txt / 剪贴板`)
end
_G.SB_DUMP = dumpNow

_G.SB_UNLOAD = function()
	if not alive then return end -- 重入保护: 连着卸两次, 第二遍会在已经 Destroy 的 gui 上炸
	alive = false
	for _, release in ipairs(heldReleases) do pcall(release) end -- 按住途中卸载: 把还按着的功能松开 (闪灯循环自己看 alive, 不用在这里通知)
	for _, e in ipairs(BUILT) do if e.off then pcall(e.off) end end -- 一个功能清理炸了不能拦住其他的
	for _, c in ipairs(conns) do c:Disconnect() end
	gui:Destroy()
	FX:Destroy()
	_G.SB_DUMP = nil -- 卸载后调它会摸到已经 Destroy 的实例: dumpLines 里 pageInfos 和各页 DUMP 都不看 alive
	_G.SB_UNLOAD = nil
end
print(`[Selfblox] {VERSION} · {#ACTIVE} 模块 · _G.SB_UNLOAD() 卸载`)
