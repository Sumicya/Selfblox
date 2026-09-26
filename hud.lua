-- Selfblox · HUD — 数据条 + 速度箭头 + 玩家 ESP（独立单文件）
-- v11 激进重写：无框架 / 无构建 / 现代 Luau / 原生 API 优先
-- 用法: loadstring(game:HttpGet(".../hud.lua"))()
-- ESP 用执行器原生 Drawing 库直绘；没有 Drawing 时 HUD/箭头照常，ESP 静默关闭

local NAME = "HUD"

-- ===== 0. 重跑替换旧实例 =====

local OLD = rawget(_G, "SB_" .. NAME)
if type(OLD) == "function" then
	pcall(OLD)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
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
local FONT_BOLD = pickFont({ "BuilderSansBold", "GothamBold", "SourceSansBold" }, Enum.Font.SourceSansBold)
local FONT_REG = pickFont({ "BuilderSans", "Gotham", "SourceSans" }, Enum.Font.SourceSans)

-- v10 遗留 GUI 一并清掉（v10 的 HUD 叫 KIT / KITText）
for _, n in ipairs({ "HUD", "KIT", "KITText", "KIT_Toast" }) do
	local old = GuiRoot:FindFirstChild(n)
	if old then
		pcall(function() old:Destroy() end)
	end
end

-- ===== 1. 常量 =====

local COL = {
	Ping = Color3.fromRGB(137, 220, 235), Fps = Color3.fromRGB(170, 230, 150),
	FpsLow = Color3.fromRGB(235, 120, 120), Memory = Color3.fromRGB(200, 180, 235),
	Time = Color3.fromRGB(235, 200, 150), Max = Color3.fromRGB(200, 200, 205),
	Current = Color3.fromRGB(235, 150, 170), Position = Color3.fromRGB(210, 212, 222),
	Velocity = Color3.fromRGB(150, 225, 200),
}

local ESP = {
	Enabled = true, EspDist = math.huge,
	FrustumExpand = 1.30, EdgeMargin = 6,
	BoxFill = 0.9, BoxAlpha = 0.25, BoxStroke = 1, BoxAspect = 0.55, BoxMinH = 8,
	HipFallback = 2, HeadFallback = 2.5,
	HueNear = 0, HueFar = 280, SatNear = 0.85, SatFar = 0.85, ValNear = 1, ValFar = 0.65,
	ColorNear = 100, ColorFar = 1200,
	NameCol = "team", DeadHide = true, DeadFade = 0.45,
	TagRef = 40, TagCurve = 0.5, TagTxtMin = 11, TagTxtMax = 13, TagAlpha = 0.25,
	EdgeAlpha = 0.5, CntAlpha = 0.2, EdgeDot = 8, CntOff = 30, TagGap = 2,
}

local HUD = {
	Size = 17, Alpha = 0.15, GroupPadding = 26, ListPadding = -5,
	Interval = 0.1, SlowInterval = 0.5, MinVelocity = 0.2, FpsWarning = 50,
	ArrowSpeedScale = 0.16, ArrowMinLen = 3, ArrowMaxLen = 8, ArrowHeadOffset = 1.2,
	ArrowAlpha = 0.15, ArrowLineAlpha = 0.35,
}

local SIDES = { "up", "down", "left", "right" }
local DIR_VEC = {
	up = Vector2.new(0, -1), down = Vector2.new(0, 1),
	left = Vector2.new(-1, 0), right = Vector2.new(1, 0),
}

-- Drawing 库探测（原生执行器 API；探测对象用完即删）
local HAS_DRAWING = false
do
	if type(Drawing) == "table" and type(Drawing.new) == "function" then
		local ok, sq = pcall(Drawing.new, "Square")
		if ok and sq then
			pcall(function() sq:Remove() end)
			HAS_DRAWING = true
		end
	end
end

-- ===== 2. GUI 根 =====

local textGui = mk("ScreenGui", {
	Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99995,
}, GuiRoot)

