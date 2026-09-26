-- Selfblox · DRIFT — 漂移控制（独立单文件）
-- v11 激进重写：无框架 / 无构建 / 现代 Luau / 原生 API 优先
-- 用法: loadstring(game:HttpGet(".../drift.lua"))()
-- 功能: 按住 W/S（或手机踏板）施加推进力、自适应增推、失速补偿、
--       手机 MobilePedals 踏板自动绑定、状态栏

local NAME = "DRIFT"

-- ===== 0. 重跑替换旧实例 =====

local OLD = rawget(_G, "SB_" .. NAME)
if type(OLD) == "function" then
	pcall(OLD)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local GuiRoot = (pcall(function() return gethui() end) and gethui()) or game:GetService("CoreGui")

local conns = {}
local function reg(c)
	conns[#conns + 1] = c
	return c
end

local function mk(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	inst.Parent = parent or props.Parent
	return inst
end

local function pickFont(names, fallback)
	for _, n in ipairs(names) do
		local ok, f = pcall(function() return Enum.Font[n] end)
		if ok and f then
			return f
		end
	end
	return fallback
end
local FONT = pickFont({ "BuilderSansBold", "GothamBold", "SourceSansBold" }, Enum.Font.SourceSansBold)

local oldGui = GuiRoot:FindFirstChild(NAME)
if oldGui then
	pcall(function() oldGui:Destroy() end)
end

-- ===== 1. 配置（原生文件 API；兼容 v10 的 KIT_Config.txt）=====

local store = rawget(_G, "SB_CFG")
if type(store) ~= "table" then
	store = { cache = {}, loaded = false, dirty = false, token = 0 }
	rawset(_G, "SB_CFG", store)
end
local CFG_FILE = "Selfblox_cfg.txt"
local HAS_RW = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"

local function flushCfg()
	if not (store.dirty and HAS_RW) then
		return
	end
	local keys = {}
	for k in pairs(store.cache) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local lines = { "KITCFG2" }
	for _, k in ipairs(keys) do
		local v = store.cache[k]
		local t = type(v)
		if t == "boolean" then
			lines[#lines + 1] = k .. "\tb\t" .. (v and "1" or "0")
		elseif t == "number" and v == v then
			lines[#lines + 1] = k .. "\tn\t" .. string.format("%.17g", v)
		elseif t == "string" then
			lines[#lines + 1] = k .. "\ts\t" .. v
		end
	end
	pcall(writefile, CFG_FILE, table.concat(lines, "\n"))
	store.dirty = false
end

if not store.loaded and HAS_RW then
	store.loaded = true
	local content = nil
	if pcall(function() return assert(isfile(CFG_FILE)) end) then
		content = readfile(CFG_FILE)
	elseif pcall(function() return assert(isfile("KIT_Config.txt")) end) then
		content = readfile("KIT_Config.txt")
	end
	if type(content) == "string" then
		local first = true
		for line in content:gmatch("[^\r\n]+") do
			if first then
				first = false
				if line ~= "KITCFG2" then
					break
				end
			else
				local k, t, v = line:match("^(.-)\t(.-)\t(.*)$")
				if k and t and k ~= "" then
					if t == "b" then
						store.cache[k] = (v == "1")
					elseif t == "n" then
						store.cache[k] = tonumber(v)
					elseif t == "s" then
						store.cache[k] = v
					end
				end
			end
		end
	end
end

local function cfgGet(key, d)
	local v = store.cache[key]
	return v == nil and d or v
end
local function cfgGetNum(key, d)
	local v = cfgGet(key, nil)
	if typeof(v) == "number" and v == v then
		return v
	end
	return d
end
local function cfgSet(key, v)
	store.cache[key] = v
	store.dirty = true
	local token = store.token
	task.delay(0.5, function()
		if store.token == token and store.dirty then
			store.token += 1
			flushCfg()
		end
	end)
end

-- ===== 2. 常量 / 状态 =====

local CFG = {
	StickDeadzone = 0.18, GroundProbeInterval = 0.05, FollowVelMinSpeed = 8,
	StallDetectSeconds = 0.8, StallMinSpeed = 2, StallMinGain = 0.04,
	StallSampleInterval = 0.1, StallAlignFloor = 0.7,
	AdaptiveBoost = true, BoostStartSpeed = 110, BoostRange = 120,
	BoostMaxMultiplier = 2.5, BoostStallExtra = 0.5,
}
CFG.Accelerate = cfgGetNum("DRIFTAcc", 5)
CFG.Brake = cfgGetNum("DRIFTBrake", 10)

local COL = {
	On = Color3.fromRGB(38, 125, 85), Off = Color3.fromRGB(48, 50, 60),
	Good = Color3.fromRGB(135, 215, 155), Bad = Color3.fromRGB(225, 135, 135),
	Wait = Color3.fromRGB(170, 175, 185), Bind = Color3.fromRGB(95, 65, 135),
	Accel = Color3.fromRGB(30, 85, 115), Decel = Color3.fromRGB(130, 90, 40),
}
local BG = Color3.fromRGB(20, 22, 28)
local ALPHA = 0.72
local SAFE_TOP = 48
local TITLE_H, ROW_H, PANEL_W = 20, 30, 120

local enabled = cfgGet("DRIFTEnabled", true) == true
local character, root = nil, nil
local touchW, touchS = false, false
local activeTouch = {}
local pedalSource, pedalConnections, pedalDirty = nil, {}, false
local pedalBoundAt = 0
local PEDAL_SETTLE = 0.3
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local cachedGroundHit, lastGroundProbeAt = nil, 0
local lastForwardSpeed, lastForwardSpeedAt, lastSpeedGain, speedStallFor = 0, os.clock(), 0, 0
local currentBoostMultiplier, currentDriveAcceleration = 1, CFG.Accelerate
local lastFollowVelActive = false
local driveForce, driveAtt = nil, nil
local alive = true

-- ===== 3. 输入 =====

local function isTyping()
	return UIS:GetFocusedTextBox() ~= nil
end

local function keyDown(code)
	return UIS.KeyboardEnabled and not isTyping() and UIS:IsKeyDown(code)
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function stickDir(deadzone)
	local ok, state = pcall(function() return UIS:GetGamepadState(Enum.UserInputType.Gamepad1) end)
	if not ok or not state then
		return Vector3.zero
	end
	for _, input in ipairs(state) do
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local v = Vector3.new(input.Position.X, 0, input.Position.Y)
			if v.Magnitude > deadzone then
				return v
			end
		end
	end
	return Vector3.zero
end

local function flatUnit(v, fallback)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude > 1e-3 then
		return f.Unit
	end
	return fallback or Vector3.zero
end

-- ===== 4. GUI =====

local totalH = TITLE_H + ROW_H * 3 + 20
local panelSize = UDim2.new(0, PANEL_W, 0, totalH)
local panelPos = UDim2.new(0.5, -PANEL_W / 2, 0.4, -totalH / 2)

local gui = mk("ScreenGui", {
	Name = NAME, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99997,
}, GuiRoot)
local main = mk("Frame", {
	Size = panelSize, Position = panelPos, BackgroundColor3 = BG,
	BackgroundTransparency = ALPHA, BorderSizePixel = 0, ClipsDescendants = true,
}, gui)

do
	local saved = cfgGet("UI.Pos." .. NAME, nil)
	local vp = workspace.CurrentCamera.ViewportSize
	if typeof(saved) == "string" then
		local sx, ox, sy, oy = saved:match("^([%-%d%.]+),([%-%d]+),([%-%d%.]+),([%-%d]+)$")
		if sx then
			local w, h = PANEL_W, totalH
			local absX = math.clamp(tonumber(ox) or 0, 0, math.max(vp.X - w, 0))
			local absY = math.clamp(tonumber(oy) or 0, SAFE_TOP, math.max(vp.Y - h, SAFE_TOP))
			main.Position = UDim2.new(tonumber(sx) or 0, absX, tonumber(sy) or 0, absY)
		end
	end
end

local titleBar = mk("TextButton", {
	Size = UDim2.new(1, 0, 0, TITLE_H), BackgroundColor3 = BG, BackgroundTransparency = 1,
	BorderSizePixel = 0, Text = "漂移控制 [-]", TextColor3 = Color3.new(1, 1, 1),
	TextSize = 13, Font = FONT, TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
}, main)

do
	local dragging, moved, origin, base = false, false, Vector2.zero, UDim2.new()
	reg(titleBar.InputBegan:Connect(function(input)
		if not isPointer(input) then
			return
		end
		dragging, moved = true, false
		origin = input.Position
		base = main.Position
	end))
	reg(UIS.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local delta = input.Position - origin
		if math.abs(delta.X) + math.abs(delta.Y) > 4 then
			moved = true
		end
		local vp = workspace.CurrentCamera.ViewportSize
		local size = main.AbsoluteSize
		local minX = -base.X.Scale * vp.X
		local maxX = vp.X - size.X - base.X.Scale * vp.X
		if minX > maxX then
			minX, maxX = maxX, minX
		end
		local minY = -base.Y.Scale * vp.Y + SAFE_TOP
		local maxY = vp.Y - size.Y - base.Y.Scale * vp.Y
		if minY > maxY then
			minY, maxY = maxY, minY
		end
		main.Position = UDim2.new(
			base.X.Scale, math.clamp(base.X.Offset + delta.X, minX, maxX),
			base.Y.Scale, math.clamp(base.Y.Offset + delta.Y, minY, maxY))
	end))
	local function release()
		if not dragging then
			return
		end
		dragging = false
		if moved then
			cfgSet("UI.Pos." .. NAME, string.format("%.6f,%.0f,%.6f,%.0f",
				main.Position.X.Scale, main.Position.X.Offset,
				main.Position.Y.Scale, main.Position.Y.Offset))
		end
	end
	reg(UIS.InputEnded:Connect(function(input)
		if isPointer(input) then
			release()
		end
	end))
	reg(UIS.WindowFocusReleased:Connect(release))

	local collapsed = false
	reg(titleBar.Activated:Connect(function()
		if moved then
			return
		end
		collapsed = not collapsed
		titleBar.Text = "漂移控制 " .. (collapsed and "[+]" or "[-]")
		main.Size = collapsed and UDim2.new(0, PANEL_W, 0, TITLE_H) or panelSize
	end))
end

local function fullInput(parent, y, rowH, labelText, color, getVal, setVal)
	local row = mk("Frame", {
		Size = UDim2.new(1, 0, 0, rowH), Position = UDim2.new(0, 0, 0, y),
		BackgroundTransparency = 1,
	}, parent)
	mk("TextLabel", {
		Size = UDim2.new(0.5, 0, 1, 0), BackgroundColor3 = color,
		BackgroundTransparency = ALPHA, BorderSizePixel = 0, Text = labelText,
		TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = FONT,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, row)
	local input = mk("TextBox", {
		Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundColor3 = color, BackgroundTransparency = ALPHA, BorderSizePixel = 0,
		TextColor3 = Color3.new(1, 1, 1), Text = tostring(getVal and getVal() or ""),
		TextSize = 11, Font = FONT, ClearTextOnFocus = true,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, row)
	reg(input.FocusLost:Connect(function()
		local v = tonumber(input.Text)
		if v and setVal then
			setVal(v)
		end
		if getVal then
			input.Text = tostring(getVal())
		end
	end))
	return input
end

fullInput(main, TITLE_H, ROW_H, "加速", COL.Accel,
	function() return CFG.Accelerate end,
	function(v)
		CFG.Accelerate = v
		cfgSet("DRIFTAcc", v)
	end)

fullInput(main, TITLE_H + ROW_H, ROW_H, "刹车", COL.Decel,
	function() return CFG.Brake end,
	function(v)
		CFG.Brake = v
		cfgSet("DRIFTBrake", v)
	end)

local buttonRow = mk("Frame", {
	Size = UDim2.new(1, 0, 0, ROW_H),
	Position = UDim2.new(0, 0, 0, TITLE_H + ROW_H * 2),
	BackgroundTransparency = 1,
}, main)

local enableButton = mk("TextButton", {
	Size = UDim2.new(0.5, 0, 1, 0),
	BackgroundColor3 = enabled and COL.On or COL.Off, BackgroundTransparency = ALPHA,
	BorderSizePixel = 0, Text = enabled and "加速 开" or "加速 关",
	TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = FONT,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, buttonRow)

local rebindButton = mk("TextButton", {
	Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0.5, 0, 0, 0),
	BackgroundColor3 = COL.Bind, BackgroundTransparency = ALPHA, BorderSizePixel = 0,
	Text = "重新绑定", TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = FONT,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, buttonRow)

local statusLabel = mk("TextLabel", {
	Size = UDim2.new(1, 0, 0, 20),
	Position = UDim2.new(0, 0, 0, TITLE_H + ROW_H * 3),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	Text = "等待角色…", TextColor3 = COL.Wait, Font = FONT, TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, main)

local function setStatus(text, color)
	statusLabel.Text = text
	statusLabel.TextColor3 = color
end

-- ===== 5. 推进力（原生 VectorForce）=====

local function stopDrive()
	if driveForce then
		pcall(function() driveForce:Destroy() end)
		driveForce = nil
	end
	if driveAtt then
		pcall(function() driveAtt:Destroy() end)
		driveAtt = nil
	end
end

local function setDriveForce(v)
	if driveForce then
		pcall(function() driveForce.Force = v end)
	end
end

local function getDrive()
	if not root or not root.Parent then
		stopDrive()
		return nil
	end
	if root.Anchored then
		setDriveForce(Vector3.zero)
		return nil
	end
	if driveForce and driveForce.Parent == root then
		return driveForce
	end
	stopDrive()
	driveAtt = mk("Attachment", { Name = "DriftAtt" }, root)
	driveForce = mk("VectorForce", {
		Name = "DriftForce", Attachment0 = driveAtt,
		Force = Vector3.zero, RelativeTo = Enum.ActuatorRelativeTo.World,
		ApplyAtCenterOfMass = true,
	}, root)
	return driveForce
end

reg(enableButton.Activated:Connect(function()
	enabled = not enabled
	if not enabled and driveForce then
		setDriveForce(Vector3.zero)
	end
	enableButton.Text = enabled and "加速 开" or "加速 关"
	enableButton.BackgroundColor3 = enabled and COL.On or COL.Off
	cfgSet("DRIFTEnabled", enabled)
end))

-- ===== 6. 角色绑定（Root 即可，不强制 Humanoid）=====

local charConns = {}
local function bindCharacter(c)
	for _, x in ipairs(charConns) do
		pcall(function() x:Disconnect() end)
	end
	table.clear(charConns)
	character = c
	stopDrive()
	root = nil
	setStatus("等待 Root…", COL.Wait)
	local function scan()
		local r = c:FindFirstChild("Root") or c:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") and r ~= root then
			root = r
			rayParams.FilterDescendantsInstances = { c }
			setStatus("已绑定: " .. tostring(r.Name), COL.Good)
			getDrive()
		end
	end
	scan()
	charConns[#charConns + 1] = c.ChildAdded:Connect(scan)
end

reg(rebindButton.Activated:Connect(function()
	setStatus("重新绑定…", COL.Wait)
	bindCharacter(character or player.Character)
end))

-- ===== 7. 踏板绑定（手机端 MobilePedals 最左两个 = 减速/加速）=====

local function clearPedals()
	for _, connection in ipairs(pedalConnections) do
		pcall(function() connection:Disconnect() end)
	end
	table.clear(pedalConnections)
	pedalSource = nil
	pedalDirty = false
end

local function bindPedals(frame)
	clearPedals()
	local buttons = {}
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiButton") then
			buttons[#buttons + 1] = child
		end
	end
	table.sort(buttons, function(a, b) return a.AbsolutePosition.X < b.AbsolutePosition.X end)
	if #buttons < 2 then
		setStatus("踏板不足，未绑定", COL.Bad)
		return
	end
	pedalSource = frame
	local function bind(button, setter)
		pedalConnections[#pedalConnections + 1] = button.InputBegan:Connect(function(input)
			if isPointer(input) then
				activeTouch[input] = setter
				setter(true)
			end
		end)
		pedalConnections[#pedalConnections + 1] = button.InputEnded:Connect(function(input)
			if isPointer(input) then
				activeTouch[input] = nil
				setter(false)
			end
		end)
		pedalConnections[#pedalConnections + 1] = button.AncestryChanged:Connect(function(_, parent)
			if not parent then
				setter(false)
			end
		end)
	end
	bind(buttons[2], function(val) touchW = val end)
	bind(buttons[1], function(val) touchS = val end)
	-- 静默期：GUI 自身构建会触发 DescendantAdded，不在该窗口内标记为脏
	local function maybeDirty()
		if os.clock() - pedalBoundAt > PEDAL_SETTLE then
			pedalDirty = true
		end
	end
	pedalConnections[#pedalConnections + 1] = frame.DescendantAdded:Connect(maybeDirty)
	pedalConnections[#pedalConnections + 1] = frame.DescendantRemoving:Connect(maybeDirty)
	pedalBoundAt = os.clock()
	if #buttons == 2 then
		setStatus("踏板已绑定", COL.Good)
	else
		setStatus("踏板已绑定（使用最左两个）", COL.Good)
	end
end

task.spawn(function()
	local playerGui = player:WaitForChild("PlayerGui")
	local function tryBind()
		if not alive then
			return
		end
		local pedals = playerGui:FindFirstChild("MobilePedals")
		local frame = pedals and pedals:FindFirstChild("Frame") or nil
		if frame then
			if frame ~= pedalSource or pedalDirty then
				bindPedals(frame)
				pedalDirty = false
			end
		elseif pedalSource then
			clearPedals()
			setStatus("等待踏板…", COL.Wait)
		end
	end
	tryBind()
	reg(playerGui.ChildAdded:Connect(function(child)
		if child.Name == "MobilePedals" then
			task.delay(0.15, tryBind)
		end
	end))
	reg(playerGui.ChildRemoved:Connect(function(child)
		if child.Name == "MobilePedals" then
			clearPedals()
			setStatus("等待踏板…", COL.Wait)
		end
	end))
	while alive do
		task.wait(5)
		if not alive then
			break
		end
		if not pedalSource or pedalDirty then
			tryBind()
		end
	end
end)

reg(UIS.InputEnded:Connect(function(input)
	local setter = activeTouch[input]
	if not setter then
		return
	end
	activeTouch[input] = nil
	setter(false)
end))

reg(UIS.WindowFocusReleased:Connect(function()
	touchW, touchS = false, false
	table.clear(activeTouch)
end))

-- ===== 8. 力学 =====

local function getDriveAcceleration(forwardSpeed)
	local multiplier = 1
	if CFG.AdaptiveBoost then
		local excess = math.max(0, math.abs(forwardSpeed) - CFG.BoostStartSpeed)
		local span = math.max(CFG.BoostRange, 1)
		local maxMultiplier = math.max(CFG.BoostMaxMultiplier, 1)
		multiplier += math.clamp(excess / span, 0, 1) * (maxMultiplier - 1)
		if speedStallFor >= CFG.StallDetectSeconds then
			multiplier += CFG.BoostStallExtra
		end
	end
	currentBoostMultiplier = multiplier
	currentDriveAcceleration = CFG.Accelerate * multiplier
	return currentDriveAcceleration
end

-- 混合推进方向：高速且与速度方向有夹角时向速度方向偏移，减少侧滑抖动
local function calculateBlendedThrustDirection(targetDir, horizontalVel)
	local hSpeed = horizontalVel.Magnitude
	if hSpeed <= CFG.FollowVelMinSpeed or targetDir.Magnitude < 0.001 then
		return targetDir, false
	end
	local velDir = horizontalVel.Unit
	local align = targetDir:Dot(velDir)
	if align <= 0 then
		return targetDir, false
	end
	local blendFactor = math.clamp((1 - align) * 0.6, 0, 0.38)
	local blended = targetDir:Lerp(velDir, blendFactor)
	if blended.Magnitude > 0.001 then
		return blended.Unit, blendFactor > 0.05
	end
	return targetDir, false
end

-- 失速采样：必须在 getDriveAcceleration 之前调用，否则 boost 慢一帧
local function sampleStall(w, direction, velocity, forwardSpeed)
	local sampleNow = os.clock()
	if sampleNow - lastForwardSpeedAt < CFG.StallSampleInterval then
		return
	end
	lastSpeedGain = forwardSpeed - lastForwardSpeed
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local align = horizontal.Magnitude > 0.001 and horizontal.Unit:Dot(direction) or 0
	if w and align > CFG.StallAlignFloor
		and forwardSpeed >= CFG.StallMinSpeed
		and lastSpeedGain < CFG.StallMinGain then
		speedStallFor += sampleNow - lastForwardSpeedAt
	else
		speedStallFor = 0
	end
	lastForwardSpeed = forwardSpeed
	lastForwardSpeedAt = sampleNow
end

local function sign(n)
	if n > 0 then
		return 1
	end
	if n < 0 then
		return -1
	end
	return 0
end

-- ===== 9. 主循环 =====

reg(RunService.PreSimulation:Connect(function()
	if not enabled then
		setDriveForce(Vector3.zero)
		return
	end
	if not root then
		return
	end
	if not root:IsDescendantOf(workspace) then
		stopDrive()
		root = nil
		setStatus("Root 失效，重连中…", COL.Bad)
		bindCharacter(character or player.Character)
		return
	end
	local f = getDrive()
	if not f then
		return
	end
	local w = keyDown(Enum.KeyCode.W) or keyDown(Enum.KeyCode.Up) or touchW
	local s = keyDown(Enum.KeyCode.S) or keyDown(Enum.KeyCode.Down) or touchS
	if not (w or s) then
		setDriveForce(Vector3.zero)
		return
	end
	local sd = stickDir(CFG.StickDeadzone)
	local targetDir = sd.Magnitude > 0.001 and sd
		or flatUnit(root.CFrame.LookVector, Vector3.new(0, 0, 1))
	local hv = root.AssemblyLinearVelocity
	local horizontalVel = Vector3.new(hv.X, 0, hv.Z)
	local direction, blendActive = calculateBlendedThrustDirection(targetDir, horizontalVel)
	lastFollowVelActive = blendActive
	local now = os.clock()
	if now - lastGroundProbeAt >= CFG.GroundProbeInterval then
		cachedGroundHit = workspace:Raycast(root.Position, Vector3.new(0, -6, 0), rayParams)
		lastGroundProbeAt = now
	end
	if cachedGroundHit then
		local n = cachedGroundHit.Normal
		local projected = direction - n * direction:Dot(n)
		direction = projected.Magnitude > 0.001 and projected.Unit or Vector3.zero
	end
	if direction.Magnitude < 0.001 then
		setDriveForce(Vector3.zero)
		return
	end
	local mass = root.AssemblyMass
	if mass <= 0 then
		setDriveForce(Vector3.zero)
		return
	end
	local velocity = root.AssemblyLinearVelocity
	local forwardSpeed = velocity:Dot(direction)
	-- W+S 同时按下视为刹车，不计入失速
	if not (w and s) then
		sampleStall(w, direction, velocity, forwardSpeed)
	end
	local driveAcceleration = getDriveAcceleration(forwardSpeed)
	if w and s then
		if math.abs(forwardSpeed) > 0.1 then
			setDriveForce(-direction * sign(forwardSpeed) * CFG.Brake * mass)
		else
			setDriveForce(Vector3.zero)
		end
	elseif w then
		setDriveForce(direction * driveAcceleration * mass)
	else
		if forwardSpeed > 0.1 then
			setDriveForce(-direction * CFG.Brake * mass)
		else
			setDriveForce(-direction * driveAcceleration * mass)
		end
	end
end))

reg(player.CharacterAdded:Connect(bindCharacter))
if player.Character then
	bindCharacter(player.Character)
end

-- ===== 10. 卸载 =====

local DBG = rawget(_G, "SB_DEBUG") or {}
rawset(_G, "SB_DEBUG", DBG)
DBG[NAME] = function()
	local lines = {
		"enabled: " .. tostring(enabled) .. " root: " .. tostring(root),
		"Accelerate: " .. tostring(CFG.Accelerate) .. " Brake: " .. tostring(CFG.Brake),
		"boost: " .. string.format("%.2f", currentBoostMultiplier)
			.. " effective: " .. string.format("%.2f", currentDriveAcceleration),
		"blend: " .. tostring(lastFollowVelActive),
		"touchW: " .. tostring(touchW) .. " touchS: " .. tostring(touchS),
		"pedals: " .. tostring(pedalSource and pedalSource.Name or "nil")
			.. " dirty=" .. tostring(pedalDirty) .. " conns=" .. tostring(#pedalConnections),
		"stick: " .. tostring(stickDir(CFG.StickDeadzone)),
		"forwardSpeed: " .. string.format("%.2f", lastForwardSpeed)
			.. " gain: " .. string.format("%.3f", lastSpeedGain)
			.. " stallFor: " .. string.format("%.2f", speedStallFor),
	}
	if root then
		lines[#lines + 1] = "mass: " .. tostring(root.AssemblyMass)
			.. " vel: " .. tostring(root.AssemblyLinearVelocity)
	end
	return "=== DRIFT ===\n" .. table.concat(lines, "\n") .. "\n=== END ==="
end

local function destroy()
	alive = false
	enabled = false
	stopDrive()
	root, character = nil, nil
	touchW, touchS = false, false
	table.clear(activeTouch)
	clearPedals()
	for _, x in ipairs(charConns) do
		pcall(function() x:Disconnect() end)
	end
	table.clear(charConns)
	gui:Destroy()
	for _, c in ipairs(conns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(conns)
	store.token += 1
	flushCfg()
	DBG[NAME] = nil
	rawset(_G, "SB_" .. NAME, nil)
end
rawset(_G, "SB_" .. NAME, destroy)

print("[drift] ready")
