RazorInput = use "razorinput"

-- Mocking InputObject since it cannot be instantiated in Luau/Roblox
type MockInputObject = {
	KeyCode: Enum.KeyCode,
	UserInputState: Enum.UserInputState,
	Position: Vector3,
}

local function createMockInput(keyCode: Enum.KeyCode, state: Enum.UserInputState): MockInputObject
	return {
		KeyCode = keyCode,
		UserInputState = state,
		Position = Vector3.new(0, 0, 0),
	}
end

local function runTests()
	print("Starting RazorInput tests...")

	-- Test 1: createAxis
	local axis = RazorInput.createAxis("W", "S", "A", "D")
	assert(#axis == 4, "createAxis should return 4 elements")
	assert(axis[1] == "W" and axis[2] == "S" and axis[3] == "A" and axis[4] == "D", "createAxis returned incorrect strings")
	print("✅ createAxis passed")

	-- Test 2: bindAction
	local actionCalled = false
	local actionValue = false
	
	RazorInput:bindAction(function(pressed: boolean)
		actionCalled = true
		actionValue = pressed
	end, "Space")

	-- Simulate Press
	RazorInput:input(createMockInput(Enum.KeyCode.Space, Enum.UserInputState.Begin))
	assert(actionCalled == true, "Action should be called on input")
	assert(actionValue == true, "Action should receive 'true' for pressed")

	-- Simulate Release
	RazorInput:input(createMockInput(Enum.KeyCode.Space, Enum.UserInputState.End))
	assert(actionValue == false, "Action should receive 'false' for released")
	print("✅ bindAction passed")

	-- Test 3: bindAxis (Single Key)
	local keyCalled = false
	RazorInput:bindAxis(function()
		keyCalled = true
	end, "E")

	RazorInput:input(createMockInput(Enum.KeyCode.E, Enum.UserInputState.Begin))
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
	RazorInput:input(createMockInput(Enum.KeyCode.W, Enum.UserInputState.Begin))
	assert(axisVector == Vector3.new(0, 1, 0), "Pressing W should result in Vector3(0, 1, 0)")
	assert(axisPressed == true, "Axis should be pressed")

	-- Test Right (D) while still holding Up
	RazorInput:input(createMockInput(Enum.KeyCode.D, Enum.UserInputState.Begin))
	assert(axisVector == Vector3.new(1, 1, 0), "Holding W and D should result in Vector3(1, 1, 0)")

	-- Test Release Up (W) while still holding Right (D)
	RazorInput:input(createMockInput(Enum.KeyCode.W, Enum.UserInputState.End))
	assert(axisVector == Vector3.new(1, 0, 0), "Releasing W while holding D should result in Vector3(1, 0, 0)")

	-- Test Down (S) while holding Right (D)
	RazorInput:input(createMockInput(Enum.KeyCode.S, Enum.UserInputState.Begin))
	assert(axisVector == Vector3.new(1, -1, 0), "Holding D and S should result in Vector3(1, -1, 0)")
	
	print("✅ bindAxis (Directional) passed")

	-- Test 5: Invalid Key Handling (should not crash)
	print("Testing invalid keys (expects warnings in output)...")
	RazorInput:bindAction(function() end, "InvalidKeyName123")
	RazorInput:bindAxis(function() end, {"InvalidKey", "W", "A", "D"})
	print("✅ Invalid Key handling passed (no crash)")

	print("---------------------------------")
	print("All tests passed successfully!")
end

-- Run the suite
local success, err = pcall(runTests)
if not success then
	warn("❌ Tests failed: " .. tostring(err))
end
