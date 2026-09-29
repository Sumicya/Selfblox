-- Selfblox v13 · 单文件 · 一次 loadstring · 一个面板 · 七个模块
-- 用法:  loadstring(game:HttpGet("https://raw.githubusercontent.com/Sumicya/Selfblox/main/selfblox.lua"))()
-- 覆盖:  执行前 _G.SB = { spd = 50, flyspd = 80, only = {"moc", "sibs"} }
-- 优先级: _G.SB > Selfblox.json(面板里改过的值) > 默认值
-- 卸载:  _G.SB_UNLOAD()   重跑会自动先卸载
-- 自检:  lua5.4 smoke.lua  (离线假引擎, 不跑也行)
--
-- v13 = 只保 Delta 最新版: 执行器能力探测(isfile/gethui/newcclosure/hookmetamethod/UIDragDetector)
--       全部当它一定有, 不留兜底; 删掉没用的变量与重复样板; 配置自动进日志;
--       刹车/灯/互动/ESP 全走引擎原生属性。
--       保持 Lua 5.4 可解析子集(不用 +=/continue/字符串插值), 换 smoke.lua 能离线跑。ponytail: 可测试性 > 语法糖

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
local ROOT = gethui() or game:GetService("CoreGui") -- Delta 有 gethui; 没有就退回 CoreGui

-- ───────── 配置: _G.SB 覆盖 > JSON > 默认 ─────────
local O = type(rawget(_G, "SB")) == "table" and _G.SB or {}
local FILE, saved = "Selfblox.json", {}
if isfile(FILE) then local okf, d = pcall(Http.JSONDecode, Http, readfile(FILE)); if okf and type(d) == "table" then saved = d end end -- 配置文件坏了不能连面板一起死
local function opt(k, d) local v = O[k]; if v == nil then v = saved[k] end; if v == nil then v = d end; return v end
local function save(k, v) saved[k] = v; writefile(FILE, Http:JSONEncode(saved)) end
local CLOCK12 = opt("clock", "12") ~= "24" -- 12 小时制默认; _G.SB = { clock = "24" } 切 24
local function clock(sec) return os.date((CLOCK12 and "%I" or "%H") .. (sec and ":%M:%S" or ":%M")) end

-- ───────── 公共 ─────────
local alive, conns, INFO, MODS, stops = true, {}, {}, {}, {}
local function on(sig, fn) local c = sig:Connect(fn); conns[#conns + 1] = c; return c end
local function mk(cls, props, parent) local i = Instance.new(cls); for k, v in pairs(props) do i[k] = v end; i.Parent = parent; return i end
local function tap(i) return i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 end
local function hum() local c = me.Character; return c and c:FindFirstChildOfClass("Humanoid") end
local function root() local c = me.Character; return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Root")) end
local function flat(v) v = Vector3.new(v.X, 0, v.Z); if v.Magnitude > 1e-3 then return v.Unit end end

-- ───────── UI: 一个 ScreenGui, 标题条(原生 UIDragDetector 拖) + 页签 + 每模块一页 ─────────
local FONT, WHITE = Enum.Font.GothamBold, Color3.new(1, 1, 1)
local BG, ON, OFF = Color3.fromRGB(20, 22, 28), Color3.fromRGB(38, 125, 85), Color3.fromRGB(48, 50, 60)
local W, ROW = 200, 26
local gui = mk("ScreenGui", { Name = "Selfblox", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99999 }, ROOT)
local FX = mk("Folder", { Name = "Selfblox_FX" }, ROOT) -- Highlight / BillboardGui 放这里, 卸载一起删

local BASE = { BackgroundColor3 = OFF, BackgroundTransparency = 0.3, BorderSizePixel = 0, Font = FONT, TextSize = 12, TextColor3 = WHITE }
local ORD = 0
local function ord() ORD = ORD + 1; return ORD end -- UIListLayout 按创建顺序排
local function ui(cls, parent, w, props) -- w=nil 整行, w=0.5 半行
	local i = Instance.new(cls)
	for k, v in pairs(BASE) do i[k] = v end
	i.Size, i.LayoutOrder = w and UDim2.new(w, -1, 1, 0) or UDim2.new(1, 0, 0, ROW), ord()
	for k, v in pairs(props or {}) do i[k] = v end
	i.Parent = parent
	return i
end
local function row(parent, h)
	local f = mk("Frame", { Size = UDim2.new(1, 0, 0, h or ROW), BackgroundTransparency = 1, LayoutOrder = ord() }, parent)
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 1) }, f)
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
	local function set(v, quiet) st = v; b.Text = s .. (v and " 开" or " 关"); b.BackgroundColor3 = v and ON or OFF; if not quiet then fn(v) end end
	set(init, true)
	on(b.Activated, function() set(not st) end)
	return set
end
local function hold(parent, s, fn, w) -- 按住 fn(true) 松开 fn(false)
	local b = ui("TextButton", parent, w, { Text = s, AutoButtonColor = false })
	on(b.InputBegan, function(i) if tap(i) then b.BackgroundColor3 = ON; fn(true) end end)
	on(b.InputEnded, function(i) if tap(i) then b.BackgroundColor3 = OFF; fn(false) end end)
end
local function num(parent, s, S, k, w, savek) -- 直接绑 S[k], 改完自动存盘; savek 缺省 = k
	local f = ui("TextLabel", parent, w, { Text = s and " " .. s or "", TextXAlignment = Enum.TextXAlignment.Left })
	local tb = mk("TextBox", { Size = UDim2.new(s and 0.5 or 1, 0, 1, 0), Position = UDim2.new(s and 0.5 or 0, 0, 0, 0), BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = Color3.fromRGB(255, 225, 140), Text = tostring(S[k]), ClearTextOnFocus = false }, f)
	on(tb.FocusLost, function() local v = tonumber(tb.Text); if v then S[k] = v; save(savek or k, v) end; tb.Text = tostring(S[k]) end)
end

