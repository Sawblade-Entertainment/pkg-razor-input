local RazorInput = use("razorinput")

function mod:init()
	RazorInput:bindAction(function(pressed: boolean)
		print("Jump:", pressed)
	end, "Space", "ButtonA")

	RazorInput:bindAxis(function(pressed: boolean, direction: Vector3)
		print("Move:", pressed, direction)
	end, RazorInput.createAxis("W", "S", "A", "D"), RazorInput.createAxis("Up", "Down", "Left", "Right"))
end

function mod:input(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	RazorInput:input(input)
end
