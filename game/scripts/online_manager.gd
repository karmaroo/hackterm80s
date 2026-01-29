extends Node
class_name OnlineManagerClass
## OnlineManager - Handles communication with multiplayer backend
## Provides graceful degradation when offline
## Supports WebSocket for real-time multi-device sync

# Signals
signal registration_complete(success: bool, data: Dictionary)
signal recovery_complete(success: bool, data: Dictionary)
signal sync_complete(success: bool)
signal filesystem_fetched(success: bool, filesystem: Dictionary)
signal connection_status_changed(online: bool)

# WebSocket signals for real-time sync
signal file_changed_remote(path: String, content: String, file_type: String, program: String, metadata: Dictionary)
signal file_deleted_remote(path: String)
signal websocket_connected()
signal websocket_disconnected()
signal versions_received(path: String, current: Dictionary, versions: Array)
signal version_restored(path: String, version: int)
signal scene_config_received(msg: Dictionary)  # For edit mode auto-save

# Server configuration
const DEFAULT_SERVER_URL = "http://localhost:3000/api"
const API_PORT = 3000
const TIMEOUT_SECONDS = 5.0

# HTTP client
var _http_request: HTTPRequest
var _current_request: String = ""

# WebSocket client
var _websocket: WebSocketPeer
var _ws_connected: bool = false
var _ws_authenticated: bool = false
var _ws_reconnect_timer: float = 0.0
var _ws_reconnect_delay: float = 2.0
const WS_RECONNECT_MAX_DELAY: float = 30.0
var _ws_ping_timer: float = 0.0
const WS_PING_INTERVAL: float = 25.0

# Connection state
var is_online: bool = false
var _last_check_time: float = 0.0
const CHECK_INTERVAL_INITIAL: float = 3.0  # Fast retries initially
const CHECK_INTERVAL_BASE: float = 30.0  # Base check interval after connected once
const CHECK_INTERVAL_MAX: float = 300.0  # Max 5 minutes between checks when offline
var _current_check_interval: float = CHECK_INTERVAL_INITIAL
var _consecutive_failures: int = 0
var _ever_connected: bool = false  # Track if we ever connected successfully
var _logged_offline: bool = false  # Prevent log spam

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

	# Detect API URL dynamically for web builds (handles port forwarding)
	_detect_server_url()

	# Load cached data from local storage
	_load_local_data()

	# Short delay before initial server check to let scene stabilize
	# Then check quickly to get online ASAP
	get_tree().create_timer(0.5).timeout.connect(_check_server_status)


func _detect_server_url() -> void:
	# For web builds, use same origin to avoid mixed content issues
	if OS.has_feature("web"):
		# Get the current page origin via JavaScript
		var origin = JavaScriptBridge.eval("window.location.origin")
		if origin:
			server_url = str(origin) + "/api"
			print("[OnlineManager] Web build - using origin API URL: ", server_url)
		else:
			# Fallback if JavaScript fails
			server_url = DEFAULT_SERVER_URL
			print("[OnlineManager] Web build - JavaScript failed, using default: ", server_url)
	else:
		server_url = DEFAULT_SERVER_URL
		print("[OnlineManager] Using API URL: ", server_url)


func _process(delta: float) -> void:
	# Periodic server connectivity check with exponential backoff
	_last_check_time += delta
	if _last_check_time >= _current_check_interval:
		_last_check_time = 0.0
		if not _current_request.is_empty():
			return  # Don't interrupt ongoing request
		_check_server_status()

	# Process WebSocket
	_process_websocket(delta)


# ===== WEBSOCKET =====

