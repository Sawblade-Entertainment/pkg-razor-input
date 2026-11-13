--!strict
--!native
--!optimize 2

-- Mobile controls. Touches reach this module through RazorInput:input(), which
-- must be called for InputBegan, InputChanged and InputEnded.
--
-- Each touch is offered to the controls first (highest priority, then newest);
-- the first control that contains the finger owns that touch until it lifts.
-- Touches no control claims, and that did not land on other game UI, go to
-- every gesture recognizer.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Button = require(script.Button)
local Gestures = require(script.Gestures)
local Thumbstick = require(script.Thumbstick)
local Touchpad = require(script.Touchpad)
local Util = require(script.Util)

export type Thumbstick = Thumbstick.Thumbstick
export type Button = Button.Button
export type Touchpad = Touchpad.Touchpad
export type Gestures = Gestures.Gestures
export type Visibility = "auto" | "always" | "never"
export type Placement = Util.Placement

local Touch = {}

-- Default look for every control. Change keys before creating controls.
Touch.theme = Util.theme

local controls: { Util.Control } = {}
local recognizers: { Gestures } = {}
local claims: { [any]: Util.Control } = {}
-- Placements from the active layout, keyed by control name.
local placements: { [string]: Placement } = {}

local screenGui: ScreenGui? = nil
local visibility: Visibility = "auto"
local listening = false

local function shouldShow(): boolean
	if visibility == "always" then
		return true
	elseif visibility == "never" then
		return false
	end

	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return true
	end

	-- Before the first input on a phone, LastInputType is still None.
	return last == Enum.UserInputType.None and UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- Let go of every touch held by a control (and every gesture in progress).
function Touch.releaseAll()
	for input, control in claims do
		claims[input] = nil
		control:_ended(input, nil)
	end

	for _, recognizer in recognizers do
		recognizer:_ended(nil, nil)
	end
end

local function updateVisibility()
	local gui = screenGui
	if not gui then
		return
	end

	local show = shouldShow()
	if gui.Enabled ~= show then
		gui.Enabled = show

		if not show then
			Touch.releaseAll()
		end
	end
end

-- The ScreenGui the controls live in, created on first use.
function Touch.gui(): ScreenGui
	if screenGui and screenGui.Parent then
		return screenGui
	end

	local player = Players.LocalPlayer
	assert(player, "RazorInput.Touch controls can only be created on the client")

	local gui = Instance.new("ScreenGui")
	gui.Name = "RazorTouch"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	screenGui = gui

	if not listening then
		listening = true
		UserInputService.LastInputTypeChanged:Connect(updateVisibility)
	end

	gui.Enabled = shouldShow()

	return gui
end

-- "auto" (default) shows the controls while the player is using touch,
-- "always" / "never" force them on or off.
function Touch.setVisibility(mode: Visibility)
	visibility = mode
	updateVisibility()
end

-- Whether controls are (or, before any exist, would be) shown right now.
function Touch.isVisible(): boolean
	return shouldShow()
end

-- Hide or restore Roblox's built-in thumbstick and jump button.
function Touch.setDefaultControlsEnabled(enabled: boolean)
	GuiService.TouchControlsEnabled = enabled
end

-- `controls` is kept in ascending priority order with newer controls after
-- older ones of the same priority; routing walks it from the back.
local function register(control: any)
	local index = #controls + 1
	while index > 1 and controls[index - 1].priority > control.priority do
		index -= 1
	end

	table.insert(controls, index, control)

	local placement = placements[control.name]
	if placement then
		control:_place(placement)
	end

	return control
end

-- Used by RazorInput.setLayout: place every control by name. Controls without
-- an entry go back to their own config. Later controls pick it up on creation.
function Touch._applyLayout(layout: { [string]: Placement }?)
	placements = layout or {}

	for index = #controls, 1, -1 do
		local control = controls[index]

		if control.destroyed then
			table.remove(controls, index)
		else
			control:_place(placements[control.name])
		end
	end
end

-- Each control's placement from its own config, keyed by name (the first
-- control found wins when names repeat).
function Touch._defaultPlacements(): { [string]: Placement }
	local result: { [string]: Placement } = {}

	for _, control in controls do
		if not control.destroyed and result[control.name] == nil then
			result[control.name] = control:_defaultPlacement()
		end
	end

	return result
end

function Touch.thumbstick(config: Thumbstick.Config?): Thumbstick
	local resolved: Thumbstick.Config = config or {}
	return register(Thumbstick.new(resolved, resolved.parent or Touch.gui()))
end

function Touch.button(config: Button.Config?): Button
	local resolved: Button.Config = config or {}
	return register(Button.new(resolved, resolved.parent or Touch.gui()))
end

function Touch.toggle(config: Button.Config?): Button
	local resolved: Button.Config = table.clone(config or {})
	resolved.toggle = true
	return register(Button.new(resolved, resolved.parent or Touch.gui()))
end

function Touch.touchpad(config: Touchpad.Config?): Touchpad
	local resolved: Touchpad.Config = config or {}
	return register(Touchpad.new(resolved, resolved.parent or Touch.gui()))
end

function Touch.gestures(config: Gestures.Config?): Gestures
	local recognizer = Gestures.new(config or {})
	table.insert(recognizers, recognizer)
	return recognizer
end

function Touch.isControl(value: any): boolean
	return type(value) == "table" and value.__razorControl == true
end

-- Route one touch InputObject. Returns true when a control owns the touch.
function Touch.process(input: InputObject, gameProcessed: boolean?): boolean
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return false
	end

	local state = input.UserInputState
	local position = Util.toVector2(input.Position)
	local owner = claims[input]

	if state == Enum.UserInputState.Begin then
		if owner then
			return true
		end

		for index = #controls, 1, -1 do
			local control = controls[index]

			if control.destroyed then
				table.remove(controls, index)
				continue
			end

			if control:_accepts(position) then
				claims[input] = control
				control:_began(input, position)
				return true
			end
		end

		if not gameProcessed then
			for index = #recognizers, 1, -1 do
				local recognizer = recognizers[index]

				if recognizer.destroyed then
					table.remove(recognizers, index)
				else
					recognizer:_began(input, position)
				end
			end
		end

		return false
	elseif state == Enum.UserInputState.Change then
		if owner then
			if owner.destroyed then
				claims[input] = nil
			else
				owner:_moved(input, position)
			end

			return true
		end

		for _, recognizer in recognizers do
			recognizer:_moved(input, position)
		end

		return false
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		if owner then
			claims[input] = nil
			owner:_ended(input, position)
			return true
		end

		for _, recognizer in recognizers do
			recognizer:_ended(input, position)
		end

		return false
	end

	return false
end

return Touch
