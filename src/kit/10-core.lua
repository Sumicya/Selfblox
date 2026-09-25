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
