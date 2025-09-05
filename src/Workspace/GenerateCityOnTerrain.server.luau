-- GenerateCityOnTerrain
-- Scans Terrain to approximate bounds, then generates a spaced city layout
-- Uses Workspace.Terrain, Region3, Instance.new("Model"/"Part"), and FindPartsInRegion3 for collision checks

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Terrain = Workspace:FindFirstChildOfClass("Terrain")
if not Terrain then
    warn("[GenerateCityOnTerrain] No Terrain found in Workspace; aborting.")
    return
end

-- Avoid double-generation on re-run
if Workspace:FindFirstChild("GeneratedCity") then
    return
end

-- Utility: random float in [a, b]
local function randf(a: number, b: number): number
    return a + (b - a) * math.random()
end

-- Ensure Region3 mins <= maxes and expand to grid for Terrain voxel ops
local function mkRegion(minV: Vector3, maxV: Vector3, grid: number)
    local mn = Vector3.new(
        math.min(minV.X, maxV.X),
        math.min(minV.Y, maxV.Y),
        math.min(minV.Z, maxV.Z)
    )
    local mx = Vector3.new(
        math.max(minV.X, maxV.X),
        math.max(minV.Y, maxV.Y),
        math.max(minV.Z, maxV.Z)
    )
    local r = Region3.new(mn, mx)
    return r:ExpandToGrid(grid)
end

-- Helper to quickly test if a voxel column contains any non-air material
local function columnHasTerrain(x0: number, z0: number, width: number, yMin: number, yMax: number, voxel: number)
    local region = mkRegion(Vector3.new(x0, yMin, z0), Vector3.new(x0 + width, yMax, z0 + width), voxel)
    local rSize = region.Size
    local sizeX = math.max(1, math.floor(rSize.X / voxel + 0.5))
    local sizeY = math.max(1, math.floor(rSize.Y / voxel + 0.5))
    local sizeZ = math.max(1, math.floor(rSize.Z / voxel + 0.5))
    local materials, occupancy = Terrain:ReadVoxels(region, voxel)
    for ix = 1, sizeX do
        for iy = 1, sizeY do
            for iz = 1, sizeZ do
                if occupancy[ix][iy][iz] and occupancy[ix][iy][iz] > 0 then
                    if materials[ix][iy][iz] ~= Enum.Material.Air then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Approximate terrain bounds by scanning coarse grid around origin
local function getTerrainBounds()
    -- Search ranges and resolution tuned to avoid heavy work but still find area
    local MAX_RADIUS = 2048
    local STEP = 128
    local VOXEL = 8
    local Y_MIN = -256
    local Y_MAX = 512

    local minVec: Vector3? = nil
    local maxVec: Vector3? = nil

    for x = -MAX_RADIUS, MAX_RADIUS, STEP do
        for z = -MAX_RADIUS, MAX_RADIUS, STEP do
            if columnHasTerrain(x, z, STEP, Y_MIN, Y_MAX, VOXEL) then
                local mn = Vector3.new(x, Y_MIN, z)
                local mx = Vector3.new(x + STEP, Y_MAX, z + STEP)
                if not minVec then
                    minVec = mn
                    maxVec = mx
                else
                    minVec = Vector3.new(
                        math.min(minVec.X, mn.X),
                        math.min(minVec.Y, mn.Y),
                        math.min(minVec.Z, mn.Z)
                    )
                    maxVec = Vector3.new(
                        math.max(maxVec.X, mx.X),
                        math.max(maxVec.Y, mx.Y),
                        math.max(maxVec.Z, mx.Z)
                    )
                end
            end
        end
        -- yield periodically to keep server responsive if scanning many cells
        RunService.Heartbeat:Wait()
    end

    if not minVec or not maxVec then
        -- Fallback to a default patch near origin if nothing detected
        minVec = Vector3.new(-256, -32, -256)
        maxVec = Vector3.new(256, 128, 256)
    end
    return minVec, maxVec
end

local minVec, maxVec = getTerrainBounds()
local center = (minVec + maxVec) / 2
local terrainSize = maxVec - minVec

-- City model container
local cityModel = Instance.new("Model")
cityModel.Name = "GeneratedCity"
cityModel.Parent = Workspace

-- Parameters scaled to terrain size
local footprintX = math.max(64, terrainSize.X)
local footprintZ = math.max(64, terrainSize.Z)
local areaXZ = footprintX * footprintZ

