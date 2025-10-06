-- ====================
-- Checkpoint detection (EXACT folder) WITH CUSTOM SLIDER UI
-- ====================
local CP_FOLDER_NAME = "Checkpoints"
local checkpoints = {}      -- { {name="10", root=Instance}, ... }  (numeric only for slider)
local cpIndexByName = {}    -- name -> index
local selectedName          -- string number
local labelDetected
local folderConn, folderChildConn
local refreshDebounce = false

local function isNumericName(n) return string.match(n, "^%d+$") ~= nil end
local function resolveFolder() return Workspace:FindFirstChild(CP_FOLDER_NAME) end

local function namesArray()
    local t = {}
    for i, cp in ipairs(checkpoints) do t[i] = cp.name end
    return t
end

local function tryResolveAnchorCF(root)
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

local function collectCheckpoints()
    checkpoints = {}; cpIndexByName = {}
    local folder = resolveFolder(); if not folder then return end
    for _, child in ipairs(folder:GetChildren()) do
        if (child:IsA("Folder") or child:IsA("Model") or child:IsA("BasePart")) and isNumericName(child.Name) then
            table.insert(checkpoints, { name = child.Name, root = child })
        end
    end
    table.sort(checkpoints, function(a,b) return tonumber(a.name) < tonumber(b.name) end)
    for i, it in ipairs(checkpoints) do cpIndexByName[it.name] = i end
end

local function updateDetectedLabel()
    local text = (#checkpoints > 0) and ("Detected Checkpoints: " .. table.concat(namesArray(), ", "))
                                   or ("No children under Workspace."..CP_FOLDER_NAME..".")
    if labelDetected and labelDetected.Set then
        pcall(function() labelDetected:Set(text) end)
    else
        labelDetected = TPTab:CreateLabel(text)
    end
end

-- ========= Custom slider =========
-- We build it once and only update its range/value on refresh.
local sliderGui -- ScreenGui
local sliderFrame -- outer frame
local bar, fill, knob, title -- UI elements
local sliderMin, sliderMax, sliderValue = 0, 1, 0  -- numeric values

local function valueToX(val)
    if sliderMax == sliderMin then return 0 end
    local pct = (val - sliderMin) / (sliderMax - sliderMin)
    return math.clamp(pct, 0, 1)
end

local function nearestExisting(num)
    -- snap to closest detected CP (down preference, then up)
    local bestName, bestDist
    for _, cp in ipairs(checkpoints) do
        local n = tonumber(cp.name)
        local d = math.abs(n - num)
        if not bestDist or d < bestDist then
            bestDist, bestName = d, cp.name
        end
    end
    return bestName
end

local function setSliderDisplay(valNumber)
    -- updates knob + fill + title label; does NOT change list
    sliderValue = valNumber
    local pct = valueToX(valNumber)
    local barAbs = bar.AbsoluteSize.X
    local x = bar.AbsolutePosition.X + pct * barAbs
    -- position knob relative to bar
    knob.Position = UDim2.fromOffset(bar.AbsolutePosition.X + pct * barAbs - sliderFrame.AbsolutePosition.X - knob.AbsoluteSize.X/2, knob.Position.Y.Offset)
    fill.Size = UDim2.new(pct, 0, 1, 0)
    title.Text = "Select checkpoint (number)   " .. tostring(valNumber) .. " #"
end

local function ensureCustomSlider()
    if sliderGui then return end
    local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    sliderGui = Instance.new("ScreenGui")
    sliderGui.Name = "GN_CustomSlider"
    sliderGui.ResetOnSpawn = false
    sliderGui.IgnoreGuiInset = true
    sliderGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sliderGui.Parent = pg

    sliderFrame = Instance.new("Frame")
    sliderFrame.Name = "SliderFrame"
    sliderFrame.Size = UDim2.new(0, 420, 0, 64)
    sliderFrame.Position = UDim2.new(0, 24, 1, -110)   -- bottom-left; tweak if you like
    sliderFrame.BackgroundColor3 = Color3.fromRGB(20,20,20)
    sliderFrame.BackgroundTransparency = 0.2
    sliderFrame.BorderSizePixel = 0
    sliderFrame.Parent = sliderGui

    local corner = Instance.new("UICorner", sliderFrame); corner.CornerRadius = UDim.new(0, 14)

    title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -20, 0, 22)
    title.Position = UDim2.new(0, 10, 0, 6)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamSemibold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "Select checkpoint (number)"
    title.TextColor3 = Color3.new(1,1,1)
    title.Parent = sliderFrame

    bar = Instance.new("Frame")
    bar.Name = "Bar"
    bar.Size = UDim2.new(1, -40, 0, 10)
    bar.Position = UDim2.new(0, 20, 0, 40)
    bar.BackgroundColor3 = Color3.fromRGB(50,50,50)
    bar.BorderSizePixel = 0
    bar.Parent = sliderFrame
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 6)

    fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.Position = UDim2.new(0, 0, 0, 0)
    fill.BackgroundColor3 = Color3.fromRGB(65, 139, 255)
    fill.BorderSizePixel = 0
    fill.Parent = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)

    knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = UDim2.fromOffset(bar.AbsolutePosition.X - sliderFrame.AbsolutePosition.X - 9, 36)
    knob.BackgroundColor3 = Color3.fromRGB(65, 139, 255)
    knob.BorderSizePixel = 0
    knob.Parent = sliderFrame
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local dragging = false

    local function setFromX(xPixel)
        -- xPixel in screen coords; convert to value
        local left = bar.AbsolutePosition.X
        local width = bar.AbsoluteSize.X
        local pct = math.clamp((xPixel - left) / math.max(width,1), 0, 1)
        local rawVal = sliderMin + pct * (sliderMax - sliderMin)
        rawVal = math.floor(rawVal + 0.5) -- step = 1
        if sliderMin == sliderMax then rawVal = sliderMin end
        local snapName = nearestExisting(rawVal)
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
-- ========= end custom slider =========

