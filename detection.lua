-- StarterPlayerScripts / WorkspaceClickInspector.client.lua
-- Click/tap any 3D object to print its name, class, and full path (client console).
-- Works on PC (mouse) and mobile (touch). Ignores your own character.

local Players     = game:GetService("Players")
local UIS         = game:GetService("UserInputService")
local Workspace   = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

-- Build a readable path like Workspace.Map.Ladder.Step01
local function getFullPath(inst: Instance): string
    if not inst then return "(nil)" end
    local parts = {inst.Name}
    local p = inst.Parent
    while p and p ~= game do
        table.insert(parts, 1, p.Name)
        p = p.Parent
    end
    return table.concat(parts, ".")
end

-- Return a RaycastResult from a screen position (Vector2)
local function raycastFromScreen(screenPos: Vector2)
    local unitRay = Camera:ViewportPointToRay(screenPos.X, screenPos.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { LocalPlayer.Character } -- ignore self
    params.IgnoreWater = false
    return Workspace:Raycast(unitRay.Origin, unitRay.Direction * 5000, params)
end

local function describeInstance(inst: Instance)
    if not inst then return end
    -- If you clicked a descendant (e.g., MeshPart inside a Model), the primary
    -- thing you may care about is the top-level Model (like "Ladder", "Sign").
    local top = inst
    while top.Parent and top.Parent ~= Workspace and not top:IsA("Model") do
        top = top.Parent
    end
    local topModel = inst:FindFirstAncestorOfClass("Model") or top

    print(("=== Clicked: %s ==="):format(inst.Name))
    print(("Class: %s"):format(inst.ClassName))
    print(("Path: %s"):format(getFullPath(inst)))
    if topModel and topModel ~= inst then
        print(("Top Model: %s  (Path: %s)"):format(topModel.Name, getFullPath(topModel)))
    end

    -- Helpful extras: attributes on the clicked instance
    local attrs = inst:GetAttributes()
    if next(attrs) ~= nil then
        print("Attributes:")
        for k, v in pairs(attrs) do
            print(("  %s = %s"):format(k, tostring(v)))
        end
    end
    print("====================================")
end

-- PC: use left-click (mouse)
local function handleMouseClick()
    local mouse = LocalPlayer:GetMouse()
    mouse.Button1Down:Connect(function()
        -- Prefer Raycast for accuracy; fall back to Mouse.Target if needed
        local pos = UIS:GetMouseLocation()
        local result = raycastFromScreen(Vector2.new(pos.X, pos.Y))
        local target = result and result.Instance or mouse.Target
        if target then
            describeInstance(target)
        end
    end)
end

-- Mobile + desktop fallback: use InputBegan (touch or mouse)
local function handleGenericInput()
    UIS.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        if input.UserInputType == Enum.UserInputType.Touch then
            local pos = input.Position
            local result = raycastFromScreen(Vector2.new(pos.X, pos.Y))
            if result and result.Instance then
                describeInstance(result.Instance)
            end
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
            -- Also catch mouse clicks here (some executors prefer this path)
            local pos = UIS:GetMouseLocation()
            local result = raycastFromScreen(Vector2.new(pos.X, pos.Y))
            if result and result.Instance then
                describeInstance(result.Instance)
            end
        end
    end)
end

-- Update the blacklist when you respawn
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.1) -- small delay so character exists before clicks arrive
end)

-- Initialize
handleMouseClick()
handleGenericInput()

print("[Inspector] Click/tap any object to log its name, class, and path.")
print("           Open the client console with F9 (Studio) / executor console.")
