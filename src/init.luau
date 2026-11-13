--!strict
--!native
--!optimize 2

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MouseLook = require(script.MouseLook)
local Signal = require(script.Signal)
local Touch = require(script.Touch)

export type Action = (pressed: boolean, value: Vector3) -> ()
export type MouseLook = MouseLook.MouseLook
-- The kind of input the player last used.
export type Device = "KeyboardMouse" | "Touch" | "Gamepad"
-- A key name ("Space", "ButtonA") or an axis from createAxis.
export type KeySpec = string | { string }
export type Placement = Touch.Placement
-- Keys per bind name and touch placements per control name. Anything left
-- out keeps what the "Default" layout gives it.
export type Layout = {
	keys: { [string]: { KeySpec } }?,
	touch: { [string]: Placement }?,
}

type Kind = "action" | "axis"

-- What a key name binds to: a KeyCode, a mouse button (UserInputType) or a
-- mouse wheel name ("MouseWheel", "MouseWheelUp", "MouseWheelDown").
type InputId = Enum.KeyCode | Enum.UserInputType | string

-- A bind created with a name, so layouts can change its keys.
type Named = {
	kind: Kind,
	action: Action,
	-- Keys given to bindAction/bindAxis: the "Default" layout.
	keys: { KeySpec },
	controls: { any },
	-- Handlers currently in InputBinds.
	codes: { [InputId]: Action },
	-- Releases any key still held under the current handlers.
	release: () -> (),
}

local DEFAULT = "Default"

local InputController = {}

-- Mobile controls: thumbsticks, buttons, toggles, touchpads and gestures.
InputController.Touch = Touch

-- Fires with the layout name after setLayout switches layouts.
InputController.layoutChanged = Signal.new() :: Signal.Signal<string>

-- Fires with the new device when the player switches between keyboard and
-- mouse, touch and gamepad.
InputController.deviceChanged = Signal.new() :: Signal.Signal<Device>

local InputBinds: { [InputId]: Action } = {}

local named: { [string]: Named } = {}
local layouts: { [string]: Layout } = {}
local current = DEFAULT

local looks: { MouseLook } = {}

local KEYBOARD_MOUSE: { [Enum.UserInputType]: true } = {
	[Enum.UserInputType.Keyboard] = true,
	[Enum.UserInputType.TextInput] = true,
	[Enum.UserInputType.MouseMovement] = true,
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
	[Enum.UserInputType.MouseWheel] = true,
}

-- Inputs that say nothing about the device (Focus, Gyro, None...) map to nil.
local function deviceFor(inputType: Enum.UserInputType): Device?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif KEYBOARD_MOUSE[inputType] then
		return "KeyboardMouse"
	elseif string.sub(inputType.Name, 1, 7) == "Gamepad" then
		return "Gamepad"
	end

	return nil
end

-- Before the first input, guess from what the device has.
local function initialDevice(): Device
	if RunService:IsClient() then
		local fromLast: Device? = deviceFor(UserInputService:GetLastInputType())
		if fromLast then
			return fromLast
		end
	end

	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end

	return "KeyboardMouse"
end

local device: Device = initialDevice()

-- Mouse inputs by name. Roblox reports mouse buttons by UserInputType (their
-- KeyCode is Unknown), so they can't be found through Enum.KeyCode.
local MOUSE_INPUTS: { [string]: InputId } = {
	MouseButton1 = Enum.UserInputType.MouseButton1,
	MouseButton2 = Enum.UserInputType.MouseButton2,
	MouseButton3 = Enum.UserInputType.MouseButton3,
	MouseLeftButton = Enum.UserInputType.MouseButton1,
	MouseRightButton = Enum.UserInputType.MouseButton2,
	MouseMiddleButton = Enum.UserInputType.MouseButton3,
	MouseWheel = "MouseWheel",
	MouseWheelUp = "MouseWheelUp",
	MouseWheelDown = "MouseWheelDown",
}

