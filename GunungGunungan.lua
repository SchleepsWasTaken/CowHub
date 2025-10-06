-- Gunung Nomaly Utility GUI
-- Fly + Noclip + Checkpoint TP (dropdown) + Tap/Click TP
-- Optimized: guarded waits, deduped connections, no UI growth, safe refresh
-- UI by Rayfield: https://sirius.menu/rayfield

--// Load Rayfield
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

--// Window
local Window = Rayfield:CreateWindow({
    Name = "Gunung Nomaly Utility GUI",
    LoadingTitle = "Flight & TP Script",
    LoadingSubtitle = "by Babang Sekelep",
    ConfigurationSaving = { Enabled = false },
})

--// Tabs
local FlightTab = Window:CreateTab("Flight Controls", 1103511846)
local TPTab    = Window:CreateTab("Checkpoint Teleports", 1103511847)

--// Services & locals
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local Workspace   = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- Utility: bounded WaitForChild
local function SafeWait(parent, name, timeout)
    local obj = parent:FindFirstChild(name)
    if obj then return obj end
    local ok, res = pcall(function()
        return parent:WaitForChild(name, timeout or 5)
    end)
    if ok then return res end
    return nil
end

-- Character refs (safe getters)
local function getCharacter()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp  = char:FindFirstChild("HumanoidRootPart") or SafeWait(char, "HumanoidRootPart", 5)
    local hum  = char:FindFirstChildOfClass("Humanoid") or SafeWait(char, "Humanoid", 5)
    return char, hrp, hum
end

-- Refs that update on respawn
local Character, HRP, Humanoid = getCharacter()

-- forward decls
local enableNoclip
local noclipOn  = false
local noclipConn = nil

LocalPlayer.CharacterAdded:Connect(function(c)
    Character = c
    HRP = SafeWait(c, "HumanoidRootPart", 5)
    Humanoid = SafeWait(c, "Humanoid", 5)
    pcall(function()
        if Humanoid then Humanoid.PlatformStand = false end
    end)
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if noclipOn and enableNoclip then enableNoclip(true) end
end)

-- ====================
-- Fly implementation
-- ====================
local isFlying = false
local flySpeed = 50
local MAX_SPEED = 200
local vel, gyro -- BodyVelocity & BodyGyro

local function startFlying()
    if not Character or not HRP or not Humanoid or Humanoid.Health <= 0 then return end
    if isFlying then return end
    isFlying = true
    Humanoid.PlatformStand = true

    vel = Instance.new("BodyVelocity")
    vel.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    vel.Velocity = Vector3.new()
    vel.Parent = HRP

    gyro = Instance.new("BodyGyro")
    gyro.MaxTorque = Vector3.new(400000, 400000, 400000)
    gyro.P = 3000
    gyro.D = 500
    gyro.Parent = HRP

    task.spawn(function()
        local cam = Workspace.CurrentCamera
        while isFlying and HRP and Humanoid and Humanoid.Health > 0 do
            local move = Vector3.new()
            local cf = cam.CFrame
            if UIS:IsKeyDown(Enum.KeyCode.W) then move += cf.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.S) then move -= cf.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.A) then move -= cf.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.D) then move += cf.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0,1,0) end
            if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then move -= Vector3.new(0,1,0) end
            if move.Magnitude > 0 then move = move.Unit * flySpeed end
            vel.Velocity = move
            local pos = HRP.Position
            gyro.CFrame = CFrame.new(pos, pos + cf.LookVector)
            RunService.Heartbeat:Wait()
        end
    end)
    Rayfield:Notify({ Title = "Flying Enabled", Content = "Use WASD/Space/Shift.", Duration = 2 })
end

local function stopFlying()
    if not isFlying then return end
    isFlying = false
    if vel then vel:Destroy() vel = nil end
    if gyro then gyro:Destroy() gyro = nil end
    if Humanoid then Humanoid.PlatformStand = false end
    Rayfield:Notify({ Title = "Flying Disabled", Content = "Flight off.", Duration = 2 })
end

-- Keybind: toggle fly with F
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.F then
        if isFlying then
            stopFlying(); Rayfield:Notify({Title="Fly", Content="Off (F)", Duration=1})
        else
            startFlying(); Rayfield:Notify({Title="Fly", Content="On (F)", Duration=1})
        end
    end
end)

-- Noclip
local function setCharacterCollide(on)
    if not Character then return end
    for _, d in ipairs(Character:GetDescendants()) do
        if d:IsA("BasePart") then d.CanCollide = on end
    end
end

enableNoclip = function(on)
    noclipOn = on
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if on then
        noclipConn = RunService.Stepped:Connect(function()
            setCharacterCollide(false)
        end)
    else
        setCharacterCollide(true)
    end
end

