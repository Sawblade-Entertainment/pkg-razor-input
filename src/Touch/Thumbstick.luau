--!strict
--!native
--!optimize 2

-- On-screen analog stick. `value` is a Vector2 with x = right, y = up and a
-- magnitude from 0 to 1 (after the deadzone), matching keyboard axes.

local Signal = require(script.Parent.Parent.Signal)
local Util = require(script.Parent.Util)

export type Config = {
	-- Center of the stick (static) or its resting spot (dynamic).
	position: UDim2?,
	-- Base diameter in pixels.
	size: number?,
	-- Knob diameter as a fraction of the base.
	knobScale: number?,
	-- Stick travel below this fraction reads as zero; the rest is rescaled to 0..1.
	deadzone: number?,
	-- Extra touchable area around a static stick, as a multiple of its size.
	hitScale: number?,
	-- Dynamic sticks appear wherever a finger lands inside `zone`.
	dynamic: boolean?,
	zone: { position: UDim2, size: UDim2 }?,
	-- Dynamic only: drag the base along when the finger goes past the edge.
	follow: boolean?,
	-- Dynamic only: fade the stick out while it is not held.
	hideWhenIdle: boolean?,
	-- Custom art ("rbxassetid://..."), drawn untinted in place of the circles.
	baseImage: string?,
	knobImage: string?,
	name: string?,
	priority: number?,
	theme: { [string]: any }?,
	parent: GuiBase2d?,
}

local Thumbstick = {}
Thumbstick.__index = Thumbstick

export type Thumbstick = typeof(setmetatable(
	{} :: {
		__razorControl: true,
		priority: number,
		enabled: boolean,
		destroyed: boolean,
		active: boolean,
		value: Vector2,
		changed: Signal.Signal<Vector2, boolean>,
		root: ImageButton,
		-- Frame by default, ImageLabel when baseImage / knobImage is set.
		base: GuiObject,
		knob: GuiObject,
		_dynamic: boolean,
		_follow: boolean,
		_hideWhenIdle: boolean,
		_deadzone: number,
		_size: number,
		_restPosition: UDim2,
		_origin: Vector2,
		_parent: GuiBase2d,
		_actions: { (active: boolean, value: Vector3) -> () },
		_theme: Util.Theme,
	},
	Thumbstick
))

local function applyDeadzone(raw: Vector2, deadzone: number): Vector2
	local magnitude = raw.Magnitude
	if magnitude <= deadzone or magnitude == 0 then
		return Vector2.zero
	end

	local scaled = math.min((magnitude - deadzone) / (1 - deadzone), 1)

	return raw.Unit * scaled
end

function Thumbstick.new(config: Config, parent: GuiBase2d): Thumbstick
	local theme = Util.resolveTheme(config.theme)
	local size = config.size or 140
	local position = config.position or UDim2.new(0, 32 + size / 2, 1, -(32 + size / 2))
	local dynamic = config.dynamic == true
	local name = config.name or "Thumbstick"

	local root = Util.hitbox(name)
	if dynamic then
		local zone = config.zone or { position = UDim2.fromScale(0, 0.3), size = UDim2.fromScale(0.45, 0.7) }
		root.Position = zone.position
		root.Size = zone.size
	else
		local hitSize = size * (config.hitScale or 1.35)
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = position
		root.Size = UDim2.fromOffset(hitSize, hitSize)
	end

	local baseSize = UDim2.fromOffset(size, size)
	local base: GuiObject
	if config.baseImage then
		base = Util.image(name .. "Base", baseSize, config.baseImage)
	else
		base = Util.circle(name .. "Base", baseSize, theme.base, theme.baseTransparency)
		Util.stroke(base, theme)
	end
	base.Position = position
	base.ZIndex = 2

	local knobSize = size * (config.knobScale or 0.45)
	local knobDimensions = UDim2.fromOffset(knobSize, knobSize)
	local knob: GuiObject = if config.knobImage
		then Util.image("Knob", knobDimensions, config.knobImage)
		else Util.circle("Knob", knobDimensions, theme.knob, theme.knobTransparency)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.ZIndex = 3
	knob.Parent = base

	root.Parent = parent
	base.Parent = parent

	local self = setmetatable({
		__razorControl = true :: true,
		priority = config.priority or 20,
		enabled = true,
		destroyed = false,
		active = false,
		value = Vector2.zero,
		changed = Signal.new() :: Signal.Signal<Vector2, boolean>,
		root = root,
		base = base,
		knob = knob,
		_dynamic = dynamic,
		_follow = config.follow ~= false,
		_hideWhenIdle = dynamic and config.hideWhenIdle == true,
		_deadzone = math.clamp(config.deadzone or 0.12, 0, 0.95),
		_size = size,
		_restPosition = position,
		_origin = Vector2.zero,
		_parent = parent,
		_actions = {},
		_theme = theme,
	}, Thumbstick)

	self:_setIdleVisual()

	return self
