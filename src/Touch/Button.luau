--!strict
--!native
--!optimize 2

-- On-screen button. Press buttons are held while any finger is on them;
-- toggle buttons flip on each touch-down and stay that way.

local Signal = require(script.Parent.Parent.Signal)
local Util = require(script.Parent.Util)

local PRESSED_SHADE = Color3.new(0, 0, 0)

export type Config = {
	-- Center of the button.
	position: UDim2?,
	-- Diameter (circle) or side length (rounded) in pixels.
	size: number?,
	shape: ("circle" | "rounded")?,
	text: string?,
	-- Icon drawn inside the button.
	image: string?,
	-- Icon tint. Unset keeps the icon's own colours.
	iconColor: Color3?,
	-- Custom art ("rbxassetid://...") drawn in place of the circle. Without
	-- pressedImage / onImage, those states tint the background image instead.
	backgroundImage: string?,
	-- Shown while a finger is on the button.
	pressedImage: string?,
	-- Toggles only: shown while the toggle is on.
	onImage: string?,
	toggle: boolean?,
	-- Starting state of a toggle.
	on: boolean?,
	-- Extra touchable area around the visual, as a multiple of its size.
	hitScale: number?,
	name: string?,
	priority: number?,
	theme: { [string]: any }?,
	parent: GuiBase2d?,
}

local Button = {}
Button.__index = Button

export type Button = typeof(setmetatable(
	{} :: {
		__razorControl: true,
		name: string,
		priority: number,
		enabled: boolean,
		destroyed: boolean,
		isToggle: boolean,
		-- A finger is on the button right now.
		held: boolean,
		-- Press button: same as held. Toggle: the toggled state.
		on: boolean,
		changed: Signal.Signal<boolean>,
		root: ImageButton,
		-- Frame by default, ImageLabel when backgroundImage is set.
		visual: GuiObject,
		label: TextLabel?,
		icon: ImageLabel?,
		_scale: UIScale,
		_stroke: UIStroke?,
		_images: { background: string, pressed: string?, on: string? }?,
		_textConstraint: UITextSizeConstraint?,
		_rounded: boolean,
		_hitScale: number,
		_defaults: { position: UDim2, size: number },
		-- Hidden by the active layout (`visible = false`).
		_layoutHidden: boolean,
		_touches: { [any]: boolean },
		_touchCount: number,
		_actions: { (active: boolean, value: Vector3) -> () },
		_theme: Util.Theme,
	},
	Button
))

