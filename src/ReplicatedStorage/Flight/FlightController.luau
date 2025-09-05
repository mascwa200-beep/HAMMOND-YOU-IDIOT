-- FlightController: Modular, idempotent flying for client characters
-- Usage (client):
--   local FlightController = require(ReplicatedStorage.Shared.Flight.FlightController)
--   local controller = FlightController.getOrCreate(Players.LocalPlayer)
--   controller:enable() -- or :toggle()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local OrientationController = require(Shared:WaitForChild("Orientation"):WaitForChild("OrientationController"))
local Grounding = require(Shared:WaitForChild("Grounding"):WaitForChild("Grounding"))
local Debug do
    local ok, mod = pcall(function()
        return require(Shared:WaitForChild("Debug"):WaitForChild("DebugFlags"))
    end)
    if ok then Debug = mod end
end

export type Config = {
    speed: number?, -- studs/second
    sprintMultiplier: number?,
    ascendKey: Enum.KeyCode?,
    descendKey: Enum.KeyCode?,
    descendAltKey: Enum.KeyCode?,
    sprintKey: Enum.KeyCode?,
    ascendSpeed: number?, -- vertical up speed (studs/sec)
    descendSpeed: number?, -- vertical down speed (studs/sec)
    transitionTime: number?, -- seconds to gently lift on enable
    liftAmount: number?, -- studs to rise during transition
    alignTo: string?, -- "movement" | "camera" | "none"
    suppressFallingAnim: boolean?, -- disable default Animate while flying
    landingTime: number?, -- seconds of horizontal decel and controlled drop (deprecated by landingMode)
    landingDescendSpeed: number?, -- studs/sec downward during landing
    landingMode: string?, -- "untilGround" | "timed" (default untilGround)
    landingTimeoutSec: number?, -- optional safety cap; nil disables timing
    landingHorizFriction: number?, -- decay rate for horizontal speed during landing (per second)
    landingPlane: string?, -- which plane to use for contact ("feet" default)
    landingGroundTolerance: number?, -- studs to consider contact
    landingRayLength: number?,
    landingMinDescendSpeed: number?, -- minimum downward speed near ground
    landingApproachRate: number?, -- how quickly speed scales with distance (studs/sec per stud)
    tiltMaxDeg: number?, -- visual pitch when moving
    tiltSmoothing: number?, -- 0..1 lerp factor per frame
    animations: { idle: string?, move: string? }?,
    pose: string?, -- "superman" | "none"
    poseSmoothing: number?, -- 0..1 transform lerp
    inputSpace: string?, -- "camera" | "world"
    disableDefaultControls: boolean?,
    moveThreshold: number?,
    activateAltitude: number?,
}

export type Controller = {
    player: Player,
    enabled: boolean,
    config: Config,
    _conn: RBXScriptConnection?,
    _charConn: RBXScriptConnection?,
    _origAutoRotate: boolean?,
    _lastCharacter: Model?,
    _controls: any?,
    _controlsDisabled: boolean?,
    _transitionMode: string?, -- "off" | "enabling"
    _transitionStart: number?,
    _antiGrav: VectorForce?,
    _antiGravAtt: Attachment?,
    _animateScript: Instance?,
    _lastFacing: Vector3?,
    _pitch: number?,
    _enableFromStandstill: boolean?,
    _enableStartHeight: number?,
    _joints: { [string]: Motor6D }?,
    _animator: Animator?,
    _idleTrack: AnimationTrack?,
    _moveTrack: AnimationTrack?,
    _orient: any?,
    _keyState: { [Enum.KeyCode]: boolean }?,
    _inputConnBegan: RBXScriptConnection?,
    _inputConnEnded: RBXScriptConnection?,
    _actionBound: boolean?,
    enable: (self: Controller) -> (),
    disable: (self: Controller) -> (),
    toggle: (self: Controller) -> (),
    destroy: (self: Controller) -> (),
}

