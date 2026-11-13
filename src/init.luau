--!strict
--!native
--!optimize 2

local Touch = require(script.Touch)

local InputController = {}

-- Mobile controls: thumbsticks, buttons, toggles, touchpads and gestures.
InputController.Touch = Touch

local InputBinds: { [Enum.KeyCode]: any } = {}

function InputController.createAxis(up: string, down: string, left: string, right: string): { string }
	return { up, down, left, right }
end

-- Touch controls passed to bindAxis/bindAction call `action(active, value)`:
-- thumbsticks pass their direction, touchpads their drag delta, and buttons
-- the touch position (toggles pass their on/off state as `active`).
function InputController:bindAxis(action: any, ...: { string } | string | any)
	for _, event in pairs(table.pack(...)) do
		if Touch.isControl(event) then
			event:_bind(action)
		elseif type(event) == "table" then
			local axisDir = { 0, 0, 0, 0 } -- UP, DOWN, LEFT, RIGHT

			for i = 1, 4 do
				local code = Enum.KeyCode:FromName(event[i])

				if not code then
					warn(event[i] .. " is not a valid KeyCode name")

					continue
				end

				InputBinds[code] = function(pressed: boolean)
					axisDir[i] = (pressed and 1) or 0

					action(pressed, Vector3.new(axisDir[4] - axisDir[3], axisDir[1] - axisDir[2]))
				end
			end
		elseif type(event) == "string" then
			local code = Enum.KeyCode:FromName(event)

			if not code then
				warn(event .. " is not a valid KeyCode name")

				continue
			end

			InputBinds[code] = action
		end
	end
end

function InputController:bindAction(action: any, ...: string | any)
	for _, event in pairs(table.pack(...)) do
		if Touch.isControl(event) then
			event:_bind(action)
		elseif type(event) == "string" then
			local code = Enum.KeyCode:FromName(event)

			if not code then
				warn(event .. " is not a valid KeyCode name")

				continue
			end

			InputBinds[code] = action
		end
	end
end

-- Call from InputBegan, InputChanged and InputEnded. Pass gameProcessed so
-- gestures ignore touches that land on other UI.
function InputController:input(inp: InputObject, gameProcessed: boolean?)
	if inp.UserInputType == Enum.UserInputType.Touch then
		Touch.process(inp, gameProcessed)
		return
	end

	if InputBinds[inp.KeyCode] then
		InputBinds[inp.KeyCode](inp.UserInputState ~= Enum.UserInputState.End, inp.Position)
	end
end

return InputController
