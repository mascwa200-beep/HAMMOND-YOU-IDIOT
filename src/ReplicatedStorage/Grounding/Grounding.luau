-- Grounding: Modular ground/plane contact helpers for characters
-- Provides distance-to-ground and plane-contact checks, focusing on "feet" contact by default.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Try to source optional GroundPlanes module to define what counts as ground.
local GroundPlanes: any = nil
do
    local ok, shared = pcall(function()
        return ReplicatedStorage:WaitForChild("Shared")
    end)
    if ok and shared then
        pcall(function()
            GroundPlanes = require(shared:WaitForChild("Grounding"):WaitForChild("GroundPlanes"))
        end)
    end
end

export type Plane = "feet" | "bottom" | "top" | "front" | "back" | "left" | "right"

local Grounding = {}

local function findFootParts(character: Model): { BasePart }
    local parts = {}
    local names = { "LeftFoot", "RightFoot", "LeftLowerLeg", "RightLowerLeg", "Left Leg", "Right Leg" }
    for _, n in ipairs(names) do
        local inst = character:FindFirstChild(n, true)
        if inst and inst:IsA("BasePart") then
            table.insert(parts, inst)
        end
    end
    return parts
end

local function hrpOrTorso(character: Model): BasePart?
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then return hrp end
    local torso = character:FindFirstChild("LowerTorso") or character:FindFirstChild("Torso")
    if torso and torso:IsA("BasePart") then return torso end
    return nil
end

local function buildRayParams(character: Model, params: RaycastParams?): RaycastParams
    local rp = params
    if not rp then
        if GroundPlanes and GroundPlanes.getRaycastParams then
            rp = GroundPlanes.getRaycastParams()
        else
            rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Exclude
        end
    end
    -- Ensure we ignore the character if using Exclude filtering
    if rp.FilterType == Enum.RaycastFilterType.Exclude then
        local list = {}
        for _, inst in ipairs(rp.FilterDescendantsInstances or {}) do
            table.insert(list, inst)
        end
        table.insert(list, character)
        rp.FilterDescendantsInstances = list
    end
    return rp
end

local function samplePoints(character: Model, plane: Plane): { { origin: Vector3, dir: Vector3 } }
    plane = plane or "feet"
    local points = {}
    if plane == "feet" or plane == "bottom" then
        local feet = findFootParts(character)
        -- If feet not found, we will sample around root instead
        local dir = Vector3.new(0, -1, 0)
        if #feet > 0 then
            for _, part in ipairs(feet) do
                local origin = part.Position + part.CFrame.UpVector * (part.Size.Y * 0.2)
                table.insert(points, { origin = origin, dir = dir })
            end
        else
            local root = hrpOrTorso(character)
            if root then
                local originCenter = root.Position
                local offset = root.Size.X * 0.3
                table.insert(points, { origin = originCenter + root.CFrame.RightVector * offset, dir = dir })
                table.insert(points, { origin = originCenter - root.CFrame.RightVector * offset, dir = dir })
            end
        end
    else
        -- Generic planes relative to HRP
        local root = hrpOrTorso(character)
        if root then
            local dir
            if plane == "top" then dir = Vector3.new(0, 1, 0)
            elseif plane == "front" then dir = root.CFrame.LookVector
            elseif plane == "back" then dir = -root.CFrame.LookVector
            elseif plane == "left" then dir = -root.CFrame.RightVector
            elseif plane == "right" then dir = root.CFrame.RightVector
            else dir = Vector3.new(0, -1, 0) end
            table.insert(points, { origin = root.Position, dir = dir })
        end
    end
    return points
end

-- Returns the minimum distance from the chosen plane to any hit along cast direction.
function Grounding.distanceToPlane(character: Model, plane: Plane?, rayLength: number?, params: RaycastParams?): number?
    local casts = samplePoints(character, plane or "feet")
    if #casts == 0 then return nil end
    local rp = buildRayParams(character, params)
    local length = rayLength or 25
    local minDist: number? = nil
    for _, c in ipairs(casts) do
        local result
        if GroundPlanes and GroundPlanes.raycast then
            result = GroundPlanes.raycast(c.origin, c.dir.Unit * length, character, rp)
        else
            result = Workspace:Raycast(c.origin, c.dir.Unit * length, rp)
        end
        if result then
            local d = (result.Position - c.origin).Magnitude
            if not minDist or d < minDist then minDist = d end
        end
    end
    return minDist
end

-- Returns true when the chosen plane has contacted something within the tolerance
function Grounding.isPlaneContact(character: Model, plane: Plane?, tolerance: number?, rayLength: number?, params: RaycastParams?): (boolean, number?)
    local dist = Grounding.distanceToPlane(character, plane, rayLength, params)
    if not dist then return false, nil end
    local tol = tolerance or 0.15
    return dist <= tol, dist
end

return Grounding