local DEFAULTS: Config = {
    speed = 70,
    sprintMultiplier = 1.8,
    ascendKey = Enum.KeyCode.Space,
    descendKey = Enum.KeyCode.LeftControl,
    descendAltKey = nil,
    sprintKey = Enum.KeyCode.LeftShift,
    transitionTime = 1.0,
    liftAmount = 3.0,
    alignTo = "movement",
    suppressFallingAnim = true,
    landingTime = 0.9,
    landingDescendSpeed = 18,
    landingMode = "untilGround",
    landingTimeoutSec = nil,
    landingHorizFriction = 5, -- higher = quicker slow
    landingPlane = "feet",
    landingGroundTolerance = 0.15,
    landingRayLength = 25,
    landingMinDescendSpeed = 6,
    landingApproachRate = 8,
    tiltMaxDeg = 18,
    tiltSmoothing = 0.2,
    animations = nil,
    pose = "superman",
    poseSmoothing = 0.25,
    inputSpace = "camera",
    disableDefaultControls = false,
    moveThreshold = 0.15,
    activateAltitude = 1.5,
}

local Controllers: { [Player]: Controller } = {}

local function mergeConfig(partial: Config?): Config
    local cfg: Config = {}
    for k, v in pairs(DEFAULTS) do
        (cfg :: any)[k] = v
    end
    if partial then
        for k, v in pairs(partial) do
            (cfg :: any)[k] = v
        end
    end
    return cfg
end

local function getCharacterParts(character: Model)
    local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hrp then
        hrp = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
    end
    if not hum then
        hum = character:WaitForChild("Humanoid", 5) :: Humanoid?
    end
    return hrp, hum
end

local function gatherJoints(character: Model)
    local joints: { [string]: Motor6D } = {}
    local names = {
        "RightShoulder","LeftShoulder","RightHip","LeftHip","Neck","RootJoint",
    }
    for _, n in ipairs(names) do
        local inst = character:FindFirstChild(n, true)
        if inst and inst:IsA("Motor6D") then
            joints[n] = inst
        end
    end
    return joints
end

local ControllerMt = {} :: Controller
ControllerMt.__index = ControllerMt

-- Robust key tracking so modifiers (e.g., LeftControl) don't suppress forward keys
function ControllerMt:_ensureInputBinding()
    if self._inputConnBegan and self._inputConnEnded then return end
    self._keyState = self._keyState or {}
    self._inputConnBegan = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            self._keyState[input.KeyCode] = true
            if Debug then
                local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
                Debug.log("flight", "InputBegan", input.KeyCode.Name, "gp=", gameProcessed, "ctrl=", ctrl)
            end
        end
    end)
    self._inputConnEnded = UserInputService.InputEnded:Connect(function(input: InputObject, gameProcessed: boolean)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            self._keyState[input.KeyCode] = false
            if Debug then
                local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
                Debug.log("flight", "InputEnded", input.KeyCode.Name, "gp=", gameProcessed, "ctrl=", ctrl)
            end
        end
    end)
end

function ControllerMt:_isDown(code: Enum.KeyCode?): boolean
    if not code then return false end
    if self._keyState and self._keyState[code] ~= nil then
        return self._keyState[code] == true
    end
    return UserInputService:IsKeyDown(code)
end

local ACTION_MOVE = "Flight_MoveAction"

