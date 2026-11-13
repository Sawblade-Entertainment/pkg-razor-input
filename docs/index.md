# Razor Input

Dead simple input handling for Roblox.

## Installation

Install via Wally:

```toml
RazorInput = "vibeonline/razorinput@0.1.6"
```

## Quick Start

```lua
local RazorInput = require(path.to.RazorInput)

-- Bind a simple action to a key
RazorInput:bindAction(function(pressed)
    print("Space pressed:", pressed)
end, "Space")

-- Bind an axis (e.g., Movement)
local moveAxis = RazorInput.createAxis("W", "S", "A", "D")
RazorInput:bindAxis(function(pressed, direction)
    print("Moving direction:", direction)
end, moveAxis)

-- Connect to UserInputService (InputChanged is needed for touch controls)
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    RazorInput:input(input, gameProcessed)
end)
UserInputService.InputChanged:Connect(function(input, gameProcessed)
    RazorInput:input(input, gameProcessed)
end)
UserInputService.InputEnded:Connect(function(input, gameProcessed)
    RazorInput:input(input, gameProcessed)
end)
```

In a ChainLink controller, the bootstrapper already forwards all three:

```lua
function mod:input(input, gameProcessed)
    RazorInput:input(input, gameProcessed)
end
```

## API Reference

### `InputController`

#### `createAxis(up: string, down: string, left: string, right: string): { string }`
Creates an axis definition for 4-way movement.
- **Returns**: A table containing the key names.