local function label(parent, props)
	local merged = {
		BackgroundTransparency = 1, BorderSizePixel = 0, Font = FONT_REG,
		AnchorPoint = Vector2.new(0.5, 0.5), TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center, Visible = false,
	}
	for k, v in pairs(props or {}) do
		merged[k] = v
	end
	return mk("TextLabel", merged, parent)
end

-- ===== 3. HUD 状态格 =====

local STAT_SPEC = {
	{ key = "ping", col = 1, row = 1, tier = "fast" },
	{ key = "fps", col = 1, row = 2, tier = "fast" },
	{ key = "memory", col = 2, row = 1, tier = "slow" },
	{ key = "time", col = 2, row = 2, tier = "slow" },
	{ key = "max", col = 3, row = 1, tier = "slow" },
	{ key = "current", col = 3, row = 2, tier = "slow" },
	{ key = "position", col = 2, row = 3, tier = "fast" },
}
local stats = {}
for _, spec in ipairs(STAT_SPEC) do
	stats[spec.key] = label(textGui, { Text = "", TextTransparency = HUD.Alpha, TextSize = HUD.Size })
end

local countLabels = {}
for _, dir in ipairs(SIDES) do
	countLabels[dir] = label(textGui, { Font = FONT_BOLD, Text = "", TextTransparency = ESP.CntAlpha, TextSize = 12 })
end
local countPositions = {}

local function layoutStats()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
	local aspect = viewport.X / math.max(viewport.Y, 1)
	local scale = math.clamp(math.min(viewport.X, viewport.Y) / 720, 1, 1.6)
	if aspect > 2.5 or aspect < 1.2 then
		scale = math.clamp(scale, 1, 1.3)
	end
	local size = math.round(HUD.Size * scale)
	local rowH = math.max(size + math.round(HUD.ListPadding * scale), 1)
	local centerX = viewport.X * 0.5
	local spacing = math.round(math.clamp((HUD.GroupPadding + HUD.Size * 2) * scale, 50 * scale, 100 * scale))
	local small = math.round(12 * scale)

	local colX = { centerX - spacing, centerX, centerX + spacing }
	local rowY = {
		size * 0.5,
		rowH + size * 0.5,
		rowH + size + math.round(HUD.ListPadding * scale) + size * 0.5,
	}
	for _, spec in ipairs(STAT_SPEC) do
		local lbl = stats[spec.key]
		lbl.TextSize = size
		lbl.Position = UDim2.fromOffset(colX[spec.col], rowY[spec.row])
	end
	for _, dir in ipairs(SIDES) do
		countLabels[dir].TextSize = small
	end

	local center = viewport * 0.5
	for _, dir in ipairs(SIDES) do
		local v = DIR_VEC[dir]
		local x, y = center.X + v.X * ESP.CntOff, center.Y + v.Y * ESP.CntOff
		countPositions[dir] = Vector2.new(x, y)
		countLabels[dir].Position = UDim2.fromOffset(x, y)
	end
end

local camera = workspace.CurrentCamera
local viewportConn

local function watchViewport()
	if viewportConn then
		pcall(function() viewportConn:Disconnect() end)
		viewportConn = nil
	end
	if camera then
		viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutStats)
	end
	layoutStats()
end

local function refreshCamera()
	camera = workspace.CurrentCamera
	watchViewport()
end
watchViewport()
reg(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(refreshCamera))

-- ===== 4. 角色监听（坐标 / 箭头锚点）=====

local character, hum, rootPart

local function getRoot(c)
	if not c then
		return nil
	end
	return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Root")
end

local function bindCharacter(c)
	character = c
	hum, rootPart = nil, nil
	local function scan()
		if not hum then
			hum = c:FindFirstChildOfClass("Humanoid")
		end
		if not rootPart then
			local r = getRoot(c)
			if r and r:IsA("BasePart") then
				rootPart = r
			end
		end
	end
	scan()
	reg(c.ChildAdded:Connect(scan))
end

reg(player.CharacterAdded:Connect(bindCharacter))
reg(player.CharacterRemoving:Connect(function()
	character = nil
end))
if player.Character then
	bindCharacter(player.Character)
end

-- ===== 5. 玩家计数 =====

local playerCount = #Players:GetPlayers()

