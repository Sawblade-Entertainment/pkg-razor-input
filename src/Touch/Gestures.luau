--!strict
--!native
--!optimize 2

-- Gesture recognizer for touches that did not land on a control (or on other
-- game UI). Positions are screen pixels with y pointing down.
--
--   tap(position)                    each quick touch-and-release
--   doubleTap(position)              second tap within `doubleTapTime`
--   longPress(position)              finger held still for `longPressTime`
--   swipe(direction, delta, speed)   fast flick; direction is "Up" | "Down" | "Left" | "Right"
--   pan(delta, position, state)      one-finger drag; state is "began" | "changed" | "ended"
--   pinch(scale, deltaScale, center) two fingers; scale is relative to when the pinch started
--   rotate(angle, deltaAngle, center) two fingers; radians, clockwise on screen is positive

local Signal = require(script.Parent.Parent.Signal)

export type Config = {
	-- Max time and movement for a touch to count as a tap.
	tapTime: number?,
	tapDistance: number?,
	doubleTapTime: number?,
	longPressTime: number?,
	-- Min movement and max time for a release to count as a swipe.
	swipeDistance: number?,
	swipeTime: number?,
	-- Only start tracking touches inside this object (default: whole screen).
	region: GuiObject?,
}

export type SwipeDirection = "Up" | "Down" | "Left" | "Right"
export type PanState = "began" | "changed" | "ended"

type TouchState = {
	start: Vector2,
	position: Vector2,
	startTime: number,
	moved: boolean,
	panning: boolean,
	longPressed: boolean,
	-- Part of a two-finger gesture; never ends as a tap or swipe.
	consumed: boolean,
	longPressThread: thread?,
}

type MultiState = {
	a: any,
	b: any,
	startDistance: number,
	lastDistance: number,
	startAngle: number,
	lastAngle: number,
}

local Gestures = {}
Gestures.__index = Gestures

export type Gestures = typeof(setmetatable(
	{} :: {
		enabled: boolean,
		destroyed: boolean,
		tap: Signal.Signal<Vector2>,
		doubleTap: Signal.Signal<Vector2>,
		longPress: Signal.Signal<Vector2>,
		swipe: Signal.Signal<SwipeDirection, Vector2, number>,
		pan: Signal.Signal<Vector2, Vector2, PanState>,
		pinch: Signal.Signal<number, number, Vector2>,
		rotate: Signal.Signal<number, number, Vector2>,
		_config: {
			tapTime: number,
			tapDistance: number,
			doubleTapTime: number,
			longPressTime: number,
			swipeDistance: number,
			swipeTime: number,
		},
		_region: GuiObject?,
		_touches: { [any]: TouchState },
		_order: { any },
		_multi: MultiState?,
		_lastTapTime: number,
		_lastTapPosition: Vector2,
	},
	Gestures
))

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

function Gestures.new(config: Config): Gestures
	return setmetatable({
		enabled = true,
		destroyed = false,
		tap = Signal.new() :: Signal.Signal<Vector2>,
		doubleTap = Signal.new() :: Signal.Signal<Vector2>,
		longPress = Signal.new() :: Signal.Signal<Vector2>,
		swipe = Signal.new() :: Signal.Signal<SwipeDirection, Vector2, number>,
		pan = Signal.new() :: Signal.Signal<Vector2, Vector2, PanState>,
		pinch = Signal.new() :: Signal.Signal<number, number, Vector2>,
		rotate = Signal.new() :: Signal.Signal<number, number, Vector2>,
		_config = {
			tapTime = config.tapTime or 0.25,
			tapDistance = config.tapDistance or 12,
			doubleTapTime = config.doubleTapTime or 0.3,
			longPressTime = config.longPressTime or 0.5,
			swipeDistance = config.swipeDistance or 60,
			swipeTime = config.swipeTime or 0.3,
		},
		_region = config.region,
		_touches = {},
		_order = {},
		_multi = nil,
		_lastTapTime = -math.huge,
		_lastTapPosition = Vector2.zero,
	}, Gestures)
end

local function cancelLongPress(touch: TouchState)
	if touch.longPressThread then
		pcall(task.cancel, touch.longPressThread)
		touch.longPressThread = nil
	end
end

