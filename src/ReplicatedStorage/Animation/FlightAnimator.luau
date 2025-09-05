-- FlightAnimator: Modular, idempotent flight animation driver
-- Goals
-- - Self-contained: does not require modifying other systems
-- - Idempotent: safe to bind multiple times; returns same instance
-- - Modular: plugs into any flight controller that exposes `enabled` and key config
-- - Two modes: asset-based (AnimationIds) or procedural poses (Motor6D.Transform)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Debug
do
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Debug"):WaitForChild("DebugFlags"))
    end)
    if ok then Debug = mod end
end

export type AnimIds = {
    hover: string?,
    cruise: string?,
    sprint: string?,
    ascend: string?,
    descend: string?,
}

export type Config = {
    keys: {
        ascend: Enum.KeyCode?,
        descend: Enum.KeyCode?,
        sprint: Enum.KeyCode?,
    }?,
    animIds: AnimIds?, -- optional Animation asset ids, else procedural
    smoothing: number?, -- 0..1 transform lerp per frame
    priority: number?, -- reserved for future provider priority
}

export type InstanceType = {
    player: Player,
    controller: any?,
    config: Config,
    _conn: RBXScriptConnection?,
    _animator: Animator?,
    _tracks: { [string]: AnimationTrack }?,
    _joints: { [string]: Motor6D }?,
    destroy: (self: InstanceType) -> (),
}

local DEFAULTS: Config = {
    keys = {
        ascend = Enum.KeyCode.Space,
        descend = Enum.KeyCode.LeftControl,
        sprint = Enum.KeyCode.LeftShift,
    },
    animIds = nil,
    smoothing = 0.25,
    priority = 50,
}

local Singletons: { [Player]: InstanceType } = {}

local function mergeConfig(partial: Config?): Config
    local cfg: Config = {}
    for k, v in pairs(DEFAULTS) do (cfg :: any)[k] = v end
    if partial then for k, v in pairs(partial) do (cfg :: any)[k] = v end end
    return cfg
end

local function getHumanoid(player: Player): (Model?, Humanoid?, BasePart?)
    local char = player.Character
    if not char then return nil, nil, nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    return char, hum, hrp
end

local function gatherJoints(character: Model)
    local joints: { [string]: Motor6D } = {}
    local nameSets = {
        "RightShoulder", "LeftShoulder", "RightHip", "LeftHip", "Neck", "RootJoint", "Root",
        -- R6 alternate naming with spaces
        "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip",
    }
    local function add(name)
        local inst = character:FindFirstChild(name, true)
        if inst and inst:IsA("Motor6D") then joints[name] = inst end
    end
    for _, n in ipairs(nameSets) do add(n) end

    -- If still missing shoulders (custom rigs), search any Motor6D connected to arms/legs
    local foundAny = (next(joints) ~= nil)
    if not foundAny then
        for _, inst in ipairs(character:GetDescendants()) do
            if inst:IsA("Motor6D") then
                if tostring(inst.Name):lower():find("shoulder") or tostring(inst.Name):lower():find("hip") or tostring(inst.Name):lower():find("neck") then
                    joints[inst.Name] = inst
                end
            end
        end
    end
    return joints
end

local function stopAllTracks(animator: Animator)
    pcall(function()
        for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do tr:Stop(0.1) end
    end)
end

local function loadTracks(animator: Animator, ids: AnimIds)
    local tracks: { [string]: AnimationTrack } = {}
    for name, id in pairs(ids) do
        if id and id ~= "" then
            local anim = Instance.new("Animation")
            anim.AnimationId = tostring(id):find("rbxassetid") and id or ("rbxassetid://" .. tostring(id))
            local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
            if ok and track then track.Looped = true; tracks[name] = track end
        end
    end
    return tracks
end

local function playExclusive(tracks: { [string]: AnimationTrack }, name: string)
    if not tracks then return end
    for key, tr in pairs(tracks) do
        if key == name then
            if not tr.IsPlaying then pcall(function() tr:Play(0.15) end) end
        else
            if tr.IsPlaying then pcall(function() tr:Stop(0.15) end) end
        end
    end
