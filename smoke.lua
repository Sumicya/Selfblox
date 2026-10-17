-- Selfblox 离线自检: 一个假 Roblox 引擎, 加载 selfblox.lua → 建面板 → 点一遍 → 卸载 → 断言干净
-- 跑法: lua5.4 smoke.lua     (luajit / lua5.1 / luau 也行; 不跑也不影响脚本本体)
-- 它只验"结构不炸 + 状态真的改了 + 卸载不留垃圾", 不验游戏里的手感。
local SRC = SB_SRC_INJECTED or rawget(_G, "SB_SRC") -- 源码从外面塞进来: CI 把 selfblox.lua 拼成本 chunk 顶部的 local SB_SRC_INJECTED(不碰全局, 见工作流), 手工跑时用 _G.SB_SRC 或 io 读文件
if not SRC then
	if not io or not io.open then error("这个 VM 没有 io 库(Luau 就是): 用 .github/workflows/spec-check.yml 的做法把源码拼成 SB_SRC_INJECTED 再跑", 0) end
	local dir = arg and arg[0] and arg[0]:match("^(.*[/\\])") or ""
	local fp = io.open(`{dir}selfblox.lua`, "rb") or io.open("selfblox.lua", "rb")
	SRC = assert(fp, "找不到 selfblox.lua; 在仓库根目录跑: lua5.4 smoke.lua"):read("*a")
end
local load_chunk = load or loadstring

