-- Roblox / 执行器 API 桩: 只实现 selfblox.lua 真会走到的部分, 让脚本能在普通 Lua VM 里跑通
-- 不是模拟器: 目的是"改了之后还能不能跑完", 不是物理正确

-- ───────── 基础数据类型 ─────────
local V3MT
local function V3(x, y, z)
	x, y, z = x or 0, y or 0, z or 0
	local m = math.sqrt(x * x + y * y + z * z)
	local v = setmetatable({ X = x, Y = y, Z = z, Magnitude = m }, V3MT)
	-- Unit 不能再调 V3, 否则 V3→Unit→V3 无限递归
	local u = m > 1e-9 and setmetatable({ X = x / m, Y = y / m, Z = z / m }, V3MT) or v
	u.Magnitude, u.Unit = 1, u
	v.Unit = u
	return v
end
V3MT = {
	__add = function(a, b) return V3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
	__sub = function(a, b) return V3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
	__mul = function(a, b) if type(a) == "number" then return V3(b.X * a, b.Y * a, b.Z * a) elseif type(b) == "number" then return V3(a.X * b, a.Y * b, a.Z * b) end return V3(a.X * b.X, a.Y * b.Y, a.Z * b.Z) end,
	__div = function(a, b) if type(b) == "number" then return V3(a.X / b, a.Y / b, a.Z / b) end return V3(a.X / b.X, a.Y / b.Y, a.Z / b.Z) end,
	__unm = function(a) return V3(-a.X, -a.Y, -a.Z) end,
	__eq = function(a, b) return rawequal(a, b) or (type(b) == "table" and a.X == b.X and a.Y == b.Y and a.Z == b.Z) end,
	__tostring = function(a) return string.format("%.1f, %.1f, %.1f", a.X, a.Y, a.Z) end,
}
-- __index 是函数时 Lua 不会再回落到元表, 所以 Dot/Cross/Lerp 要在这里手动转发
V3MT.__index = function(t, k)
	if k == "Magnitude" then local m = math.sqrt(t.X ^ 2 + t.Y ^ 2 + t.Z ^ 2); rawset(t, "Magnitude", m); return m end
	return rawget(V3MT, k)
end
function V3MT_Dot(self, o) return self.X * o.X + self.Y * o.Y + self.Z * o.Z end
V3MT.Dot = V3MT_Dot
V3MT.Cross = function(self, o) return V3(self.Y * o.Z - self.Z * o.Y, self.Z * o.X - self.X * o.Z, self.X * o.Y - self.Y * o.X) end
V3MT.Lerp = function(self, o, a) return V3(self.X + (o.X - self.X) * a, self.Y + (o.Y - self.Y) * a, self.Z + (o.Z - self.Z) * a) end
Vector3 = { new = V3, zero = V3(0, 0, 0), xAxis = V3(1, 0, 0), yAxis = V3(0, 1, 0), zAxis = V3(0, 0, 1) }

local function V2(x, y)
	local v = { X = x or 0, Y = y or 0 }
	v.Magnitude = math.sqrt(v.X * v.X + v.Y * v.Y)
	return setmetatable(v, {
		__add = function(a, b) return V2(a.X + b.X, a.Y + b.Y) end,
		__sub = function(a, b) return V2(a.X - b.X, a.Y - b.Y) end,
		__mul = function(a, b) local n = type(a) == "number" and a or b; local o = type(a) == "number" and b or a; return V2(o.X * n, o.Y * n) end,
	})
end
Vector2 = { new = V2 }

-- 3x3 旋转矩阵, 够 CFrame 乘法/lookAt/fromAxisAngle 用
local function matIdent() return { 1, 0, 0, 0, 1, 0, 0, 0, 1 } end
local function matMul(a, b)
	local r = {}
	for i = 0, 2 do for j = 0, 2 do r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[j + 4] + a[i * 3 + 3] * b[j + 7] end end
	return r
end
local function matVec(m, v) return V3(m[1] * v.X + m[2] * v.Y + m[3] * v.Z, m[4] * v.X + m[5] * v.Y + m[6] * v.Z, m[7] * v.X + m[8] * v.Y + m[9] * v.Z) end

