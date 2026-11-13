--!strict
--!native
--!optimize 2

-- Shared helpers and the default look for the touch controls.

local Util = {}

-- Edit before creating controls to restyle every control at once, or pass a
-- per-control `theme` table to override individual keys.
Util.theme = {
	base = Color3.fromRGB(20, 21, 24),
	baseTransparency = 0.45,
	stroke = Color3.fromRGB(255, 255, 255),
	strokeTransparency = 0.7,
	knob = Color3.fromRGB(236, 237, 241),
	knobTransparency = 0.1,
	accent = Color3.fromRGB(88, 166, 255),
	text = Color3.fromRGB(240, 241, 245),
	font = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
}

export type Theme = typeof(Util.theme)

-- Where a control sits in a layout. Unset keys fall back to the control's
-- own config. `size` is a pixel number for buttons and thumbsticks and a UDim2
-- for touchpads; `zone` is for dynamic thumbsticks, `anchorPoint` for touchpads.
export type Placement = {
	position: UDim2?,
	size: (number | UDim2)?,
	anchorPoint: Vector2?,
	zone: { position: UDim2, size: UDim2 }?,
	visible: boolean?,
}

-- Anything that can be routed through the touch router.
export type Control = {
	__razorControl: true,
	name: string,
	priority: number,
	enabled: boolean,
	destroyed: boolean,
	root: GuiObject,
	_accepts: (self: any, position: Vector2) -> boolean,
	_began: (self: any, input: InputObject, position: Vector2) -> (),
	_moved: (self: any, input: InputObject, position: Vector2) -> (),
	_ended: (self: any, input: InputObject?, position: Vector2?) -> (),
	_bind: (self: any, action: (active: boolean, value: Vector3) -> ()) -> (),
	_unbind: (self: any, action: (active: boolean, value: Vector3) -> ()) -> (),
	_place: (self: any, placement: Placement?) -> (),
	_defaultPlacement: (self: any) -> Placement,
}

function Util.clonePlacement(placement: Placement): Placement
	local copy = table.clone(placement)
	if copy.zone then
		copy.zone = table.clone(copy.zone)
	end

	return copy
end

-- Remove one bound action (the first match) from a control's action list.
function Util.unbind(actions: { any }, action: any)
	local index = table.find(actions, action)
	if index then
		table.remove(actions, index)
	end
end

function Util.resolveTheme(overrides: { [string]: any }?): Theme
	if not overrides then
		return Util.theme
	end

	local theme = table.clone(Util.theme) :: any
	for key, value in overrides do
		theme[key] = value
	end

	return theme
end

function Util.toVector2(position: Vector3): Vector2
	return Vector2.new(position.X, position.Y)
end

function Util.center(object: GuiBase2d): Vector2
	return object.AbsolutePosition + object.AbsoluteSize / 2
end

function Util.contains(object: GuiBase2d, position: Vector2): boolean
	local topLeft = object.AbsolutePosition
	local bottomRight = topLeft + object.AbsoluteSize

	return position.X >= topLeft.X
		and position.Y >= topLeft.Y
		and position.X <= bottomRight.X
		and position.Y <= bottomRight.Y
end

-- True when the object and every GuiObject/ScreenGui above it is shown.
function Util.isShown(object: GuiObject): boolean
	local current: Instance? = object

	while current do
		if current:IsA("GuiObject") then
			if not current.Visible then
				return false
			end
		elseif current:IsA("LayerCollector") then
			return current.Enabled
		end

		current = current.Parent
	end

	return false
end

-- Invisible, input-sinking hit area. Sinking keeps the default camera from
-- rotating when a finger lands on a control.
function Util.hitbox(name: string): ImageButton
	local hitbox = Instance.new("ImageButton")
	hitbox.Name = name
	hitbox.BackgroundTransparency = 1
	hitbox.ImageTransparency = 1
	hitbox.AutoButtonColor = false
	hitbox.Selectable = false
	hitbox.Active = true

	return hitbox
end

function Util.circle(name: string, size: UDim2, color: Color3, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = size
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame

	return frame
end

-- A centered, untinted image scaled to fit `size`, used in place of a circle
-- when a control is given custom art.
function Util.image(name: string, size: UDim2, image: string): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = size
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Image = image
	label.ScaleType = Enum.ScaleType.Fit

	return label
end

function Util.stroke(parent: GuiObject, theme: Theme, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = theme.stroke
	stroke.Transparency = theme.strokeTransparency
	stroke.Thickness = thickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent

	return stroke
end

return Util
