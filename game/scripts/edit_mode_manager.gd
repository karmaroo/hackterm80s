extends Node
## Edit Mode Manager - Visual scene editor with asset library, context menus, and undo/redo

signal edit_mode_changed(enabled: bool)

# Item types for visual categorization
enum ItemType { BUTTON, INDICATOR, OBJECT, LIGHT }

# Zoom level constants - 0 means "all levels"
const ZOOM_ALL = 0
const ZOOM_ROOM = 1
const ZOOM_DESKTOP = 2
const ZOOM_MONITOR = 3
const ZOOM_SCREEN = 4

const ZOOM_LEVEL_NAMES = {
	ZOOM_ALL: "All",
	ZOOM_ROOM: "Room",
	ZOOM_DESKTOP: "Desktop",
	ZOOM_MONITOR: "Monitor",
	ZOOM_SCREEN: "Screen",
}

# Colors for each item type
const TYPE_COLORS = {
	ItemType.BUTTON: Color(0.0, 0.8, 1.0, 0.8),     # Cyan - clickable buttons
	ItemType.INDICATOR: Color(1.0, 0.5, 0.0, 0.8),  # Orange - LED indicators
	ItemType.OBJECT: Color(0.8, 0.8, 0.2, 0.8),     # Yellow - draggable objects
	ItemType.LIGHT: Color(1.0, 1.0, 0.5, 0.8),      # Bright yellow - lights
}

const TYPE_NAMES = {
	ItemType.BUTTON: "Button",
	ItemType.INDICATOR: "Indicator",
	ItemType.OBJECT: "Object",
	ItemType.LIGHT: "Light",
}

# UI Theme colors - Modern dark theme with depth
const THEME_BG = Color(0.067, 0.067, 0.090, 0.98)          # Base background
const THEME_BG_SURFACE = Color(0.094, 0.094, 0.118, 0.98)  # Panel surfaces
const THEME_BG_ELEVATED = Color(0.118, 0.118, 0.145, 0.98) # Elevated elements
const THEME_BG_HOVER = Color(0.157, 0.165, 0.196, 0.95)    # Hover states
const THEME_BG_ACTIVE = Color(0.12, 0.22, 0.18, 0.95)      # Active/selected bg
const THEME_BORDER = Color(0.0, 0.7, 0.4, 0.9)             # Primary border
const THEME_BORDER_SUBTLE = Color(0.25, 0.28, 0.32, 0.5)   # Subtle dividers
const THEME_BORDER_FOCUS = Color(0.0, 0.85, 0.5, 1.0)      # Focus ring
const THEME_ACCENT = Color(0.0, 1.0, 0.5, 1.0)             # Primary accent
const THEME_ACCENT_DIM = Color(0.0, 0.6, 0.35, 0.8)        # Dimmed accent
const THEME_TEXT = Color(0.92, 0.94, 0.92, 1.0)            # Primary text
const THEME_TEXT_DIM = Color(0.55, 0.58, 0.55, 1.0)        # Secondary text
const THEME_TEXT_MUTED = Color(0.40, 0.42, 0.40, 0.7)      # Muted text
const THEME_DANGER = Color(0.95, 0.35, 0.35, 1.0)          # Danger/delete
const THEME_SUCCESS = Color(0.3, 0.9, 0.5, 1.0)            # Success
const THEME_WARNING = Color(1.0, 0.75, 0.25, 1.0)          # Warning

# Icon types for programmatic drawing
enum IconType {
	NONE,
	UNDO,
	REDO,
	DUPLICATE,
	DELETE,
	HIDE,
	SHOW,
	MOVE_UP,
	MOVE_DOWN,
	BRING_FRONT,
	SEND_BACK,
	EXPAND,
	COLLAPSE,
	SAVE,
	CHECK,
	CROSS,
	ALIGN_LEFT,
	ALIGN_CENTER_H,
	ALIGN_RIGHT,
	ALIGN_TOP,
	ALIGN_CENTER_V,
	ALIGN_BOTTOM,
	GRID,
	SNAP,
	GROUP,
	UNGROUP,
	FOLDER,
	LIGHT_BULB,
	GUIDE,
}

# Edit mode state
var edit_mode_enabled: bool = false
var selected_element = null  # Can be Control or Node2D (including lights)
var selected_item: Dictionary = {}
var hovered_element = null  # Can be Control or Node2D
var is_dragging: bool = false
var is_resizing: bool = false
var resize_corner: int = -1
var drag_start_mouse: Vector2 = Vector2.ZERO
var drag_start_offsets: Dictionary = {}
var drag_start_size: Vector2 = Vector2.ZERO
var multi_drag_start_offsets: Array[Dictionary] = []  # Stores {element, offsets} for each multi-selected item

# Zoom level filter for edit mode (0 = show all, 1-4 = show specific level)
var current_zoom_filter: int = ZOOM_ALL

# Hidden elements (deleted from view)
var hidden_elements: Dictionary = {}  # path -> true

# Undo/Redo system
var undo_stack: Array[Dictionary] = []  # Stack of actions that can be undone
var redo_stack: Array[Dictionary] = []  # Stack of actions that can be redone
const MAX_UNDO_HISTORY = 50

# Copy tracking for duplicates
var copy_counter: Dictionary = {}  # base_path -> count

# Edit mode zoom and pan
var edit_zoom_level: float = 1.0
var edit_zoom_offset: Vector2 = Vector2.ZERO  # Used for zoom-to-point calculations
var pan_offset: Vector2 = Vector2.ZERO         # Actual pan translation
var is_panning: bool = false
var pan_start_mouse: Vector2 = Vector2.ZERO
var pan_start_offset: Vector2 = Vector2.ZERO
var is_marquee_selecting: bool = false
var marquee_start: Vector2 = Vector2.ZERO
var marquee_current: Vector2 = Vector2.ZERO
var marquee_overlay: Control = null
var base_game_scale: Vector2 = Vector2.ONE
var base_game_pivot: Vector2 = Vector2.ZERO
var base_game_position: Vector2 = Vector2.ZERO  # Store original container position
const EDIT_ZOOM_MIN: float = 0.3
const EDIT_ZOOM_MAX: float = 5.0
const EDIT_ZOOM_STEP: float = 0.15

# Original positions backup
var original_positions: Dictionary = {}
var modified_elements: Dictionary = {}

# References
var main_node: Control = null
var zoom_container: Control = null
var zoom_manager: Node = null

# Overlay UI elements
var overlay: CanvasLayer = null
var toolbar: Panel = null
var asset_library: Panel = null
var asset_list: VBoxContainer = null
var properties_panel: Panel = null
var status_bar: Panel = null
var selection_outline: Control = null
var hover_outline: Control = null
var type_highlights: Control = null
var item_labels: Control = null
var context_menu: PopupMenu = null
var library_context_menu: PopupMenu = null
var zoom_filter_label: Label = null

# Context menu item for library
var library_context_item: Dictionary = {}

# Asset library filter
var library_filter: String = ""
var library_type_filter: int = -1
var library_tab: int = 0  # 0 = Library, 1 = In Scene
var library_tab_btn: Button = null
var scene_tab_btn: Button = null
var library_scroll: ScrollContainer = null
var scene_scroll: ScrollContainer = null
var scene_tree: VBoxContainer = null
var tree_expanded_paths: Dictionary = {}  # Track which tree paths are expanded
var tree_all_expanded: bool = true  # Track if tree is fully expanded (for toggle button)

# HTTP requests for saving
var _http_save_session: HTTPRequest = null
var _http_save_default: HTTPRequest = null
var _http_load_config: HTTPRequest = null
var _save_status: String = ""  # "", "saving", "success", "error"
var _save_message: String = ""
var _status_timer: float = 0.0
const STATUS_DISPLAY_TIME: float = 3.0

# Connection status tracking
var _last_online_state: bool = false
var _last_ws_state: bool = false
var _connection_check_timer: float = 0.0
const CONNECTION_CHECK_INTERVAL: float = 0.5  # Check every 500ms

# Admin key for saving default (can be overridden via environment or config)
var admin_key: String = "hackterm-admin-2024"

# Auto-save state
var _scene_dirty: bool = false
var _scene_debounce_timer: Timer = null
const SCENE_DEBOUNCE_SECONDS: float = 1.0
var confirmation_modal: Control = null

# Editable properties panel controls
var prop_pos_x: SpinBox = null
var prop_pos_y: SpinBox = null
var prop_size_w: SpinBox = null
var prop_size_h: SpinBox = null
var prop_rotation: SpinBox = null
var prop_opacity: HSlider = null
var prop_z_index: SpinBox = null
var _updating_properties: bool = false  # Prevent feedback loops

# Light-specific property controls
var light_section: VBoxContainer = null
var prop_light_energy: SpinBox = null
var prop_light_color: ColorPickerButton = null
var prop_light_texture_scale: SpinBox = null
var prop_light_shadow: CheckButton = null
var prop_light_shadow_color: ColorPickerButton = null
var prop_light_blend_mode: OptionButton = null

# ColorRect-specific property controls
var colorrect_section: VBoxContainer = null
var prop_colorrect_color: ColorPickerButton = null

# TextureRect-specific property controls
var texturerect_section: VBoxContainer = null
var prop_texture_path: Label = null
var prop_texture_flip_h: CheckButton = null
var prop_texture_flip_v: CheckButton = null
var prop_texture_stretch_mode: OptionButton = null

# Label/RichTextLabel property controls
var label_section: VBoxContainer = null
var prop_label_text: LineEdit = null

# Panel property controls
var panel_section: VBoxContainer = null
var prop_panel_self_modulate: ColorPickerButton = null

# Smart guides and snapping
var smart_guides_overlay: Control = null
var guide_lines: Array[Dictionary] = []
var snap_enabled: bool = true
var grid_enabled: bool = false
var guides_enabled: bool = true
var grid_size: int = 20
var snap_threshold: float = 8.0
var snap_toggle_btn: Button = null
var grid_toggle_btn: Button = null
var guides_toggle_btn: Button = null

# Multi-selection for alignment
var multi_selected: Array = []
var is_box_selecting: bool = false
var box_select_start: Vector2 = Vector2.ZERO

# Element locking
var locked_elements: Dictionary = {}  # path -> bool
var prop_lock_toggle: CheckButton = null

# Custom element names
var custom_names: Dictionary = {}  # path -> custom_name

# Container/group system
var container_nodes: Dictionary = {}  # path -> container data

# Editable elements configuration (templates for creating copies)
# Note: These paths are relative to ZoomContainer (nodes are reparented there at runtime)
# zoom_levels: 0 = all levels, or array like [1], [1,2], [2,3,4] for specific levels
var editable_config: Array[Dictionary] = [
	# Room/Background - only visible at room level
	{"path": "Background", "type": ItemType.OBJECT, "category": "Room", "zoom_levels": [1, 2]},

	# Furniture - visible at room and desktop
	{"path": "Desk", "type": ItemType.OBJECT, "category": "Furniture", "zoom_levels": [1, 2]},
	{"path": "WoodShelf1", "type": ItemType.OBJECT, "category": "Furniture", "zoom_levels": [1, 2]},
	{"path": "WoodShelf2", "type": ItemType.OBJECT, "category": "Furniture", "zoom_levels": [1, 2]},

	# Computer - Main Frame - visible at desktop and monitor levels
	{"path": "ComputerFrame", "type": ItemType.OBJECT, "category": "Computer", "zoom_levels": [1, 2, 3]},
	{"path": "ComputerFrame/ComputerAndKeyboardImage", "type": ItemType.OBJECT, "category": "Computer", "zoom_levels": [1, 2, 3]},

	# Computer - Monitor - visible at multiple levels
	{"path": "ComputerFrame/Monitor", "type": ItemType.OBJECT, "category": "Monitor", "zoom_levels": [2, 3, 4]},
	{"path": "ComputerFrame/MonitorFrame", "type": ItemType.OBJECT, "category": "Monitor", "zoom_levels": [2, 3]},
	{"path": "ComputerFrame/Monitor/ControlPanel", "type": ItemType.OBJECT, "category": "Monitor", "zoom_levels": [2, 3]},
	{"path": "ComputerFrame/Monitor/ControlPanel/PowerButton", "type": ItemType.BUTTON, "category": "Monitor", "zoom_levels": [2, 3]},
	{"path": "ComputerFrame/Monitor/ControlPanel/PowerLED", "type": ItemType.INDICATOR, "category": "Monitor", "zoom_levels": [2, 3]},
	{"path": "ComputerFrame/Monitor/ScreenOffOverlay", "type": ItemType.OBJECT, "category": "Monitor", "zoom_levels": [2, 3, 4]},
	{"path": "ComputerFrame/Monitor/TerminalView", "type": ItemType.OBJECT, "category": "Monitor", "zoom_levels": [2, 3, 4]},

	# Computer - Base Unit - visible at desktop and monitor
	{"path": "ComputerFrame/BaseUnit", "type": ItemType.OBJECT, "category": "BaseUnit", "zoom_levels": [1, 2, 3]},
	{"path": "ComputerFrame/BaseUnit/FloppyBayA", "type": ItemType.OBJECT, "category": "BaseUnit", "zoom_levels": [2, 3]},
	{"path": "ComputerFrame/BaseUnit/FloppyBayB", "type": ItemType.OBJECT, "category": "BaseUnit", "zoom_levels": [2, 3]},
	{"path": "ComputerFrame/BaseUnit/VentGrille", "type": ItemType.OBJECT, "category": "BaseUnit", "zoom_levels": [2, 3]},
	{"path": "ComputerFrame/BaseUnit/TurboBtn", "type": ItemType.BUTTON, "category": "BaseUnit", "zoom_levels": [2, 3]},
	{"path": "ComputerFrame/BaseUnit/ResetBtn", "type": ItemType.BUTTON, "category": "BaseUnit", "zoom_levels": [2, 3]},
	{"path": "ComputerFrame/BaseUnit/LEDPanel", "type": ItemType.OBJECT, "category": "BaseUnit", "zoom_levels": [2, 3]},
	{"path": "ComputerFrame/BaseUnit/BrandPanel", "type": ItemType.OBJECT, "category": "BaseUnit", "zoom_levels": [2, 3]},
	{"path": "ComputerFrame/BasePowerButton", "type": ItemType.BUTTON, "category": "BaseUnit", "zoom_levels": [1, 2, 3]},
	{"path": "ComputerFrame/BasePowerLED", "type": ItemType.INDICATOR, "category": "BaseUnit", "zoom_levels": [1, 2, 3]},
	{"path": "ComputerFrame/BaseHDDLED", "type": ItemType.INDICATOR, "category": "BaseUnit", "zoom_levels": [1, 2, 3]},

	# Computer - Keyboard - visible at desktop and monitor
	{"path": "ComputerFrame/Keyboard", "type": ItemType.OBJECT, "category": "Keyboard", "zoom_levels": [1, 2, 3]},

	# Decor Items - mostly desktop level
	{"path": "ComputerFrame/TapedNote", "type": ItemType.OBJECT, "category": "Decor", "zoom_levels": [2, 3]},
	{"path": "WargamesPoster", "type": ItemType.OBJECT, "category": "Decor", "zoom_levels": [1]},
	{"path": "LavaLamp", "type": ItemType.OBJECT, "category": "Decor", "zoom_levels": [1, 2]},
	{"path": "LavaLamp/LampBody", "type": ItemType.OBJECT, "category": "Decor", "zoom_levels": [1, 2]},
	{"path": "LavaLamp/PowerButton", "type": ItemType.BUTTON, "category": "Decor", "zoom_levels": [1, 2]},
	{"path": "LavaLamp/PowerLED", "type": ItemType.INDICATOR, "category": "Decor", "zoom_levels": [1, 2]},
	{"path": "LEDClock", "type": ItemType.OBJECT, "category": "Decor", "zoom_levels": [1, 2]},

	# Equipment - desktop level
	{"path": "DeskPhone", "type": ItemType.OBJECT, "category": "Equipment", "zoom_levels": [1, 2]},
	{"path": "HayesModem", "type": ItemType.OBJECT, "category": "Equipment", "zoom_levels": [1, 2]},
	{"path": "HayesModem/Body", "type": ItemType.OBJECT, "category": "Equipment", "zoom_levels": [1, 2]},
	{"path": "HayesModem/Body/LEDPanel", "type": ItemType.OBJECT, "category": "Equipment", "zoom_levels": [1, 2]},

	# RoomElements container (dynamically created by ZoomManager) - room level only
	{"path": "RoomElements", "type": ItemType.OBJECT, "category": "Room", "zoom_levels": [1]},

	# Room Elements - Window and blinds (created by ZoomManager)
	{"path": "RoomElements/Window", "type": ItemType.OBJECT, "category": "Window", "zoom_levels": [1]},
	{"path": "RoomElements/WindowSill", "type": ItemType.OBJECT, "category": "Window", "zoom_levels": [1]},
	{"path": "RoomElements/BlindCord", "type": ItemType.OBJECT, "category": "Window", "zoom_levels": [1]},
	{"path": "RoomElements/CordPull", "type": ItemType.OBJECT, "category": "Window", "zoom_levels": [1]},

	# Room Elements - Shelves (created by ZoomManager)
	{"path": "RoomElements/ShelfUpper", "type": ItemType.OBJECT, "category": "Shelves", "zoom_levels": [1]},
	{"path": "RoomElements/ShelfExt1", "type": ItemType.OBJECT, "category": "Shelves", "zoom_levels": [1]},
	{"path": "RoomElements/ShelfExt2", "type": ItemType.OBJECT, "category": "Shelves", "zoom_levels": [1]},
	{"path": "RoomElements/HackBooks", "type": ItemType.OBJECT, "category": "Shelves", "zoom_levels": [1]},
	{"path": "RoomElements/TechBooks", "type": ItemType.OBJECT, "category": "Shelves", "zoom_levels": [1]},

	# Room Elements - Floor
	{"path": "RoomElements/Floor", "type": ItemType.OBJECT, "category": "Room", "zoom_levels": [1]},
	{"path": "RoomElements/Baseboard", "type": ItemType.OBJECT, "category": "Room", "zoom_levels": [1]},

	# Room Elements - Light switch
	{"path": "RoomElements/LightSwitchPlate", "type": ItemType.OBJECT, "category": "Room", "zoom_levels": [1]},
	{"path": "RoomElements/LightSwitch", "type": ItemType.BUTTON, "category": "Room", "zoom_levels": [1]},

	# Desk Extensions (created by ZoomManager)
	{"path": "DeskExtensions", "type": ItemType.OBJECT, "category": "Furniture", "zoom_levels": [1]},
	{"path": "DeskExtensions/DeskExtLeft", "type": ItemType.OBJECT, "category": "Furniture", "zoom_levels": [1]},
	{"path": "DeskExtensions/DeskExtRight", "type": ItemType.OBJECT, "category": "Furniture", "zoom_levels": [1]},
	{"path": "DeskExtensions/OutletPlate", "type": ItemType.OBJECT, "category": "Room", "zoom_levels": [1]},
]

var editable_elements: Array[Dictionary] = []


func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	_setup_edit_mode()


func _setup_edit_mode() -> void:
	main_node = get_parent() as Control
	if not main_node:
		print("[EditMode] ERROR: Parent is not a Control node")
		return

	zoom_container = main_node.get_node_or_null("ZoomContainer")
	if not zoom_container:
		print("[EditMode] ERROR: ZoomContainer not found!")
		return

	zoom_manager = main_node.get_node_or_null("ZoomManager")
	if zoom_manager:
		print("[EditMode] ZoomManager found")

	_resolve_editable_elements()
	_backup_original_positions()
	_create_overlay()
	_setup_http_requests()
	_setup_auto_save()

	print("[EditMode] Initialized with %d editable elements" % editable_elements.size())


func _setup_http_requests() -> void:
	# HTTPRequest for saving to session (player-specific)
	_http_save_session = HTTPRequest.new()
	_http_save_session.timeout = 10.0
	_http_save_session.request_completed.connect(_on_save_session_completed)
	add_child(_http_save_session)

	# HTTPRequest for saving to default (master config)
	_http_save_default = HTTPRequest.new()
	_http_save_default.timeout = 10.0
	_http_save_default.request_completed.connect(_on_save_default_completed)
	add_child(_http_save_default)

	# HTTPRequest for loading config
	_http_load_config = HTTPRequest.new()
	_http_load_config.timeout = 10.0
	_http_load_config.request_completed.connect(_on_load_config_completed)
	add_child(_http_load_config)


func _setup_auto_save() -> void:
	# Set up auto-save debounce timer
	_scene_debounce_timer = Timer.new()
	_scene_debounce_timer.one_shot = true
	_scene_debounce_timer.wait_time = SCENE_DEBOUNCE_SECONDS
	_scene_debounce_timer.timeout.connect(_on_scene_debounce_timeout)
	add_child(_scene_debounce_timer)

	# Connect WebSocket signals for scene sync
	if OnlineManager:
		OnlineManager.scene_config_received.connect(_handle_ws_scene_message)
		OnlineManager.websocket_connected.connect(_on_ws_connected)
		OnlineManager.connection_status_changed.connect(_on_connection_status_changed)

		# Check if WebSocket is already connected (we may have missed the signal)
		# Load scene config on startup if player has a session
		_load_initial_scene_config()


func _load_initial_scene_config() -> void:
	"""Load scene config on startup - tries WebSocket first, falls back to HTTP"""
	if _initial_config_loaded:
		return  # Already loaded or loading

	if not OnlineManager:
		return

	# If we have a session token, try to load player-specific config
	if not OnlineManager.session_token.is_empty():
		# If WebSocket is already connected and authenticated, load via WS
		if OnlineManager.is_websocket_connected():
			print("[EditMode] WebSocket connected, requesting scene config")
			OnlineManager._ws_send({"type": "scene_load", "config_name": "default"})
			return

		# Otherwise, if online, load via HTTP
		if OnlineManager.is_online:
			print("[EditMode] Loading scene config via HTTP")
			_load_from_session()
			return

	# No session token - try loading master default config if online
	if OnlineManager.is_online:
		print("[EditMode] No session token, loading master default config")
		_load_default_config()
	else:
		print("[EditMode] Offline with no session, using scene defaults")


func _mark_scene_dirty() -> void:
	"""Mark scene config as dirty and start debounce timer"""
	_scene_dirty = true

	# Reset/start debounce timer
	if _scene_debounce_timer:
		_scene_debounce_timer.stop()
		_scene_debounce_timer.start()


func _on_scene_debounce_timeout() -> void:
	"""Called when debounce timer fires - send config to server"""
	print("[EditMode] Debounce timeout fired, dirty=%s" % _scene_dirty)
	if not _scene_dirty:
		return

	# Check if we have a valid session
	if not OnlineManager or OnlineManager.session_token.is_empty():
		print("[EditMode] No session token, skipping save")
		_scene_dirty = false  # Clear dirty flag - can't save without session
		return

	print("[EditMode] WS connected=%s" % OnlineManager.is_websocket_connected())
	if OnlineManager.is_websocket_connected():
		_send_scene_update_ws()
	else:
		# Fallback to HTTP save
		_save_to_session_http()


func _send_scene_update_ws() -> void:
	"""Send scene update via WebSocket - only sends modified elements"""
	if not OnlineManager or not OnlineManager.is_websocket_connected():
		print("[EditMode] WS send aborted - not connected")
		return

	# Build current copies list from editable_elements
	# Only include "parent" copies, not children (children are auto-created when parent is duplicated)
	var current_copies = []
	var copy_paths: Array[String] = []
	# First pass: collect all copy paths
	for item in editable_elements:
		if item.get("is_copy", false):
			copy_paths.append(item["path"])
	# Second pass: only include copies that aren't children of other copies
	for item in editable_elements:
		if item.get("is_copy", false):
			var item_path = item["path"]
			var is_child_of_copy = false
			for other_path in copy_paths:
				# Check if this item's path starts with another copy's path + "/"
				if item_path != other_path and item_path.begins_with(other_path + "/"):
					is_child_of_copy = true
					break
			if not is_child_of_copy:
				current_copies.append({
					"path": item["path"],
					"source_path": item.get("source_path", ""),
					"type": item.get("type", ItemType.OBJECT),
					"category": item.get("category", "Other"),
				})

	# Only include modified elements to reduce payload size
	var delta_config = {
		"version": 2,
		"timestamp": Time.get_unix_time_from_system(),
		"elements": {},
		"hidden": hidden_elements.keys(),
		"locked": locked_elements.keys(),
		"copies": current_copies,  # Always send full copies list
		"custom_names": custom_names.duplicate(),  # Include custom names
		"is_delta": true,  # Tell server this is a partial update
	}

	# Only add elements that were actually modified
	for path in modified_elements.keys():
		for item in editable_elements:
			if item["path"] == path:
				var element = item["element"]
				if element:
					delta_config["elements"][path] = _get_element_config(element, item)
				break

	print("[EditMode] Sending WS update with %d modified elements, %d copies" % [delta_config["elements"].size(), current_copies.size()])

	var msg = {
		"type": "scene_update",
		"config": delta_config,
		"config_name": "default"
	}

	OnlineManager._ws_send(msg)
	_scene_dirty = false
	_set_save_status("saving", "Saving...")


func _save_to_session_http() -> void:
	"""HTTP fallback for auto-save when WebSocket not connected"""
	if not OnlineManager:
		_set_save_status("", "")  # Silent - no manager
		return

	if not OnlineManager.is_online:
		_set_save_status("", "")  # Silent when offline - changes kept locally
		return

	if OnlineManager.session_token.is_empty():
		_set_save_status("", "")  # Silent - not logged in yet
		return

	var config = get_scene_config()
	var payload = {
		"token": OnlineManager.session_token,
		"config_name": "default",
		"config": config
	}

	var json = JSON.stringify(payload)
	var headers = [
		"Content-Type: application/json",
		"X-Session-Token: " + OnlineManager.session_token
	]
	var url = OnlineManager.server_url + "/scene/save"

	var err = _http_save_session.request(url, headers, HTTPClient.METHOD_POST, json)
	if err != OK:
		_set_save_status("error", "Save failed")
		print("[EditMode] HTTP save request error: %d" % err)
	else:
		_scene_dirty = false
		_set_save_status("saving", "Saving...")


func _on_ws_connected() -> void:
	"""Called when WebSocket connects - request current config"""
	if OnlineManager and OnlineManager._ws_authenticated:
		OnlineManager._ws_send({"type": "scene_load", "config_name": "default"})


var _initial_config_loaded: bool = false

func _on_connection_status_changed(online: bool) -> void:
	"""Called when connection status changes - load config when first coming online"""
	if online and not _initial_config_loaded:
		# First time coming online, try to load config
		if OnlineManager and not OnlineManager.session_token.is_empty():
			print("[EditMode] Now online, loading scene config")
			_load_initial_scene_config()
			_initial_config_loaded = true


func _handle_ws_scene_message(msg: Dictionary) -> void:
	"""Handle scene-related WebSocket messages"""
	var msg_type = msg.get("type", "")

	match msg_type:
		"scene_update_ok":
			_set_save_status("success", "Auto-saved")
			print("[EditMode] Scene auto-saved")

		"scene_changed":
			# Another session changed the scene
			var config = msg.get("config", {})
			if not config.is_empty():
				print("[EditMode] Remote scene change received")
				apply_scene_config(config)

		"scene_save_default_ok":
			_set_save_status("success", "Default saved!")
			_close_confirmation_modal()

		"scene_load_response":
			var config = msg.get("config")
			if config and config is Dictionary and not config.is_empty():
				apply_scene_config(config)
				_initial_config_loaded = true
				var is_default = msg.get("is_default", false)
				print("[EditMode] Loaded %s config via WebSocket" % ("default" if is_default else "session"))
			else:
				_initial_config_loaded = true
				print("[EditMode] No saved config found (using scene defaults)")


func _resolve_editable_elements() -> void:
	editable_elements.clear()

	# First, add all configured items (templates)
	var configured_paths: Dictionary = {}
	for config in editable_config:
		var path = config["path"]
		configured_paths[path] = config
		var element: Control = null

		if zoom_container:
			element = zoom_container.get_node_or_null(path)

		# Include all configured items, even if element doesn't exist yet
		# This allows showing templates in asset library
		var zoom_levels = config.get("zoom_levels", [1, 2, 3, 4])  # Default to all levels
		editable_elements.append({
			"element": element,  # May be null for uninstantiated templates
			"type": config["type"],
			"path": path,
			"category": config.get("category", "Other"),
			"zoom_levels": zoom_levels,
			"is_copy": false,
			"exists": element != null,
		})

	# Then, auto-discover all Control children in ZoomContainer that aren't configured
	if zoom_container:
		_discover_controls(zoom_container, "", configured_paths)


func _discover_controls(node: Node, parent_path: String, configured_paths: Dictionary) -> void:
	"""Recursively discover all Control and Node2D nodes under ZoomContainer"""
	for child in node.get_children():
		# Skip if not a visual node we can edit
		var is_control = child is Control
		var is_node2d = child is Node2D
		# Check for actual Godot light nodes (not just names containing "light")
		var is_light = (child is PointLight2D or child is DirectionalLight2D or
			child is Light2D or child is CanvasModulate or child is LightOccluder2D)

		if not is_control and not is_node2d:
			continue

		var child_path = child.name if parent_path.is_empty() else parent_path + "/" + child.name

		# Skip if already configured
		if configured_paths.has(child_path):
			_discover_controls(child, child_path, configured_paths)
			continue

		# Auto-classify based on name and node type
		var item_type = ItemType.OBJECT
		var category = "Discovered"
		var zoom_levels = [1, 2, 3, 4]  # Default: visible at all levels

		# Check if it's a light node
		if is_light:
			item_type = ItemType.LIGHT
			category = "Lighting"
			zoom_levels = [1, 2]
		else:
			# Try to infer type from name (but NOT for lights - those are node-type based only)
			var lower_name = child.name.to_lower()
			if "button" in lower_name or "btn" in lower_name or "switch" in lower_name:
				item_type = ItemType.BUTTON
			elif "led" in lower_name or "indicator" in lower_name:
				item_type = ItemType.INDICATOR

		# Try to infer category from parent path
		if category == "Discovered":
			if "RoomElements" in child_path:
				category = "Room"
				zoom_levels = [1]  # Room elements at zoom level 1
			elif "DeskExtensions" in child_path:
				category = "Furniture"
				zoom_levels = [1]
			elif "ComputerFrame" in child_path:
				category = "Computer"
				zoom_levels = [1, 2, 3]
			elif "Monitor" in child_path:
				category = "Monitor"
				zoom_levels = [2, 3, 4]
			elif "Window" in child_path or "Blind" in child_path:
				category = "Window"
				zoom_levels = [1]
			elif "Shelf" in child_path or "Book" in child_path:
				category = "Shelves"
				zoom_levels = [1]
			elif "LightContainer" in child_path:
				category = "Lighting"
				zoom_levels = [1, 2]

		editable_elements.append({
			"element": child,
			"type": item_type,
			"path": child_path,
			"category": category,
			"zoom_levels": zoom_levels,
			"is_copy": false,
			"exists": true,
			"discovered": true,  # Mark as auto-discovered
			"is_node2d": is_node2d and not is_control,  # Track if it's Node2D only
		})

		# Recurse into children
		_discover_controls(child, child_path, configured_paths)


func _item_visible_at_zoom(item: Dictionary, zoom_level: int) -> bool:
	"""Check if an item should be visible at the given zoom level"""
	if zoom_level == ZOOM_ALL:
		return true
	var item_levels = item.get("zoom_levels", [1, 2, 3, 4])
	return zoom_level in item_levels


func _cycle_zoom_filter() -> void:
	"""Cycle through zoom level filters: All -> Room -> Desktop -> Monitor -> Screen -> All"""
	current_zoom_filter = (current_zoom_filter + 1) % 5
	print("[EditMode] Zoom filter: %s" % ZOOM_LEVEL_NAMES[current_zoom_filter])
	_update_zoom_filter_display()
	_populate_asset_list()
	_update_type_highlights()
	_update_item_labels()
	_update_selection_outline()
	_update_hover_outline()


func _update_zoom_filter_display() -> void:
	"""Update the zoom level filter indicator in the UI"""
	if zoom_filter_label:
		var level_name = ZOOM_LEVEL_NAMES.get(current_zoom_filter, "All")
		zoom_filter_label.text = "Level: %s" % level_name
		# Color based on level
		match current_zoom_filter:
			ZOOM_ALL:
				zoom_filter_label.add_theme_color_override("font_color", THEME_ACCENT)
			ZOOM_ROOM:
				zoom_filter_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
			ZOOM_DESKTOP:
				zoom_filter_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.6))
			ZOOM_MONITOR:
				zoom_filter_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.6))
			ZOOM_SCREEN:
				zoom_filter_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.8))