function Button.new(config: Config, parent: GuiBase2d): Button
	local theme = Util.resolveTheme(config.theme)
	local size = config.size or 72
	local isToggle = config.toggle == true
	local name = config.name or (if isToggle then "Toggle" else "Button")

	local hitScale = config.hitScale or 1.15
	local position = config.position or UDim2.new(1, -(32 + size / 2), 1, -(32 + size / 2))

	local root = Util.hitbox(name)
	local hitSize = size * hitScale
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = position
	root.Size = UDim2.fromOffset(hitSize, hitSize)

	local visualSize = UDim2.fromOffset(size, size)
	local visual: GuiObject
	local stroke: UIStroke? = nil
	local images: { background: string, pressed: string?, on: string? }? = nil

	if config.backgroundImage then
		visual = Util.image("Visual", visualSize, config.backgroundImage)
		images = { background = config.backgroundImage, pressed = config.pressedImage, on = config.onImage }
	else
		visual = Util.circle("Visual", visualSize, theme.base, theme.baseTransparency)
		if config.shape == "rounded" then
			(visual:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius = UDim.new(0, math.floor(size * 0.22))
		end
		stroke = Util.stroke(visual, theme)
	end
	visual.Position = UDim2.fromScale(0.5, 0.5)
	visual.Parent = root

	local scale = Instance.new("UIScale")
	scale.Parent = visual

	local icon: ImageLabel? = nil
	if config.image then
		local image = Instance.new("ImageLabel")
		image.Name = "Icon"
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(0.55, 0.55)
		image.BackgroundTransparency = 1
		image.Image = config.image
		image.ScaleType = Enum.ScaleType.Fit
		image.ImageColor3 = config.iconColor or Color3.new(1, 1, 1)
		image.ZIndex = 2
		image.Parent = visual
		icon = image
	end

	local label: TextLabel? = nil
	local textConstraint: UITextSizeConstraint? = nil
	if config.text then
		local text = Instance.new("TextLabel")
		text.Name = "Label"
		text.AnchorPoint = Vector2.new(0.5, 0.5)
		text.Position = UDim2.fromScale(0.5, 0.5)
		text.Size = UDim2.fromScale(0.8, 0.8)
		text.BackgroundTransparency = 1
		text.Text = config.text
		text.TextColor3 = theme.text
		text.FontFace = theme.font
		text.TextScaled = true
		text.ZIndex = 2
		text.Parent = visual

		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MinTextSize = 10
		constraint.MaxTextSize = math.max(12, math.floor(size * 0.32))
		constraint.Parent = text

		label = text
		textConstraint = constraint
	end

	root.Parent = parent

	local self = setmetatable({
		__razorControl = true :: true,
		name = name,
		priority = config.priority or 30,
		enabled = true,
		destroyed = false,
		isToggle = isToggle,
		held = false,
		on = isToggle and config.on == true,
		changed = Signal.new() :: Signal.Signal<boolean>,
		root = root,
		visual = visual,
		label = label,
		icon = icon,
		_scale = scale,
		_stroke = stroke,
		_images = images,
		_textConstraint = textConstraint,
		_rounded = images == nil and config.shape == "rounded",
		_hitScale = hitScale,
		_defaults = { position = position, size = size },
		_layoutHidden = false,
		_touches = {},
		_touchCount = 0,
		_actions = {},
		_theme = theme,
	}, Button)

	self:_refresh()

	return self
end

function Button._refresh(self: Button)
	local theme = self._theme
	local highlighted = self.on

	self._scale.Scale = if self.held then 0.92 else 1

	local images = self._images
	if images then
		local visual = self.visual :: ImageLabel
		local showPressed = self.held and images.pressed ~= nil
		local showOn = not showPressed and self.isToggle and self.on and images.on ~= nil

		visual.Image = if showPressed
			then images.pressed :: string
			elseif showOn then images.on :: string
			else images.background

		-- States without their own image tint the background instead.
		local color = Color3.new(1, 1, 1)
		if self.isToggle and self.on and not showOn and not showPressed then
			color = theme.accent
		end
		if self.held and not showPressed then
			color = color:Lerp(PRESSED_SHADE, 0.25)
		end
		visual.ImageColor3 = color

		return
	end

	local visual = self.visual
	visual.BackgroundColor3 = if highlighted then theme.accent else theme.base
	visual.BackgroundTransparency = if self.held
		then math.max(theme.baseTransparency - 0.2, 0)
		else theme.baseTransparency

	local stroke = self._stroke
	if stroke then
		stroke.Color = if highlighted then theme.accent else theme.stroke
		stroke.Transparency = if highlighted then 0 else theme.strokeTransparency
	end
end

function Button._emit(self: Button, position: Vector3)
	local on = self.on

	self.changed:fire(on)

	for _, action in self._actions do
		task.spawn(action, on, position)
	end
end

function Button._accepts(self: Button, position: Vector2): boolean
	return self.enabled and Util.isShown(self.root) and Util.contains(self.root, position)
end

function Button._began(self: Button, input: InputObject, _position: Vector2)
	if self._touches[input] then
		return
	end

	self._touches[input] = true
	self._touchCount += 1

	if self._touchCount > 1 then
		return
	end

	self.held = true
	self.on = if self.isToggle then not self.on else true

	self:_refresh()
	self:_emit(input.Position)
end

function Button._moved(_self: Button, _input: InputObject, _position: Vector2) end

function Button._ended(self: Button, input: InputObject?, _position: Vector2?)
	if input then
		if not self._touches[input] then
			return
		end

		self._touches[input] = nil
		self._touchCount -= 1
	else
		table.clear(self._touches)
		self._touchCount = 0
	end

	if self._touchCount > 0 or not self.held then
		return
	end

	self.held = false

	if self.isToggle then
		self:_refresh()
		return
	end

	self.on = false
	self:_refresh()
	self:_emit(if input then input.Position else Vector3.zero)
end

function Button._bind(self: Button, action: (active: boolean, value: Vector3) -> ())
	table.insert(self._actions, action)
end

function Button._unbind(self: Button, action: (active: boolean, value: Vector3) -> ())
	Util.unbind(self._actions, action)
end

function Button._resize(self: Button, size: number)
	local hitSize = size * self._hitScale
	self.root.Size = UDim2.fromOffset(hitSize, hitSize)
	self.visual.Size = UDim2.fromOffset(size, size)

	if self._rounded then
		local corner = self.visual:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, math.floor(size * 0.22))
		end
	end

	if self._textConstraint then
		self._textConstraint.MaxTextSize = math.max(12, math.floor(size * 0.32))
	end
end

-- Apply a layout placement; nil restores the button's own config.
function Button._place(self: Button, placement: Util.Placement?)
	local defaults = self._defaults
	local size = if placement and type(placement.size) == "number" then placement.size :: number else defaults.size

	self.root.Position = if placement and placement.position then placement.position else defaults.position
	self:_resize(size)

	self._layoutHidden = placement ~= nil and placement.visible == false
	self.root.Visible = self.enabled and not self._layoutHidden

	if self._layoutHidden then
		self:_ended(nil, nil)
	end
end

function Button._defaultPlacement(self: Button): Util.Placement
	return { position = self._defaults.position, size = self._defaults.size, visible = true }
end

-- Toggles only: change the state from code. Fires `changed` unless `silent`.
function Button.set(self: Button, on: boolean, silent: boolean?)
	assert(self.isToggle, "set() is only available on toggle buttons")

	if self.on == on then
		return
	end

	self.on = on
	self:_refresh()

	if not silent then
		self:_emit(Vector3.zero)
	end
end

function Button.setText(self: Button, text: string)
	if self.label then
		self.label.Text = text
	end
end

-- Swap the icon image (only for buttons created with `image`).
function Button.setIcon(self: Button, image: string)
	if self.icon then
		self.icon.Image = image
	end
end

-- Swap custom art at runtime (only for buttons created with `backgroundImage`).
-- Pass nil for pressed/on to fall back to tinting.
function Button.setImages(self: Button, background: string, pressed: string?, on: string?)
	assert(self._images, "setImages() needs a button created with backgroundImage")

	self._images = { background = background, pressed = pressed, on = on }
	self:_refresh()
end

function Button.setEnabled(self: Button, enabled: boolean)
	self.enabled = enabled
	self.root.Visible = enabled and not self._layoutHidden

	if not enabled then
		self:_ended(nil, nil)
	end
end

function Button.destroy(self: Button)
	if self.destroyed then
		return
	end

	self:_ended(nil, nil)
	self.destroyed = true
	self.changed:destroy()
	table.clear(self._actions)
	self.root:Destroy()
end

return Button
