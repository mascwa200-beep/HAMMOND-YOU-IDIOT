-- GroundPlanes: self-contained, idempotent, modular registry of ground planes
-- Classifies available planes in the world as "ground" based on heuristics and optional tags.
-- Provides helpers to query, listen, and build RaycastParams that target ground only.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

export type Options = {
    thicknessThreshold: number?, -- max smallest axis (studs) to consider planar
    minUpDot: number?, -- min dot(UpVector, worldUp) to be considered upward-facing
    requireAnchored: boolean?, -- only anchored parts count
    requireCanCollide: boolean?, -- only CanCollide parts count
    includeTerrain: boolean?,
    tagOverrides: { string }?, -- any of these tags force inclusion regardless of heuristics
}

export type GroundPlanesModule = {
    configure: (opts: Options?) -> (),
    refresh: () -> (),
    getAll: () -> { BasePart },
    isGround: (inst: Instance?) -> boolean,
    getRaycastParams: (base?: RaycastParams?) -> RaycastParams,
    raycast: (origin: Vector3, direction: Vector3, character: Model?, base?: RaycastParams?) -> RaycastResult?,
}

local DEFAULTS: Options = {
    thicknessThreshold = 0.6, -- studs
    minUpDot = 0.25, -- allow slight slopes
    requireAnchored = true,
    requireCanCollide = true,
    includeTerrain = true,
    tagOverrides = { "Ground", "Plane", "Floor" },
}

local opts: Options = table.clone(DEFAULTS)

local groundSet: { [BasePart]: true } = {}
local tracked: { [BasePart]: { [string]: RBXScriptConnection } } = {}
local initialized = false

local function hasAnyTag(inst: Instance, tags: { string }): boolean
    for _, t in ipairs(tags) do
        if CollectionService:HasTag(inst, t) then
            return true
        end
    end
    return false
end

local function isPlanarPart(part: BasePart): boolean
    -- Tag override first
    if hasAnyTag(part, opts.tagOverrides :: { string }) then
        return true
    end

    -- Heuristics only apply to common primitives where Size is meaningful
    -- For MeshPart/Union, fall back to name/tag heuristics only
    local className = part.ClassName
    if className == "MeshPart" or className == "UnionOperation" then
        -- Can't reliably infer planarity; require tag override
        return false
    end

    local s = part.Size
    local minAxis = math.min(s.X, s.Y, s.Z)
    if minAxis > (opts.thicknessThreshold or DEFAULTS.thicknessThreshold :: number) then
        return false
    end

    local up = part.CFrame.UpVector
    local upDot = up:Dot(Vector3.yAxis)
    if upDot < (opts.minUpDot or DEFAULTS.minUpDot :: number) then
        return false
    end

    if opts.requireAnchored and not part.Anchored then
        return false
    end
    if opts.requireCanCollide and not part.CanCollide then
        return false
    end

    return true
end

local function addGround(part: BasePart)
    if groundSet[part] then return end
    groundSet[part] = true
end

local function removeGround(part: BasePart)
    if not groundSet[part] then return end
    groundSet[part] = nil
end

local function evaluate(part: BasePart)
    if isPlanarPart(part) then
        addGround(part)
    else
        removeGround(part)
    end
end

local function track(part: BasePart)
    if tracked[part] then return end
    evaluate(part)
    local conns: { [string]: RBXScriptConnection } = {}
    conns.size = part:GetPropertyChangedSignal("Size"):Connect(function()
        evaluate(part)
    end)
    conns.cframe = part:GetPropertyChangedSignal("CFrame"):Connect(function()
        evaluate(part)
    end)
    conns.anchored = part:GetPropertyChangedSignal("Anchored"):Connect(function()
        evaluate(part)
    end)
    conns.collide = part:GetPropertyChangedSignal("CanCollide"):Connect(function()
        evaluate(part)
    end)
    conns.name = part:GetPropertyChangedSignal("Name"):Connect(function()
        -- Name change could matter if creator names parts "Floor" and tags later
        evaluate(part)
    end)
    -- Tags can change; listen via CollectionService signal (global)
    tracked[part] = conns
end

