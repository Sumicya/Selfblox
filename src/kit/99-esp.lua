-- kit / 99-esp — ESP 实体池、屏幕渲染（箱体/边缘点/计数）、主渲染循环、卸载

-- 16. ESP 实体管理

local tracked, trackedN, espPool = {}, 0, {}
local ESP_POOL_MAX = 32
local fixedNameColor = ESP.NameCol ~= "dist"
local espCounts = {up = 0, down = 0, left = 0, right = 0}
local espNearest = {up = {}, down = {}, left = {}, right = {}}

local function idColor(plr)
	if ESP.NameCol == "team" and plr.Team then return plr.TeamColor.Color end
	return Color3.fromHSV((plr.UserId * 0.6180339887) % 1, 0.65, 1)
end

-- 距离→颜色用对数映射，近处变化快、远处收敛
local COLOR_LO = math.log(1 + math.max(ESP.ColorNear, 1))
local COLOR_SPAN = math.max(
	math.log(1 + math.max(ESP.ColorFar, ESP.ColorNear + 1)) - COLOR_LO, 1e-6)

local function distT(d)
	return math.clamp((math.log(1 + math.max(d, 0)) - COLOR_LO) / COLOR_SPAN, 0, 1)
end

local function distanceColor(t)
	return Color3.fromHSV(
		(ESP.HueNear + (ESP.HueFar - ESP.HueNear) * t) / 360,
		ESP.SatNear + (ESP.SatFar - ESP.SatNear) * t,
		ESP.ValNear + (ESP.ValFar - ESP.ValNear) * t)
end

local function makeEdge(color)
	local sq = Square.new(textGui, color, true, 0, ESP.EdgeAlpha)
	if sq.kind == "frame" then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = sq.obj
	end
	return sq
end

local function refreshNameColor(entry, plr)
	if not entry or not entry.nameLabel or not plr then return end
	if ESP.NameCol == "team" then
		entry.nameLabel:setColor(plr.Team and plr.TeamColor.Color or Color3.new(1, 1, 1))
	elseif ESP.NameCol == "id" then
		entry.nameLabel:setColor(idColor(plr))
	end
end

local function newVisualEntry(plr, color)
	return {
		boxFill = Square.new(textGui, color, true, 0, ESP.BoxFill),
		boxOutline = Square.new(textGui, color, false, ESP.BoxStroke, ESP.BoxAlpha),
		nameLabel = Label.new(textGui, FONT_BOLD_F, ESP.TagAlpha, ESP.TagTxtMax,
			fixedNameColor and idColor(plr) or color),
		distanceLabel = Label.new(textGui, FONT_BOLD_F, ESP.TagAlpha,
			math.max(ESP.TagTxtMax - 1, 1), color),
		edge = makeEdge(color),
		conns = {},
		character = nil, head = nil, root = nil, humanoid = nil,
		distance = -1, colorBucket = -1, color = color, dead = false,
	}
end

local function resetVisualEntry(entry, plr, color)
	entry.conns = {}
	entry.character, entry.head, entry.root, entry.humanoid = nil, nil, nil, nil
	entry.distance, entry.colorBucket, entry.color, entry.dead = -1, -1, color, false
	entry.boxFill:set(0, 0, 1, 1, color, ESP.BoxFill)
	entry.boxOutline:set(0, 0, 1, 1, color, ESP.BoxAlpha)
	entry.edge:set(0, 0, ESP.EdgeDot, ESP.EdgeDot, color, ESP.EdgeAlpha)
	entry.nameLabel:setText(plr.DisplayName)
	entry.nameLabel:setSize(ESP.TagTxtMax)
	entry.nameLabel:setTransparency(ESP.TagAlpha)
	entry.nameLabel:setColor(fixedNameColor and idColor(plr) or color)
	entry.distanceLabel:setText("")
	entry.distanceLabel:setSize(math.max(ESP.TagTxtMax - 1, 1))
	entry.distanceLabel:setTransparency(ESP.TagAlpha)
	entry.distanceLabel:setColor(color)
	entry.boxFill:setVisible(false)
	entry.boxOutline:setVisible(false)
	entry.nameLabel:setVisible(false)
	entry.distanceLabel:setVisible(false)
	entry.edge:setVisible(false)
end

local function createPlayerDrawings(plr, color)
	local entry = table.remove(espPool)
	if not entry then return newVisualEntry(plr, color) end
	resetVisualEntry(entry, plr, color)
	return entry
end

local function destroyVisualEntry(entry)
	if not entry then return end
	entry.boxFill:destroy()
	entry.boxOutline:destroy()
	entry.edge:destroy()
	entry.nameLabel:destroy()
	entry.distanceLabel:destroy()
end

local function clearEspPool()
	for _, entry in ipairs(espPool) do destroyVisualEntry(entry) end
	table.clear(espPool)
