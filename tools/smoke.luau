-- tools/smoke.luau — KIT v10 逻辑冒烟测试（stub 环境 + 场景驱动）
-- 由 `python3 build.py --smoke` 生成 tools/.smoke_run.lua 并用 luau CLI 执行。
-- 约定：
--   * 占位符 SOURCES_GO_HERE 被 build.py 替换为内嵌 SOURCES 表（dist 源码，
--     且 `_G.` 前缀被剥离 —— CLI 的 _G 是冻结表，裸全局才可写）。
--   * 环境以裸全局导出（game/workspace/Instance/...），与被测代码共享全局环境。
--   * task.wait 必须 yield（否则死循环）；事件处理器统一包协程，yield 无害。

local ERRORS = {}
local function fail(msg, extra)
	local line = "FAIL\t" .. tostring(msg) .. (extra ~= nil and ("\t" .. tostring(extra)) or "")
	table.insert(ERRORS, line)
	print(line)
end

local function busy(sec)
	local t0 = os.clock()
	while os.clock() - t0 < sec do end
end

------------------------------------------------------------------ 环境构造
local function buildEnv()
	-- ===== 事件 / 连接 =====
	local EVENTS = {}
	local function mkEvent(name)
		if EVENTS[name] then return EVENTS[name] end
		local handlers = {}
		local ev = { __name = name, _handlers = handlers }
		function ev:Connect(fn)
			local conn = { Connected = true }
			function conn:Disconnect()
				conn.Connected = false
				for i = #handlers, 1, -1 do
					if handlers[i] == fn then table.remove(handlers, i) end
				end
			end
			table.insert(handlers, fn)
			return conn
		end
		ev.Once = ev.Connect
		ev.Wait = ev.Connect
		function ev:Fire(...)
			for _, fn in ipairs(table.clone(handlers)) do
				local co = coroutine.wrap(fn)
				local ok, err = pcall(co, ...)
				if not ok then fail("handler:" .. name, err) end
			end
		end
		EVENTS[name] = ev
		return ev
	end

	-- ===== Enum（懒创建，任何 Enum.X.Y 都能过）=====
	local enumRoot = setmetatable({}, {
		__index = function(t, k)
			if type(k) ~= "string" then return nil end
			local sub = setmetatable({}, {
				__index = function(st, sk)
					if type(sk) ~= "string" then return nil end
					local v = { Name = sk, EnumType = k }
					rawset(st, sk, v)
					return v
				end,
			})
			rawset(t, k, sub)
			return sub
		end,
	})

	-- ===== 基础值类型（带算术元表：viewport * 0.5 之类的运算必须能过）=====
	local function vecMeta(n)
		local meta = {}
		local function raw3(t)
			return t.X, t.Y, n == 3 and t.Z or 0
		end
		local function build(x, y, z)
			local t = { X = x, Y = y }
			if n == 3 then t.Z = z end
			return setmetatable(t, meta)
		end
		meta.__add = function(a, b)
			local ax, ay, az = raw3(a)
			local bx, by, bz = raw3(b)
			return build(ax + bx, ay + by, az + bz)
		end
		meta.__sub = function(a, b)
			local ax, ay, az = raw3(a)
			local bx, by, bz = raw3(b)
			return build(ax - bx, ay - by, az - bz)
		end
		meta.__unm = function(a)
			local ax, ay, az = raw3(a)
			return build(-ax, -ay, -az)
		end
		meta.__mul = function(a, b)
			if type(a) == "number" then a, b = b, a end
			if type(b) == "number" then
				local ax, ay, az = raw3(a)
				return build(ax * b, ay * b, az * b)
			end
			local ax, ay, az = raw3(a)
			local bx, by, bz = raw3(b)
			return build(ax * bx, ay * by, az * bz)
		end
		meta.__div = function(a, b)
			if type(b) == "number" then
				local ax, ay, az = raw3(a)
				return build(ax / b, ay / b, az / b)
			end
			local ax, ay, az = raw3(a)
			local bx, by, bz = raw3(b)
			return build(ax / bx, ay / by, az / bz)
		end
		meta.__index = function(t, k)
			if k == "Magnitude" then
				local x, y, z = raw3(t)
				return math.sqrt(x * x + y * y + z * z)
			elseif k == "Unit" then
				local m = meta.__index(t, "Magnitude")
				if m == 0 then return build(0, 0, 0) end
				return meta.__div(t, m)
			elseif k == "Dot" then
				return function(a, b)
					local ax, ay, az = raw3(a)
					local bx, by, bz = raw3(b)
					return ax * bx + ay * by + az * bz
				end
			elseif k == "Cross" then
				return function(a, b)
					local ax, ay, az = raw3(a)
					local bx, by, bz = raw3(b)
					return build(ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx)
				end
			end
			return nil
		end
		return meta
	end
	local vec3Meta = vecMeta(3)
	local vec2Meta = vecMeta(2)
	local Vector3 = {
		new = function(x, y, z)
			return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, vec3Meta)
		end,
	}
	Vector3.zero = Vector3.new(0, 0, 0)
	Vector3.one = Vector3.new(1, 1, 1)
	local Vector2 = {
		new = function(x, y)
			return setmetatable({ X = x or 0, Y = y or 0 }, vec2Meta)
		end,
	}
	Vector2.zero = Vector2.new(0, 0)
	Vector2.one = Vector2.new(1, 1)
	-- CFrame 运算桩：moc 里有 root.CFrame * CFrame.new(...) 用法
	local cframeMeta
	do
		local t = {}
		t.__mul = function(a, _b) return a end
		t.__add = function(a, _b) return a end
		t.__sub = function(a, _b) return a end
		t.__index = function(tt, k)
			if k == "Position" then return Vector3.zero end
			if k == "LookVector" then return Vector3.new(0, 0, -1) end
			if k == "RightVector" then return Vector3.new(1, 0, 0) end
			if k == "UpVector" then return Vector3.new(0, 1, 0) end
			return nil
		end
		cframeMeta = t
	end
	local CFrame = {
		new = function(...) return setmetatable({ __cf = table.pack(...) }, cframeMeta) end,
		lookAt = function(pos, target)
			return setmetatable({ __lookat = pos, __target = target }, cframeMeta)
		end,
	}
	CFrame.identity = CFrame.new()
	local UDim = {
		new = function(scale, offset) return { Scale = scale or 0, Offset = offset or 0 } end,
	}
	local UDim2 = {
		new = function(a, b, c, d) return { X = a or 0, X2 = b or 0, Y = c or 0, Y2 = d or 0 } end,
		fromOffset = function(x, y) return { X = 0, X2 = x, Y = 0, Y2 = y } end,
		fromScale = function(x, y) return { X = x, X2 = 0, Y = y, Y2 = 0 } end,
	}
	local Color3 = {
		new = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end,
	}
	Color3.fromRGB = function(r, g, b) return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
	Color3.fromHSV = function(h, s, v) return { H = h, S = s, V = v, R = v, G = v, B = v } end
	Color3.fromHex = function(hex)
		local h = tostring(hex):gsub("#", "")
		return Color3.fromRGB(
			tonumber(h:sub(1, 2), 16) or 0,
			tonumber(h:sub(3, 4), 16) or 0,
			tonumber(h:sub(5, 6), 16) or 0
		)
	end
	local RaycastParams = {
		new = function()
			return {
				FilterType = enumRoot.RaycastFilterType.Exclude,
				FilterDescendantsInstances = {},
				IgnoreWater = false,
				RespectCanCollide = false,
			}
		end,
	}
	local OverlapParams = {
		new = function()
			return {
				FilterType = enumRoot.RaycastFilterType.Exclude,
				FilterDescendantsInstances = {},
				MaxParts = 0,
			}
		end,
	}

	-- ===== Instance =====
	local INHERIT = {
		Part = "BasePart", MeshPart = "BasePart", WedgePart = "BasePart", TrussPart = "BasePart",
		VehicleSeat = "Seat",
		Frame = "GuiObject", TextLabel = "GuiObject", TextButton = "GuiObject",
		TextBox = "GuiObject", ScrollingFrame = "GuiObject", ImageLabel = "GuiObject",
	}
	local AUTO_EVENTS = {
		ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true,
		Destroying = true, AncestryChanged = true, AttributeChanged = true,
		Seated = true, Touched = true, Untouched = true, Changed = true,
		InputBegan = true, InputChanged = true, InputEnded = true, InputFocus = true,
		Event = true, -- BindableEvent.Event
		-- GuiButton / TextBox 常用事件
		Activated = true, MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true,
		MouseButton2Click = true, MouseButton2Down = true, MouseButton2Up = true,
		TouchTap = true, FocusLost = true, Focused = true, Equipped = true, Unequipped = true,
	}
	local methods = {}
	function methods:GetChildren()
		local out = {}
		for _, c in ipairs(self._children) do table.insert(out, c) end
		return out
	end
	function methods:GetDescendants()
		local out = {}
		local function walk(n)
			for _, c in ipairs(n._children or {}) do
				table.insert(out, c)
				walk(c)
			end
		end
		walk(self)
		return out
	end
	function methods:FindFirstChild(name)
		for _, c in ipairs(self._children) do
			if c.Name == name then return c end
		end
		return nil
	end
	function methods:FindFirstChildOfClass(cn)
		for _, c in ipairs(self._children) do
			if c.ClassName == cn then return c end
		end
		return nil
	end
	function methods:FindFirstAncestorOfClass(cn)
		local p = self.Parent
		while p do
			if p.ClassName == cn then return p end
			p = p.Parent
		end
		return nil
	end
	function methods:IsA(target)
		local cn = self.ClassName
		local seen = {}
		while cn and not seen[cn] do
			if cn == target or target == "Instance" then return true end
			seen[cn] = true
			cn = INHERIT[cn]
		end
		return target == "Instance"
	end
	function methods:GetFullName()
		local parts = { self.Name or "?" }
		local p = self.Parent
		while p do
			local n = (type(p) == "table") and p.Name or nil
			table.insert(parts, 1, n or "?")
			p = (type(p) == "table") and rawget(p, "Parent") or nil
		end
		return table.concat(parts, ".")
	end
	function methods:IsDescendantOf(ancestor)
		local p = self.Parent
		while p do
			if p == ancestor then return true end
			p = p.Parent
		end
		return false
	end
	function methods:IsAncestorOf(descendant)
		local p = descendant and descendant.Parent
		while p do
			if p == self then return true end
			p = p.Parent
		end
		return false
	end
	function methods:GetAttribute(name) return rawget(self._attrs, name) end
	function methods:SetAttribute(name, value)
		rawset(self._attrs, name, value)
		local ev = self._events["AttributeChanged"]
		if ev then ev:Fire() end
	end
	function methods:GetAttributes()
		local out = {}
		for k, v in pairs(self._attrs) do out[k] = v end
		return out
	end
	function methods:GetPropertyChangedSignal(prop)
		local key = "PC:" .. prop
		local ev = self._events[key]
		if not ev then
			ev = mkEvent((self.Name or "?") .. "." .. prop)
			self._events[key] = ev
		end
		return ev
	end
	function methods:Clone()
		local copy = Instance.new(self.ClassName)
		for k, v in pairs(self._props) do copy[k] = v end
		for k, v in pairs(self._attrs) do copy:SetAttribute(k, v) end
		for _, c in ipairs(self._children) do c:Clone().Parent = copy end
		return copy
	end
	function methods:Destroy()
		local ev = self._events["Destroying"]
		if ev then ev:Fire() end
		local old = rawget(self, "Parent")
		if old and old._children then
			for i = #old._children, 1, -1 do
				if old._children[i] == self then table.remove(old._children, i) end
			end
		end
		rawset(self, "Parent", nil)
	end
	function methods:WaitForChild(name)
		return methods.FindFirstChild(self, name)
	end
	function methods:ClearAllChildren()
		for i = #self._children, 1, -1 do self._children[i]:Destroy() end
	end
	function methods:Fire(...)
		local key = "Event"
		local ev = self._events[key]
		if not ev then
			ev = mkEvent("bindable@" .. tostring(self))
			self._events[key] = ev
		end
		ev:Fire(...)
	end
	function methods:Invoke() return nil end
	local Instance = {}
	local nextInstanceSerial = 0
	function Instance.new(className)
		nextInstanceSerial = nextInstanceSerial + 1
		local serial = nextInstanceSerial
		local obj = {
			_serial = serial,
			_children = {},
			_attrs = {},
			_events = {},
			-- Name/ClassName 走 _props 单通道：创建后再赋值不会与原始裸字段打架
			_props = {
				Name = className,
				ClassName = className,
				Visible = true,
				Transparency = 0,
				CanCollide = true,
				Anchored = false,
				Archivable = true,
				Position = Vector3.new(0, 0, 0),
				AbsoluteSize = Vector2.new(0, 0),
				AbsolutePosition = Vector2.new(0, 0),
			},
		}
		setmetatable(obj, {
			__index = function(t, k)
				if type(k) ~= "string" then return nil end
				if k == "Parent" then return rawget(t, "Parent") end
				if k == "_children" or k == "_events" or k == "_props" or k == "_attrs" or k == "_serial" then
					return rawget(t, k)
				end
				if methods[k] then return methods[k] end
				if AUTO_EVENTS[k] then
					local ev = t._events[k]
					if not ev then
						ev = mkEvent("i" .. tostring(rawget(t, "_serial")) .. ":" .. k)
						t._events[k] = ev
					end
					return ev
				end
				return rawget(t, "_props")[k]
			end,
			__newindex = function(t, k, v)
				if k == "Parent" then
					local old = rawget(t, "Parent")
					if old == v then return end
					if old and type(old) == "table" and old._children then
						for i = #old._children, 1, -1 do
							if old._children[i] == t then table.remove(old._children, i) end
						end
					end
					rawset(t, "Parent", v)
					if v and type(v) == "table" and v._children then
						table.insert(v._children, t)
						if v._events then
							if v._events["ChildAdded"] then v._events["ChildAdded"]:Fire(t) end
							if v._events["DescendantAdded"] then v._events["DescendantAdded"]:Fire(t) end
						end
						local p = v
						while p and type(p) == "table" do
							if p._events then
								if p._events["AncestryChanged"] then p._events["AncestryChanged"]:Fire(t, p) end
								if p ~= v and p._events["DescendantAdded"] then p._events["DescendantAdded"]:Fire(t) end
							end
							p = rawget(p, "Parent")
						end
					end
					local own = t._events["AncestryChanged"]
					if own then own:Fire(t, v) end
					return
				end
				rawget(t, "_props")[k] = v
				local ev = t._events["PC:" .. k]
				if ev then ev:Fire() end
				if t._events["Changed"] then t._events["Changed"]:Fire(k) end
			end,
		})
		return obj
	end

	-- ===== task（CLI 无 task 库；wait 必须 yield 防死循环）=====
	local taskStub = {}
	function taskStub.spawn(fn, ...)
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co, ...)
		if not ok then fail("task.spawn", err) end
		return co
	end
	taskStub.defer = taskStub.spawn
	function taskStub.wait(_t)
		if coroutine.isyieldable() then return coroutine.yield() end
		return 0
	end
	function taskStub.delay(_t, fn, ...)
		return taskStub.spawn(fn, ...)
	end
	function taskStub.cancel(co)
		if co and coroutine.status(co) ~= "dead" and coroutine.close then
			pcall(coroutine.close, co)
		end
	end
	function taskStub.synchronize() end
	function taskStub.desynchronize() end

	-- ===== 文件桩 =====
	local FILES = {}
	local function writefile(path, content)
		FILES[path] = tostring(content)
		return true
	end
	local function appendfile(path, content)
		FILES[path] = (FILES[path] or "") .. tostring(content)
		return true
	end

	-- ===== 渲染绑定命名空间 =====
	local bindings = {}

	-- ===== RunService =====
	local runService = {}
	function runService:BindToRenderStep(name, _prio, fn) bindings[name] = fn end
	function runService:UnbindFromRenderStep(name) bindings[name] = nil end
	setmetatable(runService, {
		__index = function(t, k)
			if type(k) ~= "string" then return nil end
			local ev = mkEvent("RS." .. k)
			rawset(t, k, ev)
			return ev
		end,
	})
	-- harness fireName 使用平名：与模块代码 connect 的是同一个事件对象
	local function rsEvent(name)
		local ev = rawget(runService, name)
		if not ev then
			ev = mkEvent(name)
			rawset(runService, name, ev)
		end
		return ev
	end
	local heartbeat = rsEvent("Heartbeat")
	local preSim = rsEvent("PreSimulation")
	local preRender = rsEvent("PreRender")
	local renderStepped = rsEvent("RenderStepped")
	local stepped = rsEvent("Stepped")

	-- ===== UIS =====
	local uiSlots = {}
	local UIS = {
		GetFocusedTextBox = function() return nil end,
		GetMouseLocation = function() return Vector2.new(0, 0) end,
		IsKeyDown = function() return false end,
		TouchEnabled = false,
		MouseEnabled = true,
		KeyboardEnabled = true,
		GamepadEnabled = false,
		MouseDeltaSensitivity = 1,
	}
	setmetatable(UIS, {
		__index = function(_t, k)
			if type(k) ~= "string" then return nil end
			local ev = mkEvent("UIS." .. k)
			uiSlots[k] = ev
			return ev
		end,
	})
	local function uiEvent(name)
		local ev = uiSlots[name]
		if not ev then
			ev = mkEvent(name)
			uiSlots[name] = ev
		end
		return ev
	end
	local inputBegan = uiEvent("InputBegan")
	local inputEnded = uiEvent("InputEnded")
	local inputChanged = uiEvent("InputChanged")
	local focusReleased = uiEvent("WindowFocusReleased")
	local jumpRequest = uiEvent("JumpRequest")

	-- ===== Camera / Lighting / Workspace =====
	local camera = {
		ViewportSize = Vector2.new(1920, 1080),
		CFrame = CFrame.new(),
		FieldOfView = 70,
		DiagonalFieldOfView = 90,
		MaxAxisFieldOfView = 70,
	}
	function camera:WorldToViewportPoint(pos)
		return { X = 960, Y = 540, Z = 10, InViewport = true }, Vector2.new(960, 540), Vector2.new(1920, 1080)
	end
	function camera:WorldToScreenPoint(pos)
		return { X = 960, Y = 540, Z = 10 }, Vector2.new(960, 540)
	end
	function camera:ViewportPointToRay(x, y)
		return { Origin = Vector3.new(x, y, 0), Direction = Vector3.new(0, 0, -1) }
	end
	function camera:GetPropertyChangedSignal(prop) return mkEvent("cameraPC:" .. prop) end

	local lighting = {
		Ambient = Color3.fromRGB(0, 0, 0),
		OutdoorAmbient = Color3.fromRGB(128, 128, 128),
		Brightness = 2,
		FogEnd = 100000,
		FogStart = 0,
		FogColor = Color3.fromRGB(192, 192, 192),
		GlobalShadows = true,
		TimeOfDay = "14:00:00",
	}
	function lighting:FindFirstChildOfClass(_cn) return nil end
	function lighting:FindFirstChild(_n) return nil end
	function lighting:GetChildren() return {} end
	function lighting:GetPropertyChangedSignal(prop) return mkEvent("lightingPC:" .. prop) end

	local soundService = {}
	function soundService:PlayLocalSound(_snd) end
	function soundService:GetPropertyChangedSignal(prop) return mkEvent("soundPC:" .. prop) end

	local workspaceStub = {
		_children = {},
		Name = "Workspace",
		ClassName = "Workspace",
		CurrentCamera = camera,
		Gravity = 196.2,
		DistributedGameTime = 0,
	}
	workspaceStub.DescendantAdded = mkEvent("ws.DescendantAdded")
	workspaceStub.DescendantRemoving = mkEvent("ws.DescendantRemoving")
	workspaceStub.ChildAdded = mkEvent("ws.ChildAdded")
	workspaceStub.ChildRemoved = mkEvent("ws.ChildRemoved")
	function workspaceStub:GetPropertyChangedSignal(prop) return mkEvent("wsPC:" .. prop) end
	function workspaceStub:GetChildren()
		local out = {}
		for _, c in ipairs(self._children) do table.insert(out, c) end
		return out
	end
	function workspaceStub:GetDescendants()
		local out = {}
		local function walk(n)
			for _, c in ipairs(n._children or {}) do
				table.insert(out, c)
				walk(c)
			end
		end
		walk(self)
		return out
	end
	function workspaceStub:FindFirstChild(name)
		for _, c in ipairs(self._children) do
			if c.Name == name then return c end
		end
		return nil
	end
	function workspaceStub:FindFirstChildOfClass(cn)
		for _, c in ipairs(self._children) do
			if c.ClassName == cn then return c end
		end
		return nil
	end
	function workspaceStub:Raycast(_origin, _dir, _params) return nil end
	function workspaceStub:GetPartBoundsInBox(_pos, _size, _params) return {} end
	function workspaceStub:GetPartBoundsInRadius(_pos, _r, _params) return {} end
	function workspaceStub:GetServerTimeNow() return os.time() end

	-- ===== 角色 =====
	local character = Instance.new("Model")
	character.Name = "Character"
	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.Health = 100
	humanoid.MaxHealth = 100
	humanoid.WalkSpeed = 16
	humanoid.JumpPower = 50
	humanoid.JumpHeight = 7.2
	humanoid.UseJumpPower = true
	humanoid.AutoRotate = true
	humanoid.SeatPart = nil
	humanoid.MoveDirection = Vector3.new(0, 0, 0)
	humanoid.RigType = enumRoot.HumanoidRigType.R6
	humanoid.Parent = character

	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.CFrame = CFrame.new(0, 3, 0)
	rootPart.Parent = character

	local headPart = Instance.new("Part")
	headPart.Name = "Head"
	headPart.CanCollide = false
	headPart.Size = Vector3.new(2, 1, 1)
	headPart.CFrame = CFrame.new(0, 4.5, 0)
	headPart.Parent = character

	-- ===== 玩家 =====
	local playerGui = Instance.new("PlayerGui")
	playerGui.Name = "PlayerGui"

	local leaderstatsBits = { Value = 1000 }
	local leaderstatsMult = { Value = 1 }
	local leaderstats = {
		FindFirstChild = function(_self, name)
			if name == "Bits" then return leaderstatsBits end
			if name == "Multiplier" then return leaderstatsMult end
			return nil
		end,
	}
	local playerAttrs = {}
	local playerEvents = {}
	local player = {
		Name = "TestPlayer",
		UserId = 123456789,
		DisplayName = "TestPlayer",
		AccountAge = 100,
		Team = nil,
		TeamColor = nil,
		Character = nil,
		CharacterAdded = mkEvent("CharacterAdded"),
		CharacterRemoving = mkEvent("CharacterRemoving"),
		PlayerGui = playerGui,
	}
	function player:FindFirstChild(name)
		if name == "leaderstats" then return leaderstats end
		if name == "PlayerGui" then return playerGui end
		return nil
	end
	function player:FindFirstChildOfClass(cn)
		if cn == "PlayerGui" then return playerGui end
		return nil
	end
	function player:GetAttribute(name) return playerAttrs[name] end
	function player:SetAttribute(name, value) playerAttrs[name] = value end
	function player:GetPropertyChangedSignal(prop)
		local key = "playerPC:" .. prop
		local ev = playerEvents[key]
		if not ev then
			ev = mkEvent(key)
			playerEvents[key] = ev
		end
		return ev
	end
	function player:GetMouse()
		return { Hit = CFrame.new(), Target = nil }
	end
	function player:GetNetworkPing() return 0.03 end
	function player:IsDescendantOf(v) return v ~= nil end
	function player:WaitForChild(name)
		if name == "PlayerGui" then return playerGui end
		return nil
	end

	local players = { LocalPlayer = player }
	function players:GetPlayers() return { player } end
	function players:GetPlayerFromCharacter(ch) if ch == character then return player end return nil end
	players.PlayerAdded = mkEvent("PlayerAdded")
	players.PlayerRemoving = mkEvent("PlayerRemoving")

	local teams = {}
	function teams:GetTeams()
		return {
			{ Name = "Red", TeamColor = Color3.fromRGB(255, 0, 0) },
			{ Name = "Blue", TeamColor = Color3.fromRGB(0, 0, 255) },
		}
	end

	local coreGui = Instance.new("CoreGui")
	coreGui.Name = "CoreGui"

	local replicatedStorage = Instance.new("ReplicatedStorage")
	local spawnBitRemote = {
		Name = "SpawnBit",
		FireServer = function(_self, ...) return nil end,
		OnClientEvent = mkEvent("SpawnBit.OnClientEvent"),
	}
	table.insert(replicatedStorage._children, spawnBitRemote)

	-- Collector（brick 需要）
	local collector = Instance.new("Part")
	collector.Name = "Collector"
	collector.Anchored = true
	collector.CFrame = CFrame.new(10, 0, 10)
	collector:SetAttribute("UserId", player.UserId)
	collector.Parent = workspaceStub

	-- ===== game =====
	local statsService = {}
	function statsService:GetPerformanceStats() return {} end
	function statsService:GetTotalMemoryUsageMb() return 512 end
	function statsService:GetPropertyChangedSignal(prop) return mkEvent("statsPC:" .. prop) end
	statsService.Heartbeat = mkEvent("Stats.Heartbeat")

	local tweenService = {}
	function tweenService:Create(_obj, _info, _props)
		return {
			Play = function() end,
			Cancel = function() end,
			Pause = function() end,
			Completed = mkEvent("tween.Completed"),
		}
	end
	function tweenService:GetValue(_alpha, _start, _goal, _unit) return 0 end

	local vimService = {}
	function vimService:SendKeyEvent(_a, _b, _c, _d) end
	function vimService:SendMouseButtonEvent(_a, _b, _c, _d, _e) end
	function vimService:SendTouchEvent(_a, _b, _c) end

	local guiService = {}
	function guiService:GetGuiInset()
		return Vector3.new(0, 36, 0), Vector3.new(0, 0, 0)
	end
	function guiService:GetGuiInsetInPixels()
		return Vector3.new(0, 36, 0), Vector3.new(0, 0, 0)
	end
	function guiService:IsTenFootInterface() return false end
	function guiService:MenuIsOpen() return false end

	local game = {
		PlaceId = 0,
		JobId = "smoke-job",
		MaxPlayers = 30,
		Loaded = true,
		Players = players,
		Workspace = workspaceStub,
		workspace = workspaceStub,
		ReplicatedStorage = replicatedStorage,
		Lighting = lighting,
		SoundService = soundService,
		CoreGui = coreGui,
		RunService = runService,
		UserInputService = UIS,
		Teams = teams,
		Stats = statsService,
		TweenService = tweenService,
		VirtualInputManager = vimService,
		GuiService = guiService,
	}
	function game:GetService(name)
		local svc = self[name]
		if svc == nil then
			fail("GetService: unknown " .. tostring(name))
			svc = {}
			self[name] = svc
		end
		return svc
	end

	return {
		bindings = bindings,
		mkEvent = mkEvent,
		EVENTS = EVENTS,
		FILES = FILES,
		writefile = writefile,
		appendfile = appendfile,
		taskStub = taskStub,
		enumRoot = enumRoot,
		Vector3 = Vector3,
		Vector2 = Vector2,
		CFrame = CFrame,
		UDim = UDim,
		UDim2 = UDim2,
		Color3 = Color3,
		RaycastParams = RaycastParams,
		OverlapParams = OverlapParams,
		Instance = Instance,
		game = game,
		workspace = workspaceStub,
		players = players,
		player = player,
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
		headPart = headPart,
		camera = camera,
		lighting = lighting,
		UIS = UIS,
		runService = runService,
		heartbeat = heartbeat,
		preSim = preSim,
		preRender = preRender,
		renderStepped = renderStepped,
		stepped = stepped,
		inputBegan = inputBegan,
		inputEnded = inputEnded,
		inputChanged = inputChanged,
		focusReleased = focusReleased,
		jumpRequest = jumpRequest,
		coreGui = coreGui,
		replicatedStorage = replicatedStorage,
		collector = collector,
	}
