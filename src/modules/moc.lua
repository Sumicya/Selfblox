-- moc — 移动增强（模块名 MOC）
-- 依赖：kit v10；功能：速度(3 模式)/飞行/高跳/无限跳/穿墙/旋转/夜视/秒互动
-- 约定：缩进用单个 Tab

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")

local K = _G.KIT
if not K or K.ver < 10 or type(K.mod) ~= "function" then
	error("[moc] 请先执行 kit.lua（需要 _G.KIT v10）", 0)
end

local NAME = "MOC"
local mk = K.mk
local M = K.mod(NAME, {DisplayOrder = 99999, PanelW = 120})
local CFG = M.cfg
CFG.DefaultSpd = 16
CFG.DefaultFlySpd = 50
CFG.DefaultJumpHeight = 50
CFG.SpinDefault = 50
CFG.NvCCBrightness = 0.1
CFG.NvCCContrast = 0.16
CFG.NvCCSaturation = 0.15
CFG.NvRemoveFog = true
CFG.PromptDist = 1000
CFG.FlyMaxForce = math.huge
CFG.FlyMaxTorque = math.huge
CFG.FlyMaxAngVel = 8
CFG.FlyCollision = true
CFG.FlyCollisionDist = 5
CFG.PromptScanBatch = 300
CFG.RootAccel = 120
CFG.RootDecel = 160
CFG.CFrameDeadzone = 0.02
CFG.CFrameStickDeadzone = 0.06
CFG.CFrameGrace = 0.12
CFG.CFrameDirChange = 0.005
CFG.CFrameTouchMaxX = 0.55
CFG.CFrameTouchMinY = 0.25
CFG.JitterAmount = 0.015
CFG.JitterFreq = 3

-- 速度模式
local SPEED_MODES = {"RootVelocity", "WalkSpeed", "CFrame"}
local speedMode = "RootVelocity"
do
	local loaded = K.loadPrefixed(NAME, "SpeedMode", "RootVelocity")
	for _, mode in ipairs(SPEED_MODES) do
		if tostring(loaded) == mode then speedMode = mode; break end
	end
end

local spd = K.loadPrefixedNumber(NAME, "Spd", CFG.DefaultSpd)
local flySpeed = K.loadPrefixedNumber(NAME, "FlySpd", CFG.DefaultFlySpd)
local highJumpValue = K.loadPrefixedNumber(NAME, "Jump", CFG.DefaultJumpHeight)
local spinSpeed = K.loadPrefixedNumber(NAME, "Spin", CFG.SpinDefault)

-- 状态
local speedOn, fly, infJump, highJump, noClip, nv = false, false, false, false, false, false
local spinOn, spinActive = false, false
local flyTouchUp, flyTouchDown = false, false
local rootVelocityApplied = false
local char, root, hum = nil, nil, nil
local flyLv, flyAo, flyAtt = nil, nil, nil
local charParts, savedCol = {}, {}
local descAdded, descRemoving, seatConnection = nil, nil, nil
local defaultsCaptured = false
local defaultWalkSpeed = CFG.DefaultSpd
local defaultJumpPower = 0
local defaultJumpHeight = 0
local defaultUseJumpPower = true
local defaultPlatformStand = false
local speedApplied = false
local flySetter = nil
local speedModeButton = nil
local lastWalkSpeedApplied = nil
local cframeTouches = {}
local cframeLastDir = Vector3.zero
local cframeLastDirChange = os.clock()
local jitterPhase = 0
local lastFlyCollisionHit = nil
local spinDir = 1
local spinForce = nil

-- CFrame 触摸检测：屏幕左下区域且未点到 GUI 才算移动输入
local function isCFrameTouch(input)
	if input.UserInputType ~= Enum.UserInputType.Touch then return false end
	local ok, sel = pcall(function() return GuiService.SelectedObject end)
	if ok and sel then return false end
	local ok2, els = pcall(function()
		return GuiService:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
	end)
	if ok2 and els and #els > 0 then return false end
	local viewport = K.vp()
	return input.Position.X <= viewport.X * CFG.CFrameTouchMaxX
		and input.Position.Y >= viewport.Y * CFG.CFrameTouchMinY
end

M.reg(UIS.InputBegan:Connect(function(input)
	if isCFrameTouch(input) then cframeTouches[input] = true end
end))
M.reg(UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then cframeTouches[input] = nil end
end))
M.reg(UIS.WindowFocusReleased:Connect(function() table.clear(cframeTouches) end))

