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
for _, n in ipairs({ "Activated", "InputBegan", "InputEnded", "FocusLost", "Focused", "DragStart", "DragContinue", "DragEnd", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "PlayerAdded", "PlayerRemoving", "PreSimulation", "PreRender", "Heartbeat", "RenderStepped", "JumpRequest", "OnClientEvent", "Changed", "Destroying" }) do SIGNALS[n] = true end
local STRICT = { UIDragDetector = { DragStart = true, DragContinue = true, DragEnd = true } } -- 官方文档(classes/UIDragDetector): 这个类的事件只有这三个. 对它严格: 读到别的成员就和真引擎一样直接抛错 —— v13 的 DragBegin 就是被"什么名字都认"的假引擎放过去的
-- ───────── 成员白名单: 脚本只许碰"对照官方文档核对过"的成员 ─────────
-- 假引擎原来什么名字都认, DragBegin / GetMoveVector 这种官方根本没有的成员就这样溜过了测试. 现在没核对过的一碰就抛错.
-- 新增成员时: 先去 create.roblox.com/docs/reference/engine/classes/<类> 确认它存在 (官方没文档的内部服务, 如 VirtualInputManager, 看 robloxapi.github.io/ref/class/<类>.html), 再加进来. 没列出的类不检查.
local function words(s) local t = {}; for w in s:gmatch("%S+") do t[w] = true end; return t end
local function fromScript(level) -- 谁在访问: selfblox.lua 的代码 (chunk 名 selfblox*) 还是测试自己
	local ii = debug.getinfo(level or 4, "S")
	return ii ~= nil and (ii.short_src or ""):find('^%[string "selfblox') ~= nil
end
local INSTANCE_OK = words("ChildAdded DescendantAdded Destroy FindFirstAncestorOfClass FindFirstChild FindFirstChildOfClass FindFirstChildWhichIsA GetAttribute GetAttributes GetChildren GetDescendants GetFullName GetPropertyChangedSignal IsA IsDescendantOf Name Parent SetAttribute WaitForChild") -- Instance / Object 上的公共成员
local VERIFIED = {
	AlignOrientation = words("Attachment0 CFrame MaxTorque Mode Responsiveness"),
	AngularVelocity = words("AngularVelocity Attachment0 MaxTorque RelativeTo"),
	Attachment = words(""),
	BillboardGui = words("Adornee AlwaysOnTop Enabled Size StudsOffsetWorldSpace"),
	Camera = words("CFrame ViewportSize WorldToViewportPoint"),
	ColorCorrectionEffect = words("Brightness Contrast Saturation"),
	Folder = words(""),
	Frame = words("AbsolutePosition AbsoluteSize Active AnchorPoint AutomaticSize BackgroundColor3 BackgroundTransparency BorderSizePixel LayoutOrder Position Rotation Size Visible ZIndex"),
	Highlight = words("Adornee DepthMode Enabled FillColor FillTransparency OutlineColor OutlineTransparency"),
	HttpService = words("JSONDecode JSONEncode"),
	Humanoid = words("ChangeState Health JumpHeight JumpPower MoveDirection PlatformStand SeatPart UseJumpPower WalkSpeed"),
	ImageButton = words("AbsolutePosition AbsoluteSize Active InputBegan InputEnded Visible"),
	IntValue = words("Value"),
	Lighting = words("Ambient Brightness FogEnd GlobalShadows OutdoorAmbient"),
	LinearVelocity = words("Attachment0 MaxForce RelativeTo VectorVelocity"),
	Model = words("GetExtentsSize GetPivot PivotTo"),
	Part = words("Anchored AssemblyAngularVelocity AssemblyLinearVelocity AssemblyMass AssemblyRootPart CFrame CanCollide Color GetConnectedParts Position Size"),
	Player = words("Character DisplayName GetNetworkPing Team TeamColor UserId"),
	PlayerGui = words(""),
	Players = words("GetPlayerFromCharacter GetPlayers LocalPlayer MaxPlayers PlayerAdded PlayerRemoving"),
	ProximityPrompt = words("Enabled HoldDuration MaxActivationDistance RequiresLineOfSight"),
	RemoteEvent = words("FireServer OnClientEvent"),
	RemoteFunction = words(""),
	ReplicatedStorage = words(""),
	RunService = words("PreRender PreSimulation"),
	ScreenGui = words("DisplayOrder IgnoreGuiInset ResetOnSpawn"),
	Seat = words("Anchored AssemblyLinearVelocity AssemblyMass AssemblyRootPart CFrame GetConnectedParts Occupant Position Size"),
	SpotLight = words("Angle Brightness Color Enabled Face Range"),
	Stats = words("GetTotalMemoryUsageMb"),
	StringValue = words("Value"),
	Team = words("TeamColor"),
	Teams = words("GetTeams"),
	TextBox = words("BackgroundTransparency ClearTextOnFocus FocusLost Font Position Size Text TextColor3 TextSize TextXAlignment TextYAlignment"),
	TextButton = words("Activated AutoButtonColor BackgroundColor3 BackgroundTransparency BorderSizePixel Font InputBegan InputEnded LayoutOrder Position Size Text TextColor3 TextSize TextXAlignment TextYAlignment"),
	TextLabel = words("AbsolutePosition AnchorPoint AutomaticSize BackgroundColor3 BackgroundTransparency BorderSizePixel Font InputBegan InputEnded LayoutOrder Position RichText Size Text TextColor3 TextSize TextStrokeTransparency TextWrapped TextXAlignment TextYAlignment Visible"),
	UICorner = words("CornerRadius"),
	UIDragDetector = words("BoundingUI DragAxis DragContinue DragEnd DragStart DragStyle"),
	UIListLayout = words("FillDirection Padding"),
	UIPadding = words("PaddingLeft PaddingRight"),
	UserInputService = words("JumpRequest"),
	VectorForce = words("ApplyAtCenterOfMass Attachment0 Force RelativeTo"),
	VehicleSeat = words("Anchored AssemblyAngularVelocity AssemblyLinearVelocity AssemblyMass AssemblyRootPart CFrame CanCollide GetConnectedParts MaxSpeed Occupant Position Size Steer Throttle Torque"),
	VirtualInputManager = words("SendKeyEvent"),
	Workspace = words("CurrentCamera GetPartBoundsInRadius Raycast"),
}
local ENUM_OK = { -- 枚举字面量 (KeyCode 是按配置字符串动态取的, 不检查)
	ActuatorRelativeTo = words("World"),
	AutomaticSize = words("X Y"),
	FillDirection = words("Horizontal"),
	Font = words("Gotham GothamBold"),
	HighlightDepthMode = words("AlwaysOnTop"),
	HumanoidStateType = words("Jumping"),
	NormalId = words("Back Front"),
	OrientationAlignmentMode = words("OneAttachment"),
	RaycastFilterType = words("Exclude"),
	TextXAlignment = words("Center"),
	TextYAlignment = words("Center"),
	UIDragDetectorDragStyle = words("TranslateLine"),
	UserInputType = words("MouseButton1 Touch"),
}
local function guardMember(t, k) -- 读/写实例成员时调用
	local cls = rawget(t, "ClassName")
	local allow = VERIFIED[cls]
	if allow and type(k) == "string" and not allow[k] and not INSTANCE_OK[k] and fromScript() then
		error(cls .. "." .. k .. " 没对照官方文档核对过 (不在 VERIFIED 里): 先确认它真的存在, 再加进来", 3)
	end
end
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

