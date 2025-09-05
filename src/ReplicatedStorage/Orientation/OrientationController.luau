-- OrientationController: Modular, idempotent orientation routing for the local player
-- Providers can register a callback that returns a facing vector (yaw) and optional pitch.
-- The highest-priority provider that returns a value each frame wins. Smoothly lerps rotation.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

export type OrientationSample = {
    faceDir: Vector3?, -- world-space direction to face (Y component ignored for yaw)
    pitch: number?, -- radians, optional
}

export type Provider = {
    id: string,
    priority: number,
    callback: (player: Player) -> OrientationSample?,
}

export type Config = {
    lerpAlpha: number?, -- 0..1 per frame
}

export type Controller = {
    player: Player,
    config: Config,
    _conn: RBXScriptConnection?,
    _providers: { [string]: Provider },
    _sorted: { Provider }?,
    _lastYaw: Vector3?,
    _lastPitch: number?,
    registerProvider: (self: Controller, id: string, priority: number, cb: (player: Player) -> OrientationSample?) -> (),
    unregisterProvider: (self: Controller, id: string) -> (),
    destroy: (self: Controller) -> (),
}

local DEFAULTS: Config = {
    lerpAlpha = 0.25,
}

local Singletons: { [Player]: Controller } = {}

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

local ControllerMt = {} :: Controller
ControllerMt.__index = ControllerMt

local function sortProviders(t: { [string]: Provider }): { Provider }
    local arr = {}
    for _, p in pairs(t) do table.insert(arr, p) end
    table.sort(arr, function(a, b) return a.priority > b.priority end)
    return arr
end

function ControllerMt:_bind()
    if self._conn then return end
    self._conn = RunService.RenderStepped:Connect(function(dt)
        local hrp: BasePart? = nil
        local hum: Humanoid? = nil
        local character = self.player.Character
        if character then
            hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
            hum = character:FindFirstChildOfClass("Humanoid")
        end
        if not hrp or not hum then return end

        if not self._sorted then
            self._sorted = sortProviders(self._providers)
        end
        local sample: OrientationSample? = nil
        for _, p in ipairs(self._sorted :: { Provider }) do
            local ok, result = pcall(function()
                return p.callback(self.player)
            end)
            if ok and result and result.faceDir and result.faceDir.Magnitude > 1e-3 then
                sample = result
                break
            end
        end
        if not sample then return end

        local face = Vector3.new(sample.faceDir.X, 0, sample.faceDir.Z)
        if face.Magnitude < 1e-3 then return end
        local pitch = sample.pitch or 0

        local target = CFrame.lookAt(hrp.Position, hrp.Position + face.Unit) * CFrame.Angles(pitch, 0, 0)
        local alpha = self.config.lerpAlpha or DEFAULTS.lerpAlpha
        hrp.CFrame = hrp.CFrame:Lerp(target, math.clamp(alpha, 0, 1))
    end)
end

function ControllerMt:registerProvider(id: string, priority: number, cb: (player: Player) -> OrientationSample?)
    self._providers[id] = {
        id = id,
        priority = priority or 0,
        callback = cb,
    }
    self._sorted = nil
    self:_bind()
end

function ControllerMt:unregisterProvider(id: string)
    self._providers[id] = nil
    self._sorted = nil
end

function ControllerMt:destroy()
    if self._conn then self._conn:Disconnect() self._conn = nil end
    self._providers = {}
    self._sorted = nil
    Singletons[self.player] = nil
end

local OrientationController = {}

function OrientationController.get(player: Player): Controller?
    return Singletons[player]
end

function OrientationController.getOrCreate(player: Player, config: Config?): Controller
    local existing = Singletons[player]
    if existing then
        if config then
            existing.config = mergeConfig(config)
        end
        return existing
    end
    local self: Controller = setmetatable({
        player = player,
        config = mergeConfig(config),
        _conn = nil,
        _providers = {},
        _sorted = nil,
        _lastYaw = nil,
        _lastPitch = 0,
    }, ControllerMt)
    Singletons[player] = self
    return self
end

function OrientationController.forLocalPlayer(config: Config?): Controller
    local lp = Players.LocalPlayer
    assert(lp, "OrientationController.forLocalPlayer must be called from a LocalScript")
    return OrientationController.getOrCreate(lp, config)
end

return OrientationController