function ControllerMt:_bindMoveActions()
    if self._actionBound then return end
    self._keyState = self._keyState or {}
    local cfg = self.config
    local keys = {
        Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
        Enum.KeyCode.Up, Enum.KeyCode.Left, Enum.KeyCode.Down, Enum.KeyCode.Right,
    }
    local function push(k: Enum.KeyCode?)
        if k then table.insert(keys, k) end
    end
    push(cfg.ascendKey)
    push(cfg.descendKey)
    push(cfg.sprintKey)
    push(cfg.descendAltKey)

    local function onMove(actionName: string, inputState: Enum.UserInputState, inputObj: InputObject)
        if inputObj.UserInputType == Enum.UserInputType.Keyboard then
            local kc = inputObj.KeyCode
            if inputState == Enum.UserInputState.Begin then
                self._keyState[kc] = true
            elseif inputState == Enum.UserInputState.End then
                self._keyState[kc] = false
            end
            if Debug then
                local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
                Debug.log("flight", "CAS:", actionName, inputState.Name, kc.Name, "ctrl=", ctrl)
            end
        end
        return Enum.ContextActionResult.Pass
    end

    pcall(function()
        if (ContextActionService :: any).BindActionAtPriority then
            (ContextActionService :: any):BindActionAtPriority(ACTION_MOVE, onMove, false, Enum.ContextActionPriority.High.Value, table.unpack(keys))
        else
            ContextActionService:BindAction(ACTION_MOVE, onMove, false, table.unpack(keys))
        end
        self._actionBound = true
    end)
end

function ControllerMt:_unbindMoveActions()
    if not self._actionBound then return end
    pcall(function()
        ContextActionService:UnbindAction(ACTION_MOVE)
    end)
    self._actionBound = false
end