#### `bindAxis(action: (pressed: boolean, direction: Vector3) -> (), ...: { string } | string | Control)`
Binds one or more inputs to an axis action.
- If a table (from `createAxis`) is passed, it calculates a `Vector3` direction based on the pressed keys of that axis.
- Touch controls can be passed too: a thumbstick sends its direction, a touchpad its drag delta (see [Mobile controls](#mobile-controls)).
- `action` is called with `(pressed, direction)`.

#### `bindAction(action: (pressed: boolean, position: Vector3?) -> (), ...: string | Control)`
Binds one or more keys (or touch buttons) to a specific action.
- **action**: A callback function receiving `pressed` (boolean) and the input `position` (Vector3).
- Key names are `Enum.KeyCode` names (`"Space"`, `"ButtonR2"`) or [mouse input names](#mouse-buttons-and-wheel).
- Invalid key names are skipped with a warning; the remaining keys still bind.

#### `input(inp: InputObject, gameProcessed: boolean?)`
The entry point for processing input. Call it from `UserInputService.InputBegan`, `InputChanged` and `InputEnded`. Touch inputs are routed to `RazorInput.Touch` and mouse movement to [mouse looks](#mouse-look). Pass `gameProcessed` so gestures ignore touches on other UI, and clicks or scrolling over other UI don't reach mouse binds.

### Mouse buttons and wheel

Mouse buttons and the scroll wheel bind by name wherever a key name goes: `bindAction`, `bindAxis`, `createAxis` and a layout's `keys`.

```lua
RazorInput:bindAction("Fire", onFire, "MouseButton1", "ButtonR2")
RazorInput:bindAction("Aim", onAim, "MouseButton2", "ButtonL2")

RazorInput:bindAxis("Zoom", function(pressed, value)
    if pressed then
        camera:zoom(value.Y) -- +1 scrolling up, -1 scrolling down
    end
end, "MouseWheel")

RazorInput:bindAction("NextWeapon", onNext, "MouseWheelUp", "ButtonR1")
```

| Name | Behaves like |
|---|---|
| `MouseButton1`, `MouseButton2`, `MouseButton3` | A key: `action(true, position)` on press, `action(false, position)` on release. `MouseLeftButton`, `MouseRightButton` and `MouseMiddleButton` also work. |
| `MouseWheel` | A tap on every scroll step: `action(true, Vector3.new(0, scroll, 0))` then `action(false, Vector3.zero)`. `scroll` is positive scrolling up. |
| `MouseWheelUp`, `MouseWheelDown` | A tap on each step in that direction, with the same value as `MouseWheel`. |

- A press that lands on other UI (`gameProcessed`) is ignored, and so is its release. Scrolling over UI (a `ScrollingFrame`, say) is ignored too.
- Wheel names fit in axes: `createAxis("MouseWheelUp", "MouseWheelDown", "Z", "X")` gives `y = 1` or `-1` for one step, then `0`.
- Mouse buttons still reach any [mouse look](#mouse-look) whose `button` they match, as well as their bind.

#### `mouseLook(config?): MouseLook`
A look source that reports mouse movement with the same `moved` signal as a touchpad. See [Mouse look](#mouse-look).

#### `device(): "KeyboardMouse" | "Touch" | "Gamepad"` and `deviceChanged`
The kind of input the player last used, and a signal fired with the new value when it changes. See [Device detection](#device-detection).

## Mouse look

`RazorInput.mouseLook()` turns mouse movement into a look source shaped exactly like a [touchpad](#touchtouchpadconfig): the same `moved(delta, position, active)` signal with `delta` in screen space (y down), and the same `action(active, Vector3.new(delta.X, -delta.Y, 0))` when bound. One camera handler then serves PC and mobile:

```lua
local function onLook(delta: Vector2, _position: Vector2, _active: boolean)
    camera:rotate(delta)
end

RazorInput.mouseLook({ sensitivity = 0.3 }).moved:connect(onLook)
RazorInput.Touch.touchpad({ name = "Look", sensitivity = 0.4 }).moved:connect(onLook)
```

Or bind both to one axis:

```lua
local mouse = RazorInput.mouseLook({ sensitivity = 0.3 })
local pad = RazorInput.Touch.touchpad({ name = "Look" })

RazorInput:bindAxis("Look", function(active, delta)
    camera:rotate(Vector2.new(delta.X, -delta.Y))
end, mouse, pad)
```

| Option | Default | Description |
|---|---|---|
| `sensitivity` | `1` | Multiplier for the reported delta |
| `button` | none | `"MouseButton1"`, `"MouseButton2"` or `"MouseButton3"`: only report movement while it is held (a right-drag camera). A press that lands on other UI (`gameProcessed`) doesn't start looking. |
| `name` | `"MouseLook"` | Name for your own bookkeeping |

- `look.active` — without `button`, `true` while enabled; with `button`, `true` while it is held.
- When the button is released, or the look is disabled or destroyed, `moved` fires once more with a zero delta and `active = false`, like a touchpad when the finger lifts.
- `look:setEnabled(enabled)` and `look:destroy()`.
- Mouse movement only reaches the look through `RazorInput:input()` from `InputChanged`, so forward all three events.
- The delta is the raw `InputObject.Delta`, which works whether or not the mouse is locked. Locking the cursor (`UserInputService.MouseBehavior`) stays up to your camera code.

## Device detection

```lua
local function showPrompts(device)
    -- "KeyboardMouse", "Touch" or "Gamepad"
    hud:setPrompts(device)
end

showPrompts(RazorInput:device())
RazorInput.deviceChanged:connect(showPrompts)
```

The device follows `UserInputService.LastInputTypeChanged`: touch is `"Touch"`, any gamepad is `"Gamepad"`, and keyboard, mouse and text input are `"KeyboardMouse"`. Inputs that don't say which device is in use (window focus, gyro, accelerometer) leave it unchanged. Before the first input it is guessed from the hardware: a touch screen without a mouse is `"Touch"`, a gamepad without a keyboard is `"Gamepad"`, anything else `"KeyboardMouse"`. `deviceChanged` fires only when the value changes.

Touch controls decide their own visibility (see [Visibility](#visibility)); `device()` doesn't affect them.

## Layouts

A layout is a named control scheme: which keys trigger each bind, and where each touch control sits. Players can switch between layouts at any time, and you can build new ones at runtime (for example from a settings menu).

Give a bind a name as its first argument to make it layout-aware. The keys and controls you pass are the **`"Default"`** layout:

```lua
local Touch = RazorInput.Touch

local stick = Touch.thumbstick({ name = "Move" })
local jump = Touch.button({ name = "Jump", text = "Jump" })
local look = Touch.touchpad({ name = "Look" })

RazorInput:bindAxis("Move", onMove, RazorInput.createAxis("W", "S", "A", "D"), stick)
RazorInput:bindAction("Jump", onJump, "Space", "ButtonA", jump)
```

Create another layout. `keys` is keyed by **bind name**, `touch` by **control name** (the control's `name` option). Anything a layout leaves out keeps its `"Default"` keys and placement.

```lua
RazorInput:createLayout("Left-handed", {
    keys = {
        Move = { RazorInput.createAxis("Up", "Down", "Left", "Right") },
        Jump = { "RightControl", "ButtonA" },
    },
    touch = {
        Move = { position = UDim2.new(1, -110, 1, -110) },
        Jump = { position = UDim2.new(0, 80, 1, -80), size = 90 },
        Look = { position = UDim2.fromScale(0, 0), size = UDim2.fromScale(0.55, 1) },
    },
})

RazorInput:setLayout("Left-handed")
RazorInput:setLayout("Default")
```

To let players customise a layout, start from a filled-in copy, change it, and save it under a name:

```lua
local layout = RazorInput:getLayout() -- the active layout, with Default filled in
layout.keys.Jump = { "F" }
layout.touch.Jump.size = 110
RazorInput:createLayout("Custom", layout)
RazorInput:setLayout("Custom")
```

| Function | Description |
|---|---|
| `bindAction(name, action, ...)` / `bindAxis(name, action, ...)` | Named bind. Binding the same name again replaces it. |
| `unbind(name)` | Remove a named bind: its keys and touch controls stop calling its action. |
| `createLayout(name, layout)` | Add or replace a layout. Replacing the active layout re-applies it. `"Default"` can't be replaced. |
| `setLayout(name)` | Switch every named bind's keys and every touch control's placement. Keys held at the time are released (the action gets `false`). |
| `removeLayout(name)` | Delete a layout; removing the active one switches to `"Default"`. |
| `currentLayout(): string` | Name of the active layout. |
| `getLayouts(): { string }` | Every layout name, `"Default"` first. |
| `getLayout(name?): Layout?` | A copy of a layout (active one by default) with everything it leaves out filled in from `"Default"`. |
| `layoutChanged` | Signal fired with the layout name when `setLayout` switches layouts. |

A layout's `keys` entry lists key names and/or `createAxis` tables, just like the bind's own arguments; `{}` leaves the bind with no keys. A `touch` placement can set:

| Key | Applies to | Description |
|---|---|---|
| `position` | all | `UDim2`, same meaning as the control's `position` option |
| `size` | all | Pixels (`number`) for buttons and thumbsticks, `UDim2` for touchpads |
| `zone` | dynamic thumbsticks | `{ position: UDim2, size: UDim2 }` |
| `anchorPoint` | touchpads | `Vector2` |
| `visible` | all | `false` hides the control and stops it taking touches |

Notes:
- Controls are matched by `name`, so give each control you want to place a unique name. Controls created after `setLayout` pick up the active layout.
- Unnamed binds (`bindAction(action, ...)`) work as before and ignore layouts.
- A key drives one bind at a time; the last bind to claim it wins.
- `visible = false` is separate from `setEnabled`: a control shows only when it is enabled *and* the layout shows it.

## Mobile controls

`RazorInput.Touch` builds on-screen controls and recognizes gestures. Controls only receive touches that you forward through `RazorInput:input()`, including `InputChanged`.

```lua
local Touch = RazorInput.Touch

Touch.setDefaultControlsEnabled(false) -- hide Roblox's own thumbstick and jump button

local stick = Touch.thumbstick({ dynamic = true })
local jump = Touch.button({ text = "Jump" })
local sprint = Touch.toggle({ text = "Run", position = UDim2.new(1, -170, 1, -80) })
local look = Touch.touchpad({ sensitivity = 0.4 })
local gestures = Touch.gestures()

-- The same callback serves keyboard and touch
RazorInput:bindAxis(function(active, direction)
    print("Move", direction)
end, RazorInput.createAxis("W", "S", "A", "D"), stick)

RazorInput:bindAction(function(pressed)
    print("Jump", pressed)
end, "Space", jump)

sprint.changed:connect(function(on)
    print("Sprint", on)
end)

look.moved:connect(function(delta)
    print("Look", delta)
end)

gestures.pinch:connect(function(scale, deltaScale, center)
    print("Zoom", deltaScale)
end)
```

### How touches are routed

Each new touch is offered to the controls first: buttons (priority 30), then thumbsticks (20), then touchpads (10), newest first within a priority. The control that takes a touch owns it until the finger lifts, even if the finger slides off. Touches that no control takes, and that didn't land on other game UI, go to every gesture recognizer.

Controls sink input, so the default camera doesn't rotate when a finger is on them.

### Visibility

| Function | Description |
|---|---|
| `Touch.setVisibility(mode)` | `"auto"` (default) shows controls while the player is using touch; `"always"` / `"never"` force it. Hiding releases every held control. |
| `Touch.isVisible()` | Whether the controls are currently shown. |
| `Touch.setDefaultControlsEnabled(enabled)` | Show or hide Roblox's built-in touch thumbstick and jump button. |
| `Touch.gui()` | The `RazorTouch` ScreenGui the controls live in (created on first use). |
| `Touch.releaseAll()` | Let go of every held control and gesture in progress. |
| `Touch.process(input, gameProcessed?)` | Route one touch directly; returns `true` if a control took it. `RazorInput:input()` calls this for you. |

### Shared options and methods

Every control accepts `name`, `priority`, `parent` (a `GuiBase2d` to place it in instead of `Touch.gui()`) and `theme` (overrides for keys of `Touch.theme`). Every control has `setEnabled(enabled)` and `destroy()`, and exposes its hit area as `root`.

Change `Touch.theme` before creating controls to restyle all of them:

| Key | Default |
|---|---|
| `base`, `baseTransparency` | near-black, `0.45` |
| `stroke`, `strokeTransparency` | white, `0.7` |
| `knob`, `knobTransparency` | near-white, `0.1` |
| `accent` | blue, used for pressed toggles |
| `text`, `font` | near-white, Builder Sans Bold |

### `Touch.thumbstick(config?)`

| Option | Default | Description |
|---|---|---|
| `position` | bottom-left | Center of the stick (static) or its resting spot (dynamic) |
| `size` | `140` | Base diameter in pixels |
| `knobScale` | `0.45` | Knob diameter as a fraction of the base |
| `deadzone` | `0.12` | Travel below this reads as zero; the rest is rescaled to 0–1 |
| `hitScale` | `1.35` | Touchable area around a static stick, as a multiple of `size` |
| `dynamic` | `false` | Stick appears where the finger lands inside `zone` |
| `zone` | left 45%, bottom 70% | `{ position: UDim2, size: UDim2 }` for dynamic sticks |
| `follow` | `true` | Dynamic: the base follows a finger that drags past the edge |
| `hideWhenIdle` | `false` | Dynamic: hide the stick while it isn't held |
| `baseImage` | none | Image drawn untinted in place of the base circle (no outline) |
| `knobImage` | none | Image drawn untinted in place of the knob circle |

- `stick.base` / `stick.knob` — a `Frame`, or an `ImageLabel` when the matching image is set.
- `stick.value: Vector2` — x right, y **up**, magnitude 0–1.
- `stick.active: boolean`
- `stick.changed:connect(function(value: Vector2, active: boolean) end)`
- With `bindAxis` / `bindAction`: `action(active, Vector3.new(value.X, value.Y, 0))`, matching keyboard axes.

### `Touch.button(config?)` and `Touch.toggle(config?)`

| Option | Default | Description |
|---|---|---|
| `position` | bottom-right | Center of the button |
| `size` | `72` | Diameter (or side length) in pixels |
| `shape` | `"circle"` | `"circle"` or `"rounded"` |
| `text` / `image` | none | Label text and/or icon image |
| `iconColor` | none | Icon tint; unset keeps the icon's own colours |
| `backgroundImage` | none | Image drawn in place of the circle (no outline) |
| `pressedImage` | none | Shown while a finger is on the button |
| `onImage` | none | Toggle only: shown while the toggle is on |
| `hitScale` | `1.15` | Touchable area as a multiple of `size` |
| `on` | `false` | Toggle only: starting state |

- Press buttons are held while any finger is on them; `button.on` and `button.held` are `true` until the last finger lifts.
- Toggles flip on each touch-down. `toggle.on` is the state; `toggle.held` is whether a finger is on it.
- `button.changed:connect(function(on: boolean) end)`
- `toggle:set(on, silent?)` changes the state from code (fires `changed` unless `silent`).
- `button:setText(text)` and `button:setIcon(image)`
- `button:setImages(background, pressed?, on?)` swaps custom art at runtime (buttons created with `backgroundImage` only).
- `button.visual` is a `Frame`, or an `ImageLabel` when `backgroundImage` is set.

With `backgroundImage`, a state that has no image of its own is shown by tinting: a held button is shaded darker, and an "on" toggle is tinted with `theme.accent`. Held buttons also shrink slightly in every style.
- With `bindAction`: `action(on, touchPosition)`.

### `Touch.touchpad(config?)`

An invisible drag area, usually for a custom camera.

| Option | Default | Description |
|---|---|---|
| `position`, `size`, `anchorPoint` | right 55% of the screen | Area to cover |
| `sensitivity` | `1` | Multiplier for the reported delta |
| `debug` | `false` | Draw a faint outline while laying out |

- `pad.moved:connect(function(delta: Vector2, position: Vector2, active: boolean) end)` — `delta` is in screen space (y down). Fires once more with a zero delta when the finger lifts.
- With `bindAxis`: `action(active, Vector3.new(delta.X, -delta.Y, 0))`.
- One finger at a time; extra fingers fall through to gestures.

### `Touch.gestures(config?)`

| Option | Default | Description |
|---|---|---|
| `tapTime`, `tapDistance` | `0.25`, `12` | Max duration and movement of a tap |
| `doubleTapTime` | `0.3` | Max gap between taps of a double tap |
| `longPressTime` | `0.5` | Hold time for a long press |
| `swipeDistance`, `swipeTime` | `60`, `0.3` | Min distance and max duration of a swipe |
| `region` | whole screen | Only track touches that start inside this `GuiObject` |

Signals (positions are screen pixels, y down):

| Signal | Arguments |
|---|---|
| `tap` | `position` — fires for every tap, including both taps of a double tap |
| `doubleTap` | `position` |
| `longPress` | `position` |
| `swipe` | `direction` (`"Up"`, `"Down"`, `"Left"`, `"Right"`), `delta: Vector2`, `speed` (px/s) |
| `pan` | `delta: Vector2`, `position: Vector2`, `state` (`"began"`, `"changed"`, `"ended"`) |
| `pinch` | `scale` (since the pinch started), `deltaScale` (since the last update), `center` |
| `rotate` | `angle` (since start), `deltaAngle`, `center` — radians, clockwise on screen is positive |

A swipe is also a pan; fingers that take part in a pinch or rotate never end as a tap or swipe.

### Custom art

Images are ordinary content ids, so ChainLink's `asset` macro works:

```lua
local stick = Touch.thumbstick({
    baseImage = asset "ui/stick-base.png",
    knobImage = asset "ui/stick-knob.png",
})

local jump = Touch.button({
    backgroundImage = asset "ui/button.png",
    pressedImage = asset "ui/button-pressed.png",
    image = asset "ui/icons/jump.png",
})
```

Images are scaled to fit the control's square size, so square art works best. Hit areas are unaffected.

### Signals

Every signal has `connect(fn)` and `once(fn)`, which return a connection with `disconnect()`. Listeners run in their own thread, so an error in one won't break input handling.
