-- sibs / 10-scan — 轮毂识别、车辆判定（TTL 缓存）、根部件评分、所有权、扫描与瞄准

-- 轮毂识别（名字启发；沿父级上溯 3 层）
local function nameLooksLikeWheel(name)
	local n = tostring(name):lower()
	if n == "" then return false end
	if n:find("suspension", 1, true) or n:find("axle", 1, true)
		or n:find("spring", 1, true) or n:find("shock", 1, true) then
		return false
	end
	if n:find("wheel", 1, true) or n:find("tire", 1, true) or n:find("tyre", 1, true) then return true end
	for _, c in ipairs(WHEEL_CORNERS) do
		if n == c or n:match("^" .. c .. "[%_%-%s%d]")
			or n:match("[%_%-%s%d]" .. c .. "$")
			or n:match("[%_%-%s%d]" .. c .. "[%_%-%s%d]") then
			return true
		end
	end
	return false
end

local function isWheel(part)
	if not part or not part:IsA("BasePart") then return false end
	if nameLooksLikeWheel(part.Name) then return true end
	local cur = part.Parent
	for _ = 1, 3 do
		if not cur then break end
		if (cur:IsA("Model") or cur:IsA("Folder")) and nameLooksLikeWheel(cur.Name) then return true end
		cur = cur.Parent
	end
	return false
end

local function isMapModel(model)
	if not model then return false end
	local cur = model
	while cur and cur ~= workspace do
		if cur.Name:lower() == "map" then return true end
		cur = cur.Parent
	end
	return false
end

-- 车辆判定（2s TTL；运行中加装座位/轮子后按时失效，DescendantAdded 主动失效）
local vehicleLikeCache = setmetatable({}, {__mode = "k"})

local function invalidateVehicleLike(model)
	if model then vehicleLikeCache[model] = nil end
end

local function modelIsVehicleLike(model)
	if not model or not model:IsA("Model") or not model.Parent then return false end
	local now = os.clock()
	local cached = vehicleLikeCache[model]
	if cached ~= nil then
		if now - cached.at < CFG.VehicleLikeTTL then return cached.result end
	end
	local result = false
	pcall(function()
		if isMapModel(model) then result = false; return end
		if model:FindFirstChildOfClass("Humanoid") then result = false; return end
		local hasSeat, wheelCount, partCount, anchoredCount, nonAnchoredMass, n = false, 0, 0, 0, 0, 0
		for _, d in ipairs(model:GetDescendants()) do
			n += 1
			if n > 300 then break end
			if d:IsA("Seat") or d:IsA("VehicleSeat") then hasSeat = true end
			if d:IsA("BasePart") then
				partCount += 1
				if d.Anchored then anchoredCount += 1
				else
					local okM, m = pcall(function() return d.Mass end)
					if okM and type(m) == "number" then nonAnchoredMass += m end
				end
				if isWheel(d) then wheelCount += 1 end
			end
			if hasSeat and wheelCount >= 2 then break end
		end
		if partCount > 0 and anchoredCount == partCount then result = false; return end
		local score = 0
		if hasSeat then score += 60 end
		if wheelCount >= 2 then score += 20 end
		if wheelCount >= 4 then score += 10 end
		if nonAnchoredMass > 1 then score += 10 end
		if partCount > 2 then score += 10 end
		result = score >= CFG.VehicleMinScore
	end)
	vehicleLikeCache[model] = {result = result, at = now}
	return result
end

-- 无效模型判定（地图/角色/非载具）
local function modelExcluded(model)
	if not model or not model.Parent then return true end
	if not model:IsA("Model") then return true end
	if model:FindFirstChildOfClass("Humanoid") then return true end
	if not modelIsVehicleLike(model) then return true end
	if isMapModel(model) then return true end
	return false
end