function ControllerMt:_bind()
    if self._conn then return end

    self._conn = RunService.RenderStepped:Connect(function(dt)
        -- Run while enabled or during transitions (arming/enabling/landing)
        if not self.enabled and self._transitionMode ~= "enabling" and self._transitionMode ~= "landing" and self._transitionMode ~= "arming" then return end
        local character = self.player.Character
        if not character then return end

        local hrp, humanoid = getCharacterParts(character)
        if not hrp or not humanoid then return end

        -- Disable autorotate only during active flight (not during arming/landing)
        local shouldDisableAR = self.enabled or self._transitionMode == "enabling"
        if shouldDisableAR then
            if self._origAutoRotate == nil then
                self._origAutoRotate = humanoid.AutoRotate
            end
            humanoid.AutoRotate = false
        end

        local cam = workspace.CurrentCamera
        if not cam then return end

        -- Input state
        local cfg = self.config
        local forward, right
        if (cfg.inputSpace or DEFAULTS.inputSpace) == "world" then
            forward = Vector3.new(0, 0, -1)
            right = Vector3.new(1, 0, 0)
        else
            forward = cam.CFrame.LookVector
            right = cam.CFrame.RightVector
        end

        local move = Vector3.zero
        local function add(v)
            move += v
        end
        if self:_isDown(Enum.KeyCode.W) or self:_isDown(Enum.KeyCode.Up) then
            add(Vector3.new(forward.X, 0, forward.Z))
        end
        if self:_isDown(Enum.KeyCode.S) or self:_isDown(Enum.KeyCode.Down) then
            add(-Vector3.new(forward.X, 0, forward.Z))
        end
        if self:_isDown(Enum.KeyCode.A) or self:_isDown(Enum.KeyCode.Left) then
            add(-Vector3.new(right.X, 0, right.Z))
        end
        if self:_isDown(Enum.KeyCode.D) or self:_isDown(Enum.KeyCode.Right) then
            add(Vector3.new(right.X, 0, right.Z))
        end

        local vertical = 0
        if self.enabled then
            if cfg.ascendKey and self:_isDown(cfg.ascendKey) then
                vertical += 1
            end
            if cfg.descendKey and self:_isDown(cfg.descendKey) then
                vertical -= 1
            end
            if cfg.descendAltKey and self:_isDown(cfg.descendAltKey) then
                vertical -= 1
            end
        end

        -- Horizontal speed and vertical speed are computed independently so vertical is constant world Y
        local baseSpeed = cfg.speed or DEFAULTS.speed
        local horizSpeed = baseSpeed
        if self.enabled and cfg.sprintKey and self:_isDown(cfg.sprintKey) then
            horizSpeed *= cfg.sprintMultiplier or DEFAULTS.sprintMultiplier
        end
        local ascendSpeed = cfg.ascendSpeed or cfg.speed or DEFAULTS.speed
        local descendSpeed = cfg.descendSpeed or cfg.speed or DEFAULTS.speed

        local hDir = Vector3.zero
        if move.Magnitude > 0 then hDir = move.Unit end
        local hVel = hDir * horizSpeed
        local vVelY = 0
        if vertical > 0 then
            vVelY = ascendSpeed
        elseif vertical < 0 then
            vVelY = -descendSpeed
        end
        local velocity = Vector3.new(hVel.X, vVelY, hVel.Z)

        -- Gentle lift during enable transition (only when activated from standstill)
        if self._transitionMode == "enabling" and self._enableFromStandstill and vertical == 0 then
            local dur = cfg.transitionTime or DEFAULTS.transitionTime :: number
            local elapsed = os.clock() - (self._transitionStart or os.clock())
            if dur > 0 and elapsed < dur then
                local liftPerSec = (cfg.liftAmount or DEFAULTS.liftAmount :: number) / dur
                velocity += Vector3.new(0, liftPerSec, 0)
            end
            local gained = 0
            if self._enableStartHeight and hrp then
                gained = hrp.Position.Y - (self._enableStartHeight :: number)
            end
            local activateAlt = cfg.activateAltitude or DEFAULTS.activateAltitude :: number
            if elapsed >= (cfg.transitionTime or DEFAULTS.transitionTime) or (activateAlt and gained >= activateAlt) then
                self._transitionMode = "off"
                pcall(function()
                    local ch = self.player.Character
                    if ch then ch:SetAttribute("FlightMode", "flying") end
                end)
            end
        end

        -- If we're arming (started while moving), wait for altitude or ascend input to activate flight
        if self._transitionMode == "arming" then
            local activateAlt = cfg.activateAltitude or DEFAULTS.activateAltitude :: number
            local gained = 0
            if self._enableStartHeight and hrp then
                gained = hrp.Position.Y - (self._enableStartHeight :: number)
            end
            local ascendWanted = cfg.ascendKey and self:_isDown(cfg.ascendKey)
            if (activateAlt and gained >= activateAlt) or ascendWanted then
                -- Become active: set to off (active), install anti-gravity and prep anim pose
                self._transitionMode = "off"
                -- Re-run character setup to install anti-gravity now that we're active
                self:_onCharacterAdded(character)
                if Debug then Debug.log("flight", "arming->active; gained=", gained) end
            end
            -- While arming, don't override velocity or orientation; let default movement happen.
            return
        end

        -- Controlled landing transition: bleed horizontal speed, set gentle descent
        if self._transitionMode == "landing" then
            local currentVel = hrp.AssemblyLinearVelocity

            -- Distance-aware vertical descent: faster high up, slows as feet near ground
            local plane = (cfg.landingPlane or DEFAULTS.landingPlane) :: string
            local tolerance = cfg.landingGroundTolerance or DEFAULTS.landingGroundTolerance :: number
            local rayLen = cfg.landingRayLength or DEFAULTS.landingRayLength :: number

            local dist = nil
            local okD, resD = pcall(function()
                return Grounding.distanceToPlane(character, plane :: any, rayLen, nil)
            end)
            if okD then dist = resD end

            local baseDown = (cfg.landingDescendSpeed or DEFAULTS.landingDescendSpeed :: number)
            local minDown = (cfg.landingMinDescendSpeed or DEFAULTS.landingMinDescendSpeed :: number)
            local rate = (cfg.landingApproachRate or DEFAULTS.landingApproachRate :: number)
            local descendSpeed
            if typeof(dist) == "number" then
                descendSpeed = math.clamp(dist * rate, minDown, baseDown)
            else
                -- Unknown distance (too high for ray), use base speed
                descendSpeed = baseDown
            end
            local descend = -descendSpeed
            -- Only drive vertical speed; preserve current horizontal so the player can move.
            -- Keep anti-gravity until contact so descent is controlled.
            velocity = Vector3.new(currentVel.X, descend, currentVel.Z)

            -- Complete only when the chosen plane actually contacts ground
            local contact = false
            local ok, res = pcall(function()
                local hit, _ = Grounding.isPlaneContact(character, plane :: any, tolerance, rayLen, nil)
                return hit
            end)
            if ok and res then
                self._transitionMode = "off"
                self:_finalizeDisable()
                if Debug then Debug.log("flight", "landing complete (contact)") end
                return
            end
        end

        -- Apply velocity directly to the assembly (simple, idempotent)
        -- With anti-gravity active, Y stays neutral unless vertical input is given
        hrp.AssemblyLinearVelocity = Vector3.new(velocity.X, velocity.Y, velocity.Z)

        if Debug then
            local w = self:_isDown(Enum.KeyCode.W) or self:_isDown(Enum.KeyCode.Up)
            local ctrl = self:_isDown(self.config.descendKey or DEFAULTS.descendKey)
            Debug.log("flight", "keys: W=", w, " CTRL=", ctrl, " move=", move, " vertical=", vertical, " vel=", velocity)
        end

        -- Update last facing from movement; actual yaw is applied by OrientationController provider
        local flatMove = Vector3.new(move.X, 0, move.Z)
        if flatMove.Magnitude > 1e-3 then
            self._lastFacing = flatMove.Unit
        end
        local targetPitch = 0
        do
            local tiltMax = (cfg.tiltMaxDeg or DEFAULTS.tiltMaxDeg :: number) * math.pi/180
            local hMag = math.min(1, flatMove.Magnitude)
            local vMag = vertical
            -- Forward movement -> slight nose down; ascend -> nose up; descend -> nose down more
            targetPitch = -hMag * (tiltMax * 0.6) + vMag * (tiltMax)
            local smooth = cfg.tiltSmoothing or DEFAULTS.tiltSmoothing :: number
            self._pitch = (self._pitch or 0) + (targetPitch - (self._pitch or 0)) * math.clamp(smooth, 0, 1)
        end

        -- Optional custom animation driving: switch between idle/move while flying
        if self._animator and (self._idleTrack or self._moveTrack) then
            local moving = (Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 0.5)
            local verticalMoving = math.abs(velocity.Y) > 0.5
            local wantMove = (self.enabled and (moving or verticalMoving)) or self._transitionMode == "enabling"
            if wantMove then
                if self._idleTrack and self._idleTrack.IsPlaying then
                    pcall(function() self._idleTrack:Stop(0.2) end)
                end
                if self._moveTrack and not self._moveTrack.IsPlaying then
                    pcall(function() self._moveTrack:Play(0.2) end)
                end
            else
                if self._moveTrack and self._moveTrack.IsPlaying then
                    pcall(function() self._moveTrack:Stop(0.2) end)
                end
                if self._idleTrack and not self._idleTrack.IsPlaying then
                    pcall(function() self._idleTrack:Play(0.2) end)
                end
            end
        end

        -- Generic pose (Superman-style) without assets
        if (cfg.pose or DEFAULTS.pose) == "superman" and self._joints then
            local smooth = cfg.poseSmoothing or DEFAULTS.poseSmoothing :: number
            local function lerpMotor(m: Motor6D?, target: CFrame)
                if not m then return end
                m.Transform = m.Transform:Lerp(target, math.clamp(smooth, 0, 1))
            end
            -- Arms forward, slight leg extension; add subtle extra with speed
            local hMag = math.min(1, Vector3.new(move.X, 0, move.Z).Magnitude)
            local armPitch = -0.9 - 0.2 * hMag + 0.3 * (vertical)
            local legPitch = 0.2 + 0.2 * hMag - 0.2 * (vertical)
            lerpMotor(self._joints.RightShoulder, CFrame.Angles(armPitch, 0, 0))
            lerpMotor(self._joints.LeftShoulder, CFrame.Angles(armPitch, 0, 0))
            lerpMotor(self._joints.RightHip, CFrame.Angles(legPitch, 0, 0))
            lerpMotor(self._joints.LeftHip, CFrame.Angles(legPitch, 0, 0))
            lerpMotor(self._joints.Neck, CFrame.Angles(0.05 - 0.1 * hMag, 0, 0))
        end
    end)
