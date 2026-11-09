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
    Visible   = false,
    Radius    = CFG.AIM_FOV,
    Color     = CFG.AIM_FOV_COLOR,
    Thickness = 1,
    Filled    = false,
    Position  = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2),
})

-- ══════════════════════════════════════════════
--  UTILITY
-- ══════════════════════════════════════════════
local function getChar(plr) return plr and plr.Character end

local function getRootAndHuman(plr)
    local c = getChar(plr); if not c then return nil,nil end
    return c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
end

local function isTeammate(plr)
    if not CFG.AIM_TEAM_CHECK then return false end
    return plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team
end

local function worldToScreen(pos)
    local sp,on = Camera:WorldToViewportPoint(pos)
    return Vector2.new(sp.X,sp.Y), on, sp.Z
end

local function getTargetBone(char)
    return char:FindFirstChild(CFG.AIM_BONE) or char:FindFirstChild("HumanoidRootPart")
end

local function distanceTo(plr)
    local root = getRootAndHuman(plr)
    local lroot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root or not lroot then return math.huge end
    return (root.Position - lroot.Position).Magnitude
end

local function isVisible(char, bonePos)
    local origin = Camera.CFrame.Position
    local dir    = bonePos - origin
    local ray    = Ray.new(origin, dir.Unit * dir.Magnitude)
    local hit    = workspace:FindPartOnRayWithIgnoreList(ray, {LocalPlayer.Character})
    if hit == nil then return true end
    return char:IsAncestorOf(hit) or hit:IsDescendantOf(char)
end

local function getPlayerRootPos(plr)
    local char = getChar(plr)
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    return root.Position
end

-- ══════════════════════════════════════════════
--  ESP + SKELETON BUILDER
-- ══════════════════════════════════════════════
local function buildESP(plr)
    if espObjects[plr] then return end
    espObjects[plr] = {
        box    = newDraw("Square",{Visible=false,Color=CFG.ESP_COLOR,  Thickness=CFG.ESP_THICKNESS,Filled=false}),
        name   = newDraw("Text",  {Visible=false,Color=CFG.ESP_COLOR,  Size=13,Center=true,Outline=true}),
        health = newDraw("Text",  {Visible=false,Color=Color3.fromRGB(80,255,120),Size=12,Center=true,Outline=true}),
        dist   = newDraw("Text",  {Visible=false,Color=Color3.fromRGB(180,180,220),Size=11,Center=true,Outline=true}),
    }
    skelObjects[plr] = {}
    for _,pair in ipairs(BONE_PAIRS) do
        local key = pair[1].."__"..pair[2]
        skelObjects[plr][key] = newDraw("Line",{
            Visible=false, Color=CFG.SKE_COLOR, Thickness=CFG.SKE_THICKNESS,
            From=Vector2.new(0,0), To=Vector2.new(0,0),
        })
    end
end

local function removeESP(plr)
    if espObjects[plr] then
        for _,d in pairs(espObjects[plr]) do if d and d.Remove then d:Remove() end end
        espObjects[plr] = nil
    end
    if skelObjects[plr] then
        for _,d in pairs(skelObjects[plr]) do if d and d.Remove then d:Remove() end end
        skelObjects[plr] = nil
    end
end

