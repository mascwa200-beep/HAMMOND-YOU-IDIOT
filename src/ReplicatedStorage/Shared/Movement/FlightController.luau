--!strict

-- FlightController: Self-contained modular flight system for a local player.
-- Features
--  - Toggle with F: enable/disable flight
--  - If toggled off mid-air, slam to ground at high speed and stop on contact
--  - Movement: WASD (camera-relative), Space (ascend), LeftCtrl (descend)
--  - Sprint: hold LeftShift; adjust sprint speed with E (increase) / Q (decrease)
--      * Tap: small increments; Hold: fast continuous change
--  - Disables fall animation while flying and during slam; restored after landing
--  - Non-intrusive when idle/off; idempotent setup; overlay integratability via signals

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LOCAL_PLAYER = Players.LocalPlayer

-- Optional Grounding module for ground-aware altitude checks
local Grounding: any = nil
do
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Grounding"):WaitForChild("Grounding"))
    end)
    if ok then
        Grounding = mod
    end
end

export type Config = {
    baseSpeed: number?, -- studs/sec horizontal
    verticalSpeed: number?, -- studs/sec vertical
    sprintBase: number?, -- starting sprint factor
    sprintMin: number?,
    sprintMax: number?,
    sprintStep: number?, -- tap increment amount
    sprintHoldRate: number?, -- factor change per second while holding E/Q
    groundCheckMaxDist: number?,
    groundStopThreshold: number?, -- altitude to consider landed (studs)
    shootdownSpeed: number?, -- studs/sec downward during slam
}

export type State = {
    enabled: boolean,
    slamming: boolean,
    sprinting: boolean,
    sprintFactor: number,
    altitude: number?,
    ascending: boolean,
    descending: boolean,
    move: Vector3,
}

export type FlightController = {
    start: (self: FlightController) -> (),
    stop: (self: FlightController) -> (),
    destroy: (self: FlightController) -> (),
    toggleFlight: (self: FlightController) -> (),
    setEnabled: (self: FlightController, on: boolean) -> (),
    getState: (self: FlightController) -> State,
    configure: (self: FlightController, cfg: Config) -> (),
    -- Signals (RBXScriptSignal-like via BindableEvent)
    FlightChanged: RBXScriptSignal,
    SprintChanged: RBXScriptSignal,
    SpeedChanged: RBXScriptSignal,
    AltitudeChanged: RBXScriptSignal,
}

local DEFAULTS: Config = {
    baseSpeed = 60,
    verticalSpeed = 50,
    sprintBase = 1.5,
    sprintMin = 0.5,
    sprintMax = 5,
    sprintStep = 0.1,
    sprintHoldRate = 0.75,
    groundCheckMaxDist = 1000,
    groundStopThreshold = 2.0,
    shootdownSpeed = 250,
}

local function makeSignal(): (RBXScriptSignal, (any) -> (), () -> ())
    local be = Instance.new("BindableEvent")
    local fire = function(...: any)
        be:Fire(...)
    end
    local destroy = function()
        be:Destroy()
    end
    return (be :: any).Event, fire, destroy
end

local function unitOrZero(v: Vector3): Vector3
    local m = v.Magnitude
    if m > 1e-6 then
        return v / m
    end
    return Vector3.zero
end

local function projectOnPlane(v: Vector3, n: Vector3): Vector3
    return v - n * v:Dot(n)
end

local FlightController = {}
FlightController.__index = FlightController

local function getHumanoidAndRoot(char: Model): (Humanoid?, BasePart?)
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    return hum, root :: BasePart?
end

local function charAlive(char: Model?): boolean
    if not char then
        return false
    end
    local hum, root = getHumanoidAndRoot(char)
    return hum ~= nil and root ~= nil and hum.Health > 0
end

local function new(player: Player?, config: Config?): FlightController
    player = player or LOCAL_PLAYER
    assert(player ~= nil, "FlightController requires a Player")

    local self: any = setmetatable({}, FlightController)

    self.player = player
    self.config = table.clone(DEFAULTS)
    if config then
        for k, v in config do
            (self.config :: any)[k] = v
        end
    end

    self.state = {
        enabled = false,
        slamming = false,
        sprinting = false,
        sprintFactor = self.config.sprintBase,
        altitude = nil,
        ascending = false,
        descending = false,
        move = Vector3.zero,
    } :: State

    self._connections = {} :: { RBXScriptConnection }
    self._keysDown = {} :: { [Enum.KeyCode]: boolean }
    self._adjustDir = 0 -- -1 for Q, +1 for E, 0 none
    self._adjustStartTime = 0
    self._adjustActive = false

    -- Previous humanoid state to restore
    self._prev = {
        freefallEnabled = true,
        autoRotate = true,
    }

    -- Signals
    self.FlightChanged, self._flightFire, self._flightDestroy = makeSignal()
    self.SprintChanged, self._sprintFire, self._sprintDestroy = makeSignal()
    self.SpeedChanged, self._speedFire, self._speedDestroy = makeSignal()
    self.AltitudeChanged, self._altFire, self._altDestroy = makeSignal()

    return self :: FlightController
