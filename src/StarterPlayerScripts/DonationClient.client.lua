local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local donateEvent = ReplicatedStorage:WaitForChild("DonateToBooth")

-- Hook up all donation buttons when they appear
local function hookButtons(container)
    for _, btn in ipairs(container:GetDescendants()) do
        if btn:IsA("TextButton") and not btn:GetAttribute("DonationHooked") then
            btn:SetAttribute("DonationHooked", true)
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
local function hookAllBooths()
    for _, boothFolder in ipairs(workspace:GetChildren()) do
        if boothFolder.Name == "Booths" then
            for _, booth in ipairs(boothFolder:GetChildren()) do
                hookButtons(booth)
            end
        end
    end
end

-- Prefer LocalPlayer on the client to ensure hooks run reliably
local localPlayer = Players.LocalPlayer
if localPlayer then
    localPlayer.CharacterAdded:Connect(function()
        hookAllBooths()
    end)
    if localPlayer.Character then
        hookAllBooths()
    end
end

-- Still listen for new players in case the engine fires this on client
Players.PlayerAdded:Connect(function(player)
    if player == localPlayer then
        -- Already handled above
        return
    end
    player.CharacterAdded:Connect(function()
        hookAllBooths()
    end)
end)
