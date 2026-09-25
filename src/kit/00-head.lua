-- kit / 00-head — 服务引用、GUI 根、旧实例清理、绘制后端探测
-- 约定：缩进用单个 Tab；所有 *Alpha 字段按"透明度"理解（0 不透明，1 全透明）

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local NAME = "KIT"
local VERSION = 10

-- 0. GUI 根节点

local function getGuiRoot()
	if gethui then
		local ok, root = pcall(gethui)
		if ok and root then return root end
	end
	return CoreGui
end
local GuiRoot = getGuiRoot()

-- 1. 清理旧实例
-- 同版本重跑只清自己（各模块由自己的 K.mod 负责，不误杀兄弟脚本）；
-- 跨版本升级或首次运行时，额外清理历史遗留的 GUI 名。

local OWN_GUI_NAMES = {NAME, NAME .. "Text", "KIT_Toast"}
local LEGACY_GUI_NAMES = {
	"MinimalStats", "MinimalStatsText", "SIBS", "SIBS_List", "SIBS_Steer",
	"MOC", "DRIFT", "KITLOG", "PLANE",
}

local prevKIT = _G.KIT
local prevClean = _G.KIT_CLEAN_ALL
local needLegacyClean = (type(prevKIT) ~= "table") or (prevKIT.ver ~= VERSION)

if prevClean then pcall(prevClean) end

local function destroyGuis(names)
	for _, n in ipairs(names) do
		local old = GuiRoot:FindFirstChild(n)
		if old then pcall(function() old:Destroy() end) end
	end
end
destroyGuis(OWN_GUI_NAMES)
if needLegacyClean then destroyGuis(LEGACY_GUI_NAMES) end

-- 2. 绘制后端探测

local HAS_DRAWING = (type(Drawing) == "table") and (type(Drawing.new) == "function")

local function tryDrawing(className)
	if not HAS_DRAWING then return nil end
	local ok, obj = pcall(Drawing.new, className)
	if ok and obj then return obj end
	return nil
end