end

function Thumbstick._setIdleVisual(self: Thumbstick)
	self.base.Visible = not self._hideWhenIdle or self.active
end

function Thumbstick._radius(self: Thumbstick): number
	local absolute = self.base.AbsoluteSize.X
	return (if absolute > 0 then absolute else self._size) / 2
end

function Thumbstick._emit(self: Thumbstick)
	local value = self.value
	local active = self.active

	self.changed:fire(value, active)

	local vector = Vector3.new(value.X, value.Y, 0)
	for _, action in self._actions do
		task.spawn(action, active, vector)
	end
end

function Thumbstick._accepts(self: Thumbstick, position: Vector2): boolean
	return self.enabled and not self.active and Util.isShown(self.root) and Util.contains(self.root, position)
end

function Thumbstick._began(self: Thumbstick, _input: InputObject, position: Vector2)
	self.active = true

	if self._dynamic then
		self._origin = position
		self:_placeBase(position)
	else
		self._origin = Util.center(self.base)
	end

	self:_setIdleVisual()
	self:_update(position, true)
end

function Thumbstick._moved(self: Thumbstick, _input: InputObject, position: Vector2)
	if self.active then
		self:_update(position)
	end
end

function Thumbstick._ended(self: Thumbstick, _input: InputObject?, _position: Vector2?)
	if not self.active then
		return
	end

	self.active = false
	self.value = Vector2.zero
	self.knob.Position = UDim2.fromScale(0.5, 0.5)

	if self._dynamic then
		self.base.Position = self._restPosition
	end

	self:_setIdleVisual()
	self:_emit()
end

function Thumbstick._placeBase(self: Thumbstick, position: Vector2)
	local offset = position - self._parent.AbsolutePosition
	self.base.Position = UDim2.fromOffset(offset.X, offset.Y)
end

-- `force` emits even when the value is unchanged, so touch-down at dead center
-- still reports that the stick is held.
function Thumbstick._update(self: Thumbstick, position: Vector2, force: boolean?)
	local radius = self:_radius()
	local offset = position - self._origin

	if self._dynamic and self._follow and offset.Magnitude > radius then
		self._origin += offset.Unit * (offset.Magnitude - radius)
		self:_placeBase(self._origin)
		offset = position - self._origin
	end

	local raw = offset / radius
	if raw.Magnitude > 1 then
		raw = raw.Unit
	end

	self.knob.Position = UDim2.new(0.5, raw.X * radius, 0.5, raw.Y * radius)

	-- Screen space has y pointing down; flip so pushing up reads as +y.
	local value = applyDeadzone(Vector2.new(raw.X, -raw.Y), self._deadzone)
	if force or value ~= self.value then
		self.value = value
		self:_emit()
	end
end

function Thumbstick._bind(self: Thumbstick, action: (active: boolean, value: Vector3) -> ())
	table.insert(self._actions, action)
end

function Thumbstick.setEnabled(self: Thumbstick, enabled: boolean)
	self.enabled = enabled
	self.root.Visible = enabled
	self.base.Visible = enabled and (not self._hideWhenIdle or self.active)

	if not enabled then
		self:_ended(nil, nil)
	end
end

function Thumbstick.destroy(self: Thumbstick)
	if self.destroyed then
		return
	end

	self:_ended(nil, nil)
	self.destroyed = true
	self.changed:destroy()
	table.clear(self._actions)
	self.root:Destroy()
	self.base:Destroy()
end

return Thumbstick
