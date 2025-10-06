-- Gunung Nomaly Utility GUI
-- Fly + Noclip + Checkpoint TP (custom slider) + Tap/Click TP
-- Now with checkpoint caching (writefile/readfile)

----------------------------------------------------------------------
-- Safe Rayfield loader
----------------------------------------------------------------------
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
if not Rayfield then
    warn("[Rayfield] Could not load (executor/network off or module missing).")
    return
end

----------------------------------------------------------------------
-- Window & tabs
----------------------------------------------------------------------
local Window   = Rayfield:CreateWindow({
    Name = "Gunung Nomaly Utility GUI",
    LoadingTitle = "Flight & TP Script",
    LoadingSubtitle = "by Babang Sekelep",
    ConfigurationSaving = { Enabled = false },
})
local FlightTab = Window:CreateTab("Flight Controls", 1103511846)
local TPTab     = Window:CreateTab("Checkpoint Teleports", 1103511847)

----------------------------------------------------------------------
-- Services & helpers
----------------------------------------------------------------------
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local Workspace   = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local LP          = Players.LocalPlayer

local function SafeWait(parent, name, t)
    local x = parent:FindFirstChild(name); if x then return x end
    local ok, res = pcall(function() return parent:WaitForChild(name, t or 5) end)
    if ok then return res end
end

local function getCharacter()
    local c = LP.Character or LP.CharacterAdded:Wait()
    local hrp = c:FindFirstChild("HumanoidRootPart") or SafeWait(c, "HumanoidRootPart", 5)
    local hum = c:FindFirstChildOfClass("Humanoid") or SafeWait(c, "Humanoid", 5)
    return c, hrp, hum
end

local Character, HRP, Humanoid = getCharacter()

----------------------------------------------------------------------
-- Fly
----------------------------------------------------------------------
local isFlying, flySpeed, MAX_SPEED = false, 50, 200
local vel, gyro

local function startFlying()
    if not Character or not HRP or not Humanoid or Humanoid.Health <= 0 or isFlying then return end
    isFlying = true
    Humanoid.PlatformStand = true

    vel = Instance.new("BodyVelocity")
    vel.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    vel.Parent = HRP

    gyro = Instance.new("BodyGyro")
    gyro.MaxTorque = Vector3.new(4e5, 4e5, 4e5)
    gyro.P, gyro.D = 3000, 500
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
            local p = HRP.Position
            gyro.CFrame = CFrame.new(p, p + cf.LookVector)
            RunService.Heartbeat:Wait()
        end
    end)

    Rayfield:Notify({ Title = "Flying Enabled", Content = "WASD / Space / Shift", Duration = 2 })
end

local function stopFlying()
    if not isFlying then return end
    isFlying = false
    if vel then vel:Destroy() vel = nil end
    if gyro then gyro:Destroy() gyro = nil end
    if Humanoid then Humanoid.PlatformStand = false end
    Rayfield:Notify({ Title = "Flying Disabled", Duration = 2 })
end

UIS.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode == Enum.KeyCode.F then
        if isFlying then stopFlying() else startFlying() end
    end
end)

----------------------------------------------------------------------
-- Noclip
----------------------------------------------------------------------
local noclipOn, noclipConn = false, nil
local function setCollide(on)
    if not Character then return end
    for _, d in ipairs(Character:GetDescendants()) do
        if d:IsA("BasePart") then d.CanCollide = on end
    end
end
local function enableNoclip(on)
    noclipOn = on
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    if on then
        noclipConn = RunService.Stepped:Connect(function() setCollide(false) end)
    else
        setCollide(true)
    end
end

LP.CharacterAdded:Connect(function(c)
    Character = c
    HRP = SafeWait(c, "HumanoidRootPart", 5)
    Humanoid = SafeWait(c, "Humanoid", 5)
    pcall(function() if Humanoid then Humanoid.PlatformStand = false end end)
    if noclipOn then enableNoclip(true) end
end)
if Humanoid then Humanoid.Died:Connect(function() stopFlying(); enableNoclip(false) end) end

