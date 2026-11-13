RazorInput = use "razorinput"
RunService = use "RunService"

-- Mocking InputObject since it cannot be instantiated in Luau/Roblox
type MockInputObject = {
	KeyCode: Enum.KeyCode,
	UserInputType: Enum.UserInputType,
	UserInputState: Enum.UserInputState,
	Position: Vector3,
}

local function createMockInput(keyCode: Enum.KeyCode, state: Enum.UserInputState): MockInputObject
	return {
		KeyCode = keyCode,
		UserInputType = Enum.UserInputType.Keyboard,
		UserInputState = state,
		Position = Vector3.new(0, 0, 0),
	}
end

-- A touch keeps the same InputObject from Begin to End, so tests reuse one
-- mock per finger and mutate it.
local function mockTouch(position: Vector2): MockInputObject
	return {
		KeyCode = Enum.KeyCode.None,
		UserInputType = Enum.UserInputType.Touch,
		UserInputState = Enum.UserInputState.Begin,
		Position = Vector3.new(position.X, position.Y, 0),
	}
end

local function touchBegin(position: Vector2, gameProcessed: boolean?): MockInputObject
	local touch = mockTouch(position)
	RazorInput:input(touch :: any, gameProcessed)

	return touch
end

local function touchMove(touch: MockInputObject, position: Vector2)
	touch.UserInputState = Enum.UserInputState.Change
	touch.Position = Vector3.new(position.X, position.Y, 0)
	RazorInput:input(touch :: any)
end

local function touchEnd(touch: MockInputObject, position: Vector2?)
	touch.UserInputState = Enum.UserInputState.End
	if position then
		touch.Position = Vector3.new(position.X, position.Y, 0)
	end
	RazorInput:input(touch :: any)
end

-- Begin a touch through Touch.process and report whether a control claimed it.
local function claims(position: Vector2): boolean
	local touch = mockTouch(position)
	local claimed = RazorInput.Touch.process(touch :: any)
	touchEnd(touch)

	return claimed
end

local function center(object: GuiObject): Vector2
	return object.AbsolutePosition + object.AbsoluteSize / 2
end

local function near(a: Vector2 | Vector3 | number, b: Vector2 | Vector3 | number): boolean
	if type(a) == "number" then
		return math.abs(a - (b :: number)) < 1e-3
	end

	return ((a :: any) - (b :: any)).Magnitude < 1e-3
end

