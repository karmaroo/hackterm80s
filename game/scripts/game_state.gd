extends Node
## Global game state singleton
## Manages discovered systems, player progress, files, and modem state

# Discovered modems from war dialing (keyed by phone number)
var discovered_modems: Dictionary = {}

# Dynamic files created during gameplay
var dynamic_files: Dictionary = {}

# Floppy disk inventory
var owned_disks: Array = []

# Scan log counter for generating unique log filenames
var scan_log_counter: int = 0

# Player stats
var total_numbers_dialed: int = 0
var total_systems_found: int = 0

# Game time (simulated 1980s date)
var game_date: Dictionary = {
	"year": 1987,
	"month": 3,
	"day": 15,
	"hour": 22,
	"minute": 30
}

# Terminal history
var terminal_history: Array[String] = []
var max_history: int = 100

# Modem state
var modem_speaker_muted: bool = false

# Signals for modem activity (for LED indicators)
signal modem_dialing_started()
signal modem_dialing_complete()
signal modem_connected()
signal modem_hangup()
signal modem_send_data()
signal modem_receive_data()
signal modem_mute_changed(muted: bool)
signal floppy_reading()

# Disk contents definitions
const DISK_CONTENTS = {
	"wardialer": {
		"label": "WARDIALER V1.0",
		"files": {
			"WD.EXE": {"type": "exe", "program": "wardialer"},
			"README.TXT": {"type": "file", "content": "WarDialer v1.0\nPhone number scanner\n(C) 1987 Shadow Systems"}
		}
	},
	"wardialer_v2": {
		"label": "WARDIALER V2.0",
		"files": {
			"WD.EXE": {"type": "exe", "program": "wardialer"},
			"README.TXT": {"type": "file", "content": "WARDIALER V2.0 - ELITE RELEASE\n\nNew features:\n- Faster scanning\n- Better carrier detection\n- AI host support\n\nGreets to: Phoenix, Mentor, Acid\n"}
		}
	},
	"bbsdialer": {
		"label": "BBS DIALER V1.0",
		"files": {
			"BBS.EXE": {"type": "exe", "program": "bbsdialer"}
		}
	}
}


func _ready() -> void:
	print("[GameState] Initialized - Welcome to 1987")


## Add a discovered modem
func add_modem(phone: String, result_type: String, system_id: String = "") -> void:
	discovered_modems[phone] = {
		"type": result_type,
		"system_id": system_id,
		"discovered_at": get_formatted_date(),
		"connected": false,
		"note": "",
		"label": ""
	}
	total_systems_found += 1
	SessionManager.mark_dirty()


## Get modem data by phone number
func get_modem_data(phone: String) -> Dictionary:
	return discovered_modems.get(phone, {})


## Mark modem as connected
func mark_modem_connected(phone: String) -> void:
	if discovered_modems.has(phone):
		discovered_modems[phone].connected = true
		SessionManager.mark_dirty()


## Set modem note
func set_modem_note(phone: String, note: String) -> void:
	if discovered_modems.has(phone):
		discovered_modems[phone].note = note
		SessionManager.mark_dirty()


## Set modem label
func set_modem_label(phone: String, label: String) -> void:
	if discovered_modems.has(phone):
		discovered_modems[phone].label = label
		SessionManager.mark_dirty()


## Create a dynamic file
func create_file(filename: String, content: String, file_type: String = "txt") -> bool:
	dynamic_files[filename] = {
		"content": content,
		"type": file_type,
		"created": get_formatted_date()
	}
	SessionManager.mark_dirty()
	return true


## Check if a file exists
func has_file(filename: String) -> bool:
	return dynamic_files.has(filename)


## Get file content
func get_file_content(filename: String) -> String:
	if dynamic_files.has(filename):
		return dynamic_files[filename].get("content", "")
	return ""


## Delete a file
func delete_file(filename: String) -> bool:
	if dynamic_files.has(filename):
		dynamic_files.erase(filename)
		SessionManager.mark_dirty()
		return true
	return false


## Add to terminal history
func add_to_history(line: String) -> void:
	terminal_history.append(line)
	if terminal_history.size() > max_history:
		terminal_history.pop_front()


## Get formatted date string
func get_formatted_date() -> String:
	return "%02d/%02d/%d" % [game_date.month, game_date.day, game_date.year]


## Get formatted time string  
func get_formatted_time() -> String:
	return "%02d:%02d" % [game_date.hour, game_date.minute]


## Get DOS-style date
func get_dos_date() -> String:
	return "%02d-%02d-%02d" % [game_date.month, game_date.day, game_date.year % 100]


## Get DOS-style time
func get_dos_time() -> String:
	var h = game_date.hour
	var ampm = "a"
	if h >= 12:
		ampm = "p"
		if h > 12:
			h -= 12
	if h == 0:
		h = 12
	return "%2d:%02d%s" % [h, game_date.minute, ampm]


## Advance game time
func advance_time(minutes: int) -> void:
	game_date.minute += minutes
	while game_date.minute >= 60:
		game_date.minute -= 60
		game_date.hour += 1
	while game_date.hour >= 24:
		game_date.hour -= 24
		game_date.day += 1


## Generate next scan log filename
func get_next_log_filename() -> String:
	scan_log_counter += 1
	SessionManager.mark_dirty()
	return "WD%06d.LOG" % scan_log_counter


## Floppy disk management
func has_disk(disk_id: String) -> bool:
	return disk_id in owned_disks


func add_disk_to_inventory(disk_id: String) -> bool:
	if disk_id not in owned_disks:
		owned_disks.append(disk_id)
		SessionManager.mark_dirty()
		return true
	return false


func get_disk_contents(disk_id: String) -> Dictionary:
	return DISK_CONTENTS.get(disk_id, {})


## Toggle modem speaker mute
func toggle_modem_mute() -> void:
	modem_speaker_muted = not modem_speaker_muted
	modem_mute_changed.emit(modem_speaker_muted)


## Create a scan log file
func create_scan_log(filename: String, area_code: String, prefix: String, start_num: int, end_num: int) -> void:
	if not dynamic_files.has(filename):
		dynamic_files[filename] = {
			"content": "; War Dialer Scan Log\n; Range: %s-%s-%02d to %s-%s-%02d\n" % [
				area_code, prefix, start_num, area_code, prefix, end_num
			],
			"type": "scan_log",
			"created": get_formatted_date(),
			"area_code": area_code,
			"prefix": prefix,
			"start": start_num,
			"end": end_num,
			"last_scanned": start_num,
			"modems": []
		}
		SessionManager.mark_dirty()


## Add modem to a scan log
func add_modem_to_log(log_file: String, phone: String, system_id: String = "") -> void:
	# Get a random system if none specified
	if system_id == "":
		var SystemTemplates = load("res://scripts/system_templates.gd")
		var system = SystemTemplates.get_random_system()
		system_id = system.get("id", "")
	
	# Add to discovered modems
	add_modem(phone, "modem", system_id)
	
	# Add to log file if specified
	if log_file != "" and dynamic_files.has(log_file):
		dynamic_files[log_file].modems.append({
			"phone": phone,
			"system_id": system_id,
			"time": get_formatted_time()
		})
		dynamic_files[log_file].content += "%s MODEM (%s)\n" % [phone, system_id]
		SessionManager.mark_dirty()


## Update scan progress
func update_scan_progress(log_file: String, current_num: int) -> void:
	if dynamic_files.has(log_file):
		dynamic_files[log_file].last_scanned = current_num
		SessionManager.mark_dirty()