func _backup_original_positions() -> void:
	for item in editable_elements:
		var element = item["element"]
		var path = item["path"]
		# Only backup if element exists
		if element:
			if element is Control:
				original_positions[path] = {
					"is_control": true,
					"left": element.offset_left,
					"right": element.offset_right,
					"top": element.offset_top,
					"bottom": element.offset_bottom,
					"z_index": element.z_index,
					"z_as_relative": element.z_as_relative,
					"child_index": element.get_index(),
					"visible": element.visible,
				}
			elif element is Node2D:
				original_positions[path] = {
					"is_control": false,
					"position": element.position,
					"global_position": element.global_position,
					"z_index": element.z_index,
					"z_as_relative": element.z_as_relative,
					"child_index": element.get_index(),
					"visible": element.visible,
				}


func _create_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.name = "EditOverlay"
	overlay.layer = 100
	overlay.visible = false
	add_child(overlay)

	# Create a custom theme for styled tooltips
	var theme = Theme.new()
	_setup_tooltip_theme(theme)
	overlay.set("theme", theme)

	# Highlights container (below UI)
	type_highlights = Control.new()
	type_highlights.name = "TypeHighlights"
	type_highlights.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(type_highlights)

	item_labels = Control.new()
	item_labels.name = "ItemLabels"
	item_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(item_labels)

	hover_outline = Control.new()
	hover_outline.name = "HoverOutline"
	hover_outline.visible = false
	hover_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(hover_outline)

	selection_outline = Control.new()
	selection_outline.name = "SelectionOutline"
	selection_outline.visible = false
	selection_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(selection_outline)

	# Create UI panels
	_create_toolbar()
	_create_asset_library()
	_create_properties_panel()
	_create_status_bar()
	_create_context_menus()


func _setup_tooltip_theme(theme: Theme) -> void:
	"""Configure custom tooltip styling for a modern look"""
	# Tooltip panel style
	var tooltip_panel = StyleBoxFlat.new()
	tooltip_panel.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	tooltip_panel.border_color = THEME_ACCENT
	tooltip_panel.border_width_left = 1
	tooltip_panel.border_width_right = 1
	tooltip_panel.border_width_top = 1
	tooltip_panel.border_width_bottom = 1
	tooltip_panel.corner_radius_top_left = 4
	tooltip_panel.corner_radius_top_right = 4
	tooltip_panel.corner_radius_bottom_left = 4
	tooltip_panel.corner_radius_bottom_right = 4
	tooltip_panel.content_margin_left = 8
	tooltip_panel.content_margin_right = 8
	tooltip_panel.content_margin_top = 6
	tooltip_panel.content_margin_bottom = 6
	tooltip_panel.shadow_color = Color(0, 0, 0, 0.3)
	tooltip_panel.shadow_size = 4
	tooltip_panel.shadow_offset = Vector2(2, 2)

	theme.set_stylebox("panel", "TooltipPanel", tooltip_panel)

	# Tooltip label style
	theme.set_color("font_color", "TooltipLabel", THEME_TEXT)
	theme.set_font_size("font_size", "TooltipLabel", 11)


func _create_panel_style(elevated: bool = false) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = THEME_BG_ELEVATED if elevated else THEME_BG_SURFACE
	style.border_color = THEME_BORDER
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	# Add shadow for depth
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.25)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	return style


func _create_button_style(bg_color: Color = THEME_BG_SURFACE, border_color: Color = THEME_BORDER_SUBTLE) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func _create_glow_button_style(glow_color: Color) -> StyleBoxFlat:
	"""Create a button style with a glow effect for hover states"""
	var style = StyleBoxFlat.new()
	# Darker background to make glow pop
	style.bg_color = Color(glow_color.r * 0.15, glow_color.g * 0.15, glow_color.b * 0.15, 0.4)
	# Border with glow color
	style.border_color = Color(glow_color.r, glow_color.g, glow_color.b, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	# Shadow as glow
	style.shadow_color = Color(glow_color.r, glow_color.g, glow_color.b, 0.3)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 0)  # Centered glow
	return style


func _create_button_style_modern(state: String = "normal") -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	match state:
		"normal":
			style.bg_color = THEME_BG_SURFACE
			style.border_color = THEME_BORDER_SUBTLE
		"hover":
			style.bg_color = THEME_BG_HOVER
			style.border_color = Color(THEME_BORDER.r, THEME_BORDER.g, THEME_BORDER.b, 0.5)
		"pressed", "active":
			style.bg_color = THEME_BG_ACTIVE
			style.border_color = THEME_BORDER
		"disabled":
			style.bg_color = THEME_BG
			style.border_color = THEME_BORDER_SUBTLE
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _create_input_style(focused: bool = false) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = THEME_BG
	style.border_color = THEME_ACCENT if focused else THEME_BORDER_SUBTLE
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _create_toolbar() -> void:
	toolbar = Panel.new()
	toolbar.name = "Toolbar"
	toolbar.mouse_filter = Control.MOUSE_FILTER_STOP
	toolbar.add_theme_stylebox_override("panel", _create_panel_style())
	toolbar.position = Vector2(10, 10)
	toolbar.size = Vector2(get_viewport().get_visible_rect().size.x - 20, 50)  # Full width minus margins
	overlay.add_child(toolbar)

	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 10
	hbox.offset_right = -10
	hbox.offset_top = 8
	hbox.offset_bottom = -8
	hbox.add_theme_constant_override("separation", 4)
	toolbar.add_child(hbox)

	# Mode indicator with icon
	var mode_box = HBoxContainer.new()
	mode_box.add_theme_constant_override("separation", 6)
	hbox.add_child(mode_box)

	var mode_icon = ColorRect.new()
	mode_icon.custom_minimum_size = Vector2(4, 20)
	mode_icon.color = THEME_ACCENT
	mode_box.add_child(mode_icon)

	var mode_label = Label.new()
	mode_label.text = "EDIT"
	mode_label.add_theme_font_size_override("font_size", 14)
	mode_label.add_theme_color_override("font_color", THEME_ACCENT)
	mode_box.add_child(mode_label)

	hbox.add_child(_create_toolbar_separator())

	# History group
	var history_group = _create_button_group()
	history_group.add_child(_create_icon_button(IconType.UNDO, "Undo (Ctrl+Z)", _undo))
	history_group.add_child(_create_icon_button(IconType.REDO, "Redo (Ctrl+Y)", _redo))
	hbox.add_child(history_group)

	hbox.add_child(_create_toolbar_separator())

	# Edit group
	var edit_group = _create_button_group()
	edit_group.add_child(_create_icon_button(IconType.DUPLICATE, "Duplicate (Ctrl+D)", _duplicate_selected))
	edit_group.add_child(_create_icon_button(IconType.DELETE, "Delete (Del)", _delete_selected_element, THEME_DANGER))
	edit_group.add_child(_create_icon_button(IconType.HIDE, "Hide (H)", _hide_selected_element))
	hbox.add_child(edit_group)

	hbox.add_child(_create_toolbar_separator())

	# Z-Order group
	var zorder_group = _create_button_group()
	zorder_group.add_child(_create_icon_button(IconType.MOVE_UP, "Bring Forward (])", _move_forward))
	zorder_group.add_child(_create_icon_button(IconType.MOVE_DOWN, "Send Backward ([)", _move_backward))
	zorder_group.add_child(_create_icon_button(IconType.BRING_FRONT, "Bring to Front (Shift+])", _bring_to_front))
	zorder_group.add_child(_create_icon_button(IconType.SEND_BACK, "Send to Back (Shift+[)", _send_to_back))
	hbox.add_child(zorder_group)

	hbox.add_child(_create_toolbar_separator())

	# Alignment tools group
	var align_group = _create_button_group()
	align_group.add_child(_create_icon_button(IconType.ALIGN_LEFT, "Align Left (Shift+Click to multi-select)", _align_left))
	align_group.add_child(_create_icon_button(IconType.ALIGN_CENTER_H, "Align Center Horizontal", _align_center_h))
	align_group.add_child(_create_icon_button(IconType.ALIGN_RIGHT, "Align Right", _align_right))
	align_group.add_child(_create_icon_button(IconType.ALIGN_TOP, "Align Top", _align_top))
	align_group.add_child(_create_icon_button(IconType.ALIGN_CENTER_V, "Align Center Vertical", _align_center_v))
	align_group.add_child(_create_icon_button(IconType.ALIGN_BOTTOM, "Align Bottom", _align_bottom))
	hbox.add_child(align_group)

	hbox.add_child(_create_toolbar_separator())

	# Snap and grid toggles
	var snap_group = _create_button_group()
	snap_toggle_btn = _create_toggle_button(IconType.SNAP, "Toggle Snapping (S)", snap_enabled, _toggle_snap)
	snap_group.add_child(snap_toggle_btn)
	grid_toggle_btn = _create_toggle_button(IconType.GRID, "Toggle Grid (G)", grid_enabled, _toggle_grid)
	snap_group.add_child(grid_toggle_btn)
	guides_toggle_btn = _create_toggle_button(IconType.GUIDE, "Toggle Guides (Q)", guides_enabled, _toggle_guides)
	snap_group.add_child(guides_toggle_btn)
	hbox.add_child(snap_group)

	hbox.add_child(_create_toolbar_separator())

	# Zoom Level Filter
	var zoom_filter_box = HBoxContainer.new()
	zoom_filter_box.add_theme_constant_override("separation", 4)
	hbox.add_child(zoom_filter_box)

	var zoom_icon = Label.new()
	zoom_icon.text = "Z:"
	zoom_icon.add_theme_font_size_override("font_size", 12)
	zoom_filter_box.add_child(zoom_icon)

	zoom_filter_label = Label.new()
	zoom_filter_label.name = "ZoomFilterLabel"
	zoom_filter_label.text = "Level: All"
	zoom_filter_label.add_theme_font_size_override("font_size", 11)
	zoom_filter_label.add_theme_color_override("font_color", THEME_ACCENT)
	zoom_filter_label.custom_minimum_size.x = 80
	zoom_filter_box.add_child(zoom_filter_label)

	var tab_hint = Label.new()
	tab_hint.text = "(Tab)"
	tab_hint.add_theme_font_size_override("font_size", 9)
	tab_hint.add_theme_color_override("font_color", THEME_TEXT_DIM)
	zoom_filter_box.add_child(tab_hint)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# Save/Load group (auto-save is automatic, no manual Save button needed)
	var save_group = _create_button_group()
	save_group.add_child(_create_text_button("Load", "Load from server", _load_from_session, Color(0.4, 0.7, 1.0)))
	save_group.add_child(_create_text_button("Default", "Save as default (Admin)", _show_save_default_confirmation, Color(1.0, 0.8, 0.3)))
	hbox.add_child(save_group)

	hbox.add_child(_create_toolbar_separator())

	# Reset
	var reset_btn = _create_text_button("Reset", "Factory reset all elements", factory_reset, Color(1.0, 0.5, 0.2))
	hbox.add_child(reset_btn)

	hbox.add_child(_create_toolbar_separator())

	# Exit
	var exit_btn = _create_text_button("Exit [F3]", "Exit edit mode", _exit_edit_mode, Color(1.0, 1.0, 0.5))
	hbox.add_child(exit_btn)


func _create_toolbar_separator() -> VSeparator:
	var sep = VSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	sep.add_theme_color_override("separator", Color(THEME_BORDER.r, THEME_BORDER.g, THEME_BORDER.b, 0.3))
	sep.custom_minimum_size.x = 8
	return sep


func _create_button_group() -> HBoxContainer:
	var group = HBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	return group


func _create_icon_button(icon_type_or_text, tooltip: String, callback: Callable, color: Color = THEME_TEXT) -> Button:
	var btn = Button.new()
	btn.tooltip_text = tooltip
	btn.add_theme_stylebox_override("normal", _create_button_style_modern("normal"))
	btn.add_theme_stylebox_override("hover", _create_button_style_modern("hover"))
	btn.add_theme_stylebox_override("pressed", _create_button_style_modern("pressed"))
	btn.custom_minimum_size = Vector2(32, 28)
	btn.pressed.connect(callback)

	# Check if it's an icon type (int) or text (string)
	if icon_type_or_text is int and icon_type_or_text > 0:
		# Use programmatic icon
		var icon = EditIcon.new(icon_type_or_text, color, 14.0)
		icon.set_anchors_preset(Control.PRESET_CENTER)
		btn.add_child(icon)
		# Position icon after button is ready
		btn.ready.connect(func():
			icon.position = (btn.size - icon.size) / 2
		)
	else:
		# Fallback to text
		btn.text = str(icon_type_or_text)
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", color)
	return btn


func _create_toggle_button(icon_type: int, tooltip: String, initial_state: bool, callback: Callable) -> Button:
	var btn = Button.new()
	btn.toggle_mode = true
	btn.button_pressed = initial_state
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(32, 28)

	# Style based on toggle state
	_update_toggle_button_style(btn, initial_state)

	btn.toggled.connect(func(pressed: bool):
		_update_toggle_button_style(btn, pressed)
		callback.call()
	)

	# Add icon
	var icon = EditIcon.new(icon_type, THEME_TEXT if not initial_state else THEME_ACCENT, 14.0)
	icon.set_anchors_preset(Control.PRESET_CENTER)
	icon.name = "ToggleIcon"
	btn.add_child(icon)
	btn.ready.connect(func():
		icon.position = (btn.size - icon.size) / 2
	)

	return btn


func _update_toggle_button_style(btn: Button, active: bool) -> void:
	if active:
		btn.add_theme_stylebox_override("normal", _create_button_style_modern("active"))
		btn.add_theme_stylebox_override("hover", _create_button_style_modern("active"))
		btn.add_theme_stylebox_override("pressed", _create_button_style_modern("active"))
	else:
		btn.add_theme_stylebox_override("normal", _create_button_style_modern("normal"))
		btn.add_theme_stylebox_override("hover", _create_button_style_modern("hover"))
		btn.add_theme_stylebox_override("pressed", _create_button_style_modern("pressed"))

	# Update icon color
	var icon = btn.get_node_or_null("ToggleIcon") as EditIcon
	if icon:
		icon.icon_color = THEME_ACCENT if active else THEME_TEXT
		icon.queue_redraw()


func _create_text_button(text: String, tooltip: String, callback: Callable, color: Color = THEME_TEXT) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_stylebox_override("normal", _create_button_style())
	btn.add_theme_stylebox_override("hover", _create_button_style(THEME_BG_HOVER))
	btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.0, 0.3, 0.15)))
	btn.custom_minimum_size = Vector2(50, 28)
	btn.pressed.connect(callback)
	return btn




func _create_asset_library() -> void:
	asset_library = Panel.new()
	asset_library.name = "AssetLibrary"
	asset_library.mouse_filter = Control.MOUSE_FILTER_STOP
	asset_library.add_theme_stylebox_override("panel", _create_panel_style())
	asset_library.position = Vector2(10, 70)
	asset_library.custom_minimum_size = Vector2(240, 200)
	overlay.add_child(asset_library)

	var main_vbox = VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.offset_left = 10
	main_vbox.offset_right = -10
	main_vbox.offset_top = 10
	main_vbox.offset_bottom = -10
	main_vbox.add_theme_constant_override("separation", 6)
	asset_library.add_child(main_vbox)

	# Tab buttons row
	var tab_box = HBoxContainer.new()
	tab_box.add_theme_constant_override("separation", 4)
	main_vbox.add_child(tab_box)

	library_tab_btn = Button.new()
	library_tab_btn.name = "LibraryTab"
	library_tab_btn.text = "Library"
	library_tab_btn.add_theme_font_size_override("font_size", 11)
	library_tab_btn.add_theme_stylebox_override("normal", _create_tab_style(true))
	library_tab_btn.add_theme_stylebox_override("hover", _create_tab_style(true))
	library_tab_btn.add_theme_color_override("font_color", THEME_ACCENT)
	library_tab_btn.custom_minimum_size = Vector2(0, 26)
	library_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_tab_btn.pressed.connect(func(): _set_library_tab(0))
	tab_box.add_child(library_tab_btn)

	scene_tab_btn = Button.new()
	scene_tab_btn.name = "SceneTab"
	scene_tab_btn.text = "In Scene"
	scene_tab_btn.add_theme_font_size_override("font_size", 11)
	scene_tab_btn.add_theme_stylebox_override("normal", _create_tab_style(false))
	scene_tab_btn.add_theme_stylebox_override("hover", _create_tab_style(false))
	scene_tab_btn.add_theme_color_override("font_color", THEME_TEXT_DIM)
	scene_tab_btn.custom_minimum_size = Vector2(0, 26)
	scene_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_tab_btn.pressed.connect(func(): _set_library_tab(1))
	tab_box.add_child(scene_tab_btn)

	# Expand/Collapse All toggle button
	var expand_btn = Button.new()
	expand_btn.name = "ExpandCollapseBtn"
	expand_btn.tooltip_text = "Collapse All"
	expand_btn.add_theme_stylebox_override("normal", _create_button_style(THEME_BG_SURFACE, THEME_BORDER_SUBTLE))
	expand_btn.add_theme_stylebox_override("hover", _create_button_style(THEME_BG_HOVER, THEME_BORDER))
	expand_btn.custom_minimum_size = Vector2(26, 26)
	expand_btn.pressed.connect(_toggle_expand_collapse_all)
	tab_box.add_child(expand_btn)

	# Add icon to button (starts as COLLAPSE since tree starts expanded)
	var expand_icon = EditIcon.new(IconType.COLLAPSE, THEME_TEXT_DIM, 12.0)
	expand_icon.name = "ExpandCollapseIcon"
	expand_icon.set_anchors_preset(Control.PRESET_CENTER)
	expand_btn.add_child(expand_icon)
	expand_btn.resized.connect(func(): expand_icon.position = (expand_btn.size - expand_icon.size) / 2)

	# Header with count
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	main_vbox.add_child(header)

	var title_icon = ColorRect.new()
	title_icon.custom_minimum_size = Vector2(4, 14)
	title_icon.color = THEME_ACCENT
	header.add_child(title_icon)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var count_label = Label.new()
	count_label.name = "CountLabel"
	count_label.text = "0 items"
	count_label.add_theme_font_size_override("font_size", 10)
	count_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
	header.add_child(count_label)

	# Filter buttons row (only for Library tab)
	var filter_box = HBoxContainer.new()
	filter_box.name = "FilterBox"
	filter_box.add_theme_constant_override("separation", 4)
	main_vbox.add_child(filter_box)

	var filter_buttons = [
		{"text": "All", "type": -1, "color": THEME_TEXT},
		{"text": "Btn", "type": ItemType.BUTTON, "color": TYPE_COLORS[ItemType.BUTTON]},
		{"text": "Ind", "type": ItemType.INDICATOR, "color": TYPE_COLORS[ItemType.INDICATOR]},
		{"text": "Obj", "type": ItemType.OBJECT, "color": TYPE_COLORS[ItemType.OBJECT]},
		{"text": "Lit", "type": ItemType.LIGHT, "color": TYPE_COLORS[ItemType.LIGHT]},
	]

	for fb in filter_buttons:
		var btn = Button.new()
		btn.name = "Filter_%d" % fb["type"]
		btn.text = fb["text"]
		btn.add_theme_font_size_override("font_size", 10)
		btn.add_theme_stylebox_override("normal", _create_button_style())
		btn.add_theme_stylebox_override("hover", _create_button_style(THEME_BG_HOVER))
		btn.add_theme_color_override("font_color", fb["color"])
		btn.custom_minimum_size = Vector2(38, 22)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var filter_type = fb["type"]
		btn.pressed.connect(func(): _set_library_filter(filter_type))
		filter_box.add_child(btn)

	# Separator
	var sep = HSeparator.new()
	sep.add_theme_color_override("separator", Color(THEME_BORDER.r, THEME_BORDER.g, THEME_BORDER.b, 0.3))
	main_vbox.add_child(sep)

	# Library tab - Scrollable asset list by category
	library_scroll = ScrollContainer.new()
	library_scroll.name = "LibraryScroll"
	library_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(library_scroll)

	asset_list = VBoxContainer.new()
	asset_list.name = "AssetList"
	asset_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asset_list.add_theme_constant_override("separation", 1)
	library_scroll.add_child(asset_list)

	# Scene tab - Tree view of in-scene elements
	scene_scroll = ScrollContainer.new()
	scene_scroll.name = "SceneScroll"
	scene_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scene_scroll.visible = false  # Hidden by default
	main_vbox.add_child(scene_scroll)

	scene_tree = VBoxContainer.new()
	scene_tree.name = "SceneTree"
	scene_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_tree.add_theme_constant_override("separation", 0)
	scene_scroll.add_child(scene_tree)


func _create_tab_style(active: bool) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	if active:
		style.bg_color = Color(THEME_BORDER.r * 0.3, THEME_BORDER.g * 0.3, THEME_BORDER.b * 0.3, 0.5)
		style.border_color = THEME_BORDER
		style.set_border_width_all(1)
		style.border_width_bottom = 0
	else:
		style.bg_color = Color(0.05, 0.05, 0.08, 0.5)
		style.border_color = Color(THEME_BORDER.r, THEME_BORDER.g, THEME_BORDER.b, 0.3)
		style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	return style


func _set_library_tab(tab: int) -> void:
	library_tab = tab

	# Update tab button styles
	library_tab_btn.add_theme_stylebox_override("normal", _create_tab_style(tab == 0))
	library_tab_btn.add_theme_stylebox_override("hover", _create_tab_style(tab == 0))
	library_tab_btn.add_theme_color_override("font_color", THEME_ACCENT if tab == 0 else THEME_TEXT_DIM)

	scene_tab_btn.add_theme_stylebox_override("normal", _create_tab_style(tab == 1))
	scene_tab_btn.add_theme_stylebox_override("hover", _create_tab_style(tab == 1))
	scene_tab_btn.add_theme_color_override("font_color", THEME_ACCENT if tab == 1 else THEME_TEXT_DIM)

	# Filter box is now visible for both tabs
	# (no need to hide it)

	# Toggle scroll containers
	library_scroll.visible = (tab == 0)
	scene_scroll.visible = (tab == 1)

	# Populate the appropriate list
	if tab == 0:
		_populate_asset_list()
	else:
		_populate_scene_tree()


func _create_filter_button(text: String, _type: int) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_stylebox_override("normal", _create_button_style())
	btn.add_theme_stylebox_override("hover", _create_button_style(THEME_BG_HOVER))
	btn.custom_minimum_size = Vector2(45, 24)
	return btn


func _set_library_filter(type_filter: int) -> void:
	library_type_filter = type_filter

	# Update filter button styles to show active filter
	var filter_box = asset_library.get_node_or_null("MainVBox/FilterBox")
	if filter_box:
		for btn in filter_box.get_children():
			if btn is Button and btn.name.begins_with("Filter_"):
				var btn_type = int(btn.name.substr(7))  # Extract type from "Filter_X"
				var is_active = (btn_type == type_filter)
				if is_active:
					btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.1, 0.2, 0.15)))
				else:
					btn.add_theme_stylebox_override("normal", _create_button_style())

	# Update whichever tab is currently visible
	if library_tab == 0:
		_populate_asset_list()
	else:
		_populate_scene_tree()


func _populate_asset_list() -> void:
	for child in asset_list.get_children():
		child.queue_free()

	# Group by category, filtering by type and zoom level
	var categories: Dictionary = {}
	var visible_count = 0
	for item in editable_elements:
		if library_type_filter >= 0 and item["type"] != library_type_filter:
			continue
		# Filter by zoom level
		if not _item_visible_at_zoom(item, current_zoom_filter):
			continue
		var category = item.get("category", "Other")
		if not categories.has(category):
			categories[category] = []
		categories[category].append(item)
		visible_count += 1

	# Update count label (find it by name since parent container isn't named)
	var main_vbox = asset_library.get_node_or_null("MainVBox")
	if main_vbox:
		for child in main_vbox.get_children():
			if child is HBoxContainer:
				var count_label = child.get_node_or_null("CountLabel") as Label
				if count_label:
					var filter_str = ""
					if current_zoom_filter != ZOOM_ALL:
						filter_str = " @ %s" % ZOOM_LEVEL_NAMES[current_zoom_filter]
					count_label.text = "%d items%s" % [visible_count, filter_str]
					break

	# Sort categories for consistent order
	var sorted_categories = categories.keys()
	sorted_categories.sort()

	for category in sorted_categories:
		# Category header with item count
		var cat_header = HBoxContainer.new()
		cat_header.add_theme_constant_override("separation", 4)
		asset_list.add_child(cat_header)

		var cat_icon = ColorRect.new()
		cat_icon.custom_minimum_size = Vector2(3, 12)
		cat_icon.color = THEME_BORDER
		cat_header.add_child(cat_icon)

		var cat_label = Label.new()
		cat_label.text = "%s (%d)" % [category, categories[category].size()]
		cat_label.add_theme_font_size_override("font_size", 11)
		cat_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
		cat_header.add_child(cat_label)

		for item in categories[category]:
			var path = item["path"]
			var element = item["element"]
			var is_hidden = hidden_elements.get(path, false)
			var is_copy = item.get("is_copy", false)
			var exists = item.get("exists", element != null)
			var is_selected = selected_element != null and selected_element == element

			# Item row container
			var item_row = HBoxContainer.new()
			item_row.add_theme_constant_override("separation", 4)
			asset_list.add_child(item_row)

			# Type indicator dot
			var type_dot = ColorRect.new()
			type_dot.custom_minimum_size = Vector2(6, 6)
			var dot_color = TYPE_COLORS[item["type"]]
			if not exists:
				dot_color = Color(0.4, 0.4, 0.4, 0.5)  # Gray for non-existent
			elif is_hidden:
				dot_color = THEME_TEXT_DIM
			type_dot.color = dot_color
			var dot_container = CenterContainer.new()
			dot_container.custom_minimum_size = Vector2(12, 22)
			dot_container.add_child(type_dot)
			item_row.add_child(dot_container)

			# Item button
			var item_btn = Button.new()
			var display_name = _get_display_name(item)
			var prefix = ""
			if not exists:
				prefix = "[?] "  # Template without instance
			elif is_hidden:
				prefix = "[H] "
			if is_copy:
				prefix += "* "
			# Add zoom level suffix
			var zoom_levels = item.get("zoom_levels", [1, 2, 3, 4])
			var level_suffix = ""
			if zoom_levels.size() < 4:
				level_suffix = " [%s]" % ",".join(zoom_levels.map(func(x): return str(x)))
			item_btn.text = prefix + display_name + level_suffix
			item_btn.add_theme_font_size_override("font_size", 10)
			item_btn.clip_text = true
			item_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

			# Style based on state
			var bg_color = Color(0.05, 0.05, 0.08)
			if is_selected:
				bg_color = Color(0.0, 0.2, 0.1)
			elif not exists:
				bg_color = Color(0.02, 0.02, 0.04)  # Darker for non-existent
			elif is_hidden:
				bg_color = Color(0.03, 0.03, 0.05)

			var text_color = TYPE_COLORS[item["type"]]
			if not exists:
				text_color = Color(0.5, 0.5, 0.5)  # Gray for non-existent
			elif is_hidden:
				text_color = THEME_TEXT_DIM
			if is_selected:
				text_color = THEME_ACCENT

			item_btn.add_theme_color_override("font_color", text_color)
			item_btn.add_theme_stylebox_override("normal", _create_button_style(bg_color, THEME_BORDER_SUBTLE))
			# Use glow hover style matching the scene hover effect
			var item_glow_color = TYPE_COLORS[item["type"]]
			item_btn.add_theme_stylebox_override("hover", _create_glow_button_style(item_glow_color))
			item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			item_btn.custom_minimum_size = Vector2(0, 22)

			item_btn.set_meta("item", item)
			item_btn.pressed.connect(func(): _on_library_item_clicked(item))
			item_btn.gui_input.connect(func(event): _on_library_item_input(event, item, item_btn))

			item_row.add_child(item_btn)


func _populate_scene_tree() -> void:
	"""Populate the In Scene tree view with hierarchical structure"""
	for child in scene_tree.get_children():
		child.queue_free()

	# Build a tree structure from paths
	# Structure: { "node_name": { "item": item_or_null, "children": {}, "path": full_path } }
	var tree_root: Dictionary = {}

	var visible_count = 0
	for item in editable_elements:
		var element = item["element"]
		if not element:
			continue  # Skip items without scene instances

		# Filter by zoom level
		if not _item_visible_at_zoom(item, current_zoom_filter):
			continue

		# Filter by type (same as Library tab)
		if library_type_filter >= 0 and item["type"] != library_type_filter:
			continue

		var path = item["path"]
		var parts = path.split("/")

		# Navigate/create tree structure
		var current = tree_root
		var current_path = ""
		for i in range(parts.size()):
			var part = parts[i]
			current_path = part if current_path.is_empty() else current_path + "/" + part

			if not current.has(part):
				# Default to collapsed, unless explicitly expanded or contains selected item
				var is_expanded = tree_expanded_paths.get(current_path, false)
				current[part] = {"item": null, "children": {}, "path": current_path, "expanded": is_expanded}

			# If this is the last part, assign the item
			if i == parts.size() - 1:
				current[part]["item"] = item
				visible_count += 1
			current = current[part]["children"]

	# Update count label
	var main_vbox = asset_library.get_node_or_null("MainVBox")
	if main_vbox:
		for child in main_vbox.get_children():
			if child is HBoxContainer:
				var count_label = child.get_node_or_null("CountLabel") as Label
				if count_label:
					var filter_str = ""
					if current_zoom_filter != ZOOM_ALL:
						filter_str = " @ %s" % ZOOM_LEVEL_NAMES[current_zoom_filter]
					count_label.text = "%d in scene%s" % [visible_count, filter_str]
					break

	# Render the tree
	_render_tree_node(tree_root, 0)


func _toggle_tree_expand(path: String) -> void:
	"""Toggle expansion state of a tree node"""
	tree_expanded_paths[path] = not tree_expanded_paths.get(path, false)
	_populate_scene_tree()


func _expand_to_path(target_path: String) -> void:
	"""Expand all parent nodes to make target_path visible"""
	var parts = target_path.split("/")
	var current_path = ""
	for i in range(parts.size() - 1):  # Don't need to expand the last part
		current_path = parts[i] if current_path.is_empty() else current_path + "/" + parts[i]
		tree_expanded_paths[current_path] = true


func _toggle_expand_collapse_all() -> void:
	"""Toggle between expanding all and collapsing all tree nodes"""
	tree_all_expanded = not tree_all_expanded

	# Get all unique parent paths from editable elements
	var parent_paths: Dictionary = {}
	for item in editable_elements:
		var path = item.get("path", "")
		if path.is_empty():
			continue
		var parts = path.split("/")
		var current_path = ""
		for i in range(parts.size() - 1):  # Don't include the leaf node
			current_path = parts[i] if current_path.is_empty() else current_path + "/" + parts[i]
			parent_paths[current_path] = true

	# Set all parent paths to expanded or collapsed
	for parent_path in parent_paths.keys():
		tree_expanded_paths[parent_path] = tree_all_expanded

	# Update the button appearance
	_update_expand_collapse_button()

	# Refresh the tree
	_populate_scene_tree()


func _update_expand_collapse_button() -> void:
	"""Update the expand/collapse button icon and tooltip"""
	var btn = asset_library.find_child("ExpandCollapseBtn", true, false) as Button
	if not btn:
		return

	var icon = btn.find_child("ExpandCollapseIcon", true, false) as EditIcon
	if icon:
		# Remove old icon and create new one with correct type
		icon.queue_free()

	# Create new icon with appropriate type
	var new_icon: EditIcon
	if tree_all_expanded:
		new_icon = EditIcon.new(IconType.COLLAPSE, THEME_TEXT_DIM, 12.0)
		btn.tooltip_text = "Collapse All"
	else:
		new_icon = EditIcon.new(IconType.EXPAND, THEME_TEXT_DIM, 12.0)
		btn.tooltip_text = "Expand All"

	new_icon.name = "ExpandCollapseIcon"
	new_icon.set_anchors_preset(Control.PRESET_CENTER)
	btn.add_child(new_icon)
	new_icon.position = (btn.size - new_icon.size) / 2


