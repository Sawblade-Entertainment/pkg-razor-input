--!strict
--!native
--!optimize 2

-- Vibration on every device that has it: phones, gamepads and standalone VR
-- controllers. Built on HapticEffect, which plays on whatever input device
-- the player is using, so nothing here routes by device; keyboard and mouse
-- simply don't vibrate. (HapticService is deprecated and isn't used.)
--
-- Effects aim at one side of the device or all of it: "Left" / "Right" is one
-- VR hand or one side of a gamepad, "Both" (the default) is the whole device.

local RunService = game:GetService("RunService")

export type Side = "Left" | "Right" | "Both"
export type Preset = "UIHover" | "UIClick" | "UINotification" | "GameplayExplosion" | "GameplayCollision"

type Aim = { position: Vector3, radius: number }

-- HapticEffect.Position runs from -1 (left of the device) to 1 (right), and
-- Radius is how far the effect spreads; 3, the default, covers everything.
local AIMS: { [Side]: Aim } = {
	Left = { position = Vector3.new(-1, 0, 0), radius = 0.8 },
	Right = { position = Vector3.new(1, 0, 0), radius = 0.8 },
	Both = { position = Vector3.zero, radius = 3 },
}

local PRESETS: { [string]: Enum.HapticEffectType } = {
	UIHover = Enum.HapticEffectType.UIHover,
	UIClick = Enum.HapticEffectType.UIClick,
	UINotification = Enum.HapticEffectType.UINotification,
	GameplayExplosion = Enum.HapticEffectType.GameplayExplosion,
	GameplayCollision = Enum.HapticEffectType.GameplayCollision,
}

local Haptics = {}

local enabled = true
local folder: Folder? = nil

-- Effects are made once and replayed, so nothing has to be cleaned up after
-- playing (HapticEffect.Ended isn't reliable enough to destroy on). Pulses
-- and waveforms share one custom effect per side, so a newer one replaces an
-- older one; presets get one effect per preset and side.
local customs: { [Side]: HapticEffect } = {}
local presets: { [Side]: { [string]: HapticEffect } } = { Left = {}, Right = {}, Both = {} }

local function aim(side: Side?): Side
	if side == nil then
		return "Both"
	end

	assert(AIMS[side], 'Haptic side must be "Left", "Right" or "Both"')
	return side
end

local function container(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end

	local new = Instance.new("Folder")
	new.Name = "RazorHaptics"
	new.Archivable = false
	new.Parent = workspace
	folder = new

	return new
end

local function makeEffect(side: Side, effectType: Enum.HapticEffectType, name: string): HapticEffect
	local effect = Instance.new("HapticEffect")
	effect.Name = name
	effect.Type = effectType
	effect.Position = AIMS[side].position
	effect.Radius = AIMS[side].radius
	effect.Parent = container()

	return effect
end

-- Haptics only play on the client, and not while turned off.
local function canPlay(): boolean
	return enabled and RunService:IsClient()
end

local function customFor(side: Side): HapticEffect
	local existing = customs[side]
	if existing and existing.Parent then
		return existing
	end

	local made = makeEffect(side, Enum.HapticEffectType.Custom, "Pulse" .. side)
	customs[side] = made
	return made
end

local function presetFor(side: Side, preset: string, effectType: Enum.HapticEffectType): HapticEffect
	local existing = presets[side][preset]
	if existing and existing.Parent then
		return existing
	end

	local made = makeEffect(side, effectType, preset .. side)
	presets[side][preset] = made
	return made
end

local function playCustom(side: Side, keys: { FloatCurveKey })
	local effect = customFor(side)
	effect:Stop()
	effect:SetWaveformKeys(keys)
	effect:Play()
end

-- Vibrate at `strength` (0 to 1, default 1) for `duration` seconds (default
-- 0.1). A newer pulse or waveform on the same side replaces this one, so
-- calling it every frame with a changing strength gives a steady rumble.
function Haptics.pulse(strength: number?, duration: number?, side: Side?)
	local resolved: Side = aim(side)
	if not canPlay() then
		return
	end

	local level = math.clamp(strength or 1, 0, 1)
	local length = math.max((duration or 0.1) * 1000, 1)

	playCustom(resolved, {
		FloatCurveKey.new(0, level, Enum.KeyInterpolationMode.Constant),
		FloatCurveKey.new(length, level, Enum.KeyInterpolationMode.Constant),
		FloatCurveKey.new(length + 1, 0, Enum.KeyInterpolationMode.Constant),
	})
end

-- Play a custom waveform: FloatCurveKeys with Time in milliseconds and Value
-- from 0 to 1. Replaces any pulse or waveform on the same side.
function Haptics.waveform(keys: { FloatCurveKey }, side: Side?)
	assert(type(keys) == "table" and #keys > 0, "waveform needs at least one FloatCurveKey")

	local resolved: Side = aim(side)
	if not canPlay() then
		return
	end

	local clamped: { FloatCurveKey } = {}
	for index, key in keys do
		clamped[index] = FloatCurveKey.new(key.Time, math.clamp(key.Value, 0, 1), key.Interpolation)
	end

	playCustom(resolved, clamped)
end

-- Play one of Roblox's predefined effects: "UIHover", "UIClick",
-- "UINotification", "GameplayExplosion" or "GameplayCollision". Playing one
-- again restarts it.
function Haptics.play(preset: Preset, side: Side?)
	local effectType = PRESETS[preset]
	assert(effectType, 'Unknown haptic preset "' .. tostring(preset) .. '"')

	local resolved: Side = aim(side)
	if not canPlay() then
		return
	end

	local effect = presetFor(resolved, preset, effectType)
	effect:Stop()
	effect:Play()
end

local function stopSide(side: Side)
	local effect = customs[side]
	if effect and effect.Parent then
		effect:Stop()
	end

	for _, preset in presets[side] do
		if preset.Parent then
			preset:Stop()
		end
	end
end

-- Stop what is playing on one side, or everything.
function Haptics.stop(side: Side?)
	if side then
		stopSide(aim(side))
	else
		stopSide("Left")
		stopSide("Right")
		stopSide("Both")
	end
end

-- Turn every haptic off (a settings toggle, say) or back on. Turning off
-- stops whatever is playing; calls while off do nothing.
function Haptics.setEnabled(on: boolean)
	enabled = on

	if not on then
		Haptics.stop()
	end
end

function Haptics.isEnabled(): boolean
	return enabled
end

return Haptics
