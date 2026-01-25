extends Node
class_name OnlineManagerClass
## OnlineManager - Handles communication with multiplayer backend
## Provides graceful degradation when offline

# Signals
signal registration_complete(success: bool, data: Dictionary)
signal recovery_complete(success: bool, data: Dictionary)
signal sync_complete(success: bool)
signal filesystem_fetched(success: bool, filesystem: Dictionary)
signal connection_status_changed(online: bool)

# Server configuration
const DEFAULT_SERVER_URL = "http://localhost:3000/api"
const TIMEOUT_SECONDS = 5.0

# HTTP client
var _http_request: HTTPRequest
var _current_request: String = ""

# Connection state
var is_online: bool = false
var _last_check_time: float = 0.0
const CHECK_INTERVAL: float = 30.0  # Check server every 30 seconds

# Player data (cached locally)
var is_registered: bool = false
var player_handle: String = ""
var player_phone: String = ""
var recovery_code: String = ""
var session_token: String = ""

# Server URL (can be overridden)
var server_url: String = DEFAULT_SERVER_URL


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = TIMEOUT_SECONDS
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)

	# Load cached data from local storage
	_load_local_data()

	# Check server connectivity
	call_deferred("_check_server_status")


func _process(delta: float) -> void:
	# Periodic server connectivity check
	_last_check_time += delta
	if _last_check_time >= CHECK_INTERVAL:
		_last_check_time = 0.0
		if not _current_request.is_empty():
			return  # Don't interrupt ongoing request
		_check_server_status()


# ===== LOCAL DATA PERSISTENCE =====

func _load_local_data() -> void:
	var config = ConfigFile.new()
	if config.load("user://online.cfg") == OK:
		is_registered = config.get_value("player", "registered", false)
		player_handle = config.get_value("player", "handle", "")
		player_phone = config.get_value("player", "phone", "")
		recovery_code = config.get_value("player", "recovery_code", "")
		session_token = config.get_value("player", "session_token", "")
		print("[OnlineManager] Loaded local data: registered=%s, handle=%s" % [is_registered, player_handle])


func _save_local_data() -> void:
	var config = ConfigFile.new()
	config.set_value("player", "registered", is_registered)
	config.set_value("player", "handle", player_handle)
	config.set_value("player", "phone", player_phone)
	config.set_value("player", "recovery_code", recovery_code)
	config.set_value("player", "session_token", session_token)
	config.save("user://online.cfg")
	print("[OnlineManager] Saved local data")


func _get_browser_id() -> String:
	"""Generate/retrieve a persistent browser identifier"""
	var config = ConfigFile.new()
	if config.load("user://browser_id.cfg") == OK:
		return config.get_value("id", "value", "")

	# Generate new ID
	var id = str(randi()) + str(int(Time.get_unix_time_from_system()))
	config.set_value("id", "value", id)
	config.save("user://browser_id.cfg")
	return id


# ===== SERVER STATUS =====

func _check_server_status() -> void:
	if not _current_request.is_empty():
		return

	_current_request = "status"
	var headers = ["Content-Type: application/json"]
	var error = _http_request.request(server_url + "/status", headers, HTTPClient.METHOD_GET)
	if error != OK:
		_set_online(false)
		_current_request = ""


func _set_online(online: bool) -> void:
	if is_online != online:
		is_online = online
		print("[OnlineManager] Connection status: %s" % ("ONLINE" if online else "OFFLINE"))
		connection_status_changed.emit(online)


# ===== REGISTRATION =====

func register_player(handle: String) -> void:
	"""Register a new player with the server"""
	if not _current_request.is_empty():
		print("[OnlineManager] Request already in progress")
		return

	_current_request = "register"
	var body = JSON.stringify({
		"handle": handle,
		"browser_id": _get_browser_id()
	})
	var headers = ["Content-Type: application/json"]
	var error = _http_request.request(server_url + "/register", headers, HTTPClient.METHOD_POST, body)

	if error != OK:
		print("[OnlineManager] Failed to send registration request: ", error)
		_current_request = ""
		registration_complete.emit(false, {"error": "REQUEST_FAILED"})


# ===== RECOVERY =====

func recover_session(code: String) -> void:
	"""Recover a session using recovery code"""
	if not _current_request.is_empty():
		print("[OnlineManager] Request already in progress")
		return

	_current_request = "recover"
	var body = JSON.stringify({
		"recovery_code": code.to_upper(),
		"browser_id": _get_browser_id()
	})
	var headers = ["Content-Type: application/json"]
	var error = _http_request.request(server_url + "/recover", headers, HTTPClient.METHOD_POST, body)

	if error != OK:
		print("[OnlineManager] Failed to send recovery request: ", error)
		_current_request = ""
		recovery_complete.emit(false, {"error": "REQUEST_FAILED"})


# ===== FILESYSTEM SYNC =====

func sync_filesystem(filesystem: Dictionary) -> void:
	"""Sync filesystem to server"""
	if not is_online or session_token.is_empty():
		print("[OnlineManager] Cannot sync: offline or no session")
		return

	if not _current_request.is_empty():
		print("[OnlineManager] Request already in progress, queuing sync")
		# TODO: Queue for later
		return

	_current_request = "sync"
	var body = JSON.stringify({
		"filesystem": filesystem
	})
	var headers = [
		"Content-Type: application/json",
		"X-Session-Token: " + session_token
	]
	var error = _http_request.request(
		server_url + "/filesystem/" + session_token,
		headers,
		HTTPClient.METHOD_PUT,
		body
	)

	if error != OK:
		print("[OnlineManager] Failed to send sync request: ", error)
		_current_request = ""