function Gestures._began(self: Gestures, input: InputObject, position: Vector2)
	if not self.enabled or self._touches[input] then
		return
	end

	local region = self._region
	if region then
		local topLeft = region.AbsolutePosition
		local bottomRight = topLeft + region.AbsoluteSize
		if
			position.X < topLeft.X
			or position.Y < topLeft.Y
			or position.X > bottomRight.X
			or position.Y > bottomRight.Y
		then
			return
		end
	end

	local touch: TouchState = {
		start = position,
		position = position,
		startTime = os.clock(),
		moved = false,
		panning = false,
		longPressed = false,
		consumed = false,
		longPressThread = nil,
	}

	self._touches[input] = touch
	table.insert(self._order, input)

	local count = #self._order

	if count == 1 then
		touch.longPressThread = task.delay(self._config.longPressTime, function()
			touch.longPressThread = nil

			if self._touches[input] == touch and not touch.moved and not touch.consumed then
				touch.longPressed = true
				self.longPress:fire(touch.position)
			end
		end)
	elseif count == 2 then
		-- A second finger turns this into a pinch/rotate; neither finger can
		-- become a tap, swipe or long press any more.
		for _, key in self._order do
			local other = self._touches[key]
			cancelLongPress(other)
			other.consumed = true

			if other.panning then
				other.panning = false
				self.pan:fire(Vector2.zero, other.position, "ended")
			end
		end

		local a = self._touches[self._order[1]].position
		local b = position
		local offset = b - a
		local distance = math.max(offset.Magnitude, 1)
		local angle = math.atan2(offset.Y, offset.X)

		self._multi = {
			a = self._order[1],
			b = input,
			startDistance = distance,
			lastDistance = distance,
			startAngle = angle,
			lastAngle = angle,
		}
	else
		touch.consumed = true
	end
end

function Gestures._moved(self: Gestures, input: InputObject, position: Vector2)
	local touch = self._touches[input]
	if not touch then
		return
	end

	local delta = position - touch.position
	touch.position = position

	if not touch.moved and (position - touch.start).Magnitude > self._config.tapDistance then
		touch.moved = true
		cancelLongPress(touch)
	end

	local multi = self._multi
	if multi and (input == multi.a or input == multi.b) then
		local a = self._touches[multi.a].position
		local b = self._touches[multi.b].position
		local offset = b - a
		local center = (a + b) / 2
		local distance = math.max(offset.Magnitude, 1)
		local angle = math.atan2(offset.Y, offset.X)

		if distance ~= multi.lastDistance then
			local deltaScale = distance / multi.lastDistance
			multi.lastDistance = distance
			self.pinch:fire(distance / multi.startDistance, deltaScale, center)
		end

		if angle ~= multi.lastAngle then
			local deltaAngle = wrapAngle(angle - multi.lastAngle)
			multi.lastAngle = angle
			self.rotate:fire(wrapAngle(angle - multi.startAngle), deltaAngle, center)
		end

		return
	end

	if touch.consumed or not touch.moved then
		return
	end

	if not touch.panning then
		touch.panning = true
		self.pan:fire(position - touch.start, position, "began")
	elseif delta.Magnitude > 0 then
		self.pan:fire(delta, position, "changed")
	end
end

function Gestures._ended(self: Gestures, input: InputObject?, position: Vector2?)
	if input == nil then
		self:_reset()
		return
	end

	local touch = self._touches[input]
	if not touch then
		return
	end

	local finalPosition = position or touch.position

	self._touches[input] = nil
	table.remove(self._order, table.find(self._order, input) :: number)
	cancelLongPress(touch)

	local multi = self._multi
	if multi and (input == multi.a or input == multi.b) then
		self._multi = nil
	end

	if touch.panning then
		self.pan:fire(Vector2.zero, finalPosition, "ended")
	end

	if touch.consumed or touch.longPressed then
		return
	end

	local now = os.clock()
	local elapsed = now - touch.startTime
	local travel = finalPosition - touch.start
	local config = self._config

	if not touch.moved and elapsed <= config.tapTime then
		self.tap:fire(finalPosition)

		local isDouble = now - self._lastTapTime <= config.doubleTapTime
			and (finalPosition - self._lastTapPosition).Magnitude <= config.tapDistance * 3

		if isDouble then
			self._lastTapTime = -math.huge
			self.doubleTap:fire(finalPosition)
		else
			self._lastTapTime = now
			self._lastTapPosition = finalPosition
		end
	elseif elapsed <= config.swipeTime and travel.Magnitude >= config.swipeDistance then
		local direction: SwipeDirection
		if math.abs(travel.X) >= math.abs(travel.Y) then
			direction = if travel.X > 0 then "Right" else "Left"
		else
			direction = if travel.Y > 0 then "Down" else "Up"
		end

		self.swipe:fire(direction, travel, travel.Magnitude / math.max(elapsed, 1e-3))
	end
end

-- Drop every tracked touch, closing any open pan.
function Gestures._reset(self: Gestures)
	for _, touch in self._touches do
		cancelLongPress(touch)

		if touch.panning then
			self.pan:fire(Vector2.zero, touch.position, "ended")
		end
	end

	table.clear(self._touches)
	table.clear(self._order)
	self._multi = nil
end

function Gestures.setEnabled(self: Gestures, enabled: boolean)
	self.enabled = enabled

	if not enabled then
		self:_reset()
	end
end

function Gestures.destroy(self: Gestures)
	if self.destroyed then
		return
	end

	self:_reset()
	self.destroyed = true

	for _, signal in { self.tap, self.doubleTap, self.longPress } do
		signal:destroy()
	end
	self.swipe:destroy()
	self.pan:destroy()
	self.pinch:destroy()
	self.rotate:destroy()
end

return Gestures
