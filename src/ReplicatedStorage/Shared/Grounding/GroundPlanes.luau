--!strict

-- GroundPlanes: Classify and track ground-like planes for raycasts.
-- Heuristics:
--  - Anchored, collidable, relatively thin parts (smallest axis <= thicknessThreshold)
--  - Up vector mostly upwards (dot(up, Y) >= minUpDot)
--  - Or any instance tagged with one of TAGS
-- Exposes:
--  - getRaycastParams(): RaycastParams for ground-only queries (optionally includes Terrain)
--  - getAll(): {BasePart} shallow copy of known ground parts
--  - isGround(inst): boolean membership check
--  - configure(opts): update thresholds and options at runtime

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

type BasePart = Instance & {
    Size: Vector3,
    CFrame: CFrame,
    Anchored: boolean,
    CanCollide: boolean,
}

export type Config = {
    thicknessThreshold: number?,
    minUpDot: number?,
    includeTerrain: boolean?,
    tags: { string }?,
}

local TAGS_DEFAULT = { "Ground", "Plane", "Floor" }

local config = {
    thicknessThreshold = 0.6,
    minUpDot = 0.5,
    includeTerrain = false,
    tags = TAGS_DEFAULT :: { string },
}

local groundSet: { [Instance]: boolean } = {}
local groundList: { BasePart } = {}

local function isTagged(inst: Instance): boolean
    for _, tag in config.tags do
        if CollectionService:HasTag(inst, tag) then
            return true
        end
    end
    return false
end

local function isThin(part: BasePart): boolean
    local s = (part :: any).Size :: Vector3
    local minAxis = math.min(s.X, math.min(s.Y, s.Z))
    return minAxis <= config.thicknessThreshold
end

local function upMostlyUp(part: BasePart): boolean
    local up = (part :: any).CFrame.UpVector :: Vector3
    return up:Dot(Vector3.yAxis) >= config.minUpDot
end

local function qualifiesAsGround(inst: Instance): boolean
    if not inst:IsA("BasePart") then
        return false
    end
    local part = inst :: BasePart
    if isTagged(part) then
        return true
    end
    -- Heuristic checks
    local ok, anchored = pcall(function()
        return (part :: any).Anchored
    end)
    local ok2, collidable = pcall(function()
        return (part :: any).CanCollide
    end)
    if ok and ok2 and anchored and collidable and isThin(part) and upMostlyUp(part) then
        return true
    end
    return false
end

local function rebuildList()
    table.clear(groundSet)
    table.clear(groundList)
    for _, inst in Workspace:GetDescendants() do
        if qualifiesAsGround(inst) then
            groundSet[inst] = true
            table.insert(groundList, inst :: BasePart)
        end
    end
end

local function addIfGround(inst: Instance)
    if qualifiesAsGround(inst) and not groundSet[inst] then
        groundSet[inst] = true
        table.insert(groundList, inst :: BasePart)
    end
end

local function removeIfPresent(inst: Instance)
    if groundSet[inst] then
        groundSet[inst] = nil
        for i = #groundList, 1, -1 do
            if groundList[i] == inst then
                table.remove(groundList, i)
                break
            end
        end
    end
end

-- Watch for descendants being added/removed
Workspace.DescendantAdded:Connect(addIfGround)
Workspace.DescendantRemoving:Connect(removeIfPresent)

-- Watch tag changes for our tags
local function connectTagSignals(tag: string)
    CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
        addIfGround(inst)
    end)
    CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
        removeIfPresent(inst)
    end)
end

for _, tag in config.tags do
    connectTagSignals(tag)
end

-- Initial build
rebuildList()

local module = {}

function module.getRaycastParams(): RaycastParams
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Include
    local list: { Instance } = table.clone(groundList)
    if config.includeTerrain then
        table.insert(list, Workspace.Terrain)
    end
    rp.FilterDescendantsInstances = list
    return rp
end

function module.getAll(): { BasePart }
    return table.clone(groundList)
end

function module.isGround(inst: Instance): boolean
    return groundSet[inst] == true
end

function module.configure(opts: Config)
    if opts.thicknessThreshold ~= nil then
        config.thicknessThreshold = opts.thicknessThreshold
    end
    if opts.minUpDot ~= nil then
        config.minUpDot = opts.minUpDot
    end
    if opts.includeTerrain ~= nil then
        config.includeTerrain = opts.includeTerrain
    end
    if opts.tags ~= nil then
        config.tags = opts.tags
        -- Reconnect signals for new tag set (no disconnects to keep it simple)
        for _, tag in config.tags do
            connectTagSignals(tag)
        end
    end
    rebuildList()
end

return module