local function inputId(name: string): InputId?
	local mouse = MOUSE_INPUTS[name]
	if mouse then
		return mouse
	end

	local code = Enum.KeyCode:FromName(name)

	if not code then
		warn(name .. " is not a valid KeyCode or mouse input name")
	end

	return code
end

-- Build key handlers for `keys`. Returns them by input, plus a function
-- that releases whatever is still held through them.
local function buildHandlers(kind: Kind, action: Action, keys: { KeySpec }): ({ [InputId]: Action }, () -> ())
	local handlers: { [InputId]: Action } = {}
	local held: { [InputId]: boolean } = {}
	local axes: { { number } } = {}

	for _, spec in keys do
		if type(spec) == "table" then
			if kind ~= "axis" then
				warn("Axis tables can only be bound with bindAxis")
				continue
			end

			local axisDir = { 0, 0, 0, 0 } -- UP, DOWN, LEFT, RIGHT
			table.insert(axes, axisDir)

			for i = 1, 4 do
				local name = spec[i]
				local code = if type(name) == "string" then inputId(name) else nil
				if not code then
					continue
				end

				handlers[code] = function(pressed: boolean)
					axisDir[i] = (pressed and 1) or 0

					action(pressed, Vector3.new(axisDir[4] - axisDir[3], axisDir[1] - axisDir[2]))
				end
			end
		elseif type(spec) == "string" then
			local code = inputId(spec)
			if not code then
				continue
			end

			handlers[code] = function(pressed: boolean, position: Vector3)
				if pressed then
					held[code] = true
				else
					held[code] = nil
				end

				action(pressed, position)
			end
		end
	end

	local function release()
		for code in held do
			held[code] = nil
			action(false, Vector3.zero)
		end

		for _, axisDir in axes do
			if axisDir[1] + axisDir[2] + axisDir[3] + axisDir[4] > 0 then
				axisDir[1], axisDir[2], axisDir[3], axisDir[4] = 0, 0, 0, 0
				action(false, Vector3.zero)
			end
		end
	end

	return handlers, release
end

local function cloneKeys(keys: { KeySpec }): { KeySpec }
	local copy: { KeySpec } = {}
	for index, spec in keys do
		copy[index] = if type(spec) == "table" then table.clone(spec) else spec
	end

	return copy
end

local function cloneLayout(layout: Layout): Layout
	local keys: { [string]: { KeySpec } } = {}
	local sourceKeys: { [string]: { KeySpec } } = layout.keys or {}
	for name, specs in sourceKeys do
		keys[name] = cloneKeys(specs)
	end

	local touch: { [string]: Placement } = {}
	local sourceTouch: { [string]: Placement } = layout.touch or {}
	for name, placement in sourceTouch do
		local copy = table.clone(placement)
		if copy.zone then
			copy.zone = table.clone(copy.zone)
		end
		touch[name] = copy
	end

	return { keys = keys, touch = touch }
end

local function keysFor(name: string, entry: Named): { KeySpec }
	local layout = layouts[current]
	local override = layout and layout.keys and layout.keys[name]

	return override or entry.keys
end

local function attachKeys(entry: Named, keys: { KeySpec })
	local handlers, release = buildHandlers(entry.kind, entry.action, keys)

	for code, handler in handlers do
		InputBinds[code] = handler
	end

	entry.codes = handlers
	entry.release = release
end

local function detachKeys(entry: Named)
	entry.release()

	for code, handler in entry.codes do
		-- Leave keys alone that something bound later has taken over.
		if InputBinds[code] == handler then
			InputBinds[code] = nil
		end
	end

	entry.codes = {}
end

local function bindNamed(kind: Kind, name: string, action: Action, args: { any })
	assert(type(action) == "function", "bind" .. kind .. '("' .. name .. '", action, ...) needs an action function')

	InputController:unbind(name)

	local keys: { KeySpec } = {}
	local controls = {}

	for _, event in args do
		if Touch.isControl(event) then
			event:_bind(action)
			table.insert(controls, event)
		elseif type(event) == "string" or type(event) == "table" then
			table.insert(keys, if type(event) == "table" then table.clone(event) else event)
		end
	end

	local entry: Named = {
		kind = kind,
		action = action,
		keys = keys,
		controls = controls,
		codes = {},
		release = function() end,
	}

	named[name] = entry
	attachKeys(entry, keysFor(name, entry))