-- Flight tab UI
FlightTab:CreateToggle({ Name = "Toggle Fly", CurrentValue = false, Callback = function(v) if v then startFlying() else stopFlying() end end })
FlightTab:CreateSlider({ Name = "Fly Speed", Range = {10, MAX_SPEED}, Increment = 5, Suffix = "speed", CurrentValue = flySpeed, Callback = function(v) flySpeed = v end })
FlightTab:CreateToggle({ Name = "Noclip (no collisions)", CurrentValue = false, Callback = function(v) enableNoclip(v) end })
FlightTab:CreateLabel("Tip: Space=up, Shift=down. Camera decides direction.")

----------------------------------------------------------------------
-- Checkpoints + caching
----------------------------------------------------------------------
local CP_FOLDER_NAME = "Checkpoints"
local checkpoints = {}      -- { {name="10", root=Instance}, ... } numeric only
local cpIndexByName = {}    -- name -> index
local selectedName          -- string number
local labelDetected
local folderConn, folderChildConn
local refreshDebounce = false

-- cache helpers (executor FS)
local FS = {
    has = (typeof(isfile)=="function" and typeof(writefile)=="function" and typeof(readfile)=="function"),
    path = "GN_checkpoints.json"
}

local function isNumericName(n) return string.match(n, "^%d+$") ~= nil end
local function resolveFolder() return Workspace:FindFirstChild(CP_FOLDER_NAME) end

local function namesArray()
    local t = {}
    for i, cp in ipairs(checkpoints) do t[i] = cp.name end
    return t
end

local function sortAndIndex(byNames)
    table.sort(byNames, function(a,b) return tonumber(a) < tonumber(b) end)
    checkpoints, cpIndexByName = {}, {}
    local folder = resolveFolder()
    for _, name in ipairs(byNames) do
        local root = folder and folder:FindFirstChild(name)
        table.insert(checkpoints, {name=name, root=root})
        cpIndexByName[name] = #checkpoints
    end
end

-- load cache -> returns { "1","2",... } or nil
local function loadCache()
    if not FS.has or not isfile(FS.path) then return nil end
    local ok, content = pcall(function() return readfile(FS.path) end)
    if not ok or not content or content == "" then return nil end
    local ok2, obj = pcall(function() return HttpService:JSONDecode(content) end)
    if not ok2 or type(obj)~="table" or type(obj.names)~="table" then return nil end
    local out = {}
    for _,v in ipairs(obj.names) do if isNumericName(tostring(v)) then table.insert(out, tostring(v)) end end
    if #out==0 then return nil end
    return out
end

local function saveCacheFromCurrent()
    if not FS.has then return false end
    local names = namesArray()
    local ok, enc = pcall(function() return HttpService:JSONEncode({names=names, savedAt=os.time()}) end)
    if not ok then return false end
    local ok2 = pcall(function() writefile(FS.path, enc) end)
    if ok2 then Rayfield:Notify({Title="Saved", Content="Checkpoint list cached", Duration=2}) end
    return ok2
end

-- world scan -> returns set of names
local function scanWorldNames()
    local ret = {}
    local folder = resolveFolder(); if not folder then return ret end
    for _, child in ipairs(folder:GetChildren()) do
        if (child:IsA("Folder") or child:IsA("Model") or child:IsA("BasePart")) and isNumericName(child.Name) then
            table.insert(ret, child.Name)
        end
    end
    return ret
end

-- union cached+world names
local function unionNames(a, b)
    local set, out = {}, {}
    for _,v in ipairs(a or {}) do v=tostring(v); if not set[v] then set[v]=true; table.insert(out,v) end end
    for _,v in ipairs(b or {}) do v=tostring(v); if not set[v] then set[v]=true; table.insert(out,v) end end
    return out
end

-- anchor finder
local function tryResolveAnchorCF(rootOrName)
    local root = rootOrName
    if typeof(rootOrName)=="string" then
        local folder = resolveFolder()
        root = folder and folder:FindFirstChild(rootOrName)
    end
    if not root then return nil end
    if root:IsA("BasePart") then return root.CFrame end
    if root:IsA("Model") then
        if root.PrimaryPart then return root.PrimaryPart.CFrame end
        local cf = root:GetBoundingBox(); return cf
    end
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("BasePart") then return d.CFrame end
    end
    return nil