-- 射线参数：三套共用一个排除表，角色变更时只更新一次
local flyRayParams = RaycastParams.new()
flyRayParams.FilterType = Enum.RaycastFilterType.Exclude
local flyBoxParams = OverlapParams.new()
flyBoxParams.FilterType = Enum.RaycastFilterType.Exclude
local cframeRayParams = RaycastParams.new()
cframeRayParams.FilterType = Enum.RaycastFilterType.Exclude
local charFilterTable = {}

local function refreshSpeedModeButton()
	if not speedModeButton then return end
	speedModeButton.Text = "速度模式 " .. speedMode
	speedModeButton.BackgroundColor3 = speedOn and CFG.Col.On or CFG.Col.Off
end

local function isSeated()
	if not hum then return false end
	local ok, seatPart = pcall(function() return hum.SeatPart end)
	return ok and seatPart ~= nil
end

-- 飞行：LinearVelocity + AlignOrientation（朝向对齐相机水平面）
local function stopFly()
	if flyLv then pcall(function() flyLv:Destroy() end); flyLv = nil end
	if flyAo then pcall(function() flyAo:Destroy() end); flyAo = nil end
	if flyAtt then pcall(function() flyAtt:Destroy() end); flyAtt = nil end
	if hum and defaultsCaptured then pcall(function() hum.PlatformStand = defaultPlatformStand end) end
end

local function startFly()
	if not root or not hum then return end
	stopFly()
	pcall(function() hum.PlatformStand = true end)
	flyAtt = Instance.new("Attachment")
	flyAtt.Name = "MocFlyAtt"
	flyAtt.Parent = root
	flyLv = Instance.new("LinearVelocity")
	flyLv.Name = "MocFlyVelocity"
	flyLv.Attachment0 = flyAtt
	flyLv.VectorVelocity = Vector3.zero
	flyLv.MaxForce = CFG.FlyMaxForce
	flyLv.RelativeTo = Enum.ActuatorRelativeTo.World
	flyLv.Parent = root
	flyAo = Instance.new("AlignOrientation")
	flyAo.Name = "MocFlyOrientation"
	flyAo.Mode = Enum.OrientationAlignmentMode.OneAttachment
	flyAo.Attachment0 = flyAtt
	flyAo.CFrame = root.CFrame
	flyAo.MaxTorque = CFG.FlyMaxTorque
	pcall(function() flyAo.MaxAngularVelocity = CFG.FlyMaxAngVel end)
	flyAo.Parent = root
end

local function getVerticalInput()
	if K.isTyping() then return 0 end
	local value = 0
	if K.keyDown(Enum.KeyCode.Space) or K.keyDown(Enum.KeyCode.E) or flyTouchUp then value += 1 end
	if K.keyDown(Enum.KeyCode.LeftShift) or K.keyDown(Enum.KeyCode.Q) or flyTouchDown then value -= 1 end
	return value
end

-- 穿墙：只负责碰撞属性，不碰旋转
local function restoreCol()
	for part, value in pairs(savedCol) do
		if part and part.Parent then pcall(function() part.CanCollide = value end) end
	end
	table.clear(savedCol)
end

local function applyNoClipOnce()
	for part in pairs(charParts) do
		if part and part.Parent then
			if savedCol[part] == nil then savedCol[part] = part.CanCollide end
			if part.CanCollide then pcall(function() part.CanCollide = false end) end
		end
	end
end

-- 旋转（AngularVelocity 状态迁移驱动；与穿墙解耦）
local function stopSpin()
	if spinForce then spinForce.destroy(); spinForce = nil end
	spinActive = false
end

local function updateSpin()
	if not spinOn then
		if spinActive then stopSpin() end
		return
	end
	if not root or not root.Parent or root.Anchored or isSeated() then
		if spinActive then stopSpin() end
		return
	end
	if not spinActive then
		spinActive = true
		if spinForce then spinForce.destroy() end
		spinForce = K.force.angular(root, "MOC_Spin")
	end
	if spinForce and (not spinForce.alive() or spinForce.part ~= root) then
		spinForce.destroy()
		spinForce = K.force.angular(root, "MOC_Spin")
	end
	if spinForce then
		spinForce.set(Vector3.new(0, spinSpeed * spinDir, 0))
	end
end

