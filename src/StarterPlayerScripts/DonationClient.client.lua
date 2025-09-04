local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local donateEvent = ReplicatedStorage:WaitForChild("DonateToBooth")

-- Hook up all donation buttons when they appear
local function hookButtons(container)
    for _, btn in ipairs(container:GetDescendants()) do
        if btn:IsA("TextButton") then
            btn.MouseButton1Click:Connect(function()
                local model = btn:FindFirstAncestorWhichIsA("Model")
                if model then
                    local amount = tonumber(btn.Text:match("%d+"))
                    donateEvent:FireServer(model, amount)
                end
            end)
        end
    end
end

-- When the player character spawns, look for booths and hook buttons
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        for _, boothFolder in ipairs(workspace:GetChildren()) do
            if boothFolder.Name == "Booths" then
                for _, booth in ipairs(boothFolder:GetChildren()) do
                    hookButtons(booth)
                end
            end
        end
    end)
end)

