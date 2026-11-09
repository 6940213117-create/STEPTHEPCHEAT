-- STEPTHEP v1.2 | Urban Reload — FIXED
-- Language: Lua (Luau), Roblox executor script
-- Runtime: Xeno / Synapse X / Delta / UNC-compliant
-- แก้: skeleton ซ้ำ, box offset, miss on respawn

-- ══════════════════════════════════════════════
--  CONFIG
-- ══════════════════════════════════════════════
local CFG = {
    ESP_ENABLED       = true,
    ESP_BOX           = true,
    ESP_NAME          = true,
    ESP_HEALTH        = true,
    ESP_DISTANCE      = true,
    ESP_COLOR         = Color3.fromRGB(80, 160, 255),
    ESP_THICKNESS     = 1.5,
    SKE_ENABLED       = true,
    SKE_COLOR         = Color3.fromRGB(255, 210, 80),
    SKE_THICKNESS     = 1.2,
    AIM_ENABLED       = false,
    AIM_FOV           = 120,
    AIM_FOV_VISIBLE   = false,
    AIM_FOV_COLOR     = Color3.fromRGB(255, 255, 255),
    AIM_BONE          = "Head",
    AIM_TEAM_CHECK    = false,
    AIM_VISIBLE_CHECK = false,
    AIM_SMOOTH        = 0.25,
    KEY_ESP_TOGGLE    = Enum.KeyCode.X,
    KEY_FOV_UP        = Enum.KeyCode.RightBracket,
    KEY_FOV_DOWN      = Enum.KeyCode.LeftBracket,
}

-- ══════════════════════════════════════════════
--  SERVICES
-- ══════════════════════════════════════════════
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UserInputSvc = game:GetService("UserInputService")
local Camera       = workspace.CurrentCamera
local LocalPlayer  = Players.LocalPlayer

-- ══════════════════════════════════════════════
--  STATE
-- ══════════════════════════════════════════════
local espObjects = {}
local skelObjects = {}

-- R15 + R6 bone pairs ครบ
local BONE_PAIRS = {
    -- R15
    {"Head","UpperTorso"},
    {"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},  {"LeftUpperArm","LeftLowerArm"},  {"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"}, {"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},  {"LeftUpperLeg","LeftLowerLeg"},  {"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"}, {"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
    -- R6
    {"Head","Torso"},
    {"Torso","Left Arm"},  {"Left Arm","Left Hand"},
    {"Torso","Right Arm"}, {"Right Arm","Right Hand"},
    {"Torso","Left Leg"},  {"Left Leg","Left Foot"},
    {"Torso","Right Leg"}, {"Right Leg","Right Foot"},
}

-- ══════════════════════════════════════════════
--  UTILITY
-- ══════════════════════════════════════════════
local function getChar(plr)
    return plr and plr.Character
end

local function getRootAndHuman(plr)
    local c = getChar(plr)
    if not c then return nil, nil end
    return c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
end

local function distanceTo(plr)
    local root = getRootAndHuman(plr)
    local lc   = LocalPlayer.Character
    local lr   = lc and lc:FindFirstChild("HumanoidRootPart")
    if not root or not lr then return math.huge end
    return (root.Position - lr.Position).Magnitude
end

-- FIX: bounding box จริง ไม่ใช่ ±3.2 fixed
local function getScreenBounds(char)
    local parts = {}
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            table.insert(parts, v)
        end
    end
    if #parts == 0 then return nil end

    local minX, minY = math.huge,  math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyOn = false

    for _, part in ipairs(parts) do
        local sp = Camera:WorldToViewportPoint(part.Position)
        if sp.Z > 0 then
            anyOn = true
            minX = math.min(minX, sp.X)
            minY = math.min(minY, sp.Y)
            maxX = math.max(maxX, sp.X)
            maxY = math.max(maxY, sp.Y)
        end
    end

    if not anyOn then return nil end
    return minX, minY, maxX - minX, maxY - minY
end

-- ══════════════════════════════════════════════
--  DRAWING HELPERS
-- ══════════════════════════════════════════════
local function newDraw(t, props)
    local d = Drawing.new(t)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local fovCircle = newDraw("Circle", {
    Visible   = CFG.AIM_FOV_VISIBLE,
    Radius    = CFG.AIM_FOV,
    Color     = CFG.AIM_FOV_COLOR,
    Thickness = 1,
    Filled    = false,
    Position  = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2),
})

