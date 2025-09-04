-- DonationGame.server.lua
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

-- Replace this with your actual Developer Product ID for skipping a stage
local SKIP_STAGE_PRODUCT = 12345678

-- Mapping of donation product IDs to the amount of Robux they represent
local DONATION_PRODUCTS = {
    [11111111] = 5,   -- product ID for 5 R$ donation
    [22222222] = 10,  -- product ID for 10 R$ donation
    [33333333] = 20,  -- product ID for 20 R$ donation
}

-- Tracks pending donations: key = player.UserId, value = { booth = <Model>, amount = <number> }
local pendingDonations = {}

-- === Donation Booth Logic ===

local function createBooth(position)
    local model = Instance.new("Model")
    model.Name = "DonationBooth"
    model:SetAttribute("TotalDonations", 0)

    local base = Instance.new("Part")
    base.Size = Vector3.new(4, 1, 4)
    base.Position = position + Vector3.new(0, 0.5, 0)
    base.Anchored = true
    base.Name = "Base"
    base.Parent = model

    local sign = Instance.new("Part")
    sign.Size = Vector3.new(4, 3, 0.5)
    sign.Position = position + Vector3.new(0, 2, -2)
    sign.Anchored = true
    sign.Name = "Sign"
    sign.Parent = model

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(4, 0, 2, 0)
    billboard.AlwaysOnTop = true
    billboard.ExtentsOffset = Vector3.new(0, 3, 0)
    billboard.Parent = sign

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
    nameLabel.Position = UDim2.new(0, 0, 0, 0)
    nameLabel.Text = "Unclaimed"
    nameLabel.TextScaled = true
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.new(1, 1, 1)
    nameLabel.Parent = billboard

    local goalLabel = Instance.new("TextLabel")
    goalLabel.Size = UDim2.new(1, 0, 0.5, 0)
    goalLabel.Position = UDim2.new(0, 0, 0.5, 0)
    goalLabel.Text = "0 R$"
    goalLabel.TextScaled = true
    goalLabel.BackgroundTransparency = 1
    goalLabel.TextColor3 = Color3.new(0, 1, 0)
    goalLabel.Parent = billboard

    local click = Instance.new("ClickDetector")
    click.MaxActivationDistance = 10
    click.Parent = sign

    local owner = nil

    click.MouseClick:Connect(function(player)
        if not owner then
            owner = player
            nameLabel.Text = player.DisplayName .. "'s Booth"
            goalLabel.Text = "0 R$"
        elseif owner == player then
            owner = nil
            nameLabel.Text = "Unclaimed"
            goalLabel.Text = "0 R$"
        else
            -- When a visitor clicks another player's booth, prompt a donation
            MarketplaceService:PromptProductPurchase(player, SKIP_STAGE_PRODUCT)
        end
    end)

    -- Spawn donation buttons for each defined product
    local buttonOffsets = {
        Vector3.new(-1.5, 0.5, 2),
        Vector3.new(0,    0.5, 2),
        Vector3.new(1.5,  0.5, 2),
    }
    local index = 1
    for productId, amount in pairs(DONATION_PRODUCTS) do
        -- Create the button part
        local btn = Instance.new("Part")
        btn.Size = Vector3.new(1, 0.5, 1)
        btn.Position = base.Position + buttonOffsets[index]
        btn.Anchored = true
        btn.BrickColor = BrickColor.new("Bright green")
        btn.Name = "Donate" .. amount
        btn.Parent = model

        -- Label showing the donation amount
        local bbg = Instance.new("BillboardGui")
        bbg.Size = UDim2.new(1.5, 0, 0.8, 0)
        bbg.AlwaysOnTop = true
        bbg.ExtentsOffset = Vector3.new(0, 1, 0)
        bbg.Parent = btn

        local amountLabel = Instance.new("TextLabel")
        amountLabel.Size = UDim2.new(1, 0, 1, 0)
        amountLabel.BackgroundTransparency = 1
        amountLabel.Text = tostring(amount) .. " R$"
        amountLabel.TextScaled = true
        amountLabel.TextColor3 = Color3.new(1, 1, 1)
        amountLabel.Parent = bbg

        -- Add a click detector for the donation button
        local btnClick = Instance.new("ClickDetector")
        btnClick.MaxActivationDistance = 10
        btnClick.Parent = btn

        -- When clicked, prompt a product purchase
        btnClick.MouseClick:Connect(function(player)
            if owner and player ~= owner then
                pendingDonations[player.UserId] = { booth = model, amount = amount }
                MarketplaceService:PromptProductPurchase(player, productId)
            end
        end)

        index += 1
    end

    return model
