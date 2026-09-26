-- Selfblox · MOC — 移动增强（独立单文件）
-- v11 激进重写：无框架 / 无构建 / 现代 Luau / 原生 API 优先
-- 用法: loadstring(game:HttpGet(".../moc.lua"))()
-- 功能: 速度(RootVelocity/WalkSpeed/CFrame 三档) / 飞行 / 高跳 / 无限跳 / 穿墙 / 旋转 / 夜视 / 秒互动

local NAME = "MOC"

-- ===== 0. 重跑替换旧实例 =====

local OLD = rawget(_G, "SB_" .. NAME)
if type(OLD) == "function" then
	pcall(OLD)
end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local GuiRoot = (pcall(function() return gethui() end) and gethui()) or game:GetService("CoreGui")

local conns = {}
local function reg(c)
	conns[#conns + 1] = c
	return c
end

local function mk(className, props, parent)
	local inst = Instance.new(className, props)
	if parent then
		inst.Parent = parent
	end
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

-- ===== 2. 默认值与状态 =====

local DEF = {
	Spd = 16, FlySpd = 50, Jump = 50, Spin = 50,
	NvCCBrightness = 0.1, NvCCContrast = 0.16, NvCCSaturation = 0.15, NvRemoveFog = true,
	PromptDist = 1000, FlyMaxForce = math.huge, FlyMaxTorque = math.huge, FlyMaxAngVel = 8,
	FlyCollision = true, FlyCollisionDist = 5, PromptScanBatch = 300,
	RootAccel = 120, RootDecel = 160,
	CFrameDeadzone = 0.02, CFrameStickDeadzone = 0.06, CFrameGrace = 0.12,
	CFrameDirChange = 0.005, CFrameTouchMaxX = 0.55, CFrameTouchMinY = 0.25,
	JitterAmount = 0.015, JitterFreq = 3,
}

local COL = {
	On = Color3.fromRGB(38, 125, 85), Off = Color3.fromRGB(48, 50, 60),
	Good = Color3.fromRGB(135, 215, 155), Bad = Color3.fromRGB(225, 135, 135),
	Wait = Color3.fromRGB(170, 175, 185), Bind = Color3.fromRGB(95, 65, 135),
	Danger = Color3.fromRGB(155, 45, 45), Accel = Color3.fromRGB(30, 85, 115),
	Decel = Color3.fromRGB(130, 90, 40),
}
local BG = Color3.fromRGB(20, 22, 28)
local ALPHA = 0.72
local TITLE_H, ROW_H, PANEL_W, SAFE_TOP = 20, 30, 120, 48

local SPEED_MODES = { "RootVelocity", "WalkSpeed", "CFrame" }
local speedMode = tostring(cfgGet("MOCSpeedMode", "RootVelocity"))
do
	local valid = false
	for _, m in ipairs(SPEED_MODES) do
		if m == speedMode then
			valid = true
		end
	end
	if not valid then
		speedMode = "RootVelocity"
	end
end
local spd = cfgGetNum("MOCSpd", DEF.Spd)
local flySpeed = cfgGetNum("MOCFlySpd", DEF.FlySpd)
local highJumpValue = cfgGetNum("MOCJump", DEF.Jump)
local spinSpeed = cfgGetNum("MOCSpin", DEF.Spin)

local speedOn, fly, infJump, highJump, noClip, nv = false, false, false, false, false, false
local spinOn, spinActive, spinDir = false, false, 1
local flyTouchUp, flyTouchDown = false, false
local rootVelocityApplied = false
local character, root, hum = nil, nil, nil
local flyLv, flyAo, flyAtt = nil, nil, nil
local charParts, savedCol = {}, {}
local descAdded, descRemoving, seatConnection = nil, nil, nil
local defaultsCaptured = false
local defaultWalkSpeed, defaultJumpPower, defaultJumpHeight = DEF.Spd, 0, 0
local defaultUseJumpPower, defaultPlatformStand = true, false
local speedApplied = false
local flySetter = nil
local speedModeButton = nil
local lastWalkSpeedApplied = nil
local cframeTouches = {}
local cframeLastDir = Vector3.zero
local cframeLastDirChange = os.clock()
local jitterPhase = 0
local alive = true

-- CFrame 触摸检测：屏幕左下区域且未点到 GUI 才算移动输入
local function isCFrameTouch(input)
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return false
	end
	local ok, sel = pcall(function() return GuiService.SelectedObject end)
	if ok and sel then
		return false
	end
	local ok2, els = pcall(function()
		return GuiService:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
	end)
	if ok2 and els and #els > 0 then
		return false
	end
	local vp = workspace.CurrentCamera.ViewportSize
	return input.Position.X <= vp.X * DEF.CFrameTouchMaxX
		and input.Position.Y >= vp.Y * DEF.CFrameTouchMinY
end

reg(UIS.InputBegan:Connect(function(input)
	if isCFrameTouch(input) then
		cframeTouches[input] = true
	end
end))
reg(UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		cframeTouches[input] = nil
	end
end))
reg(UIS.WindowFocusReleased:Connect(function()
	table.clear(cframeTouches)
	flyTouchUp, flyTouchDown = false, false
end))