local function onPlayerAdded(plr)
	playerCount += 1
	if ESP.Enabled then
		addPlayer(plr)
	end
end

local function onPlayerRemoving(plr)
	playerCount = math.max(0, playerCount - 1)
	removePlayer(plr)
end

-- ===== 6. 速度箭头（原生 GUI：细 Frame + Label）=====

local arrowFrame = mk("Frame", {
	Name = "Arrow", Size = UDim2.fromOffset(4, 4), BackgroundColor3 = COL.Velocity,
	BackgroundTransparency = 1, BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0, 0.5), Visible = false,
}, textGui)
local arrowText = label(textGui, {
	Name = "ArrowText", Font = FONT_REG, TextSize = 12,
	TextColor3 = COL.Velocity, TextTransparency = HUD.ArrowAlpha,
})
local arrowAlpha = 0

local primaryPartCache = setmetatable({}, { __mode = "k" })

local function findPrimaryPartInModel(model)
	if not model or not model:IsA("Model") then
		return nil
	end
	local cached = primaryPartCache[model]
	if cached and cached.Parent then
		return cached
	end
	if model.PrimaryPart then
		primaryPartCache[model] = model.PrimaryPart
		return model.PrimaryPart
	end
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") then
			primaryPartCache[model] = child
			return child
		end
	end
	return nil
end

local function getArrowAnchor()
	local char = player.Character
	local h = char and char:FindFirstChildOfClass("Humanoid")
	if h and h.SeatPart then
		local model = h.SeatPart:FindFirstAncestorWhichIsA("Model")
		local primary = model and findPrimaryPartInModel(model)
		if primary then
			return primary
		end
	end
	local sub = camera and camera.CameraSubject
	if sub and sub:IsA("BasePart") then
		local model = sub:FindFirstAncestorWhichIsA("Model")
		local primary = model and findPrimaryPartInModel(model)
		if primary then
			return primary
		end
	end
	return getRoot(char)
end

local function formatVelocity(velocity, horizontalSpeed)
	local text = ""
	if horizontalSpeed > HUD.MinVelocity then
		text = string.format("%.1f", horizontalSpeed)
	end
	if math.abs(velocity.Y) > HUD.MinVelocity then
		text = text .. (text ~= "" and "  " or "") .. string.format("%.1f", velocity.Y)
	end
	return text
end

local function updateArrow(cam, dt)
	dt = dt or 0
	local anchor = getArrowAnchor()
	local velocity = anchor and anchor.AssemblyLinearVelocity
	local speedSq = velocity and velocity:Dot(velocity) or 0
	local targetAlpha = (speedSq > HUD.MinVelocity * HUD.MinVelocity) and 1 or 0
	arrowAlpha += (targetAlpha - arrowAlpha) * math.clamp(dt * 8, 0, 1)

	if arrowAlpha <= 0.01 or not anchor or not velocity then
		arrowFrame.Visible = false
		arrowText.Visible = false
		return
	end

	local speed = math.sqrt(speedSq)
	local horizontalSpeed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
	arrowText.Text = formatVelocity(velocity, horizontalSpeed)

	local direction = velocity.Unit
	local length = math.clamp(speed * HUD.ArrowSpeedScale, HUD.ArrowMinLen, HUD.ArrowMaxLen)
	local fromWorld = anchor.Position
	if anchor == getRoot(player.Character) then
		local char = player.Character
		local head = char and char:FindFirstChild("Head")
		if head and head.Parent then
			fromWorld = head.Position + Vector3.new(0, head.Size.Y * 0.5 + HUD.ArrowHeadOffset, 0)
		end
	end
	local toWorld = fromWorld + direction * length
	local fromScreen, fromVisible = cam:WorldToViewportPoint(fromWorld)
	local toScreen, toVisible = cam:WorldToViewportPoint(toWorld)

	if not (fromVisible and toVisible) or fromScreen.Z <= 0 or toScreen.Z <= 0 then
		arrowFrame.Visible = false
		arrowText.Visible = false
		return
	end
	local ddx, ddy = toScreen.X - fromScreen.X, toScreen.Y - fromScreen.Y
	if ddx * ddx + ddy * ddy < 16 then
		arrowFrame.Visible = false
		arrowText.Visible = false
		return
	end

	local len = math.sqrt(ddx * ddx + ddy * ddy)
	arrowFrame.Size = UDim2.fromOffset(len, 3)
	arrowFrame.Position = UDim2.fromOffset(fromScreen.X, fromScreen.Y - 1.5)
	arrowFrame.Rotation = math.deg(math.atan2(ddy, ddx))
	arrowFrame.BackgroundTransparency = 1 - (1 - HUD.ArrowLineAlpha) * arrowAlpha
	arrowFrame.Visible = true
	arrowText.TextTransparency = 1 - (1 - HUD.ArrowAlpha) * arrowAlpha
	arrowText.Position = UDim2.fromOffset((fromScreen.X + toScreen.X) * 0.5, (fromScreen.Y + toScreen.Y) * 0.5 - 12)
	arrowText.Visible = true