end

-- Spawn four booths at fixed positions
local boothFolder = Instance.new("Folder")
boothFolder.Name = "Booths"
boothFolder.Parent = workspace

local boothPositions = {
    Vector3.new(-12, 0, 0),
    Vector3.new(-4, 0, 0),
    Vector3.new(4, 0, 0),
    Vector3.new(12, 0, 0),
}

for _, pos in ipairs(boothPositions) do
    local booth = createBooth(pos)
    booth.Parent = boothFolder
end

-- === Obby Creation ===

local obbyFolder = Instance.new("Folder")
obbyFolder.Name = "Obby"
obbyFolder.Parent = workspace

-- Starting position for the obby
local startPos = Vector3.new(0, 5, 30)

-- Create five platforms in a straight line
for i = 1, 5 do
    local platform = Instance.new("Part")
    platform.Size = Vector3.new(6, 1, 6)
    platform.Position = startPos + Vector3.new((i - 1) * 8, 0, 0)
    platform.Anchored = true
    platform.Name = "Platform" .. i
    platform.Parent = obbyFolder
end

-- Teleport new players to the start of the obby
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        local root = char:WaitForChild("HumanoidRootPart")
        root.CFrame = CFrame.new(startPos)
    end)
end)

-- === Developer Product Handling ===

local productHandlers = {}

productHandlers[SKIP_STAGE_PRODUCT] = function(receipt, player)
    -- Find the player's current obby platform and teleport them to the next
    local char = player.Character
    if not char then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local platforms = obbyFolder:GetChildren()
    local currentIndex, minDist = 1, math.huge
    for i, p in ipairs(platforms) do
        local dist = (root.Position - p.Position).Magnitude
        if dist < minDist then
            minDist = dist
            currentIndex = i
        end
    end

    local nextIndex = math.min(currentIndex + 1, #platforms)
    local target = platforms[nextIndex]
    root.CFrame = CFrame.new(target.Position + Vector3.new(0, 3, 0))
    return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.ProcessReceipt = function(receipt)
    local player = Players:GetPlayerByUserId(receipt.PlayerId)
    -- Check for a pending donation
    local pending = pendingDonations[receipt.PlayerId]
    if pending and DONATION_PRODUCTS[receipt.ProductId] then
        -- Add the donated amount to the booth’s total (store as attribute)
        local current = pending.booth:GetAttribute("TotalDonations") or 0
        local newTotal = current + pending.amount
        pending.booth:SetAttribute("TotalDonations", newTotal)
        -- Update the goalLabel text
        local sign = pending.booth:FindFirstChild("Sign")
        if sign then
            local bbg = sign:FindFirstChildOfClass("BillboardGui")
            if bbg then
                local labels = bbg:GetChildren()
                for _, ui in ipairs(labels) do
                    if ui:IsA("TextLabel") and ui.Text:find("R$") then
                        ui.Text = tostring(newTotal) .. " R$"
                    end
                end
            end
        end
        pendingDonations[receipt.PlayerId] = nil
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end

    -- Existing skip‑stage handler remains below (leave your existing code unchanged)
    if player and productHandlers and productHandlers[receipt.ProductId] then
        return productHandlers[receipt.ProductId](receipt, player)
    end
    return Enum.ProductPurchaseDecision.NotProcessedYet
end