func _process_websocket(delta: float) -> void:
	if _websocket == null:
		# Try to connect if we have a session token and are online
		if is_online and not session_token.is_empty() and not _ws_connected:
			_ws_reconnect_timer += delta
			if _ws_reconnect_timer >= _ws_reconnect_delay:
				_ws_reconnect_timer = 0.0
				_connect_websocket()
		return

	_websocket.poll()
	var state = _websocket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _ws_connected:
				_ws_connected = true
				_ws_reconnect_delay = 2.0  # Reset reconnect delay
				print("[OnlineManager] WebSocket connected, authenticating...")
				_ws_authenticate()

			# Handle incoming messages
			while _websocket.get_available_packet_count() > 0:
				var packet = _websocket.get_packet()
				_handle_ws_message(packet.get_string_from_utf8())

			# Ping to keep alive
			_ws_ping_timer += delta
			if _ws_ping_timer >= WS_PING_INTERVAL:
				_ws_ping_timer = 0.0
				_ws_send({"type": "ping"})

		WebSocketPeer.STATE_CLOSING:
			pass  # Wait for close

		WebSocketPeer.STATE_CLOSED:
			var code = _websocket.get_close_code()
			var reason = _websocket.get_close_reason()
			if _ws_connected or _ws_authenticated:
				print("[OnlineManager] WebSocket closed: %d %s" % [code, reason])
				_ws_connected = false
				_ws_authenticated = false
				websocket_disconnected.emit()
			_websocket = null
			# Exponential backoff for reconnection
			_ws_reconnect_delay = min(_ws_reconnect_delay * 2, WS_RECONNECT_MAX_DELAY)


func _connect_websocket() -> void:
	if _websocket != null:
		return

	# Convert HTTP URL to WebSocket URL
	var ws_url = server_url.replace("http://", "ws://").replace("https://", "wss://")
	# Remove /api suffix and add /ws
	ws_url = ws_url.replace("/api", "") + "/ws"

	print("[OnlineManager] Connecting WebSocket to: %s" % ws_url)

	_websocket = WebSocketPeer.new()
	var error = _websocket.connect_to_url(ws_url)
	if error != OK:
		print("[OnlineManager] WebSocket connection failed: %d" % error)
		_websocket = null


func _ws_authenticate() -> void:
	_ws_send({
		"type": "auth",
		"token": session_token
	})


func _ws_send(data: Dictionary) -> void:
	if _websocket == null or _websocket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_websocket.send_text(JSON.stringify(data))


func _handle_ws_message(text: String) -> void:
	var json = JSON.new()
	if json.parse(text) != OK:
		print("[OnlineManager] Failed to parse WebSocket message")
		return

	var msg = json.data
	if not msg is Dictionary:
		return

	var msg_type = msg.get("type", "")

	match msg_type:
		"auth_ok":
			_ws_authenticated = true
			print("[OnlineManager] WebSocket authenticated as %s" % msg.get("handle", ""))
			websocket_connected.emit()

		"pong":
			pass  # Connection alive

		"error":
			print("[OnlineManager] WebSocket error: %s - %s" % [msg.get("code", ""), msg.get("message", "")])

		"file_changed":
			# Remote file change from another device
			var path = msg.get("path", "")
			var content = msg.get("content", "")
			var file_type = msg.get("file_type", "file")
			var program = msg.get("program", "")
			var metadata = msg.get("metadata", {})
			if metadata == null:
				metadata = {}
			print("[OnlineManager] Remote file change: %s" % path)
			file_changed_remote.emit(path, content, file_type, program, metadata)

		"file_deleted":
			# Remote file deletion from another device
			var path = msg.get("path", "")
			print("[OnlineManager] Remote file delete: %s" % path)
			file_deleted_remote.emit(path)

		"file_change_ok", "file_delete_ok", "mkdir_ok", "rmdir_ok":
			# Confirmation of our own change
			pass

		"sync_data":
			# Full sync response
			var files = msg.get("files", [])
			var fs_dict = {}
			for f in files:
				fs_dict[f.path] = {
					"type": f.type,
					"content": f.content,
					"program": f.get("program"),
					"metadata": f.get("metadata")
				}
			filesystem_fetched.emit(true, fs_dict)

		"versions_data":
			# Version history response
			var path = msg.get("path", "")
			var current = msg.get("current", {})
			var versions = msg.get("versions", [])
			versions_received.emit(path, current, versions)

		"version_restored":
			var path = msg.get("path", "")
			var version = msg.get("restored_version", 0)
			version_restored.emit(path, version)

		"scene_update_ok", "scene_changed", "scene_save_default_ok", "scene_load_response":
			# Scene configuration messages - forward to edit mode
			scene_config_received.emit(msg)


func disconnect_websocket() -> void:
	if _websocket != null:
		_websocket.close()
		_websocket = null
		_ws_connected = false
		_ws_authenticated = false