-- 射线参数：三套共用一个排除表
local flyRayParams = RaycastParams.new()
flyRayParams.FilterType = Enum.RaycastFilterType.Exclude
local flyBoxParams = OverlapParams.new()
flyBoxParams.FilterType = Enum.RaycastFilterType.Exclude
local cframeRayParams = RaycastParams.new()
cframeRayParams.FilterType = Enum.RaycastFilterType.Exclude
local charFilterTable = {}

-- ===== 3. 输入 =====

local function isTyping()
	return UIS:GetFocusedTextBox() ~= nil
end

local function keyDown(code)
	return UIS.KeyboardEnabled and not isTyping() and UIS:IsKeyDown(code)
end

local function getStick()
	local ok, state = pcall(function() return UIS:GetGamepadState(Enum.UserInputType.Gamepad1) end)
	if not ok or not state then
		return nil
	end
	for _, input in ipairs(state) do
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			return Vector3.new(input.Position.X, 0, input.Position.Y)
		end
	end
	return nil
end

local function isSeated()
	if not hum then
		return false
	end
	local ok, seatPart = pcall(function() return hum.SeatPart end)
	return ok and seatPart ~= nil
end

-- ===== 4. 飞行 =====

local function stopFly()
	if flyLv then
		pcall(function() flyLv:Destroy() end)
		flyLv = nil
	end
	if flyAo then
		pcall(function() flyAo:Destroy() end)
		flyAo = nil
	end
	if flyAtt then
		pcall(function() flyAtt:Destroy() end)
		flyAtt = nil
	end
	if hum and defaultsCaptured then
		pcall(function() hum.PlatformStand = defaultPlatformStand end)
	end
end

local function startFly()
	if not root or not hum then
		return
	end
	stopFly()
	pcall(function() hum.PlatformStand = true end)
	flyAtt = mk("Attachment", { Name = "MocFlyAtt" }, root)
	flyLv = mk("LinearVelocity", {
		Name = "MocFlyVelocity", Attachment0 = flyAtt, VectorVelocity = Vector3.zero,
		MaxForce = DEF.FlyMaxForce, RelativeTo = Enum.ActuatorRelativeTo.World,
	}, root)
	flyAo = mk("AlignOrientation", {
		Name = "MocFlyOrientation", Mode = Enum.OrientationAlignmentMode.OneAttachment,
		Attachment0 = flyAtt, CFrame = root.CFrame, MaxTorque = DEF.FlyMaxTorque,
	}, root)
	pcall(function() flyAo.MaxAngularVelocity = DEF.FlyMaxAngVel end)
end

local function getVerticalInput()
	if isTyping() then
		return 0
	end
	local value = 0
	if keyDown(Enum.KeyCode.Space) or keyDown(Enum.KeyCode.E) or flyTouchUp then
		value += 1
	end
	if keyDown(Enum.KeyCode.LeftShift) or keyDown(Enum.KeyCode.Q) or flyTouchDown then
		value -= 1
	end
	return value
end

local function isSolidCollisionInstance(instance)
	if not instance then
		return false
	end
	if instance:IsA("Terrain") then
		return true
	end
	local ok, value = pcall(function() return instance.CanCollide end)
	return ok and value == true
end

-- 飞行碰撞：前向射线 + 前方盒扫，命中实体速度投影避免穿模
local lastFlyCollisionHit = nil
local function checkFlyCollision(velocity)
	lastFlyCollisionHit = nil
	if not DEF.FlyCollision or not root or velocity.Magnitude < 0.1 then
		return velocity
	end
	local hit = workspace:Raycast(root.Position, velocity.Unit * DEF.FlyCollisionDist, flyRayParams)
	if hit and isSolidCollisionInstance(hit.Instance) then
		lastFlyCollisionHit = hit.Instance
		local normal = hit.Normal
		local dot = velocity:Dot(normal)
		if dot < 0 then
			velocity = velocity - normal * dot
		end
		return velocity
	end
	local scanDist = DEF.FlyCollisionDist * 1.5
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
	if not isTyping() then
		if keyDown(Enum.KeyCode.W) or keyDown(Enum.KeyCode.Up) then
			fb += 1
		end
		if keyDown(Enum.KeyCode.S) or keyDown(Enum.KeyCode.Down) then
			fb -= 1
		end
		if keyDown(Enum.KeyCode.D) or keyDown(Enum.KeyCode.Right) then
			lr += 1
		end
		if keyDown(Enum.KeyCode.A) or keyDown(Enum.KeyCode.Left) then
			lr -= 1
		end
	end
	local stick = getStick()
	if stick then
		if math.abs(stick.Z) > 0.15 then
			fb += stick.Z
		end
		if math.abs(stick.X) > 0.15 then
			lr += stick.X
		end
	end
	return math.clamp(fb, -1, 1), math.clamp(lr, -1, 1)