func _scroll_to_selected_in_tree(target_path: String) -> void:
	"""Scroll the scene tree to make the selected item visible"""
	if not scene_scroll or not scene_tree:
		return

	# Find the row containing the selected item by checking metadata
	var target_row: Control = null
	for child in scene_tree.get_children():
		if child is HBoxContainer and child.has_meta("tree_path"):
			if child.get_meta("tree_path") == target_path:
				target_row = child
				break

	if target_row:
		# Calculate position to scroll to
		var row_pos = target_row.position.y
		var row_height = target_row.size.y
		var scroll_height = scene_scroll.size.y
		var current_scroll = scene_scroll.scroll_vertical

		# Check if row is outside visible area
		if row_pos < current_scroll:
			# Row is above visible area - scroll up
			scene_scroll.scroll_vertical = int(row_pos)
		elif row_pos + row_height > current_scroll + scroll_height:
			# Row is below visible area - scroll down
			scene_scroll.scroll_vertical = int(row_pos + row_height - scroll_height + 10)


func _render_tree_node(node: Dictionary, depth: int) -> void:
	"""Recursively render tree nodes"""
	var sorted_keys = node.keys()
	sorted_keys.sort()

	for key in sorted_keys:
		var data = node[key]
		var item = data["item"]
		var children = data["children"]
		var node_path = data["path"]
		var has_children = not children.is_empty()
		var is_expanded = data["expanded"]

		# Create row for this node
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		row.set_meta("tree_path", node_path)  # Store path for scroll lookup
		scene_tree.add_child(row)

		# Indentation
		if depth > 0:
			var indent = Control.new()
			indent.custom_minimum_size = Vector2(depth * 12, 0)
			row.add_child(indent)

		# Expand/collapse button (if has children)
		if has_children:
			var expand_btn = Button.new()
			expand_btn.text = "v" if is_expanded else ">"
			expand_btn.add_theme_font_size_override("font_size", 8)
			expand_btn.add_theme_color_override("font_color", THEME_TEXT_DIM)
			expand_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			expand_btn.add_theme_stylebox_override("hover", _create_button_style(THEME_BG_HOVER))
			expand_btn.custom_minimum_size = Vector2(14, 22)
			expand_btn.pressed.connect(func(): _toggle_tree_expand(node_path))
			row.add_child(expand_btn)
		else:
			var spacer = Control.new()
			spacer.custom_minimum_size = Vector2(14, 22)
			row.add_child(spacer)

		# Type indicator dot
		var type_dot = ColorRect.new()
		type_dot.custom_minimum_size = Vector2(6, 6)
		if item:
			var is_hidden = hidden_elements.get(item["path"], false)
			type_dot.color = TYPE_COLORS[item["type"]] if not is_hidden else THEME_TEXT_DIM
		else:
			type_dot.color = Color(0.4, 0.4, 0.4, 0.5)  # Gray for parent-only nodes
		var dot_container = CenterContainer.new()
		dot_container.custom_minimum_size = Vector2(10, 22)
		dot_container.add_child(type_dot)
		row.add_child(dot_container)

		# Node button
		var btn = Button.new()
		# Use custom name if available, otherwise default to node name
		var display_name = key
		if item:
			display_name = _get_display_name(item)
		btn.text = display_name
		btn.add_theme_font_size_override("font_size", 10)
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 22)

		# Styling based on state
		var is_selected = item and selected_element == item["element"]
		var is_multi_selected = item and item["element"] in multi_selected
		var is_hidden = item and hidden_elements.get(item["path"], false)

		var bg_color = Color(0.05, 0.05, 0.08)
		if is_selected:
			bg_color = Color(0.0, 0.3, 0.15)  # Brighter selection highlight
		elif is_multi_selected:
			bg_color = Color(0.0, 0.2, 0.1)  # Slightly dimmer multi-select highlight
		elif not item:
			bg_color = Color(0.04, 0.04, 0.06)  # Slightly different for parent nodes
		elif is_hidden:
			bg_color = Color(0.03, 0.03, 0.05)

		var text_color = THEME_TEXT
		if item:
			text_color = TYPE_COLORS[item["type"]] if not is_hidden else THEME_TEXT_DIM
			if is_selected or is_multi_selected:
				text_color = THEME_ACCENT
		else:
			text_color = Color(0.6, 0.6, 0.6)  # Dimmer for parent-only

		btn.add_theme_color_override("font_color", text_color)
		btn.add_theme_stylebox_override("normal", _create_button_style(bg_color, THEME_BORDER_SUBTLE))

		# Create hover style with glow effect matching scene hover
		var item_color = TYPE_COLORS[item["type"]] if item else THEME_TEXT_DIM
		var hover_style = _create_glow_button_style(item_color)
		btn.add_theme_stylebox_override("hover", hover_style)

		if item:
			btn.pressed.connect(func(): _on_library_item_clicked(item))
			btn.gui_input.connect(func(event): _on_library_item_input(event, item, btn))
		elif has_children:
			# Parent-only nodes toggle expand on click
			btn.pressed.connect(func(): _toggle_tree_expand(node_path))

		row.add_child(btn)

		# Visibility toggle button (only for actual items, not parent-only nodes)
		if item:
			var vis_btn = Button.new()
			vis_btn.custom_minimum_size = Vector2(22, 22)
			vis_btn.tooltip_text = "Show" if is_hidden else "Hide"
			vis_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			vis_btn.add_theme_stylebox_override("hover", _create_button_style(THEME_BG_HOVER))
			vis_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
			vis_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

			# Create eye icon using a simple drawing
			var icon_container = Control.new()
			icon_container.custom_minimum_size = Vector2(16, 16)
			icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var is_vis = not is_hidden
			var icon_color = THEME_ACCENT if is_vis else THEME_TEXT_DIM
			icon_container.draw.connect(func():
				_draw_eye_icon(icon_container, is_vis, icon_color)
			)
			vis_btn.add_child(icon_container)
			# Center the icon
			icon_container.position = Vector2(3, 3)

			var item_path = item["path"]
			vis_btn.pressed.connect(func(): _toggle_item_visibility(item_path))
			row.add_child(vis_btn)

		# Render children if expanded
		if has_children and is_expanded:
			_render_tree_node(children, depth + 1)


func _on_library_item_clicked(item: Dictionary) -> void:
	var element = item["element"]
	var path = item["path"]
	var exists = item.get("exists", element != null)

	if not exists:
		# Item is a template without instance - show info message
		print("[EditMode] '%s' is a template - element not yet in scene" % path)
		return

	if hidden_elements.get(path, false):
		_show_element(path)
	else:
		var shift_held = Input.is_key_pressed(KEY_SHIFT)

		if shift_held:
			# Shift+Click in tree list: Add to multi-selection or make active
			if element in multi_selected:
				# Already selected - just make it the active item (shows in properties)
				selected_element = element
				selected_item = item
			else:
				# Add current selection to multi if not already there
				if selected_element and selected_element not in multi_selected:
					_add_to_multi_selection(selected_element)
				# Add the clicked element
				_add_to_multi_selection(element)
				selected_element = element
				selected_item = item
			_update_selection_outline()
			_update_properties_panel()
		else:
			# Normal click - clear multi-selection
			_clear_multi_selection()
			# Toggle selection: unselect if already selected
			if selected_element == element:
				_clear_selection()
				# Refresh the list to update highlight
				if library_tab == 0:
					_populate_asset_list()
				else:
					_populate_scene_tree()
			else:
				_select_element(element)
			_update_selection_outline()
			_update_properties_panel()


func _on_library_item_input(event: InputEvent, item: Dictionary, btn: Button) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			library_context_item = item
			_show_library_context_menu(btn.get_global_position() + Vector2(btn.size.x, 0))


func _create_context_menus() -> void:
	# Scene element context menu
	context_menu = PopupMenu.new()
	context_menu.name = "ContextMenu"
	context_menu.add_theme_stylebox_override("panel", _create_panel_style())
	context_menu.add_theme_color_override("font_color", THEME_TEXT)
	context_menu.add_theme_color_override("font_hover_color", THEME_ACCENT)
	context_menu.add_theme_font_size_override("font_size", 12)

	context_menu.add_item("Duplicate", 0)
	context_menu.add_separator()
	context_menu.add_item("Hide", 1)
	context_menu.add_item("Delete", 2)
	context_menu.add_separator()
	context_menu.add_item("Bring to Front", 3)
	context_menu.add_item("Send to Back", 4)
	context_menu.add_item("Move Forward", 5)
	context_menu.add_item("Move Backward", 6)
	context_menu.add_separator()
	context_menu.add_item("Reset Position", 7)
	context_menu.add_separator()
	context_menu.add_item("Undo Move", 8)
	context_menu.add_item("Redo Move", 9)

	context_menu.id_pressed.connect(_on_context_menu_item)
	overlay.add_child(context_menu)

	# Library item context menu
	library_context_menu = PopupMenu.new()
	library_context_menu.name = "LibraryContextMenu"
	library_context_menu.add_theme_stylebox_override("panel", _create_panel_style())
	library_context_menu.add_theme_color_override("font_color", THEME_TEXT)
	library_context_menu.add_theme_color_override("font_hover_color", THEME_ACCENT)
	library_context_menu.add_theme_font_size_override("font_size", 12)

	library_context_menu.add_item("Select in Scene", 10)
	library_context_menu.add_item("Make Copy", 11)
	library_context_menu.add_separator()
	library_context_menu.add_item("Show" if false else "Hide", 12)
	library_context_menu.add_item("Delete", 13)

	library_context_menu.id_pressed.connect(_on_library_context_menu_item)
	overlay.add_child(library_context_menu)


func _show_context_menu(pos: Vector2) -> void:
	if not selected_element:
		return

	# Update undo/redo availability
	context_menu.set_item_disabled(8, undo_stack.is_empty())
	context_menu.set_item_disabled(9, redo_stack.is_empty())

	# Check if it's a copy (can be deleted)
	var is_copy = selected_item.get("is_copy", false)
	context_menu.set_item_disabled(2, false)  # Delete always available now

	context_menu.position = Vector2i(pos)
	context_menu.popup()


func _show_library_context_menu(pos: Vector2) -> void:
	var path = library_context_item.get("path", "")
	var is_hidden = hidden_elements.get(path, false)
	var is_copy = library_context_item.get("is_copy", false)

	# Update menu item text
	library_context_menu.set_item_text(2, "Show" if is_hidden else "Hide")

	library_context_menu.position = Vector2i(pos)
	library_context_menu.popup()


func _on_context_menu_item(id: int) -> void:
	match id:
		0:  # Duplicate
			_duplicate_selected()
		1:  # Hide
			_hide_selected_element()
		2:  # Delete
			_delete_selected_element()
		3:  # Bring to Front
			_bring_to_front()
		4:  # Send to Back
			_send_to_back()
		5:  # Move Forward
			_move_forward()
		6:  # Move Backward
			_move_backward()
		7:  # Reset Position
			_reset_selected_element()
		8:  # Undo
			_undo()
		9:  # Redo
			_redo()


func _on_library_context_menu_item(id: int) -> void:
	var path = library_context_item.get("path", "")

	match id:
		10:  # Select in Scene
			if not hidden_elements.get(path, false):
				var element = library_context_item.get("element")
				if element:
					_select_element(element)
		11:  # Make Copy
			_duplicate_item(library_context_item)
		12:  # Show/Hide
			if hidden_elements.get(path, false):
				_show_element(path)
			else:
				_hide_element(path)
		13:  # Delete
			_delete_element(path)


func _duplicate_selected() -> void:
	if not selected_element or selected_item.is_empty():
		return
	_duplicate_item(selected_item)


func _duplicate_item(item: Dictionary) -> void:
	var element = item.get("element") as Control
	if not element:
		return

	var original_path = item.get("path", "")
	var item_type = item.get("type", ItemType.OBJECT)
	var category = item.get("category", "Other")

	# Extract parent path and base name for hierarchical path preservation
	var path_parts = original_path.split("/")
	var base_name = path_parts[-1] if path_parts.size() > 0 else original_path
	var parent_path = "/".join(path_parts.slice(0, -1)) if path_parts.size() > 1 else ""

	# Generate unique copy name that doesn't conflict with existing paths
	var copy_num = 1
	var new_base_name = base_name + "_copy" + str(copy_num)
	var test_path = (parent_path + "/" + new_base_name) if parent_path else new_base_name
	while _path_exists(test_path):
		copy_num += 1
		new_base_name = base_name + "_copy" + str(copy_num)
		test_path = (parent_path + "/" + new_base_name) if parent_path else new_base_name

	# Build full hierarchical path
	var new_path = test_path

	# Create duplicate node (includes all children)
	var new_element = element.duplicate() as Control
	new_element.name = new_base_name

	# Add to same parent in scene tree
	var parent = element.get_parent()
	if parent:
		parent.add_child(new_element)

		# Position with slight offset from original
		var offset_x = copy_num * 20
		var offset_y = copy_num * 20
		new_element.offset_left = element.offset_left + 50 + offset_x
		new_element.offset_right = element.offset_right + 50 + offset_x
		new_element.offset_top = element.offset_top + 50 + offset_y
		new_element.offset_bottom = element.offset_bottom + 50 + offset_y

	# Register the copy with proper hierarchical path
	var new_item = {
		"element": new_element,
		"type": item_type,
		"path": new_path,
		"category": category,
		"is_copy": true,
		"source_path": original_path,
	}
	editable_elements.append(new_item)

	# Backup position
	original_positions[new_path] = {
		"left": new_element.offset_left,
		"right": new_element.offset_right,
		"top": new_element.offset_top,
		"bottom": new_element.offset_bottom,
		"z_index": new_element.z_index,
		"child_index": new_element.get_index(),
		"visible": true,
	}

	# CRITICAL: Also register all children of the duplicate
	_register_children_recursively(new_element, new_path, original_path)

	# Record action for undo
	_push_undo_action({
		"type": "create",
		"path": new_path,
		"item": new_item,
	})

	# Select the new element
	_select_element(new_element)
	selected_item = new_item

	_populate_asset_list()
	_populate_scene_tree()  # Update In Scene tab to show children
	_update_type_highlights()
	_update_item_labels()
	_update_selection_outline()
	_update_properties_panel()
	_mark_scene_dirty()

	print("[EditMode] Created copy: %s (with children)" % new_path)


func _path_exists(path: String) -> bool:
	"""Check if a path already exists in editable_elements"""
	for item in editable_elements:
		if item.get("path", "") == path:
			return true
	return false


func _register_children_recursively(parent_node: Node, parent_path: String, original_parent_path: String) -> void:
	"""Recursively register all children of a duplicated node in editable_elements"""
	for child in parent_node.get_children():
		# Skip non-visual nodes
		if not (child is CanvasItem):
			continue

		var child_path = parent_path + "/" + child.name
		var original_child_path = original_parent_path + "/" + child.name

		# Determine type based on node class (using available ItemType values)
		var child_type = ItemType.OBJECT
		if child is Light2D:
			child_type = ItemType.LIGHT
		elif child is Button:
			child_type = ItemType.BUTTON

		var child_item = {
			"element": child,
			"path": child_path,
			"type": child_type,
			"category": "Other",
			"is_copy": true,
			"source_path": original_child_path
		}
		editable_elements.append(child_item)

		# Backup position for child
		if child is Control:
			original_positions[child_path] = {
				"left": child.offset_left,
				"right": child.offset_right,
				"top": child.offset_top,
				"bottom": child.offset_bottom,
				"z_index": child.z_index,
				"child_index": child.get_index(),
				"visible": child.visible,
			}

		# Recurse for nested children
		_register_children_recursively(child, child_path, original_child_path)


func _delete_selected_element() -> void:
	if not selected_element:
		return

	var path = selected_item.get("path", "")
	_delete_element(path)


func _delete_element(path: String) -> void:
	for i in range(editable_elements.size()):
		var item = editable_elements[i]
		if item["path"] == path:
			var element = item["element"]
			var is_copy = item.get("is_copy", false)

			if is_copy:
				# Actually delete copies
				_push_undo_action({
					"type": "delete",
					"path": path,
					"item": item.duplicate(),
					"offsets": {
						"left": element.offset_left,
						"right": element.offset_right,
						"top": element.offset_top,
						"bottom": element.offset_bottom,
					},
				})

				if selected_element == element:
					_clear_selection()

				# Remove all children from tracking first
				var paths_to_remove: Array[String] = []
				for tracked_item in editable_elements:
					var tracked_path = tracked_item.get("path", "")
					if tracked_path.begins_with(path + "/"):
						paths_to_remove.append(tracked_path)

				# Clean up child tracking data
				for child_path in paths_to_remove:
					original_positions.erase(child_path)
					modified_elements.erase(child_path)
					custom_names.erase(child_path)
					hidden_elements.erase(child_path)
					locked_elements.erase(child_path)

				# Remove children from editable_elements (iterate backwards to avoid index issues)
				for j in range(editable_elements.size() - 1, -1, -1):
					var check_item = editable_elements[j]
					var check_path = check_item.get("path", "")
					if check_path.begins_with(path + "/"):
						editable_elements.remove_at(j)

				# Now delete the parent element and its data
				element.queue_free()
				# Find the new index after removing children
				for k in range(editable_elements.size()):
					if editable_elements[k].get("path", "") == path:
						editable_elements.remove_at(k)
						break
				original_positions.erase(path)
				modified_elements.erase(path)
				custom_names.erase(path)
				hidden_elements.erase(path)
				locked_elements.erase(path)
				print("[EditMode] Deleted: %s (with %d children)" % [path, paths_to_remove.size()])
				_mark_scene_dirty()
			else:
				# Just hide original elements (this also triggers dirty)
				_hide_element(path)

			_populate_asset_list()
			_populate_scene_tree()  # Update In Scene tab
			_update_type_highlights()
			_update_item_labels()
			return


func _create_properties_panel() -> void:
	properties_panel = Panel.new()
	properties_panel.name = "PropertiesPanel"
	properties_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	properties_panel.add_theme_stylebox_override("panel", _create_panel_style(true))
	properties_panel.size = Vector2(280, 480)
	overlay.add_child(properties_panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.name = "PropertiesContent"
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.offset_left = 12
	main_vbox.offset_right = -12
	main_vbox.offset_top = 12
	main_vbox.offset_bottom = -12
	main_vbox.add_theme_constant_override("separation", 10)
	properties_panel.add_child(main_vbox)

	# Header
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	main_vbox.add_child(header)

	var title_icon = ColorRect.new()
	title_icon.name = "TitleIcon"
	title_icon.custom_minimum_size = Vector2(4, 16)
	title_icon.color = THEME_ACCENT
	header.add_child(title_icon)

	var title = Label.new()
	title.name = "PropertiesTitle"
	title.text = "PROPERTIES"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", THEME_ACCENT)
	header.add_child(title)

	# Element name container (for editable name)
	var name_container = HBoxContainer.new()
	name_container.name = "NameContainer"
	main_vbox.add_child(name_container)

	# Display label (shown by default)
	var name_label = Label.new()
	name_label.name = "ElementNameLabel"
	name_label.text = "No selection"
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	name_label.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	name_label.gui_input.connect(_on_name_label_clicked)
	name_container.add_child(name_label)

	# Edit field (hidden by default)
	var name_edit = LineEdit.new()
	name_edit.name = "ElementNameEdit"
	name_edit.visible = false
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 11)
	name_edit.add_theme_color_override("font_color", THEME_TEXT)
	name_edit.add_theme_stylebox_override("normal", _create_input_style())
	name_edit.add_theme_stylebox_override("focus", _create_input_style(true))
	name_edit.text_submitted.connect(_on_name_edit_submitted)
	name_edit.focus_exited.connect(_on_name_edit_focus_lost)
	name_container.add_child(name_edit)

	# Asset name label (shows original asset name when display name differs)
	var asset_name_label = Label.new()
	asset_name_label.name = "AssetNameLabel"
	asset_name_label.add_theme_font_size_override("font_size", 10)
	asset_name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	asset_name_label.visible = false
	main_vbox.add_child(asset_name_label)

	# Multi-select section (hidden by default, shown when multiple items selected)
	var multi_section = VBoxContainer.new()
	multi_section.name = "MultiSelectSection"
	multi_section.visible = false
	multi_section.add_theme_constant_override("separation", 8)
	main_vbox.add_child(multi_section)

	var multi_header = Label.new()
	multi_header.name = "MultiSelectHeader"
	multi_header.text = "Multiple (0) selected"
	multi_header.add_theme_font_size_override("font_size", 11)
	multi_header.add_theme_color_override("font_color", THEME_ACCENT)
	multi_section.add_child(multi_header)

	multi_section.add_child(_create_separator())

	# Visibility toggle for multi-select
	var multi_vis_row = HBoxContainer.new()
	multi_vis_row.add_theme_constant_override("separation", 8)
	multi_section.add_child(multi_vis_row)

	var multi_vis_label = Label.new()
	multi_vis_label.text = "Visibility"
	multi_vis_label.add_theme_font_size_override("font_size", 10)
	multi_vis_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
	multi_vis_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	multi_vis_row.add_child(multi_vis_label)

	var multi_show_btn = Button.new()
	multi_show_btn.name = "MultiShowBtn"
	multi_show_btn.text = "Show All"
	multi_show_btn.add_theme_font_size_override("font_size", 9)
	multi_show_btn.add_theme_stylebox_override("normal", _create_button_style(THEME_BG_ELEVATED))
	multi_show_btn.add_theme_stylebox_override("hover", _create_button_style(THEME_BG_HOVER))
	multi_show_btn.pressed.connect(_on_multi_show_all)
	multi_vis_row.add_child(multi_show_btn)

	var multi_hide_btn = Button.new()
	multi_hide_btn.name = "MultiHideBtn"
	multi_hide_btn.text = "Hide All"
	multi_hide_btn.add_theme_font_size_override("font_size", 9)
	multi_hide_btn.add_theme_stylebox_override("normal", _create_button_style(THEME_BG_ELEVATED))
	multi_hide_btn.add_theme_stylebox_override("hover", _create_button_style(THEME_BG_HOVER))
	multi_hide_btn.pressed.connect(_on_multi_hide_all)
	multi_vis_row.add_child(multi_hide_btn)

	# Lock toggle for multi-select
	var multi_lock_row = HBoxContainer.new()
	multi_lock_row.add_theme_constant_override("separation", 8)
	multi_section.add_child(multi_lock_row)

	var multi_lock_label = Label.new()
	multi_lock_label.text = "Lock"
	multi_lock_label.add_theme_font_size_override("font_size", 10)
	multi_lock_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
	multi_lock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	multi_lock_row.add_child(multi_lock_label)

	var multi_lock_btn = Button.new()
	multi_lock_btn.name = "MultiLockBtn"
	multi_lock_btn.text = "Lock All"
	multi_lock_btn.add_theme_font_size_override("font_size", 9)
	multi_lock_btn.add_theme_stylebox_override("normal", _create_button_style(THEME_BG_ELEVATED))
	multi_lock_btn.add_theme_stylebox_override("hover", _create_button_style(THEME_BG_HOVER))
	multi_lock_btn.pressed.connect(_on_multi_lock_all)
	multi_lock_row.add_child(multi_lock_btn)

	var multi_unlock_btn = Button.new()
	multi_unlock_btn.name = "MultiUnlockBtn"
	multi_unlock_btn.text = "Unlock All"
	multi_unlock_btn.add_theme_font_size_override("font_size", 9)
	multi_unlock_btn.add_theme_stylebox_override("normal", _create_button_style(THEME_BG_ELEVATED))
	multi_unlock_btn.add_theme_stylebox_override("hover", _create_button_style(THEME_BG_HOVER))
	multi_unlock_btn.pressed.connect(_on_multi_unlock_all)
	multi_lock_row.add_child(multi_unlock_btn)

	# Z-Index for multi-select
	var multi_z_row = HBoxContainer.new()
	multi_z_row.add_theme_constant_override("separation", 8)
	multi_section.add_child(multi_z_row)

	var multi_z_label = Label.new()
	multi_z_label.text = "Z-Index"
	multi_z_label.add_theme_font_size_override("font_size", 10)
	multi_z_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
	multi_z_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	multi_z_row.add_child(multi_z_label)

	var multi_z_up_btn = Button.new()
	multi_z_up_btn.name = "MultiZUpBtn"
	multi_z_up_btn.text = "+ Forward"
	multi_z_up_btn.add_theme_font_size_override("font_size", 9)
	multi_z_up_btn.add_theme_stylebox_override("normal", _create_button_style(THEME_BG_ELEVATED))
	multi_z_up_btn.add_theme_stylebox_override("hover", _create_button_style(THEME_BG_HOVER))
	multi_z_up_btn.pressed.connect(_on_multi_z_up)
	multi_z_row.add_child(multi_z_up_btn)

	var multi_z_down_btn = Button.new()
	multi_z_down_btn.name = "MultiZDownBtn"
	multi_z_down_btn.text = "- Back"
	multi_z_down_btn.add_theme_font_size_override("font_size", 9)
	multi_z_down_btn.add_theme_stylebox_override("normal", _create_button_style(THEME_BG_ELEVATED))
	multi_z_down_btn.add_theme_stylebox_override("hover", _create_button_style(THEME_BG_HOVER))
	multi_z_down_btn.pressed.connect(_on_multi_z_down)
	multi_z_row.add_child(multi_z_down_btn)

	# Opacity for multi-select
	var multi_opacity_row = HBoxContainer.new()
	multi_opacity_row.add_theme_constant_override("separation", 8)
	multi_section.add_child(multi_opacity_row)

	var multi_opacity_label = Label.new()
	multi_opacity_label.text = "Opacity"
	multi_opacity_label.add_theme_font_size_override("font_size", 10)
	multi_opacity_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
	multi_opacity_row.add_child(multi_opacity_label)

	var multi_opacity_slider = HSlider.new()
	multi_opacity_slider.name = "MultiOpacitySlider"
	multi_opacity_slider.min_value = 0
	multi_opacity_slider.max_value = 100
	multi_opacity_slider.value = 100
	multi_opacity_slider.step = 5
	multi_opacity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	multi_opacity_slider.custom_minimum_size = Vector2(80, 0)
	multi_opacity_slider.value_changed.connect(_on_multi_opacity_changed)
	multi_opacity_row.add_child(multi_opacity_slider)

	var multi_opacity_value = Label.new()
	multi_opacity_value.name = "MultiOpacityValue"
	multi_opacity_value.text = "100%"
	multi_opacity_value.add_theme_font_size_override("font_size", 9)
	multi_opacity_value.add_theme_color_override("font_color", THEME_TEXT)
	multi_opacity_value.custom_minimum_size = Vector2(35, 0)
	multi_opacity_row.add_child(multi_opacity_value)

	multi_section.add_child(_create_separator())

	# Delete for multi-select
	var multi_delete_row = HBoxContainer.new()
	multi_delete_row.add_theme_constant_override("separation", 8)
	multi_section.add_child(multi_delete_row)

	var multi_delete_spacer = Control.new()
	multi_delete_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	multi_delete_row.add_child(multi_delete_spacer)

	var multi_delete_btn = Button.new()
	multi_delete_btn.name = "MultiDeleteBtn"
	multi_delete_btn.text = "Remove All (DEL)"
	multi_delete_btn.add_theme_font_size_override("font_size", 9)
	multi_delete_btn.add_theme_color_override("font_color", THEME_DANGER)
	multi_delete_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.3, 0.1, 0.1)))
	multi_delete_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.5, 0.15, 0.15)))
	multi_delete_btn.pressed.connect(_on_multi_delete_all)
	multi_delete_row.add_child(multi_delete_btn)

	main_vbox.add_child(_create_separator())

	# Scrollable content for property sections
	var scroll = ScrollContainer.new()
	scroll.name = "PropertiesScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	var scroll_content = VBoxContainer.new()
	scroll_content.name = "ScrollContent"
	scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_content.add_theme_constant_override("separation", 12)
	scroll.add_child(scroll_content)

	# TRANSFORM SECTION
	scroll_content.add_child(_create_section_header("Transform"))

	# Position row
	var pos_row = _create_property_row("Position")
	scroll_content.add_child(pos_row)
	var pos_inputs = HBoxContainer.new()
	pos_inputs.add_theme_constant_override("separation", 8)
	pos_row.add_child(pos_inputs)
	prop_pos_x = _create_spinbox("X", -10000, 10000, 1)
	prop_pos_x.value_changed.connect(_on_prop_position_changed)
	pos_inputs.add_child(_create_labeled_input("X", prop_pos_x))
	prop_pos_y = _create_spinbox("Y", -10000, 10000, 1)
	prop_pos_y.value_changed.connect(_on_prop_position_changed)
	pos_inputs.add_child(_create_labeled_input("Y", prop_pos_y))

	# Size row
	var size_row = _create_property_row("Size")
	scroll_content.add_child(size_row)
	var size_inputs = HBoxContainer.new()
	size_inputs.add_theme_constant_override("separation", 8)
	size_row.add_child(size_inputs)
	prop_size_w = _create_spinbox("W", 1, 10000, 1)
	prop_size_w.value_changed.connect(_on_prop_size_changed)
	size_inputs.add_child(_create_labeled_input("W", prop_size_w))
	prop_size_h = _create_spinbox("H", 1, 10000, 1)
	prop_size_h.value_changed.connect(_on_prop_size_changed)
	size_inputs.add_child(_create_labeled_input("H", prop_size_h))

	# Rotation row
	var rot_row = _create_property_row("Rotation")
	scroll_content.add_child(rot_row)
	prop_rotation = _create_spinbox("deg", -180, 180, 1)
	prop_rotation.suffix = "°"
	prop_rotation.value_changed.connect(_on_prop_rotation_changed)
	rot_row.add_child(prop_rotation)

	scroll_content.add_child(_create_separator())

	# APPEARANCE SECTION
	scroll_content.add_child(_create_section_header("Appearance"))

	# Opacity row
	var opacity_row = _create_property_row("Opacity")
	scroll_content.add_child(opacity_row)
	var opacity_box = HBoxContainer.new()
	opacity_box.add_theme_constant_override("separation", 8)
	opacity_row.add_child(opacity_box)
	prop_opacity = HSlider.new()
	prop_opacity.min_value = 0
	prop_opacity.max_value = 100
	prop_opacity.step = 1
	prop_opacity.value = 100
	prop_opacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prop_opacity.custom_minimum_size.x = 100
	prop_opacity.value_changed.connect(_on_prop_opacity_changed)
	opacity_box.add_child(prop_opacity)
	var opacity_label = Label.new()
	opacity_label.name = "OpacityValue"
	opacity_label.text = "100%"
	opacity_label.add_theme_font_size_override("font_size", 10)
	opacity_label.add_theme_color_override("font_color", THEME_TEXT)
	opacity_label.custom_minimum_size.x = 35
	opacity_box.add_child(opacity_label)

	scroll_content.add_child(_create_separator())

	# LAYER SECTION
	scroll_content.add_child(_create_section_header("Layer"))

	# Z-Index row
	var z_row = _create_property_row("Z-Index")
	scroll_content.add_child(z_row)
	prop_z_index = _create_spinbox("z", -1000, 1000, 1)
	prop_z_index.value_changed.connect(_on_prop_z_index_changed)
	z_row.add_child(prop_z_index)

	# Z-order buttons
	var z_buttons = HBoxContainer.new()
	z_buttons.add_theme_constant_override("separation", 4)
	scroll_content.add_child(z_buttons)
	z_buttons.add_child(_create_icon_button(IconType.SEND_BACK, "Send to Back", _send_to_back))
	z_buttons.add_child(_create_icon_button(IconType.MOVE_DOWN, "Send Backward", _move_backward))
	z_buttons.add_child(_create_icon_button(IconType.MOVE_UP, "Bring Forward", _move_forward))
	z_buttons.add_child(_create_icon_button(IconType.BRING_FRONT, "Bring to Front", _bring_to_front))

	scroll_content.add_child(_create_separator())

	# QUICK ACTIONS SECTION
	scroll_content.add_child(_create_section_header("Actions"))

	var actions_row = HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 4)
	scroll_content.add_child(actions_row)

	actions_row.add_child(_create_icon_button(IconType.DUPLICATE, "Duplicate (Ctrl+D)", _duplicate_selected))
	actions_row.add_child(_create_icon_button(IconType.DELETE, "Delete (Del)", _delete_selected_element, THEME_DANGER))
	actions_row.add_child(_create_icon_button(IconType.HIDE, "Hide (H)", _hide_selected_element))
	var reset_btn = _create_icon_button(IconType.UNDO, "Reset Position (R)", _reset_selected_element, THEME_WARNING)
	actions_row.add_child(reset_btn)

	# Lock toggle
	var lock_row = HBoxContainer.new()
	lock_row.add_theme_constant_override("separation", 8)
	scroll_content.add_child(lock_row)
	prop_lock_toggle = CheckButton.new()
	prop_lock_toggle.text = "Lock Element"
	prop_lock_toggle.add_theme_font_size_override("font_size", 10)
	prop_lock_toggle.add_theme_color_override("font_color", THEME_TEXT)
	prop_lock_toggle.tooltip_text = "Prevent moving or modifying this element (L)"
	prop_lock_toggle.toggled.connect(_on_lock_toggled)
	lock_row.add_child(prop_lock_toggle)

	# LIGHT PROPERTIES SECTION (hidden by default, shown when light selected)
	light_section = VBoxContainer.new()
	light_section.name = "LightSection"
	light_section.visible = false
	light_section.add_theme_constant_override("separation", 8)
	scroll_content.add_child(light_section)

	light_section.add_child(_create_separator())
	light_section.add_child(_create_section_header("Light Properties"))

	# Energy/Intensity
	var energy_row = _create_property_row("Energy")
	light_section.add_child(energy_row)
	var energy_box = HBoxContainer.new()
	energy_box.add_theme_constant_override("separation", 8)
	energy_row.add_child(energy_box)
	prop_light_energy = _create_spinbox("", 0, 16, 0.1)
	prop_light_energy.value_changed.connect(_on_light_energy_changed)
	energy_box.add_child(prop_light_energy)
	var energy_label = Label.new()
	energy_label.name = "EnergyHint"
	energy_label.text = "brightness"
	energy_label.add_theme_font_size_override("font_size", 9)
	energy_label.add_theme_color_override("font_color", THEME_TEXT_MUTED)
	energy_box.add_child(energy_label)

	# Light Color
	var color_row = _create_property_row("Color")
	light_section.add_child(color_row)
	prop_light_color = ColorPickerButton.new()
	prop_light_color.custom_minimum_size = Vector2(80, 24)
	prop_light_color.color = Color.WHITE
	prop_light_color.edit_alpha = false
	prop_light_color.color_changed.connect(_on_light_color_changed)
	color_row.add_child(prop_light_color)

	# Texture Scale
	var scale_row = _create_property_row("Texture Scale")
	light_section.add_child(scale_row)
	prop_light_texture_scale = _create_spinbox("", 0.1, 10, 0.1)
	prop_light_texture_scale.value_changed.connect(_on_light_texture_scale_changed)
	scale_row.add_child(prop_light_texture_scale)

	# Blend Mode
	var blend_row = _create_property_row("Blend Mode")
	light_section.add_child(blend_row)
	prop_light_blend_mode = OptionButton.new()
	prop_light_blend_mode.add_item("Add", 0)
	prop_light_blend_mode.add_item("Subtract", 1)
	prop_light_blend_mode.add_item("Mix", 2)
	prop_light_blend_mode.custom_minimum_size = Vector2(100, 24)
	prop_light_blend_mode.add_theme_font_size_override("font_size", 10)
	prop_light_blend_mode.item_selected.connect(_on_light_blend_mode_changed)
	blend_row.add_child(prop_light_blend_mode)

	# Shadow Enable
	var shadow_row = HBoxContainer.new()
	shadow_row.add_theme_constant_override("separation", 8)
	light_section.add_child(shadow_row)
	prop_light_shadow = CheckButton.new()
	prop_light_shadow.text = "Enable Shadows"
	prop_light_shadow.add_theme_font_size_override("font_size", 10)
	prop_light_shadow.add_theme_color_override("font_color", THEME_TEXT)
	prop_light_shadow.toggled.connect(_on_light_shadow_toggled)
	shadow_row.add_child(prop_light_shadow)

	# Shadow Color
	var shadow_color_row = _create_property_row("Shadow Color")
	light_section.add_child(shadow_color_row)
	prop_light_shadow_color = ColorPickerButton.new()
	prop_light_shadow_color.custom_minimum_size = Vector2(80, 24)
	prop_light_shadow_color.color = Color.BLACK
	prop_light_shadow_color.edit_alpha = true
	prop_light_shadow_color.color_changed.connect(_on_light_shadow_color_changed)
	shadow_color_row.add_child(prop_light_shadow_color)

	# COLORRECT PROPERTIES SECTION (hidden by default)
	colorrect_section = VBoxContainer.new()
	colorrect_section.name = "ColorRectSection"
	colorrect_section.visible = false
	colorrect_section.add_theme_constant_override("separation", 8)
	scroll_content.add_child(colorrect_section)

	colorrect_section.add_child(_create_separator())
	colorrect_section.add_child(_create_section_header("ColorRect Properties"))

	var cr_color_row = _create_property_row("Fill Color")
	colorrect_section.add_child(cr_color_row)
	prop_colorrect_color = ColorPickerButton.new()
	prop_colorrect_color.custom_minimum_size = Vector2(120, 24)
	prop_colorrect_color.color = Color.WHITE
	prop_colorrect_color.edit_alpha = true
	prop_colorrect_color.color_changed.connect(_on_colorrect_color_changed)
	cr_color_row.add_child(prop_colorrect_color)

	# TEXTURERECT PROPERTIES SECTION (hidden by default)
	texturerect_section = VBoxContainer.new()
	texturerect_section.name = "TextureRectSection"
	texturerect_section.visible = false
	texturerect_section.add_theme_constant_override("separation", 8)
	scroll_content.add_child(texturerect_section)

	texturerect_section.add_child(_create_separator())
	texturerect_section.add_child(_create_section_header("Texture Properties"))

	# Texture path (read-only info)
	var tex_path_row = _create_property_row("Texture")
	texturerect_section.add_child(tex_path_row)
	prop_texture_path = Label.new()
	prop_texture_path.text = "(none)"
	prop_texture_path.add_theme_font_size_override("font_size", 9)
	prop_texture_path.add_theme_color_override("font_color", THEME_TEXT_MUTED)
	prop_texture_path.clip_text = true
	prop_texture_path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tex_path_row.add_child(prop_texture_path)

	# Flip options
	var flip_row = HBoxContainer.new()
	flip_row.add_theme_constant_override("separation", 16)
	texturerect_section.add_child(flip_row)

	prop_texture_flip_h = CheckButton.new()
	prop_texture_flip_h.text = "Flip H"
	prop_texture_flip_h.add_theme_font_size_override("font_size", 10)
	prop_texture_flip_h.add_theme_color_override("font_color", THEME_TEXT)
	prop_texture_flip_h.toggled.connect(_on_texture_flip_h_changed)
	flip_row.add_child(prop_texture_flip_h)

	prop_texture_flip_v = CheckButton.new()
	prop_texture_flip_v.text = "Flip V"
	prop_texture_flip_v.add_theme_font_size_override("font_size", 10)
	prop_texture_flip_v.add_theme_color_override("font_color", THEME_TEXT)
	prop_texture_flip_v.toggled.connect(_on_texture_flip_v_changed)
	flip_row.add_child(prop_texture_flip_v)

	# Stretch mode
	var stretch_row = _create_property_row("Stretch Mode")
	texturerect_section.add_child(stretch_row)
	prop_texture_stretch_mode = OptionButton.new()
	prop_texture_stretch_mode.add_item("Scale", 0)
	prop_texture_stretch_mode.add_item("Tile", 1)
	prop_texture_stretch_mode.add_item("Keep", 2)
	prop_texture_stretch_mode.add_item("Keep Centered", 3)
	prop_texture_stretch_mode.add_item("Keep Aspect", 4)
	prop_texture_stretch_mode.add_item("Keep Aspect Centered", 5)
	prop_texture_stretch_mode.add_item("Keep Aspect Covered", 6)
	prop_texture_stretch_mode.add_item("Keep Aspect Fit", 7)
	prop_texture_stretch_mode.custom_minimum_size = Vector2(140, 24)
	prop_texture_stretch_mode.add_theme_font_size_override("font_size", 10)
	prop_texture_stretch_mode.item_selected.connect(_on_texture_stretch_mode_changed)
	stretch_row.add_child(prop_texture_stretch_mode)

	# LABEL PROPERTIES SECTION (hidden by default)
	label_section = VBoxContainer.new()
	label_section.name = "LabelSection"
	label_section.visible = false
	label_section.add_theme_constant_override("separation", 8)
	scroll_content.add_child(label_section)

	label_section.add_child(_create_separator())
	label_section.add_child(_create_section_header("Text Properties"))

	var text_row = _create_property_row("Text")
	label_section.add_child(text_row)
	prop_label_text = LineEdit.new()
	prop_label_text.placeholder_text = "Enter text..."
	prop_label_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prop_label_text.add_theme_font_size_override("font_size", 10)
	prop_label_text.add_theme_color_override("font_color", THEME_TEXT)
	prop_label_text.add_theme_stylebox_override("normal", _create_input_style())
	prop_label_text.add_theme_stylebox_override("focus", _create_input_style(true))
	prop_label_text.text_submitted.connect(_on_label_text_submitted)
	prop_label_text.focus_exited.connect(_on_label_text_focus_lost)
	text_row.add_child(prop_label_text)

	# PANEL PROPERTIES SECTION (hidden by default)
	panel_section = VBoxContainer.new()
	panel_section.name = "PanelSection"
	panel_section.visible = false
	panel_section.add_theme_constant_override("separation", 8)
	scroll_content.add_child(panel_section)

	panel_section.add_child(_create_separator())
	panel_section.add_child(_create_section_header("Panel Properties"))

	var panel_color_row = _create_property_row("Self Modulate")
	panel_section.add_child(panel_color_row)
	prop_panel_self_modulate = ColorPickerButton.new()
	prop_panel_self_modulate.custom_minimum_size = Vector2(120, 24)
	prop_panel_self_modulate.color = Color.WHITE
	prop_panel_self_modulate.edit_alpha = true
	prop_panel_self_modulate.color_changed.connect(_on_panel_self_modulate_changed)
	panel_color_row.add_child(prop_panel_self_modulate)


