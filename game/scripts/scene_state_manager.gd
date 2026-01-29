extends Node
class_name SceneStateManager

## Scene State Manager - Saves and loads scene layouts as JSON
##
## This manager:
## - Serializes current scene elements to JSON state
## - Loads scene state and instantiates assets via AssetLibrary
## - Handles scene persistence (local + server sync)
## - Manages undo/redo for scene modifications

signal scene_loaded(scene_id: String)
signal scene_saved(scene_id: String)
signal scene_modified
signal element_added(element_id: String, node: Node)
signal element_removed(element_id: String)

const DEFAULT_SCENE_PATH = "res://data/scenes/default_desk.json"
const USER_SCENES_PATH = "user://scenes/"
const SERVER_SYNC_ENABLED = true

# Scene state structure
var current_scene: Dictionary = {
	"scene_id": "",
	"name": "Untitled",
	"author": "local",
	"created_at": "",
	"modified_at": "",
	"elements": [],
	"background": {}
}

# Runtime tracking
var scene_elements: Dictionary = {}  # instance_id -> Node
var asset_library: AssetLibrary
var scene_root: Node
var is_dirty: bool = false

# Undo/redo
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
const MAX_UNDO_STEPS = 50


func _ready() -> void:
	# Find or create AssetLibrary
	asset_library = get_node_or_null("/root/AssetLibrary")
	if not asset_library:
		asset_library = AssetLibrary.new()
		asset_library.name = "AssetLibrary"
		get_tree().root.call_deferred("add_child", asset_library)


func initialize(root: Node) -> void:
	"""Initialize with a scene root node"""
	scene_root = root
	print("[SceneStateManager] Initialized with root: " + root.name)


# =============================================================================
# SCENE LOADING
# =============================================================================

func load_scene(scene_path: String) -> bool:
	"""Load a scene from JSON file"""
	var file_path = scene_path
	if not file_path.begins_with("res://") and not file_path.begins_with("user://"):
		file_path = USER_SCENES_PATH + scene_path + ".json"

	if not FileAccess.file_exists(file_path):
		push_error("[SceneStateManager] Scene not found: " + file_path)
		return false

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("[SceneStateManager] Failed to open scene: " + file_path)
		return false

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_error("[SceneStateManager] JSON parse error: " + json.get_error_message())
		return false

	return load_scene_state(json.data)


func load_scene_state(state: Dictionary) -> bool:
	"""Load scene from state dictionary"""
	if not scene_root:
		push_error("[SceneStateManager] No scene root set")
		return false

	# Clear existing elements
	_clear_scene()

	# Store state
	current_scene = state.duplicate(true)

	# Instantiate elements
	var elements = state.get("elements", [])
	for element_data in elements:
		var node = _instantiate_element(element_data)
		if node:
			scene_root.add_child(node)
			var instance_id = element_data.get("instance_id", "")
			scene_elements[instance_id] = node
			element_added.emit(instance_id, node)

	is_dirty = false
	scene_loaded.emit(current_scene.get("scene_id", ""))
	print("[SceneStateManager] Loaded scene: %s with %d elements" % [
		current_scene.get("name", "?"),
		scene_elements.size()
	])

	return true


func _instantiate_element(element_data: Dictionary) -> Node:
	"""Create a node from element data"""
	var asset_id = element_data.get("asset_id", "")
	if asset_id.is_empty():
		return null

	if not asset_library:
		push_error("[SceneStateManager] AssetLibrary not available")
		return null

	# Get config from element data
	var config = element_data.get("config", {})

	# Instantiate via AssetLibrary
	var node = asset_library.instantiate_asset(asset_id, config)
	if not node:
		push_warning("[SceneStateManager] Failed to instantiate: " + asset_id)
		return null

	# Apply transform
	var instance_id = element_data.get("instance_id", asset_id + "_" + str(Time.get_ticks_msec()))
	node.name = instance_id

	var pos = element_data.get("position", [0, 0])
	if node is Control:
		node.position = Vector2(pos[0], pos[1])
	elif node is Node2D:
		node.position = Vector2(pos[0], pos[1])

	var scale_val = element_data.get("scale", [1, 1])
	if node is Control:
		node.scale = Vector2(scale_val[0], scale_val[1])
	elif node is Node2D:
		node.scale = Vector2(scale_val[0], scale_val[1])

	if node is Control or node is Node2D:
		node.rotation = element_data.get("rotation", 0.0)

	if node is CanvasItem:
		node.z_index = element_data.get("z_index", 0)
		node.visible = element_data.get("visible", true)
		node.modulate.a = element_data.get("opacity", 1.0)

	# Store instance_id as metadata
	node.set_meta("instance_id", instance_id)
	node.set_meta("asset_id", asset_id)

	return node


