-- Selfblox · KITLOG — 连续日志（独立单文件）
-- v11 激进重写：无框架 / 无构建 / 现代 Luau / 原生 API 优先
-- 用法: loadstring(game:HttpGet(".../log.lua"))()
-- 产物: KIT_Log.txt + 最多 3 个归档（_1/_2/_3），每档 512KB
-- 采样: 本文件状态 + 其他 Selfblox 模块经 _G.SB_DEBUG 注册的调试块
-- 需要执行器提供 appendfile / writefile

local NAME = "KITLOG"

-- ===== 0. 重跑替换旧实例 =====

local OLD = rawget(_G, "SB_" .. NAME)
if type(OLD) == "function" then
	pcall(OLD)
end

if not (type(appendfile) == "function" and type(writefile) == "function") then
	error("[kitlog] 当前执行器不支持 appendfile/writefile", 0)
end

local UIS = game:GetService("UserInputService")
local GuiRoot = (pcall(function() return gethui() end) and gethui()) or game:GetService("CoreGui")

local conns = {}
local function reg(c)
	conns[#conns + 1] = c
	return c
end

local function mk(className, props, parent)
	local inst = Instance.new(className, props)
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function pickFont(names, fallback)
	for _, n in ipairs(names) do
		local ok, f = pcall(function() return Enum.Font[n] end)
		if ok and f then
			return f
		end
	end
	return fallback
end
local FONT = pickFont({ "BuilderSansBold", "GothamBold", "SourceSansBold" }, Enum.Font.SourceSansBold)

local oldGui = GuiRoot:FindFirstChild(NAME)
if oldGui then
	pcall(function() oldGui:Destroy() end)
end

-- ===== 1. 配置（原生文件 API；兼容 v10 的 KIT_Config.txt）=====

local store = rawget(_G, "SB_CFG")
if type(store) ~= "table" then
	store = { cache = {}, loaded = false, dirty = false, token = 0 }
	rawset(_G, "SB_CFG", store)
end
local CFG_FILE = "Selfblox_cfg.txt"
local HAS_RW = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"

local function flushCfg()
	if not (store.dirty and HAS_RW) then
		return
	end
	local keys = {}
	for k in pairs(store.cache) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local lines = { "KITCFG2" }
	for _, k in ipairs(keys) do
		local v = store.cache[k]
		local t = type(v)
		if t == "boolean" then
			lines[#lines + 1] = k .. "\tb\t" .. (v and "1" or "0")
		elseif t == "number" and v == v then
			lines[#lines + 1] = k .. "\tn\t" .. string.format("%.17g", v)
		elseif t == "string" then
			lines[#lines + 1] = k .. "\ts\t" .. v
		end
	end
	pcall(writefile, CFG_FILE, table.concat(lines, "\n"))
	store.dirty = false
end

if not store.loaded and HAS_RW then
	store.loaded = true
	local content = nil
	if pcall(function() return assert(isfile(CFG_FILE)) end) then
		content = readfile(CFG_FILE)
	elseif pcall(function() return assert(isfile("KIT_Config.txt")) end) then
		content = readfile("KIT_Config.txt")
	end
	if type(content) == "string" then
		local first = true
		for line in content:gmatch("[^\r\n]+") do
			if first then
				first = false
				if line ~= "KITCFG2" then
					break
				end
			else
				local k, t, v = line:match("^(.-)\t(.-)\t(.*)$")
				if k and t and k ~= "" then
					if t == "b" then
						store.cache[k] = (v == "1")
					elseif t == "n" then
						store.cache[k] = tonumber(v)
					elseif t == "s" then
						store.cache[k] = v
					end
				end
			end
		end
	end
end

local function cfgGet(key, d)
	local v = store.cache[key]
	return v == nil and d or v
end
local function cfgGetNum(key, d)
	local v = cfgGet(key, nil)
	if typeof(v) == "number" and v == v then
		return v
	end
	return d
end
local function cfgSet(key, v)
	store.cache[key] = v
	store.dirty = true
	local token = store.token
	task.delay(0.5, function()
		if store.token == token and store.dirty then
			store.token += 1
			flushCfg()
		end
	end)
end

-- ===== 2. 常量 / 状态 =====

local CFG = {
	MaxBytes = 512 * 1024, MaxArchives = 3, File = "KIT_Log.txt",
	TitleH = 20, RowH = 30, PanelW = 128,
}
CFG.Interval = cfgGetNum("KITLOGInterval", 2)

local COL = {
	On = Color3.fromRGB(38, 125, 85), Off = Color3.fromRGB(48, 50, 60),
	Good = Color3.fromRGB(135, 215, 155), Bad = Color3.fromRGB(225, 135, 135),
	Wait = Color3.fromRGB(170, 175, 185), Bind = Color3.fromRGB(95, 65, 135),
	Stop = Color3.fromRGB(155, 45, 45),
}
local BG = Color3.fromRGB(20, 22, 28)
local ALPHA = 0.72

local running = true
local samples = 0
local written = 0
local alive = true

-- ===== 3. 归档滚动：删最老 → 逐级后移 → 当前文件进 _1 → 写新文件头 =====

local function archivePath(index)
	return "KIT_Log_" .. index .. ".txt"
end

local function fileExists(path)
	if type(isfile) ~= "function" then
		return false
	end
	local ok, exists = pcall(isfile, path)
	return ok and exists == true
end

local function rollFile(reason)
	local oldest = archivePath(CFG.MaxArchives)
	if fileExists(oldest) and type(delfile) == "function" then
		pcall(delfile, oldest)
	end
	for i = CFG.MaxArchives - 1, 1, -1 do
		local src = archivePath(i)
		if fileExists(src) then
			local okR, content = pcall(readfile, src)
			if okR then
				pcall(writefile, archivePath(i + 1), content)
			end
		end
	end
	if fileExists(CFG.File) then
		local okR, content = pcall(readfile, CFG.File)
		if okR then
			pcall(writefile, archivePath(1), content)
		end
	end
	local header = "---- " .. reason .. " " .. os.date("%H:%M:%S") .. " ----\n"
	pcall(writefile, CFG.File, header)
	written = #header
end

rollFile("会话开始 " .. os.date("%Y-%m-%d %H:%M:%S"))

-- ===== 4. 采样（_G.SB_DEBUG 注册表）=====

local function collectSamples()
	local parts = {}
	local dbg = rawget(_G, "SB_DEBUG")
	if type(dbg) == "table" then
		local names = {}
		for n in pairs(dbg) do
			names[#names + 1] = n
		end
		table.sort(names)
		for _, n in ipairs(names) do
			local ok, dump = pcall(dbg[n])
			if ok and type(dump) == "string" then
				parts[#parts + 1] = dump
			else
				parts[#parts + 1] = "=== " .. n .. " ===\nERROR\n=== END ==="
			end
		end
	end
	local selfLine = string.format(
		"=== KITLOG ===\nrun=%s int=%.1fs n=%d %.0fKB/%dKB\n=== END ===",
		tostring(running), CFG.Interval, samples,
		written / 1024, CFG.MaxBytes / 1024)
	parts[#parts + 1] = selfLine
	return parts
end

local function appendText(text)
	local ok = pcall(appendfile, CFG.File, text)
	if ok then
		written += #text
	end
	return ok
end

local function toast(text)
	-- 轻量提示：直接 print（避免再开一个 GUI）
	print("[kitlog] " .. text)
end

local function sample()
	local parts = collectSamples()
	local text = string.format("[%s] ---- #%d ----\n", os.date("%H:%M:%S"), samples + 1)
		.. table.concat(parts, "\n") .. "\n"
	if written + #text > CFG.MaxBytes then
		rollFile("滚动归档")
		toast("日志归档滚动")
	end
	appendText(text)
	samples += 1
end

-- ===== 5. GUI：间隔输入 + 录制/卸载 + 状态 =====

local inputRowH = 26
local totalH = CFG.TitleH + inputRowH + CFG.RowH + 20
local panelSize = UDim2.new(0, CFG.PanelW, 0, totalH)
local panelPos = UDim2.new(0.02, 0, 0.72, 0)

local gui = mk("ScreenGui", {
	Name = NAME, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99996,
}, GuiRoot)
local main = mk("Frame", {
	Size = panelSize, Position = panelPos, BackgroundColor3 = BG,
	BackgroundTransparency = ALPHA, BorderSizePixel = 0, ClipsDescendants = true,
}, gui)

do
	local saved = cfgGet("UI.Pos." .. NAME, nil)
	local vp = workspace.CurrentCamera.ViewportSize
	if typeof(saved) == "string" then
		local sx, ox, sy, oy = saved:match("^([%-%d%.]+),([%-%d]+),([%-%d%.]+),([%-%d]+)$")
		if sx then
			local w, h = CFG.PanelW, totalH
			local absX = math.clamp(tonumber(ox) or 0, 0, math.max(vp.X - w, 0))
			local absY = math.clamp(tonumber(oy) or 0, 0, math.max(vp.Y - h, 0))
			main.Position = UDim2.new(tonumber(sx) or 0, absX, tonumber(sy) or 0, absY)
		end
	end
end

local titleBar = mk("TextButton", {
	Size = UDim2.new(1, 0, 0, CFG.TitleH), BackgroundColor3 = BG, BackgroundTransparency = 1,
	BorderSizePixel = 0, Text = "连续日志 [-]", TextColor3 = Color3.new(1, 1, 1),
	TextSize = 13, Font = FONT, TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
}, main)

do
	local dragging, moved, origin, base = false, false, Vector2.zero, UDim2.new()
	reg(titleBar.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		dragging, moved = true, false
		origin = input.Position
		base = main.Position
	end))
	reg(UIS.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local delta = input.Position - origin
		if math.abs(delta.X) + math.abs(delta.Y) > 4 then
			moved = true
		end
		local vp = workspace.CurrentCamera.ViewportSize
		local size = main.AbsoluteSize
		local minX = -base.X.Scale * vp.X
		local maxX = vp.X - size.X - base.X.Scale * vp.X
		if minX > maxX then
			minX, maxX = maxX, minX
		end
		local minY = -base.Y.Scale * vp.Y
		local maxY = vp.Y - size.Y - base.Y.Scale * vp.Y
		if minY > maxY then
			minY, maxY = maxY, minY
		end
		main.Position = UDim2.new(
			base.X.Scale, math.clamp(base.X.Offset + delta.X, minX, maxX),
			base.Y.Scale, math.clamp(base.Y.Offset + delta.Y, minY, maxY))
	end))
	local function release()
		if not dragging then
			return
		end
		dragging = false
		if moved then
			cfgSet("UI.Pos." .. NAME, string.format("%.6f,%.0f,%.6f,%.0f",
				main.Position.X.Scale, main.Position.X.Offset,
				main.Position.Y.Scale, main.Position.Y.Offset))
		end
	end
	reg(UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			release()
		end
	end))
	reg(UIS.WindowFocusReleased:Connect(release))

	local collapsed = false
	reg(titleBar.Activated:Connect(function()
		if moved then
			return
		end
		collapsed = not collapsed
		titleBar.Text = "连续日志 " .. (collapsed and "[+]" or "[-]")
		main.Size = collapsed and UDim2.new(0, CFG.PanelW, 0, CFG.TitleH) or panelSize
	end))
end

local intervalInput = mk("TextBox", {
	Size = UDim2.new(1, 0, 0, inputRowH),
	Position = UDim2.new(0, 0, 0, CFG.TitleH),
	BackgroundColor3 = COL.Bind, BackgroundTransparency = ALPHA, BorderSizePixel = 0,
	TextColor3 = Color3.new(1, 1, 1), Text = tostring(CFG.Interval), TextSize = 11,
	Font = FONT, ClearTextOnFocus = true,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, main)

reg(intervalInput.FocusLost:Connect(function()
	local v = tonumber(intervalInput.Text)
	if v then
		CFG.Interval = math.clamp(v, 0.5, 30)
		cfgSet("KITLOGInterval", CFG.Interval)
	end
	intervalInput.Text = tostring(CFG.Interval)
end))

local recordButton = mk("TextButton", {
	Size = UDim2.new(0.5, 0, 0, CFG.RowH),
	Position = UDim2.new(0, 0, 0, CFG.TitleH + inputRowH),
	BackgroundColor3 = COL.On, BackgroundTransparency = ALPHA, BorderSizePixel = 0,
	Text = "录制 开", TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = FONT,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, main)

local unloadButton = mk("TextButton", {
	Size = UDim2.new(0.5, 0, 0, CFG.RowH),
	Position = UDim2.new(0.5, 0, 0, CFG.TitleH + inputRowH),
	BackgroundColor3 = COL.Stop, BackgroundTransparency = ALPHA, BorderSizePixel = 0,
	Text = "卸载", TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = FONT,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, main)

local statusLabel = mk("TextLabel", {
	Size = UDim2.new(1, 0, 0, 20),
	Position = UDim2.new(0, 0, 0, CFG.TitleH + inputRowH + CFG.RowH),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	Text = "启动中…", TextColor3 = COL.Wait, Font = FONT, TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, main)

local function setRunning(on)
	running = on
	recordButton.Text = on and "录制 开" or "录制 关"
	recordButton.BackgroundColor3 = on and COL.On or COL.Off
end

reg(recordButton.Activated:Connect(function()
	setRunning(not running)
end))

local function setStatus()
	if running then
		statusLabel.Text = string.format("样本 %d · %.0f KB", samples, written / 1024)
		statusLabel.TextColor3 = COL.Good
	else
		statusLabel.Text = "已暂停 · 样本 " .. samples
		statusLabel.TextColor3 = COL.Wait
	end
end

sample()
setStatus()

-- ===== 6. 主循环 =====

task.spawn(function()
	while alive do
		task.wait(math.clamp(CFG.Interval, 0.5, 30))
		if not alive then
			break
		end
		if running then
			sample()
		end
		setStatus()
	end
end)

-- ===== 7. 卸载 =====

local DBG = rawget(_G, "SB_DEBUG") or {}
rawset(_G, "SB_DEBUG", DBG)
DBG[NAME] = function()
	return string.format("=== KITLOG ===\nrun=%s int=%.1fs n=%d %.0fKB/%dKB archives=%d\n=== END ===",
		tostring(running), CFG.Interval, samples,
		written / 1024, CFG.MaxBytes / 1024, CFG.MaxArchives)
end

local function destroy()
	alive = false
	running = false
	appendText("==== 会话结束 " .. os.date("%H:%M:%S") .. " ====\n")
	gui:Destroy()
	for _, c in ipairs(conns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(conns)
	store.token += 1
	flushCfg()
	DBG[NAME] = nil
	rawset(_G, "SB_" .. NAME, nil)
end
reg(unloadButton.Activated:Connect(destroy))
rawset(_G, "SB_" .. NAME, destroy)

print("[kitlog] 就绪：每 " .. string.format("%.1f", CFG.Interval) .. "s → KIT_Log.txt（归档×" .. CFG.MaxArchives .. "）")
