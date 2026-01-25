extends Control
## LED Clock that displays current time in hh:mm format with blinking colon

@onready var time_label: RichTextLabel = $TimeLabel

var update_timer: Timer = null
var colon_bright: bool = true

# Colors for the colon
const BRIGHT_RED = "ff2619"  # Bright red
const DIM_RED = "661410"     # Dark red

func _ready():
	# Create timer to update every second
	update_timer = Timer.new()
	update_timer.wait_time = 1.0
	update_timer.timeout.connect(_update_time)
	add_child(update_timer)
	update_timer.start()

	# Initial update
	_update_time()


func _update_time():
	var time = Time.get_datetime_dict_from_system()
	var hour = time.hour
	var minute = time.minute

	# Convert to 12-hour format
	if hour > 12:
		hour -= 12
	if hour == 0:
		hour = 12

	# Toggle colon brightness
	colon_bright = not colon_bright
	var colon_color = BRIGHT_RED if colon_bright else DIM_RED

	# Format time string with BBCode for colon color
	var time_str = "%d[color=#%s]:[/color]%02d" % [hour, colon_color, minute]

	if time_label:
		time_label.text = ""
		time_label.append_text(time_str)
