-- kit / 50-force — 物理约束工厂（VectorForce / LinearVelocity / AngularVelocity）
-- forceRegistry 是弱键表，但 h.part = part 形成 key 到 value 再到 key 的环，
-- 实际回收依赖 part.Destroying，不要移除该连接

-- 8. 力约束工厂

K.force = {}
local forceRegistry = setmetatable({}, {__mode = "k"})

local function forceTeardown(part, name)
	local reg = forceRegistry[part]
	if not reg then return end
	local h = reg[name]
	if not h then return end
	reg[name] = nil
	if h.conn then pcall(function() h.conn:Disconnect() end) end
	pcall(function() h.instance:Destroy() end)
	pcall(function() h.attachment:Destroy() end)
end

local function makeForce(part, name, className, applyProps)
	if not part or not part.Parent then return nil end
	forceTeardown(part, name)
	local att = Instance.new("Attachment")
	att.Name = name .. "_Att"
	local inst = Instance.new(className)
	inst.Name = name
	inst.Attachment0 = att
	inst.RelativeTo = Enum.ActuatorRelativeTo.World
	if applyProps then pcall(applyProps, inst) end
	local h = {part = part, name = name, instance = inst, attachment = att}
	h.conn = part.Destroying:Connect(function() forceTeardown(part, name) end)
	att.Parent = part
	inst.Parent = part
	local reg = forceRegistry[part]
	if not reg then
		reg = {}
		forceRegistry[part] = reg
	end
	reg[name] = h
	function h.destroy() forceTeardown(part, name) end
	function h.alive() return inst.Parent == part end
	return h
end

function K.force.vector(part, name)
	local h = makeForce(part, name, "VectorForce", function(f)
		f.Force = Vector3.zero
		f.ApplyAtCenterOfMass = true
	end)
	if not h then return nil end
	function h.set(vec) pcall(function() h.instance.Force = vec end) end
	return h
end

function K.force.linear(part, name)
	local h = makeForce(part, name, "LinearVelocity", function(f)
		f.VectorVelocity = Vector3.zero
		f.MaxForce = math.huge
	end)
	if not h then return nil end
	function h.set(vec) pcall(function() h.instance.VectorVelocity = vec end) end
	return h
end

function K.force.angular(part, name)
	local h = makeForce(part, name, "AngularVelocity", function(f)
		f.AngularVelocity = Vector3.zero
		f.MaxTorque = math.huge
	end)
	if not h then return nil end
	function h.set(vec) pcall(function() h.instance.AngularVelocity = vec end) end
	return h
end