# ===== FILE OPERATIONS VIA WEBSOCKET =====

func create_or_update_file(path: String, content: String, file_type: String = "file", program: String = "", metadata: Dictionary = {}) -> void:
	"""Create or update a file via WebSocket (or HTTP fallback)"""
	if _ws_authenticated:
		var msg = {
			"type": "file_change",
			"path": path,
			"content": content,
			"file_type": file_type,
			"program": program if not program.is_empty() else null
		}
		if not metadata.is_empty():
			msg["metadata"] = metadata
		_ws_send(msg)
	else:
		# HTTP fallback
		_http_create_file(path, content, file_type, program, metadata)


func delete_file(path: String) -> void:
	"""Delete a file via WebSocket (or HTTP fallback)"""
	if _ws_authenticated:
		_ws_send({
			"type": "file_delete",
			"path": path
		})
	else:
		_http_delete_file(path)


func create_directory(path: String) -> void:
	"""Create a directory via WebSocket (or HTTP fallback)"""
	if _ws_authenticated:
		_ws_send({
			"type": "mkdir",
			"path": path
		})
	else:
		_http_create_dir(path)


func remove_directory(path: String) -> void:
	"""Remove a directory via WebSocket (or HTTP fallback)"""
	if _ws_authenticated:
		_ws_send({
			"type": "rmdir",
			"path": path
		})
	else:
		_http_remove_dir(path)


func request_sync(since_timestamp: int = 0) -> void:
	"""Request full sync via WebSocket"""
	if _ws_authenticated:
		_ws_send({
			"type": "request_sync",
			"since": since_timestamp if since_timestamp > 0 else null
		})


func get_file_versions(path: String) -> void:
	"""Get version history for a file"""
	if not is_online or session_token.is_empty():
		return

	if not _current_request.is_empty():
		return

	_current_request = "versions"
	var headers = ["X-Session-Token: " + session_token]
	# URL encode the path
	var encoded_path = path.uri_encode()
	var error = _http_request.request(
		server_url + "/versions/" + session_token + "/" + encoded_path,
		headers,
		HTTPClient.METHOD_GET
	)

	if error != OK:
		print("[OnlineManager] Failed to get versions: ", error)
		_current_request = ""


func restore_file_version(path: String, version: int) -> void:
	"""Restore a file to a previous version"""
	if not is_online or session_token.is_empty():
		return

	if not _current_request.is_empty():
		return

	_current_request = "restore"
	var headers = ["Content-Type: application/json", "X-Session-Token: " + session_token]
	var encoded_path = path.uri_encode()
	var error = _http_request.request(
		server_url + "/versions/" + session_token + "/" + encoded_path + "/restore/" + str(version),
		headers,
		HTTPClient.METHOD_POST
	)

	if error != OK:
		print("[OnlineManager] Failed to restore version: ", error)
		_current_request = ""


# ===== HTTP FALLBACK OPERATIONS =====

func _http_create_file(path: String, content: String, file_type: String, program: String, metadata: Dictionary = {}) -> void:
	if not is_online or session_token.is_empty():
		return
	if not _current_request.is_empty():
		return

	_current_request = "create_file"
	var data = {
		"path": path,
		"content": content,
		"file_type": file_type,
		"program": program if not program.is_empty() else null
	}
	if not metadata.is_empty():
		data["metadata"] = metadata
	var body = JSON.stringify(data)
	var headers = ["Content-Type: application/json", "X-Session-Token: " + session_token]
	_http_request.request(server_url + "/files/" + session_token, headers, HTTPClient.METHOD_POST, body)


func _http_delete_file(path: String) -> void:
	if not is_online or session_token.is_empty():
		return
	if not _current_request.is_empty():
		return

	_current_request = "delete_file"
	var headers = ["X-Session-Token: " + session_token]
	var encoded_path = path.uri_encode()
	_http_request.request(server_url + "/files/" + session_token + "/" + encoded_path, headers, HTTPClient.METHOD_DELETE)


func _http_create_dir(path: String) -> void:
	if not is_online or session_token.is_empty():
		return
	if not _current_request.is_empty():
		return

	_current_request = "create_dir"
	var body = JSON.stringify({"path": path})
	var headers = ["Content-Type: application/json", "X-Session-Token: " + session_token]
	_http_request.request(server_url + "/dirs/" + session_token, headers, HTTPClient.METHOD_POST, body)