end

-- ===== 7. ESP（Drawing 直绘；无 Drawing 整体静默关闭）=====

local tracked, trackedN = {}, 0
local espPool = {}
local ESP_POOL_MAX = 32
local fixedNameColor = ESP.NameCol ~= "dist"
local espCounts = { up = 0, down = 0, left = 0, right = 0 }
local espNearest = {
	up = { distance = math.huge, color = nil },
	down = { distance = math.huge, color = nil },
	left = { distance = math.huge, color = nil },
	right = { distance = math.huge, color = nil },
}

local function idColor(plr)
	if ESP.NameCol == "team" and plr.Team then
		return plr.TeamColor.Color
	end
	return Color3.fromHSV((plr.UserId * 0.6180339887) % 1, 0.65, 1)
end

-- 距离→颜色：对数映射，近处变化快、远处收敛
local COLOR_LO = math.log(1 + math.max(ESP.ColorNear, 1))
local COLOR_SPAN = math.max(math.log(1 + math.max(ESP.ColorFar, ESP.ColorNear + 1)) - COLOR_LO, 1e-6)

local function distT(d)
	return math.clamp((math.log(1 + math.max(d, 0)) - COLOR_LO) / COLOR_SPAN, 0, 1)
end

local function distanceColor(t)
	return Color3.fromHSV(
		(ESP.HueNear + (ESP.HueFar - ESP.HueNear) * t) / 360,
		ESP.SatNear + (ESP.SatFar - ESP.SatNear) * t,
		ESP.ValNear + (ESP.ValFar - ESP.ValNear) * t)
end

local function newSquare(filled, thickness)
	local s = Drawing.new("Square")
	s.Filled = filled
	s.Thickness = thickness
	s.Visible = false
	return s
end

local function newVisualEntry(plr, color)
	local e = {
		nameLabel = label(textGui, {
			Font = FONT_BOLD, Text = plr.DisplayName, TextSize = ESP.TagTxtMax,
			TextTransparency = ESP.TagAlpha, TextColor3 = fixedNameColor and idColor(plr) or color,
		}),
		distanceLabel = label(textGui, {
			Font = FONT_BOLD, Text = "", TextSize = math.max(ESP.TagTxtMax - 1, 1),
			TextTransparency = ESP.TagAlpha, TextColor3 = color,
		}),
		conns = {}, character = nil, head = nil, root = nil, humanoid = nil,
		distance = -1, colorBucket = -1, color = color, dead = false,
	}
	if HAS_DRAWING then
		e.boxFill = newSquare(true, 0)
		e.boxOutline = newSquare(false, ESP.BoxStroke)
		e.edge = newSquare(true, 0)
	end
	return e
end