func _clear_scene() -> void:
	"""Remove all dynamic scene elements"""
	for instance_id in scene_elements:
		var node = scene_elements[instance_id]
		if is_instance_valid(node):
			node.queue_free()
	scene_elements.clear()


# =============================================================================
# SCENE SAVING
# =============================================================================

func save_scene(scene_path: String = "") -> bool:
	"""Save current scene to JSON file"""
	_serialize_current_state()

	var file_path = scene_path
	if file_path.is_empty():
		file_path = USER_SCENES_PATH + current_scene.get("scene_id", "untitled") + ".json"

	if not file_path.begins_with("res://") and not file_path.begins_with("user://"):
		file_path = USER_SCENES_PATH + file_path
		if not file_path.ends_with(".json"):
			file_path += ".json"

	# Ensure directory exists
	var dir_path = file_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("[SceneStateManager] Failed to save scene: " + file_path)
		return false

	current_scene["modified_at"] = Time.get_datetime_string_from_system()

	file.store_string(JSON.stringify(current_scene, "\t"))
	file.close()

	is_dirty = false
	scene_saved.emit(current_scene.get("scene_id", ""))
	print("[SceneStateManager] Saved scene to: " + file_path)

	return true


func _serialize_current_state() -> void:
	"""Update current_scene with actual node states"""
	var elements: Array = []

	for instance_id in scene_elements:
		var node = scene_elements[instance_id]
		if not is_instance_valid(node):
			continue

		var element_data = _serialize_element(node)
		if not element_data.is_empty():
			elements.append(element_data)

	current_scene["elements"] = elements


func _serialize_element(node: Node) -> Dictionary:
	"""Serialize a single element to dictionary"""
	var asset_id = node.get_meta("asset_id", "")
	var instance_id = node.get_meta("instance_id", node.name)

	if asset_id.is_empty():
		return {}

	var data: Dictionary = {
		"asset_id": asset_id,
		"instance_id": instance_id
	}

	# Position
	if node is Control or node is Node2D:
		data["position"] = [node.position.x, node.position.y]
		data["scale"] = [node.scale.x, node.scale.y]
		data["rotation"] = node.rotation

	# Canvas properties
	if node is CanvasItem:
		data["z_index"] = node.z_index
		data["visible"] = node.visible
		data["opacity"] = node.modulate.a

	# Custom config (if asset has config properties)
	var asset_def = node.get_meta("asset_def", {})
	var schema = asset_def.get("config_schema", {})
	if not schema.is_empty():
		var config: Dictionary = {}
		for key in schema:
			if key in node:
				config[key] = node.get(key)
		if not config.is_empty():
			data["config"] = config

	return data


func get_scene_state() -> Dictionary:
	"""Get current scene state as dictionary"""
	_serialize_current_state()
	return current_scene.duplicate(true)


# =============================================================================
# ELEMENT MANAGEMENT
# =============================================================================

