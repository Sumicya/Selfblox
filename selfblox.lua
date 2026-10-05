-- Selfblox · 单文件 · 一次 loadstring · 一个面板 · 七页清单
-- 版本: 下面的 VERSION 是唯一来源(五段 yy.m.d.当日序号.总序号; 口径见 README「版本」); 面板标题 / 诊断快照 / 启动打印都读它
-- 用法:  loadstring(game:HttpGet("https://raw.githubusercontent.com/Sumicya/Selfblox/HEAD/selfblox.lua"))()
-- 覆盖:  执行前 _G.SB = { spd = 50, flyspd = 80, only = {"moc", "sibs"} }
-- 优先级: _G.SB > Selfblox.json(面板里改过的值) > 默认值
-- 卸载:  _G.SB_UNLOAD()   重跑会自动先卸载
-- 自检:  lua5.4 smoke.lua  (离线假引擎, 不跑也行)
--
-- 设计约定:
--   表驱动 —— 一个功能 = 一个顶层函数 + 清单里一行 feature{}; 建页 / 存盘 / 每帧连接 / 卸载 / 诊断都从清单生成,
--            核心不为新功能改一个字 (见下面「注册表」)。加功能三步: 写函数 → 在对应页的块里追加一行 → 跑 smoke.lua
--   原生优先 —— 刹车 / 灯 / 秒互动 / ESP 走引擎原生属性, 拖拽走 UIDragDetector, 不自己造轮子
--   面向 Delta 最新版 —— hookmetamethod / newcclosure / UIDragDetector 当它一定有;
--            gethui / isfile / writefile 缺失时退回 CoreGui 并跳过存盘, 面板照样起得来
--   保持 Lua 5.4 可解析子集(不用 +=/continue/字符串插值), 这样 smoke.lua 能离线跑: 可测试性 > 语法糖

local VERSION = "26.10.5.10.10" -- 单一版本来源: 五段 yy.m.d.当日序号.总序号 (日期按 Asia/Shanghai); 标签是 v<VERSION>, 打标签要先获主人授权

if rawget(_G, "SB_UNLOAD") then _G.SB_UNLOAD() end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
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
local function save(k, v) saved[k] = v; if writefile then writefile(FILE, Http:JSONEncode(saved)) end end
local CLOCK12 = opt("clock", "12") ~= "24" -- 12 小时制默认; _G.SB = { clock = "24" } 切 24
local function clock(sec) return os.date((CLOCK12 and "%I" or "%H") .. (sec and ":%M:%S" or ":%M")) end

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
local W, ROW = 200, 26
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
local function text(parent, s, w) return ui("TextLabel", parent, w, { Text = s, BackgroundTransparency = 1, TextWrapped = true }) end
local function btn(parent, s, fn, w)
	local b = ui("TextButton", parent, w, { Text = s })
	on(b.Activated, function() fn(b) end)
	return b
end
local function toggle(parent, s, init, fn, w) -- 返回 set(v): 代码里也能翻状态
	local b, st = ui("TextButton", parent, w), nil
	local function set(v, quiet) st = v; b.Text = s .. (v and " 开" or " 关"); lit(b, v); if not quiet then fn(v) end end
	set(init, true)
	on(b.Activated, function() set(not st) end)
	return set
end
local function hold(parent, s, fn, w) -- 按住 fn(true) 松开 fn(false)
	local b = ui("TextButton", parent, w, { Text = s, AutoButtonColor = false })
	on(b.InputBegan, function(i) if tap(i) then lit(b, true); fn(true) end end)
	on(b.InputEnded, function(i) if tap(i) then lit(b, false); fn(false) end end)
end
local function num(parent, s, S, k, w, savek) -- 直接绑 S[k], 改完自动存盘; savek 缺省 = k
	local f = mk("Frame", { Size = w and UDim2.new(w, 0, 1, 0) or UDim2.new(1, 0, 0, ROW), LayoutOrder = ord(), BackgroundColor3 = OFF, BackgroundTransparency = CLEAR, BorderSizePixel = 0 }, parent) -- 一行分两半: 左半标签, 右半输入框, 文字各在自己那半格里居中 (原来标签靠左 + 前面垫个空格, 和居中的按钮/输入框对不齐)
	if s then ui("TextLabel", f, nil, { Text = s, BackgroundTransparency = 1, Size = UDim2.fromScale(0.5, 1) }) end
	local tb = mk("TextBox", { Size = UDim2.fromScale(s and 0.5 or 1, 1), Position = UDim2.fromScale(s and 0.5 or 0, 0), BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = Color3.fromRGB(255, 225, 140), Text = tostring(S[k]), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, ClearTextOnFocus = false }, f)
	on(tb.FocusLost, function() local v = tonumber(tb.Text); if v then S[k] = v; save(savek or k, v) end; tb.Text = tostring(S[k]) end)
end