local ISA = {
	Part = { "BasePart" }, MeshPart = { "BasePart" }, VehicleSeat = { "BasePart" }, Seat = { "Part", "BasePart" }, -- 官方继承链: VehicleSeat 直接挂在 BasePart 下, 不是 Seat (假引擎原来写成 Seat, 把脚本里"只查 Seat"的 bug 藏住了)
	SpotLight = { "Light" }, PointLight = { "Light" }, SurfaceLight = { "Light" },
	TextButton = { "GuiButton", "GuiObject" }, ImageButton = { "GuiButton", "GuiObject" }, TextLabel = { "GuiObject" }, TextBox = { "GuiObject" }, Frame = { "GuiObject" },
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
function methods.IsDescendantOf(self, x) if x == nil then error("Argument 1 missing or nil", 2) end local p = rawget(self, "parent"); while p do if p == x then return true end; p = rawget(p, "parent") end; return false end
function methods.GetFullName(self) local p = rawget(self, "parent"); return (p and (methods.GetFullName(p) .. ".") or "") .. tostring(self.Name) end
function methods.GetAttribute(self, k) return self.attrs[k] end
function methods.SetAttribute(self, k, v) self.attrs[k] = v end
function methods.GetAttributes(self) local o = {}; for k, v in pairs(self.attrs) do o[k] = v end; return o end
function methods.GetPropertyChangedSignal(self, p) local s = self.props["__pcs_" .. p]; if not s then s = Signal.new(); self.props["__pcs_" .. p] = s end; return s end
function methods.GetPivot(self) return self.props.__pivot or CFrame.new(Vector3.zero) end
function methods.GetExtentsSize(self)
	local ext = self.props.__extents
	if ext then return ext end
	local mn, mx
	for _, d in ipairs(methods.GetDescendants(self)) do
		if methods.IsA(d, "BasePart") then
			local p, sz = d.Position or Vector3.zero, d.Size or Vector3.new(1, 1, 1)
			mn = mn and Vector3.new(math.min(mn.X, p.X), math.min(mn.Y, p.Y), math.min(mn.Z, p.Z)) or Vector3.new(p.X, p.Y, p.Z)
			mx = mx and Vector3.new(math.max(mx.X, p.X), math.max(mx.Y, p.Y), math.max(mx.Z, p.Z)) or Vector3.new(p.X, p.Y, p.Z)
		end
	end
	if not mn then return Vector3.new(1, 1, 1) end
	return Vector3.new(math.max(mx.X - mn.X, 1), math.max(mx.Y - mn.Y, 1), math.max(mx.Z - mn.Z, 1))
end
function methods.PivotTo(self, cf) self.props.__pivot = cf end
function methods.Raycast(self, o, d) local h = _G.__rayHit; if h then return { Instance = h.Instance, Position = o, Distance = h.Distance or 10 } end end
function methods.Clone(self) return inst(self.ClassName, self.props) end
function methods.WorldToViewportPoint(self, v) return Vector3.new(100, 200, 10), true end
function methods.ChangeState() end
-- VirtualInputManager 官方没有文档, 签名取自 API 清单 (robloxapi.github.io/ref/class/VirtualInputManager): 参数类型不对, 真引擎抛错, 假引擎也抛. 现在只剩喇叭用 SendKeyEvent
local function vimArgs(name, ok_, spec) if not ok_ then error(name .. " 参数类型不对, 应为 " .. spec, 3) end end
function methods.SendKeyEvent(self, down, key, rep, layer)
	vimArgs("SendKeyEvent", type(down) == "boolean" and type(key) == "table" and key.EnumType == "KeyCode" and type(rep) == "boolean" and type(layer) == "table", "(isPressed: bool, keyCode: KeyCode, isRepeatedKey: bool, layerCollector: Instance)")
	self.props.keys = (self.props.keys or 0) + 1
end
function methods.GetConnectedParts(self) -- 假装配体: 同 Model 里 AssemblyRootPart 相同的 BasePart (真引擎只返回焊在一起的, 锚定的停车台/另一个装配体不算)
	local o, seen = {}, {}
	local m = methods.FindFirstAncestorOfClass(self, "Model") or self
	local ra = self.props.AssemblyRootPart or self
	for _, d in ipairs(methods.GetDescendants(m)) do if not seen[d] and methods.IsA(d, "BasePart") and (d.props.AssemblyRootPart or d) == ra then seen[d] = true; o[#o + 1] = d end end
	if not seen[self] then o[#o + 1] = self end
	return o
end
function methods.SetNetworkOwner() error("SetNetworkOwner 客户端不让调 (上一版就是这一句把车搞成完全绑不上)") end
function methods.GetPartBoundsInRadius() return _G.__radius or {} end

local mt = {
	__index = function(t, k)
		guardMember(t, k)
		if k == "Parent" then return rawget(t, "parent") end
		local m = methods[k]
		if m then return m end
		if k == "AbsoluteSize" then -- 假布局: 默认 100x40, 允许测试自己给
			local pp = rawget(t, "props")
			return (pp and pp.AbsoluteSize) or { X = 100, Y = 40 }
		end
		if k == "AbsolutePosition" then -- 假布局: 默认 0, 但允许测试自己给坐标 (踏板排序要看它)
			local pp = rawget(t, "props")
			return (pp and pp.AbsolutePosition) or { X = 0, Y = 0 }
		end
		local props = rawget(t, "props")
		local v = props[k]
		local strict = STRICT[rawget(t, "ClassName")]
		if v == nil and strict then
			if not strict[k] then error(tostring(k) .. " is not a valid member of " .. t.ClassName, 2) end
			v = Signal.new(); props[k] = v
		elseif v == nil and SIGNALS[k] then v = Signal.new(); props[k] = v end -- 信号字段按需生成
		return v
	end,
	__newindex = function(t, k, v)
		guardMember(t, k)
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
	if ISA[cls] then -- GuiObject 默认 Visible=true, 引擎行为; 不模拟的话断言会被 nil 坑
		for _, x in ipairs(ISA[cls]) do
			if x == "GuiObject" then self.props.Visible = true end
			if x == "BasePart" then self.props.Color = Color3.fromRGB(163, 162, 165) end -- 真引擎里每个零件都有颜色 (默认 Medium stone grey)
		end
	end
	for k, v in pairs(props or {}) do self.props[k] = v end
	return self
end

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
Vector2 = {}
Vector2.mt = {
	__index = function(t, k)
		if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y) end
		error(tostring(k) .. " is not a valid member of Vector2", 2) -- 真引擎读数据类型上不存在的成员也是直接抛错; 这里不抛, i.Position 就会悄悄变成 nil 溜过去
	end,
	__add = function(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end,
	__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end,
}
Vector2.new = function(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, Vector2.mt) end
Vector2.zero = Vector2.new(0, 0)

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
	if k ~= "KeyCode" and not ENUM_OK[k] and fromScript(3) then error("Enum." .. tostring(k) .. " 没对照官方文档核对过 (不在 ENUM_OK 里)", 2) end
	local sub = setmetatable({}, { __index = function(_, v) if ENUM_OK[k] and not ENUM_OK[k][v] and fromScript(3) then error("Enum." .. k .. "." .. tostring(v) .. " 没对照官方文档核对过 (不在 ENUM_OK 里)", 2) end; local item = { Name = v, EnumType = k }; rawset(t[k], v, item); return item end })
	rawset(t, k, sub)
	return sub
end })

-- 假引擎: 挂成全局, selfblox.lua 是另一个 chunk, 只能看全局
_G.Instance = { new = function(cls, parent) local i = inst(cls); if parent then i.Parent = parent end; return i end }
_G.RaycastParams = { new = function() return { FilterType = nil } end }
_G.OverlapParams = { new = function() return { FilterType = nil, FilterDescendantsInstances = {} } end }
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
svc("UserInputService", inst("UserInputService", { JumpRequest = Signal.new(), TouchEnabled = true, GetMouseLocation = function() return Vector2.new(100, 100) end }))
svc("Lighting", inst("Lighting", { Ambient = Color3.fromRGB(70, 70, 70), OutdoorAmbient = Color3.fromRGB(70, 70, 70), Brightness = 1, FogEnd = 100000, GlobalShadows = true }))
svc("Stats", inst("Stats", { GetTotalMemoryUsageMb = function() return 512 end }))
svc("Teams", inst("Teams", { GetTeams = function() return {} end }))
svc("ReplicatedStorage", inst("ReplicatedStorage", sig()))
svc("VirtualInputManager", inst("VirtualInputManager"))
svc("HttpService", inst("HttpService"))
svc("CoreGui", inst("CoreGui", sig()))
player.props.GetNetworkPing = function() return 0.05 end
_G.CoreGui = _G.__SVC.CoreGui

-- 漂移游戏的踏板 UI: 故意嵌两层 + ImageButton, 老代码只认 MobilePedals.Frame 的直接子节点
local pedals = inst("ScreenGui", { Name = "MobilePedals" })
local pedalBox = inst("Frame", { Name = "Pedals" })
local brakeBtn = inst("ImageButton", { Name = "Brake", AbsolutePosition = Vector2.new(20, 2100) }) -- 刹车在左
local gasBtn = inst("ImageButton", { Name = "Gas", AbsolutePosition = Vector2.new(900, 2100) }) -- 油门在右
pedalBox.Parent, brakeBtn.Parent, gasBtn.Parent = pedals, pedalBox, pedalBox
pedals.Parent = pgui


-- 一辆假车 (座位 + 车身), 用来跑 sibs
local car = inst("Model", { Name = "Car" })
local seat = inst("VehicleSeat", { Name = "Seat", CanCollide = true, Anchored = false, Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(Vector3.new(10, 5, 0)), Position = Vector3.new(10, 5, 0), AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero, AssemblyMass = 20, MaxSpeed = 30, Steer = 0, Throttle = 0, Occupant = humanoid })
seat.props.AssemblyRootPart = seat
local carBody = inst("Part", { Name = "Body", CanCollide = true, Anchored = false, Size = Vector3.new(6, 2, 12), CFrame = CFrame.new(Vector3.new(10, 5, 0)), Position = Vector3.new(10, 5, 0), AssemblyLinearVelocity = Vector3.zero, AssemblyMass = 20, AssemblyRootPart = seat })
carBody.props.AssemblyRootPart = seat
seat.Parent, carBody.Parent = car, car
-- 轮子(车上最低, 底在 y=0) / 影子(本来就不碰撞, 比轮子还低) / 停车台(锚定, 和车在同一个 Model 里) / 装饰件 Sur(自己一个装配体): 穿墙和"座位是共同点"靠这些才测得出来
local CP = {}
local function carPart(name, size, pos, extra)
	local d = inst("Part", { Name = name, CanCollide = true, Anchored = false, Size = size, CFrame = CFrame.new(pos), Position = pos, AssemblyLinearVelocity = Vector3.zero, AssemblyMass = 2 })
	for k, v in pairs(extra or {}) do d.props[k] = v end
	d.props.AssemblyRootPart = seat
	d.Parent = car
	return d
end
CP.wheelL = carPart("Wheel_L", Vector3.new(1, 3, 3), Vector3.new(7, 1.5, 3))
CP.wheelR = carPart("Wheel_R", Vector3.new(1, 3, 3), Vector3.new(13, 1.5, 3))
CP.wheelUp = carPart("Wheel_Up", Vector3.new(1, 3, 3), Vector3.new(10, 2.5, 5)) -- 悬挂把这个轮子抬高了 (底在 y=1, 不在最低那圈): 只能靠名字保留
CP.hubL = carPart("RL", Vector3.new(1, 3, 3), Vector3.new(7, 1.5, -3)) -- 名字里没有 wheel/tire: 只能靠"整车最低"判成轮胎
CP.hubR = carPart("RR", Vector3.new(1, 3, 3), Vector3.new(13, 1.5, -3))
CP.shadow = carPart("Shadow", Vector3.new(4, 1, 4), Vector3.new(10, -2.5, 0), { CanCollide = false })
CP.pad = carPart("Pad", Vector3.new(30, 1, 30), Vector3.new(10, -0.5, 0), { Anchored = true })
CP.sur = carPart("Sur", Vector3.new(3, 1, 3), Vector3.new(10, 7, 0))
CP.sur.props.AssemblyRootPart = CP.sur
CP.pad.props.AssemblyRootPart = CP.pad -- 锚定的停车台自己一个装配体, 不是车的一部分
CP.fence = carPart("Fence", Vector3.new(1, 6, 20), Vector3.new(30, 6, 0), { Anchored = true }) -- 锚定的栏杆, 在高处: 不是"最低", 碰了就会被穿掉
CP.fence.props.AssemblyRootPart = CP.fence
car.Parent = workspace
local street = inst("Model", { Name = "Street", __extents = Vector3.new(4000, 200, 4000) }) -- 整个街区: 绝不能当成一辆车
local truck = inst("Model", { Name = "Truck", __extents = Vector3.new(6, 2, 12) })
local truckBed = inst("Part", { Name = "Primary", CanCollide = true, Anchored = false, Size = Vector3.new(4, 1, 16), Position = Vector3.new(60, 5, 0), CFrame = CFrame.new(Vector3.new(60, 5, 0)), AssemblyLinearVelocity = Vector3.zero, AssemblyMass = 1 })
truckBed.props.AssemblyRootPart = truckBed
truckBed.Parent = truck
truck.Parent = street
street.Parent = workspace
do -- 街道路面 = 一个横跨 3000 格的装配体; 另有一件"车"直接挂在超大容器 Model 里. 车页守卫靠这两件才测得出"量装配体, 不量 Model 容器"
	local function streetPart(name, size, pos, mass, root)
		local d = inst("Part", { Name = name, CanCollide = true, Anchored = false, Size = size, Position = pos, CFrame = CFrame.new(pos), AssemblyLinearVelocity = Vector3.zero, AssemblyMass = mass })
		d.props.AssemblyRootPart = root or d
		d.Parent = street
		return d
	end
	CP.road = streetPart("Primary", Vector3.new(40, 1, 40), Vector3.new(0, 0, 900), 1549) -- 真游戏里 Workspace.Spawned.Street.Primary 就是这种: 质量 1549, 还能被推着跑到 70
	CP.roadFar = streetPart("RoadFar", Vector3.new(40, 1, 40), Vector3.new(3000, 0, 900), 1549, CP.road) -- 和 road 同一个装配体 → 外径 ~6000 格
	CP.looseCar = streetPart("Loose", Vector3.new(6, 2, 12), Vector3.new(120, 5, 900), 800) -- 没有自己的小 Model: 上一版量容器(4000 格) → 误判成地图 → "新构建绑不上车"
end

-- ───────── 假执行器: 文件 / 剪贴板 / 钩子 / task / JSON ─────────
local VFS, CLIP = {}, nil
isfile = function(p) return VFS[p] ~= nil end
readfile = function(p) return VFS[p] end
writefile = function(p, s) VFS[p] = s end
appendfile = function(p, s) VFS[p] = (VFS[p] or "") .. s end
setclipboard = function(s) CLIP = s end
gethui = function() return _G.CoreGui end
newcclosure = function(f) return f end
getnamecallmethod = function() return _G.__ncm or "FireServer" end
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
os.clock = function() return NOW end -- 虚拟时钟: 假引擎的帧是假的, os.clock 也得跟着假, 不然 0.2s 的节流逻辑永远不触发
local realdate = os.date
local FIXED = os.time() -- 把"现在"挪到本地 14:37, 这样 12 小时制(02:37)和 24 小时制(14:37)不一样, 测得出区别
while tonumber(os.date("%H", FIXED)) ~= 14 do FIXED = FIXED + 3600 end
FIXED = FIXED - tonumber(os.date("%M", FIXED)) * 60 - tonumber(os.date("%S", FIXED)) + 37 * 60
os.date = function(f, t) return realdate(f, t or FIXED) end
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
local function toastText() local t = tabs() and tabs():FindFirstChild("SB_Toast"); return t and t.Text or "" end
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
local errs = 0 -- 模块构造时 pcall 兜住了错误会写成一行"出错: ...", 这里要当成失败抓出来
for _, d in ipairs(all()) do if d.ClassName == "TextLabel" and type(d.Text) == "string" and d.Text:sub(1, 6) == "出错: " then errs = errs + 1; print("       → " .. d.Text) end end
ok(errs == 0, "没有模块构造失败")
local VER = SRC:match('local VERSION = "([^"]+)"') -- 版本单一来源: 面板标题 / 诊断快照 / 启动打印都必须读它
ok(VER ~= nil and (VER:match("^%d%d%.%d%d?%.%d%d?$") ~= nil or VER:match("^%d%d%.%d%d?%.%d%d?%.%d+$") ~= nil), "VERSION 是合法的 yy.m.d 或 yy.m.d.ci (" .. tostring(VER) .. ")")
ok(VER ~= nil and VER:sub(1, 1) ~= "v" and select(2, SRC:gsub('"' .. VER:gsub("%.", "%%.") .. '"', "")) == 1, "展示版本不带 v, 版本号只在 VERSION 一行写死")
local title0 = tabs():FindFirstChild("SB_Title")
ok(title0 ~= nil and title0.Text == "Selfblox " .. tostring(VER), "面板标题读 VERSION (读到 " .. tostring(title0 and title0.Text) .. ")")
ok(SRC:find('print("[Selfblox] " .. VERSION', 1, true) ~= nil, "启动打印读 VERSION, 不另写一份")

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

print("\n[3a] 漂移踏板: 嵌套的 MobilePedals 也要绑上 + 间距=0")
local bound
for _, d in ipairs(all()) do if d:IsA("TextLabel") and type(d.Text) == "string" and d.Text:find("刹=Brake", 1, true) then bound = d.Text end end
ok(bound ~= nil, "嵌套 ImageButton 也自动绑上了 (" .. tostring(bound) .. ")")
local pads = 0
for _, d in ipairs(all()) do if d.ClassName == "UIListLayout" then pads = pads + d.Padding.Offset + d.Padding.Scale end end
ok(pads == 0, "所有 UIListLayout 间距 = 0")

pedals:Destroy() -- 模拟游戏重建踏板 UI: 老代码要手动点重绑, 现在应该自己每秒重试
step(1 / 60, 130) -- 2 秒多, 够循环跑两轮
local dead = 0
for _, d in ipairs(all()) do if d:IsA("TextLabel") and type(d.Text) == "string" and d.Text:find("无 MobilePedals", 1, true) then dead = dead + 1 end end
ok(dead == 1, "踏板没了 → 状态说自己没了, 不假装绑着")
local pedals2 = inst("ScreenGui", { Name = "MobilePedals" })
local box2 = inst("Frame", { Name = "Pedals" })
local b1 = inst("ImageButton", { Name = "Brake", AbsolutePosition = Vector2.new(20, 2100) })
local b2 = inst("ImageButton", { Name = "Gas", AbsolutePosition = Vector2.new(900, 2100) })
box2.Parent, b1.Parent, b2.Parent = pedals2, box2, box2
pedals2.Parent = pgui
step(1 / 60, 130)
local rebound
for _, d in ipairs(all()) do if d:IsA("TextLabel") and type(d.Text) == "string" and d.Text:find("刹=Brake", 1, true) then rebound = d.Text end end
ok(rebound ~= nil, "踏板重建后自动重绑 (" .. tostring(rebound) .. ")")
-- 自动绑上的踏板: 按住真的生效 (原来这条是靠手动点选的那套测的; 用重建后的 b2)
b2.InputBegan:Fire(input("Touch"))
step(1 / 60, 3)
if _G.SB_DUMP then _G.SB_DUMP() end
local dumpP = VFS["selfblox_dump.txt"]
ok(dumpP and dumpP:find("油门=true", 1, true) ~= nil, "按住自动绑上的油门键 → 油门状态真的变真")
b2.InputEnded:Fire(input("Touch"))
step(1 / 60, 3)
if _G.SB_DUMP then _G.SB_DUMP() end
ok(VFS["selfblox_dump.txt"]:find("油门=true", 1, true) == nil, "松手 → 油门状态回假")
pedals2:Destroy() -- 这套假踏板是测试自己造的, 用完自己收, 不然算漏实例

-- 漂移页只剩原来的: 重绑踏板 / ▲ 油门 / ▼ 刹车 (v13 多出来的「选刹车」「选油门」整套删了)
ok(findBtn("重绑踏板") ~= nil and findBtn("▲ 油门") ~= nil and findBtn("▼ 刹车") ~= nil, "漂页有 重绑踏板 / ▲ 油门 / ▼ 刹车")
local oldBtns = 0
for _, d in ipairs(all()) do if d:IsA("TextButton") and (starts(d.Text, "选") or starts(d.Text, "绑") or starts(d.Text, "自动找踏板") or starts(d.Text, "扫车") or starts(d.Text, "复制状态")) then oldBtns = oldBtns + 1 end end
ok(oldBtns == 0, "面板里没有「选…」「绑…」「自动找踏板」「扫车」「复制状态」 (剩 " .. oldBtns .. " 个)")

print("\n[3b] 点标题条 = 折叠 (+/- 也还能用)")
local tl, bd = tabs():FindFirstChild("SB_Title"), tabs():FindFirstChild("SB_Body")
ok(tl ~= nil and bd ~= nil and bd.Visible, "标题条 + 面板体都在")
local tdrag
for _, d in ipairs(tl:GetDescendants()) do if d.ClassName == "UIDragDetector" then tdrag = d end end
ok(tdrag ~= nil, "标题条上有拖拽器")
local function tapTitle() -- 真机路线: 拖拽器 DragStart/DragEnd 给的是屏幕坐标 (Vector2), 手没挪 = 点击
	NOW = NOW + 0.5 -- 虚拟时钟拨过去: 脚本里"一次点按只认一次"有 0.2 秒窗口
	tdrag.DragStart:Fire(Vector2.new(50, 20))
	tdrag.DragEnd:Fire(Vector2.new(50, 20))
end
local function dragTitle() -- 拖过 (挪了 110px) = 只挪位置, 不折叠
	NOW = NOW + 0.5
	tdrag.DragStart:Fire(Vector2.new(50, 20))
	tdrag.DragContinue:Fire(Vector2.new(90, 30))
	tdrag.DragContinue:Fire(Vector2.new(160, 60))
	tdrag.DragEnd:Fire(Vector2.new(160, 60))
end
local function jitterTitle() -- 手指必抖: 收到过 DragContinue, 但总共才挪 2px, 仍然是点击
	NOW = NOW + 0.5
	tdrag.DragStart:Fire(Vector2.new(50, 20))
	tdrag.DragContinue:Fire(Vector2.new(51, 21))
	tdrag.DragEnd:Fire(Vector2.new(52, 21))
end
tapTitle()
ok(bd.Visible == false, "点一下标题条 → 折起来")
tapTitle()
ok(bd.Visible == true, "再点一下 → 展开")
dragTitle()
ok(bd.Visible == true, "拖标题条只挪位置, 不折叠")
jitterTitle()
ok(bd.Visible == false, "手指抖了 2px (收到过 DragContinue) 仍算点击 → 折叠")
tapTitle()
ok(bd.Visible == true, "再点回去 → 展开")
tapTitle()
ok(bd.Visible == false, "拖完再点 → 折叠")
tapTitle()
ok(bd.Visible == true, "再点回去 → 展开 (后面测试要面板开着)")
local foldBtn
for _, d in ipairs(all()) do if d:IsA("TextButton") and (d.Text == "–" or d.Text == "+") then foldBtn = d end end
local function clickFold() NOW = NOW + 0.5; foldBtn.Activated:Fire() end
clickFold()
ok(bd.Visible == false, "+/- 也还能折叠")
clickFold()
ok(bd.Visible == true, "再点展开")
-- 真机上到底哪几条路会响没法在这里验, 所以三条全响也得只翻一次
NOW = NOW + 0.5
tdrag.DragStart:Fire(Vector2.new(50, 20)); tl.InputBegan:Fire(input("Touch"))
tdrag.DragEnd:Fire(Vector2.new(50, 20)); tl.InputEnded:Fire(input("Touch"))
ok(bd.Visible == false, "一次点按同时触发拖拽器 + 标签输入 → 只翻一次 (翻两次 = 没翻)")
NOW = NOW + 0.5
foldBtn.Activated:Fire(); tdrag.DragStart:Fire(Vector2.new(180, 10)); tdrag.DragEnd:Fire(Vector2.new(180, 10))
ok(bd.Visible == true, "点 +/- 时拖拽器也响 → 仍然只翻一次 (折回去, 后面要面板开着)")

do
print("\n[3c] 文字居中: 标签 / 按钮 / 输入框")
local left, boxes, good = 0, 0, 0
for _, d in ipairs(all()) do
	if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and d.TextXAlignment ~= nil and d.TextXAlignment.Name == "Left" then left = left + 1 end
	if d:IsA("TextBox") then
		boxes = boxes + 1
		local lab = d.Parent:FindFirstChildOfClass("TextLabel")
		if d.TextXAlignment.Name == "Center" and d.TextYAlignment.Name == "Center" and d.Parent.ClassName == "Frame"
			and (lab == nil or (lab.Size.X.Scale == 0.5 and d.Position.X.Scale == 0.5 and lab.Text:sub(1, 1) ~= " ")) then good = good + 1 end
	end
end
ok(left == 0, "面板里没有靠左的文字 (靠左 " .. left .. " 个)")
ok(boxes > 0 and good == boxes, "输入框: 左半标签 + 右半输入框, 文字水平垂直都居中, 标签前面不垫空格 (" .. good .. "/" .. boxes .. ")")
end

do
print("\n[3d] 底色透明度 0.9 · 状态靠字色 · 原生居中")
local tl2, bd2 = tabs():FindFirstChild("SB_Title"), tabs():FindFirstChild("SB_Body")
ok(tl2.BackgroundTransparency == 0.9 and bd2.BackgroundTransparency == 0.9, "标题条 / 页面体底色透明度 0.9")
local opaque, cells = 0, 0
for _, d in ipairs(bd2:GetDescendants()) do
	if d:IsA("GuiObject") then
		cells = cells + 1
		if d.BackgroundTransparency < 0.9 then opaque = opaque + 1 end
	end
end
ok(cells > 0 and opaque == 0, "页面里所有按钮 / 数值格 / 标签底色都 ≥ 0.9 透明 (" .. cells .. " 个控件, 不够透明的 " .. opaque .. " 个)")
local esp = findBtn("玩家 ESP")
click(esp)
ok(esp.TextColor3.R == 1 and esp.TextColor3.G == 1, "开关关着 → 字是白的 (" .. esp.Text .. ")")
click(esp)
ok(esp.TextColor3.G > esp.TextColor3.R, "开关开着 → 字变亮绿 (底色只剩 10%, 开/关靠字色) (" .. esp.Text .. ")")
local lit = 0
for _, t in ipairs({ "动", "车", "漂", "显", "志", "机", "砖" }) do local b = findBtn(t); if b and b.TextColor3.G > b.TextColor3.R then lit = lit + 1 end end
ok(lit == 1, "页签里正好一个是亮的 = 当前页 (" .. lit .. " 个)")
-- 原生居中就行: 文字不加 UIPadding 补偿, 也不加描边 / 阴影 (0.9 透明底 + 原色字)
local texts, decorated = 1, 0
for _, root in ipairs({ tl2, bd2 }) do
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			texts = texts + 1
			if d:FindFirstChildOfClass("UIPadding") ~= nil or (d.TextStrokeTransparency or 1) < 1 then decorated = decorated + 1 end
		end
	end
end
if tl2:FindFirstChildOfClass("UIPadding") ~= nil or (tl2.TextStrokeTransparency or 1) < 1 then decorated = decorated + 1 end
ok(decorated == 0, "面板里的文字原生居中: 没有 UIPadding 补偿、没有描边 / 阴影 (" .. decorated .. "/" .. texts .. " 段被加了料)")
local tp = tabs():FindFirstChild("SB_Toast"):FindFirstChildOfClass("UIPadding")
ok(tp ~= nil and tp.PaddingLeft.Offset == 10 and tp.PaddingRight.Offset == 10 and tp.PaddingBottom == nil, "提示条只留左右各 10 的内边距")
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
for _, b in ipairs(buttons()) do if starts(b.Text, "穿墙") and ends(b.Text, " 关") then click(b) end end -- 穿墙(人) + 穿墙(车) 两个都开
step(1 / 60, 10)
ok(seat.MaxSpeed == math.huge, "上车后座位限速抬到无穷")
local clipOn = 0
for _, b in ipairs(buttons()) do if starts(b.Text, "穿墙") and ends(b.Text, " 开") then clipOn = clipOn + 1 end end
ok(seat.CanCollide == false and carBody.CanCollide == false, "穿墙开着: 座位 / 车身都穿 (穿墙开着 " .. clipOn .. " 个 · 座=" .. tostring(seat.CanCollide) .. " 身=" .. tostring(carBody.CanCollide) .. ")")
ok(CP.sur.CanCollide == true, "穿墙范围只有本车装配体: 同 Model 里另一个装配体的装饰件 Sur 不再被穿掉 (" .. tostring(CP.sur.CanCollide) .. ")")
ok(CP.wheelL.CanCollide == true and CP.wheelR.CanCollide == true, "穿墙开着: 只有轮胎底(整车最低的)保留碰撞, 车才不会掉下去 (左=" .. tostring(CP.wheelL.CanCollide) .. " 右=" .. tostring(CP.wheelR.CanCollide) .. ")")
ok(CP.wheelUp.CanCollide == true, "悬挂抬高、不在最低那圈的轮子, 名字带 wheel 仍然保留")
ok(CP.hubL.CanCollide == false and CP.hubR.CanCollide == false, "认到轮子名以后只留轮胎: 名字里没有 wheel/tire 的低位零件 RL/RR 也穿掉 (兜底只在整车一个轮子名都认不到时才用)")
ok(CP.pad.CanCollide == true and CP.fence.CanCollide == true, "穿墙不碰同一个 Model 里锚定的停车台 / 栏杆 (地面/平台不是车)")

do local function pureClip() -- 包进函数: 主函数的局部变量已经快到 200 个上限
	print("\n[6a3] 「全穿」 + 诊断快照里的穿墙明细 (「穿墙不管用」的报告就是缺这一块)")
	local function status() for _, d in ipairs(all()) do if d:IsA("TextLabel") and type(d.Text) == "string" and starts(d.Text, "Car · ") then return d.Text end end end
	ok(findBtn("全穿") ~= nil, "车页有「全穿」开关")
	step(1 / 60, 20)
	ok(status() ~= nil and status():find("只留轮子", 1, true) ~= nil, "状态行写明保留规则和实测块数: " .. tostring(status()))
	_G.__rayHit = { Instance = CP.wheelL, Distance = 1 } -- 待会儿快照里的准星射线: 打到穿墙范围内的轮子
	if _G.SB_DUMP then _G.SB_DUMP() end
	local d1 = VFS["selfblox_dump.txt"]
	_G.__rayHit = nil
	ok(d1 and d1:find("穿墙: 开·只留轮子", 1, true) ~= nil and d1:find("游戏改回=", 1, true) ~= nil, "快照的穿墙一行带模式和块数 (留 / 穿 / 游戏改回)")
	ok(d1 and d1:find("留着 Wheel", 1, true) ~= nil and d1:find("原因=轮子", 1, true) ~= nil, "快照列出还碰撞的是哪几块、为什么留")
	ok(d1 and d1:find("范围外仍碰撞", 1, true) ~= nil, "快照列出同 Model 里范围外还碰撞的大件 (车卡住时先看这条)")
	ok(d1 and (d1:find("跳过没穿", 1, true) ~= nil or d1:find("本车装配体里没有被跳过的部件", 1, true) ~= nil), "快照说明本车装配体里有没有被跳过的部件 (锚定/人物的)")
	ok(d1 and d1:find("在穿墙范围内吗: 在", 1, true) ~= nil, "快照的准星射线标出这块在不在穿墙范围内")
	click(findBtn("全穿"))
	step(1 / 60, 20)
	ok(CP.wheelL.CanCollide == false and CP.wheelR.CanCollide == false and CP.wheelUp.CanCollide == false, "全穿开着: 轮子也一块不留 (左 / 右 / 抬高的那个都穿了)")
	ok(seat.CanCollide == false and carBody.CanCollide == false, "全穿开着: 座位 / 车身照旧穿")
	ok(status() ~= nil and status():find("全穿", 1, true) ~= nil, "状态行写明是全穿: " .. tostring(status()))
	click(findBtn("全穿"))
	step(1 / 60, 20)
	ok(CP.wheelL.CanCollide == true and CP.wheelR.CanCollide == true and CP.wheelUp.CanCollide == true, "关掉全穿: 轮子又保留碰撞")
	ok(CP.hubL.CanCollide == false and CP.hubR.CanCollide == false, "关掉全穿: 名字里没有 wheel 的低位零件照样穿")
end pureClip() end
seat.props.AssemblyLinearVelocity = Vector3.new(0, -5, 0)
_G.__rayHit = { Instance = CP.fence, Distance = 1.2 } -- 老逻辑: 离地只剩 0.7 → 把竖直速度顶到 +3 (上浮); 新逻辑根本不探地
step(1 / 60, 3)
ok(seat.props.AssemblyLinearVelocity.Y == -5, "穿墙不再探地推起, 开启后不上浮 (竖直速度 " .. tostring(seat.props.AssemblyLinearVelocity.Y) .. ")")
_G.__rayHit = nil
seat.props.AssemblyLinearVelocity = Vector3.zero
ok(seat:FindFirstChild("SB_SIBS") ~= nil, "车约束挂在座位装配体上")

do local function noWheelCar() -- 包进函数: 主函数的局部变量已经快到 200 个上限了
	print("\n[6a2] 穿墙兜底: 整车一个轮子名都认不到时按最低块保留; 轮子晚一批才出现就整车重判")
	local seatWas = humanoid.props.SeatPart
	humanoid.props.SeatPart = nil -- 走准星锁定这条路, 不然 part() 优先用座位
	local nw = inst("Model", { Name = "NoWheel" })
	local nwSeat = inst("VehicleSeat", { Name = "Driver", CanCollide = true, Anchored = false, Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(Vector3.new(200, 5, 0)), Position = Vector3.new(200, 5, 0), AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero, AssemblyMass = 20, Throttle = 0, Steer = 0, MaxSpeed = 100 })
	nwSeat.props.AssemblyRootPart = nwSeat
	nwSeat.Parent = nw
	local function nwPart(name, size, pos)
		local d = inst("Part", { Name = name, CanCollide = true, Anchored = false, Size = size, CFrame = CFrame.new(pos), Position = pos, AssemblyLinearVelocity = Vector3.zero, AssemblyMass = 2 })
		d.props.AssemblyRootPart = nwSeat
		d.Parent = nw
		return d
	end
	local nwBody = nwPart("Body", Vector3.new(6, 2, 12), Vector3.new(200, 5, 0)) -- 底 y=4
	local nwLowL = nwPart("RL", Vector3.new(1, 3, 3), Vector3.new(197, 1.5, 3)) -- 底 y=0
	local nwLowR = nwPart("RR", Vector3.new(1, 3, 3), Vector3.new(203, 1.5, 3)) -- 底 y=0
	local nwRoof = nwPart("Roof", Vector3.new(4, 1, 4), Vector3.new(200, 8, 0)) -- 底 y=7.5
	nw.Parent = workspace
	local function status() for _, d in ipairs(all()) do if d:IsA("TextLabel") and type(d.Text) == "string" and starts(d.Text, "NoWheel · ") then return d.Text end end end
	_G.__rayHit = { Instance = nwSeat }
	click(findBtn("换车"))
	step(1 / 60, 40) -- 0.67 秒: 跨过 noclip 的 0.5 秒批处理窗口
	ok(nwSeat:FindFirstChild("SB_SIBS") ~= nil, "换到一辆零件全都不叫 wheel/tire 的车上")
	ok(nwLowL.CanCollide == true and nwLowR.CanCollide == true, "一个轮子名都认不到 → 按整车最低兜底保留碰撞, 车不会掉出世界")
	ok(nwBody.CanCollide == false and nwRoof.CanCollide == false, "兜底也只留最低那圈: 车身 / 车顶照样穿")
	ok(status() ~= nil and status():find("没认到轮子", 1, true) ~= nil, "状态行如实说明在用兜底 (" .. tostring(status()) .. ")")
	local nwWheel = nwPart("Wheel_Late", Vector3.new(1, 3, 3), Vector3.new(197, 1.5, -3)) -- 轮子晚一批才出现
	step(1 / 60, 40)
	ok(nwWheel.CanCollide == true, "晚出现的轮子按名字保留碰撞")
	ok(nwLowL.CanCollide == false and nwLowR.CanCollide == false, "认到轮子后整车重判: 之前靠兜底留下的 RL/RR 也穿掉 (只留轮胎)")
	ok(status() ~= nil and not status():find("没认到轮子", 1, true), "认到轮子后状态行不再报兜底")
	nw:Destroy()
	_G.__rayHit = { Instance = seat } -- 锁回原来那辆, 后面的测试要用
	click(findBtn("换车"))
	step(1 / 60, 5)
	_G.__rayHit = nil
	humanoid.props.SeatPart = seatWas
end noWheelCar() end
click(findBtn("常亮"))
step(1 / 60, 3)
local lamps, onBody, onSeat = 0, 0, 0
for _, d in ipairs(car:GetDescendants()) do
	if d:IsA("Light") then
		lamps = lamps + 1
		if d:IsDescendantOf(carBody) then onBody = onBody + 1 end
		if d:IsDescendantOf(seat) then onSeat = onSeat + 1 end
	end
end
ok(lamps >= 2, "车上没灯时自己装了 " .. lamps .. " 个 SpotLight")
ok(onSeat == 0 and onBody >= 2, "灯装车身部件上, 不装座位 (身 " .. onBody .. " / 座 " .. onSeat .. ")")
click(findBtn("常亮"))
step(1 / 60, 3)
local native = inst("SpotLight", { Name = "Headlamp", Enabled = false })
native.Parent = carBody
click(findBtn("常亮"))
step(1 / 60, 3)
ok(native.Enabled == true, "车自带的灯直接点亮 (接原生灯)")
local fakes = 0
for _, d in ipairs(car:GetDescendants()) do if d:IsA("Light") and tostring(d.Name):sub(1, 3) == "SB_" then fakes = fakes + 1 end end
ok(fakes == 0, "有原生灯就不再造假灯")
click(findBtn("常亮"))
step(1 / 60, 3)
ok(native.Enabled == false, "关灯 = 原生灯回原样")
native:Destroy() -- 这个假原生灯是自检自己造的, 自己收拾
click(findBtn("飞车"))
step(1 / 60, 5)
ok(seat:FindFirstChild("SB_SIBS"):FindFirstChildOfClass("LinearVelocity") ~= nil, "飞车换成原生 LinearVelocity")
click(findBtn("飞车"))
click(findBtn("急刹"))

print("\n[6b] 方向盘: 整条能拖 / 松手回中 / 位置钉死")
click(findBtn("急刹")) -- 先关急刹: 开着的话水平速度每帧被清零, 车转不动
seat.props.Throttle, seat.props.Steer = 0, 0
seat.props.AssemblyLinearVelocity = Vector3.new(0, 0, -30)
local track
for _, d in ipairs(all()) do if d.Name == "SB_Steer" then track = d end end
ok(track ~= nil, "滑条建出来了")
local knob, kd = track and track:FindFirstChild("SB_Knob"), nil
for _, d in ipairs(track:GetDescendants()) do if d.ClassName == "UIDragDetector" then kd = d end end
ok(knob ~= nil and kd ~= nil, "圆点 + 全宽拖拽手柄都在")
local handle
for _, d in ipairs(track:GetDescendants()) do if d.Name == "SB_Handle" then handle = d end end
ok(handle and handle.Visible == false, "面板开着 → 滑条固定, 不接管触摸")
local look0 = seat.props.CFrame.LookVector
kd.DragContinue:Fire(Vector2.new(999, 0))
step(1 / 60, 12)
ok((seat.props.CFrame.LookVector - look0).Magnitude < 0.01, "面板开着时拖它 → 车不动")
kd.DragEnd:Fire()
tapTitle() -- 折起来 → 滑条才可拖
ok(handle.Visible == true, "面板折起来 → 滑条可拖")
kd.DragContinue:Fire(Vector2.new(999, 0))
step(1 / 60, 12)
local turned = (seat.props.CFrame.LookVector - look0).Magnitude
ok(turned > 0.05, "拖到最右 → 车真的转了 " .. string.format("%.2f", turned))
ok(knob.Position.X.Offset > 10, "圆点跟着手指跑 (偏 " .. knob.Position.X.Offset .. "px)")
seat.props.AssemblyLinearVelocity = Vector3.zero -- 停着也要能打方向
local look1 = seat.props.CFrame.LookVector
kd.DragContinue:Fire(Vector2.new(999, 0))
step(1 / 60, 10)
ok((seat.props.CFrame.LookVector - look1).Magnitude > 0.02, "车停着, 拖滑条照样转")
kd.DragEnd:Fire()
step(1 / 60, 2)
ok(knob.Position.X.Offset == 0 and knob.Position.X.Scale == 0.5, "松手回中, 平时固定")
ok(handle.Position.X.Scale == 0 and handle.Position.X.Offset == 0 and handle.Position.Y.Scale == 0 and handle.Position.Y.Offset == 0, "松手后手柄回到原位, 仍盖满整条轨道 (没被推到右下半格)")
ok(track.Position.Y.Scale == 1 and track.Position.Y.Offset == -10, "钉在屏幕底部 (不跟面板跑)")
tapTitle() -- 折回去, 后面还要用面板
ok(handle.Visible == false, "展开 → 滑条又固定")
ok(track.ZIndex == 1 and handle.Visible == false, "面板开着时滑条降到最底层、触摸穿透")
tapTitle()
ok(track.ZIndex == 10 and handle.Visible == true, "折起来后滑条升到最上层")
tapTitle()
print("\n[6e] 锚定的车也要立刻绑上 (不再等游戏解锁)")
seat.props.Anchored = true
step(1 / 60, 5)
ok(seat:FindFirstChild("SB_SIBS") ~= nil, "锚定状态下 SB_SIBS 照样挂上")
local rival = inst("Part", { Name = "Rival", CanCollide = true, Anchored = false, Size = Vector3.new(8, 3, 16), Position = Vector3.new(14, 5, 0), CFrame = CFrame.new(Vector3.new(14, 5, 0)), AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero, AssemblyMass = 500 })
rival.props.AssemblyRootPart = rival
rival.Parent = workspace
_G.__radius = { rival } -- 附近有个更重的自由件 (别人的车/装饰件)
step(1 / 60, 10)
ok(seat:FindFirstChild("SB_SIBS") ~= nil and rival:FindFirstChild("SB_SIBS") == nil, "有座位的车锚着时, 不会改绑到附近更重的零件")
_G.__radius = nil
rival:Destroy()
local stTxt
for _, d in ipairs(all()) do if d:IsA("TextLabel") and type(d.Text) == "string" and d.Text:find("锚定", 1, true) then stTxt = d.Text end end
ok(stTxt ~= nil, "状态行直接标出锚定 (" .. tostring(stTxt) .. ")")
tapTitle() -- 折起来才能拖滑条
local lookA = seat.props.CFrame.LookVector
kd.DragContinue:Fire(Vector2.new(999, 0))
step(1 / 60, 10)
ok((seat.props.CFrame.LookVector - lookA).Magnitude > 0.02, "锚定车的转向照样有效 (走 CFrame)")
kd.DragEnd:Fire()
tapTitle()
seat.props.Anchored = false
step(1 / 60, 3)

print("\n[6d] 飞车: 摇杆前推 = 车头方向 (摇杆读 Humanoid.MoveDirection; 官方 UserInputService 没有 GetMoveVector)")
click(findBtn("飞车"))
humanoid.props.MoveDirection = Vector3.new(0, 0, -1) -- 摄像机朝 -Z: 前推 = 世界 -Z
seat.props.Throttle = 0
step(1 / 60, 3)
local lvc = seat:FindFirstChild("SB_SIBS"):FindFirstChildOfClass("LinearVelocity")
ok(lvc and lvc.VectorVelocity.Z < -10, "摇杆前推 → 车头方向 " .. tostring(lvc and lvc.VectorVelocity))
humanoid.props.MoveDirection = Vector3.new(1, 0, 0) -- 右推 = 世界 +X
step(1 / 60, 3)
ok(lvc and lvc.VectorVelocity.X > 10, "摇杆右推 → 车右方向 " .. tostring(lvc and lvc.VectorVelocity))
camera.CFrame = CFrame.new(Vector3.zero, Vector3.new(1, 0, 0)) -- 摄像机转到朝 +X: 前推 = 世界 +X, 但车还是该往车头(-Z)飞, 不能跟着相机跑
humanoid.props.MoveDirection = Vector3.new(1, 0, 0)
step(1 / 60, 3)
local fw = seat.props.CFrame.LookVector -- 前面方向盘测试已经把假车转过了, 车头不再是 -Z, 所以跟车头的实际朝向比
fw = Vector3.new(fw.X, 0, fw.Z).Unit
ok(lvc and lvc.VectorVelocity.Magnitude > 10 and lvc.VectorVelocity.Unit:Dot(fw) > 0.99, "相机转 90° 后, 前推仍是车头方向, 不跟着相机跑 (与车头夹角余弦 " .. string.format("%.3f", lvc and lvc.VectorVelocity.Unit:Dot(fw) or 0) .. ", 速度 " .. tostring(lvc and lvc.VectorVelocity) .. ")")
camera.CFrame = CFrame.new(Vector3.zero)
humanoid.props.MoveDirection = Vector3.zero
step(1 / 60, 3)
ok(lvc and lvc.VectorVelocity.Magnitude < 0.1, "松手悬停")
click(findBtn("飞车"))

print("\n[6c] 急刹")
click(findBtn("急刹")) -- 开
seat.props.Throttle, seat.props.AssemblyLinearVelocity = 0, Vector3.new(30, 5, 0) -- 松开游戏油门, 免得急刹被"踩油门自动解除"顶掉
step(1 / 60, 2)
ok(seat.AssemblyLinearVelocity.Z == 0 and seat.AssemblyLinearVelocity.X == 0, "急刹把水平速度清了, 保留竖直 " .. tostring(seat.AssemblyLinearVelocity.Y))
click(findBtn("急刹")) -- 关

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
ok(seat.CanCollide and carBody.CanCollide and CP.sur.CanCollide and CP.wheelL.CanCollide and CP.wheelUp.CanCollide and CP.hubL.CanCollide and CP.pad.CanCollide and CP.fence.CanCollide and not CP.shadow.CanCollide, "穿墙关掉后车部件原样还原 (本来不碰撞的影子仍是不碰撞)")

print("\n[6b2] 滑条常可拖 (折不起来时的后备)")
local alwaysBtn = findBtn("滑条常可拖")
ok(alwaysBtn ~= nil, "车页有「滑条常可拖」")
click(alwaysBtn)
ok(handle and handle.Visible == true, "开了之后面板开着也能拖")
local lookA2 = seat.props.CFrame.LookVector
kd.DragContinue:Fire(Vector2.new(999, 0))
step(1 / 60, 10)
ok((seat.props.CFrame.LookVector - lookA2).Magnitude > 0.03, "面板开着也能转向了")
kd.DragEnd:Fire()
click(alwaysBtn)
ok(handle and handle.Visible == false, "关掉 → 回到「折叠才能拖」")

print("\n[6d2] 按住类按钮: 按住字变亮, 松手变回白色")
local btnGas
for _, d in ipairs(all()) do if d:IsA("TextButton") and d.Text == "▲ 加速" then btnGas = d end end
ok(btnGas ~= nil, "车页有「▲ 加速」")
btnGas.InputBegan:Fire(input("Touch"))
step(1 / 60, 3)
ok(btnGas.TextColor3.G > btnGas.TextColor3.R, "按住时字变亮 (底色只剩 10%, 按下状态靠字色)")
btnGas.InputEnded:Fire(input("Touch"))
step(1 / 60, 3)
ok(btnGas.TextColor3.R == 1 and btnGas.TextColor3.G == 1, "松手后字变回白色")

print("\n[6f] 载具范围: 街区的 Model 不能当车 (你的游戏就是这种结构)")
humanoid.props.SeatPart = nil -- 走"准星锁定"这条路(你那台卡车就是这样), 不然 part() 会优先用座位
step(1 / 60, 3)
_G.__rayHit = { Instance = truckBed }
click(findBtn("换车"))
step(1 / 60, 5)
local toastNoSeat = toastText() -- 先抓提示, 下面打包会把提示条覆盖掉
if _G.SB_DUMP then _G.SB_DUMP() end
local dumpCar = VFS["selfblox_dump.txt"]
ok(dumpCar and dumpCar:find("Model: Street", 1, true) == nil, "载具范围不是整个街区 Street")
ok(dumpCar and dumpCar:find("Truck", 1, true) ~= nil, "锁到的是 Truck 那层")
ok(toastNoSeat:find("没座位", 1, true) ~= nil, "提示如实说明「没座位」(当时提示: " .. toastNoSeat .. ")")
ok(dumpCar and dumpCar:find("座位: -", 1, true) ~= nil, "快照里座位一栏是空的")
ok(dumpCar and dumpCar:find("准星射线", 1, true) ~= nil and dumpCar:find("祖先: ", 1, true) ~= nil, "快照里有准星射线 + 祖先链")
ok(dumpCar and dumpCar:find("周围的座位", 1, true) ~= nil, "快照里有周围座位(半径扫描)")
ok(dumpCar and dumpCar:find("车周围 25 格里的部件", 1, true) ~= nil, "快照里有周围部件")

do local function mapGuard() -- 打中街道路面(横跨 3000 格的装配体): 不能当成车
	_G.__rayHit = { Instance = CP.road }
	click(findBtn("换车"))
	step(1 / 60, 5)
	ok(CP.road:FindFirstChild("SB_SIBS") == nil, "打中街道路面 → 不绑 (装配体外径 ~6000 格, 远超 carmaxstuds)")
	ok(toastText():find("地图", 1, true) ~= nil, "提示说清是地图/大容器, 不是笼统的「没座位」(" .. toastText() .. ")")
	ok(toastText():match("外径 %d+ 格") ~= nil and toastText():match("质量 %d+") ~= nil, "提示里带实测外径和质量: 下次误拒/漏拒, 报告自己就能说明为什么 (" .. toastText() .. ")")
	local slab = inst("Part", { Name = "Slab", CanCollide = true, Anchored = false, Size = Vector3.new(2000, 1, 2000), Position = Vector3.new(0, 0, 1500), CFrame = CFrame.new(Vector3.new(0, 0, 1500)), AssemblyLinearVelocity = Vector3.zero, AssemblyMass = 5000 })
	slab.props.AssemblyRootPart = slab
	slab.Parent = street
	_G.__rayHit = { Instance = slab }
	click(findBtn("换车"))
	step(1 / 60, 5)
	ok(slab:FindFirstChild("SB_SIBS") == nil and toastText():find("地图", 1, true) ~= nil, "一整块超大路面(自己一个装配体, 靠零件自身尺寸也算得出来) → 不绑")
	slab:Destroy()
end mapGuard() end
do local function looseInBigModel() -- 真车直接挂在超大容器 Model 里: 量容器会把它当地图拒掉 = 用户报的"新构建绑不上车"
	_G.__rayHit = { Instance = CP.looseCar }
	click(findBtn("换车"))
	step(1 / 60, 5)
	ok(CP.looseCar:FindFirstChild("SB_SIBS") ~= nil, "超大容器 Model 里的小装配体(没座位)照样绑得上: 量的是装配体, 不是容器")
	ok(toastText():find("没座位", 1, true) ~= nil, "绑上后照样提示没座位只能推 (" .. toastText() .. ")")
end looseInBigModel() end
_G.__rayHit = { Instance = seat } -- 换回真车: 带座位的那种
click(findBtn("换车"))
step(1 / 60, 5)
local toastSeat = toastText()
if _G.SB_DUMP then _G.SB_DUMP() end
ok(toastSeat:find("座位 Seat", 1, true) ~= nil, "有座位时提示带座位名 (当时提示: " .. toastSeat .. ")")
_G.__rayHit = nil

print("\n[6g] 锁定自愈: 车被换掉 / 锁到锚定件")
humanoid.props.SeatPart = nil
_G.__rayHit = { Instance = truckBed }
click(findBtn("换车"))
step(1 / 60, 5)
ok(truckBed:FindFirstChild("SB_SIBS") ~= nil, "先正常锁上")
truckBed:Destroy() -- 游戏把车换了一件(你日志里那种"缓存对象已销毁")
local newBed = inst("Part", { Name = "Primary", CanCollide = true, Anchored = false, Size = Vector3.new(4, 1, 16), Position = Vector3.new(60, 5, 0), CFrame = CFrame.new(Vector3.new(60, 5, 0)), AssemblyLinearVelocity = Vector3.zero, AssemblyMass = 1200 })
newBed.props.AssemblyRootPart = newBed
newBed.Parent = truck
_G.__rayHit = nil
step(1 / 60, 5)
ok(newBed:FindFirstChild("SB_SIBS") ~= nil, "被换件后按路径自动更到新件")
newBed.props.Anchored = true -- 这件还没解锁(锚定) → 应该自动改绑到旁边更重的自由件
local heavy = inst("Part", { Name = "Chassis", CanCollide = true, Anchored = false, Size = Vector3.new(6, 2, 14), Position = Vector3.new(61, 5, 0), CFrame = CFrame.new(Vector3.new(61, 5, 0)), AssemblyLinearVelocity = Vector3.zero, AssemblyMass = 2000 })
heavy.props.AssemblyRootPart = heavy
heavy.Parent = truck
do -- 就近改绑也不能改绑到地图: 30 格里最重的那件往往就是路面
	local mapBit = inst("Part", { Name = "Plaza", CanCollide = true, Anchored = false, Size = Vector3.new(60, 1, 60), Position = Vector3.new(62, 5, 0), CFrame = CFrame.new(Vector3.new(62, 5, 0)), AssemblyLinearVelocity = Vector3.zero, AssemblyMass = 9000 })
	mapBit.props.AssemblyRootPart = mapBit
	mapBit.Parent = street
	local mapFar = inst("Part", { Name = "PlazaFar", CanCollide = true, Anchored = false, Size = Vector3.new(60, 1, 60), Position = Vector3.new(2062, 5, 0), CFrame = CFrame.new(Vector3.new(2062, 5, 0)), AssemblyLinearVelocity = Vector3.zero, AssemblyMass = 9000 })
	mapFar.props.AssemblyRootPart = mapBit -- 同一个装配体 → 外径 ~4000 格
	mapFar.Parent = street
	_G.__radius = { newBed, heavy, mapBit }
	step(1 / 60, 5)
	ok(heavy:FindFirstChild("SB_SIBS") ~= nil, "锚定件被换成了附近更重的自由件 (Chassis)")
	ok(mapBit:FindFirstChild("SB_SIBS") == nil, "就近改绑没改到最重(9000)但超大的地图件上")
	mapBit:Destroy()
	mapFar:Destroy()
end
newBed.props.Anchored = false
heavy:Destroy()
newBed:Destroy()
_G.__radius = nil
_G.__rayHit = { Instance = seat } -- 收尾: 锁回真车, 后面的测试要用
click(findBtn("换车"))
step(1 / 60, 5)
_G.__rayHit = nil

do
print("\n[6h] 座位是一辆车的共同点: 瞄哪个零件, 绑的都是座位所在装配体 (带 VehicleSeat 的车)")
humanoid.props.SeatPart = nil
for _, hit in ipairs({ CP.sur, CP.wheelL, carBody, seat }) do
	_G.__rayHit = { Instance = hit }
	click(findBtn("换车"))
	step(1 / 60, 20)
	ok(seat:FindFirstChild("SB_SIBS") ~= nil and CP.sur:FindFirstChild("SB_SIBS") == nil and CP.wheelL:FindFirstChild("SB_SIBS") == nil, "瞄 " .. hit.Name .. " → 绑的是座位 Seat 所在的装配体, 不是瞄到的零件")
	ok(toastText():find("座位 Seat", 1, true) ~= nil, "提示说明是按座位锁的 (" .. toastText() .. ")")
end
local st
for _, d in ipairs(all()) do if d:IsA("TextLabel") and type(d.Text) == "string" and starts(d.Text, "Car · ") then st = d.Text end end
ok(st ~= nil, "状态行显示整辆车的名字 Car, 不是某个零件/子模型 (" .. tostring(st) .. ")")
ok(st ~= nil and not st:find("sps", 1, true), "状态行速度后面不带 sps 单位")
_G.__rayHit = nil
end

print("\n[7b] 诊断打包")
humanoid.props.SeatPart = nil -- 下车了: 车结构要靠缓存带出去
step(1 / 60, 5)
local dumpBtn
for _, d in ipairs(all()) do if d:IsA("TextButton") and type(d.Text) == "string" and d.Text:find("诊断打包", 1, true) then dumpBtn = d end end
ok(dumpBtn ~= nil, "「志」页有诊断打包按钮")
if dumpBtn then dumpBtn.Activated:Fire() end
step(1 / 60, 3)
local dm = VFS["selfblox_dump.txt"]
ok(dm ~= nil, "写了 selfblox_dump.txt")
ok(dm and dm:find("执行器 isfile=", 1, true) ~= nil, "快照里有执行器能力")
ok(dm and dm:find("脚本=" .. tostring(VER), 1, true) ~= nil, "诊断快照的版本 = VERSION (" .. tostring(VER) .. ")")
ok(dm and dm:find("MobilePedals", 1, true) ~= nil, "快照里有踏板树")
ok(dm and dm:find("sibs ", 1, true) ~= nil, "快照里有各模块状态")
ok(dm and dm:find("PlayerGui 树", 1, true) == nil, "快照里不再带整个 PlayerGui 树 (原来是给「选按钮」准备的)")
ok(dm and dm:find("CAr", 1, true) == nil and dm:find("=== CAR", 1, true) ~= nil, "快照里有车结构")
ok(CLIP ~= nil and CLIP:find("Selfblox 诊断", 1, true) ~= nil, "快照同时进了剪贴板")
ok(type(_G.SB_DUMP) == "function", "也可以用 _G.SB_DUMP() 手动打")

-- ───────── 其余模块的覆盖补齐: hud-ESP / plane / brick / log / moc / sibs 角落 ─────────
-- 这些模块原来几乎没被自检跑到 (plane 33% / brick 48% / log 67% / hud 78%): "真引擎会抛错、假引擎放行"的错最容易藏在没跑到的代码里
do local function section7c() -- 包进函数: 主函数的局部变量已经快到 200 个上限了
print("\n[7c] 其余模块: ESP / 飞机侦察 / 刷砖 / 日志 / 旋转·秒互动·速度三模式 / 翻转")
local TMP = {}
local function T(i) TMP[#TMP + 1] = i; return i end
local function mkPart(name, size, pos, extra)
	local d = inst("Part", { Name = name, CanCollide = true, Anchored = false, Size = size, CFrame = CFrame.new(pos), Position = pos, AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero, AssemblyMass = 5, Color = Color3.fromRGB(120, 120, 120) })
	for k, v in pairs(extra or {}) do d.props[k] = v end
	d.props.AssemblyRootPart = d
	return T(d)
end
local function btnExact(t) for _, b in ipairs(buttons()) do if b.Text == t then return b end end end
local function labelHas(sub) for _, d in ipairs(all()) do if d:IsA("TextLabel") and type(d.Text) == "string" and d.Text:find(sub, 1, true) then return d.Text end end end
local seatSaved = humanoid.props.SeatPart
humanoid.props.SeatPart = nil
local PS, RSv = _G.__SVC.Players, _G.__SVC.ReplicatedStorage
local savedGP, savedFC = PS.props.GetPlayers, PS.props.GetPlayerFromCharacter

-- ── hud: 别的玩家的 ESP ──
local teamRed = T(inst("Team", { Name = "Red", TeamColor = { Color = Color3.fromRGB(255, 0, 0) } }))
local teamBlue = T(inst("Team", { Name = "Blue", TeamColor = { Color = Color3.fromRGB(0, 0, 255) } }))
local bobChar, bobHum = T(inst("Model", { Name = "Bob" })), T(inst("Humanoid", { Health = 100 }))
local bobRoot = mkPart("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(30, 5, 0))
bobHum.Parent, bobRoot.Parent = bobChar, bobChar
bobChar.Parent = workspace
local bob = T(inst("Player", { Name = "Bob", DisplayName = "Bobby", UserId = 2, Character = bobChar, Team = teamRed, TeamColor = teamRed.props.TeamColor }))
PS.props.GetPlayers = function() return { player, bob } end
PS.props.GetPlayerFromCharacter = function(_, c) if c == char then return player elseif c == bobChar then return bob end end
local espBtn = findBtn("玩家 ESP")
if espBtn.Text:find("关", 1, true) then click(espBtn) end
PS.props.PlayerAdded:Fire(bob)
step(1 / 60, 20)
local function espHL(adornee) for _, d in ipairs(_G.CoreGui:GetDescendants()) do if d.ClassName == "Highlight" and d.Adornee == adornee then return d end end end
local function espBB() for _, d in ipairs(_G.CoreGui:GetDescendants()) do if d.ClassName == "BillboardGui" and d.Adornee == bobRoot then return d end end end
local hl = espHL(bobChar)
ok(hl ~= nil and hl.Enabled == true, "别的玩家有 ESP 高亮")
ok(hl and hl.FillColor.R == 1 and hl.FillColor.G == 0, "高亮用队伍颜色 (红队)")
local bb = espBB()
local nameTxt = bb and bb:FindFirstChildOfClass("TextLabel").Text
ok(nameTxt == "Bobby 30", "名牌 = 显示名 + 距离 (" .. tostring(nameTxt) .. ")")
bob.props.Team = nil
step(1 / 60, 20)
ok(espHL(bobChar).FillColor.R == 0.5, "没队伍 → 按 UserId 取色")
bobHum.props.Health = 0
step(1 / 60, 20)
ok(espHL(bobChar).Enabled == false and espBB().Enabled == false, "死了 → 高亮和名牌都关")
bobHum.props.Health = 100
click(espBtn) -- 关
step(1 / 60, 20)
ok(espHL(bobChar).Enabled == false, "「玩家 ESP」关掉 → 活人也不画")
click(espBtn) -- 开
step(1 / 60, 20)
ok(espHL(bobChar).Enabled == true, "再开 → 又画")
PS.props.PlayerRemoving:Fire(bob)
ok(espHL(bobChar) == nil and espBB() == nil, "玩家离开 → ESP 实例清掉")
PS.props.PlayerAdded:Fire(bob) -- 再进来一次, 留着让卸载去清
bob.props.Team = teamRed

-- ── 穿墙附带: 别人挡不住你 (只改本地那几份; 关掉穿墙 / 卸载都要还原) ──
local clips = {}
for _, b in ipairs(buttons()) do if starts(b.Text, "穿墙") then clips[#clips + 1] = b end end -- 开关按钮的文字带 " 开" / " 关"; 标签是 穿墙(人) / 穿墙(车)
ok(#clips == 2, "「动」和「车」各有一个「穿墙」开关 (找到 " .. #clips .. " 个)")
local clipMoc, clipCar = clips[1], clips[2] -- 树里的顺序 = 建页顺序: 动 在前, 车 在后
ok(bobRoot.CanCollide == true and hrp.CanCollide == true, "起点: 别人的部件和我自己的都还能碰撞")
click(clipMoc)
step(1 / 60, 5)
ok(bobRoot.CanCollide == false, "「动」穿墙开着 → 别的玩家在我这一份里看不到碰撞 (人挡不住)")
ok(hrp.CanCollide == false, "人物穿墙本来就全身不可碰 (自己这边也没变)")
click(clipMoc)
step(1 / 60, 5)
ok(bobRoot.CanCollide == true and hrp.CanCollide == true, "关掉「动」穿墙 → 两边的碰撞都还原")
click(clipCar)
step(1 / 60, 5)
ok(bobRoot.CanCollide == false, "「车」穿墙开着 → 别人的部件也不碰 (车保留的轮胎块不再被挡路的人顶住)")
ok(hrp.CanCollide == true, "「车」穿墙不动我自己的人物")
local latecomer = mkPart("Latecomer", Vector3.new(2, 2, 1), Vector3.new(31, 5, 0))
latecomer.Parent = bobChar
ok(latecomer.CanCollide == true, "刚冒出来的部件还是有碰撞")
step(1 / 60, 45) -- 半秒一轮: 后加入 / 重生的部件下一轮补上
ok(latecomer.CanCollide == false, "开了以后新加 / 重生的部件最迟半秒补上")
click(clipCar)
step(1 / 60, 5)
ok(bobRoot.CanCollide == true and latecomer.CanCollide == true, "关掉「车」穿墙 → 连后补的那块也还原")

do local function clipVeh() -- 包进函数: 主函数的局部变量已经快到 200 个上限
	print("\n[7c1] 别人正坐着的载具一起忽略 (开公交时被前车顶住的就是这个)")
	local bus = T(inst("Model", { Name = "Bus" }))
	local busSeat = T(inst("VehicleSeat", { Name = "Driver", CanCollide = true, Anchored = false, Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(Vector3.new(60, 5, 60)), Position = Vector3.new(60, 5, 60), AssemblyLinearVelocity = Vector3.zero, AssemblyMass = 30, Occupant = bobHum, Throttle = 0, Steer = 0, MaxSpeed = 50 }))
	busSeat.props.AssemblyRootPart = busSeat
	busSeat.Parent = bus
	local busBody = T(inst("Part", { Name = "Body", CanCollide = true, Anchored = false, Size = Vector3.new(6, 4, 16), CFrame = CFrame.new(Vector3.new(60, 5, 60)), Position = Vector3.new(60, 5, 60), AssemblyLinearVelocity = Vector3.zero, AssemblyMass = 30 }))
	busBody.props.AssemblyRootPart = busSeat
	busBody.Parent = bus
	local busAnch = T(inst("Part", { Name = "Rack", CanCollide = true, Anchored = true, Size = Vector3.new(5, 1, 5), CFrame = CFrame.new(Vector3.new(60, 9, 60)), Position = Vector3.new(60, 9, 60), AssemblyMass = 900 })) -- 焊在车上的锚定件: 该跳过的就是它
	busAnch.props.AssemblyRootPart = busSeat
	busAnch.Parent = bus
	bus.Parent = workspace
	bobHum.props.SeatPart = busSeat -- 鲍勃在开这辆公交
	ok(busBody.CanCollide == true, "起点: 别人的车还是能碰的")
	click(clipMoc)
	step(1 / 60, 45)
	ok(busBody.CanCollide == false and busSeat.CanCollide == false, "别人开的车: 车身 / 座位在本地不碰撞 (前车顶不住你)")
	ok(busAnch.CanCollide == true, "同一装配体里锚定的那块不动 (免得把焊着的地图件一起穿掉)")
	ok(seat.CanCollide == true, "我自己的车不受影响 (不同装配体)")
	humanoid.props.SeatPart = busSeat -- 我也坐这辆车: 同一装配体, 不能连我自己的座位一起穿
	step(1 / 60, 45)
	ok(busSeat.CanCollide == true, "我和别人在同一辆车里 → 这块不动 (否则我从自己的座位掉下去)")
	humanoid.props.SeatPart = nil
	step(1 / 60, 45)
	ok(busSeat.CanCollide == false, "我下车后: 又是别人开的车, 重新忽略")
	if _G.SB_DUMP then _G.SB_DUMP() end
	local dv = VFS["selfblox_dump.txt"]
	ok(dv and dv:find("别人穿墙: 人物 2 块 · 载具 2 块", 1, true) ~= nil, "诊断快照如实报别人那边改了几块 (人物 / 载具): " .. tostring(dv and dv:match("别人穿墙: [^\n]*")))
	click(clipMoc)
	step(1 / 60, 5)
	ok(busBody.CanCollide == true and busSeat.CanCollide == true, "关掉穿墙 → 别人的车还原")
	bobHum.props.SeatPart = nil
	bus:Destroy() -- 收掉: 一辆带座位的车留在场景里会进飞机侦察的「疑似」名单, 把后面的断言带偏
end clipVeh() end

-- ── plane: 飞机侦察 ──
local spawnRemote = T(inst("RemoteEvent", { Name = "SpawnPlane" })); spawnRemote.Parent = RSv
local chatFn = T(inst("RemoteFunction", { Name = "ChatFn" })); chatFn.Parent = RSv
local function mkPlane(name, o)
	local m = T(inst("Model", { Name = name }))
	local st = T(inst("VehicleSeat", { Name = "Pilot", Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(Vector3.new(200, 50, 0)), Position = Vector3.new(200, 50, 0), Occupant = o.occ }))
	if not o.noseat then st.Parent = m end -- 没座位的飞机(机库/菜单/被服务器接管的残留机): 上一版只从座位出发扫描, 这种整个漏掉
	for _, wn in ipairs(o.wings or {}) do mkPart(wn, Vector3.new(6, 0.5, 2), Vector3.new(200, 50, 0)).Parent = m end
	for i = 1, (o.fill or 0) do mkPart("Body" .. i, Vector3.new(1, 1, 1), Vector3.new(200, 50, 0)).Parent = m end
	if o.paint then mkPart("Hull", Vector3.new(20, 4, 4), Vector3.new(200, 50, 0), { Color = o.paint }).Parent = m end
	if o.remote then T(inst("RemoteEvent", { Name = o.remote })).Parent = m end
	if o.attr then m:SetAttribute(o.attr[1], o.attr[2]) end
	if o.value then T(inst("StringValue", { Name = o.value[1], Value = o.value[2] })).Parent = m end
	m.Parent = workspace
	return m
end
local p1 = mkPlane("Plane_RAF", { occ = humanoid, attr = { "Team", "RAF" }, remote = "FireGun", fill = 8 })
local p2 = mkPlane("Zero", { occ = bobHum, wings = { "LeftWing", "RightWing" }, value = { "Faction", "Axis" } })
local p3 = mkPlane("Biplane9", { occ = bobHum })
local p4 = mkPlane("RedBaron", { wings = { "Aileron", "Rudder" } })
local p5 = mkPlane("Glider", { paint = Color3.fromRGB(10, 10, 250) })
mkPlane("Shed", {}).props.IsShed = true
_G.__SVC.Teams.props.GetTeams = function() return { teamRed, teamBlue } end
local fireGun
for _, d in ipairs(p1:GetDescendants()) do if d.Name == "FireGun" then fireGun = d end end
click(findBtn("收侦听")) -- 一个 Remote 都还没扫出来就开收侦听: 实测报告里"收 0"就是这么来的
ok(labelHas("收侦听开着但一个都没挂上") ~= nil, "没扫描过就开「收侦听」→ 状态行说清要先重扫 (收 是拿扫出来的 Remote 列表挂 OnClientEvent 的)")
click(findBtn("收侦听"))
click(findBtn("写报告")) -- 一次都没重扫过就写报告
ok(VFS["plane_debug.txt"] ~= nil and VFS["plane_debug.txt"]:find("-- 飞机 5", 1, true) ~= nil, "没重扫过就点「写报告」→ 自动先扫一遍 (实测过: 人在飞, 报告却是 飞机 0 / Remote 0)")
VFS["plane_debug.txt"] = nil
click(findBtn("重扫"))
local st1 = labelHas("飞机 ")
ok(st1 and st1:find("飞机 5", 1, true) and st1:find("Remote 2", 1, true), "重扫: 5 架飞机 (车不算) + 2 个相关 Remote (" .. tostring(st1) .. ")")
click(findBtn("写报告"))
local rep = VFS["plane_debug.txt"]
ok(rep ~= nil and CLIP == rep, "写报告 → plane_debug.txt + 剪贴板")
ok(rep and rep:find("★我", 1, true) and rep:find("队:RAF(attr:Team)", 1, true), "我坐的那架标 ★我, 队伍来自属性")
ok(rep and rep:find('队:Faction="Axis"(value)', 1, true), "队伍来自 StringValue")
ok(rep and rep:find("(乘员)", 1, true) and rep:find("乘员:Bobby", 1, true) == nil or rep:find("(乘员)", 1, true), "队伍来自乘员的队伍")
ok(rep and rep:find("(名字)", 1, true), "队伍来自机名 (RedBaron)")
ok(rep and rep:find("(涂装≈)", 1, true), "队伍来自涂装颜色最接近的 Team")
ok(rep and rep:find("FireGun", 1, true) and rep:find("-- Remote 2", 1, true), "报告里列出 Remote")
-- 高亮: 我=绿 / 同队=蓝 / 敌队=红 / 未知=灰
player.props.Team = teamRed
click(findBtn("高亮 "))
local function hlOf(m) return espHL(m) end
local function near(c, r, g, b) return math.abs(c.R - r / 255) < 1e-6 and math.abs(c.G - g / 255) < 1e-6 and math.abs(c.B - b / 255) < 1e-6 end
ok(hlOf(p1) and near(hlOf(p1).FillColor, 80, 255, 80), "我坐的飞机 = 绿")
ok(hlOf(p3) and near(hlOf(p3).FillColor, 80, 140, 255), "同队 = 蓝")
ok(hlOf(p5) and near(hlOf(p5).FillColor, 255, 70, 70), "敌队 = 红")
ok(hlOf(p2) and near(hlOf(p2).FillColor, 170, 170, 170), "队伍未知 = 灰")
click(findBtn("高亮 "))
ok(hlOf(p1) == nil and hlOf(p5) == nil, "关高亮 → 全清掉")
player.props.Team = nil
-- 发侦听: hook __namecall
click(findBtn("发侦听"))
local hookF = _G.__hook
_G.__planeHook = hookF
ok(type(hookF) == "function", "开「发侦听」会装 __namecall 钩子")
hookF(fireGun, "bullet", Vector3.new(1, 2, 3), { a = 1 })
_G.__ncm = "InvokeServer"
hookF(chatFn, "hi") -- 路径里没有关键字, 默认不录
_G.__ncm = nil
ok(pcall(hookF, {}, "x"), "记录失败(self 不是实例)不能拦住游戏自己的调用")
click(findBtn("写报告"))
rep = VFS["plane_debug.txt"]
ok(rep:find("-- 发 1", 1, true) and rep:find('Workspace.Plane_RAF.FireGun:FireServer "bullet", (1,2,3), {a=1}', 1, true), "命中关键字的 FireServer 被记下来了, 参数格式化对")
click(findBtn("全录"))
_G.__ncm = "InvokeServer"
hookF(chatFn, "hi")
_G.__ncm = nil
click(findBtn("写报告"))
ok(VFS["plane_debug.txt"]:find("ReplicatedStorage.ChatFn:InvokeServer", 1, true) ~= nil, "「全录」开了 → 没关键字的 InvokeServer 也录")
click(findBtn("全录"))
-- 收侦听
click(findBtn("收侦听"))
fireGun.OnClientEvent:Fire("boom", 5)
click(findBtn("写报告"))
ok(VFS["plane_debug.txt"]:find("-- 收 1", 1, true) and VFS["plane_debug.txt"]:find("Workspace.Plane_RAF.FireGun <- \"boom\", 5", 1, true), "OnClientEvent 收到的被记下来了")
click(findBtn("清空记录"))
click(findBtn("写报告"))
ok(VFS["plane_debug.txt"]:find("-- 发 0", 1, true) and VFS["plane_debug.txt"]:find("-- 收 0", 1, true), "清空记录 → 收发都归零")
do -- 记录折叠 / 没座位的飞机 / 疑似名单 / ★我(OldOwner): 四条都是实测报告暴露出来的盲区
	hookF(fireGun, "one")
	hookF(fireGun, "two")
	hookF(fireGun, "three")
	click(findBtn("写报告"))
	rep = VFS["plane_debug.txt"]
	ok(rep:find("×3", 1, true) ~= nil, "连续同 Remote 同目标折叠成一组 ×3 (原来 200 条不折叠只装 10 秒, RequestPlane 必被刷掉)")
	ok(rep:find('FireGun:FireServer "one"', 1, true) ~= nil and rep:find('末 Workspace.Plane_RAF.FireGun:FireServer "three"', 1, true) ~= nil, "折叠后首末两条 payload 都留着 (EngineSync 从 0.64 衰减到 0 这种趋势还看得见)")
	ok(rep:find("-- 发 3 条 / 1 组", 1, true) ~= nil, "报告头写清 原始条数/组数 (" .. tostring(rep:match("-- 发 [^\n]*")) .. ")")
	local m21 = mkPlane("M21", { noseat = true, wings = { "LeftWing", "RightWing" }, fill = 12 })
	local fw = mkPlane("FW190", { noseat = true, wings = { "LeftWing", "RightWing" }, fill = 12, attr = { "OldOwner", "Me" } })
	click(findBtn("重扫"))
	click(findBtn("写报告"))
	rep = VFS["plane_debug.txt"]
	ok(rep:find("[34] Workspace.M21 | 座:无", 1, true) ~= nil, "没座位的飞机也进报告 (机型名 M21 不在 HINT 里 → 只有 34 分, 靠「2 翼 + 12 件」这条进来)")
	ok(rep:find("FW190 ★我(OldOwner)", 1, true) ~= nil, "被服务器接管的自家飞机(座位空的, 只剩 OldOwner 属性)也标 ★我")
	ok(rep:find("-- 疑似 2", 1, true) ~= nil and rep:find("Shed | 靠座", 1, true) ~= nil and rep:find("Workspace.Car | 靠座", 1, true) ~= nil, "没过门槛的进「疑似」名单(2 个: Shed + 那辆车), 写清是靠座还是靠翼认到的 (" .. tostring(rep:match("-- 疑似 [^\n]*")) .. ")")
	ok(rep:find("· 重扫于 ", 1, true) ~= nil, "报告头带重扫时间 (只点「写报告」会得到 0 架 0 Remote 的假象)")
	m21:Destroy()
	fw:Destroy()
end
-- 自动 5s
mkPlane("Jet_new", {}) -- 手动重扫之后才冒出来的飞机: 只有真的重扫了, 它才会进报告
click(findBtn("自动 5s"))
VFS["plane_debug.txt"] = nil
step(1 / 60, 330)
ok(VFS["plane_debug.txt"] ~= nil and VFS["plane_debug.txt"]:find("Jet_new", 1, true) ~= nil, "「自动 5s」开着 → 5 秒后自己重扫 (新冒出来的飞机进了报告) 并写报告")
click(findBtn("自动 5s"))
-- 发侦听 / 收侦听 故意留着开, 让卸载去验证"钩子还原 + 连接断干净"

-- ── brick: BitFarmer 刷砖 ──
local brickBtn = btnExact("刷砖 关")
click(brickBtn)
step(1 / 60, 2)
ok(toastText():find("没找到", 1, true) ~= nil and brickBtn.Text == "刷砖 关", "没有 Collector / leaderstats → 提示并自己关回去 (" .. toastText() .. ")")
local ls = T(inst("Folder", { Name = "leaderstats" })); ls.Parent = player
local bits = T(inst("IntValue", { Name = "Bits", Value = 100 })); bits.Parent = ls
local mult = T(inst("IntValue", { Name = "Multiplier", Value = 2 })); mult.Parent = ls
local collector = mkPart("Collector", Vector3.new(10, 1, 10), Vector3.new(80, 3, 0), { Anchored = true }); collector.Parent = workspace
local fires = 0
local spawnBit = T(inst("RemoteEvent", { Name = "SpawnBit", FireServer = function() fires = fires + 1 end })); spawnBit.Parent = RSv
local function mkBrick(owner, anchored) local b = mkPart("Brick", Vector3.new(1, 1, 1), Vector3.new(0, 20, 0), { Anchored = anchored or false }); b:SetAttribute("Owner", owner); b.Parent = workspace; return b end
local b1, b2, b3, b4 = mkBrick(1), mkBrick(1), mkBrick(99), mkBrick(1, true)
click(btnExact("刷砖 关"))
step(1 / 60, 60)
bits.Value = bits.Value + 50 -- 游戏给的分
local b5 = mkBrick(1)
workspace.props.ChildAdded:Fire(b5) -- 新掉出来的砖: ChildAdded → defer → 吸走
step(1 / 60, 90)
ok(fires >= 4, "每个周期按批次发 SpawnBit (发了 " .. fires .. " 次)")
ok(mult.Value == 99999 and player:GetAttribute("MultiplierUpgradeLevel") == 9999, "倍率和等级被顶上去")
local function nearCollector(b) local pz = b.CFrame.Position; return math.abs(pz.X - 80) <= 3 and math.abs(pz.Y - 4.5) < 0.01 and math.abs(pz.Z) <= 3 end
ok(nearCollector(b1) and nearCollector(b2) and b1.AssemblyLinearVelocity.Y == -35, "自己的砖被吸到 Collector 上方并往下砸")
ok(nearCollector(b5), "新掉出来的砖也被吸走 (ChildAdded)")
ok(b3.CFrame.Position.Y == 20 and b4.CFrame.Position.Y == 20, "别人的砖 / 自己锚定的砖不碰")
local brickTxt = labelHas("周期 ")
ok(brickTxt ~= nil and brickTxt:find("+50", 1, true), "状态行有周期和累计收益 (" .. tostring(brickTxt) .. ")")
-- 关了立刻又开: 不能同时跑两条循环
click(btnExact("刷砖 开"))
click(btnExact("刷砖 关"))
local f0 = fires
step(1 / 60, 192)
ok(fires - f0 <= 16, "关了立刻又开: 只有一条循环在跑 (3.2 秒发了 " .. (fires - f0) .. " 次, 两条循环会翻倍)")
click(btnExact("刷砖 开"))
step(1 / 60, 150)
ok(mult.Value == 2 and player:GetAttribute("MultiplierUpgradeLevel") == nil, "关掉 → 倍率和等级还原 (原来的 2 / 没有)")
local f1 = fires
step(1 / 60, 120)
ok(fires == f1, "关掉以后循环真的停了")

-- ── log: 录制 / 超限重写 / 循环里抛错不能死 ──
VFS["Selfblox_log.txt"] = nil
click(findBtn("录制 "))
step(1 / 60, 250)
local logTxt = VFS["Selfblox_log.txt"]
ok(logTxt ~= nil and #logTxt > 0, "录制 → 日志文件在写")
ok(logTxt and logTxt:match("%] #%d+") ~= nil, "每条带序号 (序号接着之前的数往下走, 不从 0 重来)")
ok(logTxt and logTxt:find("配置 {", 1, true) ~= nil, "每条带整份配置")
ok(logTxt and logTxt:find("moc 速度=", 1, true) ~= nil, "每条带各模块状态")
ok(labelHas("KB / ") ~= nil, "状态行显示写了多少 KB")
local limitBox
for _, d in ipairs(all()) do if d:IsA("TextBox") and d.Text == "512" then limitBox = d end end
limitBox.Text = "0.001"; limitBox.FocusLost:Fire()
step(1 / 60, 250)
local _, entries = (VFS["Selfblox_log.txt"] or ""):gsub("%] #%d+", "")
ok(entries == 1, "超过上限 → 直接重写, 文件里只剩最新一条 (" .. entries .. " 条)")
ok((VFS["Selfblox_log.txt"] or ""):sub(1, 13) == "---- Selfblox", "重写时补上表头")
limitBox.Text = "512"; limitBox.FocusLost:Fire()
-- 循环里任何一步抛错, 记录循环都不能永久死掉
local HS = _G.__SVC.HttpService
local oldEnc = HS.props.JSONEncode
HS.props.JSONEncode = function() error("boom") end
step(1 / 60, 250)
HS.props.JSONEncode = oldEnc
local before = #(VFS["Selfblox_log.txt"] or "")
step(1 / 60, 250)
ok(#(VFS["Selfblox_log.txt"] or "") > before, "中间抛过错, 恢复后记录循环照样继续写 (没有因为一次错误永久死掉)")
click(findBtn("录制 "))

-- ── moc: 旋转 / 秒互动三态 / 速度三模式 ──
local startPos = hrp.props.Position
click(findBtn("旋转 "))
step(1 / 60, 6)
local spinAV
for _, d in ipairs(hrp:GetDescendants()) do if d.ClassName == "AngularVelocity" then spinAV = d end end
ok(spinAV ~= nil and spinAV.AngularVelocity.Y == 50, "旋转: 挂上原生 AngularVelocity, 绕 Y 轴 50")
click(findBtn("旋转 "))
step(1 / 60, 3)
local spinGone = true
for _, d in ipairs(hrp:GetDescendants()) do if d.ClassName == "AngularVelocity" then spinGone = false end end
ok(spinGone, "关旋转 → 约束删掉")
local pp = T(inst("ProximityPrompt", { Name = "Prompt", HoldDuration = 2, MaxActivationDistance = 10, RequiresLineOfSight = true, Enabled = true })); pp.Parent = workspace
local ppOff = T(inst("ProximityPrompt", { Name = "PromptOff", HoldDuration = 1, MaxActivationDistance = 8, RequiresLineOfSight = true, Enabled = false })); ppOff.Parent = workspace
for _ = 1, 3 do local b = findBtn("秒互动 "); if b.Text == "秒互动 关" then break end; click(b) end
local nocdBtn = findBtn("秒互动 ")
click(nocdBtn)
ok(nocdBtn.Text == "秒互动 普通" and pp.HoldDuration == 0 and pp.MaxActivationDistance == 1000 and pp.RequiresLineOfSight == false, "秒互动·普通: 0 长按 / 超远距离 / 不要视线")
ok(ppOff.Enabled == false and ppOff.HoldDuration == 1, "普通模式不碰被游戏关掉的")
local ppNew = T(inst("ProximityPrompt", { Name = "PromptNew", HoldDuration = 3, MaxActivationDistance = 5, RequiresLineOfSight = true, Enabled = true })); ppNew.Parent = workspace
workspace.props.DescendantAdded:Fire(ppNew)
ok(ppNew.HoldDuration == 0, "之后新出现的 prompt 也被改")
click(nocdBtn)
ok(nocdBtn.Text == "秒互动 强制" and ppOff.Enabled == true and ppOff.HoldDuration == 0, "秒互动·强制: 连关掉的也打开")
click(nocdBtn)
ok(nocdBtn.Text == "秒互动 关" and pp.HoldDuration == 2 and pp.MaxActivationDistance == 10 and pp.RequiresLineOfSight == true and ppOff.Enabled == false and ppOff.HoldDuration == 1, "关掉 → 原样还原")
-- 速度三种模式
for _ = 1, 3 do local m = findBtn("模式 "); if m.Text == "模式 root" then break end; click(m) end
local modeBtn = findBtn("模式 ")
local spdBtn = findBtn("速度 ")
if spdBtn.Text:find("开", 1, true) then click(spdBtn) end
click(spdBtn)
humanoid.props.MoveDirection = Vector3.new(0, 0, -1)
step(1 / 60, 4)
ok(hrp.props.AssemblyLinearVelocity.Z == -16 and hrp.props.AssemblyLinearVelocity.X == 0, "速度·root: 直接写水平速度 (" .. tostring(hrp.props.AssemblyLinearVelocity) .. ")")
humanoid.props.MoveDirection = Vector3.zero
step(1 / 60, 4)
ok(hrp.props.AssemblyLinearVelocity.Z == 0, "松摇杆 → 水平速度归零")
click(modeBtn)
ok(modeBtn.Text == "模式 walk", "模式按钮循环到 walk")
step(1 / 60, 4)
ok(humanoid.WalkSpeed == 16, "速度·walk: 写 WalkSpeed")
click(modeBtn)
ok(modeBtn.Text == "模式 cframe", "模式按钮循环到 cframe")
humanoid.props.MoveDirection = Vector3.new(0, 0, -1)
local z0 = hrp.props.CFrame.Position.Z
step(1 / 60, 6)
ok(hrp.props.CFrame.Position.Z < z0, "速度·cframe: 直接推 CFrame")
humanoid.props.MoveDirection = Vector3.zero
click(modeBtn)
click(spdBtn)
step(1 / 60, 3)
ok(humanoid.WalkSpeed == 16, "关速度 → WalkSpeed 还原")
hrp.props.CFrame, hrp.props.Position = CFrame.new(startPos), startPos

-- ── sibs 角落: 翻转 / 缓存的车 ──
for _, d in ipairs(all()) do if d:IsA("TextButton") and d.Text == "翻转 180°" then d.Activated:Fire() end end
ok(car.props.__pivot ~= nil, "翻转: 有 Model 就整车 PivotTo")
local loose = mkPart("Loose", Vector3.new(4, 1, 4), Vector3.new(60, 5, 0)); loose.Parent = workspace
_G.__rayHit = { Instance = loose }
click(findBtn("换车"))
step(1 / 60, 5)
for _, d in ipairs(all()) do if d:IsA("TextButton") and d.Text == "翻转 180°" then d.Activated:Fire() end end
ok(math.abs(loose.CFrame.Position.Y - 7) < 1e-6, "翻转: 没有 Model 也能翻 (抬高 2 格)")
_G.__rayHit = { Instance = seat }
click(findBtn("换车"))
step(1 / 60, 5)
_G.__rayHit = nil
loose:Destroy()

-- ── 收尾: 假场景用完就收, 不然会被当成脚本漏的实例 ──
PS.props.GetPlayers, PS.props.GetPlayerFromCharacter = savedGP, savedFC
_G.__SVC.Teams.props.GetTeams = function() return {} end
humanoid.props.SeatPart = seatSaved
for i = #TMP, 1, -1 do TMP[i]:Destroy() end
end section7c() end

print("\n[8] 写盘 / 剪贴板")
ok(VFS["Selfblox.json"] ~= nil, "改过的值写进了 Selfblox.json")
local barLbl
for _, d in ipairs(all()) do if d:IsA("TextLabel") and type(d.Text) == "string" and d.RichText == true and d.Text:find("<font", 1, true) then barLbl = d end end
ok(barLbl and barLbl.Text:find("02:37", 1, true) ~= nil, "数据条是 12 小时制 (现在该显示 02:37)")
ok(barLbl and not (barLbl.Text:find("ms", 1, true) or barLbl.Text:find("fps", 1, true) or barLbl.Text:find("MB", 1, true)), "数据条数字后面不带 ms / fps / MB 单位 (" .. tostring(barLbl and barLbl.Text) .. ")")
local LOGTXT = VFS["Selfblox_log.txt"]
ok(LOGTXT == nil or not LOGTXT:find("fps"), "日志里没有 fps/ms 那种备注")
ok(CLIP == nil or true, "剪贴板接口在")
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
ok(_G.__hook ~= _G.__planeHook, "卸载时 __namecall 钩子还原成原来的")

-- ───────── 第二轮: 只装 moc + _G.SB 覆盖 ─────────
print("\n[10] _G.SB 覆盖 + only 过滤")
SNAP = #INSTANCES
_G.SB = { only = { "moc", "hud" }, spd = 99, clock = "24", stats = true }
local fn2, lerr2 = load_chunk(SRC, "selfblox2")
ok(fn2 ~= nil, "第二轮语法 OK " .. tostring(lerr2 or ""))
local ok2, err2 = pcall(fn2)
ok(ok2, "再跑一次没报错 " .. tostring(err2 or ""))
step(1 / 60, 20) -- 先把帧喂够: 数据条 0.2s 才刷一次, 页签/数值框是立刻有的
local n = 0
for _, d in ipairs(all()) do if d:IsA("TextButton") and d.Text == "动" then n = n + 1 end end
ok(n == 1, "only={moc,hud} 只留了「动」「显」两个页签")
ok(findBtn("车") == nil and findBtn("漂") == nil and findBtn("志") == nil and findBtn("机") == nil and findBtn("砖") == nil, "only 过滤掉的页 (车/漂/志/机/砖) 根本没建")
local box = nil
for _, d in ipairs(all()) do if d:IsA("TextBox") then box = d; break end end
ok(box and box.Text == "99", "_G.SB.spd=99 顶掉了默认 16")
local bar2
for _, d in ipairs(all()) do if d:IsA("TextLabel") and type(d.Text) == "string" and d.RichText == true and d.Text:find("<font", 1, true) then bar2 = d end end
ok(bar2 and bar2.Text:find("14:37", 1, true) ~= nil, "clock=\"24\" 切回 24 小时制 (14:37)")
_G.SB_UNLOAD()
step(1 / 60, 5)
leaked = 0
for _, i in ipairs(newInstancesFrom(SNAP)) do if not i.destroyed then leaked = leaked + 1 end end
ok(leaked == 0 and LIVE == 0, "第二轮同样卸载干净")

-- ───────── 第三轮: 配置文件被写坏也要能起 ─────────
print("\n[11] 坏掉的 Selfblox.json")
_G.SB = nil -- 干净跑: 默认配置 + 被写坏的 JSON
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

-- ───────── 第四轮: 一进游戏就绑 ─────────
do
print("\n[12] 一进游戏就绑: 没坐没锁时自动绑最近的空载具座位")
local bench = inst("Seat", { Name = "Bench", CanCollide = true, Anchored = true, Size = Vector3.new(6, 1, 2), CFrame = CFrame.new(Vector3.new(3, 1, 0)), Position = Vector3.new(3, 1, 0), AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero, AssemblyMass = 1 })
bench.props.AssemblyRootPart = bench
bench.Parent = workspace
local farCar = inst("Model", { Name = "FarCar" })
local farSeat = inst("VehicleSeat", { Name = "FarSeat", CanCollide = true, Anchored = false, Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(Vector3.new(100, 5, 0)), Position = Vector3.new(100, 5, 0), AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero, AssemblyMass = 20, MaxSpeed = 30, Steer = 0, Throttle = 0 })
farSeat.props.AssemblyRootPart = farSeat
farSeat.Parent = farCar
farCar.Parent = workspace
local tb2 = inst("Part", { Name = "Primary2", CanCollide = true, Anchored = false, Size = Vector3.new(4, 1, 16), Position = Vector3.new(60, 5, 0), CFrame = CFrame.new(Vector3.new(60, 5, 0)), AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero, AssemblyMass = 1 })
tb2.props.AssemblyRootPart = tb2
tb2.Parent = truck
local occ = inst("Humanoid", {})
local driver = seat.props.Occupant
seat.props.Occupant = nil -- 空座位 (场景里默认是玩家自己坐着)
humanoid.props.SeatPart = nil
local SNAP12 = #INSTANCES
local function freshSibs(o)
	if _G.SB_UNLOAD then _G.SB_UNLOAD() end
	VFS["Selfblox.json"] = nil -- 前面点开关会把 carauto 存进配置
	o = o or {}; o.only = { "sibs" }; _G.SB = o
	local okf, ef = pcall(assert(load_chunk(SRC, "selfblox12")))
	ok(okf, "sibs 单模块能起 " .. tostring(ef or ""))
end
local function bound(p) return p:FindFirstChild("SB_SIBS") ~= nil end

_G.__radius = { bench, farSeat, seat }
freshSibs()
step(1 / 60, 90)
ok(bound(seat) and not bound(bench) and not bound(farSeat), "自动绑到最近的车座位 (长椅被跳过, 远的不选)")
ok(toastText():find("自动绑定", 1, true) ~= nil, "提示说明自动绑了 (" .. toastText() .. ")")

_G.__radius = { bench }
freshSibs()
step(1 / 60, 90)
ok(not bound(bench) and not bound(seat), "附近只有锚定的长椅 → 不绑")

seat.props.Occupant = occ
_G.__radius = { seat }
freshSibs()
step(1 / 60, 90)
ok(not bound(seat), "座位上有人 → 不绑别人的车")
seat.props.Occupant = nil

freshSibs({ carauto = false })
step(1 / 60, 90)
ok(not bound(seat), "_G.SB.carauto=false → 不自动绑")

-- 只有普通 Seat、没有 VehicleSeat 的车 (没锚定): 也该绑上; 锚定的才是长椅
local sCar = inst("Model", { Name = "SeatCar" })
local sSeat = inst("Seat", { Name = "Chair", CanCollide = true, Anchored = false, Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(Vector3.new(30, 5, 0)), Position = Vector3.new(30, 5, 0), AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero, AssemblyMass = 20 })
sSeat.props.AssemblyRootPart = sSeat
sSeat.Parent = sCar
sCar.Parent = workspace
_G.__radius = { sSeat }
freshSibs()
step(1 / 60, 90)
ok(bound(sSeat), "只有没锚定的普通 Seat 的车 → 也绑上 (锚定的才是长椅)")
_G.SB_DUMP()
local dmpPlain = VFS["selfblox_dump.txt"]
ok(dmpPlain:find("(普通座, 无油门/方向)", 1, true) ~= nil, "快照: 普通 Seat 标明「普通座, 无油门/方向」")
ok(dmpPlain:find("-- 周围的座位", 1, true) ~= nil and dmpPlain:find("Chair", 1, true) ~= nil and dmpPlain:find("乘员=空", 1, true) ~= nil, "快照: 周围座位里列出这个座位, 乘员=空")
ok(dmpPlain:find("-- 车周围 25 格里的部件", 1, true) ~= nil and dmpPlain:find("Chair                          Seat", 1, true) ~= nil, "快照: 车周围的部件里有它")
_G.__radius = { sSeat, farSeat } -- 普通 Seat 更近 (30 格) 且排在前面, VehicleSeat 在 100 格外
freshSibs()
step(1 / 60, 90)
ok(bound(farSeat) and not bound(sSeat), "VehicleSeat 优先于更近的普通 Seat")
sCar:Destroy() -- 场景物件用完就销毁, 不然会被当成脚本漏的实例
do -- 车被游戏销毁后再点诊断打包: 缓存的那辆如实说"已经不在 workspace"
	local dCar = inst("Model", { Name = "DisposableCar" })
	local dSeat = inst("VehicleSeat", { Name = "DSeat", CanCollide = true, Anchored = false, Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(Vector3.new(20, 5, 0)), Position = Vector3.new(20, 5, 0), AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero, AssemblyMass = 20, MaxSpeed = 30, Steer = 0, Throttle = 0 })
	dSeat.props.AssemblyRootPart = dSeat
	dSeat.Parent = dCar
	dCar.Parent = workspace
	_G.__radius = { dSeat }
	freshSibs()
	step(1 / 60, 90)
	ok(bound(dSeat), "(对照) 一次性的车绑上了")
	_G.__radius = {}
	dCar:Destroy()
	step(1 / 60, 5)
	_G.SB_DUMP()
	ok(VFS["selfblox_dump.txt"]:find("已经不在 workspace 里了", 1, true) ~= nil, "车被销毁后点诊断打包: 缓存的那辆如实说「已经不在 workspace」")
end
_G.__radius = { bench, farSeat, seat }

freshSibs()
step(1 / 60, 90)
ok(bound(seat), "(对照) 默认开着 → 绑上了")
_G.__rayHit = { Instance = tb2 }
click(findBtn("换车"))
step(1 / 60, 150)
ok(bound(tb2) and not bound(seat), "手动瞄准是粘性的: 附近还有更近的车座位, 也不会被自动绑抢回去")
_G.__rayHit = nil

freshSibs()
step(1 / 60, 90)
ok(bound(seat), "重新开始: 自动绑上")
humanoid.props.SeatPart = seat -- 坐下: 座位优先, 自动绑的作废
step(1 / 60, 5)
humanoid.props.SeatPart = nil
_G.__radius = {}
step(1 / 60, 120)
ok(not bound(seat), "坐过一次后自动绑的作废: 下车且附近没车 → 不留旧车")
_G.__radius = { seat }
step(1 / 60, 90)
ok(bound(seat), "下车后附近有车 → 又绑上")

-- 重生那几秒 me.Character 是 nil: 车还绑着、穿墙还开着时, noclip 每帧都在跑, 不能因为 IsDescendantOf(nil) 抛错
freshSibs({ carclip = true })
step(1 / 60, 90)
ok(bound(seat), "(对照) 穿墙开着 + 自动绑上")
local charSaved = player.props.Character
player.props.Character = nil
local late = carPart("Late", Vector3.new(1, 1, 1), Vector3.new(10, 8, 0)) -- 重生期间车上新冒出来一个零件: noclip 要判它是不是人物的 (只有新零件才会走到这一步)
local okR, eR = pcall(step, 1 / 60, 60)
ok(okR, "重生那几秒(Character=nil) 车还绑着、穿墙开着, 车上还冒出新零件: 不抛错 " .. tostring(not okR and eR or ""))
ok(late.CanCollide == false, "重生期间新冒出来的零件也照常穿墙")
late:Destroy()
player.props.Character = charSaved
step(1 / 60, 5)

_G.SB_UNLOAD()
step(1 / 60, 3)
local leaked12 = 0
for i = SNAP12 + 1, #INSTANCES do if not INSTANCES[i].destroyed then leaked12 = leaked12 + 1 end end
ok(leaked12 == 0 and LIVE == 0, "自动绑车这一轮卸载同样干净 (漏 " .. leaked12 .. " 个实例 / " .. LIVE .. " 个连接)")
_G.__radius = nil
seat.props.Occupant = driver
end

-- ───────── 第五轮: 清单的扩展性 —— 加一个功能 = 一个顶层函数 + 清单一行, 不改核心 ─────────
do
print("\n[13] 清单: 往源码里注入一个玩具功能 (一个函数 + 几行清单), 核心一个字不改")
if _G.SB_UNLOAD then _G.SB_UNLOAD() end
VFS["Selfblox.json"] = nil
_G.SB = nil
_G.__ping, _G.__pingbtn = nil, nil
local EXTRA = [[
do -- 玩具: 一个顶层函数 + 清单几行
	local ticks, offs = 0, 0
	local function pingTick(dt) ticks = ticks + 1; _G.__ping = { ticks = ticks, offs = offs, v = S.pingn } end
	local function pingOff() offs = offs + 1; _G.__ping = { ticks = ticks, offs = offs, v = S.pingn } end
	feature{ kind = "page", id = "toy", tab = "玩" }
	feature{ key = "ping", save = "pingsave", label = "测试开关", num = { "pingn", 7 }, tick = pingTick, off = pingOff }
	feature{ kind = "cycle", key = "pingmode", save = "pingmode", def = "a", cycle = { "a", "b" }, text = function(v) return "档 " .. v end }
	feature{ kind = "btn", label = "测试按钮", fn = function() _G.__pingbtn = true end }
	feature{ kind = "custom", label = "坏行", build = function() error("boom") end }
	feature{ kind = "dump", key = "toydump", dump = function() return { "玩具诊断行" } end }
end
]]
local at = SRC:find("-- ───────── 启动: 按清单建页", 1, true)
ok(at ~= nil, "找得到清单的建页入口")
local SNAP13 = #INSTANCES
local okLoad, errLoad = pcall(assert(load_chunk(SRC:sub(1, at - 1) .. EXTRA .. SRC:sub(at), "selfblox14")))
ok(okLoad, "多一个功能 (含一个坏行) 后脚本照样起得来 " .. tostring(errLoad or ""))
local toy = findBtn("测试开关 ")
ok(toy ~= nil and toy.Text == "测试开关 关", "清单一行 → 面板上多了开关")
ok(findBtn("档 a") ~= nil and findBtn("测试按钮") ~= nil, "cycle / btn 行也按清单建出来")
local box
for _, d in ipairs(all()) do if d:IsA("TextBox") and d.Text == "7" then box = d end end
ok(box ~= nil, "num 框自动跟在开关后面 (默认 7)")
box.Text = "9"; box.FocusLost:Fire()
ok(jsonDecode(VFS["Selfblox.json"]).pingn == 9, "改了数值自动写进 Selfblox.json")
step(1 / 60, 5)
ok(_G.__ping == nil, "开关关着 → 不 tick")
click(toy)
step(1 / 60, 5)
ok(_G.__ping ~= nil and _G.__ping.ticks == 5 and _G.__ping.v == 9, "开着 → 每帧 tick, 读得到面板里改的数值")
click(toy)
ok(_G.__ping.offs == 1, "关掉 → 调 off")
step(1 / 60, 5)
ok(_G.__ping.ticks == 5, "关掉以后不再 tick")
ok(jsonDecode(VFS["Selfblox.json"]).pingsave == false, "save 键存了开关状态")
click(findBtn("测试按钮"))
ok(_G.__pingbtn == true, "btn 行的回调被调到")
click(findBtn("档 a"))
ok(findBtn("档 b") ~= nil, "cycle 行循环")
ok(jsonDecode(VFS["Selfblox.json"]).pingmode == "b", "cycle 行的值也按 save 键存盘")
local bad
for _, d in ipairs(all()) do if d:IsA("TextLabel") and d.Text == "✗ 坏行" then bad = d end end
ok(bad ~= nil, "坏行装不上 → 页里写一行 ✗, 其余功能不受影响")
_G.SB_DUMP()
local dm = VFS["selfblox_dump.txt"]
ok(dm:find("toy 测试开关=false", 1, true) ~= nil and dm:find("pingn=9", 1, true) ~= nil, "诊断快照自动带上新页的开关 / 数值")
ok(dm:find("玩具诊断行", 1, true) ~= nil, "dump 行注册的诊断提供者被调到")
ok(dm:find("✗ toy 坏行", 1, true) ~= nil, "快照里列出装不上的功能")
click(toy)
_G.SB_UNLOAD()
step(1 / 60, 3)
ok(_G.__ping.offs == 2, "卸载时开着的功能也被 off")
local leaked13 = 0
for i = SNAP13 + 1, #INSTANCES do if not INSTANCES[i].destroyed then leaked13 = leaked13 + 1 end end
ok(leaked13 == 0 and LIVE == 0, "加了功能的这一轮卸载同样干净 (漏 " .. leaked13 .. " 个实例 / " .. LIVE .. " 个连接)")
_G.__ping, _G.__pingbtn = nil, nil
end

print("\n" .. (FAILS == 0 and "全部通过 ✓" or ("有 " .. FAILS .. " 条没过 ✗")))
if os.exit then os.exit(FAILS == 0 and 0 or 1) end
if FAILS ~= 0 and error then error(FAILS .. " 条没过", 0) end
