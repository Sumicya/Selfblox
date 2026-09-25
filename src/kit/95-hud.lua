-- kit / 95-hud — HUD 状态格、速度箭头、视口布局（含 ESP 共享配置）

-- 15. HUD 业务层

local CORE = K.mod("KIT")
local bag, reg = CORE.bag, CORE.reg

local textGui = K.mk("ScreenGui", {
	Name = NAME .. "Text", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99995,
}, GuiRoot)

local FONT_BOLD_F = K.font(true)
local FONT_REG_F = K.font(false)

-- ESP / HUD 共享显示配置（ESP 实体渲染在 99-esp）
local ESP = {
	DefaultOn = true,
	EspDist = math.huge,
	UnlimitedRender = true,
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
	Size = 17, Alpha = 0.15, GroupPadding = 26, ListPadding = 6, TopOffset = 0,
	Interval = 0.1, SlowInterval = 0.5, MinVelocity = 0.2, FpsWarning = 50,
	ArrowSpeedScale = 0.16, ArrowMinLen = 3, ArrowMaxLen = 8, ArrowHeadOffset = 1.2,
	ArrowAlpha = 0.15, ArrowLineAlpha = 0.35,
}

local COL = {
	Ping = Color3.fromRGB(137, 220, 235), Fps = Color3.fromRGB(170, 230, 150),
	FpsLow = Color3.fromRGB(235, 120, 120), Memory = Color3.fromRGB(200, 180, 235),
	Time = Color3.fromRGB(235, 200, 150), Max = Color3.fromRGB(200, 200, 205),
	Current = Color3.fromRGB(235, 150, 170), Position = Color3.fromRGB(210, 212, 222),
	Velocity = Color3.fromRGB(150, 225, 200),
}

local SIDES = {"up", "down", "left", "right"}
local DIR_VEC = {
	up = Vector2.new(0, -1), down = Vector2.new(0, 1),
	left = Vector2.new(-1, 0), right = Vector2.new(1, 0),
}

-- ESP 开关与实体管理的前向声明（定义在 99-esp，事件回调先挂上）
local enabled = false
local addPlayer, removePlayer

local arrowLine = Line.new(textGui, COL.Velocity, 3, HUD.ArrowLineAlpha)
local arrowText = Label.new(textGui, FONT_REG_F, HUD.ArrowAlpha, 12, COL.Velocity)
local arrowAlpha = 0

local countLabels = {}
for _, dir in ipairs(SIDES) do
	countLabels[dir] = Label.new(textGui, FONT_BOLD_F, ESP.CntAlpha, 12)
end
local countPositions = {}

local STAT_SPEC = {
	{key = "ping", col = 1, row = 1, tier = "fast"},
	{key = "fps", col = 1, row = 2, tier = "fast"},
	{key = "memory", col = 2, row = 1, tier = "slow"},
	{key = "time", col = 2, row = 2, tier = "slow"},
	{key = "max", col = 3, row = 1, tier = "slow"},
	{key = "current", col = 3, row = 2, tier = "slow"},
	{key = "position", col = 2, row = 3, tier = "fast"},
}
local stats = {}
for _, spec in ipairs(STAT_SPEC) do
	stats[spec.key] = Label.new(textGui, FONT_REG_F, HUD.Alpha)
end

local function layoutStats()
	local viewport = K.vp()
	local aspect = viewport.X / math.max(viewport.Y, 1)
	local scale = math.clamp(math.min(viewport.X, viewport.Y) / 720, 1, 1.6)
	if aspect > 2.5 or aspect < 1.2 then scale = math.clamp(scale, 1, 1.3) end
	local size = math.round(HUD.Size * scale)
	local rowH = math.max(size + math.round(HUD.ListPadding * scale), 1)
	local topY = math.round(HUD.TopOffset * scale)
	local centerX = viewport.X * 0.5
	local spacing = math.round(math.clamp(
		(HUD.GroupPadding + HUD.Size * 2) * scale, 50 * scale, 100 * scale))
	local small = math.round(12 * scale)

	local colX = {centerX - spacing, centerX, centerX + spacing}
	local rowY = {
		topY + size * 0.5,
		topY + rowH + size * 0.5,
		topY + rowH + size + math.round(HUD.ListPadding * scale) + size * 0.5,
	}
	for _, spec in ipairs(STAT_SPEC) do
		local label = stats[spec.key]
		label:setSize(size)
		label:setPos(colX[spec.col], rowY[spec.row])
	end
	for _, dir in ipairs(SIDES) do countLabels[dir]:setSize(small) end
	arrowText:setSize(small)

	local center = viewport * 0.5
	for _, dir in ipairs(SIDES) do
		local v = DIR_VEC[dir]
		local x = center.X + v.X * ESP.CntOff
		local y = center.Y + v.Y * ESP.CntOff
		countPositions[dir] = Vector2.new(x, y)
		countLabels[dir]:setPos(x, y)
	end
end

local camera = workspace.CurrentCamera
local viewportConnection = nil

local function watchViewport()
	if viewportConnection then
		pcall(function() viewportConnection:Disconnect() end)
		viewportConnection = nil
	end
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutStats)
	end
	layoutStats()
end

local function refreshCamera()
	camera = workspace.CurrentCamera
	watchViewport()
end
watchViewport()
reg(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(refreshCamera))

local playerCount = #Players:GetPlayers()

local function onPlayerAdded(plr)
	playerCount += 1
	if enabled then addPlayer(plr) end
end