func _create_section_header(text: String) -> HBoxContainer:
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	var bar = ColorRect.new()
	bar.custom_minimum_size = Vector2(3, 12)
	bar.color = THEME_ACCENT_DIM
	header.add_child(bar)
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", THEME_TEXT_DIM)
	header.add_child(label)
	return header


func _create_property_row(label_text: String) -> VBoxContainer:
	var row = VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", THEME_TEXT_DIM)
	row.add_child(label)
	return row


func _create_labeled_input(label_text: String, input: Control) -> HBoxContainer:
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", THEME_ACCENT_DIM)
	label.custom_minimum_size.x = 14
	container.add_child(label)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(input)
	return container


func _create_spinbox(hint: String, min_val: float, max_val: float, step: float) -> SpinBox:
	var spin = SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step
	spin.custom_minimum_size = Vector2(60, 24)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.allow_greater = true  # Allow typing values beyond max
	spin.allow_lesser = true   # Allow typing values below min
	spin.update_on_text_changed = true  # Update value as you type

	# Style the internal LineEdit
	var line_edit = spin.get_line_edit()
	line_edit.add_theme_font_size_override("font_size", 10)
	line_edit.add_theme_color_override("font_color", THEME_TEXT)
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = THEME_BG
	input_style.border_color = THEME_BORDER_SUBTLE
	input_style.set_border_width_all(1)
	input_style.set_corner_radius_all(4)
	input_style.content_margin_left = 6
	input_style.content_margin_right = 6
	line_edit.add_theme_stylebox_override("normal", input_style)

	# Add focus style
	var focus_style = input_style.duplicate()
	focus_style.border_color = THEME_ACCENT
	line_edit.add_theme_stylebox_override("focus", focus_style)

	# Disable arrow key navigation - must wait until node is in scene tree
	spin.focus_mode = Control.FOCUS_CLICK  # Only focus on click, not keyboard nav

	# Set focus neighbors after node is in tree
	spin.ready.connect(func():
		# Point all focus directions to self to prevent navigation
		spin.focus_neighbor_top = spin.get_path()
		spin.focus_neighbor_bottom = spin.get_path()
		var le = spin.get_line_edit()
		le.focus_neighbor_top = le.get_path()
		le.focus_neighbor_bottom = le.get_path()
		le.focus_next = le.get_path()
		le.focus_previous = le.get_path()
	)

	# Custom input handler for modifier keys (Shift for 10x, Ctrl for 0.1x step)
	var base_step = step
	line_edit.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and not event.is_echo():
			if event.keycode == KEY_UP or event.keycode == KEY_DOWN:
				var multiplier = 1.0
				if event.shift_pressed:
					multiplier = 10.0  # Shift = 10x step
				elif event.ctrl_pressed:
					multiplier = 0.1   # Ctrl = 0.1x step

				var delta = base_step * multiplier
				if event.keycode == KEY_DOWN:
					delta = -delta

				spin.value += delta
				# Stop the event from propagating - use multiple methods
				line_edit.accept_event()
				spin.get_viewport().set_input_as_handled()
	)

	return spin


func _create_separator() -> HSeparator:
	var sep = HSeparator.new()
	sep.add_theme_color_override("separator", THEME_BORDER_SUBTLE)
	return sep


# Property change handlers
func _on_prop_position_changed(_value: float) -> void:
	if _updating_properties or not selected_element:
		return

	var new_x = prop_pos_x.value
	var new_y = prop_pos_y.value

	if selected_element is Control:
		var width = selected_element.offset_right - selected_element.offset_left
		var height = selected_element.offset_bottom - selected_element.offset_top

		_push_undo_action({
			"type": "move",
			"path": selected_item.get("path", ""),
			"old_offsets": _get_element_drag_state(selected_element),
			"new_offsets": {
				"is_control": true,
				"left": new_x,
				"right": new_x + width,
				"top": new_y,
				"bottom": new_y + height,
			},
		})

		selected_element.offset_left = new_x
		selected_element.offset_right = new_x + width
		selected_element.offset_top = new_y
		selected_element.offset_bottom = new_y + height
	elif selected_element is Node2D:
		_push_undo_action({
			"type": "move",
			"path": selected_item.get("path", ""),
			"old_offsets": _get_element_drag_state(selected_element),
			"new_offsets": {
				"is_control": false,
				"position": Vector2(new_x, new_y),
			},
		})
		selected_element.position = Vector2(new_x, new_y)

	_update_selection_outline()
	_mark_element_modified(selected_item.get("path", ""))


func _on_prop_size_changed(_value: float) -> void:
	if _updating_properties or not selected_element:
		return
	if not (selected_element is Control):
		return

	var new_w = prop_size_w.value
	var new_h = prop_size_h.value

	selected_element.offset_right = selected_element.offset_left + new_w
	selected_element.offset_bottom = selected_element.offset_top + new_h
	_update_selection_outline()
	_mark_element_modified(selected_item.get("path", ""))


func _on_prop_rotation_changed(value: float) -> void:
	if _updating_properties or not selected_element:
		return

	selected_element.rotation_degrees = value
	_update_selection_outline()
	_mark_element_modified(selected_item.get("path", ""))


func _on_prop_opacity_changed(value: float) -> void:
	if _updating_properties or not selected_element:
		return

	selected_element.modulate.a = value / 100.0
	# Update label
	var opacity_label = properties_panel.get_node_or_null("PropertiesContent/PropertiesScroll/ScrollContent/OpacityValue")
	if not opacity_label:
		# Find it differently
		for child in properties_panel.get_children():
			var found = child.find_child("OpacityValue", true, false)
			if found:
				found.text = "%d%%" % int(value)
				break
	_mark_element_modified(selected_item.get("path", ""))


func _on_prop_z_index_changed(value: float) -> void:
	if _updating_properties or not selected_element:
		return

	var old_z = selected_element.z_index
	_push_undo_action({
		"type": "z_order",
		"path": selected_item.get("path", ""),
		"old_z_index": old_z,
		"new_z_index": int(value),
		"old_z_as_relative": selected_element.z_as_relative,
	})

	selected_element.z_as_relative = false
	selected_element.z_index = int(value)
	_mark_element_modified(selected_item.get("path", ""))


# Multi-select property callbacks
func _on_multi_show_all() -> void:
	for elem in multi_selected:
		var item = _get_item_for_element(elem)
		var path = item.get("path", "")
		if hidden_elements.get(path, false):
			elem.visible = true
			hidden_elements.erase(path)
	_populate_scene_tree()
	_update_multi_selection_outline()
	_mark_scene_dirty()
	print("[EditMode] Showed %d elements" % multi_selected.size())


func _on_multi_hide_all() -> void:
	for elem in multi_selected:
		var item = _get_item_for_element(elem)
		var path = item.get("path", "")
		elem.visible = false
		hidden_elements[path] = true
	_clear_multi_selection()
	_clear_selection()
	_populate_scene_tree()
	_mark_scene_dirty()
	print("[EditMode] Hid %d elements" % multi_selected.size())


func _on_multi_lock_all() -> void:
	for elem in multi_selected:
		var item = _get_item_for_element(elem)
		var path = item.get("path", "")
		locked_elements[path] = true
	_update_selection_outline()
	_update_multi_selection_outline()
	_mark_scene_dirty()
	print("[EditMode] Locked %d elements" % multi_selected.size())


func _on_multi_unlock_all() -> void:
	for elem in multi_selected:
		var item = _get_item_for_element(elem)
		var path = item.get("path", "")
		locked_elements.erase(path)
	_update_selection_outline()
	_update_multi_selection_outline()
	_mark_scene_dirty()
	print("[EditMode] Unlocked %d elements" % multi_selected.size())


func _on_multi_z_up() -> void:
	for elem in multi_selected:
		var item = _get_item_for_element(elem)
		elem.z_as_relative = false
		elem.z_index += 1
		_mark_element_modified(item.get("path", ""))
	print("[EditMode] Moved %d elements forward" % multi_selected.size())


func _on_multi_z_down() -> void:
	for elem in multi_selected:
		var item = _get_item_for_element(elem)
		elem.z_as_relative = false
		elem.z_index -= 1
		_mark_element_modified(item.get("path", ""))
	print("[EditMode] Moved %d elements back" % multi_selected.size())


func _on_multi_opacity_changed(value: float) -> void:
	for elem in multi_selected:
		var item = _get_item_for_element(elem)
		elem.modulate.a = value / 100.0
		_mark_element_modified(item.get("path", ""))
	# Update the opacity value label
	var multi_section = properties_panel.find_child("MultiSelectSection", true, false)
	if multi_section:
		var opacity_label = multi_section.find_child("MultiOpacityValue", true, false) as Label
		if opacity_label:
			opacity_label.text = "%d%%" % int(value)
	print("[EditMode] Set opacity to %d%% for %d elements" % [int(value), multi_selected.size()])


func _on_multi_delete_all() -> void:
	if multi_selected.is_empty():
		return

	# Build list of elements to delete, filtering out children whose parents are also selected
	var to_delete: Array = []
	for elem in multi_selected:
		if not _has_parent_in_list(elem, multi_selected):
			to_delete.append(elem)

	var deleted_count = 0
	var hidden_count = 0

	# Process each element - copies get deleted, originals get hidden
	for elem in to_delete:
		var item = _get_item_for_element(elem)
		if item.is_empty():
			continue
		var path = item.get("path", "")
		var is_copy = item.get("is_copy", false)

		if is_copy:
			# Actually delete copies
			if selected_element == elem:
				_clear_selection()

			# Remove children from tracking
			var paths_to_remove: Array[String] = []
			for tracked_item in editable_elements:
				var tracked_path = tracked_item.get("path", "")
				if tracked_path.begins_with(path + "/"):
					paths_to_remove.append(tracked_path)

			for child_path in paths_to_remove:
				original_positions.erase(child_path)
				modified_elements.erase(child_path)
				custom_names.erase(child_path)
				hidden_elements.erase(child_path)
				locked_elements.erase(child_path)

			# Remove children from editable_elements
			for j in range(editable_elements.size() - 1, -1, -1):
				var check_item = editable_elements[j]
				var check_path = check_item.get("path", "")
				if check_path.begins_with(path + "/"):
					editable_elements.remove_at(j)

			# Delete the element
			elem.queue_free()

			# Remove from editable_elements
			for k in range(editable_elements.size() - 1, -1, -1):
				if editable_elements[k].get("path", "") == path:
					editable_elements.remove_at(k)
					break

			original_positions.erase(path)
			modified_elements.erase(path)
			custom_names.erase(path)
			hidden_elements.erase(path)
			locked_elements.erase(path)
			deleted_count += 1
		else:
			# Hide original elements (can't delete scene elements)
			elem.visible = false
			hidden_elements[path] = true
			hidden_count += 1

	_clear_multi_selection()
	_clear_selection()
	_populate_scene_tree()
	_populate_asset_list()
	_update_properties_panel()
	_mark_scene_dirty()

	if deleted_count > 0 and hidden_count > 0:
		print("[EditMode] Deleted %d copies, hid %d original elements" % [deleted_count, hidden_count])
	elif deleted_count > 0:
		print("[EditMode] Deleted %d copies" % deleted_count)
	else:
		print("[EditMode] Hid %d original elements (use Show All to restore)" % hidden_count)


func _update_properties_panel() -> void:
	_updating_properties = true  # Prevent feedback loops

	# Check for multi-selection mode
	var is_multi_select = multi_selected.size() > 1
	var multi_section = properties_panel.find_child("MultiSelectSection", true, false)
	var scroll_container = properties_panel.find_child("PropertiesScroll", true, false)
	var name_container = properties_panel.find_child("NameContainer", true, false)

	if is_multi_select:
		print("[EditMode] Multi-select mode: %d items, panel valid: %s, multi_section found: %s" % [multi_selected.size(), properties_panel != null, multi_section != null])

	if multi_section:
		multi_section.visible = is_multi_select
		# Update multi-select header
		var multi_header = multi_section.find_child("MultiSelectHeader", true, false) as Label
		if multi_header:
			multi_header.text = "Multiple (%d) selected" % multi_selected.size()
	elif is_multi_select:
		print("[EditMode] WARNING: MultiSelectSection not found!")

	if scroll_container:
		scroll_container.visible = not is_multi_select
	elif is_multi_select:
		print("[EditMode] WARNING: PropertiesScroll not found!")

	if name_container:
		name_container.visible = not is_multi_select

	# If multi-select, skip individual property updates
	if is_multi_select:
		_updating_properties = false
		return

	# Update element name label
	var name_label = properties_panel.find_child("ElementNameLabel", true, false) as Label
	if name_label:
		if selected_element:
			var display_name = _get_display_name(selected_item)
			var item_type = selected_item.get("type", ItemType.OBJECT)
			var type_name = TYPE_NAMES.get(item_type, "Object")
			name_label.text = "%s - %s" % [display_name, type_name]
			name_label.add_theme_color_override("font_color", TYPE_COLORS.get(item_type, THEME_TEXT))
			name_label.mouse_default_cursor_shape = Control.CURSOR_IBEAM
		else:
			name_label.text = "No selection"
			name_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
			name_label.mouse_default_cursor_shape = Control.CURSOR_ARROW

	# Update asset name label (shows original asset name when display name differs)
	var asset_name_label = properties_panel.find_child("AssetNameLabel", true, false) as Label
	if asset_name_label:
		if selected_element and selected_item:
			var display_name = _get_display_name(selected_item)
			var asset_name = _get_asset_name(selected_item)
			if display_name != asset_name:
				asset_name_label.text = "Asset: " + asset_name
				asset_name_label.visible = true
			else:
				asset_name_label.visible = false
		else:
			asset_name_label.visible = false

	# Update title icon color
	var title_icon = properties_panel.get_node_or_null("PropertiesContent/HBoxContainer/TitleIcon") as ColorRect
	if title_icon:
		if selected_element:
			var item_type = selected_item.get("type", ItemType.OBJECT)
			title_icon.color = TYPE_COLORS.get(item_type, THEME_ACCENT)
		else:
			title_icon.color = THEME_ACCENT

	# Update input values
	if selected_element:
		var is_control = selected_element is Control

		# Position
		if prop_pos_x and is_control:
			prop_pos_x.value = selected_element.offset_left
			prop_pos_x.editable = true
		elif prop_pos_x:
			prop_pos_x.value = selected_element.position.x if selected_element is Node2D else 0
			prop_pos_x.editable = selected_element is Node2D

		if prop_pos_y and is_control:
			prop_pos_y.value = selected_element.offset_top
			prop_pos_y.editable = true
		elif prop_pos_y:
			prop_pos_y.value = selected_element.position.y if selected_element is Node2D else 0
			prop_pos_y.editable = selected_element is Node2D

		# Size
		if prop_size_w and is_control:
			prop_size_w.value = selected_element.size.x
			prop_size_w.editable = true
		elif prop_size_w:
			prop_size_w.editable = false

		if prop_size_h and is_control:
			prop_size_h.value = selected_element.size.y
			prop_size_h.editable = true
		elif prop_size_h:
			prop_size_h.editable = false

		# Rotation
		if prop_rotation:
			prop_rotation.value = selected_element.rotation_degrees
			prop_rotation.editable = true

		# Opacity
		if prop_opacity:
			prop_opacity.value = selected_element.modulate.a * 100
			prop_opacity.editable = true
			# Update opacity label
			_update_opacity_label(selected_element.modulate.a * 100)

		# Z-Index
		if prop_z_index:
			prop_z_index.value = selected_element.z_index
			prop_z_index.editable = true
	else:
		# Disable all inputs when nothing selected
		if prop_pos_x:
			prop_pos_x.value = 0
			prop_pos_x.editable = false
		if prop_pos_y:
			prop_pos_y.value = 0
			prop_pos_y.editable = false
		if prop_size_w:
			prop_size_w.value = 0
			prop_size_w.editable = false
		if prop_size_h:
			prop_size_h.value = 0
			prop_size_h.editable = false
		if prop_rotation:
			prop_rotation.value = 0
			prop_rotation.editable = false
		if prop_opacity:
			prop_opacity.value = 100
			prop_opacity.editable = false
			_update_opacity_label(100)
		if prop_z_index:
			prop_z_index.value = 0
			prop_z_index.editable = false

	# Update lock toggle
	if prop_lock_toggle:
		if selected_element:
			var path = selected_item.get("path", "")
			prop_lock_toggle.button_pressed = locked_elements.get(path, false)
			prop_lock_toggle.disabled = false
		else:
			prop_lock_toggle.button_pressed = false
			prop_lock_toggle.disabled = true

	# Update type-specific properties
	_update_light_properties()
	_update_colorrect_properties()
	_update_texturerect_properties()
	_update_label_properties()
	_update_panel_properties()

	_updating_properties = false


func _update_opacity_label(value: float) -> void:
	# Find the opacity label and update it
	var scroll_content = properties_panel.get_node_or_null("PropertiesContent/PropertiesScroll/ScrollContent")
	if scroll_content:
		var opacity_label = scroll_content.find_child("OpacityValue", true, false) as Label
		if opacity_label:
			opacity_label.text = "%d%%" % int(value)


func _update_light_properties() -> void:
	# Show/hide light section and populate values
	var is_light = selected_element and _is_light_node(selected_element)

	if light_section:
		light_section.visible = is_light

	if not is_light:
		return

	# Populate light values
	if prop_light_energy:
		prop_light_energy.value = selected_element.energy

	if prop_light_color:
		prop_light_color.color = selected_element.color

	if prop_light_texture_scale and selected_element is PointLight2D:
		prop_light_texture_scale.value = selected_element.texture_scale
		prop_light_texture_scale.editable = true
	elif prop_light_texture_scale:
		prop_light_texture_scale.editable = false

	if prop_light_blend_mode:
		prop_light_blend_mode.selected = selected_element.blend_mode

	if prop_light_shadow:
		prop_light_shadow.button_pressed = selected_element.shadow_enabled

	if prop_light_shadow_color:
		prop_light_shadow_color.color = selected_element.shadow_color


func _is_light_node(node) -> bool:
	return node is PointLight2D or node is DirectionalLight2D or node is Light2D


# ColorRect property functions
func _update_colorrect_properties() -> void:
	var is_colorrect = selected_element and selected_element is ColorRect

	if colorrect_section:
		colorrect_section.visible = is_colorrect

	if not is_colorrect:
		return

	if prop_colorrect_color:
		prop_colorrect_color.color = selected_element.color


func _on_colorrect_color_changed(color: Color) -> void:
	if _updating_properties or not selected_element:
		return
	if not selected_element is ColorRect:
		return
	selected_element.color = color
	_mark_element_modified(selected_item.get("path", ""))


# TextureRect property functions
func _update_texturerect_properties() -> void:
	var is_texturerect = selected_element and selected_element is TextureRect

	if texturerect_section:
		texturerect_section.visible = is_texturerect

	if not is_texturerect:
		return

	if prop_texture_path:
		var tex = selected_element.texture
		if tex and tex.resource_path:
			prop_texture_path.text = tex.resource_path.get_file()
		else:
			prop_texture_path.text = "(none)"

	if prop_texture_flip_h:
		prop_texture_flip_h.button_pressed = selected_element.flip_h

	if prop_texture_flip_v:
		prop_texture_flip_v.button_pressed = selected_element.flip_v

	if prop_texture_stretch_mode:
		prop_texture_stretch_mode.selected = selected_element.stretch_mode


func _on_texture_flip_h_changed(pressed: bool) -> void:
	if _updating_properties or not selected_element:
		return
	if not selected_element is TextureRect:
		return
	selected_element.flip_h = pressed
	_mark_element_modified(selected_item.get("path", ""))


func _on_texture_flip_v_changed(pressed: bool) -> void:
	if _updating_properties or not selected_element:
		return
	if not selected_element is TextureRect:
		return
	selected_element.flip_v = pressed
	_mark_element_modified(selected_item.get("path", ""))


func _on_texture_stretch_mode_changed(index: int) -> void:
	if _updating_properties or not selected_element:
		return
	if not selected_element is TextureRect:
		return
	selected_element.stretch_mode = index
	_mark_element_modified(selected_item.get("path", ""))


# Label/RichTextLabel property functions
func _update_label_properties() -> void:
	var is_label = selected_element and (selected_element is Label or selected_element is RichTextLabel)

	if label_section:
		label_section.visible = is_label

	if not is_label:
		return

	if prop_label_text:
		if selected_element is Label:
			prop_label_text.text = selected_element.text
		elif selected_element is RichTextLabel:
			prop_label_text.text = selected_element.text


func _on_label_text_submitted(new_text: String) -> void:
	_apply_label_text(new_text)


func _on_label_text_focus_lost() -> void:
	if prop_label_text:
		_apply_label_text(prop_label_text.text)


func _apply_label_text(new_text: String) -> void:
	if _updating_properties or not selected_element:
		return
	if selected_element is Label:
		selected_element.text = new_text
		_mark_element_modified(selected_item.get("path", ""))
	elif selected_element is RichTextLabel:
		selected_element.text = new_text
		_mark_element_modified(selected_item.get("path", ""))


# Panel property functions
func _update_panel_properties() -> void:
	var is_panel = selected_element and selected_element is Panel

	if panel_section:
		panel_section.visible = is_panel

	if not is_panel:
		return

	if prop_panel_self_modulate:
		prop_panel_self_modulate.color = selected_element.self_modulate


func _on_panel_self_modulate_changed(color: Color) -> void:
	if _updating_properties or not selected_element:
		return
	if not selected_element is Panel:
		return
	selected_element.self_modulate = color
	_mark_element_modified(selected_item.get("path", ""))


# Name editing functions
func _get_display_name(item: Dictionary) -> String:
	"""Get the display name for an item, using custom name if set"""
	var path = item.get("path", "")
	if custom_names.has(path):
		return custom_names[path]
	return _get_asset_name(item)


func _get_asset_name(item: Dictionary) -> String:
	"""Get the asset name (node name) for an item"""
	var element = item.get("element")
	if element:
		return element.name
	return item.get("path", "").get_file()