-- 角色绑定
local function setupCharacter(character, humanoid, rootPart)
	if not M.bag.alive() then return end
	char = character
	hum = humanoid
	root = rootPart
	if hum then
		pcall(function()
			defaultWalkSpeed = hum.WalkSpeed
			defaultJumpPower = hum.JumpPower
			defaultJumpHeight = hum.JumpHeight
			defaultUseJumpPower = hum.UseJumpPower
			defaultPlatformStand = hum.PlatformStand
			defaultsCaptured = true
		end)
	end
	speedApplied = false
	rootVelocityApplied = false
	lastWalkSpeedApplied = nil
	table.clear(cframeTouches)
	cframeLastDir = Vector3.zero
	cframeLastDirChange = os.clock()
	stopSpin()
	if seatConnection then M.bag.unreg(seatConnection); seatConnection = nil end
	if hum then
		seatConnection = hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
			if fly and hum.SeatPart then
				if flySetter then flySetter(false)
				else fly = false; stopFly() end
			end
		end)
		M.reg(seatConnection)
	end
	table.clear(charParts)
	table.clear(savedCol)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			charParts[descendant] = true
			savedCol[descendant] = descendant.CanCollide
		end
	end
	if descAdded then M.bag.unreg(descAdded); descAdded = nil end
	if descRemoving then M.bag.unreg(descRemoving); descRemoving = nil end
	descAdded = character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			charParts[descendant] = true
			if savedCol[descendant] == nil then savedCol[descendant] = descendant.CanCollide end
			if noClip then pcall(function() descendant.CanCollide = false end) end
		end
	end)
	descRemoving = character.DescendantRemoving:Connect(function(descendant)
		charParts[descendant] = nil
		savedCol[descendant] = nil
	end)
	M.reg(descAdded)
	M.reg(descRemoving)
	table.clear(charFilterTable)
	charFilterTable[1] = character
	flyRayParams.FilterDescendantsInstances = charFilterTable
	flyBoxParams.FilterDescendantsInstances = charFilterTable
	cframeRayParams.FilterDescendantsInstances = charFilterTable
	if noClip then
		task.defer(function()
			if M.bag.alive() and noClip and char == character then applyNoClipOnce() end
		end)
	end
end

K.watchCharacter(M.bag, {
	ready = setupCharacter,
	removed = function(old)
		if old ~= char then return end
		stopFly()
		stopSpin()
		restoreCol()
		if seatConnection then M.bag.unreg(seatConnection); seatConnection = nil end
		if descAdded then M.bag.unreg(descAdded); descAdded = nil end
		if descRemoving then M.bag.unreg(descRemoving); descRemoving = nil end
		char, root, hum = nil, nil, nil
		table.clear(charParts)
		table.clear(savedCol)
		speedApplied = false
		rootVelocityApplied = false
		lastWalkSpeedApplied = nil
		table.clear(cframeTouches)
	end,
}, {requireRoot = false})

M.reg(UIS.JumpRequest:Connect(function()
	if infJump and hum and not K.isTyping() then
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
	end
end))

-- CFrame 速度：每帧直接写 CFrame（含贴墙滑动、贴地吸附、微抖动防判定）
local function cFrameHasRealInput()
	if K.isTyping() then return false end
	if K.keyDown(Enum.KeyCode.W) or K.keyDown(Enum.KeyCode.A)
		or K.keyDown(Enum.KeyCode.S) or K.keyDown(Enum.KeyCode.D)
		or K.keyDown(Enum.KeyCode.Up) or K.keyDown(Enum.KeyCode.Down)
		or K.keyDown(Enum.KeyCode.Left) or K.keyDown(Enum.KeyCode.Right) then
		return true
	end
	local ok, state = pcall(function() return UIS:GetGamepadState(Enum.UserInputType.Gamepad1) end)
	if ok and state then
		for _, input in ipairs(state) do
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				local v = Vector3.new(input.Position.X, 0, input.Position.Y)
				if v.Magnitude > CFG.CFrameStickDeadzone then return true end
			end
		end
	end
	for _ in pairs(cframeTouches) do return true end
	return false
end

local function getJitterOffset(dt)
	jitterPhase += dt * CFG.JitterFreq
	local jx = math.sin(jitterPhase * 2.1) * CFG.JitterAmount
	local jz = math.cos(jitterPhase * 1.7) * CFG.JitterAmount
	return Vector3.new(jx, 0, jz)
end