-- 根部件评分（固定降序前缀表，保证同名多关键词时打分确定）
local ROOT_WEIGHTS = {Primary = 95, Root = 90, Chassis = 85, Base = 80, Main = 75, Body = 60, Core = 55, Hull = 50}
local ROOT_PREFIX_ORDER = {"Primary", "Root", "Chassis", "Base", "Main", "Body", "Core", "Hull"}
local NON_ROOT_PARTS = {"hitbox", "hitboxes", "detector", "sensor", "trigger", "zone", "sound", "billboard", "particle"}

local function evaluatePartScore(model, part)
	if not part or not part:IsA("BasePart") or part.Anchored or isWheel(part) then return -1 end
	if model and part == model.PrimaryPart then return 100 end
	local lowerName = part.Name:lower()
	for _, p in ipairs(NON_ROOT_PARTS) do
		if lowerName:find(p, 1, true) then return -1 end
	end
	if ROOT_WEIGHTS[part.Name] then return ROOT_WEIGHTS[part.Name] end
	for _, prefix in ipairs(ROOT_PREFIX_ORDER) do
		if lowerName:find(prefix:lower(), 1, true) then return ROOT_WEIGHTS[prefix] - 5 end
	end
	if part:IsA("VehicleSeat") or part:IsA("Seat") then return 45 end
	local okM, m = pcall(function() return part.Mass end)
	local mass = (okM and type(m) == "number") and m or 0
	return math.min(10 + mass * 0.1, 40)
end

-- 扫描根定位
local function isScanRoot(inst)
	if not inst then return false end
	if inst == workspace then return true end
	if learnedRoots[inst] then return true end
	for _, n in ipairs(SCAN_ROOT_NAMES) do
		if inst.Name == n then return true end
	end
	return false
end

local function vehicleContainerFrom(inst)
	local cur = inst
	while cur and cur.Parent do
		if isScanRoot(cur.Parent) then return cur end
		local p = cur.Parent
		if not (p:IsA("Model") or p:IsA("Folder")) then return cur end
		cur = p
	end
	return cur
end

local function vehicleLabelFrom(inst)
	local c = vehicleContainerFrom(inst)
	return tostring(c and c.Name or "?")
end

local function sameAssembly(a, b)
	if not a or not b then return false end
	if a == b then return true end
	local okA, ra = pcall(function() return a.AssemblyRootPart end)
	local okB, rb = pcall(function() return b.AssemblyRootPart end)
	return okA and okB and ra == rb
end

local function resolveAssemblyAnchor(part)
	if not part or not part.Parent then return part end
	local okA, asm = pcall(function() return part.AssemblyRootPart end)
	if not okA or not asm or not asm.Parent or asm.Anchored then return part end
	if not isWheel(asm) then return asm end
	local best, bestScore = nil, -1
	local okC, parts = pcall(function() return asm:GetConnectedParts(true) end)
	if okC and type(parts) == "table" then
		local n = 0
		for _, p in ipairs(parts) do
			n += 1
			if n > 200 then break end
			if p:IsA("BasePart") then
				local s = evaluatePartScore(nil, p)
				if s > bestScore then best, bestScore = p, s end
			end
		end
	end
	return best or asm
end

-- 根部件缓存（1.5s TTL 一律返回，不按分数决定是否信任）
local rootPartCache = setmetatable({}, {__mode = "k"})

local function getRootPart(model)
	if not model or not model:IsA("Model") or not model.Parent then return nil, 0 end
	local now = os.clock()
	local cached = rootPartCache[model]
	if cached and cached.part and cached.part.Parent
		and cached.part:IsDescendantOf(model) and not cached.part.Anchored then
		if now - cached.at < CFG.RootPartTTL then return cached.part, cached.score end
	end
	local bestPart, bestScore = nil, -1
	pcall(function()
		local pp = model.PrimaryPart
		if pp and pp:IsDescendantOf(model) and not pp.Anchored and not isWheel(pp) then
			bestPart, bestScore = pp, 100
			return
		end
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			n += 1
			if n > 250 then break end
			local score = evaluatePartScore(model, d)
			if score > bestScore then
				bestPart, bestScore = d, score
				if score >= 95 then break end
			end
		end
	end)
	if bestPart then rootPartCache[model] = {part = bestPart, score = bestScore, at = now} end
	return bestPart, bestScore