-- UI controls for fly + noclip
FlightTab:CreateToggle({ Name = "Toggle Fly", CurrentValue = false, Callback = function(v) if v then startFlying() else stopFlying() end end })
FlightTab:CreateSlider({ Name = "Fly Speed", Range = {10, MAX_SPEED}, Increment = 5, Suffix = "speed", CurrentValue = flySpeed, Callback = function(v) flySpeed = v end })
FlightTab:CreateToggle({ Name = "Noclip (no collisions)", CurrentValue = false, Callback = function(v) enableNoclip(v) end })
FlightTab:CreateLabel("Tip: Space=up, Shift=down. Camera decides direction.")

if Humanoid then
    Humanoid.Died:Connect(function() stopFlying(); enableNoclip(false) end)
end

-- ====================
-- Checkpoint detection (EXACT folder, list-all children) WITH DROPDOWN UI
--  - Assumes checkpoints are direct children: Workspace.Checkpoints.<number or name>
--  - Lists EVERY child even if its parts haven't streamed in yet
--  - Anchor (BasePart) is resolved AT TELEPORT TIME
-- ====================
local checkpoints = {} -- { name=string, root=Instance }
local cpIndexByName = {}
local labelDetected
local dropdown -- Rayfield dropdown element
local selectedName
local CP_FOLDER_NAME = "Checkpoints"
local CheckpointsFolder

local folderConn, folderChildConn
local refreshDebounce = false

local function namesArray()
    local t = {}; for i, cp in ipairs(checkpoints) do t[i] = cp.name end; return t
end

local function resolveFolder()
    -- EXACT path only to avoid grabbing the wrong folder elsewhere
    return Workspace:FindFirstChild(CP_FOLDER_NAME)
end

-- Resolve a BasePart to stand on; returns CFrame or nil
local function tryResolveAnchorCF(root)
    if not root then return nil end
    if root:IsA("BasePart") then return root.CFrame end
    if root:IsA("Model") then
        if root.PrimaryPart then return root.PrimaryPart.CFrame end
        local cf = root:GetBoundingBox(); return cf
    end
    -- Folder or other container: search for any BasePart descendant on demand
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("BasePart") then return d.CFrame end
    end
    return nil
end

local function collectCheckpoints()
    checkpoints = {}; cpIndexByName = {}
    local folder = resolveFolder(); CheckpointsFolder = folder
    if not folder then return end

    -- List ALL direct children as checkpoint roots (Folder/Model/Part)
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Folder") or child:IsA("Model") or child:IsA("BasePart") then
            table.insert(checkpoints, { name = child.Name, root = child })
        end
    end

    -- sort: numeric asc (including 0), then alpha, Summit last
    for _, it in ipairs(checkpoints) do
        local n = tonumber(it.name)
        local lower = string.lower(it.name)
        local summit = (lower == "summit")
        if summit then it._group, it._key = 2, math.huge
        elseif n ~= nil then it._group, it._key = 0, n
        else it._group, it._key = 1, lower end
    end
    table.sort(checkpoints, function(a,b) if a._group ~= b._group then return a._group < b._group end return a._key < b._key end)
    for i, it in ipairs(checkpoints) do cpIndexByName[it.name] = i end
end

