--!strict

-- Grounding: Utilities for ground plane raycasts and distance checks.
-- Uses Shared/Grounding/GroundPlanes if present.

local Workspace = game:GetService("Workspace")

local ok, GroundPlanes = pcall(function()
    return require(script.Parent:WaitForChild("GroundPlanes"))
end)

type CustomRaycastResult = {
    Distance: number,
    Instance: Instance,
    Material: Enum.Material,
    Position: Vector3,
    Normal: Vector3,
}

local module = {}

local function getGroundRaycastParams(): RaycastParams
    if ok and GroundPlanes and typeof(GroundPlanes.getRaycastParams) == "function" then
        return GroundPlanes.getRaycastParams()
    end
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Include
    rp.FilterDescendantsInstances = {}
    return rp
end

function module.getRaycastParams(): RaycastParams
    return getGroundRaycastParams()
end

function module.raycast(origin: Vector3, direction: Vector3): RaycastResult?
    return Workspace:Raycast(origin, direction, getGroundRaycastParams())
end

function module.getGroundDistance(position: Vector3, maxDistance: number): number?
    local dir = -Vector3.yAxis * maxDistance
    local result = module.raycast(position, dir)
    if result then
        return (position - result.Position).Magnitude
    end
    return nil
end

function module.isGround(inst: Instance): boolean
    if ok and GroundPlanes and typeof(GroundPlanes.isGround) == "function" then
        return GroundPlanes.isGround(inst)
    end
    return false
end

return module
