-- Selfblox 离线自检: 一个假 Roblox 引擎, 加载 selfblox.lua → 建面板 → 点一遍 → 卸载 → 断言干净
-- 跑法: lua5.4 smoke.lua     (luajit / lua5.1 / luau 也行; 不跑也不影响脚本本体)
-- 它只验"结构不炸 + 状态真的改了 + 卸载不留垃圾", 不验游戏里的手感。
local SRC = rawget(_G, "SB_SRC") -- 从外面塞源码也行 (沙箱里没有真文件系统时用)
if not SRC then
	local dir = arg and arg[0] and arg[0]:match("^(.*[/\\])") or ""
	local fp = io.open(dir .. "selfblox.lua", "rb") or io.open("selfblox.lua", "rb")
	SRC = assert(fp, "找不到 selfblox.lua; 在仓库根目录跑: lua5.4 smoke.lua"):read("*a")
end
local load_chunk = load or loadstring

-- ───────── 垫片: Roblox 有、标准 Lua 没有 ─────────
local unpack = table.unpack or unpack
math.clamp = math.clamp or function(x, a, b) if x < a then return a elseif x > b then return b end return x end
math.sign = math.sign or function(x) if x > 0 then return 1 elseif x < 0 then return -1 end return 0 end
math.round = math.round or function(x) return math.floor(x + 0.5) end
math.atan2 = math.atan2 or function(y, x) if x == 0 then return y > 0 and math.pi / 2 or -math.pi / 2 end return math.atan(y / x) end
table.clear = table.clear or function(t) for k in pairs(t) do t[k] = nil end end
table.find = table.find or function(t, v) for i = 1, #t do if t[i] == v then return i end end end
table.pack = table.pack or function(...) return { n = select("#", ...), ... } end
table.unpack = table.unpack or unpack