end

local function hide(entry)
	entry.boxFill:setVisible(false)
	entry.boxOutline:setVisible(false)
	entry.nameLabel:setVisible(false)
	entry.distanceLabel:setVisible(false)
	entry.edge:setVisible(false)
end

function removePlayer(plr)
	local entry = tracked[plr]
	if not entry then return end
	for _, conn in ipairs(entry.conns) do pcall(function() conn:Disconnect() end) end
	table.clear(entry.conns)
	hide(entry)
	tracked[plr] = nil
	trackedN -= 1
	if #espPool < ESP_POOL_MAX then
		espPool[#espPool + 1] = entry
	else
		destroyVisualEntry(entry)
	end
end

function addPlayer(plr)
	if plr == player or tracked[plr] then return end
	local entry = createPlayerDrawings(plr, distanceColor(0))
	tracked[plr] = entry
	trackedN += 1
	refreshNameColor(entry, plr)
	if ESP.NameCol == "team" then
		pcall(function()
			table.insert(entry.conns, plr:GetPropertyChangedSignal("Team"):Connect(function()
				refreshNameColor(entry, plr)
			end))
		end)
		pcall(function()
			table.insert(entry.conns, plr:GetPropertyChangedSignal("TeamColor"):Connect(function()
				refreshNameColor(entry, plr)
			end))
		end)
	end
end

local function setESP(on)
	enabled = on
	if on then
		for _, plr in ipairs(Players:GetPlayers()) do addPlayer(plr) end
	else
		for plr in pairs(tracked) do removePlayer(plr) end
		for _, dir in ipairs(SIDES) do countLabels[dir]:setVisible(false) end
	end
end


-- 17. ESP 渲染
-- 视锥外的玩家画边缘指示点并计入方位计数；框体用脚→头顶两点投影

local function renderESP(cam, dt)
	if not enabled then return end
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

	for plr, entry in pairs(tracked) do
		local character = plr.Character
		if entry.character ~= character then
			entry.character = character
			entry.head, entry.root, entry.humanoid = nil, nil, nil
			entry.dead = false
		end
		if character then
			if not entry.head or not entry.head.Parent then
				entry.head = character:FindFirstChild("Head")
			end
			if not entry.root or not entry.root.Parent then
				entry.root = K.getRoot(character)
			end
			if not entry.humanoid or not entry.humanoid.Parent then
				entry.humanoid = character:FindFirstChildOfClass("Humanoid")
			end
		end

		local head, root = entry.head, entry.root
		local target = root or head
		local dead = (entry.humanoid ~= nil and entry.humanoid.Health <= 0) or false

		if not target or not character or not character:IsDescendantOf(workspace)
			or (dead and ESP.DeadHide) then
			hide(entry)
		else
			local targetPos = target.Position
			local dx, dy, dz = camPos.X - targetPos.X, camPos.Y - targetPos.Y, camPos.Z - targetPos.Z
			local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

			if distance > ESP.EspDist then
				hide(entry)
			else
				local t = distT(distance)
				local bucket = math.floor(t * 64)
				local color = entry.color
				if entry.colorBucket ~= bucket then
					entry.colorBucket = bucket
					color = distanceColor(t)
					entry.color = color
				end
				local integerDistance = math.floor(distance)
				if entry.distance ~= integerDistance then
					entry.distance = integerDistance
					entry.distanceLabel:setText(tostring(integerDistance))
					local textSize = math.clamp(
						math.round(ESP.TagTxtMax * (ESP.TagRef / math.max(distance, 1)) ^ ESP.TagCurve),
						ESP.TagTxtMin, ESP.TagTxtMax)
					entry.nameLabel:setSize(textSize)
					entry.distanceLabel:setSize(math.max(textSize - 1, 1))
				end
				if not fixedNameColor then entry.nameLabel:setColor(color) end

				local fade = dead and ESP.DeadFade or 0
				local boxFillT = fadeT(ESP.BoxFill, fade)
				local boxOutT = fadeT(ESP.BoxAlpha, fade)
				local tagT = fadeT(ESP.TagAlpha, fade)
				local edgeT = fadeT(ESP.EdgeAlpha, fade)

				local inFrustum = (camLook.X * dx + camLook.Y * dy + camLook.Z * dz) / distance > fovDot

				if not inFrustum then
					entry.boxFill:setVisible(false)
					entry.boxOutline:setVisible(false)
					entry.nameLabel:setVisible(false)
					entry.distanceLabel:setVisible(false)

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
					entry.edge:set(center.X + dirX * edgeScale, center.Y + dirY * edgeScale,
						ESP.EdgeDot, ESP.EdgeDot, color, edgeT)
					entry.edge:setVisible(true)
				else
					local isR6 = entry.humanoid and entry.humanoid.RigType == Enum.HumanoidRigType.R6
					local rootHalfY = root and (root.Size.Y * 0.5) or 1
					local hip = (entry.humanoid and entry.humanoid.HipHeight > 0)
						and entry.humanoid.HipHeight or (isR6 and 2 or ESP.HipFallback)
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

					entry.boxFill:set(left, minY, width, height, color, boxFillT)
					entry.boxOutline:set(left, minY, width, height, color, boxOutT)
					entry.nameLabel:setTransparency(tagT)
					entry.distanceLabel:setTransparency(tagT)
					entry.nameLabel:setPos(centerX, minY - ESP.TagGap - entry.nameLabel.obj.TextSize * 0.5)
					entry.distanceLabel:setPos(centerX, bottomY + ESP.TagGap + entry.distanceLabel.obj.TextSize * 0.5)
					entry.boxFill:setVisible(true)
					entry.boxOutline:setVisible(true)
					entry.nameLabel:setVisible(true)
					entry.distanceLabel:setVisible(true)
					entry.edge:setVisible(false)
				end
			end
		end
	end

	for _, dir in ipairs(SIDES) do
		local label = countLabels[dir]
		local count = espCounts[dir]
		if count > 0 then
			label:setText(tostring(count))
			local near = espNearest[dir]
			if near.color then label:setColor(near.color) end
			local pos = countPositions[dir]
			if pos then label:setPos(pos.X, pos.Y) end
			label:setVisible(true)
		else
			label:setVisible(false)
		end
	end
end


-- 20. 主渲染循环

if ESP.DefaultOn then setESP(true) end

local frameDt = K.dtTracker(0.1)
local frameCount = 0
local fpsWindowStart = os.clock()
local slowWindowStart = os.clock()
local espElapsed = 0
local renderBound = false
local RENDER_STEP_NAME = NAME .. "_Drawing"

local function safeFrame(step)
	local now = os.clock()
	local deltaTime = frameDt(step)
	if not bag.alive() then return end
	K.heartbeat()

	local cam = camera
	if cam then
		updateArrow(cam, deltaTime)
		if ESP.UnlimitedRender then
			renderESP(cam, deltaTime)
			espElapsed = 0
		else
			local espRate = K.env.isMobile and 30 or 60
			espElapsed += deltaTime
			if espElapsed >= 1 / math.max(espRate, 1) then
				renderESP(cam, espElapsed)
				espElapsed = 0
			end
		end
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

-- 优先相机之后的 RenderStep；失败退化为 PreRender 信号
local bindOk = pcall(function()
	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, safeFrame)
end)
if bindOk then
	renderBound = true
