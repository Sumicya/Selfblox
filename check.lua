-- 驱动: 把 selfblox.lua 真跑一遍。装起来 → 点每个按钮 → 跑物理帧 → 坐下开车 → 卸载
-- 场景由 check.js 通过 _G._SCENARIO 传入: "default" | "override" | "json"
local S = _G._SB
local fails = {}
local seen = {}
local function need(c, msg) if not c and not seen[msg] then seen[msg] = true; fails[#fails + 1] = msg end end
local function try(name, f)
	local o, e = pcall(f)
	if not o then
		-- 同一个错重复几百帧, 折叠成 "名字 → 错误 (×N)"
		local key = tostring(e)
		seen[key] = (seen[key] or 0) + 1
		if seen[key] == 1 then fails[#fails + 1] = name .. " → " .. key end
	end
	return o
end

local function byName(n, cls)
	for _, i in ipairs(S.ALL) do if not i._dead and i._p.Name == n and (not cls or i:IsA(cls)) then return i end end
end
local function desc(i, cls)
	local o = {}
	for _, c in ipairs(i:GetDescendants()) do if c:IsA(cls) then o[#o + 1] = c end end
	return o
end
local function outHas(pat) for _, l in ipairs(S.out) do if l:find(pat, 1, true) then return l end end end

-- ── 1. 面板建起来了 ──
local gui = byName("Selfblox", "ScreenGui")
need(gui, "ScreenGui 'Selfblox' 没建出来")
local function textHas(pat) -- toast / status 都是写进 TextLabel.Text 的, 不走 print
	for _, t in ipairs(desc(gui, "TextLabel")) do
		if type(t._p.Text) == "string" and t._p.Text:find(pat, 1, true) then return t._p.Text end
	end
end
local fx = byName("Selfblox_FX")
need(fx, "Folder 'Selfblox_FX' 没建出来")
if not gui then io.write("FAIL: 没有面板, 后面没法跑\n"); _G._CHECK = fails; return end

local buttons = desc(gui, "TextButton")
local boxes = desc(gui, "TextBox")
need(#buttons >= 20, "按钮只有 " .. #buttons .. " 个, 面板明显没铺满")

-- 模块装了几个: 脚本自己会 print "[Selfblox] v12 · N 模块"
local banner = outHas("[Selfblox] v12")
need(banner ~= nil, "启动横幅没打出来")
local nMods = banner and tonumber(banner:match("(%d+) 模块")) or 0
local expect = _G._SCENARIO == "override" and 3 or 7
need(nMods == expect, "模块数 " .. nMods .. " ≠ 期望 " .. expect .. " (横幅: " .. tostring(banner) .. ")")

-- 任何模块构造时炸了, 脚本会 warn 并在页面上写 "出错: ..."
for _, l in ipairs(S.out) do if l:find("[warn]", 1, true) then fails[#fails + 1] = "模块构造报错: " .. l end end
for _, t in ipairs(desc(gui, "TextLabel")) do
	if type(t._p.Text) == "string" and t._p.Text:find("出错:", 1, true) then fails[#fails + 1] = "页面上有错误标签: " .. t._p.Text end
end

-- ── 2. 每个页签都切一遍 ──
local TABS = { "动", "车", "漂", "显", "志", "机", "砖" }
for _, name in ipairs(TABS) do
	for _, b in ipairs(buttons) do
		if b._p.Text == name then try("切页签 " .. name, function() b.Activated:Fire() end) end
	end
end

-- ── 3. 数字框: 填个数回车 (走 FocusLost → set → save) ──
for i, tb in ipairs(boxes) do
	try("数字框 #" .. i, function()
		tb._p.Text = "3"
		tb.FocusLost:Fire(true)
	end)
end

-- ── 4. 每个按钮都点一遍 (toggle 全开, btn 全触发) ──
local touch = { UserInputType = Enum.UserInputType.Touch }
for i, b in ipairs(buttons) do
	try("按钮 #" .. i .. " (" .. tostring(b._p.Text) .. ") Activated", function() b.Activated:Fire() end)
	try("按钮 #" .. i .. " 按住", function() b.InputBegan:Fire(touch); b.InputEnded:Fire(touch) end)
end

-- ── 5. 空转一会儿, 让 task.spawn 的循环起来 (log 录制 / brick 刷砖 / plane 自动) ──
try("调度器", function() S.run(1, 20000) end)

-- ── 6. 站着: 速度/飞行/高跳/旋转/穿墙/夜视/漂移 全开时跑物理帧 ──
for i = 1, 60 do try("PreSimulation 站立 #" .. i, function() S.tick("PreSimulation", 1 / 60) end) end
for i = 1, 10 do try("PreRender #" .. i, function() S.tick("PreRender", 1 / 60) end) end
try("JumpRequest", function() S.services.UserInputService.JumpRequest:Fire() end)

-- ── 7. 漂移踏板: 左刹右油 ──
try("踏板", function()
	S.brake.InputBegan:Fire(touch); S.gas.InputBegan:Fire(touch)
	for i = 1, 20 do S.tick("PreSimulation", 1 / 60) end
	S.brake.InputEnded:Fire(touch); S.gas.InputEnded:Fire(touch)
end)

-- ── 8. 坐下开车: sibs 的座位分支 ──
try("上车", function()
	S.hum._p.SeatPart = S.seat
	S.seat._p.Throttle = 1
	S.seat._p.Steer = 0.5
	for i = 1, 60 do S.tick("PreSimulation", 1 / 60) end
	S.seat._p.Throttle = -1
	for i = 1, 30 do S.tick("PreSimulation", 1 / 60) end
end)

-- ── 9. 没座位时用准星换车 ──
try("下车 + 准星换车", function()
	S.hum._p.SeatPart = nil
	for _, b in ipairs(buttons) do
		if b._p.Text == "换车(准星)" then b.Activated:Fire() end
	end
	for i = 1, 40 do S.tick("PreSimulation", 1 / 60) end
end)
need(textHas("锁定 ") ~= nil, "准星换车没锁定到 MuscleCar")

-- ── 10. 新 ProximityPrompt 出现 (秒互动) ──
try("秒互动", function()
	local p = S.newInst("ProximityPrompt", S.hrp)
	p._p.Name = "NewPrompt"
	S.workspace.DescendantAdded:Fire(p)
	need(p._p.HoldDuration == 0, "秒互动没把 HoldDuration 改成 0")
end)

-- ── 11. plane: 扫到飞机 + 报告写盘 ──
try("飞机扫描", function()
	for _, b in ipairs(buttons) do
		if b._p.Text == "重扫" then b.Activated:Fire() end
	end
	for _, b in ipairs(buttons) do
		if b._p.Text == "写报告" then b.Activated:Fire() end
	end
end)
if nMods == 7 then
	need(S.FILES["plane_debug.txt"] ~= nil, "plane 报告没写进 plane_debug.txt")
	need(S.FILES["plane_debug.txt"] and S.FILES["plane_debug.txt"]:find("FighterJet", 1, true) ~= nil, "报告里没找到 FighterJet")
end

-- ── 12. brick: 刷砖循环至少跑了几轮 ──
try("刷砖循环", function() S.run(60, 80000) end)
if nMods == 7 then need((S.spawnBit._sent or 0) > 0, "刷砖一次 SpawnBit:FireServer 都没发出去") end

-- ── 13. log: 录制写盘 ──
if nMods == 7 then
	need(S.FILES["Selfblox_log.txt"] ~= nil and #S.FILES["Selfblox_log.txt"] > 0, "log 模块开了录制却没写出东西")
	need(S.FILES["Selfblox_log.txt"] and S.FILES["Selfblox_log.txt"]:find("moc:", 1, true) ~= nil, "日志里没有 moc 的状态行")
end

-- ── 14. 卸载 ──
try("卸载", function() _G.SB_UNLOAD() end)
need(_G.SB_UNLOAD == nil, "_G.SB_UNLOAD 卸载后没清掉")
need(gui._dead == true, "gui 卸载后没被 Destroy")
need(fx._dead == true, "Selfblox_FX 卸载后没被 Destroy")

-- ── 报告 ──
local rep = {}
if #fails == 0 then
	rep[1] = string.format("PASS  场景=%s  模块=%d  按钮=%d  数字框=%d", tostring(_G._SCENARIO), nMods, #buttons, #boxes)
else
	rep[1] = string.format("FAIL  场景=%s  %d 个问题:", tostring(_G._SCENARIO), #fails)
	for _, f in ipairs(fails) do rep[#rep + 1] = "  - " .. f end
end
io.write(table.concat(rep, "\n"), "\n")
_G._SUMMARY = rep[1]
_G._CHECK = fails
