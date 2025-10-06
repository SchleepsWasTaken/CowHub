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
    -- stop fly on respawn just in case
    pcall(function()
        if Humanoid then Humanoid.PlatformStand = false end
    end)
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

-- UI controls for fly
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

FlightTab:CreateLabel("Tip: Space=up, Shift=down. Camera decides direction.")

-- Ensure fly stops if character dies
if Humanoid then
    Humanoid.Died:Connect(stopFlying)
end

-- ====================
-- Checkpoint detection (revised for numeric names + Summit)
-- ====================
-- Expected structure: Workspace.Checkpoints contains children named "1", "2", ... and possibly "Summit".
-- Children can be BaseParts OR Models. For Models we use PrimaryPart or the model's bounding box.

local checkpoints = {} -- each item: { name=string, root=Instance, getCFrame=function():CFrame }
local labelDetected -- UI label we update once
local CP_FOLDER_NAME = "Checkpoints"
local CP_WAIT_SECS   = 20
local CheckpointsFolder

local function resolveFolder(waitTime)
    if CheckpointsFolder and CheckpointsFolder.Parent then return CheckpointsFolder end
    CheckpointsFolder = Workspace:FindFirstChild(CP_FOLDER_NAME)
    if CheckpointsFolder then return CheckpointsFolder end
    if waitTime and waitTime > 0 then
        local ok, folder = pcall(function()
            return Workspace:WaitForChild(CP_FOLDER_NAME, waitTime)
        end)
        if ok then CheckpointsFolder = folder end
    end
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
        entry.getCFrame = function() return CFrame.new(child:GetPivot().Position) end
    end
    return entry
end

local function collectCheckpoints()
    checkpoints = {}
    local folder = resolveFolder(CP_WAIT_SECS)
    if not folder then
        warn("[Checkpoints] 'Workspace."..CP_FOLDER_NAME.."' not found yet; will auto-refresh when it appears.")
        return
    end
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("BasePart") or child:IsA("Model") then
            table.insert(checkpoints, buildCheckpointEntry(child))
        end
    end
    -- Sort: numeric first ascending, then alpha, with "Summit" forced to last.
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
end

local function namesList(arr)
    local t = {}
    for i, cp in ipairs(arr) do t[i] = cp.name end
    return table.concat(t, ", ")
end

collectCheckpoints()

-- Detected label
local function updateDetectedLabel()
    local text
    if #checkpoints > 0 then
        text = "Detected Checkpoints: " .. namesList(checkpoints)
    else
        text = "No checkpoints found yet in Workspace."..CP_FOLDER_NAME.." (will auto-refresh)."
    end
    if labelDetected and labelDetected.Set then
        pcall(function() labelDetected:Set(text) end)
    else
        labelDetected = TPTab:CreateLabel(text)
    end
end
updateDetectedLabel()

-- Teleport buttons
local function teleportTo(cp)
    local _, hrp, hum = getCharacter()
    if not (hrp and hum and hum.Health > 0) then
        Rayfield:Notify({ Title = "Error", Content = "Player character not ready.", Duration = 3 })
        return
    end
    local cf = cp.getCFrame()
    hrp.CFrame = cf * CFrame.new(0, 5, 0)
    Rayfield:Notify({ Title = "Teleported", Content = "To "..cp.name, Duration = 2 })
end

local function buildButtons()

-- Auto-refresh when the folder appears / changes
Workspace.ChildAdded:Connect(function(child)
    if child.Name == CP_FOLDER_NAME then
        CheckpointsFolder = child
        task.wait(0.1)
        collectCheckpoints()
        updateDetectedLabel()
        buildButtons()
    end
end)

-- If the folder already exists, listen for new children being added later
local function startFolderWatch()
    local folder = resolveFolder(0)
    if not folder then return end
    folder.ChildAdded:Connect(function(ch)
        if ch:IsA("BasePart") or ch:IsA("Model") then
            task.wait(0.05)
            collectCheckpoints()
            updateDetectedLabel()
            buildButtons()
        end
    end)
end
startFolderWatch()
    if #checkpoints == 0 then return end
    for _, cp in ipairs(checkpoints) do
        TPTab:CreateButton({
            Name = "Teleport to "..cp.name,
            Callback = function() teleportTo(cp) end
        })
    end

    TPTab:CreateButton({
        Name = "Auto TP through all",
        Callback = function()
            local _, hrp, hum = getCharacter()
            if not (hrp and hum and hum.Health > 0) then
                Rayfield:Notify({ Title = "Error", Content = "Player character not ready.", Duration = 3 })
                return
            end
            for _, cp in ipairs(checkpoints) do
                if not hum or hum.Health <= 0 then break end
                hrp.CFrame = cp.getCFrame() * CFrame.new(0, 5, 0)
                task.wait(1)
            end
            Rayfield:Notify({ Title = "Auto TP Complete", Content = "Visited all checkpoints.", Duration = 3 })
        end
    })
end

buildButtons()

-- Helper: find which checkpoint a clicked/tapped part belongs to
local function findCheckpointByInstance(inst)
    if not inst then return nil end
    for _, cp in ipairs(checkpoints) do
        if cp.root == inst then return cp end
        if inst:IsDescendantOf(cp.root) then return cp end
    end
    return nil
end

-- Refresh list/buttons
TPTab:CreateButton({
    Name = "Refresh checkpoints",
    Callback = function()
        collectCheckpoints()
        if labelDetected and labelDetected.Set then
            pcall(function()
                labelDetected:Set("Detected Checkpoints: " .. namesList(checkpoints))
            end)
        else
            Rayfield:Notify({ Title = "Refreshed", Content = (#checkpoints).." checkpoints detected.", Duration = 2 })
        end
        -- Note: Rayfield doesn't support removing old buttons; new ones will append.
        buildButtons()
    end
})

-- ====================
-- Tap-to-teleport (checkpoint-aware, works with Models too)
-- ====================
local touchConn

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
    Name = "Tap-to-TP on checkpoints",
    CurrentValue = false,
    Callback = function(value)
        if touchConn then touchConn:Disconnect() touchConn = nil end
        if value then
            touchConn = UIS.TouchTap:Connect(function(pos, processed)
                if processed then return end
                local r = raycastFromScreen(pos[1])
                if r and r.Instance then
                    local cp = findCheckpointByInstance(r.Instance)
                    if cp then teleportTo(cp) end
                end
            end)
            Rayfield:Notify({ Title = "Tap-TP Enabled", Content = "Tap a checkpoint part/model to teleport.", Duration = 3 })
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
    print("[Checkpoints] "..namesList(checkpoints))
else
    print("[Checkpoints] none found")
end

-- Done
