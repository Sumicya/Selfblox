-- Selfblox · SIBS — 载具控制（独立单文件）
-- v11 激进重写：无框架 / 无构建 / 现代 Luau / 原生 API 优先
-- 用法: loadstring(game:HttpGet(".../sibs.lua"))()
-- 功能: 锁定/换车/车列表 / 加速减速 / 转向 / 定速 / 急刹 / 穿墙 / 飞车 / 翻转 / 灯光 / 喇叭 / 引擎音调
-- 注意: 转向滑条仅在主面板折叠时响应（展开时拖动会干扰转向）

local NAME = "SIBS"

-- ===== 0. 重跑替换旧实例 =====

local OLD = rawget(_G, "SB_" .. NAME)
if type(OLD) == "function" then
	pcall(OLD)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
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

for _, n in ipairs({ NAME, NAME .. "_List", NAME .. "_Steer", NAME .. "_Toast" }) do
	local old = GuiRoot:FindFirstChild(n)
	if old then
		pcall(function() old:Destroy() end)
	end
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
	Acceleration = 500, TurnSpeed = 2.2, TurnRefSpeed = 25,
	HighSpeedTurnFloor = 0.62, NoCharScan = 0.8, NoCharScreenMargin = 80,
	NoCharOwnCarDist = 15, ManualLockDuration = 8, OwnedTakeoverInterval = 0.5,
	MovingCarSpeed = 15, NearOwnDist = 25, AimRadius = 0.20, MaxSwitchDist = 500,
	MinVehicleParts = 6, ClipFallSpeed = -20, ClipFallProbeDist = 60, ClipRebuildInterval = 0.5,
	HoverBand = 2, HoverSinkCap = -10, HoverPushGain = 10, HoverPushMax = 30,
	HornKey = Enum.KeyCode.H, LampKey = Enum.KeyCode.O,
	FlySpeed = 60, FlyVertAccel = 80, BrakeDecelMult = 2,
	GroundClearance = 3, GroundProbeExtra = 6, FlashHalfPeriod = 0.1,
	BrakeDeadzone = 2, CruiseDeadzone = 3, CruiseGain = 2, ForceDeadzone = 0.5,
	VehicleMinScore = 20, VehicleLikeTTL = 2, RootPartTTL = 1.5,
}
CFG.TurnGrip = cfgGetNum("SIBSGrip", 5)
CFG.Acceleration = cfgGetNum("SIBSAcc", CFG.Acceleration)

local COL = {
	On = Color3.fromRGB(38, 125, 85), Off = Color3.fromRGB(48, 50, 60),
	Good = Color3.fromRGB(135, 215, 155), Bad = Color3.fromRGB(225, 135, 135),
	Wait = Color3.fromRGB(170, 175, 185), Bind = Color3.fromRGB(95, 65, 135),
	Danger = Color3.fromRGB(155, 45, 45), Stop = Color3.fromRGB(155, 45, 45),
	Accel = Color3.fromRGB(30, 85, 115), Decel = Color3.fromRGB(130, 90, 40),
}
local BG = Color3.fromRGB(20, 22, 28)
local ALPHA = 0.72
local SAFE_TOP = 48
local TITLE_H, INPUT_ROW_H, ROW_H, SIG_ROW_H, BTN_H, PANEL_W = 24, 26, 32, 30, 44, 180

local B = {} -- UI/状态合并表(避免超 200 local 寄存器上限)
B.seat = nil
local acceleration = CFG.Acceleration
local accelerating, decelerating = false, false
local steerValue = 0
local cruise, stopped = false, false
local targetSpeed = 0
local locked = false
local lockModel, lockPart = nil, nil
local lockPartScore = 0
local manualLockUntil = 0
local lastAutoScan = 0
local lastOwnedCheck = 0
local noClip = cfgGet("SIBSNoClip", false) == true
local carFly = false
local flyUp, flyDown = false, false
local flyVertVel = 0
local lightsOn = false
B.nativeHead = {}
B.nativeTail = {}
B.createdLamps = {}
local lightSteady = false
local hornSteady = false
local flashUntil, beepUntil = 0, 0
local hornKeyIsDown = false
B.clipParts = {}
B.clipWheels = {}
local clipDirty = true
local clipOriginal = setmetatable({}, { __mode = "k" })
local clipSetState = setmetatable({}, { __mode = "k" })
B.clipModel = nil
local clipFalling = false
local reverseHold = false
local lastAim = nil
local learnedRoots = setmetatable({}, { __mode = "k" })
local modelAddedConn = nil
local vehicleCount = 0
local cachedModels, cachedModelsAt = nil, 0
local lastGrounded = false
local reconnectTarget = nil
local forceRescan = false
local seatMaxSpeedSaved = setmetatable({}, { __mode = "k" })

-- UI 按钮 local（定义早、赋值晚：帮助函数可先引用）
local collapsed = false

-- 前向声明：这些函数在后面才定义，但锁定/座位/面板逻辑会调用

-- ===== 3. 工具 / 输入 =====

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function flatUnit(v, fallback)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude > 1e-3 then
		return f.Unit
	end
	return fallback or Vector3.zero
end

local function safeFullName(inst)
	if not inst then
		return "nil"
	end
	local ok, r = pcall(function() return inst:GetFullName() end)
	return ok and r or tostring(inst)
end

local function isTyping()
	return UIS:GetFocusedTextBox() ~= nil
end

local function keyDown(code)
	return UIS.KeyboardEnabled and not isTyping() and UIS:IsKeyDown(code)
end

local function forwardStates()
	return (keyDown(Enum.KeyCode.W) or keyDown(Enum.KeyCode.Up)) == true,
		(keyDown(Enum.KeyCode.S) or keyDown(Enum.KeyCode.Down)) == true
end

local function verticalStates()
	return (keyDown(Enum.KeyCode.Space) or keyDown(Enum.KeyCode.E)) == true,
		(keyDown(Enum.KeyCode.LeftShift) or keyDown(Enum.KeyCode.Q)) == true
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1
end

B.toastGui = nil
local function toast(text, color)
	if not B.toastGui or not B.toastGui.Parent then
		B.toastGui = mk("ScreenGui", {
			Name = NAME .. "_Toast", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 100000,
		}, GuiRoot)
	end
	local label = mk("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(240, 28), BackgroundColor3 = BG, BackgroundTransparency = 0.15,
		BorderSizePixel = 0, Text = tostring(text), TextColor3 = color or Color3.fromRGB(240, 244, 255),
		TextSize = 13, Font = FONT, TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, B.toastGui)
	task.delay(2.2, function()
		pcall(function() label:Destroy() end)
	end)
end

-- ===== 4. 扫描：轮毂 / 车辆判定 / 根部件 / 所有权 =====

local SCAN_ROOT_NAMES = { "Vehicles", "Cars", "Spawned", "PlayerVehicles", "Driveable",
	"CarSpawns", "Bricks", "Blocks", "Drift" }
local WHEEL_CORNERS = { "fl", "fr", "rl", "rr", "lf", "lr", "rf" }

local function nameLooksLikeWheel(name)
	local n = tostring(name):lower()
	if n == "" then
		return false
	end
	if n:find("suspension", 1, true) or n:find("axle", 1, true)
		or n:find("spring", 1, true) or n:find("shock", 1, true) then
		return false
	end
	if n:find("wheel", 1, true) or n:find("tire", 1, true) or n:find("tyre", 1, true) then
		return true
	end
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
	if not part or not part:IsA("BasePart") then
		return false
	end
	if nameLooksLikeWheel(part.Name) then
		return true
	end
	local cur = part.Parent
	for _ = 1, 3 do
		if not cur then
			break
		end
		if (cur:IsA("Model") or cur:IsA("Folder")) and nameLooksLikeWheel(cur.Name) then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function isMapModel(model)
	if not model then
		return false
	end
	local cur = model
	while cur and cur ~= workspace do
		if cur.Name:lower() == "map" then
			return true
		end
		cur = cur.Parent
	end
	return false
end

-- 车辆判定（2s TTL；运行中加装座位/轮子后按时失效，DescendantAdded 主动失效）
local vehicleLikeCache = setmetatable({}, { __mode = "k" })

local function invalidateVehicleLike(model)
	if model then
		vehicleLikeCache[model] = nil
	end
end

