extends Control
## Lava Lamp - Interactive 80s desk accessory with animated blob effect
## Features temperature simulation - cold has 1 blob, warm has 4-5 blobs
## Shift+L cycles through color presets when lamp is on

# Exactly like computer power button pattern
@onready var power_button: Panel = $PowerButton
@onready var power_led: ColorRect = $PowerLED
@onready var lamp_body: ColorRect = $LampBody
@onready var wall_light: PointLight2D = $WallLight

var lamp_on: bool = false  # Start OFF
var temperature: float = 0.0  # 0 = cold, 1 = hot
var target_temperature: float = 0.0
const WARMUP_SPEED: float = 0.04  # How fast it warms up (per second) - ~25 seconds to full
const COOLDOWN_SPEED: float = 0.10  # How fast it cools down (per second) - ~10 seconds (faster than heating)

# Color presets: [blob_bottom, blob_top, liquid, light_color, led_color]
# Bottom color is at base of lamp (heat source), top color is where blobs rise to
var current_color_index: int = 0
const COLOR_PRESETS = [
	{  # Green to Cyan - default
		"name": "Green-Cyan",
		"blob_bottom": Color(0.2, 0.9, 0.4, 1.0),
		"blob_top": Color(0.3, 0.95, 0.85, 1.0),
		"liquid": Color(0.02, 0.04, 0.03, 1.0),
		"light": Color(0.3, 0.95, 0.5, 1.0),
		"led": Color(0.1, 0.85, 0.3, 1.0)
	},
	{  # Red to Yellow - classic lava, hot at bottom cooling to yellow
		"name": "Lava",
		"blob_bottom": Color(1.0, 0.15, 0.05, 1.0),
		"blob_top": Color(1.0, 0.85, 0.2, 1.0),
		"liquid": Color(0.05, 0.02, 0.01, 1.0),
		"light": Color(1.0, 0.4, 0.1, 1.0),
		"led": Color(1.0, 0.3, 0.1, 1.0)
	},
	{  # Magenta to Cyan - synthwave/vaporwave
		"name": "Synthwave",
		"blob_bottom": Color(1.0, 0.1, 0.6, 1.0),
		"blob_top": Color(0.2, 0.9, 1.0, 1.0),
		"liquid": Color(0.03, 0.01, 0.04, 1.0),
		"light": Color(0.8, 0.3, 0.9, 1.0),
		"led": Color(1.0, 0.2, 0.7, 1.0)
	},
	{  # Orange to Purple - sunset
		"name": "Sunset",
		"blob_bottom": Color(1.0, 0.5, 0.1, 1.0),
		"blob_top": Color(0.6, 0.2, 0.9, 1.0),
		"liquid": Color(0.04, 0.02, 0.03, 1.0),
		"light": Color(1.0, 0.4, 0.5, 1.0),
		"led": Color(1.0, 0.5, 0.3, 1.0)
	},
	{  # Blue to Green - ocean/aurora
		"name": "Aurora",
		"blob_bottom": Color(0.1, 0.3, 1.0, 1.0),
		"blob_top": Color(0.2, 1.0, 0.5, 1.0),
		"liquid": Color(0.01, 0.02, 0.04, 1.0),
		"light": Color(0.2, 0.7, 0.8, 1.0),
		"led": Color(0.1, 0.6, 0.9, 1.0)
	},
	{  # Yellow to White - molten gold
		"name": "Gold",
		"blob_bottom": Color(1.0, 0.7, 0.1, 1.0),
		"blob_top": Color(1.0, 1.0, 0.85, 1.0),
		"liquid": Color(0.04, 0.03, 0.01, 1.0),
		"light": Color(1.0, 0.85, 0.4, 1.0),
		"led": Color(1.0, 0.8, 0.2, 1.0)
	},
	{  # Pink to Blue - cotton candy
		"name": "Cotton Candy",
		"blob_bottom": Color(1.0, 0.5, 0.7, 1.0),
		"blob_top": Color(0.5, 0.7, 1.0, 1.0),
		"liquid": Color(0.03, 0.02, 0.04, 1.0),
		"light": Color(0.9, 0.6, 0.9, 1.0),
		"led": Color(1.0, 0.5, 0.8, 1.0)
	},
	{  # Deep red to bright orange - fire
		"name": "Fire",
		"blob_bottom": Color(0.8, 0.1, 0.05, 1.0),
		"blob_top": Color(1.0, 0.6, 0.1, 1.0),
		"liquid": Color(0.03, 0.01, 0.01, 1.0),
		"light": Color(1.0, 0.35, 0.1, 1.0),
		"led": Color(1.0, 0.2, 0.05, 1.0)
	}
]

