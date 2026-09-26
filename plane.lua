-- Selfblox · PLANE — 飞机对战侦测（独立单文件）
-- v11 激进重写：无框架 / 无构建 / 现代 Luau / 原生 API 优先
-- 用法: loadstring(game:HttpGet(".../plane.lua"))()
-- 功能: 飞机模型体检评分、队伍推断（属性/Value/乘员/名字/涂装）、Remote 清单、
--       FireServer 发送间谍（hookmetamethod）、OnClientEvent 接收监听、
--       侦测报告写文件/剪贴板、队伍高亮、自动扫描+自动写报告

local NAME = "PLANE"

-- ===== 0. 重跑替换旧实例 =====

local OLD = rawget(_G, "SB_" .. NAME)
if type(OLD) == "function" then
	pcall(OLD)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
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

-- ===== 1. 配置（仅存面板位置；兼容 v10 的 KIT_Config.txt）=====

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
	StatusH = 42, PanelVisibleH = 240, PlaneMinScore = 55, MaxModelParts = 400,
	SpyLogCap = 120, AutoWriteInterval = 5, AutoScanInterval = 5,
	TeamInfoTTL = 2, HighlightCap = 28, HighlightFillT = 0.75,
	RowH = 32, TitleH = 24, PanelW = 190,
}
local COL = {
	On = Color3.fromRGB(38, 125, 85), Off = Color3.fromRGB(48, 50, 60),
	Good = Color3.fromRGB(135, 215, 155), Bad = Color3.fromRGB(225, 135, 135),
	Wait = Color3.fromRGB(170, 175, 185), Bind = Color3.fromRGB(95, 65, 135),
}
local BG = Color3.fromRGB(20, 22, 28)
local ALPHA = 0.72
local SAFE_TOP = 48

local FILENAME = "plane_debug.txt"
local HAS_WRITEFILE = type(writefile) == "function"

local planeResults, remoteResults, bulletResults = {}, {}, {}
local spyLog, incomingLog = {}, {}
local watchConns, highlightMap = {}, {}
local spyOn, watchOn, previewOn, autoWrite, spyLogAll = false, false, false, false, false
local lastAutoWrite = 0
local lastAutoScan = 0
local mySeat, myPlaneModel = nil, nil
local myPlaneInfo, myPlaneInfoAt = nil, 0
local lastWriteTarget = "未输出"
local lastReportContent = ""
local namecallHooked, oldNamecall = false, nil
local statusLabel = nil
local teamInfoCache = setmetatable({}, { __mode = "k" })
local alive = true

-- ===== 3. 工具 =====

local function nowStamp()
	return os.date("%H:%M:%S")
end

local function safeFullName(inst)
	if not inst then
		return "nil"
	end
	local ok, r = pcall(function() return inst:GetFullName() end)
	return ok and r or tostring(inst)
end

local function getRoot(c)
	if not c then
		return nil
	end
	return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Root")
end