local function modelIsVehicleLike(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return false
	end
	local now = os.clock()
	local cached = vehicleLikeCache[model]
	if cached ~= nil then
		if now - cached.at < CFG.VehicleLikeTTL then
			return cached.result
		end
	end
	local result = false
	pcall(function()
		if isMapModel(model) then
			result = false
			return
		end
		if model:FindFirstChildOfClass("Humanoid") then
			result = false
			return
		end
		local hasSeat, wheelCount, partCount, anchoredCount, nonAnchoredMass, n = false, 0, 0, 0, 0, 0
		for _, d in ipairs(model:GetDescendants()) do
			n += 1
			if n > 300 then
				break
			end
			if d:IsA("Seat") or d:IsA("VehicleSeat") then
				hasSeat = true
			end
			if d:IsA("BasePart") then
				partCount += 1
				if d.Anchored then
					anchoredCount += 1
				else
					local okM, m = pcall(function() return d.Mass end)
					if okM and type(m) == "number" then
						nonAnchoredMass += m
					end
				end
				if isWheel(d) then
					wheelCount += 1
				end
			end
			if hasSeat and wheelCount >= 2 then
				break
			end
		end
		if partCount > 0 and anchoredCount == partCount then
			result = false
			return
		end
		local score = 0
		if hasSeat then
			score += 60
		end
		if wheelCount >= 2 then
			score += 20
		end
		if wheelCount >= 4 then
			score += 10
		end
		if nonAnchoredMass > 1 then
			score += 10
		end
		if partCount > 2 then
			score += 10
		end
		result = score >= CFG.VehicleMinScore
	end)
	vehicleLikeCache[model] = { result = result, at = now }
	return result
end

local function modelExcluded(model)
	if not model or not model.Parent then
		return true
	end
	if not model:IsA("Model") then
		return true
	end
	if model:FindFirstChildOfClass("Humanoid") then
		return true
	end
	if not modelIsVehicleLike(model) then
		return true
	end
	if isMapModel(model) then
		return true
	end
	return false
end

-- 根部件评分（固定降序前缀表，保证同名多关键词时打分确定）
local ROOT_WEIGHTS = { Primary = 95, Root = 90, Chassis = 85, Base = 80, Main = 75, Body = 60, Core = 55, Hull = 50 }
local ROOT_PREFIX_ORDER = { "Primary", "Root", "Chassis", "Base", "Main", "Body", "Core", "Hull" }
local NON_ROOT_PARTS = { "hitbox", "hitboxes", "detector", "sensor", "trigger", "zone", "sound", "billboard", "particle" }

local function evaluatePartScore(model, part)
	if not part or not part:IsA("BasePart") or part.Anchored or isWheel(part) then
		return -1
	end
	if model and part == model.PrimaryPart then
		return 100
	end
	local lowerName = part.Name:lower()
	for _, p in ipairs(NON_ROOT_PARTS) do
		if lowerName:find(p, 1, true) then
			return -1
		end
	end
	if ROOT_WEIGHTS[part.Name] then
		return ROOT_WEIGHTS[part.Name]
	end
	for _, prefix in ipairs(ROOT_PREFIX_ORDER) do
		if lowerName:find(prefix:lower(), 1, true) then
			return ROOT_WEIGHTS[prefix] - 5
		end
	end
	if part:IsA("VehicleSeat") or part:IsA("Seat") then
		return 45
	end
	local okM, m = pcall(function() return part.Mass end)
	local mass = (okM and type(m) == "number") and m or 0
	return math.min(10 + mass * 0.1, 40)
end

local function isScanRoot(inst)
	if not inst then
		return false
	end
	if inst == workspace then
		return true
	end
	if learnedRoots[inst] then
		return true
	end
	for _, n in ipairs(SCAN_ROOT_NAMES) do
		if inst.Name == n then
			return true
		end
	end
	return false
end

local function vehicleContainerFrom(inst)
	local cur = inst
	while cur and cur.Parent do
		if isScanRoot(cur.Parent) then
			return cur
		end
		local p = cur.Parent
		if not (p:IsA("Model") or p:IsA("Folder")) then
			return cur
		end
		cur = p
	end
	return cur
end

local function vehicleLabelFrom(inst)
	local c = vehicleContainerFrom(inst)
	return tostring(c and c.Name or "?")
end

local function sameAssembly(a, b)
	if not a or not b then
		return false
	end
	if a == b then
		return true
	end
	local okA, ra = pcall(function() return a.AssemblyRootPart end)
	local okB, rb = pcall(function() return b.AssemblyRootPart end)
	return okA and okB and ra == rb
end

local function resolveAssemblyAnchor(part)
	if not part or not part.Parent then
		return part
	end
	local okA, asm = pcall(function() return part.AssemblyRootPart end)
	if not okA or not asm or not asm.Parent or asm.Anchored then
		return part
	end
	if not isWheel(asm) then
		return asm
	end
	local best, bestScore = nil, -1
	local okC, parts = pcall(function() return asm:GetConnectedParts(true) end)
	if okC and type(parts) == "table" then
		local n = 0
		for _, p in ipairs(parts) do
			n += 1
			if n > 200 then
				break
			end
			if p:IsA("BasePart") then
				local s = evaluatePartScore(nil, p)
				if s > bestScore then
					best, bestScore = p, s
				end
			end
		end
	end
	return best or asm
end

-- 根部件缓存（1.5s TTL 一律返回，不按分数决定是否信任）
local rootPartCache = setmetatable({}, { __mode = "k" })

local function getRootPart(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return nil, 0
	end
	local now = os.clock()
	local cached = rootPartCache[model]
	if cached and cached.part and cached.part.Parent
		and cached.part:IsDescendantOf(model) and not cached.part.Anchored then
		if now - cached.at < CFG.RootPartTTL then
			return cached.part, cached.score
		end
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
			if n > 250 then
				break
			end
			local score = evaluatePartScore(model, d)
			if score > bestScore then
				bestPart, bestScore = d, score
				if score >= 95 then
					break
				end
			end
		end
	end)
	if bestPart then
		rootPartCache[model] = { part = bestPart, score = bestScore, at = now }
	end
	return bestPart, bestScore
end

-- 所有权（属性 / ObjectValue / StringValue，5s TTL）
local ownerCache = setmetatable({}, { __mode = "k" })
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
					if typeof(v) == "number" and v == myId then
						owned = true
					elseif typeof(v) == "string" and (v == myName or v == myDisp) then
						owned = true
					end
					if owned then
						return
					end
				end
			end
		end
	end)
	if not owned then
		pcall(function()
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do
				n += 1
				if n > 150 or owned then
					break
				end
				local dn = d.Name:lower()
				local isOwnerObj = d:IsA("ObjectValue")
					or ((d:IsA("StringValue") or d:IsA("IntValue") or d:IsA("NumberValue"))
					and (dn:find("owner") or dn:find("creator") or dn:find("player") or dn:find("user")))
				if isOwnerObj then
					local okV, v = pcall(function() return d.Value end)
					if okV then
						if v == player then
							owned = true
						elseif typeof(v) == "number" and v == myId then
							owned = true
						elseif typeof(v) == "string" and (v == myName or v == myDisp) then
							owned = true
						end
					end
				end
			end
		end)
	end
	return owned
end

local function playerOwnsModel(model)
	if not model or not model.Parent then
		return false
	end
	local now = os.clock()
	local rec = ownerCache[model]
	if rec and now - rec.at < OWNER_CACHE_TTL then
		return rec.owned
	end
	local owned = computeOwned(model)
	ownerCache[model] = { owned = owned, at = now }
	return owned
end

-- 车辆记忆（换车/重连用）
local function rememberMyVehicle(model, anchor)
	if not model or not model.Parent then
		return
	end
	B.myVehicleModel = model
	B.myVehicleAsm = nil
	B.myVehicleName = vehicleLabelFrom(anchor or model)
	if anchor and anchor.Parent then
		local okA, asm = pcall(function() return anchor.AssemblyRootPart end)
		if okA and asm and asm.Parent then
			B.myVehicleAsm = asm
		end
	end
end

local function isMyVehicle(model)
	if not model or not model.Parent then
		return false
	end
	local rp = getRootPart(model)
	if not rp then
		return false
	end
	if B.myVehicleAsm then
		local okA, asm = pcall(function() return rp.AssemblyRootPart end)
		if okA and asm == B.myVehicleAsm then
			return true
		end
	end
	if B.myVehicleName and vehicleLabelFrom(rp) == B.myVehicleName then
		return true
	end
	return model == B.myVehicleModel
end

local function getControlledVehicleModel()
	if B.seat and B.seat.Parent then
		local m = B.seat:FindFirstAncestorWhichIsA("Model")
		if m then
			return m
		end
	end
	if lockPart and lockPart.Parent then
		return vehicleContainerFrom(lockPart)
	end
	return lockModel
end

local function learnContainerFromModel(model)
	if not model then
		return
	end
	local cur = model
	while cur and cur.Parent and cur.Parent ~= workspace do
		cur = cur.Parent
	end
	if cur and cur ~= workspace and cur.Parent == workspace then
		if cur:IsA("Folder") or cur:IsA("Model") then
			learnedRoots[cur] = true
		end
	end
end

