extends Node
class_name AIAssetGenerator

## AI Asset Generator - Creates custom assets via Google Imagen API
##
## This manager:
## - Builds structured prompts for consistent style
## - Calls Google Imagen API via server proxy
## - Downloads and processes generated images
## - Registers new assets with AssetLibrary

signal generation_started(prompt: String)
signal generation_progress(message: String)
signal generation_complete(asset_id: String, texture: Texture2D)
signal generation_failed(error: String)

# API configuration (proxied through server for security)
const API_PROXY_ENDPOINT = "/api/assets/generate"
const DIRECT_API_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/imagen-4.0-generate-001:predict"

# Generation settings
var api_key: String = ""  # Set via server or config
var use_server_proxy: bool = true
var current_request: HTTPRequest = null
var asset_library: AssetLibrary


func _ready() -> void:
	asset_library = get_node_or_null("/root/AssetLibrary")


func set_api_key(key: String) -> void:
	"""Set the Google API key (for direct API calls)"""
	api_key = key


# =============================================================================
# PUBLIC API
# =============================================================================

func generate_asset(
	user_prompt: String,
	asset_name: String = "",
	style_preset: String = "retro_80s",
	object_type: String = "desk_accessory",
	options: Dictionary = {}
) -> void:
	"""Generate a new asset from text description"""

	if current_request and current_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		generation_failed.emit("A generation is already in progress")
		return

	# Build structured prompt
	var full_prompt = _build_prompt(user_prompt, style_preset, object_type)

	generation_started.emit(user_prompt)
	generation_progress.emit("Building prompt...")

	if use_server_proxy:
		_generate_via_server(full_prompt, asset_name, user_prompt, options)
	else:
		_generate_direct(full_prompt, asset_name, user_prompt, options)


func _build_prompt(user_prompt: String, style_preset: String, object_type: String) -> String:
	"""Build a structured prompt for consistent results"""

	var style_suffixes = {
		"retro_80s": "1980s retro computing aesthetic, vintage tech vibes, muted CRT monitor colors (green/amber phosphor glow), subtle cathode ray texture, nostalgic 8-bit era feel, soft shadows, isolated object centered on solid dark charcoal background (#1a1a1a), clean edges suitable for game asset, no text or watermarks",
		"pixel_art": "pixel art style, limited 16-color palette, clean crisp edges, retro game aesthetic, 16-bit era sprite style, isolated centered on transparent background, suitable for 2D game",
		"photorealistic": "photorealistic product photography, soft studio lighting, high detail, slight vintage film grain, isolated centered on neutral dark gray background, professional quality",
		"hand_drawn": "hand-drawn illustration style, ink and watercolor aesthetic, slightly worn paper texture, vintage technical manual illustration feel, isolated on cream paper background"
	}

	var object_prefixes = {
		"book": "A vintage computer book or programming manual from the 1980s",
		"desk_accessory": "A 1980s office desk accessory",
		"tech_prop": "A piece of vintage computing equipment from the early 1980s",
		"poster": "A poster or wall decoration from the 1980s era",
		"plant": "A small office plant in a simple pot",
		"beverage": "A beverage container (coffee mug or soda can)",
		"stationery": "Office supplies",
		"floppy_disk": "A 5.25 inch floppy disk",
		"cassette": "An audio cassette tape",
		"cable": "A vintage computer cable or connector"
	}

	var prefix = object_prefixes.get(object_type, "An object")
	var suffix = style_suffixes.get(style_preset, style_suffixes["retro_80s"])

	return "%s: %s. Style: %s" % [prefix, user_prompt, suffix]


# =============================================================================
# SERVER PROXY GENERATION (Recommended)
# =============================================================================

func _generate_via_server(full_prompt: String, asset_name: String, original_prompt: String, options: Dictionary) -> void:
	"""Generate via server proxy (hides API key)"""

	generation_progress.emit("Sending request to server...")

	# Create HTTP request
	current_request = HTTPRequest.new()
	add_child(current_request)
	current_request.request_completed.connect(
		_on_server_response.bind(asset_name, original_prompt)
	)

	# Build request
	var body = JSON.stringify({
		"prompt": full_prompt,
		"aspect_ratio": options.get("aspect_ratio", "1:1"),
		"style": options.get("style", "retro_80s")
	})

	var headers = [
		"Content-Type: application/json"
	]

	# Determine server URL
	var server_url = _get_server_url() + API_PROXY_ENDPOINT

	var error = current_request.request(server_url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		_cleanup_request()
		generation_failed.emit("Failed to send request: " + str(error))


func _on_server_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, asset_name: String, original_prompt: String) -> void:
	"""Handle server proxy response"""

	if result != HTTPRequest.RESULT_SUCCESS:
		_cleanup_request()
		generation_failed.emit("Request failed: " + str(result))
		return

	if response_code != 200:
		_cleanup_request()
		var error_text = body.get_string_from_utf8()
		generation_failed.emit("Server error %d: %s" % [response_code, error_text])
		return

	generation_progress.emit("Processing response...")

	# Parse response
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		_cleanup_request()
		generation_failed.emit("Failed to parse response")
		return

	var response = json.data

	# Check for error
	if response.has("error"):
		_cleanup_request()
		generation_failed.emit(response.get("error", "Unknown error"))
		return

	# Get image data
	var image_base64 = response.get("image", "")
	if image_base64.is_empty():
		_cleanup_request()
		generation_failed.emit("No image in response")
		return

	# Decode and create texture
	var texture = _decode_image(image_base64)
	if not texture:
		_cleanup_request()
		generation_failed.emit("Failed to decode image")
		return

	# Register asset
	var final_name = asset_name if asset_name != "" else original_prompt.substr(0, 30)
	var asset_id = _register_asset(texture, original_prompt, final_name)

	_cleanup_request()
	generation_complete.emit(asset_id, texture)