end

function ControllerMt:_unbind()
    if self._conn then
        self._conn:Disconnect()
        self._conn = nil
    end
end

function ControllerMt:_onCharacterAdded(character: Model)
    self._lastCharacter = character
    if not self.enabled then return end
    -- Ensure humanoid autorotate is disabled while enabled
    local _, hum = getCharacterParts(character)
    if hum then
        if self._transitionMode ~= "arming" then
            self._origAutoRotate = hum.AutoRotate
            hum.AutoRotate = false
        end
        -- Optionally suppress default falling animation by disabling Animate LocalScript (only when not arming)
        if self._transitionMode ~= "arming" and (self.config.suppressFallingAnim or DEFAULTS.suppressFallingAnim) and self.player == Players.LocalPlayer then
            local animate = character:FindFirstChild("Animate")
            if animate and animate:IsA("LocalScript") then
                self._animateScript = animate
                pcall(function() (animate :: any).Disabled = true end)
            end
        end
        -- Stop any currently playing tracks so run/walk does not persist
        local animator = hum:FindFirstChildOfClass("Animator")
        if animator then
            pcall(function()
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    track:Stop(0.2)
                end
            end)
        end
        -- Prepare optional custom animations (only when not arming)
        if self._transitionMode ~= "arming" then
            self._animator = (hum:FindFirstChildOfClass("Animator")) or Instance.new("Animator", hum)
            local animCfg = self.config.animations
            if animCfg then
                local function loadTrack(id: string?): AnimationTrack?
                    if not id or id == "" then return nil end
                    local anim = Instance.new("Animation")
                    if not tostring(id):find("rbxassetid") then
                        anim.AnimationId = "rbxassetid://" .. tostring(id)
                    else
                        anim.AnimationId = tostring(id)
                    end
                    local ok, track = pcall(function()
                        return self._animator:LoadAnimation(anim)
                    end)
                    if ok and track then
                        track.Looped = true
                        return track
                    end
                    return nil
                end
                self._idleTrack = loadTrack(animCfg.idle)
                self._moveTrack = loadTrack(animCfg.move)
                if self._idleTrack then
                    pcall(function() self._idleTrack:Play(0.2) end)
                end
            end
        end
    end

    -- Install anti-gravity VectorForce to fully cancel gravity and hover (skip during arming)
    local hrp, _ = getCharacterParts(character)
    if hrp and not self._antiGrav and self._transitionMode ~= "arming" then
        local att = Instance.new("Attachment")
        att.Name = "FlightAttachment"
        att.Parent = hrp

        local vf = Instance.new("VectorForce")
        vf.Name = "FlightAntiGravity"
        vf.Attachment0 = att
        vf.ApplyAtCenterOfMass = true
        vf.RelativeTo = Enum.ActuatorRelativeTo.World
        vf.Parent = hrp

        self._antiGrav = vf
        self._antiGravAtt = att

        -- Update force each frame in case mass changes (backpack, accessories)
        task.defer(function()
            while (self.enabled or self._transitionMode == "landing" or self._transitionMode == "enabling")
                and self.player.Character == character and self._antiGrav do
                vf.Force = Vector3.new(0, (hrp.AssemblyMass) * workspace.Gravity, 0)
                RunService.Heartbeat:Wait()
            end
        end)
    end

    -- Gather joints for procedural pose
    self._joints = gatherJoints(character)
