local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local donationEvent = ReplicatedStorage:WaitForChild("BoothDonationRequest")

local function bindBoard(boardGui)
    if not boardGui or boardGui.ClassName ~= "SurfaceGui" or boardGui.Name ~= "BoardGui" then return end
    local sign = boardGui.Parent
    if not sign then return end
    local model = sign.Parent
    if not model or not model:IsA("Model") then return end

    local buttonRow = boardGui:FindFirstChild("ButtonRow")
    if not buttonRow then return end

    for _, child in ipairs(buttonRow:GetChildren()) do
        if child:IsA("TextButton") then
            child.MouseButton1Click:Connect(function()
                local lp = Players.LocalPlayer
                if not lp then return end
                local ownerUserId = model:GetAttribute("OwnerUserId") or 0
                if ownerUserId ~= 0 and ownerUserId ~= lp.UserId then
                    local productId = child:GetAttribute("ProductId")
                    local amount = child:GetAttribute("Amount")
                    if typeof(productId) == "number" then
                        donationEvent:FireServer(model, productId, amount)
                    end
                end
            end)
        end
    end
end

-- Bind existing boards
for _, inst in ipairs(workspace:GetDescendants()) do
    if inst:IsA("SurfaceGui") and inst.Name == "BoardGui" then
        bindBoard(inst)
    end
end

-- Bind new boards as they appear
workspace.DescendantAdded:Connect(function(inst)
    if inst:IsA("SurfaceGui") and inst.Name == "BoardGui" then
        bindBoard(inst)
    end
end)