local function rebuildCustomSliderRange()
    ensureCustomSlider()
    -- derive min/max from detected numerics; if none, show a disabled state
    local arr = {}
    for _, cp in ipairs(checkpoints) do table.insert(arr, tonumber(cp.name)) end
    table.sort(arr)
    sliderMin, sliderMax = arr[1] or 0, arr[#arr] or 1
    -- default to highest available
    if #arr > 0 then
        selectedName = tostring(arr[#arr])
        setSliderDisplay(arr[#arr])
    else
        selectedName = nil
        setSliderDisplay(0)
    end
end

local function refreshUI()
    if refreshDebounce then return end
    refreshDebounce = true
    task.delay(0.2, function() refreshDebounce = false end)

    collectCheckpoints()
    updateDetectedLabel()
    rebuildCustomSliderRange()

    print("[CP children] "..(#checkpoints>0 and table.concat(namesArray(), ", ") or "(none)"))
end

-- Buttons
TPTab:CreateButton({
    Name = "Teleport (selected)",
    Callback = function()
        if not selectedName then
            Rayfield:Notify({Title="No checkpoint", Content="Use the slider first.", Duration=2})
            return
        end
        local idx = cpIndexByName[selectedName]; if not idx then return end
        local cp = checkpoints[idx]
        local cf = tryResolveAnchorCF(cp.root)
        if not cf then
            Rayfield:Notify({Title="No anchor yet", Content="No part inside '"..cp.name.."' (streaming?).", Duration=3})
            return
        end
        local _, hrp, hum = getCharacter(); if not (hrp and hum and hum.Health>0) then return end
        hrp.CFrame = cf * CFrame.new(0,5,0)
        Rayfield:Notify({Title="Teleported", Content="To "..selectedName, Duration=2})
    end
})
TPTab:CreateButton({
    Name = "Auto TP through all",
    Callback = function()
        local _, hrp, hum = getCharacter(); if not (hrp and hum and hum.Health>0) then return end
        for _, cp in ipairs(checkpoints) do
            local cf = tryResolveAnchorCF(cp.root)
            if cf then hrp.CFrame = cf * CFrame.new(0,5,0); task.wait(1) end
        end
        Rayfield:Notify({Title="Auto TP Complete", Duration=3})
    end
})
TPTab:CreateButton({ Name = "Refresh checkpoints", Callback = refreshUI })

-- Initial build
refreshUI()

-- Watchers for exact folder (update when children under Checkpoints change)
if folderConn then folderConn:Disconnect() end
folderConn = Workspace.ChildAdded:Connect(function(child)
    if child.Name == CP_FOLDER_NAME then
        task.wait(0.05); refreshUI()
        if folderChildConn then folderChildConn:Disconnect() end
        folderChildConn = child.ChildAdded:Connect(function(ch)
            if ch:IsA("Folder") or ch:IsA("Model") or ch:IsA("BasePart") then
                task.wait(0.05); refreshUI()
            end
        end)
    end
end)
local f = resolveFolder()
if f then
    if folderChildConn then folderChildConn:Disconnect() end
    folderChildConn = f.ChildAdded:Connect(function(ch)
        if ch:IsA("Folder") or ch:IsA("Model") or ch:IsA("BasePart") then
            task.wait(0.05); refreshUI()
        end
    end)
end
