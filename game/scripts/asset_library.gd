extends Node
class_name AssetLibrary

## Asset Library - Manages asset manifest and dynamic asset loading
##
## This singleton provides:
## - Asset manifest loading and querying
## - Dynamic asset instantiation
## - Custom/AI-generated asset registration
## - Asset dependency resolution

signal manifest_loaded
signal asset_registered(asset_id: String)
signal asset_instantiated(asset_id: String, instance: Node)

const MANIFEST_PATH = "res://data/asset_manifest.json"
const USER_ASSETS_PATH = "user://custom_assets/"
const USER_MANIFEST_PATH = "user://custom_assets/manifest.json"

# Asset types
enum AssetType {
	TEXTURE,      # Simple TextureRect
	COMPOSITE,    # Complex node with script/children
	PROCEDURAL,   # Generated at runtime (shaders, etc.)
	SCENE         # Full .tscn scene file
}

# Loaded manifest data
var manifest: Dictionary = {}
var categories: Dictionary = {}
var assets: Dictionary = {}
var ai_config: Dictionary = {}

# Runtime caches
var loaded_textures: Dictionary = {}  # asset_id -> Texture2D
var loaded_scenes: Dictionary = {}    # asset_id -> PackedScene
var custom_assets: Dictionary = {}    # user-added assets

# Singleton instances (for singleton assets)
var singleton_instances: Dictionary = {}  # asset_id -> Node

var _initialized: bool = false


func _ready() -> void:
	_load_manifest()
	_load_custom_assets()