end

function FlightController:configure(cfg: Config)
    for k, v in cfg do
        (self.config :: any)[k] = v
    end
end

local function getAltitude(self: FlightController, root: BasePart): number?
    if Grounding and type(Grounding.getGroundDistance) == "function" then
        local d = Grounding.getGroundDistance(root.Position, self.config.groundCheckMaxDist)
        return d
    end
    -- Fallback raycast straight down ignoring character
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = { self.player.Character }
    local result = Workspace:Raycast(root.Position, -Vector3.yAxis * self.config.groundCheckMaxDist, rp)
    if result then
        return (root.Position - result.Position).Magnitude
    end
    return nil
end

local function setFallAnimEnabled(hum: Humanoid, enabled: boolean)
    -- Freefall drives Roblox fall animation; disabling prevents it
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, enabled)
    end)
end

local function saveHumanoidState(self: FlightController, hum: Humanoid)
    self._prev.freefallEnabled = hum:GetStateEnabled(Enum.HumanoidStateType.Freefall)
    self._prev.autoRotate = hum.AutoRotate
end

local function restoreHumanoidState(self: FlightController, hum: Humanoid)
    setFallAnimEnabled(hum, self._prev.freefallEnabled)
    hum.AutoRotate = self._prev.autoRotate
end

local function enableFlight(self: FlightController)
    local char = self.player.Character or self.player.CharacterAdded:Wait()
    if not charAlive(char) then
        return
    end
    local hum, root = getHumanoidAndRoot(char)
    if not hum or not root then
        return
    end

    saveHumanoidState(self, hum)
    setFallAnimEnabled(hum, false)
    hum.AutoRotate = false
    hum:ChangeState(Enum.HumanoidStateType.Physics)

    self.state.enabled = true
    self._flightFire(true)

    -- Movement step
    table.insert(
        self._connections,
        RunService.RenderStepped:Connect(function()
            if not charAlive(char) then
                return
            end
            local camera = Workspace.CurrentCamera
            if not camera then
                return
            end

            -- Update altitude periodically (not necessarily every frame, but fine for simplicity)
            local alt = getAltitude(self, root)
            self.state.altitude = alt
            self._altFire(alt)

            -- Movement vector from inputs
            local look = camera.CFrame.LookVector
            local right = camera.CFrame.RightVector
            local forwardPlanar = unitOrZero(projectOnPlane(look, Vector3.yAxis))
            local rightPlanar = unitOrZero(projectOnPlane(right, Vector3.yAxis))

            local moveX = 0
            local moveZ = 0
            if self._keysDown[Enum.KeyCode.W] then
                moveZ += 1
            end
            if self._keysDown[Enum.KeyCode.S] then
                moveZ -= 1
            end
            if self._keysDown[Enum.KeyCode.D] then
                moveX += 1
            end
            if self._keysDown[Enum.KeyCode.A] then
                moveX -= 1
            end
            local horizontal = unitOrZero(forwardPlanar * moveZ + rightPlanar * moveX)

            self.state.ascending = self._keysDown[Enum.KeyCode.Space] == true
            self.state.descending = (
                self._keysDown[Enum.KeyCode.LeftControl] or self._keysDown[Enum.KeyCode.RightControl]
            ) == true

            local vSpeed = self.config.verticalSpeed
            local y = 0
            if self.state.ascending then
                y = y + vSpeed
            end
            if self.state.descending then
                y = y - vSpeed
            end

            local sFactor = if self.state.sprinting then self.state.sprintFactor else 1
            local speed = self.config.baseSpeed * sFactor
            self._speedFire(speed, sFactor)

            local vel = horizontal * speed + Vector3.new(0, y, 0)
            root.AssemblyLinearVelocity = vel

            self.state.move = vel
        end)
    )
end

local function landedNow(self: FlightController, hum: Humanoid, root: BasePart): boolean
    if hum.FloorMaterial ~= Enum.Material.Air then
        return true
    end
    local alt = getAltitude(self, root)
    if alt and alt <= self.config.groundStopThreshold then
        return true
    end
    return false
end

local function slamToGround(self: FlightController)
    local char = self.player.Character
    if not charAlive(char) then
        return
    end
    local hum, root = getHumanoidAndRoot(char)
    if not hum or not root then
        return
    end

    -- Keep fall animation disabled during slam
    setFallAnimEnabled(hum, false)
    hum.AutoRotate = false
    hum:ChangeState(Enum.HumanoidStateType.Physics)

    self.state.slamming = true

    -- Stop normal movement loop while slamming
    for _, conn in self._connections do
        conn:Disconnect()
    end
    table.clear(self._connections)

    local slamConn
    slamConn = RunService.Heartbeat:Connect(function()
        if not charAlive(char) then
            return
        end
        root.AssemblyLinearVelocity = Vector3.new(0, -self.config.shootdownSpeed, 0)
        if landedNow(self, hum, root) then
            -- Hard stop
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero

            self.state.enabled = false
            self.state.slamming = false
            self._flightFire(false)

            restoreHumanoidState(self, hum)

            slamConn:Disconnect()
        end
    end)