end

local E = buildEnv()

-- ===== 裸全局导出（CLI 的 _G 冻结，只能写裸名）=====
game = E.game
workspace = E.workspace
Instance = E.Instance
Enum = E.enumRoot
Vector3 = E.Vector3
Vector2 = E.Vector2
CFrame = E.CFrame
UDim = E.UDim
UDim2 = E.UDim2
Color3 = E.Color3
RaycastParams = E.RaycastParams
OverlapParams = E.OverlapParams
task = E.taskStub
writefile = E.writefile
appendfile = E.appendfile

local EVENTS = E.EVENTS
local FILES = E.FILES
local bindings = E.bindings

local function fireName(name, ...)
	local ev = EVENTS[name]
	if not ev then
		fail("no event: " .. name)
		return
	end
	ev:Fire(...)
end

------------------------------------------------------------------ 加载被测代码
--@SOURCES@

local ORDER = { "kit", "moc", "sibs", "plane", "drift", "log", "brick" }

local function loadOne(name)
	local src = SOURCES[name]
	if not src then
		fail("no source: " .. name)
		return false
	end
	local chunk, err = loadstring(src, "@" .. name .. ".lua")
	if not chunk then
		fail("compile: " .. name, err)
		return false
	end
	local ok, e = pcall(chunk)
	if not ok then
		fail("load: " .. name, e)
		return false
	end
	return true
