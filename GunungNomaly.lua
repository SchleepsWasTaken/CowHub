-- Rayfield GUI Teleport Script for Gunung Nomaly
-- Compatible with Delta Mobile Executor and PC Executors like Xeno
-- Assumes checkpoints are in Workspace.Checkpoints folder, with numbered names like "1", "2", etc.
-- If not, adjust the findCheckpoints function accordingly.

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "Gunung Nomaly TP GUI",
   LoadingTitle = "Teleport Script",
   LoadingSubtitle = "by Grok",
   ConfigurationSaving = {
      Enabled = false,
      FolderName = nil,
      FileName = "GunungNomalyTP"
   }
})

local Tab = Window:CreateTab("Teleports", nil)

-- Function to find and sort checkpoints
local function findCheckpoints()
   local checkpoints = {}
   local checkpointFolder = game.Workspace:FindFirstChild("Checkpoints")  -- Adjust if folder name is different
   if checkpointFolder then
      for _, child in ipairs(checkpointFolder:GetChildren()) do
         if child:IsA("Part") or child:IsA("MeshPart") then  -- Assuming checkpoints are parts
            table.insert(checkpoints, child)
         end
      end
      -- Sort by name, assuming names are numbers
      table.sort(checkpoints, function(a, b)
         return tonumber(a.Name) < tonumber(b.Name)
      end)
   else
      Rayfield:Notify({
         Title = "Error",
         Content = "Checkpoints folder not found in Workspace.",
         Duration = 5,
         Image = nil,
         Actions = {}
      })
   end
   return checkpoints
end

local checkpoints = findCheckpoints()

-- Create buttons for each checkpoint
if #checkpoints > 0 then
   for i, cp in ipairs(checkpoints) do
      local Button = Tab:CreateButton({
         Name = "Teleport to Checkpoint " .. cp.Name,
         Callback = function()
            local player = game.Players.LocalPlayer
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
               player.Character.HumanoidRootPart.CFrame = cp.CFrame * CFrame.new(0, 5, 0)  -- TP above the checkpoint
               Rayfield:Notify({
                  Title = "Teleported",
                  Content = "To Checkpoint " .. cp.Name,
                  Duration = 3
               })
            end
         end
      })
   end
else
   Tab:CreateLabel("No checkpoints found. Adjust script if needed.")
end

-- Optional: Auto TP through all checkpoints button
local AutoTPButton = Tab:CreateButton({
   Name = "Auto TP Through All Checkpoints",
   Callback = function()
      local player = game.Players.LocalPlayer
      if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
         for i, cp in ipairs(checkpoints) do
            player.Character.HumanoidRootPart.CFrame = cp.CFrame * CFrame.new(0, 5, 0)
            wait(1)  -- Delay between TPs, adjust as needed
         end
         Rayfield:Notify({
            Title = "Auto TP Complete",
            Content = "Teleported through all checkpoints.",
            Duration = 5
         })
      end
   end
})