local CF
local function CFmt()
	return {
		__mul = function(a, b)
			if type(b) == "table" and b._m and b.Position then return CF(matVec(a._m, b.Position) + a.Position, matMul(a._m, b._m)) end
			if type(b) == "table" and b.X then return matVec(a._m, b) + a.Position end
			error("CFrame * " .. type(b))
		end,
		__add = function(a, b) return CF(a.Position + b, a._m) end,
		__sub = function(a, b) return CF(a.Position - b, a._m) end,
		__tostring = function(a) return "CFrame(" .. tostring(a.Position) .. ")" end,
	}
end
CF = function(pos, rot)
	rot = rot or matIdent()
	local c = { Position = pos, _m = rot }
	c.LookVector = matVec(rot, V3(0, 0, -1))
	c.Rotation = setmetatable({ Position = V3(0, 0, 0), _m = rot, LookVector = c.LookVector }, CFmt())
	return setmetatable(c, CFmt())
end
CFrame = {
	new = function(a, b, c)
		if type(a) == "table" and a.X and not b then return CF(V3(a.X, a.Y, a.Z)) end
		if type(a) == "table" and type(b) == "table" then -- lookAt 两参数形式
			local z = (a - b); z = z.Magnitude > 1e-9 and z.Unit or V3(0, 0, 1)
			local x = V3(0, 1, 0):Cross(z); x = x.Magnitude > 1e-9 and x.Unit or V3(1, 0, 0)
			local y = z:Cross(x)
			return CF(a, { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z })
		end
		return CF(V3(a or 0, b or 0, c or 0))
	end,
	lookAt = function(from, to) return CFrame.new(from, to) end,
	fromAxisAngle = function(axis, ang)
		local x, y, z, c, s = axis.X, axis.Y, axis.Z, math.cos(ang), math.sin(ang)
		local t = 1 - c
		return CF(V3(0, 0, 0), {
			t * x * x + c, t * x * y - s * z, t * x * z + s * y,
			t * x * y + s * z, t * y * y + c, t * y * z - s * x,
			t * x * z - s * y, t * y * z + s * x, t * z * z + c,
		})
	end,
	identity = CF(V3(0, 0, 0)),
}

local function C3(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, { __tostring = function(c) return string.format("%.2f %.2f %.2f", c.R, c.G, c.B) end }) end
Color3 = { new = C3, fromRGB = function(r, g, b) return C3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end, fromHSV = function(h, s, v) return C3(v, v * (1 - s), v * s) end }
BrickColor = { new = function() return { Color = C3(1, 1, 1) } end }

local function UD(s, o) return setmetatable({ Scale = s or 0, Offset = o or 0 }, { __add = function(a, b) return UD(a.Scale + b.Scale, a.Offset + b.Offset) end }) end
UDim = { new = UD }
local function U2(sx, ox, sy, oy)
	return setmetatable({ Scale = V2(sx or 0, sy or 0), Offset = V2(ox or 0, oy or 0), X = sx or 0, Y = sy or 0 }, {
		__add = function(a, b) return U2(a.Scale.X + b.Scale.X, a.Offset.X + b.Offset.X, a.Scale.Y + b.Scale.Y, a.Offset.Y + b.Offset.Y) end,
	})
end
UDim2 = { new = U2, fromOffset = function(x, y) return U2(0, x, 0, y) end, fromScale = function(x, y) return U2(x, 0, y, 0) end }

-- ───────── Enum: 每条路径一个唯一 table, 靠身份比较 ─────────
Enum = setmetatable({}, { __index = function(t, k) local e = setmetatable({ _n = k }, { __index = function(tt, kk) local i = { Name = kk, Value = kk }; rawset(tt, kk, i); return i end, __tostring = function() return "Enum." .. k end }); rawset(t, k, e); return e end })