local function updateCFrameSpeed(dt)
	if not (speedOn and root and hum and root.Parent) then return end
	if fly or isSeated() or K.isTyping() or hum.Health <= 0 or root.Anchored then return end
	dt = math.clamp(dt, 0, 0.05)
	local now = os.clock()
	local md = hum.MoveDirection or Vector3.zero
	if md.Magnitude > CFG.CFrameDeadzone then
		if (md - cframeLastDir).Magnitude > CFG.CFrameDirChange then
			cframeLastDir = md
			cframeLastDirChange = now
		end
	else
		cframeLastDir = Vector3.zero
		cframeLastDirChange = now
	end
	local horizontal = Vector3.new(md.X, 0, md.Z)
	local canMove = false
	if horizontal.Magnitude > CFG.CFrameDeadzone then
		if cFrameHasRealInput() then canMove = true
		elseif now - cframeLastDirChange < CFG.CFrameGrace then canMove = true end
	end
	if not canMove then return end

	local dir = horizontal.Unit
	local stepDist = spd * dt
	local moveOffset = dir * stepDist
	if not noClip and char then
		local wallHit = workspace:Raycast(root.Position, dir * (stepDist + 1.2), cframeRayParams)
		if wallHit and wallHit.Instance and wallHit.Instance.CanCollide then
			local normal = wallHit.Normal
			local slideDir = dir - normal * dir:Dot(normal)
			if slideDir.Magnitude > 0.05 then moveOffset = slideDir.Unit * stepDist
			else moveOffset = Vector3.zero end
		end
	end
	local currentPos = root.Position
	local currentCF = root.CFrame
	local targetY = currentPos.Y
	if char then
		local groundHit = workspace:Raycast(currentPos + Vector3.new(0, 2.5, 0),
			Vector3.new(0, -9, 0), cframeRayParams)
		if groundHit then
			local hip = (hum and hum.HipHeight > 0) and hum.HipHeight or 2
			local idealY = groundHit.Position.Y + hip + (root.Size.Y * 0.5)
			targetY = math.clamp(idealY, currentPos.Y - 2.5, currentPos.Y + 2.5)
		end
	end
	local jitter = getJitterOffset(dt)
	local newPos = Vector3.new(currentPos.X + moveOffset.X, targetY, currentPos.Z + moveOffset.Z) + jitter
	pcall(function()
		root.CFrame = CFrame.new(newPos) * (currentCF - currentCF.Position)
	end)
end

-- RootVelocity 速度：加速度限制的水平速度接管
local function clearRootVelocity()
	if root and root.Parent then
		local cur = root.AssemblyLinearVelocity
		pcall(function() root.AssemblyLinearVelocity = Vector3.new(0, cur.Y, 0) end)
	end
	rootVelocityApplied = false
end

local function updateRootVelocity(dt)
	if fly or isSeated() or not (root and root.Parent) then
		-- 退出时归零，避免高速状态上车或切飞行后持续滑行
		if rootVelocityApplied then clearRootVelocity() end
		return
	end
	if not speedOn and not rootVelocityApplied then return end
	local moveDir = hum and hum.MoveDirection or Vector3.zero
	local target = Vector3.zero
	if speedOn and moveDir.Magnitude > 0 then
		local horizontalMove = Vector3.new(moveDir.X, 0, moveDir.Z)
		if horizontalMove.Magnitude > 0 then target = horizontalMove.Unit * spd end
	end
	local current = root.AssemblyLinearVelocity
	local horizontal = Vector3.new(current.X, 0, current.Z)
	local accel = target.Magnitude > 0 and CFG.RootAccel or CFG.RootDecel
	local maxDelta = accel * dt
	local delta = target - horizontal
	if delta.Magnitude > maxDelta then delta = delta.Unit * maxDelta end
	local newHorizontal = horizontal + delta
	if not speedOn and newHorizontal.Magnitude < 0.05 then
		newHorizontal = Vector3.zero
		rootVelocityApplied = false
	end
	pcall(function()
		root.AssemblyLinearVelocity = Vector3.new(newHorizontal.X, current.Y, newHorizontal.Z)
	end)
	if speedOn then rootVelocityApplied = true end
end

local function updateSpeed(dt)
	if speedMode == "WalkSpeed" then
		if not hum then return end
		if speedOn then
			if lastWalkSpeedApplied ~= spd then
				pcall(function() hum.WalkSpeed = spd end)
				lastWalkSpeedApplied = spd
			end
			speedApplied = true
		elseif speedApplied then
			pcall(function() hum.WalkSpeed = defaultWalkSpeed end)
			speedApplied = false
			lastWalkSpeedApplied = nil
		end
	elseif speedMode == "RootVelocity" then
		if hum and root then updateRootVelocity(dt) end
	elseif speedMode == "CFrame" then
		updateCFrameSpeed(dt)
	end
end

-- 高跳（尊重原版 UseJumpPower 模式）
local function updateHighJump()
	if not (highJump and hum) then return end
	pcall(function()
		if defaultUseJumpPower then
			if hum.UseJumpPower ~= true or hum.JumpPower ~= highJumpValue then
				hum.UseJumpPower = true
				hum.JumpPower = highJumpValue
			end
		else
			if hum.UseJumpPower ~= false or hum.JumpHeight ~= highJumpValue then
				hum.UseJumpPower = false
				hum.JumpHeight = highJumpValue
			end
		end
	end)
end

local function restoreJump()
	if not (hum and defaultsCaptured) then return end
	pcall(function()
		hum.UseJumpPower = defaultUseJumpPower
		hum.JumpPower = defaultJumpPower
		hum.JumpHeight = defaultJumpHeight
	end)
