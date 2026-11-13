--!strict
--!native
--!optimize 2

-- Invisible drag area, typically for custom camera look. Reports the finger's
-- movement since the last update, scaled by `sensitivity`.

local Signal = require(script.Parent.Parent.Signal)
local Util = require(script.Parent.Util)

export type Config = {
	position: UDim2?,
	size: UDim2?,
	anchorPoint: Vector2?,
	sensitivity: number?,
	-- Show a faint outline of the area (useful while laying out controls).
	debug: boolean?,
	name: string?,
	priority: number?,
	theme: { [string]: any }?,
	parent: GuiBase2d?,
}

local Touchpad = {}
Touchpad.__index = Touchpad

export type Touchpad = typeof(setmetatable(
	{} :: {
		__razorControl: true,
		name: string,
		priority: number,
		enabled: boolean,
		destroyed: boolean,
		active: boolean,
		sensitivity: number,
		-- delta (screen space, y down), position, active
		moved: Signal.Signal<Vector2, Vector2, boolean>,
		root: ImageButton,
		_defaults: { position: UDim2, size: UDim2, anchorPoint: Vector2 },
		-- Hidden by the active layout (`visible = false`).
		_layoutHidden: boolean,
		_input: any,
		_last: Vector2,
		_actions: { (active: boolean, value: Vector3) -> () },
	},
	Touchpad
))

function Touchpad.new(config: Config, parent: GuiBase2d): Touchpad
	local theme = Util.resolveTheme(config.theme)

	local name = config.name or "Touchpad"
	local defaults = {
		position = config.position or UDim2.fromScale(0.45, 0),
		size = config.size or UDim2.fromScale(0.55, 1),
		anchorPoint = config.anchorPoint or Vector2.zero,
	}

	local root = Util.hitbox(name)
	root.AnchorPoint = defaults.anchorPoint
	root.Position = defaults.position
	root.Size = defaults.size

	if config.debug then
		root.BackgroundTransparency = 0.92
		root.BackgroundColor3 = theme.accent
		Util.stroke(root, theme, 1)
	end

	root.Parent = parent

	return setmetatable({
		__razorControl = true :: true,
		name = name,
		priority = config.priority or 10,
		enabled = true,
		destroyed = false,
		active = false,
		sensitivity = config.sensitivity or 1,
		moved = Signal.new() :: Signal.Signal<Vector2, Vector2, boolean>,
		root = root,
		_defaults = defaults,
		_layoutHidden = false,
		_input = nil,
		_last = Vector2.zero,
		_actions = {},
	}, Touchpad)
end

function Touchpad._emit(self: Touchpad, delta: Vector2, position: Vector2)
	local active = self.active

	self.moved:fire(delta, position, active)

	local vector = Vector3.new(delta.X, -delta.Y, 0)
	for _, action in self._actions do
		task.spawn(action, active, vector)
	end
end

function Touchpad._accepts(self: Touchpad, position: Vector2): boolean
	-- One finger at a time; extra fingers fall through to gestures.
	return self.enabled and not self.active and Util.isShown(self.root) and Util.contains(self.root, position)
end

function Touchpad._began(self: Touchpad, input: InputObject, position: Vector2)
	self.active = true
	self._input = input
	self._last = position
end

function Touchpad._moved(self: Touchpad, input: InputObject, position: Vector2)
	if input ~= self._input then
		return
	end

	local delta = (position - self._last) * self.sensitivity
	self._last = position

	if delta.Magnitude > 0 then
		self:_emit(delta, position)
	end
end

function Touchpad._ended(self: Touchpad, input: InputObject?, position: Vector2?)
	if not self.active or (input and input ~= self._input) then
		return
	end

	self.active = false
	self._input = nil
	self:_emit(Vector2.zero, position or self._last)
end

function Touchpad._bind(self: Touchpad, action: (active: boolean, value: Vector3) -> ())
	table.insert(self._actions, action)
end

function Touchpad._unbind(self: Touchpad, action: (active: boolean, value: Vector3) -> ())
	Util.unbind(self._actions, action)
end

-- Apply a layout placement; nil restores the touchpad's own config.
function Touchpad._place(self: Touchpad, placement: Util.Placement?)
	local defaults = self._defaults
	local root = self.root

	root.Position = if placement and placement.position then placement.position else defaults.position
	root.Size = if placement and typeof(placement.size) == "UDim2" then placement.size :: UDim2 else defaults.size
	root.AnchorPoint = if placement and placement.anchorPoint then placement.anchorPoint else defaults.anchorPoint

	self._layoutHidden = placement ~= nil and placement.visible == false
	root.Visible = self.enabled and not self._layoutHidden

	if self._layoutHidden then
		self:_ended(nil, nil)
	end
end

function Touchpad._defaultPlacement(self: Touchpad): Util.Placement
	local defaults = self._defaults
	return { position = defaults.position, size = defaults.size, anchorPoint = defaults.anchorPoint, visible = true }
end

function Touchpad.setEnabled(self: Touchpad, enabled: boolean)
	self.enabled = enabled
	self.root.Visible = enabled and not self._layoutHidden

	if not enabled then
		self:_ended(nil, nil)
	end
end

function Touchpad.destroy(self: Touchpad)
	if self.destroyed then
		return
	end

	self:_ended(nil, nil)
	self.destroyed = true
	self.moved:destroy()
	table.clear(self._actions)
	self.root:Destroy()
end

return Touchpad