local numBuildings = math.clamp(math.floor(areaXZ / 80000), 10, 300)
local largestSpan = math.max(footprintX, footprintZ)
local buildingMinSize = math.clamp(largestSpan / 90, 12, 40)
local buildingMaxSize = math.clamp(largestSpan / 22, 40, 140)
local spacing = buildingMaxSize * 0.75

-- Cast down to land height (Terrain or any part)
local function getGroundY(x: number, z: number): number?
    local origin = Vector3.new(x, maxVec.Y + 512, z)
    local direction = Vector3.new(0, -1, 0) * (terrainSize.Y + 1024)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { cityModel }
    local res = Workspace:Raycast(origin, direction, params)
    if res then
        return res.Position.Y
    end
    return nil
end

-- Find parts in region (collision check), ignoring current city model
local function findPartsInRegion(region: Region3)
    -- Legacy API as requested
    return Workspace:FindPartsInRegion3(region, cityModel, math.huge)
end

-- Check overlap with placed buildings and other parts
local placed = {} :: { { pos: Vector3, size: Vector3 } }
local function regionHasTerrain(minV: Vector3, maxV: Vector3, voxel: number): boolean
    local region = mkRegion(minV, maxV, voxel)
    local rSize = region.Size
    local sx = math.max(1, math.floor(rSize.X / voxel + 0.5))
    local sy = math.max(1, math.floor(rSize.Y / voxel + 0.5))
    local sz = math.max(1, math.floor(rSize.Z / voxel + 0.5))
    local materials, occupancy = Terrain:ReadVoxels(region, voxel)
    for ix = 1, sx do
        for iy = 1, sy do
            for iz = 1, sz do
                if occupancy[ix][iy][iz] and occupancy[ix][iy][iz] > 0 then
                    if materials[ix][iy][iz] ~= Enum.Material.Air then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function isClear(pos: Vector3, size: Vector3): boolean
    local half = size / 2
    local region = Region3.new(pos - half, pos + half)
    local parts = findPartsInRegion(region)
    if #parts > 0 then
        return false
    end
    -- Check for terrain intrusion above the base (allow small epsilon near base)
    local VOXEL = 8
    local baseClearMin = Vector3.new(pos.X - half.X, pos.Y - half.Y + 1, pos.Z - half.Z)
    local baseClearMax = Vector3.new(pos.X + half.X, pos.Y + half.Y, pos.Z + half.Z)
    if regionHasTerrain(baseClearMin, baseClearMax, VOXEL) then
        return false
    end
    for _, it in ipairs(placed) do
        local dx = math.abs(pos.X - it.pos.X)
        local dz = math.abs(pos.Z - it.pos.Z)
        local allowX = (size.X + it.size.X) / 2 + spacing
        local allowZ = (size.Z + it.size.Z) / 2 + spacing
        if dx < allowX and dz < allowZ then
            return false
        end
    end
    return true
end

-- Grid sampling with jitter to avoid bunching
local startX = minVec.X + spacing
local startZ = minVec.Z + spacing
local endX = maxVec.X - spacing
local endZ = maxVec.Z - spacing
local step = math.max(spacing, buildingMinSize * 1.2)

local placedCount = 0
for x = startX, endX, step do
    for z = startZ, endZ, step do
        if placedCount >= numBuildings then break end

        -- Randomize building footprint and jitter position
        local sx = randf(buildingMinSize, buildingMaxSize)
        local sz = randf(buildingMinSize, buildingMaxSize)
        local sy = randf(buildingMinSize * 2, buildingMaxSize * 3)
        local jx = randf(-step * 0.35, step * 0.35)
        local jz = randf(-step * 0.35, step * 0.35)
        local px = x + jx
        local pz = z + jz

        local gy = getGroundY(px, pz)
        if gy then
            local pos = Vector3.new(px, gy + sy / 2, pz)
            local size = Vector3.new(sx, sy, sz)
            if isClear(pos, size) then
                local part = Instance.new("Part")
                part.Name = "Building"
                part.Size = size
                part.Position = pos
                part.Anchored = true
                part.Material = Enum.Material.Concrete
                part.Color = Color3.fromRGB(
                    math.random(160, 230),
                    math.random(160, 230),
                    math.random(160, 230)
                )
                part.TopSurface = Enum.SurfaceType.Smooth
                part.BottomSurface = Enum.SurfaceType.Smooth
                part.Parent = cityModel

                table.insert(placed, { pos = pos, size = size })
                placedCount += 1
            end
        end
    end
    -- yield per row to keep heartbeat
    RunService.Heartbeat:Wait()
end

print(string.format("[GenerateCityOnTerrain] Placed %d/%d buildings within terrain bounds.", placedCount, numBuildings))
