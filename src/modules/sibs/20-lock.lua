-- sibs / 20-lock — 锁定状态、换车、自动锁定（含所有权接管与重连）

-- 换车按钮文字（switchButton 在 50 才创建，故做 nil 守卫）
local function setNoCharLabel(extra)
	if not switchButton then return end
	if locked and lockModel then
		local name = tostring(myVehicleName or lockModel.Name)
		local tag = " "
		if playerOwnsModel(lockModel) then tag = "·主"
		elseif isMyVehicle(lockModel) then tag = "·我" end
		local maxLen = tag ~= " " and 5 or 8
		if #name > maxLen then name = name:sub(1, maxLen - 1) .. "…" end
		switchButton.Text = "换车 " .. name .. tag
	else
		switchButton.Text = extra or "换车"
	end
end

local function resetLockState()
	if modelAddedConn then pcall(function() modelAddedConn:Disconnect() end); modelAddedConn = nil end
	lockPart, lockModel = nil, nil
	lockPartScore = 0
	locked = false
	clipDirty = true
	accelerating, decelerating = false, false
	steerValue = 0
	cruise, stopped = false, false
	targetSpeed = 0
	reverseHold = false
end

-- 锁定模型（根部件评分 < 85 时挂 DescendantAdded 追踪更优根部件并使缓存失效）
local function applyLock(model)
	if not model or not model.Parent or not modelIsVehicleLike(model) then return false end
	local rootP, score = getRootPart(model)
	if not rootP then return false end
	lockModel = model
	lockPart = resolveAssemblyAnchor(rootP)
	lockPartScore = score
	locked = true
	clipDirty = true
	reverseHold = false
	targetSpeed = 0
	flyVertVel = 0
	clipFalling = false
	rememberMyVehicle(model, lockPart)
	learnContainerFromModel(model)
	rearmLights()
	collectEngineSounds()
	setNoCharLabel()
	toast("锁定 " .. tostring(myVehicleName or model.Name), K.Col.Good)
	if modelAddedConn then pcall(function() modelAddedConn:Disconnect() end); modelAddedConn = nil end
	if lockPartScore < 85 then
		modelAddedConn = model.DescendantAdded:Connect(function(desc)
			if not locked or lockModel ~= model then return end
			if desc:IsA("BasePart") then
				invalidateVehicleLike(model)
				rootPartCache[model] = nil
				local newScore = evaluatePartScore(model, desc)
				if newScore > lockPartScore then
					lockPart = resolveAssemblyAnchor(desc)
					lockPartScore = newScore
					clearDrive()
					ensureDrive(lockPart)
					if newScore >= 90 and modelAddedConn then
						pcall(function() modelAddedConn:Disconnect() end)
						modelAddedConn = nil
					end
				end
			end
		end)
	end
	return true
end

