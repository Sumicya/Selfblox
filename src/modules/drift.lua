-- drift — 漂移控制（模块名 DRIFT）
-- 依赖：kit v10；功能：按住加速/刹车施加推进力、自适应增推、失速采样、
--       手机踏板绑定（MobilePedals）、状态栏
-- 约定：缩进用单个 Tab

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer

local K = _G.KIT
if not K or K.ver < 10 or type(K.mod) ~= "function" then
	error("[drift] 请先执行 kit.lua（需要 _G.KIT v10）", 0)
end

local NAME = "DRIFT"
local mk, isP = K.mk, K.isP
local M = K.mod(NAME, {DisplayOrder = 99997})
local CFG = M.cfg
CFG.Accelerate = 5
CFG.Brake = 10
CFG.StickDeadzone = 0.18
CFG.GroundProbeInterval = 0.05
CFG.FollowVelMinSpeed = 8
CFG.StallDetectSeconds = 0.8
CFG.StallMinSpeed = 2
CFG.StallMinGain = 0.04
CFG.StallSampleInterval = 0.1
CFG.StallAlignFloor = 0.7
CFG.AdaptiveBoost = true
CFG.BoostStartSpeed = 110
CFG.BoostRange = 120
CFG.BoostMaxMultiplier = 2.5
CFG.BoostStallExtra = 0.5

CFG.Accelerate = K.loadPrefixedNumber(NAME, "Acc", CFG.Accelerate)
CFG.Brake = K.loadPrefixedNumber(NAME, "Brake", CFG.Brake)

-- 状态
local enabled = K.loadPrefixed(NAME, "Enabled", true) == true
local root, character
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
local drive = nil

-- GUI
local totalH = CFG.TitleH + CFG.RowH * 3 + 20
CFG.PanelSize = UDim2.new(0, CFG.PanelW, 0, totalH)
CFG.PanelPos = UDim2.new(0.5, -CFG.PanelW / 2, 0.4, -totalH / 2)
CFG.CollapseSize = UDim2.new(0, CFG.PanelW, 0, CFG.TitleH)

local main = M.panel()
K.titleBar(main, CFG, M.bag, "漂移控制", CFG.TitleH)

K.fullInput(main, CFG.TitleH, CFG.RowH, "加速", CFG.Col.Accel,
	function() return CFG.Accelerate end,
	function(v) CFG.Accelerate = v; K.savePrefixed(NAME, "Acc", v) end,
	M.bag, CFG)

K.fullInput(main, CFG.TitleH + CFG.RowH, CFG.RowH, "刹车", CFG.Col.Decel,
	function() return CFG.Brake end,
	function(v) CFG.Brake = v; K.savePrefixed(NAME, "Brake", v) end,
	M.bag, CFG)

local buttonRow = mk("Frame", {
	Size = UDim2.new(1, 0, 0, CFG.RowH),
	Position = UDim2.new(0, 0, 0, CFG.TitleH + CFG.RowH * 2),
	BackgroundTransparency = 1,
}, main)

local enableButton = K.halfButton(buttonRow, K.toggleText("加速", enabled),
	0, 0, enabled and CFG.Col.On or CFG.Col.Off, CFG.RowH, CFG)

local rebindButton = K.halfButton(buttonRow, "重新绑定",
	0.5, 0, CFG.Col.Bind, CFG.RowH, CFG)

local status = K.label(main, {
	Size = UDim2.new(1, 0, 0, 20),
	Position = UDim2.new(0, 0, 0, CFG.TitleH + CFG.RowH * 3),
	Text = "等待角色…", TextColor3 = CFG.Col.Wait, TextSize = 10,
}, CFG)

local function setStatus(text, color)
	status.Text = text
	status.TextColor3 = color
end

-- 推进力
local function stopDrive()
	if drive then drive.destroy(); drive = nil end
end

local function getDrive()
	if not root or not root.Parent then stopDrive(); return nil end
	if root.Anchored then
		if drive then drive.set(Vector3.zero) end
		return nil
	end
	if drive and drive.alive() and drive.part == root then return drive end
	stopDrive()
	drive = K.force.vector(root, "DriftForce")
	return drive