local function updateESP(plr)
    local esp = espObjects[plr]
    local ske = skelObjects[plr]
    if not esp then return end

    if not CFG.ESP_ENABLED then
        for _,d in pairs(esp) do d.Visible=false end
        if ske then for _,d in pairs(ske) do d.Visible=false end end
        return
    end

    local char = getChar(plr)
    local root,human = getRootAndHuman(plr)
    if not char or not root or not human or human.Health <= 0 then
        for _,d in pairs(esp) do d.Visible=false end
        if ske then for _,d in pairs(ske) do d.Visible=false end end
        return
    end

    local hrpPos = root.Position
    local top2d,onTop = worldToScreen(hrpPos + Vector3.new(0,3.2,0))
    local bot2d,onBot = worldToScreen(hrpPos - Vector3.new(0,3.2,0))

    if not onTop and not onBot then
        for _,d in pairs(esp) do d.Visible=false end
        if ske then for _,d in pairs(ske) do d.Visible=false end end
        return
    end

    local height = math.abs(top2d.Y - bot2d.Y)
    local width  = height * 0.5
    local cx     = (top2d.X + bot2d.X) / 2

    esp.box.Visible = CFG.ESP_BOX
    if CFG.ESP_BOX then
        esp.box.Position = Vector2.new(cx - width/2, top2d.Y)
        esp.box.Size     = Vector2.new(width, height)
    end
    esp.name.Visible = CFG.ESP_NAME
    if CFG.ESP_NAME then
        esp.name.Text     = plr.Name
        esp.name.Position = Vector2.new(cx, top2d.Y - 16)
    end
    esp.health.Visible = CFG.ESP_HEALTH
    if CFG.ESP_HEALTH then
        esp.health.Text     = math.floor(human.Health).." HP"
        esp.health.Position = Vector2.new(cx, bot2d.Y + 2)
    end
    esp.dist.Visible = CFG.ESP_DISTANCE
    if CFG.ESP_DISTANCE then
        esp.dist.Text     = math.floor(distanceTo(plr)).."m"
        esp.dist.Position = Vector2.new(cx, bot2d.Y + 14)
    end

    if ske then
        for _,pair in ipairs(BONE_PAIRS) do
            local key  = pair[1].."__"..pair[2]
            local line = ske[key]
            if not line then continue end
            if not CFG.SKE_ENABLED then line.Visible=false continue end
            local b0 = char:FindFirstChild(pair[1])
            local b1 = char:FindFirstChild(pair[2])
            if not b0 or not b1 then line.Visible=false continue end
            local s0,on0 = worldToScreen(b0.Position)
            local s1,on1 = worldToScreen(b1.Position)
            if not on0 or not on1 then line.Visible=false continue end
            line.From    = s0
            line.To      = s1
            line.Visible = true
        end
    end
end

--[=[
Fluent GUI - single-file bundle
Combines Fluent, SaveManager, InterfaceManager, and the supplied example.
Original Fluent project: https://github.com/dawid-scripts/Fluent
]=]