end

-- label
local function updateDetectedLabel()
    local text = (#checkpoints > 0) and ("Detected Checkpoints: " .. table.concat(namesArray(), ", ")) or "No checkpoints yet."
    if labelDetected and labelDetected.Set then pcall(function() labelDetected:Set(text) end)
    else labelDetected = TPTab:CreateLabel(text) end
end

----------------------------------------------------------------------
-- Custom slider (built once, updated on refresh)
----------------------------------------------------------------------
local sliderGui, sliderFrame, bar, fill, knob, title
local sliderMin, sliderMax, sliderValue = 0, 1, 0
local cacheOnly = false  -- toggle: use only cached names (skip world scans)

local function valueToPct(val)
    if sliderMax == sliderMin then return 0 end
    return math.clamp((val - sliderMin) / (sliderMax - sliderMin), 0, 1)
end

local function setSliderDisplay(valNumber)
    sliderValue = valNumber
    local pct = valueToPct(valNumber)
    local width = bar.AbsoluteSize.X
    local left  = bar.AbsolutePosition.X
    local knobX = left + pct * width - knob.AbsoluteSize.X/2 - sliderFrame.AbsolutePosition.X
    knob.Position = UDim2.fromOffset(knobX, knob.Position.Y.Offset)
    fill.Size     = UDim2.new(pct, 0, 1, 0)
    title.Text    = ("Select checkpoint (number)   %d #"):format(valNumber)
end

local function ensureCustomSlider()
    if sliderGui then return end
    local pg = LP:WaitForChild("PlayerGui")

    sliderGui = Instance.new("ScreenGui")
    sliderGui.Name, sliderGui.ResetOnSpawn, sliderGui.IgnoreGuiInset = "GN_CustomSlider", false, true
    sliderGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sliderGui.Parent = pg

    sliderFrame = Instance.new("Frame")
    sliderFrame.Size = UDim2.new(0, 420, 0, 64)
    sliderFrame.Position = UDim2.new(0, 24, 1, -110)  -- bottom-left anchor
    sliderFrame.BackgroundColor3 = Color3.fromRGB(20,20,20)
    sliderFrame.BackgroundTransparency = 0.2
    sliderFrame.BorderSizePixel = 0
    sliderFrame.Parent = sliderGui
    Instance.new("UICorner", sliderFrame).CornerRadius = UDim.new(0, 14)

    title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 22)
    title.Position = UDim2.new(0, 10, 0, 6)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamSemibold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.new(1,1,1)
    title.Text = "Select checkpoint (number)"
    title.Parent = sliderFrame

    bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -40, 0, 10)
    bar.Position = UDim2.new(0, 20, 0, 40)
    bar.BackgroundColor3 = Color3.fromRGB(50,50,50)
    bar.BorderSizePixel = 0
    bar.Parent = sliderFrame
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 6)

    fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.Position = UDim2.new(0, 0, 0, 0)
    fill.BackgroundColor3 = Color3.fromRGB(65, 139, 255)
    fill.BorderSizePixel = 0
    fill.Parent = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)

    knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = UDim2.fromOffset(bar.AbsolutePosition.X - sliderFrame.AbsolutePosition.X - 9, 36)
    knob.BackgroundColor3 = Color3.fromRGB(65, 139, 255)
    knob.BorderSizePixel = 0
    knob.Parent = sliderFrame
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local dragging = false
    local function nearestExisting(num)
        local bestName, bestDist
        for _, cp in ipairs(checkpoints) do
            local n = tonumber(cp.name)
            local d = math.abs(n - num)
            if not bestDist or d < bestDist then bestDist, bestName = d, cp.name end
        end
        return bestName
    end
    local function setFromX(xPixel)
        local left = bar.AbsolutePosition.X
        local width = bar.AbsoluteSize.X
        local pct = math.clamp((xPixel - left) / math.max(width, 1), 0, 1)
        local raw = sliderMin + pct * (sliderMax - sliderMin)
        raw = math.floor(raw + 0.5)
        if sliderMin == sliderMax then raw = sliderMin end
        local snapName = nearestExisting(raw)
        if snapName then
            selectedName = snapName
            setSliderDisplay(tonumber(snapName))
        end
    end

    knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)
    knob.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            setFromX((input.Position and input.Position.X) or UIS:GetMouseLocation().X)
            dragging = true
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            setFromX((input.Position and input.Position.X) or UIS:GetMouseLocation().X)
        end
    end)