local function untrack(part: BasePart)
    local conns = tracked[part]
    if conns then
        for _, c in pairs(conns) do
            pcall(function() c:Disconnect() end)
        end
        tracked[part] = nil
    end
    removeGround(part)
end

local function scan(desc: Instance)
    for _, inst in ipairs(desc:GetDescendants()) do
        if inst:IsA("BasePart") then
            track(inst)
        end
    end
    if desc:IsA("BasePart") then
        track(desc)
    end
end

local function attachSignals()
    Workspace.DescendantAdded:Connect(function(inst)
        if inst:IsA("BasePart") then
            track(inst)
        end
    end)
    Workspace.DescendantRemoving:Connect(function(inst)
        if inst:IsA("BasePart") then
            untrack(inst)
        end
    end)
end

local tagConnMap: { [string]: { add: RBXScriptConnection, rem: RBXScriptConnection } } = {}

local function attachTagSignals(tags: { string })
    for _, tag in ipairs(tags) do
        if not tagConnMap[tag] then
            local addConn = CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
                if inst:IsA("BasePart") then evaluate(inst) end
            end)
            local remConn = CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
                if inst:IsA("BasePart") then evaluate(inst) end
            end)
            tagConnMap[tag] = { add = addConn, rem = remConn }
        end
    end
end

local GroundPlanes = {} :: GroundPlanesModule

function GroundPlanes.configure(newOpts: Options?)
    if not newOpts then return end
    for k, v in pairs(newOpts) do
        (opts :: any)[k] = v
    end
    if newOpts.tagOverrides then
        attachTagSignals(newOpts.tagOverrides)
    end
    -- Re-evaluate all currently tracked parts after config change
    for part, _ in pairs(tracked) do
        evaluate(part)
    end
end

function GroundPlanes.refresh()
    -- Clear and rescan
    for part, _ in pairs(tracked) do
        untrack(part)
    end
    groundSet = {}
    tracked = {}
    scan(Workspace)
end

function GroundPlanes.getAll(): { BasePart }
    local arr = {}
    for part, _ in pairs(groundSet) do
        table.insert(arr, part)
    end
    -- Terrain: representable via raycast only; not returned in list
    return arr
end

function GroundPlanes.isGround(inst: Instance?): boolean
    if not inst then return false end
    if inst == Workspace.Terrain then
        return opts.includeTerrain == true
    end
    if inst:IsA("BasePart") then
        return groundSet[inst] == true
    end
    return false
end

function GroundPlanes.getRaycastParams(base: RaycastParams?): RaycastParams
    local rp = base or RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Include
    rp.FilterDescendantsInstances = GroundPlanes.getAll()
    return rp
end

local function ensureExclude(rp: RaycastParams, inst: Instance)
    if rp.FilterType ~= Enum.RaycastFilterType.Exclude then return end
    local list = {}
    for _, i in ipairs(rp.FilterDescendantsInstances or {}) do
        table.insert(list, i)
    end
    table.insert(list, inst)
    rp.FilterDescendantsInstances = list
end

function GroundPlanes.raycast(origin: Vector3, direction: Vector3, character: Model?, base: RaycastParams?): RaycastResult?
    -- First pass: ground parts only (Include)
    local rpInclude = GroundPlanes.getRaycastParams(base)
    if character and rpInclude.FilterType == Enum.RaycastFilterType.Exclude then
        ensureExclude(rpInclude, character)
    end
    local hit = Workspace:Raycast(origin, direction, rpInclude)
    if hit then return hit end

    if not (opts.includeTerrain == true) then
        return nil
    end

    -- Second pass: search for Terrain only via iterative exclusion of non-terrain hits
    local rp = base or RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = rp.FilterDescendantsInstances or {}
    if character then ensureExclude(rp, character) end

    local tries = 0
    while tries < 20 do
        tries += 1
        local res = Workspace:Raycast(origin, direction, rp)
        if not res then return nil end
        if res.Instance == Workspace.Terrain then
            return res
        end
        -- Not terrain; ignore and continue searching
        ensureExclude(rp, res.Instance)
    end
    return nil
end

local function initOnce()
    if initialized then return end
    initialized = true
    scan(Workspace)
    attachSignals()
    attachTagSignals(opts.tagOverrides :: { string })
end

initOnce()

return GroundPlanes
