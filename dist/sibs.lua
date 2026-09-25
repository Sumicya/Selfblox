-- sibs.lua — KIT v10 单文件 bundle（由 build.py 生成，勿直接编辑）
-- 源: src/modules/sibs/00-head.lua, src/modules/sibs/10-scan.lua, src/modules/sibs/20-lock.lua, src/modules/sibs/30-drive.lua, src/modules/sibs/40-signals.lua, src/modules/sibs/50-ui.lua
-- 构建: python3 build.py

-- ==== src/modules/sibs/00-head.lua ====
-- sibs / 00-head — 载具控制：状态、配置、前向声明
-- 依赖：kit v10（kit.lua 先执行）
-- 功能：锁定/换车/车列表/加速减速/转向滑条/旋转滑条/翻转/定速/穿墙/飞车/灯/喇叭/引擎音调
-- 约定：缩进用单个 Tab

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

local NAME = "SIBS"
local K = _G.KIT
if not K or K.ver < 10 or type(K.mod) ~= "function" then
	error("[sibs] 请先执行 kit.lua（需要 _G.KIT v10）", 0)
end

local mk = K.mk
local toast = K.toast
local M = K.mod(NAME, {DisplayOrder = 99998, TitleH = 24, InputRowH = 26, RowH = 32,
	SigRowH = 30, BtnH = 44, PanelW = 180, PanelVisibleH = 480})
local CFG = M.cfg
CFG.Acceleration = 500
CFG.TurnSpeed = 2.2
CFG.TurnGrip = 5
CFG.HighSpeedTurnFloor = 0.62
CFG.NoCharScan = 0.8
CFG.NoCharScreenMargin = 80
CFG.NoCharOwnCarDist = 15
CFG.ManualLockDuration = 8
CFG.OwnedTakeoverInterval = 0.5
CFG.MovingCarSpeed = 15
CFG.NearOwnDist = 25
CFG.AimRadius = 0.20
CFG.MaxSwitchDist = 500
CFG.MinVehicleParts = 6
CFG.ClipFallSpeed = -20
CFG.ClipFallProbeDist = 60
CFG.ClipRebuildInterval = 0.5
CFG.HoverBand = 2
CFG.HoverSinkCap = -10
CFG.HoverPushGain = 10
CFG.HoverPushMax = 30
CFG.HornKey = Enum.KeyCode.H
CFG.LampKey = Enum.KeyCode.O
CFG.FlySpeed = 60
CFG.FlyVertAccel = 80
CFG.BrakeDecelMult = 2
CFG.GroundClearance = 3
CFG.GroundProbeExtra = 6
CFG.FlashHalfPeriod = 0.1
CFG.BrakeDeadzone = 2
CFG.CruiseDeadzone = 3
CFG.CruiseGain = 2
CFG.ForceDeadzone = 0.5
CFG.VehicleMinScore = 20
CFG.SpinMax = 15
CFG.SteerMaxDeg = 45
CFG.VehicleLikeTTL = 2
CFG.RootPartTTL = 1.5
CFG.TurnGrip = K.loadPrefixedNumber(NAME, "Grip", CFG.TurnGrip)

-- 状态
local seat = nil
local acceleration = K.loadPrefixedNumber(NAME, "Acc", CFG.Acceleration)
local accelerating, decelerating = false, false
local steerValue = 0
local spinSpeed = K.loadPrefixedNumber(NAME, "Spin", 0)
local cruise, stopped = false, false
local targetSpeed = 0
local locked = false
local lockModel, lockPart = nil, nil
local lockPartScore = 0
local manualLockUntil = 0
local lastAutoScan = 0
local lastOwnedCheck = 0
local noClip = K.loadPrefixed(NAME, "NoClip", false) == true
local carFly = false
local flyUp, flyDown = false, false
local flyVertVel = 0
local drive = nil
local carFlyHandle = nil
local spinHandle = nil
local lightsOn = false
local nativeHead, nativeTail = {}, {}
local createdLamps = {}
local lightSteady = false
local hornSteady = false
local flashUntil, beepUntil = 0, 0
local hornKeyIsDown = false
local clipParts, clipWheels = {}, {}
local clipDirty = true
local clipOriginal = setmetatable({}, {__mode = "k"})
local clipSetState = setmetatable({}, {__mode = "k"})
local clipModel = nil
local clipFalling = false
local reverseHold = false
local myVehicleModel, myVehicleName, myVehicleAsm = nil, nil, nil
local lastAim = nil
local learnedRoots = setmetatable({}, {__mode = "k"})
local modelAddedConn = nil
local vehicleCount = 0
local cachedModels, cachedModelsAt = nil, 0
local lastGrounded = false
local reconnectTarget = nil
local forceRescan = false
local seatMaxSpeedSaved = setmetatable({}, {__mode = "k"})