local Fluent = (function()
--[[
    Fluent Interface Suite
    This script is not intended to be modified.
    To view the source code, see the 'src' folder on GitHub!

    Author: dawid
    License: MIT
    GitHub: https://github.com/dawid-scripts/Fluent
--]]

local a,b={{1,'ModuleScript',{'MainModule'},{{18,'ModuleScript',{'Creator'}},{28,'ModuleScript',{'Icons'}},{47,'ModuleScript',{'Themes'},{{50,'ModuleScript',{'Dark'}},{52,'ModuleScript',{'Light'}},{51,'ModuleScript',{'Darker'}},{53,'ModuleScript',{'Rose'}},{49,'ModuleScript',{'Aqua'}},{48,'ModuleScript',{'Amethyst'}}}},{19,'ModuleScript',{'Elements'},{{21,'ModuleScript',{'Colorpicker'}},{27,'ModuleScript',{'Toggle'}},{23,'ModuleScript',{'Input'}},{20,'ModuleScript',{'Button'}},{25,'ModuleScript',{'Paragraph'}},{22,'ModuleScript',{'Dropdown'}},{26,'ModuleScript',{'Slider'}},{24,'ModuleScript',{'Keybind'}}}},{29,'Folder',{'Packages'},{{30,'ModuleScript',{'Flipper'},{{33,'ModuleScript',{'GroupMotor'}},{46,'ModuleScript',{'isMotor.spec'}},{39,'ModuleScript',{'Signal'}},{40,'ModuleScript',{'Signal.spec'}},{45,'ModuleScript',{'isMotor'}},{36,'ModuleScript',{'Instant.spec'}},{44,'ModuleScript',{'Spring.spec'}},{42,'ModuleScript',{'SingleMotor.spec'}},{38,'ModuleScript',{'Linear.spec'}},{31,'ModuleScript',{'BaseMotor'}},{43,'ModuleScript',{'Spring'}},{35,'ModuleScript',{'Instant'}},{37,'ModuleScript',{'Linear'}},{41,'ModuleScript',{'SingleMotor'}},{34,'ModuleScript',{'GroupMotor.spec'}},{32,'ModuleScript',{'BaseMotor.spec'}}}}}},{2,'ModuleScript',{'Acrylic'},{{3,'ModuleScript',{'AcrylicBlur'}},{5,'ModuleScript',{'CreateAcrylic'}},{6,'ModuleScript',{'Utils'}},{4,'ModuleScript',{'AcrylicPaint'}}}},{7,'Folder',{'Components'},{{9,'ModuleScript',{'Button'}},{12,'ModuleScript',{'Notification'}},{13,'ModuleScript',{'Section'}},{17,'ModuleScript',{'Window'}},{14,'ModuleScript',{'Tab'}},{10,'ModuleScript',{'Dialog'}},{8,'ModuleScript',{'Assets'}},{16,'ModuleScript',{'TitleBar'}},{15,'ModuleScript',{'Textbox'}},{11,'ModuleScript',{'Element'}}}}}}}local aa={function()local c,d,e,f,g=b(1)local h,i,j,k,l,m=game:GetService'Lighting',game:GetService'RunService',game:GetService'Players'.LocalPlayer,game:GetService'UserInputService',game:GetService'TweenService',game:GetService'Workspace'.CurrentCamera local n,o=j:GetMouse(),d local p,q,r,s=e(o.Creator),e(o.Elements),e(o.Acrylic),o.Components local t,u,v=e(s.Notification),p.New,protectgui or(syn and syn.protect_gui)or function()end local w=u('ScreenGui',{Parent=i:IsStudio()and j.PlayerGui or game:GetService'CoreGui'})v(w)t:Init(w)local x={Version='1.1.0',OpenFrames={},Options={},Themes=e(o.Themes).Names,Window=nil,WindowFrame=nil,Unloaded=false,Theme='Dark',DialogOpen=false,UseAcrylic=false,Acrylic=false,Transparency=true,MinimizeKeybind=nil,MinimizeKey=Enum.KeyCode.LeftControl,GUI=w}function x.SafeCallback(y,z,...)if not z then return end local A,B=pcall(z,...)if not A then local C,D=B:find':%d+: 'if not D then return x:Notify{Title='Interface',Content='Callback error',SubContent=B,Duration=5}end return x:Notify{Title='Interface',Content='Callback error',SubContent=B:sub(D+1),Duration=5}end end function x.Round(y,z,A)if A==0 then return math.floor(z)end z=tostring(z)return z:find'%.'and tonumber(z:sub(1,z:find'%.'+A))or z end local y=e(o.Icons).assets function x.GetIcon(z,A)if A~=nil and y['lucide-'..A]then return y['lucide-'..A]end return nil end local z={}z.__index=z z.__namecall=function(A,B,...)return z[B](...)end for A,B in ipairs(q)do z['Add'..B.__type]=function(C,D,E)B.Container=C.Container B.Type=C.Type B.ScrollFrame=C.ScrollFrame B.Library=x return B:New(D,E)end end x.Elements=z function x.CreateWindow(C,D)assert(D.Title,'Window - Missing Title')if x.Window then print'You cannot create more than one window.'return end x.MinimizeKey=D.MinimizeKey x.UseAcrylic=D.Acrylic if D.Acrylic then r.init()end local E=e(s.Window){Parent=w,Size=D.Size,Title=D.Title,SubTitle=D.SubTitle,TabWidth=D.TabWidth}x.Window=E x:SetTheme(D.Theme)return E end function x.SetTheme(C,D)if x.Window and table.find(x.Themes,D)then x.Theme=D p.UpdateTheme()end end function x.Destroy(C)if x.Window then x.Unloaded=true if x.UseAcrylic then x.Window.AcrylicPaint.Model:Destroy()end p.Disconnect()x.GUI:Destroy()end end function x.ToggleAcrylic(C,D)if x.Window then if x.UseAcrylic then x.Acrylic=D x.Window.AcrylicPaint.Model.Transparency=D and 0.98 or 1 if D then r.Enable()else r.Disable()end end end end function x.ToggleTransparency(C,D)if x.Window then x.Window.AcrylicPaint.Frame.Background.BackgroundTransparency=D and 0.35 or 0 end end function x.Notify(C,D)return t:New(D)end if getgenv then getgenv().Fluent=x end return x end,function()local c,d,e,f,g=b(2)local h={AcrylicBlur=e(d.AcrylicBlur),CreateAcrylic=e(d.CreateAcrylic),AcrylicPaint=e(d.AcrylicPaint)}function h.init()local i=Instance.new'DepthOfFieldEffect'i.FarIntensity=0 i.InFocusRadius=0.1 i.NearIntensity=1 local j={}function h.Enable()for k,l in pairs(j)do l.Enabled=false end i.Parent=game:GetService'Lighting'end function h.Disable()for k,l in pairs(j)do l.Enabled=l.enabled end i.Parent=nil end local k=function()local k=function(k)if k:IsA'DepthOfFieldEffect'then j[k]={enabled=k.Enabled}end end for l,m in pairs(game:GetService'Lighting':GetChildren())do k(m)end if game:GetService'Workspace'.CurrentCamera then for n,o in pairs(game:GetService'Workspace'.CurrentCamera:GetChildren())do k(o)end end end k()h.Enable()end return h end,function()local c,d,e,f,g=b(3)local h,i,j,k=e(d.Parent.Parent.Creator),e(d.Parent.CreateAcrylic),unpack(e(d.Parent.Utils))local l=function(l)local m={}l=l or 0.001 local n,o={topLeft=Vector2.new(),topRight=Vector2.new(),bottomRight=Vector2.new()},i()o.Parent=workspace local p,q=function(p,q)n.topLeft=q n.topRight=q+Vector2.new(p.X,0)n.bottomRight=q+p end,function()local p=game:GetService'Workspace'.CurrentCamera if p then p=p.CFrame end local q=p if not q then q=CFrame.new()end local r,s,t,u=q,n.topLeft,n.topRight,n.bottomRight local v,w,x=j(s,l),j(t,l),j(u,l)local y,z=(w-v).Magnitude,(w-x).Magnitude o.CFrame=CFrame.fromMatrix((v+x)/2,r.XVector,r.YVector,r.ZVector)o.Mesh.Scale=Vector3.new(y,z,0)end local r,s=function(r)local s=k()local t,u=r.AbsoluteSize-Vector2.new(s,s),r.AbsolutePosition+Vector2.new(s/2,s/2)p(t,u)task.spawn(q)end,function()local r=game:GetService'Workspace'.CurrentCamera if not r then return end table.insert(m,r:GetPropertyChangedSignal'CFrame':Connect(q))table.insert(m,r:GetPropertyChangedSignal'ViewportSize':Connect(q))table.insert(m,r:GetPropertyChangedSignal'FieldOfView':Connect(q))task.spawn(q)end o.Destroying:Connect(function()for t,u in m do pcall(function()u:Disconnect()end)end end)s()return r,o end return function(m)local n,o,p={},l(m)local q=h.New('Frame',{BackgroundTransparency=1,Size=UDim2.fromScale(1,1)})h.AddSignal(q:GetPropertyChangedSignal'AbsolutePosition',function()o(q)end)h.AddSignal(q:GetPropertyChangedSignal'AbsoluteSize',function()o(q)end)n.AddParent=function(r)h.AddSignal(r:GetPropertyChangedSignal'Visible',function()n.SetVisibility(r.Visible)end)end n.SetVisibility=function(r)p.Transparency=r and 0.98 or 1 end n.Frame=q n.Model=p return n end end,function()local c,d,e,f,g=b(4)local h,i=e(d.Parent.Parent.Creator),e(d.Parent.AcrylicBlur)local j=h.New return function(k)local l={}l.Frame=j('Frame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=0.9,BackgroundColor3=Color3.fromRGB(255,255,255),BorderSizePixel=0},{j('ImageLabel',{Image='rbxassetid://8992230677',ScaleType='Slice',SliceCenter=Rect.new(Vector2.new(99,99),Vector2.new(99,99)),AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.new(1,120,1,116),Position=UDim2.new(0.5,0,0.5,0),BackgroundTransparency=1,ImageColor3=Color3.fromRGB(0,0,0),ImageTransparency=0.7}),j('UICorner',{CornerRadius=UDim.new(0,8)}),j('Frame',{BackgroundTransparency=0.45,Size=UDim2.fromScale(1,1),Name='Background',ThemeTag={BackgroundColor3='AcrylicMain'}},{j('UICorner',{CornerRadius=UDim.new(0,8)})}),j('Frame',{BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=0.4,Size=UDim2.fromScale(1,1)},{j('UICorner',{CornerRadius=UDim.new(0,8)}),j('UIGradient',{Rotation=90,ThemeTag={Color='AcrylicGradient'}})}),j('ImageLabel',{Image='rbxassetid://9968344105',ImageTransparency=0.98,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.new(0,128,0,128),Size=UDim2.fromScale(1,1),BackgroundTransparency=1},{j('UICorner',{CornerRadius=UDim.new(0,8)})}),j('ImageLabel',{Image='rbxassetid://9968344227',ImageTransparency=0.9,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.new(0,128,0,128),Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ThemeTag={ImageTransparency='AcrylicNoise'}},{j('UICorner',{CornerRadius=UDim.new(0,8)})}),j('Frame',{BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=2},{j('UICorner',{CornerRadius=UDim.new(0,8)}),j('UIStroke',{Transparency=0.5,Thickness=1,ThemeTag={Color='AcrylicBorder'}})})})local m if e(d.Parent.Parent).UseAcrylic then m=i()m.Frame.Parent=l.Frame l.Model=m.Model l.AddParent=m.AddParent l.SetVisibility=m.SetVisibility end return l end end,function()local c,d,e,f,g=b(5)local h=d.Parent.Parent local i=e(h.Creator)local j=function()local j=i.New('Part',{Name='Body',Color=Color3.new(0,0,0),Material=Enum.Material.Glass,Size=Vector3.new(1,1,0),Anchored=true,CanCollide=false,Locked=true,CastShadow=false,Transparency=0.98},{i.New('SpecialMesh',{MeshType=Enum.MeshType.Brick,Offset=Vector3.new(0,0,-1E-6)})})return j end return j end,function()local c,d,e,f,g=b(6)local h,i=function(h,i,j,k,l)return(h-i)*(l-k)/(j-i)+k end,function(h,i)local j=game:GetService'Workspace'.CurrentCamera:ScreenPointToRay(h.X,h.Y)return j.Origin+j.Direction*i end local j=function()local j=game:GetService'Workspace'.CurrentCamera.ViewportSize.Y return h(j,0,2560,8,56)end return{i,j}end,[8]=function()local c,d,e,f,g=b(8)return{Close='rbxassetid://9886659671',Min='rbxassetid://9886659276',Max='rbxassetid://9886659406',Restore='rbxassetid://9886659001'}end,[9]=function()local c,d,e,f,g=b(9)local h=d.Parent.Parent local i,j=e(h.Packages.Flipper),e(h.Creator)local k,l=j.New,i.Spring.new return function(m,n,o)o=o or false local p={}p.Title=k('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',TextColor3=Color3.fromRGB(200,200,200),TextSize=14,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center,BackgroundColor3=Color3.fromRGB(255,255,255),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,S