else
	local okRender, renderConn = pcall(function()
		return RunService.PreRender:Connect(safeFrame)
	end)
	if okRender and renderConn then
		reg(renderConn)
	end
end


-- 21. 调试

CORE.debug(function()
	local lines = {}
	local function log(msg) lines[#lines + 1] = tostring(msg) end
	log("alive: " .. tostring(bag.alive()))
	log("fps: " .. tostring(lastFps))
	log("renderBound: " .. tostring(renderBound))
	log("drawingBackend: " .. (HAS_DRAWING and "Drawing" or "Frame"))
	log("esp: " .. tostring(enabled))
	log("tracked: " .. tostring(trackedN))
	log("pooled: " .. tostring(#espPool))
	log("espRenderHz: " .. (ESP.UnlimitedRender and "inf" or (K.env.isMobile and 30 or 60)))
	log("playerCount: " .. tostring(playerCount))
	log("viewport: " .. tostring(K.vp()))
	log("colorRange: " .. ESP.ColorNear .. "~" .. ESP.ColorFar)
	log("env.isMobile: " .. tostring(K.env.isMobile))
	log("kitErrors: " .. tostring(#K.errors))
	return K.debugDump(NAME, lines)
end)


-- 22. 清理

CORE.done(function()
	if renderBound then
		pcall(function() RunService:UnbindFromRenderStep(RENDER_STEP_NAME) end)
		renderBound = false
	end
	if viewportConnection then
		pcall(function() viewportConnection:Disconnect() end)
		viewportConnection = nil
	end
	setESP(false)
	clearEspPool()
	arrowLine:destroy()
	arrowText:destroy()
	for _, dir in ipairs(SIDES) do
		if countLabels[dir] then countLabels[dir]:destroy() end
		countLabels[dir] = nil
	end
	for _, spec in ipairs(STAT_SPEC) do
		local label = stats[spec.key]
		if label then label:destroy() end
		stats[spec.key] = nil
	end
	if textGui then
		pcall(function() textGui:Destroy() end)
		textGui = nil
	end
end)

print("[KIT] core + hud + esp ready (v" .. tostring(VERSION) .. ")")
