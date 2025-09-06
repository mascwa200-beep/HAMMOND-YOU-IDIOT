local Poses = {}

--[[
	Collects and returns a table of Motor6D joints from the given character model,
	mapping common joint names (e.g., Neck, Waist, Shoulders, Elbows, Hips, Knees, Ankles)
	to their corresponding Motor6D instances or nil if not found.
]]
local function collectMotors(character: Model)
	local m: { [string]: Motor6D? } = {
		Neck = nil,
		Waist = nil,
		LShoulder = nil,
		RShoulder = nil,
		LElbow = nil,
		RElbow = nil,
		LHip = nil,
		RHip = nil,
		LKnee = nil,
		RKnee = nil,
		LAnkle = nil,
		RAnkle = nil,
	}
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("Motor6D") then
			local n = inst.Name:gsub("%s+", "")
			if n == "Neck" then
				m.Neck = inst
			end
			if n == "Waist" then
				m.Waist = inst
			end
			-- Some rigs use "RootJoint" instead of "Waist"; use as fallback if "Waist" not found
			if n == "RootJoint" and not m.Waist then
				m.Waist = inst
			end
			if n == "LeftShoulder" then
				m.LShoulder = inst
			end
			if n == "RightShoulder" then
				m.RShoulder = inst
			end
			if n == "LeftElbow" then
				m.LElbow = inst
			end
			if n == "RightElbow" then
				m.RElbow = inst
			end
			if n == "LeftHip" then
				m.LHip = inst
			end
			if n == "RightHip" then
				m.RHip = inst
			end
			if n == "LeftKnee" then
				m.LKnee = inst
			end
			if n == "RightKnee" then
				m.RKnee = inst
			end
			if n == "LeftAnkle" then
				m.LAnkle = inst
			end
			if n == "RightAnkle" then
				m.RAnkle = inst
			end
		end
	end
	return m
end
local function angleCFrame(x: number?, y: number?, z: number?)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end
local function set(motor: Motor6D?, cf: CFrame, motorName: string?)
	if motor then
		motor.Transform = cf
	else
		if motorName then
			warn("[Poses] Missing Motor6D: " .. motorName)
		end
	end
end

local function apply(character: Model, spec: { [string]: number? })
	local m = collectMotors(character)
	set(m.Waist, angleCFrame(spec.torsoPitch or 0, spec.torsoYaw or 0, 0), "Waist")
	set(m.Neck, angleCFrame(spec.headPitch or 0, 0, 0), "Neck")

	set(
		m.LShoulder,
		angleCFrame(spec.lShoulderPitch or 0, spec.lShoulderYaw or 0, spec.lShoulderRoll or 0),
		"LShoulder"
	)
	set(
		m.RShoulder,
		angleCFrame(spec.rShoulderPitch or 0, spec.rShoulderYaw or 0, spec.rShoulderRoll or 0),
		"RShoulder"
	)

	set(m.LElbow, angleCFrame(spec.lElbowFlex or 0, 0, 0), "LElbow")
	set(m.RElbow, angleCFrame(spec.rElbowFlex or 0, 0, 0), "RElbow")

	set(m.LHip, angleCFrame(spec.lHipPitch or 0, 0, 0), "LHip")
	set(m.RHip, angleCFrame(spec.rHipPitch or 0, 0, 0), "RHip")

	set(m.LKnee, angleCFrame(spec.lKneeFlex or 0, 0, 0), "LKnee")
	set(m.RKnee, angleCFrame(spec.rKneeFlex or 0, 0, 0), "RKnee")

	set(m.LAnkle, angleCFrame(spec.lAnklePitch or 0, 0, 0), "LAnkle")
	set(m.RAnkle, angleCFrame(spec.rAnklePitch or 0, 0, 0), "RAnkle")
end

function Poses.hover(character: Model)
	apply(character, {
		torsoPitch = 0,
		headPitch = -5,
		lShoulderRoll = 10,
		rShoulderRoll = -10,
		lShoulderPitch = 0,
		rShoulderPitch = 0,
		lElbowFlex = 18,
		rElbowFlex = 18,
		lHipPitch = 10,
		rHipPitch = 0,
		lKneeFlex = 20,
		rKneeFlex = 0,
		lAnklePitch = 0,
		rAnklePitch = 0,
	})
end

function Poses.cruise(character: Model)
	apply(character, {
		torsoPitch = 10,
		headPitch = -5,
		lShoulderRoll = 10,
		rShoulderRoll = -10,
		lShoulderPitch = 0,
		rShoulderPitch = 0,
		lElbowFlex = 15,
		rElbowFlex = 15,
		lHipPitch = 10,
		rHipPitch = 0,
		lKneeFlex = 20,
		rKneeFlex = 0,
		lAnklePitch = 0,
		rAnklePitch = 0,
	})
end

function Poses.sprint(character: Model)
	apply(character, {
		torsoPitch = 5,
		headPitch = -2,
		rShoulderPitch = 75,
		rShoulderYaw = 0,
		rShoulderRoll = 0,
		lShoulderPitch = -20,
		lShoulderYaw = 10,
		lShoulderRoll = 0,
		rElbowFlex = 10,
		lElbowFlex = 20,
		lHipPitch = 10,
		rHipPitch = -5,
		lKneeFlex = 35,
		rKneeFlex = 0,
		lAnklePitch = 0,
		rAnklePitch = 0,
	})
end

function Poses.ascend(character: Model)
	apply(character, {
		torsoPitch = -8,
		headPitch = -2,
		rShoulderPitch = 75,
		rShoulderYaw = 0,
		rShoulderRoll = 0,
		lShoulderPitch = -20,
		lShoulderYaw = 10,
		lShoulderRoll = 0,
		rElbowFlex = 10,
		lElbowFlex = 20,
		lHipPitch = 10,
		rHipPitch = -5,
		lKneeFlex = 35,
		rKneeFlex = 0,
		lAnklePitch = -10,
		rAnklePitch = -10,
	})
end

function Poses.descend(character: Model)
	apply(character, {
		torsoPitch = 0,
		headPitch = -5,
		lShoulderRoll = 10,
		rShoulderRoll = -10,
		lShoulderPitch = 0,
		rShoulderPitch = 0,
		lElbowFlex = 12,
		rElbowFlex = 12,
		lHipPitch = 10,
		rHipPitch = 0,
		lKneeFlex = 18,
		rKneeFlex = 0,
		lAnklePitch = 0,
		rAnklePitch = 0,
	})
end

return Poses