-- UI 按钮 local（定义早、赋值晚：帮助函数可先引用）
local switchButton, stopButton

-- 前向声明：这些函数在 20/30/40 才定义，但 20/30 会调用
local clearDrive, ensureDrive, rearmLights, collectEngineSounds

-- 扫描根与轮毂识别
local SCAN_ROOT_NAMES = {"Vehicles", "Cars", "Spawned", "PlayerVehicles", "Driveable",
	"CarSpawns", "Bricks", "Blocks", "Drift"}
local WHEEL_CORNERS = {"fl", "fr", "rl", "rr", "lf", "lr", "rf"}

-- 急刹按钮刷新（仅依赖状态与 stopButton local，可最早定义）
local function refreshStopButton()
	if not stopButton then return end
	stopButton.Text = stopped and "急刹 开" or "急刹 关"
	stopButton.BackgroundColor3 = stopped and CFG.Col.On or CFG.Col.Stop
end

-- ==== src/modules/sibs/10-scan.lua ====
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

-- ==== src/modules/sibs/20-lock.lua ====
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

-- ==== src/modules/sibs/30-drive.lua ====
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
	-- 转向：直接旋转向量（速度不敏感的角位移）
	local turned = false
	if math.abs(steerInput) > 0.02 then
		turned = true
		local speed = velocity.Magnitude
		local speedFactor = math.clamp(1 - (speed / 180) * 0.35, CFG.HighSpeedTurnFloor, 1)
		local turnAngle = steerInput * CFG.TurnSpeed * speedFactor * deltaTime
		local pos = part.Position
		local rot = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), turnAngle)
		pcall(function() part.CFrame = (rot * (part.CFrame - pos)) + pos end)
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
	-- 旋转滑条（角速度常驻）
	if math.abs(spinSpeed) > 0.1 then
		if not spinHandle or not spinHandle.alive() or spinHandle.part ~= part then
			if spinHandle then spinHandle.destroy() end
			spinHandle = K.force.angular(part, "SIBS_Spin")
		end
		if spinHandle then spinHandle.set(Vector3.new(0, spinSpeed, 0)) end
	else
		if spinHandle then spinHandle.set(Vector3.zero) end
	end
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

-- ==== src/modules/sibs/40-signals.lua ====
-- sibs / 40-signals — 灯光、喇叭（按键探测）、引擎音调、心跳调度

-- 引擎音调：收集带关键词的 Sound，按车速调 PlaybackSpeed；
-- 外部改动（游戏自己在调）则让位不再接管
local ENGINE_KEYWORDS = {"engine", "motor", "idle"}
local engineSounds = {}

