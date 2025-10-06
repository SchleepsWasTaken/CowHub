-- Gunung Nomaly Utility GUI
-- Fly + Noclip + Checkpoint TP (single persistent slider) + Tap/Click TP
-- Safe Rayfield loader (executor or Studio)

-- === Safe Rayfield loader ===
local Rayfield
do
    local okGet, src = pcall(game.HttpGet, game, "https://sirius.menu/rayfield")
    if okGet and typeof(loadstring) == "function" then
        local fn = loadstring(src)
        if fn then
            local okRun, lib = pcall(fn)
            if okRun and type(lib) == "table" and lib.CreateWindow then Rayfield = lib end
        end
    end
end
if not Rayfield then
    local RS = game:GetService("ReplicatedStorage")
    local okRequire, lib = pcall(function() return require(RS:WaitForChild("Rayfield", 5)) end)
    if okRequire and type(lib) == "table" and lib.CreateWindow then Rayfield = lib end
end
if not Rayfield then warn("[Rayfield] Could not load"); return end

-- === Window & tabs ===
local Window   = Rayfield:CreateWindow({ Name = "Gunung Nomaly Utility GUI",
    LoadingTitle = "Flight & TP Script", LoadingSubtitle = "by Babang Sekelep",
    ConfigurationSaving = {Enabled=false}})
local FlightTab = Window:CreateTab("Flight Controls", 1103511846)
local TPTab     = Window:CreateTab("Checkpoint Teleports", 1103511847)

-- === Services/locals ===
local Players   = game:GetService("Players")
local RunService= game:GetService("RunService")
local UIS       = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LP        = Players.LocalPlayer

local function SafeWait(parent, name, t)
    local x = parent:FindFirstChild(name); if x then return x end
    local ok,res = pcall(function() return parent:WaitForChild(name, t or 5) end)
    if ok then return res end
end

local function getCharacter()
    local c = LP.Character or LP.CharacterAdded:Wait()
    local hrp = c:FindFirstChild("HumanoidRootPart") or SafeWait(c,"HumanoidRootPart",5)
    local hum = c:FindFirstChildOfClass("Humanoid") or SafeWait(c,"Humanoid",5)
    return c, hrp, hum
end

local Character, HRP, Humanoid = getCharacter()

-- === Fly ===
local isFlying, flySpeed, MAX_SPEED = false, 50, 200
local vel, gyro
local function startFlying()
    if not Character or not HRP or not Humanoid or Humanoid.Health<=0 or isFlying then return end
    isFlying = true; Humanoid.PlatformStand = true
    vel = Instance.new("BodyVelocity"); vel.MaxForce = Vector3.new(math.huge,math.huge,math.huge); vel.Parent = HRP
    gyro = Instance.new("BodyGyro");   gyro.MaxTorque = Vector3.new(4e5,4e5,4e5); gyro.P=3000; gyro.D=500; gyro.Parent=HRP
    task.spawn(function()
        local cam = Workspace.CurrentCamera
        while isFlying and HRP and Humanoid and Humanoid.Health>0 do
            local move = Vector3.new(); local cf = cam.CFrame
            if UIS:IsKeyDown(Enum.KeyCode.W) then move += cf.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.S) then move -= cf.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.A) then move -= cf.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.D) then move += cf.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0,1,0) end
            if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then move -= Vector3.new(0,1,0) end
            if move.Magnitude>0 then move = move.Unit*flySpeed end
            vel.Velocity = move; local p = HRP.Position; gyro.CFrame = CFrame.new(p, p+cf.LookVector)
            RunService.Heartbeat:Wait()
        end
    end)
    Rayfield:Notify({Title="Flying Enabled", Content="Use WASD/Space/Shift.", Duration=2})
end
local function stopFlying()
    if not isFlying then return end
    isFlying=false; if vel then vel:Destroy() end; if gyro then gyro:Destroy() end; if Humanoid then Humanoid.PlatformStand=false end
    Rayfield:Notify({Title="Flying Disabled", Duration=2})
end
UIS.InputBegan:Connect(function(i,gp)
    if gp then return end
    if i.UserInputType==Enum.UserInputType.Keyboard and i.KeyCode==Enum.KeyCode.F then
        if isFlying then stopFlying() else startFlying() end
    end
end)

-- === Noclip ===
local noclipOn, noclipConn = false, nil
local function setCollide(on)
    if not Character then return end
    for _,d in ipairs(Character:GetDescendants()) do if d:IsA("BasePart") then d.CanCollide = on end end