end

local function lerpMotor(m: Motor6D?, target: CFrame, alpha: number)
    if not m then return end
    m.Transform = m.Transform:Lerp(target, math.clamp(alpha, 0, 1))
end

local function applyProceduralPose(joints: { [string]: Motor6D }?, state: string, alpha: number)
    if not joints then return end
    -- Default neutral
    local RS, LS = joints.RightShoulder, joints.LeftShoulder
    local RH, LH = joints.RightHip, joints.LeftHip
    local NK = joints.Neck
    local armFwd, armUp = -0.7, 1.0
    local small = 0.15

    if state == "hover" then
        -- Hal-style relaxed hover: slight elbows down, open chest
        lerpMotor(RS, CFrame.Angles(-0.3, small, 0), alpha)
        lerpMotor(LS, CFrame.Angles(-0.3, -small, 0), alpha)
        lerpMotor(RH, CFrame.Angles(0.1, 0, 0), alpha)
        lerpMotor(LH, CFrame.Angles(0.1, 0, 0), alpha)
        lerpMotor(NK, CFrame.Angles(0, 0, 0), alpha)
    elseif state == "cruise" then
        -- Slow forward: slight nose-down, arms back a bit
        lerpMotor(RS, CFrame.Angles(-0.5, small, 0), alpha)
        lerpMotor(LS, CFrame.Angles(-0.5, -small, 0), alpha)
        lerpMotor(RH, CFrame.Angles(0.2, 0, 0), alpha)
        lerpMotor(LH, CFrame.Angles(0.2, 0, 0), alpha)
        lerpMotor(NK, CFrame.Angles(0, 0, 0), alpha)
    elseif state == "sprint" then
        -- John Stewart: one arm forward, body streamlined
        lerpMotor(RS, CFrame.Angles(armFwd, 0, 0), alpha)
        lerpMotor(LS, CFrame.Angles(-0.2, 0, 0), alpha)
        lerpMotor(RH, CFrame.Angles(0.3, 0, 0), alpha)
        lerpMotor(LH, CFrame.Angles(0.3, 0, 0), alpha)
        lerpMotor(NK, CFrame.Angles(0, 0, 0), alpha)
    elseif state == "ascend" then
        -- Arms up and slightly forward
        lerpMotor(RS, CFrame.Angles(armUp, small, 0), alpha)
        lerpMotor(LS, CFrame.Angles(armUp, -small, 0), alpha)
        lerpMotor(RH, CFrame.Angles(0.1, 0, 0), alpha)
        lerpMotor(LH, CFrame.Angles(0.1, 0, 0), alpha)
        lerpMotor(NK, CFrame.Angles(-0.1, 0, 0), alpha)
    elseif state == "descend" then
        -- Arms trailing slightly downward
        lerpMotor(RS, CFrame.Angles(-0.2, small, 0), alpha)
        lerpMotor(LS, CFrame.Angles(-0.2, -small, 0), alpha)
        lerpMotor(RH, CFrame.Angles(0.05, 0, 0), alpha)
        lerpMotor(LH, CFrame.Angles(0.05, 0, 0), alpha)
        lerpMotor(NK, CFrame.Angles(0.05, 0, 0), alpha)
    else
        -- reset
        lerpMotor(RS, CFrame.new(), alpha)
        lerpMotor(LS, CFrame.new(), alpha)
        lerpMotor(RH, CFrame.new(), alpha)
        lerpMotor(LH, CFrame.new(), alpha)
        lerpMotor(NK, CFrame.new(), alpha)
    end
end

local AnimatorMt = {} :: InstanceType
AnimatorMt.__index = AnimatorMt