func _http_remove_dir(path: String) -> void:
	if not is_online or session_token.is_empty():
		return
	if not _current_request.is_empty():
		return

	_current_request = "remove_dir"
	var headers = ["X-Session-Token: " + session_token]
	var encoded_path = path.uri_encode()
	_http_request.request(server_url + "/dirs/" + session_token + "/" + encoded_path, headers, HTTPClient.METHOD_DELETE)


# ===== LOCAL DATA PERSISTENCE =====

func _load_local_data() -> void:
	var config = ConfigFile.new()
	if config.load("user://online.cfg") == OK:
		is_registered = config.get_value("player", "registered", false)
		player_handle = config.get_value("player", "handle", "")
		player_phone = config.get_value("player", "phone", "")
		recovery_code = config.get_value("player", "recovery_code", "")
		session_token = config.get_value("player", "session_token", "")
		var has_session = "yes" if not session_token.is_empty() else "no"
		print("[OnlineManager] Loaded local data: registered=%s, handle=%s, has_session=%s" % [is_registered, player_handle, has_session])


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
	var status_changed = is_online != online
	is_online = online

	if online:
		# Reset backoff on successful connection
		_consecutive_failures = 0
		_ever_connected = true
		_current_check_interval = CHECK_INTERVAL_BASE
		_logged_offline = false
		if status_changed:
			print("[OnlineManager] Connection status: ONLINE")
			connection_status_changed.emit(online)
			# Try to connect WebSocket when coming online
			if not session_token.is_empty() and not _ws_connected:
				_connect_websocket()
	else:
		# Increase backoff on failure
		_consecutive_failures += 1
		if _ever_connected:
			# Slower backoff if we've connected before (network went down)
			_current_check_interval = min(CHECK_INTERVAL_BASE * pow(2, _consecutive_failures - 1), CHECK_INTERVAL_MAX)
		else:
			# Fast retries during initial connection attempts (3s, 5s, 8s, 12s...)
			_current_check_interval = min(CHECK_INTERVAL_INITIAL + (_consecutive_failures * 2), 15.0)
		if status_changed or not _logged_offline:
			print("[OnlineManager] Connection status: OFFLINE (retry in %.0fs)" % _current_check_interval)
			_logged_offline = true
			if status_changed:
				connection_status_changed.emit(online)
				# Disconnect WebSocket when going offline
				disconnect_websocket()


# ===== HANDLE CHECK =====

signal handle_check_complete(available: bool, data: Dictionary)
signal email_check_complete(available: bool, data: Dictionary)

func check_handle_available(handle: String) -> void:
	"""Check if a handle is available for registration"""
	if not _current_request.is_empty():
		print("[OnlineManager] Request already in progress")
		return

	if not is_online:
		print("[OnlineManager] Cannot check handle: not online")
		handle_check_complete.emit(false, {"error": "OFFLINE"})
		return

	_current_request = "check_handle"
	var headers = ["Content-Type: application/json"]
	var error = _http_request.request(server_url + "/player/" + handle.uri_encode(), headers, HTTPClient.METHOD_GET)

	if error != OK:
		print("[OnlineManager] Failed to check handle: ", error)
		_current_request = ""
		handle_check_complete.emit(false, {"error": "REQUEST_FAILED"})


func check_email_available(email: String) -> void:
	"""Check if an email is available for registration"""
	if not _current_request.is_empty():
		print("[OnlineManager] Request already in progress")
		return

	if not is_online:
		print("[OnlineManager] Cannot check email: not online")
		email_check_complete.emit(false, {"error": "OFFLINE"})
		return

	_current_request = "check_email"
	var headers = ["Content-Type: application/json"]
	var error = _http_request.request(server_url + "/email/" + email.uri_encode(), headers, HTTPClient.METHOD_GET)

	if error != OK:
		print("[OnlineManager] Failed to check email: ", error)
		_current_request = ""
		email_check_complete.emit(false, {"error": "REQUEST_FAILED"})


# ===== REGISTRATION =====

