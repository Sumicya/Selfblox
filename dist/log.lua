-- log.lua — KIT v10 单文件 bundle（由 build.py 生成，勿直接编辑）
-- 源: src/modules/log.lua
-- 构建: python3 build.py

-- ==== src/modules/log.lua ====
-- log — KIT 连续日志（模块名 KITLOG）
-- 依赖：kit v10；产物：KIT_Log.txt + 最多 3 个归档（_1/_2/_3），每档 512KB
-- 需要执行器提供 appendfile / writefile

local K = _G.KIT
if not K or K.ver < 10 or type(K.mod) ~= "function" then
	error("[kitlog] 请先执行 kit.lua（需要 _G.KIT v10）", 0)
end
if not (type(appendfile) == "function" and type(writefile) == "function") then
	error("[kitlog] 当前执行器不支持 appendfile/writefile", 0)
end

local NAME = "KITLOG"
local M = K.mod(NAME, {DisplayOrder = 99996, PanelW = 128})
local CFG = M.cfg
CFG.Interval = K.loadPrefixedNumber(NAME, "Interval", 2)
CFG.MaxBytes = 512 * 1024
CFG.MaxArchives = 3
CFG.File = "KIT_Log.txt"

local running = true
local samples = 0
local written = 0

-- 归档滚动：删最老 → 逐级后移 → 当前文件进 _1 → 写新文件头
local function archivePath(index)
	return "KIT_Log_" .. index .. ".txt"
end

local function rollFile(reason)
	local oldest = archivePath(CFG.MaxArchives)
	if K.env.hasIsfile then
		local okE, exists = pcall(isfile, oldest)
		if okE and exists and type(delfile) == "function" then
			pcall(delfile, oldest)
		end
	end
	for i = CFG.MaxArchives - 1, 1, -1 do
		local src = archivePath(i)
		if K.env.hasIsfile then
			local okS, exists = pcall(isfile, src)
			if okS and exists then
				local okR, content = pcall(readfile, src)
				if okR then pcall(writefile, archivePath(i + 1), content) end
			end
		end
	end
	if K.env.hasIsfile then
		local okC, exists = pcall(isfile, CFG.File)
		if okC and exists then
			local okR, content = pcall(readfile, CFG.File)
			if okR then pcall(writefile, archivePath(1), content) end
		end
	end
	local header = "---- " .. reason .. " " .. os.date("%H:%M:%S") .. " ----\n"
	pcall(writefile, CFG.File, header)
	written = #header
end

rollFile("会话开始 " .. os.date("%Y-%m-%d %H:%M:%S"))

-- 收集所有已注册模块的调试输出 + 核心错误
local function collectSamples()
	local parts = {}
	local names = {}
	for n in pairs(K.debugRegistry) do names[#names + 1] = n end
	table.sort(names)
	local prevQuiet = K.quietDump
	K.quietDump = true
	for _, n in ipairs(names) do
		local ok, dump = pcall(K.debugRegistry[n])
		if ok and type(dump) == "string" then
			parts[#parts + 1] = dump
		else
			parts[#parts + 1] = "=== " .. n .. " ===\nERROR\n=== END ==="
		end
	end
	K.quietDump = prevQuiet
	local errCount = #K.errors
	if errCount > 0 then
		local seg = {"=== KITERRORS ===", ("count: %d"):format(errCount)}
		local from = math.max(1, errCount - 9)
		for i = from, errCount do
			local e = K.errors[i]
			seg[#seg + 1] = tostring(e.m) .. ": " .. tostring(e.e)
		end
		seg[#seg + 1] = "=== END ==="
		parts[#parts + 1] = table.concat(seg, "\n")
	end
	return parts
end

local function appendText(text)
	local ok = pcall(appendfile, CFG.File, text)
	if ok then written += #text end
	return ok
end

local function sample()
	local parts = collectSamples()
	local text = string.format("[%s] ---- #%d ----\n", os.date("%H:%M:%S"), samples + 1)
		.. table.concat(parts, "\n") .. "\n"
	if written + #text > CFG.MaxBytes then
		rollFile("滚动归档")
		K.toast("日志归档滚动", K.Col.Wait)
	end
	appendText(text)
	samples += 1
end

-- GUI：标题 + 间隔输入 + 录制/卸载 + 状态
local inputRowH = 26
local totalH = CFG.TitleH + inputRowH + CFG.RowH + 20
CFG.PanelSize = UDim2.new(0, CFG.PanelW, 0, totalH)
CFG.PanelPos = UDim2.new(0.02, 0, 0.72, 0)
CFG.CollapseSize = UDim2.new(0, CFG.PanelW, 0, CFG.TitleH)

local main = M.panel()
K.titleBar(main, CFG, M.bag, "连续日志", CFG.TitleH)

K.fullInput(main, CFG.TitleH, inputRowH, "间隔", CFG.Col.Bind,
	function() return CFG.Interval end,
	function(v)
		CFG.Interval = math.clamp(v, 0.5, 30)
		K.savePrefixed(NAME, "Interval", CFG.Interval)
	end,
	M.bag, CFG)

local recordButton = K.btn(main, {
	Size = UDim2.new(0.5, 0, 0, CFG.RowH),
	Position = UDim2.new(0, 0, 0, CFG.TitleH + inputRowH),
	BackgroundColor3 = CFG.Col.On,
	Text = K.toggleText("录制", running),
}, CFG)

local unloadButton = K.btn(main, {
	Size = UDim2.new(0.5, 0, 0, CFG.RowH),
	Position = UDim2.new(0.5, 0, 0, CFG.TitleH + inputRowH),
	BackgroundColor3 = CFG.Col.Stop,
	Text = "卸载",
}, CFG)

local status = K.label(main, {
	Size = UDim2.new(1, 0, 0, 20),
	Position = UDim2.new(0, 0, 0, CFG.TitleH + inputRowH + CFG.RowH),
	Text = "启动中…", TextColor3 = CFG.Col.Wait, TextSize = 10,
}, CFG)

local function setRunning(on)
	running = on
	recordButton.Text = K.toggleText("录制", on)
	recordButton.BackgroundColor3 = on and CFG.Col.On or CFG.Col.Off
end

M.reg(recordButton.Activated:Connect(function() setRunning(not running) end))

local function setStatus()
	if running then
		status.Text = string.format("样本 %d · %.0f KB", samples, written / 1024)
		status.TextColor3 = CFG.Col.Good
	else
		status.Text = "已暂停 · 样本 " .. samples
		status.TextColor3 = CFG.Col.Wait
	end
end

sample()
setStatus()

-- 主循环
task.spawn(function()
	while M.bag.alive() do
		task.wait(math.clamp(CFG.Interval, 0.5, 30))
		if not M.bag.alive() then break end
		if running then
			sample()
		end
		setStatus()
	end
end)

M.debug(function()
	return string.format("=== KITLOG ===\nrun=%s int=%.1fs n=%d %.0fKB/%dKB archives=%d\n=== END ===",
		tostring(running), CFG.Interval, samples,
		written / 1024, CFG.MaxBytes / 1024, CFG.MaxArchives)
end)

M.done(function()
	running = false
	appendText("==== 会话结束 " .. os.date("%H:%M:%S") .. " ====\n")
end)

print("[kitlog] 就绪：每 " .. string.format("%.1f", CFG.Interval) .. "s → KIT_Log.txt（归档×" .. CFG.MaxArchives .. "）")

