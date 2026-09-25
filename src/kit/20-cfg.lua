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