end

function ControllerMt:enable()
    if self.enabled then return end
    -- Ensure input tracking is bound so modifier keys don't suppress movement combos
    self:_ensureInputBinding()
    self:_bindMoveActions()
    self.enabled = true
    self._transitionMode = "enabling"
    self._transitionStart = os.clock()
    -- Attempt to disable default player controls (client only)
    if self.player == Players.LocalPlayer and (self.config.disableDefaultControls or DEFAULTS.disableDefaultControls) then
        local playerScripts = self.player:FindFirstChild("PlayerScripts")
        if playerScripts then
            local playerModule = playerScripts:FindFirstChild("PlayerModule")
            if playerModule then
                pcall(function()
                    local Controls = require(playerModule):GetControls()
                    self._controls = Controls
                    Controls:Disable()
                    self._controlsDisabled = true
                end)
            end
        end
    end
    -- Decide if we start from standstill (hover) or moving (no hover)
    do
        local character = self.player.Character
        local hrp, hum = if character then getCharacterParts(character) else nil, nil
        local moveMag = 0
        if hum then
            moveMag = hum.MoveDirection.Magnitude
        end
        local threshold = self.config.moveThreshold or DEFAULTS.moveThreshold :: number
        self._enableFromStandstill = (moveMag < threshold)
        if hrp then
            self._enableStartHeight = hrp.Position.Y
        end
        if not self._enableFromStandstill then
            -- Start in arming mode: keep normal movement until altitude or ascend input
            self._transitionMode = "arming"
        end
    end
    if self.player.Character then
        self:_onCharacterAdded(self.player.Character)
    end
    -- Publish attributes for modular consumers (e.g., animators)
    pcall(function()
        local ch = self.player.Character
        if ch then
            ch:SetAttribute("FlightEnabled", true)
            ch:SetAttribute("FlightMode", self._enableFromStandstill and "enabling" or (self._transitionMode == "arming" and "arming" or "flying"))
        end
    end)
    if not self._charConn then
        self._charConn = self.player.CharacterAdded:Connect(function(char)
            self:_onCharacterAdded(char)
        end)
    end
    -- Register a flight orientation provider with high priority
    if self.player == Players.LocalPlayer then
        self._orient = OrientationController.forLocalPlayer({})
        self._orient:registerProvider("flight", 100, function(_player)
            -- Only drive orientation during active flight (not arming or landing)
            if not self.enabled or self._transitionMode == "arming" or self._transitionMode == "landing" then
                return nil
            end
            local character = _player.Character
            if not character then return nil end
            local hrp = character:FindFirstChild("HumanoidRootPart")
            local hum = character:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum then return nil end
            local moveDir = hum.MoveDirection
            local face: Vector3? = nil
            if moveDir.Magnitude > 1e-3 then
                face = Vector3.new(moveDir.X, 0, moveDir.Z).Unit
                self._lastFacing = face
            else
                face = self._lastFacing
            end
            if not face then return nil end
            return { faceDir = face, pitch = self._pitch or 0 }
        end)
    end
    self:_bind()
