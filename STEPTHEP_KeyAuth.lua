-- ╔══════════════════════════════════════════════════════╗
-- ║          STEPTHEP  v1.1  |  Urban Reload            ║
-- ║   ESP · Skeleton · FOV Aimbot · Vehicle Lock        ║
-- ║   Executor: Xeno / Synapse X / UNC-compliant        ║
-- ╚══════════════════════════════════════════════════════╝

-- ══════════════════════════════════════════════
--  CONFIG  — ทุกฟีเจอร์ off เริ่มต้น
-- ══════════════════════════════════════════════
local CFG = {
    ESP_ENABLED       = false,
    ESP_BOX           = false,
    ESP_NAME          = false,
    ESP_HEALTH        = false,
    ESP_DISTANCE      = false,
    ESP_COLOR         = Color3.fromRGB(80, 160, 255),
    ESP_THICKNESS     = 1.5,
    SKE_ENABLED       = false,
    SKE_COLOR         = Color3.fromRGB(255, 210, 80),
    SKE_THICKNESS     = 1.2,
    AIM_ENABLED       = false,
    AIM_FOV           = 120,
    AIM_FOV_VISIBLE   = false,
    AIM_FOV_COLOR     = Color3.fromRGB(255, 255, 255),
    AIM_BONE          = "Head",
    AIM_TEAM_CHECK    = false,
    AIM_VISIBLE_CHECK = false,
    AIM_VEHICLE       = false,
    AIM_HEAD_OFFSET   = Vector3.new(0, 0, 0),
    AIM_SMOOTH        = 0.25,
    KEY_LOCK         = Enum.KeyCode.E,
    KEY_ESP_TOGGLE   = Enum.KeyCode.X,
    KEY_FOV_UP       = Enum.KeyCode.RightBracket,
    KEY_FOV_DOWN     = Enum.KeyCode.LeftBracket,
    KEY_UI_TOGGLE    = Enum.KeyCode.Insert,
    KEY_MOUSE_TOGGLE = Enum.KeyCode.LeftAlt,
}

-- ══════════════════════════════════════════════
--  SERVICES
-- ══════════════════════════════════════════════
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UserInputSvc = game:GetService("UserInputService")
local TweenSvc     = game:GetService("TweenService")
local Camera       = workspace.CurrentCamera
local LocalPlayer  = Players.LocalPlayer

-- ══════════════════════════════════════════════
--  STATE
-- ══════════════════════════════════════════════
local espObjects    = {}
local skelObjects   = {}
local lockedTarget  = nil
local aimActive     = false
local uiVisible     = true
local mouseUnlocked = false

local BONE_PAIRS = {
    {"Head","UpperTorso"},  {"Head","Torso"},
    {"UpperTorso","LowerTorso"},
    {"Torso","HumanoidRootPart"},{"UpperTorso","HumanoidRootPart"},
    {"UpperTorso","LeftUpperArm"},  {"LeftUpperArm","LeftLowerArm"},  {"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"}, {"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},  {"LeftUpperLeg","LeftLowerLeg"},  {"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"}, {"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
    {"Torso","Left Arm"},  {"Left Arm","Left Hand"},
    {"Torso","Right Arm"}, {"Right Arm","Right Hand"},
    {"Torso","Left Leg"},  {"Left Leg","Left Foot"},
    {"Torso","Right Leg"}, {"Right Leg","Right Foot"},
}

-- ══════════════════════════════════════════════
--  MOUSE HELPERS
-- ══════════════════════════════════════════════
local function unlockMouse()
    UserInputSvc.MouseBehavior    = Enum.MouseBehavior.Default
    UserInputSvc.MouseIconEnabled = true
    mouseUnlocked = true
end
local function lockMouse()
    UserInputSvc.MouseBehavior    = Enum.MouseBehavior.LockCenter
    UserInputSvc.MouseIconEnabled = false
    mouseUnlocked = false
end

-- ══════════════════════════════════════════════
--  DRAWING HELPERS
-- ══════════════════════════════════════════════
local function newDraw(t, props)
    local d = Drawing.new(t)
    for k,v in pairs(props) do d[k]=v end
    return d
end

local fovCircle = newDraw("Circle",{
