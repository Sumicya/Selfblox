-- brick — BitFarmer v2.1 | 独立脚本（可选接入 KIT 调试）
-- 事件驱动即时收集 + 高频刷砖 + 倍率锁定
-- 执行一次启动，再执行一次停止

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local p = Players.LocalPlayer
local K = _G.KIT

-- 运行状态存全局：重复执行即切换开关
if _G._BitFarmActive then
	_G._BitFarmActive = false
	return
end
_G._BitFarmActive = true

local NAME = "BitFarm"
local collector = workspace:FindFirstChild("Collector")
local spawnBit = ReplicatedStorage:FindFirstChild("SpawnBit")
local ls = p:FindFirstChild("leaderstats")
local bitsVal = ls and ls:FindFirstChild("Bits")
local multVal = ls and ls:FindFirstChild("Multiplier")

if not collector or not bitsVal then
	local errMsg = "[BitFarm] 致命错误: 未找到 Collector 或 leaderstats.Bits"
	warn(errMsg)
	if K and K.copyClipboard then K.copyClipboard(errMsg) end
	_G._BitFarmActive = false
	return
end

local CFG = {
	BatchSpawns = 4,        -- 每次刷砖触发次数
	SpawnInterval = 0.08,   -- 刷砖发包间隔(秒)
	DrainTimeout = 0.6,     -- 消化等待上限
	ForceMult = 99999,      -- 强制倍率
	ForceLevel = 9999,      -- 强制等级
}

local stats = {
	startTime = os.clock(),
	cycles = 0,
	totalEarned = 0,
	spawnedPackets = 0,
	collectedBits = 0,
	lastBits = bitsVal.Value,
	bitsPerSec = 0,
	lastRateCalc = os.clock(),
}

local origMult = multVal and multVal.Value or 1
local origLevel = p:GetAttribute("MultiplierUpgradeLevel") or 0

-- 倍率强制维持
local function assertMultiplier()
	if multVal and multVal.Value < CFG.ForceMult then
		pcall(function() multVal.Value = CFG.ForceMult end)
	end
	pcall(function() p:SetAttribute("MultiplierUpgradeLevel", CFG.ForceLevel) end)
end
assertMultiplier()

-- 物理推进：把砖拽到 Collector 并赋初速，唤醒接触判定
local function ingestBit(b)
	if not b or not b.Parent or b.Anchored then return false end
	return pcall(function()
		b.CFrame = collector.CFrame + Vector3.new(math.random(-3, 3), 1.5, math.random(-3, 3))
		b.AssemblyLinearVelocity = Vector3.new(0, -35, 0)
		b.AssemblyAngularVelocity = Vector3.new(math.random(-5, 5), 0, math.random(-5, 5))
	end)
end

local function ownBit(c)
	if not c:IsA("BasePart") or c.Anchored then return false end
	local ok, owner = pcall(function() return c:GetAttribute("Owner") end)
	return ok and owner == p.UserId
end

-- 存量清理扫描
local function drainExisting()
	local count = 0
	for _, c in ipairs(workspace:GetChildren()) do
		if ownBit(c) and ingestBit(c) then count += 1 end
	end
	return count
end

-- 调试探针（KIT 存在时注册，供 KITLOG / debugAll 采集）
_G.BitFarm_Debug = function()
	local now = os.clock()
	local elapsed = math.max(now - stats.startTime, 0.1)
	local liveField = 0
	for _, c in ipairs(workspace:GetChildren()) do
		if ownBit(c) then liveField += 1 end
	end

	local lines = {
		"status: " .. tostring(_G._BitFarmActive),
		"uptime: " .. string.format("%.1fs", elapsed),
		"cycles: " .. tostring(stats.cycles),
		"totalEarned: " .. tostring(stats.totalEarned),
		"bitsPerSec: " .. string.format("%.1f", stats.bitsPerSec),
		"currentBits: " .. tostring(bitsVal and bitsVal.Value or 0),
		"multiplierVal: " .. tostring(multVal and multVal.Value or "?"),
		"activeInField: " .. tostring(liveField),
		"spawnPackets: " .. tostring(stats.spawnedPackets),
		"collectedCount: " .. tostring(stats.collectedBits),
		"collectorPart: " .. tostring(collector:GetFullName()),
	}

	if K and K.debugDump then
		return K.debugDump(NAME, lines)
	end
	local dump = "=== " .. NAME .. " ===\n" .. table.concat(lines, "\n") .. "\n=== END ==="
	print(dump)
	return dump
end

if K and type(K.registerDebug) == "function" then
	K.registerDebug(NAME, _G.BitFarm_Debug)
end

-- 主流水线：消化积压 → 高频刷砖 → 结算
local connChildAdded = workspace.ChildAdded:Connect(function(child)
	if not _G._BitFarmActive then return end
	task.defer(function()
		if not _G._BitFarmActive then return end
		if ownBit(child) and ingestBit(child) then
			stats.collectedBits += 1
		end
	end)
end)

task.spawn(function()
	print(string.format("[BitFarm] v2.1 启动成功 | 目标 Collector: %s", collector.Name))

	while _G._BitFarmActive do
		stats.cycles += 1
		local cycleStartBits = bitsVal.Value

		drainExisting()

		if spawnBit then
			for _ = 1, CFG.BatchSpawns do
				if not _G._BitFarmActive then break end
				pcall(function() spawnBit:FireServer() end)
				stats.spawnedPackets += 1
				task.wait(CFG.SpawnInterval)
			end
		end

		task.wait(CFG.DrainTimeout)
		drainExisting()

		local currentBits = bitsVal.Value
		local earned = currentBits - cycleStartBits
		if earned > 0 then stats.totalEarned += earned end

		local now = os.clock()
		local dt = now - stats.lastRateCalc
		if dt >= 1.0 then
			stats.bitsPerSec = (currentBits - stats.lastBits) / dt
			stats.lastBits = currentBits
			stats.lastRateCalc = now
		end

		assertMultiplier()
		task.wait(0.15)
	end

	-- 安全退出还原
	pcall(function() connChildAdded:Disconnect() end)
	if multVal then pcall(function() multVal.Value = origMult end) end
	pcall(function() p:SetAttribute("MultiplierUpgradeLevel", origLevel) end)
	if K and K.debugRegistry then K.debugRegistry[NAME] = nil end
	print(string.format("[BitFarm] 已安全停止 | 总产出: +%d Bits", stats.totalEarned))
	_G._BitFarmActive = nil
end)
