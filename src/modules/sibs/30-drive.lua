-- sibs / 30-drive — 驱动力、穿墙碰撞管理、悬浮、翻转、飞车、主物理循环、座位同步

-- 驱动力（前向声明在 00；此处赋值给已声明的 local）
function clearDrive()
	if drive then drive.destroy(); drive = nil end
end

function ensureDrive(part)
	if not part or not part.Parent then clearDrive(); return nil end
	if part.Anchored then
		local ok, parts = pcall(function() return part:GetConnectedParts(true) end)
		if ok then
			for _, p in ipairs(parts) do
				if p:IsA("BasePart") and not p.Anchored then part = p; break end
			end
		end
		if part.Anchored then clearDrive(); return nil end
	end
	local okR, asmRoot = pcall(function() return part.AssemblyRootPart end)
	if okR and asmRoot and asmRoot ~= part and asmRoot.Parent and not asmRoot.Anchored then
		part = asmRoot
	end
	if drive and drive.alive() and drive.part == part then return drive end
	clearDrive()
	drive = K.force.vector(part, "SIBS_DriveForce")
	return drive
end

-- 穿墙：记录原碰撞属性，批量开关（轮毂单独一组便于翻滚检测时恢复）
local function rememberOriginal(part)
	if not part or not part.Parent then return end
	if clipOriginal[part] == nil then
		local ok, value = pcall(function() return part.CanCollide end)
		if ok then clipOriginal[part] = value end
	end
end

local function setPartCollision(part, value)
	if not part or not part.Parent then return end
	if clipSetState[part] == value then return end
	rememberOriginal(part)
	local ok, current = pcall(function() return part.CanCollide end)
	if ok and current ~= value then pcall(function() part.CanCollide = value end) end
	clipSetState[part] = value
end