end

-- 飞行碰撞：前向射线 + 前方盒扫，命中实体速度投影避免穿模
local function isSolidCollisionInstance(instance)
	if not instance then return false end
	if instance:IsA("Terrain") then return true end
	local ok, value = pcall(function() return instance.CanCollide end)
	return ok and value == true
end

local function checkFlyCollision(velocity)
	lastFlyCollisionHit = nil
	if not CFG.FlyCollision or not root or velocity.Magnitude < 0.1 then return velocity end
	local hit = workspace:Raycast(root.Position, velocity.Unit * CFG.FlyCollisionDist, flyRayParams)
	if hit and isSolidCollisionInstance(hit.Instance) then
		lastFlyCollisionHit = hit.Instance
		local normal = hit.Normal
		local dot = velocity:Dot(normal)
		if dot < 0 then velocity = velocity - normal * dot end
		return velocity
	end
	local scanDist = CFG.FlyCollisionDist * 1.5
	local scanCF = CFrame.new(
		root.Position + velocity.Unit * (scanDist * 0.5),
		root.Position + velocity.Unit * scanDist
	)
	local ok, parts = pcall(function()
		return workspace:GetPartBoundsInBox(scanCF, Vector3.new(2, 2, 2), flyBoxParams)
	end)
	if ok and parts and #parts > 0 then
		for _, candidate in ipairs(parts) do
			if isSolidCollisionInstance(candidate) then
				lastFlyCollisionHit = candidate
				velocity = velocity * 0.5
				break
			end
		end
	end
	return velocity
end

local function getFlyInput()
	local fb, lr = 0, 0
	if not K.isTyping() then
		if K.keyDown(Enum.KeyCode.W) or K.keyDown(Enum.KeyCode.Up) then fb += 1 end
		if K.keyDown(Enum.KeyCode.S) or K.keyDown(Enum.KeyCode.Down) then fb -= 1 end
		if K.keyDown(Enum.KeyCode.D) or K.keyDown(Enum.KeyCode.Right) then lr += 1 end
		if K.keyDown(Enum.KeyCode.A) or K.keyDown(Enum.KeyCode.Left) then lr -= 1 end
	end
	local ok, state = pcall(function() return UIS:GetGamepadState(Enum.UserInputType.Gamepad1) end)
	if ok and state then
		for _, input in ipairs(state) do
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				if math.abs(input.Position.Y) > 0.15 then fb += input.Position.Y end
				if math.abs(input.Position.X) > 0.15 then lr += input.Position.X end
			end
		end
	end
	return math.clamp(fb, -1, 1), math.clamp(lr, -1, 1)
end

local function updateFly()
	if fly and isSeated() then
		if flySetter then flySetter(false) else fly = false; stopFly() end
		return
	end
	if fly and root and hum then
		if not flyLv or flyLv.Parent ~= root then startFly() end
		local camera = workspace.CurrentCamera
		if camera and flyLv and flyAo then
			local camCF = camera.CFrame
			local look = camCF.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude > 0.001 then
				pcall(function() flyAo.CFrame = CFrame.lookAt(Vector3.zero, flatLook) end)
			end
			local fb, lr = getFlyInput()
			local velocity = Vector3.zero
			local forward = camCF.LookVector
			local rightFlat = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)
			if rightFlat.Magnitude > 0.001 then rightFlat = rightFlat.Unit else rightFlat = Vector3.new(1, 0, 0) end
			if fb ~= 0 or lr ~= 0 then
				velocity = forward * (fb * flySpeed) + rightFlat * (lr * flySpeed)
			else
				local md = hum.MoveDirection
				if md.Magnitude > 0.01 then
					local flatForward = Vector3.new(forward.X, 0, forward.Z)
					if flatForward.Magnitude > 0.001 then flatForward = flatForward.Unit
					else flatForward = Vector3.new(0, 0, -1) end
					local moveH = Vector3.new(md.X, 0, md.Z).Unit
					local dotFwd = moveH:Dot(flatForward)
					velocity = moveH * flySpeed + Vector3.new(0, forward.Y * dotFwd * flySpeed, 0)
				end
			end
			velocity = velocity + Vector3.new(0, getVerticalInput() * flySpeed, 0)
			velocity = checkFlyCollision(velocity)
			pcall(function() flyLv.VectorVelocity = velocity end)
		end
	elseif flyLv or flyAo or flyAtt then
		stopFly()
	end
end

-- 穿墙节流清扫（30Hz，补新增部件）
local noClipNextSweep = 0
local NOCLIP_SWEEP_INTERVAL = 1 / 30