end
local function enableNoclip(on)
    noclipOn = on; if noclipConn then noclipConn:Disconnect(); noclipConn=nil end
    if on then noclipConn = RunService.Stepped:Connect(function() setCollide(false) end) else setCollide(true) end
end
if Humanoid then Humanoid.Died:Connect(function() stopFlying(); enableNoclip(false) end) end
LP.CharacterAdded:Connect(function(c)
    Character=c; HRP=SafeWait(c,"HumanoidRootPart",5); Humanoid=SafeWait(c,"Humanoid",5)
    pcall(function() if Humanoid then Humanoid.PlatformStand=false end end)
    if noclipOn then enableNoclip(true) end
end)

-- === Flight tab UI ===
FlightTab:CreateToggle({Name="Toggle Fly", CurrentValue=false, Callback=function(v) if v then startFlying() else stopFlying() end end})
FlightTab:CreateSlider({Name="Fly Speed", Range={10,MAX_SPEED}, Increment=5, Suffix="speed",
    CurrentValue=flySpeed, Callback=function(v) flySpeed=v end})
FlightTab:CreateToggle({Name="Noclip (no collisions)", CurrentValue=false, Callback=function(v) enableNoclip(v) end})
FlightTab:CreateLabel("Tip: Space=up, Shift=down. Camera decides direction.")

-- === Checkpoints: persistent slider ===
local CP_FOLDER_NAME = "Checkpoints"
local checkpoints = {}      -- { {name="1", root=Instance}, ... } (only numeric names + 'Summit' ignored by slider)
local cpIndexByName = {}    -- name -> index in checkpoints
local labelDetected

-- whitelist: numeric only (slider), but we still keep Summit in list for auto-TP if you want later
local function isNumericName(n) return string.match(n, "^%d+$") ~= nil end

local function resolveFolder() return Workspace:FindFirstChild(CP_FOLDER_NAME) end

local function namesArray()
    local t = {}; for i,cp in ipairs(checkpoints) do t[i]=cp.name end; return t
end

local function tryResolveAnchorCF(root)
    if not root then return nil end
    if root:IsA("BasePart") then return root.CFrame end
    if root:IsA("Model") then if root.PrimaryPart then return root.PrimaryPart.CFrame end; local cf = root:GetBoundingBox(); return cf end
    for _,d in ipairs(root:GetDescendants()) do if d:IsA("BasePart") then return d.CFrame end end
    return nil
end

local function collectCheckpoints()
    checkpoints = {}; cpIndexByName={}
    local folder = resolveFolder(); if not folder then return end
    for _, child in ipairs(folder:GetChildren()) do
        if (child:IsA("Folder") or child:IsA("Model") or child:IsA("BasePart")) and isNumericName(child.Name) then
            table.insert(checkpoints, {name=child.Name, root=child})
        end
    end
    table.sort(checkpoints, function(a,b) return tonumber(a.name)<tonumber(b.name) end)
    for i,it in ipairs(checkpoints) do cpIndexByName[it.name]=i end
end

local cpSlider            -- the ONE slider (persistent)
local selectedName        -- string number of currently selected checkpoint
local minN, maxN          -- numeric range snapshot for display only

local function nearestExisting(num)
    local down=num; while down>=0 do if cpIndexByName[tostring(down)] then return tostring(down) end down-=1 end
    local up=num;   while up<=num+1000 do if cpIndexByName[tostring(up)] then return tostring(up)   end up+=1   end
end