local vp = workspace.CurrentCamera.ViewportSize
local pos = opt("pos", { vp.X / 2 - W / 2, vp.Y * 0.3 })
local title = mk("TextLabel", { Name = "SB_Title", Size = UDim2.fromOffset(W, ROW), Position = UDim2.fromOffset(math.clamp(pos[1], 0, math.max(vp.X - W, 0)), math.clamp(pos[2], 0, math.max(vp.Y - ROW, 0))), BackgroundColor3 = BG, BackgroundTransparency = 0.15, BorderSizePixel = 0, Font = FONT, TextSize = 13, TextColor3 = WHITE, Text = "Selfblox v13" }, gui)
local body = mk("Frame", { Name = "SB_Body", Size = UDim2.new(0, W, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = title.Position + UDim2.fromOffset(0, ROW), BackgroundColor3 = BG, BackgroundTransparency = 0.35, BorderSizePixel = 0 }, gui)
mk("UIListLayout", { Padding = UDim.new(0, 1) }, body)
on(title:GetPropertyChangedSignal("Position"), function() body.Position = title.Position + UDim2.fromOffset(0, ROW) end)
local drag = mk("UIDragDetector", { BoundingUI = gui }, title)
on(drag.DragEnd, function() save("pos", { title.AbsolutePosition.X, title.AbsolutePosition.Y }) end)
local fold = mk("TextButton", { Size = UDim2.fromOffset(ROW, ROW), Position = UDim2.new(1, -ROW, 0, 0), BackgroundTransparency = 1, Font = FONT, TextSize = 16, TextColor3 = WHITE, Text = "–" }, title)
local function setFold(v) body.Visible = v; fold.Text = v and "–" or "+" end
on(fold.Activated, function() setFold(not body.Visible) end)
local pressPos -- 标题条整条都能点: 手指没挪动 = 点击折叠, 挪了 = 拖面板
on(title.InputBegan, function(i) if tap(i) then pressPos = title.AbsolutePosition end end)
on(title.InputEnded, function(i)
	if pressPos and tap(i) then
		local p = title.AbsolutePosition
		if math.abs(p.X - pressPos.X) + math.abs(p.Y - pressPos.Y) < 8 then setFold(not body.Visible) end
	end
	pressPos = nil
end)
local tabs = row(body)

local toastL = mk("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = BG, BackgroundTransparency = 0.2, BorderSizePixel = 0, Font = FONT, TextSize = 13, TextColor3 = WHITE, Visible = false }, gui)
mk("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, toastL)
local toastN = 0
local function toast(s) toastN = toastN + 1; local n = toastN; toastL.Text, toastL.Visible = s, true; task.delay(2, function() if toastN == n then toastL.Visible = false end end) end

-- ═════════ moc: 角色 ═════════
MODS[#MODS + 1] = { name = "moc", tab = "动", fn = function(page)
	local S = { spd = opt("spd", 16), mode = opt("spdmode", "root"), fly = opt("flyspd", 50), jump = opt("jump", 50), spin = opt("spin", 50), dist = opt("promptdist", 1000) }
	local speedOn, flyOn, jumpOn, spinOn, infJump, clip, nv, nocd = false, false, false, false, false, false, false, "off"
	local up, down, moving, nvT, setFly = false, false, false, 0, nil
	local att, flyLV, flyAO, spinAV, cc, nvSaved
	local base = setmetatable({}, { __mode = "k" }) -- humanoid -> 原始 WalkSpeed/JumpPower/JumpHeight
	local col = setmetatable({}, { __mode = "k" }) -- 穿墙前 CanCollide=true 的部件
	local prompts = setmetatable({}, { __mode = "k" }) -- prompt -> 原始属性

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
		flyLV.VectorVelocity = md * S.fly + Vector3.yAxis * (S.fly * (cam.LookVector.Y * md:Dot(look) + (up and 1 or 0) - (down and 1 or 0)))
		flyAO.CFrame = CFrame.lookAt(Vector3.zero, look)
	end
	local function doSpeed(r, h, dt)
		local md = h.MoveDirection
		if S.mode == "walk" then baseOf(h); h.WalkSpeed = S.spd
		elseif S.mode == "cframe" then if md.Magnitude > 0 then r.CFrame = r.CFrame + md * (S.spd * dt) end
		else -- root: 直接写水平速度, 松摇杆归零一次
			local v = r.AssemblyLinearVelocity
			if md.Magnitude > 0 then r.AssemblyLinearVelocity = Vector3.new(md.X * S.spd, v.Y, md.Z * S.spd); moving = true
			elseif moving then r.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0); moving = false end
		end
	end
	local function noclip(c) for _, p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then col[p] = true; p.CanCollide = false end end end
	local function reclip() for p in pairs(col) do if p.Parent then p.CanCollide = true end end; table.clear(col) end
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
		if not p:IsA("ProximityPrompt") or prompts[p] or (nocd == "normal" and not p.Enabled) then return end
		prompts[p] = { p.HoldDuration, p.MaxActivationDistance, p.RequiresLineOfSight, p.Enabled }
		p.HoldDuration, p.MaxActivationDistance, p.RequiresLineOfSight, p.Enabled = 0, math.max(p.MaxActivationDistance, S.dist), false, true
	end
	local function setNocd(m)
		nocd = m
		for p, s in pairs(prompts) do if p.Parent then p.HoldDuration, p.MaxActivationDistance, p.RequiresLineOfSight, p.Enabled = s[1], s[2], s[3], s[4] end end
		table.clear(prompts)
		if m ~= "off" then for _, p in ipairs(workspace:GetDescendants()) do patch(p) end end
	end
	on(workspace.DescendantAdded, function(p) if nocd ~= "off" then patch(p) end end)
	on(UIS.JumpRequest, function() local h = hum(); if infJump and h then h:ChangeState(Enum.HumanoidStateType.Jumping) end end)

	on(RunService.PreSimulation, function(dt)
		local c, h, r = me.Character, hum(), root()
		if not (c and h and r and r:IsDescendantOf(workspace)) then return end
		local seated = h.SeatPart ~= nil
		if clip then noclip(c) end
		if flyOn and seated then setFly(false) elseif flyOn then doFly(r, h) elseif flyLV then stopFly() end
		if speedOn and not seated and h.Health > 0 then doSpeed(r, h, dt) end
		if jumpOn then baseOf(h); if h.UseJumpPower then h.JumpPower = S.jump else h.JumpHeight = S.jump end end
		if spinOn and not seated then doSpin(r) elseif spinAV then stopSpin() end
		if nv and os.clock() - nvT > 0.5 then nvT = os.clock(); nvOn() end -- 游戏会重置光照, 半秒补一次
	end)

	local r1 = row(page)
	toggle(r1, "速度", false, function(v) speedOn, moving = v, false; if not v then restore() end end, 0.5)
	num(r1, nil, S, "spd", 0.5)
	local MODES = { root = "walk", walk = "cframe", cframe = "root" }
	btn(page, "模式 " .. S.mode, function(b) restore(); moving = false; S.mode = MODES[S.mode] or "root"; save("spdmode", S.mode); b.Text = "模式 " .. S.mode end)
	local r2 = row(page)
	setFly = toggle(r2, "飞行", false, function(v) flyOn = v; if not v then stopFly() end end, 0.5)
	num(r2, nil, S, "fly", 0.5, "flyspd")
	local r3 = row(page)
	toggle(r3, "高跳", false, function(v) jumpOn = v; if not v then restore() end end, 0.5)
	num(r3, nil, S, "jump", 0.5)
	local r4 = row(page)
	toggle(r4, "旋转", false, function(v) spinOn = v; if not v then stopSpin() end end, 0.5)
	num(r4, nil, S, "spin", 0.5)
	local r5 = row(page)
	toggle(r5, "无限跳", false, function(v) infJump = v end, 0.5)
	toggle(r5, "穿墙", false, function(v) clip = v; if not v then reclip() end end, 0.5)
	local r6 = row(page)
	toggle(r6, "夜视", false, function(v) nv = v; if v then nvOn() else nvOff() end end, 0.5)
	local NEXT, CN = { off = "normal", normal = "force", force = "off" }, { off = "秒互动 关", normal = "秒互动 普通", force = "秒互动 强制" }
	btn(r6, CN.off, function(b) setNocd(NEXT[nocd]); b.Text = CN[nocd]; b.BackgroundColor3 = nocd ~= "off" and ON or OFF end, 0.5)
	local r7 = row(page, 36)
	hold(r7, "▲ 上升", function(v) up = v end, 0.5)
	hold(r7, "▼ 下降", function(v) down = v end, 0.5)
	num(page, "秒互动距离", S, "dist", nil, "promptdist")

	INFO.moc = function() return string.format("速度=%s/%s 飞行=%s 高跳=%s 旋转=%s 穿墙=%s 夜视=%s 秒互动=%s", tostring(speedOn), S.mode, tostring(flyOn), tostring(jumpOn), tostring(spinOn), tostring(clip), tostring(nv), nocd) end
	return function() setFly(false); stopSpin(); reclip(); restore(); nvOff(); setNocd("off"); if att then att:Destroy() end end
end }

-- ═════════ sibs: 载具 (坐着 = 控制座位所在装配体; 没坐 = 准星"换车"锁定) ═════════
MODS[#MODS + 1] = { name = "sibs", tab = "车", fn = function(page)
	local S = { acc = opt("acc", 500), grip = opt("grip", 5), turn = opt("turn", 2.2), cap = opt("turncap", 1), fly = opt("carfly", 60), horn = opt("hornkey", "H") }
	local picked, pickSeat, curSeat, curMax, att, vf, lv, status, clipModel, setBrake
	local accel, decel, up, down, cruise, brake, flying, lampOn, target, statT = false, false, false, false, false, false, false, false, 0, 0
	local clip = opt("carclip", false)
	local lamps, lampSaved, col = {}, setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude

	local function seat() local h = hum(); return h and h.SeatPart end
	local function part() -- 控制部件, 座位
		local s = seat()
		if s then return s.AssemblyRootPart, s end
		if picked and picked:IsDescendantOf(workspace) then return picked, pickSeat end
	end
	local function model() -- 载具模型: 座位/锁定件往上到最外层 Model
		local p, s = part()
		local m = (s or p) and (s or p):FindFirstAncestorOfClass("Model")
		while m and m.Parent and m.Parent:IsA("Model") do m = m.Parent end -- ponytail: 游戏把所有车套在一个大 Model 里会拿到整个容器
		return m
	end
	local function facing() local p, s = part(); return p and (flat((s or p).CFrame.LookVector) or Vector3.zAxis) end
	local function attach(p)
		if att and att.Parent == p then return end
		if att then att:Destroy() end
		p:SetNetworkOwner(me) -- 不抢网络所有权, 客户端推不动别人的车(这就是"要动一会才能控制"的原因)
		att = mk("Attachment", { Name = "SB_SIBS" }, p)
		vf = mk("VectorForce", { Attachment0 = att, Force = Vector3.zero, RelativeTo = Enum.ActuatorRelativeTo.World, ApplyAtCenterOfMass = true }, att)
		lv = nil
	end
	local function detach() if att then att:Destroy(); att, vf, lv = nil, nil, nil end end
	local function reclip() for d in pairs(col) do if d.Parent then d.CanCollide = true end end; table.clear(col); clipModel = nil end
	local function noclip(p, m)
		if m ~= clipModel then reclip(); clipModel = m end
		if m then for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") and d.CanCollide then col[d] = true; d.CanCollide = false end end end -- ponytail: 每物理步扫全车部件, 几百件无感
	end
	local function hover(p, m) -- 穿墙时探地: 贴地推起 / 带内止跌, 坠得快探得远
		rp.FilterDescendantsInstances = { m or p, me.Character }
		local v, half = p.AssemblyLinearVelocity, p.Size.Y / 2
		local hit = workspace:Raycast(p.Position, Vector3.new(0, -(half + 3 + math.max(6, -v.Y * 0.05)), 0), rp)
		if not hit then return end
		local d = hit.Distance - half
		if d < 1 then p.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y, (1 - d) * 10), v.Z)
		elseif d < 3 and v.Y < 0 then p.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z) end
	end
	local function dropLamps() for _, l in ipairs(lamps) do if lampSaved[l] ~= nil then l.Enabled = lampSaved[l] else l:Destroy() end end; table.clear(lamps) end
	local function asm(p) return p:GetConnectedParts(true) end -- 本车装配体的所有部件 (不是整个 Model 容器, 免得动到别人的车)
	local function setLamps(v)
		local p = part()
		if not p then return end
		local fwd = facing()
		if v and #lamps == 0 then
			for _, d in ipairs(asm(p)) do -- 先接车自己带的灯 (SpotLight/PointLight/SurfaceLight)
				if d ~= me.Character and not d:IsDescendantOf(me.Character) then
					for _, c in ipairs(d:GetChildren()) do if c:IsA("Light") then lampSaved[c] = c.Enabled; lamps[#lamps + 1] = c end end
				end
			end
			if #lamps == 0 then -- 车上本来没灯: 装到车头/车尾部件上, 不装座位; 车头朝向和车相反就照背面
				local head, tail, big, vol = nil, nil, nil, 0
				for _, d in ipairs(asm(p)) do
					if not d:IsDescendantOf(me.Character) then
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
	local function horn(v) VIM:SendKeyEvent(v, Enum.KeyCode[S.horn], false, game) end
	local function pick()
		local cam = workspace.CurrentCamera
		rp.FilterDescendantsInstances = { me.Character }
		local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 5000, rp)
		if not hit then toast("准星前面没东西"); return end
		local m = hit.Instance:FindFirstAncestorOfClass("Model")
		while m and m.Parent and m.Parent:IsA("Model") do m = m.Parent end
		local s = m and (m:FindFirstChildWhichIsA("VehicleSeat", true) or m:FindFirstChildWhichIsA("Seat", true))
		local r = (s or hit.Instance).AssemblyRootPart
		if m and m:FindFirstChildOfClass("Humanoid") then toast("打中的是人, 不是车"); return end
		if r.Anchored then toast("车被锁死(锚定), 游戏解锁后再锁"); return end
		picked, pickSeat = r, s
		dropLamps()
		toast("锁定 " .. (m and m.Name or hit.Instance.Name))
	end
	local function flip()
		local p, m = part(), model()
		if not (p and m) then toast("没有载具"); return end
		local pv = m:GetPivot()
		m:PivotTo(CFrame.new(pv.Position + Vector3.yAxis * 2) * CFrame.fromAxisAngle(p.CFrame.LookVector, math.pi) * pv.Rotation)
		p.AssemblyAngularVelocity = Vector3.zero
	end
	local function brakeNow(p, v) p.AssemblyLinearVelocity = Vector3.yAxis * v.Y end -- 急刹: 水平速度直接归零, 比推力快且不吃质量

	-- 方向盘: 钉在屏幕底部不动; ZIndex 压过面板, 面板开着也点得到; 整条背景都能拖 (拖的是全宽透明手柄, 圆点跟着手指), 松手回中
	local track = mk("Frame", { Name = "SB_Steer", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(200, 36), BackgroundColor3 = BG, BackgroundTransparency = 0.4, BorderSizePixel = 0, Visible = false, ZIndex = 10 }, gui)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
	local knob = mk("Frame", { Name = "SB_Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = Color3.fromRGB(95, 65, 135), BorderSizePixel = 0, ZIndex = 11 }, track)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
	local handle = mk("Frame", { Name = "SB_Handle", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Active = true, ZIndex = 12 }, track) -- 看不见的手柄盖在最上面, 整条都能按
	local kd = mk("UIDragDetector", { DragStyle = Enum.UIDragDetectorDragStyle.TranslateLine, DragAxis = Vector2.new(1, 0), BoundingUI = track }, handle)
	local dragX
	on(kd.DragContinue, function(i) local x = i and i.Position and i.Position.X; dragX = (x and x ~= 0) and x or UIS:GetMouseLocation().X end)
	on(kd.DragEnd, function() dragX = nil; handle.Position = UDim2.fromScale(0.5, 0.5) end)
	local function steer() -- 轨道宽 200 / 圆点半径 18 → 圆心能走 ±82
		local cx = track.AbsolutePosition.X + 100
		local s = math.clamp((dragX or cx) - cx, -82, 82)
		knob.Position = UDim2.new(0.5, s, 0.5, 0) -- 圆点是纯显示, 只跟手指
		return s / 82
	end

	on(RunService.PreSimulation, function(dt)
		local s = seat()
		if s ~= curSeat then -- 换座: 还原旧座限速, 新座解限速, 灯重挂
			if curSeat and curMax then curSeat.MaxSpeed = curMax end
			curSeat, curMax = s, s and s:IsA("VehicleSeat") and s.MaxSpeed or nil
			if curMax then s.MaxSpeed = math.huge end
			dropLamps()
			if lampOn then setLamps(true) end
		end
		local p, sp = part()
		track.Visible = p ~= nil
		if not p or p.Anchored then detach(); if clipModel then reclip() end; return end
		attach(p)
		local m = model()
		local v = p.AssemblyLinearVelocity
		local hv = Vector3.new(v.X, 0, v.Z)
		local spd, mass, fwd = hv.Magnitude, p.AssemblyMass, facing()
		local gst, thr, st = 0, 0, steer()
		if sp and sp:IsA("VehicleSeat") then gst, thr, st = sp.Steer, sp.Throttle, math.clamp(st + sp.Steer, -1, 1) end -- 游戏自带的手机油门/方向盘也吃
		local acc, dec = accel or thr > 0, decel or thr < 0
		if os.clock() - statT > 0.2 then statT = os.clock(); status.Text = (m and m.Name or p.Name) .. " · " .. math.floor(spd + 0.5) .. " sps" .. (s and "" or " · 准星锁定") end
		if clip then noclip(p, m); if not flying then hover(p, m) end elseif clipModel then reclip() end
		if flying then -- 飞车: 摇杆(前后左右) + 面板按钮都吃; 松手悬停
			if not lv then lv = mk("LinearVelocity", { Attachment0 = att, MaxForce = math.huge, VectorVelocity = Vector3.zero, RelativeTo = Enum.ActuatorRelativeTo.World }, att) end
			local mv = UIS:GetMoveVector() -- 摇杆: 前推 Z=-1, 右推 X=1 (引擎原生, 坐姿也能读)
			local dir = fwd * math.clamp(-mv.Z + (acc and 1 or 0) - (dec and 1 or 0), -1, 1) + (flat(p.CFrame.RightVector) or Vector3.xAxis) * math.clamp(mv.X, -1, 1)
			if dir.Magnitude > 1 then dir = dir.Unit end
			lv.VectorVelocity = dir * S.fly + Vector3.yAxis * (S.fly * ((up and 1 or 0) - (down and 1 or 0)))
			vf.Force = Vector3.zero
			return
		elseif lv then lv:Destroy(); lv = nil end
		-- 转向: 游戏自己的 Steer 那部分让它自己转, 我们只转滑条多出来的部分, 不重复
		local mine = st - gst
		if math.abs(mine) > 0.02 then -- 停着也能转(原地打方向), 不再等车动起来
			p.CFrame = CFrame.fromAxisAngle(Vector3.yAxis, -mine * S.turn * math.clamp(spd / 25, 0.2, S.cap) * dt) * p.CFrame.Rotation + p.Position -- turncap = 转向速率随速度放大的上限
			if spd > 1 then
				local dir = hv:Dot(fwd) < 0 and -fwd or fwd
				p.AssemblyLinearVelocity = hv.Unit:Lerp(dir, math.min(dt * S.grip, 1)).Unit * spd + Vector3.yAxis * v.Y
			end
		end
		local f, F = mass * S.acc, Vector3.zero
		if brake then -- 急刹: 刹到停, 再踩油门自动解除
			if acc then setBrake(false) else brakeNow(p, v) end
		elseif acc and dec then brakeNow(p, v)
		elseif acc then F = fwd * f
		elseif dec then F = -fwd * (f * (hv:Dot(fwd) > 3 and 2 or 1)) -- 前进中双倍刹, 停了就倒车
		elseif cruise then F = fwd * math.clamp((target - hv:Dot(fwd)) * mass * 2, -f, f) end
		if not cruise then target = hv:Dot(fwd) end -- 定速一开就锁当前车速
		vf.Force = F
	end)

	local r1 = row(page)
	num(r1, "加速", S, "acc", 0.5)
	num(r1, "飞速", S, "fly", 0.5, "carfly")
	local rg = row(page)
	num(rg, "抓地", S, "grip", 0.5)
	num(rg, "转向", S, "turn", 0.5)
	local r2 = row(page)
	btn(r2, "换车(准星)", pick, 0.5)
	toggle(r2, "穿墙", clip, function(v) clip = v; save("carclip", v) end, 0.5)
	local r3 = row(page)
	toggle(r3, "定速", false, function(v) cruise = v end, 0.5)
	toggle(r3, "飞车", false, function(v) flying = v end, 0.5)
	local r4 = row(page)
	btn(r4, "翻转 180°", flip, 0.5)
	setBrake = toggle(r4, "急刹", false, function(v) brake = v end, 0.5)
	local r5 = row(page)
	toggle(r5, "常亮", false, function(v) lampOn = v; if v then setLamps(true) else dropLamps() end end, 0.5)
	btn(r5, "闪 ×3", function() task.spawn(function() for _ = 1, 3 do setLamps(true); task.wait(0.12); setLamps(false); task.wait(0.12) end; if lampOn then setLamps(true) else dropLamps() end end) end, 0.5)
	local r6 = row(page)
	toggle(r6, "常声(" .. S.horn .. ")", false, horn, 0.5)
	hold(r6, "声", horn, 0.5)
	local r7 = row(page, 36)
	hold(r7, "▲ 加速", function(v) accel = v end, 0.5)
	hold(r7, "▼ 减速", function(v) decel = v end, 0.5)
	local r8 = row(page, 36)
	hold(r8, "飞 ↑", function(v) up = v end, 0.5)
	hold(r8, "飞 ↓", function(v) down = v end, 0.5)
	status = text(page, "上车即控; 没车就对准它按 换车")

	INFO.sibs = function() local p = part(); return "抓地=" .. S.grip .. "/转向=" .. S.turn .. "/过弯上限=" .. S.cap .. " 部件=" .. (p and p:GetFullName() or "-") .. " 定速=" .. tostring(cruise) .. "@" .. math.floor(target) .. " 飞车=" .. tostring(flying) .. " 穿墙=" .. tostring(clip) .. " 急刹=" .. tostring(brake) end
	return function() detach(); reclip(); dropLamps(); horn(false); if curSeat and curMax then curSeat.MaxSpeed = curMax end end
end }

-- ═════════ drift: 人物推进 (MobilePedals 自动绑; 没有就用面板按钮) ═════════
MODS[#MODS + 1] = { name = "drift", tab = "漂", fn = function(page)
	local S = { acc = opt("dacc", 5), brake = opt("dbrake", 10) }
	local enabled, w, s, att, vf, status = opt("drift", true), false, false, nil, nil, nil
	local pedalConns = {}
	local function bindPedals()
		for _, c in ipairs(pedalConns) do c:Disconnect() end
		table.clear(pedalConns)
		local pg = me:FindFirstChild("PlayerGui")
		local f = pg and pg:FindFirstChild("MobilePedals")
		f = f and f:FindFirstChild("Frame")
		if not f then status.Text = "无 MobilePedals, 用下面按钮"; return end
		local b = {}
		for _, c in ipairs(f:GetChildren()) do if c:IsA("GuiButton") then b[#b + 1] = c end end
		table.sort(b, function(x, y) return x.AbsolutePosition.X < y.AbsolutePosition.X end)
		if #b < 2 then status.Text = "踏板不足 2 个"; return end
		local function bind(g, set) -- 最左 = 刹车, 次左 = 油门
			pedalConns[#pedalConns + 1] = g.InputBegan:Connect(function(i) if tap(i) then set(true) end end)
			pedalConns[#pedalConns + 1] = g.InputEnded:Connect(function(i) if tap(i) then set(false) end end)
		end
		bind(b[1], function(v) s = v end)
		bind(b[2], function(v) w = v end)
		pedalConns[#pedalConns + 1] = f.ChildAdded:Connect(function() task.delay(0.2, bindPedals) end)
		status.Text = "踏板已绑定 (" .. #b .. " 个)"
	end

	on(RunService.PreSimulation, function()
		local c = me.Character
		local r = c and c:FindFirstChild("Root") or root() -- 漂移游戏的车体叫 Root
		if not (enabled and r and r:IsDescendantOf(workspace)) or r.Anchored then if att then att:Destroy(); att = nil end; return end
		if not att or att.Parent ~= r then
			if att then att:Destroy() end
			att = mk("Attachment", { Name = "SB_DRIFT" }, r)
			vf = mk("VectorForce", { Attachment0 = att, Force = Vector3.zero, RelativeTo = Enum.ActuatorRelativeTo.World, ApplyAtCenterOfMass = true }, att)
		end
		local look = flat(r.CFrame.LookVector) or Vector3.zAxis
		local m, fs = r.AssemblyMass, r.AssemblyLinearVelocity:Dot(look)
		local F = Vector3.zero
		if w and s then if math.abs(fs) > 0.1 then F = -look * (math.sign(fs) * S.brake * m) end
		elseif w then F = look * (S.acc * m)
		elseif s then F = -look * ((fs > 0.1 and S.brake or S.acc) * m) end -- 前进中刹车, 停了倒退
		vf.Force = F
	end)

	local r1 = row(page)
	num(r1, "加速", S, "acc", 0.5, "dacc")
	num(r1, "刹车", S, "brake", 0.5, "dbrake")
	local r2 = row(page)
	toggle(r2, "推进", enabled, function(v) enabled = v; save("drift", v) end, 0.5)
	btn(r2, "重绑踏板", bindPedals, 0.5)
	local r3 = row(page, 36)
	hold(r3, "▲ 油门", function(v) w = v end, 0.5)
	hold(r3, "▼ 刹车", function(v) s = v end, 0.5)
	status = text(page, "…")
	task.spawn(function()
		local pg = me:WaitForChild("PlayerGui")
		on(pg.ChildAdded, function(c) if c.Name == "MobilePedals" then task.delay(0.2, bindPedals) end end)
		bindPedals()
	end)

	INFO.drift = function() return "推进=" .. tostring(enabled) .. " 油门=" .. tostring(w) .. " 刹车=" .. tostring(s) .. " 踏板连接=" .. #pedalConns end
	return function() if att then att:Destroy() end; for _, c in ipairs(pedalConns) do c:Disconnect() end end
end }

-- ═════════ hud: 数据条 / 速度箭头 / 玩家 ESP (原生 Highlight + BillboardGui) ═════════
MODS[#MODS + 1] = { name = "hud", tab = "显", fn = function(page)
	local showBar, showArrow, showEsp = opt("stats", true), opt("arrow", true), opt("esp", true)
	local bar = mk("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, RichText = true, Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = WHITE, TextStrokeTransparency = 0.6 }, gui)
	local arrow = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(0, 3), BackgroundColor3 = Color3.fromRGB(150, 225, 200), BackgroundTransparency = 0.3, BorderSizePixel = 0, Visible = false }, gui)
	local arrowTxt = mk("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(90, 14), BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = Color3.fromRGB(150, 225, 200), TextStrokeTransparency = 0.5, Visible = false }, gui)
	local esp, frames, fps, tick = {}, 0, 0, os.clock()
	local function espAdd(pl)
		if pl == me or esp[pl] then return end
		local hl = mk("Highlight", { FillTransparency = 0.6, OutlineTransparency = 0.2, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Enabled = false }, FX) -- ponytail: 引擎同时只画 31 个 Highlight, 更多人时超出的不显示
		local bb = mk("BillboardGui", { Size = UDim2.fromOffset(160, 16), StudsOffsetWorldSpace = Vector3.yAxis * 3.2, AlwaysOnTop = true, Enabled = false }, FX)
		esp[pl] = { hl, bb, mk("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextStrokeTransparency = 0.5 }, bb) }
	end
	local function espDrop(pl) local e = esp[pl]; if e then e[1]:Destroy(); e[2]:Destroy(); esp[pl] = nil end end
	for _, pl in ipairs(Players:GetPlayers()) do espAdd(pl) end
	on(Players.PlayerAdded, espAdd)
	on(Players.PlayerRemoving, espDrop)

	on(RunService.PreRender, function()
		frames = frames + 1
		local cam, r, now = workspace.CurrentCamera, root(), os.clock()
		local shown = false
		if showArrow and cam then
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
		bar.Visible = showBar
		if showBar then
			local pos = r and string.format("%.0f %.0f %.0f", r.Position.X, r.Position.Y, r.Position.Z) or "-"
			bar.Text = string.format("<font color='#89dceb'>%.0fms</font>  <font color='%s'>%.0ffps</font>  <font color='#c8b4eb'>%.0fMB</font>  <font color='#ebc896'>%s</font>  <font color='#eb96aa'>%d/%d</font>  <font color='#d2d4de'>%s</font>",
				me:GetNetworkPing() * 1000, fps >= 50 and "#aae696" or "#eb7878", fps, Stats:GetTotalMemoryUsageMb(), clock(), #Players:GetPlayers(), Players.MaxPlayers, pos)
		end
		for pl, e in pairs(esp) do
			local c = pl.Character
			local h, hr = c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
			local show = showEsp and h ~= nil and hr ~= nil and h.Health > 0
			e[1].Enabled, e[2].Enabled = show, show
			if show then
				local colr = pl.Team and pl.TeamColor.Color or Color3.fromHSV((pl.UserId * 0.618) % 1, 0.65, 1)
				e[1].Adornee, e[1].FillColor, e[1].OutlineColor = c, colr, colr
				e[2].Adornee, e[3].TextColor3 = hr, colr
				e[3].Text = pl.DisplayName .. (r and string.format(" %.0f", (hr.Position - r.Position).Magnitude) or "")
			end
		end
	end)

	local r1 = row(page)
	toggle(r1, "数据条", showBar, function(v) showBar = v; save("stats", v) end, 0.5)
	toggle(r1, "速度箭头", showArrow, function(v) showArrow = v; save("arrow", v) end, 0.5)
	toggle(page, "玩家 ESP", showEsp, function(v) showEsp = v; save("esp", v) end)
	btn(page, "复制状态", function() setclipboard(Http:JSONEncode(saved)); toast("配置已复制") end)

	INFO.hud = function() return string.format("数据条=%s 箭头=%s ESP=%s", tostring(showBar), tostring(showArrow), tostring(showEsp)) end
	return function() for pl in pairs(esp) do espDrop(pl) end end
end }

-- ═════════ log: 配置 + 各模块状态定时追加到 Selfblox_log.txt ═════════
MODS[#MODS + 1] = { name = "log", tab = "志", fn = function(page)
	local S = { int = opt("logint", 2), max = opt("logmax", 512) }
	local F, run, n, written = "Selfblox_log.txt", false, 0, 0
	local status = text(page, "开 录制 后写 " .. F)
	local function head() local h = "---- Selfblox " .. os.date("%Y-%m-%d ") .. clock(true) .. " ----\n"; writefile(F, h); written = #h end
	task.spawn(function()
		while alive do
			task.wait(S.int)
			if run then
				local L = { "[" .. clock(true) .. "] #" .. n, "配置 " .. Http:JSONEncode(saved) } -- 数值不用各模块自己拼, 这里全有
				for _, m in ipairs(MODS) do if INFO[m.name] then L[#L + 1] = m.name .. " " .. INFO[m.name]() end end
				local txt = table.concat(L, "\n") .. "\n"
				if written == 0 or written + #txt > S.max * 1024 then head() end -- ponytail: 超限直接重写, 不归档; 要历史自己复制文件
				appendfile(F, txt)
				n, written = n + 1, written + #txt
				status.Text = "#" .. n .. " · " .. math.floor(written / 1024) .. "KB / " .. S.max .. "KB"
			end
		end
	end)
	local r1 = row(page)
	num(r1, "间隔s", S, "int", 0.5, "logint")
	num(r1, "上限KB", S, "max", 0.5, "logmax")
	toggle(page, "录制", false, function(v) run = v end)
end }

-- ═════════ plane: 飞机侦察 (找飞机/判队伍/列 Remote/收发侦听/写报告) ═════════
MODS[#MODS + 1] = { name = "plane", tab = "机", fn = function(page)
	local HINT = { "plane", "jet", "aircraft", "fighter", "bomber", "heli", "glider", "warbird", "biplane", "gunship", "blimp" }
	local WING = { "wing", "aileron", "rudder", "elevator", "propeller", "rotor", "flap", "stabilizer", "tailfin" }
	local TEAMK = { "team", "faction", "side", "country", "nation" }
	local RHINT = { "fire", "shoot", "shot", "bullet", "gun", "weapon", "attack", "damage", "hit", "kill", "launch", "missile", "rocket", "bomb", "plane", "spawn", "team", "seat", "pilot" }
	local function hint(name, list) name = name:lower(); for _, h in ipairs(list) do if name:find(h, 1, true) then return h end end end
	local planes, remotes, sent, got, hls, watch = {}, {}, {}, {}, {}, {}
	local spyOn, watchOn, hlOn, autoOn, all, oldNC, status = false, false, false, false, opt("pall", false), nil, nil
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
	local function push(log, s) log[#log + 1] = clock(true) .. " " .. s; if #log > 200 then table.remove(log, 1) end end
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
		return p
	end
	local function highlight()
		for _, h in ipairs(hls) do h:Destroy() end
		table.clear(hls)
		if not hlOn then return end
		for _, p in ipairs(planes) do
			local c = p.mine and Color3.fromRGB(80, 255, 80) or (p.teamObj and me.Team and (p.teamObj == me.Team and Color3.fromRGB(80, 140, 255) or Color3.fromRGB(255, 70, 70))) or Color3.fromRGB(170, 170, 170)
			hls[#hls + 1] = mk("Highlight", { Adornee = p.model, FillColor = c, OutlineColor = c, FillTransparency = 0.75 }, FX)
		end
	end
	local function setWatch(v)
		watchOn = v
		for _, c in ipairs(watch) do c:Disconnect() end
		table.clear(watch)
		if not v then return end
		for _, r in ipairs(remotes) do
			if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") then
				watch[#watch + 1] = r.OnClientEvent:Connect(function(...) push(got, r:GetFullName() .. " <- " .. args(table.pack(...))) end)
			end
		end
	end
	local function setSpy(v)
		if v and not oldNC then
			oldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
				local m = getnamecallmethod()
				if spyOn and (m == "FireServer" or m == "InvokeServer") then
					local a = table.pack(...)
					pcall(function() local path = self:GetFullName(); if all or hint(path, RHINT) then push(sent, path .. ":" .. m .. " " .. args(a)) end end) -- 记录失败不能拦住游戏自己的调用
				end
				return oldNC(self, ...)
			end))
		end
		spyOn = v
		return true
	end
	local function scan()
		table.clear(planes)
		table.clear(remotes)
		local seen = {}
		local function remote(d) if isRemote(d) and (all or hint(d:GetFullName(), RHINT)) then remotes[#remotes + 1] = d end end
		for _, d in ipairs(workspace:GetDescendants()) do
			remote(d)
			if d:IsA("Seat") or d:IsA("VehicleSeat") then -- 有座位的最外层 Model 才是候选
				local m = d:FindFirstAncestorOfClass("Model")
				while m and m.Parent and m.Parent:IsA("Model") do m = m.Parent end -- ponytail: 全部飞机套在一个 Model 里会被并成一架
				if m and not seen[m] and not m:FindFirstChildOfClass("Humanoid") then
					seen[m] = true
					local p = inspect(m)
					if p.score >= 55 then planes[#planes + 1] = p end
				end
			end
		end
		for _, d in ipairs(RS:GetDescendants()) do remote(d) end
		table.sort(planes, function(a, b) return a.score > b.score end)
		if watchOn then setWatch(true) end
		highlight()
		status.Text = "飞机 " .. #planes .. " · Remote " .. #remotes .. " · 发 " .. #sent .. " 收 " .. #got
	end
	local function report()
		local L = { "==== PLANE " .. os.date("%Y-%m-%d ") .. clock(true) .. " place=" .. game.PlaceId .. " me=" .. me.Name .. " team=" .. (me.Team and me.Team.Name or "-") .. " ====", "-- 飞机 " .. #planes }
		for _, p in ipairs(planes) do
			L[#L + 1] = "[" .. p.score .. "] " .. p.path .. (p.mine and " ★我" or "") .. " | 座:" .. (p.seat and "有" or "无") .. " 翼:" .. p.wings .. " 件:" .. p.parts .. " | 队:" .. p.team .. "(" .. p.src .. ")" .. (p.occ and " 乘员:" .. p.occ.Name or "")
			for k, v in pairs(p.model:GetAttributes()) do L[#L + 1] = "    attr " .. k .. "=" .. fmt(v) end
			for _, r in ipairs(p.remotes) do L[#L + 1] = "    " .. r.ClassName .. " " .. r:GetFullName() end
		end
		L[#L + 1] = "-- Remote " .. #remotes
		for _, r in ipairs(remotes) do L[#L + 1] = "  " .. r.ClassName .. " " .. r:GetFullName() end
		L[#L + 1] = "-- 发 " .. #sent
		for _, s in ipairs(sent) do L[#L + 1] = "  " .. s end
		L[#L + 1] = "-- 收 " .. #got
		for _, s in ipairs(got) do L[#L + 1] = "  " .. s end
		local txt = table.concat(L, "\n")
		writefile("plane_debug.txt", txt)
		setclipboard(txt)
		toast("报告 " .. #L .. " 行 → plane_debug.txt / 剪贴板")
	end

	local r1 = row(page)
	btn(r1, "重扫", scan, 0.5)
	btn(r1, "写报告", report, 0.5)
	local r2 = row(page)
	toggle(r2, "发侦听", false, setSpy, 0.5)
	toggle(r2, "收侦听", false, setWatch, 0.5)
	local r3 = row(page)
	toggle(r3, "高亮", false, function(v) hlOn = v; highlight() end, 0.5)
	toggle(r3, "自动 5s", false, function(v) autoOn = v end, 0.5)
	local r4 = row(page)
	toggle(r4, "全录", all, function(v) all = v; save("pall", v) end, 0.5)
	btn(r4, "清空记录", function() table.clear(sent); table.clear(got) end, 0.5)
	status = text(page, "上机 → 发侦听 → 开几枪 → 写报告")
	task.spawn(function() while alive do task.wait(5); if autoOn and alive then scan(); report() end end end)

	INFO.plane = function() return "飞机=" .. #planes .. " Remote=" .. #remotes .. " 发=" .. #sent .. " 收=" .. #got .. " 侦听=" .. tostring(spyOn) end
	return function() setWatch(false); hlOn = false; highlight(); if oldNC then hookmetamethod(game, "__namecall", oldNC) end end
end }

-- ═════════ brick: BitFarmer 刷砖 ═════════
MODS[#MODS + 1] = { name = "brick", tab = "砖", fn = function(page)
	local S = { batch = opt("bbatch", 4), int = opt("bint", 0.08), drain = opt("bdrain", 0.6), mult = opt("bmult", 99999), lvl = opt("blevel", 9999) }
	local run, setRun, status = false, nil, nil
	local st = { cycles = 0, earned = 0, sent = 0, got = 0, rate = 0 }
	local function mine(c) return c:IsA("BasePart") and not c.Anchored and c:GetAttribute("Owner") == me.UserId end
	local function ingest(b, col) b.CFrame = col.CFrame + Vector3.new(math.random(-3, 3), 1.5, math.random(-3, 3)); b.AssemblyLinearVelocity = Vector3.new(0, -35, 0) end
	local function loop()
		local ls = me:FindFirstChild("leaderstats")
		local col, spawnBit = workspace:FindFirstChild("Collector"), RS:FindFirstChild("SpawnBit")
		local bits, mult = ls and ls:FindFirstChild("Bits"), ls and ls:FindFirstChild("Multiplier")
		if not (col and bits) then setRun(false); toast("没找到 workspace.Collector / leaderstats.Bits"); return end
		local mult0, lvl0 = mult and mult.Value, me:GetAttribute("MultiplierUpgradeLevel")
		local last, lastT = bits.Value, os.clock()
		local conn = workspace.ChildAdded:Connect(function(c) task.defer(function() if run and mine(c) then ingest(c, col); st.got = st.got + 1 end end) end)
		local function drain() for _, c in ipairs(workspace:GetChildren()) do if mine(c) then ingest(c, col) end end end
		while run and alive do
			st.cycles = st.cycles + 1
			local before = bits.Value
			drain()
			if spawnBit then for _ = 1, S.batch do if not run then break end; spawnBit:FireServer(); st.sent = st.sent + 1; task.wait(S.int) end end
			task.wait(S.drain)
			drain()
			st.earned = st.earned + math.max(bits.Value - before, 0)
			local t = os.clock()
			if t - lastT >= 1 then st.rate = (bits.Value - last) / (t - lastT); last, lastT = bits.Value, t end
			if mult and mult.Value < S.mult then mult.Value = S.mult end
			me:SetAttribute("MultiplierUpgradeLevel", S.lvl)
			status.Text = string.format("周期 %d · +%.0f · %.1f/s · 发 %d 收 %d", st.cycles, st.earned, st.rate, st.sent, st.got)
			task.wait(0.15)
		end
		conn:Disconnect()
		if mult and mult0 then mult.Value = mult0 end
		me:SetAttribute("MultiplierUpgradeLevel", lvl0)
	end
	setRun = toggle(page, "刷砖", false, function(v) run = v; if v then task.spawn(loop) end end)
	local r1 = row(page)
	num(r1, "批次", S, "batch", 0.5, "bbatch")
	num(r1, "间隔", S, "int", 0.5, "bint")
	local r2 = row(page)
	num(r2, "排空间隔", S, "drain", nil, "bdrain")
	status = text(page, "BitFarmer 专用")

	INFO.brick = function() return string.format("刷=%s 周期=%d 已刷=%.0f 速率=%.1f/s", tostring(run), st.cycles, st.earned, st.rate) end
	return function() run = false end
end }

-- ───────── 启动: 建页签 + 各模块页; _G.SB.only = {"moc","sibs"} 只装一部分 ─────────
local only, active, pages, tabBtns = opt("only", nil), {}, {}, {}
for _, m in ipairs(MODS) do if type(only) ~= "table" or table.find(only, m.name) then active[#active + 1] = m end end
local function show(name)
	for n, pg in pairs(pages) do pg.Visible = n == name; tabBtns[n].BackgroundColor3 = n == name and ON or OFF end
	save("tab", name)
end
for _, m in ipairs(active) do
	local page = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = false, LayoutOrder = ord() }, body)
	mk("UIListLayout", { Padding = UDim.new(0, 1) }, page)
	pages[m.name] = page
	tabBtns[m.name] = btn(tabs, m.tab, function() show(m.name) end, 1 / #active)
	local ok, stop = pcall(m.fn, page) -- 一个模块炸了不拖死其他模块
	if ok then stops[#stops + 1] = stop else warn("[Selfblox] " .. m.name .. ": " .. tostring(stop)); text(page, "出错: " .. tostring(stop)) end
end
if #active > 0 then show(pages[opt("tab", "moc")] and opt("tab", "moc") or active[1].name) end

_G.SB_UNLOAD = function()
	alive = false
	for _, s in ipairs(stops) do pcall(s) end -- 一个模块清理炸了不能拦住其他的
	for _, c in ipairs(conns) do c:Disconnect() end
	gui:Destroy()
	FX:Destroy()
	_G.SB_UNLOAD = nil
end
print("[Selfblox] v13 · " .. #active .. " 模块 · _G.SB_UNLOAD() 卸载")
