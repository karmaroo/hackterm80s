extends PointLight2D
## Pulsing red light for the desk phone's message indicator bulb

@export var is_on: bool = true
@export var pulse_speed: float = 3.0
@export var min_energy: float = 0.3
@export var max_energy: float = 0.8

func _ready():
	# Set light color to red
	color = Color(1.0, 0.2, 0.1, 1.0)
	# Set initial state
	_update_state()

func _process(_delta):
	if is_on:
		# Pulse the light energy
		var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * pulse_speed)
		energy = lerpf(min_energy, max_energy, pulse)
	else:
		energy = 0.0

func _update_state():
	visible = is_on
	if not is_on:
		energy = 0.0

func set_lit(lit: bool):
	is_on = lit
	_update_state()
