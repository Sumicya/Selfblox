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
