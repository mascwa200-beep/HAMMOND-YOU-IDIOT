-- Client bootstrap for FlightController
-- Press F to toggle flight. While flying: WASD to move, Space to ascend, LeftControl to descend, LeftShift to sprint.

if _G.__FlightClientInitialized then
    return
end
_G.__FlightClientInitialized = true

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FlightController = require(Shared:WaitForChild("Flight"):WaitForChild("FlightController"))
local FlightAnimator = require(Shared:WaitForChild("Animation"):WaitForChild("FlightAnimator"))

local controller = FlightController.forLocalPlayer({
    -- Adjust defaults here if desired
    speed = 70,
    sprintMultiplier = 1.8,
    ascendKey = Enum.KeyCode.Space,
    descendKey = Enum.KeyCode.LeftControl,
    descendAltKey = Enum.KeyCode.C, -- fallback in environments where Ctrl+W is intercepted
    sprintKey = Enum.KeyCode.LeftShift,
    ascendSpeed = 70,
    descendSpeed = 70,
    transitionTime = 1.0, -- gentle hover duration on enable
    liftAmount = 3.0, -- studs to rise during hover
    -- Modular behavior tuning
    alignTo = "movement",
    inputSpace = "camera",
    -- Keep default controls active; flight code uses its own
    -- input tracking and won’t conflict with modifiers like LeftControl.
    disableDefaultControls = false,
    suppressFallingAnim = true, -- suppress default tracks while flight animator drives
    moveThreshold = 0.15, -- if below, treat as standstill and hover
    activateAltitude = 1.5, -- switch to full flight once risen this much
    landingMode = "untilGround",
    landingDescendSpeed = 18,
    landingHorizFriction = 5,
    landingPlane = "feet",
    landingGroundTolerance = 0.15,
    landingRayLength = 25,
    landingMinDescendSpeed = 6,
    landingApproachRate = 8,
    pose = "none", -- external animator drives the pose
    poseSmoothing = 0.25,
})

local ACTION_TOGGLE = "ToggleFlight"
local TOGGLE_KEY = Enum.KeyCode.F -- The button to press for flight (no UI)
pcall(function()
    ContextActionService:UnbindAction(ACTION_TOGGLE)
end)

local function onToggle(_, inputState: Enum.UserInputState)
    if inputState == Enum.UserInputState.Begin then
        controller:toggle()
    end
end

ContextActionService:BindAction(ACTION_TOGGLE, onToggle, false, TOGGLE_KEY)

-- Keep controller alive across character spawns; state persists
Players.LocalPlayer.CharacterAdded:Connect(function()
    if controller.enabled then
        -- Re-apply on the next frame to allow character parts to exist
        task.defer(function()
            controller:enable()
        end)
    end
end)

-- Bind modular flight animator (assetless procedural by default)
local anim = FlightAnimator.forLocalPlayer(controller, {
    keys = {
        ascend = Enum.KeyCode.Space,
        descend = Enum.KeyCode.LeftControl,
        sprint = Enum.KeyCode.LeftShift,
    },
    -- animIds = { -- supply if/when you have custom assets
    --     hover = "rbxassetid://<id>",
    --     cruise = "rbxassetid://<id>",
    --     sprint = "rbxassetid://<id>",
    --     ascend = "rbxassetid://<id>",
    --     descend = "rbxassetid://<id>",
    -- },
    smoothing = 0.25,
})