end

-- 所有权（属性 / ObjectValue / StringValue，5s TTL）
local ownerCache = setmetatable({}, {__mode = "k"})
local OWNER_CACHE_TTL = 5

local function computeOwned(model)
	local myId = player.UserId
	local myName = player.Name
	local myDisp = player.DisplayName
	local owned = false
	pcall(function()
		local okA, attrs = pcall(function() return model:GetAttributes() end)
		if okA and type(attrs) == "table" then
			for key, v in pairs(attrs) do
				local k = tostring(key):lower()
				if k:find("owner") or k:find("creator") or k == "userid" or k == "player" then
					if typeof(v) == "number" and v == myId then owned = true
					elseif typeof(v) == "string" and (v == myName or v == myDisp) then owned = true end
					if owned then return end
				end
			end
		end
	end)
	if not owned then
		pcall(function()
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do
				n += 1
				if n > 150 or owned then break end
				local dn = d.Name:lower()
				local isOwnerObj = d:IsA("ObjectValue")
					or ((d:IsA("StringValue") or d:IsA("IntValue") or d:IsA("NumberValue"))
					and (dn:find("owner") or dn:find("creator") or dn:find("player") or dn:find("user")))
				if isOwnerObj then
					local okV, v = pcall(function() return d.Value end)
					if okV then
						if v == player then owned = true
						elseif typeof(v) == "number" and v == myId then owned = true
						elseif typeof(v) == "string" and (v == myName or v == myDisp) then owned = true end
					end
				end
			end
		end)
	end
	return owned
end

local function playerOwnsModel(model)
	if not model or not model.Parent then return false end
	local now = os.clock()
	local rec = ownerCache[model]
	if rec and now - rec.at < OWNER_CACHE_TTL then return rec.owned end
	local owned = computeOwned(model)
	ownerCache[model] = {owned = owned, at = now}
	return owned
end

-- 车辆记忆（换车/重连用）
local function rememberMyVehicle(model, anchor)
	if not model or not model.Parent then return end
	myVehicleModel = model
	myVehicleAsm = nil
	myVehicleName = vehicleLabelFrom(anchor or model)
	if anchor and anchor.Parent then
		local okA, asm = pcall(function() return anchor.AssemblyRootPart end)
		if okA and asm and asm.Parent then myVehicleAsm = asm end
	end
end

local function isMyVehicle(model)
	if not model or not model.Parent then return false end
	local rp = getRootPart(model)
	if not rp then return false end
	if myVehicleAsm then
		local okA, asm = pcall(function() return rp.AssemblyRootPart end)
		if okA and asm == myVehicleAsm then return true end
	end
	if myVehicleName and vehicleLabelFrom(rp) == myVehicleName then return true end
	return model == myVehicleModel
end

local function getControlledVehicleModel()
	if seat and seat.Parent then
		local m = seat:FindFirstAncestorWhichIsA("Model")
		if m then return m end
	end
	if lockPart and lockPart.Parent then return vehicleContainerFrom(lockPart) end
	return lockModel
end

local function learnContainerFromModel(model)
	if not model then return end
	local cur = model
	while cur and cur.Parent and cur.Parent ~= workspace do cur = cur.Parent end
	if cur and cur ~= workspace and cur.Parent == workspace then
		if cur:IsA("Folder") or cur:IsA("Model") then learnedRoots[cur] = true end
	end
end

