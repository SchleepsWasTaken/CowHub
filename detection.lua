-- LocalScript — StarterPlayerScripts / CheckpointTouchLogger.client.lua
-- Prints checkpoint names to the CLIENT console when your character touches one.

-- Detects checkpoints by:
-- 1) Parts inside Workspace.Checkpoints
-- 2) Any BasePart named "Checkpoint..." (case-insensitive)
-- 3) Any BasePart with Attribute IsCheckpoint = true

local Players     = game:GetService("Players")
local Workspace   = game:GetService("Workspace")
local RunService  = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- === Character helpers ===
local function getCharacter()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp  = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart")
    return char, hrp
end

local Character = getCharacter()
LocalPlayer.CharacterAdded:Connect(function(c) Character = c end)

-- === Checkpoint detection ===
local checkpoints = {}
local touchConns  = {} -- part -> RBXScriptConnection
local debounce    = {} -- part -> tick()

local function isCheckpointPart(p: Instance): boolean
    if not p or not p:IsA("BasePart") then return false end
    if p:GetAttribute("IsCheckpoint") == true then return true end
    local n = string.lower(p.Name)
    if string.sub(n, 1, 10) == "checkpoint" then return true end
    return false
end

local function collectCheckpoints()
    checkpoints = {}
    local folder = Workspace:FindFirstChild("Checkpoints")
    if folder then
        for _, ch in ipairs(folder:GetChildren()) do
            if isCheckpointPart(ch) then table.insert(checkpoints, ch) end
        end
    end

    -- Fallback: shallow scan if folder missing or empty
    if #checkpoints == 0 then
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("BasePart") and isCheckpointPart(d) then
                table.insert(checkpoints, d)
            end
        end
    end

    -- Sort by trailing number if present, else by name
    table.sort(checkpoints, function(a, b)
        local na = tonumber(string.match(a.Name, "%d+")) or math.huge
        local nb = tonumber(string.match(b.Name, "%d+")) or math.huge
        if na ~= nb then return na < nb end
        return a.Name < b.Name
    end)
end

local function checkpointNames()
    local t = {}
    for i, cp in ipairs(checkpoints) do t[i] = cp.Name end
    return table.concat(t, ", ")
end

-- === Touch wiring ===
local function onTouched(part, other)
    -- Debounce per-part to avoid spam on multi-contact
    local last = debounce[part] or 0
    if tick() - last < 0.2 then return end
    debounce[part] = tick()

    local char = Character
    if not char then return end
    if other and other:IsDescendantOf(char) then
        -- Refresh list to be safe (optional; comment out if you prefer static)
        collectCheckpoints()
        print(("[Checkpoint Touch] Touched: %s"):format(part.Name))
        print("[Checkpoint Touch] All detected checkpoints:")
        print("  " .. (checkpointNames() ~= "" and checkpointNames() or "(none)"))
    end
end

local function connectPart(p)
    if touchConns[p] then return end
    touchConns[p] = p.Touched:Connect(function(other) onTouched(p, other) end)
end

local function disconnectAll()
    for p, conn in pairs(touchConns) do
        if conn and conn.Disconnect then conn:Disconnect() end
        touchConns[p] = nil
    end
end

local function wireAll()
    disconnectAll()
    collectCheckpoints()
    for _, cp in ipairs(checkpoints) do
        connectPart(cp)
    end
    print(("[Checkpoint Touch] Wired %d checkpoint(s): %s")
        :format(#checkpoints, checkpointNames()))
end

-- Keep wiring up as the world changes
wireAll()

-- Re-wire if new checkpoints appear later
Workspace.DescendantAdded:Connect(function(d)
    if d:IsA("BasePart") and isCheckpointPart(d) then
        table.insert(checkpoints, d)
        connectPart(d)
        print(("[Checkpoint Touch] New checkpoint detected: %s"):format(d.Name))
    end
end)

-- Optional periodic re-scan (uncomment if your map streams in/out often)
-- task.spawn(function()
--     while true do
--         task.wait(5)
--         wireAll()
--     end
-- end)