local function fmtValue(v, depth)
	depth = depth or 0
	local t = typeof(v)
	if t == "string" then
		local s = v
		if #s > 64 then
			s = s:sub(1, 61) .. "..."
		end
		return '"' .. s .. '"'
	elseif t == "number" then
		return ("%.4g"):format(v)
	elseif t == "boolean" or t == "nil" then
		return tostring(v)
	elseif t == "Vector3" then
		return ("V3(%.1f,%.1f,%.1f)"):format(v.X, v.Y, v.Z)
	elseif t == "CFrame" then
		local p = v.Position
		return ("CF(%.0f,%.0f,%.0f)"):format(p.X, p.Y, p.Z)
	elseif t == "Instance" then
		return safeFullName(v)
	elseif t == "table" and depth < 2 then
		local parts = {}
		local n = 0
		for k, val in pairs(v) do
			n += 1
			if n > 8 then
				parts[#parts + 1] = "…"
				break
			end
			parts[#parts + 1] = tostring(k) .. "=" .. fmtValue(val, depth + 1)
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

local function fmtArgs(...)
	local n = select("#", ...)
	if n == 0 then
		return "(无参数)"
	end
	local parts = {}
	for i = 1, n do
		parts[#parts + 1] = fmtValue((select(i, ...)))
	end
	return table.concat(parts, ", ")
end

-- ===== 4. 启发式关键词 =====

local PLANE_HINTS = { "plane", "jet", "aircraft", "airplane", "fighter", "bomber", "heli",
	"helicopter", "gunship", "glider", "zeppelin", "blimp", "biplane", "warbird" }
local WING_HINTS = { "wing", "aileron", "rudder", "elevator", "tailfin", "stabilizer",
	"propeller", "rotor", "flap" }
local BULLET_HINTS = { "bullet", "shell", "projectile", "ammo", "missile", "rocket", "pellet" }
local REMOTE_HINTS = { "fire", "shoot", "shot", "bullet", "gun", "weapon", "attack", "damage",
	"hit", "kill", "launch", "missile", "rocket", "bomb", "click", "activate",
	"plane", "spawn", "team", "join", "seat", "pilot" }

local function nameHint(name, hints)
	local n = tostring(name):lower()
	for _, h in ipairs(hints) do
		if n:find(h, 1, true) then
			return h
		end
	end
	return nil
end

-- 归一化色距：明度差异按比例缩放，避免深灰误判到深色队伍
local function colorDistance(a, b)
	local dr, dg, db = a.R - b.R, a.G - b.G, a.B - b.B
	local lumA = 0.299 * a.R + 0.587 * a.G + 0.114 * a.B
	local lumB = 0.299 * b.R + 0.587 * b.G + 0.114 * b.B
	local lumScale = 1 + math.abs(lumA - lumB)
	return math.sqrt(dr * dr + dg * dg + db * db) / lumScale
end

-- ===== 5. 飞机体检 =====

local function inspectModel(model)
	local info = {
		model = model, path = safeFullName(model),
		hint = nameHint(model.Name, PLANE_HINTS),
		hasSeat = false, seatNames = {}, wingCount = 0,
		partCount = 0, anchoredCount = 0,
		attributes = {}, values = {}, remotes = {}, clickables = {},
		occupant = nil, mainPart = nil, bodyColor = nil,
		isMine = false, teamInfo = nil, dist = nil,
	}
	pcall(function()
		local n = 0
		local bestVol = 0
		for _, d in ipairs(model:GetDescendants()) do
			n += 1
			if n > CFG.MaxModelParts then
				break
			end
			local cn = d.ClassName
			if cn == "Seat" or cn == "VehicleSeat" then
				info.hasSeat = true
				if #info.seatNames < 4 then
					info.seatNames[#info.seatNames + 1] = d.Name
				end
				if not info.occupant then
					local occ = d.Occupant
					if occ then
						local chr = occ.Parent
						info.occupant = chr and Players:GetPlayerFromCharacter(chr) or nil
					end
				end
			elseif cn == "RemoteEvent" or cn == "RemoteFunction" or cn == "UnreliableRemoteEvent" then
				if #info.remotes < 8 then
					info.remotes[#info.remotes + 1] = d
				end
			elseif cn == "ClickDetector" or cn == "ProximityPrompt" then
				if #info.clickables < 8 then
					info.clickables[#info.clickables + 1] = d
				end
			elseif d:IsA("BasePart") and cn ~= "Terrain" then
				info.partCount += 1
				if d.Anchored then
					info.anchoredCount += 1
				end
				if nameHint(d.Name, WING_HINTS) then
					info.wingCount += 1
				end
				local vol = d.Size.X * d.Size.Y * d.Size.Z
				if vol > bestVol then
					bestVol, info.mainPart = vol, d
				end
			elseif d:IsA("ValueBase") then
				local dn = d.Name:lower()
				if dn:find("team") or dn:find("owner") or dn:find("faction") or dn:find("side")
					or dn:find("creator") or dn:find("player") or dn:find("user") or dn:find("country") then
					local okV, v = pcall(function() return d.Value end)
					if okV and #info.values < 8 then
						info.values[#info.values + 1] = d.Name .. "=" .. fmtValue(v)
					end
				end
			end
		end
		if info.mainPart then
			info.bodyColor = info.mainPart.Color
		end
	end)
	pcall(function()
		local list = {}
		for k, v in pairs(model:GetAttributes()) do
			list[#list + 1] = k .. "=" .. fmtValue(v)
		end
		info.attributes = list
	end)
	local score = 0
	if info.hint then
		score += 40
	end
	if info.hasSeat then
		score += 35
	end
	if info.wingCount >= 1 then
		score += 15
	end
	if info.wingCount >= 2 then
		score += 10
	end
	if info.partCount >= 8 then
		score += 10
	end
	if info.partCount > 0 and info.anchoredCount < info.partCount then
		score += 5
	end
	if info.occupant then
		score += 5
	end
	info.score = score
	return info
end

-- 队伍推断优先级：模型属性 → Value 对象 → 乘员队伍 → 名字色词 → 涂装近似
local function inferTeam(info)
	local model = info.model
	if not model or not model.Parent then
		return nil
	end
	local found = nil
	pcall(function()
		for k, v in pairs(model:GetAttributes()) do
			if found then
				break
			end
			local lk = tostring(k):lower()
			if lk:find("team") or lk:find("faction") or lk:find("side")
				or lk:find("country") or lk:find("force") or lk:find("nation") then
				found = { src = "attr:" .. k, value = tostring(v) }
			end
		end
	end)
	if found then
		return found
	end

	found = nil
	pcall(function()
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			n += 1
			if n > 200 or found then
				break
			end
			local dn = d.Name:lower()
			if d:IsA("ValueBase") and (dn:find("team") or dn:find("faction")
				or dn:find("side") or dn:find("country")) then
				local okV, v = pcall(function() return d.Value end)
				if okV then
					found = { src = "value:" .. d.Name, value = fmtValue(v) }
				end
			end
		end
	end)
	if found then
		return found
	end

	if info.occupant and info.occupant.Team then
		return { src = "乘员", value = info.occupant.Team.Name, playerTeam = info.occupant.Team }
	end

	local n = model.Name:lower()
	if n:find("red", 1, true) then
		return { src = "名字:red", value = "红方?" }
	end
	if n:find("blue", 1, true) then
		return { src = "名字:blue", value = "蓝方?" }
	end
	if n:find("axis", 1, true) then
		return { src = "名字:axis", value = "轴心?" }
	end
	if n:find("allied", 1, true) or n:find("ally", 1, true) then
		return { src = "名字:allied", value = "同盟?" }
	end

	if info.bodyColor then
		local bestTeam, bestD = nil, math.huge
		pcall(function()
			for _, t in ipairs(Teams:GetTeams()) do
				local d = colorDistance(info.bodyColor, t.TeamColor.Color)
				if d < bestD then
					bestTeam, bestD = t, d
				end
			end
		end)
		if bestTeam and bestD <= 0.5 then
			return { src = "涂装≈" .. bestTeam.Name, value = bestTeam.Name, playerTeam = bestTeam }
		end
		return { src = "涂装", value = string.format("RGB(%.0f,%.0f,%.0f)",
			info.bodyColor.R * 255, info.bodyColor.G * 255, info.bodyColor.B * 255) }
	end
	return nil
end

-- 队伍推断带 TTL 缓存（按模型）
local function teamInfoFor(info)
	local rec = teamInfoCache[info.model]
	local now = os.clock()
	if rec and now - rec.at < CFG.TeamInfoTTL then
		return rec.info
	end
	local ti = inferTeam(info)
	teamInfoCache[info.model] = { info = ti, at = now }
	return ti
end

local function dumpPlaneInfo(log, info)
	local tags = {}
	if info.isMine then
		tags[#tags + 1] = "★我乘坐"
	end
	if info.occupant then
		tags[#tags + 1] = "乘员:" .. info.occupant.Name
	end
	local tagStr = #tags > 0 and ("  [" .. table.concat(tags, " ") .. "]") or ""
	log(string.format("  [%d分] %s%s", info.score, info.path, tagStr))
	log(string.format("    提示:%s | 座位:%s | 部件:%d(锚:%d) | 翼件:%d",
		tostring(info.hint or "-"),
		(#info.seatNames > 0 and table.concat(info.seatNames, "/") or "无"),
		info.partCount, info.anchoredCount, info.wingCount))
	if info.dist then
		log(string.format("    距离: %.0f", info.dist))
	end
	if #info.attributes > 0 then
		log("    属性: " .. table.concat(info.attributes, "; "))
	end
	if #info.values > 0 then
		log("    Values: " .. table.concat(info.values, "; "))
	end
	if info.teamInfo then
		log(string.format("    推测队伍: %s (依据:%s)",
			tostring(info.teamInfo.value), tostring(info.teamInfo.src)))
	end
	if info.bodyColor then
		log(string.format("    涂装: RGB(%.0f,%.0f,%.0f)",
			info.bodyColor.R * 255, info.bodyColor.G * 255, info.bodyColor.B * 255))
	end
	for _, r in ipairs(info.remotes) do
		log("    内嵌 " .. r.ClassName .. ": " .. safeFullName(r))
	end
	for _, c in ipairs(info.clickables) do
		log("    内嵌 " .. c.ClassName .. ": " .. safeFullName(c))
	end
end

-- ===== 6. 扫描 =====

local function scanPlanes()
	local results = {}
	local inspected = 0

	local function visit(container, depth)
		if depth > 4 or inspected > 300 or #results >= 80 then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if inspected > 300 or #results >= 80 then
				return
			end
			if child:IsA("Model") then
				if not child:FindFirstChildOfClass("Humanoid") then
					inspected += 1
					local info = inspectModel(child)
					if info.score >= CFG.PlaneMinScore then
						results[#results + 1] = info
					else
						visit(child, depth + 1)
					end
				end
			elseif child:IsA("Folder") then
				visit(child, depth + 1)
			end
		end
	end

	pcall(function() visit(workspace, 0) end)

	-- 距离参考：我在的飞机 → 角色 → 相机
	local refPos = nil
	local cam = workspace.CurrentCamera
	if cam then
		refPos = cam.CFrame.Position
	end
	local char = player.Character
	if char then
		local r = getRoot(char)
		if r then
			refPos = r.Position
		end
	end
	if myPlaneModel and myPlaneModel.Parent then
		local okP, mp = pcall(function()
			return myPlaneModel.PrimaryPart or myPlaneModel:FindFirstChildWhichIsA("BasePart", true)
		end)
		if okP and mp then
			refPos = mp.Position
		end
	end

	for _, info in ipairs(results) do
		if info.mainPart and refPos then
			local okD, d = pcall(function() return (info.mainPart.Position - refPos).Magnitude end)
			if okD then
				info.dist = d
			end
		end
		if mySeat and mySeat.Parent and mySeat:IsDescendantOf(info.model) then
			info.isMine = true
		end
	end

	table.sort(results, function(a, b)
		if a.isMine ~= b.isMine then
			return a.isMine
		end
		if a.score ~= b.score then
			return a.score > b.score
		end
		return (a.dist or math.huge) < (b.dist or math.huge)
	end)
	return results
end

local function scanRemotes()
	local results = {}
	pcall(function()
		for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
			local cn = d.ClassName
			if cn == "RemoteEvent" or cn == "RemoteFunction" or cn == "UnreliableRemoteEvent" then
				results[#results + 1] = { remote = d, hint = nameHint(d.Name, REMOTE_HINTS) }
				if #results >= 400 then
					break
				end
			end
		end
	end)
	pcall(function()
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			n += 1
			if n > 3000 or #results >= 500 then
				break
			end
			local cn = d.ClassName
			if cn == "RemoteEvent" or cn == "RemoteFunction" or cn == "UnreliableRemoteEvent" then
				results[#results + 1] = { remote = d, hint = nameHint(d.Name, REMOTE_HINTS) }
			end
		end
	end)
	table.sort(results, function(a, b)
		local ha, hb = a.hint ~= nil, b.hint ~= nil
		if ha ~= hb then
			return ha
		end
		return safeFullName(a.remote) < safeFullName(b.remote)
	end)
	return results
end

local function scanBullets()
	local found = {}
	pcall(function()
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			n += 1
			if n > 4000 then
				break
			end
			if d:IsA("BasePart") and nameHint(d.Name, BULLET_HINTS) then
				found[#found + 1] = d
				if #found >= 30 then
					break
				end
			end
		end
	end)
	return found
end

-- ===== 7. 发送间谍（__namecall 钩子）=====

local function recordSpy(path, method, argsStr)
	spyLog[#spyLog + 1] = string.format("%s %s:%s %s", nowStamp(), path, method, argsStr)
	if #spyLog > CFG.SpyLogCap then
		table.remove(spyLog, 1)
	end
end

local function spyFilter(path)
	if spyLogAll then
		return true
	end
	return nameHint(path, REMOTE_HINTS) ~= nil
end

local function startSpy()
	if namecallHooked then
		return true
	end
	if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
		return false, "环境缺少 hookmetamethod / getnamecallmethod"
	end
	local wrap = (type(newcclosure) == "function") and newcclosure or function(f) return f end
	local previous = nil
	local hookFn = function(self, ...)
		local m = getnamecallmethod()
		if m == "FireServer" or m == "InvokeServer" then
			-- 参数先打包再进 pcall：嵌套闭包里不能直接用 ...
			local args = table.pack(...)
			pcall(function()
				local path = safeFullName(self)
				if spyFilter(path) then
					recordSpy(path, m, fmtArgs(table.unpack(args, 1, args.n)))
				end
			end)
		end
		-- 无条件回落到原元方法：previous 异常时也不能吞掉调用
		return previous(self, ...)
	end
	local ok, old = pcall(hookmetamethod, game, "__namecall", wrap(hookFn))
	if not ok or type(old) ~= "function" then
		return false, "hookmetamethod 安装失败"
	end
	previous = old
	oldNamecall = old
	namecallHooked = true
	return true
end

local function stopSpy()
	if not namecallHooked then
		return
	end
	pcall(function() hookmetamethod(game, "__namecall", oldNamecall) end)
	namecallHooked = false
	oldNamecall = nil
end

-- ===== 8. 接收监听（OnClientEvent）=====

local function watchRemotes(remotes)
	for _, c in pairs(watchConns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(watchConns)
	if not watchOn then
		return
	end
	local limit = spyLogAll and 40 or 24
	local n = 0
	for _, rec in ipairs(remotes) do
		if n >= limit then
			break
		end
		if rec.hint or spyLogAll then
			local r = rec.remote
			local cn = r.ClassName
			if (cn == "RemoteEvent" or cn == "UnreliableRemoteEvent") and r.Parent then
				local okC, con = pcall(function()
					return r.OnClientEvent:Connect(function(...)
						-- 参数先打包再进 pcall：嵌套闭包里不能直接用 ...
						local args = table.pack(...)
						pcall(function()
							incomingLog[#incomingLog + 1] = string.format("%s <- %s %s",
								nowStamp(), safeFullName(r), fmtArgs(table.unpack(args, 1, args.n)))
							if #incomingLog > CFG.SpyLogCap then
								table.remove(incomingLog, 1)
							end
						end)
					end)
				end)
				if okC and con then
					watchConns[r] = con
					n += 1
				end
			end
		end
	end
end

-- ===== 9. 报告 =====

local function buildReport()
	local lines = {}
	local function log(msg) lines[#lines + 1] = tostring(msg) end

	log("==== PLANE DEBUG REPORT ====")
	log("时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
	log("PlaceId: " .. tostring(game.PlaceId))
	log("玩家: " .. player.Name .. " #" .. tostring(player.UserId)
		.. " | 队伍: " .. (player.Team and player.Team.Name or "无"))
	do
		local pattrs = {}
		pcall(function()
			for k, v in pairs(player:GetAttributes()) do
				pattrs[#pattrs + 1] = k .. "=" .. tostring(v)
			end
		end)
		if #pattrs > 0 then
			log("玩家属性: " .. table.concat(pattrs, "; "))
		end
	end

	log("")
	log("== Teams 服务 ==")
	local teams = Teams:GetTeams()
	if #teams == 0 then
		log("  (空 → 队伍可能用 属性 / Value / 涂装 / 名字 区分)")
	else
		for _, t in ipairs(teams) do
			local n = 0
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Team == t then
					n += 1
				end
			end
			log(string.format("  %-18s | %s | %d人", t.Name, tostring(t.TeamColor), n))
		end
	end

	log("")
	log("== 玩家列表 ==")
	for _, p in ipairs(Players:GetPlayers()) do
		log(string.format("  %-20s | 队:%s", p.Name, p.Team and p.Team.Name or "-"))
	end

	log("")
	log("== 我乘坐的飞机 ==")
	if mySeat and mySeat.Parent then
		log("  座位: " .. safeFullName(mySeat) .. " (" .. mySeat.ClassName .. ")")
		if myPlaneModel and myPlaneModel.Parent then
			local now = os.clock()
			if not myPlaneInfo or now - myPlaneInfoAt > CFG.TeamInfoTTL then
				local info = inspectModel(myPlaneModel)
				info.isMine = true
				info.teamInfo = teamInfoFor(info)
				myPlaneInfo = info
				myPlaneInfoAt = now
			end
			dumpPlaneInfo(log, myPlaneInfo)
		end
	else
		log("  (当前未乘坐)")
	end

	log("")
	log("== 我的背包 / 手持 ==")
	pcall(function()
		local bp = player:FindFirstChild("Backpack")
		if bp then
			for _, item in ipairs(bp:GetChildren()) do
				local extra = item:IsA("Tool") and " | Tool" or ""
				if item:IsA("Tool") and (item:FindFirstChildOfClass("RemoteEvent")
					or item:FindFirstChildOfClass("RemoteFunction")) then
					extra = " | Tool(内嵌Remote)"
				end
				log("  " .. item.ClassName .. " '" .. item.Name .. "'" .. extra)
			end
		end
	end)
	pcall(function()
		local char = player.Character
		if char then
			for _, item in ipairs(char:GetChildren()) do
				if item:IsA("Tool") then
					log("  [手持] Tool '" .. item.Name .. "'")
				end
			end
		end
	end)

	log("")
	log(string.format("== 飞机候选 %d 架 (判定分≥%d) ==", #planeResults, CFG.PlaneMinScore))
	if #planeResults == 0 then
		log("  (无 → 试试降低「判定分」阈值；仍无就把飞机的路径发我)")
	else
		for i, info in ipairs(planeResults) do
			if i > 40 then
				log("  … 其余 " .. (#planeResults - 40) .. " 架省略")
				break
			end
			dumpPlaneInfo(log, info)
		end
	end

	log("")
	log(string.format("== Remote 清单 %d 个 ==", #remoteResults))
	local hinted, plain = {}, {}
	for _, rec in ipairs(remoteResults) do
		if rec.hint then
			hinted[#hinted + 1] = rec
		else
			plain[#plain + 1] = rec
		end
	end
	log("-- 名字带关键词 --")
	if #hinted == 0 then
		log("  (无)")
	end
	for _, rec in ipairs(hinted) do
		log("  " .. safeFullName(rec.remote) .. " [" .. rec.remote.ClassName .. "] 命中:" .. rec.hint)
	end
	log("-- 其它（前 60）--")
	for i, rec in ipairs(plain) do
		if i > 60 then
			log("  … 其余 " .. (#plain - 60) .. " 个省略")
			break
		end
		log("  " .. safeFullName(rec.remote) .. " [" .. rec.remote.ClassName .. "]")
	end

	log("")
	log(string.format("== 弹体样本 %d 个 ==", #bulletResults))
	if #bulletResults == 0 then
		log("  (未抓到 → 子弹可能不叫这些名字，或即生即灭)")
	end
	for _, b in ipairs(bulletResults) do
		local okV, v = pcall(function() return b.AssemblyLinearVelocity end)
		local velStr = okV and ("%.0f"):format(v.Magnitude) or "?"
		local okS, s = pcall(function() return b.Size end)
		local sizeStr = okS and ("%.1f"):format(s.Magnitude) or "?"
		log(string.format("  %s | 速度:%s | 大小:%s", safeFullName(b), velStr, sizeStr))
	end

	log("")
	log(string.format("== FireServer / InvokeServer 记录 %d 条 ==", #spyLog))
	if #spyLog == 0 then
		log("  (空 → 打开「发侦听」后进飞机开几枪，再点「写文件」)")
	end
	for _, entry in ipairs(spyLog) do
		log("  " .. entry)
	end

	log("")
	log(string.format("== OnClientEvent 记录 %d 条 ==", #incomingLog))
	if #incomingLog == 0 then
		log("  (空 → 打开「收侦听」)")
	end
	for _, entry in ipairs(incomingLog) do
		log("  " .. entry)
	end

	log("")
	log(string.format("开关状态: 发侦听=%s 收侦听=%s 全录=%s 高亮=%s 自动=%s",
		tostring(spyOn), tostring(watchOn), tostring(spyLogAll),
		tostring(previewOn), tostring(autoWrite)))
	log("==== END ====")
	return lines
end

local function refreshStatus()
	if not statusLabel then
		return
	end
	local friendly, enemy, unknown = 0, 0, 0
	local myTeam = player.Team
	for _, info in ipairs(planeResults) do
		local ti = info.teamInfo
		if ti and ti.playerTeam and myTeam then
			if ti.playerTeam == myTeam then
				friendly += 1
			else
				enemy += 1
			end
		else
			unknown += 1
		end
	end
	statusLabel.Text = string.format("飞机 %d | 敌 %d 友 %d 未知 %d\nRemote %d | 弹体 %d | %s",
		#planeResults, enemy, friendly, unknown, #remoteResults, #bulletResults, lastWriteTarget)
end

local function writeReport()
	local lines = buildReport()
	lastReportContent = table.concat(lines, "\n")
	if HAS_WRITEFILE then
		local ok = pcall(writefile, FILENAME, lastReportContent)
		if ok then
			lastWriteTarget = FILENAME
			refreshStatus()
			return FILENAME, #lines
		end
	end
	local CH = 45
	for i = 1, #lines, CH do
		local part = {}
		for j = i, math.min(i + CH - 1, #lines) do
			part[#part + 1] = lines[j]
		end
		print("[plane] " .. table.concat(part, "\n"))
	end
	lastWriteTarget = "console"
	refreshStatus()
	return "console", #lines
end

-- ===== 10. 高亮（复用，不重建）=====

local function applyHighlights()
	local aliveSet = {}
	local myTeam = player.Team
	local n = 0
	for _, info in ipairs(planeResults) do
		if n >= CFG.HighlightCap then
			break
		end
		local model = info.model
		if model and model.Parent then
			local color = Color3.fromRGB(200, 200, 200)
			local ti = info.teamInfo
			if ti and ti.playerTeam and myTeam then
				color = (ti.playerTeam == myTeam)
					and Color3.fromRGB(70, 210, 100) or Color3.fromRGB(235, 70, 70)
			end
			local h = highlightMap[model]
			if not h or not h.Parent then
				local ok, created = pcall(function()
					local hl = mk("Highlight", {
						Name = "PLANE_Preview",
						DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
					}, model)
					return hl
				end)
				h = ok and created or nil
			end
			if h then
				h.FillColor = color
				h.OutlineColor = color
				h.FillTransparency = CFG.HighlightFillT
				highlightMap[model] = h
				aliveSet[model] = true
				n += 1
			end
		end
	end
	for model, h in pairs(highlightMap) do
		if not aliveSet[model] then
			pcall(function() h:Destroy() end)
			highlightMap[model] = nil
		end
	end
end

-- ===== 11. 重扫 =====

local function rescan()
	planeResults = scanPlanes()
	remoteResults = scanRemotes()
	bulletResults = scanBullets()
	for _, info in ipairs(planeResults) do
		info.teamInfo = teamInfoFor(info)
	end
	watchRemotes(remoteResults)
	applyHighlights()
	refreshStatus()
end

-- ===== 12. 座位同步 =====

local function syncSeat(s)
	if s and (s:IsA("VehicleSeat") or s:IsA("Seat")) then
		if mySeat ~= s then
			mySeat = s
			myPlaneModel = s:FindFirstAncestorWhichIsA("Model")
			myPlaneInfo = nil
			rescan()
			-- 报告构建可能较重，defer 出事件回调
			task.defer(function()
				if alive then
					writeReport()
				end
			end)
			print("[plane] 登机 → 报告已更新: " .. safeFullName(myPlaneModel))
		end
	else
		mySeat = nil
		myPlaneModel = nil
		myPlaneInfo = nil
		refreshStatus()
	end
end

-- ===== 13. UI =====

local CONTENT_H = CFG.StatusH + 4 + CFG.RowH * 4 + 2 + 20 + 2 + 16
local totalH = math.min(CFG.TitleH + CONTENT_H + 4, CFG.PanelVisibleH)
local panelSize = UDim2.new(0, CFG.PanelW, 0, totalH)
local panelPos = UDim2.new(0.5, -CFG.PanelW / 2, 0.30, -totalH / 2)

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
			local w, h = CFG.PanelW, totalH
			local absX = math.clamp(tonumber(ox) or 0, 0, math.max(vp.X - w, 0))
			local absY = math.clamp(tonumber(oy) or 0, SAFE_TOP, math.max(vp.Y - h, SAFE_TOP))
			main.Position = UDim2.new(tonumber(sx) or 0, absX, tonumber(sy) or 0, absY)
		end
	end
end

local titleBar = mk("TextButton", {
	Size = UDim2.new(1, 0, 0, CFG.TitleH), BackgroundColor3 = BG, BackgroundTransparency = 1,
	BorderSizePixel = 0, Text = "飞机侦测 [-]", TextColor3 = Color3.new(1, 1, 1),
	TextSize = 13, Font = FONT, TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
}, main)

do
	local dragging, moved, origin, base = false, false, Vector2.zero, UDim2.new()
	reg(titleBar.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
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
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
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
		titleBar.Text = "飞机侦测 " .. (collapsed and "[+]" or "[-]")
		main.Size = collapsed and UDim2.new(0, CFG.PanelW, 0, CFG.TitleH) or panelSize
	end))
end

local scroll = mk("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -CFG.TitleH), Position = UDim2.new(0, 0, 0, CFG.TitleH),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 2, ScrollingDirection = Enum.ScrollingDirection.Y,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, main)

statusLabel = mk("TextLabel", {
	Size = UDim2.new(1, -8, 0, CFG.StatusH), Position = UDim2.new(0, 4, 0, 0),
	BackgroundTransparency = 1, BorderSizePixel = 0, Text = "初始化…",
	TextColor3 = Color3.fromRGB(235, 235, 235), Font = FONT, TextSize = 11,
	TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
}, scroll)

local function setToggle(btn, on, labelText)
	btn.Text = labelText .. (on and " 开" or " 关")
	btn.BackgroundColor3 = on and COL.On or COL.Off
end

local function halfButton(parent, text, x, y, color, h)
	return mk("TextButton", {
		Size = UDim2.new(0.5, 0, 0, h), Position = UDim2.new(x, 0, 0, y),
		BackgroundColor3 = color, BackgroundTransparency = ALPHA, BorderSizePixel = 0,
		Text = text, TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = FONT,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, parent)
end

local y0 = CFG.StatusH + 4
local function rowY(i) return y0 + CFG.RowH * (i - 1) end

local rescanBtn = halfButton(scroll, "重扫", 0, rowY(1), COL.Bind, CFG.RowH)
local writeBtn = halfButton(scroll, "写文件", 0.5, rowY(1), COL.Bind, CFG.RowH)
local spyBtn = halfButton(scroll, "发侦听 关", 0, rowY(2), COL.Off, CFG.RowH)
local watchBtn = halfButton(scroll, "收侦听 关", 0.5, rowY(2), COL.Off, CFG.RowH)
local hlBtn = halfButton(scroll, "高亮 关", 0, rowY(3), COL.Off, CFG.RowH)
local autoBtn = halfButton(scroll, "自动 关", 0.5, rowY(3), COL.Off, CFG.RowH)

local SCORE_STEPS = { 35, 45, 55, 70, 85 }
local scoreIdx = 3
local scoreBtn = halfButton(scroll, "判定分 " .. tostring(CFG.PlaneMinScore), 0, rowY(4), COL.Off, CFG.RowH)
local allBtn = halfButton(scroll, "全录 关", 0.5, rowY(4), COL.Off, CFG.RowH)

local clearBtn = mk("TextButton", {
	Size = UDim2.new(1, 0, 0, 20),
	Position = UDim2.new(0, 0, 0, rowY(4) + CFG.RowH + 2),
	BackgroundColor3 = COL.Off, BackgroundTransparency = 0.85, BorderSizePixel = 0,
	Text = "清空侦听记录", TextColor3 = Color3.fromRGB(200, 200, 205),
	TextSize = 11, Font = FONT, TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
}, scroll)

mk("TextLabel", {
	Size = UDim2.new(1, -8, 0, 16),
	Position = UDim2.new(0, 4, 0, rowY(4) + CFG.RowH + 26),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	Text = "流程: 上机 → 发侦听 → 开几枪 → 写文件",
	TextColor3 = Color3.fromRGB(150, 155, 165), Font = FONT, TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Left,
}, scroll)

reg(rescanBtn.Activated:Connect(function()
	rescan()
end))

reg(writeBtn.Activated:Connect(function()
	local target, n = writeReport()
	local extra = ""
	if type(setclipboard) == "function" then
		local ok = pcall(setclipboard, lastReportContent)
		if ok then
			extra = " | 已复制到剪贴板"
		end
	end
	print("[plane] 报告 → " .. tostring(target) .. " (" .. tostring(n) .. " 行)" .. extra)
end))

reg(spyBtn.Activated:Connect(function()
	if spyOn then
		stopSpy()
		spyOn = false
	else
		local ok, err = startSpy()
		if ok then
			spyOn = true
		else
			warn("[plane] 发侦听不可用: " .. tostring(err))
		end
	end
	setToggle(spyBtn, spyOn, "发侦听")
end))

reg(watchBtn.Activated:Connect(function()
	watchOn = not watchOn
	watchRemotes(remoteResults)
	setToggle(watchBtn, watchOn, "收侦听")
end))

reg(hlBtn.Activated:Connect(function()
	previewOn = not previewOn
	applyHighlights()
	setToggle(hlBtn, previewOn, "高亮")
end))

reg(autoBtn.Activated:Connect(function()
	autoWrite = not autoWrite
	lastAutoWrite = 0
	lastAutoScan = 0
	setToggle(autoBtn, autoWrite, "自动")
end))

reg(scoreBtn.Activated:Connect(function()
	scoreIdx = scoreIdx % #SCORE_STEPS + 1
	CFG.PlaneMinScore = SCORE_STEPS[scoreIdx]
	scoreBtn.Text = "判定分 " .. tostring(CFG.PlaneMinScore)
	rescan()
end))

reg(allBtn.Activated:Connect(function()
	spyLogAll = not spyLogAll
	if watchOn then
		watchRemotes(remoteResults)
	end
	setToggle(allBtn, spyLogAll, "全录")
end))

reg(clearBtn.Activated:Connect(function()
	table.clear(spyLog)
	table.clear(incomingLog)
	refreshStatus()
end))

reg(player:GetPropertyChangedSignal("Team"):Connect(function()
	refreshStatus()
	applyHighlights()
end))

local function isTyping()
	return UIS:GetFocusedTextBox() ~= nil
end

-- 发侦听开启且在机上时，记录按键（帮助定位开火键）
reg(UIS.InputBegan:Connect(function(input, gp)
	if gp or not spyOn then
		return
	end
	if not (mySeat and mySeat.Parent) then
		return
	end
	if isTyping() then
		return
	end
	local desc = nil
	local uit = input.UserInputType
	if uit == Enum.UserInputType.MouseButton1 then
		desc = "MB1"
	elseif uit == Enum.UserInputType.MouseButton2 then
		desc = "MB2"
	elseif input.KeyCode ~= Enum.KeyCode.Unknown then
		desc = tostring(input.KeyCode)
	end
	if desc then
		recordSpy("(输入)", "InputBegan", desc)
	end
end))

-- ===== 14. 自动循环 =====

reg(RunService.Heartbeat:Connect(function()
	if not autoWrite then
		return
	end
	local now = os.clock()
	if now - lastAutoWrite < CFG.AutoWriteInterval then
		return
	end
	lastAutoWrite = now
	-- 扫描按自己的节奏跑；间谍日志本身是实时的
	if now - lastAutoScan >= CFG.AutoScanInterval then
		lastAutoScan = now
		pcall(rescan)
	end
	pcall(writeReport)
end))

-- 座位监听（替代 kit context）
local seatConns = {}
local function hookHumanoid(h)
	seatConns[#seatConns + 1] = h.Seated:Connect(function(_, seatPart)
		syncSeat(seatPart)
	end)
	seatConns[#seatConns + 1] = h:GetPropertyChangedSignal("SeatPart"):Connect(function()
		syncSeat(h.SeatPart)
	end)
	syncSeat(h.SeatPart)
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

-- ===== 15. 卸载 / 启动 =====

local DBG = rawget(_G, "SB_DEBUG") or {}
rawset(_G, "SB_DEBUG", DBG)
DBG[NAME] = function()
	local function countTable(t)
		local n = 0
		for _ in pairs(t) do
			n += 1
		end
		return n
	end
	local lines = {
		"file: " .. tostring(lastWriteTarget),
		"writefile: " .. tostring(HAS_WRITEFILE) .. " clipboard: " .. tostring(type(setclipboard) == "function"),
		"hook: " .. tostring(type(hookmetamethod) == "function"),
		"planes: " .. tostring(#planeResults) .. " remotes: " .. tostring(#remoteResults)
			.. " bullets: " .. tostring(#bulletResults),
		"mySeat: " .. safeFullName(mySeat) .. " myPlane: " .. safeFullName(myPlaneModel),
		"spy: " .. tostring(spyOn) .. " hooked=" .. tostring(namecallHooked) .. " log=" .. tostring(#spyLog),
		"watch: " .. tostring(watchOn) .. " conns=" .. countTable(watchConns) .. " log=" .. tostring(#incomingLog),
		"preview: " .. tostring(previewOn) .. " hl=" .. countTable(highlightMap),
		"autoWrite: " .. tostring(autoWrite) .. " minScore: " .. tostring(CFG.PlaneMinScore),
	}
	return "=== PLANE ===\n" .. table.concat(lines, "\n") .. "\n=== END ==="
end

local function destroy()
	alive = false
	stopSpy()
	for _, c in pairs(watchConns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(watchConns)
	for _, h in pairs(highlightMap) do
		pcall(function() h:Destroy() end)
	end
	table.clear(highlightMap)
	table.clear(spyLog)
	table.clear(incomingLog)
	table.clear(teamInfoCache)
	planeResults, remoteResults, bulletResults = {}, {}, {}
	spyOn, watchOn, previewOn, autoWrite, spyLogAll = false, false, false, false, false
	mySeat, myPlaneModel, myPlaneInfo = nil, nil, nil
	for _, x in ipairs(seatConns) do
		pcall(function() x:Disconnect() end)
	end
	table.clear(seatConns)
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

-- 启动
rescan()
if player.Character then
	bindSeatCharacter(player.Character)
end
if lastWriteTarget == "未输出" then
	writeReport()
end
print("[plane] ready（侦察报告 → " .. tostring(lastWriteTarget) .. "）")