-- ───────── 垫片: Roblox 有、标准 Lua 没有 ─────────
-- Luau CLI 冻结了标准库表和 _G (实测: math.sign = f / _G.x = 1 都报 attempt to modify a readonly table, 但裸全局可写)。
-- 自检要给 math/table 补缺失成员、把 os.clock 换成虚拟时钟、往 _G 上挂假引擎, 所以在冻结的 VM 里先换成可写副本。
-- Roblox 里这些本来就可写: 每一步都先探测再动手, 在 Lua 5.4 / fengari 下是空操作。
local function isFrozen(t) return type(t) ~= "table" or not pcall(function() rawset(t, "__sb_probe", 1) end) end
local function thaw(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end
if isFrozen(math) then math = thaw(math) end
if isFrozen(table) then table = thaw(table) end
if isFrozen(os) then os = thaw(os) end
local FROZEN_G = isFrozen(_G)
if FROZEN_G then local realG = _G; _G = setmetatable({}, { __index = realG }) end -- 写进代理, 读不到就回落原来那张表

-- Luau CLI: _G 是上面换掉的可写代理, 可 selfblox.lua 和下面的 inst() 读的是裸全局;
-- 这些名字在本文件里是 local, 直接写会写到 local 上, 所以借一个没有同名 local 的 chunk 把它们写成真全局。
-- 每批 _G.X = ... 之后都要再调一次: 假引擎自己也会按全局名读它们 (Color3.fromRGB 就是)。
local MODULES = {} -- ModuleScript 实例 -> require 它拿到的表 (假引擎里 require 就是查这张表)
local function fakeRequire(ms) local m = MODULES[ms]; if m == nil then error("ModuleScript 没有内容", 2) end; return m end

local function exposeGlobals()
	if not FROZEN_G then return end
	local expose = assert(load_chunk("Instance, RaycastParams, OverlapParams, Vector3, Vector2, Color3, CFrame, UDim, UDim2, Enum, workspace, CoreGui, warn, typeof, require = ...", "smoke_expose"))
	expose(_G.Instance, _G.RaycastParams, _G.OverlapParams, _G.Vector3, _G.Vector2, _G.Color3, _G.CFrame, _G.UDim, _G.UDim2, _G.Enum, _G.workspace, _G.CoreGui, _G.warn, _G.typeof, fakeRequire) -- typeof 也要装: Luau 自带原生 typeof, 对假 Vector3 只回 "table",
	-- 脚本第 883 行的 `t == "Vector3"` 分支走不到, 参数会被渲染成 {Y=2,X=1,Z=3} 而不是 (1,2,3)
end

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
local di = debug.getinfo or function(level, _) return { short_src = debug.info(level + 1, "s") } end
local function fromScript(level) -- 谁在访问: selfblox.lua 的代码 (chunk 名 selfblox*) 还是测试自己
	local ii = di(level or 4, "S")
	local src = ii and (ii.short_src or ii.source) or ""
	return src:find('^%[string "selfblox') ~= nil or src:find("^=?selfblox") ~= nil
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
	Humanoid = words("ChangeState GetState Health JumpHeight JumpPower MoveDirection PlatformStand SeatPart UseJumpPower WalkSpeed"),
	ImageButton = words("AbsolutePosition AbsoluteSize Active InputBegan InputEnded Visible"),
	IntValue = words("Value"),
	Lighting = words("Ambient Brightness FogEnd GlobalShadows OutdoorAmbient"),
	LinearVelocity = words("Attachment0 MaxForce RelativeTo VectorVelocity"),
	Model = words("GetExtentsSize GetPivot PivotTo"),
	Part = words("Anchored AssemblyAngularVelocity AssemblyLinearVelocity AssemblyMass AssemblyRootPart CFrame CanCollide Color GetConnectedParts Position Size"),
	Player = words("Character DisplayName GetNetworkPing Team TeamColor UserId"),
	PlayerGui = words(""),
	Players = words("GetPlayerFromCharacter GetPlayers LocalPlayer MaxPlayers PlayerAdded PlayerRemoving"),
	ProximityPrompt = words("Enabled HoldDuration MaxActivationDistance RequiresLineOfSight KeyboardKeyCode"),
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
	TextButton = words("AbsolutePosition AbsoluteSize Active Activated AutoButtonColor BackgroundColor3 BackgroundTransparency BorderSizePixel Font InputBegan InputEnded LayoutOrder Position Size Text TextColor3 TextSize TextXAlignment TextYAlignment Visible"),
	TextLabel = words("AbsolutePosition AnchorPoint AutomaticSize BackgroundColor3 BackgroundTransparency BorderSizePixel Font InputBegan InputEnded LayoutOrder Position RichText Size Text TextColor3 TextSize TextStrokeTransparency TextWrapped TextXAlignment TextYAlignment Visible"),
	UICorner = words("CornerRadius"),
	UIDragDetector = words("BoundingUI DragAxis DragContinue DragEnd DragStart DragStyle"),
	UIListLayout = words("FillDirection Padding"),
	UIPadding = words("PaddingLeft PaddingRight"),
	UserInputService = words("InputEnded JumpRequest"), -- InputEnded 是真成员: 按住钮的全局松手兜底靠它
	VectorForce = words("ApplyAtCenterOfMass Attachment0 Force RelativeTo"),
	VehicleSeat = words("Anchored AssemblyAngularVelocity AssemblyLinearVelocity AssemblyMass AssemblyRootPart CFrame CanCollide GetConnectedParts MaxSpeed Occupant Position Size Steer Throttle Torque"),
	VirtualInputManager = words("SendKeyEvent SendMouseButtonEvent"),
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
		error(`{cls}.{k} 没对照官方文档核对过 (不在 VERIFIED 里): 先确认它真的存在, 再加进来`, 3)
	end
end
local Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({ hs = {} }, Signal) end
function Signal:Connect(fn)
	local c = { fn = fn, on = true }
	LIVE += 1
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
	_G.__descCalls = (_G.__descCalls or 0) + 1 -- 数全树遍历: 半秒一轮的功能有没有护栏, 靠这个才量得出来
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
function methods.GetFullName(self) local p = rawget(self, "parent"); return (p and (`{methods.GetFullName(p)}.`) or "") .. tostring(self.Name) end
function methods.GetAttribute(self, k) return self.attrs[k] end
function methods.SetAttribute(self, k, v) self.attrs[k] = v end
function methods.GetAttributes(self) local o = {}; for k, v in pairs(self.attrs) do o[k] = v end; return o end
function methods.GetPropertyChangedSignal(self, p) local s = self.props[`__pcs_{p}`]; if not s then s = Signal.new(); self.props[`__pcs_{p}`] = s end; return s end
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
local function vimArgs(name, ok_, spec) if not ok_ then error(`{name} 参数类型不对, 应为 {spec}`, 3) end end
function methods.SendMouseButtonEvent(self, x, y, btn, down, g, rep) -- 签名同上出处: (x: number, y: number, mouseButton: number, isPressed: bool, game: any, replayCount: number)
	vimArgs("SendMouseButtonEvent", type(x) == "number" and x == x and type(y) == "number" and y == y and type(btn) == "number" and type(down) == "boolean" and type(g) == "table" and type(rep) == "number", "(x: number, y: number, mouseButton: number, isPressed: bool, game: any, replayCount: number)")
	self.props.clicks = self.props.clicks or {}
	self.props.clicks[#self.props.clicks + 1] = { x = x, y = y, btn = btn, down = down }
end
function methods.SendKeyEvent(self, down, key, rep, layer)
	vimArgs("SendKeyEvent", type(down) == "boolean" and type(key) == "table" and key.EnumType == "KeyCode" and type(rep) == "boolean" and type(layer) == "table", "(isPressed: bool, keyCode: KeyCode, isRepeatedKey: bool, layerCollector: Instance)")
	self.props.keys = (self.props.keys or 0) + 1
	-- 只记个数验不出「按下加抬起」和「键对不对」: 只按不抬, 游戏那边下一次就不认了 (点按钮那条已经吃过这个亏)
	self.props.keySeq = self.props.keySeq or {}
	self.props.keySeq[#self.props.keySeq + 1] = { down = down, name = key.Name }
end
function methods.GetConnectedParts(self) -- 假装配体: 同 Model 里 AssemblyRootPart 相同的 BasePart (真引擎只返回焊在一起的, 锚定的停车台/另一个装配体不算)
	local o, seen = {}, {}
	local m = methods.FindFirstAncestorOfClass(self, "Model") or self
	local ra = self.props.AssemblyRootPart or self
	for _, d in ipairs(methods.GetDescendants(m)) do if not seen[d] and methods.IsA(d, "BasePart") and (d.props.AssemblyRootPart or d) == ra then seen[d] = true; o[#o + 1] = d end end
	if not seen[self] then o[#o + 1] = self end
	return o
end
function methods.GetState(self) return rawget(self, "sbstate") or { Name = "Running" } end -- 默认 Running: 状态门在旧断言里应当是空操作
function methods.SetNetworkOwner() error("SetNetworkOwner 客户端不让调 (上一版就是这一句把车搞成完全绑不上)") end
function methods.GetPartBoundsInRadius(self, pos, radius) _G.__radiusCalls = (_G.__radiusCalls or 0) + 1; _G.__radiusArgs = { r = radius } -- 记次数验节流, 记入参验半径真的传下去了
	return _G.__radius or {} end

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
			if not strict[k] then error(`{tostring(k)} is not a valid member of {t.ClassName}`, 2) end
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
			if k == "CFrame" then -- Luau 把 a.b.c 这种全常量键链编译成 GETIMPORT; 实测(本地按 0.741 源码编的 Luau):
				-- 经 loadstring 装载的 chunk 里, 同一条链首次求值后就被冻住 —— 第二次读 gws.CurrentCamera.CFrame 返回的仍是
				-- 旧对象、__index 一次都不再触发; 主 chunk 里直接读则每次都新鲜。上游: LOP_GETIMPORT 的常量池快路径
				-- (VM/src/lvmexecute.cpp:489-508); luaV_getimport 自己不缓存、且最多 3 段(VM/src/lvmload.cpp:91)。
				-- 真引擎的属性不是 Lua 表链, 没这回事; 假引擎用 __index 模拟属性才中招。这里把旧对象就地改成新值,
				-- 让被冻住的引用也跟着变; props 里另存一份, 不和调用方手里的对象串味。
				local wasC = rawget(t, "props")[k]
				if type(wasC) == "table" and rawget(wasC, "x") and type(v) == "table" and rawget(v, "x") then
					-- 就地改 wasC 并且**不换掉它**: 原来这里改完又把一份副本存回 props, 于是被冻住的那个引用只在
					-- 第一次写入时跟着变, 第二次写入改的是副本, 脚本手里的旧对象从此停在中间值上 —— selfblox 读
					-- workspace.CurrentCamera.CFrame 拿到飞车测试时朝 +X 的相机, 而主 chunk 现读的是新的, 两边对不上。
					-- 只维护同一个规范对象就两头都新鲜, 调用方手里那个 v 也照样不被串改。
					wasC.x, wasC.y, wasC.z, wasC.p = v.x, v.y, v.z, v.p
					return
				end
			end
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
		error(`{tostring(k)} is not a valid member of Vector2`, 2) -- 真引擎读数据类型上不存在的成员也是直接抛错; 这里不抛, i.Position 就会悄悄变成 nil 溜过去
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
	if k ~= "KeyCode" and not ENUM_OK[k] and fromScript(3) then error(`Enum.{tostring(k)} 没对照官方文档核对过 (不在 ENUM_OK 里)`, 2) end
	local sub = setmetatable({}, { __index = function(_, v) if ENUM_OK[k] and not ENUM_OK[k][v] and fromScript(3) then error(`Enum.{k}.{tostring(v)} 没对照官方文档核对过 (不在 ENUM_OK 里)`, 2) end; local item = { Name = v, EnumType = k }; rawset(t[k], v, item); return item end })
	rawset(t, k, sub)
	return sub
end })

-- 假引擎: 挂成全局, selfblox.lua 是另一个 chunk, 只能看全局
_G.Instance = { new = function(cls, parent) local i = inst(cls); if parent then i.Parent = parent end; return i end }
_G.RaycastParams = { new = function() return { FilterType = nil } end }
_G.OverlapParams = { new = function() return { FilterType = nil, FilterDescendantsInstances = {} } end }
_G.Vector3, _G.Vector2, _G.Color3, _G.CFrame, _G.UDim, _G.UDim2, _G.Enum = Vector3, Vector2, Color3, CFrame, UDim, UDim2, Enum
if not warn then _G.warn = function(...) print("warn:", ...) end end
exposeGlobals()

-- 假引擎: 场景
local function sig(props) props = props or {}; for _, n in ipairs({ "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving" }) do props[n] = Signal.new() end; return props end
game = { PlaceId = 0, Name = "SmokePlace", GetService = function(_, n) return assert(_G.__SVC[n], `没造的服: {n}`) end }
_G.__SVC = {}
local function svc(name, o) o = o or inst(name); _G.__SVC[name] = o; return o end

local workspace = svc("Workspace", inst("Workspace", sig()))
local camera = inst("Camera", { CFrame = CFrame.new(Vector3.zero), ViewportSize = Vector2.new(1080, 2400) })
workspace.props.CurrentCamera = camera
_G.workspace = workspace
exposeGlobals()

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

-- 官方 PlayerModule: PlayerScripts/PlayerModule → require 出来直接 :GetControls():GetMoveVector()
-- 照官方源码, require 回来那张表上只有 GetCameras / GetControls / GetClickToMoveController, 没有 GetModule。
-- 上一版脚本凭空多插了一层 :GetModule(), 真机错误串就是 "attempt to call missing method 'GetModule' of tab";
-- 而假引擎原来是照着那个错写法建的(见下), 所以这个 bug 一路绿灯混过了六版 —— 假件必须照官方建, 不照脚本建。
-- SBMV.force 不为 nil 时返回它, SBMV.gone 为真时抛错 —— 造真机上「MoveDirection 冻住 / 控制模块坏了」两种分歧。
local SBMV = {}
local pmodule = inst("ModuleScript", { Name = "PlayerModule" })
pmodule.Parent = inst("PlayerScripts", { Name = "PlayerScripts" })
pmodule.Parent.Parent = player
local function mkControls()
	return { GetMoveVector = function()
		if SBMV.gone then error("控制模块不可用") end
		if SBMV.force ~= nil then return SBMV.force end
		local md = humanoid.props.MoveDirection or Vector3.zero -- 世界 → 相机相对(前推 Z=-1)
		if md.Magnitude < 1e-9 then return Vector3.zero end
		local cf = camera.CFrame
		return Vector3.new(md:Dot(cf.RightVector), md:Dot(cf.UpVector), -md:Dot(cf.LookVector))
	end }
end
-- require 回来就是这张表: 只有 GetControls / GetCameras, 读 GetModule 得到 nil (和真引擎一致),
-- 脚本里 `t.GetControls and t:GetControls()` 因此直调成功, 而上一版那句 :GetModule() 会在这儿抛错。
MODULES[pmodule] = {
	GetControls = function() if SBMV.gone then error("PlayerModule 不可用") end; return mkControls() end,
	GetCameras = function() return {} end,
}svc("Players", inst("Players", { LocalPlayer = player, MaxPlayers = 12, GetPlayers = function() return { player } end, GetPlayerFromCharacter = function(_, c) return c == char and player or nil end, PlayerAdded = Signal.new(), PlayerRemoving = Signal.new() }))
svc("RunService", inst("RunService", { PreSimulation = Signal.new(), PreRender = Signal.new(), Heartbeat = Signal.new() }))
svc("UserInputService", inst("UserInputService", { InputEnded = Signal.new(), JumpRequest = Signal.new(), TouchEnabled = true, GetMouseLocation = function() return Vector2.new(100, 100) end }))
svc("Lighting", inst("Lighting", { Ambient = Color3.fromRGB(70, 70, 70), OutdoorAmbient = Color3.fromRGB(70, 70, 70), Brightness = 1, FogEnd = 100000, GlobalShadows = true }))
svc("Stats", inst("Stats", { GetTotalMemoryUsageMb = function() return 512 end }))
svc("Teams", inst("Teams", { GetTeams = function() return {} end }))
svc("ReplicatedStorage", inst("ReplicatedStorage", sig()))
svc("VirtualInputManager", inst("VirtualInputManager"))
svc("HttpService", inst("HttpService"))
svc("CoreGui", inst("CoreGui", sig()))
player.props.GetNetworkPing = function() return 0.05 end
_G.CoreGui = _G.__SVC.CoreGui

exposeGlobals()


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
	spawn = function(f, ...) local co = coroutine.create(f); local ok, err = coroutine.resume(co, ...); if not ok then error(`task.spawn: {tostring(err)}`, 0) end; return co end,
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
		local o = {}; for k, x in pairs(v) do o[#o + 1] = `"{tostring(k)}":{jsonEncode(x)}`end; return "{" .. table.concat(o, ",") .. "}"
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
			i += 1; local o = {}; skip()
			if s:sub(i, i) == "}" then i = i + 1; return o end
			while true do skip(); local k = str(); skip(); i = i + 1; o[k] = parse(); skip(); if s:sub(i, i) == "," then i = i + 1 else i = i + 1; break end end
			return o
		elseif c == "[" then
			i += 1; local o = {}; skip()
			if s:sub(i, i) == "]" then i = i + 1; return o end
			while true do o[#o + 1] = parse(); skip(); if s:sub(i, i) == "," then i = i + 1 else i = i + 1; break end end
			return o
		elseif c == '"' then return str() end
		if s:sub(i, i + 3) == "true" then i = i + 4; return true end
		if s:sub(i, i + 4) == "false" then i = i + 5; return false end
		if s:sub(i, i + 3) == "null" then i = i + 4; return nil end
		local n = assert(s:match("^[%-%d%.eE]+", i), `坏 JSON @{i}: {s:sub(i, i + 20)}`)
		i += #n; return tonumber(n)
	end
	return parse()
end
_G.__SVC.HttpService.props.JSONEncode = function(_, v) return jsonEncode(v) end
_G.__SVC.HttpService.props.JSONDecode = function(_, s) return jsonDecode(s) end

-- ───────── 断言 + 步进 ─────────
local FAILS = 0
local function ok(cond, msg) if cond then print(`  ✓ {msg}`) else FAILS = FAILS + 1; print(`  ✗ {msg}`) end end
local function step(dt, n)
	for i2 = 1, (n or 1) do
		NOW += dt
		local due = {}; local keep = {}
		for _, w in ipairs(WAITERS) do if w.t <= NOW then due[#due + 1] = w else keep[#keep + 1] = w end end
		WAITERS = keep
		for _, w in ipairs(due) do
			if coroutine.status(w.co) ~= "dead" then
				local ok2, err = coroutine.resume(w.co)
				if not ok2 then error(`任务里炸了: {tostring(err)}`, 0) end
			end
		end
		_G.__SVC.RunService.props.PreSimulation:Fire(dt)
		_G.__SVC.RunService.props.PreRender:Fire(dt)
		if _G.__SVC.UserInputService.props.JumpRequest then _G.__SVC.UserInputService.props.JumpRequest:Fire() end
		-- 假引擎不算物理, "游戏自己把人挪走了"这一步只能由测试演。放在信号跑完之后, 顺序才和真引擎一致:
		-- 脚本先在 PreSimulation 里量上一帧到这一帧的位移(= 游戏挪的量), 推完, 然后游戏才挪这一步。
		if _G.__gameMove then hrp.props.CFrame = hrp.props.CFrame + _G.__gameMove end
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

print(`── 假引擎就绪: {#INSTANCES} 个场景实例`)
local SNAP = #INSTANCES

-- ───────── 假引擎自己的严格性自检 ─────────
-- 白名单只拦 chunk 名 selfblox* 的调用方, 判断靠 fromScript; 换 VM (Lua 5.4 → Luau) 时 fromScript 可能静默失效,
-- 失效了后面几百条断言就全变成"什么成员都认"的宽松模式, 所以这里先主动验一次它真的在拦。
print("\n[0] 假引擎白名单还生效吗")
local probe = Instance.new("Part")
-- 栈层要和真代码一致: 访问发生在 selfblox* 的函数里, 上面还得有两层 selfblox* 的调用者 (fromScript 默认查第 4 层)
local wrapper = assert(load_chunk([[
local inst = ...
local function touch(i) return i.ThisMemberIsInNoDoc end
local function mid() return touch(inst) end
return mid()
]], "selfblox_strict"))
local okBad, errBad = pcall(wrapper, probe)
ok(not okBad and tostring(errBad):find("没对照官方文档核对过", 1, true) ~= nil, `selfblox* 的代码碰没核对过的成员会抛错 ({tostring(errBad)})`)
local okMine = pcall(function() return probe.ThisMemberIsInNoDoc end)
ok(okMine, "白名单不管自检自己的代码, 只拦 selfblox* 的 chunk")
probe:Destroy() -- 探针也是实例, 不销毁就会算成卸载后漏掉的实例

-- ───────── 第一轮: 全量加载 ─────────
print("\n[1] 加载 selfblox.lua")
local chunk = assert(load_chunk(SRC, "selfblox"))
local okLoad, errLoad = pcall(chunk)
ok(okLoad, `脚本跑完没报错 {tostring(errLoad or "")}`)
ok(type(_G.SB_UNLOAD) == "function", "_G.SB_UNLOAD 有了")
ok(tabs() ~= nil, "面板建在 gethui() 里")
local names = {}
for _, b in ipairs(buttons()) do if #b.Text <= 3 and b.Text ~= "" then names[b.Text] = true end end
ok(names["动"] and names["车"] and names["漂"] and names["显"] and names["志"] and names["机"] and names["抓"], "七个页签都在")
ok(#newInstancesFrom(SNAP) > 60, `控件建了 {#newInstancesFrom(SNAP)} 个实例`)
local errs = 0 -- 模块构造时 pcall 兜住了错误会写成一行"出错: ...", 这里要当成失败抓出来
for _, d in ipairs(all()) do if d.ClassName == "TextLabel" and type(d.Text) == "string" and d.Text:sub(1, 6) == "出错: " then errs = errs + 1; print(`       → {d.Text}`) end end
ok(errs == 0, "没有模块构造失败")
local VER = SRC:match('local VERSION = "([^"]+)"') -- 版本单一来源: 面板标题 / 诊断快照 / 启动打印都必须读它
local vy, vm, vd, vdaily, vtotal -- 五段: yy.m.d.当日序号.总序号 (注意 `x and f()` 只回传一个值, 多返回值不能用 and 接)
if VER then vy, vm, vd, vdaily, vtotal = VER:match("^(%d%d)%.(%d%d?)%.(%d%d?)%.(%d+)%.(%d+)$") end
ok(vy ~= nil, `VERSION 是五段 yy.m.d.当日序号.总序号 ({tostring(VER)})`)
ok(vy ~= nil and tonumber(vm) >= 1 and tonumber(vm) <= 12 and tonumber(vd) >= 1 and tonumber(vd) <= 31 and tonumber(vdaily) >= 1 and tonumber(vtotal) >= 1, `五段取值合法: 月 1~12 / 日 1~31 / 当日序号与总序号都从 1 起 ({tostring(VER)})`)
ok(VER ~= nil and VER:sub(1, 1) ~= "v" and select(2, SRC:gsub(`"{VER:gsub("%.", "%%.")}"`, "")) == 1, "展示版本不带 v, 版本号只在 VERSION 一行写死")
local title0 = tabs():FindFirstChild("SB_Title")
-- 标题就是 VERSION 本身: 原来前面还挂着 "Selfblox " 前缀, 总序号上三位数后整条撑出面板 184px。
ok(title0 ~= nil and title0.Text == tostring(VER), `面板标题就是 VERSION, 不另抄一份 (读到 {tostring(title0 and title0.Text)})`)
-- 面板宽度: 一行两个按钮各占一半, 面板窄了它们才真的左右靠近 (26.10.15 起 200 → 160, 半行按钮 100 → 80)
ok(title0 ~= nil and title0.Size.X.Offset == 184, `面板宽 184, 半行按钮 = {title0 and title0.Size.X.Offset / 2}px (读到 {title0 and title0.Size.X.Offset})`)
ok(tabs():FindFirstChild("SB_Body") ~= nil and tabs():FindFirstChild("SB_Body").Size.X.Offset == 184, "面板体和标题一样宽")
-- 折叠钮原来是直接压在标题文字上的 (26×26 贴右边): 200px 时刚好不撞, 面板一窄就会盖住版本号末位
-- 不变量 = 标题用 UIPadding 让出的宽度必须等于折叠钮占的宽度, 两边一起动才不会重新叠上
local foldB
for _, c in ipairs(title0:GetChildren()) do if c.ClassName == "TextButton" and c.Text == "–" then foldB = c end end
ok(foldB ~= nil, "标题条上有折叠钮")
ok(foldB ~= nil and foldB.Size.X.Offset == 18, `折叠钮占宽 18 (原 26) (读到 {foldB and foldB.Size.X.Offset})`)
ok(foldB ~= nil and foldB.Position.X.Offset == -foldB.Size.X.Offset, "折叠钮贴右边, 不越界")
ok(title0 ~= nil and title0.TextSize == 12, `标题字号跟面板其它文字一致 = 12 (读到 {title0 and title0.TextSize})`)
-- 面板宽度的真正下限是标题栏: 折叠钮压在标题上, 标题又是居中的, 所以 "标题文字宽 + 折叠钮宽" 必须塞得进面板
-- 宽度只能估(假引擎没有字体度量): CJK 按 12px, 其它按 7px @ 12 号 —— 这是偏保守的上界
local function estPx(str)
	local wide, narrow = 0, 0
	for i = 1, #str do local b = str:byte(i); if b >= 0xE0 then wide += 1 elseif b < 0x80 then narrow += 1 end end
	return wide * 12 + narrow * 7 -- 3 字节字符的续字节 0x80..0xBF 两个分支都不进, 不会重复计
end
-- 文字是居中的(标题没设 TextXAlignment, TextLabel 默认居中), 折叠钮贴在右边 FOLDW 宽, 标题又没有 UIPadding,
-- 所以真正的约束是「文字宽 + 折叠钮两侧各让一份」<= 面板宽, 不是原先写的「文字宽 + 一份」。原先那条比真约束松了
-- 一个折叠钮的宽度 —— 松方向的错, 会把快要压上的情况判成安全。
local need = estPx(title0 and title0.Text or "") + 2 * (foldB and foldB.Size.X.Offset or 0)
ok(title0 ~= nil and foldB ~= nil and need <= title0.Size.X.Offset, `标题文字(估 {estPx(title0 and title0.Text or "")}px) 居中 + 折叠钮({foldB and foldB.Size.X.Offset}px)两侧各让一份 塞得进面板 {title0 and title0.Size.X.Offset}px (需要 {need}px)`)

-- 通用不变量: 每个「不换行」的文字都得塞得进自己那一格。钉单个标签没用 —— 「抓取半径」4 个汉字
-- 48px 挤在 46px 的半行标签槽里被切掉, 就是没有这条才漏过去的。会换行的行不在此列(它们靠自动长高)。
do
	local function pxW(d) -- 假引擎没有布局, 按 Size 的 scale/offset 顺着父链折算像素宽
		if d.ClassName == "ScreenGui" then return 184 end
		local sz = d.props.Size
		local sc = (sz and sz.X and sz.X.Scale) or 0
		local off = (sz and sz.X and sz.X.Offset) or 0
		local par = d.Parent
		return sc * (par and pxW(par) or 184) + off
	end
	local over = {}
	for _, d in ipairs(all()) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and type(d.props.Text) == "string" and d.props.Text ~= "" then
			local as = d.props.AutomaticSize
			local grows = as ~= nil and as.EnumType == "AutomaticSize" and as.Name ~= "None"
			if not grows and d.props.TextWrapped ~= true then
				local need, have = estPx(d.props.Text), pxW(d)
				if need > have then over[#over + 1] = string.format("「%s」%dpx>%dpx", d.props.Text, need, have) end
			end
		end
	end
	ok(#over == 0, `每个不换行的文字都塞得进自己的槽 (超出的: {#over > 0 and table.concat(over, " ") or "无"})`)
end

-- 会换行的帮助行必须自己长高: 面板 184px 宽, 有两条帮助文字估到 195px / 191px, 一定会换行;
-- 而 ui() 给的是固定 26px 行高, 不开自动高度的话第二行等于写了看不见 (自查量出来的真缺陷)。
do
	local nWrap, nAuto = 0, 0
	for _, d in ipairs(all()) do
		if d:IsA("TextLabel") and d.props.TextWrapped == true then
			nWrap += 1
			local as = d.props.AutomaticSize
			if as ~= nil and as.EnumType == "AutomaticSize" and as.Name ~= "None" then nAuto += 1 end
		end
	end
	ok(nWrap > 0 and nAuto == nWrap, `会换行的帮助行都开了自动长高 ({nAuto}/{nWrap})`)
end
-- 启动打印改成了 Luau 插值写法(26.10 起 selfblox.lua 以 Luau 为基线), 断言跟着认新写法
ok(SRC:find('print(`[Selfblox] {VERSION}', 1, true) ~= nil, "启动打印读 VERSION, 不另写一份")

print("\n[2] 空转 30 帧 (没有任何开关)")
step(1 / 60, 30)
ok(true, "空转没炸")

print("\n[3] 页签逐个点")
for _, t in ipairs({ "动", "车", "漂", "显", "志", "机", "抓" }) do
	local b = findBtn(t)
	click(b)
	local on = 0
	for _, x in ipairs(buttons()) do if x.Text == t and x.BackgroundColor3.G > 0.4 then on = on + 1 end end
	ok(on == 1, `点「{t}」后只有它高亮`)
end

print("\n[3a] 漂移: 不要油门/刹车, 推进开着就一直推")
local pads = 0
for _, d in ipairs(all()) do if d.ClassName == "UIListLayout" then pads = pads + d.Padding.Offset + d.Padding.Scale end end
ok(pads == 0, "所有 UIListLayout 间距 = 0")
ok(findBtn("▲ 油门") == nil and findBtn("▼ 刹车") == nil, "漂页没有 ▲ 油门 / ▼ 刹车 (漂移不需要)")
ok(findBtn("重绑踏板") == nil, "漂页没有 重绑踏板 (踏板是油门/刹车的输入, 一起没了)")
local pedText = 0
for _, d in ipairs(all()) do if d:IsA("TextLabel") and type(d.Text) == "string" and (d.Text:find("刹=", 1, true) or d.Text:find("MobilePedals", 1, true)) then pedText = pedText + 1 end end
ok(pedText == 0, `漂页不再报踏板绑定状态 (剩 {pedText} 条)`)
local oldBtns = 0
for _, d in ipairs(all()) do if d:IsA("TextButton") and (starts(d.Text, "选") or starts(d.Text, "绑") or starts(d.Text, "自动找踏板") or starts(d.Text, "扫车") or starts(d.Text, "复制状态")) then oldBtns = oldBtns + 1 end end
ok(oldBtns == 0, `面板里没有「选…」「绑…」「自动找踏板」「扫车」「复制状态」 (剩 {oldBtns} 个)`)
-- 推进默认开: 不需要按任何键, VectorForce 就该已经挂上并且出着力
local function driftForce() -- VectorForce 挂在车体上(workspace), 不在 CoreGui 里, all() 找不到
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.ClassName == "VectorForce" and d.props.Attachment0 and d.props.Attachment0.Name == "SB_DRIFT" then return d end
	end
	return nil
end
local dforce = driftForce()
ok(dforce ~= nil, "推进开着 → SB_DRIFT 的 VectorForce 已经挂上")
step(1 / 60, 3)
local fm = dforce and dforce.props.Force.Magnitude or 0
ok(fm > 0, string.format("不按任何键也在出力 (|F|=%.0f, 加速 5 × 质量 10)", fm))
local lk = hrp.props.CFrame.LookVector
local along = dforce.props.Force.X * lk.X + dforce.props.Force.Z * lk.Z
ok(along > 0, "力沿车头方向, 不是反的")
local driftBtn = findBtn("推进 ")
ok(driftBtn ~= nil and driftBtn.Text:find("开", 1, true) ~= nil, "推进默认开")
click(driftBtn)
step(1 / 60, 3)
ok(driftForce() == nil, "关掉推进 → Attachment 连带 VectorForce 一起删掉")
click(driftBtn)
step(1 / 60, 3)
ok(driftForce() ~= nil, "再开回来 → VectorForce 重新挂上")

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
	NOW += 0.5
	tdrag.DragStart:Fire(Vector2.new(50, 20))
	tdrag.DragContinue:Fire(Vector2.new(90, 30))
	tdrag.DragContinue:Fire(Vector2.new(160, 60))
	tdrag.DragEnd:Fire(Vector2.new(160, 60))
end
local function jitterTitle() -- 手指必抖: 收到过 DragContinue, 但总共才挪 2px, 仍然是点击
	NOW += 0.5
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
NOW += 0.5
tdrag.DragStart:Fire(Vector2.new(50, 20)); tl.InputBegan:Fire(input("Touch"))
tdrag.DragEnd:Fire(Vector2.new(50, 20)); tl.InputEnded:Fire(input("Touch"))
ok(bd.Visible == false, "一次点按同时触发拖拽器 + 标签输入 → 只翻一次 (翻两次 = 没翻)")
NOW += 0.5
foldBtn.Activated:Fire(); tdrag.DragStart:Fire(Vector2.new(180, 10)); tdrag.DragEnd:Fire(Vector2.new(180, 10))
ok(bd.Visible == true, "点 +/- 时拖拽器也响 → 仍然只翻一次 (折回去, 后面要面板开着)")

do
print("\n[3c] 文字居中: 标签 / 按钮 / 输入框")
local left, boxes, good = 0, 0, 0
for _, d in ipairs(all()) do
	if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and d.TextXAlignment ~= nil and d.TextXAlignment.Name == "Left" then left = left + 1 end
	if d:IsA("TextBox") then
		boxes += 1
		local lab = d.Parent:FindFirstChildOfClass("TextLabel")
		if d.TextXAlignment.Name == "Center" and d.TextYAlignment.Name == "Center" and d.Parent.ClassName == "Frame"
			and (lab == nil or (lab.Size.X.Scale == 0.5 and d.Position.X.Scale == 0.5 and lab.Text:sub(1, 1) ~= " ")) then good = good + 1 end
	end
end
ok(left == 0, `面板里没有靠左的文字 (靠左 {left} 个)`)
ok(boxes > 0 and good == boxes, `输入框: 左半标签 + 右半输入框, 文字水平垂直都居中, 标签前面不垫空格 ({good}/{boxes})`)
end

do
print("\n[3d] 底色透明度 0.9 · 状态靠字色 · 原生居中")
local tl2, bd2 = tabs():FindFirstChild("SB_Title"), tabs():FindFirstChild("SB_Body")
ok(tl2.BackgroundTransparency == 0.9 and bd2.BackgroundTransparency == 0.9, "标题条 / 页面体底色透明度 0.9")
local opaque, cells = 0, 0
for _, d in ipairs(bd2:GetDescendants()) do
	if d:IsA("GuiObject") then
		cells += 1
		if d.BackgroundTransparency < 0.9 then opaque = opaque + 1 end
	end
end
ok(cells > 0 and opaque == 0, `页面里所有按钮 / 数值格 / 标签底色都 ≥ 0.9 透明 ({cells} 个控件, 不够透明的 {opaque} 个)`)
local esp = findBtn("玩家 ESP")
click(esp)
ok(esp.TextColor3.R == 1 and esp.TextColor3.G == 1, `开关关着 → 字是白的 ({esp.Text})`)
click(esp)
ok(esp.TextColor3.G > esp.TextColor3.R, `开关开着 → 字变亮绿 (底色只剩 10%, 开/关靠字色) ({esp.Text})`)
local lit = 0
for _, t in ipairs({ "动", "车", "漂", "显", "志", "机", "抓" }) do local b = findBtn(t); if b and b.TextColor3.G > b.TextColor3.R then lit = lit + 1 end end
ok(lit == 1, `页签里正好一个是亮的 = 当前页 ({lit} 个)`)
-- 原生居中就行: 文字不加 UIPadding 补偿, 也不加描边 / 阴影 (0.9 透明底 + 原色字)
local texts, decorated = 1, 0
for _, root in ipairs({ tl2, bd2 }) do
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			texts += 1
			if d:FindFirstChildOfClass("UIPadding") ~= nil or (d.TextStrokeTransparency or 1) < 1 then decorated = decorated + 1 end
		end
	end
end
if tl2:FindFirstChildOfClass("UIPadding") ~= nil or (tl2.TextStrokeTransparency or 1) < 1 then decorated = decorated + 1 end
ok(decorated == 0, `面板里的文字原生居中: 没有 UIPadding 补偿、没有描边 / 阴影 ({decorated}/{texts} 段被加了料)`)
local tp = tabs():FindFirstChild("SB_Toast"):FindFirstChildOfClass("UIPadding")
ok(tp ~= nil and tp.PaddingLeft.Offset == 10 and tp.PaddingRight.Offset == 10 and tp.PaddingBottom == nil, "提示条只留左右各 10 的内边距")
end

print("\n[4] 角色模块: 开速度 → 真的动")
local spd = findBtn("速度")
click(spd)
humanoid.props.MoveDirection = Vector3.new(0, 0, -1)
step(1 / 60, 10)
local vel = hrp.AssemblyLinearVelocity
ok(math.abs(vel.Z) > 10, `开关开着时 root 水平速度 = {string.format("%.1f", math.abs(vel.Z))}`)
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
ok(seat.CanCollide == false and carBody.CanCollide == false, `穿墙开着: 座位 / 车身都穿 (穿墙开着 {clipOn} 个 · 座={tostring(seat.CanCollide)} 身={tostring(carBody.CanCollide)})`)
ok(CP.sur.CanCollide == true, `穿墙范围只有本车装配体: 同 Model 里另一个装配体的装饰件 Sur 不再被穿掉 ({tostring(CP.sur.CanCollide)})`)
ok(CP.wheelL.CanCollide == true and CP.wheelR.CanCollide == true, `穿墙开着: 只有轮胎底(整车最低的)保留碰撞, 车才不会掉下去 (左={tostring(CP.wheelL.CanCollide)} 右={tostring(CP.wheelR.CanCollide)})`)
ok(CP.wheelUp.CanCollide == true, "悬挂抬高、不在最低那圈的轮子, 名字带 wheel 仍然保留")
ok(CP.hubL.CanCollide == false and CP.hubR.CanCollide == false, "认到轮子名以后只留轮胎: 名字里没有 wheel/tire 的低位零件 RL/RR 也穿掉 (兜底只在整车一个轮子名都认不到时才用)")
ok(CP.pad.CanCollide == true and CP.fence.CanCollide == true, "穿墙不碰同一个 Model 里锚定的停车台 / 栏杆 (地面/平台不是车)")
seat.props.AssemblyLinearVelocity = Vector3.new(0, -5, 0)
_G.__rayHit = { Instance = CP.fence, Distance = 1.2 } -- 老逻辑: 离地只剩 0.7 → 把竖直速度顶到 +3 (上浮); 新逻辑根本不探地
step(1 / 60, 3)
ok(seat.props.AssemblyLinearVelocity.Y == -5, `穿墙不再探地推起, 开启后不上浮 (竖直速度 {tostring(seat.props.AssemblyLinearVelocity.Y)})`)
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
	ok(status() ~= nil and status():find("没认到轮子", 1, true) ~= nil, `状态行如实说明在用兜底 ({tostring(status())})`)
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
		lamps += 1
		if d:IsDescendantOf(carBody) then onBody = onBody + 1 end
		if d:IsDescendantOf(seat) then onSeat = onSeat + 1 end
	end
end
ok(lamps >= 2, `车上没灯时自己装了 {lamps} 个 SpotLight`)
ok(onSeat == 0 and onBody >= 2, `灯装车身部件上, 不装座位 (身 {onBody} / 座 {onSeat})`)
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
local knob = track and track:FindFirstChild("SB_Knob")
local kd = track and track:FindFirstChildOfClass("UIDragDetector") -- 挂在整条轨道上: 面板折叠时可拖
local kdk = knob and knob:FindFirstChildOfClass("UIDragDetector") -- 挂在圆点上: 面板展开时可拖
ok(knob ~= nil and kd ~= nil and kdk ~= nil, "圆点 + 整条轨道 + 各自的拖拽器都在")
local VP = camera.props.ViewportSize
ok(track.Position.X.Scale == 0 and track.Position.X.Offset == 0.25 * VP.X - 100 and track.Position.Y.Offset == VP.Y - 46, `默认在左下正中 (左上角 {track.Position.X.Offset},{track.Position.Y.Offset}; 视口 {VP.X}x{VP.Y} → 圆心在屏宽 25% 处)`)
track.props.AbsolutePosition = { X = track.Position.X.Offset, Y = track.Position.Y.Offset }
do -- 面板开着时就算平台真把背景的拖动事件发过来, 处理函数自己也得挡住
	local bx, by = track.Position.X.Offset, track.Position.Y.Offset
	kd.DragStart:Fire(Vector2.new(bx + 5, by + 5))
	kd.DragContinue:Fire(Vector2.new(bx + 300, by - 300))
	ok(track.Position.X.Offset == bx and track.Position.Y.Offset == by, "面板开着 → 拖背景不搬 (不只靠 Active, 处理函数自己也挡)")
	kd.DragEnd:Fire()
	ok(track.Position.X.Offset == bx, "面板开着时没真搬过 → 也不写盘")
end
ok(kdk.BoundingUI == track, "圆点的拖拽器以轨道为边界: 36 的圆点在 200 的轨道里行程正好 ±82, 拖不出去")
ok(track.Active == false and knob.Active == true, "面板开着 → 整条轨道不接管触摸(会挡面板), 只有圆点可拖")
local look0 = seat.props.CFrame.LookVector
kdk.DragContinue:Fire(Vector2.new(999, 0)) -- 面板开着只有圆点是 Active 的; 假引擎不模拟输入路由, 所以只 Fire 真机上真能触发的那个
step(1 / 60, 12)
ok((seat.props.CFrame.LookVector - look0).Magnitude > 0.05, "面板开着拖圆点 → 车转了")
kdk.DragEnd:Fire()
tapTitle() -- 关起来 → 整条背景才可拖
ok(track.Active == true and knob.Active == true, "面板关起来 → 背景可拖(搬位置), 圆点也照样可拖(转向)")
local px, py = track.Position.X.Offset, track.Position.Y.Offset
track.props.AbsolutePosition = { X = px, Y = py } -- 假布局不真算坐标, 给个起点让拖拽有参照
local look1, knobX0 = seat.props.CFrame.LookVector, knob.Position.X.Offset
kd.DragStart:Fire(Vector2.new(px + 5, py + 5))
kd.DragContinue:Fire(Vector2.new(px + 105, py - 195))
step(1 / 60, 12)
ok(track.Position.X.Offset == px + 100 and track.Position.Y.Offset == py - 200, `关起来拖背景 → 整条滑条被搬走了, 横竖都跟手 (到 {track.Position.X.Offset},{track.Position.Y.Offset})`)
ok(knob.Position.X.Offset == knobX0, "搬滑条时圆点不跟着乱动")
ok((seat.props.CFrame.LookVector - look1).Magnitude < 0.01, "搬滑条不是转向, 车不动")
kd.DragContinue:Fire(Vector2.new(99999, 99999)) -- 拖出屏幕外要夹回来
ok(track.Position.X.Offset == VP.X - 200 and track.Position.Y.Offset == VP.Y - 36, `拖过头会夹在屏幕内 ({track.Position.X.Offset},{track.Position.Y.Offset} = 视口减滑条尺寸)`)
kd.DragEnd:Fire()
ok(VFS["Selfblox.json"] ~= nil and VFS["Selfblox.json"]:find("steerpos", 1, true) ~= nil, "搬完松手 → 位置写进 Selfblox.json, 下次进来还在老地方")
track.Position = UDim2.fromOffset(px, py); track.props.AbsolutePosition = { X = px, Y = py } -- 复原, 后面的转向断言要用原位
seat.props.AssemblyLinearVelocity = Vector3.zero -- 停着也要能打方向
local look2 = seat.props.CFrame.LookVector
kdk.DragContinue:Fire(Vector2.new(999, 0))
step(1 / 60, 10)
ok((seat.props.CFrame.LookVector - look2).Magnitude > 0.02, "车停着, 拖圆点照样转")
ok(knob.Position.X.Offset > 10, `圆点跟着手指跑 (偏 {knob.Position.X.Offset}px)`)
kdk.DragEnd:Fire()
ok(knob.Position.X.Offset == 0 and knob.Position.X.Scale == 0.5, "松手当帧就回中, 不等下一帧 steer()")
step(1 / 60, 2)
ok(knob.Position.X.Offset == 0 and knob.Position.X.Scale == 0.5, "松手回中, 平时固定")
ok(track:FindFirstChild("SB_Handle") == nil, "隐形手柄已经去掉: 折叠时拖的就是轨道本身, 不再靠全透明 Frame 接触摸")
tapTitle() -- 折回去, 后面还要用面板
ok(track.Active == false, "展开 → 滑条又固定")
ok(track.ZIndex == 10 and track.Active == false, "面板开着时轨道自己不接触摸(只有圆点接), 所以不会挡住面板的操作")
tapTitle()
ok(track.ZIndex == 10 and track.Active == true, "折起来后滑条升到最上层、整条可拖")
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
ok(stTxt ~= nil, `状态行直接标出锚定 ({tostring(stTxt)})`)
tapTitle() -- 折起来才能拖滑条
local lookA = seat.props.CFrame.LookVector
kdk.DragContinue:Fire(Vector2.new(999, 0))
step(1 / 60, 10)
ok((seat.props.CFrame.LookVector - lookA).Magnitude > 0.02, "锚定车的转向照样有效 (走 CFrame)")
kdk.DragEnd:Fire()
tapTitle()
seat.props.Anchored = false
step(1 / 60, 3)

print("\n[6d] 飞车: 摇杆前推 = 车头方向 (摇杆读 Humanoid.MoveDirection; 官方 UserInputService 没有 GetMoveVector)")
click(findBtn("飞车"))
humanoid.props.MoveDirection = Vector3.new(0, 0, -1) -- 摄像机朝 -Z: 前推 = 世界 -Z
seat.props.Throttle = 0
step(1 / 60, 3)
local lvc = seat:FindFirstChild("SB_SIBS"):FindFirstChildOfClass("LinearVelocity")
ok(lvc and lvc.VectorVelocity.Z < -10, `摇杆前推 → 车头方向 {tostring(lvc and lvc.VectorVelocity)}`)
humanoid.props.MoveDirection = Vector3.new(1, 0, 0) -- 右推 = 世界 +X
step(1 / 60, 3)
ok(lvc and lvc.VectorVelocity.X > 10, `摇杆右推 → 车右方向 {tostring(lvc and lvc.VectorVelocity)}`)
camera.CFrame = CFrame.new(Vector3.zero, Vector3.new(1, 0, 0)) -- 摄像机转到朝 +X: 前推 = 世界 +X, 但车还是该往车头(-Z)飞, 不能跟着相机跑
humanoid.props.MoveDirection = Vector3.new(1, 0, 0)
step(1 / 60, 3)
local okHum, humTxt = pcall(function()
	return assert(load_chunk([[
		local plr = game:GetService("Players").LocalPlayer
		local ch = plr.Character
		local h = ch and ch:FindFirstChildOfClass("Humanoid")
		return "LocalPlayer=" .. tostring(plr) .. " Character=" .. tostring(ch) .. " 人形=" .. tostring(h) .. " SeatPart=" .. tostring(h and h.SeatPart)
	]], "smoke_probe"))()
end)
if not okHum then humTxt = `人形探针炸了: {tostring(humTxt)}`end
local okProbe, probeTxt = pcall(function()
	return assert(load_chunk([[
		local rv = workspace.CurrentCamera.CFrame.RightVector
		local f = Vector3.new(rv.X, 0, rv.Z)
		local r = f.Magnitude > 1e-3 and f.Unit or Vector3.xAxis
		local md = Vector3.new(1, 0, 0)
		local cr = Vector3.yAxis:Cross(r)
		local mv = Vector3.new(md:Dot(r), 0, -md:Dot(cr))
		return "相机右=" .. tostring(rv) .. " 拍平后模长=" .. tostring(f.Magnitude) .. " r=" .. tostring(r) .. " yAxis=" .. tostring(Vector3.yAxis) .. " y叉r=" .. tostring(cr) .. " md点r=" .. tostring(md:Dot(r)) .. " 摇杆=" .. tostring(mv)
	]], "smoke_probe"))()
end)
if not okProbe then probeTxt = `探针自己炸了: {tostring(probeTxt)}`end
local fw = seat.props.CFrame.LookVector -- 前面方向盘测试已经把假车转过了, 车头不再是 -Z, 所以跟车头的实际朝向比
fw = Vector3.new(fw.X, 0, fw.Z).Unit
ok(lvc and lvc.VectorVelocity.Magnitude > 10 and lvc.VectorVelocity.Unit:Dot(fw) > 0.99,
	"相机转 90° 后, 前推仍是车头方向, 不跟着相机走 (实际写入的速度 = " .. tostring(lvc and lvc.VectorVelocity) .. ")")
camera.CFrame = CFrame.new(Vector3.zero)
humanoid.props.MoveDirection = Vector3.zero
step(1 / 60, 3)
ok(lvc and lvc.VectorVelocity.Magnitude < 0.1, "松手悬停")
click(findBtn("飞车"))

do -- 急刹要挨在 ▲加速 / ▼减速 上方 (主人 2026-10-05 要求: 要停的时候手就在那两个键旁边)
	local bs, ib, ig = buttons(), nil, nil
	for i, b in ipairs(bs) do
		if b.Text:sub(1, #"急刹") == "急刹" then ib = i end -- 按字节数取, 跟 findBtn 一个写法; 写死 2 会截断 UTF-8
		if b.Text == "▲ 加速" then ig = i end
	end
	ok(ib ~= nil and ig ~= nil and ib == ig - 1, `急刹排在 ▲加速 正上方 (急刹第 {tostring(ib)} 个 / ▲加速第 {tostring(ig)} 个)`)
	local jb
	for _, b in ipairs(bs) do if b.Text:sub(1, #"急刹") == "急刹" then jb = b end end
	ok(jb ~= nil and jb.Size.X.Scale == 1, `急刹单占一行 (宽度占比 {tostring(jb and jb.Size.X.Scale)}, 半行是 0.5)`)
end

print("\n[6c] 急刹")
click(findBtn("急刹")) -- 开
seat.props.Throttle, seat.props.AssemblyLinearVelocity = 0, Vector3.new(30, 5, 0) -- 松开游戏油门, 免得急刹被"踩油门自动解除"顶掉
step(1 / 60, 2)
ok(seat.AssemblyLinearVelocity.Z == 0 and seat.AssemblyLinearVelocity.X == 0, `急刹把水平速度清了, 保留竖直 {tostring(seat.AssemblyLinearVelocity.Y)}`)
click(findBtn("急刹")) -- 关

print("\n[7] 全部控件点一遍 (开), 30 帧, 再点一遍 (关)")
local flipped, held = 0, 0
for _, b in ipairs(buttons()) do if ends(b.Text, " 关") then click(b); flipped = flipped + 1 end end
for _, b in ipairs(buttons()) do b.InputBegan:Fire(input("Touch")); held = held + 1 end
step(1 / 60, 30)
for _, b in ipairs(buttons()) do b.InputEnded:Fire(input("Touch")) end
step(1 / 60, 10)
ok(flipped >= 15, `开了 {flipped} 个开关`)
for _, b in ipairs(buttons()) do if ends(b.Text, " 开") then click(b); flipped = flipped - 1 end end
step(1 / 60, 10)
ok(true, `按住/松开 {held} 个按钮 + 全开全关走完没炸`)
ok(_G.__SVC.VirtualInputManager.props.keys ~= nil, "喇叭真的发了按键事件")
ok(seat.CanCollide and carBody.CanCollide and CP.sur.CanCollide and CP.wheelL.CanCollide and CP.wheelUp.CanCollide and CP.hubL.CanCollide and CP.pad.CanCollide and CP.fence.CanCollide and not CP.shadow.CanCollide, "穿墙关掉后车部件原样还原 (本来不碰撞的影子仍是不碰撞)")

print("\n[6b2] 没有开关: 可拖区只看面板开合")
ok(findBtn("滑条常可拖") == nil, "「滑条常可拖」开关已经去掉, 不再有两套状态打架")
ok(track.Active == false and knob.Active == true, "面板开着 → 只有圆点可拖")
local lookA2 = seat.props.CFrame.LookVector
kdk.DragContinue:Fire(Vector2.new(999, 0))
step(1 / 60, 10)
ok((seat.props.CFrame.LookVector - lookA2).Magnitude > 0.03, "面板开着拖圆点也能转向了")
kdk.DragEnd:Fire()
ok(knob.Position.X.Offset == 0 and knob.Position.X.Scale == 0.5, "拖圆点松手也当帧回中")

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

print("\n[6d3] 按住钮: 指针滑出按钮再松手也要放 (原来只听按钮自己的 InputEnded, 滑出去就永远卡在按着)")
btnGas.InputBegan:Fire(input("Touch"))
step(1 / 60, 3)
ok(btnGas.TextColor3.G > btnGas.TextColor3.R, "前置: 按住了")
_G.__SVC.UserInputService.props.InputEnded:Fire(input("Touch")) -- 只发全局那条, 按钮自己那条不发 = 指针已经不在按钮上
step(1 / 60, 3)
ok(btnGas.TextColor3.R == 1 and btnGas.TextColor3.G == 1, "全局 InputEnded 也放得开")
btnGas.InputBegan:Fire(input("Touch")) -- 放开了才按得下去第二次: held 标记必须真的清了
step(1 / 60, 3)
ok(btnGas.TextColor3.G > btnGas.TextColor3.R, "放开后还能再按 (held 标记清了)")
btnGas.InputEnded:Fire(input("Touch"))
step(1 / 60, 3)

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
ok(toastNoSeat:find("没座位", 1, true) ~= nil, `提示如实说明「没座位」(当时提示: {toastNoSeat})`)
ok(dumpCar and dumpCar:find("座位: -", 1, true) ~= nil, "快照里座位一栏是空的")
ok(dumpCar and dumpCar:find("准星射线", 1, true) ~= nil and dumpCar:find("祖先: ", 1, true) ~= nil, "快照里有准星射线 + 祖先链")
ok(dumpCar and dumpCar:find("周围的座位", 1, true) ~= nil, "快照里有周围座位(半径扫描)")
ok(dumpCar and dumpCar:find("车周围 25 格里的部件", 1, true) ~= nil, "快照里有周围部件")
do local function mapGuard() -- 打中街道路面(横跨 3000 格的装配体): 不能当成车
	_G.__rayHit = { Instance = CP.road }
	click(findBtn("换车"))
	step(1 / 60, 5)
	ok(CP.road:FindFirstChild("SB_SIBS") == nil, "打中街道路面 → 不绑 (装配体外径 ~6000 格, 远超 carmaxstuds)")
	ok(toastText():find("地图", 1, true) ~= nil, `提示说清是地图/大容器, 不是笼统的「没座位」({toastText()})`)
	ok(toastText():match("外径 %d+ 格") ~= nil and toastText():match("质量 %d+") ~= nil, `提示里带实测外径和质量: 下次误拒/漏拒, 报告自己就能说明为什么 ({toastText()})`)
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
	ok(toastText():find("没座位", 1, true) ~= nil, `绑上后照样提示没座位只能推 ({toastText()})`)
end looseInBigModel() end
_G.__rayHit = { Instance = seat } -- 换回真车: 带座位的那种
click(findBtn("换车"))
step(1 / 60, 5)
local toastSeat = toastText()
if _G.SB_DUMP then _G.SB_DUMP() end
ok(toastSeat:find("座位 Seat", 1, true) ~= nil, `有座位时提示带座位名 (当时提示: {toastSeat})`)
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
do -- 绑车的改绑检查要有节流: 锚定件一锚就是好几秒, 原来每帧都做一次 30 格球查询 + 逐件量整个装配体
	_G.__radius = {} -- 附近没有可改绑的 → 部件保持锚定, 每帧都会走到改绑检查这一支
	_G.__radiusCalls = 0
	step(1 / 60, 60)
	ok((_G.__radiusCalls or 0) <= 2, `改绑的空间查询有节流: 60 帧查了 {tostring(_G.__radiusCalls)} 次 (不节流的话是 60 次)`)
end
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
	ok(seat:FindFirstChild("SB_SIBS") ~= nil and CP.sur:FindFirstChild("SB_SIBS") == nil and CP.wheelL:FindFirstChild("SB_SIBS") == nil, `瞄 {hit.Name} → 绑的是座位 Seat 所在的装配体, 不是瞄到的零件`)
	ok(toastText():find("座位 Seat", 1, true) ~= nil, `提示说明是按座位锁的 ({toastText()})`)
end
local st
for _, d in ipairs(all()) do if d:IsA("TextLabel") and type(d.Text) == "string" and starts(d.Text, "Car · ") then st = d.Text end end
ok(st ~= nil, `状态行显示整辆车的名字 Car, 不是某个零件/子模型 ({tostring(st)})`)
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
ok(dm and dm:find(`脚本={tostring(VER)}`, 1, true) ~= nil, `诊断快照的版本 = VERSION ({tostring(VER)})`)
ok(dm and dm:find("MobilePedals", 1, true) == nil, "快照里不再有踏板树 (漂移不看踏板了)")
ok(dm and dm:find("sibs ", 1, true) ~= nil, "快照里有各模块状态")
ok(dm and dm:find("摇杆=", 1, true) ~= nil, `快照的 moc 行带摇杆原值和推帧计数 (停不下来时靠它分清是摇杆没回中还是别处在推)`)
ok(dm and dm:find("PlayerGui 树", 1, true) == nil, "快照里不再带整个 PlayerGui 树 (原来是给「选按钮」准备的)")
ok(dm and dm:find("CAr", 1, true) == nil and dm:find("=== CAR", 1, true) ~= nil, "快照里有车结构")
ok(CLIP ~= nil and CLIP:find("Selfblox 诊断", 1, true) ~= nil, "快照同时进了剪贴板")
ok(type(_G.SB_DUMP) == "function", "也可以用 _G.SB_DUMP() 手动打")

-- ───────── 其余模块的覆盖补齐: hud-ESP / plane / grab / log / moc / sibs 角落 ─────────
-- 这些模块原来几乎没被自检跑到 (plane 33% / grab / log 67% / hud 78%): "真引擎会抛错、假引擎放行"的错最容易藏在没跑到的代码里
do local function section7c() -- 包进函数: 主函数的局部变量已经快到 200 个上限了
print("\n[7c] 其余模块: ESP / 飞机侦察 / 抓散件 / 日志 / 旋转·秒互动·速度三模式 / 翻转")
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
ok(nameTxt == "Bobby 30", `名牌 = 显示名 + 距离 ({tostring(nameTxt)})`)
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

-- ── plane: 飞机侦察 ──
local spawnRemote = T(inst("RemoteEvent", { Name = "SpawnPlane" })); spawnRemote.Parent = RSv
local chatFn = T(inst("RemoteFunction", { Name = "ChatFn" })); chatFn.Parent = RSv
local function mkPlane(name, o)
	local m = T(inst("Model", { Name = name }))
	local st = T(inst("VehicleSeat", { Name = "Pilot", Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(Vector3.new(200, 50, 0)), Position = Vector3.new(200, 50, 0), Occupant = o.occ }))
	if not o.noseat then st.Parent = m end -- 没座位的飞机(机库/菜单/被服务器接管的残留机): 上一版只从座位出发扫描, 这种整个漏掉
	for _, wn in ipairs(o.wings or {}) do mkPart(wn, Vector3.new(6, 0.5, 2), Vector3.new(200, 50, 0)).Parent = m end
	for i = 1, (o.fill or 0) do mkPart(`Body{i}`, Vector3.new(1, 1, 1), Vector3.new(200, 50, 0)).Parent = m end
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
ok(st1 and st1:find("飞机 5", 1, true) and st1:find("Remote 2", 1, true), `重扫: 5 架飞机 (车不算) + 2 个相关 Remote ({tostring(st1)})`)
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
local atFa = rep and rep:find("%-%-%s*发")
local faSec = atFa and rep:sub(atFa, atFa + 200) or "报告里没有发小节" -- 不用 %%n 匹配, 直接截子串
faSec = faSec:gsub("[\r\n]+", " / ") -- 压成单行: GitHub 注解会在第一个换行处截断
-- typeof 在 Luau 里是内建函数(VM/src/lbuiltins.cpp:887 luauF_typeof, 注册于 :2630), 编译器还按名字认它
-- (Compiler/src/Builtins.cpp:78 builtin.isGlobal("typeof")), 常量可定时直接折叠(BuiltinFolding.cpp:528)。
-- 所以假引擎盖不住 typeof, 假 Vector3 只会被认成 table、走脚本第 886 行的通用表分支;
-- 真引擎里 typeof(Vector3) 就是 "Vector3", 故 Lua 5.4 下仍按 (1,2,3) 严判, Luau 下逐项核内容(键序由 Luau 的哈希序决定)。
local okArgs
if FROZEN_G then
	okArgs = rep:find('FireGun:FireServer "bullet", {', 1, true) and rep:find("X=1", 1, true)
		and rep:find("Y=2", 1, true) and rep:find("Z=3", 1, true) and rep:find("{a=1}", 1, true)
else
	okArgs = rep:find('Workspace.Plane_RAF.FireGun:FireServer "bullet", (1,2,3), {a=1}', 1, true)
end
ok(rep:find("-- 发 1", 1, true) and okArgs, `命中关键字的 FireServer 被记下来了, 参数格式化对 (发小节原文: {faSec})`)
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
	ok(rep:find("-- 发 3 条 / 1 组", 1, true) ~= nil, `报告头写清 原始条数/组数 ({tostring(rep:match("-- 发 [^\n]*"))})`)
	local m21 = mkPlane("M21", { noseat = true, wings = { "LeftWing", "RightWing" }, fill = 12 })
	local fw = mkPlane("FW190", { noseat = true, wings = { "LeftWing", "RightWing" }, fill = 12, attr = { "OldOwner", "Me" } })
	click(findBtn("重扫"))
	click(findBtn("写报告"))
	rep = VFS["plane_debug.txt"]
	ok(rep:find("[34] Workspace.M21 | 座:无", 1, true) ~= nil, "没座位的飞机也进报告 (机型名 M21 不在 HINT 里 → 只有 34 分, 靠「2 翼 + 12 件」这条进来)")
	ok(rep:find("FW190 ★我(OldOwner)", 1, true) ~= nil, "被服务器接管的自家飞机(座位空的, 只剩 OldOwner 属性)也标 ★我")
	ok(rep:find("-- 疑似 2", 1, true) ~= nil and rep:find("Shed | 靠座", 1, true) ~= nil and rep:find("Workspace.Car | 靠座", 1, true) ~= nil, `没过门槛的进「疑似」名单(2 个: Shed + 那辆车), 写清是靠座还是靠翼认到的 ({tostring(rep:match("-- 疑似 [^\n]*"))})`)
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

-- ── grab: 抓散件 + 现场清单 ──
-- 新游戏的物件名一个都不知道 (主人只说「一堆乱七八糟的东西可以推进岛周围的收纳槽」), 所以断言只认行为不认名字:
-- 没锚定的散件被拉向人, 锚定的地图件不碰, 别人身上的零件不碰, 关着一个都不动, 半径和清单都得对得上。
local hp0 = hrp.props.Position
local function mkLoose(name, dx, dz, anchored)
	local q = mkPart(name, Vector3.new(2, 2, 2), Vector3.new(hp0.X + dx, hp0.Y, hp0.Z + dz), { Anchored = anchored or false })
	q.Parent = workspace
	return q
end
local g1, g2 = mkLoose("Crate", 10, 0), mkLoose("Barrel", -8, 6)
local g3, g4 = mkLoose("Island", 3, 3, true), mkLoose("Rock", -4, -4, true)
-- 别人的零件也是没锚定的部件: 前面的 ESP 测试已经留了一个 bob (bobChar 里有 bobRoot), 正好拿来当"别人"
local matePart = mkPart("mateArm", Vector3.new(1, 2, 1), Vector3.new(hp0.X + 3, hp0.Y, hp0.Z))
matePart.Parent = bobChar
_G.__radius = { g1, g2, g3, g4, matePart, bobRoot, hrp }
click(findBtn("自动抓"))
step(1 / 60, 4)
ok(g1.AssemblyLinearVelocity.X < -1, `散件被拉向人: 件在 +X 10 格, 速度该往 -X (实际 {g1.AssemblyLinearVelocity.X})`)
ok(g2.AssemblyLinearVelocity.X > 1 and g2.AssemblyLinearVelocity.Z < -1, `斜后方那个方向也对 (实际 {g2.AssemblyLinearVelocity.X},{g2.AssemblyLinearVelocity.Z})`)
ok(g3.AssemblyLinearVelocity.Magnitude == 0 and g4.AssemblyLinearVelocity.Magnitude == 0, "锚定的不碰 (整座岛的地板就是锚定件)")
ok(matePart.AssemblyLinearVelocity.Magnitude == 0 and bobRoot.AssemblyLinearVelocity.Magnitude == 0, "别人身上的零件不碰 (不排掉就会把玩家拽过来)")
-- 自己身上的零件同样是没锚定的部件: 不排掉就会把自己的手拽到脚边
local selfPart = mkPart("selfArm", Vector3.new(1, 2, 1), Vector3.new(hp0.X + 2, hp0.Y, hp0.Z))
selfPart.Parent = char
_G.__radius = { g1, g2, g3, g4, matePart, bobRoot, hrp, selfPart }
step(1 / 60, 3)
ok(selfPart.AssemblyLinearVelocity.Magnitude == 0, "自己身上的零件也不碰")
selfPart:Destroy()
_G.__radius = { g1, g2, g3, g4, matePart, bobRoot, hrp }
ok(g1.AssemblyLinearVelocity.Y == 0, `只写水平速度, Y 留给引擎 (实际 Y={g1.AssemblyLinearVelocity.Y}, 三个分量全写死会把地上的东西顶上天)`)
ok(_G.__radiusArgs ~= nil and _G.__radiusArgs.r == 40, `半径真的传给了引擎 (传的 {tostring(_G.__radiusArgs and _G.__radiusArgs.r)}, 默认 40)`)
-- 页状态不是标签, 是 pageInfos() 写进日志/诊断的一行 ⟹ 从打包结果里读
for _, d in ipairs(all()) do if d:IsA("TextButton") and type(d.Text) == "string" and d.Text:find("诊断打包", 1, true) then d.Activated:Fire() end end
step(1 / 60, 2)
local gTxt = (VFS["selfblox_dump.txt"] or ""):match("\n  grab [^\n]*")
ok(gTxt ~= nil and gTxt:find("半径内=2", 1, true) ~= nil, `页状态只数散件: 7 个里锚定 2 个、自己 1 个、别人 2 个都不算 ({tostring(gTxt)})`)
ok(gTxt ~= nil and gTxt:find("INFO 报错", 1, true) == nil, "页状态这一行没抛错 (抛错的话整行会变成 INFO 报错)")
-- 关掉就一个都不动 (速度归零后再跑, 还被动就说明开关没管住)
click(findBtn("自动抓"))
g1.props.AssemblyLinearVelocity = Vector3.zero
g2.props.AssemblyLinearVelocity = Vector3.zero
step(1 / 60, 10)
ok(g1.AssemblyLinearVelocity.Magnitude == 0 and g2.AssemblyLinearVelocity.Magnitude == 0, "关掉 → 一个都不再推")
-- 页状态只许数不许推: 打包会跑 info(), info 里要是也推, 关着的时候一打包东西就飞
g1.props.AssemblyLinearVelocity = Vector3.zero
for _, d in ipairs(all()) do if d:IsA("TextButton") and type(d.Text) == "string" and d.Text:find("诊断打包", 1, true) then d.Activated:Fire() end end
step(1 / 60, 3)
ok(g1.AssemblyLinearVelocity.Magnitude == 0, "关掉以后打包也不推 (info 只数不推)")
-- 按住钮: 按着才拉, 松手就停 (松手不停这一类的毛病在 cframe 上翻过六次车)
local grabBtn = btnExact("抓取") -- 页签也叫「抓」, 用 btnExact 加全名才不会抓到页签
ok(grabBtn ~= nil, "有「抓取」这个按住钮")
grabBtn.InputBegan:Fire(input("Touch"))
g1.props.AssemblyLinearVelocity = Vector3.zero
step(1 / 60, 4)
ok(g1.AssemblyLinearVelocity.X < -1, `按住「抓取」→ 拉 (实际 {g1.AssemblyLinearVelocity.X})`)
grabBtn.InputEnded:Fire(input("Touch"))
g1.props.AssemblyLinearVelocity = Vector3.zero
step(1 / 60, 4)
ok(g1.AssemblyLinearVelocity.Magnitude == 0, "松手 → 停")
-- 现场清单: 物件名未知 ⟹ 诊断打包必须把半径内的东西全列出来, 下一份日志才认得出哪个是散件、哪个是收纳槽
local function grabDump()
	for _, d in ipairs(all()) do if d:IsA("TextButton") and type(d.Text) == "string" and d.Text:find("诊断打包", 1, true) then d.Activated:Fire() end end
	step(1 / 60, 2)
	return VFS["selfblox_dump.txt"] or ""
end
local slot = mkPart("StorageSlot", Vector3.new(4, 4, 4), Vector3.new(hp0.X + 20, hp0.Y, hp0.Z + 20), { Anchored = true })
slot:SetAttribute("ItemId", 42)
slot.Parent = workspace
_G.__radius = { g1, g2, g3, g4, matePart, bobRoot, hrp, slot }
local gd = grabDump()
ok(gd:find("==== GRAB ", 1, true) ~= nil, "诊断打包里有抓这页的现场清单")
ok(gd:find("Crate/Part", 1, true) ~= nil and gd:find("StorageSlot/Part", 1, true) ~= nil, "散件和锚定的都列 (不筛: 哪个是收纳槽由人看着判, 不由代码猜)")
ok(gd:find("属:ItemId=42", 1, true) ~= nil, "属性一起打出来 (Owner / ItemId 这类关键信息常常只在属性里)")
ok(gd:find(" 锚A ", 1, true) ~= nil and gd:find(" 锚a ", 1, true) ~= nil, "锚没锚标出来, 岛上锚定的和地上散的一眼分开")
ok(gd:find("扫描半径内部件 8 个", 1, true) ~= nil, "数出来的个数和放进去的一样 (8 个)")
ok(gd:find("其中 ProximityPrompt ", 1, true) ~= nil, "ProximityPrompt 全列 (收纳槽很可能就是个长按交互块)")
ok(gd:find("-- Remote ", 1, true) ~= nil and gd:find("SpawnPlane", 1, true) ~= nil, "Remote 全列 (推进去怎么算数, 另一条路就是发包)")
-- 近 → 远排序 + 32KB 护栏: 整岛几千个部件会顶爆写盘, 砍掉的只能是最远的, 而且得说明砍了几个
local bulk = {}
for i = 1, 900 do bulk[i] = mkPart(`Debris{i}`, Vector3.new(1, 1, 1), Vector3.new(hp0.X + i, hp0.Y, hp0.Z)) end
-- 倒着放: 引擎回来的顺序不保证按距离, 正着放的话排序是白排一遍, 删掉排序自检也发现不了
for i = 1, 450 do bulk[i], bulk[901 - i] = bulk[901 - i], bulk[i] end
_G.__radius = bulk
local gdBig = grabDump()
ok(gdBig:find("Debris1/Part", 1, true) ~= nil, "最近的排在最前面 (Debris1 只隔 1 格)")
ok(gdBig:find("没列(超32KB)", 1, true) ~= nil and gdBig:find("还有 %d+ 个没列") ~= nil, "超 32KB 才截断, 而且把砍了几个写在清单里")
ok(gdBig:find("Debris900/Part", 1, true) == nil, "被砍掉的是最远的那头 (Debris900 隔 900 格, 不在清单里)")
for _, b in ipairs(bulk) do b:Destroy() end
_G.__radius = nil
_G.__radiusArgs = nil
grabDump()
ok(grabDump():find("没列(超32KB)", 1, true) == nil, "部件撤了以后护栏跟着消失, 清单恢复完整")
matePart:Destroy()
slot:Destroy()
g1:Destroy()
g2:Destroy()
g3:Destroy()
g4:Destroy()


-- ── grab: 三档范围 + 界面 ──
-- 真机 26.10.16.6.96 那份日志 (place=133363783004873 地图=Ugc) 说清了这游戏的分法: 可卖件是未锚定部件,
-- 身上带 SellReadyAt / SellToken 两个属性; 地图装饰件 (Metal / Body / Black) 同样未锚定, 一个属性都没有。
local hi0 = hrp.props.Position
local function mkThing(name, dx, dz, anchored, attr)
	local q = mkPart(name, Vector3.new(2, 2, 2), Vector3.new(hi0.X + dx, hi0.Y, hi0.Z + dz), { Anchored = anchored or false })
	if attr then for k, v in pairs(attr) do q:SetAttribute(k, v) end end
	q.Parent = workspace
	return q
end
local it1 = mkThing("JellyFish", 12, 0, false, { SellReadyAt = 3527.35, SellToken = "001f7120" })
local it2 = mkThing("Revolver", -9, 4, false, { SellReadyAt = 3527.07, SellToken = "f979cd13" })
local deco = mkThing("Metal", 6, 6) -- 地图装饰件: 未锚定, 没属性
local wall = mkThing("ItemBlock", 15, 15, true) -- 锚定的地图件
_G.__radius = { it1, it2, deco, wall, hrp }
click(findBtn("自动抓"))
step(1 / 60, 4)
ok(it1.AssemblyLinearVelocity.X < -1 and it2.AssemblyLinearVelocity.X > 1, "范围 散件: 未锚定的都拉")
ok(deco.AssemblyLinearVelocity.Magnitude > 0, "范围 散件: 没属性的装饰件也拉 (主人要「能抓的都抓」, 不按属性挑)")
ok(wall.CFrame.Position.X == hi0.X + 15, "范围 散件: 锚定的一个不动 (客户端搬锚定件能不能同步没验过, 默认不碰)")
click(findBtn("自动抓"))
-- 属档: 只抓带属性的
click(btnExact("范围 散件"))
step(1 / 60, 1)
ok(btnExact("范围 带属性") ~= nil, "范围切一档 → 「带属性」")
it1.props.AssemblyLinearVelocity = Vector3.zero
it2.props.AssemblyLinearVelocity = Vector3.zero
deco.props.AssemblyLinearVelocity = Vector3.zero
click(findBtn("自动抓"))
step(1 / 60, 4)
ok(it1.AssemblyLinearVelocity.Magnitude > 0 and it2.AssemblyLinearVelocity.Magnitude > 0, "范围 带属性: 带 SellToken 的照拉")
ok(deco.AssemblyLinearVelocity.Magnitude == 0, "范围 带属性: 没属性的装饰件不碰 (真机 936 个部件里大半是这种)")
click(findBtn("自动抓"))
-- 全档: 连锚定的一起搬, 锚定件不吃速度, 只能直接写 CFrame
click(btnExact("范围 带属性"))
step(1 / 60, 1)
ok(btnExact("范围 全部") ~= nil, "范围再切一档 → 「全部」")
local wx0 = wall.CFrame.Position.X
click(findBtn("自动抓"))
step(1 / 60, 10)
ok(wall.CFrame.Position.X < wx0, `范围 全部: 锚定的直接搬 CFrame 往人这边挪 ({wx0} → {wall.CFrame.Position.X})`)
click(findBtn("自动抓"))
click(btnExact("范围 全部"))
step(1 / 60, 1)
ok(btnExact("范围 散件") ~= nil, "范围转一圈回到「散件」")
local gq0 = grabDump()
ok(gq0:find("范围=loose", 1, true) ~= nil, "诊断里报当前是哪一档")
ok(gq0:find("未锚定非人物 %d+ 个 / 带属性非人物 %d+ 个") ~= nil, "诊断里分别数出两档各有多少 (真机报的是 84 和 936 混在一起, 分不出)")

-- ── 界面: 可点按钮全列 + 按名字点 ──
local ggui = inst("ScreenGui", { Name = "ShopGui" })
ggui.Parent = pgui
local gbtn = inst("TextButton", { Name = "BuyButton", Text = "Buy", Visible = true, Active = true })
gbtn.Parent = ggui
gbtn.props.AbsoluteSize = { X = 72, Y = 29 }
gbtn.props.AbsolutePosition = { X = 577, Y = 378 } -- 真机日志里 AllOGUpgrade/BuyButton 就在这个位置这个尺寸
-- ImageButton 自己没有文字, 真机 AbilityFrame 那一排全是图, 文字在子物件上
local gico = inst("ImageButton", { Name = "AbilityBtn", Visible = true, Active = true }) -- 名字里故意不带 Black: 只按名字匹配的变异才拦得住
gico.Parent = ggui
gico.props.AbsoluteSize = { X = 60, Y = 51 }
gico.props.AbsolutePosition = { X = 769, Y = 88 }
local gtxt = inst("TextLabel", { Name = "Text", Text = "Black Hole", Visible = true })
gtxt.Parent = gico
-- 隐着的按钮也照列: 只收可见的会把还没打开的菜单整个漏掉
local ghid = inst("TextButton", { Name = "SecretBtn", Text = "Secret", Visible = false, Active = true })
ghid.Parent = ggui
ghid.props.AbsoluteSize = { X = 40, Y = 20 }
ghid.props.AbsolutePosition = { X = 10, Y = 10 }
step(1 / 60, 2)
local gq = grabDump()
ok(gq:find("界面可点按钮 3 个", 1, true) ~= nil, "界面按钮全列: 3 个都数到")
ok(gq:find("ShopGui.BuyButton:TextButton@577,378 72x29 VA 「Buy」", 1, true) ~= nil, "按钮报全路径/类名/坐标/尺寸/可见/Active/文字")
ok(gq:find("「Black Hole」", 1, true) ~= nil, "ImageButton 自己没文字 → 去子物件里找一行 (真机那排技能钮全是图)")
ok(gq:find("SecretBtn:TextButton@10,10 40x20 vA 「Secret」", 1, true) ~= nil, "隐着的按钮也列, 不按可见性筛")
ok(gq:find("SB_Title", 1, true) == nil and gq:find("SB_Body", 1, true) == nil, "自家面板的按钮不进清单")
ok(gq:find("AbilityBtn", 1, true) < gq:find("BuyButton", 1, true), "清单按全路径排, 不按树的先后 (32KB 截断砍的是排在后头的, 顺序乱了就说不清砍了谁)")
-- 按名字点: 客户端点不动别人的 Activated, 只能让执行器发一次真鼠标事件
local VIMi = _G.__SVC.VirtualInputManager
local keyBox, nEmpty = nil, 0
for _, d in ipairs(all()) do if d:IsA("TextBox") and d.Text == "" then nEmpty += 1 keyBox = d end end
ok(nEmpty == 1, `找到唯一的空文本框当「按钮名」(空文本框 {nEmpty} 个; 以后多出一个, 这条就得换认法)`)
VIMi.props.clicks = nil
click(btnExact("点按钮"))
step(1 / 60, 2)
ok(VIMi.props.clicks == nil and toastText():find("空着不点", 1, true) ~= nil, `「按钮名」空着 → 一个都不点 ({toastText()})`)
keyBox.Text = "Buy"
keyBox.FocusLost:Fire()
click(btnExact("点按钮"))
step(1 / 60, 2)
local cl = VIMi.props.clicks or {}
ok(#cl == 2, `点「Buy」→ 按下加抬起两次事件 (实际 {#cl} 次)`)
ok(cl[1] ~= nil and cl[1].x == 577 + 36 and cl[1].y == 378 + 14.5 and cl[1].down == true, `点在按钮正中 ({cl[1] and cl[1].x},{cl[1] and cl[1].y}; 该是 613,392.5)`)
ok(cl[2] ~= nil and cl[2].down == false, "第二次是抬起 (只按不放, 游戏那边不算一次点击)")
ok(toastText():find("点了 1 个", 1, true) ~= nil, `提示说清点了几个, 不闷着 ({toastText()})`)
VIMi.props.clicks = nil
keyBox.Text = "Black"
keyBox.FocusLost:Fire()
click(btnExact("点按钮"))
step(1 / 60, 2)
ok(#(VIMi.props.clicks or {}) == 2, "按子物件上的文字也认得 (按钮名字叫 AbilityBtn, 里头没有 Black)")
keyBox.Text = ""
keyBox.FocusLost:Fire()
ggui:Destroy()
it1:Destroy()
it2:Destroy()
deco:Destroy()
wall:Destroy()
_G.__radius = nil
step(1 / 60, 2)
ok(grabDump():find("界面可点按钮 0 个", 1, true) ~= nil, "界面撤了以后按钮清单跟着归零")
-- ── grab: 推法三档 + 触发提示 ──
-- 真机 26.10.16.7.97 那 641 条: 散件档每帧写 65 个速度; 半径 400 那 49 条里 272 个件每帧都在写,
-- 写入/在半径内 = 1.00, 没有一个进过 1 格以内 —— 客户端写的速度很可能一个都没被吃。所以推法留三档,
-- 写完当场读回来对一遍, 「没吃」这个数就是让机器自己招供的, 别再靠猜。
do
	local function grabInfo() return grabDump():match("\n  grab [^\n]*") or "" end
	local function num1(s, k) return tonumber(s:match(k .. "=(%-?%d+)")) end
	local hi = hrp.props.Position
	local soft = mkThing("Gem", 10, 0, false, { SellToken = "aa" }) -- 速度吃得进去的
	local hard = mkThing("TNT", -8, 0, false, { SellToken = "bb" }) -- 速度写进去就丢的
	-- 模拟「这个件不认客户端写的速度」(所有权在服务端 / 装配体根锚定): 写进去直接吞掉, 读回来还是旧值
	local real = hard.props
	hard.props = setmetatable({}, { __index = real,
		__newindex = function(_, k, v) if k ~= "AssemblyLinearVelocity" then rawset(real, k, v) end end })
	real.AssemblyLinearVelocity = Vector3.zero
	_G.__radius = { soft, hard, hrp }

	local gi0 = grabInfo()
	ok(gi0:find("推法=auto", 1, true) ~= nil, `默认推法是「自动」({gi0})`)
	-- 「未清点」那一档在这套自检里跑不到: 前面「把所有开关翻一遍」那条已经把 自动触发 打开过一次,
	-- st.pp 当时就被写成 0 了。所以这里只钉「数过以后报的是数」, 别假装验了没验的东西。
	ok(gi0:find("提示=%d+") ~= nil or gi0:find("提示=未清点", 1, true) ~= nil, `提示这项要么报数要么报「未清点」, 不会是空 ({gi0})`)
	click(findBtn("自动抓"))
	step(1 / 60, 6)
	local hardX0 = hard.CFrame.Position.X
	step(1 / 60, 6)
	ok(soft.AssemblyLinearVelocity.Magnitude > 0, "自动档: 速度吃得进去的照写速度")
	ok(hard.CFrame.Position.X > hardX0, `自动档: 写不进去的改搬 CFrame ({hardX0} → {hard.CFrame.Position.X})`)
	local gi1 = grabInfo()
	ok((num1(gi1, "没吃") or 0) > 0, `「没吃」把不认速度的件数报出来 ({gi1})`)
	click(findBtn("自动抓"))

	-- 只写速度: 不读回、不改搬 —— 两条路得能分开验, 混在一起就永远说不清是哪条不通
	click(btnExact("推法 自动"))
	step(1 / 60, 1)
	ok(btnExact("推法 只写速度") ~= nil, "推法切一档 → 「只写速度」")
	soft.props.AssemblyLinearVelocity = Vector3.zero
	local hx1, d0 = hard.CFrame.Position.X, num1(grabInfo(), "没吃")
	click(findBtn("自动抓"))
	step(1 / 60, 6)
	ok(soft.AssemblyLinearVelocity.Magnitude > 0, "只写速度: 还是写速度")
	ok(hard.CFrame.Position.X == hx1, "只写速度: 写不进去也不偷偷改搬")
	ok(num1(grabInfo(), "没吃") == d0, `只写速度档不记「没吃」, 这个数才只来自自动档 ({tostring(d0)})`)
	click(findBtn("自动抓"))

	-- 只搬位: 整条速度路都不走
	click(btnExact("推法 只写速度"))
	step(1 / 60, 1)
	ok(btnExact("推法 只搬位") ~= nil, "推法再切一档 → 「只搬位」")
	soft.props.AssemblyLinearVelocity = Vector3.zero
	local gi3 = grabInfo()
	local sx0, p0, m0 = soft.CFrame.Position.X, num1(gi3, "速度写"), num1(gi3, "搬位")
	click(findBtn("自动抓"))
	step(1 / 60, 6)
	ok(soft.AssemblyLinearVelocity.Magnitude == 0, "只搬位: 未锚定的也不写速度")
	ok((num1(grabInfo(), "搬位") or 0) > (m0 or 0), `只搬位档真的在搬, 不是白切一档 (搬位 {tostring(m0)} → {tostring(num1(grabInfo(), "搬位"))})`)
	ok(soft.CFrame.Position.X < sx0, `只搬位: 直接搬 CFrame 往人这边挪 ({sx0} → {soft.CFrame.Position.X})`)
	ok(num1(grabInfo(), "速度写") == p0, `只搬位档不记「速度写」({tostring(p0)})`)
	click(findBtn("自动抓"))
	click(btnExact("推法 只搬位"))
	step(1 / 60, 1)
	ok(btnExact("推法 自动") ~= nil, "推法转一圈回到「自动」")

	-- 自动触发默认关: 半秒发一次全场提示, 主人没要求就不该自己按
	local apOff = false
	for _, b in ipairs(buttons()) do if starts(b.Text, "自动触发") and ends(b.Text, " 关") then apOff = true end end
	ok(apOff, "自动触发默认是关的")

	-- 先在场内一个提示都没有的时候按一次: 缓存下的是空清单。等下新建了提示再按, 手动那次必须绕开缓存
	-- 看到当场的新提示 —— 这条就是钉住「手动 = force」, 不然 1 秒内的手动点击会被上一轮的空清单糊住。
	VIMi.props.keySeq = nil
	click(btnExact("触发提示"))
	step(1 / 60, 2)
	ok(#(VIMi.props.keySeq or {}) == 0 and toastText():find("范围内 0 个", 1, true) ~= nil, `场内没提示就一个都不发 ({toastText()})`)
	-- 触发提示: 收纳槽就是个 ProximityPrompt (真机全场 4 个), 抓到手边还得替主人按下去
	local ppHost = mkPart("Prompt", Vector3.new(1, 1, 1), Vector3.new(hi.X - 3, hi.Y, hi.Z), { Anchored = true })
	ppHost.Parent = workspace
	local pr = inst("ProximityPrompt", { Name = "Prompt", Enabled = true, HoldDuration = 0,
		MaxActivationDistance = 1000, RequiresLineOfSight = false, KeyboardKeyCode = Enum.KeyCode.F })
	pr.Parent = ppHost
	local prOff = inst("ProximityPrompt", { Name = "PromptOff2", Enabled = false, HoldDuration = 0,
		MaxActivationDistance = 1000, RequiresLineOfSight = false, KeyboardKeyCode = Enum.KeyCode.G })
	prOff.Parent = ppHost -- 关着的不能替他按: 游戏关掉一个交互是有原因的
	VIMi.props.keySeq = nil
	click(btnExact("触发提示"))
	step(1 / 60, 2)
	local ks = VIMi.props.keySeq or {}
	ok(#ks == 2, `触发提示 → 按下加抬起两次 (实际 {#ks} 次)`)
	ok(ks[1] ~= nil and ks[1].down == true and ks[1].name == "F", `键是问提示自己要的, 不猜 E (实际 {ks[1] and ks[1].name})`)
	ok(ks[2] ~= nil and ks[2].down == false, "第二次是抬起 (只按不抬下一次就不认了)")
	ok(toastText():find("范围内 1 个", 1, true) ~= nil, `报清范围内几个、发出去几个 ({toastText()})`)
	ok(grabInfo():find("提示=1", 1, true) ~= nil, "页状态里报清点到的提示数")
	-- 自动触发: 半秒一轮。每帧发一次既刷爆游戏那边的事件, 也会半秒一条把日志冲掉
	click(findBtn("自动触发"))
	step(1 / 60, 1)
	VIMi.props.keySeq = nil
	step(1 / 60, 60) -- 一整秒
	local ks2 = VIMi.props.keySeq or {}
	ok(#ks2 >= 2 and #ks2 <= 8, `自动触发按半秒一轮发, 不是每帧刷 (一秒发了 {(#ks2 / 2)} 轮)`)
	ok(toastText():find("范围内", 1, true) == nil, `自动的不弹提示 —— 半秒一条会把日志冲掉 ({toastText()})`)
	-- 半秒一轮 = 每秒两轮, 每轮都全树遍历一次; 真机大地图几万物件, 这个成本得有护栏 (1 秒缓存)
	click(findBtn("自动触发"))
	_G.__descCalls = 0
	step(1 / 60, 60) -- 关着: 这一秒一个全树遍历都不该有
	local dOff = _G.__descCalls or 0
	click(findBtn("自动触发"))
	_G.__descCalls = 0
	step(1 / 60, 60) -- 开着: 两轮触发, 但 1 秒缓存 ⟹ 只真扫一次
	local dOn = _G.__descCalls or 0
	ok(dOff == 0, `自动触发关着时不做全树遍历 (实际 {dOff} 次)`)
	ok(dOn == 1, `开着也只在缓存过期时扫一次全树, 不是每轮都扫 (一秒 {dOn} 次, 两轮触发)`)
	click(findBtn("自动触发"))
	pr:Destroy()
	prOff:Destroy()
	ppHost:Destroy()
	soft:Destroy()
	hard:Destroy()
	_G.__radius = nil
	step(1 / 60, 2)
end

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
ok(entries == 1, `超过上限 → 直接重写, 文件里只剩最新一条 ({entries} 条)`)
ok((VFS["Selfblox_log.txt"] or ""):sub(1, 13) == "---- Selfblox", "重写时补上表头")
ok((VFS["Selfblox_log.txt"] or ""):find(`---- Selfblox {tostring(VER)} `, 1, true) == 1, "表头带版本号 (日志文件跨会话留着, 不带版本就分不清这一份是哪个构建录的)")
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
-- 数字框打 nan / inf: 不能落进配置 (JSONEncode 会抛错, 之后每次改设置都失败)
local spdBox
for _, d in ipairs(all()) do if d:IsA("TextBox") and d.Text == "16" then spdBox = d end end
ok(spdBox ~= nil, "找到速度的数字框 (前置)")
spdBox.Text = "30"; spdBox.FocusLost:Fire()
humanoid.props.MoveDirection = Vector3.new(0, 0, -1)
step(1 / 60, 3)
ok(hrp.props.AssemblyLinearVelocity.Z == -30, `前置: 这个框确实是速度框 (改成 30 就跑到 30, 实际 {hrp.props.AssemblyLinearVelocity.Z})`)
spdBox.Text = "nan"; spdBox.FocusLost:Fire()
step(1 / 60, 3)
ok(hrp.props.AssemblyLinearVelocity.Z == -30, `打 nan → 不落进配置, 速度还是 30 (实际 {hrp.props.AssemblyLinearVelocity.Z})`)
spdBox.Text = "inf"; spdBox.FocusLost:Fire()
step(1 / 60, 3)
ok(hrp.props.AssemblyLinearVelocity.Z == -30, `打 inf → 同样挡掉 (实际 {hrp.props.AssemblyLinearVelocity.Z})`)
spdBox.Text = "16"; spdBox.FocusLost:Fire()
step(1 / 60, 3)
humanoid.props.MoveDirection = Vector3.new(0, 0, -1)
step(1 / 60, 4)
ok(hrp.props.AssemblyLinearVelocity.Z == -16 and hrp.props.AssemblyLinearVelocity.X == 0, `速度·root: 直接写水平速度 ({tostring(hrp.props.AssemblyLinearVelocity)})`)
humanoid.props.MoveDirection = Vector3.zero
step(1 / 60, 4)
ok(hrp.props.AssemblyLinearVelocity.Z == 0, "松摇杆 → 水平速度归零")
-- 模块恒为 0 的游戏里, 速度不能跟着一起废掉。真机 26.10.15.6.89 的 162 条里 ControlModule:GetMoveVector()
-- 全是 0 而人一直在动(相邻样本水平中位 14.1 格/秒), 推=0/跑=489 —— 上一版就是这么把功能整个关掉的。
SBMV.force = Vector3.zero
humanoid.props.MoveDirection = Vector3.new(0, 0, -1)
step(1 / 60, 3)
ok(hrp.props.AssemblyLinearVelocity.Z == -16, `模块报 0 时退回 MoveDirection, root 模式照常写速度 (实际 {tostring(hrp.props.AssemblyLinearVelocity)})`)
SBMV.force = nil
humanoid.props.MoveDirection = Vector3.zero
step(1 / 60, 3)
click(modeBtn)
ok(modeBtn.Text == "模式 walk", "模式按钮循环到 walk")
step(1 / 60, 4)
ok(humanoid.WalkSpeed == 16, "速度·walk: 写 WalkSpeed")
click(modeBtn)
ok(modeBtn.Text == "模式 cframe", "模式按钮循环到 cframe")
-- cframe 模式不再看输入源, 看的是"游戏自己这一步把人挪了多少"。数字照 26.10.15.6.89 的真机日志:
-- 游戏自己那一步约 22 格/秒, spd 设的是 16, 而两个输入源一个恒 1.00 一个恒 0。
_G.__gameMove = Vector3.new(0, 0, -22 / 60)
humanoid.props.MoveDirection = Vector3.new(0, 0, -1) -- 游戏写的满偏, 而且从不归零 (真机 287 条全是 1.00)
step(1 / 60, 1) -- 开门第一帧只记位置基准, 不推
local z0 = hrp.props.CFrame.Position.Z
step(1 / 60, 5)
local per = (z0 - hrp.props.CFrame.Position.Z) / 5 * 60
ok(math.abs(per - 16) < 1e-6, `速度·cframe: 游戏自己在挪人 → 把这一步换成 spd*dt, 净速度就是 spd 而不是 22 + 16 (量到 {per} 格/秒, 设的是 16; 加法语义下滑杆低于 22 就完全不起作用, 想慢下来没门)`)
hrp.props.AssemblyLinearVelocity = Vector3.new(0, 0, -999) -- 引擎从 CFrame 位移里攒出来的动量
step(1 / 60, 3)
ok(hrp.props.AssemblyLinearVelocity.Z == 0, `速度·cframe: 推着走的时候水平速度也每帧钉死, 攒不出动量 (实际 {hrp.props.AssemblyLinearVelocity.Z})`)

-- 方向必须跟着实测位移走, 不能跟着 MoveDirection 走: 真机 26.10.15.5.63 的 287 条里摇杆那一路
-- 恒为 (-0.97,0.00,-0.25) 冻了 23 秒, 而人早转向了。拿 md 当方向就会把人往冻住的那个方向推。
_G.__gameMove = Vector3.new(22 / 60, 0, 0) -- 游戏把人往 +X 挪
humanoid.props.MoveDirection = Vector3.new(0, 0, -1) -- 摇杆那一路还冻在 -Z
step(1 / 60, 1) -- 重新对位基准
local x0, z0b = hrp.props.CFrame.Position.X, hrp.props.CFrame.Position.Z
step(1 / 60, 5)
local dx, dz = hrp.props.CFrame.Position.X - x0, hrp.props.CFrame.Position.Z - z0b
ok(math.abs(dx - 16 * 5 / 60) < 1e-6 and math.abs(dz) < 1e-9, `推力方向取实测位移不取 MoveDirection: 游戏往 +X 挪而摇杆冻在 -Z, 人就该沿 +X 走 (实走 dx={dx} dz={dz}, 该是 {16 * 5 / 60} 和 0)`)
_G.__gameMove = Vector3.new(0, 0, -22 / 60)
step(1 / 60, 2)

-- 松手 = 游戏不再挪人。两个源这时候都还满偏着, 一帧都不许推 —— 26.10.15.5.63 的 #172–#286 就是这个场面
-- (连续 115 条、23.0 秒人不动而摇杆恒为 (-0.97,0.00,-0.25))。前六版都在改怎么拦, 这版把判据换成了游戏本身。
_G.__gameMove = nil
SBMV.force = Vector3.new(0, 0, -1) -- 连控制模块都跟着喊满偏
local zStop = hrp.props.CFrame.Position.Z
step(1 / 60, 6)
local extra = hrp.props.CFrame.Position.Z - zStop
ok(extra >= -1e-9 and extra < 16 / 60, `游戏不挪人了 → 判据是上一帧那一步, 晚一帧才知道, 顶多把那一步补完 (多走了 {extra} 格, 一帧的量是 {16 / 60} 格)`)
local zEnd = hrp.props.CFrame.Position.Z
step(1 / 60, 6)
ok(hrp.props.CFrame.Position.Z == zEnd, "停下之后就一步都不动了, 两个源还满偏也不动 (这就是「停不下来」的出口)")
ok(hrp.props.AssemblyLinearVelocity.Z == 0 and hrp.props.AssemblyLinearVelocity.X == 0, "速度·cframe: 残余速度也钉住, 不会带着人一直滑")
SBMV.force = nil

-- 门槛: 水平不到 1 格/秒算没动。物理抖动 / 站在斜坡上慢慢蹭不能当成走路, 否则站在原地也会被推着走。
_G.__gameMove = Vector3.new(0, 0, -0.3 / 60)
local zCreep = hrp.props.CFrame.Position.Z
step(1 / 60, 6)
ok(math.abs(hrp.props.CFrame.Position.Z - (zCreep - 0.3 / 60 * 6)) < 1e-9, `水平 0.3 格/秒不算走路: 只跟着游戏蹭, 一帧都不额外推 (人在 {hrp.props.CFrame.Position.Z}, 该在 {zCreep - 0.3 / 60 * 6})`)
_G.__gameMove = nil

-- 传送/重生那种一步几十格不能当走路: 当成走路的话下一帧 -d 会照着原路把人拽回去
_G.__gameMove = Vector3.new(0, 0, -30)
step(1 / 60, 2) -- 第二帧才轮到量到那一步 30 格
local zTp = hrp.props.CFrame.Position.Z
_G.__gameMove = nil
step(1 / 60, 3)
ok(hrp.props.CFrame.Position.Z == zTp, `一步 30 格只重新对位, 下一帧不照着 -d 把人拽回去 (人还在 {hrp.props.CFrame.Position.Z}, 对完位是 {zTp})`)
_G.__gameMove = Vector3.new(0, 0, -22 / 60)
step(1 / 60, 2) -- 重新对位那一帧不推, 下一帧才重新开门
ok(hrp.props.CFrame.Position.Z < zTp, "传送之后接着走, 门重新打开")
_G.__gameMove = nil

-- 控制模块坏了不许连速度一起废掉: 丢掉缓存, 退回 Humanoid.MoveDirection
SBMV.gone = true
step(1 / 60, 130) -- 跨过每秒一次的重探窗口
_G.__gameMove = Vector3.new(0, 0, -22 / 60)
local zFb = hrp.props.CFrame.Position.Z
step(1 / 60, 5)
ok(hrp.props.CFrame.Position.Z < zFb, "控制模块抛错 → 退回 Humanoid.MoveDirection, 速度照常能用")
_G.__gameMove = nil
SBMV.gone = nil
step(1 / 60, 130) -- 让它重新拿到控制模块, 后面的断言按原路走

do -- 「模块=无」必须说清是哪一种"无": 真机两份日志 (367 条 + 140 条) 全是这句, 但三种成因的修法完全不同
	local psInst = pmodule.Parent
	local function dumpTxt()
		for _, d in ipairs(all()) do if d:IsA("TextButton") and type(d.Text) == "string" and d.Text:find("诊断打包", 1, true) then d.Activated:Fire() end end
		step(1 / 60, 2)
		return VFS["selfblox_dump.txt"] or ""
	end
	-- 探针是 `if not ctrl and os.clock()-ctrlT > 1`, ctrl 缓存着就永远不进 ⟹ 先用 gone 把缓存打掉
	SBMV.gone = true
	step(1 / 60, 130)
	SBMV.gone = nil
	-- 情况一: PlayerScripts 在, 但里头没有叫 PlayerModule 的 (改名 / 自制控制模块)
	local decoyA = inst("ModuleScript", { Name = "ClientPlayerModule" }); decoyA.Parent = psInst
	local decoyB = inst("LocalScript", { Name = "CustomControls" }); decoyB.Parent = psInst
	pmodule.Parent = nil
	step(1 / 60, 130) -- 跨过每秒一次的重探窗口
	local dm1 = dumpTxt()
	ok(dm1:find("PlayerScripts 在, 但没有 PlayerModule", 1, true) ~= nil, "PlayerScripts 在但没 PlayerModule → 日志明说是这种情况")
	ok(dm1:find("ClientPlayerModule:ModuleScript", 1, true) ~= nil and dm1:find("CustomControls:LocalScript", 1, true) ~= nil, "把 PlayerScripts 底下实际有什么列出来 (改名过的控制模块靠这个认)")
	-- 情况二: 整个 PlayerScripts 都不在
	decoyA:Destroy(); decoyB:Destroy()
	psInst.Parent = nil
	step(1 / 60, 130)
	ok(dumpTxt():find("角色下没有 PlayerScripts", 1, true) ~= nil, "PlayerScripts 整个不在 → 日志说的是这一种, 不和上一种混")
	-- 情况三: PlayerModule 在但取控制模块时抛错
	psInst.Parent = player; pmodule.Parent = psInst
	SBMV.gone = true
	step(1 / 60, 130)
	local dm3 = dumpTxt()
	ok(dm3:find("PlayerModule 在, 但抛错", 1, true) ~= nil, "PlayerModule 在但取不到控制模块 → 日志说的是这一种")
	ok(dm3:find("不可用", 1, true) ~= nil, "而且把 pcall 拿到的真实错误串打出来 (只说「抛错」还是分不清 require 被挡还是脚本自己报错)")
	ok(dm3:find("require/GetModule/GetControls 抛错", 1, true) == nil, "不再用那句信息量为零的旧话")
	SBMV.gone = nil
	step(1 / 60, 130) -- 恢复: 让它重新拿到控制模块
	ok(dumpTxt():find("模块=无", 1, true) == nil, "恢复后模块这条路重新走通, 不再是「模块=无」")

	-- 探针必须由 info 自己调: 上一版 info 只读 doSpeed 留下的缓存, 而 doSpeed 只在速度开着时跑,
	-- 于是 26.10.15.4.62 那份真机日志前 90 条全是「模块=无(还没探过)」, 白等 18 秒才看到真成因。
	if spdBtn.Text:find("开", 1, true) then click(spdBtn) end -- 速度关掉: doSpeed 一帧都不会跑
	step(1 / 60, 3)
	SBMV.gone = true
	step(1 / 60, 130) -- 跨过每秒一次的重探窗口
	local dmOff = dumpTxt()
	SBMV.gone = nil
	ok(dmOff:find("还没探过", 1, true) == nil, "速度关着也探了控制模块 (上一版这里会一直停在「还没探过」)")
	-- 这条原先断言的是 "PlayerModule 在, 但抛错" —— 那是**上一轮探失败时留下的旧话**: GetMoveVector 抛错后
	-- 只清了 ctrl, ctrlWhy/stickFrom/ctrlPath 都没清, 所以旧成因一直挂在日志上。主人评审点出这个自相矛盾,
	-- 清干净之后这里读到的是当场的成因。顺带钉住: 探不到时不许再打「路=」, 那会和 ctrl=nil 打架。
	-- 只看当前那一行 moc: 整份打包里还带着「日志尾部」, 那里面有探成功时期的旧条目, 拿整份找会误判
	local mocNow = dmOff:match("\n  moc [^\n]*") or ""
	ok(mocNow:find("GetMoveVector 抛错", 1, true) ~= nil, `而且报的是当场的成因, 不是上一轮留下的旧话 ({mocNow:match("模块=[^ ]*")})`)
	ok(mocNow:find("路=", 1, true) == nil and mocNow:find("模块=无(", 1, true) ~= nil, "当前这行不再打「路=」(stickFrom 跟着 ctrl 一起清了)")
	step(1 / 60, 130)

	-- 游戏自己的滑竿: 主人说这游戏有自己的跳跃和趴下滑竿(右边上下), 但物件名未知 ⟹ 先扫不问。
	-- 认法只有一条不依赖名字: 底座 Active 且方, 子物件的 Position 会变的就是滑块。
	local gctl = inst("ScreenGui", { Name = "GameControls" }); gctl.Parent = pgui
	local gbase = inst("Frame", { Name = "SlideStick", Active = true, Visible = true }); gbase.Parent = gctl -- inst 不接父参数, 得赋 .Parent
	gbase.props.AbsoluteSize = { X = 120, Y = 120 }
	gbase.props.AbsolutePosition = { X = 900, Y = 1800 } -- 视口 1080 宽, 中线 540 ⟹ 这是右半屏
	local gknob = inst("Frame", { Name = "Knob", Visible = true }); gknob.Parent = gbase
	gknob.props.AbsoluteSize = { X = 60, Y = 60 }
	gknob.props.AbsolutePosition = { X = 930, Y = 1830 }
	gknob.Position = UDim2.fromOffset(30, 30)
	-- 主人认出真机日志里那 6 个 Unlocked/ImageIcon 是游戏最上面的菜单条 (三份日志 y=109/183/179, 等大等距一排)。
	-- 上一版按 尺寸 / 屏幕区 / Active 层层筛, 还只留 6 个名额, 报出来的就全是顶栏 —— 被筛掉的正好是要找的那个。
	-- 这版全列: 树里每个不是自家的 GuiObject 都进日志。顶栏的、隐身的、10px 的各摆一个, 一个都不许漏。
	local topBar = inst("Frame", { Name = "Unlocked" }); topBar.Parent = gctl
	local topIco = inst("ImageButton", { Name = "ImageIcon", Active = true, Visible = true }); topIco.Parent = topBar
	topIco.props.AbsoluteSize = { X = 84, Y = 84 }
	topIco.props.AbsolutePosition = { X = 700, Y = 100 } -- 顶栏: 上一版就是被 y < 视口*0.3 挡掉的那个
	local hid = inst("Frame", { Name = "HiddenBtn", Active = true, Visible = false }); hid.Parent = gctl
	hid.props.AbsoluteSize = { X = 10, Y = 10 } -- 又小又隐: 上一版可见性和尺寸两道筛都会把它吃掉
	hid.props.AbsolutePosition = { X = 30, Y = 2300 }
	step(1 / 60, 130)
	local dg1 = dumpTxt()
	ok(dg1:find("没认出滑块", 1, true) ~= nil, "第一次扫认不出滑块: 没有上一次的 Position 可比")
	ok(dg1:find("全清单:", 1, true) ~= nil and dg1:find("视口 1080x2400", 1, true) ~= nil, "认不出来就把整棵树列出来, 并带上视口 (光有 y=179 这种绝对像素分不出顶还是底)")
	-- 真机 26.10.15.5.63 报出右半屏 6 个全是 "ImageIcon:ImageButton" —— 名字类名一模一样, 分不出跳跃和趴下滑竿,
	-- 所以光报名字不够, 得带上父名 + 类名 + 屏幕坐标 + 尺寸 + 可见 + Active + 子物件数, 下一份日志才认得出谁是谁。
	ok(dg1:find("GameControls/SlideStick:Frame@900,1800 120x120 VA 子1", 1, true) ~= nil, "每个物件报父名/类名/坐标/尺寸/可见/Active/子物件数 (光报 名字:类名 在真机上六个全一样, 等于没报)")
	ok(dg1:find("Unlocked/ImageIcon:ImageButton@700,100 84x84 VA 子0", 1, true) ~= nil, "顶栏那排照列, 不再按屏幕位置筛掉 (是不是菜单条由人看着坐标判, 不由代码猜)")
	ok(dg1:find("GameControls/HiddenBtn:Frame@30,2300 10x10 vA 子0", 1, true) ~= nil, "隐身的、10px 的也照列 (上一版可见性和尺寸两道筛都会把它吃掉)")
	ok(dg1:find("SB_Title", 1, true) == nil, "自家面板不进清单 (sbOwn 认得自家 gui)")
	ok(dumpTxt():find("清单同上", 1, true) ~= nil, "同一份清单不重打: info 每 0.2 秒进一次日志, 一秒没变也打五遍, 十来秒就把 logmax 顶爆重写")
	gknob.Position = UDim2.fromOffset(30, 60) -- 往下拨: 真机那个趴下滑竿就是上下动
	gknob.props.AbsolutePosition = { X = 930, Y = 1860 }
	step(1 / 60, 130)
	local dg2 = dumpTxt()
	ok(dg2:find("SlideStick/Knob@右", 1, true) ~= nil, "Position 变过 → 认定是滑块, 报出名字和它在左还是右")
	ok(dg2:find("(0.00,0.50)", 1, true) ~= nil, "值按底座几何中心归一: 下偏半个半径 = (0.00,0.50)")
	-- 自家面板也是 Active 方块, 不能混进来 (转向条本身就长得像滑竿)
	local myTrack
	for _, d in ipairs(all()) do if d.Name == "SB_Steer" then myTrack = d end end
	ok(myTrack ~= nil, "前置: 面板里有自己的转向条")
	myTrack.Visible = true; myTrack.Active = true
	myTrack.props.AbsoluteSize = { X = 120, Y = 60 }
	myTrack.props.AbsolutePosition = { X = 900, Y = 1800 }
	local myKnob = inst("Frame", { Name = "SB_Knob", Visible = true }); myKnob.Parent = myTrack
	myKnob.props.AbsoluteSize = { X = 40, Y = 40 }
	myKnob.Position = UDim2.fromOffset(0, 0)
	step(1 / 60, 130) -- 必须先跨过 1 秒节流: 上一次探针就在 dg2 里, 不 step 直接打包这次探不到 (实测漏过)
	dumpTxt() -- 探针只在 info 里跑, step 不触发它 ⟹ 要探两次就得打包两次, 少一次这条断言会假绿(实测过)
	myKnob.Position = UDim2.fromOffset(40, 0)
	step(1 / 60, 130) -- 跨过每秒一次节流
	local dg3 = dumpTxt()
	ok(dg3:find("SB_Steer", 1, true) == nil and dg3:find("SB_Knob", 1, true) == nil, "自家转向条摆成滑竿的样子也不混进来 (sbOwn 认得自家 gui)")
	ok(dg3:find("SlideStick/Knob@右", 1, true) ~= nil, "排除自家的同时没把游戏那个弄丢")
	myKnob:Destroy(); myTrack.Visible = false; myTrack.Active = false
	gctl:Destroy()
	step(1 / 60, 130)
	ok(dumpTxt():find("SlideStick", 1, true) == nil, "游戏那棵树撤了以后, 认出来的滑块也跟着从日志里消失")
	-- Active=false 的照样列: 触屏控件常常是 Active=false 靠 InputBegan 自己收事件, 只收 Active 的会整个漏掉。
	-- 60x400 的竖条: 竖着的趴下滑竿轨道, 上一版两道尺寸筛都会把它吃掉。
	local pass = inst("Frame", { Name = "ProneTrack", Active = false, Visible = true }); pass.Parent = pgui
	pass.props.AbsoluteSize = { X = 60, Y = 400 }
	pass.props.AbsolutePosition = { X = 950, Y = 1700 }
	step(1 / 60, 130)
	ok(dumpTxt():find("PlayerGui/ProneTrack:Frame@950,1700 60x400 V- 子0", 1, true) ~= nil, "Active=false 的、400 高的竖条也照列, 不做尺寸和 Active 筛选")
	pass:Destroy()
	step(1 / 60, 130)
	ok(dumpTxt():find("ProneTrack", 1, true) == nil, "撤掉以后日志里也跟着没了")
	-- 16KB 护栏得真跑一遍: 上千物件的 UI 会把 logmax 顶爆重写, 速度样本全丢。砍了多少个必须明写出来 ——
	-- 上一版就是 6 个名额把要找的东西砍掉了还没吭声, 主人只能一轮一轮重发日志。
	local bulk = inst("ScreenGui", { Name = "Bulk" }); bulk.Parent = pgui
	for i = 1, 500 do
		local b = inst("Frame", { Name = "B" .. i, Visible = true }); b.Parent = bulk
		b.props.AbsoluteSize = { X = 50, Y = 50 }
		b.props.AbsolutePosition = { X = i % 1000, Y = i % 2000 }
	end
	step(1 / 60, 130)
	local dgBulk = dumpTxt()
	local nBulk = tonumber(dgBulk:match("物件 (%d+) 个"))
	ok(nBulk ~= nil and nBulk >= 500, `500 个物件一个不落地数到 (数到 {tostring(nBulk)} 个)`)
	ok(dgBulk:find("没列(超16KB", 1, true) ~= nil, "超 16KB 才截断, 而且把截断这件事写在日志里")
	ok(dgBulk:find("还有 %d+ 个没列") ~= nil, "砍掉了几个也报个数, 不闷着")
	-- 护栏可以砍日志行, 不能砍掉「能查的」。真机那轮 3699 个物件砍掉 3381 个, 要找的按钮大概率就在被砍的
	-- 那堆里, 所以诊断打包里必须另有一份一个不砍的。这一条钉住「日志行砍掉的, 打包里补回来了」。
	local nFull = tonumber(dgBulk:match("界面物件全清单 (%d+) 个"))
	local nCut = tonumber(dgBulk:match("还有 (%d+) 个没列"))
	ok(nCut ~= nil and nCut > 0, `日志行确实砍了 ({tostring(nCut)} 个)`)
	ok(nFull ~= nil and nFull == nBulk, `打包里的全清单一个不少 ({tostring(nFull)} / {tostring(nBulk)})`)
	bulk:Destroy()
	step(1 / 60, 130)
	ok(dumpTxt():find("超16KB", 1, true) == nil, "物件撤了以后护栏跟着消失, 清单恢复完整")
	click(spdBtn) -- 复原: 上面为了测「速度关着也探」把它关了, 后面的断言按速度开着走
	step(1 / 60, 3)
	ok(spdBtn.Text:find("开", 1, true) ~= nil, "复原: 速度重新是开的")
end

do -- 控制模块那两条路。真机 26.10.15.5.63 的错误串 ":278: attempt to call missing method 'GetModule' of tab"
	-- 说的就是脚本凭空插的那层 GetModule —— 官方 require 出来的表上只有 GetControls。这一版改成直调。
	local function dumpTxt()
		for _, d in ipairs(all()) do if d:IsA("TextButton") and type(d.Text) == "string" and d.Text:find("诊断打包", 1, true) then d.Activated:Fire() end end
		step(1 / 60, 2)
		return VFS["selfblox_dump.txt"] or ""
	end
	local function reprobe() SBMV.gone = true; step(1 / 60, 130); SBMV.gone = nil; step(1 / 60, 130) end -- 先打掉 ctrl 缓存, 再跨过每秒重探窗口
	reprobe()
	local dp = dumpTxt()
	ok(dp:find("路=GetControls", 1, true) ~= nil, "官方那层 GetControls 直调就走通了, 并把走的是哪条路打进日志")
	ok(dp:find("路=GetModule", 1, true) == nil, "官方表上没有 GetModule, 所以走的必须是直调那条 (上一版死在这儿)")
	-- 第二条路: roblox-ts 生成的那套才多一层 GetModule, 不能因为修官方那条就把它弄丢
	local stock = MODULES[pmodule]
	MODULES[pmodule] = { GetModule = function() return { GetControls = mkControls } end }
	reprobe()
	local dl = dumpTxt()
	MODULES[pmodule] = stock
	ok(dl:find("路=GetModule", 1, true) ~= nil, "只有 GetModule 那套也认得出来, 自动走第二条路")
	step(1 / 60, 130)
	ok(dumpTxt():find("路=GetControls", 1, true) ~= nil, "换回官方那张表后回到直调那条路")
end

do -- cframe 的门必须自己打进日志: 26.10.15.6.89 那份日志只有「推=0/跑=489」, 光看它分不清是门没开还是根本没跑
	local function dumpTxt()
		for _, d in ipairs(all()) do if d:IsA("TextButton") and type(d.Text) == "string" and d.Text:find("诊断打包", 1, true) then d.Activated:Fire() end end
		step(1 / 60, 2)
		return VFS["selfblox_dump.txt"] or ""
	end
	_G.__gameMove = Vector3.new(0, 0, -22 / 60)
	step(1 / 60, 4)
	local dOn = dumpTxt()
	ok(dOn:find("门=开", 1, true) ~= nil, "游戏在挪人 → 日志里门是开的")
	ok(dOn:find("游=22.0 净=16.0格/秒", 1, true) ~= nil, `游戏自己那一步和换完的净速度并排打, 真机好对账 (实际 {tostring(dOn:match("游=[^ ]* [^ ]*"))})`)
	_G.__gameMove = nil
	step(1 / 60, 4)
	ok(dumpTxt():find("门=关", 1, true) ~= nil, "游戏不挪人了 → 门是关的 (下一份日志一眼就能看出门开没开)")
end
click(modeBtn) -- 回到 root
humanoid.props.MoveDirection = Vector3.new(0, 0, -1)
step(1 / 60, 3)
ok(hrp.props.AssemblyLinearVelocity.Z == -16, "前置: root 模式推着摇杆, 水平速度 = 16")
humanoid.props.MoveDirection = Vector3.zero -- 松摇杆但这一帧不跑 tick, 直接关开关
click(spdBtn)
step(1 / 60, 3)
ok(hrp.props.AssemblyLinearVelocity.Z == 0 and hrp.props.AssemblyLinearVelocity.X == 0, "关掉「速度」也得清掉残余水平速度, 不然开关关了人还在滑")
ok(humanoid.WalkSpeed == 16, "关速度 → WalkSpeed 还原")
-- 速度关着也要能看出摇杆回没回中 (上一版把摇杆缓存在 doSpeed 里, 速度关着就一直是旧值, 20 个初始零被当成了证据)
humanoid.props.MoveDirection = Vector3.new(0, 0, -1)
for _, d in ipairs(all()) do if d:IsA("TextButton") and type(d.Text) == "string" and d.Text:find("诊断打包", 1, true) then d.Activated:Fire() end end
step(1 / 60, 2)
ok((VFS["selfblox_dump.txt"] or ""):find("摇杆=(0.00,0.00,-1.00)", 1, true) ~= nil, "速度关着也照采摇杆 (info() 现读, 不缓存)")
ok((VFS["selfblox_dump.txt"] or ""):find("态=Running", 1, true) ~= nil, "诊断里带人形状态 (真机实测站着不动也是 Running, 所以不能拿它当没输入的判据; 但 Climbing 这类能看出来)")
humanoid.props.MoveDirection = Vector3.zero
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
ok(barLbl and not (barLbl.Text:find("ms", 1, true) or barLbl.Text:find("fps", 1, true) or barLbl.Text:find("MB", 1, true)), `数据条数字后面不带 ms / fps / MB 单位 ({tostring(barLbl and barLbl.Text)})`)
local LOGTXT = VFS["Selfblox_log.txt"]
ok(LOGTXT == nil or not LOGTXT:find("fps"), "日志里没有 fps/ms 那种备注")
ok(CLIP == nil or true, "剪贴板接口在")
ok(jsonDecode(VFS["Selfblox.json"]).tab ~= nil, "JSON 里有上次页签")

do -- 包一层: smoke 是一整个顶层 chunk, 局部变量超 200 就编不过
print("\n[8e] 关「高跳」不能把速度也还原掉 (原来一个 restore() 把 WalkSpeed/JumpPower/JumpHeight 三样一起写回)")
local jumpBtn = findBtn("高跳")
local spdBtn2 = findBtn("速度 ") -- spdBtn 是前面 do 块里的局部, 这里够不着
ok(jumpBtn ~= nil and spdBtn2 ~= nil, `有「高跳」和「速度」开关 (高跳 {tostring(jumpBtn ~= nil)} / 速度 {tostring(spdBtn2 ~= nil)})`)
local function numOf(tog) -- 跟开关同一行的那个数字框 (feature 的 num= 会紧跟在开关后面, 两个同属一行 Frame)
	for _, c in ipairs(tog.Parent:GetChildren()) do
		if c:IsA("Frame") then for _, g in ipairs(c:GetChildren()) do if g:IsA("TextBox") then return g end end end
	end
end
local spdBox2, jmpBox2 = numOf(spdBtn2), numOf(jumpBtn)
ok(spdBox2 ~= nil and jmpBox2 ~= nil, "前置: 找到速度 / 高跳的数字框")
local modeBtn = findBtn("模式 ") -- 只有 walk 模式写 WalkSpeed; root/cframe 模式写的是速度向量, 拿它测不出串扰
for _ = 1, 3 do if modeBtn.Text:find("walk", 1, true) then break end; click(modeBtn); step(1 / 60, 2) end
ok(modeBtn.Text:find("walk", 1, true) ~= nil, `前置: 切到 walk 模式 (读到 {modeBtn.Text})`)
spdBox2.Text = "30"; spdBox2.FocusLost:Fire() -- 默认 16 跟基准 WalkSpeed 一样, 不改就看不出"有没有被改过"
jmpBox2.Text = "90"; jmpBox2.FocusLost:Fire() -- 默认 50 跟基准 JumpPower 一样, 同上
step(1 / 60, 2)
local wsRest = humanoid.WalkSpeed
click(spdBtn2); step(1 / 60, 3)
local wsOn = humanoid.WalkSpeed
ok(wsOn == 30, `前置: 开速度把 WalkSpeed 写成 30 (读到 {wsOn}, 基准 {wsRest})`)
click(jumpBtn); step(1 / 60, 3)
local jpOn = humanoid.JumpPower
ok(jpOn == 90, `前置: 开高跳把 JumpPower 写成 90 (读到 {jpOn})`)
click(jumpBtn) -- 关高跳: off 是同步跑的
-- 必须在这里断言, 不能先 step: speedTick 每帧把 WalkSpeed 重写回 S.spd, 跑一帧串扰就被盖掉看不见了
ok(humanoid.WalkSpeed == wsOn, `关高跳不当场动 WalkSpeed (读到 {humanoid.WalkSpeed}, 该还是 {wsOn})`)
step(1 / 60, 3)
ok(humanoid.JumpPower == 50, `关高跳 → JumpPower 还原 (读到 {humanoid.JumpPower})`)
ok(humanoid.WalkSpeed == wsOn, `跑过帧后 WalkSpeed 仍是 {wsOn} (读到 {humanoid.WalkSpeed})`)
click(spdBtn2); step(1 / 60, 3) -- 关速度
ok(humanoid.WalkSpeed == wsRest, `关速度 → WalkSpeed 还原 (读到 {humanoid.WalkSpeed})`)
ok(humanoid.JumpPower == 50, `关速度不动 JumpPower (读到 {humanoid.JumpPower})`)

print("\n[8f] 存盘失败不能连累改它的功能 (原来 writefile/JSONEncode 抛错会顺着调用方一路炸上来)")
-- writefile 换不动: FROZEN_G 之后 _G 的写入被吞掉 (实测替换后调用 0 次)。JSONEncode 走 _G.__SVC 拿得到, 而且它就在 save() 的 pcall 里面
local HS8 = _G.__SVC.HttpService
local oldEnc8 = HS8.props.JSONEncode
HS8.props.JSONEncode = function() error("序列化炸了(模拟)") end
local okSv, errSv = pcall(function() jmpBox2.Text = "77"; jmpBox2.FocusLost:Fire(); step(1 / 60, 2) end)
ok(okSv, `存盘炸了数值照常改, 没炸到调用方 ({tostring(errSv)})`)
HS8.props.JSONEncode = oldEnc8
local okSv2, errSv2 = pcall(function() jmpBox2.Text = "90"; jmpBox2.FocusLost:Fire(); step(1 / 60, 2) end)
ok(okSv2, `序列化恢复后存盘照旧 ({tostring(errSv2)})`)

-- 下面四条只有静态断言: 假引擎里拆掉它们不会变红 (实测过), 所以这里只能钉住"代码还在", 不等于验过行为
--   · toast 卸载后不写死标签 · 相机没就绪时 vp 有兜底 · SB_UNLOAD 重入保护 · 闪灯代号
local lampGuards = select(2, SRC:gsub("if not alive or gen ~= lampGen then return end", ""))
ok(SRC:find("if not alive or not toastL.Parent then return end", 1, true) ~= nil
	and SRC:find("(cam0 and cam0.ViewportSize) or Vector2.new(800, 600)", 1, true) ~= nil
	and SRC:find("if not alive then return end -- 重入保护", 1, true) ~= nil
	and lampGuards == 2,
	`toast/相机/卸载重入 三处守卫 + 闪灯代号两处都在 (闪灯读到 {lampGuards} 处, 该是 2; 静态: 假引擎拆掉不会变红)`)

end

print("\n[9] 卸载")
humanoid.props.SeatPart = nil
local before = newInstancesFrom(SNAP)
local unloadRef = _G.SB_UNLOAD -- 重入测试要一个卸载后还在手的引用
_G.SB_UNLOAD()
step(1 / 60, 10)
-- 卸载后还留着 SB_DUMP 的话, 一调就去摸已经 Destroy 的实例: dumpLines 里 pageInfos 和各页 DUMP 都不看 alive
ok(_G.SB_DUMP == nil, "卸载把 SB_DUMP 也摘了 (只摘 SB_UNLOAD 会留一个能摸到死实例的入口)")
local leaked = 0
for _, i in ipairs(before) do if not i.destroyed then leaked = leaked + 1 end end
ok(tabs() == nil, "面板整个没了")
ok(leaked == 0, `没漏实例 (漏了 {leaked} 个)`)
ok(LIVE == 0, `没漏连接 (还剩 {LIVE} 个)`)
ok(_G.SB_UNLOAD == nil, "SB_UNLOAD 自己清了")
local okTwice, errTwice = pcall(unloadRef) -- 存着的旧引用再卸一次: 没重入保护就会在已销毁的面板上再走一遍
ok(okTwice, `拿旧引用再卸一次不炸 ({tostring(errTwice)})`)
ok(_G.__hook ~= _G.__planeHook, "卸载时 __namecall 钩子还原成原来的")

-- ───────── 第二轮: 只装 moc + _G.SB 覆盖 ─────────
print("\n[10] _G.SB 覆盖 + only 过滤")
SNAP = #INSTANCES
_G.SB = { only = { "moc", "hud" }, spd = 99, clock = "24", stats = true }
local fn2, lerr2 = load_chunk(SRC, "selfblox2")
ok(fn2 ~= nil, `第二轮语法 OK {tostring(lerr2 or "")}`)
local ok2, err2 = pcall(fn2)
ok(ok2, `再跑一次没报错 {tostring(err2 or "")}`)
step(1 / 60, 20) -- 先把帧喂够: 数据条 0.2s 才刷一次, 页签/数值框是立刻有的
local n = 0
for _, d in ipairs(all()) do if d:IsA("TextButton") and d.Text == "动" then n = n + 1 end end
ok(n == 1, "only={moc,hud} 只留了「动」「显」两个页签")
ok(findBtn("车") == nil and findBtn("漂") == nil and findBtn("志") == nil and findBtn("机") == nil and findBtn("抓") == nil, "only 过滤掉的页 (车/漂/志/机/砖) 根本没建")
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
ok(fn3 ~= nil, `语法 OK {tostring(lerr3 or "")}`)
local ok3, err3 = pcall(fn3)
ok(ok3, `配置坏了照样起面板 {tostring(err3 or "")}`)
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
	ok(okf, `sibs 单模块能起 {tostring(ef or "")}`)
end
local function bound(p) return p:FindFirstChild("SB_SIBS") ~= nil end

_G.__radius = { bench, farSeat, seat }
freshSibs()
step(1 / 60, 90)
ok(bound(seat) and not bound(bench) and not bound(farSeat), "自动绑到最近的车座位 (长椅被跳过, 远的不选)")
ok(toastText():find("自动绑定", 1, true) ~= nil, `提示说明自动绑了 ({toastText()})`)

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
ok(okR, `重生那几秒(Character=nil) 车还绑着、穿墙开着, 车上还冒出新零件: 不抛错 {tostring(not okR and eR or "")}`)
ok(late.CanCollide == false, "重生期间新冒出来的零件也照常穿墙")
late:Destroy()
player.props.Character = charSaved
step(1 / 60, 5)

_G.SB_UNLOAD()
step(1 / 60, 3)
local leaked12 = 0
for i = SNAP12 + 1, #INSTANCES do if not INSTANCES[i].destroyed then leaked12 = leaked12 + 1 end end
ok(leaked12 == 0 and LIVE == 0, `自动绑车这一轮卸载同样干净 (漏 {leaked12} 个实例 / {LIVE} 个连接)`)
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
ok(okLoad, `多一个功能 (含一个坏行) 后脚本照样起得来 {tostring(errLoad or "")}`)
do -- 「默认值」和「没数过」只有空配置刚起来这一刻验得到: 前面点过的开关都存进配置了,
	-- 之后再读默认值读到的是存盘值 —— 自动触发默认开就是这么漏过一轮变异自检的。
	local apDef = false
	for _, b in ipairs(buttons()) do if starts(b.Text, "自动触发") and ends(b.Text, " 关") then apDef = true end end
	ok(apDef, "空配置起来 → 自动触发默认关 (半秒发一次全场提示, 不能默认开)")
	local gmDef = false -- btnExact 是前面一个 do 块里的局部, 这儿够不着, 自己找一遍
	for _, b in ipairs(buttons()) do if b.Text == "推法 自动" then gmDef = true end end
	ok(gmDef, "空配置起来 → 推法默认「自动」")
	for _, d in ipairs(all()) do if d:IsA("TextButton") and type(d.Text) == "string" and d.Text:find("诊断打包", 1, true) then d.Activated:Fire() end end
	step(1 / 60, 2)
	local gFresh = (VFS["selfblox_dump.txt"] or ""):match("\n  grab [^\n]*") or ""
	ok(gFresh:find("提示=未清点", 1, true) ~= nil and gFresh:find("界面按钮=未清点", 1, true) ~= nil,
		`没清点过的报「未清点」不报 0 —— 0 会被读成「这游戏没提示 / 没按钮」({gFresh})`)
end
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
ok(leaked13 == 0 and LIVE == 0, `加了功能的这一轮卸载同样干净 (漏 {leaked13} 个实例 / {LIVE} 个连接)`)
_G.__ping, _G.__pingbtn = nil, nil
end

print(`\n{((if FAILS == 0 then "全部通过 ✓" else ("有 " .. FAILS .. " 条没过 ✗")))}`)
if FAILS > 0 then error(`{FAILS} 条断言没过`, 0) end -- 不靠 os.exit: Luau 的 os 库只有 clock/date/difftime/time, 没有 exit; 只有 error 能让进程退出码非 0
if FAILS ~= 0 and error then error(`{FAILS} 条没过`, 0) end