end

local function updateFly()
	if fly and isSeated() then
		if flySetter then
			flySetter(false)
		else
			fly = false
			stopFly()
		end
		return
	end
	if fly and root and hum then
		if not flyLv or flyLv.Parent ~= root then
			startFly()
		end
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
			if rightFlat.Magnitude > 0.001 then
				rightFlat = rightFlat.Unit
			else
				rightFlat = Vector3.new(1, 0, 0)
			end
			if fb ~= 0 or lr ~= 0 then
				velocity = forward * (fb * flySpeed) + rightFlat * (lr * flySpeed)
			else
				local md = hum.MoveDirection
				if md.Magnitude > 0.01 then
					local flatForward = Vector3.new(forward.X, 0, forward.Z)
					if flatForward.Magnitude > 0.001 then
						flatForward = flatForward.Unit
					else
						flatForward = Vector3.new(0, 0, -1)
					end
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

-- ===== 5. 穿墙 =====

local function restoreCol()
	for part, value in pairs(savedCol) do
		if part and part.Parent then
			pcall(function() part.CanCollide = value end)
		end
	end
	table.clear(savedCol)
end

local function applyNoClipOnce()
	for part in pairs(charParts) do
		if part and part.Parent then
			if savedCol[part] == nil then
				savedCol[part] = part.CanCollide
			end
			if part.CanCollide then
				pcall(function() part.CanCollide = false end)
			end
		end
	end
end

-- 节流清扫（30Hz，补新增部件）
local noClipNextSweep = 0
local NOCLIP_SWEEP_INTERVAL = 1 / 30
local function updateNoClip()
	if not noClip then
		return
	end
	local now = os.clock()
	if now < noClipNextSweep then
		return
	end
	noClipNextSweep = now + NOCLIP_SWEEP_INTERVAL
	applyNoClipOnce()
end

-- ===== 6. 旋转（角色）=====

local spinForce, spinAtt = nil, nil
local function stopSpin()
	if spinForce then
		pcall(function() spinForce:Destroy() end)
		spinForce = nil
	end
	if spinAtt then
		pcall(function() spinAtt:Destroy() end)
		spinAtt = nil
	end
	spinActive = false
end

local function updateSpin()
	if not spinOn then
		if spinActive then
			stopSpin()
		end
		return
	end
	if not root or not root.Parent or root.Anchored or isSeated() then
		if spinActive then
			stopSpin()
		end
		return
	end
	if not spinActive then
		spinActive = true
		if spinForce and spinForce.Parent ~= root then
			pcall(function() spinForce:Destroy() end)
			pcall(function() spinAtt:Destroy() end)
			spinForce, spinAtt = nil, nil
		end
		if not spinForce then
			spinAtt = mk("Attachment", { Name = "MocSpinAtt" }, root)
			spinForce = mk("AngularVelocity", {
				Name = "MOC_Spin", Attachment0 = spinAtt,
				AngularVelocity = Vector3.zero, MaxTorque = math.huge,
			}, root)
		end
	end
	if spinForce then
		pcall(function() spinForce.AngularVelocity = Vector3.new(0, spinSpeed * spinDir, 0) end)
	end
end

-- ===== 7. 速度 =====

local function refreshSpeedModeButton()
	if not speedModeButton then
		return
	end
	speedModeButton.Text = "速度模式 " .. speedMode
	speedModeButton.BackgroundColor3 = speedOn and COL.On or COL.Off
end

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
		if rootVelocityApplied then
			clearRootVelocity()
		end
		return
	end
	if not speedOn and not rootVelocityApplied then
		return
	end
	local moveDir = hum and hum.MoveDirection or Vector3.zero
	local target = Vector3.zero
	if speedOn and moveDir.Magnitude > 0 then
		local horizontalMove = Vector3.new(moveDir.X, 0, moveDir.Z)
		if horizontalMove.Magnitude > 0 then
			target = horizontalMove.Unit * spd
		end
	end
	local current = root.AssemblyLinearVelocity
	local horizontal = Vector3.new(current.X, 0, current.Z)
	local accel = target.Magnitude > 0 and DEF.RootAccel or DEF.RootDecel
	local maxDelta = accel * dt
	local delta = target - horizontal
	if delta.Magnitude > maxDelta then
		delta = delta.Unit * maxDelta
	end
	local newHorizontal = horizontal + delta
	if not speedOn and newHorizontal.Magnitude < 0.05 then
		newHorizontal = Vector3.zero
		rootVelocityApplied = false
	end
	pcall(function()
		root.AssemblyLinearVelocity = Vector3.new(newHorizontal.X, current.Y, newHorizontal.Z)
	end)
	if speedOn then
		rootVelocityApplied = true
	end