func _on_name_label_clicked(event: InputEvent) -> void:
	"""Handle click on name label to start editing"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if selected_element:
			_start_name_edit()


func _start_name_edit() -> void:
	"""Switch from label to edit field"""
	var name_label = properties_panel.find_child("ElementNameLabel", true, false) as Label
	var name_edit = properties_panel.find_child("ElementNameEdit", true, false) as LineEdit
	if name_label and name_edit:
		# Extract just the name part (before the " - Type")
		var display_name = _get_display_name(selected_item)
		name_edit.text = display_name
		name_label.visible = false
		name_edit.visible = true
		name_edit.grab_focus()
		name_edit.select_all()


func _on_name_edit_submitted(new_name: String) -> void:
	"""Handle Enter key in name edit field"""
	_finish_name_edit(new_name)


func _on_name_edit_focus_lost() -> void:
	"""Handle focus lost from name edit field"""
	var name_edit = properties_panel.find_child("ElementNameEdit", true, false) as LineEdit
	if name_edit and name_edit.visible:
		_finish_name_edit(name_edit.text)


func _finish_name_edit(new_name: String) -> void:
	"""Complete name editing and save the custom name"""
	var name_label = properties_panel.find_child("ElementNameLabel", true, false) as Label
	var name_edit = properties_panel.find_child("ElementNameEdit", true, false) as LineEdit

	if name_label and name_edit:
		name_edit.visible = false
		name_label.visible = true

		# Save the custom name
		var path = selected_item.get("path", "")
		if not path.is_empty() and not new_name.strip_edges().is_empty():
			var clean_name = new_name.strip_edges()
			if clean_name != _get_asset_name(selected_item):
				custom_names[path] = clean_name
			else:
				# Reverted to asset name, remove custom name
				custom_names.erase(path)

			_mark_scene_dirty()

		_update_properties_panel()
		_update_status_bar()
		_populate_asset_list()
		_populate_scene_tree()


func _cancel_name_edit() -> bool:
	"""Cancel name editing if active, returns true if editing was cancelled"""
	var name_edit = properties_panel.find_child("ElementNameEdit", true, false) as LineEdit
	var name_label = properties_panel.find_child("ElementNameLabel", true, false) as Label
	if name_edit and name_edit.visible:
		name_edit.visible = false
		if name_label:
			name_label.visible = true
		return true
	return false


# Light property change handlers
func _on_light_energy_changed(value: float) -> void:
	if _updating_properties or not selected_element:
		return
	if not _is_light_node(selected_element):
		return
	selected_element.energy = value
	_mark_element_modified(selected_item.get("path", ""))


func _on_light_color_changed(color: Color) -> void:
	if _updating_properties or not selected_element:
		return
	if not _is_light_node(selected_element):
		return
	selected_element.color = color
	_mark_element_modified(selected_item.get("path", ""))


func _on_light_texture_scale_changed(value: float) -> void:
	if _updating_properties or not selected_element:
		return
	if not selected_element is PointLight2D:
		return
	selected_element.texture_scale = value
	_mark_element_modified(selected_item.get("path", ""))


func _on_light_blend_mode_changed(index: int) -> void:
	if _updating_properties or not selected_element:
		return
	if not _is_light_node(selected_element):
		return
	selected_element.blend_mode = index
	_mark_element_modified(selected_item.get("path", ""))


func _on_light_shadow_toggled(enabled: bool) -> void:
	if _updating_properties or not selected_element:
		return
	if not _is_light_node(selected_element):
		return
	selected_element.shadow_enabled = enabled
	_mark_element_modified(selected_item.get("path", ""))


func _on_light_shadow_color_changed(color: Color) -> void:
	if _updating_properties or not selected_element:
		return
	if not _is_light_node(selected_element):
		return
	selected_element.shadow_color = color
	_mark_element_modified(selected_item.get("path", ""))


# Lock toggle handler
func _on_lock_toggled(locked: bool) -> void:
	if _updating_properties or not selected_element:
		return
	var path = selected_item.get("path", "")
	if path.is_empty():
		return

	if locked:
		locked_elements[path] = true
	else:
		locked_elements.erase(path)

	_update_selection_outline()
	_populate_asset_list()  # Refresh to show lock icon
	print("[EditMode] %s: %s" % ["Locked" if locked else "Unlocked", path])


func _is_element_locked(element) -> bool:
	if not element:
		return false
	for item in editable_elements:
		if item["element"] == element:
			return locked_elements.get(item["path"], false)
	return false


func _toggle_selected_lock() -> void:
	if not selected_element:
		return
	var path = selected_item.get("path", "")
	if path.is_empty():
		return

	var is_locked = locked_elements.get(path, false)
	if is_locked:
		locked_elements.erase(path)
	else:
		locked_elements[path] = true

	_update_properties_panel()
	_update_selection_outline()
	_populate_asset_list()
	_mark_scene_dirty()
	print("[EditMode] %s: %s" % ["Locked" if not is_locked else "Unlocked", path])


func _is_text_input_focused() -> bool:
	# Check if any text input (LineEdit, TextEdit, SpinBox) has focus
	var focused = get_viewport().gui_get_focus_owner()
	if focused:
		if focused is LineEdit or focused is TextEdit:
			return true
		# Check if it's a SpinBox's internal LineEdit
		if focused.get_parent() is SpinBox:
			return true
	return false


func _nudge_selected(keycode: int, shift_held: bool) -> void:
	if not selected_element:
		return

	# Determine nudge amount: 1 pixel normally, 10 with Shift
	var amount = 10.0 if shift_held else 1.0
	var delta = Vector2.ZERO

	match keycode:
		KEY_UP:
			delta = Vector2(0, -amount)
		KEY_DOWN:
			delta = Vector2(0, amount)
		KEY_LEFT:
			delta = Vector2(-amount, 0)
		KEY_RIGHT:
			delta = Vector2(amount, 0)

	if delta == Vector2.ZERO:
		return

	# Record for undo
	var path = selected_item.get("path", "")
	_push_undo_action({
		"type": "move",
		"path": path,
		"old_offsets": _get_element_drag_state(selected_element),
		"new_offsets": {},  # Will be filled after move
	})

	# Apply the nudge
	if selected_element is Control:
		selected_element.offset_left += delta.x
		selected_element.offset_right += delta.x
		selected_element.offset_top += delta.y
		selected_element.offset_bottom += delta.y
	elif selected_element is Node2D:
		selected_element.position += delta

	# Update undo with new position
	undo_stack[undo_stack.size() - 1]["new_offsets"] = _get_element_drag_state(selected_element)

	_mark_element_modified(selected_element)
	_update_selection_outline()
	_update_properties_panel()


func _create_status_bar() -> void:
	status_bar = Panel.new()
	status_bar.name = "StatusBar"
	status_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	status_bar.add_theme_stylebox_override("panel", _create_panel_style())
	status_bar.size = Vector2(900, 36)
	overlay.add_child(status_bar)

	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 12
	hbox.offset_right = -12
	hbox.offset_top = 6
	hbox.offset_bottom = -6
	hbox.add_theme_constant_override("separation", 12)
	status_bar.add_child(hbox)

	# Zoom indicator
	var zoom_box = HBoxContainer.new()
	zoom_box.add_theme_constant_override("separation", 4)
	hbox.add_child(zoom_box)

	var zoom_icon = Label.new()
	zoom_icon.text = "Z:"
	zoom_icon.add_theme_font_size_override("font_size", 12)
	zoom_box.add_child(zoom_icon)

	var zoom_label = Label.new()
	zoom_label.name = "ZoomLabel"
	zoom_label.text = "100%"
	zoom_label.add_theme_font_size_override("font_size", 11)
	zoom_label.add_theme_color_override("font_color", THEME_ACCENT)
	zoom_label.custom_minimum_size.x = 40
	zoom_box.add_child(zoom_label)

	hbox.add_child(_create_status_separator())

	# Selection info
	var selection_label = Label.new()
	selection_label.name = "SelectionLabel"
	selection_label.text = "No selection"
	selection_label.add_theme_font_size_override("font_size", 11)
	selection_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
	selection_label.custom_minimum_size.x = 140
	hbox.add_child(selection_label)

	hbox.add_child(_create_status_separator())

	# Status/hint (flexible width)
	var hint_label = Label.new()
	hint_label.name = "HintLabel"
	hint_label.text = "Ctrl+Wheel: Zoom | Ctrl+Drag or Middle: Pan"
	hint_label.add_theme_font_size_override("font_size", 10)
	hint_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(hint_label)

	hbox.add_child(_create_status_separator())

	# Modified elements count
	var modified_label = Label.new()
	modified_label.name = "ModifiedLabel"
	modified_label.text = "0 changes"
	modified_label.add_theme_font_size_override("font_size", 10)
	modified_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
	modified_label.tooltip_text = "Number of modified elements"
	hbox.add_child(modified_label)

	hbox.add_child(_create_status_separator())

	# Player handle
	var player_label = Label.new()
	player_label.name = "PlayerLabel"
	player_label.text = "Guest"
	player_label.add_theme_font_size_override("font_size", 10)
	player_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
	player_label.tooltip_text = "Current player"
	hbox.add_child(player_label)

	hbox.add_child(_create_status_separator())

	# Connection status with colored dot and text
	var conn_box = HBoxContainer.new()
	conn_box.add_theme_constant_override("separation", 6)
	hbox.add_child(conn_box)

	# Use a ColorRect for the dot instead of font symbol
	var dot_container = CenterContainer.new()
	dot_container.custom_minimum_size = Vector2(10, 20)
	conn_box.add_child(dot_container)

	var conn_dot = ColorRect.new()
	conn_dot.name = "ConnectionDot"
	conn_dot.custom_minimum_size = Vector2(8, 8)
	conn_dot.color = Color(1.0, 0.3, 0.3)  # Red = offline
	dot_container.add_child(conn_dot)

	var conn_label = Label.new()
	conn_label.name = "ConnectionLabel"
	conn_label.text = "Offline"
	conn_label.add_theme_font_size_override("font_size", 10)
	conn_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
	conn_label.tooltip_text = "Server connection status"
	conn_box.add_child(conn_label)


func _create_status_separator() -> Label:
	var sep = Label.new()
	sep.text = "|"
	sep.add_theme_font_size_override("font_size", 10)
	sep.add_theme_color_override("font_color", Color(THEME_BORDER.r, THEME_BORDER.g, THEME_BORDER.b, 0.3))
	return sep


func _update_overlay_positions() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var margin = 10
	var toolbar_height = 50
	var status_height = 36

	# Toolbar - spans full width
	toolbar.position = Vector2(margin, margin)
	toolbar.size = Vector2(viewport_size.x - margin * 2, toolbar_height)

	# Asset Library - left side, fills height between toolbar and status bar
	var side_panel_top = margin + toolbar_height + margin
	var side_panel_height = viewport_size.y - side_panel_top - status_height - margin * 2
	asset_library.position = Vector2(margin, side_panel_top)
	asset_library.size = Vector2(240, side_panel_height)

	# Properties Panel - right side, use full available height
	properties_panel.position = Vector2(viewport_size.x - 300 - margin, side_panel_top)
	properties_panel.size = Vector2(300, side_panel_height)

	# Status Bar - centered at bottom
	status_bar.position = Vector2((viewport_size.x - status_bar.size.x) / 2, viewport_size.y - status_height - margin)


func _process(delta: float) -> void:
	if not edit_mode_enabled:
		return

	# Skip hover detection while panning or dragging
	if is_panning or is_dragging:
		if hovered_element:
			hovered_element = null
			_update_hover_outline()
	else:
		var mouse_pos = get_viewport().get_mouse_position()
		var element_under_mouse = _get_element_at_position(mouse_pos)

		# ALT held: show parent element instead
		if element_under_mouse and Input.is_key_pressed(KEY_ALT):
			var item = _get_item_for_element(element_under_mouse)
			var parent_item = _get_parent_item(item)
			if not parent_item.is_empty() and parent_item.get("element"):
				element_under_mouse = parent_item["element"]

		if element_under_mouse != hovered_element:
			hovered_element = element_under_mouse
			_update_hover_outline()

	if is_dragging or is_resizing:
		_update_selection_outline()
		_update_properties_panel()
		_update_type_highlights()
		_update_item_labels()

	if is_panning:
		_update_type_highlights()
		_update_item_labels()
		_update_selection_outline()
		_update_hover_outline()

	# Handle status message timeout
	if _save_status in ["success", "error"]:
		_status_timer += delta
		if _status_timer >= STATUS_DISPLAY_TIME:
			_save_status = ""
			_save_message = ""
			_status_timer = 0.0
			_update_status_bar()

	# Periodic connection status check
	_connection_check_timer += delta
	if _connection_check_timer >= CONNECTION_CHECK_INTERVAL:
		_connection_check_timer = 0.0
		_check_connection_status()


func _check_connection_status() -> void:
	"""Check if connection status changed and update status bar if needed"""
	var is_online = OnlineManager and OnlineManager.is_online
	var is_ws = OnlineManager and OnlineManager.is_websocket_connected()

	if is_online != _last_online_state or is_ws != _last_ws_state:
		_last_online_state = is_online
		_last_ws_state = is_ws
		_update_status_bar()


func _input(event: InputEvent) -> void:
	# F3 to toggle edit mode
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_F3:
			_toggle_edit_mode()
			get_viewport().set_input_as_handled()
			return

		if edit_mode_enabled:
			# Ctrl+Z for undo
			if event.ctrl_pressed and event.keycode == KEY_Z:
				_undo()
				get_viewport().set_input_as_handled()
				return

			# Ctrl+Y or Ctrl+Shift+Z for redo
			if event.ctrl_pressed and (event.keycode == KEY_Y or (event.shift_pressed and event.keycode == KEY_Z)):
				_redo()
				get_viewport().set_input_as_handled()
				return

			# Ctrl+D for duplicate
			if event.ctrl_pressed and event.keycode == KEY_D:
				_duplicate_selected()
				get_viewport().set_input_as_handled()
				return

			# Ctrl+S for immediate save (bypass debounce)
			if event.ctrl_pressed and event.keycode == KEY_S:
				_scene_dirty = true
				_on_scene_debounce_timeout()  # Force immediate save
				get_viewport().set_input_as_handled()
				return

			# Check if text input is focused - don't process most hotkeys
			var text_input_focused = _is_text_input_focused()

			match event.keycode:
				KEY_ESCAPE:
					# Check if name edit is active first
					if _cancel_name_edit():
						get_viewport().set_input_as_handled()
					else:
						_exit_edit_mode()
						get_viewport().set_input_as_handled()
				KEY_R:
					if selected_element and not text_input_focused:
						_reset_selected_element()
						get_viewport().set_input_as_handled()
				KEY_H:
					if selected_element and not text_input_focused:
						_hide_selected_element()
						get_viewport().set_input_as_handled()
				KEY_DELETE, KEY_BACKSPACE:
					if not text_input_focused:
						if multi_selected.size() > 1:
							_on_multi_delete_all()
							get_viewport().set_input_as_handled()
						elif selected_element:
							_delete_selected_element()
							get_viewport().set_input_as_handled()
				KEY_BRACKETRIGHT:
					if selected_element:
						if event.shift_pressed:
							_bring_to_front()
						else:
							_move_forward()
						get_viewport().set_input_as_handled()
				KEY_BRACKETLEFT:
					if selected_element:
						if event.shift_pressed:
							_send_to_back()
						else:
							_move_backward()
						get_viewport().set_input_as_handled()
				KEY_PAGEUP:
					if selected_element:
						_move_forward()
						get_viewport().set_input_as_handled()
				KEY_PAGEDOWN:
					if selected_element:
						_move_backward()
						get_viewport().set_input_as_handled()
				KEY_TAB:
					if not text_input_focused:
						_cycle_zoom_filter()
						get_viewport().set_input_as_handled()
				KEY_S:
					if not event.ctrl_pressed and not text_input_focused:  # Ctrl+S is save, plain S is snap
						_toggle_snap()
						_update_snap_toggle_button()
						get_viewport().set_input_as_handled()
				KEY_G:
					if not text_input_focused:
						_toggle_grid()
						_update_grid_toggle_button()
						get_viewport().set_input_as_handled()
				KEY_Q:
					if not text_input_focused:
						_toggle_guides()
						_update_guides_toggle_button()
						get_viewport().set_input_as_handled()
				KEY_L:
					if selected_element and not text_input_focused:
						_toggle_selected_lock()
						get_viewport().set_input_as_handled()
				KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
					# Arrow keys to nudge selected element (only if no text input focused)
					if selected_element and not _is_text_input_focused():
						if not _is_element_locked(selected_element):
							_nudge_selected(event.keycode, event.shift_pressed)
							get_viewport().set_input_as_handled()

	if not edit_mode_enabled:
		return

	if event is InputEventMouseButton:
		# Ctrl+Wheel for zoom
		if event.ctrl_pressed and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_edit_zoom_in(event.position)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_edit_zoom_out(event.position)
				get_viewport().set_input_as_handled()
				return

		# Middle mouse button for panning (always works)
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if not _is_over_ui_panel(event.position):
				if event.pressed:
					is_panning = true
					pan_start_mouse = event.position
					pan_start_offset = pan_offset
				else:
					is_panning = false
				get_viewport().set_input_as_handled()
				return

		# Right-click for context menu
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not _is_over_ui_panel(event.position):
				var clicked = _get_element_at_position(event.position)
				# ALT+Right-click: Select parent node instead
				if clicked and event.alt_pressed:
					var clicked_item = _get_item_for_element(clicked)
					var parent_item = _get_parent_item(clicked_item)
					if not parent_item.is_empty() and parent_item.get("element"):
						clicked = parent_item["element"]
				if clicked:
					_select_element(clicked)
					selected_item = _get_item_for_element(clicked)
					_update_selection_outline()
					_update_properties_panel()
					_show_context_menu(event.position)
				get_viewport().set_input_as_handled()
				return

		if event.button_index == MOUSE_BUTTON_LEFT:
			if _is_over_ui_panel(event.position):
				return

			# Ctrl+Left click for panning (works with Ctrl+scroll zoom)
			if event.ctrl_pressed:
				if event.pressed:
					is_panning = true
					pan_start_mouse = event.position
					pan_start_offset = pan_offset
				else:
					is_panning = false
				get_viewport().set_input_as_handled()
				return

			if event.pressed:
				_handle_mouse_down(event.position)
			else:
				_handle_mouse_up(event.position)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if is_marquee_selecting:
			marquee_current = event.position
			_update_marquee_overlay()
			get_viewport().set_input_as_handled()
			return

		if _is_over_ui_panel(event.position):
			return
		elif is_panning:
			_handle_pan(event.position)
			get_viewport().set_input_as_handled()
		elif is_dragging or is_resizing:
			_handle_drag(event.position)
			get_viewport().set_input_as_handled()


func _is_over_ui_panel(pos: Vector2) -> bool:
	if toolbar and toolbar.visible:
		if Rect2(toolbar.position, toolbar.size).has_point(pos):
			return true

	if asset_library and asset_library.visible:
		if Rect2(asset_library.position, asset_library.size).has_point(pos):
			return true

	if properties_panel and properties_panel.visible:
		if Rect2(properties_panel.position, properties_panel.size).has_point(pos):
			return true

	if status_bar and status_bar.visible:
		if Rect2(status_bar.position, status_bar.size).has_point(pos):
			return true

	return false


func _toggle_edit_mode() -> void:
	if edit_mode_enabled:
		_exit_edit_mode()
	else:
		_enter_edit_mode()


func _enter_edit_mode() -> void:
	edit_mode_enabled = true
	overlay.visible = true

	if zoom_container:
		base_game_scale = zoom_container.scale
		base_game_pivot = zoom_container.pivot_offset
		base_game_position = zoom_container.position

	edit_zoom_level = 1.0
	edit_zoom_offset = Vector2.ZERO
	pan_offset = Vector2.ZERO
	current_zoom_filter = ZOOM_ALL  # Reset zoom filter
	_apply_edit_zoom()

	# Re-resolve elements in case room elements were created after init
	_resolve_editable_elements()
	_backup_original_positions()

	_update_overlay_positions()
	_update_zoom_filter_display()
	_populate_asset_list()
	_update_type_highlights()
	_update_item_labels()
	_clear_selection()

	print("[EditMode] ENABLED - %d elements" % editable_elements.size())
	emit_signal("edit_mode_changed", true)


func _exit_edit_mode() -> void:
	edit_mode_enabled = false
	overlay.visible = false

	if zoom_container:
		zoom_container.scale = base_game_scale
		zoom_container.pivot_offset = base_game_pivot
		zoom_container.position = base_game_position

	edit_zoom_level = 1.0
	edit_zoom_offset = Vector2.ZERO
	pan_offset = Vector2.ZERO

	_clear_selection()
	_export_coordinates()

	print("[EditMode] DISABLED")
	emit_signal("edit_mode_changed", false)


func _select_element(element) -> void:  # Can be Control or Node2D
	selected_element = element
	selected_item = _get_item_for_element(element)
	_update_selection_outline()
	_update_properties_panel()
	_update_status_bar()

	# Always switch to "In Scene" tab and highlight the selected item
	var path = selected_item.get("path", "")
	if not path.is_empty():
		# Expand tree to show selected item FIRST
		_expand_to_path(path)

		# Switch to In Scene tab if not already there
		if library_tab != 1:
			_set_library_tab(1)  # This calls _populate_scene_tree() internally
		else:
			# Already on In Scene tab, just refresh the tree to show selection
			_populate_scene_tree()

		# Scroll to make selected item visible (deferred to allow UI to update)
		call_deferred("_scroll_to_selected_in_tree", path)
	else:
		# Fallback: just update current tab
		if library_tab == 0:
			_populate_asset_list()
		else:
			_populate_scene_tree()


func _clear_selection() -> void:
	selected_element = null
	selected_item = {}
	is_dragging = false
	is_resizing = false
	is_panning = false
	resize_corner = -1
	selection_outline.visible = false
	_update_properties_panel()
	_update_status_bar()
	# Update the appropriate list based on current tab
	if library_tab == 0:
		_populate_asset_list()
	else:
		_populate_scene_tree()


func _hide_selected_element() -> void:
	if not selected_element:
		return

	var path = selected_item.get("path", "")
	_hide_element(path)


func _hide_element(path: String) -> void:
	for item in editable_elements:
		if item["path"] == path:
			var element = item["element"]

			_push_undo_action({
				"type": "hide",
				"path": path,
			})

			element.visible = false
			hidden_elements[path] = true
			print("[EditMode] Hidden: %s" % path)

			if selected_element == element:
				_clear_selection()

			_update_type_highlights()
			_update_item_labels()
			_populate_asset_list()
			_populate_scene_tree()  # Update In Scene tab
			_mark_scene_dirty()
			return


func _show_element(path: String) -> void:
	for item in editable_elements:
		if item["path"] == path:
			var element = item["element"]

			_push_undo_action({
				"type": "show",
				"path": path,
			})

			element.visible = true
			hidden_elements.erase(path)
			print("[EditMode] Shown: %s" % path)

			_update_type_highlights()
			_update_item_labels()
			_populate_asset_list()
			_populate_scene_tree()  # Update In Scene tab
			_mark_scene_dirty()
			return


func _toggle_item_visibility(path: String) -> void:
	if hidden_elements.get(path, false):
		_show_element(path)
	else:
		_hide_element(path)


# Undo/Redo System
func _push_undo_action(action: Dictionary) -> void:
	undo_stack.push_back(action)
	if undo_stack.size() > MAX_UNDO_HISTORY:
		undo_stack.pop_front()
	redo_stack.clear()  # Clear redo on new action
	_update_properties_panel()


func _undo() -> void:
	if undo_stack.is_empty():
		return

	var action = undo_stack.pop_back()
	_apply_undo_action(action)
	redo_stack.push_back(action)
	_update_properties_panel()
	print("[EditMode] Undo: %s" % action.get("type", "unknown"))


func _redo() -> void:
	if redo_stack.is_empty():
		return

	var action = redo_stack.pop_back()
	_apply_redo_action(action)
	undo_stack.push_back(action)
	_update_properties_panel()
	print("[EditMode] Redo: %s" % action.get("type", "unknown"))


func _apply_undo_action(action: Dictionary) -> void:
	var action_type = action.get("type", "")
	var path = action.get("path", "")

	match action_type:
		"move":
			for item in editable_elements:
				if item["path"] == path:
					var element = item["element"]
					var old_offsets = action.get("old_offsets", {})
					if old_offsets.get("is_control", true) and element is Control:
						element.offset_left = old_offsets.get("left", element.offset_left)
						element.offset_right = old_offsets.get("right", element.offset_right)
						element.offset_top = old_offsets.get("top", element.offset_top)
						element.offset_bottom = old_offsets.get("bottom", element.offset_bottom)
					elif element is Node2D:
						element.position = old_offsets.get("position", element.position)
					break

		"multi_move":
			var moves = action.get("moves", [])
			for move_data in moves:
				var move_path = move_data.get("path", "")
				var old_offsets = move_data.get("old_offsets", {})
				for item in editable_elements:
					if item["path"] == move_path:
						var element = item["element"]
						if old_offsets.get("is_control", true) and element is Control:
							element.offset_left = old_offsets.get("left", element.offset_left)
							element.offset_right = old_offsets.get("right", element.offset_right)
							element.offset_top = old_offsets.get("top", element.offset_top)
							element.offset_bottom = old_offsets.get("bottom", element.offset_bottom)
						elif element is Node2D:
							element.position = old_offsets.get("position", element.position)
						break

		"hide":
			for item in editable_elements:
				if item["path"] == path:
					item["element"].visible = true
					hidden_elements.erase(path)
					break

		"show":
			for item in editable_elements:
				if item["path"] == path:
					item["element"].visible = false
					hidden_elements[path] = true
					break

		"create":
			# Undo creation = delete
			for i in range(editable_elements.size()):
				if editable_elements[i]["path"] == path:
					var element = editable_elements[i]["element"]
					if selected_element == element:
						_clear_selection()
					element.queue_free()
					editable_elements.remove_at(i)
					original_positions.erase(path)
					break

		"delete":
			# Undo deletion = recreate
			var saved_item = action.get("item", {})
			var source_path = saved_item.get("source_path", "")
			# Find source element to duplicate
			for item in editable_elements:
				if item["path"] == source_path:
					var source = item["element"]
					var new_element = source.duplicate() as Control
					new_element.name = path
					var parent = source.get_parent()
					if parent:
						parent.add_child(new_element)
						var offsets = action.get("offsets", {})
						new_element.offset_left = offsets.get("left", 0)
						new_element.offset_right = offsets.get("right", 0)
						new_element.offset_top = offsets.get("top", 0)
						new_element.offset_bottom = offsets.get("bottom", 0)

					var restored_item = saved_item.duplicate()
					restored_item["element"] = new_element
					editable_elements.append(restored_item)
					original_positions[path] = action.get("offsets", {}).duplicate()
					break

		"z_order":
			for item in editable_elements:
				if item["path"] == path:
					var element = item["element"]
					var old_z = action.get("old_z_index", 0)
					var old_relative = action.get("old_z_as_relative", true)
					element.z_index = old_z
					element.z_as_relative = old_relative
					break

	_populate_asset_list()
	_update_type_highlights()
	_update_item_labels()
	_update_selection_outline()


func _apply_redo_action(action: Dictionary) -> void:
	var action_type = action.get("type", "")
	var path = action.get("path", "")

	match action_type:
		"move":
			for item in editable_elements:
				if item["path"] == path:
					var element = item["element"]
					var new_offsets = action.get("new_offsets", {})
					if new_offsets.get("is_control", true) and element is Control:
						element.offset_left = new_offsets.get("left", element.offset_left)
						element.offset_right = new_offsets.get("right", element.offset_right)
						element.offset_top = new_offsets.get("top", element.offset_top)
						element.offset_bottom = new_offsets.get("bottom", element.offset_bottom)
					elif element is Node2D:
						element.position = new_offsets.get("position", element.position)
					break

		"multi_move":
			var moves = action.get("moves", [])
			for move_data in moves:
				var move_path = move_data.get("path", "")
				var new_offsets = move_data.get("new_offsets", {})
				for item in editable_elements:
					if item["path"] == move_path:
						var element = item["element"]
						if new_offsets.get("is_control", true) and element is Control:
							element.offset_left = new_offsets.get("left", element.offset_left)
							element.offset_right = new_offsets.get("right", element.offset_right)
							element.offset_top = new_offsets.get("top", element.offset_top)
							element.offset_bottom = new_offsets.get("bottom", element.offset_bottom)
						elif element is Node2D:
							element.position = new_offsets.get("position", element.position)
						break

		"hide":
			for item in editable_elements:
				if item["path"] == path:
					item["element"].visible = false
					hidden_elements[path] = true
					break

		"show":
			for item in editable_elements:
				if item["path"] == path:
					item["element"].visible = true
					hidden_elements.erase(path)
					break

		"create":
			# Redo creation = duplicate again
			var saved_item = action.get("item", {})
			var source_path = saved_item.get("source_path", "")
			for item in editable_elements:
				if item["path"] == source_path:
					var source = item["element"]
					var new_element = source.duplicate() as Control
					new_element.name = path
					var parent = source.get_parent()
					if parent:
						parent.add_child(new_element)

					var restored_item = saved_item.duplicate()
					restored_item["element"] = new_element
					editable_elements.append(restored_item)
					break

		"delete":
			# Redo deletion = delete again
			for i in range(editable_elements.size()):
				if editable_elements[i]["path"] == path:
					var element = editable_elements[i]["element"]
					if selected_element == element:
						_clear_selection()
					element.queue_free()
					editable_elements.remove_at(i)
					original_positions.erase(path)
					break

		"z_order":
			for item in editable_elements:
				if item["path"] == path:
					var element = item["element"]
					var new_z = action.get("new_z_index", 0)
					element.z_as_relative = false
					element.z_index = new_z
					break

	_populate_asset_list()
	_update_type_highlights()
	_update_item_labels()
	_update_selection_outline()


func _edit_zoom_in(mouse_pos: Vector2) -> void:
	_zoom_towards_point(mouse_pos, EDIT_ZOOM_STEP)


func _edit_zoom_out(mouse_pos: Vector2) -> void:
	_zoom_towards_point(mouse_pos, -EDIT_ZOOM_STEP)


func _zoom_towards_point(mouse_pos: Vector2, zoom_delta: float) -> void:
	var old_zoom = edit_zoom_level
	var new_zoom = clamp(edit_zoom_level + zoom_delta, EDIT_ZOOM_MIN, EDIT_ZOOM_MAX)

	if abs(new_zoom - old_zoom) < 0.001:
		return  # No change

	# The zoom container uses a pivot point for scaling.
	# When we zoom, content around the pivot stays still, but content away from pivot moves.
	# To zoom towards mouse, we need to adjust the pan so the point under mouse stays there.

	# Current total offset (pan_offset is our main translation)
	var current_scale = base_game_scale.x * old_zoom
	var new_scale = base_game_scale.x * new_zoom

	# The pivot point in screen coordinates
	var pivot_screen = base_game_position + pan_offset + base_game_pivot * current_scale

	# Vector from pivot to mouse (in screen space)
	var mouse_from_pivot = mouse_pos - pivot_screen

	# After zoom, this vector would scale by (new_scale / current_scale)
	# To keep mouse position constant, we need to adjust pan_offset
	var scale_ratio = new_scale / current_scale
	var adjustment = mouse_from_pivot * (1.0 - scale_ratio)

	# Apply zoom and pan adjustment
	edit_zoom_level = new_zoom
	pan_offset = pan_offset + adjustment

	_apply_edit_zoom()
	_refresh_all_highlights()


func _handle_pan(mouse_pos: Vector2) -> void:
	var delta = mouse_pos - pan_start_mouse
	# Pan in screen space - 1:1 with mouse movement regardless of zoom
	pan_offset = pan_start_offset + delta
	_apply_edit_zoom()
	_refresh_all_highlights()


func _apply_edit_zoom() -> void:
	if not zoom_container:
		return

	zoom_container.scale = base_game_scale * edit_zoom_level
	zoom_container.pivot_offset = base_game_pivot
	# Apply pan offset for translation
	zoom_container.position = base_game_position + pan_offset

	# Update zoom label in status bar
	var hbox = status_bar.get_child(0) if status_bar.get_child_count() > 0 else null
	if hbox:
		var zoom_box = hbox.get_child(0) if hbox.get_child_count() > 0 else null
		if zoom_box:
			var zoom_label = zoom_box.get_node_or_null("ZoomLabel") as Label
			if zoom_label:
				zoom_label.text = "%d%%" % int(edit_zoom_level * 100)


func _refresh_all_highlights() -> void:
	_update_type_highlights()
	_update_item_labels()
	_update_selection_outline()
	_update_hover_outline()
	_update_multi_selection_outline()


func _update_type_highlights() -> void:
	# Disabled - too visually busy
	# Now we only show hover outline for cleaner UI
	for child in type_highlights.get_children():
		child.queue_free()
	type_highlights.visible = false


func _update_item_labels() -> void:
	# Disabled - labels now only shown on hover
	for child in item_labels.get_children():
		child.queue_free()
	item_labels.visible = false


func _is_rect_visible(rect: Rect2, viewport_rect: Rect2) -> bool:
	return viewport_rect.grow(50).intersects(rect)


func _handle_mouse_down(mouse_pos: Vector2) -> void:
	var shift_held = Input.is_key_pressed(KEY_SHIFT)
	var alt_held = Input.is_key_pressed(KEY_ALT)

	# Check if clicking on a resize handle of selected element (only for Control nodes)
	# Don't allow resize if element is locked
	if selected_element and not shift_held and selected_element is Control and not _is_element_locked(selected_element):
		var corner = _get_corner_at_position(mouse_pos)
		if corner >= 0:
			is_resizing = true
			resize_corner = corner
			drag_start_mouse = mouse_pos
			drag_start_size = selected_element.size
			drag_start_offsets = _get_element_drag_state(selected_element)
			return

	var clicked_element = _get_element_at_position(mouse_pos)
	print("[EditMode] Mouse down at %s, clicked_element: %s" % [mouse_pos, clicked_element])

	# ALT+Click: Select parent node instead
	if clicked_element and alt_held:
		var clicked_item = _get_item_for_element(clicked_element)
		var parent_item = _get_parent_item(clicked_item)
		if not parent_item.is_empty() and parent_item.get("element"):
			clicked_element = parent_item["element"]
			print("[EditMode] ALT+Click: Selected parent %s" % parent_item.get("path", ""))

	var ctrl_held = Input.is_key_pressed(KEY_CTRL)

	# Ctrl+Shift+drag starts marquee selection even over elements
	if shift_held and ctrl_held:
		print("[EditMode] Ctrl+Shift+click - starting marquee selection")
		is_marquee_selecting = true
		marquee_start = mouse_pos
		marquee_current = mouse_pos
		_create_marquee_overlay()
		return

	if clicked_element:
		if shift_held:
			# Shift+Click: Toggle multi-selection (add or remove)
			if clicked_element in multi_selected:
				# Already selected - REMOVE from multi-selection
				_remove_from_multi_selection(clicked_element)
				# Update active selection
				if clicked_element == selected_element:
					if multi_selected.size() > 0:
						selected_element = multi_selected[0]
						selected_item = _get_item_for_element(selected_element)
					else:
						selected_element = null
						selected_item = {}
				print("[EditMode] Removed from multi-selection, count: %d" % multi_selected.size())
			else:
				# Not selected - ADD to multi-selection
				if selected_element and selected_element not in multi_selected:
					_add_to_multi_selection(selected_element)
				_add_to_multi_selection(clicked_element)
				selected_element = clicked_element
				selected_item = _get_item_for_element(clicked_element)
				print("[EditMode] Added to multi-selection, count: %d" % multi_selected.size())

			_update_selection_outline()
			_update_properties_panel()
			return

		# Normal click - check if clicking on a multi-selected element
		if clicked_element in multi_selected and multi_selected.size() > 1:
			# Clicking on a multi-selected element - start multi-drag
			selected_element = clicked_element
			selected_item = _get_item_for_element(clicked_element)
			if not _is_element_locked(clicked_element):
				is_dragging = true
				drag_start_mouse = mouse_pos
				drag_start_offsets = _get_element_drag_state(selected_element)
				drag_start_size = selected_element.size if selected_element is Control else Vector2(32, 32)
				# Store offsets for ALL multi-selected elements
				multi_drag_start_offsets.clear()
				for elem in multi_selected:
					multi_drag_start_offsets.append({
						"element": elem,
						"offsets": _get_element_drag_state(elem)
					})
		else:
			# Normal click - clear multi-selection and select single element
			_clear_multi_selection()
			_select_element(clicked_element)  # This handles tab switching, tree expansion, scrolling

			# Only start dragging if element is not locked
			if not _is_element_locked(clicked_element):
				is_dragging = true
				drag_start_mouse = mouse_pos
				drag_start_offsets = _get_element_drag_state(selected_element)
				drag_start_size = selected_element.size if selected_element is Control else Vector2(32, 32)
				multi_drag_start_offsets.clear()  # Clear multi-drag offsets for single drag
	else:
		# Clicked on empty space
		print("[EditMode] Clicked empty space, shift_held: %s" % shift_held)
		if shift_held:
			# Start marquee selection
			print("[EditMode] Starting marquee selection at %s" % mouse_pos)
			is_marquee_selecting = true
			marquee_start = mouse_pos
			marquee_current = mouse_pos
			_create_marquee_overlay()
		else:
			_clear_multi_selection()
			# Start panning WITHOUT clearing selection
			# Selection is preserved so user can still see properties while panning
			is_panning = true
			pan_start_mouse = mouse_pos
			pan_start_offset = pan_offset


func _get_corner_at_position(screen_pos: Vector2) -> int:
	if not selected_element:
		return -1

	var rect = _get_element_screen_rect(selected_element)
	var handle_size = 16

	var corners = [
		Rect2(rect.position - Vector2(handle_size/2, handle_size/2), Vector2(handle_size, handle_size)),
		Rect2(Vector2(rect.position.x + rect.size.x - handle_size/2, rect.position.y - handle_size/2), Vector2(handle_size, handle_size)),
		Rect2(Vector2(rect.position.x - handle_size/2, rect.position.y + rect.size.y - handle_size/2), Vector2(handle_size, handle_size)),
		Rect2(rect.position + rect.size - Vector2(handle_size/2, handle_size/2), Vector2(handle_size, handle_size)),
	]

	for i in range(4):
		if corners[i].has_point(screen_pos):
			return i

	return -1


func _handle_mouse_up(_mouse_pos: Vector2) -> void:
	if (is_dragging or is_resizing) and selected_element:
		var path = selected_item.get("path", "")

		# Check if position actually changed
		var moved = _element_position_changed(selected_element, drag_start_offsets)

		if moved:
			# Check if this was a multi-drag
			if multi_drag_start_offsets.size() > 1:
				# Build list of all elements for parent checking
				var moving_elements: Array = []
				for drag_data in multi_drag_start_offsets:
					moving_elements.append(drag_data["element"])

				# Record multi-move for undo (skip children whose parents also moved)
				var multi_moves: Array[Dictionary] = []
				for drag_data in multi_drag_start_offsets:
					var elem = drag_data["element"]
					var offsets = drag_data["offsets"]
					# Skip elements whose parent is also being moved
					if _has_parent_in_list(elem, moving_elements):
						continue
					var elem_item = _get_item_for_element(elem)
					var elem_path = elem_item.get("path", "")
					multi_moves.append({
						"path": elem_path,
						"old_offsets": offsets.duplicate(),
						"new_offsets": _get_element_drag_state(elem),
					})
					# Update modified_elements for each
					modified_elements[elem_path] = _get_element_drag_state(elem)
				_push_undo_action({
					"type": "multi_move",
					"moves": multi_moves,
				})
			else:
				# Single element move
				_push_undo_action({
					"type": "move",
					"path": path,
					"old_offsets": drag_start_offsets.duplicate(),
					"new_offsets": _get_element_drag_state(selected_element),
				})
				modified_elements[path] = _get_element_drag_state(selected_element)
			# Trigger auto-save for drag changes
			_mark_scene_dirty()

	# Handle marquee selection completion
	if is_marquee_selecting:
		_complete_marquee_selection()
		is_marquee_selecting = false
		_remove_marquee_overlay()

	is_dragging = false
	is_resizing = false
	is_panning = false
	resize_corner = -1
	multi_drag_start_offsets.clear()
	_clear_smart_guides()
	# Update multi-selection outlines to final positions
	if multi_selected.size() > 0:
		_update_multi_selection_outline()


func _handle_drag(mouse_pos: Vector2) -> void:
	if not selected_element:
		return

	var screen_delta = mouse_pos - drag_start_mouse
	var zoom_scale = zoom_container.scale if zoom_container else Vector2.ONE
	var scene_delta = screen_delta / zoom_scale

	if is_resizing:
		_handle_resize(scene_delta)
	elif is_dragging:
		# Get starting position based on element type
		var start_pos: Vector2
		if drag_start_offsets.get("is_control", true):
			start_pos = Vector2(drag_start_offsets.get("left", 0), drag_start_offsets.get("top", 0))
		else:
			start_pos = drag_start_offsets.get("position", Vector2.ZERO)

		var new_pos = start_pos + scene_delta

		# Apply snapping if enabled (only for Control elements currently)
		if snap_enabled and selected_element is Control:
			var snap_result = _calculate_snap(new_pos.x, new_pos.y)
			new_pos.x = snap_result["x"]
			new_pos.y = snap_result["y"]
			_draw_smart_guides(snap_result["guides"])
		else:
			_clear_smart_guides()

		# Calculate final delta
		var final_delta = new_pos - start_pos

		# Apply the position change to selected element
		_apply_drag_delta(selected_element, drag_start_offsets, final_delta)

		# Also move all other multi-selected elements by the same delta
		if multi_drag_start_offsets.size() > 1:
			# Build a set of all elements being moved for parent checking
			var moving_elements: Array = []
			for drag_data in multi_drag_start_offsets:
				moving_elements.append(drag_data["element"])

			for drag_data in multi_drag_start_offsets:
				var elem = drag_data["element"]
				var offsets = drag_data["offsets"]
				# Skip the main selected element (already moved above)
				if elem == selected_element:
					continue
				# Skip elements whose parent is also being moved (they move automatically with parent)
				if _has_parent_in_list(elem, moving_elements):
					continue
				# Apply same delta to this element
				_apply_drag_delta(elem, offsets, final_delta)
			# Update multi-selection outlines to follow the elements
			_update_multi_selection_outline()


func _handle_resize(scene_delta: Vector2) -> void:
	# Resizing only works for Control elements
	if not selected_element or resize_corner < 0 or not selected_element is Control:
		return

	match resize_corner:
		0:
			selected_element.offset_left = drag_start_offsets.get("left", 0) + scene_delta.x
			selected_element.offset_top = drag_start_offsets.get("top", 0) + scene_delta.y
		1:
			selected_element.offset_right = drag_start_offsets.get("right", 0) + scene_delta.x
			selected_element.offset_top = drag_start_offsets.get("top", 0) + scene_delta.y
		2:
			selected_element.offset_left = drag_start_offsets.get("left", 0) + scene_delta.x
			selected_element.offset_bottom = drag_start_offsets.get("bottom", 0) + scene_delta.y
		3:
			selected_element.offset_right = drag_start_offsets.get("right", 0) + scene_delta.x
			selected_element.offset_bottom = drag_start_offsets.get("bottom", 0) + scene_delta.y


func _is_mouse_over_ui_panel(screen_pos: Vector2) -> bool:
	# Check if mouse position is over any UI panel
	var panels = [properties_panel, asset_library, status_bar, toolbar]
	for panel in panels:
		if panel and panel.visible:
			var panel_rect = Rect2(panel.position, panel.size)
			if panel_rect.has_point(screen_pos):
				return true
	return false


func _get_element_at_position(screen_pos: Vector2):  # Returns Control or Node2D or null
	# Don't detect elements when mouse is over UI panels
	if _is_mouse_over_ui_panel(screen_pos):
		return null

	var candidates: Array[Dictionary] = []

	for item in editable_elements:
		var element = item["element"]
		var path = item["path"]

		if not element or not element.is_inside_tree() or not element.visible:
			continue
		if hidden_elements.get(path, false):
			continue
		# Filter by zoom level
		if not _item_visible_at_zoom(item, current_zoom_filter):
			continue

		var elem_rect = _get_element_screen_rect(element)

		if elem_rect.has_point(screen_pos):
			candidates.append({
				"element": element,
				"rect": elem_rect,
				"area": elem_rect.size.x * elem_rect.size.y,
				"item": item,
			})

	if candidates.is_empty():
		return null

	candidates.sort_custom(func(a, b): return a["area"] < b["area"])
	return candidates[0]["element"]


func _get_item_for_element(element) -> Dictionary:  # Can be Control or Node2D
	for item in editable_elements:
		if item["element"] == element:
			return item
	return {}


func _has_parent_in_list(element, element_list: Array) -> bool:
	"""Check if any of the element's scene tree ancestors are in the given list"""
	if not element or not is_instance_valid(element):
		return false
	var parent = element.get_parent()
	while parent:
		if parent in element_list:
			return true
		parent = parent.get_parent()
	return false


