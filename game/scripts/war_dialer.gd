extends Node
class_name WarDialer
## War Dialer - Automatically dials phone numbers looking for modems/computers
## Classic 80s hacking tool featured in movies like WarGames

signal scan_started(start_number: String, end_number: String)
signal number_dialing(number: String)
signal number_result(number: String, result: String)  # result: "NO_ANSWER", "VOICE", "MODEM", "FAX", "BUSY"
signal scan_complete(results: Dictionary)
signal scan_stopped()

# Scan settings
var area_code: String = "555"
var prefix: String = "01"
var start_suffix: int = 00
var end_suffix: int = 99
var current_suffix: int = 0

# Timing settings (in seconds)
var ring_wait_time: float = 4.0  # How long to wait for answer
var between_calls_delay: float = 0.5  # Delay between calls

# Scan state
var is_scanning: bool = false
var is_paused: bool = false
var scan_results: Dictionary = {
	"modems": [],
	"voice": [],
	"fax": [],
	"busy": [],
	"no_answer": [],
	"total_scanned": 0
}

# DTMF generator
var dtmf: DTMFGenerator

# Result probabilities (for simulation)
const RESULT_WEIGHTS = {
	"NO_ANSWER": 45,
	"VOICE": 30,
	"BUSY": 15,
	"MODEM": 7,
	"FAX": 3
}

# Debug: force next call to be a modem
var force_next_modem: bool = false


func _ready() -> void:
	# Create DTMF generator
	dtmf = DTMFGenerator.new()
	add_child(dtmf)
	
	# Connect DTMF signals
	dtmf.dialing_complete.connect(_on_dialing_complete)


## Start a war dialing scan
func start_scan(p_area_code: String, p_prefix: String, p_start: int, p_end: int) -> void:
	if is_scanning:
		return
	
	area_code = p_area_code
	prefix = p_prefix
	start_suffix = p_start
	end_suffix = p_end
	current_suffix = start_suffix
	
	# Reset results
	scan_results = {
		"modems": [],
		"voice": [],
		"fax": [],
		"busy": [],
		"no_answer": [],
		"total_scanned": 0
	}
	
	is_scanning = true
	is_paused = false
	
	var start_num = _format_number(start_suffix)
	var end_num = _format_number(end_suffix)
	emit_signal("scan_started", start_num, end_num)
	
	# Start dialing
	_dial_next()


## Stop the current scan
func stop_scan() -> void:
	is_scanning = false
	is_paused = false
	dtmf.stop_dialing()
	emit_signal("scan_stopped")


## Pause/resume the scan
func toggle_pause() -> void:
	is_paused = !is_paused
	if not is_paused and is_scanning:
		_dial_next()


## Format a phone number
func _format_number(suffix: int) -> String:
	return "%s-%s-%02d" % [area_code, prefix, suffix]


## Dial the next number in the sequence
func _dial_next() -> void:
	if not is_scanning or is_paused:
		return
	
	if current_suffix > end_suffix:
		# Scan complete
		is_scanning = false
		emit_signal("scan_complete", scan_results)
		return
	
	var number = _format_number(current_suffix)
	emit_signal("number_dialing", number)
	
	# Dial with DTMF tones
	var dial_digits = area_code + prefix + "%02d" % current_suffix
	dtmf.dial_number(dial_digits)


## Called when DTMF dialing is complete
func _on_dialing_complete(_number: String) -> void:
	if not is_scanning:
		return
	
	# Simulate waiting for answer
	await get_tree().create_timer(ring_wait_time).timeout
	
	# Determine result (simulated)
	var result = _simulate_call_result()
	var number = _format_number(current_suffix)
	
	# Record result
	match result:
		"MODEM":
			scan_results["modems"].append(number)
		"VOICE":
			scan_results["voice"].append(number)
		"FAX":
			scan_results["fax"].append(number)
		"BUSY":
			scan_results["busy"].append(number)
		"NO_ANSWER":
			scan_results["no_answer"].append(number)
	
	scan_results["total_scanned"] += 1
	
	emit_signal("number_result", number, result)
	
	# Move to next number
	current_suffix += 1
	
	# Delay before next call
	await get_tree().create_timer(between_calls_delay).timeout
	
	# Dial next
	_dial_next()


## Simulate the result of a phone call
func _simulate_call_result() -> String:
	# Check if we're forcing a modem result
	if force_next_modem:
		force_next_modem = false
		return "MODEM"
	
	var total_weight = 0
	for weight in RESULT_WEIGHTS.values():
		total_weight += weight
	
	var roll = randi() % total_weight
	var cumulative = 0
	
	for result in RESULT_WEIGHTS:
		cumulative += RESULT_WEIGHTS[result]
		if roll < cumulative:
			return result
	
	return "NO_ANSWER"


## Get current scan progress (0.0 - 1.0)
func get_progress() -> float:
	var total = end_suffix - start_suffix + 1
	var done = current_suffix - start_suffix
	return float(done) / float(total) if total > 0 else 0.0


## Get scan statistics
func get_stats() -> Dictionary:
	return {
		"total": scan_results["total_scanned"],
		"modems": scan_results["modems"].size(),
		"voice": scan_results["voice"].size(),
		"fax": scan_results["fax"].size(),
		"busy": scan_results["busy"].size(),
		"no_answer": scan_results["no_answer"].size(),
	}