-- ══════════════════════════════════════════════
--  BUILD ESP PER PLAYER
-- ══════════════════════════════════════════════
local function buildESP(plr)
    if espObjects[plr] then return end
    espObjects[plr] = {
        box   = newDraw("Square", {Visible=false, Color=CFG.ESP_COLOR, Thickness=CFG.ESP_THICKNESS, Filled=false}),
        name  = newDraw("Text",   {Visible=false, Color=CFG.ESP_COLOR, Size=13, Center=true, Outline=true}),
        dist  = newDraw("Text",   {Visible=false, Color=Color3.fromRGB(180,180,220), Size=11, Center=true, Outline=true}),
        HpBg  = newDraw("Square", {Visible=false, Color=Color3.fromRGB(0,0,0), Filled=true, Thickness=1}),
        HpBar = newDraw("Square", {Visible=false, Color=Color3.fromRGB(50,255,50), Filled=true, Thickness=1}),
    }
    skelObjects[plr] = {}
    for _, pair in ipairs(BONE_PAIRS) do
        local key = pair[1] .. "__" .. pair[2]
        skelObjects[plr][key] = newDraw("Line", {
            Visible   = false,
            Color     = CFG.SKE_COLOR,
            Thickness = CFG.SKE_THICKNESS,
            From      = Vector2.new(0, 0),
            To        = Vector2.new(0, 0),
        })
    end
end

local function removeESP(plr)
    if espObjects[plr] then
        for _, d in pairs(espObjects[plr]) do
            if d and d.Remove then d:Remove() end
        end
        espObjects[plr] = nil
    end
    if skelObjects[plr] then
        for _, d in pairs(skelObjects[plr]) do
            if d and d.Remove then d:Remove() end
        end
        skelObjects[plr] = nil
    end
end

-- ══════════════════════════════════════════════
--  UPDATE ESP — FIX MAIN (skeleton block เดียว, bounding box จริง)
-- ══════════════════════════════════════════════
local function updateESP(plr)
    local esp = espObjects[plr]
    local ske = skelObjects[plr]
    if not esp then return end

    local function hideAll()
        for _, d in pairs(esp) do d.Visible = false end
        if ske then for _, d in pairs(ske) do d.Visible = false end end
    end

    if not CFG.ESP_ENABLED then hideAll(); return end

    local char = getChar(plr)
    local root, human = getRootAndHuman(plr)
    if not char or not root or not human or human.Health <= 0 then
        hideAll(); return
    end

    -- FIX: ใช้ bounding box จริงจากทุก part
    local bX, bY, bW, bH = getScreenBounds(char)
    if not bX then hideAll(); return end
    if bH < 2 then hideAll(); return end

    -- padding เล็กน้อย
    local pad = 2
    bX = bX - pad
    bY = bY - pad
    bW = bW + pad * 2
    bH = bH + pad * 2

    -- Box
    esp.box.Visible = CFG.ESP_BOX
    if CFG.ESP_BOX then
        esp.box.Position = Vector2.new(bX, bY)
        esp.box.Size     = Vector2.new(bW, bH)
    end

    -- Name
    esp.name.Visible = CFG.ESP_NAME
    if CFG.ESP_NAME then
        esp.name.Text     = plr.Name
        esp.name.Position = Vector2.new(bX + bW / 2, bY - 16)
    end

    -- Distance
    esp.dist.Visible = CFG.ESP_DISTANCE
    if CFG.ESP_DISTANCE then
        esp.dist.Text     = math.floor(distanceTo(plr)) .. "m"
        esp.dist.Position = Vector2.new(bX + bW / 2, bY + bH + 2)
    end

    -- Health Bar
    if CFG.ESP_HEALTH then
        local r     = math.clamp(human.Health / math.max(human.MaxHealth, 1), 0, 1)
        local barX  = bX - 7
        esp.HpBg.Size     = Vector2.new(4, bH)
        esp.HpBg.Position = Vector2.new(barX, bY)
        esp.HpBg.Visible  = true
        esp.HpBar.Size     = Vector2.new(4, math.max(1, bH * r))
        esp.HpBar.Position = Vector2.new(barX, bY + bH * (1 - r))
        esp.HpBar.Color    = Color3.fromRGB(
            math.floor(255 * (1 - r)),
            math.floor(255 * r), 0)
        esp.HpBar.Visible = true
    else
        esp.HpBg.Visible  = false
        esp.HpBar.Visible = false
    end

    -- FIX: skeleton block เดียว ใช้ .Z > 0 เป็น depth check (ลบบล็อกซ้ำออก)
    if ske then
        for _, pair in ipairs(BONE_PAIRS) do
            local key  = pair[1] .. "__" .. pair[2]
            local line = ske[key]
            if not line then continue end
            if not CFG.SKE_ENABLED then line.Visible = false; continue end

            local b0 = char:FindFirstChild(pair[1])
            local b1 = char:FindFirstChild(pair[2])
            if not b0 or not b1 then line.Visible = false; continue end

            local s0 = Camera:WorldToViewportPoint(b0.Position)
            local s1 = Camera:WorldToViewportPoint(b1.Position)
            if s0.Z <= 0 or s1.Z <= 0 then line.Visible = false; continue end

            line.From    = Vector2.new(s0.X, s0.Y)
            line.To      = Vector2.new(s1.X, s1.Y)
            line.Visible = true
        end
    end