local function rebuildClipParts()
	for _, part in ipairs(clipParts) do
		if part and part.Parent then
			local original = clipOriginal[part]
			pcall(function() part.CanCollide = original ~= false end)
		end
		clipSetState[part] = nil
	end
	for _, w in ipairs(clipWheels) do
		if w and w.Parent then
			local original = clipOriginal[w]
			pcall(function() w.CanCollide = original ~= false end)
		end
		clipSetState[w] = nil
	end
	table.clear(clipParts)
	table.clear(clipWheels)
	local model = getControlledVehicleModel()
	if not model then clipModel = nil; clipDirty = false; return end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			rememberOriginal(descendant)
			if isWheel(descendant) then clipWheels[#clipWheels + 1] = descendant
			else clipParts[#clipParts + 1] = descendant end
		end
	end
	clipModel = model
	clipDirty = false
end

local function applyClipCollision()
	if clipDirty then rebuildClipParts() end
	for _, part in ipairs(clipParts) do
		setPartCollision(part, clipFalling and (clipOriginal[part] ~= false) or false)
	end
	for _, wheel in ipairs(clipWheels) do
		setPartCollision(wheel, clipFalling and (clipOriginal[wheel] ~= false) or false)
	end
end

local function restoreClip()
	for _, part in ipairs(clipParts) do
		if part and part.Parent then
			local original = clipOriginal[part]
			pcall(function() part.CanCollide = original ~= false end)
		end
	end
	for _, w in ipairs(clipWheels) do
		if w and w.Parent then
			local original = clipOriginal[w]
			pcall(function() w.CanCollide = original ~= false end)
		end
	end
	table.clear(clipParts)
	table.clear(clipWheels)
	table.clear(clipOriginal)
	table.clear(clipSetState)
	clipModel = nil
	clipFalling = false
end

-- 穿墙更新：节流重建 + 自由落体探测；悬浮支持仅在穿墙开启时生效
-- 地面射线（filter 表复用，不每帧新建）
local groundRayParams = RaycastParams.new()
groundRayParams.FilterType = Enum.RaycastFilterType.Exclude
local groundFilterTable = {}

local function setGroundFilter(inst)
	if groundFilterTable[1] ~= inst or (inst == nil and #groundFilterTable > 0) then
		table.clear(groundFilterTable)
		if inst then groundFilterTable[1] = inst end
	end
	groundRayParams.FilterDescendantsInstances = groundFilterTable
end

local function isGrounded(part)
	local model = getControlledVehicleModel()
	setGroundFilter(model or part)
	local drop = part.Size.Y * 0.5 + CFG.GroundClearance + CFG.GroundProbeExtra
	local ok, hit = pcall(workspace.Raycast, workspace, part.Position, Vector3.new(0, -drop, 0), groundRayParams)
	return ok and hit ~= nil
end

-- 悬浮支撑：近地轻推、带内消除下坠、深坑限速下沉
local function hoverSupport(part)
	if not part or not part.Parent then return end
	local model = getControlledVehicleModel()
	setGroundFilter(model or part)
	local half = part.Size.Y * 0.5
	local far = half + CFG.GroundClearance + CFG.GroundProbeExtra
	local ok, hit = pcall(workspace.Raycast, workspace, part.Position, Vector3.new(0, -far, 0), groundRayParams)
	if not ok or not hit then return end
	local vel = part.AssemblyLinearVelocity
	local near = half + 0.75
	if hit.Distance <= near then
		local push = math.clamp((near - hit.Distance) * CFG.HoverPushGain, 0, CFG.HoverPushMax)
		if push > 0 then pcall(function() part.AssemblyLinearVelocity = Vector3.new(vel.X, push, vel.Z) end) end
	elseif hit.Distance <= near + CFG.HoverBand then
		if vel.Y < 0 then pcall(function() part.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z) end) end
	elseif hit.Distance <= far then
		if vel.Y < CFG.HoverSinkCap then
			pcall(function() part.AssemblyLinearVelocity = Vector3.new(vel.X, CFG.HoverSinkCap, vel.Z) end)
		end
	end
end

local clipNextRebuild = 0

local function updateWallClip(part)
	if noClip then
		local ownModel = getControlledVehicleModel()
		if not ownModel or not part or not part.Parent then
			if clipModel then restoreClip(); clipDirty = true end
			return
		end
		if clipModel ~= ownModel then restoreClip(); clipDirty = true; clipNextRebuild = 0 end
		if part:IsDescendantOf(workspace) then
			local vel = part.AssemblyLinearVelocity
			if vel.Y < CFG.ClipFallSpeed then
				-- 快速下坠：探测下方地面，进入"翻滚免碰撞"状态
				setGroundFilter(ownModel)
				local okF, hitF = pcall(workspace.Raycast, workspace, part.Position,
					Vector3.new(0, -CFG.ClipFallProbeDist, 0), groundRayParams)
				if okF and hitF then clipFalling = true end
			elseif clipFalling and vel.Y > -3 then
				clipFalling = false
			end
		end
		local now = os.clock()
		if now >= clipNextRebuild then
			clipNextRebuild = now + CFG.ClipRebuildInterval
			clipDirty = true
		end
		applyClipCollision()
		if not clipFalling and not carFly then hoverSupport(part) end
	else
		if clipModel then restoreClip(); clipDirty = true end
	end
end

-- 翻转：旋转整个装配体（只转根部件会把车撕开）
local function flipVehicle()
	local part = seat or lockPart
	if not part or not part.Parent then toast("无锁定车辆", K.Col.Wait); return end
	local anchor = resolveAssemblyAnchor(part)
	local pos = anchor.Position
	local ok, parts = pcall(function() return anchor:GetConnectedParts(true) end)
	local list = (ok and type(parts) == "table") and parts or {anchor}
	local rot = CFrame.fromAxisAngle(anchor.CFrame.LookVector, math.pi)
	for _, p in ipairs(list) do
		if p:IsA("BasePart") and p.Parent and not p.Anchored then
			pcall(function()
				p.CFrame = (rot * (p.CFrame - pos)) + pos
			end)
		end
	end
	toast("已翻转", K.Col.Good)
end

-- 飞车（LinearVelocity 接管；前向用锁定朝向，垂直由加速度积分）
local function stopCarFly()
	if carFlyHandle then carFlyHandle.destroy(); carFlyHandle = nil end
	flyVertVel = 0
end

local function updateCarFly(part, dt, seatThrottle)
	if not part or not part.Parent then stopCarFly(); return end
	if not carFlyHandle or not carFlyHandle.alive() or carFlyHandle.part ~= part then
		stopCarFly()
		carFlyHandle = K.force.linear(part, "SIBS_FlyVelocity")
		if not carFlyHandle then return end
	end
	local kbUp, kbDown = K.input.verticalStates()
	local vertInput = 0
	if flyUp or kbUp then vertInput += 1 end
	if flyDown or kbDown then vertInput -= 1 end
	flyVertVel += vertInput * CFG.FlyVertAccel * dt
	if vertInput == 0 and math.abs(flyVertVel) < 1 then flyVertVel = 0 end
	local look = getVehicleFacing(part)
	if look.Magnitude < 0.001 then look = Vector3.new(0, 0, 1) end
	local kbW, kbS = K.input.forwardStates()
	local fwdInput = 0
	if accelerating or kbW or seatThrottle > 0.1 then fwdInput += 1 end
	if decelerating or kbS or seatThrottle < -0.1 then fwdInput -= 1 end
	local currentVel = part.AssemblyLinearVelocity
	local currentHVel = K.flat(currentVel)
	local cruiseSpeed = math.max(currentHVel.Magnitude, CFG.FlySpeed)
	local targetHVel = (fwdInput ~= 0) and (look * (cruiseSpeed * fwdInput)) or currentHVel
	carFlyHandle.set(Vector3.new(targetHVel.X, flyVertVel, targetHVel.Z))
end

-- 每帧缓存朝向（主循环内会取两次，避免重复向上遍历父级）
local facingCache = {at = -1, part = nil, value = Vector3.zero}

local function getVehicleFacingCached(part, now)
	if facingCache.part == part and now - facingCache.at < 1 / 30 then
		return facingCache.value
	end
	local v = getVehicleFacing(part)
	facingCache.part, facingCache.at, facingCache.value = part, now, v
	return v
end

-- 主物理循环：锁定维护 → 穿墙 → 油门/刹车/定速 → 转向+抓地 → 旋转
local simDt = K.dtTracker(0.1)
local spinWasActive = false

M.reg(RunService.PreSimulation:Connect(function(step)
	K.heartbeat()
	local deltaTime = simDt(step)
	local now = os.clock()
	if not seat then updateLockBinding(now) end
	local part = seat or lockPart
	updateWallClip(part)
	if not part or not part:IsDescendantOf(workspace) then return end
	local velocity = part.AssemblyLinearVelocity
	if velocity.X ~= velocity.X or velocity.Y ~= velocity.Y or velocity.Z ~= velocity.Z then
		pcall(function() part.AssemblyLinearVelocity = Vector3.zero end)
		velocity = Vector3.zero
	end
	-- 旋转滑条：放在循环最前，停止/飞车等早退分支也会更新——回中立刻停转（复位）
	local spinActive = math.abs(spinSpeed) > 0.1
	if spinActive then
		if not spinHandle or not spinHandle.alive() or spinHandle.part ~= part then
			if spinHandle then spinHandle.destroy() end
			spinHandle = K.force.angular(part, "SIBS_Spin")
		end
		if spinHandle then spinHandle.set(Vector3.new(0, spinSpeed, 0)) end
	else
		if spinHandle then spinHandle.set(Vector3.zero) end
		if spinWasActive then
			pcall(function()
				local av = part.AssemblyAngularVelocity
				part.AssemblyAngularVelocity = Vector3.new(av.X, 0, av.Z)
			end)
		end
	end
	spinWasActive = spinActive
	local seatThrottle, seatSteer = 0, 0
	if seat and seat:IsA("VehicleSeat") and seat.Parent then
		local okT, t = pcall(function() return seat.Throttle end)
		if okT then seatThrottle = t end
		local okS, s = pcall(function() return seat.Steer end)
		if okS then seatSteer = s end
	end
	local flatLook = getVehicleFacingCached(part, now)
	local brakeRate = acceleration * CFG.BrakeDecelMult
	if carFly then
		updateCarFly(part, deltaTime, seatThrottle)
		return
	end
	local kbW, kbS = K.input.forwardStates()
	local wantAccel = accelerating or kbW or seatThrottle > 0.1
	local wantDecel = decelerating or kbS or seatThrottle < -0.1
	local steerInput = steerValue
	if math.abs(seatSteer) > 0.05 then steerInput = steerInput + seatSteer * 0.5 end
	steerInput = math.clamp(steerInput, -1, 1)
	if stopped then
		if wantAccel then
			stopped = false
			refreshStopButton()
		else
			targetSpeed = 0
			local frc = ensureDrive(part)
			if frc then
				local mass = math.max(part.AssemblyMass, 1)
				local hv = K.flat(velocity)
				local spd = hv.Magnitude
				if spd > CFG.BrakeDeadzone then
					local brakeMult = math.clamp(spd / 50, 0.1, 1)
					frc.set(-hv.Unit * (mass * brakeRate * brakeMult))
				else
					frc.set(Vector3.zero)
					if hv.Magnitude > 0.1 then
						pcall(function() part.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0) end)
					end
				end
			end
			return
		end
	end
	-- 轮胎转向：角速度 ∝ 车速（自行车模型，转弯半径恒定），静止时打方向不转
	local turned = false
	if math.abs(steerInput) > 0.02 then
		local speed = velocity.Magnitude
		local speedGate = math.clamp(speed / CFG.TurnRefSpeed, 0, 1)
		if speedGate > 0 then
			turned = true
			local speedFactor = math.clamp(1 - (speed / 180) * 0.35, CFG.HighSpeedTurnFloor, 1)
			local turnAngle = steerInput * CFG.TurnSpeed * speedFactor * speedGate * deltaTime
			local pos = part.Position
			local rot = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), turnAngle)
			pcall(function() part.CFrame = (rot * (part.CFrame - pos)) + pos end)
		end
	end
	local hasInput = wantAccel or wantDecel or cruise
	lastGrounded = isGrounded(part)
	if hasInput then
		local frc = ensureDrive(part)
		if frc then
			local mass = math.max(part.AssemblyMass, 1)
			local hv = K.flat(velocity)
			local speed = hv.Magnitude
			local accelForce = mass * acceleration
			local brakeForce = mass * brakeRate
			local moveDir = flatLook.Magnitude > 0.001 and flatLook or Vector3.new(0, 0, 1)
			local force = Vector3.zero
			if wantAccel and wantDecel then
				if speed > 1.5 then force = -hv.Unit * brakeForce end
				reverseHold = false
			elseif wantAccel then
				force = moveDir * accelForce
				reverseHold = false
			elseif wantDecel then
				local fwdSpeed = hv:Dot(moveDir)
				if fwdSpeed > 3 then
					force = -moveDir * brakeForce
					reverseHold = false
				else
					force = -moveDir * accelForce
					reverseHold = true
				end
			elseif cruise then
				local currentFwd = velocity:Dot(moveDir)
				local err = targetSpeed - currentFwd
				if math.abs(err) > CFG.CruiseDeadzone then
					force = moveDir * math.clamp(err * mass * CFG.CruiseGain, -accelForce, accelForce)
				else
					force = Vector3.zero
				end
			end
			if not lastGrounded then force = force * 0.1 end
			if force.Magnitude < CFG.ForceDeadzone then force = Vector3.zero end
			local maxForceLimit = mass * acceleration * 2.5
			if force.Magnitude > maxForceLimit then force = force.Unit * maxForceLimit end
			frc.set(force)
			if not cruise then targetSpeed = velocity:Dot(moveDir) end
		else
			clearDrive()
		end
	else
		clearDrive()
		reverseHold = false
		if not cruise then
			local hv = K.flat(velocity)
			targetSpeed = flatLook.Magnitude > 0.001 and hv:Dot(flatLook) or hv.Magnitude
		end
	end
	-- 抓地：把速度方向朝推进方向回正
	if turned and flatLook.Magnitude > 0.001 then
		local hv = K.flat(velocity)
		if hv.Magnitude > 0.5 then
			local gripTarget = flatLook
			if hv.Unit:Dot(flatLook) < 0 then gripTarget = -flatLook end
			local lerpFactor = math.clamp(deltaTime * CFG.TurnGrip, 0, 1)
			local newDir = hv.Unit:Lerp(gripTarget, lerpFactor)
			if newDir.Magnitude > 0.001 then
				pcall(function()
					part.AssemblyLinearVelocity = newDir.Unit * hv.Magnitude + Vector3.new(0, velocity.Y, 0)
				end)
			end
		end
	end
	-- 旋转逻辑已提前到循环开头（见 spinActive）
end))

