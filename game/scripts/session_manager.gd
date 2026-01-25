extends Node
## Session Manager - Handles persistent storage for game sessions
## Uses Godot's user:// path which maps to IndexedDB in HTML5 exports

const SAVE_VERSION = 1
const SESSIONS_DIR = "user://sessions/"
const CURRENT_SESSION_FILE = "user://current_session.txt"
const AUTO_SAVE_INTERVAL = 30.0  # Auto-save every 30 seconds

var current_session_id: String = ""
var auto_save_timer: Timer
var _dirty: bool = false  # Track if state has changed since last save

signal session_loaded(session_id: String)
signal session_saved(session_id: String)
signal session_created(session_id: String)


func _ready() -> void:
	# Ensure sessions directory exists
	_ensure_directory(SESSIONS_DIR)
	
	# Set up auto-save timer
	auto_save_timer = Timer.new()
	auto_save_timer.wait_time = AUTO_SAVE_INTERVAL
	auto_save_timer.timeout.connect(_on_auto_save)
	add_child(auto_save_timer)
	
	# Try to load existing session or create new one
	_initialize_session()


func _ensure_directory(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)


func _initialize_session() -> void:
	# Check if there's a current session saved
	if FileAccess.file_exists(CURRENT_SESSION_FILE):
		var file = FileAccess.open(CURRENT_SESSION_FILE, FileAccess.READ)
		if file:
			current_session_id = file.get_as_text().strip_edges()
			file.close()
			
			# Try to load this session
			if _session_exists(current_session_id):
				load_session(current_session_id)
				return
	
	# No valid session found, create a new one
	create_new_session()


func _session_exists(session_id: String) -> bool:
	var path = SESSIONS_DIR + session_id + ".json"
	return FileAccess.file_exists(path)


func _generate_session_id() -> String:
	# Generate a unique session ID based on timestamp and random
	var timestamp = Time.get_unix_time_from_system()
	var random_part = randi() % 10000
	return "SES%d%04d" % [int(timestamp) % 1000000, random_part]


## Create a new session
func create_new_session() -> String:
	current_session_id = _generate_session_id()
	
	# Save the current session ID
	var file = FileAccess.open(CURRENT_SESSION_FILE, FileAccess.WRITE)
	if file:
		file.store_string(current_session_id)
		file.close()
	
	# Reset GameState to defaults
	_reset_game_state()
	
	# Save initial state
	save_session()
	
	print("[SessionManager] Created new session: ", current_session_id)
	session_created.emit(current_session_id)
	
	# Start auto-save
	auto_save_timer.start()
	
	return current_session_id


## Save current game state to session file
func save_session() -> bool:
	if current_session_id == "":
		push_error("No active session to save")
		return false
	
	var save_data = {
		"version": SAVE_VERSION,
		"session_id": current_session_id,
		"saved_at": Time.get_unix_time_from_system(),
		"game_state": _serialize_game_state()
	}
	
	var path = SESSIONS_DIR + current_session_id + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		_dirty = false
		print("[SessionManager] Session saved: ", current_session_id)
		session_saved.emit(current_session_id)
		return true
	else:
		push_error("Failed to save session: " + str(FileAccess.get_open_error()))
		return false


## Load a session by ID
func load_session(session_id: String) -> bool:
	var path = SESSIONS_DIR + session_id + ".json"
	
	if not FileAccess.file_exists(path):
		push_error("Session file not found: " + path)
		return false
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open session file")
		return false
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	if parse_result != OK:
		push_error("Failed to parse session JSON: " + json.get_error_message())
		return false
	
	var save_data = json.data
	
	# Version check
	if save_data.get("version", 0) != SAVE_VERSION:
		print("[SessionManager] Warning: Session version mismatch, may need migration")
	
	# Restore game state
	_deserialize_game_state(save_data.get("game_state", {}))
	
	current_session_id = session_id
	
	# Update current session file
	var current_file = FileAccess.open(CURRENT_SESSION_FILE, FileAccess.WRITE)
	if current_file:
		current_file.store_string(current_session_id)
		current_file.close()
	
	_dirty = false
	print("[SessionManager] Session loaded: ", current_session_id)
	session_loaded.emit(current_session_id)
	
	# Start auto-save
	auto_save_timer.start()
	
	return true