func fetch_filesystem() -> void:
	"""Fetch filesystem from server"""
	if not is_online or session_token.is_empty():
		print("[OnlineManager] Cannot fetch: offline or no session")
		return

	if not _current_request.is_empty():
		return

	_current_request = "fetch"
	var headers = ["X-Session-Token: " + session_token]
	var error = _http_request.request(
		server_url + "/filesystem/" + session_token,
		headers,
		HTTPClient.METHOD_GET
	)

	if error != OK:
		print("[OnlineManager] Failed to send fetch request: ", error)
		_current_request = ""


# ===== RESPONSE HANDLING =====

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var request_type = _current_request
	_current_request = ""

	# Check for timeout or connection errors
	if result != HTTPRequest.RESULT_SUCCESS:
		print("[OnlineManager] Request failed: result=%d" % result)
		_set_online(false)
		_handle_request_error(request_type, {"error": "CONNECTION_FAILED"})
		return

	# Parse response
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	var data: Dictionary = {}
	if parse_result == OK:
		data = json.data if json.data is Dictionary else {}

	print("[OnlineManager] %s response: %d" % [request_type, response_code])

	# Handle based on request type
	match request_type:
		"status":
			_set_online(response_code == 200)
		"register":
			_handle_registration_response(response_code, data)
		"recover":
			_handle_recovery_response(response_code, data)
		"sync":
			_handle_sync_response(response_code, data)
		"fetch":
			_handle_fetch_response(response_code, data)


func _handle_request_error(request_type: String, error_data: Dictionary) -> void:
	match request_type:
		"register":
			registration_complete.emit(false, error_data)
		"recover":
			recovery_complete.emit(false, error_data)
		"sync":
			sync_complete.emit(false)


func _handle_registration_response(response_code: int, data: Dictionary) -> void:
	if response_code == 200 and data.get("success", false):
		# Success!
		is_registered = true
		player_handle = data.get("handle", "")
		player_phone = data.get("phone_number", "")
		recovery_code = data.get("recovery_code", "")
		session_token = data.get("session_token", "")
		_save_local_data()
		_set_online(true)
		print("[OnlineManager] Registration successful: %s (%s)" % [player_handle, player_phone])
		registration_complete.emit(true, data)
	else:
		# Error
		var error = data.get("error", "UNKNOWN")
		var message = data.get("message", "Registration failed")
		print("[OnlineManager] Registration failed: %s - %s" % [error, message])
		registration_complete.emit(false, data)


func _handle_recovery_response(response_code: int, data: Dictionary) -> void:
	if response_code == 200 and data.get("success", false):
		# Success!
		is_registered = true
		player_handle = data.get("handle", "")
		player_phone = data.get("phone_number", "")
		session_token = data.get("session_token", "")
		# Keep existing recovery code if we have it
		_save_local_data()
		_set_online(true)
		print("[OnlineManager] Recovery successful: %s (%s)" % [player_handle, player_phone])
		recovery_complete.emit(true, data)
	else:
		var error = data.get("error", "UNKNOWN")
		var message = data.get("message", "Recovery failed")
		print("[OnlineManager] Recovery failed: %s - %s" % [error, message])
		recovery_complete.emit(false, data)


func _handle_sync_response(response_code: int, data: Dictionary) -> void:
	if response_code == 200:
		print("[OnlineManager] Sync successful: %d files" % data.get("files_synced", 0))
		sync_complete.emit(true)
	else:
		print("[OnlineManager] Sync failed: %s" % data.get("error", "UNKNOWN"))
		sync_complete.emit(false)


func _handle_fetch_response(response_code: int, data: Dictionary) -> void:
	if response_code == 200:
		var filesystem = data.get("filesystem", {})
		print("[OnlineManager] Fetched filesystem: %d entries" % filesystem.size())
		filesystem_fetched.emit(true, filesystem)
	else:
		print("[OnlineManager] Fetch failed: %s" % data.get("error", "UNKNOWN"))
		filesystem_fetched.emit(false, {})


# ===== OFFLINE REGISTRATION =====

func setup_offline_mode(handle: String) -> void:
	"""Setup player in offline mode (no server connection)"""
	is_registered = true
	player_handle = handle.to_upper()
	player_phone = "555-%04d" % (randi() % 9000 + 1000)  # Random local-only number
	recovery_code = ""  # No recovery code in offline mode
	session_token = ""
	_save_local_data()
	print("[OnlineManager] Offline mode: %s (%s)" % [player_handle, player_phone])


# ===== UTILITY =====

func clear_local_data() -> void:
	"""Clear all local player data (for testing)"""
	is_registered = false
	player_handle = ""
	player_phone = ""
	recovery_code = ""
	session_token = ""
	var dir = DirAccess.open("user://")
	if dir:
		dir.remove("online.cfg")
		dir.remove("browser_id.cfg")
	print("[OnlineManager] Local data cleared")