local function getScanRoots()
	local roots, seen = {}, {}
	local function add(folder)
		if folder and folder.Parent and not seen[folder] then
			seen[folder] = true
			roots[#roots + 1] = folder
		end
	end
	for f in pairs(learnedRoots) do
		if f and f.Parent then
			add(f)
		else
			learnedRoots[f] = nil
		end
	end
	for _, name in ipairs(SCAN_ROOT_NAMES) do
		local f = workspace:FindFirstChild(name)
		if f then
			add(f)
		end
	end
	if #roots == 0 then
		for _, child in ipairs(workspace:GetChildren()) do
			if child:IsA("Folder") and child.Name:lower() ~= "map" then
				add(child)
				if #roots >= 5 then
					break
				end
			end
		end
	end
	if #roots == 0 then
		roots[1] = workspace
	end
	return roots
end

local function collectModels(rootFolder, cap)
	if not rootFolder then
		return {}
	end
	local list, count = {}, 0
	local function visit(container, depth)
		if count >= cap or depth > 5 then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if count >= cap then
				return
			end
			if child:IsA("Model") then
				if modelIsVehicleLike(child) and child:FindFirstChildOfClass("Humanoid") == nil then
					local rp = getRootPart(child)
					if rp then
						count += 1
						list[count] = child
					end
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
						g = { rep = m, repParts = #m:GetDescendants() }
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
			if okC and type(parts) == "table" then
				count = #parts + 1
			end
		end
		if count >= CFG.MinVehicleParts then
			all[#all + 1] = g.rep
		end
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
		if cur:IsA("Model") and modelIsVehicleLike(cur) then
			vehicleLike = cur
		end
		if not (p:IsA("Model") or p:IsA("Folder")) then
			break
		end
		cur = p
	end
	if cur and cur:IsA("Model") and modelIsVehicleLike(cur) then
		vehicleLike = cur
	end
	return vehicleLike
end

local function getCameraAimModel(models, allowMoving)
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	local char = player.Character
	camRayParams.FilterDescendantsInstances = char and { char } or {}
	local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 600, camRayParams)
	if hit then
		local rootM = getVehicleRootFromInstance(hit.Instance)
		if rootM and rootM ~= char and modelIsVehicleLike(rootM) then
			local rpM = getRootPart(rootM)
			for _, m in ipairs(models) do
				if m == rootM then
					return m
				end
				local rp = getRootPart(m)
				if rp and rpM and sameAssembly(rp, rpM) then
					return m
				end
			end
		end
	end
	local list = models
	if not list then
		return nil
	end
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
						local spd = flat(v).Magnitude
						if allowMoving or spd <= CFG.MovingCarSpeed or isMyVehicle(model) or playerOwnsModel(model) then
							local ownedBonus = playerOwnsModel(model) and 2000 or 0
							local score = (dx * dx + dy * dy) * 20000 + (pp.Position - camPos).Magnitude - ownedBonus
							if score < bestScore then
								best, bestScore = model, score
							end
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
	if onScreen then
		score = score - 400
	end
	if model and model.PrimaryPart then
		score = score - 600
	end
	if camTarget and model == camTarget then
		score = score - 10000
	end
	if playerOwnsModel(model) then
		score = score - 50000
	end
	if isMyVehicle(model) then
		score = score - 20000
	end
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
	if ok and cf and test(cf.Position) then
		return true
	end
	if part then
		return test(part.Position)
	end
	return false
end

-- 控制座位（VehicleSeat 优先）
local controlSeatCache = setmetatable({}, { __mode = "k" })

local function getControlSeat(model)
	if not model then
		return nil
	end
	local cached = controlSeatCache[model]
	if cached and cached.Parent and cached:IsDescendantOf(model) then
		return cached
	end
	local vs, ss = nil, nil
	pcall(function()
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("VehicleSeat") then
				vs = d
				break
			elseif d:IsA("Seat") and not ss then
				ss = d
			end
		end
	end)
	local found = vs or ss
	controlSeatCache[model] = found
	return found
end

-- 载具水平朝向：座位 → 控制座位 → 锁定根
local function getVehicleFacing(root)
	if B.seat and B.seat.Parent then
		local l = B.seat.CFrame.LookVector
		local f = flat(l)
		if f.Magnitude > 0.001 then
			return f.Unit
		end
	end
	local model = getControlledVehicleModel()
	local vs = getControlSeat(model)
	if vs then
		local l = vs.CFrame.LookVector
		local f = flat(l)
		if f.Magnitude > 0.001 then
			return f.Unit
		end
	end
	if root and root.Parent then
		local l = root.CFrame.LookVector
		local f = flat(l)
		if f.Magnitude > 0.001 then
			return f.Unit
		end
	end
	return Vector3.zero
end

-- ===== 5. 锁定 / 换车 / 自动锁定 =====

local function setNoCharLabel(extra)
	if not B.switchButton then
		return
	end
	if locked and lockModel then
		local name = tostring(B.myVehicleName or lockModel.Name)
		local tag = " "
		if playerOwnsModel(lockModel) then
			tag = "·主"
		elseif isMyVehicle(lockModel) then
			tag = "·我"
		end
		local maxLen = tag ~= " " and 5 or 8
		if #name > maxLen then
			name = name:sub(1, maxLen - 1) .. "…"
		end
		B.switchButton.Text = "换车 " .. name .. tag
	else
		B.switchButton.Text = extra or "换车"
	end
end

local function resetLockState()
	if modelAddedConn then
		pcall(function() modelAddedConn:Disconnect() end)
		modelAddedConn = nil
	end
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
	if not model or not model.Parent or not modelIsVehicleLike(model) then
		return false
	end
	local rootP, score = getRootPart(model)
	if not rootP then
		return false
	end
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
	B.rearmLights()
	B.collectEngineSounds()
	setNoCharLabel()
	toast("锁定 " .. tostring(B.myVehicleName or model.Name), COL.Good)
	if modelAddedConn then
		pcall(function() modelAddedConn:Disconnect() end)
		modelAddedConn = nil
	end
	if lockPartScore < 85 then
		modelAddedConn = model.DescendantAdded:Connect(function(desc)
			if not locked or lockModel ~= model then
				return
			end
			if desc:IsA("BasePart") then
				invalidateVehicleLike(model)
				rootPartCache[model] = nil
				local newScore = evaluatePartScore(model, desc)
				if newScore > lockPartScore then
					lockPart = resolveAssemblyAnchor(desc)
					lockPartScore = newScore
					B.clearDrive()
					B.ensureDrive(lockPart)
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
		if applyLock(aim) then
			return
		end
	end
	local cam = workspace.CurrentCamera
	if not cam or #models == 0 then
		setNoCharLabel("无车")
		toast("无车", COL.Wait)
		return
	end
	local camPos = cam.CFrame.Position
	local entries = {}
	for _, m in ipairs(models) do
		local rp = getRootPart(m)
		if rp and modelIsVehicleLike(m) and not modelExcluded(m) then
			local dist = (rp.Position - camPos).Magnitude
			if dist <= CFG.MaxSwitchDist then
				entries[#entries + 1] = { model = m, dist = dist }
			end
		end
	end
	if #entries == 0 then
		setNoCharLabel("无可用")
		toast("无可用车辆", COL.Wait)
		return
	end
	table.sort(entries, function(a, b) return a.dist < b.dist end)
	local idx = 0
	for i, e in ipairs(entries) do
		if e.model == lockModel then
			idx = i
		end
	end
	idx = (idx % #entries) + 1
	manualLockUntil = now + CFG.ManualLockDuration
	if applyLock(entries[idx].model) then
		return
	end
	if not locked and #models > 0 then
		local best, bestD = nil, math.huge
		for _, m in ipairs(models) do
			local rp = getRootPart(m)
			if rp then
				local d = (rp.Position - camPos).Magnitude
				if d < bestD then
					best, bestD = m, d
				end
			end
		end
		if best then
			applyLock(best)
		end
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
	if not list then
		return nil
	end
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or nil
	local best, bestD = nil, math.huge
	for _, m in ipairs(list) do
		if modelIsVehicleLike(m) and playerOwnsModel(m) and not modelExcluded(m) then
			local rp = getRootPart(m)
			if rp then
				local d = camPos and (rp.Position - camPos).Magnitude or 0
				if d < bestD then
					best, bestD = m, d
				end
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
			if now < manualLockUntil then
				return
			end
			if not playerOwnsModel(lockModel) and now - lastOwnedCheck >= CFG.OwnedTakeoverInterval then
				lastOwnedCheck = now
				local mine = findOwnedModel()
				if mine and mine ~= lockModel then
					applyLock(mine)
					return
				end
			end
			return
		end
		B.clearDrive()
		locked = false
		reconnectTarget = lockModel
		resetLockState()
		B.collectEngineSounds()
		setNoCharLabel("重连新车…")
		toast("锁定丢失", COL.Bad)
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
	if now - lastAutoScan < CFG.NoCharScan and not forceRescan then
		return
	end
	lastAutoScan = now
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	refreshModelCache(now)
	local models = cachedModels
	if not models or #models == 0 then
		return
	end
	-- 优先找回我的车（装配体 → 容器名）
	if B.myVehicleAsm then
		for _, m in ipairs(models) do
			if modelIsVehicleLike(m) and not modelExcluded(m) then
				local rp = getRootPart(m)
				if rp then
					local okA, asm = pcall(function() return rp.AssemblyRootPart end)
					if okA and asm == B.myVehicleAsm then
						if applyLock(m) then
							return
						end
					end
				end
			end
		end
	end
	if B.myVehicleName then
		for _, m in ipairs(models) do
			if modelIsVehicleLike(m) and not modelExcluded(m) then
				local rp = getRootPart(m)
				if rp and vehicleLabelFrom(rp) == B.myVehicleName then
					if applyLock(m) then
						return
					end
				end
			end
		end
	end
	-- 打分锁定
	local aimTarget = getCameraAimModel(models)
	lastAim = aimTarget
	local camPos = cam.CFrame.Position
	local look = cam.CFrame.LookVector
	local charRoot = player.Character and (player.Character:FindFirstChild("HumanoidRootPart")
		or player.Character:FindFirstChild("Root")) or nil
	local charPos = charRoot and charRoot.Position or nil
	local best, bestScore = nil, math.huge
	for _, model in ipairs(models) do
		if modelIsVehicleLike(model) then
			local rp = getRootPart(model)
			if rp then
				local delta = rp.Position - camPos
				local partD = delta.Magnitude
				local vv = rp.AssemblyLinearVelocity
				local sp = flat(vv).Magnitude
				if not modelExcluded(model) and (sp <= CFG.MovingCarSpeed or isMyVehicle(model) or playerOwnsModel(model)) then
					local cos = partD > 1e-3 and delta:Dot(look) / partD or 1
					local onScreen = getModelScreenInfo(model, rp, cam)
					if onScreen or playerOwnsModel(model) then
						local score = candidateScore(model, rp, partD, cos, onScreen, charPos, aimTarget, sp)
						if score < bestScore then
							best, bestScore = model, score
						end
					end
				end
			end
		end
	end
	if best then
		applyLock(best)
	end
end

reg(workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("Model") then
		forceRescan = true
	end
end))

-- ===== 6. 驱动力 / 穿墙 / 悬浮 / 翻转 / 飞车 =====

B.clearDrive = function()
	if B.driveForce then
		pcall(function() B.driveForce:Destroy() end)
		B.driveForce = nil
	end
	if B.driveAtt then
		pcall(function() B.driveAtt:Destroy() end)
		B.driveAtt = nil
	end
end

B.ensureDrive = function(part)
	if not part or not part.Parent then
		B.clearDrive()
		return nil
	end
	if part.Anchored then
		local ok, parts = pcall(function() return part:GetConnectedParts(true) end)
		if ok then
			for _, p in ipairs(parts) do
				if p:IsA("BasePart") and not p.Anchored then
					part = p
					break
				end
			end
		end
		if part.Anchored then
			B.clearDrive()
			return nil
		end
	end
	local okR, asmRoot = pcall(function() return part.AssemblyRootPart end)
	if okR and asmRoot and asmRoot ~= part and asmRoot.Parent and not asmRoot.Anchored then
		part = asmRoot
	end
	if B.driveForce and B.driveForce.Parent == part then
		return B.driveForce
	end
	B.clearDrive()
	B.driveAtt = mk("Attachment", { Name = "SIBS_DriveAtt" }, part)
	B.driveForce = mk("VectorForce", {
		Name = "SIBS_DriveForce", Attachment0 = B.driveAtt,
		Force = Vector3.zero, RelativeTo = Enum.ActuatorRelativeTo.World,
		ApplyAtCenterOfMass = true,
	}, part)
	return B.driveForce
end

B.setDriveForce = function(v)
	if B.driveForce then
		pcall(function() B.driveForce.Force = v end)
	end
end

-- 穿墙：记录原碰撞属性，批量开关（轮毂单独一组便于翻滚检测时恢复）
local function rememberOriginal(part)
	if not part or not part.Parent then
		return
	end
	if clipOriginal[part] == nil then
		local ok, value = pcall(function() return part.CanCollide end)
		if ok then
			clipOriginal[part] = value
		end
	end
end

local function setPartCollision(part, value)
	if not part or not part.Parent then
		return
	end
	if clipSetState[part] == value then
		return
	end
	rememberOriginal(part)
	local ok, current = pcall(function() return part.CanCollide end)
	if ok and current ~= value then
		pcall(function() part.CanCollide = value end)
	end
	clipSetState[part] = value
end

local function rebuildClipParts()
	for _, part in ipairs(B.clipParts) do
		if part and part.Parent then
			local original = clipOriginal[part]
			pcall(function() part.CanCollide = original ~= false end)
		end
		clipSetState[part] = nil
	end
	for _, w in ipairs(B.clipWheels) do
		if w and w.Parent then
			local original = clipOriginal[w]
			pcall(function() w.CanCollide = original ~= false end)
		end
		clipSetState[w] = nil
	end
	table.clear(B.clipParts)
	table.clear(B.clipWheels)
	local model = getControlledVehicleModel()
	if not model then
		B.clipModel = nil
		clipDirty = false
		return
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			rememberOriginal(descendant)
			if isWheel(descendant) then
				B.clipWheels[#B.clipWheels + 1] = descendant
			else
				B.clipParts[#B.clipParts + 1] = descendant
			end
		end
	end
	B.clipModel = model
	clipDirty = false
end

local function applyClipCollision()
	if clipDirty then
		rebuildClipParts()
	end
	for _, part in ipairs(B.clipParts) do
		setPartCollision(part, clipFalling and (clipOriginal[part] ~= false) or false)
	end
	for _, wheel in ipairs(B.clipWheels) do
		setPartCollision(wheel, clipFalling and (clipOriginal[wheel] ~= false) or false)
	end
end

local function restoreClip()
	for _, part in ipairs(B.clipParts) do
		if part and part.Parent then
			local original = clipOriginal[part]
			pcall(function() part.CanCollide = original ~= false end)
		end
	end
	for _, w in ipairs(B.clipWheels) do
		if w and w.Parent then
			local original = clipOriginal[w]
			pcall(function() w.CanCollide = original ~= false end)
		end
	end
	table.clear(B.clipParts)
	table.clear(B.clipWheels)
	table.clear(clipOriginal)
	table.clear(clipSetState)
	B.clipModel = nil
	clipFalling = false
end

-- 穿墙更新：节流重建 + 自由落体探测；悬浮支持仅在穿墙开启时生效
local groundRayParams = RaycastParams.new()
groundRayParams.FilterType = Enum.RaycastFilterType.Exclude
local groundFilterTable = {}

local function setGroundFilter(inst)
	if groundFilterTable[1] ~= inst or (inst == nil and #groundFilterTable > 0) then
		table.clear(groundFilterTable)
		if inst then
			groundFilterTable[1] = inst
		end
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
	if not part or not part.Parent then
		return
	end
	local model = getControlledVehicleModel()
	setGroundFilter(model or part)
	local half = part.Size.Y * 0.5
	local far = half + CFG.GroundClearance + CFG.GroundProbeExtra
	local ok, hit = pcall(workspace.Raycast, workspace, part.Position, Vector3.new(0, -far, 0), groundRayParams)
	if not ok or not hit then
		return
	end
	local vel = part.AssemblyLinearVelocity
	local near = half + 0.75
	if hit.Distance <= near then
		local push = math.clamp((near - hit.Distance) * CFG.HoverPushGain, 0, CFG.HoverPushMax)
		if push > 0 then
			pcall(function() part.AssemblyLinearVelocity = Vector3.new(vel.X, push, vel.Z) end)
		end
	elseif hit.Distance <= near + CFG.HoverBand then
		if vel.Y < 0 then
			pcall(function() part.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z) end)
		end
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
			if B.clipModel then
				restoreClip()
				clipDirty = true
			end
			return
		end
		if B.clipModel ~= ownModel then
			restoreClip()
			clipDirty = true
			clipNextRebuild = 0
		end
		if part:IsDescendantOf(workspace) then
			local vel = part.AssemblyLinearVelocity
			if vel.Y < CFG.ClipFallSpeed then
				-- 快速下坠：探测下方地面，进入"翻滚免碰撞"状态
				setGroundFilter(ownModel)
				local okF, hitF = pcall(workspace.Raycast, workspace, part.Position,
					Vector3.new(0, -CFG.ClipFallProbeDist, 0), groundRayParams)
				if okF and hitF then
					clipFalling = true
				end
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
		if not clipFalling and not carFly then
			hoverSupport(part)
		end
	else
		if B.clipModel then
			restoreClip()
			clipDirty = true
		end
	end
end

-- 翻转：旋转整个装配体（只转根部件会把车撕开）
local function flipVehicle()
	local part = B.seat or lockPart
	if not part or not part.Parent then
		toast("无锁定车辆", COL.Wait)
		return
	end
	local anchor = resolveAssemblyAnchor(part)
	local pos = anchor.Position
	local ok, parts = pcall(function() return anchor:GetConnectedParts(true) end)
	local list = (ok and type(parts) == "table") and parts or { anchor }
	local rot = CFrame.fromAxisAngle(anchor.CFrame.LookVector, math.pi)
	for _, p in ipairs(list) do
		if p:IsA("BasePart") and p.Parent and not p.Anchored then
			pcall(function()
				p.CFrame = (rot * (p.CFrame - pos)) + pos
			end)
		end
	end
	toast("已翻转", COL.Good)
end

-- 飞车（LinearVelocity 接管；前向用锁定朝向，垂直由加速度积分）
local function stopCarFly()
	if B.carFlyForce then
		pcall(function() B.carFlyForce:Destroy() end)
		B.carFlyForce = nil
	end
	if B.carFlyAtt then
		pcall(function() B.carFlyAtt:Destroy() end)
		B.carFlyAtt = nil
	end
	flyVertVel = 0
end

local function updateCarFly(part, dt, seatThrottle)
	if not part or not part.Parent then
		stopCarFly()
		return
	end
	if not B.carFlyForce or B.carFlyForce.Parent ~= part then
		stopCarFly()
		B.carFlyAtt = mk("Attachment", { Name = "SIBS_FlyAtt" }, part)
		B.carFlyForce = mk("LinearVelocity", {
			Name = "SIBS_FlyVelocity", Attachment0 = B.carFlyAtt,
			VectorVelocity = Vector3.zero, MaxForce = math.huge,
			RelativeTo = Enum.ActuatorRelativeTo.World,
		}, part)
		if not B.carFlyForce then
			return
		end
	end
	local kbUp, kbDown = verticalStates()
	local vertInput = 0
	if flyUp or kbUp then
		vertInput += 1
	end
	if flyDown or kbDown then
		vertInput -= 1
	end
	flyVertVel += vertInput * CFG.FlyVertAccel * dt
	if vertInput == 0 and math.abs(flyVertVel) < 1 then
		flyVertVel = 0
	end
	local look = getVehicleFacing(part)
	if look.Magnitude < 0.001 then
		look = Vector3.new(0, 0, 1)
	end
	local kbW, kbS = forwardStates()
	local fwdInput = 0
	if accelerating or kbW or seatThrottle > 0.1 then
		fwdInput += 1
	end
	if decelerating or kbS or seatThrottle < -0.1 then
		fwdInput -= 1
	end
	local currentVel = part.AssemblyLinearVelocity
	local currentHVel = flat(currentVel)
	local cruiseSpeed = math.max(currentHVel.Magnitude, CFG.FlySpeed)
	local targetHVel = (fwdInput ~= 0) and (look * (cruiseSpeed * fwdInput)) or currentHVel
	pcall(function()
		B.carFlyForce.VectorVelocity = Vector3.new(targetHVel.X, flyVertVel, targetHVel.Z)
	end)
end

-- 每帧缓存朝向（主循环内会取两次，避免重复向上遍历父级）
local facingCache = { at = -1, part = nil, value = Vector3.zero }

local function getVehicleFacingCached(part, now)
	if facingCache.part == part and now - facingCache.at < 1 / 30 then
		return facingCache.value
	end
	local v = getVehicleFacing(part)
	facingCache.part, facingCache.at, facingCache.value = part, now, v
	return v
end

-- 主物理循环：锁定维护 → 穿墙 → 油门/刹车/定速 → 转向+抓地
local dtState = { last = os.clock() }
local function simDt(step)
	local now = os.clock()
	local dt = step
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 then
		dt = now - dtState.last
	end
	dtState.last = now
	return math.clamp(dt, 0, 0.1)
end

local function refreshStopButton()
	if not B.stopButton then
		return
	end
	B.stopButton.Text = stopped and "急刹 开" or "急刹 关"
	B.stopButton.BackgroundColor3 = stopped and COL.On or COL.Stop
end

reg(RunService.PreSimulation:Connect(function(step)
	local deltaTime = simDt(step)
	local now = os.clock()
	if not B.seat then
		updateLockBinding(now)
	end
	local part = B.seat or lockPart
	updateWallClip(part)
	if not part or not part:IsDescendantOf(workspace) then
		return
	end
	local velocity = part.AssemblyLinearVelocity
	if velocity.X ~= velocity.X or velocity.Y ~= velocity.Y or velocity.Z ~= velocity.Z then
		pcall(function() part.AssemblyLinearVelocity = Vector3.zero end)
		velocity = Vector3.zero
	end
	local seatThrottle, seatSteer = 0, 0
	if B.seat and B.seat:IsA("VehicleSeat") and B.seat.Parent then
		local okT, t = pcall(function() return B.seat.Throttle end)
		if okT then
			seatThrottle = t
		end
		local okS, s = pcall(function() return B.seat.Steer end)
		if okS then
			seatSteer = s
		end
	end
	local flatLook = getVehicleFacingCached(part, now)
	local brakeRate = acceleration * CFG.BrakeDecelMult
	if carFly then
		updateCarFly(part, deltaTime, seatThrottle)
		return
	end
	local kbW, kbS = forwardStates()
	local wantAccel = accelerating or kbW or seatThrottle > 0.1
	local wantDecel = decelerating or kbS or seatThrottle < -0.1
	local steerInput = steerValue
	if math.abs(seatSteer) > 0.05 then
		steerInput = steerInput + seatSteer * 0.5
	end
	steerInput = math.clamp(steerInput, -1, 1)
	if stopped then
		if wantAccel then
			stopped = false
			refreshStopButton()
		else
			targetSpeed = 0
			local frc = B.ensureDrive(part)
			if frc then
				local mass = math.max(part.AssemblyMass, 1)
				local hv = flat(velocity)
				local spd = hv.Magnitude
				if spd > CFG.BrakeDeadzone then
					local brakeMult = math.clamp(spd / 50, 0.1, 1)
					B.setDriveForce(-hv.Unit * (mass * brakeRate * brakeMult))
				else
					B.setDriveForce(Vector3.zero)
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
		local frc = B.ensureDrive(part)
		if frc then
			local mass = math.max(part.AssemblyMass, 1)
			local hv = flat(velocity)
			local speed = hv.Magnitude
			local accelForce = mass * acceleration
			local brakeForce = mass * brakeRate
			local moveDir = flatLook.Magnitude > 0.001 and flatLook or Vector3.new(0, 0, 1)
			local force = Vector3.zero
			if wantAccel and wantDecel then
				if speed > 1.5 then
					force = -hv.Unit * brakeForce
				end
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
			if not lastGrounded then
				force = force * 0.1
			end
			if force.Magnitude < CFG.ForceDeadzone then
				force = Vector3.zero
			end
			local maxForceLimit = mass * acceleration * 2.5
			if force.Magnitude > maxForceLimit then
				force = force.Unit * maxForceLimit
			end
			B.setDriveForce(force)
			if not cruise then
				targetSpeed = velocity:Dot(moveDir)
			end
		else
			B.clearDrive()
		end
	else
		B.clearDrive()
		reverseHold = false
		if not cruise then
			local hv = flat(velocity)
			targetSpeed = flatLook.Magnitude > 0.001 and hv:Dot(flatLook) or hv.Magnitude
		end
	end
	-- 抓地：把速度方向朝推进方向回正
	if turned and flatLook.Magnitude > 0.001 then
		local hv = flat(velocity)
		if hv.Magnitude > 0.5 then
			local gripTarget = flatLook
			if hv.Unit:Dot(flatLook) < 0 then
				gripTarget = -flatLook
			end
			local lerpFactor = math.clamp(deltaTime * CFG.TurnGrip, 0, 1)
			local newDir = hv.Unit:Lerp(gripTarget, lerpFactor)
			if newDir.Magnitude > 0.001 then
				pcall(function()
					part.AssemblyLinearVelocity = newDir.Unit * hv.Magnitude + Vector3.new(0, velocity.Y, 0)
				end)
			end
		end
	end
end))

-- 座位同步（含 MaxSpeed 保存/还原，避免离座后永久失去限速）
local function setSeat(newSeat)
	if B.seat == newSeat then
		return
	end
	B.clearDrive()
	local oldSeat = B.seat
	if oldSeat and oldSeat.Parent then
		local original = seatMaxSpeedSaved[oldSeat]
		if original then
			pcall(function() oldSeat.MaxSpeed = original end)
		end
	end
	if oldSeat then
		seatMaxSpeedSaved[oldSeat] = nil
	end
	B.seat = nil
	accelerating, decelerating = false, false
	steerValue = 0
	cruise, stopped = false, false
	targetSpeed = 0
	flyVertVel = 0
	clipDirty = true
	clipFalling = false
	if not newSeat or (not newSeat:IsA("VehicleSeat") and not newSeat:IsA("Seat")) then
		return
	end
	B.seat = newSeat
	learnContainerFromModel(newSeat:FindFirstAncestorWhichIsA("Model"))
	if seatMaxSpeedSaved[B.seat] == nil then
		local okM, orig = pcall(function() return B.seat.MaxSpeed end)
		if okM then
			seatMaxSpeedSaved[B.seat] = orig
		end
	end
	pcall(function() B.seat.MaxSpeed = math.huge end)
	B.rearmLights()
	B.collectEngineSounds()
end

local seatConns = {}
local function hookHumanoid(h)
	seatConns[#seatConns + 1] = h.Seated:Connect(function(_, seatPart)
		setSeat(seatPart)
	end)
	seatConns[#seatConns + 1] = h:GetPropertyChangedSignal("SeatPart"):Connect(function()
		setSeat(h.SeatPart)
	end)
	setSeat(h.SeatPart)
end

local function bindSeatCharacter(c)
	for _, x in ipairs(seatConns) do
		pcall(function() x:Disconnect() end)
	end
	table.clear(seatConns)
	local h = c:FindFirstChildOfClass("Humanoid")
	if h then
		hookHumanoid(h)
	else
		seatConns[#seatConns + 1] = c.ChildAdded:Connect(function(d)
			if d:IsA("Humanoid") then
				hookHumanoid(d)
			end
		end)
	end
end

reg(player.CharacterAdded:Connect(bindSeatCharacter))

-- ===== 7. 灯光 / 喇叭 / 引擎音调 =====

local ENGINE_KEYWORDS = { "engine", "motor", "idle" }
local engineSounds = {}

B.collectEngineSounds = function()
	for _, rec in ipairs(engineSounds) do
		if not rec.foreign then
			pcall(function() rec.sound.PlaybackSpeed = rec.base end)
		end
	end
	table.clear(engineSounds)
	local container = getControlledVehicleModel()
	if not container then
		return
	end
	local n = 0
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("Sound") then
			local ln = d.Name:lower()
			for _, kw in ipairs(ENGINE_KEYWORDS) do
				if ln:find(kw, 1, true) then
					n += 1
					if n <= 6 then
						engineSounds[#engineSounds + 1] =
							{ sound = d, base = d.PlaybackSpeed, lastSet = d.PlaybackSpeed, foreign = false }
					end
					break
				end
			end
		end
	end
end

local function updateEngineSounds()
	local part = B.seat or lockPart
	if not part or not part.Parent or #engineSounds == 0 then
		return
	end
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
	for _, rec in ipairs(B.nativeHead) do
		pcall(function() rec.light.Enabled = rec.saved end)
	end
	for _, rec in ipairs(B.nativeTail) do
		pcall(function() rec.light.Enabled = rec.saved end)
	end
	table.clear(B.nativeHead)
	table.clear(B.nativeTail)
	for _, l in ipairs(B.createdLamps) do
		pcall(function() l:Destroy() end)
	end
	table.clear(B.createdLamps)
	lightsOn = false
end

local function collectNativeLights()
	local model = getControlledVehicleModel()
	local part = B.seat or lockPart
	if not model or not part or not part.Parent then
		return
	end
	local fwd = getVehicleFacing(part)
	if fwd.Magnitude < 0.001 then
		fwd = flatUnit(part.CFrame.LookVector, Vector3.new(0, 0, -1))
	end
	if fwd.Magnitude < 0.001 then
		return
	end
	local anchorPos = part.Position
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		n += 1
		if n > 400 then
			break
		end
		if (d:IsA("SpotLight") or d:IsA("SurfaceLight") or d:IsA("PointLight"))
			and d.Parent and d.Parent:IsA("BasePart") then
			local rel = (d.Parent.Position - anchorPos):Dot(fwd)
			local rec = { light = d, saved = d.Enabled }
			if rel >= 0 then
				if #B.nativeHead < 12 then
					B.nativeHead[#B.nativeHead + 1] = rec
				end
			else
				if #B.nativeTail < 8 then
					B.nativeTail[#B.nativeTail + 1] = rec
				end
			end
		end
	end
end

local function armLights()
	if lightsOn then
		return true
	end
	local model = getControlledVehicleModel()
	local part = B.seat or lockPart
	if not model or not part or not part.Parent then
		return false
	end
	collectNativeLights()
	if #B.nativeHead > 0 or #B.nativeTail > 0 then
		lightsOn = true
		return true
	end
	local okPP, pp = pcall(function() return model.PrimaryPart end)
	local parentPart = (okPP and pp and pp.Parent and pp) or part
	if parentPart and parentPart.Parent then
		pcall(function()
			local front = mk("SpotLight", {
				Name = "SIBS_OvFront", Brightness = 14, Range = 160, Angle = 85,
				Face = Enum.NormalId.Front, Enabled = false,
			}, parentPart)
			B.createdLamps[#B.createdLamps + 1] = front
			local back = mk("SpotLight", {
				Name = "SIBS_OvBack", Brightness = 8, Range = 80, Angle = 75,
				Color = Color3.fromRGB(255, 40, 40), Face = Enum.NormalId.Back, Enabled = false,
			}, parentPart)
			B.createdLamps[#B.createdLamps + 1] = back
			local glow = mk("PointLight", {
				Name = "SIBS_OvGlow", Brightness = 4, Range = 60, Enabled = false,
			}, parentPart)
			B.createdLamps[#B.createdLamps + 1] = glow
		end)
		lightsOn = #B.createdLamps > 0
	end
	return lightsOn
end

B.rearmLights = function()
	restoreLamps()
	if lightSteady or (os.clock() < flashUntil) then
		armLights()
	end
end

local function applyLamps(on)
	for _, rec in ipairs(B.nativeHead) do
		pcall(function() rec.light.Enabled = on end)
	end
	for _, rec in ipairs(B.nativeTail) do
		pcall(function() rec.light.Enabled = on end)
	end
	for _, l in ipairs(B.createdLamps) do
		if l and l.Parent then
			pcall(function() l.Enabled = on end)
		end
	end
end

-- 喇叭：优先 keypress 注入；探测候选键（按住时是否有 horn 类 Sound 开始播放）
local savedHornKeyName = cfgGet("SIBSHornKey", nil)
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
local HORN_CANDIDATES = { "H", "G", "J", "K", "B", "N", "F" }

local function sendKey(key, down)
	if type(keypress) == "function" then
		if down then
			pcall(keypress, key)
		else
			pcall(keyrelease, key)
		end
	else
		pcall(function()
			local vim = game:GetService("VirtualInputManager")
			vim:SendKeyEvent(down, key, false, game)
		end)
	end
end

local function detectHornKey()
	if hornDetecting then
		return false
	end
	local container = getControlledVehicleModel()
	if not container or not (B.seat and B.seat.Parent) then
		toast("先坐进车里再点喇叭", COL.Wait)
		return false
	end
	hornDetecting = true
	toast("探测喇叭键中…", COL.Bind)
	task.spawn(function()
		local found = nil
		for _, name in ipairs(HORN_CANDIDATES) do
			local okK, key = pcall(function() return Enum.KeyCode[name] end)
			if not okK then
				continue
			end
			local before = {}
			for _, d in ipairs(container:GetDescendants()) do
				if d:IsA("Sound") then
					before[d] = d.Playing
				end
			end
			sendKey(key, true)
			task.wait(0.18)
			sendKey(key, false)
			task.wait(0.12)
			if not container.Parent then
				break
			end
			for _, d in ipairs(container:GetDescendants()) do
				if d:IsA("Sound") and before[d] ~= true and d.Playing == true then
					local ln = d.Name:lower()
					if ln:find("horn", 1, true) or ln:find("klaxon", 1, true) or ln:find("beep", 1, true) then
						found = key
						break
					end
				end
			end
			if found then
				break
			end
		end
		hornDetecting = false
		if found then
			hornKey = found
			hornKeyFound = true
			cfgSet("SIBSHornKey", found.Name)
			toast("喇叭键: " .. found.Name, COL.Good)
		else
			toast("未探测到，默认 " .. hornKey.Name, COL.Wait)
		end
	end)
	return true
end

local function setHornKey(down)
	if hornKeyIsDown == down then
		return
	end
	hornKeyIsDown = down
	sendKey(hornKey, down)
end

-- 心跳：灯光闪烁方波、喇叭按住/松开、引擎音调跟随
reg(RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local lightOn = false
	if now < flashUntil then
		lightOn = (math.floor(now / CFG.FlashHalfPeriod) % 2) == 0
	elseif lightSteady then
		lightOn = true
	end
	if lightsOn then
		applyLamps(lightOn)
	end
	local wantHorn = false
	if now < beepUntil then
		wantHorn = true
	elseif hornSteady then
		wantHorn = true
	end
	if not hornDetecting then
		if wantHorn and not hornKeyIsDown then
			setHornKey(true)
		elseif not wantHorn and hornKeyIsDown then
			setHornKey(false)
		end
	end
	updateEngineSounds()
end))

-- 初始座位同步（必须在灯光/引擎函数定义之后：setSeat 会调用它们）
if player.Character then
	bindSeatCharacter(player.Character)
end

-- ===== 8. 主面板 =====

B.panelSize = UDim2.new(0, PANEL_W, 0, 396)
B.panelPos = UDim2.new(0.5, -PANEL_W / 2, 0.4, -198)

B.gui = mk("ScreenGui", {
	Name = NAME, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99998,
}, GuiRoot)
B.main = mk("Frame", {
	Size = B.panelSize, Position = B.panelPos, BackgroundColor3 = BG,
	BackgroundTransparency = ALPHA, BorderSizePixel = 0, ClipsDescendants = true,
}, B.gui)

do
	local saved = cfgGet("UI.Pos." .. NAME, nil)
	local vp = workspace.CurrentCamera.ViewportSize
	if typeof(saved) == "string" then
		local sx, ox, sy, oy = saved:match("^([%-%d%.]+),([%-%d]+),([%-%d%.]+),([%-%d]+)$")
		if sx then
			local w, h = PANEL_W, B.panelSize.Y.Offset
			local absX = math.clamp(tonumber(ox) or 0, 0, math.max(vp.X - w, 0))
			local absY = math.clamp(tonumber(oy) or 0, SAFE_TOP, math.max(vp.Y - h, SAFE_TOP))
			B.main.Position = UDim2.new(tonumber(sx) or 0, absX, tonumber(sy) or 0, absY)
		end
	end
end

B.titleBar = mk("TextButton", {
	Size = UDim2.new(1, 0, 0, TITLE_H), BackgroundColor3 = BG, BackgroundTransparency = 1,
	BorderSizePixel = 0, Text = "车辆控制 [-]", TextColor3 = Color3.new(1, 1, 1),
	TextSize = 13, Font = FONT, TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
}, B.main)

do
	local dragging, moved, origin, base = false, false, Vector2.zero, UDim2.new()
	reg(B.titleBar.InputBegan:Connect(function(input)
		if not isPointer(input) then
			return
		end
		dragging, moved = true, false
		origin = input.Position
		base = B.main.Position
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
		local size = B.main.AbsoluteSize
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
		B.main.Position = UDim2.new(
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
				B.main.Position.X.Scale, B.main.Position.X.Offset,
				B.main.Position.Y.Scale, B.main.Position.Y.Offset))
		end
	end
	reg(UIS.InputEnded:Connect(function(input)
		if isPointer(input) then
			release()
		end
	end))
	reg(UIS.WindowFocusReleased:Connect(release))

	reg(B.titleBar.Activated:Connect(function()
		if moved then
			return
		end
		collapsed = not collapsed
		B.titleBar.Text = "车辆控制 " .. (collapsed and "[+]" or "[-]")
		B.main.Size = collapsed and UDim2.new(0, PANEL_W, 0, TITLE_H) or B.panelSize
		-- 展开时转向滑条立即松手回中（避免面板挡着还在转向）
		if not collapsed then
			B.steerRelease()
		end
	end))
end

B.scroll = mk("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -TITLE_H), Position = UDim2.new(0, 0, 0, TITLE_H),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 2, ScrollingDirection = Enum.ScrollingDirection.Y,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, B.main)

local function label(parent, props)
	local merged = {
		BackgroundTransparency = 1, BorderSizePixel = 0, Font = FONT,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}
	for k, v in pairs(props or {}) do
		merged[k] = v
	end
	return mk("TextLabel", merged, parent)
end

local function fullInput(parent, y, rowH, labelText, color, getVal, setVal)
	local row = mk("Frame", {
		Size = UDim2.new(1, 0, 0, rowH), Position = UDim2.new(0, 0, 0, y),
		BackgroundTransparency = 1,
	}, parent)
	label(row, {
		Size = UDim2.new(0.5, 0, 1, 0), BackgroundColor3 = color,
		BackgroundTransparency = ALPHA, BorderSizePixel = 0, Text = labelText,
		TextColor3 = Color3.new(1, 1, 1), TextSize = 11,
	})
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

local function halfButton(parent, text, x, y, color, h)
	return mk("TextButton", {
		Size = UDim2.new(0.5, 0, 0, h), Position = UDim2.new(x, 0, 0, y),
		BackgroundColor3 = color, BackgroundTransparency = ALPHA, BorderSizePixel = 0,
		Text = text, TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = FONT,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, parent)
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

fullInput(B.scroll, 0, INPUT_ROW_H, "加速", COL.Accel,
	function() return acceleration end,
	function(v)
		acceleration = v
		cfgSet("SIBSAcc", v)
	end)

fullInput(B.scroll, INPUT_ROW_H, INPUT_ROW_H, "抓地", COL.On,
	function() return CFG.TurnGrip end,
	function(v)
		CFG.TurnGrip = v
		cfgSet("SIBSGrip", v)
	end)

B.yBtn = INPUT_ROW_H * 2

B.switchButton = halfButton(B.scroll, "换车", 0.5, B.yBtn, COL.Bind, ROW_H)
setNoCharLabel()
reg(B.switchButton.Activated:Connect(function()
	cycleVehicle()
end))

B.clipButton = halfButton(B.scroll, noClip and "穿墙 开" or "穿墙 关", 0, B.yBtn,
	noClip and COL.On or COL.Off, ROW_H)
reg(B.clipButton.Activated:Connect(function()
	noClip = not noClip
	if noClip then
		clipDirty = true
		clipFalling = false
		clipNextRebuild = 0
	else
		restoreClip()
		clipDirty = true
	end
	B.clipButton.Text = noClip and "穿墙 开" or "穿墙 关"
	B.clipButton.BackgroundColor3 = noClip and COL.On or COL.Off
	cfgSet("SIBSNoClip", noClip)
end))

B.yBtn2 = B.yBtn + ROW_H
B.cruiseButton = halfButton(B.scroll, "定速 关", 0, B.yBtn2, COL.Off, ROW_H)
reg(B.cruiseButton.Activated:Connect(function()
	if not (B.seat or lockPart) then
		return
	end
	cruise = not cruise
	if cruise then
		local p = B.seat or lockPart
		local look = getVehicleFacing(p)
		if look.Magnitude < 0.001 then
			look = Vector3.new(0, 0, 1)
		end
		local hv = flat(p.AssemblyLinearVelocity)
		targetSpeed = hv:Dot(look)
		stopped = false
		refreshStopButton()
	end
	B.cruiseButton.Text = cruise and "定速 开" or "定速 关"
	B.cruiseButton.BackgroundColor3 = cruise and COL.On or COL.Off
end))

B.flyButton = halfButton(B.scroll, "飞车 关", 0.5, B.yBtn2, COL.Off, ROW_H)
reg(B.flyButton.Activated:Connect(function()
	carFly = not carFly
	if not carFly then
		stopCarFly()
	end
	B.flyButton.Text = carFly and "飞车 开" or "飞车 关"
	B.flyButton.BackgroundColor3 = carFly and COL.On or COL.Off
end))

B.yBtn3 = B.yBtn2 + ROW_H
B.listButton = halfButton(B.scroll, "车列表", 0, B.yBtn3, COL.Bind, ROW_H)

B.flipButton = halfButton(B.scroll, "翻转", 0.5, B.yBtn3, COL.Danger, ROW_H)
reg(B.flipButton.Activated:Connect(function()
	flipVehicle()
end))

-- 灯/喇叭四键
B.ySig = B.yBtn3 + ROW_H

B.steadyLBtn = halfButton(B.scroll, "常亮", 0, B.ySig, COL.Off, SIG_ROW_H)
B.flashBtn = halfButton(B.scroll, "闪", 0, B.ySig + SIG_ROW_H, COL.Off, SIG_ROW_H)
B.steadySBtn = halfButton(B.scroll, "常声", 0.5, B.ySig, COL.Off, SIG_ROW_H)
B.beepBtn = halfButton(B.scroll, "声", 0.5, B.ySig + SIG_ROW_H, COL.Off, SIG_ROW_H)

local function refreshSigButtons()
	B.steadyLBtn.BackgroundColor3 = lightSteady and COL.On or COL.Off
	B.steadySBtn.BackgroundColor3 = hornSteady and COL.On or COL.Off
end

reg(B.steadyLBtn.Activated:Connect(function()
	lightSteady = not lightSteady
	if lightSteady then
		armLights()
	else
		B.rearmLights()
	end
	refreshSigButtons()
end))

reg(B.flashBtn.Activated:Connect(function()
	armLights()
	flashUntil = os.clock() + 0.45
end))

reg(B.steadySBtn.Activated:Connect(function()
	if not hornKeyFound then
		detectHornKey()
		return
	end
	hornSteady = not hornSteady
	refreshSigButtons()
end))

reg(B.beepBtn.Activated:Connect(function()
	if not hornKeyFound then
		detectHornKey()
		return
	end
	beepUntil = os.clock() + 0.38
end))

refreshSigButtons()

-- 急刹
B.yStop = B.ySig + SIG_ROW_H * 2
B.stopButton = mk("TextButton", {
	Size = UDim2.new(1, 0, 0, ROW_H), Position = UDim2.new(0, 0, 0, B.yStop),
	BackgroundColor3 = COL.Stop, BackgroundTransparency = ALPHA, BorderSizePixel = 0,
	Text = "急刹 关", TextColor3 = Color3.new(1, 1, 1), TextSize = 13, Font = FONT,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, B.scroll)

reg(B.stopButton.Activated:Connect(function()
	stopped = not stopped
	refreshStopButton()
	if stopped then
		accelerating, decelerating = false, false
		cruise = false
	end
end))

-- 按钮网格（车辆旋转已删：太难用）
B.yGrid = B.yStop + ROW_H
B.grid = mk("Frame", {
	Size = UDim2.new(1, 0, 0, BTN_H * 3),
	Position = UDim2.new(0, 0, 0, B.yGrid),
	BackgroundTransparency = 1,
}, B.scroll)

B.accelHoldButton = halfButton(B.grid, "按住加速", 0, 0, COL.Accel, BTN_H)
B.decelHoldButton = halfButton(B.grid, "按住减速", 0.5, 0, COL.Decel, BTN_H)
holdOn(B.accelHoldButton,
	function()
		stopped = false
		refreshStopButton()
		accelerating = true
	end,
	function() accelerating = false end)
holdOn(B.decelHoldButton,
	function()
		stopped = false
		refreshStopButton()
		decelerating = true
	end,
	function() decelerating = false end)

B.flyUpButton = halfButton(B.grid, "飞车↑", 0, BTN_H, COL.Off, BTN_H)
B.flyDownButton = halfButton(B.grid, "飞车↓", 0.5, BTN_H, COL.Off, BTN_H)
holdOn(B.flyUpButton, function() flyUp = true end, function() flyUp = false end)
holdOn(B.flyDownButton, function() flyDown = true end, function() flyDown = false end)

B.flip180Button = halfButton(B.grid, "翻转 180°", 0, BTN_H * 2, COL.Danger, BTN_H)
reg(B.flip180Button.Activated:Connect(function()
	flipVehicle()
end))

-- 灯光快捷键 O
reg(UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or isTyping() then
		return
	end
	if input.KeyCode == CFG.LampKey then
		lightSteady = not lightSteady
		if lightSteady then
			armLights()
		else
			B.rearmLights()
		end
		refreshSigButtons()
	end
end))

reg(UIS.WindowFocusReleased:Connect(function()
	accelerating, decelerating = false, false
	flyUp, flyDown = false, false
	setHornKey(false)
end))

-- ===== 9. 转向滑条（仅主面板折叠时响应）=====

local STEER_W, STEER_H, STEER_KNOB_R = 150, 36, 14
B.steerGui = mk("ScreenGui", {
	Name = NAME .. "_Steer", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99999,
}, GuiRoot)
B.steerTrack = mk("Frame", {
	Size = UDim2.fromOffset(STEER_W, STEER_H),
	Position = UDim2.new(0, 12, 0.55, -STEER_H / 2),
	BackgroundColor3 = BG, BackgroundTransparency = 0.25, BorderSizePixel = 0,
	Active = true,
}, B.steerGui)
mk("Frame", {
	Size = UDim2.new(0, 2, 0.6, 0), Position = UDim2.new(0.5, -1, 0.2, 0),
	BackgroundColor3 = Color3.fromRGB(80, 84, 100), BorderSizePixel = 0,
}, B.steerTrack)
B.steerKnob = mk("Frame", {
	Size = UDim2.fromOffset(STEER_KNOB_R * 2, STEER_KNOB_R * 2),
	Position = UDim2.new(0.5, -STEER_KNOB_R, 0.5, -STEER_KNOB_R),
	BackgroundColor3 = Color3.fromRGB(140, 190, 155), BorderSizePixel = 0,
}, B.steerTrack)
mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, B.steerKnob)

do
	local saved = cfgGet("UI.Pos." .. NAME .. "Steer", nil)
	if type(saved) == "string" then
		local sx, ox, sy, oy = saved:match("^([%-%d%.]+),([%-%d]+),([%-%d%.]+),([%-%d]+)$")
		if sx then
			local vp = workspace.CurrentCamera.ViewportSize
			local cx = math.clamp(tonumber(ox) or 12, 0, math.max(vp.X - STEER_W, 0))
			local cy = math.clamp(tonumber(oy) or 0, SAFE_TOP, math.max(vp.Y - STEER_H, SAFE_TOP))
			B.steerTrack.Position = UDim2.new(tonumber(sx) or 0, cx, tonumber(sy) or 0.55, cy)
		end
	end
end

B.steerDragging = false
B.steerMoving = false
B.steerAxis = nil
B.steerOrigin = Vector2.zero
B.steerBasePos = UDim2.new()
B.steerTween = nil

local function steerSavePos()
	cfgSet("UI.Pos." .. NAME .. "Steer", string.format("%.6f,%.0f,%.6f,%.0f",
		B.steerTrack.Position.X.Scale, math.floor(B.steerTrack.Position.X.Offset + 0.5),
		B.steerTrack.Position.Y.Scale, math.floor(B.steerTrack.Position.Y.Offset + 0.5)))
end

local function steerReturnCenter()
	steerValue = 0
	if B.steerTween then
		pcall(function() B.steerTween:Cancel() end)
	end
	B.steerTween = TweenService:Create(B.steerKnob,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, -STEER_KNOB_R, 0.5, -STEER_KNOB_R) })
	B.steerTween:Play()
end

-- 触点 X → 转向值（按下即点转，横滑连续转向）
local function steerApplyX(x)
	local usable = STEER_W - STEER_KNOB_R * 2
	local rel = (x - B.steerTrack.AbsolutePosition.X - STEER_KNOB_R) / math.max(usable, 1)
	steerValue = math.clamp(rel * 2 - 1, -1, 1)
	local px = STEER_KNOB_R + usable * ((steerValue + 1) / 2)
	B.steerKnob.Position = UDim2.new(0, px - STEER_KNOB_R, 0.5, -STEER_KNOB_R)
end

B.steerRelease = function()
	if not B.steerDragging then
		return
	end
	B.steerDragging = false
	if B.steerMoving then
		steerSavePos()
	end
	B.steerMoving = false
	B.steerAxis = nil
	steerReturnCenter()
end

reg(B.steerTrack.InputBegan:Connect(function(input)
	-- 核心规则：只有面板折叠时才允许拖动转向（展开时拖动会干扰转向）
	if not isPointer(input) or not collapsed then
		return
	end
	B.steerDragging = true
	B.steerMoving = false
	B.steerAxis = nil
	B.steerOrigin = Vector2.new(input.Position.X, input.Position.Y)
	B.steerBasePos = B.steerTrack.Position
	if B.steerTween then
		pcall(function() B.steerTween:Cancel() end)
	end
	steerApplyX(input.Position.X) -- 按下即点转
end))

reg(UIS.InputChanged:Connect(function(input)
	if not B.steerDragging then
		return
	end
	if not collapsed then
		B.steerRelease()
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local cur = Vector2.new(input.Position.X, input.Position.Y)
	local delta = cur - B.steerOrigin
	-- 轴向定模式：横滑 = 转向；竖滑 = 挪位置
	if not B.steerAxis and (math.abs(delta.X) + math.abs(delta.Y)) > 8 then
		B.steerAxis = (math.abs(delta.X) >= math.abs(delta.Y)) and "steer" or "move"
	end
	if B.steerAxis == "move" then
		B.steerMoving = true
		local vp = workspace.CurrentCamera.ViewportSize
		local minX = -B.steerBasePos.X.Scale * vp.X
		local maxX = vp.X - STEER_W - B.steerBasePos.X.Scale * vp.X
		if minX > maxX then
			minX, maxX = maxX, minX
		end
		local minY = SAFE_TOP - B.steerBasePos.Y.Scale * vp.Y
		local maxY = vp.Y - STEER_H - B.steerBasePos.Y.Scale * vp.Y
		if minY > maxY then
			minY, maxY = maxY, minY
		end
		B.steerTrack.Position = UDim2.new(
			B.steerBasePos.X.Scale, math.clamp(B.steerBasePos.X.Offset + delta.X, minX, maxX),
			B.steerBasePos.Y.Scale, math.clamp(B.steerBasePos.Y.Offset + delta.Y, minY, maxY))
	elseif B.steerAxis == "steer" then
		steerApplyX(cur.X)
	end
end))

reg(UIS.InputEnded:Connect(function(input)
	if isPointer(input) then
		B.steerRelease()
	end
end))
reg(UIS.WindowFocusReleased:Connect(B.steerRelease))

-- ===== 10. 车辆列表（弹窗，按距离排序取前 10）=====

B.listGui = nil

local function closeVehicleList()
	if B.listGui then
		pcall(function() B.listGui:Destroy() end)
		B.listGui = nil
	end
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
			entries[#entries + 1] = {
				model = m, name = tostring(m.Name),
				dist = (rp.Position - camPos).Magnitude, tag = tag,
			}
		end
	end
	if #entries == 0 then
		toast("无候选车辆", COL.Wait)
		return
	end
	table.sort(entries, function(a, b) return a.dist < b.dist end)
	local shown = math.min(#entries, 10)
	B.listGui = mk("ScreenGui", {
		Name = NAME .. "_List", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99999,
	}, GuiRoot)
	local w, rowH = 170, 26
	local frame = mk("Frame", {
		Size = UDim2.new(0, w, 0, 24 + (shown + 1) * rowH),
		Position = UDim2.new(0.5, -w / 2, 0.3, 0),
		BackgroundColor3 = BG, BackgroundTransparency = 0.08, BorderSizePixel = 0,
	}, B.listGui)
	local title = halfButton(frame, "车辆 ×" .. tostring(#entries) .. "（点选）", 0, 0, BG, 24)
	reg(title.Activated:Connect(closeVehicleList))
	for i = 1, shown do
		local e = entries[i]
		local lbl = e.name
		if #lbl > 9 then
			lbl = lbl:sub(1, 8) .. "…"
		end
		local btn = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, rowH),
			Position = UDim2.new(0, 0, 0, 24 + (i - 1) * rowH),
			BackgroundColor3 = (e.model == lockModel) and COL.On or COL.Off,
			BackgroundTransparency = ALPHA, BorderSizePixel = 0,
			Text = " " .. lbl .. " ·" .. tostring(math.floor(e.dist)) .. "m" .. e.tag,
			TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = FONT,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		}, frame)
		reg(btn.Activated:Connect(function()
			manualLockUntil = os.clock() + CFG.ManualLockDuration
			applyLock(e.model)
			closeVehicleList()
		end))
	end
	local rescan = halfButton(frame, "重扫描", 0, 24 + shown * rowH, COL.Bind, rowH)
	reg(rescan.Activated:Connect(openVehicleList))
end

reg(B.listButton.Activated:Connect(function()
	if B.listGui then
		closeVehicleList()
	else
		openVehicleList()
	end
end))

-- ===== 11. 卸载 =====

local DBG = rawget(_G, "SB_DEBUG") or {}
rawset(_G, "SB_DEBUG", DBG)
DBG[NAME] = function()
	local lines = {
		"seat: " .. safeFullName(B.seat),
		"lockPart: " .. safeFullName(lockPart) .. " (score=" .. tostring(lockPartScore) .. ")",
		"lockModel: " .. safeFullName(lockModel),
		"container: " .. safeFullName(getControlledVehicleModel()),
		"owned: " .. tostring(lockModel ~= nil and playerOwnsModel(lockModel) or false),
		"aim: " .. safeFullName(lastAim),
		"myVehicle: " .. tostring(B.myVehicleName or "nil"),
		"cruise: " .. tostring(cruise) .. " stopped: " .. tostring(stopped),
		"locked: " .. tostring(locked) .. " vehicles: " .. tostring(vehicleCount),
		"noClip: " .. tostring(noClip) .. " clipFalling: " .. tostring(clipFalling) .. " carFly: " .. tostring(carFly),
		"steer: " .. string.format("%.2f", steerValue) .. " collapsed: " .. tostring(collapsed),
		"lights: " .. tostring(lightsOn) .. " horn: " .. tostring(hornKey and hornKey.Name) .. " found=" .. tostring(hornKeyFound),
		"accel: " .. tostring(acceleration) .. " grip: " .. tostring(CFG.TurnGrip) .. " targetSpeed: " .. tostring(targetSpeed),
		"grounded: " .. tostring(lastGrounded),
	}
	local control = B.seat or lockPart
	if control then
		local okVel, vel = pcall(function() return control.AssemblyLinearVelocity end)
		if okVel then
			lines[#lines + 1] = "velocity: " .. tostring(vel)
		end
	end
	return "=== SIBS ===\n" .. table.concat(lines, "\n") .. "\n=== END ==="
end

local function destroy()
	accelerating, decelerating = false, false
	steerValue = 0
	cruise, stopped = false, false
	noClip, carFly = false, false
	flyUp, flyDown = false, false
	targetSpeed = 0
	flyVertVel = 0
	closeVehicleList()
	setSeat(nil)
	B.clearDrive()
	stopCarFly()
	restoreClip()
	restoreLamps()
	B.collectEngineSounds()
	table.clear(engineSounds)
	setHornKey(false)
	resetLockState()
	B.myVehicleModel, B.myVehicleName, B.myVehicleAsm = nil, nil, nil
	for _, x in ipairs(seatConns) do
		pcall(function() x:Disconnect() end)
	end
	table.clear(seatConns)
	B.steerGui:Destroy()
	if B.toastGui then
		pcall(function() B.toastGui:Destroy() end)
		B.toastGui = nil
	end
	B.gui:Destroy()
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

print("[sibs] ready（转向滑条仅折叠态可用 / 车列表 / 喇叭探测）")