# =============================================================================
# DIRECT API GENERATION (Requires API key in client)
# =============================================================================

func _generate_direct(full_prompt: String, asset_name: String, original_prompt: String, options: Dictionary) -> void:
	"""Generate directly via Google API (requires API key)"""

	if api_key.is_empty():
		generation_failed.emit("API key not set")
		return

	generation_progress.emit("Connecting to Google API...")

	# Create HTTP request
	current_request = HTTPRequest.new()
	add_child(current_request)
	current_request.request_completed.connect(
		_on_direct_response.bind(asset_name, original_prompt)
	)

	# Build request body
	var body = JSON.stringify({
		"instances": [{"prompt": full_prompt}],
		"parameters": {
			"sampleCount": 1,
			"aspectRatio": options.get("aspect_ratio", "1:1"),
			"safetyFilterLevel": "block_medium_and_above",
			"personGeneration": "dont_allow"
		}
	})

	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]

	var error = current_request.request(DIRECT_API_ENDPOINT, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		_cleanup_request()
		generation_failed.emit("Failed to send request: " + str(error))


func _on_direct_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, asset_name: String, original_prompt: String) -> void:
	"""Handle direct API response"""

	if result != HTTPRequest.RESULT_SUCCESS:
		_cleanup_request()
		generation_failed.emit("Request failed: " + str(result))
		return

	if response_code != 200:
		_cleanup_request()
		var error_text = body.get_string_from_utf8()
		generation_failed.emit("API error %d: %s" % [response_code, error_text])
		return

	generation_progress.emit("Processing image...")

	# Parse response
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_cleanup_request()
		generation_failed.emit("Failed to parse API response")
		return

	var response = json.data

	# Check for predictions
	var predictions = response.get("predictions", [])
	if predictions.is_empty():
		_cleanup_request()
		generation_failed.emit("No predictions in response")
		return

	# Get base64 image
	var image_base64 = predictions[0].get("bytesBase64Encoded", "")
	if image_base64.is_empty():
		_cleanup_request()
		generation_failed.emit("No image data in response")
		return

	# Decode and create texture
	var texture = _decode_image(image_base64)
	if not texture:
		_cleanup_request()
		generation_failed.emit("Failed to decode image")
		return

	# Register asset
	var final_name = asset_name if asset_name != "" else original_prompt.substr(0, 30)
	var asset_id = _register_asset(texture, original_prompt, final_name)

	_cleanup_request()
	generation_complete.emit(asset_id, texture)


# =============================================================================
# UTILITY
# =============================================================================

func _decode_image(base64_data: String) -> Texture2D:
	"""Decode base64 image data to texture"""

	var raw_data = Marshalls.base64_to_raw(base64_data)
	if raw_data.is_empty():
		return null

	var image = Image.new()

	# Try PNG first, then JPEG
	var error = image.load_png_from_buffer(raw_data)
	if error != OK:
		error = image.load_jpg_from_buffer(raw_data)
		if error != OK:
			error = image.load_webp_from_buffer(raw_data)
			if error != OK:
				return null

	return ImageTexture.create_from_image(image)


func _register_asset(texture: Texture2D, prompt: String, name: String) -> String:
	"""Register the generated texture as a new asset"""

	if not asset_library:
		asset_library = get_node_or_null("/root/AssetLibrary")

	if asset_library:
		return asset_library.register_ai_generated_asset(texture, prompt, name)

	# Fallback: just return a generated ID
	return "ai_" + str(Time.get_unix_time_from_system())


func _get_server_url() -> String:
	"""Get the API server URL"""
	# In web builds, use relative path
	if OS.has_feature("web"):
		return ""

	# In desktop builds, use configured server
	return "http://localhost:3000"


func _cleanup_request() -> void:
	"""Clean up HTTP request"""
	if current_request:
		current_request.queue_free()
		current_request = null


func cancel_generation() -> void:
	"""Cancel any in-progress generation"""
	if current_request:
		current_request.cancel_request()
		_cleanup_request()
		generation_failed.emit("Generation cancelled")


func is_generating() -> bool:
	"""Check if a generation is in progress"""
	return current_request != null and current_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED


# =============================================================================
# PREVIEW GENERATION (Low-cost placeholder)
# =============================================================================

func generate_placeholder(prompt: String, size: Vector2 = Vector2(128, 128)) -> Texture2D:
	"""Generate a placeholder texture (no API call)"""

	var image = Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)

	# Fill with dark gradient
	for y in range(int(size.y)):
		for x in range(int(size.x)):
			var t = float(y) / size.y
			var gray = lerp(0.15, 0.08, t)
			image.set_pixel(x, y, Color(gray, gray, gray * 1.1, 1.0))

	# Add border
	var border_color = Color(0.3, 0.8, 0.4, 0.5)
	for x in range(int(size.x)):
		image.set_pixel(x, 0, border_color)
		image.set_pixel(x, int(size.y) - 1, border_color)
	for y in range(int(size.y)):
		image.set_pixel(0, y, border_color)
		image.set_pixel(int(size.x) - 1, y, border_color)

	return ImageTexture.create_from_image(image)