end

function ControllerMt:_finalizeDisable()
    -- Called after landing completes
    -- Restore controls if we disabled them
    if self._controls and self._controlsDisabled then
        pcall(function()
            self._controls:Enable()
        end)
        self._controlsDisabled = false
    end
    -- Re-enable default animations if we disabled them
    if self._animateScript then
        pcall(function()
            (self._animateScript :: any).Disabled = false
        end)
        self._animateScript = nil
    end
    if self._idleTrack then pcall(function() self._idleTrack:Stop(0.1) end) self._idleTrack = nil end
    if self._moveTrack then pcall(function() self._moveTrack:Stop(0.1) end) self._moveTrack = nil end
    self._animator = nil
    local character = self.player.Character or self._lastCharacter
    if character then
        local hrp, hum = getCharacterParts(character)
        if hrp then
            -- Let the engine retake control smoothly
            hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
        end
        if hum then
            if self._origAutoRotate ~= nil then
                hum.AutoRotate = self._origAutoRotate
            else
                hum.AutoRotate = true
            end
            -- Return to GettingUp/Idle if possible
            pcall(function()
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end)
        end
        -- Remove anti-gravity components
        if self._antiGrav then
            self._antiGrav:Destroy()
            self._antiGrav = nil
        end
        if self._antiGravAtt then
            self._antiGravAtt:Destroy()
            self._antiGravAtt = nil
        end
        -- Reset any procedural pose transforms
        if self._joints then
            for _, m in pairs(self._joints) do
                pcall(function() m.Transform = CFrame.new() end)
            end
            self._joints = nil
        end
    end
    -- Reset published attributes
    pcall(function()
        local ch = self.player.Character
        if ch then
            ch:SetAttribute("FlightEnabled", false)
            ch:SetAttribute("FlightMode", "off")
        end
    end)
    -- Unregister orientation provider
    if self._orient then
        pcall(function() self._orient:unregisterProvider("flight") end)
        self._orient = nil
    end
    self:_unbindMoveActions()
    self:_unbind()