function AnimatorMt:_bind()
    if self._conn then return end
    self._conn = RunService.RenderStepped:Connect(function()
        local char, hum = getHumanoid(self.player)
        if not hum then return end

        -- Reacquire animator/joints after respawn
        if not self._animator or self._animator.Parent ~= hum then
            self._animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
            self._tracks = nil
            self._joints = nil
            if self.config.animIds then
                self._tracks = loadTracks(self._animator, self.config.animIds :: any)
            else
                if char then self._joints = gatherJoints(char) end
            end
        end

        local mode = (char and (char:GetAttribute("FlightMode") :: any)) or "off"
        local enabledAttr = (char and char:GetAttribute("FlightEnabled") == true) or false
        -- Only animate during core flight phases; exclude arming so we don't pose before takeoff
        local inFlightPhase = (mode == "enabling" or mode == "flying" or mode == "landing")
        local enabled = (self.controller and self.controller.enabled) or (enabledAttr and inFlightPhase)
        if not enabled then
            -- reset and idle
            if self._tracks then stopAllTracks(self._animator) end
            if self._joints then applyProceduralPose(self._joints, "reset", self.config.smoothing or DEFAULTS.smoothing) end
            return
        end

        local keys = self.config.keys or {
            ascend = (self.controller and self.controller.config and self.controller.config.ascendKey) or DEFAULTS.keys.ascend,
            descend = (self.controller and self.controller.config and self.controller.config.descendKey) or DEFAULTS.keys.descend,
            sprint = (self.controller and self.controller.config and self.controller.config.sprintKey) or DEFAULTS.keys.sprint,
        }
        local ascendHeld = keys.ascend and UserInputService:IsKeyDown(keys.ascend)
        local descendHeld = keys.descend and UserInputService:IsKeyDown(keys.descend)
        local sprintHeld = keys.sprint and UserInputService:IsKeyDown(keys.sprint)

        local moveMag = hum.MoveDirection.Magnitude
        local moving = moveMag > 0.05

        local state: string
        if mode == "landing" then
            state = "descend"
        elseif ascendHeld then
            state = "ascend"
        elseif descendHeld and moving == false then
            -- slow fall / hover when descending but not moving horizontally
            state = "descend"
        elseif sprintHeld and moving then
            state = "sprint"
        elseif moving then
            state = "cruise"
        else
            state = "hover"
        end

        if self._tracks and next(self._tracks) ~= nil then
            playExclusive(self._tracks, state)
        else
            applyProceduralPose(self._joints, state, self.config.smoothing or DEFAULTS.smoothing)
        end

        if Debug then Debug.log("anim", "state=", state, "mode=", mode, "moving=", moving) end
    end)
end

function AnimatorMt:destroy()
    if self._conn then self._conn:Disconnect(); self._conn = nil end
    if self._tracks and self._animator then stopAllTracks(self._animator) end
    self._tracks = nil
    if self._joints then
        for _, m in pairs(self._joints) do pcall(function() m.Transform = CFrame.new() end) end
        self._joints = nil
    end
    Singletons[self.player] = nil
end

local FlightAnimator = {}

function FlightAnimator.bindTo(player: Player, controller: any?, config: Config?)
    local existing = Singletons[player]
    if existing then
        if config then existing.config = mergeConfig(config) end
        existing.controller = controller or existing.controller
        return existing
    end
    local self: InstanceType = setmetatable({
        player = player,
        controller = controller,
        config = mergeConfig(config),
        _conn = nil,
        _animator = nil,
        _tracks = nil,
        _joints = nil,
    }, AnimatorMt)

    local char, hum = getHumanoid(player)
    if hum then
        local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
        self._animator = animator
        if self.config.animIds then
            self._tracks = loadTracks(animator, self.config.animIds :: any)
        else
            self._joints = gatherJoints(char :: Model)
        end
    end

    Singletons[player] = self
    self:_bind()
    return self
end

function FlightAnimator.forLocalPlayer(controller: any?, config: Config?)
    local lp = Players.LocalPlayer
    assert(lp, "FlightAnimator.forLocalPlayer must be called from a LocalScript")
    return FlightAnimator.bindTo(lp, controller, config)
end

return FlightAnimator
