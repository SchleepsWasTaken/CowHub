-- Gunung Nomaly Utility GUI
-- Fly mode + checkpoint teleports + optional tap-to-teleport on checkpoints
-- Works on Delta/Xeno executors and Roblox Studio test (LocalScript)
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
local Players   = game:GetService("Players")
local RunService= game:GetService("RunService")
local UIS       = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- Character refs (safe getters)
local function getCharacter()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp  = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart")
    local hum  = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
    return char, hrp, hum
end

-- Refs that update on respawn
local Character, HRP, Humanoid = getCharacter()
LocalPlayer.CharacterAdded:Connect(function(c)
    Character = c
    HRP = c:WaitForChild("HumanoidRootPart")
    Humanoid = c:WaitForChild("Humanoid")
    -- stop fly/noclip on respawn just in case
    pcall(function()
        if Humanoid then Humanoid.PlatformStand = false end
    end)
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if noclipOn then enableNoclip(true) end
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

    -- control loop
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

            if move.Magnitude > 0 then
                move = move.Unit * flySpeed
            end

            vel.Velocity = move
            -- Orient the body to face camera forward (correct CFrame uses world position target)
            local pos = HRP.Position
            gyro.CFrame = CFrame.new(pos, pos + cf.LookVector)

            RunService.Heartbeat:Wait()
        end
    end)

    Rayfield:Notify({ Title = "Flying Enabled", Content = "Use WASD/Space/Shift.", Duration = 3 })
end

local function stopFlying()
    if not isFlying then return end
    isFlying = false
    if vel then vel:Destroy() vel = nil end
    if gyro then gyro:Destroy() gyro = nil end
    if Humanoid then Humanoid.PlatformStand = false end
    Rayfield:Notify({ Title = "Flying Disabled", Content = "Flight off.", Duration = 3 })
end

