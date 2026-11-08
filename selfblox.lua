-- Selfblox · 单文件 · 一次 loadstring · 一个面板 · 八个模块
-- 用法:  loadstring(game:HttpGet("https://raw.githubusercontent.com/Sumicya/Selfblox/main/selfblox.lua"))()
-- 覆盖:  执行前 _G.SB = { spd = 50, flyspd = 80, only = {"moc", "sibs"} }   键名 = 各模块 opt("键", 默认) 的第一个参数
-- 优先级: _G.SB > Selfblox.json(面板里改过的值) > 默认值
-- 卸载:  _G.SB_UNLOAD()   重跑会自动先卸载

if rawget(_G, "SB_UNLOAD") then pcall(_G.SB_UNLOAD) end

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
local ROOT = (pcall(gethui) and gethui()) or game:GetService("CoreGui")

-- ───────── 配置: _G.SB 覆盖 > JSON > 默认 ─────────
local O = type(rawget(_G, "SB")) == "table" and _G.SB or {}
local FILE, saved = "Selfblox.json", {}
if isfile and isfile(FILE) then pcall(function() saved = Http:JSONDecode(readfile(FILE)) end) end
local function opt(k, d) local v = O[k]; if v == nil then v = saved[k] end; if v == nil then v = d end; return v end
local function save(k, v)
	saved[k] = v
	if writefile then
		local ok, err = pcall(function() writefile(FILE, Http:JSONEncode(saved)) end)
		if not ok then warn("[Selfblox] 配置保存失败: " .. tostring(err)) end
	end
end