func add_element(asset_id: String, position: Vector2 = Vector2.ZERO, config: Dictionary = {}) -> Node:
	"""Add a new element to the scene"""
	if not scene_root or not asset_library:
		return null

	# Check singleton constraint
	if asset_library.is_singleton(asset_id):
		for id in scene_elements:
			var node = scene_elements[id]
			if is_instance_valid(node) and node.get_meta("asset_id", "") == asset_id:
				push_warning("[SceneStateManager] Singleton asset already in scene: " + asset_id)
				return null

	# Check dependencies
	var deps = asset_library.get_dependencies(asset_id)
	for dep_id in deps:
		var dep_exists = false
		for id in scene_elements:
			var node = scene_elements[id]
			if is_instance_valid(node) and node.get_meta("asset_id", "") == dep_id:
				dep_exists = true
				break
		if not dep_exists:
			# Auto-add dependency
			print("[SceneStateManager] Auto-adding dependency: " + dep_id)
			add_element(dep_id, Vector2.ZERO, {})

	var node = asset_library.instantiate_asset(asset_id, config)
	if not node:
		return null

	var instance_id = asset_id + "_" + str(Time.get_ticks_msec())
	node.name = instance_id
	node.set_meta("instance_id", instance_id)
	node.set_meta("asset_id", asset_id)

	if node is Control or node is Node2D:
		node.position = position

	scene_root.add_child(node)
	scene_elements[instance_id] = node

	# Record for undo
	_push_undo({
		"action": "add",
		"instance_id": instance_id,
		"asset_id": asset_id,
		"position": [position.x, position.y],
		"config": config
	})

	_mark_dirty()
	element_added.emit(instance_id, node)

	return node


func remove_element(instance_id: String) -> bool:
	"""Remove an element from the scene"""
	if not scene_elements.has(instance_id):
		return false

	var node = scene_elements[instance_id]
	if not is_instance_valid(node):
		scene_elements.erase(instance_id)
		return false

	# Check if required
	var asset_id = node.get_meta("asset_id", "")
	if asset_library and asset_library.is_required(asset_id):
		push_warning("[SceneStateManager] Cannot remove required asset: " + asset_id)
		return false

	# Record for undo
	_push_undo({
		"action": "remove",
		"instance_id": instance_id,
		"element_data": _serialize_element(node)
	})

	scene_elements.erase(instance_id)
	node.queue_free()

	_mark_dirty()
	element_removed.emit(instance_id)

	return true


func get_element(instance_id: String) -> Node:
	"""Get an element by instance ID"""
	if scene_elements.has(instance_id):
		var node = scene_elements[instance_id]
		if is_instance_valid(node):
			return node
	return null


func get_all_elements() -> Dictionary:
	"""Get all scene elements"""
	var valid: Dictionary = {}
	for id in scene_elements:
		if is_instance_valid(scene_elements[id]):
			valid[id] = scene_elements[id]
	return valid


func update_element(instance_id: String, properties: Dictionary) -> bool:
	"""Update element properties"""
	var node = get_element(instance_id)
	if not node:
		return false

	# Record for undo
	var old_state = _serialize_element(node)

	# Apply properties
	for key in properties:
		match key:
			"position":
				var pos = properties[key]
				if node is Control or node is Node2D:
					node.position = Vector2(pos[0], pos[1]) if pos is Array else pos
			"scale":
				var s = properties[key]
				if node is Control or node is Node2D:
					node.scale = Vector2(s[0], s[1]) if s is Array else s
			"rotation":
				if node is Control or node is Node2D:
					node.rotation = properties[key]
			"z_index":
				if node is CanvasItem:
					node.z_index = properties[key]
			"visible":
				if node is CanvasItem:
					node.visible = properties[key]
			"opacity":
				if node is CanvasItem:
					node.modulate.a = properties[key]

	_push_undo({
		"action": "update",
		"instance_id": instance_id,
		"old_state": old_state,
		"new_state": _serialize_element(node)
	})

	_mark_dirty()
	return true


# =============================================================================
# UNDO/REDO
# =============================================================================

func _push_undo(action: Dictionary) -> void:
	undo_stack.append(action)
	if undo_stack.size() > MAX_UNDO_STEPS:
		undo_stack.pop_front()
	redo_stack.clear()


func undo() -> bool:
	if undo_stack.is_empty():
		return false

	var action = undo_stack.pop_back()
	redo_stack.append(action)

	match action.get("action"):
		"add":
			# Undo add = remove
			var instance_id = action.get("instance_id", "")
			if scene_elements.has(instance_id):
				var node = scene_elements[instance_id]
				if is_instance_valid(node):
					node.queue_free()
				scene_elements.erase(instance_id)
				element_removed.emit(instance_id)

		"remove":
			# Undo remove = add back
			var element_data = action.get("element_data", {})
			var node = _instantiate_element(element_data)
			if node and scene_root:
				scene_root.add_child(node)
				var instance_id = element_data.get("instance_id", "")
				scene_elements[instance_id] = node
				element_added.emit(instance_id, node)

		"update":
			# Undo update = restore old state
			var instance_id = action.get("instance_id", "")
			var old_state = action.get("old_state", {})
			var node = get_element(instance_id)
			if node:
				_apply_element_state(node, old_state)

	_mark_dirty()
	return true


