-- kit.lua — KIT v10 单文件 bundle（由 build.py 生成，勿直接编辑）
-- 源: src/kit/00-head.lua, src/kit/10-core.lua, src/kit/20-cfg.lua, src/kit/30-input.lua, src/kit/40-bag.lua, src/kit/50-force.lua, src/kit/60-watch.lua, src/kit/70-ui.lua, src/kit/80-draw.lua, src/kit/90-lifecycle.lua, src/kit/95-hud.lua, src/kit/99-esp.lua
-- 构建: python3 build.py

-- ==== src/kit/00-head.lua ====
-- kit / 00-head — 服务引用、GUI 根、旧实例清理、绘制后端探测
-- 约定：缩进用单个 Tab；所有 *Alpha 字段按"透明度"理解（0 不透明，1 全透明）

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local NAME = "KIT"
local VERSION = 10

-- 0. GUI 根节点

local function getGuiRoot()
	if gethui then
		local ok, root = pcall(gethui)
		if ok and root then return root end
	end
	return CoreGui
end
local GuiRoot = getGuiRoot()

-- 1. 清理旧实例
-- 同版本重跑只清自己（各模块由自己的 K.mod 负责，不误杀兄弟脚本）；
-- 跨版本升级或首次运行时，额外清理历史遗留的 GUI 名。

local OWN_GUI_NAMES = {NAME, NAME .. "Text", "KIT_Toast"}
local LEGACY_GUI_NAMES = {
	"MinimalStats", "MinimalStatsText", "SIBS", "SIBS_List", "SIBS_Steer",
	"MOC", "DRIFT", "KITLOG", "PLANE",
}

local prevKIT = _G.KIT
local prevClean = _G.KIT_CLEAN_ALL
local needLegacyClean = (type(prevKIT) ~= "table") or (prevKIT.ver ~= VERSION)

if prevClean then pcall(prevClean) end

local function destroyGuis(names)
	for _, n in ipairs(names) do
		local old = GuiRoot:FindFirstChild(n)
		if old then pcall(function() old:Destroy() end) end
	end
end
destroyGuis(OWN_GUI_NAMES)
if needLegacyClean then destroyGuis(LEGACY_GUI_NAMES) end

-- 2. 绘制后端探测

local HAS_DRAWING = (type(Drawing) == "table") and (type(Drawing.new) == "function")

local function tryDrawing(className)
	if not HAS_DRAWING then return nil end
	local ok, obj = pcall(Drawing.new, className)
	if ok and obj then return obj end
	return nil
end

-- ==== src/kit/10-core.lua ====
-- kit / 10-core — K 表、环境探测、错误守卫、调试注册、主题、基础工具

-- 3. K 核心

local K = {ver = VERSION, modules = {}, debugRegistry = {}, DEBUG_MODE = false, quietDump = false, errors = {}}
_G.KIT = K

K.env = {
	isMobile = UIS.TouchEnabled,
	hasDrawing = HAS_DRAWING,
	hasGethui = type(gethui) == "function",
	hasWritefile = type(writefile) == "function",
	hasReadfile = type(readfile) == "function",
	hasIsfile = type(isfile) == "function",
	hasAppendfile = type(appendfile) == "function",
	hasKeypress = type(keypress) == "function" and type(keyrelease) == "function",
	hasVIM = pcall(function() game:GetService("VirtualInputManager") end),
}

local FONT_BOLD = {"BuilderSansBold", "GothamBold", "SourceSansBold"}
local FONT_REG = {"BuilderSans", "Gotham", "SourceSans"}
local function pickFont(names)
	for _, n in ipairs(names) do
		local ok, f = pcall(function() return Enum.Font[n] end)
		if ok and f then return f end
	end
	return Enum.Font.SourceSans
end
function K.font(bold) return pickFont(bold and FONT_BOLD or FONT_REG) end

K.Col = {
	On = Color3.fromRGB(38, 125, 85), Off = Color3.fromRGB(48, 50, 60),
	Accel = Color3.fromRGB(30, 85, 115), Decel = Color3.fromRGB(130, 90, 40),
	Danger = Color3.fromRGB(155, 45, 45), Stop = Color3.fromRGB(155, 45, 45),
	Push = Color3.fromRGB(155, 45, 45), Bind = Color3.fromRGB(95, 65, 135),
	Good = Color3.fromRGB(135, 215, 155), Bad = Color3.fromRGB(225, 135, 135),
	Wait = Color3.fromRGB(170, 175, 185),
}
-- 所有面板共享的默认配置；模块用 K.mod(name, overrides) 只写差异项
K.THEME = {
	Alpha = 0.72, BG = Color3.fromRGB(20, 22, 28), DragTol = 4,
	TitleH = 20, RowH = 30,
	Text = Color3.fromRGB(210, 215, 225), TextWhite = Color3.fromRGB(245, 248, 255),
	Font = K.font(true), Col = K.Col,
	DisplayOrder = 99995, PanelW = 120,
}