end

local function sanity(tag)
	if type(KIT) ~= "table" then fail(tag .. ": KIT not global") return end
	if type(KIT_CLEAN_ALL) ~= "function" then fail(tag .. ": KIT_CLEAN_ALL missing") end
	if not KIT.debugRegistry or not KIT.debugRegistry["KIT"] then fail(tag .. ": KIT debug not registered") end
end

local function runDebugAll(tag)
	local K = KIT
	if not (K and K.runDebug and K.debugRegistry) then fail(tag .. ": no runDebug") return end
	local ids = {}
	for id in pairs(K.debugRegistry) do table.insert(ids, id) end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local ok, out, extra = pcall(K.runDebug, id)
		if not ok then
			fail(tag .. " debug:" .. id, out)
		elseif out == false then
			fail(tag .. " debug:" .. id, extra)
		else
			print(("  debug %-9s -> %s"):format(id, tostring(out):sub(1, 72)))
		end
	end
end

local function cleanAll(tag)
	if type(KIT_CLEAN_ALL) ~= "function" then fail(tag .. ": KIT_CLEAN_ALL missing") return end
	local ok, err = pcall(KIT_CLEAN_ALL)
	if not ok then fail(tag .. " cleanAll", err) end
end

local function pulse(rounds)
	for _ = 1, rounds do
		local fns = {}
		for _, fn in pairs(bindings) do table.insert(fns, fn) end
		for _, fn in ipairs(fns) do
			local ok, err = pcall(fn, 0.016)
			if not ok then fail("renderBinding", err) break end
		end
		fireName("Heartbeat", 0.016, os.clock())
		fireName("PreSimulation", 0.016, os.clock())
		fireName("PreRender", 0.016, os.clock())
		busy(0.016) -- 真实时钟推进：fps 分层 (0.1s / 0.5s) 才能触发
	end
