-- kit / 30-input — 键盘 / 手柄 / 触摸统一输入层

-- 6. 输入层
-- forwardStates/sideStates/verticalStates 返回 (a, b) 布尔对，
-- flags 用于把触摸按钮等外部状态并入判定。

K.input = {}

local function anyKeyDown(...)
	for i = 1, select("#", ...) do
		if K.keyDown(select(i, ...)) then return true end
	end
	return false
end

function K.input.forwardStates(flags)
	local w = anyKeyDown(Enum.KeyCode.W, Enum.KeyCode.Up) or (flags and flags.w == true)
	local s = anyKeyDown(Enum.KeyCode.S, Enum.KeyCode.Down) or (flags and flags.s == true)
	return w == true, s == true
end

function K.input.sideStates(flags)
	local d = anyKeyDown(Enum.KeyCode.D, Enum.KeyCode.Right) or (flags and flags.d == true)
	local a = anyKeyDown(Enum.KeyCode.A, Enum.KeyCode.Left) or (flags and flags.a == true)
	return d == true, a == true
end

function K.input.verticalStates(flags)
	local up = anyKeyDown(Enum.KeyCode.Space, Enum.KeyCode.E) or (flags and flags.up == true)
	local down = anyKeyDown(Enum.KeyCode.LeftShift, Enum.KeyCode.Q) or (flags and flags.down == true)
	return up == true, down == true
end

function K.input.forward(flags)
	local w, s = K.input.forwardStates(flags)
	return (w and 1 or 0) - (s and 1 or 0)
end

function K.input.side(flags)
	local d, a = K.input.sideStates(flags)
	return (d and 1 or 0) - (a and 1 or 0)
end

function K.input.vertical(flags)
	local up, down = K.input.verticalStates(flags)
	return math.clamp((up and 1 or 0) - (down and 1 or 0), -1, 1)
end

function K.input.stick()
	local ok, state = pcall(function() return UIS:GetGamepadState(Enum.UserInputType.Gamepad1) end)
	if not ok or not state then return nil end
	for _, input in ipairs(state) do
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			return Vector3.new(input.Position.X, 0, input.Position.Y)
		end
	end
	return nil
end

-- 摇杆方向换算到相机平面（返回世界水平方向）
function K.input.stickDir(deadzone)
	local s = K.input.stick()
	if not s or s.Magnitude < (deadzone or 0.15) then return Vector3.zero end
	local cam = workspace.CurrentCamera
	local cf = cam and cam.CFrame
	local look, right
	if cf then
		look = K.flatUnit(cf.LookVector, Vector3.new(0, 0, 1))
		right = K.flatUnit(cf.RightVector, Vector3.new(1, 0, 0))
	else
		look, right = Vector3.new(0, 0, 1), Vector3.new(1, 0, 0)
	end
	local dir = look * s.Z + right * s.X
	if dir.Magnitude > 1e-3 then return dir.Unit end
	return Vector3.zero
end