end

M.reg(enableButton.Activated:Connect(function()
	enabled = not enabled
	if not enabled and drive then drive.set(Vector3.zero) end
	enableButton.Text = K.toggleText("加速", enabled)
	enableButton.BackgroundColor3 = enabled and CFG.Col.On or CFG.Col.Off
	K.savePrefixed(NAME, "Enabled", enabled)
end))

-- 角色绑定
local rebindCharacter = K.watchCharacter(M.bag, {
	ready = function(char, hum, newRoot)
		stopDrive()
		character, root = char, newRoot
		rayParams.FilterDescendantsInstances = {char}
		setStatus("已绑定: " .. tostring(newRoot.Name), CFG.Col.Good)
		getDrive()
	end,
	removed = function(old)
		if character ~= old then return end
		stopDrive()
		root, character = nil, nil
	end,
	waiting = function()
		setStatus("等待 Root…", CFG.Col.Wait)
	end,
}, {rootNames = {"Root", "HumanoidRootPart"}, requireHumanoid = false})

M.reg(rebindButton.Activated:Connect(function()
	setStatus("重新绑定…", CFG.Col.Wait)
	rebindCharacter()
end))

-- 踏板绑定（手机端 MobilePedals 的最左两个按钮 = 减速/加速）
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
		if child:IsA("GuiButton") then buttons[#buttons + 1] = child end
	end
	table.sort(buttons, function(a, b) return a.AbsolutePosition.X < b.AbsolutePosition.X end)
	if #buttons < 2 then
		setStatus("踏板不足，未绑定", CFG.Col.Bad)
		return
	end
	pedalSource = frame
	local function bind(button, setter)
		pedalConnections[#pedalConnections + 1] = button.InputBegan:Connect(function(input)
			if isP(input) then activeTouch[input] = setter; setter(true) end
		end)
		pedalConnections[#pedalConnections + 1] = button.InputEnded:Connect(function(input)
			if isP(input) then activeTouch[input] = nil; setter(false) end
		end)
		pedalConnections[#pedalConnections + 1] = button.AncestryChanged:Connect(function(_, parent)
			if not parent then setter(false) end
		end)
	end
	bind(buttons[2], function(val) touchW = val end)
	bind(buttons[1], function(val) touchS = val end)
	-- 静默期：GUI 自身构建会触发 DescendantAdded，不在该窗口内标记为脏
	local function maybeDirty()
		if os.clock() - pedalBoundAt > PEDAL_SETTLE then pedalDirty = true end
	end
	pedalConnections[#pedalConnections + 1] = frame.DescendantAdded:Connect(maybeDirty)
	pedalConnections[#pedalConnections + 1] = frame.DescendantRemoving:Connect(maybeDirty)
	pedalBoundAt = os.clock()
	if #buttons == 2 then setStatus("踏板已绑定", CFG.Col.Good)
	else setStatus("踏板已绑定（使用最左两个）", CFG.Col.Good) end
end

task.spawn(function()
	K.guard("drift:pedalBind", function()
		local playerGui = player:WaitForChild("PlayerGui")
		local function tryBind()
			if not M.bag.alive() then return end
			local pedals = playerGui:FindFirstChild("MobilePedals")
			local frame = pedals and pedals:FindFirstChild("Frame") or nil
			if frame then
				if frame ~= pedalSource or pedalDirty then
					bindPedals(frame)
					pedalDirty = false
				end
			elseif pedalSource then
				clearPedals()
				setStatus("等待踏板…", CFG.Col.Wait)
			end
		end
		tryBind()
		M.reg(playerGui.ChildAdded:Connect(function(child)
			if child.Name == "MobilePedals" then task.delay(0.15, tryBind) end
		end))
		M.reg(playerGui.ChildRemoved:Connect(function(child)
			if child.Name == "MobilePedals" then
				clearPedals()
				setStatus("等待踏板…", CFG.Col.Wait)
			end
		end))
		while M.bag.alive() do
			task.wait(5)
			if not pedalSource or pedalDirty then tryBind() end
		end
	end)
end)

M.reg(UIS.InputEnded:Connect(function(input)
	local setter = activeTouch[input]
	if not setter then return end
	activeTouch[input] = nil
	setter(false)
end))

M.reg(UIS.WindowFocusReleased:Connect(function()
	touchW, touchS = false, false
	table.clear(activeTouch)
end))

-- 力学工具
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
	if align <= 0 then return targetDir, false end
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
	if sampleNow - lastForwardSpeedAt < CFG.StallSampleInterval then return end
	lastSpeedGain = forwardSpeed - lastForwardSpeed
	local horizontal = K.flat(velocity)
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
	if n > 0 then return 1 end
	if n < 0 then return -1 end
	return 0
end

-- 主循环
M.reg(RunService.PreSimulation:Connect(function()
	K.heartbeat()
	if not enabled then
		if drive then drive.set(Vector3.zero) end
		return
	end
	if not root then return end
	if not root:IsDescendantOf(workspace) then
		stopDrive()
		root = nil
		setStatus("Root 失效，重连中…", CFG.Col.Bad)
		rebindCharacter()
		return
	end
	local f = getDrive()
	if not f then return end
	local w, s = K.input.forwardStates({w = touchW, s = touchS})
	if not (w or s) then
		f.set(Vector3.zero)
		return
	end
	local stickDir = K.input.stickDir(CFG.StickDeadzone)
	local targetDir = stickDir.Magnitude > 0.001 and stickDir
		or K.flatUnit(root.CFrame.LookVector, Vector3.new(0, 0, 1))
	local hv = root.AssemblyLinearVelocity
	local horizontalVel = K.flat(hv)
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
		f.set(Vector3.zero)
		return
	end
	local mass = root.AssemblyMass
	if mass <= 0 then
		f.set(Vector3.zero)
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
			f.set(-direction * sign(forwardSpeed) * CFG.Brake * mass)
		else
			f.set(Vector3.zero)
		end
	elseif w then
		f.set(direction * driveAcceleration * mass)
	else
		if forwardSpeed > 0.1 then
			f.set(-direction * CFG.Brake * mass)
		else
			f.set(-direction * driveAcceleration * mass)
		end
	end
end))

-- 调试
M.debug(function()
	local lines = {}
	local function log(msg) lines[#lines + 1] = tostring(msg) end
	log("enabled: " .. tostring(enabled))
	log("root: " .. tostring(root))
	log("Accelerate: " .. tostring(CFG.Accelerate))
	log("Brake: " .. tostring(CFG.Brake))
	log("boostMultiplier: " .. tostring(currentBoostMultiplier))
	log("effectiveAcceleration: " .. tostring(currentDriveAcceleration))
	log("hybridBlendActive: " .. tostring(lastFollowVelActive))
	log("keyboardEnabled: " .. tostring(K.hasKeyboard()))
	log("touchW: " .. tostring(touchW) .. " touchS: " .. tostring(touchS))
	log("pedalSource: " .. tostring(pedalSource))
	log("pedalDirty: " .. tostring(pedalDirty))
	log("pedalConnections: " .. tostring(#pedalConnections))
	log("stickDirection: " .. tostring(K.input.stickDir(CFG.StickDeadzone)))
	log("forwardSpeed: " .. tostring(lastForwardSpeed))
	log("speedGain/0.1s: " .. tostring(lastSpeedGain))
	log("speedStallFor: " .. tostring(speedStallFor))
	if root then
		log("root in workspace: " .. tostring(root:IsDescendantOf(workspace)))
		log("AssemblyMass: " .. tostring(root.AssemblyMass))
		log("AssemblyLinearVelocity: " .. tostring(root.AssemblyLinearVelocity))
		log("DriftForce: " .. tostring(drive and drive.instance))
		if drive then log("DriftForce.Force: " .. tostring(drive.instance.Force)) end
	end
	log("kitErrors(drift): " .. tostring(#K.getErrors("drift:pedalBind")))
	return K.debugDump(NAME, lines)
end)

-- 清理
M.done(function()
	enabled = false
	stopDrive()
	root, character = nil, nil
	touchW, touchS = false, false
	table.clear(activeTouch)
	clearPedals()
end)

print("[KIT] drift ready")
