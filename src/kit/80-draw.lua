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