end

local function cFrameHasRealInput()
	if isTyping() then
		return false
	end
	if keyDown(Enum.KeyCode.W) or keyDown(Enum.KeyCode.A)
		or keyDown(Enum.KeyCode.S) or keyDown(Enum.KeyCode.D)
		or keyDown(Enum.KeyCode.Up) or keyDown(Enum.KeyCode.Down)
		or keyDown(Enum.KeyCode.Left) or keyDown(Enum.KeyCode.Right) then
		return true
	end
	local stick = getStick()
	if stick and stick.Magnitude > DEF.CFrameStickDeadzone then
		return true
	end
	for _ in pairs(cframeTouches) do
		return true
	end
	return false
end

local function getJitterOffset(dt)
	jitterPhase += dt * DEF.JitterFreq
	local jx = math.sin(jitterPhase * 2.1) * DEF.JitterAmount
	local jz = math.cos(jitterPhase * 1.7) * DEF.JitterAmount
	return Vector3.new(jx, 0, jz)
end

-- CFrame 速度：每帧直接写 CFrame（含贴墙滑动、贴地吸附、微抖动防判定）
local function updateCFrameSpeed(dt)
	if not (speedOn and root and hum and root.Parent) then
		return
	end
	if fly or isSeated() or isTyping() or hum.Health <= 0 or root.Anchored then
		return
	end
	dt = math.clamp(dt, 0, 0.05)
	local now = os.clock()
	local md = hum.MoveDirection or Vector3.zero
	if md.Magnitude > DEF.CFrameDeadzone then
		if (md - cframeLastDir).Magnitude > DEF.CFrameDirChange then
			cframeLastDir = md
			cframeLastDirChange = now
		end
	else
		cframeLastDir = Vector3.zero
		cframeLastDirChange = now
	end
	local horizontal = Vector3.new(md.X, 0, md.Z)
	local canMove = false
	if horizontal.Magnitude > DEF.CFrameDeadzone then
		if cFrameHasRealInput() then
			canMove = true
		elseif now - cframeLastDirChange < DEF.CFrameGrace then
			canMove = true
		end
	end
	if not canMove then
		return
	end

	local dir = horizontal.Unit
	local stepDist = spd * dt
	local moveOffset = dir * stepDist
	if not noClip and character then
		local wallHit = workspace:Raycast(root.Position, dir * (stepDist + 1.2), cframeRayParams)
		if wallHit and wallHit.Instance and wallHit.Instance.CanCollide then
			local normal = wallHit.Normal
			local slideDir = dir - normal * dir:Dot(normal)
			if slideDir.Magnitude > 0.05 then
				moveOffset = slideDir.Unit * stepDist
			else
				moveOffset = Vector3.zero
			end
		end
	end
	local currentPos = root.Position
	local currentCF = root.CFrame
	local targetY = currentPos.Y
	if character then
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
		root.CFrame = CFrame.new(newPos) * (currentCF - currentPos)
	end)
end

local function restoreWalkSpeed()
	if speedMode == "WalkSpeed" and hum then
		pcall(function() hum.WalkSpeed = defaultWalkSpeed end)
		speedApplied = false
		lastWalkSpeedApplied = nil
	end
end

local function updateSpeed(dt)
	if speedMode == "WalkSpeed" then
		if not hum then
			return
		end
		if speedOn then
			if lastWalkSpeedApplied ~= spd then
				pcall(function() hum.WalkSpeed = spd end)
				lastWalkSpeedApplied = spd
			end
			speedApplied = true
		elseif speedApplied then
			restoreWalkSpeed()
		end
	elseif speedMode == "RootVelocity" then
		if hum and root then
			updateRootVelocity(dt)
		end
	elseif speedMode == "CFrame" then
		updateCFrameSpeed(dt)
	end
end

-- ===== 8. 高跳（尊重原版 UseJumpPower 模式）=====

local function updateHighJump()
	if not (highJump and hum) then
		return
	end
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
	if not (hum and defaultsCaptured) then
		return
	end
	pcall(function()
		hum.UseJumpPower = defaultUseJumpPower
		hum.JumpPower = defaultJumpPower
		hum.JumpHeight = defaultJumpHeight
	end)
end

-- ===== 9. 夜视 =====

local nvEffect = nil
local nvNextCheck = 0
local nvSavedLighting = nil
local nvFogAtm = nil

local function nvClearEffect()
	if nvEffect then
		pcall(function() nvEffect:Destroy() end)
		nvEffect = nil
	end
end

