--!strict
-- Wires up the FlightController for the local player.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer

local Flight = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Movement"):WaitForChild("FlightController"))

local controller = Flight.new(Player, {
    baseSpeed = 60,
    verticalSpeed = 50,
    shootdownSpeed = 275,
})

controller:start()

-- Overlay integratability example hooks (optional)
controller.FlightChanged:Connect(function(on)
    -- print("Flight:", on)
end)

controller.AltitudeChanged:Connect(function(alt)
    -- Could update an overlay with altitude readout
    -- print("Alt:", alt)
end)

-- Press F to toggle flight (handled inside controller)