end

local function countHandlers()
	local n = 0
	local names = {}
	for name, ev in pairs(EVENTS) do
		if #ev._handlers > 0 then
			n = n + #ev._handlers
			table.insert(names, name .. "×" .. #ev._handlers)
		end
	end
	return n, names
end

local totalStart = os.clock()

print("== SMOKE 1/2: 加载 ==")
for _, name in ipairs(ORDER) do
	loadOne(name)
end
sanity("round1")
if type(KIT) == "table" and KIT.debugRegistry then
	local ids = {}
	for id in pairs(KIT.debugRegistry) do table.insert(ids, id) end
	table.sort(ids)
	print("  registry: " .. table.concat(ids, ", "))
end

print("== SMOKE 2/2: 场景 ==")
E.player.Character = E.character
E.character.Parent = E.workspace
fireName("CharacterAdded", E.character)

pulse(40)

fireName("WindowFocusReleased")
local fakeTouch = {
	UserInputType = Enum.UserInputType.Touch,
	Position = Vector2.new(100, 200),
	KeyCode = Enum.KeyCode.Unknown,
	UserInputState = Enum.UserInputState.End,
}
fireName("InputEnded", fakeTouch)
fireName("JumpRequest")
pulse(3)

runDebugAll("round1")
local nFiles = 0
for _ in pairs(FILES) do nFiles = nFiles + 1 end
print(("  config files: %d, elapsed %.2fs"):format(nFiles, os.clock() - totalStart))

print("== cleanAll round1 ==")
cleanAll("round1")

print("== SMOKE extra: 热重载 (kit+moc) ==")
loadOne("kit")
loadOne("moc")
sanity("round2")
fireName("CharacterAdded", E.character)
pulse(4)
runDebugAll("round2")
cleanAll("round2")

local residueN, residueNames = countHandlers()
print(("== 残留: handlers=%d [%s] bindings=%d"):format(
	residueN,
	table.concat(residueNames, ", "),
	(function()
		local n = 0
		for _ in pairs(bindings) do n = n + 1 end
		return n
	end)()
))

if #ERRORS > 0 then
	error(("SMOKE FAILED (%d)"):format(#ERRORS), 0)
end
print("SMOKE OK")