local function nvApply()
	if not nvSavedLighting then
		nvSavedLighting = {
			Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient,
			Brightness = Lighting.Brightness,
			FogEnd = Lighting.FogEnd,
			FogStart = Lighting.FogStart,
			FogColor = Lighting.FogColor,
		}
	end
	pcall(function()
		Lighting.Ambient = Color3.fromRGB(150, 150, 150)
		Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 150)
		Lighting.Brightness = math.max(Lighting.Brightness, 2)
		if DEF.NvRemoveFog then
			Lighting.FogEnd = 1e6
		end
	end)
	if DEF.NvRemoveFog then
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		if atm and atm.Parent then
			if not nvFogAtm then
				nvFogAtm = atm
			end
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
	if not nv then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if nvEffect and nvEffect.Parent ~= cam then
		nvClearEffect()
	end
	if not nvEffect or not nvEffect.Parent then
		pcall(function()
			local cc = mk("ColorCorrectionEffect", {
				Name = "MocNV", Brightness = DEF.NvCCBrightness,
				Contrast = DEF.NvCCContrast, Saturation = DEF.NvCCSaturation,
			}, cam)
			nvEffect = cc
		end)
	end
	nvApply()
end

local function setNV(on)
	nv = on
	if on then
		nvSync()
	else
		nvClearEffect()
		nvRestore()
	end
end

reg(RunService.Heartbeat:Connect(function()
	if not nv then
		return
	end
	local now = os.clock()
	if now < nvNextCheck then
		return
	end
	nvNextCheck = now + 0.5
	nvSync()
end))

-- ===== 10. 秒互动（off/normal/force 三态）=====

local NOCD_MODES = { "off", "normal", "force" }
local noCdModeIndex = 1
local noCdVersion = 0
local promptSaved = setmetatable({}, { __mode = "k" })

local function currentNoCdMode()
	return NOCD_MODES[noCdModeIndex]
end
local function noCdActive()
	return noCdModeIndex > 1
end

local function patchPrompt(obj)
	if not obj or not obj:IsA("ProximityPrompt") or promptSaved[obj] then
		return
	end
	local force = currentNoCdMode() == "force"
	local okEnabled, enabled = pcall(function() return obj.Enabled end)
	if not okEnabled then
		return
	end
	if not force and not enabled then
		return
	end
	promptSaved[obj] = {
		hold = obj.HoldDuration,
		dist = obj.MaxActivationDistance,
		enabled = obj.Enabled,
		los = obj.RequiresLineOfSight,
	}
	pcall(function()
		if force then
			obj.Enabled = true
		end
		obj.HoldDuration = 0
		obj.MaxActivationDistance = math.max(obj.MaxActivationDistance, DEF.PromptDist)
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
		local count = 0
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if v ~= noCdVersion then
				return
			end
			if descendant:IsA("ProximityPrompt") then
				patchPrompt(descendant)
				count += 1
				if count > PROMPT_SCAN_CAP then
					break
				end
				if count % DEF.PromptScanBatch == 0 then
					task.wait()
				end
			end
		end
	end)
end

local function setNoCdMode(mode)
	for i, v in ipairs(NOCD_MODES) do
		if v == mode then
			noCdModeIndex = i
		end
	end
	noCdVersion += 1
	restorePrompts()
	if noCdActive() then
		scanPrompts()
	end
end

reg(workspace.DescendantAdded:Connect(function(descendant)
	if noCdActive() and descendant:IsA("ProximityPrompt") then
		patchPrompt(descendant)
	end
end))

-- ===== 11. 角色绑定 =====

local function setupCharacter()
	if not character then
		return
	end
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
	if seatConnection then
		pcall(function() seatConnection:Disconnect() end)
		seatConnection = nil
	end
	if hum then
		seatConnection = hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
			if fly and hum.SeatPart then
				if flySetter then
					flySetter(false)
				else
					fly = false
					stopFly()
				end
			end
		end)
	end
	table.clear(charParts)
	table.clear(savedCol)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			charParts[descendant] = true
			savedCol[descendant] = descendant.CanCollide
		end
	end
	if descAdded then
		pcall(function() descAdded:Disconnect() end)
		descAdded = nil
	end
	if descRemoving then
		pcall(function() descRemoving:Disconnect() end)
		descRemoving = nil
	end
	descAdded = character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			charParts[descendant] = true
			if savedCol[descendant] == nil then
				savedCol[descendant] = descendant.CanCollide
			end
			if noClip then
				pcall(function() descendant.CanCollide = false end)
			end
		end
	end)
	descRemoving = character.DescendantRemoving:Connect(function(descendant)
		charParts[descendant] = nil
		savedCol[descendant] = nil
	end)
	table.clear(charFilterTable)
	charFilterTable[1] = character
	flyRayParams.FilterDescendantsInstances = charFilterTable
	flyBoxParams.FilterDescendantsInstances = charFilterTable
	cframeRayParams.FilterDescendantsInstances = charFilterTable
	if noClip then
		task.defer(function()
			if alive and noClip and character then
				applyNoClipOnce()
			end
		end)
	end