-- ───────── Instance ─────────
local ANCESTRY = {
	Part = { "Part", "BasePart", "PVInstance", "Instance" }, MeshPart = { "MeshPart", "BasePart", "PVInstance", "Instance" },
	Model = { "Model", "PVInstance", "Instance" }, Folder = { "Folder", "Instance" },
	Humanoid = { "Humanoid", "Instance" }, Attachment = { "Attachment", "Instance" },
	Seat = { "Seat", "BasePart", "PVInstance", "Instance" }, VehicleSeat = { "VehicleSeat", "Seat", "BasePart", "PVInstance", "Instance" },
	ScreenGui = { "ScreenGui", "GuiObject", "Instance" }, Frame = { "Frame", "GuiObject", "Instance" },
	TextLabel = { "TextLabel", "GuiObject", "Instance" }, TextButton = { "TextButton", "GuiButton", "GuiObject", "Instance" },
	ImageButton = { "ImageButton", "GuiButton", "GuiObject", "Instance" }, TextBox = { "TextBox", "GuiObject", "Instance" },
	UIListLayout = { "UIListLayout", "Instance" }, UIPadding = { "UIPadding", "Instance" }, UICorner = { "UICorner", "Instance" },
	UIDragDetector = { "UIDragDetector", "Instance" }, Highlight = { "Highlight", "Instance" }, BillboardGui = { "BillboardGui", "Instance" },
	ProximityPrompt = { "ProximityPrompt", "Instance" }, RemoteEvent = { "RemoteEvent", "Instance" },
	UnreliableRemoteEvent = { "UnreliableRemoteEvent", "Instance" }, RemoteFunction = { "RemoteFunction", "Instance" },
	SpotLight = { "SpotLight", "Light", "Instance" }, PointLight = { "PointLight", "Light", "Instance" },
	IntValue = { "IntValue", "ValueBase", "Instance" }, NumberValue = { "NumberValue", "ValueBase", "Instance" },
	StringValue = { "StringValue", "ValueBase", "Instance" }, BoolValue = { "BoolValue", "ValueBase", "Instance" },
	LinearVelocity = { "LinearVelocity", "Instance" }, VectorForce = { "VectorForce", "Instance" },
	AngularVelocity = { "AngularVelocity", "Instance" }, AlignOrientation = { "AlignOrientation", "Instance" },
	ColorCorrectionEffect = { "ColorCorrectionEffect", "PostEffect", "Instance" }, Atmosphere = { "Atmosphere", "Instance" },
	Camera = { "Camera", "Instance" }, Player = { "Player", "Instance" }, Team = { "Team", "Instance" },
	Workspace = { "Workspace", "Instance" },
}
local SIGNALS = {
	Activated = 1, InputBegan = 1, InputEnded = 1, FocusLost = 1, Changed = 1, ChildAdded = 1, ChildRemoved = 1,
	DescendantAdded = 1, DescendantRemoving = 1, AncestryChanged = 1, OnClientEvent = 1, JumpRequest = 1,
	PreSimulation = 1, PreRender = 1, PostSimulation = 1, PlayerAdded = 1, PlayerRemoving = 1, DragEnd = 1,
	DragStart = 1, MouseButton1Down = 1, Stepped = 1, Heartbeat = 1, RenderStepped = 1,
}