func _ready() -> void:
	# Connect power button (same as computer button)
	if power_button:
		power_button.gui_input.connect(_on_power_button_input)
		print("[LavaLamp] Power button connected")
	else:
		print("[LavaLamp] WARNING: Power button not found!")
	
	# Initialize to OFF state
	lamp_on = false
	temperature = 0.0
	target_temperature = 0.0
	_apply_color_preset()  # Apply initial color
	_update_lamp_state()
	_update_temperature()

# Exactly like _on_power_button_input in main.gd
func _on_power_button_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("[LavaLamp] Power button clicked!")
			_toggle_lamp()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F8:
			if event.shift_pressed and lamp_on:
				# Shift+F8 cycles colors when lamp is on
				_cycle_color()
			else:
				# F8 toggles lamp on/off
				_toggle_lamp()
			get_viewport().set_input_as_handled()


func _cycle_color() -> void:
	current_color_index = (current_color_index + 1) % COLOR_PRESETS.size()
	_apply_color_preset()
	print("[LavaLamp] Color changed to: ", COLOR_PRESETS[current_color_index].name)


func _apply_color_preset() -> void:
	var preset = COLOR_PRESETS[current_color_index]

	# Update shader colors
	if lamp_body and lamp_body.material:
		var shader_mat = lamp_body.material as ShaderMaterial
		if shader_mat:
			shader_mat.set_shader_parameter("blob_color_bottom", preset.blob_bottom)
			shader_mat.set_shader_parameter("blob_color_top", preset.blob_top)
			shader_mat.set_shader_parameter("liquid_color", preset.liquid)

	# Update wall light color
	if wall_light:
		wall_light.color = preset.light

	# Update power LED color (when on)
	if power_led and lamp_on:
		power_led.color = preset.led

func _process(delta: float) -> void:
	# Gradually adjust temperature towards target
	if lamp_on:
		if temperature < target_temperature:
			temperature = min(temperature + WARMUP_SPEED * delta, target_temperature)
			_update_temperature()
	else:
		if temperature > 0.0:
			temperature = max(temperature - COOLDOWN_SPEED * delta, 0.0)
			_update_temperature()

func _toggle_lamp() -> void:
	lamp_on = !lamp_on
	if lamp_on:
		target_temperature = 1.0
	else:
		target_temperature = 0.0
	_update_lamp_state()

func _update_lamp_state() -> void:
	# Update shader is_on uniform
	if lamp_body and lamp_body.material:
		var shader_mat = lamp_body.material as ShaderMaterial
		if shader_mat:
			shader_mat.set_shader_parameter("is_on", lamp_on)

	# Update power LED based on current color preset
	if power_led:
		if lamp_on:
			power_led.color = COLOR_PRESETS[current_color_index].led
		else:
			# Dark LED when off
			power_led.color = Color(0.02, 0.06, 0.03, 1.0)

	# Wall light enabled state depends on temperature too (stays on while cooling)
	if wall_light:
		wall_light.enabled = lamp_on or temperature > 0.02
		wall_light.color = COLOR_PRESETS[current_color_index].light

func _update_temperature() -> void:
	# Update shader temperature uniform
	if lamp_body and lamp_body.material:
		var shader_mat = lamp_body.material as ShaderMaterial
		if shader_mat:
			shader_mat.set_shader_parameter("temperature", temperature)

	# Update wall light intensity based on temperature
	if wall_light:
		wall_light.energy = temperature * 2.5  # Brighter glow to cut through ambient darkness
		# Keep light enabled while still warm
		wall_light.enabled = lamp_on or temperature > 0.02

## Force lamp to specific state (called externally)
func set_lamp_on(state: bool) -> void:
	lamp_on = state
	target_temperature = 1.0 if state else 0.0
	_update_lamp_state()

## Set temperature directly (for testing)
func set_temperature(temp: float) -> void:
	temperature = clamp(temp, 0.0, 1.0)
	_update_temperature()