func register_player(handle: String, email: String = "") -> void:
	"""Register a new player with the server"""
	if not _current_request.is_empty():
		print("[OnlineManager] Request already in progress")
		return

	if not is_online:
		print("[OnlineManager] Cannot register: not online")
		registration_complete.emit(false, {"error": "OFFLINE", "message": "Network connection required"})
		return

	_current_request = "register"
	var body = JSON.stringify({
		"handle": handle,
		"email": email,
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


# ===== FILESYSTEM SYNC (Legacy HTTP) =====

func sync_filesystem(filesystem: Dictionary) -> void:
	"""Sync filesystem to server (full replacement - legacy)"""
	if not is_online or session_token.is_empty():
		print("[OnlineManager] Cannot sync: offline or no session")
		return

	if not _current_request.is_empty():
		print("[OnlineManager] Request already in progress, queuing sync")
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
		# Only log non-status failures to reduce spam
		if request_type != "status":
			print("[OnlineManager] Request failed: %s (result=%d)" % [request_type, result])
		_set_online(false)
		_handle_request_error(request_type, {"error": "CONNECTION_FAILED"})
		return

	# Parse response
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	var data: Dictionary = {}
	if parse_result == OK:
		data = json.data if json.data is Dictionary else {}

	# Only log non-status responses to reduce spam
	if request_type != "status":
		print("[OnlineManager] %s response: %d" % [request_type, response_code])

	# Handle based on request type
	match request_type:
		"status":
			_set_online(response_code == 200)
		"check_handle":
			_handle_check_handle_response(response_code, data)
		"check_email":
			_handle_check_email_response(response_code, data)
		"register":
			_handle_registration_response(response_code, data)
		"recover":
			_handle_recovery_response(response_code, data)
		"sync":
			_handle_sync_response(response_code, data)
		"fetch":
			_handle_fetch_response(response_code, data)
		"versions":
			_handle_versions_response(response_code, data)
		"restore":
			_handle_restore_response(response_code, data)
		"create_file", "delete_file", "create_dir", "remove_dir":
			# HTTP fallback operations - just log
			if response_code != 200:
				print("[OnlineManager] %s failed: %s" % [request_type, data.get("error", "UNKNOWN")])


func _handle_request_error(request_type: String, error_data: Dictionary) -> void:
	match request_type:
		"check_handle":
			handle_check_complete.emit(false, error_data)
		"check_email":
			email_check_complete.emit(false, error_data)
		"register":
			registration_complete.emit(false, error_data)
		"recover":
			recovery_complete.emit(false, error_data)
		"sync":
			sync_complete.emit(false)


func _handle_check_handle_response(response_code: int, data: Dictionary) -> void:
	if response_code == 404:
		# Handle not found = available
		handle_check_complete.emit(true, {"available": true})
	else:
		# Handle exists = taken
		handle_check_complete.emit(false, {"available": false, "error": "HANDLE_TAKEN"})


func _handle_check_email_response(response_code: int, data: Dictionary) -> void:
	if response_code == 404:
		# Email not found = available
		email_check_complete.emit(true, {"available": true})
	else:
		# Email exists = taken
		email_check_complete.emit(false, {"available": false, "error": "EMAIL_TAKEN"})


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
		# Connect WebSocket after successful registration
		_connect_websocket()
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
		# Connect WebSocket after successful recovery
		_connect_websocket()
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


func _handle_versions_response(response_code: int, data: Dictionary) -> void:
	if response_code == 200:
		var path = data.get("path", "")
		var current = data.get("current", {})
		var versions = data.get("versions", [])
		versions_received.emit(path, current, versions)
	else:
		print("[OnlineManager] Versions fetch failed: %s" % data.get("error", "UNKNOWN"))


func _handle_restore_response(response_code: int, data: Dictionary) -> void:
	if response_code == 200:
		var path = data.get("path", "")
		var version = data.get("restored_version", 0)
		version_restored.emit(path, version)
	else:
		print("[OnlineManager] Version restore failed: %s" % data.get("error", "UNKNOWN"))


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
	disconnect_websocket()
	var dir = DirAccess.open("user://")
	if dir:
		dir.remove("online.cfg")
		dir.remove("browser_id.cfg")
	print("[OnlineManager] Local data cleared")


func is_websocket_connected() -> bool:
	return _ws_authenticated