func _get_parent_item(item: Dictionary) -> Dictionary:
	"""Get the parent item for a given item based on path hierarchy"""
	var path = item.get("path", "")
	if path.is_empty():
		return {}

	# Get parent path by removing the last component
	var last_slash = path.rfind("/")
	if last_slash < 0:
		return {}  # No parent (top-level item)

	var parent_path = path.substr(0, last_slash)

	# Find the item with this parent path
	for other_item in editable_elements:
		if other_item.get("path", "") == parent_path:
			return other_item

	return {}


func _get_element_screen_rect(element) -> Rect2:
	if not element:
		return Rect2()

	var transform = element.get_global_transform()
	var local_size: Vector2

	# Handle different node types
	if element is Control:
		local_size = element.size
	elif element is Sprite2D:
		var texture = element.texture
		if texture:
			local_size = texture.get_size()
		else:
			local_size = Vector2(32, 32)
	elif element is PointLight2D or element is DirectionalLight2D or element is Light2D:
		# Lights don't have a visual size, use a default based on texture_scale if available
		var range_size = 64.0
		if element.has_method("get") and element.get("texture_scale"):
			range_size = element.texture_scale * 32
		local_size = Vector2(range_size, range_size)
	elif element is CanvasModulate:
		# CanvasModulate affects the whole canvas, show a small icon
		local_size = Vector2(48, 48)
	elif element is LightOccluder2D:
		# LightOccluder2D - try to get occluder polygon bounds or use default
		local_size = Vector2(64, 64)
	elif element is Node2D:
		# Generic Node2D - use default size
		local_size = Vector2(64, 64)
	else:
		local_size = Vector2(32, 32)

	# For centered elements (Sprite2D, lights), offset by half size
	var offset = Vector2.ZERO
	if element is Sprite2D:
		if element.centered:
			offset = -local_size / 2
	elif (element is PointLight2D or element is DirectionalLight2D or
		element is Light2D or element is CanvasModulate or element is LightOccluder2D):
		offset = -local_size / 2

	var corners = [
		transform * (offset + Vector2.ZERO),
		transform * (offset + Vector2(local_size.x, 0)),
		transform * (offset + Vector2(0, local_size.y)),
		transform * (offset + local_size),
	]

	var min_pos = corners[0]
	var max_pos = corners[0]
	for corner in corners:
		min_pos.x = min(min_pos.x, corner.x)
		min_pos.y = min(min_pos.y, corner.y)
		max_pos.x = max(max_pos.x, corner.x)
		max_pos.y = max(max_pos.y, corner.y)

	return Rect2(min_pos, max_pos - min_pos)


func _update_hover_outline() -> void:
	for child in hover_outline.get_children():
		child.queue_free()

	# Don't show hover while panning or dragging
	if is_panning or is_dragging:
		hover_outline.visible = false
		return

	if not hovered_element or hovered_element == selected_element:
		hover_outline.visible = false
		return

	hover_outline.visible = true
	var rect = _get_element_screen_rect(hovered_element)

	var item = _get_item_for_element(hovered_element)
	var item_type = item.get("type", ItemType.OBJECT)
	var path = item.get("path", hovered_element.name)
	var color = TYPE_COLORS.get(item_type, Color.YELLOW)
	var bright_color = Color(min(color.r + 0.3, 1.0), min(color.g + 0.3, 1.0), min(color.b + 0.3, 1.0), 1.0)

	# Draw glow effect (multiple outlines with decreasing opacity)
	for i in range(3):
		var glow_color = Color(bright_color.r, bright_color.g, bright_color.b, 0.3 - i * 0.1)
		_draw_outline(hover_outline, rect.grow(i * 2), glow_color, 2)

	# Draw main outline
	_draw_outline(hover_outline, rect, bright_color, 2)

	# Create hover label/tooltip
	var label_panel = Panel.new()
	var label_style = StyleBoxFlat.new()
	label_style.bg_color = Color(0.0, 0.0, 0.0, 0.85)
	label_style.border_color = color
	label_style.set_border_width_all(1)
	label_style.set_corner_radius_all(3)
	label_style.set_content_margin_all(4)
	label_panel.add_theme_stylebox_override("panel", label_style)

	var label_hbox = HBoxContainer.new()
	label_hbox.add_theme_constant_override("separation", 6)
	label_panel.add_child(label_hbox)

	# Type indicator dot
	var type_dot = ColorRect.new()
	type_dot.custom_minimum_size = Vector2(8, 8)
	type_dot.color = color
	var dot_center = CenterContainer.new()
	dot_center.add_child(type_dot)
	label_hbox.add_child(dot_center)

	# Item name (use custom name if available)
	var name_label = Label.new()
	var display_name = _get_display_name(item)
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", bright_color)
	label_hbox.add_child(name_label)

	# Type badge
	var type_label = Label.new()
	type_label.text = TYPE_NAMES.get(item_type, "Object")
	type_label.add_theme_font_size_override("font_size", 9)
	type_label.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.7))
	label_hbox.add_child(type_label)

	# Position the label above the element
	label_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	label_hbox.offset_left = 6
	label_hbox.offset_right = -6
	label_hbox.offset_top = 2
	label_hbox.offset_bottom = -2

	# Calculate label size and position
	var label_width = display_name.length() * 7 + TYPE_NAMES.get(item_type, "Object").length() * 6 + 50
	label_panel.size = Vector2(label_width, 24)

	# Position above element, centered
	var label_x = rect.position.x + rect.size.x / 2 - label_width / 2
	var label_y = rect.position.y - 30

	# Keep on screen
	var viewport_size = get_viewport().get_visible_rect().size
	label_x = clamp(label_x, 5, viewport_size.x - label_width - 5)
	if label_y < 5:
		label_y = rect.position.y + rect.size.y + 6  # Show below if no room above

	label_panel.position = Vector2(label_x, label_y)
	label_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	hover_outline.add_child(label_panel)


func _update_selection_outline() -> void:
	for child in selection_outline.get_children():
		child.queue_free()

	if not selected_element:
		selection_outline.visible = false
		return

	selection_outline.visible = true
	var rect = _get_element_screen_rect(selected_element)
	var is_locked = _is_element_locked(selected_element)

	# Check if this is a light element - draw special indicator
	var is_light = (selected_element is PointLight2D or selected_element is DirectionalLight2D or
		selected_element is Light2D or selected_element is CanvasModulate or selected_element is LightOccluder2D)

	# Use red/orange color for locked elements
	var outline_color = Color(1.0, 0.3, 0.2, 1.0) if is_locked else Color(0.0, 1.0, 0.4, 1.0)
	var light_color = Color(1.0, 0.5, 0.3, 1.0) if is_locked else TYPE_COLORS[ItemType.LIGHT]

	if is_light:
		# Draw a special crosshair/target indicator for lights
		_draw_light_indicator(selection_outline, rect, light_color)
	else:
		_draw_outline(selection_outline, rect, outline_color, 3)

	var handle_size = 10
	var handle_color = Color(1.0, 0.5, 0.0, 1.0) if is_locked else (Color(1.0, 1.0, 0.0, 1.0) if not is_light else TYPE_COLORS[ItemType.LIGHT])

	# Don't show resize handles for locked elements
	if not is_locked:
		var corners = [
			rect.position,
			Vector2(rect.position.x + rect.size.x - handle_size, rect.position.y),
			Vector2(rect.position.x, rect.position.y + rect.size.y - handle_size),
			rect.position + rect.size - Vector2(handle_size, handle_size),
		]

		for corner_pos in corners:
			var handle = ColorRect.new()
			handle.color = handle_color
			handle.position = corner_pos
			handle.size = Vector2(handle_size, handle_size)
			selection_outline.add_child(handle)

	# Draw lock indicator if locked
	if is_locked:
		_draw_lock_indicator(selection_outline, rect)


func _draw_eye_icon(container: Control, is_open: bool, color: Color) -> void:
	var size = container.size
	var cx = size.x / 2
	var cy = size.y / 2

	if is_open:
		# Draw open eye - almond shape with pupil
		var eye_points: PackedVector2Array = []
		for i in range(20):
			var t = float(i) / 19.0
			var angle = t * PI
			var x = cx + cos(angle) * 7
			var y_offset = sin(angle) * 4
			eye_points.append(Vector2(x, cy - y_offset))
		for i in range(20):
			var t = float(i) / 19.0
			var angle = t * PI
			var x = cx - cos(angle) * 7
			var y_offset = sin(angle) * 4
			eye_points.append(Vector2(x, cy + y_offset))
		container.draw_polyline(eye_points, color, 1.5)
		# Draw pupil
		container.draw_circle(Vector2(cx, cy), 2.5, color)
	else:
		# Draw closed eye - horizontal line with slight curve
		var closed_points: PackedVector2Array = []
		for i in range(10):
			var t = float(i) / 9.0
			var x = cx - 7 + t * 14
			var y = cy + sin(t * PI) * 2
			closed_points.append(Vector2(x, y))
		container.draw_polyline(closed_points, color, 1.5)
		# Draw eyelashes (short lines down)
		container.draw_line(Vector2(cx - 5, cy + 1), Vector2(cx - 6, cy + 4), color, 1.0)
		container.draw_line(Vector2(cx, cy + 2), Vector2(cx, cy + 5), color, 1.0)
		container.draw_line(Vector2(cx + 5, cy + 1), Vector2(cx + 6, cy + 4), color, 1.0)


func _draw_outline(container: Control, rect: Rect2, color: Color, width: int) -> void:
	var top = ColorRect.new()
	top.color = color
	top.position = Vector2(rect.position.x, rect.position.y)
	top.size = Vector2(rect.size.x, width)
	container.add_child(top)

	var bottom = ColorRect.new()
	bottom.color = color
	bottom.position = Vector2(rect.position.x, rect.position.y + rect.size.y - width)
	bottom.size = Vector2(rect.size.x, width)
	container.add_child(bottom)

	var left = ColorRect.new()
	left.color = color
	left.position = Vector2(rect.position.x, rect.position.y + width)
	left.size = Vector2(width, rect.size.y - width * 2)
	container.add_child(left)

	var right = ColorRect.new()
	right.color = color
	right.position = Vector2(rect.position.x + rect.size.x - width, rect.position.y + width)
	right.size = Vector2(width, rect.size.y - width * 2)
	container.add_child(right)


func _draw_lock_indicator(container: Control, rect: Rect2) -> void:
	# Draw a lock icon in the top-right corner
	var icon_size = 20
	var padding = 4
	var icon_pos = Vector2(rect.end.x - icon_size - padding, rect.position.y + padding)

	var indicator = Control.new()
	indicator.set_anchors_preset(Control.PRESET_FULL_RECT)
	indicator.draw.connect(func():
		var lock_color = Color(1.0, 0.4, 0.2, 1.0)
		var bg_color = Color(0.1, 0.1, 0.1, 0.8)

		# Background circle
		var center = icon_pos + Vector2(icon_size / 2, icon_size / 2)
		indicator.draw_circle(center, icon_size / 2 + 2, bg_color)

		# Draw lock shape
		var body_w = icon_size * 0.6
		var body_h = icon_size * 0.45
		var body_x = center.x - body_w / 2
		var body_y = center.y

		# Lock body (rectangle)
		indicator.draw_rect(Rect2(body_x, body_y, body_w, body_h), lock_color)

		# Lock shackle (arc)
		var shackle_radius = body_w * 0.35
		var shackle_center = Vector2(center.x, body_y)
		var points: PackedVector2Array = []
		for i in range(13):
			var angle = PI + (i / 12.0) * PI
			points.append(shackle_center + Vector2(cos(angle), sin(angle)) * shackle_radius)
		indicator.draw_polyline(points, lock_color, 3.0)
	)
	container.add_child(indicator)


func _draw_light_indicator(container: Control, rect: Rect2, color: Color) -> void:
	"""Draw a special crosshair/target indicator for light elements"""
	var center = rect.position + rect.size / 2
	var radius = max(rect.size.x, rect.size.y) / 2 + 8

	# Create a custom drawing control for the light indicator
	var indicator = Control.new()
	indicator.set_anchors_preset(Control.PRESET_FULL_RECT)
	indicator.draw.connect(func():
		# Outer circle
		indicator.draw_arc(center, radius, 0, TAU, 32, color, 2.0)
		# Inner circle
		indicator.draw_arc(center, radius * 0.5, 0, TAU, 24, color, 1.5)
		# Crosshair lines
		var line_len = radius * 0.3
		indicator.draw_line(center + Vector2(-radius - line_len, 0), center + Vector2(-radius + 4, 0), color, 2.0)
		indicator.draw_line(center + Vector2(radius - 4, 0), center + Vector2(radius + line_len, 0), color, 2.0)
		indicator.draw_line(center + Vector2(0, -radius - line_len), center + Vector2(0, -radius + 4), color, 2.0)
		indicator.draw_line(center + Vector2(0, radius - 4), center + Vector2(0, radius + line_len), color, 2.0)
		# Center dot
		indicator.draw_circle(center, 4, color)
		# Glow effect - outer rings with decreasing opacity
		for i in range(3):
			var glow_color = Color(color.r, color.g, color.b, 0.2 - i * 0.06)
			indicator.draw_arc(center, radius + 4 + i * 3, 0, TAU, 32, glow_color, 2.0)
	)
	container.add_child(indicator)
	indicator.queue_redraw()


func _reset_selected_element() -> void:
	if not selected_element:
		return

	var path = selected_item.get("path", "")
	var orig = original_positions.get(path)

	if orig:
		# Record for undo before reset
		_push_undo_action({
			"type": "move",
			"path": path,
			"old_offsets": _get_element_drag_state(selected_element),
			"new_offsets": orig.duplicate(),
		})

		# Restore position based on element type
		if orig.get("is_control", true) and selected_element is Control:
			selected_element.offset_left = orig["left"]
			selected_element.offset_right = orig["right"]
			selected_element.offset_top = orig["top"]
			selected_element.offset_bottom = orig["bottom"]
		elif selected_element is Node2D:
			selected_element.position = orig.get("position", selected_element.position)

		selected_element.z_index = orig.get("z_index", 0)
		selected_element.z_as_relative = orig.get("z_as_relative", true)

		var parent = selected_element.get_parent()
		if parent and orig.has("child_index"):
			var target_index = orig["child_index"]
			if target_index < parent.get_child_count():
				parent.move_child(selected_element, target_index)

		modified_elements.erase(path)

		_update_selection_outline()
		_update_properties_panel()
		_update_type_highlights()
		_update_item_labels()
		print("[EditMode] Reset: %s" % path)


func _move_forward() -> void:
	if not selected_element:
		return

	var old_z = selected_element.z_index
	var new_z = old_z + 1

	_push_undo_action({
		"type": "z_order",
		"path": selected_item.get("path", ""),
		"old_z_index": old_z,
		"new_z_index": new_z,
		"old_z_as_relative": selected_element.z_as_relative,
	})

	# Use global z-index for cross-parent ordering
	selected_element.z_as_relative = false
	selected_element.z_index = new_z
	_record_z_change()
	print("[EditMode] Z-index: %d -> %d" % [old_z, new_z])


func _move_backward() -> void:
	if not selected_element:
		return

	var old_z = selected_element.z_index
	var new_z = old_z - 1

	_push_undo_action({
		"type": "z_order",
		"path": selected_item.get("path", ""),
		"old_z_index": old_z,
		"new_z_index": new_z,
		"old_z_as_relative": selected_element.z_as_relative,
	})

	# Use global z-index for cross-parent ordering
	selected_element.z_as_relative = false
	selected_element.z_index = new_z
	_record_z_change()
	print("[EditMode] Z-index: %d -> %d" % [old_z, new_z])


func _bring_to_front() -> void:
	if not selected_element:
		return

	# Find the highest z_index among all editable elements
	var max_z = 0
	for item in editable_elements:
		var element = item["element"]
		if element and element != selected_element:
			max_z = max(max_z, element.z_index)

	var old_z = selected_element.z_index
	var new_z = max_z + 10  # Jump above all others

	_push_undo_action({
		"type": "z_order",
		"path": selected_item.get("path", ""),
		"old_z_index": old_z,
		"new_z_index": new_z,
		"old_z_as_relative": selected_element.z_as_relative,
	})

	selected_element.z_as_relative = false
	selected_element.z_index = new_z
	_record_z_change()
	print("[EditMode] Bring to front: z_index = %d" % new_z)


func _send_to_back() -> void:
	if not selected_element:
		return

	# Find the lowest z_index among all editable elements
	var min_z = 0
	for item in editable_elements:
		var element = item["element"]
		if element and element != selected_element:
			min_z = min(min_z, element.z_index)

	var old_z = selected_element.z_index
	var new_z = min_z - 10  # Jump below all others

	_push_undo_action({
		"type": "z_order",
		"path": selected_item.get("path", ""),
		"old_z_index": old_z,
		"new_z_index": new_z,
		"old_z_as_relative": selected_element.z_as_relative,
	})

	selected_element.z_as_relative = false
	selected_element.z_index = new_z
	_record_z_change()
	print("[EditMode] Send to back: z_index = %d" % new_z)


func _record_z_change() -> void:
	if not selected_element:
		return

	var path = selected_item.get("path", "")

	if not modified_elements.has(path):
		modified_elements[path] = {
			"left": selected_element.offset_left,
			"right": selected_element.offset_right,
			"top": selected_element.offset_top,
			"bottom": selected_element.offset_bottom,
		}

	modified_elements[path]["z_index"] = selected_element.z_index
	modified_elements[path]["z_as_relative"] = selected_element.z_as_relative
	modified_elements[path]["child_index"] = selected_element.get_index()

	_update_properties_panel()
	_update_type_highlights()
	_mark_scene_dirty()


func _export_coordinates() -> void:
	if modified_elements.is_empty() and hidden_elements.is_empty():
		print("[EditMode] No changes to export.")
		return

	print("")
	print("=" .repeat(60))
	print("[EditMode] SCENE CHANGES - Copy to main.tscn")
	print("=" .repeat(60))

	if not modified_elements.is_empty():
		print("\nMODIFIED ELEMENTS:")
		for path in modified_elements:
			var data = modified_elements[path]
			var node_name = path.get_file()
			print("\n# %s" % path)
			print("[node name=\"%s\" ...]" % node_name)
			print("offset_left = %.1f" % data["left"])
			print("offset_right = %.1f" % data["right"])
			print("offset_top = %.1f" % data["top"])
			print("offset_bottom = %.1f" % data["bottom"])
			if data.has("z_index"):
				print("z_index = %d" % data["z_index"])

	if not hidden_elements.is_empty():
		print("\nHIDDEN ELEMENTS:")
		for path in hidden_elements.keys():
			print("  - %s" % path)

	# List copies
	var copies = []
	for item in editable_elements:
		if item.get("is_copy", false):
			copies.append(item["path"])

	if not copies.is_empty():
		print("\nCOPIED ELEMENTS:")
		for path in copies:
			print("  + %s" % path)

	print("")
	print("=" .repeat(60))
	print("")


func get_scene_config() -> Dictionary:
	var config = {
		"version": 2,  # Bumped for expanded property support
		"timestamp": Time.get_unix_time_from_system(),
		"elements": {},
		"hidden": hidden_elements.keys(),
		"locked": locked_elements.keys(),  # Include lock state
		"copies": [],
		"custom_names": custom_names.duplicate(),  # Include custom names
	}

	# Collect all copy paths for filtering child copies
	var copy_paths: Array[String] = []
	for item in editable_elements:
		if item.get("is_copy", false):
			copy_paths.append(item["path"])

	for item in editable_elements:
		var element = item["element"]
		var path = item["path"]

		if not element:
			continue

		var element_data = {}

		# Handle Control vs Node2D
		if element is Control:
			element_data["is_control"] = true
			element_data["offset_left"] = element.offset_left
			element_data["offset_right"] = element.offset_right
			element_data["offset_top"] = element.offset_top
			element_data["offset_bottom"] = element.offset_bottom
		elif element is Node2D:
			element_data["is_control"] = false
			element_data["position"] = {"x": element.position.x, "y": element.position.y}
			element_data["scale"] = {"x": element.scale.x, "y": element.scale.y}

		# Common properties
		element_data["z_index"] = element.z_index
		element_data["z_as_relative"] = element.z_as_relative
		element_data["child_index"] = element.get_index()
		element_data["visible"] = element.visible
		element_data["rotation_degrees"] = element.rotation_degrees
		element_data["modulate_a"] = element.modulate.a
		element_data["is_copy"] = item.get("is_copy", false)
		element_data["source_path"] = item.get("source_path", "")

		# Light-specific properties
		if _is_light_node(element):
			element_data["light_energy"] = element.energy
			element_data["light_color"] = {
				"r": element.color.r,
				"g": element.color.g,
				"b": element.color.b
			}
			element_data["light_shadow_enabled"] = element.shadow_enabled
			element_data["light_shadow_color"] = {
				"r": element.shadow_color.r,
				"g": element.shadow_color.g,
				"b": element.shadow_color.b,
				"a": element.shadow_color.a
			}
			element_data["light_blend_mode"] = element.blend_mode

			if element is PointLight2D:
				element_data["light_texture_scale"] = element.texture_scale

		# ColorRect-specific properties
		if element is ColorRect:
			element_data["colorrect_color"] = {
				"r": element.color.r,
				"g": element.color.g,
				"b": element.color.b,
				"a": element.color.a
			}

		# TextureRect-specific properties
		if element is TextureRect:
			element_data["texture_flip_h"] = element.flip_h
			element_data["texture_flip_v"] = element.flip_v
			element_data["texture_stretch_mode"] = element.stretch_mode

		# Label/RichTextLabel properties
		if element is Label:
			element_data["label_text"] = element.text
		elif element is RichTextLabel:
			element_data["label_text"] = element.text

		# Panel properties
		if element is Panel:
			element_data["panel_self_modulate"] = {
				"r": element.self_modulate.r,
				"g": element.self_modulate.g,
				"b": element.self_modulate.b,
				"a": element.self_modulate.a
			}

		config["elements"][path] = element_data

		if item.get("is_copy", false):
			# Only include parent copies, not children of other copies
			var is_child_of_copy = false
			for other_path in copy_paths:
				if path != other_path and path.begins_with(other_path + "/"):
					is_child_of_copy = true
					break
			if not is_child_of_copy:
				config["copies"].append({
					"path": path,
					"source_path": item.get("source_path", ""),
					"type": item.get("type", ItemType.OBJECT),
					"category": item.get("category", "Other"),
				})

	return config