-- ───────── 公共 ─────────
local alive, conns, DBG, MODS, stops = true, {}, {}, {}, {}
local heldReleases = {}
local function on(sig, fn) local c = sig:Connect(fn); conns[#conns + 1] = c; return c end
local function mk(cls, props, parent) local i = Instance.new(cls); for k, v in pairs(props) do i[k] = v end; i.Parent = parent; return i end
local function tap(i) return i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 end
local function hum() local c = me.Character; return c and c:FindFirstChildOfClass("Humanoid") end
local function root() local c = me.Character; return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Root")) end
local function flat(v) v = Vector3.new(v.X, 0, v.Z); return v.Magnitude > 1e-3 and v.Unit or nil end
local function hint(name, list) name = name:lower(); for _, h in ipairs(list) do if name:find(h, 1, true) then return h end end end
local function idx(t, k) return t[k] end
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
local function push(log, s) log[#log + 1] = os.date("%H:%M:%S ") .. s; if #log > 200 then table.remove(log, 1) end end

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
local function num(parent, s, get, set, w) -- 标签 + 数字框; s=nil 只有框
	local f = ui("TextLabel", parent, w, { Text = s and " " .. s or "", TextXAlignment = Enum.TextXAlignment.Left })
	local tb = mk("TextBox", { Size = UDim2.new(s and 0.5 or 1, 0, 1, 0), Position = UDim2.new(s and 0.5 or 0, 0, 0, 0), BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = Color3.fromRGB(255, 225, 140), Text = tostring(get()), ClearTextOnFocus = false }, f)
	on(tb.FocusLost, function() local v = tonumber(tb.Text); if v then set(v) end; tb.Text = tostring(get()) end)
end
local function hold(parent, s, fn, w) -- 全局 InputEnded 兜底，避免指针移出按钮后卡住
	local b, held, input = ui("TextButton", parent, w, { Text = s, AutoButtonColor = false }), false, nil
	local function release(i)
		if held and (i == nil or i == input) then -- 只释放按下它的那根手指, 多指触屏不互相串
			held, input = false, nil
			if b.Parent then b.BackgroundColor3 = OFF end
			pcall(fn, false)
		end
	end
	heldReleases[#heldReleases + 1] = function() release(nil) end
	on(b.InputBegan, function(i) if tap(i) and not held then held, input = true, i; b.BackgroundColor3 = ON; pcall(fn, true) end end)
	on(b.InputEnded, release)
	on(UIS.InputEnded, release)
	on(UIS.WindowFocusReleased, function() release(nil) end)
end

-- ───────── 共享 __namecall 钩子: 各模块登记 handler, 最后一个撤掉时才还原, 避免多模块互相覆盖 ─────────
local ncHandlers, ncRaw = {}, nil
local function ncDispatch(self, m, ...)
	for id, h in pairs(ncHandlers) do
		if h.methods[m] then
			local ok, rep = pcall(h.fn, self, m, ...)
			if ok and rep ~= nil then return table.unpack(rep, 1, rep.n) end
			if not ok and not h.warned then h.warned = true; warn("[Selfblox] namecall handler " .. id .. ": " .. tostring(rep)) end
		end
	end
	local ok, f = pcall(idx, self, m) -- 直接取方法原函数调用, 不依赖执行器对 namecall 寄存器的保持
	if ok and type(f) == "function" then return f(self, ...) end
	return ncRaw(self, ...)
end
local function ncAdd(id, methods, fn)
	ncHandlers[id] = { methods = methods, fn = fn }
	if not ncRaw then
		if not (hookmetamethod and getnamecallmethod) then ncHandlers[id] = nil; return false end
		local wrap = newcclosure or function(f) return f end
		ncRaw = hookmetamethod(game, "__namecall", wrap(function(self, ...)
			return ncDispatch(self, getnamecallmethod(), ...)
		end))
	end
	return true
end
local function ncDel(id)
	ncHandlers[id] = nil
	if ncRaw and next(ncHandlers) == nil then
		hookmetamethod(game, "__namecall", ncRaw)
		ncRaw = nil
	end
end

local camera = workspace.CurrentCamera
local vp = camera and camera.ViewportSize or Vector2.new(800, 600)
local pos = opt("pos", { vp.X / 2 - W / 2, vp.Y * 0.3 })
local title = mk("TextLabel", { Size = UDim2.fromOffset(W, ROW), Position = UDim2.fromOffset(math.clamp(pos[1], 0, math.max(vp.X - W, 0)), math.clamp(pos[2], 0, math.max(vp.Y - ROW, 0))), BackgroundColor3 = BG, BackgroundTransparency = 0.15, BorderSizePixel = 0, Font = FONT, TextSize = 13, TextColor3 = WHITE, Text = "Selfblox" }, gui)
local body = mk("Frame", { Size = UDim2.new(0, W, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = title.Position + UDim2.fromOffset(0, ROW), BackgroundColor3 = BG, BackgroundTransparency = 0.35, BorderSizePixel = 0 }, gui)
mk("UIListLayout", { Padding = UDim.new(0, 1) }, body)
on(title:GetPropertyChangedSignal("Position"), function() body.Position = title.Position + UDim2.fromOffset(0, ROW) end)
local okDrag, drag = pcall(mk, "UIDragDetector", { BoundingUI = gui }, title) -- 老客户端没这个类就不能拖
if okDrag then on(drag.DragEnd, function() save("pos", { title.AbsolutePosition.X, title.AbsolutePosition.Y }) end) end
local fold = mk("TextButton", { Size = UDim2.fromOffset(ROW, ROW), Position = UDim2.new(1, -ROW, 0, 0), BackgroundTransparency = 1, Font = FONT, TextSize = 16, TextColor3 = WHITE, Text = "–" }, title)
on(fold.Activated, function() body.Visible = not body.Visible; fold.Text = body.Visible and "–" or "+" end)
local tabs = row(body)

local toastL = mk("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = BG, BackgroundTransparency = 0.2, BorderSizePixel = 0, Font = FONT, TextSize = 13, TextColor3 = WHITE, Visible = false }, gui)
mk("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, toastL)
local toastN = 0
local function toast(s)
	if not alive or not toastL.Parent then return end
	toastN = toastN + 1
	local n = toastN
	toastL.Text, toastL.Visible = s, true
	task.delay(2, function() if alive and toastN == n and toastL.Parent then toastL.Visible = false end end)
end

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
	local function restoreSpeed() local h = hum(); local b = h and base[h]; if b then h.WalkSpeed = b[1] end end
	local function restoreJump() local h = hum(); local b = h and base[h]; if b then h.JumpPower, h.JumpHeight = b[2], b[3] end end
	local function restore() restoreSpeed(); restoreJump() end
	local function attach(r) -- 飞行/旋转的约束都挂在这一个 Attachment 下, 删它就全删
		if not att or att.Parent ~= r then if att then att:Destroy() end; att = mk("Attachment", { Name = "SB_MOC" }, r); flyLV, flyAO, spinAV = nil, nil, nil end
		return att
	end
	local function stopFly() if flyLV then flyLV:Destroy(); flyAO:Destroy(); flyLV, flyAO = nil, nil end; local h = hum(); if h then h.PlatformStand = false end end
	local function doFly(r, h)
		local cam = workspace.CurrentCamera
		if not cam then return end
		local a = attach(r)
		if not flyLV then
			flyLV = mk("LinearVelocity", { Attachment0 = a, MaxForce = math.huge, VectorVelocity = Vector3.zero, RelativeTo = Enum.ActuatorRelativeTo.World }, a)
			flyAO = mk("AlignOrientation", { Attachment0 = a, Mode = Enum.OrientationAlignmentMode.OneAttachment, MaxTorque = math.huge, Responsiveness = 200 }, a)
			h.PlatformStand = true
		end
		local cam, md = cam.CFrame, h.MoveDirection
		local look = flat(cam.LookVector) or Vector3.zAxis
		-- 水平跟摇杆, 前后分量带上相机俯仰, 上升/下降按钮叠加
		flyLV.VectorVelocity = md * S.fly + Vector3.yAxis * (S.fly * (cam.LookVector.Y * md:Dot(look) + (up and 1 or 0) - (down and 1 or 0)))
		flyAO.CFrame = CFrame.lookAt(Vector3.zero, look)
	end
	local ctrl, ctrlT = nil, -1e9
	local function cframeMoveVector()
		-- CFrame 模式直接读控制模块的原始输入；MoveDirection 在部分角色状态下会残留非零值。
		if not ctrl and os.clock() - ctrlT > 1 then
			ctrlT = os.clock()
			local ps = me:FindFirstChildOfClass("PlayerScripts")
			local pm = ps and ps:FindFirstChild("PlayerModule")
			if pm then
				pcall(function()
					local module = require(pm)
					local controls = module and module:GetControls()
					if controls and controls.GetMoveVector then ctrl = controls end
				end)
			end
		end
		if not ctrl then return Vector3.zero end
		local ok, mv = pcall(function() return ctrl:GetMoveVector() end)
		if not ok or typeof(mv) ~= "Vector3" then ctrl, ctrlT = nil, os.clock(); return Vector3.zero end
		if mv.Magnitude <= 1e-4 then return Vector3.zero end
		local cam = workspace.CurrentCamera
		if not cam then return Vector3.zero end
		local cf = cam.CFrame
		local world = Vector3.new(cf.RightVector.X * mv.X - cf.LookVector.X * mv.Z, 0, cf.RightVector.Z * mv.X - cf.LookVector.Z * mv.Z)
		return world.Magnitude > 1e-4 and world.Unit or Vector3.zero
	end
	local function doSpeed(r, h, dt)
		if S.mode == "walk" then
			baseOf(h); h.WalkSpeed = S.spd
		elseif S.mode == "cframe" then
			local md = cframeMoveVector()
			-- CFrame 驱动时每帧清水平动量，避免松手后物理速度继续带动角色。
			local v = r.AssemblyLinearVelocity
			r.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
			if md.Magnitude > 0 then r.CFrame = r.CFrame + md * (S.spd * dt) end
		else -- root: 直接写水平速度, 松摇杆归零一次
			local md = h.MoveDirection
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
		nvSaved = nvSaved or { Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.Brightness, Lighting.FogEnd, Lighting.GlobalShadows, atm and atm.Density, atm }
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
		if atm and atm == nvSaved[7] and nvSaved[6] ~= nil then atm.Density = nvSaved[6] end
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
	toggle(r1, "速度", false, function(v)
		speedOn, moving = v, false
		if not v then
			if S.mode == "cframe" then local r = root(); if r then local vel = r.AssemblyLinearVelocity; r.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0) end end
			restoreSpeed()
		end
	end, 0.5)
	num(r1, nil, function() return S.spd end, function(v) S.spd = v; save("spd", v) end, 0.5)
	local MODES = { root = "walk", walk = "cframe", cframe = "root" }
	btn(page, "模式 " .. S.mode, function(b)
		if S.mode == "cframe" then local r = root(); if r then local vel = r.AssemblyLinearVelocity; r.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0) end end
		restoreSpeed(); moving = false; S.mode = MODES[S.mode] or "root"; save("spdmode", S.mode); b.Text = "模式 " .. S.mode
	end)
	local r2 = row(page)
	setFly = toggle(r2, "飞行", false, function(v) flyOn = v; if not v then stopFly() end end, 0.5)
	num(r2, nil, function() return S.fly end, function(v) S.fly = v; save("flyspd", v) end, 0.5)
	local r3 = row(page)
	toggle(r3, "高跳", false, function(v) jumpOn = v; if not v then restoreJump() end end, 0.5)
	num(r3, nil, function() return S.jump end, function(v) S.jump = v; save("jump", v) end, 0.5)
	local r4 = row(page)
	toggle(r4, "旋转", false, function(v) spinOn = v; if not v then stopSpin() end end, 0.5)
	num(r4, nil, function() return S.spin end, function(v) S.spin = v; save("spin", v) end, 0.5)
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

	DBG.moc = function() return "speed=" .. tostring(speedOn) .. "/" .. S.mode .. "/" .. S.spd .. " fly=" .. tostring(flyOn) .. " jump=" .. tostring(jumpOn) .. " spin=" .. tostring(spinOn) .. " clip=" .. tostring(clip) .. " nv=" .. tostring(nv) .. " nocd=" .. nocd end
	return function() setFly(false); stopSpin(); reclip(); restore(); nvOff(); setNocd("off"); if att then att:Destroy() end end
end }

-- ═════════ gun: 武器 (无限子弹 / 子弹穿墙 / 探针报告; 字段自动扫, 游戏无关) ═════════
MODS[#MODS + 1] = { name = "gun", tab = "枪", fn = function(page)
	local S = { amount = opt("ammo", 999), pierce = opt("pierce", 16) }
	local AK = { "ammo", "clip", "magazine", "cartridge" } -- 弹药字段名 hint (不匹配伤害/射速等调参字段)
	local infOn, wallOn, hooked, status = false, false, false, nil
	local vals = setmetatable({}, { __mode = "k" }) -- NumberValue/IntValue -> 原值
	local attrs = setmetatable({}, { __mode = "k" }) -- Instance -> { key = 原值 }
	local tbls = setmetatable({}, { __mode = "k" }) -- 配置表 -> { key = 原值 }
	local stat = { refills = 0, fields = 0, rays = 0, pierced = 0 }

	local function isAmmoName(n) return hint(n, AK) ~= nil end
	local function containers() -- 只扫武器相关容器: 手持/背包 Tool + leaderstats; 弹药 GUI 按需再加
		local out, seen = {}, {}
		local function add(i) if i and not seen[i] then seen[i] = true; out[#out + 1] = i end end
		local c = me.Character
		if c then for _, d in ipairs(c:GetChildren()) do if d:IsA("Tool") then add(d) end end end
		local bp = me:FindFirstChildOfClass("Backpack")
		if bp then for _, d in ipairs(bp:GetChildren()) do if d:IsA("Tool") then add(d) end end end
		add(me:FindFirstChild("leaderstats"))
		return out
	end
	local function trackVal(v)
		if vals[v] == nil and (v:IsA("IntValue") or v:IsA("NumberValue")) and isAmmoName(v.Name) then vals[v] = v.Value; stat.fields = stat.fields + 1 end
	end
	local function trackAttrs(i)
		if not (i:IsA("Tool") or i:IsA("Model") or i:IsA("Folder") or i:IsA("Configuration")) then return end
		for k, x in pairs(i:GetAttributes()) do
			if type(x) == "number" and isAmmoName(k) then
				local t = attrs[i]; if not t then t = {}; attrs[i] = t end
				if t[k] == nil then t[k] = x; stat.fields = stat.fields + 1 end
			end
		end
	end
	local function scan(deep)
		for _, c in ipairs(containers()) do
			trackAttrs(c)
			for _, d in ipairs(c:GetDescendants()) do trackVal(d); trackAttrs(d) end
		end
		if deep and getgc then -- 深改只在开关/重扫时跑: getgc 全量遍历太贵, 不进每帧循环
			local ok, gc = pcall(getgc, true)
			if ok and type(gc) == "table" then
				for _, o in ipairs(gc) do
					if type(o) == "table" and o ~= _G and o ~= shared and getmetatable(o) == nil and tbls[o] == nil then
						local keys, hitK, bad = 0, false, false
						for k, x in pairs(o) do
							keys = keys + 1
							if keys > 64 then bad = true; break end
							if type(k) == "string" and type(x) == "number" and k:lower():find("ammo", 1, true) then hitK = true end
						end
						if hitK and not bad then
							local t = {}
							for k, x in pairs(o) do if type(k) == "string" and type(x) == "number" and k:lower():find("ammo", 1, true) then t[k] = x end end
							tbls[o] = t; stat.fields = stat.fields + 1
						end
					end
				end
			end
		end
	end
	local function refill()
		for v in pairs(vals) do
			if v.Parent then
				if v.Value < S.amount then local ok = pcall(function() v.Value = S.amount end); if ok then stat.refills = stat.refills + 1 end end
			else vals[v] = nil end
		end
		for i, t in pairs(attrs) do
			if i.Parent then
				for k in pairs(t) do
					if (i:GetAttribute(k) or S.amount) < S.amount then
						local ok = pcall(function() i:SetAttribute(k, S.amount) end)
						if ok then stat.refills = stat.refills + 1 end
					end
				end
			else attrs[i] = nil end
		end
		for o, t in pairs(tbls) do for k in pairs(t) do if type(o[k]) == "number" and o[k] < S.amount then if pcall(function() o[k] = S.amount end) then stat.refills = stat.refills + 1 end end end end
	end
	local function restore()
		for v, orig in pairs(vals) do if v.Parent then pcall(function() v.Value = orig end) end end
		for i, t in pairs(attrs) do if i.Parent then for k, x in pairs(t) do pcall(function() i:SetAttribute(k, x) end) end end end
		for o, t in pairs(tbls) do for k, x in pairs(t) do pcall(function() o[k] = x end) end end
		table.clear(vals); table.clear(attrs); table.clear(tbls)
		stat.fields = 0
	end

	-- 穿墙: 只拦游戏脚本发起的 workspace.Raycast (checkcaller 滤掉执行器脚本); 内部用点调用绕过 namecall, 天然无递归
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local function isChar(p)
		local m = p and p:FindFirstAncestorOfClass("Model")
		return m and m:FindFirstChildOfClass("Humanoid") ~= nil
	end
	local function pierceCast(origin, dir, params)
		local res = workspace.Raycast(workspace, origin, dir, params) -- 点调用不走 __namecall
		stat.rays = stat.rays + 1
		if not res or isChar(res.Instance) then return res end
		local exclude, left = {}, math.floor(S.pierce)
		rp.IgnoreWater, rp.CollisionGroup = true, "Default"
		if params then
			if params.FilterType == Enum.RaycastFilterType.Include then return res end -- 白名单射线语义不能改
			rp.IgnoreWater, rp.CollisionGroup = params.IgnoreWater, params.CollisionGroup
			for _, i in ipairs(params.FilterDescendantsInstances) do exclude[#exclude + 1] = i end
		end
		while res and left > 0 and not isChar(res.Instance) do
			exclude[#exclude + 1] = res.Instance
			rp.FilterDescendantsInstances = exclude
			res = workspace.Raycast(workspace, origin, dir, rp)
			left = left - 1
			stat.pierced = stat.pierced + 1
		end
		if res and not isChar(res.Instance) then return nil end -- 穿完仍没打到人: 按未命中处理
		return res
	end
	local function setWall(v)
		if v then
			if not hooked then
				if not ncAdd("gun", { Raycast = true }, function(self, m, origin, dir, params)
					if self ~= workspace or not wallOn then return end
					if checkcaller and checkcaller() then return end
					if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" then return end
					local ok, res = pcall(pierceCast, origin, dir, params)
					if ok then return table.pack(res) end
					warn("[Selfblox] gun raycast: " .. tostring(res))
				end) then
					toast("执行器没有 hookmetamethod")
					return false
				end
				hooked = true
			end
			wallOn = true
		else
			wallOn = false
			if hooked then ncDel("gun"); hooked = false end
		end
		return true
	end

	local acc = 0
	on(RunService.PreSimulation, function(dt)
		acc = acc + dt
		if acc < 0.25 then return end
		acc = 0
		if infOn then scan(); refill() end
		if status and status.Parent then status.Text = string.format("字段 %d · 回填 %d · 射线 %d(穿 %d)", stat.fields, stat.refills, stat.rays, stat.pierced) end
	end)

	local r1 = row(page)
	toggle(r1, "无限子弹", false, function(v)
		infOn = v
		if v then scan(true); refill() else restore() end
	end, 0.5)
	num(r1, nil, function() return S.amount end, function(v) S.amount = math.max(1, v); save("ammo", S.amount) end, 0.5)
	local r2 = row(page)
	local wallT
	wallT = toggle(r2, "子弹穿墙", false, function(v)
		if not setWall(v) then wallT(false, true) end
	end, 0.5)
	num(r2, nil, function() return S.pierce end, function(v) S.pierce = math.max(1, math.floor(v)); save("pierce", S.pierce) end, 0.5)
	local r3 = row(page)
	btn(r3, "重扫字段", function()
		if not infOn then toast("先开 无限子弹"); return end
		local ok, err = pcall(function() scan(true); refill() end)
		toast(ok and ("字段 " .. stat.fields) or ("扫描失败: " .. tostring(err)))
	end, 0.5)
	btn(r3, "探针报告", function()
		local L = { "==== GUN " .. os.date("%Y-%m-%d %H:%M:%S") .. " place=" .. game.PlaceId .. " ====" }
		L[#L + 1] = string.format("inf=%s wall=%s amount=%d pierce=%d fields=%d refills=%d rays=%d pierced=%d", tostring(infOn), tostring(wallOn), S.amount, S.pierce, stat.fields, stat.refills, stat.rays, stat.pierced)
		L[#L + 1] = "-- 执行器: hookmetamethod=" .. tostring(hookmetamethod ~= nil) .. " getgc=" .. tostring(getgc ~= nil) .. " hookfunction=" .. tostring(hookfunction ~= nil)
		L[#L + 1] = "-- 当前跟踪字段"
		for v, orig in pairs(vals) do if v.Parent then L[#L + 1] = "  " .. v:GetFullName() .. " = " .. tostring(v.Value) .. " (原 " .. tostring(orig) .. ")" end end
		for i, t in pairs(attrs) do if i.Parent then for k, x in pairs(t) do L[#L + 1] = "  attr " .. i:GetFullName() .. "." .. k .. " = " .. tostring(i:GetAttribute(k)) .. " (原 " .. tostring(x) .. ")" end end end
		for _, t in pairs(tbls) do for k, x in pairs(t) do L[#L + 1] = "  tbl " .. k .. " (原 " .. tostring(x) .. ")" end end
		L[#L + 1] = "-- 手持工具"
		local c = me.Character
		if c then for _, d in ipairs(c:GetChildren()) do if d:IsA("Tool") then
			L[#L + 1] = "  " .. d:GetFullName()
			for k, x in pairs(d:GetAttributes()) do L[#L + 1] = "    attr " .. k .. "=" .. fmt(x) end
			for _, v in ipairs(d:GetDescendants()) do if v:IsA("ValueBase") then L[#L + 1] = "    " .. v.ClassName .. " " .. v.Name .. "=" .. fmt(v.Value) end end
		end end end
		local txt = table.concat(L, "\n")
		local savedOk = false
		if writefile then local ok, err = pcall(function() writefile("gun_debug.txt", txt) end); savedOk = ok; if not ok then warn("[Selfblox] 枪械报告写入失败: " .. tostring(err)) end end
		if setclipboard then pcall(function() setclipboard(txt) end) end
		toast("报告 " .. #L .. " 行" .. (savedOk and " → gun_debug.txt" or "（文件写入失败）"))
	end, 0.5)
	status = text(page, "拿上武器 → 开无限子弹; 没效果就发探针报告")

	DBG.gun = function() return string.format("inf=%s wall=%s fields=%d refills=%d rays=%d pierced=%d", tostring(infOn), tostring(wallOn), stat.fields, stat.refills, stat.rays, stat.pierced) end
	return function() infOn = false; setWall(false); restore() end
end }

-- ═════════ sibs: 载具 (坐着 = 控制座位所在装配体; 没坐 = 准星"换车"锁定) ═════════
MODS[#MODS + 1] = { name = "sibs", tab = "车", fn = function(page)
	local S = { acc = opt("acc", 500), grip = opt("grip", 5), turn = opt("turn", 2.2), turncap = math.max(0, math.min(5, tonumber(opt("turncap", 1)) or 1)), carmaxstuds = math.max(1, math.min(10000, tonumber(opt("carmaxstuds", 150)) or 150)), fly = opt("carfly", 60), horn = opt("hornkey", "H") }
	local picked, pickSeat, curSeat, clipModel, att, vf, lv, status
	local accel, decel, up, down, cruise, brake, flying, lampOn = false, false, false, false, false, false, false, false
	local clip, target, statT, setBrake = opt("carclip", false), 0, 0, nil
	local lamps, lampSaved = {}, setmetatable({}, { __mode = "k" })
	local lampFlashGeneration = 0
	local seatMax = setmetatable({}, { __mode = "k" })
	local col = setmetatable({}, { __mode = "k" })
	local function restoreSeatMax(s)
		local original = s and seatMax[s]
		if original ~= nil then
			if s.MaxSpeed == math.huge then pcall(function() s.MaxSpeed = original end) end
			seatMax[s] = nil
		end
	end
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
		att = mk("Attachment", { Name = "SB_SIBS" }, p)
		vf = mk("VectorForce", { Attachment0 = att, Force = Vector3.zero, RelativeTo = Enum.ActuatorRelativeTo.World, ApplyAtCenterOfMass = true }, att)
		lv = nil
	end
	local function detach() if att then att:Destroy(); att, vf, lv = nil, nil, nil end end
	local function reclip() for d in pairs(col) do if d.Parent then d.CanCollide = true end end; table.clear(col); clipModel = nil end
	local function noclip(p, m)
		if m ~= clipModel then reclip(); clipModel = m end
		if not p then return end
		local function disable(d)
			if d:IsA("BasePart") and not d.Anchored and d.CanCollide then col[d] = true; d.CanCollide = false end
		end
		disable(p)
		for _, d in ipairs(p:GetConnectedParts(true)) do disable(d) end -- 只处理本车物理装配体, 不扫整个 Model 容器
	end
	local function hover(p, m) -- 穿墙时探地: 贴地推起 / 带内止跌, 坠得快探得远
		rp.FilterDescendantsInstances = { m or p, me.Character }
		local v, half = p.AssemblyLinearVelocity, p.Size.Y / 2
		local hit = workspace.Raycast(workspace, p.Position, Vector3.new(0, -(half + 3 + math.max(6, -v.Y * 0.05)), 0), rp) -- 点调用: 不被 gun 穿墙钩子改写
		if not hit then return end
		local d = hit.Distance - half
		if d < 1 then p.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y, (1 - d) * 10), v.Z)
		elseif d < 3 and v.Y < 0 then p.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z) end
	end
	local function dropLamps() for _, l in ipairs(lamps) do if lampSaved[l] ~= nil then l.Enabled = lampSaved[l] else l:Destroy() end end; table.clear(lamps) end
	local function setLamps(v)
		local p, s = part()
		local m = model()
		if v and #lamps == 0 and m then
			for _, d in ipairs(m:GetDescendants()) do if d:IsA("Light") then lampSaved[d] = d.Enabled; lamps[#lamps + 1] = d end end
			if #lamps == 0 then -- 车上没灯: 前白后红各一只
				lamps[1] = mk("SpotLight", { Brightness = 14, Range = 160, Angle = 85, Face = Enum.NormalId.Front }, s or p)
				lamps[2] = mk("SpotLight", { Brightness = 8, Range = 80, Angle = 75, Face = Enum.NormalId.Back, Color = Color3.fromRGB(255, 40, 40) }, s or p)
			end
		end
		for _, l in ipairs(lamps) do l.Enabled = v end
	end
	local function horn(v) pcall(function() VIM:SendKeyEvent(v, Enum.KeyCode[S.horn], false, game) end) end -- 执行器可能禁 VIM
	local function asmDims(r) -- 量装配体而非 Model 容器, 避免把整条街误判成车
		local span, origin = 0.5 * r.Size.Magnitude, r.Position
		for _, d in ipairs(r:GetConnectedParts(true)) do
			local extent = (d.Position - origin).Magnitude + 0.5 * d.Size.Magnitude
			if extent > span then span = extent end
		end
		return span * 2
	end
	local function pick()
		local cam = workspace.CurrentCamera
		if not cam then toast("相机尚未就绪"); return end
		rp.FilterDescendantsInstances = { me.Character }
		local hit = workspace.Raycast(workspace, cam.CFrame.Position, cam.CFrame.LookVector * 5000, rp) -- 点调用: 不被 gun 穿墙钩子改写
		if not hit then toast("准星前面没东西"); return end
		local inst = hit.Instance
		local m = inst:FindFirstAncestorOfClass("Model")
		local node, s, seatModel, isCharacter = m, nil, nil, false
		while node do
			if node:FindFirstChildOfClass("Humanoid") then isCharacter = true end
			if not s then
				s = node:FindFirstChildWhichIsA("VehicleSeat", true) or node:FindFirstChildWhichIsA("Seat", true)
				if s then seatModel = node end
			end
			node = node:FindFirstAncestorOfClass("Model")
		end
		local r = (s or inst).AssemblyRootPart
		if not r or isCharacter then toast("准星没对准载具"); return end
		if not s then
			local ok, span = pcall(asmDims, r)
			if not ok or span > S.carmaxstuds then
				toast(ok and ("目标装配体过大，不锁定 (" .. math.floor(span + 0.5) .. " > " .. S.carmaxstuds .. " 格)") or "无法识别目标装配体")
				return
			end
		end
		if r.Anchored then toast("这个还锁着(锚定), 等游戏解锁"); return end
		picked, pickSeat = r, s
		dropLamps()
		toast("锁定 " .. (seatModel and seatModel.Name or inst.Name))
	end
	local function flip()
		local p, m = part(), model()
		if not (p and m) then toast("没有载具"); return end
		local pv = m:GetPivot()
		m:PivotTo(CFrame.new(pv.Position + Vector3.yAxis * 2) * CFrame.fromAxisAngle(p.CFrame.LookVector, math.pi) * pv.Rotation)
		p.AssemblyAngularVelocity = Vector3.zero
	end

	-- 方向盘: 屏幕底部滑条, 原生 UIDragDetector 单轴拖, 松手回中
	local track = mk("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(200, 36), BackgroundColor3 = BG, BackgroundTransparency = 0.4, BorderSizePixel = 0, Visible = false }, gui)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
	local knob = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = Color3.fromRGB(95, 65, 135), BorderSizePixel = 0 }, track)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
	local okK, kd = pcall(mk, "UIDragDetector", { DragStyle = Enum.UIDragDetectorDragStyle.TranslateLine, DragAxis = Vector2.new(1, 0), BoundingUI = track }, knob)
	local function center() knob.Position = UDim2.fromScale(0.5, 0.5) end
	if okK then on(kd.DragEnd, center) end -- 老客户端没有 UIDragDetector: 不显示死滑条, 用游戏自带方向盘
	local function steer() -- 按实际尺寸算, 不再写死 82; 钳到 [-1,1]
		local travel = (track.AbsoluteSize.X - knob.AbsoluteSize.X) / 2
		if travel <= 0 then return 0 end
		return math.clamp((knob.AbsolutePosition.X + knob.AbsoluteSize.X / 2 - track.AbsolutePosition.X - track.AbsoluteSize.X / 2) / travel, -1, 1)
	end

	on(RunService.PreSimulation, function(dt)
		local s = seat()
		if s ~= curSeat then -- 换座: 还原旧座限速, 新座解限速, 灯重挂
			restoreSeatMax(curSeat)
			curSeat = s
			if s and s:IsA("VehicleSeat") then seatMax[s] = s.MaxSpeed; s.MaxSpeed = math.huge end
			dropLamps()
			if lampOn then setLamps(true) end
		end
		local p, sp = part()
		track.Visible = okK and p ~= nil
		if not p or p.Anchored then detach(); if clipModel then reclip() end; return end
		attach(p)
		local m = model()
		local v = p.AssemblyLinearVelocity
		local hv = Vector3.new(v.X, 0, v.Z)
		local spd, mass, fwd = hv.Magnitude, p.AssemblyMass, facing()
		local thr, st = 0, steer()
		if sp and sp:IsA("VehicleSeat") then thr, st = sp.Throttle, math.clamp(st + sp.Steer, -1, 1) end -- 游戏自带的手机油门/方向盘也吃
		local acc, dec = accel or thr > 0, decel or thr < 0
		if os.clock() - statT > 0.2 then statT = os.clock(); status.Text = (m and m.Name or p.Name) .. " · " .. math.floor(spd + 0.5) .. " sps" .. (s and "" or " · 准星锁定") end
		if clip then noclip(p, m); if not flying then hover(p, m) end elseif clipModel then reclip() end
		if flying then -- 飞车: 直接给速度, 没输入就悬停
			if not lv then lv = mk("LinearVelocity", { Attachment0 = att, MaxForce = math.huge, VectorVelocity = Vector3.zero, RelativeTo = Enum.ActuatorRelativeTo.World }, att) end
			lv.VectorVelocity = fwd * (S.fly * ((acc and 1 or 0) - (dec and 1 or 0))) + Vector3.yAxis * (S.fly * ((up and 1 or 0) - (down and 1 or 0)))
			vf.Force = Vector3.zero
			return
		elseif lv then lv:Destroy(); lv = nil end
		-- 转向: 角速度 ∝ 车速(静止不转); 抓地把速度方向拉回车头
		if math.abs(st) > 0.02 and spd > 0.5 then
			p.CFrame = CFrame.fromAxisAngle(Vector3.yAxis, -st * S.turn * math.min(spd / 25, S.turncap) * dt) * p.CFrame.Rotation + p.Position
			local dir = hv:Dot(fwd) < 0 and -fwd or fwd
			p.AssemblyLinearVelocity = hv.Unit:Lerp(dir, math.min(dt * S.grip, 1)).Unit * spd + Vector3.yAxis * v.Y
		end
		local f, F = mass * S.acc, Vector3.zero
		if brake then -- 急刹: 刹到停, 再踩油门自动解除
			if acc then setBrake(false)
			elseif spd > 1 then F = -hv.Unit * (f * 2)
			else p.AssemblyLinearVelocity = Vector3.yAxis * v.Y end
		elseif acc and dec then if spd > 1 then F = -hv.Unit * (f * 2) end
		elseif acc then F = fwd * f
		elseif dec then F = -fwd * (f * (hv:Dot(fwd) > 3 and 2 or 1)) -- 前进中双倍刹, 停了就倒车
		elseif cruise then F = fwd * math.clamp((target - hv:Dot(fwd)) * mass * 2, -f, f) end
		if not cruise then target = hv:Dot(fwd) end -- 定速一开就锁当前车速
		vf.Force = F
	end)

	local r1 = row(page)
	num(r1, "加速", function() return S.acc end, function(v) S.acc = v; save("acc", v) end, 0.5)
	num(r1, "抓地", function() return S.grip end, function(v) S.grip = v; save("grip", v) end, 0.5)
	local r2 = row(page)
	num(r2, "转向", function() return S.turn end, function(v) S.turn = v; save("turn", v) end, 0.5)
	num(r2, "飞速", function() return S.fly end, function(v) S.fly = v; save("carfly", v) end, 0.5)
	local r3 = row(page)
	btn(r3, "换车(准星)", pick, 0.5)
	toggle(r3, "穿墙", clip, function(v) clip = v; save("carclip", v) end, 0.5)
	local r4 = row(page)
	toggle(r4, "定速", false, function(v) cruise = v end, 0.5)
	toggle(r4, "飞车", false, function(v) flying = v end, 0.5)
	local r5 = row(page)
	btn(r5, "翻转 180°", flip, 0.5)
	setBrake = toggle(r5, "急刹", false, function(v) brake = v end, 0.5)
	local r6 = row(page)
	toggle(r6, "常亮", false, function(v) lampOn = v; if v then setLamps(true) else dropLamps() end end, 0.5)
	btn(r6, "闪 ×3", function()
		lampFlashGeneration = lampFlashGeneration + 1
		local generation = lampFlashGeneration
		task.spawn(function()
			for _ = 1, 3 do
				if not alive or generation ~= lampFlashGeneration then return end
				setLamps(true); task.wait(0.12)
				if not alive or generation ~= lampFlashGeneration then return end
				setLamps(false); task.wait(0.12)
			end
			if alive and generation == lampFlashGeneration then
				if lampOn then setLamps(true) else dropLamps() end
			end
		end)
	end, 0.5)
	local r7 = row(page)
	toggle(r7, "常声(" .. S.horn .. ")", false, horn, 0.5)
	hold(r7, "声", horn, 0.5)
	local r8 = row(page, 36)
	hold(r8, "▲ 加速", function(v) accel = v end, 0.5)
	hold(r8, "▼ 减速", function(v) decel = v end, 0.5)
	local r9 = row(page, 36)
	hold(r9, "飞 ↑", function(v) up = v end, 0.5)
	hold(r9, "飞 ↓", function(v) down = v end, 0.5)
	status = text(page, "上车即控; 没车就对准它按 换车")

	DBG.sibs = function() local p = part(); return "part=" .. (p and p:GetFullName() or "-") .. " cruise=" .. tostring(cruise) .. "@" .. math.floor(target) .. " fly=" .. tostring(flying) .. " clip=" .. tostring(clip) .. " brake=" .. tostring(brake) end
	return function()
		lampFlashGeneration = lampFlashGeneration + 1
		detach(); reclip(); dropLamps(); horn(false)
		restoreSeatMax(curSeat)
	end
end }

-- ═════════ drift: 人物推进 (MobilePedals 自动绑; 没有就用面板按钮) ═════════
MODS[#MODS + 1] = { name = "drift", tab = "漂", fn = function(page)
	local S = { acc = opt("dacc", 5), brake = opt("dbrake", 10) }
	local enabled, w, s, att, vf, status = opt("drift", true), false, false, nil, nil, nil
	local pedalConns = {}
	local function bindPedals()
		if not alive then return end
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
		pedalConns[#pedalConns + 1] = f.ChildAdded:Connect(function() task.delay(0.2, function() if alive then bindPedals() end end) end)
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
	num(r1, "加速", function() return S.acc end, function(v) S.acc = v; save("dacc", v) end, 0.5)
	num(r1, "刹车", function() return S.brake end, function(v) S.brake = v; save("dbrake", v) end, 0.5)
	local r2 = row(page)
	toggle(r2, "推进", enabled, function(v) enabled = v; save("drift", v) end, 0.5)
	btn(r2, "重绑踏板", bindPedals, 0.5)
	local r3 = row(page, 36)
	hold(r3, "▲ 油门", function(v) w = v end, 0.5)
	hold(r3, "▼ 刹车", function(v) s = v end, 0.5)
	status = text(page, "…")
	task.spawn(function()
		local pg = me:FindFirstChild("PlayerGui")
		while alive and not pg do task.wait(0.1); pg = me:FindFirstChild("PlayerGui") end
		if not alive or not pg then return end
		on(pg.ChildAdded, function(c)
			if alive and c.Name == "MobilePedals" then task.delay(0.2, function() if alive then bindPedals() end end) end
		end)
		if alive then bindPedals() end
	end)

	DBG.drift = function() return "on=" .. tostring(enabled) .. " w=" .. tostring(w) .. " s=" .. tostring(s) .. " pedals=" .. #pedalConns end
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
				me:GetNetworkPing() * 1000, fps >= 50 and "#aae696" or "#eb7878", fps, Stats:GetTotalMemoryUsageMb(), os.date("%H:%M"), #Players:GetPlayers(), Players.MaxPlayers, pos)
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

	DBG.hud = function() return string.format("fps=%.0f players=%d", fps, #Players:GetPlayers()) end
	return function() for pl in pairs(esp) do espDrop(pl) end end
end }

-- ═════════ log: 各模块状态定时追加到 Selfblox_log.txt ═════════
MODS[#MODS + 1] = { name = "log", tab = "志", fn = function(page)
	local S = { int = opt("logint", 2), max = opt("logmax", 512) }
	local F, run, n, written = "Selfblox_log.txt", false, 0, 0
	local setRecording
	if not (appendfile and writefile) then text(page, "执行器没有 appendfile/writefile"); return end
	local status = text(page, "开 录制 后写 " .. F)
	local function head() local h = "---- Selfblox " .. os.date("%Y-%m-%d %H:%M:%S") .. " ----\n"; writefile(F, h); written = #h end
	task.spawn(function()
		while alive do
			task.wait(S.int)
			if run and alive then
				local L = {}
				for name, fn in pairs(DBG) do local ok, s = pcall(fn); L[#L + 1] = name .. ": " .. tostring(s) end -- 别的模块 dump 炸了日志照写
				table.sort(L)
				local txt = "[" .. os.date("%H:%M:%S") .. "] #" .. n .. "\n" .. table.concat(L, "\n") .. "\n"
				local ok, err = pcall(function()
					if written == 0 or written + #txt > S.max * 1024 then head() end -- 超限直接重写，不归档
					appendfile(F, txt)
				end)
				if ok then
					n, written = n + 1, written + #txt
					if status.Parent then status.Text = "#" .. n .. " · " .. math.floor(written / 1024) .. "KB / " .. S.max .. "KB" end
				else
					run = false
					if setRecording then setRecording(false, true) end
					if status.Parent then status.Text = "写日志失败，已停止录制" end
					warn("[Selfblox] 日志写入失败: " .. tostring(err))
				end
			end
		end
	end)
	local r1 = row(page)
	num(r1, "间隔s", function() return S.int end, function(v) S.int = v; save("logint", v) end, 0.5)
	num(r1, "上限KB", function() return S.max end, function(v) S.max = v; save("logmax", v) end, 0.5)
	setRecording = toggle(page, "录制", false, function(v) run = v end)
end }

-- ═════════ plane: 飞机侦察 (找飞机/判队伍/列 Remote/收发侦听/写报告) ═════════
MODS[#MODS + 1] = { name = "plane", tab = "机", fn = function(page)
	local HINT = { "plane", "jet", "aircraft", "fighter", "bomber", "heli", "glider", "warbird", "biplane", "gunship", "blimp" }
	local WING = { "wing", "aileron", "rudder", "elevator", "propeller", "rotor", "flap", "stabilizer", "tailfin" }
	local TEAMK = { "team", "faction", "side", "country", "nation" }
	local RHINT = { "fire", "shoot", "shot", "bullet", "gun", "weapon", "attack", "damage", "hit", "kill", "launch", "missile", "rocket", "bomb", "plane", "spawn", "team", "seat", "pilot" }
	local planes, remotes, sent, got, hls, watch = {}, {}, {}, {}, {}, {}
	local spyOn, watchOn, hlOn, autoOn, all, status = false, false, false, false, opt("pall", false), nil
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
		local wanted = {}
		if v then
			for _, r in ipairs(remotes) do
				if r.Parent and (r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent")) then
					wanted[r] = true
					if not watch[r] then
						watch[r] = r.OnClientEvent:Connect(function(...)
							if watchOn and r.Parent then push(got, r:GetFullName() .. " <- " .. args(table.pack(...))) end
						end)
					end
				end
			end
		end
		for r, c in pairs(watch) do
			if not v or not wanted[r] or not r.Parent then c:Disconnect(); watch[r] = nil end
		end
	end
	local function setSpy(v)
		if v then
			if not ncAdd("plane", { FireServer = true, InvokeServer = true }, function(self, m, ...)
				local a = table.pack(...)
				local path = self:GetFullName()
				if all or hint(path, RHINT) then push(sent, path .. ":" .. m .. " " .. args(a)) end
			end) then
				toast("执行器没有 hookmetamethod")
				return false
			end
		else
			ncDel("plane")
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
		local L = { "==== PLANE " .. os.date("%Y-%m-%d %H:%M:%S") .. " place=" .. game.PlaceId .. " me=" .. me.Name .. " team=" .. (me.Team and me.Team.Name or "-") .. " ====", "-- 飞机 " .. #planes }
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
		local savedOk = false
		if writefile then
			local ok, err = pcall(function() writefile("plane_debug.txt", txt) end)
			savedOk = ok
			if not ok then warn("[Selfblox] 飞机报告写入失败: " .. tostring(err)) end
		end
		if setclipboard then
			local ok, err = pcall(function() setclipboard(txt) end)
			if not ok then warn("[Selfblox] 剪贴板写入失败: " .. tostring(err)) end
		end
		toast("报告 " .. #L .. " 行" .. (savedOk and " → plane_debug.txt" or "（文件写入失败）"))
	end

	local r1 = row(page)
	local function safeScan()
		local ok, err = pcall(scan)
		if not ok then
			warn("[Selfblox] 飞机扫描失败: " .. tostring(err))
			if status and status.Parent then status.Text = "扫描失败: " .. tostring(err) end
		end
	end
	local function safeReport()
		local ok, err = pcall(report)
		if not ok then
			warn("[Selfblox] 飞机报告失败: " .. tostring(err))
			if status and status.Parent then status.Text = "报告失败: " .. tostring(err) end
		end
	end
	btn(r1, "重扫", safeScan, 0.5)
	btn(r1, "写报告", safeReport, 0.5)
	local r2 = row(page)
	local spyT
	spyT = toggle(r2, "发侦听", false, function(v) if not setSpy(v) then spyT(false) end end, 0.5)
	toggle(r2, "收侦听", false, setWatch, 0.5)
	local r3 = row(page)
	toggle(r3, "高亮", false, function(v) hlOn = v; highlight() end, 0.5)
	toggle(r3, "自动 5s", false, function(v) autoOn = v end, 0.5)
	local r4 = row(page)
	toggle(r4, "全录", all, function(v) all = v; save("pall", v) end, 0.5)
	btn(r4, "清空记录", function() table.clear(sent); table.clear(got) end, 0.5)
	status = text(page, "上机 → 发侦听 → 开几枪 → 写报告")
	task.spawn(function() while alive do task.wait(5); if autoOn and alive then safeScan() end end end)

	DBG.plane = function() return "planes=" .. #planes .. " remotes=" .. #remotes .. " sent=" .. #sent .. " got=" .. #got .. " spy=" .. tostring(spyOn) end
	return function() setWatch(false); hlOn = false; highlight(); ncDel("plane") end
end }

-- ═════════ brick: BitFarmer 刷砖 ═════════
MODS[#MODS + 1] = { name = "brick", tab = "砖", fn = function(page)
	local S = { batch = opt("bbatch", 4), int = opt("bint", 0.08), drain = opt("bdrain", 0.6), mult = opt("bmult", 99999), lvl = opt("blevel", 9999) }
	local run, setRun, status = false, nil, nil
	local runGeneration = 0
	local sessionOriginal
	local st = { cycles = 0, earned = 0, sent = 0, got = 0, rate = 0 }
	local function mine(c) return c:IsA("BasePart") and not c.Anchored and c:GetAttribute("Owner") == me.UserId end
	local function ingest(b, col) b.CFrame = col.CFrame + Vector3.new(math.random(-3, 3), 1.5, math.random(-3, 3)); b.AssemblyLinearVelocity = Vector3.new(0, -35, 0) end
	local function loop(generation)
		local ls = me:FindFirstChild("leaderstats")
		local col, spawnBit = workspace:FindFirstChild("Collector"), RS:FindFirstChild("SpawnBit")
		local bits, mult = ls and ls:FindFirstChild("Bits"), ls and ls:FindFirstChild("Multiplier")
		if not (col and bits) then setRun(false); toast("没找到 workspace.Collector / leaderstats.Bits"); return end
		if not sessionOriginal then
			sessionOriginal = { mult = mult and mult.Value, level = me:GetAttribute("MultiplierUpgradeLevel") }
		end
		local mult0, lvl0 = sessionOriginal.mult, sessionOriginal.level
		local last, lastT = bits.Value, os.clock()
		local conn = workspace.ChildAdded:Connect(function(c) task.defer(function() if run and alive and generation == runGeneration and mine(c) then ingest(c, col); st.got = st.got + 1 end end) end)
		local function drain() for _, c in ipairs(workspace:GetChildren()) do if mine(c) then ingest(c, col) end end end
		local ok, err = pcall(function()
		while run and alive and generation == runGeneration do
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
		end)
		conn:Disconnect()
		if generation == runGeneration or not run then
			if mult and mult0 ~= nil and mult.Parent then pcall(function() mult.Value = mult0 end) end
			if me.Parent then pcall(function() me:SetAttribute("MultiplierUpgradeLevel", lvl0) end) end
			sessionOriginal = nil
		end
		if not ok then
			warn("[Selfblox] brick loop: " .. tostring(err))
			if generation == runGeneration then run = false; if setRun then setRun(false, true) end; toast("刷砖循环异常，已停止") end
		end
	end
	setRun = toggle(page, "刷砖", false, function(v)
		runGeneration = runGeneration + 1
		run = v
		if v then local generation = runGeneration; task.spawn(function() loop(generation) end) end
	end)
	local r1 = row(page)
	num(r1, "批次", function() return S.batch end, function(v) S.batch = v; save("bbatch", v) end, 0.5)
	num(r1, "间隔", function() return S.int end, function(v) S.int = v; save("bint", v) end, 0.5)
	status = text(page, "BitFarmer 专用")

	DBG.brick = function() return "run=" .. tostring(run) .. " cycles=" .. st.cycles .. " earned=" .. st.earned .. " rate=" .. string.format("%.1f", st.rate) end
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
	if not alive then return end
	alive = false
	for _, release in ipairs(heldReleases) do pcall(release) end
	for _, s in ipairs(stops) do pcall(s) end -- 一个模块清理炸了不能拦住其他的
	for _, c in ipairs(conns) do c:Disconnect() end
	gui:Destroy()
	FX:Destroy()
	_G.SB_UNLOAD = nil
end
print("[Selfblox] " .. #active .. " 模块 · _G.SB_UNLOAD() 卸载")