end

local function disableFlight(self: FlightController)
    local char = self.player.Character
    if not charAlive(char) then
        self.state.enabled = false
        self._flightFire(false)
        return
    end
    local hum, root = getHumanoidAndRoot(char)
    if not hum or not root then
        self.state.enabled = false
        self._flightFire(false)
        return
    end

    -- If sufficiently above ground, slam to ground
    local alt = getAltitude(self, root)
    if alt and alt > self.config.groundStopThreshold then
        slamToGround(self)
        return
    end

    -- Otherwise, cleanly stop interfering
    for _, conn in self._connections do
        conn:Disconnect()
    end
    table.clear(self._connections)

    self.state.enabled = false
    self._flightFire(false)

    restoreHumanoidState(self, hum)
end

function FlightController:setEnabled(on: boolean)
    if on and not self.state.enabled and not self.state.slamming then
        enableFlight(self)
    elseif (not on) and self.state.enabled then
        disableFlight(self)
    end
end

function FlightController:toggleFlight()
    if self.state.slamming then
        return
    end
    self:setEnabled(not self.state.enabled)
end

local function onInputBegan(self: FlightController, input: InputObject, _gpe: boolean)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        self._keysDown[input.KeyCode] = true

        if input.KeyCode == Enum.KeyCode.F then
            self:toggleFlight()
        elseif input.KeyCode == Enum.KeyCode.LeftShift then
            if not self.state.sprinting then
                self.state.sprinting = true
                self._sprintFire(true)
            end
        elseif input.KeyCode == Enum.KeyCode.E then
            self._adjustDir = 1
            self._adjustStartTime = time()
            self._adjustActive = true
        elseif input.KeyCode == Enum.KeyCode.Q then
            self._adjustDir = -1
            self._adjustStartTime = time()
            self._adjustActive = true
        end
    end
end

local function onInputEnded(self: FlightController, input: InputObject, _gpe: boolean)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        self._keysDown[input.KeyCode] = false

        if input.KeyCode == Enum.KeyCode.LeftShift then
            if self.state.sprinting then
                self.state.sprinting = false
                self._sprintFire(false)
            end
        elseif input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Q then
            -- Tap vs hold behavior
            local held = time() - self._adjustStartTime
            local step = self.config.sprintStep
            local min = self.config.sprintMin
            local max = self.config.sprintMax
            if held < 0.25 then
                local newSprintFactor = math.clamp(self.state.sprintFactor + (self._adjustDir * step), min, max)
                if newSprintFactor ~= self.state.sprintFactor then
                    self.state.sprintFactor = newSprintFactor
                    self._speedFire(
                        self.config.baseSpeed * (self.state.sprinting and newSprintFactor or 1),
                        newSprintFactor
                    )
                end
            end
            self._adjustDir = 0
            self._adjustActive = false
        end
    end
end

local function onSteppedAdjust(self: FlightController, dt: number)
    if not self._adjustActive or self._adjustDir == 0 then
        return
    end
    -- Continuous adjustment while holding E/Q
    local rate = self.config.sprintHoldRate
    local newFactor = math.clamp(
        self.state.sprintFactor + (self._adjustDir * rate * dt),
        self.config.sprintMin,
        self.config.sprintMax
    )
    if newFactor ~= self.state.sprintFactor then
        self.state.sprintFactor = newFactor
        self._speedFire(self.config.baseSpeed * (self.state.sprinting and newFactor or 1), newFactor)
    end
end

function FlightController:start()
    -- Idempotent: avoid duplicating listeners
    self:stop()

    table.insert(
        self._connections,
        UserInputService.InputBegan:Connect(function(i, gpe)
            onInputBegan(self, i, gpe)
        end)
    )
    table.insert(
        self._connections,
        UserInputService.InputEnded:Connect(function(i, gpe)
            onInputEnded(self, i, gpe)
        end)
    )
    table.insert(
        self._connections,
        RunService.Heartbeat:Connect(function(dt)
            onSteppedAdjust(self, dt)
        end)
    )
end

function FlightController:stop()
    for _, conn in self._connections do
        conn:Disconnect()
    end
    table.clear(self._connections)
end

function FlightController:getState(): State
    return table.clone(self.state)
end

function FlightController:destroy()
    self:stop()
    -- ensure flight stopped if active
    if self.state.enabled then
        self:setEnabled(false)
    end
    self._flightDestroy()
    self._sprintDestroy()
    self._speedDestroy()
    self._altDestroy()
end

return {
    new = new,
}