end

function ControllerMt:disable()
    if not self.enabled then return end
    self.enabled = false
    -- Start landing; keep connection alive for transition
    self._transitionMode = "landing"
    self._transitionStart = os.clock()
    pcall(function()
        local ch = self.player.Character
        if ch then ch:SetAttribute("FlightMode", "landing") end
    end)
    -- Immediately restore player controls so horizontal movement works during landing
    if self._controls and self._controlsDisabled then
        pcall(function()
            self._controls:Enable()
        end)
        self._controlsDisabled = false
    end
    -- Immediately restore player orientation/controls to avoid blocking rotation
    local character = self.player.Character or self._lastCharacter
    if character then
        local _, hum = getCharacterParts(character)
        if hum then
            pcall(function()
                hum.AutoRotate = true
            end)
        end
    end
    if self._orient then
        pcall(function() self._orient:unregisterProvider("flight") end)
        self._orient = nil
    end
end

function ControllerMt:toggle()
    if self.enabled then
        self:disable()
    else
        self:enable()
    end
end

function ControllerMt:destroy()
    self:disable()
    if self._charConn then
        self._charConn:Disconnect()
        self._charConn = nil
    end
    if self._inputConnBegan then self._inputConnBegan:Disconnect(); self._inputConnBegan = nil end
    if self._inputConnEnded then self._inputConnEnded:Disconnect(); self._inputConnEnded = nil end
    self:_unbindMoveActions()
    Controllers[self.player] = nil
end

local FlightController = {}

function FlightController.get(player: Player): Controller?
    return Controllers[player]
end

function FlightController.getOrCreate(player: Player, config: Config?): Controller
    local existing = Controllers[player]
    if existing then
        -- Update config if provided
        if config then
            existing.config = mergeConfig(config)
        end
        return existing
    end

    local self: Controller = setmetatable({
        player = player,
        enabled = false,
        config = mergeConfig(config),
        _conn = nil,
        _charConn = nil,
        _origAutoRotate = nil,
        _lastCharacter = nil,
        _controls = nil,
        _controlsDisabled = false,
        _transitionMode = "off",
        _transitionStart = nil,
        _antiGrav = nil,
        _antiGravAtt = nil,
        _animateScript = nil,
        _lastFacing = nil,
        _pitch = 0,
        _animator = nil,
        _idleTrack = nil,
        _moveTrack = nil,
        _orient = nil,
        _enableFromStandstill = nil,
        _enableStartHeight = nil,
        _keyState = nil,
        _inputConnBegan = nil,
        _inputConnEnded = nil,
        _actionBound = false,
    }, ControllerMt)

    Controllers[player] = self
    return self
end

-- Convenience for the local player (client only)
function FlightController.forLocalPlayer(config: Config?): Controller
    local lp = Players.LocalPlayer
    assert(lp, "FlightController.forLocalPlayer must be called from a LocalScript")
    return FlightController.getOrCreate(lp, config)
end

return FlightController