-- 座位同步（含 MaxSpeed 保存/还原，避免离座后永久失去限速）
local function setSeat(newSeat)
	if seat == newSeat then return end
	clearDrive()
	local oldSeat = seat
	if oldSeat and oldSeat.Parent then
		local original = seatMaxSpeedSaved[oldSeat]
		if original then pcall(function() oldSeat.MaxSpeed = original end) end
	end
	seatMaxSpeedSaved[oldSeat] = nil
	seat = nil
	accelerating, decelerating = false, false
	steerValue = 0
	cruise, stopped = false, false
	targetSpeed = 0
	flyVertVel = 0
	clipDirty = true
	clipFalling = false
	if not newSeat or (not newSeat:IsA("VehicleSeat") and not newSeat:IsA("Seat")) then return end
	seat = newSeat
	learnContainerFromModel(newSeat:FindFirstAncestorWhichIsA("Model"))
	if seatMaxSpeedSaved[seat] == nil then
		local okM, orig = pcall(function() return seat.MaxSpeed end)
		if okM then seatMaxSpeedSaved[seat] = orig end
	end
	pcall(function() seat.MaxSpeed = math.huge end)
	rearmLights()
	collectEngineSounds()
end

local function syncSeatFromContext()
	local s = K.context.seat
	if K.context.seated and s and (s:IsA("VehicleSeat") or s:IsA("Seat")) then
		setSeat(s)
	else
		setSeat(nil)
	end
end

M.reg(K.context.changed:Connect(function(key)
	if key == "seat" or key == "seated" then syncSeatFromContext() end
end))
-- 初始同步在 50 末尾执行（setSeat 会调用 40 才定义的灯光/引擎函数）