local function updateDetectedLabel()
    local text = (#checkpoints > 0) and ("Detected Checkpoints: " .. table.concat(namesArray(), ", ")) or ("No children under Workspace.Checkpoints yet.")
    if labelDetected and labelDetected.Set then pcall(function() labelDetected:Set(text) end) else labelDetected = TPTab:CreateLabel(text) end
end

local function rebuildDropdownUI()
    local options = namesArray()
    if dropdown and dropdown.Set then
        local ok = pcall(function() dropdown:Set(options) end)
        if not ok then dropdown = nil end
    end
    if not dropdown then
        dropdown = TPTab:CreateDropdown({
            Name = "Choose checkpoint",
            Options = options,
            CurrentOption = options[1],
            Multiple = false,
            Callback = function(opt)
                if typeof(opt) == "table" then opt = opt[1] end
                selectedName = opt
            end
        })
    end
    if options[1] then selectedName = options[1] end
end

local function refreshUI()
    if refreshDebounce then return end
    refreshDebounce = true
    task.delay(0.25, function() refreshDebounce = false end)
    collectCheckpoints(); updateDetectedLabel(); rebuildDropdownUI()
    print("[CP children] "..(#checkpoints>0 and table.concat(namesArray(), ", ") or "(none)"))
end

-- Buttons
TPTab:CreateButton({ Name = "Teleport (selected)", Callback = function()
    if not selectedName then return end
    local idx = cpIndexByName[selectedName]; if not idx then return end
    local cp = checkpoints[idx]
    local cf = tryResolveAnchorCF(cp.root)
    if not cf then Rayfield:Notify({Title="No anchor yet", Content="No part found inside '"..cp.name.."' (streaming?).", Duration=3}); return end
    local _, hrp, hum = getCharacter(); if not (hrp and hum and hum.Health > 0) then return end
    hrp.CFrame = cf * CFrame.new(0,5,0); Rayfield:Notify({Title="Teleported", Content="To "..cp.name, Duration=2})
end })

TPTab:CreateButton({ Name = "Auto TP through all", Callback = function()
    local _, hrp, hum = getCharacter(); if not (hrp and hum and hum.Health > 0) then return end
    for _, cp in ipairs(checkpoints) do
        local cf = tryResolveAnchorCF(cp.root)
        if cf then hrp.CFrame = cf * CFrame.new(0,5,0); task.wait(1) end
    end
    Rayfield:Notify({ Title = "Auto TP Complete", Content = "Visited all with anchors", Duration = 3 })
end })

TPTab:CreateButton({ Name = "Refresh checkpoints", Callback = refreshUI })

-- Initial build
refreshUI()

-- Watchers for exact folder
if folderConn then folderConn:Disconnect() end
folderConn = Workspace.ChildAdded:Connect(function(child)
    if child.Name == CP_FOLDER_NAME then
        CheckpointsFolder = child; task.wait(0.05); refreshUI()
        if folderChildConn then folderChildConn:Disconnect() end
        folderChildConn = child.ChildAdded:Connect(function(ch)
            if ch:IsA("Folder") or ch:IsA("Model") or ch:IsA("BasePart") then task.wait(0.05); refreshUI() end
        end)
    end
end)

local folder = resolveFolder()
if folder then
    if folderChildConn then folderChildConn:Disconnect() end
    folderChildConn = folder.ChildAdded:Connect(function(ch)
        if ch:IsA("Folder") or ch:IsA("Model") or ch:IsA("BasePart") then task.wait(0.05); refreshUI() end
    end)
end

-- ====================
-- Tap-to-teleport (mobile) + Click-to-teleport (PC)
-- ====================
local function raycastFromScreen(screenPos)
    local cam = Workspace.CurrentCamera
    local unitRay = cam:ViewportPointToRay(screenPos.X, screenPos.Y)
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = { LocalPlayer.Character }
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.IgnoreWater = false
    return Workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, rayParams)
end

local touchConn, mouseClickConn

local function findCheckpointAncestor(inst)
    local folder = CheckpointsFolder or resolveFolder(); if not folder then return nil end
    local cur = inst
    while cur and cur ~= Workspace do
        if cur.Parent == folder then return cur end
        cur = cur.Parent
    end
    return nil
end

TPTab:CreateToggle({ Name = "Tap-to-TP on checkpoints (mobile)", CurrentValue = false, Callback = function(value)
    if touchConn then touchConn:Disconnect() touchConn = nil end
    if value then
        touchConn = UIS.TouchTap:Connect(function(pos, processed)
            if processed then return end
            local r = raycastFromScreen(pos[1])
            if r and r.Instance then
                local owner = findCheckpointAncestor(r.Instance)
                if owner and cpIndexByName[owner.Name] then teleportToByName(owner.Name) end
            end
        end)
        Rayfield:Notify({ Title = "Tap-TP Enabled", Content = "Tap a checkpoint to teleport.", Duration = 2 })
    else
        Rayfield:Notify({ Title = "Tap-TP Disabled", Content = "Tap teleport off.", Duration = 2 })
    end
end })

TPTab:CreateToggle({ Name = "Click-to-TP on checkpoints (PC)", CurrentValue = false, Callback = function(enable)
    if mouseClickConn then mouseClickConn:Disconnect(); mouseClickConn = nil end
    if not enable then return end
    mouseClickConn = UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local pos = UIS:GetMouseLocation()
            local cam = Workspace.CurrentCamera
            local ur = cam:ViewportPointToRay(pos.X, pos.Y)
            local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Blacklist; params.FilterDescendantsInstances = { LocalPlayer.Character }
            local r = Workspace:Raycast(ur.Origin, ur.Direction * 2000, params)
            if r and r.Instance then
                local owner = findCheckpointAncestor(r.Instance)
                if owner and cpIndexByName[owner.Name] then teleportToByName(owner.Name) end
            end
        end
    end)
end })

-- ====================
-- Window visibility toggles
-- ====================
local function addVisibilityToggle(tab)
    tab:CreateToggle({ Name = "Toggle GUI Visibility", CurrentValue = true, Callback = function(v) Rayfield:ToggleWindow(v) end })
end
addVisibilityToggle(FlightTab); addVisibilityToggle(TPTab)

-- Debug print once
if #checkpoints > 0 then print("[Checkpoints] "..table.concat(namesArray(), ", ")) else print("[Checkpoints] none found") end

-- Done