local function resetVisualEntry(e, plr, color)
	e.conns = {}
	e.character, e.head, e.root, e.humanoid = nil, nil, nil, nil
	e.distance, e.colorBucket, e.color, e.dead = -1, -1, color, false
	e.nameLabel.Text = plr.DisplayName
	e.nameLabel.TextSize = ESP.TagTxtMax
	e.nameLabel.TextTransparency = ESP.TagAlpha
	e.nameLabel.TextColor3 = fixedNameColor and idColor(plr) or color
	e.distanceLabel.Text = ""
	e.distanceLabel.TextSize = math.max(ESP.TagTxtMax - 1, 1)
	e.distanceLabel.TextTransparency = ESP.TagAlpha
	e.distanceLabel.TextColor3 = color
	e.nameLabel.Visible = false
	e.distanceLabel.Visible = false
	if e.boxFill then
		e.boxFill.Visible = false
		e.boxOutline.Visible = false
		e.edge.Visible = false
	end
end

local function createPlayerDrawings(plr, color)
	local e = table.remove(espPool)
	if not e then
		return newVisualEntry(plr, color)
	end
	resetVisualEntry(e, plr, color)
	return e
end

local function destroyVisualEntry(e)
	if not e then
		return
	end
	for _, s in ipairs({ e.boxFill, e.boxOutline, e.edge }) do
		if s then
			pcall(function() s:Remove() end)
		end
	end
	e.nameLabel:Destroy()
	e.distanceLabel:Destroy()
end

local function clearEspPool()
	for _, e in ipairs(espPool) do
		destroyVisualEntry(e)
	end
	table.clear(espPool)
end

local function hide(e)
	e.nameLabel.Visible = false
	e.distanceLabel.Visible = false
	if e.boxFill then
		e.boxFill.Visible = false
		e.boxOutline.Visible = false
		e.edge.Visible = false
	end
end

local function refreshNameColor(e, plr)
	if not e or not plr then
		return
	end
	if ESP.NameCol == "team" then
		e.nameLabel.TextColor3 = plr.Team and plr.TeamColor.Color or Color3.new(1, 1, 1)
	elseif ESP.NameCol == "id" then
		e.nameLabel.TextColor3 = idColor(plr)
	end
end

