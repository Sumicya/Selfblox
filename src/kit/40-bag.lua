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
