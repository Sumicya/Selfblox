-- sibs / 00-head — 载具控制：状态、配置、前向声明
-- 依赖：kit v10（kit.lua 先执行）
-- 功能：锁定/换车/车列表/加速减速/转向滑条/旋转滑条/翻转/定速/穿墙/飞车/灯/喇叭/引擎音调
-- 约定：缩进用单个 Tab

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

local NAME = "SIBS"
local K = _G.KIT
if not K or K.ver < 10 or type(K.mod) ~= "function" then
	error("[sibs] 请先执行 kit.lua（需要 _G.KIT v10）", 0)
end

local mk = K.mk
local toast = K.toast
local M = K.mod(NAME, {DisplayOrder = 99998, TitleH = 24, InputRowH = 26, RowH = 32,
	SigRowH = 30, BtnH = 44, PanelW = 180, PanelVisibleH = 480})
local CFG = M.cfg
CFG.Acceleration = 500
CFG.TurnSpeed = 2.2
CFG.TurnRefSpeed = 25 -- 轮胎转向：车速达此值才给满转向角，以下按车速线性衰减，静止不转
CFG.TurnGrip = 5
CFG.HighSpeedTurnFloor = 0.62
CFG.NoCharScan = 0.8
CFG.NoCharScreenMargin = 80
CFG.NoCharOwnCarDist = 15
CFG.ManualLockDuration = 8
CFG.OwnedTakeoverInterval = 0.5
CFG.MovingCarSpeed = 15
CFG.NearOwnDist = 25
CFG.AimRadius = 0.20
CFG.MaxSwitchDist = 500
CFG.MinVehicleParts = 6
CFG.ClipFallSpeed = -20
CFG.ClipFallProbeDist = 60
CFG.ClipRebuildInterval = 0.5
CFG.HoverBand = 2
CFG.HoverSinkCap = -10
CFG.HoverPushGain = 10
CFG.HoverPushMax = 30
CFG.HornKey = Enum.KeyCode.H
CFG.LampKey = Enum.KeyCode.O
CFG.FlySpeed = 60
CFG.FlyVertAccel = 80
CFG.BrakeDecelMult = 2
CFG.GroundClearance = 3
CFG.GroundProbeExtra = 6
CFG.FlashHalfPeriod = 0.1
CFG.BrakeDeadzone = 2
CFG.CruiseDeadzone = 3
CFG.CruiseGain = 2
CFG.ForceDeadzone = 0.5
CFG.VehicleMinScore = 20
CFG.SpinMax = 15
CFG.SteerMaxDeg = 45
CFG.VehicleLikeTTL = 2
CFG.RootPartTTL = 1.5
CFG.TurnGrip = K.loadPrefixedNumber(NAME, "Grip", CFG.TurnGrip)

-- 状态
local seat = nil
local acceleration = K.loadPrefixedNumber(NAME, "Acc", CFG.Acceleration)
local accelerating, decelerating = false, false
local steerValue = 0
local spinSpeed = K.loadPrefixedNumber(NAME, "Spin", 0)
local cruise, stopped = false, false
local targetSpeed = 0
local locked = false
local lockModel, lockPart = nil, nil
local lockPartScore = 0
local manualLockUntil = 0
local lastAutoScan = 0
local lastOwnedCheck = 0
local noClip = K.loadPrefixed(NAME, "NoClip", false) == true
local carFly = false
local flyUp, flyDown = false, false
local flyVertVel = 0
local drive = nil
local carFlyHandle = nil
local spinHandle = nil
local lightsOn = false
local nativeHead, nativeTail = {}, {}
local createdLamps = {}
local lightSteady = false
local hornSteady = false
local flashUntil, beepUntil = 0, 0
local hornKeyIsDown = false
local clipParts, clipWheels = {}, {}
local clipDirty = true
local clipOriginal = setmetatable({}, {__mode = "k"})
local clipSetState = setmetatable({}, {__mode = "k"})
local clipModel = nil
local clipFalling = false
local reverseHold = false
local myVehicleModel, myVehicleName, myVehicleAsm = nil, nil, nil
local lastAim = nil
local learnedRoots = setmetatable({}, {__mode = "k"})
local modelAddedConn = nil
local vehicleCount = 0
local cachedModels, cachedModelsAt = nil, 0
local lastGrounded = false
local reconnectTarget = nil
local forceRescan = false
local seatMaxSpeedSaved = setmetatable({}, {__mode = "k"})

-- UI 按钮 local（定义早、赋值晚：帮助函数可先引用）
local switchButton, stopButton

-- 前向声明：这些函数在 20/30/40 才定义，但 20/30 会调用
local clearDrive, ensureDrive, rearmLights, collectEngineSounds

-- 扫描根与轮毂识别
local SCAN_ROOT_NAMES = {"Vehicles", "Cars", "Spawned", "PlayerVehicles", "Driveable",
	"CarSpawns", "Bricks", "Blocks", "Drift"}
local WHEEL_CORNERS = {"fl", "fr", "rl", "rr", "lf", "lr", "rf"}

-- 急刹按钮刷新（仅依赖状态与 stopButton local，可最早定义）
local function refreshStopButton()
	if not stopButton then return end
	stopButton.Text = stopped and "急刹 开" or "急刹 关"
	stopButton.BackgroundColor3 = stopped and CFG.Col.On or CFG.Col.Stop
end