end

local charConns = {}
local function clearCharConns()
	for _, c in ipairs(charConns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(charConns)
end

local function onCharacterRemoving(c)
	if c ~= character then
		return
	end
	stopFly()
	stopSpin()
	restoreCol()
	if seatConnection then
		pcall(function() seatConnection:Disconnect() end)
		seatConnection = nil
	end
	if descAdded then
		pcall(function() descAdded:Disconnect() end)
		descAdded = nil
	end
	if descRemoving then
		pcall(function() descRemoving:Disconnect() end)
		descRemoving = nil
	end
	character, root, hum = nil, nil, nil
	table.clear(charParts)
	table.clear(savedCol)
	speedApplied = false
	rootVelocityApplied = false
	lastWalkSpeedApplied = nil
	table.clear(cframeTouches)
end

local function bindCharacter(c)
	clearCharConns()
	character = c
	hum, root = nil, nil
	local function scan()
		local h = c:FindFirstChildOfClass("Humanoid")
		local r = c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Root")
		local newHum, newRoot = h, (r and r:IsA("BasePart") and r or nil)
		if newHum ~= hum or newRoot ~= root then
			hum, root = newHum, newRoot
			if hum or root then
				setupCharacter()
			end
		end
	end
	scan()
	charConns[#charConns + 1] = c.ChildAdded:Connect(scan)
end

reg(player.CharacterAdded:Connect(bindCharacter))
reg(player.CharacterRemoving:Connect(onCharacterRemoving))
if player.Character then
	bindCharacter(player.Character)
end

reg(UIS.JumpRequest:Connect(function()
	if infJump and hum and not isTyping() then
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
	end
end))

-- ===== 12. 主循环 =====

local dtState = { last = os.clock() }
local function frameDt(step)
	local now = os.clock()
	local dt = step
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 then
		dt = now - dtState.last
	end
	dtState.last = now
	return math.clamp(dt, 0, 0.1)
end

reg(RunService.PreSimulation:Connect(function(step)
	if not character or not character:IsDescendantOf(workspace) then
		return
	end
	local deltaTime = frameDt(step)
	updateSpeed(deltaTime)
	updateHighJump()
	updateFly()
	updateNoClip()
	updateSpin()
end))

-- ===== 13. GUI =====

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function encodePos(pos)
	return string.format("%.6f,%.0f,%.6f,%.0f", pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset)
end

local panelSize = UDim2.new(0, PANEL_W, 0, TITLE_H + ROW_H * 9)
local panelPos = UDim2.new(0.5, -PANEL_W / 2, 0.4, -panelSize.Y.Offset / 2)

local gui = mk("ScreenGui", {
	Name = NAME, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99999,
}, GuiRoot)
local main = mk("Frame", {
	Size = panelSize, Position = panelPos, BackgroundColor3 = BG,
	BackgroundTransparency = ALPHA, BorderSizePixel = 0, ClipsDescendants = true,
}, gui)

-- 恢复保存的位置（收进安全区）
do
	local saved = cfgGet("UI.Pos." .. NAME, nil)
	local vp = workspace.CurrentCamera.ViewportSize
	if typeof(saved) == "string" then
		local sx, ox, sy, oy = saved:match("^([%-%d%.]+),([%-%d]+),([%-%d%.]+),([%-%d]+)$")
		if sx then
			local w = PANEL_W
			local h = panelSize.Y.Offset
			local absX = math.clamp(tonumber(ox) or 0, 0, math.max(vp.X - w, 0))
			local absY = math.clamp(tonumber(oy) or 0, SAFE_TOP, math.max(vp.Y - h, SAFE_TOP))
			main.Position = UDim2.new(tonumber(sx) or 0, absX, tonumber(sy) or 0, absY)
		end
	end
end

local titleBar = mk("TextButton", {
	Size = UDim2.new(1, 0, 0, TITLE_H), BackgroundColor3 = BG, BackgroundTransparency = 1,
	BorderSizePixel = 0, Text = "移动增强 [-]", TextColor3 = Color3.new(1, 1, 1),
	TextSize = 13, Font = FONT, TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
}, main)

-- 拖拽（带容差，松手存位置）
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
			cfgSet("UI.Pos." .. NAME, encodePos(main.Position))
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
		titleBar.Text = "移动增强 " .. (collapsed and "[+]" or "[-]")
		main.Size = collapsed and UDim2.new(0, PANEL_W, 0, TITLE_H) or panelSize
	end))
end