local function updateNoClip()
	if not noClip then return end
	local now = os.clock()
	if now < noClipNextSweep then return end
	noClipNextSweep = now + NOCLIP_SWEEP_INTERVAL
	applyNoClipOnce()
end

-- 夜视：ColorCorrection + 灯光保存/还原 + 可选去雾
local nvEffect = nil
local nvNextCheck = 0
local nvSavedLighting = nil
local nvFogAtm = nil

local function nvClearEffect()
	if nvEffect then pcall(function() nvEffect:Destroy() end); nvEffect = nil end
end

local function nvCapture()
	if nvSavedLighting then return end
	nvSavedLighting = {
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		Brightness = Lighting.Brightness,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		FogColor = Lighting.FogColor,
	}
end

local function nvApply()
	nvCapture()
	pcall(function()
		Lighting.Ambient = Color3.fromRGB(150, 150, 150)
		Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 150)
		Lighting.Brightness = math.max(Lighting.Brightness, 2)
		if CFG.NvRemoveFog then Lighting.FogEnd = 1e6 end
	end)
	if CFG.NvRemoveFog then
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		if atm and atm.Parent then
			if not nvFogAtm then nvFogAtm = atm end
			pcall(function() atm.Parent = nil end)
		end
	end
end

local function nvRestore()
	if nvFogAtm and not nvFogAtm.Parent then
		if Lighting:FindFirstChildOfClass("Atmosphere") then
			pcall(function() nvFogAtm:Destroy() end)
		else
			pcall(function() nvFogAtm.Parent = Lighting end)
		end
	end
	nvFogAtm = nil
	if nvSavedLighting then
		for prop, val in pairs(nvSavedLighting) do
			pcall(function() Lighting[prop] = val end)
		end
		nvSavedLighting = nil
	end
end

local function nvSync()
	if not nv then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	if nvEffect and nvEffect.Parent ~= cam then nvClearEffect() end
	if not nvEffect or not nvEffect.Parent then
		pcall(function()
			local cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "MocNV"
			cc.Brightness = CFG.NvCCBrightness
			cc.Contrast = CFG.NvCCContrast
			cc.Saturation = CFG.NvCCSaturation
			cc.Enabled = true
			cc.Parent = cam
			nvEffect = cc
		end)
	end
	nvApply()
end

local function setNV(on)
	nv = on
	if on then nvSync()
	else nvClearEffect(); nvRestore() end
end

M.reg(RunService.Heartbeat:Connect(function()
	if not nv then return end
	local now = os.clock()
	if now < nvNextCheck then return end
	nvNextCheck = now + 0.5
	nvSync()
end))

-- 秒互动：off/normal/force 三态，直接改写 ProximityPrompt 属性
local NOCD_MODES = {"off", "normal", "force"}
local noCdModeIndex = 1
local noCdVersion = 0
local promptSaved = setmetatable({}, {__mode = "k"})

local function currentNoCdMode() return NOCD_MODES[noCdModeIndex] end
local function noCdActive() return noCdModeIndex > 1 end

local function patchPrompt(obj)
	if not obj or not obj:IsA("ProximityPrompt") or promptSaved[obj] then return end
	local force = currentNoCdMode() == "force"
	local okEnabled, enabled = pcall(function() return obj.Enabled end)
	if not okEnabled then return end
	if not force and not enabled then return end
	promptSaved[obj] = {
		hold = obj.HoldDuration,
		dist = obj.MaxActivationDistance,
		enabled = obj.Enabled,
		los = obj.RequiresLineOfSight,
	}
	pcall(function()
		if force then obj.Enabled = true end
		obj.HoldDuration = 0
		obj.MaxActivationDistance = math.max(obj.MaxActivationDistance, CFG.PromptDist)
		obj.RequiresLineOfSight = false
	end)
end

local function restorePrompts()
	for obj, saved in pairs(promptSaved) do
		if obj.Parent then
			pcall(function()
				obj.HoldDuration = saved.hold
				obj.MaxActivationDistance = saved.dist
				obj.Enabled = saved.enabled
				obj.RequiresLineOfSight = saved.los
			end)
		end
	end
	table.clear(promptSaved)
end

local PROMPT_SCAN_CAP = 15000

local function scanPrompts()
	local v = noCdVersion
	task.spawn(function()
		K.guard("moc:promptScan", function()
			local count = 0
			for _, descendant in ipairs(workspace:GetDescendants()) do
				if v ~= noCdVersion then return end
				if descendant:IsA("ProximityPrompt") then
					patchPrompt(descendant)
					count += 1
					if count > PROMPT_SCAN_CAP then break end
					if count % CFG.PromptScanBatch == 0 then task.wait() end
				end
			end
		end)
	end)
end

