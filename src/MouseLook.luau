--!strict
--!native
--!optimize 2

-- Mouse movement as a look source. Reports the same `moved` signal as a
-- touchpad (delta in screen space, y down), so one camera handler can serve
-- both. Mouse input reaches it through RazorInput:input(), which must be
-- called for InputBegan, InputChanged and InputEnded.

local Signal = require(script.Parent.Signal)

export type Button = "MouseButton1" | "MouseButton2" | "MouseButton3"

export type Config = {
	sensitivity: number?,
	-- Only report movement while this mouse button is held (for example
	-- "MouseButton2" for a right-drag camera). Unset reports all movement.
	button: Button?,
	name: string?,
}

local MouseLook = {}
MouseLook.__index = MouseLook

export type MouseLook = typeof(setmetatable(
	{} :: {
		__razorControl: true,
		name: string,
		enabled: boolean,
		destroyed: boolean,
		-- Without `button`: true while enabled. With `button`: true while held.
		active: boolean,
		sensitivity: number,
		-- delta (screen space, y down), position, active
		moved: Signal.Signal<Vector2, Vector2, boolean>,
		_button: Enum.UserInputType?,
		_last: Vector2,
		_actions: { (active: boolean, value: Vector3) -> () },
	},
	MouseLook
))

function MouseLook.new(config: Config): MouseLook
	local button: Enum.UserInputType? = nil
	if config.button then
		button = (Enum.UserInputType :: any)[config.button]
		assert(
			button == Enum.UserInputType.MouseButton1
				or button == Enum.UserInputType.MouseButton2
				or button == Enum.UserInputType.MouseButton3,
			'mouseLook button must be "MouseButton1", "MouseButton2" or "MouseButton3"'
		)
	end

	return setmetatable({
		__razorControl = true :: true,
		name = config.name or "MouseLook",
		enabled = true,
		destroyed = false,
		active = button == nil,
		sensitivity = config.sensitivity or 1,
		moved = Signal.new() :: Signal.Signal<Vector2, Vector2, boolean>,
		_button = button,
		_last = Vector2.zero,
		_actions = {},
	}, MouseLook)
end

function MouseLook._emit(self: MouseLook, delta: Vector2, position: Vector2)
	local active = self.active

	self.moved:fire(delta, position, active)

	local vector = Vector3.new(delta.X, -delta.Y, 0)
	for _, action in self._actions do
		task.spawn(action, active, vector)
	end
end

-- Stop reporting: fires a final zero delta with active = false, like a
-- touchpad when its finger lifts.
function MouseLook._stop(self: MouseLook)
	if not self.active then
		return
	end

	self.active = false
	self:_emit(Vector2.zero, self._last)
end

-- Called by RazorInput:input() for mouse movement and mouse buttons.
function MouseLook._process(self: MouseLook, input: InputObject, gameProcessed: boolean?)
	if not self.enabled then
		return
	end

	local inputType = input.UserInputType

	if inputType == Enum.UserInputType.MouseMovement then
		local position = Vector2.new(input.Position.X, input.Position.Y)
		self._last = position

		if not self.active then
			return
		end

		local delta = Vector2.new(input.Delta.X, input.Delta.Y) * self.sensitivity
		if delta.Magnitude > 0 then
			self:_emit(delta, position)
		end
	elseif inputType == self._button then
		local state = input.UserInputState

		if state == Enum.UserInputState.Begin then
			-- A click on other UI doesn't start looking.
			if not gameProcessed then
				self.active = true
			end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			self:_stop()
		end
	end
end

function MouseLook._bind(self: MouseLook, action: (active: boolean, value: Vector3) -> ())
	table.insert(self._actions, action)
end

function MouseLook._unbind(self: MouseLook, action: (active: boolean, value: Vector3) -> ())
	local index = table.find(self._actions, action)
	if index then
		table.remove(self._actions, index)
	end
end

function MouseLook.setEnabled(self: MouseLook, enabled: boolean)
	if self.destroyed or self.enabled == enabled then
		return
	end

	self.enabled = enabled

	if not enabled then
		self:_stop()
	elseif self._button == nil then
		self.active = true
	end
end

function MouseLook.destroy(self: MouseLook)
	if self.destroyed then
		return
	end

	self:_stop()
	self.destroyed = true
	self.moved:destroy()
	table.clear(self._actions)
end

return MouseLook