func _get_element_config(element, item: Dictionary) -> Dictionary:
	"""Get config for a single element"""
	var element_data = {}

	# Handle Control vs Node2D
	if element is Control:
		element_data["is_control"] = true
		element_data["offset_left"] = element.offset_left
		element_data["offset_right"] = element.offset_right
		element_data["offset_top"] = element.offset_top
		element_data["offset_bottom"] = element.offset_bottom
	elif element is Node2D:
		element_data["is_control"] = false
		element_data["position"] = {"x": element.position.x, "y": element.position.y}
		element_data["scale"] = {"x": element.scale.x, "y": element.scale.y}

	# Common properties
	element_data["z_index"] = element.z_index
	element_data["z_as_relative"] = element.z_as_relative
	element_data["child_index"] = element.get_index()
	element_data["visible"] = element.visible
	element_data["rotation_degrees"] = element.rotation_degrees
	element_data["modulate_a"] = element.modulate.a
	element_data["is_copy"] = item.get("is_copy", false)
	element_data["source_path"] = item.get("source_path", "")

	# Light-specific properties
	if _is_light_node(element):
		element_data["light_energy"] = element.energy
		element_data["light_color"] = {
			"r": element.color.r,
			"g": element.color.g,
			"b": element.color.b
		}
		element_data["light_shadow_enabled"] = element.shadow_enabled
		element_data["light_shadow_color"] = {
			"r": element.shadow_color.r,
			"g": element.shadow_color.g,
			"b": element.shadow_color.b,
			"a": element.shadow_color.a
		}
		element_data["light_blend_mode"] = element.blend_mode

		if element is PointLight2D:
			element_data["light_texture_scale"] = element.texture_scale

	return element_data


func apply_scene_config(config: Dictionary) -> void:
	if not config.has("elements"):
		print("[EditMode] Invalid config: no elements")
		return

	var elements_data = config["elements"]
	var config_version = config.get("version", 1)
	var copies_recreated = 0

	# First, recreate copies
	if config.has("copies"):
		# Collect all copy paths to detect children
		var all_copy_paths: Array[String] = []
		for cd in config["copies"]:
			all_copy_paths.append(cd.get("path", ""))

		for copy_data in config["copies"]:
			var copy_path = copy_data.get("path", "")
			var source_path = copy_data.get("source_path", "")

			# Skip children of other copies (they're auto-created when parent is duplicated)
			var is_child_of_copy = false
			for other_path in all_copy_paths:
				if copy_path != other_path and copy_path.begins_with(other_path + "/"):
					is_child_of_copy = true
					break
			if is_child_of_copy:
				continue

			# Check if already exists
			var exists = false
			for item in editable_elements:
				if item["path"] == copy_path:
					exists = true
					break

			if not exists:
				# Find source and duplicate
				for item in editable_elements:
					if item["path"] == source_path:
						var source = item["element"]
						var new_element = source.duplicate()
						# Set node name to just the base name (last path component), not the full path
						var base_name = copy_path.get_file()  # Gets "Binder0_copy1" from "RoomElements/Binder0_copy1"
						new_element.name = base_name
						var parent = source.get_parent()
						if parent:
							parent.add_child(new_element)

						var new_item = {
							"element": new_element,
							"type": copy_data.get("type", ItemType.OBJECT),
							"path": copy_path,
							"category": copy_data.get("category", "Other"),
							"is_copy": true,
							"source_path": source_path,
						}
						editable_elements.append(new_item)
						copies_recreated += 1
						break

	if copies_recreated > 0:
		print("[EditMode] Recreated %d copies from config" % copies_recreated)

	# Apply positions and properties to all elements
	for item in editable_elements:
		var element = item["element"]
		var path = item["path"]

		if not elements_data.has(path) or not element:
			continue

		var data = elements_data[path]
		var is_control = data.get("is_control", element is Control)

		# Position/size based on node type
		if is_control and element is Control:
			if data.has("offset_left"):
				element.offset_left = data["offset_left"]
			if data.has("offset_right"):
				element.offset_right = data["offset_right"]
			if data.has("offset_top"):
				element.offset_top = data["offset_top"]
			if data.has("offset_bottom"):
				element.offset_bottom = data["offset_bottom"]
		elif element is Node2D:
			if data.has("position"):
				element.position = Vector2(data["position"]["x"], data["position"]["y"])
			if data.has("scale"):
				element.scale = Vector2(data["scale"]["x"], data["scale"]["y"])

		# Common properties
		if data.has("z_index"):
			element.z_index = data["z_index"]
		if data.has("z_as_relative"):
			element.z_as_relative = data["z_as_relative"]
		if data.has("visible"):
			element.visible = data["visible"]
			if not data["visible"]:
				hidden_elements[path] = true
		if data.has("rotation_degrees"):
			element.rotation_degrees = data["rotation_degrees"]
		if data.has("modulate_a"):
			element.modulate.a = data["modulate_a"]

		# Child index (z-order in scene tree)
		if data.has("child_index"):
			var parent = element.get_parent()
			if parent:
				var target_index = data["child_index"]
				if target_index < parent.get_child_count():
					parent.move_child(element, target_index)

		# Light properties (config version 2+)
		if config_version >= 2 and _is_light_node(element):
			if data.has("light_energy"):
				element.energy = data["light_energy"]
			if data.has("light_color"):
				element.color = Color(
					data["light_color"]["r"],
					data["light_color"]["g"],
					data["light_color"]["b"]
				)
			if data.has("light_shadow_enabled"):
				element.shadow_enabled = data["light_shadow_enabled"]
			if data.has("light_shadow_color"):
				var sc = data["light_shadow_color"]
				element.shadow_color = Color(sc["r"], sc["g"], sc["b"], sc["a"])
			if data.has("light_blend_mode"):
				element.blend_mode = data["light_blend_mode"]
			if data.has("light_texture_scale") and element is PointLight2D:
				element.texture_scale = data["light_texture_scale"]

		# ColorRect properties
		if element is ColorRect and data.has("colorrect_color"):
			var c = data["colorrect_color"]
			element.color = Color(c["r"], c["g"], c["b"], c["a"])

		# TextureRect properties
		if element is TextureRect:
			if data.has("texture_flip_h"):
				element.flip_h = data["texture_flip_h"]
			if data.has("texture_flip_v"):
				element.flip_v = data["texture_flip_v"]
			if data.has("texture_stretch_mode"):
				element.stretch_mode = data["texture_stretch_mode"]

		# Label/RichTextLabel properties
		if element is Label and data.has("label_text"):
			element.text = data["label_text"]
		elif element is RichTextLabel and data.has("label_text"):
			element.text = data["label_text"]

		# Panel properties
		if element is Panel and data.has("panel_self_modulate"):
			var c = data["panel_self_modulate"]
			element.self_modulate = Color(c["r"], c["g"], c["b"], c["a"])

	# Apply hidden list
	if config.has("hidden"):
		for path in config["hidden"]:
			hidden_elements[path] = true
			for item in editable_elements:
				if item["path"] == path and item["element"]:
					item["element"].visible = false
					break

	# Apply locked list (config version 2+)
	if config.has("locked"):
		for path in config["locked"]:
			locked_elements[path] = true

	# Apply custom names
	custom_names.clear()
	if config.has("custom_names"):
		for path in config["custom_names"]:
			custom_names[path] = config["custom_names"][path]

	print("[EditMode] Applied config v%d with %d elements" % [config_version, elements_data.size()])

	if edit_mode_enabled:
		_populate_asset_list()
		_update_type_highlights()
		_update_item_labels()
		_update_selection_outline()


func factory_reset() -> void:
	# Remove all copies first
	var copies_to_remove = []
	for item in editable_elements:
		if item.get("is_copy", false):
			copies_to_remove.append(item)

	for item in copies_to_remove:
		var element = item["element"]
		if selected_element == element:
			_clear_selection()
		element.queue_free()
		editable_elements.erase(item)
		original_positions.erase(item["path"])

	# Reset all original elements
	for item in editable_elements:
		var element = item["element"]
		var path = item["path"]
		var orig = original_positions.get(path)

		if not orig:
			continue

		# Restore position based on element type
		if orig.get("is_control", true) and element is Control:
			element.offset_left = orig["left"]
			element.offset_right = orig["right"]
			element.offset_top = orig["top"]
			element.offset_bottom = orig["bottom"]
		elif element is Node2D:
			element.position = orig.get("position", element.position)

		element.z_index = orig.get("z_index", 0)
		element.z_as_relative = orig.get("z_as_relative", true)
		element.visible = orig.get("visible", true)

		var parent = element.get_parent()
		if parent and orig.has("child_index"):
			var target_index = orig["child_index"]
			if target_index < parent.get_child_count():
				parent.move_child(element, target_index)

	modified_elements.clear()
	hidden_elements.clear()
	undo_stack.clear()
	redo_stack.clear()
	copy_counter.clear()
	custom_names.clear()

	print("[EditMode] Factory reset complete")

	if edit_mode_enabled:
		_clear_selection()
		_populate_asset_list()
		_update_type_highlights()
		_update_item_labels()
		_update_properties_panel()


# ===== ALIGNMENT AND SNAP/GRID TOOLS =====

func _toggle_snap() -> void:
	snap_enabled = not snap_enabled
	print("[EditMode] Snapping %s" % ("enabled" if snap_enabled else "disabled"))


func _toggle_grid() -> void:
	grid_enabled = not grid_enabled
	print("[EditMode] Grid %s" % ("enabled" if grid_enabled else "disabled"))
	if grid_enabled:
		_create_grid_overlay()
	else:
		_remove_grid_overlay()


func _toggle_guides() -> void:
	guides_enabled = not guides_enabled
	print("[EditMode] Guides %s" % ("enabled" if guides_enabled else "disabled"))
	if not guides_enabled:
		_clear_smart_guides()


func _update_snap_toggle_button() -> void:
	if snap_toggle_btn:
		snap_toggle_btn.button_pressed = snap_enabled
		_update_toggle_button_style(snap_toggle_btn, snap_enabled)


func _update_grid_toggle_button() -> void:
	if grid_toggle_btn:
		grid_toggle_btn.button_pressed = grid_enabled
		_update_toggle_button_style(grid_toggle_btn, grid_enabled)


func _update_guides_toggle_button() -> void:
	if guides_toggle_btn:
		guides_toggle_btn.button_pressed = guides_enabled
		_update_toggle_button_style(guides_toggle_btn, guides_enabled)


func _create_grid_overlay() -> void:
	if not overlay:
		return

	# Remove existing grid if any
	_remove_grid_overlay()

	var grid = Control.new()
	grid.name = "GridOverlay"
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.z_index = -1  # Behind selection outlines

	grid.draw.connect(func():
		var viewport_size = get_viewport().get_visible_rect().size
		var grid_color = Color(0.3, 0.4, 0.35, 0.15)
		var grid_color_major = Color(0.3, 0.5, 0.4, 0.25)

		# Get zoom scale if available
		var scale = Vector2.ONE
		if zoom_container:
			scale = zoom_container.scale

		var adjusted_grid = grid_size * scale.x

		# Draw vertical lines
		var x = 0.0
		var count = 0
		while x < viewport_size.x:
			var col = grid_color_major if count % 5 == 0 else grid_color
			grid.draw_line(Vector2(x, 0), Vector2(x, viewport_size.y), col, 1.0)
			x += adjusted_grid
			count += 1

		# Draw horizontal lines
		var y = 0.0
		count = 0
		while y < viewport_size.y:
			var col = grid_color_major if count % 5 == 0 else grid_color
			grid.draw_line(Vector2(0, y), Vector2(viewport_size.x, y), col, 1.0)
			y += adjusted_grid
			count += 1
	)

	overlay.add_child(grid)
	overlay.move_child(grid, 0)  # Put at back


func _remove_grid_overlay() -> void:
	if not overlay:
		return
	var grid = overlay.get_node_or_null("GridOverlay")
	if grid:
		grid.queue_free()


func _get_elements_for_alignment() -> Array:
	# Returns selected element(s) for alignment operations
	# If multi_selected has items, use those; otherwise use single selected element
	if multi_selected.size() > 1:
		return multi_selected.duplicate()
	elif selected_element:
		return [selected_element]
	return []


func _get_element_bounds(element) -> Rect2:
	# Get bounding rect for an element (works with Control and Node2D)
	if element is Control:
		return element.get_global_rect()
	elif element is Node2D:
		# For Node2D (including lights), create a bounds from position
		var pos = element.global_position
		var size = Vector2(32, 32)  # Default size for Node2D
		if element.has_method("get_rect"):
			var rect = element.get_rect()
			size = rect.size
		return Rect2(pos - size / 2, size)
	return Rect2()


func _set_element_position(element, new_pos: Vector2) -> void:
	# Set position for an element (works with Control and Node2D)
	if element is Control:
		var current_rect = element.get_global_rect()
		var delta = new_pos - current_rect.position
		element.offset_left += delta.x
		element.offset_right += delta.x
		element.offset_top += delta.y
		element.offset_bottom += delta.y
		_mark_element_modified(element)
	elif element is Node2D:
		var current_bounds = _get_element_bounds(element)
		element.global_position = new_pos + current_bounds.size / 2
		_mark_element_modified(element)


func _get_element_drag_state(element) -> Dictionary:
	# Get current position state for drag operations (works with Control and Node2D)
	if element is Control:
		return {
			"is_control": true,
			"left": element.offset_left,
			"right": element.offset_right,
			"top": element.offset_top,
			"bottom": element.offset_bottom,
		}
	elif element is Node2D:
		return {
			"is_control": false,
			"position": element.position,
			"global_position": element.global_position,
		}
	return {}


func _apply_drag_delta(element, start_state: Dictionary, delta: Vector2) -> void:
	# Apply position delta to element (works with Control and Node2D)
	if start_state.get("is_control", true) and element is Control:
		element.offset_left = start_state["left"] + delta.x
		element.offset_right = start_state["right"] + delta.x
		element.offset_top = start_state["top"] + delta.y
		element.offset_bottom = start_state["bottom"] + delta.y
	elif element is Node2D:
		element.position = start_state["position"] + delta


func _get_element_position(element) -> Vector2:
	# Get top-left position of element (works with Control and Node2D)
	if element is Control:
		return Vector2(element.offset_left, element.offset_top)
	elif element is Node2D:
		return element.position
	return Vector2.ZERO


func _element_position_changed(element, start_state: Dictionary) -> bool:
	# Check if element position changed from start state
	if start_state.get("is_control", true) and element is Control:
		return (
			abs(element.offset_left - start_state.get("left", 0)) > 0.1 or
			abs(element.offset_top - start_state.get("top", 0)) > 0.1
		)
	elif element is Node2D:
		var start_pos = start_state.get("position", Vector2.ZERO)
		return element.position.distance_to(start_pos) > 0.1
	return false


func _mark_element_modified(element_or_path) -> void:
	# Mark element as modified for save tracking
	# Accepts either an element object or a path string
	var path: String = ""

	if element_or_path is String:
		path = element_or_path
	else:
		# It's an element - find its path
		for item in editable_elements:
			if item["element"] == element_or_path:
				path = item["path"]
				break

	if not path.is_empty():
		modified_elements[path] = true

	# Trigger auto-save
	_mark_scene_dirty()


func _align_left() -> void:
	var elements = _get_elements_for_alignment()
	if elements.size() < 2:
		print("[EditMode] Select multiple elements for alignment (Shift+Click)")
		return

	# Find leftmost position
	var min_x = INF
	for el in elements:
		var bounds = _get_element_bounds(el)
		if bounds.position.x < min_x:
			min_x = bounds.position.x

	# Align all to leftmost
	for el in elements:
		var bounds = _get_element_bounds(el)
		_set_element_position(el, Vector2(min_x, bounds.position.y))

	_update_selection_outline()
	print("[EditMode] Aligned %d elements to left" % elements.size())


func _align_center_h() -> void:
	var elements = _get_elements_for_alignment()
	if elements.size() < 2:
		print("[EditMode] Select multiple elements for alignment (Shift+Click)")
		return

	# Find center X of all elements combined
	var min_x = INF
	var max_x = -INF
	for el in elements:
		var bounds = _get_element_bounds(el)
		if bounds.position.x < min_x:
			min_x = bounds.position.x
		if bounds.end.x > max_x:
			max_x = bounds.end.x

	var center_x = (min_x + max_x) / 2

	# Align all to center
	for el in elements:
		var bounds = _get_element_bounds(el)
		var new_x = center_x - bounds.size.x / 2
		_set_element_position(el, Vector2(new_x, bounds.position.y))

	_update_selection_outline()
	print("[EditMode] Aligned %d elements to horizontal center" % elements.size())


func _align_right() -> void:
	var elements = _get_elements_for_alignment()
	if elements.size() < 2:
		print("[EditMode] Select multiple elements for alignment (Shift+Click)")
		return

	# Find rightmost position
	var max_x = -INF
	for el in elements:
		var bounds = _get_element_bounds(el)
		if bounds.end.x > max_x:
			max_x = bounds.end.x

	# Align all to rightmost
	for el in elements:
		var bounds = _get_element_bounds(el)
		var new_x = max_x - bounds.size.x
		_set_element_position(el, Vector2(new_x, bounds.position.y))

	_update_selection_outline()
	print("[EditMode] Aligned %d elements to right" % elements.size())


func _align_top() -> void:
	var elements = _get_elements_for_alignment()
	if elements.size() < 2:
		print("[EditMode] Select multiple elements for alignment (Shift+Click)")
		return

	# Find topmost position
	var min_y = INF
	for el in elements:
		var bounds = _get_element_bounds(el)
		if bounds.position.y < min_y:
			min_y = bounds.position.y

	# Align all to top
	for el in elements:
		var bounds = _get_element_bounds(el)
		_set_element_position(el, Vector2(bounds.position.x, min_y))

	_update_selection_outline()
	print("[EditMode] Aligned %d elements to top" % elements.size())


func _align_center_v() -> void:
	var elements = _get_elements_for_alignment()
	if elements.size() < 2:
		print("[EditMode] Select multiple elements for alignment (Shift+Click)")
		return

	# Find center Y of all elements combined
	var min_y = INF
	var max_y = -INF
	for el in elements:
		var bounds = _get_element_bounds(el)
		if bounds.position.y < min_y:
			min_y = bounds.position.y
		if bounds.end.y > max_y:
			max_y = bounds.end.y

	var center_y = (min_y + max_y) / 2

	# Align all to center
	for el in elements:
		var bounds = _get_element_bounds(el)
		var new_y = center_y - bounds.size.y / 2
		_set_element_position(el, Vector2(bounds.position.x, new_y))

	_update_selection_outline()
	print("[EditMode] Aligned %d elements to vertical center" % elements.size())


func _align_bottom() -> void:
	var elements = _get_elements_for_alignment()
	if elements.size() < 2:
		print("[EditMode] Select multiple elements for alignment (Shift+Click)")
		return

	# Find bottommost position
	var max_y = -INF
	for el in elements:
		var bounds = _get_element_bounds(el)
		if bounds.end.y > max_y:
			max_y = bounds.end.y

	# Align all to bottom
	for el in elements:
		var bounds = _get_element_bounds(el)
		var new_y = max_y - bounds.size.y
		_set_element_position(el, Vector2(bounds.position.x, new_y))

	_update_selection_outline()
	print("[EditMode] Aligned %d elements to bottom" % elements.size())


# Marquee (box) selection functions
func _create_marquee_overlay() -> void:
	print("[EditMode] Creating marquee overlay")
	if marquee_overlay:
		marquee_overlay.queue_free()

	marquee_overlay = Control.new()
	marquee_overlay.name = "MarqueeOverlay"
	marquee_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	marquee_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marquee_overlay.z_index = 100

	var edit_mgr = self
	marquee_overlay.draw.connect(func():
		edit_mgr._draw_marquee_rect(marquee_overlay)
	)

	if overlay:
		overlay.add_child(marquee_overlay)
		print("[EditMode] Marquee overlay added to overlay")
	else:
		print("[EditMode] ERROR: overlay is null!")


func _update_marquee_overlay() -> void:
	if marquee_overlay:
		marquee_overlay.queue_redraw()


func _remove_marquee_overlay() -> void:
	if marquee_overlay:
		marquee_overlay.queue_free()
		marquee_overlay = null


func _draw_marquee_rect(container: Control) -> void:
	var rect = _get_marquee_rect()
	var color = THEME_ACCENT.lerp(Color.CYAN, 0.5)
	var fill_color = Color(color.r, color.g, color.b, 0.1)

	# Draw preview highlights for elements that would be selected
	var preview_color = Color(0.0, 1.0, 0.6, 0.8)  # Bright green for preview
	var preview_fill = Color(0.0, 1.0, 0.5, 0.15)
	for item in editable_elements:
		var element = item.get("element")
		if not element or not is_instance_valid(element):
			continue
		var path = item.get("path", "")
		if hidden_elements.get(path, false):
			continue
		# Skip already multi-selected elements
		if element in multi_selected:
			continue

		var elem_rect = _get_element_screen_rect(element)
		if rect.intersects(elem_rect):
			# Draw preview fill
			container.draw_rect(elem_rect, preview_fill, true)
			# Draw preview outline
			container.draw_rect(elem_rect, preview_color, false, 2.0)

	# Draw filled rectangle for marquee
	container.draw_rect(rect, fill_color, true)

	# Draw dashed border
	var dash_length = 8.0
	var gap_length = 4.0

	# Top edge
	var x = rect.position.x
	while x < rect.end.x:
		var end_x = min(x + dash_length, rect.end.x)
		container.draw_line(Vector2(x, rect.position.y), Vector2(end_x, rect.position.y), color, 2.0)
		x += dash_length + gap_length

	# Bottom edge
	x = rect.position.x
	while x < rect.end.x:
		var end_x = min(x + dash_length, rect.end.x)
		container.draw_line(Vector2(x, rect.end.y), Vector2(end_x, rect.end.y), color, 2.0)
		x += dash_length + gap_length

	# Left edge
	var y = rect.position.y
	while y < rect.end.y:
		var end_y = min(y + dash_length, rect.end.y)
		container.draw_line(Vector2(rect.position.x, y), Vector2(rect.position.x, end_y), color, 2.0)
		y += dash_length + gap_length

	# Right edge
	y = rect.position.y
	while y < rect.end.y:
		var end_y = min(y + dash_length, rect.end.y)
		container.draw_line(Vector2(rect.end.x, y), Vector2(rect.end.x, end_y), color, 2.0)
		y += dash_length + gap_length


func _get_marquee_rect() -> Rect2:
	var min_x = min(marquee_start.x, marquee_current.x)
	var min_y = min(marquee_start.y, marquee_current.y)
	var max_x = max(marquee_start.x, marquee_current.x)
	var max_y = max(marquee_start.y, marquee_current.y)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


func _complete_marquee_selection() -> void:
	var marquee_rect = _get_marquee_rect()

	# Skip if marquee is too small (just a click)
	if marquee_rect.size.x < 5 and marquee_rect.size.y < 5:
		return

	var selected_count = 0
	for item in editable_elements:
		var element = item.get("element")
		if not element or not is_instance_valid(element):
			continue

		# Skip hidden elements
		var path = item.get("path", "")
		if hidden_elements.get(path, false):
			continue

		# Get element's screen rect
		var elem_rect = _get_element_screen_rect(element)

		# Check if element intersects with marquee
		if marquee_rect.intersects(elem_rect):
			if element not in multi_selected:
				multi_selected.append(element)
				selected_count += 1

	if selected_count > 0:
		# Set the first selected as the active element
		if multi_selected.size() > 0:
			selected_element = multi_selected[0]
			selected_item = _get_item_for_element(selected_element)

		_update_multi_selection_outline()
		_update_selection_outline()
		_update_properties_panel()
		_populate_scene_tree()
		print("[EditMode] Marquee selected %d elements (total: %d)" % [selected_count, multi_selected.size()])


func _add_to_multi_selection(element) -> void:
	if element and element not in multi_selected:
		multi_selected.append(element)
		_update_multi_selection_outline()
		_populate_scene_tree()  # Refresh tree to show multi-select highlighting


func _remove_from_multi_selection(element) -> void:
	if element in multi_selected:
		multi_selected.erase(element)
		_update_multi_selection_outline()
		_populate_scene_tree()  # Refresh tree to show multi-select highlighting


func _clear_multi_selection() -> void:
	var had_selection = multi_selected.size() > 0
	multi_selected.clear()
	_update_multi_selection_outline()
	if had_selection:
		_populate_scene_tree()  # Refresh tree to clear multi-select highlighting


func _update_multi_selection_outline() -> void:
	# Remove existing multi-selection indicators immediately
	if not overlay:
		return

	var to_remove: Array[Node] = []
	for child in overlay.get_children():
		if child.name.begins_with("MultiSelect_"):
			to_remove.append(child)
	for child in to_remove:
		overlay.remove_child(child)
		child.queue_free()

	# Draw outline for each multi-selected element
	for i in range(multi_selected.size()):
		var element = multi_selected[i]
		if not is_instance_valid(element):
			continue

		var indicator = Control.new()
		indicator.name = "MultiSelect_%d" % i
		indicator.set_anchors_preset(Control.PRESET_FULL_RECT)
		indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Store element reference for dynamic bounds lookup
		indicator.set_meta("target_element", element)

		var color = THEME_ACCENT.lerp(Color.CYAN, 0.3)
		var edit_mgr = self  # Capture reference for closure

		indicator.draw.connect(func():
			var target = indicator.get_meta("target_element", null)
			if not target or not is_instance_valid(target):
				return
			# Get fresh screen-space bounds each draw call (accounts for zoom/pan)
			var rect = edit_mgr._get_element_screen_rect(target)

			# Dashed outline for multi-select
			var dash_length = 6.0
			var gap_length = 4.0

			# Top edge
			var x = rect.position.x
			while x < rect.end.x:
				var end_x = min(x + dash_length, rect.end.x)
				indicator.draw_line(Vector2(x, rect.position.y), Vector2(end_x, rect.position.y), color, 2.0)
				x += dash_length + gap_length

			# Bottom edge
			x = rect.position.x
			while x < rect.end.x:
				var end_x = min(x + dash_length, rect.end.x)
				indicator.draw_line(Vector2(x, rect.end.y), Vector2(end_x, rect.end.y), color, 2.0)
				x += dash_length + gap_length

			# Left edge
			var y = rect.position.y
			while y < rect.end.y:
				var end_y = min(y + dash_length, rect.end.y)
				indicator.draw_line(Vector2(rect.position.x, y), Vector2(rect.position.x, end_y), color, 2.0)
				y += dash_length + gap_length

			# Right edge
			y = rect.position.y
			while y < rect.end.y:
				var end_y = min(y + dash_length, rect.end.y)
				indicator.draw_line(Vector2(rect.end.x, y), Vector2(rect.end.x, end_y), color, 2.0)
				y += dash_length + gap_length
		)

		overlay.add_child(indicator)


# ===== SMART GUIDES AND SNAPPING =====

func _calculate_snap(new_left: float, new_top: float) -> Dictionary:
	# Calculate snapped position and return snap guides to draw
	# Like Figma: only show guides for the BEST snap match, not all possible snaps
	var result = {"x": new_left, "y": new_top, "guides": []}

	if not selected_element or not selected_element is Control:
		return result

	# Convert proposed local offsets to proposed global position
	var current_local = Vector2(selected_element.offset_left, selected_element.offset_top)
	var proposed_local = Vector2(new_left, new_top)
	var delta = proposed_local - current_local

	var current_global_rect = selected_element.get_global_rect()
	var el_left = current_global_rect.position.x + delta.x
	var el_top = current_global_rect.position.y + delta.y
	var el_width = current_global_rect.size.x
	var el_height = current_global_rect.size.y
	var el_right = el_left + el_width
	var el_bottom = el_top + el_height
	var el_center_x = el_left + el_width / 2
	var el_center_y = el_top + el_height / 2

	var snap_x = INF
	var snap_y = INF
	var best_global_x = el_left
	var best_global_y = el_top
	var best_guide_x = null  # Only store the BEST guide
	var best_guide_y = null

	# Collect snap targets from other elements
	for item in editable_elements:
		var other = item["element"]
		if other == null or other == selected_element:
			continue
		if not other.visible:
			continue

		var bounds = _get_element_bounds(other)
		var o_left = bounds.position.x
		var o_top = bounds.position.y
		var o_right = bounds.end.x
		var o_bottom = bounds.end.y
		var o_center_x = o_left + bounds.size.x / 2
		var o_center_y = o_top + bounds.size.y / 2

		# Check horizontal snaps - only keep the BEST match
		# Left to left
		var dist = abs(el_left - o_left)
		if dist < snap_threshold and dist < snap_x:
			snap_x = dist
			best_global_x = o_left
			best_guide_x = {"type": "v", "x": o_left, "y1": min(el_top, o_top), "y2": max(el_bottom, o_bottom)}

		# Left to right
		dist = abs(el_left - o_right)
		if dist < snap_threshold and dist < snap_x:
			snap_x = dist
			best_global_x = o_right
			best_guide_x = {"type": "v", "x": o_right, "y1": min(el_top, o_top), "y2": max(el_bottom, o_bottom)}

		# Right to left
		dist = abs(el_right - o_left)
		if dist < snap_threshold and dist < snap_x:
			snap_x = dist
			best_global_x = o_left - el_width
			best_guide_x = {"type": "v", "x": o_left, "y1": min(el_top, o_top), "y2": max(el_bottom, o_bottom)}

		# Right to right
		dist = abs(el_right - o_right)
		if dist < snap_threshold and dist < snap_x:
			snap_x = dist
			best_global_x = o_right - el_width
			best_guide_x = {"type": "v", "x": o_right, "y1": min(el_top, o_top), "y2": max(el_bottom, o_bottom)}

		# Center to center (horizontal)
		dist = abs(el_center_x - o_center_x)
		if dist < snap_threshold and dist < snap_x:
			snap_x = dist
			best_global_x = o_center_x - el_width / 2
			best_guide_x = {"type": "v", "x": o_center_x, "y1": min(el_top, o_top), "y2": max(el_bottom, o_bottom)}

		# Check vertical snaps - only keep the BEST match
		# Top to top
		dist = abs(el_top - o_top)
		if dist < snap_threshold and dist < snap_y:
			snap_y = dist
			best_global_y = o_top
			best_guide_y = {"type": "h", "y": o_top, "x1": min(el_left, o_left), "x2": max(el_right, o_right)}

		# Top to bottom
		dist = abs(el_top - o_bottom)
		if dist < snap_threshold and dist < snap_y:
			snap_y = dist
			best_global_y = o_bottom
			best_guide_y = {"type": "h", "y": o_bottom, "x1": min(el_left, o_left), "x2": max(el_right, o_right)}

		# Bottom to top
		dist = abs(el_bottom - o_top)
		if dist < snap_threshold and dist < snap_y:
			snap_y = dist
			best_global_y = o_top - el_height
			best_guide_y = {"type": "h", "y": o_top, "x1": min(el_left, o_left), "x2": max(el_right, o_right)}

		# Bottom to bottom
		dist = abs(el_bottom - o_bottom)
		if dist < snap_threshold and dist < snap_y:
			snap_y = dist
			best_global_y = o_bottom - el_height
			best_guide_y = {"type": "h", "y": o_bottom, "x1": min(el_left, o_left), "x2": max(el_right, o_right)}

		# Center to center (vertical)
		dist = abs(el_center_y - o_center_y)
		if dist < snap_threshold and dist < snap_y:
			snap_y = dist
			best_global_y = o_center_y - el_height / 2
			best_guide_y = {"type": "h", "y": o_center_y, "x1": min(el_left, o_left), "x2": max(el_right, o_right)}

	# Grid snap
	if grid_enabled:
		var grid_snap_x = round(el_left / grid_size) * grid_size
		var grid_snap_y = round(el_top / grid_size) * grid_size

		if abs(el_left - grid_snap_x) < snap_threshold and abs(el_left - grid_snap_x) < snap_x:
			snap_x = abs(el_left - grid_snap_x)
			best_global_x = grid_snap_x
			best_guide_x = null  # No guide for grid snap
		if abs(el_top - grid_snap_y) < snap_threshold and abs(el_top - grid_snap_y) < snap_y:
			snap_y = abs(el_top - grid_snap_y)
			best_global_y = grid_snap_y
			best_guide_y = null

	# Only add the best guides (max 2: one horizontal, one vertical)
	if best_guide_x:
		result["guides"].append(best_guide_x)
	if best_guide_y:
		result["guides"].append(best_guide_y)

	# Convert snapped global position back to local offsets
	var snapped_global_delta_x = best_global_x - current_global_rect.position.x if snap_x < INF else delta.x
	var snapped_global_delta_y = best_global_y - current_global_rect.position.y if snap_y < INF else delta.y

	result["x"] = current_local.x + snapped_global_delta_x
	result["y"] = current_local.y + snapped_global_delta_y

	return result