end

local function rebuildSliderRange()
    ensureCustomSlider()
    local arr = {}
    for _, cp in ipairs(checkpoints) do table.insert(arr, tonumber(cp.name)) end
    table.sort(arr)
    sliderMin, sliderMax = arr[1] or 0, arr[#arr] or 1
    if #arr > 0 then
        selectedName = tostring(arr[#arr])      -- default to highest
        setSliderDisplay(arr[#arr])
    else
        selectedName = nil
        setSliderDisplay(0)
    end
end

-- main refresh
local cachedNames = loadCache() or {}
local function refreshUI()
    if refreshDebounce then return end
    refreshDebounce = true
    task.delay(0.2, function() refreshDebounce = false end)

    local worldNames = cacheOnly and {} or scanWorldNames()
    local merged = unionNames(cachedNames, worldNames)
    local beforeCount = #cachedNames
    sortAndIndex(merged)
    updateDetectedLabel()
    rebuildSliderRange()

    -- auto-save if we discovered new names
    if #merged > beforeCount then
        cachedNames = merged
        saveCacheFromCurrent()
    end

    print("[CP] " .. (#checkpoints > 0 and table.concat(namesArray(), ", ") or "(none)"))
end

-- Buttons (TP + refresh + cache ops)
TPTab:CreateButton({
    Name = "Teleport (selected)",
    Callback = function()
        if not selectedName then Rayfield:Notify({Title="No checkpoint", Content="Use the slider first.", Duration=2}); return end
        local cf = tryResolveAnchorCF(selectedName)
        if not cf then Rayfield:Notify({Title="No anchor", Content="No part in '"..selectedName.."' yet (streaming).", Duration=2}); return end
        local _, hrp, hum = getCharacter(); if not (hrp and hum and hum.Health>0) then return end
        hrp.CFrame = cf * CFrame.new(0,5,0); Rayfield:Notify({Title="Teleported", Content="To "..selectedName, Duration=2})

        -- if we just hit the highest known, save to cache
        if #checkpoints > 0 and selectedName == checkpoints[#checkpoints].name then
            cachedNames = namesArray()
            saveCacheFromCurrent()
        end
    end
})
TPTab:CreateButton({
    Name = "Auto TP through all (and save)",
    Callback = function()
        local _, hrp, hum = getCharacter(); if not (hrp and hum and hum.Health>0) then return end
        for _, cp in ipairs(checkpoints) do
            local cf = tryResolveAnchorCF(cp.name)
            if cf then hrp.CFrame = cf * CFrame.new(0,5,0); task.wait(1) end
        end
        cachedNames = namesArray()
        saveCacheFromCurrent()
        Rayfield:Notify({Title="Auto TP Complete", Content="Saved to cache", Duration=3})
    end
})
TPTab:CreateButton({ Name = "Refresh checkpoints", Callback = refreshUI })

TPTab:CreateToggle({
    Name = "Cache only (skip world scan)",
    CurrentValue = false,
    Callback = function(v) cacheOnly = v; refreshUI() end
})
TPTab:CreateButton({
    Name = "Save cache now",
    Callback = function() cachedNames = namesArray(); saveCacheFromCurrent() end
})
TPTab:CreateButton({
    Name = "Clear cache",
    Callback = function()
        if not FS.has then Rayfield:Notify({Title="No FS", Content="Executor FS not available", Duration=2}); return end
        if isfile(FS.path) then pcall(function() writefile(FS.path, HttpService:JSONEncode({names={}})) end) end
        cachedNames = {}
        refreshUI()
        Rayfield:Notify({Title="Cleared", Content="Checkpoint cache cleared", Duration=2})
    end
})

-- Build once (loads cache immediately)
refreshUI()

-- Watch for Checkpoints folder + children (updates cache automatically when new ones appear)
if folderConn then folderConn:Disconnect() end
folderConn = Workspace.ChildAdded:Connect(function(ch)
    if ch.Name == CP_FOLDER_NAME then
        task.wait(0.05); refreshUI()
        if folderChildConn then folderChildConn:Disconnect() end
        folderChildConn = ch.ChildAdded:Connect(function(c2)
            if c2:IsA("Folder") or c2:IsA("Model") or c2:IsA("BasePart") then
                task.wait(0.05); refreshUI()
            end
        end)
    end
end)
local f = resolveFolder()
if f then
    if folderChildConn then folderChildConn:Disconnect() end
    folderChildConn = f.ChildAdded:Connect(function(c2)
        if c2:IsA("Folder") or c2:IsA("Model") or c2:IsA("BasePart") then
            task.wait(0.05); refreshUI()
        end
    end)
end

----------------------------------------------------------------------
-- Optional: Tap/Click to TP directly on checkpoint parts
----------------------------------------------------------------------
local function findOwnerUnderFolder(inst, folder)
    local cur = inst
    while cur and cur ~= Workspace do
        if cur.Parent == folder then return cur end
        cur = cur.Parent
    end
    return nil
end
local function rayFromScreen(pos)
    local cam = Workspace.CurrentCamera
    local r = cam:ViewportPointToRay(pos.X, pos.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { LP.Character }
    return Workspace:Raycast(r.Origin, r.Direction * 2000, params)
end

local touchConn, mouseConn
TPTab:CreateToggle({
    Name = "Tap-to-TP (mobile)",
    CurrentValue = false,
    Callback = function(v)
        if touchConn then touchConn:Disconnect() touchConn = nil end
        if not v then return end
        touchConn = UIS.TouchTap:Connect(function(pos, processed)
            if processed then return end
            local hit = rayFromScreen(pos[1])
            local folder = resolveFolder()
            if hit and hit.Instance and folder then
                local owner = findOwnerUnderFolder(hit.Instance, folder)
                if owner and cpIndexByName[owner.Name] then
                    selectedName = owner.Name
                    local cf = tryResolveAnchorCF(owner)
                    if cf then local _, hrp, hum = getCharacter(); if hrp and hum and hum.Health>0 then hrp.CFrame = cf * CFrame.new(0,5,0) end end
                end
            end
        end)
    end
})
TPTab:CreateToggle({
    Name = "Click-to-TP (PC)",
    CurrentValue = false,
    Callback = function(v)
        if mouseConn then mouseConn:Disconnect() mouseConn = nil end
        if not v then return end
        mouseConn = UIS.InputBegan:Connect(function(i, gp)
            if gp then return end
            if i.UserInputType == Enum.UserInputType.MouseButton1 then
                local pos = UIS:GetMouseLocation()
                local hit = rayFromScreen(Vector2.new(pos.X, pos.Y))
                local folder = resolveFolder()
                if hit and hit.Instance and folder then
                    local owner = findOwnerUnderFolder(hit.Instance, folder)
                    if owner and cpIndexByName[owner.Name] then
                        selectedName = owner.Name
                        local cf = tryResolveAnchorCF(owner)
                        if cf then local _, hrp, hum = getCharacter(); if hrp and hum and hum.Health>0 then hrp.CFrame = cf * CFrame.new(0,5,0) end end
                    end
                end
            end
        end)
    end
})

----------------------------------------------------------------------
-- Window visibility toggle
----------------------------------------------------------------------
local function addVisibilityToggle(tab)
    tab:CreateToggle({ Name = "Toggle GUI Visibility", CurrentValue = true, Callback = function(v) Rayfield:ToggleWindow(v) end })
end
addVisibilityToggle(FlightTab)
addVisibilityToggle(TPTab)