## Get list of all saved sessions
func get_saved_sessions() -> Array:
	var sessions: Array = []
	
	var dir = DirAccess.open(SESSIONS_DIR)
	if dir:
		dir.list_dir_begin()
		var filename = dir.get_next()
		while filename != "":
			if filename.ends_with(".json"):
				var session_id = filename.replace(".json", "")
				var info = get_session_info(session_id)
				if info:
					sessions.append(info)
			filename = dir.get_next()
		dir.list_dir_end()
	
	# Sort by saved_at descending (most recent first)
	sessions.sort_custom(func(a, b): return a.saved_at > b.saved_at)
	
	return sessions


## Get info about a specific session without fully loading it
func get_session_info(session_id: String) -> Dictionary:
	var path = SESSIONS_DIR + session_id + ".json"
	
	if not FileAccess.file_exists(path):
		return {}
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_text) != OK:
		return {}
	
	var data = json.data
	var game_state = data.get("game_state", {})
	
	return {
		"session_id": session_id,
		"saved_at": data.get("saved_at", 0),
		"modem_count": game_state.get("discovered_modems", {}).size(),
		"file_count": game_state.get("dynamic_files", {}).size(),
		"game_date": game_state.get("game_date", {})
	}


## Delete a session
func delete_session(session_id: String) -> bool:
	var path = SESSIONS_DIR + session_id + ".json"
	
	if FileAccess.file_exists(path):
		var dir = DirAccess.open(SESSIONS_DIR)
		if dir:
			dir.remove(session_id + ".json")
			print("[SessionManager] Session deleted: ", session_id)
			return true
	
	return false


## Mark state as dirty (needs saving)
func mark_dirty() -> void:
	_dirty = true


## Check if state needs saving
func is_dirty() -> bool:
	return _dirty


func _on_auto_save() -> void:
	if _dirty:
		save_session()


func _serialize_game_state() -> Dictionary:
	return {
		"dynamic_files": GameState.dynamic_files.duplicate(true),
		"discovered_modems": GameState.discovered_modems.duplicate(true),
		"scan_log_counter": GameState.scan_log_counter,
		"total_numbers_dialed": GameState.total_numbers_dialed,
		"total_systems_found": GameState.total_systems_found,
		"game_date": GameState.game_date.duplicate(),
		"terminal_history": GameState.terminal_history.duplicate()
	}


func _deserialize_game_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	
	# Restore dynamic files
	GameState.dynamic_files = {}
	var files_data = data.get("dynamic_files", {})
	for filename in files_data:
		GameState.dynamic_files[filename] = files_data[filename]
	
	# Restore discovered modems
	GameState.discovered_modems = {}
	var modems_data = data.get("discovered_modems", {})
	for phone in modems_data:
		GameState.discovered_modems[phone] = modems_data[phone]
	
	# Restore counters
	GameState.scan_log_counter = data.get("scan_log_counter", 0)
	GameState.total_numbers_dialed = data.get("total_numbers_dialed", 0)
	GameState.total_systems_found = data.get("total_systems_found", 0)
	
	# Restore game date
	var date_data = data.get("game_date", {})
	if not date_data.is_empty():
		GameState.game_date = date_data
	
	# Restore terminal history
	GameState.terminal_history = []
	var history_data = data.get("terminal_history", [])
	for line in history_data:
		GameState.terminal_history.append(line)


func _reset_game_state() -> void:
	GameState.dynamic_files = {}
	GameState.discovered_modems = {}
	GameState.scan_log_counter = 0
	GameState.total_numbers_dialed = 0
	GameState.total_systems_found = 0
	GameState.game_date = {
		"year": 1987,
		"month": 3,
		"day": 15,
		"hour": 22,
		"minute": 30
	}
	GameState.terminal_history = []