local function setNoCdMode(mode)
	for i, v in ipairs(NOCD_MODES) do
		if v == mode then noCdModeIndex = i; break end
	end
	noCdVersion += 1
	restorePrompts()
	if noCdActive() then scanPrompts() end
end

M.reg(workspace.DescendantAdded:Connect(function(descendant)
	if noCdActive() and descendant:IsA("ProximityPrompt") then patchPrompt(descendant) end
end))

-- 主循环
local simDt = K.dtTracker(0.1)

M.reg(RunService.PreSimulation:Connect(function(step)
	K.heartbeat()
	if not char or not char:IsDescendantOf(workspace) then return end
	local deltaTime = simDt(step)
	updateSpeed(deltaTime)
	updateHighJump()
	updateFly()
	updateNoClip()
	updateSpin()
end))

-- GUI
local INPUT_ROWS = 5
local GRID_ROWS = 4
local totalH = CFG.TitleH + CFG.RowH * INPUT_ROWS + CFG.RowH * GRID_ROWS
CFG.PanelSize = UDim2.new(0, CFG.PanelW, 0, totalH)
CFG.PanelPos = UDim2.new(0.5, -CFG.PanelW / 2, 0.4, -totalH / 2)
CFG.CollapseSize = UDim2.new(0, CFG.PanelW, 0, CFG.TitleH)

local main = M.panel()
K.titleBar(main, CFG, M.bag, "移动增强", CFG.TitleH)

K.makeToggleRow(main, CFG.TitleH, CFG.RowH, "速度", false, function(on)
	speedOn = on
	if not on then
		if speedMode == "WalkSpeed" and hum then
			pcall(function() hum.WalkSpeed = defaultWalkSpeed end)
			speedApplied = false
			lastWalkSpeedApplied = nil
		end
		table.clear(cframeTouches)
	end
	refreshSpeedModeButton()
end, function() return spd end, function(val)
	spd = val
	K.savePrefixed(NAME, "Spd", spd)
end, M.bag, CFG)

speedModeButton = K.btn(main, {
	Size = UDim2.new(1, 0, 0, CFG.RowH),
	Position = UDim2.new(0, 0, 0, CFG.TitleH + CFG.RowH),
	BackgroundColor3 = CFG.Col.Off,
	Text = "速度模式 " .. speedMode,
}, CFG)
refreshSpeedModeButton()

M.reg(speedModeButton.Activated:Connect(function()
	local oldMode = speedMode
	local index = 1
	for i, mode in ipairs(SPEED_MODES) do
		if mode == speedMode then index = i; break end
	end
	index = index % #SPEED_MODES + 1
	speedMode = SPEED_MODES[index]
	if oldMode == "WalkSpeed" and speedApplied and hum then
		pcall(function() hum.WalkSpeed = defaultWalkSpeed end)
		speedApplied = false
		lastWalkSpeedApplied = nil
	end
	if oldMode == "RootVelocity" then rootVelocityApplied = false end
	if oldMode == "CFrame" then table.clear(cframeTouches) end
	K.savePrefixed(NAME, "SpeedMode", speedMode)
	refreshSpeedModeButton()
end))

_, _, flySetter = K.makeToggleRow(main, CFG.TitleH + CFG.RowH * 2, CFG.RowH, "飞行", false, function(on)
	fly = on
	if not on then stopFly() end
end, function() return flySpeed end, function(val)
	flySpeed = val
	K.savePrefixed(NAME, "FlySpd", flySpeed)
end, M.bag, CFG)

K.makeToggleRow(main, CFG.TitleH + CFG.RowH * 3, CFG.RowH, "高跳", false, function(on)
	highJump = on
	if not on then restoreJump() end
end, function() return highJumpValue end, function(val)
	highJumpValue = val
	K.savePrefixed(NAME, "Jump", highJumpValue)
end, M.bag, CFG)

K.fullInput(main, CFG.TitleH + CFG.RowH * 4, CFG.RowH, "转速", CFG.Col.Push,
	function() return spinSpeed end,
	function(v) spinSpeed = v; K.savePrefixed(NAME, "Spin", spinSpeed) end,
	M.bag, CFG)

local grid = mk("Frame", {
	Size = UDim2.new(1, 0, 0, CFG.RowH * GRID_ROWS),
	Position = UDim2.new(0, 0, 0, CFG.TitleH + CFG.RowH * INPUT_ROWS),
	BackgroundTransparency = 1,
}, main)