function collectEngineSounds()
	for _, rec in ipairs(engineSounds) do
		if not rec.foreign then pcall(function() rec.sound.PlaybackSpeed = rec.base end) end
	end
	table.clear(engineSounds)
	local container = getControlledVehicleModel()
	if not container then return end
	local n = 0
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("Sound") then
			local ln = d.Name:lower()
			for _, kw in ipairs(ENGINE_KEYWORDS) do
				if ln:find(kw, 1, true) then
					n += 1
					if n <= 6 then
						engineSounds[#engineSounds + 1] =
							{sound = d, base = d.PlaybackSpeed, lastSet = d.PlaybackSpeed, foreign = false}
					end
					break
				end
			end
		end
	end
end

local function updateEngineSounds()
	local part = seat or lockPart
	if not part or not part.Parent or #engineSounds == 0 then return end
	local v = part.AssemblyLinearVelocity
	local speed = math.sqrt(v.X ^ 2 + v.Z ^ 2)
	local ratio = 0.6 + math.clamp(speed / 150, 0, 1.4)
	for _, rec in ipairs(engineSounds) do
		local s = rec.sound
		if s.Parent and not rec.foreign then
			local cur = s.PlaybackSpeed
			if math.abs(cur - rec.lastSet) > 0.02 then
				pcall(function() s.PlaybackSpeed = rec.base end)
				rec.foreign = true
			else
				local want = rec.base * ratio
				if math.abs(cur - want) > 0.02 then
					pcall(function() s.PlaybackSpeed = want end)
					rec.lastSet = want
				else
					rec.lastSet = cur
				end
			end
		end
	end
end

-- 灯光：优先接管车体自带灯（前向分组），否则创建三只覆盖灯
local function restoreLamps()
	for _, rec in ipairs(nativeHead) do pcall(function() rec.light.Enabled = rec.saved end) end
	for _, rec in ipairs(nativeTail) do pcall(function() rec.light.Enabled = rec.saved end) end
	table.clear(nativeHead)
	table.clear(nativeTail)
	for _, l in ipairs(createdLamps) do pcall(function() l:Destroy() end) end
	table.clear(createdLamps)
	lightsOn = false
end

local function collectNativeLights()
	local model = getControlledVehicleModel()
	local part = seat or lockPart
	if not model or not part or not part.Parent then return end
	local fwd = getVehicleFacing(part)
	if fwd.Magnitude < 0.001 then fwd = K.flatUnit(part.CFrame.LookVector, Vector3.new(0, 0, -1)) end
	if fwd.Magnitude < 0.001 then return end
	local anchorPos = part.Position
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		n += 1
		if n > 400 then break end
		if (d:IsA("SpotLight") or d:IsA("SurfaceLight") or d:IsA("PointLight"))
			and d.Parent and d.Parent:IsA("BasePart") then
			local rel = (d.Parent.Position - anchorPos):Dot(fwd)
			local rec = {light = d, saved = d.Enabled}
			if rel >= 0 then
				if #nativeHead < 12 then nativeHead[#nativeHead + 1] = rec end
			else
				if #nativeTail < 8 then nativeTail[#nativeTail + 1] = rec end
			end
		end
	end
end

local function armLights()
	if lightsOn then return true end
	local model = getControlledVehicleModel()
	local part = seat or lockPart
	if not model or not part or not part.Parent then return false end
	collectNativeLights()
	if #nativeHead > 0 or #nativeTail > 0 then lightsOn = true; return true end
	local okPP, pp = pcall(function() return model.PrimaryPart end)
	local parentPart = (okPP and pp and pp.Parent and pp) or part
	if parentPart and parentPart.Parent then
		pcall(function()
			local front = Instance.new("SpotLight")
			front.Name = "SIBS_OvFront"
			front.Brightness = 14
			front.Range = 160
			front.Angle = 85
			front.Face = Enum.NormalId.Front
			front.Enabled = false
			front.Parent = parentPart
			createdLamps[#createdLamps + 1] = front
			local back = Instance.new("SpotLight")
			back.Name = "SIBS_OvBack"
			back.Brightness = 8
			back.Range = 80
			back.Angle = 75
			back.Color = Color3.fromRGB(255, 40, 40)
			back.Face = Enum.NormalId.Back
			back.Enabled = false
			back.Parent = parentPart
			createdLamps[#createdLamps + 1] = back
			local glow = Instance.new("PointLight")
			glow.Name = "SIBS_OvGlow"
			glow.Brightness = 4
			glow.Range = 60
			glow.Enabled = false
			glow.Parent = parentPart
			createdLamps[#createdLamps + 1] = glow
		end)
		lightsOn = #createdLamps > 0
	end
	return lightsOn
end

function rearmLights()
	restoreLamps()
	if lightSteady or (os.clock() < flashUntil) then armLights() end
end

local function applyLamps(on)
	for _, rec in ipairs(nativeHead) do pcall(function() rec.light.Enabled = on end) end
	for _, rec in ipairs(nativeTail) do pcall(function() rec.light.Enabled = on end) end
	for _, l in ipairs(createdLamps) do
		if l and l.Parent then pcall(function() l.Enabled = on end) end
	end
end

-- 喇叭：优先 keypress 注入；探测候选键（按住时是否有 horn 类 Sound 开始播放）
local savedHornKeyName = K.loadPrefixed(NAME, "HornKey", nil)
local hornKey = CFG.HornKey
local hornKeyFound = false
if type(savedHornKeyName) == "string" then
	local ok, k = pcall(function() return Enum.KeyCode[savedHornKeyName] end)
	if ok and k then
		hornKey = k
		hornKeyFound = true
	end
end
local hornDetecting = false
local HORN_CANDIDATES = {"H", "G", "J", "K", "B", "N", "F"}

local function sendKey(key, down)
	if K.env.hasKeypress then
		if down then pcall(keypress, key) else pcall(keyrelease, key) end
	elseif K.env.hasVIM then
		pcall(function()
			local vim = game:GetService("VirtualInputManager")
			vim:SendKeyEvent(down, key, false, game)
		end)
	end
end

local function detectHornKey()
	if hornDetecting then return false end
	local container = getControlledVehicleModel()
	if not container or not (seat and seat.Parent) then
		toast("先坐进车里再点喇叭", K.Col.Wait)
		return false
	end
	hornDetecting = true
	toast("探测喇叭键中…", K.Col.Bind)
	task.spawn(function()
		local found = nil
		for _, name in ipairs(HORN_CANDIDATES) do
			local okK, key = pcall(function() return Enum.KeyCode[name] end)
			if not okK then continue end
			local before = {}
			for _, d in ipairs(container:GetDescendants()) do
				if d:IsA("Sound") then before[d] = d.Playing end
			end
			sendKey(key, true)
			task.wait(0.18)
			sendKey(key, false)
			task.wait(0.12)
			if not container.Parent then break end
			for _, d in ipairs(container:GetDescendants()) do
				if d:IsA("Sound") and before[d] ~= true and d.Playing == true then
					local ln = d.Name:lower()
					if ln:find("horn", 1, true) or ln:find("klaxon", 1, true) or ln:find("beep", 1, true) then
						found = key
						break
					end
				end
			end
			if found then break end
		end
		hornDetecting = false
		if found then
			hornKey = found
			hornKeyFound = true
			K.savePrefixed(NAME, "HornKey", found.Name)
			toast("喇叭键: " .. found.Name, K.Col.Good)
		else
			toast("未探测到，默认 " .. hornKey.Name, K.Col.Wait)
		end
	end)
	return true
end

local function setHornKey(down)
	if hornKeyIsDown == down then return end
	hornKeyIsDown = down
	sendKey(hornKey, down)
end

-- 心跳：灯光闪烁方波、喇叭按住/松开、引擎音调跟随
M.reg(RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local lightOn = false
	if now < flashUntil then
		lightOn = (math.floor(now / CFG.FlashHalfPeriod) % 2) == 0
	elseif lightSteady then
		lightOn = true
	end
	if lightsOn then applyLamps(lightOn) end
	local wantHorn = false
	if now < beepUntil then wantHorn = true
	elseif hornSteady then wantHorn = true end
	if not hornDetecting then
		if wantHorn and not hornKeyIsDown then setHornKey(true)
		elseif not wantHorn and hornKeyIsDown then setHornKey(false) end
	end
	updateEngineSounds()
end))

-- ==== src/modules/sibs/50-ui.lua ====
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