func redo() -> bool:
	if redo_stack.is_empty():
		return false

	var action = redo_stack.pop_back()
	undo_stack.append(action)

	match action.get("action"):
		"add":
			# Redo add
			var asset_id = action.get("asset_id", "")
			var pos = action.get("position", [0, 0])
			var config = action.get("config", {})
			var instance_id = action.get("instance_id", "")

			var node = asset_library.instantiate_asset(asset_id, config)
			if node and scene_root:
				node.name = instance_id
				node.set_meta("instance_id", instance_id)
				node.set_meta("asset_id", asset_id)
				if node is Control or node is Node2D:
					node.position = Vector2(pos[0], pos[1])
				scene_root.add_child(node)
				scene_elements[instance_id] = node
				element_added.emit(instance_id, node)

		"remove":
			# Redo remove
			var element_data = action.get("element_data", {})
			var instance_id = element_data.get("instance_id", "")
			if scene_elements.has(instance_id):
				var node = scene_elements[instance_id]
				if is_instance_valid(node):
					node.queue_free()
				scene_elements.erase(instance_id)
				element_removed.emit(instance_id)

		"update":
			# Redo update = apply new state
			var instance_id = action.get("instance_id", "")
			var new_state = action.get("new_state", {})
			var node = get_element(instance_id)
			if node:
				_apply_element_state(node, new_state)

	_mark_dirty()
	return true


func _apply_element_state(node: Node, state: Dictionary) -> void:
	"""Apply serialized state to a node"""
	if state.has("position"):
		var pos = state["position"]
		if node is Control or node is Node2D:
			node.position = Vector2(pos[0], pos[1])

	if state.has("scale"):
		var s = state["scale"]
		if node is Control or node is Node2D:
			node.scale = Vector2(s[0], s[1])

	if state.has("rotation"):
		if node is Control or node is Node2D:
			node.rotation = state["rotation"]

	if state.has("z_index") and node is CanvasItem:
		node.z_index = state["z_index"]

	if state.has("visible") and node is CanvasItem:
		node.visible = state["visible"]

	if state.has("opacity") and node is CanvasItem:
		node.modulate.a = state["opacity"]


func can_undo() -> bool:
	return not undo_stack.is_empty()


func can_redo() -> bool:
	return not redo_stack.is_empty()


# =============================================================================
# UTILITY
# =============================================================================

func _mark_dirty() -> void:
	is_dirty = true
	scene_modified.emit()


func is_scene_dirty() -> bool:
	return is_dirty


func create_new_scene(name: String = "New Scene") -> void:
	"""Create a blank scene"""
	_clear_scene()

	current_scene = {
		"scene_id": "scene_" + str(Time.get_unix_time_from_system()),
		"name": name,
		"author": "local",
		"created_at": Time.get_datetime_string_from_system(),
		"modified_at": Time.get_datetime_string_from_system(),
		"elements": [],
		"background": {}
	}

	undo_stack.clear()
	redo_stack.clear()
	is_dirty = false

	scene_loaded.emit(current_scene.get("scene_id", ""))


func list_saved_scenes() -> Array[Dictionary]:
	"""List all saved scenes in user directory"""
	var scenes: Array[Dictionary] = []

	var dir = DirAccess.open(USER_SCENES_PATH)
	if not dir:
		return scenes

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var path = USER_SCENES_PATH + file_name
			var file = FileAccess.open(path, FileAccess.READ)
			if file:
				var json = JSON.new()
				if json.parse(file.get_as_text()) == OK:
					var data = json.data
					scenes.append({
						"path": path,
						"scene_id": data.get("scene_id", ""),
						"name": data.get("name", file_name),
						"modified_at": data.get("modified_at", "")
					})
				file.close()
		file_name = dir.get_next()
	dir.list_dir_end()

	return scenes