-- 候选扫描
local function getScanRoots()
	local roots, seen = {}, {}
	local function add(folder)
		if folder and folder.Parent and not seen[folder] then
			seen[folder] = true
			roots[#roots + 1] = folder
		end
	end
	for f in pairs(learnedRoots) do
		if f and f.Parent then add(f) else learnedRoots[f] = nil end
	end
	for _, name in ipairs(SCAN_ROOT_NAMES) do
		local f = workspace:FindFirstChild(name)
		if f then add(f) end
	end
	if #roots == 0 then
		for _, child in ipairs(workspace:GetChildren()) do
			if child:IsA("Folder") and child.Name:lower() ~= "map" then
				add(child)
				if #roots >= 5 then break end
			end
		end
	end
	if #roots == 0 then roots[1] = workspace end
	return roots
end

local function collectModels(rootFolder, cap)
	if not rootFolder then return {} end
	local list, count = {}, 0
	local function visit(container, depth)
		if count >= cap or depth > 5 then return end
		for _, child in ipairs(container:GetChildren()) do
			if count >= cap then return end
			if child:IsA("Model") then
				if modelIsVehicleLike(child) and child:FindFirstChildOfClass("Humanoid") == nil then
					local rp = getRootPart(child)
					if rp then count += 1; list[count] = child end
				else
					visit(child, depth + 1)
				end
			elseif child:IsA("Folder") and child.Name:lower() ~= "map" then
				visit(child, depth + 1)
			end
		end
	end
	visit(rootFolder, 0)
	return list
end

-- 同装配体的嵌套模型归组，返回代表模型列表
local function scanCandidates()
	local roots = getScanRoots()
	local seenModels, groups, groupList = {}, {}, {}
	for _, rootFolder in ipairs(roots) do
		local models = collectModels(rootFolder, 800)
		for _, m in ipairs(models) do
			if not seenModels[m] then
				seenModels[m] = true
				local rp = getRootPart(m)
				if rp then
					local okA, asm = pcall(function() return rp.AssemblyRootPart end)
					local key = (okA and asm and asm.Parent and not asm.Anchored) and asm or rp
					local g = groups[key]
					if not g then
						g = {rep = m, repParts = #m:GetDescendants()}
						groups[key] = g
						groupList[#groupList + 1] = g
					elseif #m:GetDescendants() > g.repParts then
						g.repParts = #m:GetDescendants()
						g.rep = m
					end
				end
			end
		end
	end
	local all = {}
	for _, g in ipairs(groupList) do
		local rp = getRootPart(g.rep)
		local count = 0
		if rp then
			local okC, parts = pcall(function() return rp:GetConnectedParts(true) end)
			if okC and type(parts) == "table" then count = #parts + 1 end
		end
		if count >= CFG.MinVehicleParts then all[#all + 1] = g.rep end
	end
	vehicleCount = #all
	return all
end

-- 相机瞄准（射线优先，其次屏幕中心 + 视口内打分）
local camRayParams = RaycastParams.new()
camRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function getVehicleRootFromInstance(inst)
	local cur = inst
	local vehicleLike = nil
	while cur and cur.Parent do
		local p = cur.Parent
		if cur:IsA("Model") and modelIsVehicleLike(cur) then vehicleLike = cur end
		if not (p:IsA("Model") or p:IsA("Folder")) then break end
		cur = p
	end
	if cur and cur:IsA("Model") and modelIsVehicleLike(cur) then vehicleLike = cur end
	return vehicleLike
end

local function getCameraAimModel(models, allowMoving)
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local char = player.Character
	camRayParams.FilterDescendantsInstances = char and {char} or {}
	local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 600, camRayParams)
	if hit then
		local rootM = getVehicleRootFromInstance(hit.Instance)
		if rootM and rootM ~= char and modelIsVehicleLike(rootM) then
			local rpM = getRootPart(rootM)
			for _, m in ipairs(models) do
				if m == rootM then return m end
				local rp = getRootPart(m)
				if rp and rpM and sameAssembly(rp, rpM) then return m end
			end
		end
	end
	local list = models
	if not list then return nil end
	local vp = cam.ViewportSize
	local center = vp * 0.5
	local radius = CFG.AimRadius
	local camPos = cam.CFrame.Position
	local best, bestScore = nil, math.huge
	for _, model in ipairs(list) do
		if modelIsVehicleLike(model) then
			local pp = getRootPart(model) or model.PrimaryPart
			if pp then
				local sp = cam:WorldToViewportPoint(pp.Position)
				if sp.Z > 0 then
					local dx = (sp.X - center.X) / math.max(vp.X, 1)
					local dy = (sp.Y - center.Y) / math.max(vp.Y, 1)
					if math.abs(dx) <= radius and math.abs(dy) <= radius then
						local v = pp.AssemblyLinearVelocity
						local spd = K.flat(v).Magnitude
						if allowMoving or spd <= CFG.MovingCarSpeed or isMyVehicle(model) or playerOwnsModel(model) then
							local ownedBonus = playerOwnsModel(model) and 2000 or 0
							local score = (dx * dx + dy * dy) * 20000 + (pp.Position - camPos).Magnitude - ownedBonus
							if score < bestScore then best, bestScore = model, score end
						end
					end
				end
			end
		end
	end
	return best
end

-- 自动锁定候选打分（越小越优；相机中心/所有权/我的车大幅加分）
local function candidateScore(model, part, partD, cos, onScreen, charPos, camTarget, partSpeed)
	local score = (1 - math.clamp(cos or 0, -1, 1)) * 8000 + partD * 2
	if onScreen then score = score - 400 end
	if model and model.PrimaryPart then score = score - 600 end
	if camTarget and model == camTarget then score = score - 10000 end
	if playerOwnsModel(model) then score = score - 50000 end
	if isMyVehicle(model) then score = score - 20000 end
	if charPos and part then
		local ownDist = (part.Position - charPos).Magnitude
		if (partSpeed or 0) <= 5 and ownDist <= CFG.NearOwnDist then
			score = score - 8000 + ownDist * 100
		elseif ownDist < CFG.NoCharOwnCarDist then
			score = score - (CFG.NoCharOwnCarDist - ownDist) * 120
		end
	end
	return score
end

local function getModelScreenInfo(model, part, cam)
	local viewport = cam.ViewportSize
	local margin = CFG.NoCharScreenMargin
	local function test(pos)
		local screen, visible = cam:WorldToViewportPoint(pos)
		return visible and screen.Z > 0
			and screen.X >= -margin and screen.X <= viewport.X + margin
			and screen.Y >= -margin and screen.Y <= viewport.Y + margin
	end
	local ok, cf = pcall(function() return model:GetBoundingBox() end)
	if ok and cf and test(cf.Position) then return true end
	if part then return test(part.Position) end
	return false
end

-- 控制座位（VehicleSeat 优先）
local controlSeatCache = setmetatable({}, {__mode = "k"})

local function getControlSeat(model)
	if not model then return nil end
	local cached = controlSeatCache[model]
	if cached and cached.Parent and cached:IsDescendantOf(model) then return cached end
	local vs, ss = nil, nil
	pcall(function()
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("VehicleSeat") then vs = d; break
			elseif d:IsA("Seat") and not ss then ss = d end
		end
	end)
	local found = vs or ss
	controlSeatCache[model] = found
	return found
end

-- 载具水平朝向：座位 → 控制座位 → 锁定根
local function getVehicleFacing(root)
	if seat and seat.Parent then
		local l = seat.CFrame.LookVector
		local flat = K.flat(l)
		if flat.Magnitude > 0.001 then return flat.Unit end
	end
	local model = getControlledVehicleModel()
	local vs = getControlSeat(model)
	if vs then
		local l = vs.CFrame.LookVector
		local flat = K.flat(l)
		if flat.Magnitude > 0.001 then return flat.Unit end
	end
	if root and root.Parent then
		local l = root.CFrame.LookVector
		local flat = K.flat(l)
		if flat.Magnitude > 0.001 then return flat.Unit end
	end
	return Vector3.zero
end
