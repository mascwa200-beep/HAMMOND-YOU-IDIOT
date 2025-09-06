local Poses = {}

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

local function ang(x: number?, y: number?, z: number?)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end

local function set(motor: Motor6D?, cf: CFrame)
	if motor then
		motor.Transform = cf
	end
end

local function apply(character: Model, spec: { [string]: number? })
	local m = collectMotors(character)
	set(m.Waist, ang(spec.torsoPitch or 0, spec.torsoYaw or 0, 0))
	set(m.Neck, ang(spec.headPitch or 0, 0, 0))

	set(m.LShoulder, ang(spec.lShoulderPitch or 0, spec.lShoulderYaw or 0, spec.lShoulderRoll or 0))
	set(m.RShoulder, ang(spec.rShoulderPitch or 0, spec.rShoulderYaw or 0, spec.rShoulderRoll or 0))

	set(m.LElbow, ang(spec.lElbowFlex or 0, 0, 0))
	set(m.RElbow, ang(spec.rElbowFlex or 0, 0, 0))

	set(m.LHip, ang(spec.lHipPitch or 0, 0, 0))
	set(m.RHip, ang(spec.rHipPitch or 0, 0, 0))

	set(m.LKnee, ang(spec.lKneeFlex or 0, 0, 0))
	set(m.RKnee, ang(spec.rKneeFlex or 0, 0, 0))

	set(m.LAnkle, ang(spec.lAnklePitch or 0, 0, 0))
	set(m.RAnkle, ang(spec.rAnklePitch or 0, 0, 0))
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