func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_error("[AssetLibrary] Manifest not found: " + MANIFEST_PATH)
		return

	var file = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if not file:
		push_error("[AssetLibrary] Failed to open manifest: " + str(FileAccess.get_open_error()))
		return

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_error("[AssetLibrary] JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return

	manifest = json.data
	categories = manifest.get("categories", {})
	assets = manifest.get("assets", {})
	ai_config = manifest.get("ai_generation", {})

	_initialized = true
	print("[AssetLibrary] Loaded manifest v%s with %d assets in %d categories" % [
		manifest.get("version", "?"),
		assets.size(),
		categories.size()
	])

	manifest_loaded.emit()


func _load_custom_assets() -> void:
	"""Load user's custom/AI-generated assets from user:// directory"""
	if not FileAccess.file_exists(USER_MANIFEST_PATH):
		return

	var file = FileAccess.open(USER_MANIFEST_PATH, FileAccess.READ)
	if not file:
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		custom_assets = json.data.get("assets", {})
		print("[AssetLibrary] Loaded %d custom assets" % custom_assets.size())
	file.close()


func save_custom_assets() -> void:
	"""Save custom assets manifest to user:// directory"""
	DirAccess.make_dir_recursive_absolute(USER_ASSETS_PATH)

	var file = FileAccess.open(USER_MANIFEST_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"version": "1.0.0",
			"assets": custom_assets
		}
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


# =============================================================================
# PUBLIC API - Asset Queries
# =============================================================================

func is_initialized() -> bool:
	return _initialized


func get_asset_def(asset_id: String) -> Dictionary:
	"""Get asset definition by ID"""
	if assets.has(asset_id):
		return assets[asset_id]
	if custom_assets.has(asset_id):
		return custom_assets[asset_id]
	return {}


func get_all_assets() -> Dictionary:
	"""Get all assets (built-in + custom)"""
	var all = assets.duplicate(true)
	all.merge(custom_assets)
	return all


func get_assets_by_category(category: String) -> Array[Dictionary]:
	"""Get all assets in a category"""
	var results: Array[Dictionary] = []
	for id in assets:
		if assets[id].get("category") == category:
			results.append(assets[id])
	for id in custom_assets:
		if custom_assets[id].get("category") == category:
			results.append(custom_assets[id])
	return results


func get_categories() -> Dictionary:
	return categories


func search_assets(query: String, tags: Array = []) -> Array[Dictionary]:
	"""Search assets by name or tags"""
	var results: Array[Dictionary] = []
	var query_lower = query.to_lower()

	var all_assets = get_all_assets()
	for id in all_assets:
		var asset = all_assets[id]
		var matches = false

		# Check name
		if asset.get("name", "").to_lower().contains(query_lower):
			matches = true

		# Check description
		if asset.get("description", "").to_lower().contains(query_lower):
			matches = true

		# Check tags
		var asset_tags = asset.get("tags", [])
		if tags.size() > 0:
			for tag in tags:
				if tag in asset_tags:
					matches = true
					break
		elif query_lower != "":
			for tag in asset_tags:
				if tag.to_lower().contains(query_lower):
					matches = true
					break

		if matches:
			results.append(asset)

	return results


func is_singleton(asset_id: String) -> bool:
	"""Check if asset is a singleton (only one instance allowed)"""
	var asset = get_asset_def(asset_id)
	return asset.get("singleton", false)


func is_required(asset_id: String) -> bool:
	"""Check if asset is required (cannot be removed)"""
	var asset = get_asset_def(asset_id)
	return asset.get("required", false)


func get_dependencies(asset_id: String) -> Array:
	"""Get asset dependencies (other assets that must exist)"""
	var asset = get_asset_def(asset_id)
	return asset.get("dependencies", [])


# =============================================================================
# PUBLIC API - Asset Instantiation
# =============================================================================

func instantiate_asset(asset_id: String, config: Dictionary = {}) -> Node:
	"""Create a new instance of an asset"""
	var asset_def = get_asset_def(asset_id)
	if asset_def.is_empty():
		push_error("[AssetLibrary] Unknown asset: " + asset_id)
		return null

	# Check singleton constraint
	if asset_def.get("singleton", false):
		if singleton_instances.has(asset_id) and is_instance_valid(singleton_instances[asset_id]):
			push_warning("[AssetLibrary] Singleton asset already exists: " + asset_id)
			return singleton_instances[asset_id]

	var instance: Node = null
	var asset_type = asset_def.get("type", "texture")

	match asset_type:
		"texture":
			instance = _create_texture_asset(asset_def, config)
		"composite":
			instance = _create_composite_asset(asset_def, config)
		"procedural":
			instance = _create_procedural_asset(asset_def, config)
		"scene":
			instance = _create_scene_asset(asset_def, config)
		_:
			push_error("[AssetLibrary] Unknown asset type: " + asset_type)
			return null

	if instance:
		instance.set_meta("asset_id", asset_id)
		instance.set_meta("asset_def", asset_def)

		if asset_def.get("singleton", false):
			singleton_instances[asset_id] = instance

		asset_instantiated.emit(asset_id, instance)

	return instance


func _create_texture_asset(asset_def: Dictionary, config: Dictionary) -> Node:
	"""Create a simple texture-based asset"""
	var texture_path = asset_def.get("texture_path", "")
	if texture_path.is_empty():
		push_error("[AssetLibrary] No texture_path for asset: " + asset_def.get("id", "?"))
		return null

	# Load texture (with caching)
	var texture: Texture2D
	if loaded_textures.has(texture_path):
		texture = loaded_textures[texture_path]
	else:
		if texture_path.begins_with("user://"):
			# User asset - load from file
			var image = Image.load_from_file(texture_path)
			if image:
				texture = ImageTexture.create_from_image(image)
		else:
			# Built-in asset
			texture = load(texture_path)

		if texture:
			loaded_textures[texture_path] = texture

	if not texture:
		push_error("[AssetLibrary] Failed to load texture: " + texture_path)
		return null

	var tex_rect = TextureRect.new()
	tex_rect.name = asset_def.get("id", "Asset")
	tex_rect.texture = texture
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Apply default size
	var default_size = asset_def.get("default_size", [100, 100])
	tex_rect.custom_minimum_size = Vector2(default_size[0], default_size[1])
	tex_rect.size = tex_rect.custom_minimum_size

	return tex_rect


func _create_composite_asset(asset_def: Dictionary, config: Dictionary) -> Node:
	"""Create a composite asset (texture + script + children)"""
	var root: Node

	# If has texture, start with TextureRect
	var texture_path = asset_def.get("texture_path", "")
	if not texture_path.is_empty():
		root = _create_texture_asset(asset_def, config)
		if not root:
			return null
	else:
		# No texture, use Control as root
		root = Control.new()
		root.name = asset_def.get("id", "Asset")

		var default_size = asset_def.get("default_size", [100, 100])
		root.custom_minimum_size = Vector2(default_size[0], default_size[1])
		root.size = root.custom_minimum_size

	# Attach script if specified
	var script_path = asset_def.get("script", "")
	if not script_path.is_empty():
		var script = load(script_path)
		if script:
			root.set_script(script)
		else:
			push_warning("[AssetLibrary] Failed to load script: " + script_path)

	# Apply config
	_apply_asset_config(root, asset_def, config)

	return root


func _create_procedural_asset(asset_def: Dictionary, config: Dictionary) -> Node:
	"""Create a procedurally generated asset (shaders, etc.)"""
	var asset_id = asset_def.get("id", "")

	# Handle specific procedural assets
	match asset_id:
		"wood_shelf":
			return _create_wood_shelf(asset_def, config)
		"desk":
			return _create_desk(asset_def, config)
		_:
			# Generic procedural - just a colored rect
			var rect = ColorRect.new()
			rect.name = asset_id
			var default_size = asset_def.get("default_size", [100, 100])
			rect.custom_minimum_size = Vector2(default_size[0], default_size[1])
			rect.size = rect.custom_minimum_size
			rect.color = Color(0.5, 0.5, 0.5)
			return rect


func _create_scene_asset(asset_def: Dictionary, config: Dictionary) -> Node:
	"""Create an asset from a .tscn scene file"""
	var scene_path = asset_def.get("scene_path", "")
	if scene_path.is_empty():
		push_error("[AssetLibrary] No scene_path for asset: " + asset_def.get("id", "?"))
		return null

	var scene: PackedScene
	if loaded_scenes.has(scene_path):
		scene = loaded_scenes[scene_path]
	else:
		scene = load(scene_path)
		if scene:
			loaded_scenes[scene_path] = scene

	if not scene:
		push_error("[AssetLibrary] Failed to load scene: " + scene_path)
		return null

	var instance = scene.instantiate()
	_apply_asset_config(instance, asset_def, config)

	return instance


func _create_wood_shelf(asset_def: Dictionary, config: Dictionary) -> Control:
	"""Create a wood shelf procedurally"""
	var shelf = Control.new()
	shelf.name = "WoodShelf"

	var default_size = asset_def.get("default_size", [350, 18])
	shelf.custom_minimum_size = Vector2(default_size[0], default_size[1])
	shelf.size = shelf.custom_minimum_size

	var schema = asset_def.get("config_schema", {})
	var wood_color = _get_config_color(config, schema, "wood_color", Color(0.35, 0.22, 0.12))
	var highlight_color = _get_config_color(config, schema, "highlight_color", Color(0.48, 0.32, 0.2))
	var shadow_color = wood_color.darkened(0.4)

	# Main shelf body
	var body = ColorRect.new()
	body.name = "Body"
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.color = wood_color
	shelf.add_child(body)

	# Top highlight
	var edge = ColorRect.new()
	edge.name = "Edge"
	edge.set_anchors_preset(Control.PRESET_TOP_WIDE)
	edge.offset_bottom = 4
	edge.color = highlight_color
	shelf.add_child(edge)

	# Bottom shadow
	var bottom = ColorRect.new()
	bottom.name = "Bottom"
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -5
	bottom.offset_bottom = 5
	bottom.color = shadow_color
	shelf.add_child(bottom)

	return shelf


func _create_desk(asset_def: Dictionary, config: Dictionary) -> Panel:
	"""Create a desk surface procedurally"""
	var desk = Panel.new()
	desk.name = "Desk"

	var default_size = asset_def.get("default_size", [1600, 250])
	desk.custom_minimum_size = Vector2(default_size[0], default_size[1])
	desk.size = desk.custom_minimum_size

	# Create style
	var style = StyleBoxFlat.new()
	var schema = asset_def.get("config_schema", {})
	var wood_color = _get_config_color(config, schema, "wood_color", Color(0.28, 0.18, 0.1))

	style.bg_color = wood_color
	style.border_width_top = 8
	style.border_color = wood_color.lightened(0.2)

	desk.add_theme_stylebox_override("panel", style)

	return desk


func _apply_asset_config(node: Node, asset_def: Dictionary, config: Dictionary) -> void:
	"""Apply configuration to an asset instance"""
	var schema = asset_def.get("config_schema", {})

	for key in config:
		if not schema.has(key):
			continue

		var prop_def = schema[key]
		var value = config[key]

		# Try to set as property on the node
		if node.has_method("set_" + key):
			node.call("set_" + key, value)
		elif key in node:
			node.set(key, value)


func _get_config_color(config: Dictionary, schema: Dictionary, key: String, default: Color) -> Color:
	"""Helper to get a color from config with schema defaults"""
	if config.has(key):
		var val = config[key]
		if val is Color:
			return val
		elif val is Array and val.size() >= 3:
			return Color(val[0], val[1], val[2], val[3] if val.size() > 3 else 1.0)

	if schema.has(key):
		var def = schema[key].get("default", [])
		if def is Array and def.size() >= 3:
			return Color(def[0], def[1], def[2], def[3] if def.size() > 3 else 1.0)

	return default


# =============================================================================
# PUBLIC API - Custom Asset Registration
# =============================================================================

func register_custom_asset(asset_def: Dictionary) -> String:
	"""Register a new custom asset (e.g., AI-generated)"""
	var asset_id = asset_def.get("id", "")
	if asset_id.is_empty():
		asset_id = "custom_" + str(Time.get_unix_time_from_system())
		asset_def["id"] = asset_id

	# Ensure category is set
	if not asset_def.has("category"):
		asset_def["category"] = "ai_generated"

	# Ensure type is set
	if not asset_def.has("type"):
		asset_def["type"] = "texture"

	custom_assets[asset_id] = asset_def
	save_custom_assets()

	asset_registered.emit(asset_id)
	print("[AssetLibrary] Registered custom asset: " + asset_id)

	return asset_id


func unregister_custom_asset(asset_id: String) -> bool:
	"""Remove a custom asset"""
	if not custom_assets.has(asset_id):
		return false

	# Delete texture file if it exists
	var asset = custom_assets[asset_id]
	var texture_path = asset.get("texture_path", "")
	if texture_path.begins_with("user://") and FileAccess.file_exists(texture_path):
		DirAccess.remove_absolute(texture_path)

	custom_assets.erase(asset_id)
	save_custom_assets()

	return true


# =============================================================================
# AI Generation Support
# =============================================================================

func get_ai_style_presets() -> Dictionary:
	"""Get available AI generation style presets"""
	return ai_config.get("style_presets", {})


func get_ai_object_types() -> Dictionary:
	"""Get available AI object type prompts"""
	return ai_config.get("object_types", {})


func build_ai_prompt(user_prompt: String, style_preset: String = "retro_80s", object_type: String = "desk_accessory") -> String:
	"""Build a structured prompt for AI image generation"""
	var presets = get_ai_style_presets()
	var types = get_ai_object_types()

	var style_suffix = presets.get(style_preset, {}).get("prompt_suffix", "")
	var type_prefix = types.get(object_type, "object")

	return "A %s: %s. %s" % [type_prefix, user_prompt, style_suffix]


func register_ai_generated_asset(texture: Texture2D, prompt: String, name: String = "") -> String:
	"""Register an AI-generated texture as a new asset"""
	var asset_id = "ai_" + str(Time.get_unix_time_from_system())
	var texture_path = USER_ASSETS_PATH + asset_id + ".png"

	# Ensure directory exists
	DirAccess.make_dir_recursive_absolute(USER_ASSETS_PATH)

	# Save texture
	var image = texture.get_image()
	if image:
		image.save_png(texture_path)

	# Register asset
	var asset_def = {
		"id": asset_id,
		"name": name if name != "" else "AI: " + prompt.substr(0, 30),
		"category": "ai_generated",
		"type": "texture",
		"description": prompt,
		"texture_path": texture_path,
		"source": "ai_generated",
		"prompt": prompt,
		"created_at": Time.get_datetime_string_from_system(),
		"singleton": false,
		"default_size": [image.get_width() if image else 100, image.get_height() if image else 100],
		"tags": ["ai", "generated", "custom"]
	}

	return register_custom_asset(asset_def)