local function removePlayer(plr)
	local e = tracked[plr]
	if not e then
		return
	end
	for _, c in ipairs(e.conns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(e.conns)
	hide(e)
	tracked[plr] = nil
	trackedN -= 1
	if #espPool < ESP_POOL_MAX then
		espPool[#espPool + 1] = e
	else
		destroyVisualEntry(e)
	end
end

local function addPlayer(plr)
	if plr == player or tracked[plr] then
		return
	end
	local e = createPlayerDrawings(plr, distanceColor(0))
	tracked[plr] = e
	trackedN += 1
	refreshNameColor(e, plr)
	if ESP.NameCol == "team" then
		pcall(function()
			table.insert(e.conns, plr:GetPropertyChangedSignal("Team"):Connect(function()
				refreshNameColor(e, plr)
			end))
			table.insert(e.conns, plr:GetPropertyChangedSignal("TeamColor"):Connect(function()
				refreshNameColor(e, plr)
			end))
		end)
	end
end

local espEnabled = false
local function setESP(on)
	espEnabled = on
	if on then
		for _, plr in ipairs(Players:GetPlayers()) do
			addPlayer(plr)
		end
	else
		for plr in pairs(tracked) do
			removePlayer(plr)
		end
		for _, dir in ipairs(SIDES) do
			countLabels[dir].Visible = false
		end
	end
end

local function fadeT(t, fade)
	return math.clamp(t + (fade or 0), 0, 1)
end

-- 视锥外画边缘指示点 + 方位计数；框体用脚→头顶两点投影
local function renderESP(cam)
	if not espEnabled or not HAS_DRAWING then
		return
	end
	local viewport = cam.ViewportSize
	local center = viewport * 0.5
	local camCF = cam.CFrame
	local camPos = camCF.Position
	local camLook = camCF.LookVector
	local edgeMaxX = math.max(center.X - ESP.EdgeMargin, 1)
	local edgeMaxY = math.max(center.Y - ESP.EdgeMargin, 1)

	local fov = cam.FieldOfView or 70
	local vFov = math.rad(math.clamp(fov, 1, 170) * 0.5)
	local aspect = viewport.X / math.max(viewport.Y, 1)
	local hFov = math.atan(math.tan(vFov) * math.max(aspect, 1))
	local halfFov = math.clamp(math.max(vFov, hFov) * ESP.FrustumExpand, 0.01, math.pi * 0.495)
	local fovDot = math.cos(halfFov)

	for _, dir in ipairs(SIDES) do
		espCounts[dir] = 0
		espNearest[dir].distance = math.huge
		espNearest[dir].color = nil
	end

	for plr, e in pairs(tracked) do
		local char = plr.Character
		if e.character ~= char then
			e.character = char
			e.head, e.root, e.humanoid = nil, nil, nil
			e.dead = false
		end
		if char then
			if not e.head or not e.head.Parent then
				e.head = char:FindFirstChild("Head")
			end
			if not e.root or not e.root.Parent then
				e.root = getRoot(char)
			end
			if not e.humanoid or not e.humanoid.Parent then
				e.humanoid = char:FindFirstChildOfClass("Humanoid")
			end
		end

		local head, root = e.head, e.root
		local target = root or head
		local dead = (e.humanoid ~= nil and e.humanoid.Health <= 0) or false

		if not target or not char or not char:IsDescendantOf(workspace)
			or (dead and ESP.DeadHide) then
			hide(e)
			continue
		end

		local targetPos = target.Position
		local dx, dy, dz = camPos.X - targetPos.X, camPos.Y - targetPos.Y, camPos.Z - targetPos.Z
		local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

		if distance > ESP.EspDist then
			hide(e)
			continue
		end

		local t = distT(distance)
		local bucket = math.floor(t * 64)
		local color = e.color
		if e.colorBucket ~= bucket then
			e.colorBucket = bucket
			color = distanceColor(t)
			e.color = color
		end
		local integerDistance = math.floor(distance)
		if e.distance ~= integerDistance then
			e.distance = integerDistance
			e.distanceLabel.Text = tostring(integerDistance)
			local textSize = math.clamp(
				math.round(ESP.TagRef / math.max(distance, 1) ^ ESP.TagCurve * ESP.TagTxtMax),
				ESP.TagTxtMin, ESP.TagTxtMax)
			e.nameLabel.TextSize = textSize
			e.distanceLabel.TextSize = math.max(textSize - 1, 1)
		end
		if not fixedNameColor then
			e.nameLabel.TextColor3 = color
		end

		local fade = dead and ESP.DeadFade or 0
		local boxFillT = fadeT(ESP.BoxFill, fade)
		local boxOutT = fadeT(ESP.BoxAlpha, fade)
		local tagT = fadeT(ESP.TagAlpha, fade)
		local edgeT = fadeT(ESP.EdgeAlpha, fade)

		local inFrustum = (camLook.X * dx + camLook.Y * dy + camLook.Z * dz) / distance > fovDot

		if not inFrustum then
			hide(e)
			-- 边缘指示点
			local topScreen = cam:WorldToViewportPoint(Vector3.new(targetPos.X, targetPos.Y + 2, targetPos.Z))
			local footScreen = cam:WorldToViewportPoint(Vector3.new(targetPos.X, targetPos.Y - 2, targetPos.Z))
			local midX = (topScreen.X + footScreen.X) * 0.5
			local midY = (topScreen.Y + footScreen.Y) * 0.5
			local midZ = (topScreen.Z + footScreen.Z) * 0.5
			local x, y = midX, midY
			if midZ < 0 then
				x = viewport.X - x
				y = viewport.Y - y
			end
			local dirX, dirY = x - center.X, y - center.Y
			local mag = math.sqrt(dirX * dirX + dirY * dirY)
			local side
			if mag > 1e-3 then
				dirX, dirY = dirX / mag, dirY / mag
				if math.abs(dirX) > math.abs(dirY) then
					side = dirX < 0 and "left" or "right"
				else
					side = dirY < 0 and "up" or "down"
				end
			else
				side = "up"
			end
			if not dead then
				espCounts[side] += 1
				if distance < espNearest[side].distance then
					espNearest[side].distance = distance
					espNearest[side].color = color
				end
			end
			local tx = dirX ~= 0 and edgeMaxX / math.abs(dirX) or math.huge
			local ty = dirY ~= 0 and edgeMaxY / math.abs(dirY) or math.huge
			local edgeScale = math.min(tx, ty)
			local edge = e.edge
			edge.Position = Vector2.new(center.X + dirX * edgeScale, center.Y + dirY * edgeScale)
			edge.Size = Vector2.new(ESP.EdgeDot, ESP.EdgeDot)
			edge.Color = color
			edge.Transparency = edgeT
			edge.Visible = true
		else
			local isR6 = e.humanoid and e.humanoid.RigType == Enum.HumanoidRigType.R6
			local rootHalfY = root and (root.Size.Y * 0.5) or 1
			local hip = (e.humanoid and e.humanoid.HipHeight > 0)
				and e.humanoid.HipHeight or (isR6 and 2 or ESP.HipFallback)
			local footY = root and (root.Position.Y - rootHalfY - hip)
				or (targetPos.Y - (ESP.HipFallback + 1))
			local topWorldY = head and (head.Position.Y + head.Size.Y * 0.5)
				or (targetPos.Y + ESP.HeadFallback)
			local topScreen = cam:WorldToViewportPoint(Vector3.new(targetPos.X, topWorldY, targetPos.Z))
			local footScreen = cam:WorldToViewportPoint(Vector3.new(targetPos.X, footY, targetPos.Z))

			local centerX = (topScreen.X + footScreen.X) * 0.5
			local minY = math.min(topScreen.Y, footScreen.Y)
			local bottomY = math.max(topScreen.Y, footScreen.Y)
			local height = math.max(bottomY - minY, ESP.BoxMinH)
			local width = height * ESP.BoxAspect
			local left = centerX - width * 0.5

			local function setBox(s, trans)
				s.Position = Vector2.new(left, minY)
				s.Size = Vector2.new(width, height)
				s.Color = color
				s.Transparency = trans
				s.Visible = true
			end
			setBox(e.boxFill, boxFillT)
			setBox(e.boxOutline, boxOutT)

			e.nameLabel.TextTransparency = tagT
			e.distanceLabel.TextTransparency = tagT
			e.nameLabel.Position = UDim2.fromOffset(centerX, minY - ESP.TagGap - e.nameLabel.TextSize * 0.5)
			e.distanceLabel.Position = UDim2.fromOffset(centerX, bottomY + ESP.TagGap + e.distanceLabel.TextSize * 0.5)
			e.nameLabel.Visible = true
			e.distanceLabel.Visible = true
			e.edge.Visible = false
		end
	end

	for _, dir in ipairs(SIDES) do
		local lbl = countLabels[dir]
		local count = espCounts[dir]
		if count > 0 then
			lbl.Text = tostring(count)
			local near = espNearest[dir]
			if near.color then
				lbl.TextColor3 = near.color
			end
			local pos = countPositions[dir]
			if pos then
				lbl.Position = UDim2.fromOffset(pos.X, pos.Y)
			end
			lbl.Visible = true
		else
			lbl.Visible = false
		end
	end
end

-- ===== 7.5 玩家计数 =====

local playerCount = #Players:GetPlayers()

local function onPlayerAdded(plr)
	playerCount += 1
	if ESP.Enabled then
		addPlayer(plr)
	end
end

local function onPlayerRemoving(plr)
	playerCount = math.max(0, playerCount - 1)
	removePlayer(plr)
end

-- ===== 8. HUD 更新 =====

local function formatTime()
	local now = os.date("*t", os.time())
	local hour = now.hour % 12
	if hour == 0 then
		hour = 12
	end
	local text = hour .. (now.hour >= 12 and "p" or "a")
	if now.min > 0 then
		text = text .. tostring(now.min)
	end
	if now.sec > 0 then
		text = text .. "," .. tostring(now.sec)
	end
	return text
end

local lastFps = 0

local function updateStat(key)
	local lbl = stats[key]
	local text = ""
	local col = COL.Max
	if key == "ping" then
		local ok, v = pcall(function() return player:GetNetworkPing() end)
		if ok and typeof(v) == "number" and v == v then
			text = tostring(math.floor(v * 1000))
		end
		col = COL.Ping
	elseif key == "fps" then
		text = tostring(lastFps)
		col = lastFps >= HUD.FpsWarning and COL.Fps or COL.FpsLow
	elseif key == "memory" then
		local ok, v = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
		if ok and typeof(v) == "number" then
			text = tostring(math.floor(v))
		end
		col = COL.Memory
	elseif key == "time" then
		text = formatTime()
		col = COL.Time
	elseif key == "max" then
		text = tostring(Players.MaxPlayers)
		col = COL.Max
	elseif key == "current" then
		text = tostring(playerCount)
		col = COL.Current
	elseif key == "position" then
		local root = getRoot(character)
		if root then
			text = string.format("%.1f %.1f %.1f", root.Position.X, root.Position.Y, root.Position.Z)
		end
		col = COL.Position
	end
	lbl.Text = text
	lbl.TextColor3 = col
	lbl.Visible = text ~= ""
end

local function updateTier(tier)
	for _, spec in ipairs(STAT_SPEC) do
		if spec.tier == tier then
			updateStat(spec.key)
		end
	end
end

-- ===== 9. 主渲染循环（相机之后的 RenderStep，失败退 PreRender）=====

local dtState = { last = os.clock() }
local function dtTracker(maxDt)
	return function(step)
		local now = os.clock()
		local dt = step
		if type(dt) ~= "number" or dt ~= dt or dt <= 0 then
			dt = now - dtState.last
		end
		dtState.last = now
		return math.clamp(dt, 0, maxDt)
	end
end
local frameDt = dtTracker(0.1)
local frameCount = 0
local fpsWindowStart = os.clock()
local slowWindowStart = os.clock()

local STEP_NAME = "SB_HUD_Draw"
local function safeFrame(step)
	local now = os.clock()
	local deltaTime = frameDt(step)
	if camera then
		updateArrow(camera, deltaTime)
		renderESP(camera)
	end
	frameCount += 1
	local fpsElapsed = now - fpsWindowStart
	if fpsElapsed >= HUD.Interval then
		lastFps = math.round(frameCount / math.max(fpsElapsed, 1e-6))
		frameCount = 0
		fpsWindowStart = now
		updateTier("fast")
	end
	if now - slowWindowStart >= HUD.SlowInterval then
		slowWindowStart = now
		updateTier("slow")
	end
end

local bound = pcall(function()
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, safeFrame)
end)
if not bound then
	reg(RunService.PreRender:Connect(safeFrame))
end

-- ===== 10. 启动 / 卸载 =====

reg(Players.PlayerAdded:Connect(onPlayerAdded))
reg(Players.PlayerRemoving:Connect(onPlayerRemoving))
if ESP.Enabled then
	setESP(true)
end

local DBG = rawget(_G, "SB_DEBUG") or {}
rawset(_G, "SB_DEBUG", DBG)
DBG[NAME] = function()
	local lines = {
		"fps: " .. tostring(lastFps),
		"drawing: " .. (HAS_DRAWING and "yes" or "no"),
		"esp: " .. tostring(espEnabled),
		"tracked: " .. tostring(trackedN) .. " pooled: " .. tostring(#espPool),
		"players: " .. tostring(playerCount),
	}
	return "=== HUD ===\n" .. table.concat(lines, "\n") .. "\n=== END ==="
end

local function destroy()
	if bound then
		pcall(function() RunService:UnbindFromRenderStep(STEP_NAME) end)
		bound = false
	end
	if viewportConn then
		pcall(function() viewportConn:Disconnect() end)
		viewportConn = nil
	end
	setESP(false)
	clearEspPool()
	arrowFrame:Destroy()
	arrowText:Destroy()
	for _, dir in ipairs(SIDES) do
		countLabels[dir]:Destroy()
	end
	for _, spec in ipairs(STAT_SPEC) do
		stats[spec.key]:Destroy()
	end
	textGui:Destroy()
	for _, c in ipairs(conns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(conns)
	DBG[NAME] = nil
	rawset(_G, "SB_" .. NAME, nil)
end
rawset(_G, "SB_" .. NAME, destroy)

print("[hud] ready (Drawing=" .. (HAS_DRAWING and "yes" or "no") .. ")")