local function updateDetectedLabel()
    local text = (#checkpoints>0) and ("Detected Checkpoints: "..table.concat(namesArray(), ", ")) or "No checkpoints yet."
    if labelDetected and labelDetected.Set then pcall(function() labelDetected:Set(text) end) else labelDetected = TPTab:CreateLabel(text) end
end

-- Create the slider ONCE
local function ensureSlider()
    if cpSlider then return end
    cpSlider = TPTab:CreateSlider({
        Name = "Select checkpoint (number)",
        Range = {0, 1},   -- dummy visual range; we manage validity ourselves
        Increment = 1,
        Suffix = "#",
        CurrentValue = 0,
        Callback = function(v)
            -- clamp to nearest valid existing checkpoint
            local nearest = nearestExisting(tonumber(v) or 0)
            selectedName = nearest
        end
    })
end

-- Refresh data and clamp the existing slider (no duplicates)
local function refreshUI()
    collectCheckpoints()
    updateDetectedLabel()
    ensureSlider()

    -- recompute min/max for info and clamp selection
    local nums = {}
    for _,cp in ipairs(checkpoints) do table.insert(nums, tonumber(cp.name)) end
    table.sort(nums)
    minN, maxN = nums[1], nums[#nums]

    -- set a safe default if none selected
    if not selectedName and maxN then selectedName = tostring(maxN) end

    -- try to keep slider's thumb near the selected number (visual only)
    if maxN then
        local ok = pcall(function()
            -- some Rayfield sliders expose .Set; if not, the visual may not move—teleport still uses selectedName
            if cpSlider and cpSlider.Set then cpSlider:Set(tonumber(selectedName) or maxN) end
        end)
    end
end

-- Buttons
TPTab:CreateButton({
    Name="Teleport (selected)",
    Callback=function()
        if not selectedName then Rayfield:Notify({Title="No checkpoint", Content="Use the slider first.", Duration=2}); return end
        local idx = cpIndexByName[selectedName]; if not idx then return end
        local cp = checkpoints[idx]; local cf = tryResolveAnchorCF(cp.root)
        if not cf then Rayfield:Notify({Title="No anchor", Content="No part inside checkpoint yet (streaming).", Duration=2}); return end
        local _,hrp,hum = getCharacter(); if not (hrp and hum and hum.Health>0) then return end
        hrp.CFrame = cf * CFrame.new(0,5,0)
        Rayfield:Notify({Title="Teleported", Content="To "..selectedName, Duration=2})
    end
})
TPTab:CreateButton({
    Name="Auto TP through all",
    Callback=function()
        local _,hrp,hum = getCharacter(); if not (hrp and hum and hum.Health>0) then return end
        for _,cp in ipairs(checkpoints) do
            local cf = tryResolveAnchorCF(cp.root)
            if cf then hrp.CFrame = cf * CFrame.new(0,5,0); task.wait(1) end
        end
        Rayfield:Notify({Title="Auto TP Complete", Duration=3})
    end
})
TPTab:CreateButton({
    Name="Refresh checkpoints",
    Callback=function()
        refreshUI()
        Rayfield:Notify({Title="Refreshed", Content=(#checkpoints).." checkpoints", Duration=1})
    end
})
TPTab:CreateButton({
    Name="Reset to highest",
    Callback=function()
        if #checkpoints==0 then return end
        selectedName = checkpoints[#checkpoints].name
        if cpSlider and cpSlider.Set then pcall(function() cpSlider:Set(tonumber(selectedName)) end) end
    end
})

-- Initial build
refreshUI()

-- Optional: mobile/PC click-to-TP on actual checkpoint parts (kept for convenience)
local function findOwnerUnderFolder(inst, folder)
    local cur=inst; while cur and cur~=Workspace do if cur.Parent==folder then return cur end; cur=cur.Parent end; return nil
end
local function raycastFromScreen(p)
    local cam=Workspace.CurrentCamera; local ur=cam:ViewportPointToRay(p.X, p.Y)
    local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Blacklist; params.FilterDescendantsInstances={LP.Character}
    return Workspace:Raycast(ur.Origin, ur.Direction*2000, params)
end
local touchConn; TPTab:CreateToggle({
    Name="Tap-to-TP on checkpoints (mobile)", CurrentValue=false,
    Callback=function(v)
        if touchConn then touchConn:Disconnect(); touchConn=nil end
        if not v then return end
        touchConn = UIS.TouchTap:Connect(function(pos, processed)
            if processed then return end
            local r = raycastFromScreen(pos[1]); local folder = resolveFolder()
            if r and r.Instance and folder then
                local owner = findOwnerUnderFolder(r.Instance, folder)
                if owner and cpIndexByName[owner.Name] then
                    selectedName = owner.Name
                    local cf = tryResolveAnchorCF(owner)
                    if cf then local _,hrp,hum=getCharacter(); if hrp and hum and hum.Health>0 then hrp.CFrame = cf * CFrame.new(0,5,0) end end
                end
            end
        end)
    end
})

-- Visibility toggles
local function addVisibilityToggle(tab) tab:CreateToggle({Name="Toggle GUI Visibility", CurrentValue=true, Callback=function(v) Rayfield:ToggleWindow(v) end}) end
addVisibilityToggle(FlightTab); addVisibilityToggle(TPTab)