end

-- ══════════════════════════════════════════════
--  AIMBOT (ถ้าเปิด)
-- ══════════════════════════════════════════════
local function getBestTarget()
    local best, bestDist = nil, math.huge
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        local char = getChar(plr)
        local root, human = getRootAndHuman(plr)
        if not char or not root or not human or human.Health <= 0 then continue end

        local bone = char:FindFirstChild(CFG.AIM_BONE) or root
        local sp   = Camera:WorldToViewportPoint(bone.Position)
        if sp.Z <= 0 then continue end

        local screenPos = Vector2.new(sp.X, sp.Y)
        local d = (screenPos - center).Magnitude
        if d < CFG.AIM_FOV and d < bestDist then
            bestDist = d
            best = bone
        end
    end
    return best
end

-- ══════════════════════════════════════════════
--  PLAYER HOOKS — FIX: CharacterAdded wrap respawn
-- ══════════════════════════════════════════════
local function onPlayerAdded(plr)
    if plr == LocalPlayer then return end
    buildESP(plr)

    -- FIX: rebuild on respawn ด้วย
    plr.CharacterAdded:Connect(function()
        removeESP(plr)
        task.wait(0.5) -- รอ character load
        buildESP(plr)
    end)
end

local function onPlayerRemoving(plr)
    removeESP(plr)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- inject ตอนคนอยู่แล้ว
for _, plr in ipairs(Players:GetPlayers()) do
    onPlayerAdded(plr)
end

-- ══════════════════════════════════════════════
--  RENDER LOOP
-- ══════════════════════════════════════════════
RunService.RenderStepped:Connect(function()
    -- อัพเดต FOV circle
    fovCircle.Visible  = CFG.AIM_ENABLED and CFG.AIM_FOV_VISIBLE
    fovCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    fovCircle.Radius   = CFG.AIM_FOV

    -- ESP
    for plr in pairs(espObjects) do
        updateESP(plr)
    end

    -- Aimbot
    if CFG.AIM_ENABLED and UserInputSvc:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        local bone = getBestTarget()
        if bone then
            local sp = Camera:WorldToViewportPoint(bone.Position)
            if sp.Z > 0 then
                local cf    = Camera.CFrame
                local target = CFrame.new(cf.Position, bone.Position)
                Camera.CFrame = cf:Lerp(target, CFG.AIM_SMOOTH)
            end
        end
    end
end)

-- ══════════════════════════════════════════════
--  KEYBINDS
-- ══════════════════════════════════════════════
UserInputSvc.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == CFG.KEY_ESP_TOGGLE then
        CFG.ESP_ENABLED = not CFG.ESP_ENABLED
    elseif input.KeyCode == CFG.KEY_FOV_UP then
        CFG.AIM_FOV = math.min(CFG.AIM_FOV + 10, 500)
    elseif input.KeyCode == CFG.KEY_FOV_DOWN then
        CFG.AIM_FOV = math.max(CFG.AIM_FOV - 10, 10)
    end
end)

print("[STEPTHEP v1.2] loaded — absolute olliE, bench stayed lit")