local function runKeyboardTests()
	-- Test 1: createAxis
	local axis = RazorInput.createAxis("W", "S", "A", "D")
	assert(#axis == 4, "createAxis should return 4 elements")
	assert(
		axis[1] == "W" and axis[2] == "S" and axis[3] == "A" and axis[4] == "D",
		"createAxis returned incorrect strings"
	)
	print("✅ createAxis passed")

	-- Test 2: bindAction
	local actionCalled = false
	local actionValue = false

	RazorInput:bindAction(function(pressed: boolean)
		actionCalled = true
		actionValue = pressed
	end, "Space")

	-- Simulate Press
	RazorInput:input(createMockInput(Enum.KeyCode.Space, Enum.UserInputState.Begin) :: any)
	assert(actionCalled == true, "Action should be called on input")
	assert(actionValue == true, "Action should receive 'true' for pressed")

	-- Simulate Release
	RazorInput:input(createMockInput(Enum.KeyCode.Space, Enum.UserInputState.End) :: any)
	assert(actionValue == false, "Action should receive 'false' for released")
	print("✅ bindAction passed")

	-- Test 3: bindAxis (Single Key)
	local keyCalled = false
	RazorInput:bindAxis(function()
		keyCalled = true
	end, "E")

	RazorInput:input(createMockInput(Enum.KeyCode.E, Enum.UserInputState.Begin) :: any)
	assert(keyCalled == true, "Single key axis bind should trigger")
	print("✅ bindAxis (Single Key) passed")

	-- Test 4: bindAxis (Axis Table/Directional)
	local axisVector = Vector3.new(0, 0, 0)
	local axisPressed = false

	-- Bind W, S, A, D
	RazorInput:bindAxis(function(pressed: boolean, vec: Vector3)
		axisPressed = pressed
		axisVector = vec
	end, axis)

	-- Test Up (W)
	RazorInput:input(createMockInput(Enum.KeyCode.W, Enum.UserInputState.Begin) :: any)
	assert(axisVector == Vector3.new(0, 1, 0), "Pressing W should result in Vector3(0, 1, 0)")
	assert(axisPressed == true, "Axis should be pressed")

	-- Test Right (D) while still holding Up
	RazorInput:input(createMockInput(Enum.KeyCode.D, Enum.UserInputState.Begin) :: any)
	assert(axisVector == Vector3.new(1, 1, 0), "Holding W and D should result in Vector3(1, 1, 0)")

	-- Test Release Up (W) while still holding Right (D)
	RazorInput:input(createMockInput(Enum.KeyCode.W, Enum.UserInputState.End) :: any)
	assert(axisVector == Vector3.new(1, 0, 0), "Releasing W while holding D should result in Vector3(1, 0, 0)")

	-- Test Down (S) while holding Right (D)
	RazorInput:input(createMockInput(Enum.KeyCode.S, Enum.UserInputState.Begin) :: any)
	assert(axisVector == Vector3.new(1, -1, 0), "Holding D and S should result in Vector3(1, -1, 0)")

	print("✅ bindAxis (Directional) passed")

	-- Test 5: Invalid Key Handling (should not crash)
	print("Testing invalid keys (expects warnings in output)...")
	RazorInput:bindAction(function() end, "InvalidKeyName123")
	RazorInput:bindAxis(function() end, { "InvalidKey", "W", "A", "D" })

	-- An invalid key no longer stops the remaining keys from binding.
	local fallbackCalled = false
	RazorInput:bindAction(function()
		fallbackCalled = true
	end, "NotAKey", "Q")
	RazorInput:input(createMockInput(Enum.KeyCode.Q, Enum.UserInputState.Begin) :: any)
	assert(fallbackCalled, "Keys after an invalid key name should still bind")
	print("✅ Invalid Key handling passed (no crash)")
end

local function runTouchTests()
	local Touch = RazorInput.Touch

	Touch.setVisibility("always")
	assert(Touch.isVisible(), "setVisibility('always') should show the controls")

	local stick = Touch.thumbstick({ position = UDim2.fromOffset(200, 300), size = 100, deadzone = 0 })
	local button = Touch.button({ position = UDim2.fromOffset(500, 300), size = 80, text = "A" })
	local toggle = Touch.toggle({ position = UDim2.fromOffset(650, 300), size = 80, text = "Run" })
	local pad = Touch.touchpad({ position = UDim2.fromOffset(3000, 3000), size = UDim2.fromOffset(200, 200) })
	local gestures = Touch.gestures({ longPressTime = 0.2 })

	-- Let the GUI lay out so AbsolutePosition/AbsoluteSize are real.
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()

	-- Thumbstick
	local stickActive, stickVector = false, Vector3.zero
	RazorInput:bindAxis(function(active: boolean, value: Vector3)
		stickActive = active
		stickVector = value
	end, stick)

	local origin = center(stick.base)
	local finger = touchBegin(origin)
	assert(stick.active and stickActive, "Touching the stick should activate it")
	assert(near(stick.value, Vector2.zero), "Touching dead center should read zero")

	touchMove(finger, origin + Vector2.new(50, 0))
	assert(near(stick.value, Vector2.new(1, 0)), "Full right should read (1, 0), got " .. tostring(stick.value))
	assert(near(stickVector, Vector3.new(1, 0, 0)), "bindAxis should receive the stick direction")

	touchMove(finger, origin + Vector2.new(0, -500))
	assert(near(stick.value, Vector2.new(0, 1)), "Dragging up past the edge should clamp to (0, 1)")

	touchMove(finger, origin + Vector2.new(0, 25))
	assert(near(stick.value, Vector2.new(0, -0.5)), "Half down should read (0, -0.5)")

	touchEnd(finger)
	assert(not stick.active and not stickActive, "Releasing should deactivate the stick")
	assert(near(stickVector, Vector3.zero), "Releasing should reset the direction")
	print("✅ Thumbstick passed")

	-- Deadzone
	local deadStick = Touch.thumbstick({ position = UDim2.fromOffset(200, 600), size = 100, deadzone = 0.2 })
	RunService.RenderStepped:Wait()
	local deadOrigin = center(deadStick.base)
	finger = touchBegin(deadOrigin)
	touchMove(finger, deadOrigin + Vector2.new(5, 0))
	assert(near(deadStick.value, Vector2.zero), "Movement inside the deadzone should read zero")
	touchMove(finger, deadOrigin + Vector2.new(30, 0))
	assert(near(deadStick.value, Vector2.new(0.5, 0)), "Deadzone should rescale: 0.6 travel -> 0.5")
	touchEnd(finger)
	deadStick:destroy()
	print("✅ Thumbstick deadzone passed")

	-- Press button
	local pressedLog = {}
	RazorInput:bindAction(function(pressed: boolean)
		table.insert(pressedLog, pressed)
	end, "F", button)

	local buttonFinger = touchBegin(center(button.root))
	assert(button.held and button.on, "Touching the button should press it")

	-- A second finger on the same button keeps it held without re-firing.
	local secondFinger = touchBegin(center(button.root))
	touchEnd(buttonFinger)
	assert(button.on, "Button stays pressed while another finger is on it")
	touchEnd(secondFinger)
	assert(not button.on and not button.held, "Releasing every finger should release the button")
	assert(
		#pressedLog == 2 and pressedLog[1] == true and pressedLog[2] == false,
		"bindAction should see one press and one release"
	)
	print("✅ Button passed")

	-- Toggle
	local toggleLog = {}
	toggle.changed:connect(function(on: boolean)
		table.insert(toggleLog, on)
	end)

	local tap = touchBegin(center(toggle.root))
	touchEnd(tap)
	assert(toggle.on, "First tap should turn the toggle on")
	tap = touchBegin(center(toggle.root))
	touchEnd(tap)
	assert(not toggle.on, "Second tap should turn the toggle off")
	toggle:set(true)
	assert(toggle.on, "set(true) should turn the toggle on")
	toggle:set(false, true)
	assert(
		#toggleLog == 3 and toggleLog[1] == true and toggleLog[2] == false and toggleLog[3] == true,
		"Toggle should fire for taps and set(), but not silent set()"
	)
	print("✅ Toggle passed")

	-- Touchpad
	local padDelta = Vector3.zero
	RazorInput:bindAxis(function(_active: boolean, delta: Vector3)
		padDelta = delta
	end, pad)

	local padCenter = center(pad.root)
	local padFinger = touchBegin(padCenter)
	assert(pad.active, "Touching the pad should activate it")
	touchMove(padFinger, padCenter + Vector2.new(10, 5))
	assert(near(padDelta, Vector3.new(10, -5, 0)), "Touchpad delta should be (10, -5), got " .. tostring(padDelta))
	touchEnd(padFinger)
	assert(not pad.active, "Releasing should deactivate the pad")
	print("✅ Touchpad passed")

	-- Gestures (well away from every control)
	local events = {}
	gestures.tap:connect(function()
		table.insert(events, "tap")
	end)
	gestures.doubleTap:connect(function()
		table.insert(events, "doubleTap")
	end)
	gestures.longPress:connect(function()
		table.insert(events, "longPress")
	end)

	local swipeDirection = nil
	gestures.swipe:connect(function(direction: string)
		swipeDirection = direction
	end)

	local panStates = {}
	gestures.pan:connect(function(_delta: Vector2, _position: Vector2, state: string)
		table.insert(panStates, state)
	end)

	local pinchScale, rotateAngle = 1, 0
	gestures.pinch:connect(function(scale: number)
		pinchScale = scale
	end)
	gestures.rotate:connect(function(angle: number)
		rotateAngle = angle
	end)

	local free = Vector2.new(5000, 5000)

	assert(not claims(free), "A touch off every control should not be claimed")
	task.wait(0.35) -- let that tap's double-tap window close
	table.clear(events)

	tap = touchBegin(free)
	touchEnd(tap)
	tap = touchBegin(free)
	touchEnd(tap)
	assert(table.concat(events, ",") == "tap,tap,doubleTap", "Two taps should fire tap, tap, doubleTap")
	print("✅ Tap / double tap passed")

	table.clear(events)
	local hold = touchBegin(free + Vector2.new(400, 0))
	task.wait(0.35)
	touchEnd(hold)
	assert(table.concat(events, ",") == "longPress", "Holding still should fire only longPress")
	print("✅ Long press passed")

	local swipe = touchBegin(free)
	touchMove(swipe, free + Vector2.new(40, 2))
	touchMove(swipe, free + Vector2.new(120, 4))
	touchEnd(swipe)
	assert(swipeDirection == "Right", "A fast drag right should swipe Right")
	assert(table.concat(panStates, ",") == "began,changed,ended", "Dragging should pan began/changed/ended")
	print("✅ Swipe / pan passed")

	local a = touchBegin(free)
	local b = touchBegin(free + Vector2.new(100, 0))
	touchMove(b, free + Vector2.new(200, 0))
	assert(near(pinchScale, 2), "Doubling finger distance should pinch to 2, got " .. pinchScale)
	touchMove(b, free + Vector2.new(0, 200))
	assert(near(rotateAngle, math.pi / 2), "Quarter turn clockwise should rotate pi/2, got " .. rotateAngle)
	table.clear(events)
	touchEnd(b)
	touchEnd(a)
	assert(#events == 0, "Fingers from a pinch should not fire taps")
	print("✅ Pinch / rotate passed")

	-- Touches that land on other game UI are ignored by gestures.
	table.clear(events)
	tap = touchBegin(free, true)
	touchEnd(tap)
	assert(#events == 0, "gameProcessed touches should not reach gestures")
	print("✅ gameProcessed passthrough passed")

	-- Disabled and hidden controls don't claim touches.
	button:setEnabled(false)
	assert(not claims(center(button.root)), "A disabled button should not claim touches")
	button:setEnabled(true)
	assert(claims(center(button.root)), "A re-enabled button should claim touches")

	Touch.setVisibility("never")
	assert(not Touch.isVisible(), "setVisibility('never') should hide the controls")
	assert(not claims(center(stick.root)), "Hidden controls should not claim touches")
	print("✅ Visibility passed")

	-- Custom images
	Touch.setVisibility("always")

	local artA = "rbxasset://textures/face.png"
	local artB = "rbxasset://textures/ui/GuiImagePlaceholder.png"
	local artC = "rbxasset://textures/loading/robloxTilt.png"

	local imageStick = Touch.thumbstick({ position = UDim2.fromOffset(200, 900), baseImage = artA, knobImage = artB })
	local imageButton = Touch.button({
		position = UDim2.fromOffset(500, 900),
		backgroundImage = artA,
		pressedImage = artB,
		image = artC,
	})
	local tintToggle = Touch.toggle({ position = UDim2.fromOffset(650, 900), backgroundImage = artA })
	local swapToggle = Touch.toggle({ position = UDim2.fromOffset(800, 900), backgroundImage = artA, onImage = artC })
	local tintedIcon = Touch.button({ position = UDim2.fromOffset(950, 900), image = artC, iconColor = Color3.new(1, 0, 0) })
	RunService.RenderStepped:Wait()

	local imageBase, imageKnob = imageStick.base :: any, imageStick.knob :: any
	assert(imageBase:IsA("ImageLabel") and imageBase.Image == artA, "baseImage should draw the base as that image")
	assert(imageKnob:IsA("ImageLabel") and imageKnob.Image == artB, "knobImage should draw the knob as that image")
	assert(not imageBase:FindFirstChildOfClass("UIStroke"), "Image bases should not get the default outline")
	local imageOrigin = center(imageStick.base)
	finger = touchBegin(imageOrigin)
	touchMove(finger, imageOrigin + Vector2.new(70, 0))
	assert(near(imageStick.value.Unit, Vector2.new(1, 0)), "An image stick should still steer")
	touchEnd(finger)
	print("✅ Thumbstick images passed")

	local buttonVisual = imageButton.visual :: any
	assert(buttonVisual:IsA("ImageLabel") and buttonVisual.Image == artA, "backgroundImage should draw the button")
	finger = touchBegin(center(imageButton.root))
	assert(buttonVisual.Image == artB, "pressedImage should show while held")
	touchEnd(finger)
	assert(buttonVisual.Image == artA, "Releasing should restore backgroundImage")
	local icon = imageButton.icon :: ImageLabel
	assert(icon.Image == artC and icon.ImageColor3 == Color3.new(1, 1, 1), "Icons are untinted by default")
	imageButton:setIcon(artB)
	assert(icon.Image == artB, "setIcon should swap the icon")
	assert((tintedIcon.icon :: ImageLabel).ImageColor3 == Color3.new(1, 0, 0), "iconColor should tint the icon")
	print("✅ Button images passed")

	local tintVisual = tintToggle.visual :: any
	tap = touchBegin(center(tintToggle.root))
	assert(tintVisual.Image == artA, "Without onImage, a toggle keeps its background image")
	assert(tintVisual.ImageColor3 ~= Color3.new(1, 1, 1), "A held toggle should be shaded")
	touchEnd(tap)
	assert(tintVisual.ImageColor3 == Touch.theme.accent, "Without onImage, an on toggle is tinted with the accent")
	tintToggle:set(false)
	assert(tintVisual.ImageColor3 == Color3.new(1, 1, 1), "An off toggle is untinted")

	local swapVisual = swapToggle.visual :: any
	tap = touchBegin(center(swapToggle.root))
	touchEnd(tap)
	assert(swapVisual.Image == artC and swapVisual.ImageColor3 == Color3.new(1, 1, 1), "onImage should show while on")
	swapToggle:setImages(artB, nil, artA)
	assert(swapVisual.Image == artA, "setImages should swap the on image")
	swapToggle:set(false)
	assert(swapVisual.Image == artB, "setImages should swap the background image")
	print("✅ Toggle images passed")

	for _, control in { imageStick, imageButton, tintToggle, swapToggle, tintedIcon } :: { any } do
		control:destroy()
	end

	for _, control in { stick, button, toggle, pad, gestures } :: { any } do
		control:destroy()
	end
	Touch.setVisibility("auto")
end

function mod:start()
	print("Starting RazorInput tests...")

	local success, err = pcall(function()
		runKeyboardTests()
		runTouchTests()
	end)

	if not success then
		warn("❌ Tests failed: " .. tostring(err))
		return
	end

	print("---------------------------------")
	print("All tests passed successfully!")
end
