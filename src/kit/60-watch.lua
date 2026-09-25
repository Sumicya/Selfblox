-- kit / 60-watch — 全局上下文状态机 + 角色生命周期监听

-- 9. 上下文状态机
-- context.changed 广播 (key, value)；seat/seated/vehicleModel 由 watchCharacter 维护

K.context = {character = nil, humanoid = nil, root = nil, seated = false, seat = nil, vehicleModel = nil}
local ctxEvent = Instance.new("BindableEvent")
K.context.changed = ctxEvent.Event

function K.context.set(key, value)
	if K.context[key] ~= value then
		K.context[key] = value
		ctxEvent:Fire(key, value)
	end
end

-- 10. 角色监听
-- ready(character, humanoid, root) / removed(old) / waiting(reason)
-- 返回手动重绑函数；rootNames / requireHumanoid / requireRoot 可配

function K.watchCharacter(bag, callbacks, opts)
	callbacks = callbacks or {}
	opts = opts or {}
	local onReady, onRemoved, onWaiting = callbacks.ready, callbacks.removed, callbacks.waiting
	local requireRoot = opts.requireRoot ~= false
	local rootNames = opts.rootNames
	local version = 0
	local waitConn = nil
	local current = nil

	local function clearWait()
		if waitConn then
			pcall(function() waitConn:Disconnect() end)
			waitConn = nil
		end
	end

	local function matchRootName(child)
		if rootNames and #rootNames > 0 then
			for _, n in ipairs(rootNames) do
				if child.Name == n then return true end
			end
			return false
		end
		return child.Name == "HumanoidRootPart" or child.Name == "Root"
	end

	local function hookHumanoid(humanoid)
		if not humanoid then return end
		K.context.set("humanoid", humanoid)
		bag.reg(humanoid.Seated:Connect(function(active, seatPart)
			K.context.set("seated", active)
			K.context.set("seat", active and seatPart or nil)
			if active and seatPart then
				K.context.set("vehicleModel", seatPart:FindFirstAncestorWhichIsA("Model"))
			else
				K.context.set("vehicleModel", nil)
			end
		end))
	end

	local function checkRoot(character, humanoid, v)
		if not bag.alive() or v ~= version then return end
		local root = nil
		if rootNames and #rootNames > 0 then
			for _, n in ipairs(rootNames) do
				local r = character:FindFirstChild(n)
				if r and r:IsA("BasePart") then
					root = r
					break
				end
			end
		else
			root = K.getRoot(character)
		end
		if root or not requireRoot then
			if onReady then onReady(character, humanoid, root) end
			return
		end
		if onWaiting then onWaiting("root") end
		clearWait()
		waitConn = character.ChildAdded:Connect(function(child)
			if not child:IsA("BasePart") or not matchRootName(child) then return end
			clearWait()
			if bag.alive() and v == version and onReady then onReady(character, humanoid, child) end
		end)
	end

	local function bind(character)
		version += 1
		local v = version
		clearWait()
		current = character
		K.context.set("character", character)
		if not bag.alive() then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid or opts.requireHumanoid == false then
			hookHumanoid(humanoid)
			if not humanoid then
				bag.reg(character.ChildAdded:Connect(function(child)
					if child:IsA("Humanoid") then hookHumanoid(child) end
				end))
			end
			checkRoot(character, humanoid, v)
		else
			if onWaiting then onWaiting("humanoid") end
			waitConn = character.ChildAdded:Connect(function(child)
				if not child:IsA("Humanoid") then return end
				clearWait()
				if bag.alive() and v == version then
					hookHumanoid(child)
					checkRoot(character, child, v)
				end
			end)
		end
	end

	bag.reg(player.CharacterAdded:Connect(bind))
	bag.reg(player.CharacterRemoving:Connect(function(old)
		if old ~= current then return end
		version += 1
		clearWait()
		current = nil
		K.context.set("character", nil)
		K.context.set("humanoid", nil)
		K.context.set("root", nil)
		K.context.set("seated", false)
		K.context.set("seat", nil)
		K.context.set("vehicleModel", nil)
		if onRemoved then onRemoved(old) end
		if onWaiting then onWaiting("character") end
	end))
	if player.Character then
		bind(player.Character)
	elseif onWaiting then
		onWaiting("character")
	end
	return function()
		if player.Character then bind(player.Character) end
	end
end
