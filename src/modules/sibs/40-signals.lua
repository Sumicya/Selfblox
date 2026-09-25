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