-- 换车：相机瞄准优先，否则按距离循环
local function cycleVehicle()
	local now = os.clock()
	cachedModels, cachedModelsAt = nil, 0
	local models = scanCandidates()
	local aim = getCameraAimModel(models, true)
	lastAim = aim
	if aim and aim ~= lockModel and modelIsVehicleLike(aim) and not modelExcluded(aim) then
		manualLockUntil = now + CFG.ManualLockDuration
		if applyLock(aim) then return end
	end
	local cam = workspace.CurrentCamera
	if not cam or #models == 0 then setNoCharLabel("无车"); toast("无车", K.Col.Wait); return end
	local camPos = cam.CFrame.Position
	local entries = {}
	for _, m in ipairs(models) do
		local rp = getRootPart(m)
		if rp and modelIsVehicleLike(m) and not modelExcluded(m) then
			local dist = (rp.Position - camPos).Magnitude
			if dist <= CFG.MaxSwitchDist then entries[#entries + 1] = {model = m, dist = dist} end
		end
	end
	if #entries == 0 then setNoCharLabel("无可用"); toast("无可用车辆", K.Col.Wait); return end
	table.sort(entries, function(a, b) return a.dist < b.dist end)
	local idx = 0
	for i, e in ipairs(entries) do
		if e.model == lockModel then idx = i; break end
	end
	idx = (idx % #entries) + 1
	manualLockUntil = now + CFG.ManualLockDuration
	if applyLock(entries[idx].model) then return end
	if not locked and #models > 0 then
		local best, bestD = nil, math.huge
		for _, m in ipairs(models) do
			local rp = getRootPart(m)
			if rp then
				local d = (rp.Position - camPos).Magnitude
				if d < bestD then best, bestD = m, d end
			end
		end
		if best then applyLock(best) end
	end
end

-- 模型缓存（0.8s + DescendantAdded 触发的 forceRescan）
local function refreshModelCache(now)
	if not cachedModels or now - cachedModelsAt >= CFG.NoCharScan or forceRescan then
		local okScan, result = pcall(scanCandidates)
		cachedModels = okScan and result or nil
		cachedModelsAt = now
		forceRescan = false
	end
end

local function findOwnedModel()
	refreshModelCache(os.clock())
	local list = cachedModels
	if not list then return nil end
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or nil
	local best, bestD = nil, math.huge
	for _, m in ipairs(list) do
		if modelIsVehicleLike(m) and playerOwnsModel(m) and not modelExcluded(m) then
			local rp = getRootPart(m)
			if rp then
				local d = camPos and (rp.Position - camPos).Magnitude or 0
				if d < bestD then best, bestD = m, d end
			end
		end
	end
	return best
end

-- 锁定维护：有效性 → 所有权接管 → 重连 → 自动扫描锁定
local function updateLockBinding(now)
	if locked then
		local partValid = lockPart and lockPart.Parent and lockPart:IsDescendantOf(workspace)
		local modelValid = lockModel and lockModel.Parent and lockModel:IsDescendantOf(workspace)
		if partValid and modelValid then
			if now < manualLockUntil then return end
			if not playerOwnsModel(lockModel) and now - lastOwnedCheck >= CFG.OwnedTakeoverInterval then
				lastOwnedCheck = now
				local mine = findOwnedModel()
				if mine and mine ~= lockModel then applyLock(mine); return end
			end
			return
		end
		clearDrive()
		locked = false
		reconnectTarget = lockModel
		resetLockState()
		collectEngineSounds()
		setNoCharLabel("重连新车…")
		toast("锁定丢失", K.Col.Bad)
	end
	if reconnectTarget and reconnectTarget.Parent then
		local rp = getRootPart(reconnectTarget)
		if rp and not modelExcluded(reconnectTarget) then
			if applyLock(reconnectTarget) then
				reconnectTarget = nil
				return
			end
		end
	end
	reconnectTarget = nil
	if now - lastAutoScan < CFG.NoCharScan and not forceRescan then return end
	lastAutoScan = now
	local cam = workspace.CurrentCamera
	if not cam then return end
	refreshModelCache(now)
	local models = cachedModels
	if not models or #models == 0 then return end
	-- 优先找回我的车（装配体 → 容器名）
	if myVehicleAsm then
		for _, m in ipairs(models) do
			if modelIsVehicleLike(m) and not modelExcluded(m) then
				local rp = getRootPart(m)
				if rp then
					local okA, asm = pcall(function() return rp.AssemblyRootPart end)
					if okA and asm == myVehicleAsm then
						if applyLock(m) then return end
					end
				end
			end
		end
	end
	if myVehicleName then
		for _, m in ipairs(models) do
			if modelIsVehicleLike(m) and not modelExcluded(m) then
				local rp = getRootPart(m)
				if rp and vehicleLabelFrom(rp) == myVehicleName then
					if applyLock(m) then return end
				end
			end
		end
	end
	-- 打分锁定
	local aimTarget = getCameraAimModel(models)
	lastAim = aimTarget
	local camPos = cam.CFrame.Position
	local look = cam.CFrame.LookVector
	local charRoot = player.Character and K.getRoot(player.Character) or nil
	local charPos = charRoot and charRoot.Position or nil
	local best, bestScore = nil, math.huge
	for _, model in ipairs(models) do
		if modelIsVehicleLike(model) then
			local rp = getRootPart(model)
			if rp then
				local delta = rp.Position - camPos
				local partD = delta.Magnitude
				local vv = rp.AssemblyLinearVelocity
				local sp = K.flat(vv).Magnitude
				if not modelExcluded(model) and (sp <= CFG.MovingCarSpeed or isMyVehicle(model) or playerOwnsModel(model)) then
					local cos = partD > 1e-3 and delta:Dot(look) / partD or 1
					local onScreen = getModelScreenInfo(model, rp, cam)
					if onScreen or playerOwnsModel(model) then
						local score = candidateScore(model, rp, partD, cos, onScreen, charPos, aimTarget, sp)
						if score < bestScore then best, bestScore = model, score end
					end
				end
			end
		end
	end
	if best then applyLock(best) end
end

-- 新出现的 Model 立即触发重扫（补偿 0.8s 的扫描间隔）
M.reg(workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("Model") then forceRescan = true end
end))