-- ───────── 假引擎: 实例 / 信号 ─────────
local INSTANCES, LIVE = {}, 0
local methods = {}
local SIGNALS = {}
for _, n in ipairs({ "Activated", "InputBegan", "InputEnded", "FocusLost", "Focused", "DragBegin", "DragEnd", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "PlayerAdded", "PlayerRemoving", "PreSimulation", "PreRender", "Heartbeat", "RenderStepped", "JumpRequest", "OnClientEvent", "Changed", "Destroying" }) do SIGNALS[n] = true end
local Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({ hs = {} }, Signal) end
function Signal:Connect(fn)
	local c = { fn = fn, on = true }
	LIVE = LIVE + 1
	function c:Disconnect() if self.on then self.on = false; LIVE = LIVE - 1 end end
	self.hs[#self.hs + 1] = c
	return c
end
function Signal:Once(fn) local c = self:Connect(function(...) c:Disconnect(); fn(...) end); return c end
function Signal:Fire(...) for _, c in ipairs(self.hs) do if c.on then c.fn(...) end end end

local mt = {
	__index = function(t, k)
		if k == "Parent" then return rawget(t, "parent") end
		local m = methods[k]
		if m then return m end
		if k == "AbsolutePosition" then return { X = 0, Y = 0 } end -- 假布局: 屏幕坐标一律 0
		local props = rawget(t, "props")
		local v = props[k]
		if v == nil and SIGNALS[k] then v = Signal.new(); props[k] = v end -- 信号字段按需生成
		return v
	end,
	__newindex = function(t, k, v)
		if k == "Parent" then
			local old = rawget(t, "parent")
			if old then for i, c in ipairs(old.children) do if c == t then table.remove(old.children, i); break end end end
			rawset(t, "parent", v)
			if v then v.children[#v.children + 1] = t end
		else
			rawget(t, "props")[k] = v
		end
	end,
}
local function inst(cls, props)
	local self = setmetatable({ ClassName = cls, props = {}, children = {}, attrs = {}, destroyed = false }, mt)
	INSTANCES[#INSTANCES + 1] = self
	self.props.Name = cls -- Roblox 默认给实例起类名, FindFirstChild("LinearVelocity") 这类调用要靠它
	for k, v in pairs(props or {}) do self.props[k] = v end
	return self
end

local ISA = {
	Part = { "BasePart" }, MeshPart = { "BasePart" }, VehicleSeat = { "Seat", "BasePart" }, Seat = { "BasePart" },
	SpotLight = { "Light" }, PointLight = { "Light" }, SurfaceLight = { "Light" },
	TextButton = { "GuiButton", "GuiObject" }, TextLabel = { "GuiObject" }, TextBox = { "GuiObject" }, Frame = { "GuiObject" },
	ScreenGui = { "LayerCollector" }, BillboardGui = { "LayerCollector" },
	IntValue = { "ValueBase" }, StringValue = { "ValueBase" }, NumberValue = { "ValueBase" }, BoolValue = { "ValueBase" },
	RemoteEvent = {}, RemoteFunction = {}, UnreliableRemoteEvent = {}, ProximityPrompt = {}, Humanoid = {},
}
function methods.IsA(self, cls)
	if cls == "Instance" or self.ClassName == cls then return true end
	for _, x in ipairs(ISA[self.ClassName] or {}) do if x == cls then return true end end
	return false
end
function methods.Destroy(self)
	if self.destroyed then return end
	self.destroyed = true
	local kids = {}
	for i, c in ipairs(self.children) do kids[i] = c end -- 复制一份: Destroy 会从 self.children 里摘人
	for _, c in ipairs(kids) do methods.Destroy(c) end
	local p = rawget(self, "parent")
	if p then for i, c in ipairs(p.children) do if c == self then table.remove(p.children, i); break end end end
	rawset(self, "parent", nil)
end
function methods.GetChildren(self) local o = {}; for i, c in ipairs(self.children) do o[i] = c end; return o end
function methods.GetDescendants(self)
	local o = {}
	local function walk(x) for _, c in ipairs(x.children) do o[#o + 1] = c; walk(c) end end
	walk(self)
	return o
end
function methods.FindFirstChild(self, name, recur)
	for _, c in ipairs(self.children) do if c.Name == name then return c end end
	if recur then for _, c in ipairs(self.children) do local f = methods.FindFirstChild(c, name, true); if f then return f end end end
end
function methods.FindFirstChildOfClass(self, cls) for _, c in ipairs(self.children) do if c.ClassName == cls then return c end end end
function methods.FindFirstChildWhichIsA(self, cls, recur)
	for _, c in ipairs(self.children) do if methods.IsA(c, cls) then return c end end
	if recur then for _, c in ipairs(self.children) do local f = methods.FindFirstChildWhichIsA(c, cls, true); if f then return f end end end
end
function methods.WaitForChild(self, name) return methods.FindFirstChild(self, name) end
function methods.FindFirstAncestorOfClass(self, cls) local p = rawget(self, "parent"); while p do if methods.IsA(p, cls) then return p end; p = rawget(p, "parent") end end
function methods.IsDescendantOf(self, x) local p = rawget(self, "parent"); while p do if p == x then return true end; p = rawget(p, "parent") end; return false end
function methods.GetFullName(self) local p = rawget(self, "parent"); return (p and (methods.GetFullName(p) .. ".") or "") .. tostring(self.Name) end
function methods.GetAttribute(self, k) return self.attrs[k] end
function methods.SetAttribute(self, k, v) self.attrs[k] = v end
function methods.GetAttributes(self) local o = {}; for k, v in pairs(self.attrs) do o[k] = v end; return o end
function methods.GetPropertyChangedSignal(self, p) local s = self.props["__pcs_" .. p]; if not s then s = Signal.new(); self.props["__pcs_" .. p] = s end; return s end
function methods.GetPivot(self) return self.props.__pivot or CFrame.new(Vector3.zero) end
function methods.PivotTo(self, cf) self.props.__pivot = cf end
function methods.Raycast() return nil end
function methods.WorldToViewportPoint(self, v) return Vector3.new(100, 200, 10), true end
function methods.ChangeState() end
function methods.SendKeyEvent(self, ...) self.props.keys = (self.props.keys or 0) + 1 end

-- ───────── 假引擎: 向量 / CFrame / 颜色 / UDim / Enum ─────────
local Vector3, Color3, CFrame, UDim, UDim2, Vector2
local v3mt = {
	__index = function(t, k)
		if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
		if k == "Unit" then local m = t.Magnitude; if m < 1e-9 then return Vector3.new(0, 0, 0) end; return Vector3.new(t.X / m, t.Y / m, t.Z / m) end
		if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
		if k == "Lerp" then return function(a, b, x) return Vector3.new(a.X + (b.X - a.X) * x, a.Y + (b.Y - a.Y) * x, a.Z + (b.Z - a.Z) * x) end end
		if k == "Cross" then return function(a, b) return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end end
	end,
	__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
	__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
	__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end,
	__mul = function(a, b) if type(a) == "number" then return Vector3.new(a * b.X, a * b.Y, a * b.Z) end if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z) end,
	__tostring = function(a) return string.format("(%.1f,%.1f,%.1f)", a.X, a.Y, a.Z) end,
}
Vector3 = { new = function(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, v3mt) end }
Vector3.zero, Vector3.one = Vector3.new(0, 0, 0), Vector3.new(1, 1, 1)
Vector3.xAxis, Vector3.yAxis, Vector3.zAxis = Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1)
Vector2 = { new = function(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, { __index = { Magnitude = 0 } }) end }

Color3 = {
	new = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end,
	fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end,
	fromHSV = function() return { R = 0.5, G = 0.5, B = 0.5 } end,
}
local cfmt = {
	__index = function(t, k)
		if k == "Position" then return t.p end
		if k == "LookVector" then return -t.z end
		if k == "RightVector" then return t.x end
		if k == "UpVector" then return t.y end
		if k == "Rotation" then return CFrame.fromBasis(t.x, t.y, t.z, Vector3.zero) end
	end,
	__mul = function(a, b) -- 只做旋转叠加, 精度够假引擎用
		local function rot(v, m) return Vector3.new(v.X * m.x.X + v.Y * m.y.X + v.Z * m.z.X, v.X * m.x.Y + v.Y * m.y.Y + v.Z * m.z.Y, v.X * m.x.Z + v.Y * m.y.Z + v.Z * m.z.Z) end
		local bx, by, bz = rot(b.x, a), rot(b.y, a), rot(b.z, a)
		return CFrame.fromBasis(bx, by, bz, a.p + rot(b.p, a))
	end,
	__add = function(a, v) return CFrame.fromBasis(a.x, a.y, a.z, a.p + v) end,
	__sub = function(a, v) return CFrame.fromBasis(a.x, a.y, a.z, a.p - v) end,
	__tostring = function(a) return "CFrame" .. tostring(a.p) end,
}
CFrame = {}
CFrame.fromBasis = function(x, y, z, p) return setmetatable({ x = x, y = y, z = z, p = p }, cfmt) end
CFrame.new = function(p, look) if look then return CFrame.lookAt(p, look) end; return CFrame.fromBasis(Vector3.xAxis, Vector3.yAxis, Vector3.zAxis, p or Vector3.zero) end
CFrame.Angles = function() return CFrame.new(Vector3.zero) end
CFrame.fromAxisAngle = function(axis, ang)
	local a = axis.Unit or axis
	local c, s = math.cos(ang), math.sin(ang)
	local t = 1 - c
	local x, y, z = a.X, a.Y, a.Z
	local r1 = Vector3.new(c + x * x * t, x * y * t + z * s, x * z * t - y * s)
	local r2 = Vector3.new(y * x * t - z * s, c + y * y * t, y * z * t + x * s)
	local r3 = Vector3.new(z * x * t + y * s, z * y * t - x * s, c + z * z * t)
	return CFrame.fromBasis(r1, r2, r3, Vector3.zero)
end
CFrame.lookAt = function(from, to)
	local back = (from - to).Unit
	local right = Vector3.new(0, 1, 0):Cross(back)
	if right.Magnitude < 1e-6 then right = Vector3.xAxis end
	right = right.Unit
	local up = back:Cross(right)
	return CFrame.fromBasis(right, up, back, from)
end
UDim = { new = function(s, o) return { Scale = s or 0, Offset = o or 0 } end }
UDim2 = {
	new = function(xs, xo, ys, yo) return { X = UDim.new(xs, xo), Y = UDim.new(ys, yo) } end,
	fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end,
	fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end,
}
local udmt = { __add = function(a, b) return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset) end }
setmetatable(UDim2, { __call = function(_, ...) return UDim2.new(...) end })
for _, f in ipairs({ "new", "fromOffset", "fromScale" }) do local orig = UDim2[f]; UDim2[f] = function(...) return setmetatable(orig(...), udmt) end end

local Enum = setmetatable({}, { __index = function(t, k)
	local sub = setmetatable({}, { __index = function(_, v) local item = { Name = v, EnumType = k }; rawset(t[k], v, item); return item end })
	rawset(t, k, sub)
	return sub
end })

-- 假引擎: 挂成全局, selfblox.lua 是另一个 chunk, 只能看全局
_G.Instance = { new = function(cls, parent) local i = inst(cls); if parent then i.Parent = parent end; return i end }
_G.RaycastParams = { new = function() return { FilterType = nil } end }
_G.Vector3, _G.Vector2, _G.Color3, _G.CFrame, _G.UDim, _G.UDim2, _G.Enum = Vector3, Vector2, Color3, CFrame, UDim, UDim2, Enum
if not warn then _G.warn = function(...) print("warn:", ...) end end

-- 假引擎: 场景
local function sig(props) props = props or {}; for _, n in ipairs({ "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving" }) do props[n] = Signal.new() end; return props end
game = { PlaceId = 0, Name = "SmokePlace", GetService = function(_, n) return assert(_G.__SVC[n], "没造的服: " .. n) end }
_G.__SVC = {}
local function svc(name, o) o = o or inst(name); _G.__SVC[name] = o; return o end

local workspace = svc("Workspace", inst("Workspace", sig()))
local camera = inst("Camera", { CFrame = CFrame.new(Vector3.zero), ViewportSize = Vector2.new(1080, 2400) })
workspace.props.CurrentCamera = camera
_G.workspace = workspace

local humanoid = inst("Humanoid", { WalkSpeed = 16, JumpPower = 50, JumpHeight = 7, Health = 100, UseJumpPower = true, MoveDirection = Vector3.zero })
local hrp = inst("Part", { Name = "HumanoidRootPart", CanCollide = true, Anchored = false, Size = Vector3.new(2, 2, 1), CFrame = CFrame.new(Vector3.new(0, 5, 0)), Position = Vector3.new(0, 5, 0), AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero, AssemblyMass = 10, AssemblyRootPart = nil })
hrp.props.AssemblyRootPart = hrp
local char = inst("Model", { Name = "Me" })
char.props.Humanoid, char.props.HumanoidRootPart = humanoid, hrp
humanoid.Parent, hrp.Parent = char, char
char.Parent = workspace
local player = inst("Player", { Name = "Me", DisplayName = "Me", UserId = 1, Character = char, Team = nil, TeamColor = nil, CharacterAdded = Signal.new() })
local pgui = inst("PlayerGui", sig())
pgui.Parent = player
svc("Players", inst("Players", { LocalPlayer = player, MaxPlayers = 12, GetPlayers = function() return { player } end, GetPlayerFromCharacter = function(_, c) return c == char and player or nil end, PlayerAdded = Signal.new(), PlayerRemoving = Signal.new() }))
svc("RunService", inst("RunService", { PreSimulation = Signal.new(), PreRender = Signal.new(), Heartbeat = Signal.new() }))
svc("UserInputService", inst("UserInputService", { JumpRequest = Signal.new(), TouchEnabled = true }))
svc("Lighting", inst("Lighting", { Ambient = Color3.fromRGB(70, 70, 70), OutdoorAmbient = Color3.fromRGB(70, 70, 70), Brightness = 1, FogEnd = 100000, GlobalShadows = true }))
svc("Stats", inst("Stats", { GetTotalMemoryUsageMb = function() return 512 end }))
svc("Teams", inst("Teams", { GetTeams = function() return {} end }))
svc("ReplicatedStorage", inst("ReplicatedStorage", sig()))
svc("VirtualInputManager", inst("VirtualInputManager"))
svc("HttpService", inst("HttpService"))
svc("CoreGui", inst("CoreGui", sig()))
player.props.GetNetworkPing = function() return 0.05 end
_G.CoreGui = _G.__SVC.CoreGui

-- 一辆假车 (座位 + 车身), 用来跑 sibs
local car = inst("Model", { Name = "Car" })
local seat = inst("VehicleSeat", { Name = "Seat", CanCollide = true, Anchored = false, Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(Vector3.new(10, 5, 0)), Position = Vector3.new(10, 5, 0), AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero, AssemblyMass = 20, MaxSpeed = 30, Steer = 0, Throttle = 0, Occupant = humanoid })
seat.props.AssemblyRootPart = seat
local carBody = inst("Part", { Name = "Body", CanCollide = true, Anchored = false, Size = Vector3.new(6, 2, 12), CFrame = CFrame.new(Vector3.new(10, 5, 0)), Position = Vector3.new(10, 5, 0), AssemblyLinearVelocity = Vector3.zero, AssemblyMass = 20, AssemblyRootPart = seat })
carBody.props.AssemblyRootPart = seat
seat.Parent, carBody.Parent = car, car
car.Parent = workspace

-- ───────── 假执行器: 文件 / 剪贴板 / 钩子 / task / JSON ─────────
local VFS, CLIP = {}, nil
isfile = function(p) return VFS[p] ~= nil end
readfile = function(p) return VFS[p] end
writefile = function(p, s) VFS[p] = s end
appendfile = function(p, s) VFS[p] = (VFS[p] or "") .. s end
setclipboard = function(s) CLIP = s end
gethui = function() return _G.CoreGui end
newcclosure = function(f) return f end
getnamecallmethod = function() return "FireServer" end
hookmetamethod = function(o, m, f) local old = _G.__hook; _G.__hook = f; return old or function() end end
typeof = function(v)
	if type(v) == "table" then
		local mtv = getmetatable(v)
		if v.ClassName then return "Instance" end
		if mtv == v3mt then return "Vector3" end
		if mtv == cfmt then return "CFrame" end
		if v.R and v.G and v.B and not v.X then return "Color3" end
		if v.EnumType then return "EnumItem" end
	end
	return type(v)
end
local NOW, WAITERS = 0, {}
event = {}
task = {
	spawn = function(f, ...) local co = coroutine.create(f); local ok, err = coroutine.resume(co, ...); if not ok then error("task.spawn: " .. tostring(err), 0) end; return co end,
	defer = function(f, ...) return task.delay(0, f, ...) end,
	delay = function(t, f, ...)
		local a = table.pack(...)
		local co = coroutine.create(function() f(unpack(a, 1, a.n)) end)
		WAITERS[#WAITERS + 1] = { co = co, t = NOW + (t or 0) }
		return co
	end,
	wait = function(t) WAITERS[#WAITERS + 1] = { co = coroutine.running(), t = NOW + (t or 0) }; coroutine.yield() end,
}
local function jsonEncode(v)
	local t = type(v)
	if t == "nil" then return "null" end
	if t == "number" or t == "boolean" then return tostring(v) end
	if t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
	if t == "table" then
		if #v > 0 or next(v) == nil then local o = {}; for i = 1, #v do o[i] = jsonEncode(v[i]) end; return "[" .. table.concat(o, ",") .. "]" end
		local o = {}; for k, x in pairs(v) do o[#o + 1] = '"' .. tostring(k) .. '":' .. jsonEncode(x) end; return "{" .. table.concat(o, ",") .. "}"
	end
	return "null"
end
local function jsonDecode(s)
	local i = 1
	local function skip() while i <= #s and s:sub(i, i):match("%s") do i = i + 1 end end
	local parse
	local function str() i = i + 1; local o = {}; while true do if i > #s then error("JSON 字符串没闭合") end; local c = s:sub(i, i); if c == '"' then i = i + 1; break elseif c == "\\" then local n = s:sub(i + 1, i + 1); if n == "u" then local h = s:sub(i + 2, i + 5); o[#o + 1] = string.char(tonumber(h, 16) % 256); i = i + 6 else o[#o + 1] = n; i = i + 2 end else o[#o + 1] = c; i = i + 1 end end; return table.concat(o) end
	parse = function()
		skip()
		if i > #s then error("JSON 意外结束") end -- 假解码器也得会报错, 不然死循环吃光内存
		local c = s:sub(i, i)
		if c == "{" then
			i = i + 1; local o = {}; skip()
			if s:sub(i, i) == "}" then i = i + 1; return o end
			while true do skip(); local k = str(); skip(); i = i + 1; o[k] = parse(); skip(); if s:sub(i, i) == "," then i = i + 1 else i = i + 1; break end end
			return o
		elseif c == "[" then
			i = i + 1; local o = {}; skip()
			if s:sub(i, i) == "]" then i = i + 1; return o end
			while true do o[#o + 1] = parse(); skip(); if s:sub(i, i) == "," then i = i + 1 else i = i + 1; break end end
			return o
		elseif c == '"' then return str() end
		if s:sub(i, i + 3) == "true" then i = i + 4; return true end
		if s:sub(i, i + 4) == "false" then i = i + 5; return false end
		if s:sub(i, i + 3) == "null" then i = i + 4; return nil end
		local n = assert(s:match("^[%-%d%.eE]+", i), "坏 JSON @" .. i .. ": " .. s:sub(i, i + 20))
		i = i + #n; return tonumber(n)
	end
	return parse()
end
_G.__SVC.HttpService.props.JSONEncode = function(_, v) return jsonEncode(v) end
_G.__SVC.HttpService.props.JSONDecode = function(_, s) return jsonDecode(s) end

-- ───────── 断言 + 步进 ─────────
local FAILS = 0
local function ok(cond, msg) if cond then print("  ✓ " .. msg) else FAILS = FAILS + 1; print("  ✗ " .. msg) end end
local function step(dt, n)
	for _ = 1, (n or 1) do
		NOW = NOW + dt
		local due = {}; local keep = {}
		for _, w in ipairs(WAITERS) do if w.t <= NOW then due[#due + 1] = w else keep[#keep + 1] = w end end
		WAITERS = keep
		for _, w in ipairs(due) do
			if coroutine.status(w.co) ~= "dead" then
				local ok2, err = coroutine.resume(w.co)
				if not ok2 then error("任务里炸了: " .. tostring(err), 0) end
			end
		end
		_G.__SVC.RunService.props.PreSimulation:Fire(dt)
		_G.__SVC.RunService.props.PreRender:Fire(dt)
		if _G.__SVC.UserInputService.props.JumpRequest then _G.__SVC.UserInputService.props.JumpRequest:Fire() end
	end
end
local function tabs() return _G.__SVC.CoreGui:FindFirstChild("Selfblox") end
local function all() local g = tabs(); return g and g:GetDescendants() or {} end
local function buttons() local o = {}; for _, d in ipairs(all()) do if d:IsA("TextButton") and d.Text ~= "–" and d.Text ~= "+" then o[#o + 1] = d end end; return o end
local function findBtn(prefix) for _, b in ipairs(buttons()) do if b.Text:sub(1, #prefix) == prefix then return b end end end
local function input(kind) return { UserInputType = Enum.UserInputType[kind] } end
local function ends(s, suf) return #s >= #suf and s:sub(-#suf) == suf end
local function starts(s, pre) return s:sub(1, #pre) == pre end
local function click(b) b.Activated:Fire() end
local function newInstancesFrom(n) local o = {}; for i = n + 1, #INSTANCES do o[#o + 1] = INSTANCES[i] end; return o end

print("── 假引擎就绪: " .. #INSTANCES .. " 个场景实例")
local SNAP = #INSTANCES

-- ───────── 第一轮: 全量加载 ─────────
print("\n[1] 加载 selfblox.lua")
local chunk = assert(load_chunk(SRC, "selfblox"))
local okLoad, errLoad = pcall(chunk)
ok(okLoad, "脚本跑完没报错 " .. tostring(errLoad or ""))
ok(type(_G.SB_UNLOAD) == "function", "_G.SB_UNLOAD 有了")
ok(tabs() ~= nil, "面板建在 gethui() 里")
local names = {}
for _, b in ipairs(buttons()) do if #b.Text <= 3 and b.Text ~= "" then names[b.Text] = true end end
ok(names["动"] and names["车"] and names["漂"] and names["显"] and names["志"] and names["机"] and names["砖"], "七个页签都在")
ok(#newInstancesFrom(SNAP) > 60, "控件建了 " .. #newInstancesFrom(SNAP) .. " 个实例")

print("\n[2] 空转 30 帧 (没有任何开关)")
step(1 / 60, 30)
ok(true, "空转没炸")

print("\n[3] 页签逐个点")
for _, t in ipairs({ "动", "车", "漂", "显", "志", "机", "砖" }) do
	local b = findBtn(t)
	click(b)
	local on = 0
	for _, x in ipairs(buttons()) do if x.Text == t and x.BackgroundColor3.G > 0.4 then on = on + 1 end end
	ok(on == 1, "点「" .. t .. "」后只有它高亮")
end

print("\n[4] 角色模块: 开速度 → 真的动")
local spd = findBtn("速度")
click(spd)
humanoid.props.MoveDirection = Vector3.new(0, 0, -1)
step(1 / 60, 10)
local vel = hrp.AssemblyLinearVelocity
ok(math.abs(vel.Z) > 10, "开关开着时 root 水平速度 = " .. string.format("%.1f", math.abs(vel.Z)))
click(findBtn("速度"))
humanoid.props.MoveDirection = Vector3.zero
step(1 / 60, 3)

print("\n[5] 角色模块: 飞行/穿墙/夜视/秒互动")
click(findBtn("飞行"))
step(1 / 60, 3)
local att = hrp:FindFirstChild("SB_MOC")
ok(att and att:FindFirstChild("LinearVelocity") and att:FindFirstChild("AlignOrientation"), "飞行挂上了原生 LinearVelocity + AlignOrientation")
ok(humanoid.PlatformStand == true, "飞行时 PlatformStand 打开")
click(findBtn("飞行"))
click(findBtn("穿墙"))
step(1 / 60, 3)
ok(hrp.CanCollide == false, "穿墙后部件 CanCollide=false")
click(findBtn("穿墙"))
step(1 / 60, 3)
ok(hrp.CanCollide == true, "关掉后 CanCollide 还原")
click(findBtn("夜视"))
step(1 / 60, 3)
ok(_G.__SVC.Lighting.Brightness > 1, "夜视改了 Lighting")
click(findBtn("夜视"))
click(findBtn("秒互动"))
ok(true, "秒互动按钮能点")
click(findBtn("模式"))
ok(findBtn("模式") ~= nil, "模式按钮循环后还在")

print("\n[6] 车模块: 坐进假车")
humanoid.props.SeatPart = seat
seat.props.Throttle, seat.props.Steer = 1, 0.5
for _, b in ipairs(buttons()) do if starts(b.Text, "穿墙") and ends(b.Text, " 关") then click(b) end end -- moc + sibs 两个穿墙都开
step(1 / 60, 10)
ok(seat.MaxSpeed == math.huge, "上车后座位限速抬到无穷")
local clipOn = 0
for _, b in ipairs(buttons()) do if starts(b.Text, "穿墙") and ends(b.Text, " 开") then clipOn = clipOn + 1 end end
ok(seat.CanCollide == false and carBody.CanCollide == false, "穿墙开着时车部件 CanCollide=false (穿墙开着 " .. clipOn .. " 个 · 座=" .. tostring(seat.CanCollide) .. " 身=" .. tostring(carBody.CanCollide) .. ")")
ok(seat:FindFirstChild("SB_SIBS") ~= nil, "车约束挂在座位装配体上")
click(findBtn("常亮"))
step(1 / 60, 3)
local lamps = 0
for _, d in ipairs(seat:GetDescendants()) do if d:IsA("Light") then lamps = lamps + 1 end end
ok(lamps >= 2, "车上没灯时自己装了 " .. lamps .. " 个 SpotLight")
click(findBtn("常亮"))
click(findBtn("飞车"))
step(1 / 60, 5)
ok(seat:FindFirstChild("SB_SIBS"):FindFirstChildOfClass("LinearVelocity") ~= nil, "飞车换成原生 LinearVelocity")
click(findBtn("飞车"))
click(findBtn("急刹"))
seat.props.Throttle, seat.props.AssemblyLinearVelocity = 0, Vector3.new(30, 5, 0) -- 松开游戏油门, 免得急刹被"踩油门自动解除"顶掉
step(1 / 60, 2)
ok(seat.AssemblyLinearVelocity.Z == 0 and seat.AssemblyLinearVelocity.X == 0, "急刹把水平速度清了, 保留竖直 " .. tostring(seat.AssemblyLinearVelocity.Y))
click(findBtn("急刹"))

print("\n[7] 全部控件点一遍 (开), 30 帧, 再点一遍 (关)")
local flipped, held = 0, 0
for _, b in ipairs(buttons()) do if ends(b.Text, " 关") then click(b); flipped = flipped + 1 end end
for _, b in ipairs(buttons()) do b.InputBegan:Fire(input("Touch")); held = held + 1 end
step(1 / 60, 30)
for _, b in ipairs(buttons()) do b.InputEnded:Fire(input("Touch")) end
step(1 / 60, 10)
ok(flipped >= 15, "开了 " .. flipped .. " 个开关")
for _, b in ipairs(buttons()) do if ends(b.Text, " 开") then click(b); flipped = flipped - 1 end end
step(1 / 60, 10)
ok(true, "按住/松开 " .. held .. " 个按钮 + 全开全关走完没炸")
ok(_G.__SVC.VirtualInputManager.props.keys ~= nil, "喇叭真的发了按键事件")

print("\n[8] 写盘 / 剪贴板")
ok(VFS["Selfblox.json"] ~= nil, "改过的值写进了 Selfblox.json")
ok(jsonDecode(VFS["Selfblox.json"]).tab ~= nil, "JSON 里有上次页签")

print("\n[9] 卸载")
humanoid.props.SeatPart = nil
local before = newInstancesFrom(SNAP)
_G.SB_UNLOAD()
step(1 / 60, 10)
local leaked = 0
for _, i in ipairs(before) do if not i.destroyed then leaked = leaked + 1 end end
ok(tabs() == nil, "面板整个没了")
ok(leaked == 0, "没漏实例 (漏了 " .. leaked .. " 个)")
ok(LIVE == 0, "没漏连接 (还剩 " .. LIVE .. " 个)")
ok(_G.SB_UNLOAD == nil, "SB_UNLOAD 自己清了")

-- ───────── 第二轮: 只装 moc + _G.SB 覆盖 ─────────
print("\n[10] _G.SB 覆盖 + only 过滤")
SNAP = #INSTANCES
_G.SB = { only = { "moc" }, spd = 99 }
local fn2, lerr2 = load_chunk(SRC, "selfblox2")
ok(fn2 ~= nil, "第二轮语法 OK " .. tostring(lerr2 or ""))
local ok2, err2 = pcall(fn2)
ok(ok2, "再跑一次没报错 " .. tostring(err2 or ""))
local n = 0
for _, d in ipairs(all()) do if d:IsA("TextButton") and d.Text == "动" then n = n + 1 end end
ok(n == 1, "only={moc} 只留了「动」一个页签")
local box = nil
for _, d in ipairs(all()) do if d:IsA("TextBox") then box = d; break end end
ok(box and box.Text == "99", "_G.SB.spd=99 顶掉了默认 16")
step(1 / 60, 5)
_G.SB_UNLOAD()
step(1 / 60, 5)
leaked = 0
for _, i in ipairs(newInstancesFrom(SNAP)) do if not i.destroyed then leaked = leaked + 1 end end
ok(leaked == 0 and LIVE == 0, "第二轮同样卸载干净")

-- ───────── 第三轮: 配置文件被写坏也要能起 ─────────
print("\n[11] 坏掉的 Selfblox.json")
VFS["Selfblox.json"] = "{这不是 JSON"
SNAP = #INSTANCES
local fn3, lerr3 = load_chunk(SRC, "selfblox3")
ok(fn3 ~= nil, "语法 OK " .. tostring(lerr3 or ""))
local ok3, err3 = pcall(fn3)
ok(ok3, "配置坏了照样起面板 " .. tostring(err3 or ""))
ok(tabs() ~= nil, "面板确实建出来了")
_G.SB_UNLOAD()
step(1 / 60, 3)
leaked = 0
for _, i in ipairs(newInstancesFrom(SNAP)) do if not i.destroyed then leaked = leaked + 1 end end
ok(leaked == 0 and LIVE == 0, "第三轮卸载同样干净")

print("\n" .. (FAILS == 0 and "全部通过 ✓" or ("有 " .. FAILS .. " 条没过 ✗")))
if os.exit then os.exit(FAILS == 0 and 0 or 1) end
if FAILS ~= 0 and error then error(FAILS .. " 条没过", 0) end