end

local function bindUnnamed(kind: Kind, action: Action, args: { any })
	local keys: { KeySpec } = {}

	for _, event in args do
		if Touch.isControl(event) then
			event:_bind(action)
		elseif type(event) == "string" or type(event) == "table" then
			table.insert(keys, event)
		end
	end

	local handlers = buildHandlers(kind, action, keys)
	for code, handler in handlers do
		InputBinds[code] = handler
	end
end

function InputController.createAxis(up: string, down: string, left: string, right: string): { string }
	return { up, down, left, right }
end

-- Touch controls passed to bindAxis/bindAction call `action(active, value)`:
-- thumbsticks pass their direction, touchpads their drag delta, and buttons
-- the touch position (toggles pass their on/off state as `active`).
--
-- Pass a name first (`bindAxis("Move", action, ...)`) to let layouts change
-- its keys. The keys given here are what the "Default" layout uses.
function InputController:bindAxis(nameOrAction: string | Action, ...: any)
	if type(nameOrAction) == "string" then
		bindNamed("axis", nameOrAction, (...), { select(2, ...) })
		return
	end

	bindUnnamed("axis", nameOrAction, { ... })
end

function InputController:bindAction(nameOrAction: string | Action, ...: any)
	if type(nameOrAction) == "string" then
		bindNamed("action", nameOrAction, (...), { select(2, ...) })
		return
	end

	bindUnnamed("action", nameOrAction, { ... })
end

-- Remove a named bind: its keys stop firing and its touch controls stop
-- calling its action.
function InputController:unbind(name: string)
	local entry = named[name]
	if not entry then
		return
	end

	named[name] = nil
	detachKeys(entry)

	for _, control in entry.controls do
		if not control.destroyed then
			control:_unbind(entry.action)
		end
	end
end

-- Add (or replace) a layout. `layout.keys` maps bind names to key lists,
-- `layout.touch` maps control names to placements. Anything not listed keeps
-- its "Default" keys / placement.
function InputController:createLayout(name: string, layout: Layout)
	assert(type(name) == "string", "createLayout needs a layout name")
	assert(name ~= DEFAULT, '"Default" is built from your binds and control configs and cannot be replaced')
	assert(type(layout) == "table", "createLayout needs a layout table")

	layouts[name] = cloneLayout(layout)

	if current == name then
		self:setLayout(name)
	end
end

-- Switch every named bind's keys and every touch control's placement.
function InputController:setLayout(name: string)
	local layout = layouts[name]
	assert(name == DEFAULT or layout, 'No layout named "' .. tostring(name) .. '"')

	local previous = current
	current = name

	-- Detach everything first so layouts can swap keys between binds.
	for _, entry in named do
		detachKeys(entry)
	end

	for bindName, entry in named do
		attachKeys(entry, keysFor(bindName, entry))
	end

	Touch._applyLayout(if layout then layout.touch else nil)

	if previous ~= name then
		InputController.layoutChanged:fire(name)
	end
end

-- Delete a layout. Removing the active one switches back to "Default".
function InputController:removeLayout(name: string)
	assert(name ~= DEFAULT, '"Default" cannot be removed')

	if not layouts[name] then
		return
	end

	layouts[name] = nil

	if current == name then
		self:setLayout(DEFAULT)
	end
end

-- Name of the active layout.
function InputController:currentLayout(): string
	return current
end

-- Every layout name, starting with "Default".
function InputController:getLayouts(): { string }
	local names = {}
	for name in layouts do
		table.insert(names, name)
	end
	table.sort(names)
	table.insert(names, 1, DEFAULT)

	return names
end