local vp = workspace.CurrentCamera.ViewportSize
local pos = opt("pos", { vp.X / 2 - W / 2, vp.Y * 0.3 })
local title = mk("TextLabel", { Name = "SB_Title", Size = UDim2.fromOffset(W, ROW), Position = UDim2.fromOffset(math.clamp(pos[1], 0, math.max(vp.X - W, 0)), math.clamp(pos[2], 0, math.max(vp.Y - ROW, 0))), BackgroundColor3 = BG, BackgroundTransparency = CLEAR, BorderSizePixel = 0, Font = FONT, TextSize = 13, TextColor3 = WHITE, Text = "Selfblox " .. VERSION }, gui)
local body = mk("Frame", { Name = "SB_Body", Size = UDim2.new(0, W, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = title.Position + UDim2.fromOffset(0, ROW), BackgroundColor3 = BG, BackgroundTransparency = CLEAR, BorderSizePixel = 0 }, gui)
mk("UIListLayout", { Padding = UDim.new(0, 0) }, body)
on(title:GetPropertyChangedSignal("Position"), function() body.Position = title.Position + UDim2.fromOffset(0, ROW) end)
local fold = mk("TextButton", { Size = UDim2.fromOffset(ROW, ROW), Position = UDim2.new(1, -ROW, 0, 0), BackgroundTransparency = 1, Font = FONT, TextSize = 16, TextColor3 = WHITE, Text = "–" }, title)
local foldHooks = {} -- 想知道"面板是折着还是开着"的模块挂这里
local function setFold(v) body.Visible = v; fold.Text = v and "–" or "+"; for _, f in ipairs(foldHooks) do f(v) end end
local drag = mk("UIDragDetector", { BoundingUI = gui }, title)
local flipT, down = -math.huge, nil
local function flip() -- 一次点按可能同时走下面三条路(拖拽器 / +按钮 / 标签自己的输入), 0.2 秒内只认第一条, 不然翻两次等于没翻. ponytail: 0.2 秒内连点两下会被当成一下
	if os.clock() - flipT > 0.2 then flipT = os.clock(); setFold(not body.Visible) end
end
on(drag.DragStart, function(p) down = p end) -- 事件名: 官方文档里 UIDragDetector 只有 DragStart / DragContinue / DragEnd, 没有 DragBegin (写错 = 真引擎直接抛错, 脚本死在这一行, 后面一个页签都没建)
on(drag.DragEnd, function(p) -- 抬手: 挪动 <8px = 点击 = 折叠, 否则是拖动 = 存位置. 手指必然会抖, 所以不能拿"有没有收到 DragContinue"来判
	if down and (p - down).Magnitude < 8 then flip() else save("pos", { title.AbsolutePosition.X, title.AbsolutePosition.Y }) end
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

local toastL = mk("TextLabel", { Name = "SB_Toast", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = BG, BackgroundTransparency = 0.2, BorderSizePixel = 0, Font = FONT, TextSize = 13, TextColor3 = WHITE, Visible = false }, gui)
mk("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, toastL)
local toastN = 0
local function toast(s) toastN = toastN + 1; local n = toastN; toastL.Text, toastL.Visible = s, true; task.delay(2, function() if toastN == n then toastL.Visible = false end end) end
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
	elseif k == "num" then S[e.key] = opt(e.key, e.def) end
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
	text = function(e, p, w) W[e.key] = text(p, e.label, w) end,
	custom = function(e, p) e.build(p) end,
	tick = function() end, dump = function() end, -- 没有控件的行: 只挂每帧 / 诊断
}
local NOUI = { tick = true, dump = true }

do -- ═════════ 动: 角色 (速度 / 飞行 / 高跳 / 旋转 / 无限跳 / 穿墙 / 夜视 / 秒互动) ═════════
	local moving, nvT = false, 0
	local att, flyLV, flyAO, spinAV, cc, nvSaved
	local base = setmetatable({}, { __mode = "k" }) -- humanoid -> 原始 WalkSpeed/JumpPower/JumpHeight
	local col = setmetatable({}, { __mode = "k" }) -- 穿墙前 CanCollide=true 的部件
	local prompts = setmetatable({}, { __mode = "k" }) -- prompt -> 原始属性
	local function body() -- 角色在场才干活: 返回 character, humanoid, root
		local c, h, r = me.Character, hum(), root()
		if c and h and r and r:IsDescendantOf(workspace) then return c, h, r end
	end

	local function baseOf(h) local b = base[h]; if not b then b = { h.WalkSpeed, h.JumpPower, h.JumpHeight }; base[h] = b end; return b end
	local function restore() local h = hum(); local b = h and base[h]; if b then h.WalkSpeed, h.JumpPower, h.JumpHeight = b[1], b[2], b[3] end end
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
		flyLV.VectorVelocity = md * S.flyspd + Vector3.yAxis * (S.flyspd * (cam.LookVector.Y * md:Dot(look) + (F.up and 1 or 0) - (F.down and 1 or 0)))
		flyAO.CFrame = CFrame.lookAt(Vector3.zero, look)
	end
	local function doSpeed(r, h, dt)
		local md = h.MoveDirection
		if F.spdmode == "walk" then baseOf(h); h.WalkSpeed = S.spd
		elseif F.spdmode == "cframe" then if md.Magnitude > 0 then r.CFrame = r.CFrame + md * (S.spd * dt) end
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

	local function speedTick(dt) local _, h, r = body(); if h and not h.SeatPart and h.Health > 0 then doSpeed(r, h, dt) end end
	local function flyTick() local _, h, r = body(); if h then if h.SeatPart then W.fly(false) else doFly(r, h) end end end
	local function jumpTick() local _, h = body(); if h then baseOf(h); if h.UseJumpPower then h.JumpPower = S.jump else h.JumpHeight = S.jump end end end
	local function spinTick() local _, h, r = body(); if h then if h.SeatPart then if spinAV then stopSpin() end else doSpin(r) end end end
	local function clipTick() local c = body(); if c then noclip(c) end end
	local function nvTick() if body() and os.clock() - nvT > 0.5 then nvT = os.clock(); nvOn() end end -- 游戏会重置光照, 半秒补一次
	feature{ kind = "page", id = "moc", tab = "动" }
	feature{ key = "speed", label = "速度", num = { "spd", 16 }, tick = speedTick, set = function() moving = false end, off = restore }
	feature{ kind = "cycle", key = "spdmode", save = "spdmode", def = "root", cycle = { "root", "walk", "cframe" }, text = function(v) return "模式 " .. v end, set = function() restore(); moving = false end, w = 1 }
	feature{ key = "fly", label = "飞行", num = { "flyspd", 50 }, tick = flyTick, off = stopFly }
	feature{ key = "jump", label = "高跳", num = { "jump", 50 }, tick = jumpTick, off = restore }
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
end

do -- ═════════ 车: 载具 (坐着 = 控制座位所在装配体; 没坐 = 准星"换车"锁定 / 自动绑最近的空座位) ═════════
	S.turncap, S.hornkey, S.carmaxstuds, S.carswap = opt("turncap", 1), opt("hornkey", "H"), opt("carmaxstuds", 150), opt("carswap", true) -- 只读配置 (没有面板控件) -- maxstuds: 装配体外径超过这个数就不当成车(是地图/大容器). 量装配体不量 Model 容器: 车直接挂在超大容器里也认得出来
	local picked, pickSeat, pickPath, autoPick, curSeat, curMax, att, vf, lv, clipCar, lastCar, lastAnch
	local target, statT, autoT = 0, 0, 0
	local lamps, lampSaved, col = {}, setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local track, knob, handle, kd, dragX -- 方向盘控件 (init 里建)
	local live = false
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
	local function asmDims(r) -- 装配体的粗略外径(格) + 质量. 判"这是车还是地图"量装配体, 不量 Model 容器: 容器可能装着整条街而车只是里面一件; 反过来整块路面自己就是一个超大装配体
		local span = 0
		for _, d in ipairs(r:GetConnectedParts(true)) do
			local m = (d.Position - r.Position).Magnitude + 0.5 * d.Size.Magnitude -- 加半件尺寸: 单件的装配体(一整块路面)也能算出来
			if m > span then span = m end
		end
		return span * 2, nn(r.AssemblyMass)
	end
	local function heavyNear(p) -- 附近最重的"没锚定"零件: 锁到装饰件时, 真身往往是它
		swapParams.FilterDescendantsInstances = { me.Character }
		local best, bm
		for _, d in ipairs(workspace:GetPartBoundsInRadius(p.Position, 30, swapParams)) do
			if d:IsA("BasePart") and not d.Anchored and d.AssemblyRootPart and nn(d.AssemblyMass) > (bm or 0) then
				local r = d.AssemblyRootPart
				if (asmDims(r)) <= S.carmaxstuds then best, bm = r, nn(d.AssemblyMass) end -- 就近改绑也不能改绑到整条街: 30 格里最重的那件往往就是地图
			end
		end
		return best
	end
	local function part() -- 控制部件, 座位
		local s = seat()
		if s then return s.AssemblyRootPart, s end
		if picked and not picked.Parent and pickPath then -- 车被换掉了: 按路径找回
			local node = findByPath(pickPath)
			if node and node:IsA("BasePart") then picked = node; toast("车被换掉, 自动更到 " .. node.Name) end
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
	local clipList, clipSeen, clipKeep, clipBottom, clipLow, clipT, clipWheels = {}, {}, {}, {}, nil, -1, false
	local function wheelish(d) local nm = d.Name:lower(); return (nm:find("wheel") or nm:find("tire") or nm:find("tyre") or nm:find("轮")) ~= nil end
	local function reclip() reclipAll(col); clipCar, clipList, clipSeen, clipKeep, clipBottom, clipLow, clipT, clipWheels = nil, {}, {}, {}, {}, nil, -1, false end
	local function bottomY(d) -- 零件在世界坐标里的最低点 (按旋转后的包围盒算)
		local c, z = d.CFrame, d.Size
		return d.Position.Y - 0.5 * (math.abs(c.RightVector.Y) * z.X + math.abs(c.UpVector.Y) * z.Y + math.abs(c.LookVector.Y) * z.Z)
	end
	local function keepRule(d) -- 只留轮胎碰撞; 一个轮子名都认不到时才退回"整车最低 0.5 格内"兜底, 不然车直接掉出世界
		if clipWheels then return wheelish(d) end
		return (clipBottom[d] or math.huge) <= (clipLow or math.huge) + 0.5
	end
	local function rejudge() for _, d in ipairs(clipList) do clipKeep[d] = keepRule(d) or nil end end -- 高度用第一次看到时的值: 悬挂压缩 / 车翻身都不改判, 不然轮子会被自己穿掉
	local function noclip(p) -- 穿墙: 范围只有本车装配体(不是整个 Model 容器, 免得穿掉同容器里别的车和地图件); 锚定的(地面/平台)和人物的不碰. 不悬浮: 探地推起会把车托高、轮子悬空 = "开启上浮"
		if p ~= clipCar then reclip(); clipCar = p end
		if os.clock() - clipT > 0.5 then -- 半秒补一批新零件
			clipT = os.clock()
			local fresh = {}
			for _, d in ipairs(p:GetConnectedParts(true)) do
				if d:IsA("BasePart") and not clipSeen[d] and not d.Anchored and not mine(d) then
					clipSeen[d] = true; clipList[#clipList + 1] = d; fresh[#fresh + 1] = d
					clipBottom[d] = bottomY(d)
					if d.CanCollide then clipLow = math.min(clipLow or math.huge, clipBottom[d]) end -- 本来就不碰撞的(影子/玻璃)不参与"最低"
					if wheelish(d) then clipWheels = true end -- 轮子可能晚一批才出现: 认到就整车重判一次
				end
			end
			if #fresh > 0 then rejudge() end
		end
		for _, d in ipairs(clipList) do if d.Parent and d.CanCollide and not clipKeep[d] then col[d] = true; d.CanCollide = false end end
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
	local function horn(v) VIM:SendKeyEvent(v, Enum.KeyCode[S.hornkey], false, game) end
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
		if s then toast("锁定 " .. seatM.Name .. " · 座位 " .. s.Name)
		else toast("锁定 " .. inst.Name .. " · 没座位(只能推/飞/翻转, 没油门)") end
	end
	local function autoBind() -- 没坐没锁: 找最近的"空载具座位"绑上. ponytail: 每秒一次 150 格球查询; 极稠密的地图可改成 DescendantAdded 注册表
		local r = root()
		if not r then return end
		swapParams.FilterDescendantsInstances = { me.Character }
		local best, bd, bv
		for _, d in ipairs(workspace:GetPartBoundsInRadius(r.Position, 150, swapParams)) do
			local isV = d:IsA("VehicleSeat")
			if (isV or d:IsA("Seat")) and not d.Occupant and d.AssemblyRootPart and (isV or not d.AssemblyRootPart.Anchored) then -- 锚定的普通 Seat 是长椅/椅子, 不是车
				local dist = (d.Position - r.Position).Magnitude
				if not best or (isV and not bv) or (isV == bv and dist < bd) then best, bd, bv = d, dist, isV end -- VehicleSeat 优先, 同类取最近
			end
		end
		if not best then return end
		picked, pickSeat, pickPath, autoPick = best.AssemblyRootPart, best, best.AssemblyRootPart:GetFullName(), true
		dropLamps()
		toast("自动绑定 " .. (best:FindFirstAncestorOfClass("Model") or best).Name .. " · 座位 " .. best.Name)
	end
	local function flipCar()
		local p, m = part(), model()
		if not p then toast("没有载具"); return end
		local cf = CFrame.new(p.Position + Vector3.yAxis * 2) * CFrame.fromAxisAngle(p.CFrame.LookVector, math.pi)
		if m then m:PivotTo(cf * m:GetPivot().Rotation) else p.CFrame = cf * p.CFrame.Rotation end -- 没有 Model 也能翻
		p.AssemblyAngularVelocity = Vector3.zero
	end
	local function brakeNow(p, v) p.AssemblyLinearVelocity = Vector3.yAxis * v.Y end -- 急刹: 水平速度直接归零, 比推力快且不吃质量

	local function setLive(v)
		live = v
		handle.Visible = v
		track.ZIndex, knob.ZIndex = v and 10 or 1, v and 11 or 2
		track.BackgroundTransparency, knob.BackgroundTransparency = v and 0.4 or 0.75, v and 0 or 0.55
		if not v then dragX = nil; knob.Position = UDim2.fromScale(0.5, 0.5) end
	end
	local function steer() -- 轨道宽 200 / 圆点半径 18 → 圆心能走 ±82
		if not live then return 0 end
		local cx = track.AbsolutePosition.X + 100
		local s = math.clamp((dragX or cx) - cx, -82, 82)
		knob.Position = UDim2.new(0.5, s, 0.5, 0) -- 圆点是纯显示, 只跟手指
		return s / 82
	end
	local function moveVec() -- 摇杆原始输入 (前推 Z=-1, 右推 X=1). 官方 UserInputService 没有 GetMoveVector (那是 PlayerModule.ControlModule 的方法), 真引擎里一调就抛错; 这里把 Humanoid.MoveDirection (相机相对的世界方向) 换回相机坐标
		local h, md = hum(), nil
		md = h and h.MoveDirection
		if not md or md.Magnitude < 1e-3 then return Vector3.zero end
		local r = flat(workspace.CurrentCamera.CFrame.RightVector) or Vector3.xAxis
		return Vector3.new(md:Dot(r), 0, -md:Dot(Vector3.yAxis:Cross(r)))
	end
	local function wheelInit() -- 建好页之后: 钉在屏幕底部的方向盘 (有副作用, 不能放块级)
		track = mk("Frame", { Name = "SB_Steer", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(200, 36), BackgroundColor3 = BG, BackgroundTransparency = 0.4, BorderSizePixel = 0, Visible = false, ZIndex = 10 }, gui)
		mk("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
		knob = mk("Frame", { Name = "SB_Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = Color3.fromRGB(95, 65, 135), BorderSizePixel = 0, ZIndex = 11 }, track)
		mk("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
		local HOME = UDim2.new(0, 0, 0, 0) -- 手柄的家: 全宽 + 锚点(0,0). 松手要回到这里; 原来照抄圆点的 fromScale(0.5,0.5), 一松手整条手柄被推到右下半格, 左半条就按不到了
		handle = mk("Frame", { Name = "SB_Handle", Position = HOME, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Active = true, ZIndex = 12 }, track) -- 看不见的手柄盖在最上面, 整条都能按
		kd = mk("UIDragDetector", { DragStyle = Enum.UIDragDetectorDragStyle.TranslateLine, DragAxis = Vector2.new(1, 0), BoundingUI = track }, handle)
		on(kd.DragContinue, function(p) dragX = p.X end) -- 官方文档: DragContinue 给的是 inputPosition: Vector2 (屏幕坐标), 不是 InputObject; 原来按 i.Position 读, 在 Vector2 上会直接抛错
		on(kd.DragEnd, function() dragX = nil; handle.Position = HOME end)
		foldHooks[#foldHooks + 1] = function(open) setLive(F.steeropen or not open) end -- 钩子收到的是"面板开着吗", 滑条要的是"能不能拖"
		setLive(not body.Visible)
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
		if p and not sp and p.Anchored and S.carswap then -- 没座位的锚定件(还没解锁/装饰件): 就近改绑到能推的那件. 有座位的车不改绑: 座位所在装配体就是车, 锚着就等游戏解锁
			local cand = heavyNear(p)
			if cand and cand ~= p then
				picked, pickSeat, pickPath = cand, nil, cand:GetFullName()
				toast("锚定件改用 " .. cand.Name)
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
		if os.clock() - statT > 0.2 then statT = os.clock(); say("car_status", (m and m.Name or p.Name) .. " · " .. math.floor(spd + 0.5) .. (s and "" or " · 准星锁定") .. (anch and " · 锚定(等游戏解锁)" or "") .. (F.carclip and #clipList > 0 and not clipWheels and " · 穿墙没认到轮子(按最低块兜底)" or "")) end
		if F.carclip then noclip(p) elseif clipCar then reclip() end
		if F.cfly then -- 飞车: 摇杆(前后左右) + 面板按钮都吃; 松手悬停
			if not lv then lv = mk("LinearVelocity", { Attachment0 = att, MaxForce = math.huge, VectorVelocity = Vector3.zero, RelativeTo = Enum.ActuatorRelativeTo.World }, att) end
			local mv = moveVec() -- 摇杆: 前推 Z=-1, 右推 X=1
			local dir = fwd * math.clamp(-mv.Z + (acc and 1 or 0) - (dec and 1 or 0), -1, 1) + (flat(p.CFrame.RightVector) or Vector3.xAxis) * math.clamp(mv.X, -1, 1)
			if dir.Magnitude > 1 then dir = dir.Unit end
			lv.VectorVelocity = anch and Vector3.zero or (dir * S.carfly + Vector3.yAxis * (S.carfly * ((F.cup and 1 or 0) - (F.cdown and 1 or 0))))
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
		elseif dec then push = -fwd * (f * (hv:Dot(fwd) > 3 and 2 or 1)) -- 前进中双倍刹, 停了就倒车
		elseif F.cruise then push = fwd * math.clamp((target - hv:Dot(fwd)) * mass * 2, -f, f) end
		if not F.cruise then target = hv:Dot(fwd) end -- 定速一开就锁当前车速
		if anch then vf.Force = Vector3.zero else vf.Force = push end -- 锚定: 力无效, 清零等着
	end

	local function carLines()
		local p, s, cached = part()
		if not p and lastCar then p, s, cached = lastCar.p, lastCar.s, true end -- 打包时没车也能带出最近一辆的结构
		if not p then return { "没有载具 (先用 换车 锁定或坐上去, 再点诊断打包)" } end
		if cached and not (p:IsDescendantOf(workspace)) then
			return { "最近一辆: " .. tostring(lastCar.path), "  已经不在 workspace 里了(被游戏销毁/回收) → 结构拿不到, 只能在车还在的时候点诊断打包" }
		end
		local m = cached and lastCar.m or model()
		local L = { "==== CAR " .. os.date("%Y-%m-%d ") .. clock(true) .. " place=" .. game.PlaceId .. (cached and " (缓存的最近一辆)" or "") .. " ====",
			"座位: " .. (s and s:GetFullName() or "-") .. "   根部件: " .. p:GetFullName() .. "   Model: " .. (m and m:GetFullName() or "-"),
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
					if c:IsA("Light") then L[#L + 1] = "        灯 " .. c.ClassName .. " " .. c.Name .. " Enabled=" .. tostring(c.Enabled)
					elseif c:IsA("Constraint") or c:IsA("BodyMover") or c:IsA("Attachment") then L[#L + 1] = "        " .. c.ClassName .. " " .. c.Name end
				end
			end
		end
		-- 准星现在打到什么: 车不听话时这一条最有用
		local cam = workspace.CurrentCamera
		rp.FilterDescendantsInstances = { me.Character }
		local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 5000, rp)
		L[#L + 1] = "-- 准星射线: " .. (hit and (hit.Instance.ClassName .. " " .. hit.Instance:GetFullName()) or "没打到东西")
		if hit then
			local chain, x = {}, hit.Instance
			while x and x ~= workspace do chain[#chain + 1] = x.Name .. "(" .. x.ClassName .. ")"; x = x.Parent end
			L[#L + 1] = "    祖先: " .. table.concat(chain, " ← ")
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
				near = near + 1
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
	local function holdInfo() return (F.accel and " 按加速" or "") .. (F.decel and " 按减速" or "") .. (F.cup and " 按升" or "") .. (F.cdown and " 按降" or "") end
	local function carInfo()
		local p, s = part()
		if p and vf then
			return string.format("抓地=%s/转向=%s/过弯上限=%s 部件=%s%s 推力=%.0f(%.1f/kg) 质量=%.0f 速度=%.0f%s 定速=%s@%.0f 飞车=%s 穿墙=%s 急刹=%s%s",
				S.grip, S.turn, S.turncap, p:GetFullName(), seatInfo(s), vf.Force.Magnitude, vf.Force.Magnitude / math.max(p.AssemblyMass, 1), p.AssemblyMass,
				p.AssemblyLinearVelocity.Magnitude, p.Anchored and " 锚定(引擎不让推)" or "", tostring(F.cruise), target, tostring(F.cfly), tostring(F.carclip), tostring(F.brake), holdInfo())
		end
		return "抓地=" .. S.grip .. "/转向=" .. S.turn .. "/过弯上限=" .. S.turncap .. " 部件=-" .. seatInfo(nil) .. " 定速=" .. tostring(F.cruise) .. "@" .. math.floor(target) .. " 飞车=" .. tostring(F.cfly) .. " 穿墙=" .. tostring(F.carclip) .. " 急刹=" .. tostring(F.brake) .. holdInfo()
	end
	local function carStop() detach(); reclip(); dropLamps(); horn(false); if curSeat and curMax then curSeat.MaxSpeed = curMax end end
	feature{ kind = "page", id = "sibs", tab = "车", info = carInfo }
	feature{ kind = "num", key = "acc", def = 500, label = "加速" }
	feature{ kind = "num", key = "carfly", def = 60, label = "飞速" }
	feature{ kind = "num", key = "grip", def = 5, label = "抓地" }
	feature{ kind = "num", key = "turn", def = 2.2, label = "转向" }
	feature{ kind = "btn", label = "换车(准星)", fn = pick }
	feature{ key = "carclip", save = "carclip", label = "穿墙" }
	feature{ key = "cruise", label = "定速" }
	feature{ key = "cfly", label = "飞车" }
	feature{ kind = "btn", label = "翻转 180°", fn = flipCar }
	feature{ key = "brake", label = "急刹" }
	feature{ key = "lamp", label = "常亮", set = function(v) if v then setLamps(true) else dropLamps() end end }
	feature{ kind = "btn", label = "闪 ×3", fn = function() task.spawn(function() for _ = 1, 3 do setLamps(true); task.wait(0.12); setLamps(false); task.wait(0.12) end; if F.lamp then setLamps(true) else dropLamps() end end) end }
	feature{ key = "steeropen", save = "steeropen", label = "滑条常可拖", w = 1, set = function(v) setLive(v or not body.Visible) end } -- true = 面板开着也能拖滑条 (默认: 折起来才能拖)
	feature{ key = "carauto", save = "carauto", def = true, label = "自动绑车", w = 1 }
	feature{ key = "hornon", label = "常声(" .. S.hornkey .. ")", set = horn }
	feature{ kind = "hold", label = "声", set = horn }
	feature{ kind = "hold", key = "accel", label = "▲ 加速", h = 36 }
	feature{ kind = "hold", key = "decel", label = "▼ 减速", h = 36 }
	feature{ kind = "hold", key = "cup", label = "飞 ↑", h = 36 }
	feature{ kind = "hold", key = "cdown", label = "飞 ↓", h = 36 }
	feature{ kind = "text", key = "car_status", label = "上车即控; 没车就对准它按 换车" }
	feature{ kind = "dump", key = "car", dump = carLines }
	feature{ kind = "tick", tick = carTick, init = wheelInit, off = carStop }
end

do -- ═════════ 漂: 人物推进 (自动找踏板; 找不到就用面板按钮) ═════════
	local att, vf, pedalRoot
	local slots = {} -- slots[1]=刹车 slots[2]=油门
	F.dgas, F.dbrake = false, false -- 油门 / 刹车现在是不是踩着: 游戏踏板和面板按钮都写这两个
	local function pedalLines() -- 踏板的真实结构: 绑不上时能直接看出它长啥样
		local pg = me:FindFirstChild("PlayerGui")
		local f = pg and pg:FindFirstChild("MobilePedals")
		if not f then
			local tops = {}
			if pg then for _, c in ipairs(pg:GetChildren()) do tops[#tops + 1] = c.Name .. "(" .. c.ClassName .. ")" end end
			return { "无 MobilePedals; PlayerGui 顶层: " .. (#tops > 0 and table.concat(tops, ", ") or "(空)") }
		end
		local L = { "MobilePedals: " .. f:GetFullName() }
		for _, d in ipairs(f:GetDescendants()) do
			local ap, sz = d.AbsolutePosition or Vector2.zero, d.AbsoluteSize or Vector2.zero
			L[#L + 1] = string.format("  %-28s %-12s 可见=%-5s 可点=%-5s 位置=(%.0f,%.0f) 尺寸=(%.0f,%.0f)", d.Name, d.ClassName, tostring(d.Visible), tostring(d.Active), nn(ap.X), nn(ap.Y), nn(sz.X), nn(sz.Y))
		end
		return L
	end
	local function slotName(n) return slots[n] and slots[n].btn.Name or "未绑" end
	local function setSlot(n, v) if n == 1 then F.dbrake = v else F.dgas = v end end
	local function clearSlot(n) local sl = slots[n]; if sl then for _, c in ipairs(sl.conns) do c:Disconnect() end end; slots[n] = nil; F.dgas, F.dbrake = F.dgas or false, F.dbrake or false end
	local function bindSlot(n, g) -- 按住 g 就当踩着第 n 个踏板
		clearSlot(n)
		local conns = {}
		conns[#conns + 1] = g.InputBegan:Connect(function(i) if tap(i) then setSlot(n, true) end end)
		conns[#conns + 1] = g.InputEnded:Connect(function(i) if tap(i) then setSlot(n, false) end end)
		slots[n] = { btn = g, conns = conns }
	end
	local function slotsText() return "踏板 刹=" .. slotName(1) .. " 油=" .. slotName(2) end
	local function slotLive(n) local sl = slots[n]; return (sl and sl.btn and sl.btn.Parent) and true or false end
	local function prune() -- 游戏重建 UI 时旧按钮会消失, 留着就是按不动的死连接
		for n = 1, 2 do if slots[n] and not slots[n].btn.Parent then clearSlot(n) end end
	end
	local function autoBind(force) -- force = 手动点了「重绑踏板」(清掉重来)
		if force then clearSlot(1); clearSlot(2) end
		pedalRoot = nil
		local pg = me:FindFirstChild("PlayerGui")
		local f = pg and pg:FindFirstChild("MobilePedals")
		if not f then
			if not slotLive(1) and not slotLive(2) then say("drift_status", "无 MobilePedals → 用下面的 ▲ 油门 / ▼ 刹车") end
			return
		end
		local b = {}
		for _, c in ipairs(f:GetDescendants()) do if c:IsA("GuiButton") then b[#b + 1] = c end end -- 框名/嵌套深度每个游戏不一样, 整个子树找按钮
		table.sort(b, function(x, y) return (x.AbsolutePosition or Vector2.zero).X < (y.AbsolutePosition or Vector2.zero).X end)
		if #b < 2 then if force then say("drift_status", "MobilePedals 里只找到 " .. #b .. " 个按钮 → 用下面的 ▲ 油门 / ▼ 刹车") end; return end
		bindSlot(1, b[1])
		bindSlot(2, b[2])
		pedalRoot = f
		say("drift_status", slotsText())
	end

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
		local m, fs = r.AssemblyMass, r.AssemblyLinearVelocity:Dot(look)
		local push = Vector3.zero
		if F.dgas and F.dbrake then if math.abs(fs) > 0.1 then push = -look * (math.sign(fs) * S.dbrake * m) end
		elseif F.dgas then push = look * (S.dacc * m)
		elseif F.dbrake then push = -look * ((fs > 0.1 and S.dbrake or S.dacc) * m) end -- 前进中刹车, 停了倒退
		vf.Force = push
	end
	local function driftOff() if att then att:Destroy(); att = nil end end
	local function pedalInit() -- 游戏晚点才生成踏板 UI / 重建 UI: 出现就绑
		task.spawn(function()
			local pg = me:WaitForChild("PlayerGui")
			on(pg.ChildAdded, function(c) if c.Name == "MobilePedals" then task.delay(0.2, autoBind) end end)
			autoBind()
		end)
	end
	local function pedalPoll() -- 每秒: 清掉死按钮; 没绑上就自己再试 (不用手动点)
		prune()
		if F.drift and (not pedalRoot or not pedalRoot.Parent or not slotLive(1) or not slotLive(2)) then autoBind() end
	end
	local function pedalStop() driftOff(); for _, sl in pairs(slots) do for _, c in ipairs(sl.conns) do c:Disconnect() end end end
	feature{ kind = "page", id = "drift", tab = "漂", info = function() return "油门=" .. tostring(F.dgas) .. " 刹车=" .. tostring(F.dbrake) .. " " .. slotsText() .. " 状态=" .. tostring(W.drift_status and W.drift_status.Text) end }
	feature{ kind = "num", key = "dacc", def = 5, label = "加速" }
	feature{ kind = "num", key = "dbrake", def = 10, label = "刹车" }
	feature{ key = "drift", save = "drift", def = true, label = "推进", tick = driftTick, off = driftOff }
	feature{ kind = "btn", label = "重绑踏板", fn = function() autoBind(true) end }
	feature{ kind = "hold", key = "dgas", label = "▲ 油门", h = 36 }
	feature{ kind = "hold", key = "dbrake", label = "▼ 刹车", h = 36 }
	feature{ kind = "text", key = "drift_status", label = "…" }
	feature{ kind = "dump", key = "pedals", dump = pedalLines }
	feature{ kind = "tick", loop = pedalPoll, every = 1, init = pedalInit, off = pedalStop }
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
		frames = frames + 1
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
				me:GetNetworkPing() * 1000, fps >= 50 and "#aae696" or "#eb7878", fps, Stats:GetTotalMemoryUsageMb(), clock(), #Players:GetPlayers(), Players.MaxPlayers, pos) -- 数字后面不带单位, 靠颜色认: 青=延迟 绿/红=帧率 紫=内存 黄=时间 粉=人数 灰=坐标
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
	local function head() local h = "---- Selfblox " .. os.date("%Y-%m-%d ") .. clock(true) .. " ----\n"; writefile(LOGFILE, h); written = #h end
	local function logTick() -- 每 S.logint 秒一轮 (清单的 loop 每轮 pcall: 某个页的状态函数 / 序列化 / 写盘抛错, 记录也不会永久停)
		local L = { "[" .. clock(true) .. "] #" .. count, "配置 " .. Http:JSONEncode(saved) } -- 数值不用各模块自己拼, 这里全有
		for _, line in ipairs(pageInfos()) do L[#L + 1] = line end
		local txt = table.concat(L, "\n") .. "\n"
		if written == 0 or written + #txt > S.logmax * 1024 then head() end -- ponytail: 超限直接重写, 不归档; 要历史自己复制文件
		appendfile(LOGFILE, txt)
		count, written = count + 1, written + #txt
		say("log_status", "#" .. count .. " · " .. math.floor(written / 1024) .. "KB / " .. S.logmax .. "KB")
	end
	feature{ kind = "page", id = "log", tab = "志" }
	feature{ kind = "text", key = "log_status", label = "开 录制 后写 " .. LOGFILE }
	feature{ kind = "btn", label = "诊断打包 (整机快照 → 剪贴板)", w = 1, fn = function() if dumpNow then dumpNow() end end }
	feature{ kind = "num", key = "logint", def = 2, label = "间隔s" }
	feature{ kind = "num", key = "logmax", def = 512, label = "上限KB" }
	feature{ key = "rec", label = "录制", w = 1, loop = logTick, every = function() return S.logint end,
		onerr = function(err) say("log_status", "记录出错 (下一轮再试): " .. tostring(err)) end }
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
			for k, x in pairs(v) do o[#o + 1] = tostring(k) .. "=" .. fmt(x, (depth or 0) + 1); if #o >= 8 then break end end
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
			o[#o + 1] = "  " .. (e.n > 1 and e.t0 .. "→" .. e.t1 .. " ×" .. e.n .. " " or e.t0 .. " ") .. e.s0
			if e.n > 1 and e.s1 ~= e.s0 then o[#o + 1] = "      末 " .. e.s1 end
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
				p.parts = p.parts + 1
				if hint(d.Name, WING) then p.wings = p.wings + 1 end
				local vol = d.Size.X * d.Size.Y * d.Size.Z
				if vol > p.vol then p.big, p.vol = d, vol end
			elseif d:IsA("ValueBase") and hint(d.Name, TEAMK) then p.teamVal = p.teamVal or (d.Name .. "=" .. fmt(d.Value)) end
		end
		p.score = (p.hint and 40 or 0) + (p.seat and 35 or 0) + math.min(p.wings, 2) * 12 + (p.parts >= 8 and 10 or 0) + (p.occ and 5 or 0)
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
				watch[#watch + 1] = r.OnClientEvent:Connect(function(...) local a = table.pack(...); push(got, r:GetFullName() .. " <- " .. keyOf(a), r:GetFullName() .. " <- " .. args(a)) end)
			end
		end
	end
	local function setSpy(v)
		if v and not oldNC then
			oldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
				local m = getnamecallmethod()
				if F.spy and (m == "FireServer" or m == "InvokeServer") then
					local a = table.pack(...)
					pcall(function() local path = self:GetFullName(); if F.pall or hint(path, RHINT) then push(sent, path .. ":" .. m .. " " .. keyOf(a), path .. ":" .. m .. " " .. args(a)) end end) -- 记录失败不能拦住游戏自己的调用
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
		say("plane_status", "飞机 " .. #planes .. " · Remote " .. #remotes .. " · 发 " .. tot(sent) .. "/" .. #sent .. "组 收 " .. tot(got) .. "/" .. #got .. "组")
	end
	local function report()
		if #planes == 0 and #remotes == 0 then scan() end -- 只点「写报告」会得到"飞机 0 Remote 0"的假象: 两个表都只有 scan() 会填 (实测过: 人在飞, 报告却是 0 架 0 个 Remote)
		local L = { "==== PLANE " .. os.date("%Y-%m-%d ") .. clock(true) .. " place=" .. game.PlaceId .. " me=" .. me.Name .. " team=" .. (me.Team and me.Team.Name or "-") .. " ====", "-- 飞机 " .. #planes .. " · 重扫于 " .. (scanAt or "从未") }
		for _, p in ipairs(planes) do
			L[#L + 1] = "[" .. p.score .. "] " .. p.path .. (p.mine and " ★我" .. (p.ownBy and "(" .. p.ownBy .. ")" or "") or "") .. " | 座:" .. (p.seat and "有" or "无") .. " 翼:" .. p.wings .. " 件:" .. p.parts .. " | 队:" .. p.team .. "(" .. p.src .. ")" .. (p.occ and " 乘员:" .. p.occ.Name or "")
			for k, v in pairs(p.model:GetAttributes()) do L[#L + 1] = "    attr " .. k .. "=" .. fmt(v) end
			for _, r in ipairs(p.remotes) do L[#L + 1] = "    " .. r.ClassName .. " " .. r:GetFullName() end
		end
		if #rejects > 0 then
			L[#L + 1] = "-- 疑似 " .. #rejects .. " (扫到但没过门槛; 靠「座」=有座位, 靠「翼」=只认到机翼名)"
			for _, p in ipairs(rejects) do L[#L + 1] = "[" .. p.score .. "] " .. p.path .. " | 靠" .. p.why .. " 座:" .. (p.seat and "有" or "无") .. " 翼:" .. p.wings .. " 件:" .. p.parts end
		end
		L[#L + 1] = "-- Remote " .. #remotes
		for _, r in ipairs(remotes) do L[#L + 1] = "  " .. r.ClassName .. " " .. r:GetFullName() end
		L[#L + 1] = "-- 发 " .. tot(sent) .. " 条 / " .. #sent .. " 组 (上限 " .. CAP .. " 组; 连续同 Remote 同目标折叠成一组, 首末 payload 都留着)"
		for _, s in ipairs(dump(sent)) do L[#L + 1] = s end
		L[#L + 1] = "-- 收 " .. tot(got) .. " 条 / " .. #got .. " 组" .. (F.watch and #watch == 0 and " ← 收侦听开着却一个都没挂上 (要先点 重扫)" or "")
		for _, s in ipairs(dump(got)) do L[#L + 1] = s end
		local txt = table.concat(L, "\n")
		writefile("plane_debug.txt", txt)
		setclipboard(txt)
		toast("报告 " .. #L .. " 行 → plane_debug.txt / 剪贴板")
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

do -- ═════════ 砖: BitFarmer 刷砖 (单游戏专用) ═════════
	local st = { cycles = 0, earned = 0, sent = 0, got = 0, rate = 0 }
	S.bmult, S.blevel = opt("bmult", 99999), opt("blevel", 9999) -- 只读配置 (没有面板控件)
	local function ownBrick(c) return c:IsA("BasePart") and not c.Anchored and c:GetAttribute("Owner") == me.UserId end
	local function ingest(b, col) b.CFrame = col.CFrame + Vector3.new(math.random(-3, 3), 1.5, math.random(-3, 3)); b.AssemblyLinearVelocity = Vector3.new(0, -35, 0) end
	local function loop()
		local ls = me:FindFirstChild("leaderstats")
		local col, spawnBit = workspace:FindFirstChild("Collector"), RS:FindFirstChild("SpawnBit")
		local bits, mult = ls and ls:FindFirstChild("Bits"), ls and ls:FindFirstChild("Multiplier")
		if not (col and bits) then W.brick(false); toast("没找到 workspace.Collector / leaderstats.Bits"); return end
		local mult0, lvl0 = mult and mult.Value, me:GetAttribute("MultiplierUpgradeLevel")
		local last, lastT, seen = bits.Value, os.clock(), bits.Value -- seen = 上次记账时的 Bits: 按它算增量, 周期之间到账的也不丢
		local conn = workspace.ChildAdded:Connect(function(c) task.defer(function() if F.brick and ownBrick(c) then ingest(c, col); st.got = st.got + 1 end end) end)
		local function drain() for _, c in ipairs(workspace:GetChildren()) do if ownBrick(c) then ingest(c, col) end end end
		while F.brick and alive do
			st.cycles = st.cycles + 1
			drain()
			if spawnBit then for _ = 1, S.bbatch do if not F.brick then break end; spawnBit:FireServer(); st.sent = st.sent + 1; task.wait(S.bint) end end
			task.wait(S.bdrain)
			drain()
			st.earned, seen = st.earned + math.max(bits.Value - seen, 0), bits.Value
			local t = os.clock()
			if t - lastT >= 1 then st.rate = (bits.Value - last) / (t - lastT); last, lastT = bits.Value, t end
			if mult and mult.Value < S.bmult then mult.Value = S.bmult end
			me:SetAttribute("MultiplierUpgradeLevel", S.blevel)
			say("brick_status", string.format("周期 %d · +%.0f · %.1f/s · 发 %d 收 %d", st.cycles, st.earned, st.rate, st.sent, st.got))
			task.wait(0.15)
		end
		conn:Disconnect()
		if mult and mult0 then mult.Value = mult0 end
		me:SetAttribute("MultiplierUpgradeLevel", lvl0)
	end
	local looping = false -- 关了立刻又开时旧循环还没退出: 只认一条, 不然两条同时跑 (请求翻倍, 还原值也乱)
	local function brickSet(v)
		if v and not looping then
			looping = true
			task.spawn(function() local ok, err = pcall(loop); looping = false; if not ok then W.brick(false); toast("刷砖出错: " .. tostring(err)) end end)
		end
	end
	feature{ kind = "page", id = "brick", tab = "砖", info = function() return string.format("刷=%s 周期=%d 已刷=%.0f 速率=%.1f/s", tostring(F.brick), st.cycles, st.earned, st.rate) end }
	feature{ key = "brick", label = "刷砖", w = 1, set = brickSet, off = function() F.brick = false end }
	feature{ kind = "num", key = "bbatch", def = 4, label = "批次" }
	feature{ kind = "num", key = "bint", def = 0.08, label = "间隔" }
	feature{ kind = "num", key = "bdrain", def = 0.6, label = "排空间隔", w = 1 }
	feature{ kind = "text", key = "brick_status", label = "BitFarmer 专用" }
end

-- ───────── 启动: 按清单建页 / 控件 / 每帧连接; 一个功能装不上不拖累别的 (记下来, 页里写一行) ─────────
local only = opt("only", nil) -- _G.SB.only = {"moc","sibs"} 只装一部分
local function wanted(id) return type(only) ~= "table" or table.find(only, id) ~= nil end
for _, e in ipairs(FEATURES) do if e.kind == "page" and wanted(e.id) then ACTIVE[#ACTIVE + 1] = e end end
local pages, tabBtns, BUILT, FAILED = {}, {}, {}, {}
local function show(name)
	for n, pg in pairs(pages) do pg.Visible = n == name; lit(tabBtns[n], n == name) end
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
			local parent, w = page, e.w or (k == "text" and 1 or 0.5)
			if NOUI[k] then w = 1
			elseif w < 1 then -- 半行控件两两并一行; 行高变了或装不下就另起一行
				local h = e.h or ROW
				if not cur or used + w > 1.001 or curH ~= h then cur, used, curH = row(page, e.h), 0, h end
				used, parent = used + w, cur
			else cur = nil end
			local ok, err = pcall(function()
				KIND[k](e, parent, w < 1 and w or nil)
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
							if not ok2 then if e.onerr then e.onerr(err2) else warn("[Selfblox] " .. (e.label or e.key) .. ": " .. tostring(err2)) end end
						end
					end
				end) end
			else
				local what = e.label or e.key or k
				FAILED[#FAILED + 1] = pid .. " " .. what .. ": " .. tostring(err)
				warn("[Selfblox] " .. FAILED[#FAILED])
				text(page, "✗ " .. what)
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
					if k == "toggle" then t[#t + 1] = e.label .. "=" .. tostring(F[e.key])
					elseif k == "num" then t[#t + 1] = e.key .. "=" .. tostring(S[e.key])
					elseif k == "cycle" then t[#t + 1] = e.key .. "=" .. tostring(F[e.key]) end
				end
			end
			if p.info then t[#t + 1] = p.info() end
			return table.concat(t, " ")
		end)
		o[#o + 1] = p.id .. " " .. (ok and tostring(v) or ("INFO 报错: " .. tostring(v)))
	end
	return o
end

local function dumpLines()
	local L = { "==== Selfblox 诊断 " .. os.date("%Y-%m-%d ") .. clock(true) .. " ====",
		"脚本=" .. VERSION .. " 页签=" .. tostring(saved.tab) .. " place=" .. game.PlaceId .. " 地图=" .. tostring(game.Name),
		"配置 " .. Http:JSONEncode(saved),
		"执行器 isfile=" .. tostring(isfile ~= nil) .. " writefile=" .. tostring(writefile ~= nil) .. " appendfile=" .. tostring(appendfile ~= nil) .. " setclipboard=" .. tostring(setclipboard ~= nil) .. " gethui=" .. tostring(gethui ~= nil) .. " hookmetamethod=" .. tostring(hookmetamethod ~= nil) .. " newcclosure=" .. tostring(newcclosure ~= nil) .. " getnamecallmethod=" .. tostring(getnamecallmethod ~= nil),
		"角色 " .. tostring(me.Name) .. " 队=" .. tostring(me.Team and me.Team.Name) .. " 坐=" .. tostring(hum() and hum().SeatPart and (hum().SeatPart:GetFullName())) .. " 根=" .. tostring(root() and root().Anchored) }
	local r = root()
	if r then L[#L + 1] = string.format("角色 位置=(%.0f,%.0f,%.0f) 速度=%.0f 血=%s", r.Position.X, r.Position.Y, r.Position.Z, r.AssemblyLinearVelocity.Magnitude, tostring(hum() and hum().Health)) end
	L[#L + 1] = "-- 模块状态"
	for _, line in ipairs(pageInfos()) do L[#L + 1] = "  " .. line end
	for _, f in ipairs(FAILED) do L[#L + 1] = "  ✗ " .. f end
	for k, f in pairs(DUMP) do local o, lines = pcall(f); L[#L + 1] = "-- " .. k .. " dump"; if o then for _, x in ipairs(lines) do L[#L + 1] = "  " .. tostring(x) end else L[#L + 1] = "  dump 报错: " .. tostring(lines) end end
	if isfile("Selfblox_log.txt") then local t = readfile("Selfblox_log.txt") or ""; L[#L + 1] = "-- 日志尾部"; L[#L + 1] = t:sub(-1500) end
	return L
end
dumpNow = function()
	local txt = table.concat(dumpLines(), "\n")
	writefile("selfblox_dump.txt", txt)
	setclipboard(txt)
	toast("诊断 " .. #txt .. " 字节 → selfblox_dump.txt / 剪贴板")
end
_G.SB_DUMP = dumpNow

_G.SB_UNLOAD = function()
	alive = false
	for _, e in ipairs(BUILT) do if e.off then pcall(e.off) end end -- 一个功能清理炸了不能拦住其他的
	for _, c in ipairs(conns) do c:Disconnect() end
	gui:Destroy()
	FX:Destroy()
	_G.SB_UNLOAD = nil
end
print("[Selfblox] " .. VERSION .. " · " .. #ACTIVE .. " 模块 · _G.SB_UNLOAD() 卸载")