func _draw_smart_guides(guides: Array) -> void:
	_clear_smart_guides()

	if not guides_enabled or not overlay or guides.is_empty():
		return

	var guide_container = Control.new()
	guide_container.name = "SmartGuides"
	guide_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	guide_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide_container.z_index = 100  # On top

	var guide_color = Color(1.0, 0.2, 0.4, 0.9)  # Bright pink/red for visibility
	var guide_data = guides.duplicate()

	guide_container.draw.connect(func():
		for guide in guide_data:
			if guide["type"] == "v":
				# Vertical line
				guide_container.draw_line(
					Vector2(guide["x"], guide["y1"]),
					Vector2(guide["x"], guide["y2"]),
					guide_color, 1.0
				)
			elif guide["type"] == "h":
				# Horizontal line
				guide_container.draw_line(
					Vector2(guide["x1"], guide["y"]),
					Vector2(guide["x2"], guide["y"]),
					guide_color, 1.0
				)
	)

	overlay.add_child(guide_container)


func _clear_smart_guides() -> void:
	if not overlay:
		return
	# Remove ALL SmartGuides nodes (in case multiple accumulated)
	for child in overlay.get_children():
		if child.name == "SmartGuides" or child.name.begins_with("SmartGuides"):
			child.free()  # Immediate removal, not queue_free()


# ===== SAVE/LOAD FUNCTIONALITY =====

func _update_status_bar() -> void:
	if not status_bar:
		return

	var hbox = status_bar.get_child(0) if status_bar.get_child_count() > 0 else null
	if not hbox:
		return

	# Update selection label
	var selection_label = hbox.get_node_or_null("SelectionLabel") as Label
	if selection_label:
		if selected_element:
			var display_name = _get_display_name(selected_item)
			var type_name = TYPE_NAMES.get(selected_item.get("type", ItemType.OBJECT), "Object")
			selection_label.text = "%s (%s)" % [display_name, type_name]
			selection_label.add_theme_color_override("font_color", TYPE_COLORS.get(selected_item.get("type", ItemType.OBJECT), THEME_TEXT))
		else:
			selection_label.text = "No selection"
			selection_label.add_theme_color_override("font_color", THEME_TEXT_DIM)

	# Update hint/status label
	var hint_label = hbox.get_node_or_null("HintLabel") as Label
	if hint_label:
		match _save_status:
			"saving":
				hint_label.text = "Saving..."
				hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5))
			"success":
				hint_label.text = _save_message if _save_message else "Saved!"
				hint_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
			"error":
				hint_label.text = _save_message if _save_message else "Save failed"
				hint_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
			_:
				hint_label.text = "Ctrl+Wheel: Zoom | Ctrl+Drag: Pan"
				hint_label.add_theme_color_override("font_color", THEME_TEXT_DIM)

	# Update modified count
	var modified_label = hbox.get_node_or_null("ModifiedLabel") as Label
	if modified_label:
		var count = modified_elements.size()
		if count == 0:
			modified_label.text = "No changes"
			modified_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
		elif count == 1:
			modified_label.text = "1 change"
			modified_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
		else:
			modified_label.text = "%d changes" % count
			modified_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
		modified_label.tooltip_text = "Modified elements: %d" % count

	# Update player label
	var player_label = hbox.get_node_or_null("PlayerLabel") as Label
	if player_label:
		if OnlineManager and not OnlineManager.player_handle.is_empty():
			player_label.text = OnlineManager.player_handle
			player_label.add_theme_color_override("font_color", THEME_ACCENT)
			player_label.tooltip_text = "Logged in as " + OnlineManager.player_handle
		else:
			player_label.text = "Guest"
			player_label.add_theme_color_override("font_color", THEME_TEXT_DIM)
			player_label.tooltip_text = "Not logged in"

	# Update connection status (dot + text) - these are inside a nested container
	var conn_dot = status_bar.find_child("ConnectionDot", true, false) as ColorRect
	var conn_label = status_bar.find_child("ConnectionLabel", true, false) as Label

	if conn_dot and conn_label:
		var is_online = OnlineManager and OnlineManager.is_online
		var is_ws = OnlineManager and OnlineManager.is_websocket_connected()

		if is_ws:
			conn_dot.color = Color(0.3, 1.0, 0.3)  # Green
			conn_label.text = "Online"
			conn_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
			conn_label.tooltip_text = "WebSocket connected - real-time sync active"
		elif is_online:
			conn_dot.color = Color(1.0, 0.8, 0.3)  # Yellow
			conn_label.text = "Connecting"
			conn_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
			conn_label.tooltip_text = "HTTP connected - WebSocket connecting..."
		else:
			conn_dot.color = Color(1.0, 0.3, 0.3)  # Red
			conn_label.text = "Offline"
			conn_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
			conn_label.tooltip_text = "Not connected to server"


func _show_save_default_confirmation() -> void:
	"""Show confirmation modal for Save as Default"""
	if not OnlineManager:
		_set_save_status("error", "OnlineManager not available")
		return

	if not OnlineManager.is_online:
		_set_save_status("error", "Not connected to server")
		return

	if not confirmation_modal:
		_create_confirmation_modal()

	confirmation_modal.visible = true


func _create_confirmation_modal() -> void:
	"""Create the admin confirmation modal"""
	confirmation_modal = Control.new()
	confirmation_modal.name = "ConfirmationModal"
	confirmation_modal.visible = false
	confirmation_modal.z_index = 200  # Above other UI
	confirmation_modal.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Darken background
	var bg_darken = ColorRect.new()
	bg_darken.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_darken.color = Color(0, 0, 0, 0.7)
	bg_darken.mouse_filter = Control.MOUSE_FILTER_STOP
	confirmation_modal.add_child(bg_darken)

	# Modal panel - centered
	var modal_panel = Panel.new()
	modal_panel.add_theme_stylebox_override("panel", _create_panel_style(true))
	modal_panel.custom_minimum_size = Vector2(420, 220)
	modal_panel.set_anchors_preset(Control.PRESET_CENTER)
	modal_panel.offset_left = -210
	modal_panel.offset_right = 210
	modal_panel.offset_top = -110
	modal_panel.offset_bottom = 110
	confirmation_modal.add_child(modal_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 24
	vbox.offset_right = -24
	vbox.offset_top = 20
	vbox.offset_bottom = -20
	vbox.add_theme_constant_override("separation", 12)
	modal_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "SAVE AS DEFAULT"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", THEME_WARNING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Warning message
	var message = Label.new()
	message.text = "This will save the current scene layout as the default\nfor ALL new players. This action cannot be undone.\n\nAre you sure you want to continue?"
	message.add_theme_font_size_override("font_size", 11)
	message.add_theme_color_override("font_color", THEME_TEXT)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(message)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Buttons
	var btn_box = HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 20)
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_box)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 36)
	cancel_btn.add_theme_stylebox_override("normal", _create_button_style(THEME_BG_SURFACE))
	cancel_btn.add_theme_stylebox_override("hover", _create_button_style(THEME_BG_HOVER))
	cancel_btn.add_theme_stylebox_override("pressed", _create_button_style(THEME_BG_ACTIVE))
	cancel_btn.add_theme_color_override("font_color", THEME_TEXT)
	cancel_btn.pressed.connect(_close_confirmation_modal)
	btn_box.add_child(cancel_btn)

	var confirm_btn = Button.new()
	confirm_btn.text = "Save Default"
	confirm_btn.custom_minimum_size = Vector2(120, 36)
	confirm_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.6, 0.3, 0.1)))
	confirm_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.8, 0.4, 0.1)))
	confirm_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.5, 0.25, 0.05)))
	confirm_btn.add_theme_color_override("font_color", THEME_WARNING)
	confirm_btn.pressed.connect(_confirm_save_default)
	btn_box.add_child(confirm_btn)

	overlay.add_child(confirmation_modal)


func _close_confirmation_modal() -> void:
	"""Close the confirmation modal"""
	if confirmation_modal:
		confirmation_modal.visible = false


func _confirm_save_default() -> void:
	"""Actually save as default after confirmation"""
	_close_confirmation_modal()

	if OnlineManager and OnlineManager.is_websocket_connected():
		# Use WebSocket
		var config = get_scene_config()
		OnlineManager._ws_send({
			"type": "scene_save_default",
			"admin_key": admin_key,
			"config": config
		})
		_set_save_status("saving", "Saving as default...")
	else:
		# Fallback to HTTP
		_save_to_default()


func _save_to_default() -> void:
	if not OnlineManager:
		_set_save_status("error", "OnlineManager not available")
		return

	if not OnlineManager.is_online:
		_set_save_status("error", "Not connected to server")
		return

	_set_save_status("saving", "Saving as default...")

	var config = get_scene_config()
	var body = JSON.stringify({
		"admin_key": admin_key,
		"config": config
	})

	var headers = ["Content-Type: application/json"]

	var url = OnlineManager.server_url + "/scene/save-default"
	var error = _http_save_default.request(url, headers, HTTPClient.METHOD_POST, body)

	if error != OK:
		_set_save_status("error", "Failed to send save request")
		print("[EditMode] Save to default request failed: %d" % error)


func _load_from_session() -> void:
	if not OnlineManager:
		_set_save_status("error", "OnlineManager not available")
		return

	if not OnlineManager.is_online:
		_set_save_status("error", "Not connected to server")
		return

	if OnlineManager.session_token.is_empty():
		_set_save_status("error", "No session - please register first")
		return

	_set_save_status("saving", "Loading configuration...")

	var headers = ["X-Session-Token: " + OnlineManager.session_token]
	var url = OnlineManager.server_url + "/scene/load/" + OnlineManager.session_token

	var error = _http_load_config.request(url, headers, HTTPClient.METHOD_GET)

	if error != OK:
		_set_save_status("error", "Failed to send load request")
		print("[EditMode] Load config request failed: %d" % error)


func _load_default_config() -> void:
	"""Load master default config (no session required)"""
	if not OnlineManager:
		return

	if not OnlineManager.is_online:
		print("[EditMode] Offline, cannot load default config")
		return

	var url = OnlineManager.server_url + "/scene/default"
	var error = _http_load_config.request(url, [], HTTPClient.METHOD_GET)

	if error != OK:
		print("[EditMode] Load default config request failed: %d" % error)


func _set_save_status(status: String, message: String = "") -> void:
	_save_status = status
	_save_message = message
	_status_timer = 0.0
	_update_status_bar()


func _on_save_session_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_save_status("error", "Connection failed")
		print("[EditMode] Save to session failed: result=%d" % result)
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_set_save_status("error", "Invalid server response")
		return

	var data = json.data if json.data is Dictionary else {}

	if response_code == 200 and data.get("success", false):
		_set_save_status("success", "Session config saved!")
		print("[EditMode] Session configuration saved successfully")
	else:
		var error_msg = data.get("message", "Save failed")
		_set_save_status("error", error_msg)
		print("[EditMode] Save to session failed: %s" % error_msg)


func _on_save_default_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_save_status("error", "Connection failed")
		print("[EditMode] Save to default failed: result=%d" % result)
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_set_save_status("error", "Invalid server response")
		return

	var data = json.data if json.data is Dictionary else {}

	if response_code == 200 and data.get("success", false):
		_set_save_status("success", "Default config saved for all players!")
		print("[EditMode] Default configuration saved successfully")
	elif response_code == 403:
		_set_save_status("error", "Invalid admin key")
		print("[EditMode] Save to default failed: invalid admin key")
	else:
		var error_msg = data.get("message", "Save failed")
		_set_save_status("error", error_msg)
		print("[EditMode] Save to default failed: %s" % error_msg)


func _on_load_config_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_save_status("error", "Connection failed")
		print("[EditMode] Load config failed: result=%d" % result)
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_set_save_status("error", "Invalid server response")
		return

	var data = json.data if json.data is Dictionary else {}

	if response_code == 200 and data.get("success", false):
		var config = data.get("config")
		if config and config is Dictionary and not config.is_empty():
			apply_scene_config(config)
			_initial_config_loaded = true
			var is_default = data.get("is_default", false)
			if is_default:
				_set_save_status("success", "Loaded default configuration")
			else:
				_set_save_status("success", "Loaded session configuration")
			print("[EditMode] Configuration loaded via HTTP (is_default=%s)" % is_default)
		else:
			_initial_config_loaded = true
			_set_save_status("success", "No saved configuration found")
			print("[EditMode] No saved configuration found (using scene defaults)")
	else:
		var error_msg = data.get("message", "Load failed")
		_set_save_status("error", error_msg)
		print("[EditMode] Load config failed: %s" % error_msg)


# ============================================================================
# ICON DRAWING INNER CLASS
# ============================================================================

class EditIcon extends Control:
	var icon_type: int = 0  # IconType enum value
	var icon_color: Color = Color(0.9, 0.95, 0.9, 1.0)
	var icon_size: float = 14.0
	var stroke_width: float = 1.5

	func _init(type: int = 0, color: Color = Color(0.9, 0.95, 0.9), sz: float = 14.0) -> void:
		icon_type = type
		icon_color = color
		icon_size = sz
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(sz + 4, sz + 4)

	func _draw() -> void:
		var center = size / 2
		var half = icon_size / 2

		match icon_type:
			1: _draw_undo(center, half)      # UNDO
			2: _draw_redo(center, half)      # REDO
			3: _draw_duplicate(center, half) # DUPLICATE
			4: _draw_delete(center, half)    # DELETE
			5: _draw_hide(center, half)      # HIDE
			6: _draw_show(center, half)      # SHOW
			7: _draw_chevron_up(center, half)    # MOVE_UP
			8: _draw_chevron_down(center, half)  # MOVE_DOWN
			9: _draw_double_chevron_up(center, half)   # BRING_FRONT
			10: _draw_double_chevron_down(center, half) # SEND_BACK
			11: _draw_expand(center, half)    # EXPAND
			12: _draw_collapse(center, half)  # COLLAPSE
			13: _draw_save(center, half)      # SAVE
			14: _draw_check(center, half)     # CHECK
			15: _draw_cross(center, half)     # CROSS
			16: _draw_align_left(center, half)
			17: _draw_align_center_h(center, half)
			18: _draw_align_right(center, half)
			19: _draw_align_top(center, half)
			20: _draw_align_center_v(center, half)
			21: _draw_align_bottom(center, half)
			22: _draw_grid(center, half)
			23: _draw_snap(center, half)
			24: _draw_group(center, half)
			25: _draw_ungroup(center, half)
			26: _draw_folder(center, half)
			27: _draw_light_bulb(center, half)
			28: _draw_guide(center, half)

	func _draw_undo(center: Vector2, half: float) -> void:
		# Curved arrow pointing left
		var points: PackedVector2Array = []
		for i in range(9):
			var angle = PI * 0.2 + (i / 8.0) * PI * 0.9
			points.append(center + Vector2(cos(angle), sin(angle)) * half * 0.65)
		draw_polyline(points, icon_color, stroke_width, true)
		# Arrow head
		var tip = points[0]
		draw_line(tip, tip + Vector2(half * 0.35, half * 0.15), icon_color, stroke_width)
		draw_line(tip, tip + Vector2(half * 0.15, -half * 0.35), icon_color, stroke_width)

	func _draw_redo(center: Vector2, half: float) -> void:
		# Curved arrow pointing right
		var points: PackedVector2Array = []
		for i in range(9):
			var angle = PI * 0.8 - (i / 8.0) * PI * 0.9
			points.append(center + Vector2(cos(angle), sin(angle)) * half * 0.65)
		draw_polyline(points, icon_color, stroke_width, true)
		var tip = points[0]
		draw_line(tip, tip + Vector2(-half * 0.35, half * 0.15), icon_color, stroke_width)
		draw_line(tip, tip + Vector2(-half * 0.15, -half * 0.35), icon_color, stroke_width)

	func _draw_duplicate(center: Vector2, half: float) -> void:
		# Two overlapping rectangles
		var offset = half * 0.2
		# Back rectangle
		var back_rect = Rect2(center.x - half * 0.55 - offset, center.y - half * 0.55 - offset, half * 0.9, half * 0.9)
		draw_rect(back_rect, icon_color, false, stroke_width)
		# Front rectangle
		var front_rect = Rect2(center.x - half * 0.55 + offset, center.y - half * 0.55 + offset, half * 0.9, half * 0.9)
		draw_rect(front_rect, Color(icon_color.r * 0.3, icon_color.g * 0.3, icon_color.b * 0.3, 0.8), true)
		draw_rect(front_rect, icon_color, false, stroke_width)

	func _draw_delete(center: Vector2, half: float) -> void:
		# Trash can
		var w = half * 0.7
		var h = half * 0.85
		# Lid
		draw_line(center + Vector2(-w, -h * 0.4), center + Vector2(w, -h * 0.4), icon_color, stroke_width)
		# Handle
		draw_line(center + Vector2(-w * 0.3, -h * 0.4), center + Vector2(-w * 0.3, -h * 0.65), icon_color, stroke_width)
		draw_line(center + Vector2(-w * 0.3, -h * 0.65), center + Vector2(w * 0.3, -h * 0.65), icon_color, stroke_width)
		draw_line(center + Vector2(w * 0.3, -h * 0.65), center + Vector2(w * 0.3, -h * 0.4), icon_color, stroke_width)
		# Body
		draw_line(center + Vector2(-w * 0.8, -h * 0.3), center + Vector2(-w * 0.6, h * 0.65), icon_color, stroke_width)
		draw_line(center + Vector2(-w * 0.6, h * 0.65), center + Vector2(w * 0.6, h * 0.65), icon_color, stroke_width)
		draw_line(center + Vector2(w * 0.6, h * 0.65), center + Vector2(w * 0.8, -h * 0.3), icon_color, stroke_width)
		# Lines inside
		draw_line(center + Vector2(0, -h * 0.15), center + Vector2(0, h * 0.45), icon_color, stroke_width * 0.7)

	func _draw_hide(center: Vector2, half: float) -> void:
		# Eye with diagonal line through it
		_draw_eye_shape(center, half)
		# Diagonal slash
		draw_line(center + Vector2(-half * 0.7, half * 0.5), center + Vector2(half * 0.7, -half * 0.5), icon_color, stroke_width * 1.3)

	func _draw_show(center: Vector2, half: float) -> void:
		# Eye shape
		_draw_eye_shape(center, half)

	func _draw_eye_shape(center: Vector2, half: float) -> void:
		# Almond eye shape
		var points: PackedVector2Array = []
		for i in range(13):
			var t = i / 12.0
			var angle = t * PI * 2
			var rx = half * 0.75
			var ry = half * 0.35
			points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
		draw_polyline(points, icon_color, stroke_width, false)
		# Pupil
		draw_circle(center, half * 0.2, icon_color)

	func _draw_chevron_up(center: Vector2, half: float) -> void:
		draw_line(center + Vector2(-half * 0.5, half * 0.2), center + Vector2(0, -half * 0.3), icon_color, stroke_width)
		draw_line(center + Vector2(0, -half * 0.3), center + Vector2(half * 0.5, half * 0.2), icon_color, stroke_width)

	func _draw_chevron_down(center: Vector2, half: float) -> void:
		draw_line(center + Vector2(-half * 0.5, -half * 0.2), center + Vector2(0, half * 0.3), icon_color, stroke_width)
		draw_line(center + Vector2(0, half * 0.3), center + Vector2(half * 0.5, -half * 0.2), icon_color, stroke_width)

	func _draw_double_chevron_up(center: Vector2, half: float) -> void:
		_draw_chevron_up(center + Vector2(0, half * 0.2), half * 0.7)
		_draw_chevron_up(center + Vector2(0, -half * 0.2), half * 0.7)

	func _draw_double_chevron_down(center: Vector2, half: float) -> void:
		_draw_chevron_down(center + Vector2(0, -half * 0.2), half * 0.7)
		_draw_chevron_down(center + Vector2(0, half * 0.2), half * 0.7)

	func _draw_expand(center: Vector2, half: float) -> void:
		# Plus in a box
		var s = half * 0.6
		draw_rect(Rect2(center.x - s, center.y - s, s * 2, s * 2), icon_color, false, stroke_width)
		draw_line(center + Vector2(-s * 0.5, 0), center + Vector2(s * 0.5, 0), icon_color, stroke_width)
		draw_line(center + Vector2(0, -s * 0.5), center + Vector2(0, s * 0.5), icon_color, stroke_width)

	func _draw_collapse(center: Vector2, half: float) -> void:
		# Minus in a box
		var s = half * 0.6
		draw_rect(Rect2(center.x - s, center.y - s, s * 2, s * 2), icon_color, false, stroke_width)
		draw_line(center + Vector2(-s * 0.5, 0), center + Vector2(s * 0.5, 0), icon_color, stroke_width)

	func _draw_save(center: Vector2, half: float) -> void:
		# Floppy disk
		var s = half * 0.75
		draw_rect(Rect2(center.x - s, center.y - s, s * 2, s * 2), icon_color, false, stroke_width)
		# Metal slider
		draw_rect(Rect2(center.x - s * 0.35, center.y - s, s * 0.7, s * 0.5), icon_color, false, stroke_width)
		# Label
		draw_rect(Rect2(center.x - s * 0.6, center.y + s * 0.15, s * 1.2, s * 0.6), icon_color, false, stroke_width)

	func _draw_check(center: Vector2, half: float) -> void:
		draw_line(center + Vector2(-half * 0.5, 0), center + Vector2(-half * 0.1, half * 0.4), icon_color, stroke_width * 1.3)
		draw_line(center + Vector2(-half * 0.1, half * 0.4), center + Vector2(half * 0.5, -half * 0.4), icon_color, stroke_width * 1.3)

	func _draw_cross(center: Vector2, half: float) -> void:
		draw_line(center + Vector2(-half * 0.4, -half * 0.4), center + Vector2(half * 0.4, half * 0.4), icon_color, stroke_width * 1.3)
		draw_line(center + Vector2(half * 0.4, -half * 0.4), center + Vector2(-half * 0.4, half * 0.4), icon_color, stroke_width * 1.3)

	func _draw_align_left(center: Vector2, half: float) -> void:
		# Vertical bar on left + horizontal lines
		draw_line(center + Vector2(-half * 0.7, -half * 0.7), center + Vector2(-half * 0.7, half * 0.7), icon_color, stroke_width * 1.2)
		draw_line(center + Vector2(-half * 0.7, -half * 0.4), center + Vector2(half * 0.5, -half * 0.4), icon_color, stroke_width)
		draw_line(center + Vector2(-half * 0.7, half * 0.0), center + Vector2(half * 0.1, half * 0.0), icon_color, stroke_width)
		draw_line(center + Vector2(-half * 0.7, half * 0.4), center + Vector2(half * 0.7, half * 0.4), icon_color, stroke_width)

	func _draw_align_center_h(center: Vector2, half: float) -> void:
		draw_line(center + Vector2(0, -half * 0.7), center + Vector2(0, half * 0.7), icon_color, stroke_width * 1.2)
		draw_line(center + Vector2(-half * 0.6, -half * 0.4), center + Vector2(half * 0.6, -half * 0.4), icon_color, stroke_width)
		draw_line(center + Vector2(-half * 0.35, half * 0.0), center + Vector2(half * 0.35, half * 0.0), icon_color, stroke_width)
		draw_line(center + Vector2(-half * 0.5, half * 0.4), center + Vector2(half * 0.5, half * 0.4), icon_color, stroke_width)

	func _draw_align_right(center: Vector2, half: float) -> void:
		draw_line(center + Vector2(half * 0.7, -half * 0.7), center + Vector2(half * 0.7, half * 0.7), icon_color, stroke_width * 1.2)
		draw_line(center + Vector2(-half * 0.5, -half * 0.4), center + Vector2(half * 0.7, -half * 0.4), icon_color, stroke_width)
		draw_line(center + Vector2(-half * 0.1, half * 0.0), center + Vector2(half * 0.7, half * 0.0), icon_color, stroke_width)
		draw_line(center + Vector2(-half * 0.7, half * 0.4), center + Vector2(half * 0.7, half * 0.4), icon_color, stroke_width)

	func _draw_align_top(center: Vector2, half: float) -> void:
		draw_line(center + Vector2(-half * 0.7, -half * 0.7), center + Vector2(half * 0.7, -half * 0.7), icon_color, stroke_width * 1.2)
		draw_line(center + Vector2(-half * 0.4, -half * 0.7), center + Vector2(-half * 0.4, half * 0.5), icon_color, stroke_width)
		draw_line(center + Vector2(0, -half * 0.7), center + Vector2(0, half * 0.1), icon_color, stroke_width)
		draw_line(center + Vector2(half * 0.4, -half * 0.7), center + Vector2(half * 0.4, half * 0.7), icon_color, stroke_width)

	func _draw_align_center_v(center: Vector2, half: float) -> void:
		draw_line(center + Vector2(-half * 0.7, 0), center + Vector2(half * 0.7, 0), icon_color, stroke_width * 1.2)
		draw_line(center + Vector2(-half * 0.4, -half * 0.6), center + Vector2(-half * 0.4, half * 0.6), icon_color, stroke_width)
		draw_line(center + Vector2(0, -half * 0.35), center + Vector2(0, half * 0.35), icon_color, stroke_width)
		draw_line(center + Vector2(half * 0.4, -half * 0.5), center + Vector2(half * 0.4, half * 0.5), icon_color, stroke_width)

	func _draw_align_bottom(center: Vector2, half: float) -> void:
		draw_line(center + Vector2(-half * 0.7, half * 0.7), center + Vector2(half * 0.7, half * 0.7), icon_color, stroke_width * 1.2)
		draw_line(center + Vector2(-half * 0.4, -half * 0.5), center + Vector2(-half * 0.4, half * 0.7), icon_color, stroke_width)
		draw_line(center + Vector2(0, -half * 0.1), center + Vector2(0, half * 0.7), icon_color, stroke_width)
		draw_line(center + Vector2(half * 0.4, -half * 0.7), center + Vector2(half * 0.4, half * 0.7), icon_color, stroke_width)

	func _draw_grid(center: Vector2, half: float) -> void:
		var s = half * 0.65
		for i in range(4):
			var offset = -s + i * (s * 2 / 3.0)
			draw_line(center + Vector2(offset, -s), center + Vector2(offset, s), icon_color, stroke_width * 0.8)
			draw_line(center + Vector2(-s, offset), center + Vector2(s, offset), icon_color, stroke_width * 0.8)

	func _draw_snap(center: Vector2, half: float) -> void:
		# Magnet shape
		var w = half * 0.6
		var h = half * 0.7
		# U-shape
		draw_line(center + Vector2(-w, -h * 0.7), center + Vector2(-w, h * 0.2), icon_color, stroke_width)
		draw_line(center + Vector2(w, -h * 0.7), center + Vector2(w, h * 0.2), icon_color, stroke_width)
		# Bottom arc
		var points: PackedVector2Array = []
		for i in range(9):
			var angle = PI + (i / 8.0) * PI
			points.append(center + Vector2(cos(angle) * w, h * 0.2 + sin(angle) * h * 0.5))
		draw_polyline(points, icon_color, stroke_width, false)
		# Poles
		draw_line(center + Vector2(-w - half * 0.15, -h * 0.5), center + Vector2(-w + half * 0.15, -h * 0.5), icon_color, stroke_width)
		draw_line(center + Vector2(w - half * 0.15, -h * 0.5), center + Vector2(w + half * 0.15, -h * 0.5), icon_color, stroke_width)

	func _draw_guide(center: Vector2, half: float) -> void:
		# Two crossing alignment lines with small endpoint marks (like Figma guides)
		var s = half * 0.75
		# Horizontal guide line
		draw_line(center + Vector2(-s, 0), center + Vector2(s, 0), icon_color, stroke_width)
		# Vertical guide line
		draw_line(center + Vector2(0, -s), center + Vector2(0, s), icon_color, stroke_width)
		# Small endpoint markers on horizontal line
		draw_line(center + Vector2(-s, -half * 0.15), center + Vector2(-s, half * 0.15), icon_color, stroke_width)
		draw_line(center + Vector2(s, -half * 0.15), center + Vector2(s, half * 0.15), icon_color, stroke_width)
		# Small endpoint markers on vertical line
		draw_line(center + Vector2(-half * 0.15, -s), center + Vector2(half * 0.15, -s), icon_color, stroke_width)
		draw_line(center + Vector2(-half * 0.15, s), center + Vector2(half * 0.15, s), icon_color, stroke_width)

	func _draw_group(center: Vector2, half: float) -> void:
		# Nested rectangles
		draw_rect(Rect2(center.x - half * 0.7, center.y - half * 0.7, half * 1.4, half * 1.4), icon_color, false, stroke_width)
		draw_rect(Rect2(center.x - half * 0.35, center.y - half * 0.35, half * 0.7, half * 0.7), icon_color, false, stroke_width)

	func _draw_ungroup(center: Vector2, half: float) -> void:
		# Separated rectangles
		draw_rect(Rect2(center.x - half * 0.7, center.y - half * 0.7, half * 0.6, half * 0.6), icon_color, false, stroke_width)
		draw_rect(Rect2(center.x + half * 0.1, center.y + half * 0.1, half * 0.6, half * 0.6), icon_color, false, stroke_width)

	func _draw_folder(center: Vector2, half: float) -> void:
		# Folder shape
		var w = half * 0.8
		var h = half * 0.6
		# Tab
		draw_line(center + Vector2(-w, -h * 0.6), center + Vector2(-w * 0.3, -h * 0.6), icon_color, stroke_width)
		draw_line(center + Vector2(-w * 0.3, -h * 0.6), center + Vector2(-w * 0.1, -h), icon_color, stroke_width)
		draw_line(center + Vector2(-w * 0.1, -h), center + Vector2(w * 0.2, -h), icon_color, stroke_width)
		draw_line(center + Vector2(w * 0.2, -h), center + Vector2(w * 0.35, -h * 0.6), icon_color, stroke_width)
		# Body
		draw_line(center + Vector2(w * 0.35, -h * 0.6), center + Vector2(w, -h * 0.6), icon_color, stroke_width)
		draw_line(center + Vector2(w, -h * 0.6), center + Vector2(w, h), icon_color, stroke_width)
		draw_line(center + Vector2(w, h), center + Vector2(-w, h), icon_color, stroke_width)
		draw_line(center + Vector2(-w, h), center + Vector2(-w, -h * 0.6), icon_color, stroke_width)

	func _draw_light_bulb(center: Vector2, half: float) -> void:
		# Bulb shape (circle with base)
		draw_arc(center + Vector2(0, -half * 0.15), half * 0.5, 0, TAU, 16, icon_color, stroke_width)
		# Base
		draw_line(center + Vector2(-half * 0.25, half * 0.35), center + Vector2(half * 0.25, half * 0.35), icon_color, stroke_width)
		draw_line(center + Vector2(-half * 0.2, half * 0.5), center + Vector2(half * 0.2, half * 0.5), icon_color, stroke_width)
		draw_line(center + Vector2(-half * 0.15, half * 0.65), center + Vector2(half * 0.15, half * 0.65), icon_color, stroke_width)
		# Filament
		draw_line(center + Vector2(0, half * 0.0), center + Vector2(0, half * 0.2), icon_color, stroke_width * 0.7)