-- A copy of a layout (the active one by default) with everything it leaves
-- out filled in from "Default", ready to tweak and pass to createLayout.
function InputController:getLayout(name: string?): Layout?
	local layoutName = name or current
	local layout = layouts[layoutName]
	if layoutName ~= DEFAULT and not layout then
		return nil
	end

	local keys: { [string]: { KeySpec } } = {}
	for bindName, entry in named do
		keys[bindName] = entry.keys
	end

	local touch = Touch._defaultPlacements()

	if layout then
		local layoutKeys: { [string]: { KeySpec } } = layout.keys or {}
		for bindName, specs in layoutKeys do
			keys[bindName] = specs
		end

		local layoutTouch: { [string]: Placement } = layout.touch or {}
		for controlName, placement in layoutTouch do
			local merged = touch[controlName] or {}
			for key, value in placement :: any do
				(merged :: any)[key] = value
			end
			touch[controlName] = merged
		end
	end

	return cloneLayout({ keys = keys, touch = touch })
end

-- A look source that reports mouse movement through `moved`, with the same
-- arguments as a touchpad. Can be passed to bindAxis like a touch control.
function InputController.mouseLook(config: MouseLook.Config?): MouseLook
	local look = MouseLook.new(config or {})
	table.insert(looks, look)
	return look
end

-- The kind of input the player last used: "KeyboardMouse", "Touch" or "Gamepad".
function InputController:device(): Device
	return device
end

-- Internal: update the device from a LastInputType (exposed for tests).
function InputController._updateDevice(inputType: Enum.UserInputType)
	local newDevice: Device? = deviceFor(inputType)
	if newDevice and newDevice ~= device then
		device = newDevice
		InputController.deviceChanged:fire(newDevice)
	end
end

if RunService:IsClient() then
	UserInputService.LastInputTypeChanged:Connect(InputController._updateDevice)
end

-- Mouse buttons whose press reached the binds, so a release only follows a
-- delivered press.
local mouseHeld: { [Enum.UserInputType]: boolean } = {}

-- The wheel has no held state: each scroll step presses and releases at once.
local function tap(id: InputId, value: Vector3)
	local handler = InputBinds[id]
	if handler then
		handler(true, value)
		handler(false, Vector3.zero)
	end
end

-- Call from InputBegan, InputChanged and InputEnded. Pass gameProcessed so
-- gestures ignore touches that land on other UI, and clicks or scrolling on
-- other UI don't reach mouse binds.
function InputController:input(inp: InputObject, gameProcessed: boolean?)
	local inputType = inp.UserInputType

	if inputType == Enum.UserInputType.Touch then
		Touch.process(inp, gameProcessed)
		return
	end

	if
		inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
	then
		for index = #looks, 1, -1 do
			local look = looks[index]

			if look.destroyed then
				table.remove(looks, index)
			else
				look:_process(inp, gameProcessed)
			end
		end

		if inputType == Enum.UserInputType.MouseMovement then
			return
		end

		local handler = InputBinds[inputType]
		local state = inp.UserInputState

		if state == Enum.UserInputState.Begin then
			-- A click on other UI doesn't press the bind.
			if not gameProcessed then
				mouseHeld[inputType] = true

				if handler then
					handler(true, inp.Position)
				end
			end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			-- Only release presses that were delivered.
			if mouseHeld[inputType] then
				mouseHeld[inputType] = nil

				if handler then
					handler(false, inp.Position)
				end
			end
		end

		return
	end

	if inputType == Enum.UserInputType.MouseWheel then
		local scroll = inp.Position.Z
		if gameProcessed or scroll == 0 then
			return
		end

		local value = Vector3.new(0, scroll, 0)
		tap("MouseWheel", value)
		tap(if scroll > 0 then "MouseWheelUp" else "MouseWheelDown", value)
		return
	end

	if InputBinds[inp.KeyCode] then
		InputBinds[inp.KeyCode](inp.UserInputState ~= Enum.UserInputState.End, inp.Position)
	end
end

return InputController
