--!strict
--!native
--!optimize 2

-- VR headsets and controllers: whether VR is on, head and hand poses in world
-- space, pointer rays, haptics and recentering.
--
-- Controller buttons and sticks arrive as Gamepad1 keys, so they bind through
-- bindAction/bindAxis like any key ("VRRightTrigger", "VRLeftStick"...).
-- This module covers what keys can't: where the head and hands are.

local RunService = game:GetService("RunService")
local VRService = game:GetService("VRService")

local Haptics = require(script.Parent.Haptics)
local Signal = require(script.Parent.Signal)

export type Part = "Head" | "LeftHand" | "RightHand"
export type Hand = "Left" | "Right"

export type Config = {
	name: string?,
}

local USER_CFRAMES: { [Part]: Enum.UserCFrame } = {
	Head = Enum.UserCFrame.Head,
	LeftHand = Enum.UserCFrame.LeftHand,
	RightHand = Enum.UserCFrame.RightHand,
}

local RENDER_STEP = "RazorInputVRPoses"

local Pose = {}
Pose.__index = Pose

export type Pose = typeof(setmetatable(
	{} :: {
		__razorControl: true,
		name: string,
		part: Part,
		enabled: boolean,
		destroyed: boolean,
		-- Whether the headset or controller is tracked right now.
		tracked: boolean,
		-- Latest pose in world space.
		cframe: CFrame,
		-- Latest pose as VRService reports it: relative to the camera, unscaled.
		localCFrame: CFrame,
		-- world, local, tracked
		moved: Signal.Signal<CFrame, CFrame, boolean>,
		_actions: { (active: boolean, value: Vector3) -> () },
	},
	Pose
))

local VR = {}

-- Fires with the new value when a headset is connected or disconnected.
VR.enabledChanged = Signal.new() :: Signal.Signal<boolean>

-- Test override for VREnabled: nil follows VRService.
local enabledOverride: boolean? = nil
-- Test overrides for poses, relative to the camera like VRService reports.
local poseOverrides: { [Part]: CFrame } = {}

local poses: { Pose } = {}
local stepping = false

-- Whether the player is in VR.
function VR.enabled(): boolean
	if enabledOverride ~= nil then
		return enabledOverride
	end

	return RunService:IsClient() and VRService.VREnabled
end

local lastEnabled = VR.enabled()

local function refreshEnabled()
	local enabled = VR.enabled()
	if enabled ~= lastEnabled then
		lastEnabled = enabled
		VR.enabledChanged:fire(enabled)
	end
end

local function partFor(hand: Hand): Part
	if hand == "Left" then
		return "LeftHand"
	elseif hand == "Right" then
		return "RightHand"
	end

	error('VR hand must be "Left" or "Right"', 3)
end

-- Convert a pose relative to the camera (what VRService reports) to world
-- space: scale its position by Camera.HeadScale, then apply the camera.
function VR.toWorld(localCFrame: CFrame): CFrame
	local camera = workspace.CurrentCamera
	if not camera then
		return localCFrame
	end

	return camera.CFrame * (localCFrame.Rotation + localCFrame.Position * camera.HeadScale)
end

-- A part's pose relative to the camera, and whether it is tracked. Untracked
-- parts report CFrame.identity.
function VR.localPose(part: Part): (CFrame, boolean)
	local userCFrame = USER_CFRAMES[part]
	assert(userCFrame, 'VR part must be "Head", "LeftHand" or "RightHand"')

	if not VR.enabled() then
		return CFrame.identity, false
	end

	local override = poseOverrides[part]
	if override then
		return override, true
	end

	-- With VR faked (_setEnabled), only faked poses are tracked: VRService
	-- has nothing real to report, and what it reports early on can vary.
	if enabledOverride ~= nil then
		return CFrame.identity, false
	end

	if not VRService:GetUserCFrameEnabled(userCFrame) then
		return CFrame.identity, false
	end

	return VRService:GetUserCFrame(userCFrame), true
end

-- A part's pose in world space, and whether it is tracked.
function VR.pose(part: Part): (CFrame, boolean)
	local localCFrame, tracked = VR.localPose(part)
	if not tracked then
		return CFrame.identity, false
	end

	return VR.toWorld(localCFrame), true
end

-- A ray from a hand along where the controller points, `length` studs long
-- (1000 by default). nil while the hand isn't tracked.
function VR.pointer(hand: Hand, length: number?): Ray?
	local cframe, tracked = VR.pose(partFor(hand))
	if not tracked then
		return nil
	end

	return Ray.new(cframe.Position, cframe.LookVector * (length or 1000))
end

local function checkHand(hand: Hand?)
	assert(hand == nil or hand == "Left" or hand == "Right", 'VR hand must be "Left" or "Right"')
end

