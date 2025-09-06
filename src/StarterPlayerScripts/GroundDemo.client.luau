-- Minimal demo of Grounding utilities
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ok, Grounding = pcall(function()
    return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Grounding"):WaitForChild("Grounding"))
end)

if not ok then
    warn("Grounding module not found; demo will not run.")
    return
end

local function reportDistance()
    local player = Players.LocalPlayer
    local char = player.Character or player.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
    local d = Grounding.getGroundDistance(hrp.Position, 100)
    if d then
        print(string.format("Distance to ground: %.2f", d))
    else
        print("No ground detected below.")
    end
end

task.spawn(function()
    while true do
        reportDistance()
        task.wait(2)
    end
end)