local function onPlayerRemoving(plr)
	playerCount = math.max(0, playerCount - 1)
	removePlayer(plr)
end
reg(Players.PlayerAdded:Connect(onPlayerAdded))
reg(Players.PlayerRemoving:Connect(onPlayerRemoving))


-- 18. HUD 更新

local function formatTime()
	local now = os.date("*t", os.time())
	local hour = now.hour % 12
	if hour == 0 then hour = 12 end
	local period = now.hour >= 12 and "p" or "a"
	local text = hour .. period
	if now.min > 0 then text = text .. tostring(now.min) end
	if now.sec > 0 then text = text .. "," .. tostring(now.sec) end
	return text
end

local function formatVelocity(velocity, horizontalSpeed)
	local text = ""
	if horizontalSpeed > HUD.MinVelocity then text = string.format("%.1f", horizontalSpeed) end
	if math.abs(velocity.Y) > HUD.MinVelocity then
		text = text .. (text ~= "" and "  " or "") .. string.format("%.1f", velocity.Y)
	end
	return text
end

local lastFps = 0

local UPDATERS = {}
function UPDATERS.ping(label)
	local ok, v = pcall(function() return player:GetNetworkPing() end)
	if ok and typeof(v) == "number" and v == v then
		label:setText(tostring(math.floor(v * 1000)))
	else
		label:setText("")
	end
	label:setColor(COL.Ping)
end
function UPDATERS.fps(label)
	label:setText(tostring(lastFps))
	label:setColor(lastFps >= HUD.FpsWarning and COL.Fps or COL.FpsLow)
end
function UPDATERS.memory(label)
	local ok, v = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
	if ok and typeof(v) == "number" then
		label:setText(tostring(math.floor(v)))
	else
		label:setText("")
	end
	label:setColor(COL.Memory)
end
function UPDATERS.time(label)
	label:setText(formatTime())
	label:setColor(COL.Time)
end
UPDATERS.max = function(label)
	label:setText(tostring(Players.MaxPlayers))
	label:setColor(COL.Max)
end
UPDATERS.current = function(label)
	label:setText(tostring(playerCount))
	label:setColor(COL.Current)
end
function UPDATERS.position(label)
	local root = K.getRoot(player.Character)
	if root then
		label:setText(string.format("%.1f %.1f %.1f", root.Position.X, root.Position.Y, root.Position.Z))
	else
		label:setText("")
	end
	label:setColor(COL.Position)
end

local function updateTier(tier)
	for _, spec in ipairs(STAT_SPEC) do
		if spec.tier == tier then
			local label = stats[spec.key]
			local fn = UPDATERS[spec.key]
			if fn then fn(label) end
			label:hideIfEmpty()
		end
	end
end


-- 19. 速度箭头
-- 锚点优先级：乘坐的载具 → 相机主体载具 → 角色 Root；头部上方起笔

local primaryPartCache = setmetatable({}, {__mode = "k"})

local function findPrimaryPartInModel(model)
	if not model or not model:IsA("Model") then return nil end
	local cached = primaryPartCache[model]
	if cached and cached.Parent then return cached end
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

local function getArrowAnchor(cam)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		local model = hum.SeatPart:FindFirstAncestorWhichIsA("Model")
		local primary = model and findPrimaryPartInModel(model)
		if primary then return primary end
	end
	local sub = cam and cam.CameraSubject
	if sub and sub:IsA("BasePart") then
		local model = sub:FindFirstAncestorWhichIsA("Model")
		local primary = model and findPrimaryPartInModel(model)
		if primary then return primary end
	end
	return K.getRoot(char)
end

local function updateArrow(cam, dt)
	dt = dt or 0
	local anchor = getArrowAnchor(cam)
	local velocity = anchor and anchor.AssemblyLinearVelocity
	local speedSq = velocity and velocity:Dot(velocity) or 0
	local targetAlpha = (speedSq > HUD.MinVelocity * HUD.MinVelocity) and 1 or 0
	arrowAlpha += (targetAlpha - arrowAlpha) * math.clamp(dt * 8, 0, 1)

	if arrowAlpha <= 0.01 or not anchor or not velocity then
		arrowLine:setVisible(false)
		arrowText:setVisible(false)
		return
	end

	local speed = math.sqrt(speedSq)
	local horizontalSpeed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
	arrowText:setText(formatVelocity(velocity, horizontalSpeed))

	local direction = velocity.Unit
	local length = math.clamp(speed * HUD.ArrowSpeedScale, HUD.ArrowMinLen, HUD.ArrowMaxLen)
	local fromWorld = anchor.Position
	if anchor == K.getRoot(player.Character) then
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
		arrowLine:setVisible(false)
		arrowText:setVisible(false)
		return
	end
	local ddx, ddy = toScreen.X - fromScreen.X, toScreen.Y - fromScreen.Y
	if ddx * ddx + ddy * ddy < 16 then
		arrowLine:setVisible(false)
		arrowText:setVisible(false)
		return
	end

	arrowLine:set(fromScreen.X, fromScreen.Y, toScreen.X, toScreen.Y, COL.Velocity,
		fadeTo(HUD.ArrowLineAlpha, arrowAlpha))
	arrowLine:setVisible(true)
	arrowText:setTransparency(fadeTo(HUD.ArrowAlpha, arrowAlpha))
	arrowText:setPos((fromScreen.X + toScreen.X) * 0.5, (fromScreen.Y + toScreen.Y) * 0.5 - 12)
	arrowText:setVisible(true)
end
