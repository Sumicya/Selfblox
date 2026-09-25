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
		local minY = -base.Y.Scale * vp.Y
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
		local vp = K.vp()
		local w = config.PanelSize.X.Scale * vp.X + config.PanelSize.X.Offset
		local h = config.PanelSize.Y.Scale * vp.Y + config.PanelSize.Y.Offset
		local absX = saved[1] * vp.X + saved[2]
		local absY = saved[3] * vp.Y + saved[4]
		local cx = math.clamp(absX, 0, math.max(vp.X - w, 0))
		local cy = math.clamp(absY, 0, math.max(vp.Y - h, 0))
		main.Position = UDim2.new(saved[1], cx - saved[1] * vp.X, saved[3], cy - saved[3] * vp.Y)
	end
	return gui, main
end

-- 可折叠标题栏（点击折叠/展开，拖动与点击用 moved 区分）
function K.titleBar(main, config, bag, title, height)
	height = height or 20
	local button = K.mk("TextButton", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = config.BG or K.THEME.BG,
		BackgroundTransparency = 0, -- 标题栏纯色：避免与面板叠色出现透光接缝
		BorderSizePixel = 0, Active = true, Text = title .. " [-]",
		TextColor3 = Color3.new(1, 1, 1), TextSize = 13, Font = config.Font or K.THEME.Font,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, main)
	local dragMoved = K.drag(button, main, bag, config.DragTol)
	local collapsed = false
	local collapseSize = config.CollapseSize
		or UDim2.new(config.PanelSize.X.Scale, config.PanelSize.X.Offset, 0, height)
	bag.reg(button.Activated:Connect(function()
		if dragMoved() then return end
		collapsed = not collapsed
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
