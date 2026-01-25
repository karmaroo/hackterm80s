extends Node
## Settings Manager - Handles persistent settings including API keys
## Uses Godot's user:// storage (localStorage in web builds)

const SETTINGS_FILE = "user://settings.cfg"

var _config: ConfigFile

# Settings
var openai_api_key: String = ""
var ai_hosts_enabled: bool = false


func _ready() -> void:
	_config = ConfigFile.new()
	load_settings()


func load_settings() -> void:
	var err = _config.load(SETTINGS_FILE)
	if err == OK:
		openai_api_key = _config.get_value("api", "openai_key", "")
		ai_hosts_enabled = _config.get_value("features", "ai_hosts", false)
		print("[Settings] Loaded - AI hosts: ", ai_hosts_enabled)
	else:
		print("[Settings] No settings file, using defaults")


func save_settings() -> void:
	_config.set_value("api", "openai_key", openai_api_key)
	_config.set_value("features", "ai_hosts", ai_hosts_enabled)
	_config.save(SETTINGS_FILE)
	print("[Settings] Saved")


func set_openai_key(key: String) -> void:
	openai_api_key = key
	ai_hosts_enabled = not key.is_empty()
	save_settings()


func has_openai_key() -> bool:
	return not openai_api_key.is_empty()