mk("UIGridLayout", {
	CellSize = UDim2.new(0.5, 0, 1 / GRID_ROWS, 0),
	CellPadding = UDim2.new(0, 0, 0, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, grid)

local function gridBtn(text, order, onClick)
	return K.mkBtn(grid, text, CFG.Col.Off, order, onClick, M.bag, CFG)
end

gridBtn(K.toggleText("无限跳", infJump), 1, function(button)
	infJump = not infJump
	button.Text = K.toggleText("无限跳", infJump)
	button.BackgroundColor3 = infJump and CFG.Col.On or button:GetAttribute("Base")
end)

gridBtn(K.toggleText("穿墙", noClip), 2, function(button)
	noClip = not noClip
	button.Text = K.toggleText("穿墙", noClip)
	button.BackgroundColor3 = noClip and CFG.Col.On or button:GetAttribute("Base")
	if noClip then applyNoClipOnce() else restoreCol() end
end)

gridBtn(K.toggleText("旋转", spinOn), 3, function(button)
	spinOn = not spinOn
	button.Text = K.toggleText("旋转", spinOn)
	button.BackgroundColor3 = spinOn and CFG.Col.On or button:GetAttribute("Base")
end)

gridBtn(K.toggleText("夜视", nv), 4, function(button)
	setNV(not nv)
	button.Text = K.toggleText("夜视", nv)
	button.BackgroundColor3 = nv and CFG.Col.On or button:GetAttribute("Base")
end)

gridBtn("秒互动 关", 5, function(button)
	noCdModeIndex = noCdModeIndex % #NOCD_MODES + 1
	setNoCdMode(NOCD_MODES[noCdModeIndex])
	local mode = currentNoCdMode()
	button.Text = mode == "off" and "秒互动 关" or (mode == "normal" and "秒互动 普通" or "秒互动 强制")
	button.BackgroundColor3 = noCdActive() and CFG.Col.On or button:GetAttribute("Base")
end)

gridBtn("换向 ▶", 6, function(button)
	spinDir = -spinDir
	button.Text = spinDir == 1 and "换向 ▶" or "换向 ◀"
end)

local flyUpButton = gridBtn("按住上升", 7, function() end)
local flyDownButton = gridBtn("按住下降", 8, function() end)
K.holdButton(flyUpButton, M.bag, function() flyTouchUp = true end, function() flyTouchUp = false end)
K.holdButton(flyDownButton, M.bag, function() flyTouchDown = true end, function() flyTouchDown = false end)

M.reg(UIS.WindowFocusReleased:Connect(function()
	flyTouchUp, flyTouchDown = false, false
end))

-- 调试
M.debug(function()
	local lines = {}
	local function log(msg) lines[#lines + 1] = tostring(msg) end
	log("speedOn: " .. tostring(speedOn))
	log("speedMode: " .. tostring(speedMode))
	log("spd: " .. tostring(spd))
	log("fly: " .. tostring(fly))
	log("flySpeed: " .. tostring(flySpeed))
	log("infJump: " .. tostring(infJump))
	log("highJump: " .. tostring(highJump))
	log("highJumpValue: " .. tostring(highJumpValue))
	log("noClip: " .. tostring(noClip) .. " tracked=" .. tostring(next(savedCol) ~= nil))
	log("spinOn: " .. tostring(spinOn) .. " active=" .. tostring(spinActive) .. " dir=" .. tostring(spinDir))
	log("spinSpeed: " .. tostring(spinSpeed))
	log("nv: " .. tostring(nv))
	log("noCdMode: " .. tostring(currentNoCdMode()))
	log("char: " .. tostring(char))
	log("root: " .. tostring(root))
	log("hum: " .. tostring(hum))
	if hum then
		log("WalkSpeed: " .. tostring(hum.WalkSpeed))
		log("JumpPower: " .. tostring(hum.JumpPower))
		log("SeatPart: " .. tostring(hum.SeatPart))
		log("Health: " .. tostring(hum.Health))
	end
	if root then
		log("root.AssemblyLinearVelocity: " .. tostring(root.AssemblyLinearVelocity))
		log("root.Anchored: " .. tostring(root.Anchored))
	end
	log("flyCollisionHit: " .. tostring(lastFlyCollisionHit))
	log("kitErrors(moc): " .. tostring(#K.getErrors("moc:promptScan")))
	return K.debugDump(NAME, lines)
end)

-- 清理
M.done(function()
	speedOn, fly, infJump, highJump, noClip, nv, spinOn = false, false, false, false, false, false, false
	flyTouchUp, flyTouchDown = false, false
	stopFly()
	stopSpin()
	if speedMode == "WalkSpeed" and hum then
		pcall(function() hum.WalkSpeed = defaultWalkSpeed end)
	end
	speedApplied = false
	rootVelocityApplied = false
	lastWalkSpeedApplied = nil
	table.clear(cframeTouches)
	restoreCol()
	restoreJump()
	setNV(false)
	setNoCdMode("off")
end)

print("[KIT] moc ready")