-- Vibrate one controller at `strength` (0 to 1, default 1) for `duration`
-- seconds (default 0.1). Shortcut for Haptics.pulse aimed at that hand.
function VR.pulse(hand: Hand, strength: number?, duration: number?)
	assert(hand ~= nil, 'VR.pulse needs a hand: "Left" or "Right"')
	checkHand(hand)
	Haptics.pulse(strength, duration, hand)
end

-- Stop vibrating one hand, or both. Shortcut for Haptics.stop.
function VR.stopHaptics(hand: Hand?)
	checkHand(hand)
	Haptics.stop(hand)
end

-- Make the headset's current position and facing the new center.
function VR.recenter()
	if VR.enabled() then
		VRService:RecenterUserHeadCFrame()
	end
end

-- Pose sources ---------------------------------------------------------------

function Pose._emit(self: Pose)
	local tracked = self.tracked
	local cframe = self.cframe

	self.moved:fire(cframe, self.localCFrame, tracked)

	local position = cframe.Position
	for _, action in self._actions do
		task.spawn(action, tracked, position)
	end
end

function Pose._update(self: Pose, cframe: CFrame, localCFrame: CFrame, tracked: boolean)
	if not self.enabled then
		return
	end

	if tracked == self.tracked and cframe == self.cframe then
		return
	end

	self.tracked = tracked
	self.cframe = cframe
	self.localCFrame = localCFrame
	self:_emit()
end

-- Stop reporting: fires once more with tracked = false if it was tracked.
function Pose._stop(self: Pose)
	if not self.tracked then
		return
	end

	self.tracked = false
	self:_emit()
end

function Pose._bind(self: Pose, action: (active: boolean, value: Vector3) -> ())
	table.insert(self._actions, action)
end

function Pose._unbind(self: Pose, action: (active: boolean, value: Vector3) -> ())
	local index = table.find(self._actions, action)
	if index then
		table.remove(self._actions, index)
	end
end

function Pose.setEnabled(self: Pose, enabled: boolean)
	if self.destroyed or self.enabled == enabled then
		return
	end

	if not enabled then
		self:_stop()
	end

	self.enabled = enabled
end

function Pose.destroy(self: Pose)
	if self.destroyed then
		return
	end

	self:_stop()
	self.destroyed = true
	self.moved:destroy()
	table.clear(self._actions)
end

-- Read every part once and update each pose source. Runs every frame right
-- after the camera, so world poses follow both the player and the camera.
-- Exposed for tests.
function VR._step()
	local frame: { [Part]: { any } } = {}

	for index = #poses, 1, -1 do
		local pose = poses[index]

		if pose.destroyed then
			table.remove(poses, index)
			continue
		end

		local reading = frame[pose.part]
		if not reading then
			local localCFrame, tracked = VR.localPose(pose.part)
			local cframe = if tracked then VR.toWorld(localCFrame) else CFrame.identity
			reading = { cframe, localCFrame, tracked }
			frame[pose.part] = reading
		end

		pose:_update(reading[1], reading[2], reading[3])
	end

	if #poses == 0 and stepping then
		stepping = false
		RunService:UnbindFromRenderStep(RENDER_STEP)
	end
end

local function track(pose: Pose): Pose
	table.insert(poses, pose)

	if not stepping and RunService:IsClient() then
		stepping = true
		RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, VR._step)
	end

	return pose
end

local function newPose(part: Part, config: Config?): Pose
	local resolved: Config = config or {}

	return track(setmetatable({
		__razorControl = true :: true,
		name = (resolved.name or part) :: string,
		part = part,
		enabled = true,
		destroyed = false,
		tracked = false,
		cframe = CFrame.identity,
		localCFrame = CFrame.identity,
		moved = Signal.new() :: Signal.Signal<CFrame, CFrame, boolean>,
		_actions = {},
	}, Pose))
end

-- A pose source for one controller. `moved` fires every frame the pose
-- changes; bound to bindAxis, it calls `action(tracked, worldPosition)`.
function VR.hand(hand: Hand, config: Config?): Pose
	return newPose(partFor(hand), config)
end

-- A pose source for the headset, like VR.hand.
function VR.head(config: Config?): Pose
	return newPose("Head", config)
end

-- Test hooks -----------------------------------------------------------------

-- Force VR on or off; nil follows VRService again.
function VR._setEnabled(enabled: boolean?)
	enabledOverride = enabled
	refreshEnabled()
end

-- Report `cframe` (relative to the camera) for a part; nil clears it.
function VR._setPose(part: Part, cframe: CFrame?)
	assert(USER_CFRAMES[part], 'VR part must be "Head", "LeftHand" or "RightHand"')
	if cframe then
		poseOverrides[part] = cframe
	else
		poseOverrides[part] = nil
	end
end

if RunService:IsClient() then
	VRService:GetPropertyChangedSignal("VREnabled"):Connect(refreshEnabled)
end

return VR