local function toggleRow(parent, y, labelText, initialOn, onToggle, getVal, setVal)
	local row = mk("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_H), Position = UDim2.new(0, 0, 0, y),
		BackgroundTransparency = 1,
	}, parent)
	local button = mk("TextButton", {
		Size = UDim2.new(0.5, 0, 1, 0),
		BackgroundColor3 = initialOn and COL.On or COL.Off,
		BackgroundTransparency = ALPHA, BorderSizePixel = 0,
		Text = labelText .. (initialOn and " 开" or " 关"), TextColor3 = Color3.new(1, 1, 1),
		TextSize = 11, Font = FONT, TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, row)
	local inputFrame = mk("Frame", {
		Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundColor3 = BG, BackgroundTransparency = ALPHA, BorderSizePixel = 0,
	}, row)
	local input = mk("TextBox", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
		TextColor3 = Color3.new(1, 1, 1), Text = tostring(getVal and getVal() or ""),
		TextSize = 11, Font = FONT, ClearTextOnFocus = true,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, inputFrame)
	reg(input.FocusLost:Connect(function()
		local v = tonumber(input.Text)
		if v and setVal then
			setVal(v)
		end
		if getVal then
			input.Text = tostring(getVal())
		end
	end))
	local state = initialOn == true
	local function apply(newState)
		if state == newState then
			return
		end
		state = newState
		button.Text = labelText .. (state and " 开" or " 关")
		button.BackgroundColor3 = state and COL.On or COL.Off
		onToggle(state)
	end
	reg(button.Activated:Connect(function() apply(not state) end))
	return button, input, apply
end

local function fullInput(parent, y, labelText, color, getVal, setVal)
	local row = mk("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_H), Position = UDim2.new(0, 0, 0, y),
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

local function holdOn(button, onStart, onEnd)
	local held = false
	local function start()
		if not held then
			held = true
			onStart()
		end
	end
	local function endHold()
		if held then
			held = false
			onEnd()
		end
	end
	reg(button.InputBegan:Connect(function(input)
		if isPointer(input) then
			start()
		end
	end))
	reg(button.InputEnded:Connect(function(input)
		if isPointer(input) then
			endHold()
		end
	end))
	reg(UIS.InputEnded:Connect(function(input)
		if isPointer(input) then
			endHold()
		end
	end))
	reg(UIS.WindowFocusReleased:Connect(endHold))
	reg(button.AncestryChanged:Connect(function(_, parent)
		if not parent then
			endHold()
		end
	end))
end

toggleRow(main, TITLE_H, "速度", false, function(on)
	speedOn = on
	if not on then
		restoreWalkSpeed()
		table.clear(cframeTouches)
	end
	refreshSpeedModeButton()
end, function() return spd end, function(v)
	spd = v
	cfgSet("MOCSpd", spd)
end)

speedModeButton = mk("TextButton", {
	Size = UDim2.new(1, 0, 0, ROW_H), Position = UDim2.new(0, 0, 0, TITLE_H + ROW_H),
	BackgroundColor3 = COL.Off, BackgroundTransparency = ALPHA, BorderSizePixel = 0,
	Text = "速度模式 " .. speedMode, TextColor3 = Color3.new(1, 1, 1), TextSize = 11,
	Font = FONT, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, main)
refreshSpeedModeButton()
reg(speedModeButton.Activated:Connect(function()
	local oldMode = speedMode
	local index = 1
	for i, mode in ipairs(SPEED_MODES) do
		if mode == speedMode then
			index = i
		end
	end
	index = index % #SPEED_MODES + 1
	speedMode = SPEED_MODES[index]
	if oldMode == "WalkSpeed" then
		restoreWalkSpeed()
	end
	if oldMode == "RootVelocity" then
		rootVelocityApplied = false
	end
	if oldMode == "CFrame" then
		table.clear(cframeTouches)
	end
	cfgSet("MOCSpeedMode", speedMode)
	refreshSpeedModeButton()
end))

_, _, flySetter = toggleRow(main, TITLE_H + ROW_H * 2, "飞行", false, function(on)
	fly = on
	if not on then
		stopFly()
	end
end, function() return flySpeed end, function(v)
	flySpeed = v
	cfgSet("MOCFlySpd", flySpeed)
end)

toggleRow(main, TITLE_H + ROW_H * 3, "高跳", false, function(on)
	highJump = on
	if not on then
		restoreJump()
	end
end, function() return highJumpValue end, function(v)
	highJumpValue = v
	cfgSet("MOCJump", highJumpValue)
end)

fullInput(main, TITLE_H + ROW_H * 4, "转速", COL.Bind,
	function() return spinSpeed end,
	function(v)
		spinSpeed = v
		cfgSet("MOCSpin", spinSpeed)
	end)

local grid = mk("Frame", {
	Size = UDim2.new(1, 0, 0, ROW_H * 4),
	Position = UDim2.new(0, 0, 0, TITLE_H + ROW_H * 5),
	BackgroundTransparency = 1,
}, main)
mk("UIGridLayout", {
	CellSize = UDim2.new(0.5, 0, 1 / 4, 0), CellPadding = UDim2.new(0, 0, 0, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, grid)

local function gridBtn(text, color, order, onClick)
	local button = mk("TextButton", {
		BackgroundColor3 = color, BackgroundTransparency = ALPHA, BorderSizePixel = 0,
		Text = text, TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = FONT,
		LayoutOrder = order, TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, grid)
	button:SetAttribute("Base", color)
	if onClick then
		reg(button.Activated:Connect(function() onClick(button) end))
	end
	return button
end

gridBtn("无限跳 关", COL.Off, 1, function(button)
	infJump = not infJump
	button.Text = "无限跳 " .. (infJump and "开" or "关")
	button.BackgroundColor3 = infJump and COL.On or button:GetAttribute("Base")
end)

gridBtn("穿墙 关", COL.Off, 2, function(button)
	noClip = not noClip
	button.Text = "穿墙 " .. (noClip and "开" or "关")
	button.BackgroundColor3 = noClip and COL.On or button:GetAttribute("Base")
	if noClip then
		applyNoClipOnce()
	else
		restoreCol()
	end
end)

gridBtn("旋转 关", COL.Off, 3, function(button)
	spinOn = not spinOn
	button.Text = "旋转 " .. (spinOn and "开" or "关")
	button.BackgroundColor3 = spinOn and COL.On or button:GetAttribute("Base")
end)

gridBtn("夜视 关", COL.Off, 4, function(button)
	setNV(not nv)
	button.Text = "夜视 " .. (nv and "开" or "关")
	button.BackgroundColor3 = nv and COL.On or button:GetAttribute("Base")
end)

gridBtn("秒互动 关", COL.Off, 5, function(button)
	noCdModeIndex = noCdModeIndex % #NOCD_MODES + 1
	setNoCdMode(NOCD_MODES[noCdModeIndex])
	local mode = currentNoCdMode()
	button.Text = mode == "off" and "秒互动 关" or (mode == "normal" and "秒互动 普通" or "秒互动 强制")
	button.BackgroundColor3 = noCdActive() and COL.On or button:GetAttribute("Base")
end)

gridBtn("换向 ▶", COL.Off, 6, function(button)
	spinDir = -spinDir
	button.Text = spinDir == 1 and "换向 ▶" or "换向 ◀"
end)

local flyUpButton = gridBtn("按住上升", COL.Off, 7, nil)
local flyDownButton = gridBtn("按住下降", COL.Off, 8, nil)
holdOn(flyUpButton, function() flyTouchUp = true end, function() flyTouchUp = false end)
holdOn(flyDownButton, function() flyTouchDown = true end, function() flyTouchDown = false end)

-- ===== 14. 卸载 =====

local DBG = rawget(_G, "SB_DEBUG") or {}
rawset(_G, "SB_DEBUG", DBG)
DBG[NAME] = function()
	local lines = {
		"speedOn: " .. tostring(speedOn) .. " mode: " .. speedMode .. " spd: " .. tostring(spd),
		"fly: " .. tostring(fly) .. " flySpeed: " .. tostring(flySpeed) .. " hit: " .. tostring(lastFlyCollisionHit),
		"infJump: " .. tostring(infJump) .. " highJump: " .. tostring(highJump) .. " (" .. tostring(highJumpValue) .. ")",
		"noClip: " .. tostring(noClip) .. " tracked: " .. tostring(next(savedCol) ~= nil),
		"spin: " .. tostring(spinOn) .. " active: " .. tostring(spinActive) .. " dir: " .. tostring(spinDir) .. " spd: " .. tostring(spinSpeed),
		"nv: " .. tostring(nv) .. " noCd: " .. currentNoCdMode(),
		"char: " .. tostring(character) .. " root: " .. tostring(root) .. " hum: " .. tostring(hum),
	}
	if hum then
		lines[#lines + 1] = "WalkSpeed: " .. tostring(hum.WalkSpeed) .. " Health: " .. tostring(hum.Health) .. " Seat: " .. tostring(hum.SeatPart)
	end
	if root then
		lines[#lines + 1] = "vel: " .. tostring(root.AssemblyLinearVelocity) .. " anchored: " .. tostring(root.Anchored)
	end
	return "=== MOC ===\n" .. table.concat(lines, "\n") .. "\n=== END ==="
end

local function destroy()
	alive = false
	speedOn, fly, infJump, highJump, noClip, nv, spinOn = false, false, false, false, false, false, false
	flyTouchUp, flyTouchDown = false, false
	stopFly()
	stopSpin()
	restoreWalkSpeed()
	rootVelocityApplied = false
	table.clear(cframeTouches)
	restoreCol()
	restoreJump()
	setNV(false)
	setNoCdMode("off")
	for _, c in ipairs(charConns) do
		pcall(function() c:Disconnect() end)
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

print("[moc] ready")