-- Noclip (NEW)
local function setCharacterCollide(on)
    if not Character then return end
    for _, d in ipairs(Character:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = on
        end
    end
end

noclipOn = false
noclipConn = nil
function enableNoclip(on)
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
FlightTab:CreateToggle({
    Name = "Toggle Fly",
    CurrentValue = false,
    Callback = function(v)
        if v then startFlying() else stopFlying() end
    end
})

FlightTab:CreateSlider({
    Name = "Fly Speed",
    Range = {10, MAX_SPEED},
    Increment = 5,
    Suffix = "speed",
    CurrentValue = flySpeed,
    Callback = function(v)
        flySpeed = v
        Rayfield:Notify({ Title = "Speed Updated", Content = "Fly speed = "..v, Duration = 2 })
    end
})

FlightTab:CreateToggle({
    Name = "Noclip (no collisions)",
    CurrentValue = false,
    Callback = function(v)
        enableNoclip(v)
        Rayfield:Notify({ Title = v and "Noclip ON" or "Noclip OFF", Content = v and "Collisions disabled" or "Collisions restored", Duration = 2 })
    end
})

FlightTab:CreateLabel("Tip: Space=up, Shift=down. Camera decides direction.")

-- Ensure fly stops if character dies
if Humanoid then
    Humanoid.Died:Connect(function()
        stopFlying()
        enableNoclip(false)
    end)
end

-- ====================
-- Checkpoint detection (numeric names + Summit) WITH DROPDOWN UI (no infinite scroll)
-- ====================
local checkpoints = {} -- { name=string, root=Instance, getCFrame=function():CFrame }
local cpIndexByName = {}
local labelDetected
local dropdown -- Rayfield dropdown element
local selectedName
local CP_FOLDER_NAME = "Checkpoints"
local CheckpointsFolder

local function resolveFolder()
    CheckpointsFolder = Workspace:FindFirstChild(CP_FOLDER_NAME)
    return CheckpointsFolder
end

local function buildCheckpointEntry(child)
    local entry = { name = child.Name, root = child }
    if child:IsA("BasePart") then
        entry.getCFrame = function() return child.CFrame end
    elseif child:IsA("Model") then
        entry.getCFrame = function()
            if child.PrimaryPart then return child.PrimaryPart.CFrame end
            local cf = child:GetBoundingBox()
            return cf
        end
    else
        entry.getCFrame = function() return child:GetPivot() end
    end
    return entry
end

local function collectCheckpoints()
    checkpoints = {}
    cpIndexByName = {}
    local folder = resolveFolder()
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("BasePart") or child:IsA("Model") then
                local e = buildCheckpointEntry(child)
                table.insert(checkpoints, e)
            end
        end
    end
    -- Sort: numeric asc, then alpha, Summit last
    for _, it in ipairs(checkpoints) do
        local n = tonumber(it.name)
        local lower = string.lower(it.name)
        local summit = (lower == "summit")
        if summit then
            it._group, it._key = 2, math.huge
        elseif n then
            it._group, it._key = 0, n
        else
            it._group, it._key = 1, lower
        end
    end
    table.sort(checkpoints, function(a,b)
        if a._group ~= b._group then return a._group < b._group end
        return a._key < b._key
    end)
    for i, it in ipairs(checkpoints) do cpIndexByName[it.name] = i end
end

local function namesList()
    local t = {}
    for i, cp in ipairs(checkpoints) do t[i] = cp.name end
    return t
end

local function updateDetectedLabel()
    local text
    if #checkpoints > 0 then
        text = "Detected Checkpoints: " .. table.concat(namesList(), ", ")
    else
        text = "No checkpoints found in Workspace."..CP_FOLDER_NAME
    end
    if labelDetected and labelDetected.Set then
        pcall(function() labelDetected:Set(text) end)
    else
        labelDetected = TPTab:CreateLabel(text)
    end
end

-- Build/refresh the dropdown UI
local function rebuildDropdownUI()
    local options = namesList()
    if dropdown and dropdown.Set then
        pcall(function()
            dropdown:Set(options)
        end)
    else
        dropdown = TPTab:CreateDropdown({
            Name = "Choose checkpoint",
            Options = options,
            CurrentOption = options[1],
            Multiple = false,
            Callback = function(opt)
                -- Rayfield may pass a string or a table with one string
                if typeof(opt) == "table" then opt = opt[1] end
                selectedName = opt
            end
        })
    end
    if options[1] and not selectedName then selectedName = options[1] end
end

-- Teleport helpers
local function teleportToByName(name)
    local idx = cpIndexByName[name]
    if not idx then return end
    local cp = checkpoints[idx]
    local _, hrp, hum = getCharacter()
    if not (hrp and hum and hum.Health > 0) then
        Rayfield:Notify({ Title = "Error", Content = "Player not ready", Duration = 2 })
        return
    end
    hrp.CFrame = cp.getCFrame() * CFrame.new(0, 5, 0)
    Rayfield:Notify({ Title = "Teleported", Content = "To "..cp.name, Duration = 2 })
end

-- Static buttons (operate on dropdown selection)
TPTab:CreateButton({
    Name = "Teleport (selected)",
    Callback = function()
        if selectedName then teleportToByName(selectedName) end
    end
})

TPTab:CreateButton({
    Name = "Auto TP through all",
    Callback = function()
        local _, hrp, hum = getCharacter()
        if not (hrp and hum and hum.Health > 0) then
            Rayfield:Notify({ Title = "Error", Content = "Player not ready", Duration = 2 })
            return
        end
        for _, cp in ipairs(checkpoints) do
            if not hum or hum.Health <= 0 then break end
            hrp.CFrame = cp.getCFrame() * CFrame.new(0, 5, 0)
            task.wait(1)
        end
        Rayfield:Notify({ Title = "Auto TP Complete", Content = "Visited all checkpoints", Duration = 3 })
    end
})

TPTab:CreateButton({
    Name = "Refresh checkpoints",
    Callback = function()
        collectCheckpoints()
        updateDetectedLabel()
        rebuildDropdownUI()
    end
})

-- Initial build
collectCheckpoints()
updateDetectedLabel()
rebuildDropdownUI()

-- Watchers (no duplication, just refresh dropdown)
Workspace.ChildAdded:Connect(function(child)
    if child.Name == CP_FOLDER_NAME then
        CheckpointsFolder = child
        task.wait(0.05)
        collectCheckpoints()
        updateDetectedLabel()
        rebuildDropdownUI()
    end
end)

local function startFolderWatch()
    local folder = resolveFolder()
    if not folder then return end
    folder.ChildAdded:Connect(function(ch)
        if ch:IsA("BasePart") or ch:IsA("Model") then
            task.wait(0.05)
            collectCheckpoints()
            updateDetectedLabel()
            rebuildDropdownUI()
        end
    end)
end
startFolderWatch()

-- ====================
-- Tap-to-teleport (checkpoint-aware, works with Models too)
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

TPTab:CreateToggle({
    Name = "Tap-to-TP on checkpoints (mobile)",
    CurrentValue = false,
    Callback = function(value)
        if touchConn then touchConn:Disconnect() touchConn = nil end
        if value then
            touchConn = UIS.TouchTap:Connect(function(pos, processed)
                if processed then return end
                local r = raycastFromScreen(pos[1])
                if r and r.Instance then
                    -- Find owning checkpoint by ancestry
                    local inst = r.Instance
                    while inst and inst ~= Workspace do
                        if CheckpointsFolder and inst.Parent == CheckpointsFolder then break end
                        inst = inst.Parent
                    end
                    if inst and cpIndexByName[inst.Name] then
                        teleportToByName(inst.Name)
                    end
                end
            end)
            Rayfield:Notify({ Title = "Tap-TP Enabled", Content = "Tap a checkpoint to teleport.", Duration = 3 })
        else
            Rayfield:Notify({ Title = "Tap-TP Disabled", Content = "Tap teleport off.", Duration = 3 })
        end
    end
})

-- ====================
-- Window visibility toggles
-- ====================
local function addVisibilityToggle(tab)
    tab:CreateToggle({
        Name = "Toggle GUI Visibility",
        CurrentValue = true,
        Callback = function(v) Rayfield:ToggleWindow(v) end
    })
end
addVisibilityToggle(FlightTab)
addVisibilityToggle(TPTab)

-- Debug print once
if #checkpoints > 0 then
    print("[Checkpoints] "..table.concat(namesList(), ", "))
else
    print("[Checkpoints] none found")
end

-- Done