local ALL = {} -- 建过的所有 Instance, 驱动脚本用来遍历按钮
local function Signal(name)
	local s = { _name = name, _h = {} }
	function s:Connect(f)
		local h = { Connected = true }
		function h:Disconnect() h.Connected = false end
		s._h[#s._h + 1] = h
		h._f = f
		return h
	end
	function s:Fire(...) for _, h in ipairs(s._h) do if h.Connected then local ok, e = pcall(h._f, ...) if not ok then error(e, 0) end end end end
	return s
end

local Inst_mt = {}
Inst_mt.__newindex = function(t, k, v)
	if k == "Parent" then
		local old = rawget(t, "_p").Parent
		if old and old._kids then old._kids[t] = nil end
		rawget(t, "_p").Parent = v
		if v and v._kids then v._kids[t] = t end
		return
	end
	rawget(t, "_p")[k] = v
end

local function newInst(class, parent)
	local i = setmetatable({ _p = {}, _kids = {}, _class = class, _dead = false, _sig = {} }, Inst_mt)
	i._p.Name = class
	i._p.ClassName = class
	i._p.Parent = parent
	if parent then parent._kids[i] = i end
	-- 常用默认值, 免得脚本读到 nil 就崩
	local d = { Size = U2(0, 100, 0, 20), Position = U2(0, 0, 0, 0), Text = "", Visible = true, Enabled = true, CanCollide = true, Anchored = false,
		AssemblyMass = 100, Health = 100, WalkSpeed = 16, JumpPower = 50, JumpHeight = 7.2, UseJumpPower = true, MaxSpeed = 30,
		MoveDirection = Vector3.zero, PlatformStand = false, Value = 0, Throttle = 0, Steer = 0, AbsolutePosition = V2(0, 0),
		AbsoluteSize = V2(100, 20), MaxActivationDistance = 32, HoldDuration = 0.5, RequiresLineOfSight = true }
	for k, v in pairs(d) do if i._p[k] == nil then i._p[k] = v end end
	if class == "Part" or class == "MeshPart" then
		i._p.Size = V3(4, 1, 2); i._p.Position = V3(0, 0, 0); i._p.CFrame = CFrame.new(0, 0, 0)
		i._p.AssemblyLinearVelocity = Vector3.zero; i._p.AssemblyAngularVelocity = Vector3.zero
		i._p.AssemblyRootPart = i; i._p.Color = C3(0.5, 0.5, 0.5)
	elseif class == "VehicleSeat" or class == "Seat" then
		i._p.Size = V3(2, 1, 2); i._p.CFrame = CFrame.new(0, 0, 0); i._p.AssemblyRootPart = i
		i._p.AssemblyLinearVelocity = Vector3.zero; i._p.AssemblyAngularVelocity = Vector3.zero
		i._p.AssemblyMass = 800; i._p.Position = V3(0, 0, 0)
	elseif class == "Model" then
		i._p.PrimaryPart = nil
	elseif class == "Camera" then
		i._p.ViewportSize = V2(1080, 2340); i._p.CFrame = CFrame.new(0, 5, 10)
	elseif class == "Highlight" or class == "BillboardGui" then
		i._p.Adornee = nil
	end
	ALL[#ALL + 1] = i
	return i
end

local M = {}
Inst_mt.__index = function(t, k)
	local p = rawget(t, "_p")
	if p[k] ~= nil then return p[k] end
	if M[k] ~= nil then return M[k] end
	if SIGNALS[k] then local s = Signal(k); p[k] = s; return s end
	return nil
end

-- 方法表: 所有 Instance 共享
local function methods(t)
	return setmetatable({}, { __index = function(_, k) return M[k] end })
end
function M:IsA(c) local a = ANCESTRY[self._class] or { self._class, "Instance" }; for _, n in ipairs(a) do if n == c then return true end end return false end
function M:GetClassName() return self._class end
function M:Destroy()
	self._dead = true
	if self._p.Parent then self._p.Parent._kids[self] = nil end
	self._p.Parent = nil
	local function kids(i) for c in pairs(i._kids) do c._dead = true; kids(c) end end
	kids(self)
end
function M:IsDescendantOf(a) local p = self._p.Parent; while p do if p == a then return true end; p = p._p.Parent end return false end
function M:IsAncestorOf(a) return a:IsDescendantOf(self) end
function M:GetChildren() local o = {}; for c in pairs(self._kids) do if not c._dead then o[#o + 1] = c end end; return o end
function M:GetDescendants()
	local o = {}
	local function walk(i) for c in pairs(i._kids) do if not c._dead then o[#o + 1] = c; walk(c) end end end
	walk(self)
	return o
end
function M:FindFirstChild(n, rec)
	for c in pairs(self._kids) do if not c._dead and c._p.Name == n then return c end end
	if rec then for _, c in ipairs(self:GetDescendants()) do if c._p.Name == n then return c end end end
	return nil
end
function M:FindFirstChildOfClass(c, rec)
	for _, k in ipairs(self:GetChildren()) do if k:IsA(c) then return k end end
	if rec then for _, k in ipairs(self:GetDescendants()) do if k:IsA(c) then return k end end end
	return nil
end
function M:FindFirstChildWhichIsA(c, rec) return self:FindFirstChildOfClass(c, rec) end
function M:FindFirstAncestorOfClass(c) local p = self._p.Parent; while p do if p:IsA(c) then return p end; p = p._p.Parent end return nil end
function M:WaitForChild(n, to) local c = self:FindFirstChild(n); if c then return c end; if to then return nil end; return self:FindFirstChild(n) end
function M:GetFullName()
	local parts, p = { self._p.Name }, self._p.Parent
	while p do parts[#parts + 1] = p._p.Name; p = p._p.Parent end
	local o = {}; for i = #parts, 1, -1 do o[#o + 1] = parts[i] end
	return table.concat(o, ".")
end
function M:GetAttribute(k) return self._attr and self._attr[k] end
function M:SetAttribute(k, v) self._attr = self._attr or {}; self._attr[k] = v end
function M:GetAttributes() return self._attr or {} end
function M:GetPropertyChangedSignal(prop)
	self._pc = self._pc or {}
	if not self._pc[prop] then self._pc[prop] = Signal("PropertyChanged:" .. prop) end
	return self._pc[prop]
end
function M:GetPivot() return self._p.CFrame or CFrame.new(0, 0, 0) end
function M:PivotTo(cf) self._p.CFrame = cf; self._p.Position = cf.Position end
function M:FireServer(...) self._sent = (self._sent or 0) + 1 end
function M:InvokeServer(...) return nil end
function M:Clone() return newInst(self._class, nil) end
function M:ChangeState(s) self._state = s end
function M:WorldToViewportPoint(v) return V3(v.X * 10, v.Y * 10, 0), true end
function M:MoveTo(p) self._p.Position = p end
function M:Raycast(origin, dir, params)
	-- 一处 Raycast 两用: sibs 的 hover() 要地面命中, pick() 要能被 FindFirstAncestorOfClass("Model") 找到车
	-- 所以直接命中那辆 MuscleCar 的座位, 距离 3 → hover 的 d<3 分支和 pick 的锁定分支都会走到
	local seat = _SB.seat
	return { Instance = seat, Position = origin + V3(0, -3, 0), Distance = 3, Normal = V3(0, 1, 0), Material = Enum.Material.Concrete }
end
function M:GetTotalMemoryUsageMb() return 320 end
function M:GetNetworkPing() return 0.045 end
function M:GetPlayerFromCharacter(c) return nil end
function M:GetTeams() return {} end
function M:GetPlayers() return rawget(self, "_players") or {} end
function M:JSONEncode(t)
	local function enc(v)
		local ty = type(v)
		if ty == "table" then
			local isArr, n = true, 0
			for k in pairs(v) do n = n + 1; if type(k) ~= "number" then isArr = false end end
			if isArr then local o = {}; for _, x in ipairs(v) do o[#o + 1] = enc(x) end; return "[" .. table.concat(o, ",") .. "]" end
			local o = {}; for k, x in pairs(v) do o[#o + 1] = '"' .. tostring(k) .. '":' .. enc(x) end
			return "{" .. table.concat(o, ",") .. "}"
		elseif ty == "string" then return '"' .. v .. '"' end
		return tostring(v)
	end
	return enc(t)
end
function M:JSONDecode(s)
	if not s or s == "" then return nil end
	local ok, r = pcall(_SB_JSON_DECODE, s)
	return ok and r or nil
end
function M:SendKeyEvent(...) end
function M:Disconnect() end

RaycastParams = { new = function() return { FilterType = nil, FilterDescendantsInstances = {}, IgnoreWater = false, CollisionGroup = "Default" } end }
OverlapParams = { new = function() return { FilterType = nil, FilterDescendantsInstances = {} } end }

Instance = { new = function(class, parent)
	if not ANCESTRY[class] and not SIGNALS[class] then -- 未登记的类也允许建, 只是 IsA 只认自己
		ANCESTRY[class] = { class, "Instance" }
	end
	local i = newInst(class, nil)
	i._M = methods(i)
	if parent then i._p.Parent = parent; parent._kids[i] = i end
	return i
end }

-- ───────── 场景: 角色 / 一辆车 / 一架飞机 / 一个 Collector ─────────
local workspace = newInst("Workspace", nil); workspace._M = methods(workspace); workspace._p.Name = "Workspace"
local cam = newInst("Camera", workspace); cam._M = methods(cam); cam._p.Name = "Camera"
workspace.CurrentCamera = cam
workspace._p.CFrame = CFrame.new(0, 0, 0)

local char = newInst("Model", workspace); char._M = methods(char); char._p.Name = "Sumicya"
local hrp = newInst("Part", char); hrp._M = methods(hrp); hrp._p.Name = "HumanoidRootPart"
hrp._p.CFrame = CFrame.new(0, 3, 0); hrp._p.Position = V3(0, 3, 0); hrp._p.AssemblyRootPart = hrp
hrp._p.AssemblyLinearVelocity = V3(5, 0, 0)
local hum = newInst("Humanoid", char); hum._M = methods(hum); hum._p.Name = "Humanoid"
char._p.PrimaryPart = hrp
local prompt = newInst("ProximityPrompt", hrp); prompt._M = methods(prompt); prompt._p.Name = "Interact"

-- 车
local car = newInst("Model", workspace); car._M = methods(car); car._p.Name = "MuscleCar"
local seat = newInst("VehicleSeat", car); seat._M = methods(seat); seat._p.Name = "Drive"
seat._p.CFrame = CFrame.new(10, 2, 0); seat._p.Position = V3(10, 2, 0); seat._p.AssemblyRootPart = seat
seat._p.AssemblyLinearVelocity = V3(0, 0, 0); seat._p.AssemblyMass = 900
for i = 1, 3 do local b = newInst("Part", car); b._M = methods(b); b._p.Name = "Body" .. i end
local lamp = newInst("SpotLight", seat); lamp._M = methods(lamp); lamp._p.Name = "Head"; lamp._p.Enabled = false

-- 飞机 (plane 模块要能扫到)
local jet = newInst("Model", workspace); jet._M = methods(jet); jet._p.Name = "FighterJet"
local pseat = newInst("VehicleSeat", jet); pseat._M = methods(pseat); pseat._p.Name = "PilotSeat"
pseat._p.CFrame = CFrame.new(0, 200, 0); pseat._p.Position = V3(0, 200, 0); pseat._p.AssemblyRootPart = pseat
for i = 1, 10 do local w = newInst("Part", jet); w._M = methods(w); w._p.Name = "Wing" .. i; w._p.Size = V3(10, 1, 4) end
local jetRemote = newInst("RemoteEvent", jet); jetRemote._M = methods(jetRemote); jetRemote._p.Name = "FireGun"

-- Collector + leaderstats (brick 模块)
local collector = newInst("Part", workspace); collector._M = methods(collector); collector._p.Name = "Collector"
collector._p.CFrame = CFrame.new(0, 0, 0)
local spawnBit = newInst("RemoteEvent", nil); spawnBit._M = methods(spawnBit); spawnBit._p.Name = "SpawnBit"

-- RemoteStorage
local RS = newInst("Folder", nil); RS._M = methods(RS); RS._p.Name = "ReplicatedStorage"
spawnBit._p.Parent = RS; RS._kids[spawnBit] = spawnBit
local rsRemote = newInst("RemoteEvent", RS); rsRemote._M = methods(rsRemote); rsRemote._p.Name = "ShootBullet"

-- Lighting
local Lighting = newInst("Folder", nil); Lighting._M = methods(Lighting); Lighting._p.Name = "Lighting"
Lighting._p.Ambient = C3(0.1, 0.1, 0.1); Lighting._p.OutdoorAmbient = C3(0.2, 0.2, 0.2)
Lighting._p.Brightness = 1; Lighting._p.FogEnd = 100000; Lighting._p.GlobalShadows = true
local atm = newInst("Atmosphere", Lighting); atm._M = methods(atm); atm._p.Name = "Atmosphere"; atm._p.Density = 0.3

-- CoreGui
local CoreGui = newInst("Folder", nil); CoreGui._M = methods(CoreGui); CoreGui._p.Name = "CoreGui"

-- Player
local me = newInst("Player", nil); me._M = methods(me); me._p.Name = "Sumicya"
me._p.DisplayName = "Sumicya"; me._p.UserId = 12345; me._p.Character = char
me._p.TeamColor = { Color = C3(1, 0.2, 0.2) }; me._p.Team = nil
local pg = newInst("Folder", me); pg._M = methods(pg); pg._p.Name = "PlayerGui"
local ls = newInst("Folder", me); ls._M = methods(ls); ls._p.Name = "leaderstats"
local bits = newInst("IntValue", ls); bits._M = methods(bits); bits._p.Name = "Bits"; bits._p.Value = 0
local mult = newInst("NumberValue", ls); mult._M = methods(mult); mult._p.Name = "Multiplier"; mult._p.Value = 1

-- MobilePedals: 两个踏板按钮
local pedals = newInst("ScreenGui", pg); pedals._M = methods(pedals); pedals._p.Name = "MobilePedals"
local pframe = newInst("Frame", pedals); pframe._M = methods(pframe); pframe._p.Name = "Frame"
local brk = newInst("TextButton", pframe); brk._M = methods(brk); brk._p.Name = "Brake"; brk._p.AbsolutePosition = V2(100, 900)
local gas = newInst("TextButton", pframe); gas._M = methods(gas); gas._p.Name = "Gas"; gas._p.AbsolutePosition = V2(300, 900)

local Players = newInst("Folder", nil); Players._M = methods(Players); Players._p.Name = "Players"
Players.LocalPlayer = me; Players.MaxPlayers = 20; Players._players = { me }

local other = newInst("Player", Players); other._M = methods(other); other._p.Name = "Rival"
other._p.DisplayName = "Rival"; other._p.UserId = 999
local ochar = newInst("Model", workspace); ochar._M = methods(ochar); ochar._p.Name = "Rival"
local ohrp = newInst("Part", ochar); ohrp._M = methods(ohrp); ohrp._p.Name = "HumanoidRootPart"; ohrp._p.Position = V3(20, 3, 0)
local ohum = newInst("Humanoid", ochar); ohum._M = methods(ohum); ohum._p.Name = "Humanoid"
other._p.Character = ochar
Players._players = { me, other }

local Teams = newInst("Folder", nil); Teams._M = methods(Teams); Teams._p.Name = "Teams"
local RunService = newInst("Folder", nil); RunService._M = methods(RunService); RunService._p.Name = "RunService"
local UIS = newInst("Folder", nil); UIS._M = methods(UIS); UIS._p.Name = "UserInputService"
local Http = newInst("Folder", nil); Http._M = methods(Http); Http._p.Name = "HttpService"
local Stats = newInst("Folder", nil); Stats._M = methods(Stats); Stats._p.Name = "Stats"
local VIM = newInst("Folder", nil); VIM._M = methods(VIM); VIM._p.Name = "VirtualInputManager"

local SERVICES = { Workspace = workspace, Players = Players, RunService = RunService, UserInputService = UIS,
	HttpService = Http, Lighting = Lighting, Stats = Stats, Teams = Teams, ReplicatedStorage = RS,
	VirtualInputManager = VIM, CoreGui = CoreGui }

game = { PlaceId = 123456789, PlaceVersion = 1 }
function game:GetService(n) return SERVICES[n] end
function game:HttpGet(u) return "-- stub" end
_G.workspace = workspace

-- ───────── Luau 专有全局 ─────────
typeof = function(v)
	local t = type(v)
	if t ~= "table" then return t end
	if v.X and v.Y and v.Z and v.Magnitude ~= nil then return "Vector3" end
	if v._m then return "CFrame" end
	if v.Scale and v.Offset and v.X ~= nil then return "UDim2" end
	if v.R and v.G and v.B then return "Color3" end
	if v._class then return "Instance" end
	return "table"
end
table.clear = function(t) for k in pairs(t) do t[k] = nil end end
table.find = function(t, v) for i, x in ipairs(t) do if x == v then return i end end return nil end
math.sign = math.sign or function(x) return x > 0 and 1 or (x < 0 and -1 or 0) end
math.clamp = math.clamp or function(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
math.round = math.round or function(v) return math.floor(v + 0.5) end
table.create = table.create or function(n, v) local t = {}; for i = 1, n do t[i] = v end; return t end
string.split = string.split or function(s, sep) local o = {}; for p in (s .. sep):gmatch("(.-)" .. sep) do o[#o + 1] = p end; return o end

-- ───────── 执行器 API ─────────
local FILES = {}
gethui = function() return CoreGui end
isfile = function(p) return FILES[p] ~= nil end
readfile = function(p) return FILES[p] or error("no file " .. p) end
writefile = function(p, c) FILES[p] = c end
appendfile = function(p, c) FILES[p] = (FILES[p] or "") .. c end
delfile = function(p) FILES[p] = nil end
setclipboard = function(s) FILES["<clipboard>"] = s end
getgenv = function() return _G end
-- 抓 print/warn 输出: 驱动脚本靠它断言"模块数"和"有没有模块炸了"
_SB_OUT = {}
local _print = print
print = function(...) local o = {} for i = 1, select("#", ...) do o[i] = tostring(select(i, ...)) end _SB_OUT[#_SB_OUT + 1] = table.concat(o, "\t") end
warn = function(...) local o = {} for i = 1, select("#", ...) do o[i] = tostring(select(i, ...)) end _SB_OUT[#_SB_OUT + 1] = "[warn] " .. table.concat(o, "\t") end
hookmetamethod = function(obj, key, fn)
	obj._hooks = obj._hooks or {}
	local old = obj._hooks[key]
	obj._hooks[key] = fn
	return old or function(self, ...) local m = self -- 占位: 桩里 __namecall 侦听只验证装/卸不炸
		return nil end
end
getnamecallmethod = function() return "FireServer" end
newcclosure = function(f) return f end

-- ───────── task 调度器 ─────────
local clock, queue = 0, {}
local function push(t, f) queue[#queue + 1] = { t = clock + t, co = coroutine.create(f) } end
task = {}
function task.spawn(f, ...) local a = table.pack(...); push(0, function() return f(table.unpack(a, 1, a.n)) end) end
function task.defer(f, ...) local a = table.pack(...); push(0, function() return f(table.unpack(a, 1, a.n)) end) end
function task.delay(t, f, ...) local a = table.pack(...); push(t or 0, function() return f(table.unpack(a, 1, a.n)) end) end
function task.wait(t) coroutine.yield(t or 0) return t or 0 end

-- ───────── JSON 解码 (给 readfile 回来的 Selfblox.json 用) ─────────
function _SB_JSON_DECODE(s)
	local pos = 1
	local function ws() pos = s:find("[^ \t\r\n]", pos) or (#s + 1) end
	local parse
	local function str()
		pos = pos + 1
		local st = s:find('"', pos, true)
		local v = s:sub(pos, st - 1)
		pos = st + 1
		return v
	end
	function parse()
		ws()
		local c = s:sub(pos, pos)
		if c == "{" then
			pos = pos + 1; local o = {}
			ws(); if s:sub(pos, pos) == "}" then pos = pos + 1; return o end
			while true do
				ws(); local k = str(); ws(); pos = pos + 1; o[k] = parse(); ws()
				local d = s:sub(pos, pos); pos = pos + 1
				if d ~= "," then break end
			end
			return o
		elseif c == "[" then
			pos = pos + 1; local o = {}
			ws(); if s:sub(pos, pos) == "]" then pos = pos + 1; return o end
			while true do
				o[#o + 1] = parse(); ws()
				local d = s:sub(pos, pos); pos = pos + 1
				if d ~= "," then break end
			end
			return o
		elseif c == '"' then return str()
		elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
		elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
		elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
		else
			local st, en = s:find("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
			pos = en + 1
			return tonumber(s:sub(st, en))
		end
	end
	return parse()
end

-- ───────── 给驱动脚本用的钩子 ─────────
_SB = {
	ALL = ALL, FILES = FILES, out = _SB_OUT, Signal = Signal, newInst = newInst, methods = methods,
	services = SERVICES, me = me, char = char, hrp = hrp, hum = hum, seat = seat, car = car,
	jet = jet, collector = collector, spawnBit = spawnBit, bits = bits, mult = mult,
	brake = brk, gas = gas, prompt = prompt, workspace = workspace, cam = cam,
	clock = function() return clock end,
	-- 跑一轮调度器: 到 limit 虚拟秒或 steps 步为止
	run = function(limit, steps)
		steps = steps or 20000
		local n = 0
		while n < steps do
			table.sort(queue, function(a, b) return a.t < b.t end)
			local next_ = queue[1]
			if not next_ then break end
			if next_.t > limit then break end
			clock = next_.t
			table.remove(queue, 1)
			local ok, res = coroutine.resume(next_.co)
			if ok and coroutine.status(next_.co) == "suspended" then
				queue[#queue + 1] = { t = clock + (type(res) == "number" and res or 0), co = next_.co }
			elseif not ok then error(res, 0) end
			n = n + 1
		end
		return n
	end,
	-- 触发一次 RunService 信号
	tick = function(sig, dt)
		local s = SERVICES.RunService._p[sig] or SERVICES.RunService[sig]
		if type(s) == "table" and s.Fire then s:Fire(dt or 1 / 60) end
	end,
}
_G._SB = _SB
return _SB
