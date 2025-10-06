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
    LoadingSubtitle = "by Grok",
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
-- Checkpoint detection
-- ====================
-- We support:
-- 1) Workspace.Checkpoints folder containing parts named "CheckpointX" (X = number)
-- 2) Any BasePart with Attribute "IsCheckpoint" = true
-- 3) Any BasePart with Name starting with "Checkpoint" (case-insensitive)

local checkpoints = {}

local function isCheckpointPart(p)
    if not p or not p:IsA("BasePart") then return false end
    if p:GetAttribute("IsCheckpoint") == true then return true end
    local n = string.lower(p.Name)
    if string.sub(n,1,10) == "checkpoint" then return true end
    return false
end

local function collectCheckpoints()
    checkpoints = {}
    -- Folder path preferred
    local folder = Workspace:FindFirstChild("Checkpoints")
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if isCheckpointPart(child) then table.insert(checkpoints, child) end
        end
    else
        -- fallback: scan a shallow set of descendants (avoid huge scans)
        for _, child in ipairs(Workspace:GetDescendants()) do
            if child:IsA("BasePart") and isCheckpointPart(child) then
                table.insert(checkpoints, child)
            end
        end
    end
    -- sort by trailing number if present, otherwise by name
    table.sort(checkpoints, function(a,b)
        local na = tonumber(string.match(a.Name, "%d+")) or math.huge
        local nb = tonumber(string.match(b.Name, "%d+")) or math.huge
        if na ~= nb then return na < nb end
        return a.Name < b.Name
    end)
end

local function namesList(arr)
    local t = {}
    for i, cp in ipairs(arr) do t[i] = cp.Name end
    return table.concat(t, ", ")
end

collectCheckpoints()

if #checkpoints > 0 then
    TPTab:CreateLabel("Detected Checkpoints: " .. namesList(checkpoints))
else
    TPTab:CreateLabel("No checkpoints found. Ensure parts are named 'CheckpointX' or set Attribute IsCheckpoint=true.")
end

-- Create buttons
local function buildButtons()
    if #checkpoints == 0 then return end
    for _, cp in ipairs(checkpoints) do
        TPTab:CreateButton({
            Name = "Teleport to "..cp.Name,
            Callback = function()
                local _, hrp, hum = getCharacter()
                if hrp and hum and hum.Health > 0 then
                    hrp.CFrame = cp.CFrame * CFrame.new(0, 5, 0)
                    Rayfield:Notify({ Title = "Teleported", Content = "To "..cp.Name, Duration = 2 })
                else
                    Rayfield:Notify({ Title = "Error", Content = "Player character not ready.", Duration = 3 })
                end
            end
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
                hrp.CFrame = cp.CFrame * CFrame.new(0, 5, 0)
                task.wait(1)
            end
            Rayfield:Notify({ Title = "Auto TP Complete", Content = "Visited all checkpoints.", Duration = 3 })
        end
    })
end

buildButtons()

-- Refresh list/buttons
TPTab:CreateButton({
    Name = "Refresh checkpoints",
    Callback = function()
        collectCheckpoints()
        Rayfield:Notify({ Title = "Refreshed", Content = (#checkpoints).." checkpoints detected.", Duration = 2 })
        -- Rebuild the tab by toggling window (simple way to redraw)
        Rayfield:ToggleWindow(false)
        Rayfield:ToggleWindow(true)
    end
})

-- ====================
-- Tap-to-teleport (only on checkpoint parts)
-- ====================
local tapTPEnabled = false

local function raycastFromScreen(screenPos)
    local cam = Workspace.CurrentCamera
    local unitRay = cam:ViewportPointToRay(screenPos.X, screenPos.Y)
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = { LocalPlayer.Character }
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.IgnoreWater = false
    return Workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, rayParams)
end

local function partIsInCheckpoints(part)
    for _, cp in ipairs(checkpoints) do
        if part == cp then return true end
    end
    return false
end

local touchConn

TPTab:CreateToggle({
    Name = "Tap-to-TP on checkpoints",
    CurrentValue = false,
    Callback = function(value)
        tapTPEnabled = value
        if touchConn then touchConn:Disconnect() touchConn = nil end
        if value then
            touchConn = UIS.TouchTap:Connect(function(pos, processed)
                if processed then return end
                local r = raycastFromScreen(pos[1])
                if r and r.Instance and partIsInCheckpoints(r.Instance) then
                    local _, hrp, hum = getCharacter()
                    if hrp and hum and hum.Health > 0 then
                        hrp.CFrame = r.Instance.CFrame * CFrame.new(0, 5, 0)
                        Rayfield:Notify({ Title = "Teleported", Content = "To "..r.Instance.Name, Duration = 2 })
                    end
                end
            end)
            Rayfield:Notify({ Title = "Tap-TP Enabled", Content = "Tap a checkpoint part to teleport.", Duration = 3 })
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

-- Done
