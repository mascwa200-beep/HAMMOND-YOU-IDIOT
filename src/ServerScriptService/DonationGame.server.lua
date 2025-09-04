-- DonationGame.server.lua
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- RemoteEvent for client -> server donation requests (new name)
local donateEvent = ReplicatedStorage:FindFirstChild("DonateToBooth")
if not donateEvent then
    donateEvent = Instance.new("RemoteEvent")
    donateEvent.Name = "DonateToBooth"
    donateEvent.Parent = ReplicatedStorage
end

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
    model:SetAttribute("OwnerUserId", 0)

    local base = Instance.new("Part")
    base.Size = Vector3.new(4, 1, 4)
    base.Position = position + Vector3.new(0, 0.5, 0)
    base.Anchored = true
    base.Name = "Base"
    base.Parent = model

    local sign = Instance.new("Part")
    sign.Size = Vector3.new(6, 4, 0.5)
    sign.Position = position + Vector3.new(0, 2, -2)
    sign.Anchored = true
    sign.Name = "Sign"
    sign.Parent = model
    sign.BrickColor = BrickColor.new("Institutional white")

    -- Whiteboard GUI on the front of the sign
    local boardGui = Instance.new("SurfaceGui")
    boardGui.Name = "BoardGui"
    boardGui.Face = Enum.NormalId.Front
    boardGui.CanvasSize = Vector2.new(600, 400)
    boardGui.AlwaysOnTop = true
    boardGui.Parent = sign

    -- Title label (rigid font)
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 0.3, 0)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "Unclaimed"
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextScaled = true
    titleLabel.TextColor3 = Color3.new(0, 0.7, 0)
    titleLabel.Parent = boardGui

    -- Donation total label (rigid font)
    local totalLabel = Instance.new("TextLabel")
    totalLabel.Size = UDim2.new(1, 0, 0.2, 0)
    totalLabel.Position = UDim2.new(0, 0, 0.3, 0)
    totalLabel.BackgroundTransparency = 1
    totalLabel.Text = "0 R$"
    totalLabel.Font = Enum.Font.GothamBold
    totalLabel.TextScaled = true
    totalLabel.TextColor3 = Color3.new(0, 0.7, 0)
    totalLabel.Parent = boardGui

    -- Frame for the donation buttons row
    local buttonRow = Instance.new("Frame")
    buttonRow.Name = "ButtonRow"
    buttonRow.Size = UDim2.new(1, 0, 0.5, 0)
    buttonRow.Position = UDim2.new(0, 0, 0.5, 0)
    buttonRow.BackgroundTransparency = 1
    buttonRow.Parent = boardGui

    -- Marker‑style donation buttons
    do
        -- Build an ordered list from the DONATION_PRODUCTS map
        local products = {}
        for productId, amount in pairs(DONATION_PRODUCTS) do
            table.insert(products, { productId = productId, amount = amount })
        end
        table.sort(products, function(a, b)
            return a.amount < b.amount
        end)

        local n = #products
        for i, info in ipairs(products) do
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1 / n, -5, 1, -5)
            btn.Position = UDim2.new((i - 1) / n, 2, 0, 2)
            btn.BackgroundColor3 = Color3.new(1, 1, 1) -- white board
            btn.BorderSizePixel = 2
            btn.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
            btn.Text = tostring(info.amount) .. " R$"
            btn.Font = Enum.Font.Cartoon  -- looks hand‑drawn
            btn.TextScaled = true
            btn.TextColor3 = Color3.new(0, 0, 0)
            btn.Parent = buttonRow

            -- store metadata for client click handling
            btn:SetAttribute("ProductId", info.productId)
            btn:SetAttribute("Amount", info.amount)
        end
    end

    local click = Instance.new("ClickDetector")
    click.MaxActivationDistance = 10
    click.Parent = sign

    local owner = nil

    click.MouseClick:Connect(function(player)
        if not owner then
            owner = player
            titleLabel.Text = player.DisplayName .. "'s Booth"
            totalLabel.Text = "0 R$"
            model:SetAttribute("OwnerUserId", player.UserId)
        elseif owner == player then
            owner = nil
            titleLabel.Text = "Unclaimed"
            totalLabel.Text = "0 R$"
            model:SetAttribute("OwnerUserId", 0)
        else
            -- When a visitor clicks another player's booth, prompt a donation
            MarketplaceService:PromptProductPurchase(player, SKIP_STAGE_PRODUCT)
        end
    end)

    -- (Old 3D donation buttons removed; buttons now live in BoardGui)

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

-- Handle donation requests from client GUI buttons (amount-based)
donateEvent.OnServerEvent:Connect(function(player, boothModel, amount)
    if typeof(amount) ~= "number" then return end

    -- Find a productId that matches the requested amount
    local productId
    for pid, amt in pairs(DONATION_PRODUCTS) do
        if amt == amount then
            productId = pid
            break
        end
    end
    if not productId then return end

    -- Validate booth reference
    if not (boothModel and typeof(boothModel) == "Instance" and boothModel:IsA("Model") and (boothModel.Parent == boothFolder or boothModel:IsDescendantOf(boothFolder))) then
        return
    end

    local ownerUserId = boothModel:GetAttribute("OwnerUserId") or 0
    if ownerUserId == 0 or ownerUserId == player.UserId then
        return
    end

    pendingDonations[player.UserId] = { booth = boothModel, amount = amount }
    MarketplaceService:PromptProductPurchase(player, productId)
end)

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
        -- Update the total label text on the whiteboard
        local sign = pending.booth:FindFirstChild("Sign")
        if sign then
            local boardGui = sign:FindFirstChild("BoardGui")
            if boardGui then
                for _, ui in ipairs(boardGui:GetDescendants()) do
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