-- 错误守卫：pcall + 环形错误表（最多 50 条）
function K.guard(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		K.errors[#K.errors + 1] = {t = os.clock(), m = tostring(name), e = tostring(err)}
		if #K.errors > 50 then table.remove(K.errors, 1) end
		if K.DEBUG_MODE then warn("[KIT:" .. tostring(name) .. "] " .. tostring(err)) end
	end
	return ok, err
end

function K.getErrors(moduleName)
	if not moduleName then return K.errors end
	local out = {}
	for _, e in ipairs(K.errors) do
		if e.m == moduleName then out[#out + 1] = e end
	end
	return out
end

-- 调试：registerDebug 注册取数函数；debugDump 输出到文件或控制台
function K.registerDebug(moduleName, fn) K.debugRegistry[tostring(moduleName)] = fn end

function K.debugDump(title, lines, saveFile)
	local dump = "=== " .. tostring(title) .. " ===\n" .. table.concat(lines, "\n") .. "\n=== END ==="
	if K.quietDump then return dump, false end
	local saved = false
	if saveFile ~= false and K.env.hasWritefile then
		saved = pcall(function() writefile(tostring(title) .. "_Debug.txt", dump) end)
	end
	if saved then
		print("[KIT] debug → " .. tostring(title) .. "_Debug.txt")
	else
		print(dump)
	end
	return dump, saved
end

function K.runDebug(moduleName)
	local fn = K.debugRegistry[tostring(moduleName)]
	if type(fn) == "function" then return pcall(fn) end
	return false
end

function K.debugAll()
	local parts, names = {}, {}
	for n in pairs(K.debugRegistry) do names[#names + 1] = n end
	table.sort(names)
	local prev = K.quietDump
	K.quietDump = true
	for _, n in ipairs(names) do
		local ok, dump = pcall(K.debugRegistry[n])
		if ok and type(dump) == "string" then
			parts[#parts + 1] = dump
		else
			parts[#parts + 1] = "=== " .. n .. " ===\nERROR\n=== END ==="
		end
	end
	K.quietDump = prev
	local text = table.concat(parts, "\n\n")
	local saved = false
	if K.env.hasWritefile then
		saved = pcall(function() writefile("KIT_DebugAll.txt", text) end)
	end
	if saved then
		print("[KIT] debugAll → KIT_DebugAll.txt")
	else
		print(text)
	end
	return text
end

-- 5. 基础工具

function K.mk(class, props, parent)
	local obj = Instance.new(class)
	if props then
		for k, v in pairs(props) do pcall(function() obj[k] = v end) end
	end
	if parent then pcall(function() obj.Parent = parent end) end
	return obj
end

function K.isP(input)
	return input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1
end

function K.getRoot(char)
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Root")
end

function K.vp()
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1920, 1080)
end

function K.isTyping() return UIS:GetFocusedTextBox() ~= nil end
function K.hasKeyboard() return UIS.KeyboardEnabled == true end

function K.keyDown(code)
	return UIS.KeyboardEnabled and not K.isTyping() and UIS:IsKeyDown(code)
end

function K.toggleText(base, on) return tostring(base) .. " " .. (on and "开" or "关") end

function K.safeFullName(inst)
	if not inst then return "nil" end
	local ok, r = pcall(function() return inst:GetFullName() end)
	return ok and r or tostring(inst)
end

function K.dtTracker(maxDt)
	maxDt = maxDt or 0.1
	local last = os.clock()
	return function(step)
		local now = os.clock()
		local dt = step
		if type(dt) ~= "number" or dt ~= dt or dt <= 0 then dt = now - last end
		last = now
		return math.clamp(dt, 0, maxDt)
	end
end

function K.flat(v) return Vector3.new(v.X, 0, v.Z) end

function K.flatUnit(v, fallback)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude > 1e-3 then return f.Unit end
	return fallback or Vector3.zero
end

function K.countTable(t)
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

-- ==== src/kit/20-cfg.lua ====
-- kit / 20-cfg — 持久化配置（跨重跑共享存储 + 防抖落盘）

-- 4. 配置
-- 用 _G.KIT_CFG_STORE 共享存储，开关状态跨重跑保留；
-- cleanAll 时冻结并同步落盘，避免旧实例的延迟回调在新实例加载后覆盖配置。

local CONFIG_FILE = "KIT_Config.txt"
local CONFIG_MAGIC = "KITCFG2"

local CFG = _G.KIT_CFG_STORE
if type(CFG) ~= "table" then
	CFG = {cache = {}, loaded = false, dirty = false, pending = false, frozen = false}
	_G.KIT_CFG_STORE = CFG
end
CFG.frozen = false

local function cfgLoad()
	if CFG.loaded then return end
	CFG.loaded = true
	if not (K.env.hasReadfile and K.env.hasIsfile) then return end
	local okE, exists = pcall(isfile, CONFIG_FILE)
	if not okE or not exists then return end
	local okR, content = pcall(readfile, CONFIG_FILE)
	if not okR or type(content) ~= "string" then return end
	local first = true
	for line in content:gmatch("[^\r\n]+") do
		if first then
			first = false
			if line ~= CONFIG_MAGIC then return end
		else
			local k, t, v = line:match("^(.-)\t(.-)\t(.*)$")
			if k and t and k ~= "" then
				if t == "b" then
					CFG.cache[k] = (v == "1")
				elseif t == "n" then
					CFG.cache[k] = tonumber(v)
				elseif t == "s" then
					CFG.cache[k] = v
				end
			end
		end
	end
end

local function cfgFlush()
	if CFG.frozen then return end
	if not K.env.hasWritefile then return end
	local keys, lines = {}, {CONFIG_MAGIC}
	for k in pairs(CFG.cache) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local v = CFG.cache[k]
		local t = type(v)
		if t == "boolean" then
			lines[#lines + 1] = k .. "\tb\t" .. (v and "1" or "0")
		elseif t == "number" then
			lines[#lines + 1] = k .. "\tn\t" .. string.format("%.17g", v)
		elseif t == "string" then
			lines[#lines + 1] = k .. "\ts\t" .. v
		end
	end
	pcall(writefile, CONFIG_FILE, table.concat(lines, "\n"))
	CFG.dirty = false
end
CFG.flush = cfgFlush

K.cfg = {}
function K.cfg.get(key, default)
	cfgLoad()
	local v = CFG.cache[key]
	if v ~= nil then return v end
	return default
end

function K.cfg.set(key, value)
	if CFG.frozen then return end
	cfgLoad()
	if value == nil then
		CFG.cache[key] = nil
	else
		CFG.cache[key] = value
	end
	CFG.dirty = true
	if not CFG.pending then
		CFG.pending = true
		task.delay(0.5, function()
			CFG.pending = false
			if CFG.dirty then cfgFlush() end
		end)
	end
end

function K.cfg.flush()
	if CFG.dirty then cfgFlush() end
end

-- 带模块前缀的快捷方式（模块配置键 = 模块名 .. 键名）
function K.loadPrefixed(module, key, default)
	return K.cfg.get(tostring(module) .. tostring(key), default)
end

function K.loadPrefixedNumber(module, key, default)
	local v = K.loadPrefixed(module, key, default)
	if typeof(v) == "number" and v == v then return v end
	return default
end

function K.savePrefixed(module, key, value)
	K.cfg.set(tostring(module) .. tostring(key), value)
end

-- ==== src/kit/30-input.lua ====
-- kit / 30-input — 键盘 / 手柄 / 触摸统一输入层

-- 6. 输入层
-- forwardStates/sideStates/verticalStates 返回 (a, b) 布尔对，
-- flags 用于把触摸按钮等外部状态并入判定。

K.input = {}

local function anyKeyDown(...)
	for i = 1, select("#", ...) do
		if K.keyDown(select(i, ...)) then return true end
	end
	return false
end

function K.input.forwardStates(flags)
	local w = anyKeyDown(Enum.KeyCode.W, Enum.KeyCode.Up) or (flags and flags.w == true)
	local s = anyKeyDown(Enum.KeyCode.S, Enum.KeyCode.Down) or (flags and flags.s == true)
	return w == true, s == true
end

function K.input.sideStates(flags)
	local d = anyKeyDown(Enum.KeyCode.D, Enum.KeyCode.Right) or (flags and flags.d == true)
	local a = anyKeyDown(Enum.KeyCode.A, Enum.KeyCode.Left) or (flags and flags.a == true)
	return d == true, a == true
end

function K.input.verticalStates(flags)
	local up = anyKeyDown(Enum.KeyCode.Space, Enum.KeyCode.E) or (flags and flags.up == true)
	local down = anyKeyDown(Enum.KeyCode.LeftShift, Enum.KeyCode.Q) or (flags and flags.down == true)
	return up == true, down == true
end

function K.input.forward(flags)
	local w, s = K.input.forwardStates(flags)
	return (w and 1 or 0) - (s and 1 or 0)
end

function K.input.side(flags)
	local d, a = K.input.sideStates(flags)
	return (d and 1 or 0) - (a and 1 or 0)
end

function K.input.vertical(flags)
	local up, down = K.input.verticalStates(flags)
	return math.clamp((up and 1 or 0) - (down and 1 or 0), -1, 1)
end

function K.input.stick()
	local ok, state = pcall(function() return UIS:GetGamepadState(Enum.UserInputType.Gamepad1) end)
	if not ok or not state then return nil end
	for _, input in ipairs(state) do
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			return Vector3.new(input.Position.X, 0, input.Position.Y)
		end
	end
	return nil
end

-- 摇杆方向换算到相机平面（返回世界水平方向）
function K.input.stickDir(deadzone)
	local s = K.input.stick()
	if not s or s.Magnitude < (deadzone or 0.15) then return Vector3.zero end
	local cam = workspace.CurrentCamera
	local cf = cam and cam.CFrame
	local look, right
	if cf then
		look = K.flatUnit(cf.LookVector, Vector3.new(0, 0, 1))
		right = K.flatUnit(cf.RightVector, Vector3.new(1, 0, 0))
	else
		look, right = Vector3.new(0, 0, 1), Vector3.new(1, 0, 0)
	end
	local dir = look * s.Z + right * s.X
	if dir.Magnitude > 1e-3 then return dir.Unit end
	return Vector3.zero
end

-- ==== src/kit/40-bag.lua ====
-- kit / 40-bag — 连接袋（统一注册/断开事件连接，随模块卸载清理）

-- 7. 连接袋

function K.bag()
	local conns, alive = {}, true
	return {
		reg = function(c)
			if not c then return c end
			if not alive then
				pcall(function() c:Disconnect() end)
				return c
			end
			conns[#conns + 1] = c
			return c
		end,
		unreg = function(c)
			if not c then return end
			pcall(function() c:Disconnect() end)
			for i = #conns, 1, -1 do
				if conns[i] == c then
					conns[i] = conns[#conns]
					conns[#conns] = nil
					break
				end
			end
		end,
		alive = function() return alive end,
		clear = function()
			if not alive then return end
			alive = false
			for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
			table.clear(conns)
		end,
	}
end

-- ==== src/kit/50-force.lua ====
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

-- ==== src/kit/60-watch.lua ====
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

-- ==== src/kit/70-ui.lua ====
-- kit / 70-ui — 面板工厂、拖拽、标题栏、输入行、按钮、按住按钮、toast

-- 11. UI 工厂

local function encodePanelPos(pos)
	return string.format("%.6f,%.0f,%.6f,%.0f", pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset)
end

local function decodePanelPos(s)
	if typeof(s) ~= "string" then return nil end
	local sx, ox, sy, oy = s:match("^([%-%d%.]+),([%-%d]+),([%-%d%.]+),([%-%d]+)$")
	if not sx then return nil end
	return {(tonumber(sx) or 0), (tonumber(ox) or 0), (tonumber(sy) or 0), (tonumber(oy) or 0)}
end

-- 面板位置安全区：顶部留出这段，防止标题栏被拖出/存出可点区（手机状态栏/顶栏手势区）
local SAFE_TOP = 48
K.SAFE_TOP = SAFE_TOP
K.collapsedState = K.collapsedState or {}

-- 带容差的拖拽；松手后把位置写进配置（key = ScreenGui.Name）
function K.drag(handle, frame, bag, tolerance)
	tolerance = tolerance or 4
	local dragging, moved = false, false
	local origin = Vector3.zero
	local base = UDim2.new()

	local function savePanelPos()
		local gui = frame:FindFirstAncestorOfClass("ScreenGui")
		if not gui then return end
		K.cfg.set("UI.Pos." .. gui.Name, encodePanelPos(frame.Position))
	end

	bag.reg(handle.InputBegan:Connect(function(input)
		if not K.isP(input) then return end
		dragging, moved = true, false
		origin = input.Position
		base = frame.Position
	end))
	bag.reg(UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local delta = input.Position - origin
		if math.abs(delta.X) + math.abs(delta.Y) > tolerance then moved = true end
		local vp = K.vp()
		local size = frame.AbsoluteSize
		local minX = -base.X.Scale * vp.X
		local maxX = vp.X - size.X - base.X.Scale * vp.X
		if minX > maxX then minX, maxX = maxX, minX end
		local minY = -base.Y.Scale * vp.Y + SAFE_TOP
		local maxY = vp.Y - size.Y - base.Y.Scale * vp.Y
		if minY > maxY then minY, maxY = maxY, minY end
		frame.Position = UDim2.new(
			base.X.Scale, math.clamp(base.X.Offset + delta.X, minX, maxX),
			base.Y.Scale, math.clamp(base.Y.Offset + delta.Y, minY, maxY)
		)
	end))
	local function release()
		if not dragging then return end
		dragging = false
		if moved then savePanelPos() end
	end
	bag.reg(UIS.InputEnded:Connect(function(input)
		if K.isP(input) then release() end
	end))
	bag.reg(UIS.WindowFocusReleased:Connect(release))
	return function()
		local r = moved
		moved = false
		return r
	end
end

-- 面板容器（恢复保存过的位置）。返回 ScreenGui, 主 Frame。
function K.panel(name, config, bag)
	local gui = K.mk("ScreenGui", {
		Name = name, ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = config.DisplayOrder,
	}, GuiRoot)
	local main = K.mk("Frame", {
		Size = config.PanelSize, Position = config.PanelPos,
		BackgroundColor3 = config.BG, BackgroundTransparency = config.Alpha,
		BorderSizePixel = 0, Active = true, ClipsDescendants = true,
	}, gui)
	local saved = decodePanelPos(K.cfg.get("UI.Pos." .. name, nil))
	if saved then
		main.Position = UDim2.new(saved[1], saved[2], saved[3], saved[4])
	end
	-- 无论默认还是恢复的位置都收进安全区（顶部 ≥ SAFE_TOP），标题栏永远点得到
	do
		local vp = K.vp()
		local w = config.PanelSize.X.Scale * vp.X + config.PanelSize.X.Offset
		local h = config.PanelSize.Y.Scale * vp.Y + config.PanelSize.Y.Offset
		local absX = main.Position.X.Scale * vp.X + main.Position.X.Offset
		local absY = main.Position.Y.Scale * vp.Y + main.Position.Y.Offset
		local cx = math.clamp(absX, 0, math.max(vp.X - w, 0))
		local cy = math.clamp(absY, SAFE_TOP, math.max(vp.Y - h, SAFE_TOP))
		main.Position = UDim2.new(main.Position.X.Scale, cx - main.Position.X.Scale * vp.X,
			main.Position.Y.Scale, cy - main.Position.Y.Scale * vp.Y)
	end
	return gui, main
end

-- 可折叠标题栏（点击折叠/展开，拖动与点击用 moved 区分）
function K.titleBar(main, config, bag, title, height)
	height = height or 20
	local button = K.mk("TextButton", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = config.BG or K.THEME.BG,
		BackgroundTransparency = 1, -- 标题栏背景全透明：不叠色、无接缝，保留面板透明风格
		BorderSizePixel = 0, Active = true, Text = title .. " [-]",
		TextColor3 = Color3.new(1, 1, 1), TextSize = 13, Font = config.Font or K.THEME.Font,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, main)
	local dragMoved = K.drag(button, main, bag, config.DragTol)
	local collapsed = false
	K.collapsedState[main] = false
	local collapseSize = config.CollapseSize
		or UDim2.new(config.PanelSize.X.Scale, config.PanelSize.X.Offset, 0, height)
	bag.reg(button.Activated:Connect(function()
		if dragMoved() then return end
		collapsed = not collapsed
		K.collapsedState[main] = collapsed
		button.Text = title .. (collapsed and " [+]" or " [-]")
		main.Size = collapsed and collapseSize or config.PanelSize
	end))
	return button
end

function K.numBox(box, bag, get, set)
	bag.reg(box.FocusLost:Connect(function()
		local value = tonumber(box.Text)
		if value and set then set(value) end
		if get then box.Text = tostring(get()) end
	end))
end

-- "标签 + 数值输入" 行
function K.fullInput(parent, y, rowH, labelText, color, get, set, bag, cfg)
	cfg = cfg or K.THEME
	local row = K.mk("Frame", {
		Size = UDim2.new(1, 0, 0, rowH), Position = UDim2.new(0, 0, 0, y),
		BackgroundTransparency = 1,
	}, parent)
	K.mk("TextLabel", {
		Size = UDim2.new(0.5, 0, 1, 0), BackgroundColor3 = cfg.BG, BackgroundTransparency = cfg.Alpha,
		BorderSizePixel = 0, Text = labelText, TextColor3 = cfg.TextWhite, TextSize = 11, Font = cfg.Font,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, row)
	local input = K.mk("TextBox", {
		Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundColor3 = cfg.BG, BackgroundTransparency = cfg.Alpha, BorderSizePixel = 0,
		Text = tostring(get and get() or ""), TextColor3 = cfg.TextWhite, TextSize = 11, Font = cfg.Font,
		ClearTextOnFocus = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, row)
	K.numBox(input, bag, get, set)
	return input, row
end

-- TextButton 快捷创建：填充通用默认（透明背景、白字、居中）
function K.btn(parent, props, cfg)
	cfg = cfg or K.THEME
	local merged = {
		BackgroundTransparency = cfg.Alpha,
		BorderSizePixel = 0,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 11,
		Font = cfg.Font,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	}
	for k, v in pairs(props or {}) do merged[k] = v end
	return K.mk("TextButton", merged, parent)
end

-- TextLabel 快捷创建（透明背景、居中）
function K.label(parent, props, cfg)
	cfg = cfg or K.THEME
	local merged = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = cfg.Font,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	}
	for k, v in pairs(props or {}) do merged[k] = v end
	return K.mk("TextLabel", merged, parent)
end

-- 网格按钮（点击回调拿到按钮自身；Base 属性记录底色，便于"关"时还原）
function K.mkBtn(grid, text, color, order, onClick, bag, cfg, textSize)
	cfg = cfg or K.THEME
	local button = K.btn(grid, {
		BackgroundColor3 = color,
		Text = text,
		TextSize = textSize or 11,
		LayoutOrder = order,
	}, cfg)
	button:SetAttribute("Base", color)
	bag.reg(button.Activated:Connect(function() onClick(button) end))
	return button
end

-- 半宽按钮（x 为 0/0.5 的缩放位）
function K.halfButton(parent, text, x, y, color, h, cfg)
	cfg = cfg or K.THEME
	return K.btn(parent, {
		Size = UDim2.new(0.5, 0, 0, h),
		Position = UDim2.new(x, 0, 0, y),
		BackgroundColor3 = color,
		Text = text,
	}, cfg)
end

-- 开关按钮 + 数值输入 组合行。返回 (button, input, apply)，
-- apply(state) 可从外部（如角色重绑）同步开关状态。
function K.makeToggleRow(parent, y, rowH, toggleLabel, defaultVal, onToggle, get, set, bag, cfg)
	cfg = cfg or K.THEME
	local col = cfg.Col or K.THEME.Col
	local row = K.mk("Frame", {
		Size = UDim2.new(1, 0, 0, rowH), Position = UDim2.new(0, 0, 0, y),
		BackgroundTransparency = 1,
	}, parent)
	local button = K.mk("TextButton", {
		Size = UDim2.new(0.5, 0, 1, 0), BackgroundColor3 = defaultVal == true and col.On or col.Off,
		BackgroundTransparency = cfg.Alpha, BorderSizePixel = 0,
		Text = K.toggleText(toggleLabel, defaultVal == true), TextColor3 = Color3.new(1, 1, 1),
		TextSize = 11, Font = cfg.Font,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, row)
	local inputFrame = K.mk("Frame", {
		Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundColor3 = cfg.BG, BackgroundTransparency = cfg.Alpha, BorderSizePixel = 0,
	}, row)
	local input = K.mk("TextBox", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
		TextColor3 = cfg.TextWhite, Text = tostring(get and get() or defaultVal),
		TextSize = 11, Font = cfg.Font, ClearTextOnFocus = true,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, inputFrame)
	local state = defaultVal == true
	local function apply(newState)
		if state == newState then return end
		state = newState
		button.Text = K.toggleText(toggleLabel, state)
		button.BackgroundColor3 = state and col.On or col.Off
		onToggle(state)
	end
	bag.reg(button.Activated:Connect(function() apply(not state) end))
	K.numBox(input, bag, get, set)
	return button, input, apply
end

-- 按住型按钮：按下触发 onStart，松开/失焦/销毁触发 onEnd
function K.holdButton(button, bag, onStart, onEnd)
	local heldInput = nil
	local function start(input)
		if heldInput then return end
		heldInput = input
		if onStart then onStart() end
	end
	local function finish()
		if not heldInput then return end
		heldInput = nil
		if onEnd then onEnd() end
	end
	bag.reg(button.InputBegan:Connect(function(input)
		if K.isP(input) then start(input) end
	end))
	bag.reg(button.InputEnded:Connect(function(input)
		if input == heldInput or K.isP(input) then finish() end
	end))
	bag.reg(UIS.InputEnded:Connect(function(input)
		if input == heldInput then finish() end
	end))
	bag.reg(button.AncestryChanged:Connect(function(_, parent)
		if not parent then finish() end
	end))
	bag.reg(UIS.WindowFocusReleased:Connect(finish))
	return {cancel = finish, isHeld = function() return heldInput ~= nil end}
end


-- 12. Toast
-- 计数随标签销毁自动回收，外部删掉 KIT_Toast 也不会永久失效

local toastGui = nil
local toastCount = 0

local function ensureToastGui()
	if toastGui and toastGui.Parent then return true end
	toastGui = Instance.new("ScreenGui")
	toastGui.Name = "KIT_Toast"
	toastGui.ResetOnSpawn = false
	toastGui.IgnoreGuiInset = true
	toastGui.DisplayOrder = 100000
	toastGui.Parent = GuiRoot
	toastCount = 0
	return true
end

function K.toast(text, color)
	pcall(function()
		if not ensureToastGui() then return end
		if toastCount >= 4 then return end
		local slot = toastCount
		toastCount += 1
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 10 + slot * 32)
		label.Size = UDim2.new(0, 240, 0, 28)
		label.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
		label.BackgroundTransparency = 0.15
		label.BorderSizePixel = 0
		label.Text = tostring(text)
		label.TextColor3 = color or Color3.fromRGB(240, 244, 255)
		label.TextSize = 13
		label.Font = K.font(true)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Parent = toastGui
		label.Destroying:Connect(function()
			toastCount = math.max(0, toastCount - 1)
		end)
		task.delay(2.2, function()
			pcall(function()
				local tw = TweenService:Create(label, TweenInfo.new(0.25), {
					BackgroundTransparency = 1, TextTransparency = 1,
				})
				tw:Play()
				tw.Completed:Wait()
			end)
			pcall(function() label:Destroy() end)
		end)
	end)
end

-- ==== src/kit/80-draw.lua ====
-- kit / 80-draw — 轻量绘制封装（Drawing 优先，缺失时降级 Frame + UIStroke）
-- 全部带变更检测：同值不写，减少 GC 与属性同步开销

-- 14. 绘制后端封装

local Square = {}
Square.__index = Square

function Square.new(parent, color, filled, thickness, transparency)
	local self = setmetatable({}, Square)
	self.filled = filled
	self._x, self._y, self._w, self._h = math.huge, math.huge, -1, -1
	self._c, self._t, self._v = nil, -1, nil
	local d = tryDrawing("Square")
	if d then
		d.Filled = filled
		d.Thickness = thickness
		d.Color = color
		d.Transparency = transparency
		d.Visible = false
		self.obj = d
		self.kind = "drawing"
	else
		local f = Instance.new("Frame")
		f.Name = "KIT_Box"
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color
		f.BackgroundTransparency = filled and transparency or 1
		f.Size = UDim2.fromOffset(1, 1)
		f.Visible = false
		f.Parent = parent
		local stroke
		if not filled and thickness > 0 then
			stroke = Instance.new("UIStroke")
			stroke.Color = color
			stroke.Thickness = thickness
			stroke.Transparency = transparency
			stroke.Parent = f
		end
		self.obj = f
		self.stroke = stroke
		self.kind = "frame"
	end
	return self
end

function Square:set(x, y, w, h, color, transparency)
	if self._x ~= x or self._y ~= y then
		self._x, self._y = x, y
		if self.kind == "drawing" then
			self.obj.Position = Vector2.new(x, y)
		else
			self.obj.Position = UDim2.fromOffset(x, y)
		end
	end
	if self._w ~= w or self._h ~= h then
		self._w, self._h = w, h
		if self.kind == "drawing" then
			self.obj.Size = Vector2.new(w, h)
		else
			self.obj.Size = UDim2.fromOffset(w, h)
		end
	end
	if self._c ~= color then
		self._c = color
		if self.kind == "drawing" then
			self.obj.Color = color
		else
			self.obj.BackgroundColor3 = color
			if self.stroke then self.stroke.Color = color end
		end
	end
	if self._t ~= transparency then
		self._t = transparency
		if self.kind == "drawing" then
			self.obj.Transparency = transparency
		else
			self.obj.BackgroundTransparency = self.filled and transparency or 1
			if self.stroke then self.stroke.Transparency = transparency end
		end
	end
end

function Square:setVisible(v)
	if self._v ~= v then
		self._v = v
		self.obj.Visible = v
	end
end

function Square:destroy()
	pcall(function() self.obj:Remove() end)
	pcall(function() self.obj:Destroy() end)
	if self.stroke then pcall(function() self.stroke:Destroy() end) end
end

local Line = {}
Line.__index = Line

function Line.new(parent, color, thickness, transparency)
	local self = setmetatable({}, Line)
	self.thickness = thickness
	self._fx, self._fy, self._tx, self._ty = math.huge, math.huge, math.huge, math.huge
	self._c, self._t, self._v = nil, -1, nil
	local d = tryDrawing("Line")
	if d then
		d.Color = color
		d.Thickness = thickness
		d.Transparency = transparency
		d.Visible = false
		self.obj = d
		self.kind = "drawing"
	else
		local f = Instance.new("Frame")
		f.Name = "KIT_Line"
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color
		f.BackgroundTransparency = transparency
		f.Size = UDim2.fromOffset(1, thickness)
		f.Visible = false
		f.Parent = parent
		self.obj = f
		self.kind = "frame"
	end
	return self
end

function Line:set(fromX, fromY, toX, toY, color, transparency)
	if self._fx ~= fromX or self._fy ~= fromY or self._tx ~= toX or self._ty ~= toY then
		self._fx, self._fy, self._tx, self._ty = fromX, fromY, toX, toY
		if self.kind == "drawing" then
			self.obj.From = Vector2.new(fromX, fromY)
			self.obj.To = Vector2.new(toX, toY)
		else
			local dx, dy = toX - fromX, toY - fromY
			local len = math.sqrt(dx * dx + dy * dy)
			self.obj.Position = UDim2.fromOffset((fromX + toX) * 0.5, (fromY + toY) * 0.5)
			self.obj.Size = UDim2.fromOffset(len, self.thickness)
			self.obj.Rotation = math.deg(math.atan(dy, dx))
		end
	end
	if self._c ~= color then
		self._c = color
		if self.kind == "drawing" then
			self.obj.Color = color
		else
			self.obj.BackgroundColor3 = color
		end
	end
	if self._t ~= transparency then
		self._t = transparency
		if self.kind == "drawing" then
			self.obj.Transparency = transparency
		else
			self.obj.BackgroundTransparency = transparency
		end
	end
end

function Line:setVisible(v)
	if self._v ~= v then
		self._v = v
		self.obj.Visible = v
	end
end

function Line:destroy()
	pcall(function() self.obj:Remove() end)
	pcall(function() self.obj:Destroy() end)
end

local Label = {}
Label.__index = Label

function Label.new(parent, font, transparency, textSize, color)
	local inst = Instance.new("TextLabel")
	inst.Name = "KIT_Label"
	inst.BackgroundTransparency = 1
	inst.AnchorPoint = Vector2.new(0.5, 0.5)
	inst.AutomaticSize = Enum.AutomaticSize.XY
	inst.TextXAlignment = Enum.TextXAlignment.Center
	inst.TextYAlignment = Enum.TextYAlignment.Center
	inst.TextColor3 = color or Color3.new(1, 1, 1)
	inst.TextTransparency = transparency or 0
	inst.Font = font
	inst.TextSize = textSize or 12
	inst.Text = ""
	inst.Visible = false
	inst.Parent = parent
	return setmetatable({
		obj = inst, _t = "", _x = math.huge, _y = math.huge,
		_c = nil, _s = -1, _tr = -1, _v = nil,
	}, Label)
end

function Label:setText(t)
	if self._t ~= t then
		self._t = t
		self.obj.Text = t
	end
end

function Label:setPos(x, y)
	if self._x ~= x or self._y ~= y then
		self._x, self._y = x, y
		self.obj.Position = UDim2.fromOffset(x, y)
	end
end

function Label:setColor(c)
	if self._c ~= c then
		self._c = c
		self.obj.TextColor3 = c
	end
end

function Label:setSize(s)
	if self._s ~= s then
		self._s = s
		self.obj.TextSize = s
	end
end

function Label:setTransparency(t)
	if self._tr ~= t then
		self._tr = t
		self.obj.TextTransparency = t
	end
end

function Label:setVisible(v)
	if self._v ~= v then
		self._v = v
		self.obj.Visible = v
	end
end

function Label:hideIfEmpty()
	self:setVisible(self._t ~= "")
end

function Label:destroy()
	pcall(function() self.obj:Destroy() end)
end

local function fadeT(t, fade) return math.clamp(t + (fade or 0), 0, 1) end
local function fadeTo(baseT, k) return 1 - (1 - baseT) * k end

-- ==== src/kit/90-lifecycle.lua ====
-- kit / 90-lifecycle — 模块生命周期 K.mod / K.cleanAll、心跳看门狗

-- 13. 模块生命周期
-- K.mod(name, cfgOverrides?) 返回模块句柄 M：
--   M.cfg        合并过 THEME 默认值的配置表（模块只写差异项）
--   M.bag        连接袋；M.reg(conn) 是它的糖
--   M.panel()    用 M.cfg 建 ScreenGui（M.gui），卸载时自动销毁
--   M.done(fn)   注册清理：fn() -> bag.clear() -> gui 销毁
--   M.debug(fn)  注册调试取数函数（供 KITLOG / debugAll 采集）
-- 同名模块再次 K.mod 会先执行旧模块的清理（热重载语义）。

local coreBag = K.bag()
local lastHeartbeat = os.clock()

function K.heartbeat() lastHeartbeat = os.clock() end

task.spawn(function()
	while coreBag.alive() do
		task.wait(5)
		if coreBag.alive() and os.clock() - lastHeartbeat > 30 then
			warn("[KIT] 看门狗：主循环超时")
			lastHeartbeat = os.clock()
		end
	end
end)

-- 核心自身也占一个模块槽，负责 context.root 与整套 HUD/ESP 的卸载
K.watchCharacter(coreBag, {
	ready = function(_, _, rootPart) K.context.set("root", rootPart) end,
})

function K.mod(name, cfgOverrides)
	name = tostring(name)
	local old = K.modules[name]
	if old then
		K.modules[name] = nil
		if type(old.cleanup) == "function" then pcall(old.cleanup) end
	end

	local cfg = {}
	for k, v in pairs(K.THEME) do cfg[k] = v end
	if cfgOverrides then
		for k, v in pairs(cfgOverrides) do cfg[k] = v end
	end

	local bag = K.bag()
	local M = {name = name, cfg = cfg, bag = bag, gui = nil}
	M.reg = bag.reg

	function M.done(fn)
		K.modules[name] = {
			name = name,
			bag = bag,
			cleanup = function()
				if not bag.alive() then return end
				if fn then fn() end
				bag.clear()
				if M.gui then pcall(function() M.gui:Destroy() end); M.gui = nil end
				-- 卸载后不再被 KITLOG / debugAll 采集
				if K.debugRegistry[name] ~= nil then K.debugRegistry[name] = nil end
			end,
		}
	end

	function M.debug(fn)
		K.registerDebug(name, fn)
	end

	function M.panel()
		local gui, main = K.panel(name, cfg, bag)
		M.gui = gui
		return main
	end

	-- 先占位（未 done 前也要能被 cleanAll 找到，避免热重载间隙泄漏）
	K.modules[name] = {name = name, bag = bag}
	return M
end

function K.cleanAll()
	local mods = K.modules
	K.modules = {}
	for _, rec in pairs(mods) do
		if type(rec.cleanup) == "function" then pcall(rec.cleanup) end
	end
	coreBag.clear()
	local toast = GuiRoot:FindFirstChild("KIT_Toast")
	if toast then pcall(function() toast:Destroy() end) end
	CFG.frozen = true
	if CFG.dirty then cfgFlush() end
end
_G.KIT_CLEAN_ALL = K.cleanAll

-- ==== src/kit/95-hud.lua ====
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
	Size = 17, Alpha = 0.15, GroupPadding = 26, ListPadding = -5, TopOffset = 0,
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

-- ==== src/kit/99-esp.lua ====
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

