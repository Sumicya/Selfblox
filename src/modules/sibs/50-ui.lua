-- sibs / 50-ui — 车辆列表、主面板、转向/旋转滑条、按键绑定、调试与卸载

-- 车辆列表（弹窗，按距离排序取前 10）
local listGui = nil

local function closeVehicleList()
	if listGui then pcall(function() listGui:Destroy() end); listGui = nil end
end

local function getListRoot()
	if gethui then local ok, r = pcall(gethui) if ok and r then return r end end
	return game:GetService("CoreGui")
end

local function openVehicleList()
	closeVehicleList()
	local models = scanCandidates()
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	local entries = {}
	for _, m in ipairs(models) do
		local rp = getRootPart(m)
		if rp then
			local tag = playerOwnsModel(m) and " ·主" or (isMyVehicle(m) and " ·我" or " ")
			entries[#entries + 1] = {model = m, name = tostring(m.Name),
				dist = (rp.Position - camPos).Magnitude, tag = tag}
		end
	end
	if #entries == 0 then toast("无候选车辆", K.Col.Wait); return end
	table.sort(entries, function(a, b) return a.dist < b.dist end)
	local shown = math.min(#entries, 10)
	listGui = Instance.new("ScreenGui")
	listGui.Name = NAME .. "_List"
	listGui.ResetOnSpawn = false
	listGui.IgnoreGuiInset = true
	listGui.DisplayOrder = 99999
	listGui.Parent = getListRoot()
	local w, rowH = 170, 26
	local frame = mk("Frame", {
		Size = UDim2.new(0, w, 0, 24 + (shown + 1) * rowH),
		Position = UDim2.new(0.5, -w / 2, 0.3, 0),
		BackgroundColor3 = CFG.BG, BackgroundTransparency = 0.08, BorderSizePixel = 0, Active = true,
	}, listGui)
	local title = K.btn(frame, {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = CFG.BG,
		Text = "车辆 ×" .. tostring(#entries) .. "（点选）",
	}, CFG)
	M.reg(title.Activated:Connect(closeVehicleList))
	for i = 1, shown do
		local e = entries[i]
		local label = e.name
		if #label > 9 then label = label:sub(1, 8) .. "…" end
		local btn = K.btn(frame, {
			Size = UDim2.new(1, 0, 0, rowH),
			Position = UDim2.new(0, 0, 0, 24 + (i - 1) * rowH),
			BackgroundColor3 = (e.model == lockModel) and CFG.Col.On or CFG.Col.Off,
			Text = " " .. label .. " ·" .. tostring(math.floor(e.dist)) .. "m" .. e.tag,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, CFG)
		M.reg(btn.Activated:Connect(function()
			manualLockUntil = os.clock() + CFG.ManualLockDuration
			applyLock(e.model)
			closeVehicleList()
		end))
	end
	local rescan = K.btn(frame, {
		Size = UDim2.new(1, 0, 0, rowH),
		Position = UDim2.new(0, 0, 0, 24 + shown * rowH),
		BackgroundColor3 = CFG.Col.Bind,
		Text = "重扫描",
	}, CFG)
	M.reg(rescan.Activated:Connect(openVehicleList))
end

-- 主面板
local INPUT_ROWS = 2
local GRID_ROWS = 3
local totalH = CFG.TitleH + CFG.InputRowH * INPUT_ROWS + CFG.RowH * 3 + CFG.SigRowH * 2
	+ CFG.RowH + CFG.RowH + CFG.BtnH * GRID_ROWS
CFG.PanelSize = UDim2.new(0, CFG.PanelW, 0, math.min(totalH, CFG.PanelVisibleH))
CFG.PanelPos = UDim2.new(0.5, -CFG.PanelW / 2, 0.4, -math.min(totalH, CFG.PanelVisibleH) / 2)
CFG.CollapseSize = UDim2.new(0, CFG.PanelW, 0, CFG.TitleH)

local main = M.panel()
K.titleBar(main, CFG, M.bag, "车辆控制", CFG.TitleH)

local scroll = mk("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -CFG.TitleH),
	Position = UDim2.new(0, 0, 0, CFG.TitleH),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 2,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, main)

K.fullInput(scroll, 0, CFG.InputRowH, "加速", CFG.Col.Accel,
	function() return acceleration end,
	function(v) acceleration = v; K.savePrefixed(NAME, "Acc", v) end, M.bag, CFG)

K.fullInput(scroll, CFG.InputRowH, CFG.InputRowH, "抓地", CFG.Col.On,
	function() return CFG.TurnGrip end,
	function(v) CFG.TurnGrip = v; K.savePrefixed(NAME, "Grip", v) end, M.bag, CFG)

local yBtn = CFG.InputRowH * INPUT_ROWS

switchButton = K.halfButton(scroll, "换车", 0.5, yBtn, CFG.Col.Bind, CFG.RowH, CFG)
setNoCharLabel()
M.reg(switchButton.Activated:Connect(function() cycleVehicle() end))

local clipButton = K.halfButton(scroll, noClip and "穿墙 开" or "穿墙 关", 0, yBtn,
	noClip and CFG.Col.On or CFG.Col.Off, CFG.RowH, CFG)
M.reg(clipButton.Activated:Connect(function()
	noClip = not noClip
	if noClip then clipDirty = true; clipFalling = false; clipNextRebuild = 0
	else restoreClip(); clipDirty = true end
	clipButton.Text = noClip and "穿墙 开" or "穿墙 关"
	clipButton.BackgroundColor3 = noClip and CFG.Col.On or CFG.Col.Off
	K.savePrefixed(NAME, "NoClip", noClip)
end))

local yBtn2 = yBtn + CFG.RowH
local cruiseButton = K.halfButton(scroll, "定速 关", 0, yBtn2, CFG.Col.Off, CFG.RowH, CFG)
M.reg(cruiseButton.Activated:Connect(function()
	if not (seat or lockPart) then return end
	cruise = not cruise
	if cruise then
		local p = seat or lockPart
		local look = getVehicleFacing(p)
		if look.Magnitude < 0.001 then look = Vector3.new(0, 0, 1) end
		local hv = K.flat(p.AssemblyLinearVelocity)
		targetSpeed = hv:Dot(look)
		stopped = false
		refreshStopButton()
	end
	cruiseButton.Text = cruise and "定速 开" or "定速 关"
	cruiseButton.BackgroundColor3 = cruise and CFG.Col.On or CFG.Col.Off
end))

local flyButton = K.halfButton(scroll, "飞车 关", 0.5, yBtn2, CFG.Col.Off, CFG.RowH, CFG)
M.reg(flyButton.Activated:Connect(function()
	carFly = not carFly
	if not carFly then stopCarFly() end
	flyButton.Text = carFly and "飞车 开" or "飞车 关"
	flyButton.BackgroundColor3 = carFly and CFG.Col.On or CFG.Col.Off
end))

local yBtn3 = yBtn2 + CFG.RowH
local listButton = K.halfButton(scroll, "车列表", 0, yBtn3, CFG.Col.Bind, CFG.RowH, CFG)
M.reg(listButton.Activated:Connect(function()
	if listGui then closeVehicleList() else openVehicleList() end
end))

local flipButton = K.halfButton(scroll, "翻转", 0.5, yBtn3, CFG.Col.Danger, CFG.RowH, CFG)
M.reg(flipButton.Activated:Connect(function() flipVehicle() end))

-- 灯/喇叭四键
local ySig = yBtn3 + CFG.RowH

local steadyLBtn = K.halfButton(scroll, "常亮", 0, ySig, CFG.Col.Off, CFG.SigRowH, CFG)
local flashBtn = K.halfButton(scroll, "闪", 0, ySig + CFG.SigRowH, CFG.Col.Off, CFG.SigRowH, CFG)
local steadySBtn = K.halfButton(scroll, "常声", 0.5, ySig, CFG.Col.Off, CFG.SigRowH, CFG)
local beepBtn = K.halfButton(scroll, "声", 0.5, ySig + CFG.SigRowH, CFG.Col.Off, CFG.SigRowH, CFG)

local function refreshSigButtons()
	if steadyLBtn then steadyLBtn.BackgroundColor3 = lightSteady and CFG.Col.On or CFG.Col.Off end
	if steadySBtn then steadySBtn.BackgroundColor3 = hornSteady and CFG.Col.On or CFG.Col.Off end
end

M.reg(steadyLBtn.Activated:Connect(function()
	lightSteady = not lightSteady
	if lightSteady then armLights() else rearmLights() end
	refreshSigButtons()
end))

M.reg(flashBtn.Activated:Connect(function()
	armLights()
	flashUntil = os.clock() + 0.45
end))

M.reg(steadySBtn.Activated:Connect(function()
	if not hornKeyFound then detectHornKey(); return end
	hornSteady = not hornSteady
	refreshSigButtons()
end))

M.reg(beepBtn.Activated:Connect(function()
	if not hornKeyFound then detectHornKey(); return end
	beepUntil = os.clock() + 0.38
end))

refreshSigButtons()

-- 急刹
local yStop = ySig + CFG.SigRowH * 2
stopButton = K.btn(scroll, {
	Size = UDim2.new(1, 0, 0, CFG.RowH),
	Position = UDim2.new(0, 0, 0, yStop),
	BackgroundColor3 = CFG.Col.Stop,
	Text = "急刹 关",
	TextSize = 13,
}, CFG)

M.reg(stopButton.Activated:Connect(function()
	stopped = not stopped
	refreshStopButton()
	if stopped then accelerating, decelerating = false, false; cruise = false end
end))

-- 旋转滑条（面板内，松手保持）
local ySpin = yStop + CFG.RowH
local spinRow = mk("Frame", {
	Size = UDim2.new(1, 0, 0, CFG.RowH),
	Position = UDim2.new(0, 0, 0, ySpin),
	BackgroundTransparency = 1,
}, scroll)

K.label(spinRow, {
	Size = UDim2.new(0.3, 0, 1, 0),
	Text = "旋转", TextColor3 = Color3.new(1, 1, 1), TextSize = 11,
})

local spinTrack = mk("Frame", {
	Size = UDim2.new(0.7, -8, 0, 8),
	Position = UDim2.new(0.3, 4, 0.5, -4),
	BackgroundColor3 = Color3.fromRGB(50, 52, 62),
	BorderSizePixel = 0,
}, spinRow)

local spinKnob = mk("Frame", {
	Size = UDim2.fromOffset(16, 16),
	Position = UDim2.new(0.5, -8, 0.5, -8),
	BackgroundColor3 = Color3.fromRGB(140, 190, 155),
	BorderSizePixel = 0,
}, spinTrack)
mk("UICorner", {CornerRadius = UDim.new(0.5, 0)}, spinKnob)

local spinDragging = false

local function spinKnobTo(v)
	local usable = spinTrack.AbsoluteSize.X - 16
	local px = 8 + usable * ((v / CFG.SpinMax + 1) / 2)
	spinKnob.Position = UDim2.new(0, px - 8, 0.5, -8)
end

-- 初始化旋钮位置：等布局完成，重试若干帧
task.spawn(function()
	for _ = 1, 30 do
		if not M.bag.alive() then return end
		if spinTrack and spinTrack.Parent and spinTrack.AbsoluteSize.X > 0 then
			spinKnobTo(spinSpeed)
			return
		end
		task.wait()
	end
end)

M.reg(spinTrack.InputBegan:Connect(function(input)
	if K.isP(input) then spinDragging = true end
end))

M.reg(UIS.InputChanged:Connect(function(input)
	if not spinDragging then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local usable = spinTrack.AbsoluteSize.X - 16
	local rel = (input.Position.X - spinTrack.AbsolutePosition.X - 8) / math.max(usable, 1)
	spinSpeed = math.clamp((rel * 2 - 1) * CFG.SpinMax, -CFG.SpinMax, CFG.SpinMax)
	spinKnobTo(spinSpeed)
	K.savePrefixed(NAME, "Spin", spinSpeed)
end))

M.reg(UIS.InputEnded:Connect(function(input)
	if K.isP(input) then spinDragging = false end
end))

-- 按钮网格
local yGrid = ySpin + CFG.RowH
local grid = mk("Frame", {
	Size = UDim2.new(1, 0, 0, CFG.BtnH * GRID_ROWS),
	Position = UDim2.new(0, 0, 0, yGrid),
	BackgroundTransparency = 1,
}, scroll)

mk("UIGridLayout", {
	CellSize = UDim2.new(0.5, 0, 0, CFG.BtnH),
	CellPadding = UDim2.new(0, 0, 0, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, grid)

local accelHoldButton = K.mkBtn(grid, "按住加速", CFG.Col.Accel, 1, function() end, M.bag, CFG)
local decelHoldButton = K.mkBtn(grid, "按住减速", CFG.Col.Decel, 2, function() end, M.bag, CFG)
K.holdButton(accelHoldButton, M.bag,
	function() stopped = false; refreshStopButton(); accelerating = true end,
	function() accelerating = false end)
K.holdButton(decelHoldButton, M.bag,
	function() stopped = false; refreshStopButton(); decelerating = true end,
	function() decelerating = false end)

local flyUpButton = K.mkBtn(grid, "飞车↑", CFG.Col.Off, 3, function() end, M.bag, CFG)
local flyDownButton = K.mkBtn(grid, "飞车↓", CFG.Col.Off, 4, function() end, M.bag, CFG)
K.holdButton(flyUpButton, M.bag, function() flyUp = true end, function() flyUp = false end)
K.holdButton(flyDownButton, M.bag, function() flyDown = true end, function() flyDown = false end)

K.mkBtn(grid, "翻转 180°", CFG.Col.Danger, 5, function() flipVehicle() end, M.bag, CFG)

-- 灯光快捷键 O
M.reg(UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or K.isTyping() then return end
	if input.KeyCode == CFG.LampKey then
		lightSteady = not lightSteady
		if lightSteady then armLights() else rearmLights() end
		refreshSigButtons()
	end
end))

M.reg(UIS.WindowFocusReleased:Connect(function()
	accelerating, decelerating = false, false
	flyUp, flyDown = false, false
	setHornKey(false)
end))

-- 转向滑条（独立 GUI；短按转向、长按拖动改位置，松手回中）
local steerGui = nil
local steerTrack = nil
local steerKnob = nil
local steerDragging = false
local steerMoving = false
local steerOrigin = Vector2.zero
local steerBasePos = UDim2.new()
local steerTween = nil
local STEER_W, STEER_H, STEER_KNOB_R = 150, 36, 14

local function steerSavePos()
	local vp = K.vp()
	local pos = steerTrack.Position
	local absX = pos.X.Scale * vp.X + pos.X.Offset
	local absY = pos.Y.Scale * vp.Y + pos.Y.Offset
	K.cfg.set("UI.Pos.SIBS_Steer", string.format("%.6f,%.0f,%.6f,%.0f",
		pos.X.Scale, math.floor(absX + 0.5), pos.Y.Scale, math.floor(absY + 0.5)))
end

local function steerReturnCenter()
	steerValue = 0
	if steerTween then pcall(function() steerTween:Cancel() end) end
	steerTween = TweenService:Create(steerKnob,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = UDim2.new(0.5, -STEER_KNOB_R, 0.5, -STEER_KNOB_R)})
	steerTween:Play()
end

local function createSteerSlider()
	steerGui = Instance.new("ScreenGui")
	steerGui.Name = "SIBS_Steer"
	steerGui.ResetOnSpawn = false
	steerGui.IgnoreGuiInset = true
	steerGui.DisplayOrder = 99999
	steerGui.Parent = getListRoot()

	steerTrack = mk("Frame", {
		Size = UDim2.fromOffset(STEER_W, STEER_H),
		Position = UDim2.new(0, 12, 0.55, -STEER_H / 2),
		BackgroundColor3 = CFG.BG,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Active = true,
	}, steerGui)

	mk("Frame", {
		Size = UDim2.new(0, 2, 0.6, 0),
		Position = UDim2.new(0.5, -1, 0.2, 0),
		BackgroundColor3 = Color3.fromRGB(80, 84, 100),
		BorderSizePixel = 0,
	}, steerTrack)

	steerKnob = mk("Frame", {
		Size = UDim2.fromOffset(STEER_KNOB_R * 2, STEER_KNOB_R * 2),
		Position = UDim2.new(0.5, -STEER_KNOB_R, 0.5, -STEER_KNOB_R),
		BackgroundColor3 = Color3.fromRGB(140, 190, 155),
		BorderSizePixel = 0,
	}, steerTrack)
	mk("UICorner", {CornerRadius = UDim.new(0.5, 0)}, steerKnob)

	-- 恢复保存的位置
	local saved = K.cfg.get("UI.Pos.SIBS_Steer", nil)
	if type(saved) == "string" then
		local sx, ox, sy, oy = saved:match("^([%-%d%.]+),([%-%d]+),([%-%d%.]+),([%-%d]+)$")
		if sx then
			local vp = K.vp()
			local cx = math.clamp(tonumber(ox) or 12, 0, math.max(vp.X - STEER_W, 0))
			local cy = math.clamp(tonumber(oy) or 0, 0, math.max(vp.Y - STEER_H, 0))
			steerTrack.Position = UDim2.new(tonumber(sx) or 0, cx, tonumber(sy) or 0.55, cy)
		end
	end

	M.reg(steerTrack.InputBegan:Connect(function(input)
		if not K.isP(input) then return end
		steerDragging = true
		steerMoving = false
		steerOrigin = Vector2.new(input.Position.X, input.Position.Y)
		steerBasePos = steerTrack.Position
		if steerTween then pcall(function() steerTween:Cancel() end) end
	end))

	M.reg(UIS.InputChanged:Connect(function(input)
		if not steerDragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local cur = Vector2.new(input.Position.X, input.Position.Y)
		local delta = cur - steerOrigin
		if not steerMoving and (math.abs(delta.X) + math.abs(delta.Y)) > 10 then
			steerMoving = true
		end
		if steerMoving then
			local vp = K.vp()
			local minX = -steerBasePos.X.Scale * vp.X
			local maxX = vp.X - STEER_W - steerBasePos.X.Scale * vp.X
			if minX > maxX then minX, maxX = maxX, minX end
			local minY = -steerBasePos.Y.Scale * vp.Y
			local maxY = vp.Y - STEER_H - steerBasePos.Y.Scale * vp.Y
			if minY > maxY then minY, maxY = maxY, minY end
			steerTrack.Position = UDim2.new(
				steerBasePos.X.Scale, math.clamp(steerBasePos.X.Offset + delta.X, minX, maxX),
				steerBasePos.Y.Scale, math.clamp(steerBasePos.Y.Offset + delta.Y, minY, maxY))
		else
			local usable = STEER_W - STEER_KNOB_R * 2
			local rel = (cur.X - steerTrack.AbsolutePosition.X - STEER_KNOB_R) / math.max(usable, 1)
			steerValue = math.clamp(rel * 2 - 1, -1, 1)
			local px = STEER_KNOB_R + usable * ((steerValue + 1) / 2)
			steerKnob.Position = UDim2.new(0, px - STEER_KNOB_R, 0.5, -STEER_KNOB_R)
		end
	end))

	local function steerRelease()
		if not steerDragging then return end
		steerDragging = false
		if steerMoving then steerSavePos() end
		steerMoving = false
		steerReturnCenter()
	end

	M.reg(UIS.InputEnded:Connect(function(input) if K.isP(input) then steerRelease() end end))
	M.reg(UIS.WindowFocusReleased:Connect(steerRelease))
end

createSteerSlider()

-- 初始座位同步（必须在 40 的灯光/引擎函数定义之后）
syncSeatFromContext()

-- 调试
M.debug(function()
	local lines = {}
	local function log(msg) lines[#lines + 1] = tostring(msg) end
	log("seat: " .. K.safeFullName(seat))
	log("lockPart: " .. K.safeFullName(lockPart) .. " (score=" .. tostring(lockPartScore) .. ")")
	log("lockModel: " .. K.safeFullName(lockModel))
	log("container: " .. K.safeFullName(getControlledVehicleModel()))
	log("owned: " .. tostring(lockModel ~= nil and playerOwnsModel(lockModel) or false))
	log("aim: " .. K.safeFullName(lastAim))
	log("myVehicle: " .. tostring(myVehicleName or "nil"))
	log("cruise: " .. tostring(cruise) .. " stopped: " .. tostring(stopped))
	log("locked: " .. tostring(locked))
	log("vehicleCount: " .. tostring(vehicleCount))
	log("noClip: " .. tostring(noClip))
	log("clipFalling: " .. tostring(clipFalling))
	log("carFly: " .. tostring(carFly))
	log("driveForce: " .. tostring(drive and drive.instance))
	log("flyForce: " .. tostring(carFlyHandle and carFlyHandle.instance))
	log("spinSpeed: " .. tostring(spinSpeed))
	log("steerValue: " .. tostring(steerValue))
	log("lightsOn: " .. tostring(lightsOn))
	log("hornKey: " .. tostring(hornKey and hornKey.Name) .. " found=" .. tostring(hornKeyFound))
	log("acceleration: " .. tostring(acceleration))
	log("targetSpeed: " .. tostring(targetSpeed))
	log("grounded: " .. tostring(lastGrounded))
	local control = seat or lockPart
	if control then
		local okVel, vel = pcall(function() return control.AssemblyLinearVelocity end)
		if okVel then log("velocity: " .. tostring(vel)) end
	end
	return K.debugDump(NAME, lines)
end)

-- 清理
M.done(function()
	accelerating, decelerating = false, false
	steerValue = 0
	cruise, stopped = false, false
	noClip, carFly = false, false
	flyUp, flyDown = false, false
	targetSpeed = 0
	flyVertVel = 0
	closeVehicleList()
	setSeat(nil)
	clearDrive()
	stopCarFly()
	if spinHandle then spinHandle.destroy(); spinHandle = nil end
	restoreClip()
	restoreLamps()
	collectEngineSounds()
	table.clear(engineSounds)
	setHornKey(false)
	resetLockState()
	myVehicleModel, myVehicleName, myVehicleAsm = nil, nil, nil
	if steerGui then pcall(function() steerGui:Destroy() end); steerGui = nil end
end)

print("[sibs] 就绪（转向滑条 / 旋转滑条 / 翻转 / 车列表 / 喇叭探测）")
