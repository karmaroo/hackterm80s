extends Node
## Manages the 4-level zoom system for cinematic scene viewing

signal zoom_changed(level: int)

enum ZoomLevel { ROOM = 1, DESKTOP = 2, MONITOR = 3, SCREEN = 4 }

var current_level: int = ZoomLevel.DESKTOP  # Initialize at desktop, then zoom to room
var target_level: int = ZoomLevel.DESKTOP   # Track target during transitions
var is_transitioning: bool = false
var queued_level: int = -1  # Queue next zoom level if Tab pressed during transition

# Reference to the container being zoomed (created at runtime)
var zoom_container: Control = null

# References to elements
var room_elements: Control = null  # Window, desk legs (only visible at level 1)
var desk_extensions: Control = null  # Desk drawers - needs to be above main desk
var main_node: Control = null

# Fullscreen terminal overlay for SCREEN level
var screen_overlay: Control = null
var screen_viewport_display: TextureRect = null  # Displays the terminal SubViewport
var terminal_subviewport: SubViewport = null  # Reference to the actual SubViewport

# Window/blinds state
enum BlindsState { CLOSED, TILTED, OPEN }
var blinds_state: int = BlindsState.CLOSED
var blinds_transitioning: bool = false
var blind_slats: Array = []
var window_glass: ColorRect = null
var sun_moon_sprite: TextureRect = null  # Circular sun/moon texture

# Day/night state (for testing)
var force_day_night: int = -1  # -1 = auto, 0 = night, 1 = day
var force_time_hour: float = -1.0  # -1 = auto, 0-24 = forced hour

# Lighting system references
var window_light: PointLight2D = null
var floor_light: PointLight2D = null
var ambient_light: CanvasModulate = null
var light_container: Control = null  # Center-anchored container for lights/particles
var light_occluder_container: Node2D = null
var dust_particles: GPUParticles2D = null

# Overhead light system (controlled by wall switch)
var overhead_light: PointLight2D = null
var light_switch: Control = null
var light_switch_toggle: ColorRect = null
var overhead_light_on: bool = false

# Lighting constants
const BLINDS_LIGHT_FACTOR = {
	BlindsState.CLOSED: 0.08,   # Tiny amount through gaps
	BlindsState.TILTED: 0.45,   # Moderate through tilted slats
	BlindsState.OPEN: 1.0,      # Full light
}

# Time-based lighting (hour -> {color, intensity, ambient})
# Sunlight is warm yellow, moonlight is cool blue
const LIGHTING_PRESETS = {
	"night": {
		"light_color": Color(0.4, 0.5, 0.8),      # Cool blue moonlight
		"light_energy": 0.4,
		"ambient": Color(0.12, 0.12, 0.18),       # Dark blue ambient
		"sky_color": Color(0.02, 0.03, 0.08),     # Dark night sky
		"celestial_color": Color(0.9, 0.92, 0.95), # Moon color
	},
	"dawn": {
		"light_color": Color(1.0, 0.7, 0.5),      # Warm orange
		"light_energy": 0.7,
		"ambient": Color(0.25, 0.2, 0.22),        # Warm dark
		"sky_color": Color(0.6, 0.4, 0.5),        # Pink/orange sky
		"celestial_color": Color(1.0, 0.85, 0.5), # Rising sun
	},
	"morning": {
		"light_color": Color(1.0, 0.95, 0.8),     # Warm white
		"light_energy": 1.0,
		"ambient": Color(0.35, 0.33, 0.32),       # Neutral
		"sky_color": Color(0.5, 0.7, 0.9),        # Light blue
		"celestial_color": Color(1.0, 0.98, 0.7), # Morning sun
	},
	"midday": {
		"light_color": Color(1.0, 0.98, 0.9),     # Bright white
		"light_energy": 1.3,
		"ambient": Color(0.42, 0.4, 0.38),        # Bright neutral
		"sky_color": Color(0.4, 0.65, 0.95),      # Bright blue
		"celestial_color": Color(1.0, 1.0, 0.85), # Bright sun
	},
	"afternoon": {
		"light_color": Color(1.0, 0.92, 0.75),    # Golden
		"light_energy": 1.1,
		"ambient": Color(0.38, 0.35, 0.32),       # Warm
		"sky_color": Color(0.45, 0.6, 0.85),      # Softer blue
		"celestial_color": Color(1.0, 0.95, 0.6), # Afternoon sun
	},
	"dusk": {
		"light_color": Color(1.0, 0.6, 0.4),      # Deep orange
		"light_energy": 0.6,
		"ambient": Color(0.22, 0.18, 0.2),        # Warm dark
		"sky_color": Color(0.7, 0.4, 0.35),       # Orange/red sky
		"celestial_color": Color(1.0, 0.6, 0.3),  # Setting sun
	},
}

# Nodes to move into ZoomContainer
var nodes_to_zoom: Array[String] = [
	"Background", "Desk", "WoodShelf1", "WoodShelf2",
	"LEDClock", "LavaLamp", "ComputerFrame",
	"WargamesPoster", "DeskPhone", "HayesModem"
]

# Zoom scale factors
const ZOOM_SCALES = {
	ZoomLevel.ROOM: Vector2(0.55, 0.55),    # Zoomed out - see full room
	ZoomLevel.DESKTOP: Vector2(1.0, 1.0),   # Normal (current view)
	ZoomLevel.MONITOR: Vector2(1.6, 1.6),   # Zoomed in - monitor focus
	ZoomLevel.SCREEN: Vector2(2.0, 2.0),    # Maximum zoom - just the screen content
}

# Pivot points relative to viewport (where to center the zoom)
const ZOOM_PIVOTS = {
	ZoomLevel.ROOM: Vector2(0.5, 0.6),      # Center of room (lower to show ceiling area)
	ZoomLevel.DESKTOP: Vector2(0.5, 0.5),   # Center of desk area
	ZoomLevel.MONITOR: Vector2(0.5, 0.08),  # Center on monitor screen (shifted down to show full monitor)
	ZoomLevel.SCREEN: Vector2(0.5, 0.18),   # Center on screen content only (no monitor frame)
}

# Transition duration in seconds
const TRANSITION_DURATION: float = 0.6


func _ready() -> void:
	# Wait for scene to be fully ready
	await get_tree().process_frame
	await get_tree().process_frame
	_setup_zoom_system()


func _process(_delta: float) -> void:
	# Update screen overlay size if needed (viewport texture auto-updates)
	if current_level == ZoomLevel.SCREEN and screen_overlay and screen_overlay.visible:
		pass  # ViewportTexture auto-syncs, no manual update needed


func _setup_zoom_system() -> void:
	main_node = get_parent() as Control
	if not main_node:
		print("[ZoomManager] ERROR: Parent is not a Control node")
		return

	# Create ZoomContainer
	zoom_container = Control.new()
	zoom_container.name = "ZoomContainer"
	zoom_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	zoom_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Get viewport size for initial pivot (start at DESKTOP level)
	var viewport_size = main_node.get_viewport_rect().size
	zoom_container.pivot_offset = viewport_size * ZOOM_PIVOTS[ZoomLevel.DESKTOP]
	# Scale is 1.0 at DESKTOP, no need to set explicitly

	# Insert ZoomContainer as first child (after AmbientDarkness)
	var ambient = main_node.get_node_or_null("AmbientDarkness")
	var insert_index = 1 if ambient else 0
	main_node.add_child(zoom_container)
	main_node.move_child(zoom_container, insert_index)

	# Reparent nodes into ZoomContainer
	for node_name in nodes_to_zoom:
		var node = main_node.get_node_or_null(node_name)
		if node:
			var global_pos = node.global_position if node is Control else Vector2.ZERO
			node.reparent(zoom_container)
			print("[ZoomManager] Moved %s into ZoomContainer" % node_name)
		else:
			print("[ZoomManager] Node not found: %s" % node_name)

	# Create RoomElements for level 1 view
	_create_room_elements()

	# Create fullscreen terminal overlay for SCREEN level
	_create_screen_overlay()

	print("[ZoomManager] Zoom system initialized")

	# Connect to window resize to update pivot
	main_node.get_tree().root.size_changed.connect(_on_viewport_resize)

	# Start at Room level - wait a frame then zoom out
	await get_tree().process_frame
	_instant_zoom_to_room()


func _on_viewport_resize() -> void:
	if not zoom_container or not main_node:
		return
	# Update pivot based on new viewport size
	var viewport_size = main_node.get_viewport_rect().size
	zoom_container.pivot_offset = viewport_size * ZOOM_PIVOTS[current_level]


func _create_room_elements() -> void:
	# Create container for room-only elements (window, wall, shelves, etc.)
	room_elements = Control.new()
	room_elements.name = "RoomElements"
	room_elements.set_anchors_preset(Control.PRESET_FULL_RECT)
	room_elements.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Start hidden since we load at DESKTOP zoom level
	room_elements.modulate.a = 0.0
	room_elements.visible = false

	# Add room elements to ZoomContainer (behind other elements)
	zoom_container.add_child(room_elements)
	zoom_container.move_child(room_elements, 0)

	# Create extended wall/floor area
	_create_extended_background()

	# Create Window with blinds on the right side
	_create_window()

	# Create extended shelves on the left
	_create_extended_shelves()

	# Create the lighting system (lights, ambient, occluders)
	_create_lighting_system()

	# Create wall light switch and overhead light
	_create_light_switch()

	# Create desk extensions AFTER other elements are set up
	# These need to be added to zoom_container directly (not room_elements)
	# so they render ON TOP of the main Desk
	call_deferred("_create_extended_desk")

	# Add occluders after desk extensions are created
	call_deferred("_create_light_occluders")

	print("[ZoomManager] Room elements created")


func _create_screen_overlay() -> void:
	# Create a fullscreen overlay for SCREEN zoom level
	# Displays the terminal SubViewport directly (shows terminal AND any programs like editor)

	# Get reference to the SubViewport
	var computer_frame = zoom_container.get_node_or_null("ComputerFrame")
	if computer_frame:
		terminal_subviewport = computer_frame.get_node_or_null("Monitor/TerminalView/SubViewport")

	if not terminal_subviewport:
		print("[ZoomManager] WARNING: Could not find SubViewport for screen overlay")
		return

	# Create overlay container (outside zoom_container so it doesn't scale)
	screen_overlay = Control.new()
	screen_overlay.name = "ScreenOverlay"
	screen_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_overlay.visible = false  # Hidden by default

	# Black background
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.02, 0.0)  # Very dark green-black like terminal
	screen_overlay.add_child(bg)

	# Display the SubViewport as a texture - shows terminal AND editor
	screen_viewport_display = TextureRect.new()
	screen_viewport_display.name = "ViewportDisplay"
	screen_viewport_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_viewport_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_viewport_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	screen_viewport_display.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL

	# Add some padding
	screen_viewport_display.offset_left = 40
	screen_viewport_display.offset_right = -40
	screen_viewport_display.offset_top = 30
	screen_viewport_display.offset_bottom = -30

	# Get the viewport's texture directly (Godot 4 way)
	screen_viewport_display.texture = terminal_subviewport.get_texture()

	screen_overlay.add_child(screen_viewport_display)

	# Add overlay to main_node (on top of everything)
	main_node.add_child(screen_overlay)

	print("[ZoomManager] Screen overlay created (viewport mirror)")


func _create_extended_background() -> void:
	# Get the main Background node (it was reparented to zoom_container) and make it much larger
	# This ensures seamless blending since we use the same node with the same shader
	var background = zoom_container.get_node_or_null("Background")
	if background:
		# Remove anchors preset and set fixed size to cover room view area
		background.set_anchors_preset(Control.PRESET_CENTER)
		background.size = Vector2(5000, 3200)  # Very large to cover entire room including far right
		background.position = Vector2(-2200, -1600)  # Offset to cover more on right side
		# Move Background to be first child (behind everything)
		zoom_container.move_child(background, 0)
		# Move room_elements to be second (in front of background, behind other content)
		zoom_container.move_child(room_elements, 1)
		print("[ZoomManager] Extended main Background to cover room view")
	else:
		print("[ZoomManager] WARNING: Background node not found in zoom_container")

	# Floor area below desk
	var floor_rect = ColorRect.new()
	floor_rect.name = "Floor"
	floor_rect.set_anchors_preset(Control.PRESET_CENTER)
	floor_rect.size = Vector2(3200, 600)
	floor_rect.position = Vector2(-1600, 150)
	floor_rect.color = Color(0.08, 0.06, 0.05)  # Dark floor
	room_elements.add_child(floor_rect)

	# Baseboard trim
	var baseboard = ColorRect.new()
	baseboard.name = "Baseboard"
	baseboard.set_anchors_preset(Control.PRESET_CENTER)
	baseboard.size = Vector2(3200, 12)
	baseboard.position = Vector2(-1600, 138)
	baseboard.color = Color(0.16, 0.11, 0.07)  # Wood baseboard
	room_elements.add_child(baseboard)


func _create_shelf_items() -> void:
	# Hack books image on left side of top shelf (replaces procedural books)
	var hack_books_texture = load("res://assets/hack-books-787772.png")
	if hack_books_texture:
		var hack_books = TextureRect.new()
		hack_books.name = "HackBooks"
		hack_books.texture = hack_books_texture
		hack_books.set_anchors_preset(Control.PRESET_CENTER)
		hack_books.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hack_books.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		hack_books.size = Vector2(540, 390)  # Bigger size
		hack_books.position = Vector2(-1420, -725)  # Left side of top shelf, resting on shelf
		hack_books.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		hack_books.modulate = Color(0.6, 0.55, 0.5)  # Darker, slightly warm tint
		room_elements.add_child(hack_books)

	# Tech books image on right side of top shelf
	var tech_books_texture = load("res://assets/tech-books-443311.png")
	if tech_books_texture:
		var tech_books = TextureRect.new()
		tech_books.name = "TechBooks"
		tech_books.texture = tech_books_texture
		tech_books.set_anchors_preset(Control.PRESET_CENTER)
		# Scale to fit nicely on shelf (adjust size as needed)
		tech_books.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tech_books.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		tech_books.size = Vector2(400, 280)  # Much bigger
		tech_books.position = Vector2(-900, -654)  # Right side of top shelf, resting on shelf top edge
		# Use linear filtering for smooth scaling (not pixelated)
		tech_books.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# Darken with modulate to simulate shelf shadow/ambient lighting
		tech_books.modulate = Color(0.6, 0.55, 0.5)  # Darker, slightly warm tint
		room_elements.add_child(tech_books)

	# Box on middle shelf
	_create_storage_box(Vector2(-1100, -355), Vector2(80, 55), Color(0.5, 0.45, 0.35))

	# Cassette tapes stack on middle shelf
	_create_cassette_stack(Vector2(-950, -300))

	# Floppy disk box on lower shelf
	_create_floppy_box(Vector2(-1050, -230))

	# Binders/manuals on lower shelf
	_create_binders(Vector2(-900, -190))


func _create_books_on_shelf(start_x: float, shelf_y: float, shelf_name: String) -> void:
	# Muted, realistic book colors - dusty, worn appearance
	var muted_colors = [
		Color(0.45, 0.28, 0.22),   # Dusty burgundy
		Color(0.25, 0.30, 0.38),   # Faded navy
		Color(0.38, 0.32, 0.24),   # Worn brown
		Color(0.28, 0.35, 0.30),   # Muted olive
		Color(0.42, 0.35, 0.32),   # Taupe
		Color(0.35, 0.28, 0.32),   # Dusty plum
		Color(0.32, 0.32, 0.35),   # Slate gray
		Color(0.40, 0.36, 0.28),   # Khaki
		Color(0.30, 0.25, 0.22),   # Dark umber
		Color(0.38, 0.38, 0.36),   # Warm gray
	]

	var x_offset = start_x
	var num_books = 10

	for i in range(num_books):
		# Bigger books with varied heights
		var book_width = randf_range(18, 35)
		var book_height = randf_range(80, 110)

		# Pick a random muted color with slight variation
		var base_color = muted_colors[randi() % muted_colors.size()]
		base_color = Color(
			clamp(base_color.r + randf_range(-0.04, 0.04), 0.18, 0.48),
			clamp(base_color.g + randf_range(-0.04, 0.04), 0.18, 0.48),
			clamp(base_color.b + randf_range(-0.04, 0.04), 0.18, 0.48)
		)

		# Occasional slight tilt
		var is_tilted = randf() < 0.1

		_create_simple_book(
			Vector2(x_offset, shelf_y - book_height),
			Vector2(book_width, book_height),
			base_color,
			is_tilted,
			"%s_book_%d" % [shelf_name, i]
		)

		# Tight spacing
		x_offset += book_width + randf_range(1, 2)


func _create_simple_book(pos: Vector2, size: Vector2, base_color: Color, is_tilted: bool, book_name: String) -> void:
	# Container for the book
	var book_container = Control.new()
	book_container.name = book_name
	book_container.set_anchors_preset(Control.PRESET_CENTER)
	book_container.position = pos
	book_container.size = size
	if is_tilted:
		book_container.rotation_degrees = randf_range(-12, -4)
	room_elements.add_child(book_container)

	# Main book spine - use gradient for smoother appearance
	var spine = ColorRect.new()
	spine.name = "Spine"
	spine.size = size
	spine.color = base_color
	book_container.add_child(spine)

	# Soft left shadow (gradient effect using multiple thin rects with decreasing opacity)
	var shadow_color = Color(base_color.r * 0.5, base_color.g * 0.5, base_color.b * 0.5)
	for s in range(4):
		var shadow_strip = ColorRect.new()
		shadow_strip.size = Vector2(1, size.y)
		shadow_strip.position = Vector2(s, 0)
		shadow_strip.color = Color(shadow_color.r, shadow_color.g, shadow_color.b, 0.6 - s * 0.15)
		book_container.add_child(shadow_strip)

	# Soft right highlight (gradient effect)
	var highlight_color = Color(
		min(base_color.r + 0.12, 0.6),
		min(base_color.g + 0.12, 0.6),
		min(base_color.b + 0.12, 0.6)
	)
	for h in range(3):
		var highlight_strip = ColorRect.new()
		highlight_strip.size = Vector2(1, size.y)
		highlight_strip.position = Vector2(size.x - 1 - h, 0)
		highlight_strip.color = Color(highlight_color.r, highlight_color.g, highlight_color.b, 0.4 - h * 0.12)
		book_container.add_child(highlight_strip)

	# Top edge (pages) - soft cream color
	var pages_color = Color(0.88, 0.85, 0.78)
	var pages_top = ColorRect.new()
	pages_top.name = "PagesTop"
	pages_top.size = Vector2(size.x - 2, 2)
	pages_top.position = Vector2(1, 0)
	pages_top.color = pages_color
	book_container.add_child(pages_top)


func _create_storage_box(pos: Vector2, size: Vector2, color: Color) -> void:
	var box_container = Control.new()
	box_container.name = "StorageBox"
	box_container.set_anchors_preset(Control.PRESET_CENTER)
	box_container.position = pos
	box_container.size = size
	room_elements.add_child(box_container)

	# Main box
	var box = ColorRect.new()
	box.size = size
	box.color = color
	box_container.add_child(box)

	# Box lid line
	var lid_line = ColorRect.new()
	lid_line.size = Vector2(size.x, 2)
	lid_line.position = Vector2(0, 8)
	lid_line.color = Color(color.r * 0.7, color.g * 0.7, color.b * 0.7)
	box_container.add_child(lid_line)

	# Box highlight
	var highlight = ColorRect.new()
	highlight.size = Vector2(size.x, 2)
	highlight.position = Vector2(0, 0)
	highlight.color = Color(min(color.r * 1.3, 1.0), min(color.g * 1.3, 1.0), min(color.b * 1.3, 1.0))
	box_container.add_child(highlight)


func _create_cassette_stack(pos: Vector2) -> void:
	var tape_colors = [
		Color(0.12, 0.12, 0.14),
		Color(0.15, 0.15, 0.17),
		Color(0.1, 0.1, 0.12),
		Color(0.18, 0.18, 0.2),
	]

	for i in range(4):
		var tape_container = Control.new()
		tape_container.name = "Tape%d" % i
		tape_container.set_anchors_preset(Control.PRESET_CENTER)
		tape_container.position = Vector2(pos.x, pos.y - (i * 14))
		tape_container.size = Vector2(70, 12)
		room_elements.add_child(tape_container)

		# Tape body
		var tape = ColorRect.new()
		tape.size = Vector2(70, 12)
		tape.color = tape_colors[i]
		tape_container.add_child(tape)

		# Label area
		var label = ColorRect.new()
		label.size = Vector2(50, 8)
		label.position = Vector2(10, 2)
		label.color = Color(0.9, 0.88, 0.82)
		tape_container.add_child(label)

		# Label lines (text simulation)
		for j in range(2):
			var text_line = ColorRect.new()
			text_line.size = Vector2(40, 1)
			text_line.position = Vector2(15, 4 + j * 3)
			text_line.color = Color(0.3, 0.3, 0.35)
			tape_container.add_child(text_line)


func _create_floppy_box(pos: Vector2) -> void:
	var box_container = Control.new()
	box_container.name = "FloppyBox"
	box_container.set_anchors_preset(Control.PRESET_CENTER)
	box_container.position = pos
	box_container.size = Vector2(90, 40)
	room_elements.add_child(box_container)

	# Main box (dark plastic)
	var box = ColorRect.new()
	box.size = Vector2(90, 40)
	box.color = Color(0.12, 0.12, 0.15)
	box_container.add_child(box)

	# Box dividers (floppy slots visible)
	for i in range(8):
		var divider = ColorRect.new()
		divider.size = Vector2(1, 35)
		divider.position = Vector2(8 + i * 10, 3)
		divider.color = Color(0.08, 0.08, 0.1)
		box_container.add_child(divider)

	# Front label
	var label = ColorRect.new()
	label.size = Vector2(60, 10)
	label.position = Vector2(15, 28)
	label.color = Color(0.85, 0.82, 0.75)
	box_container.add_child(label)


func _create_binders(pos: Vector2) -> void:
	var binder_colors = [
		Color(0.85, 0.82, 0.7),   # Cream
		Color(0.7, 0.65, 0.55),   # Tan
		Color(0.6, 0.58, 0.5),    # Gray-tan
	]

	for i in range(3):
		var binder_container = Control.new()
		binder_container.name = "Binder%d" % i
		binder_container.set_anchors_preset(Control.PRESET_CENTER)
		binder_container.position = Vector2(pos.x + (i * 38), pos.y - 50)
		binder_container.size = Vector2(35, 50)
		room_elements.add_child(binder_container)

		# Main binder
		var binder = ColorRect.new()
		binder.size = Vector2(35, 50)
		binder.color = binder_colors[i]
		binder_container.add_child(binder)

		# Spine ridge
		var ridge = ColorRect.new()
		ridge.size = Vector2(4, 50)
		ridge.position = Vector2(0, 0)
		ridge.color = Color(binder_colors[i].r * 0.8, binder_colors[i].g * 0.8, binder_colors[i].b * 0.8)
		binder_container.add_child(ridge)

		# Ring holes hint
		for j in range(3):
			var ring = ColorRect.new()
			ring.size = Vector2(3, 6)
			ring.position = Vector2(5, 10 + j * 15)
			ring.color = Color(0.5, 0.48, 0.45)
			binder_container.add_child(ring)


func _create_window() -> void:
	# Large window that extends past the right edge and top of the scene
	# We only see the bottom-left corner of the window
	var window = Control.new()
	window.name = "Window"
	window.set_anchors_preset(Control.PRESET_CENTER)
	window.size = Vector2(700, 650)
	window.position = Vector2(1050, -650)

	# Window frame (outer) - dark wood
	var frame_outer = ColorRect.new()
	frame_outer.name = "FrameOuter"
	frame_outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_outer.color = Color(0.2, 0.14, 0.08)
	window.add_child(frame_outer)

	# Window frame (inner) - lighter wood
	var frame_inner = ColorRect.new()
	frame_inner.name = "FrameInner"
	frame_inner.anchor_right = 1.0
	frame_inner.anchor_bottom = 1.0
	frame_inner.offset_left = 12
	frame_inner.offset_top = 12
	frame_inner.offset_right = -12
	frame_inner.offset_bottom = -12
	frame_inner.color = Color(0.28, 0.2, 0.12)
	window.add_child(frame_inner)

	# Determine if day or night
	var is_day = _is_daytime()
	var sky_color = Color(0.4, 0.6, 0.85, 1.0) if is_day else Color(0.02, 0.03, 0.08, 1.0)

	# Window glass area (sky visible when blinds open)
	window_glass = ColorRect.new()
	window_glass.name = "Glass"
	window_glass.anchor_right = 1.0
	window_glass.anchor_bottom = 1.0
	window_glass.offset_left = 20
	window_glass.offset_top = 20
	window_glass.offset_right = -20
	window_glass.offset_bottom = -20
	window_glass.color = sky_color
	window.add_child(window_glass)

	# Sun or Moon (visible when blinds are open) - using TextureRect for circular shape
	var sun_moon_texture = TextureRect.new()
	sun_moon_texture.name = "SunMoonTexture"
	sun_moon_texture.set_anchors_preset(Control.PRESET_CENTER)
	sun_moon_texture.texture = _create_celestial_texture()
	sun_moon_texture.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	if is_day:
		sun_moon_texture.size = Vector2(120, 120)
		sun_moon_texture.position = Vector2(200, 150)
		sun_moon_texture.modulate = Color(1.0, 0.95, 0.4, 0.9)  # Bright yellow sun
	else:
		sun_moon_texture.size = Vector2(80, 80)
		sun_moon_texture.position = Vector2(220, 180)
		sun_moon_texture.modulate = Color(0.9, 0.92, 0.95, 0.85)  # Pale moon
	sun_moon_texture.modulate.a = 0.0  # Hidden initially
	window_glass.add_child(sun_moon_texture)
	# Store reference (we'll use the TextureRect but update references)
	sun_moon_sprite = sun_moon_texture

	# Window divider (vertical center bar)
	var divider_v = ColorRect.new()
	divider_v.name = "DividerV"
	divider_v.anchor_left = 0.5
	divider_v.anchor_right = 0.5
	divider_v.anchor_bottom = 1.0
	divider_v.offset_left = -8
	divider_v.offset_top = 20
	divider_v.offset_right = 8
	divider_v.offset_bottom = -20
	divider_v.color = Color(0.25, 0.18, 0.1)
	window.add_child(divider_v)

	# Window divider (horizontal center bar)
	var divider_h = ColorRect.new()
	divider_h.name = "DividerH"
	divider_h.anchor_top = 0.5
	divider_h.anchor_right = 1.0
	divider_h.anchor_bottom = 0.5
	divider_h.offset_left = 20
	divider_h.offset_top = -6
	divider_h.offset_right = -20
	divider_h.offset_bottom = 6
	divider_h.color = Color(0.25, 0.18, 0.1)
	window.add_child(divider_h)

	# Blinds valance (top cover)
	var valance = ColorRect.new()
	valance.name = "Valance"
	valance.anchor_right = 1.0
	valance.offset_left = 15
	valance.offset_top = 15
	valance.offset_right = -15
	valance.offset_bottom = 50
	valance.color = Color(0.82, 0.78, 0.72)
	window.add_child(valance)

	# Clickable blinds container
	var blinds_container = Control.new()
	blinds_container.name = "Blinds"
	blinds_container.anchor_right = 1.0
	blinds_container.anchor_bottom = 1.0
	blinds_container.offset_left = 25
	blinds_container.offset_top = 55
	blinds_container.offset_right = -25
	blinds_container.offset_bottom = -25
	blinds_container.mouse_filter = Control.MOUSE_FILTER_STOP
	window.add_child(blinds_container)

	# Make blinds clickable
	var blinds_button = Button.new()
	blinds_button.name = "BlindsButton"
	blinds_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	blinds_button.flat = true
	blinds_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	blinds_button.pressed.connect(_on_blinds_clicked)
	blinds_container.add_child(blinds_button)

	# Create blind slats
	blind_slats.clear()
	var num_slats = 22
	var slat_height = 24
	var gap = 4
	var light_color = Color(1.0, 0.95, 0.75, 0.5) if is_day else Color(0.6, 0.7, 0.9, 0.3)

	for i in range(num_slats):
		# Light gap (behind slat)
		var light_gap = ColorRect.new()
		light_gap.name = "LightGap%d" % i
		light_gap.position = Vector2(0, i * (slat_height + gap))
		light_gap.size = Vector2(650, gap + 2)
		light_gap.color = light_color
		light_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		blinds_container.add_child(light_gap)

		# Slat (partially covering the light)
		var slat = ColorRect.new()
		slat.name = "Slat%d" % i
		slat.position = Vector2(0, i * (slat_height + gap) + gap)
		slat.size = Vector2(650, slat_height)
		var shade = 0.82 + (i % 3) * 0.02
		slat.color = Color(shade, shade - 0.04, shade - 0.08)
		slat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		blinds_container.add_child(slat)

		# Store slat reference for animation
		blind_slats.append({"slat": slat, "gap": light_gap, "original_y": slat.position.y, "original_height": slat_height})

	# Blind cord on left side of window (visible side)
	var cord = ColorRect.new()
	cord.name = "BlindCord"
	cord.set_anchors_preset(Control.PRESET_CENTER)
	cord.size = Vector2(4, 150)
	cord.position = Vector2(1070, -450)
	cord.color = Color(0.9, 0.85, 0.75)
	room_elements.add_child(cord)

	# Cord pull
	var cord_pull = ColorRect.new()
	cord_pull.name = "CordPull"
	cord_pull.set_anchors_preset(Control.PRESET_CENTER)
	cord_pull.size = Vector2(14, 24)
	cord_pull.position = Vector2(1065, -300)
	cord_pull.color = Color(0.85, 0.8, 0.7)
	room_elements.add_child(cord_pull)

	# Window sill - wider for large window, positioned at window bottom
	var sill = ColorRect.new()
	sill.name = "WindowSill"
	sill.set_anchors_preset(Control.PRESET_CENTER)
	sill.size = Vector2(750, 22)
	sill.position = Vector2(1025, 5)  # Moved up with window
	sill.color = Color(0.32, 0.24, 0.14)
	room_elements.add_child(sill)

	# Sill highlight
	var sill_highlight = ColorRect.new()
	sill_highlight.name = "SillHighlight"
	sill_highlight.set_anchors_preset(Control.PRESET_CENTER)
	sill_highlight.size = Vector2(750, 4)
	sill_highlight.position = Vector2(1025, 5)
	sill_highlight.color = Color(0.45, 0.35, 0.22)
	room_elements.add_child(sill_highlight)

	room_elements.add_child(window)


func _create_extended_desk() -> void:
	# Create container for desk extensions - renders ON TOP of the main Desk
	desk_extensions = Control.new()
	desk_extensions.name = "DeskExtensions"
	desk_extensions.set_anchors_preset(Control.PRESET_FULL_RECT)
	desk_extensions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Start hidden since we load at DESKTOP zoom level
	desk_extensions.modulate.a = 0.0
	desk_extensions.visible = false

	zoom_container.add_child(desk_extensions)

	# Desk top Y position - aligned with main desk
	var desk_y = 150

	# === LEFT DESK EXTENSION ===
	# Extends from main desk to far left edge
	var desk_ext_left = ColorRect.new()
	desk_ext_left.name = "DeskExtLeft"
	desk_ext_left.set_anchors_preset(Control.PRESET_CENTER)
	desk_ext_left.size = Vector2(900, 250)
	desk_ext_left.position = Vector2(-1700, desk_y)
	desk_ext_left.color = Color(0.28, 0.18, 0.1)
	desk_extensions.add_child(desk_ext_left)

	# Left desk - top edge (matches DeskTopEdge)
	var desk_ext_left_edge = ColorRect.new()
	desk_ext_left_edge.name = "DeskExtLeftEdge"
	desk_ext_left_edge.set_anchors_preset(Control.PRESET_CENTER)
	desk_ext_left_edge.size = Vector2(900, 12)
	desk_ext_left_edge.position = Vector2(-1700, desk_y)
	desk_ext_left_edge.color = Color(0.38, 0.24, 0.14)
	desk_extensions.add_child(desk_ext_left_edge)

	# Left desk - top highlight (matches DeskTopHighlight)
	var desk_ext_left_highlight = ColorRect.new()
	desk_ext_left_highlight.name = "DeskExtLeftHighlight"
	desk_ext_left_highlight.set_anchors_preset(Control.PRESET_CENTER)
	desk_ext_left_highlight.size = Vector2(900, 2)
	desk_ext_left_highlight.position = Vector2(-1700, desk_y + 1)
	desk_ext_left_highlight.color = Color(0.48, 0.32, 0.2)
	desk_extensions.add_child(desk_ext_left_highlight)

	# Left desk - top shadow (matches DeskTopShadow)
	var desk_ext_left_shadow = ColorRect.new()
	desk_ext_left_shadow.name = "DeskExtLeftShadow"
	desk_ext_left_shadow.set_anchors_preset(Control.PRESET_CENTER)
	desk_ext_left_shadow.size = Vector2(900, 2)
	desk_ext_left_shadow.position = Vector2(-1700, desk_y + 10)
	desk_ext_left_shadow.color = Color(0.22, 0.14, 0.08)
	desk_extensions.add_child(desk_ext_left_shadow)

	# Left desk wood grain lines (matching main desk pattern)
	var left_grain_data = [
		[35, 3, Color(0.22, 0.13, 0.07)],
		[65, 2, Color(0.32, 0.20, 0.12)],
		[95, 3, Color(0.20, 0.12, 0.06)],
		[130, 2, Color(0.26, 0.16, 0.09)],
		[165, 3, Color(0.18, 0.10, 0.05)],
		[200, 3, Color(0.24, 0.15, 0.08)],
	]
	for i in range(left_grain_data.size()):
		var grain = ColorRect.new()
		grain.name = "LeftGrain%d" % i
		grain.set_anchors_preset(Control.PRESET_CENTER)
		grain.size = Vector2(900, left_grain_data[i][1])
		grain.position = Vector2(-1700, desk_y + left_grain_data[i][0])
		grain.color = left_grain_data[i][2]
		desk_extensions.add_child(grain)

	# === RIGHT DESK EXTENSION ===
	# Extends from main desk to far right edge
	var desk_ext_right = ColorRect.new()
	desk_ext_right.name = "DeskExtRight"
	desk_ext_right.set_anchors_preset(Control.PRESET_CENTER)
	desk_ext_right.size = Vector2(900, 250)
	desk_ext_right.position = Vector2(800, desk_y)
	desk_ext_right.color = Color(0.28, 0.18, 0.1)
	desk_extensions.add_child(desk_ext_right)

	# Right desk - top edge (matches DeskTopEdge)
	var desk_ext_right_edge = ColorRect.new()
	desk_ext_right_edge.name = "DeskExtRightEdge"
	desk_ext_right_edge.set_anchors_preset(Control.PRESET_CENTER)
	desk_ext_right_edge.size = Vector2(900, 12)
	desk_ext_right_edge.position = Vector2(800, desk_y)
	desk_ext_right_edge.color = Color(0.38, 0.24, 0.14)
	desk_extensions.add_child(desk_ext_right_edge)

	# Right desk - top highlight (matches DeskTopHighlight)
	var desk_ext_right_highlight = ColorRect.new()
	desk_ext_right_highlight.name = "DeskExtRightHighlight"
	desk_ext_right_highlight.set_anchors_preset(Control.PRESET_CENTER)
	desk_ext_right_highlight.size = Vector2(900, 2)
	desk_ext_right_highlight.position = Vector2(800, desk_y + 1)
	desk_ext_right_highlight.color = Color(0.48, 0.32, 0.2)
	desk_extensions.add_child(desk_ext_right_highlight)

	# Right desk - top shadow (matches DeskTopShadow)
	var desk_ext_right_shadow = ColorRect.new()
	desk_ext_right_shadow.name = "DeskExtRightShadow"
	desk_ext_right_shadow.set_anchors_preset(Control.PRESET_CENTER)
	desk_ext_right_shadow.size = Vector2(900, 2)
	desk_ext_right_shadow.position = Vector2(800, desk_y + 10)
	desk_ext_right_shadow.color = Color(0.22, 0.14, 0.08)
	desk_extensions.add_child(desk_ext_right_shadow)

	# Right desk wood grain lines (matching main desk pattern)
	var right_grain_data = [
		[35, 3, Color(0.22, 0.13, 0.07)],
		[65, 2, Color(0.32, 0.20, 0.12)],
		[95, 3, Color(0.20, 0.12, 0.06)],
		[130, 2, Color(0.26, 0.16, 0.09)],
		[165, 3, Color(0.18, 0.10, 0.05)],
		[200, 3, Color(0.24, 0.15, 0.08)],
	]
	for i in range(right_grain_data.size()):
		var grain = ColorRect.new()
		grain.name = "RightGrain%d" % i
		grain.set_anchors_preset(Control.PRESET_CENTER)
		grain.size = Vector2(900, right_grain_data[i][1])
		grain.position = Vector2(800, desk_y + right_grain_data[i][0])
		grain.color = right_grain_data[i][2]
		desk_extensions.add_child(grain)

	# === DESK BOTTOM ENDCAP ===
	# Dark wood layer at the bottom edge of the desk, spanning full width
	var endcap_y = desk_y + 240  # Bottom of desk
	var endcap_height = 35  # Thicker endcap

	var desk_endcap = ColorRect.new()
	desk_endcap.name = "DeskEndcap"
	desk_endcap.set_anchors_preset(Control.PRESET_CENTER)
	desk_endcap.size = Vector2(3400, endcap_height)
	desk_endcap.position = Vector2(-1700, endcap_y)
	desk_endcap.color = Color(0.18, 0.11, 0.06)  # Dark wood
	desk_extensions.add_child(desk_endcap)

	# Endcap highlight (top edge)
	var desk_endcap_highlight = ColorRect.new()
	desk_endcap_highlight.name = "DeskEndcapHighlight"
	desk_endcap_highlight.set_anchors_preset(Control.PRESET_CENTER)
	desk_endcap_highlight.size = Vector2(3400, 4)
	desk_endcap_highlight.position = Vector2(-1700, endcap_y)
	desk_endcap_highlight.color = Color(0.24, 0.15, 0.08)
	desk_extensions.add_child(desk_endcap_highlight)

	# Endcap middle grain line
	var desk_endcap_grain = ColorRect.new()
	desk_endcap_grain.name = "DeskEndcapGrain"
	desk_endcap_grain.set_anchors_preset(Control.PRESET_CENTER)
	desk_endcap_grain.size = Vector2(3400, 2)
	desk_endcap_grain.position = Vector2(-1700, endcap_y + 15)
	desk_endcap_grain.color = Color(0.14, 0.08, 0.04)
	desk_extensions.add_child(desk_endcap_grain)

	# Endcap shadow (bottom edge)
	var desk_endcap_shadow = ColorRect.new()
	desk_endcap_shadow.name = "DeskEndcapShadow"
	desk_endcap_shadow.set_anchors_preset(Control.PRESET_CENTER)
	desk_endcap_shadow.size = Vector2(3400, 5)
	desk_endcap_shadow.position = Vector2(-1700, endcap_y + endcap_height - 5)
	desk_endcap_shadow.color = Color(0.10, 0.06, 0.03)
	desk_extensions.add_child(desk_endcap_shadow)

	# === POWER OUTLET ON WALL ===
	var outlet_y = 480  # Near floor
	var outlet_x = -500

	# Outlet plate (drawn first, so cord appears on top)
	var outlet_plate = ColorRect.new()
	outlet_plate.name = "OutletPlate"
	outlet_plate.set_anchors_preset(Control.PRESET_CENTER)
	outlet_plate.size = Vector2(50, 70)
	outlet_plate.position = Vector2(outlet_x, outlet_y)
	outlet_plate.color = Color(0.85, 0.82, 0.78)  # Off-white plastic
	desk_extensions.add_child(outlet_plate)

	# Outlet plate border/shadow
	var outlet_border = ColorRect.new()
	outlet_border.name = "OutletBorder"
	outlet_border.set_anchors_preset(Control.PRESET_CENTER)
	outlet_border.size = Vector2(46, 66)
	outlet_border.position = Vector2(outlet_x + 2, outlet_y + 2)
	outlet_border.color = Color(0.75, 0.72, 0.68)
	desk_extensions.add_child(outlet_border)

	# Outlet plate inner
	var outlet_inner = ColorRect.new()
	outlet_inner.name = "OutletInner"
	outlet_inner.set_anchors_preset(Control.PRESET_CENTER)
	outlet_inner.size = Vector2(42, 62)
	outlet_inner.position = Vector2(outlet_x + 4, outlet_y + 4)
	outlet_inner.color = Color(0.88, 0.85, 0.80)
	desk_extensions.add_child(outlet_inner)

	# Top socket hole (left) - this one will have plug in it
	var socket1_left = ColorRect.new()
	socket1_left.name = "Socket1Left"
	socket1_left.set_anchors_preset(Control.PRESET_CENTER)
	socket1_left.size = Vector2(6, 14)
	socket1_left.position = Vector2(outlet_x + 12, outlet_y + 12)
	socket1_left.color = Color(0.15, 0.12, 0.10)
	desk_extensions.add_child(socket1_left)

	# Top socket hole (right) - this one will have plug in it
	var socket1_right = ColorRect.new()
	socket1_right.name = "Socket1Right"
	socket1_right.set_anchors_preset(Control.PRESET_CENTER)
	socket1_right.size = Vector2(6, 14)
	socket1_right.position = Vector2(outlet_x + 32, outlet_y + 12)
	socket1_right.color = Color(0.15, 0.12, 0.10)
	desk_extensions.add_child(socket1_right)

	# Bottom socket hole (left) - unused
	var socket2_left = ColorRect.new()
	socket2_left.name = "Socket2Left"
	socket2_left.set_anchors_preset(Control.PRESET_CENTER)
	socket2_left.size = Vector2(6, 14)
	socket2_left.position = Vector2(outlet_x + 12, outlet_y + 42)
	socket2_left.color = Color(0.15, 0.12, 0.10)
	desk_extensions.add_child(socket2_left)

	# Bottom socket hole (right) - unused
	var socket2_right = ColorRect.new()
	socket2_right.name = "Socket2Right"
	socket2_right.set_anchors_preset(Control.PRESET_CENTER)
	socket2_right.size = Vector2(6, 14)
	socket2_right.position = Vector2(outlet_x + 32, outlet_y + 42)
	socket2_right.color = Color(0.15, 0.12, 0.10)
	desk_extensions.add_child(socket2_right)

	# === POWER CORD (drawn on top of outlet) ===
	# Cord coming from desk down to the outlet
	var cord_start_y = endcap_y + endcap_height  # Bottom of desk
	var cord_plug_y = outlet_y + 8  # Top of plug area

	# Vertical section of cord (hanging down from desk to plug)
	var cord_vertical = ColorRect.new()
	cord_vertical.name = "PowerCordVertical"
	cord_vertical.set_anchors_preset(Control.PRESET_CENTER)
	cord_vertical.size = Vector2(8, cord_plug_y - cord_start_y)
	cord_vertical.position = Vector2(outlet_x + 21, cord_start_y)
	cord_vertical.color = Color(0.1, 0.1, 0.1)  # Black cord
	desk_extensions.add_child(cord_vertical)

	# Cord shadow/highlight
	var cord_highlight = ColorRect.new()
	cord_highlight.name = "PowerCordHighlight"
	cord_highlight.set_anchors_preset(Control.PRESET_CENTER)
	cord_highlight.size = Vector2(2, cord_plug_y - cord_start_y)
	cord_highlight.position = Vector2(outlet_x + 21, cord_start_y)
	cord_highlight.color = Color(0.2, 0.2, 0.2)  # Slight highlight on left edge
	desk_extensions.add_child(cord_highlight)

	# Plug body (the rectangular part that sits against the outlet)
	var plug_body = ColorRect.new()
	plug_body.name = "PlugBody"
	plug_body.set_anchors_preset(Control.PRESET_CENTER)
	plug_body.size = Vector2(34, 24)
	plug_body.position = Vector2(outlet_x + 8, outlet_y + 6)
	plug_body.color = Color(0.12, 0.12, 0.12)  # Dark plug
	desk_extensions.add_child(plug_body)

	# Plug highlight
	var plug_highlight = ColorRect.new()
	plug_highlight.name = "PlugHighlight"
	plug_highlight.set_anchors_preset(Control.PRESET_CENTER)
	plug_highlight.size = Vector2(34, 3)
	plug_highlight.position = Vector2(outlet_x + 8, outlet_y + 6)
	plug_highlight.color = Color(0.22, 0.22, 0.22)
	desk_extensions.add_child(plug_highlight)

	# === UNDER-DESK SHADOW ===
	# Dark gradient/shadow over the plug and outlet area (under the desk)
	var shadow_under_desk = ColorRect.new()
	shadow_under_desk.name = "UnderDeskShadow"
	shadow_under_desk.set_anchors_preset(Control.PRESET_CENTER)
	shadow_under_desk.size = Vector2(200, 180)
	shadow_under_desk.position = Vector2(outlet_x - 70, outlet_y - 60)
	shadow_under_desk.color = Color(0.0, 0.0, 0.0, 0.4)  # Semi-transparent black
	desk_extensions.add_child(shadow_under_desk)

	# Deeper shadow closer to desk bottom
	var shadow_deep = ColorRect.new()
	shadow_deep.name = "UnderDeskShadowDeep"
	shadow_deep.set_anchors_preset(Control.PRESET_CENTER)
	shadow_deep.size = Vector2(200, 60)
	shadow_deep.position = Vector2(outlet_x - 70, outlet_y - 60)
	shadow_deep.color = Color(0.0, 0.0, 0.0, 0.3)  # Additional darkness at top
	desk_extensions.add_child(shadow_deep)

	print("[ZoomManager] Desk extensions created")


func _create_extended_shelves() -> void:
	# All shelves extend to the left edge of the scene (x = -1600)
	var shelf_left_edge = -1600

	# Upper shelf (above existing shelves) - extends to far left, positioned higher
	var shelf_upper = ColorRect.new()
	shelf_upper.name = "ShelfUpper"
	shelf_upper.set_anchors_preset(Control.PRESET_CENTER)
	shelf_upper.size = Vector2(1100, 18)
	shelf_upper.position = Vector2(shelf_left_edge, -480)
	shelf_upper.color = Color(0.35, 0.22, 0.12)
	room_elements.add_child(shelf_upper)

	# Shelf edge highlight
	var shelf_upper_edge = ColorRect.new()
	shelf_upper_edge.name = "ShelfUpperEdge"
	shelf_upper_edge.set_anchors_preset(Control.PRESET_CENTER)
	shelf_upper_edge.size = Vector2(1100, 4)
	shelf_upper_edge.position = Vector2(shelf_left_edge, -480)
	shelf_upper_edge.color = Color(0.48, 0.32, 0.2)
	room_elements.add_child(shelf_upper_edge)

	# Shelf bottom shadow
	var shelf_upper_shadow = ColorRect.new()
	shelf_upper_shadow.name = "ShelfUpperShadow"
	shelf_upper_shadow.set_anchors_preset(Control.PRESET_CENTER)
	shelf_upper_shadow.size = Vector2(1100, 5)
	shelf_upper_shadow.position = Vector2(shelf_left_edge, -462)
	shelf_upper_shadow.color = Color(0.22, 0.13, 0.07)
	room_elements.add_child(shelf_upper_shadow)

	# Extended shelf 1 (continuing existing WoodShelf1 to the left edge)
	var shelf_ext1 = ColorRect.new()
	shelf_ext1.name = "ShelfExt1"
	shelf_ext1.set_anchors_preset(Control.PRESET_CENTER)
	shelf_ext1.size = Vector2(1000, 18)
	shelf_ext1.position = Vector2(shelf_left_edge, -300)
	shelf_ext1.color = Color(0.35, 0.22, 0.12)
	room_elements.add_child(shelf_ext1)

	var shelf_ext1_edge = ColorRect.new()
	shelf_ext1_edge.name = "ShelfExt1Edge"
	shelf_ext1_edge.set_anchors_preset(Control.PRESET_CENTER)
	shelf_ext1_edge.size = Vector2(1000, 4)
	shelf_ext1_edge.position = Vector2(shelf_left_edge, -300)
	shelf_ext1_edge.color = Color(0.48, 0.32, 0.2)
	room_elements.add_child(shelf_ext1_edge)

	var shelf_ext1_shadow = ColorRect.new()
	shelf_ext1_shadow.name = "ShelfExt1Shadow"
	shelf_ext1_shadow.set_anchors_preset(Control.PRESET_CENTER)
	shelf_ext1_shadow.size = Vector2(1000, 5)
	shelf_ext1_shadow.position = Vector2(shelf_left_edge, -282)
	shelf_ext1_shadow.color = Color(0.22, 0.13, 0.07)
	room_elements.add_child(shelf_ext1_shadow)

	# Extended shelf 2 (continuing existing WoodShelf2 to the left edge)
	var shelf_ext2 = ColorRect.new()
	shelf_ext2.name = "ShelfExt2"
	shelf_ext2.set_anchors_preset(Control.PRESET_CENTER)
	shelf_ext2.size = Vector2(1000, 18)
	shelf_ext2.position = Vector2(shelf_left_edge, -190)
	shelf_ext2.color = Color(0.35, 0.22, 0.12)
	room_elements.add_child(shelf_ext2)

	var shelf_ext2_edge = ColorRect.new()
	shelf_ext2_edge.name = "ShelfExt2Edge"
	shelf_ext2_edge.set_anchors_preset(Control.PRESET_CENTER)
	shelf_ext2_edge.size = Vector2(1000, 4)
	shelf_ext2_edge.position = Vector2(shelf_left_edge, -190)
	shelf_ext2_edge.color = Color(0.48, 0.32, 0.2)
	room_elements.add_child(shelf_ext2_edge)

	var shelf_ext2_shadow = ColorRect.new()
	shelf_ext2_shadow.name = "ShelfExt2Shadow"
	shelf_ext2_shadow.set_anchors_preset(Control.PRESET_CENTER)
	shelf_ext2_shadow.size = Vector2(1000, 5)
	shelf_ext2_shadow.position = Vector2(shelf_left_edge, -172)
	shelf_ext2_shadow.color = Color(0.22, 0.13, 0.07)
	room_elements.add_child(shelf_ext2_shadow)

	# Some items on the upper shelf (books)
	_create_shelf_items()


func _create_lighting_system() -> void:
	# Create ambient light that affects the entire scene at ALL zoom levels
	ambient_light = CanvasModulate.new()
	ambient_light.name = "AmbientLight"
	ambient_light.color = Color(1, 1, 1, 1)  # Start with no tint
	main_node.add_child(ambient_light)  # Add to main so it applies at all zoom levels

	# Create gradient texture for point lights
	var gradient = Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.add_point(0.15, Color(1, 1, 1, 0.7))
	gradient.add_point(0.4, Color(1, 1, 1, 0.3))
	gradient.add_point(0.7, Color(1, 1, 1, 0.1))
	gradient.set_offset(gradient.get_point_count() - 1, 1.0)
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))

	var texture = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 512
	texture.height = 512
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	# Create a container for lights that uses center anchoring (like scene elements)
	light_container = Control.new()
	light_container.name = "LightContainer"
	light_container.set_anchors_preset(Control.PRESET_CENTER)
	light_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_container.add_child(light_container)

	# Main window light - positioned at the window (right side of scene)
	# Light comes from right, casts shadows to the left
	window_light = PointLight2D.new()
	window_light.name = "WindowLight"
	window_light.position = Vector2(900, -200)  # Right side, where window is
	window_light.texture = texture
	window_light.texture_scale = 12.0
	window_light.shadow_enabled = true
	window_light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF13  # Higher quality filter
	window_light.shadow_filter_smooth = 8.0  # Much smoother shadows
	window_light.shadow_color = Color(0.02, 0.02, 0.06, 0.35)  # Softer, more subtle shadows
	window_light.blend_mode = Light2D.BLEND_MODE_ADD
	light_container.add_child(window_light)

	# Secondary floor light - angled light hitting the desk from window direction
	floor_light = PointLight2D.new()
	floor_light.name = "FloorLight"
	floor_light.position = Vector2(200, 100)  # Light landing on desk area
	floor_light.texture = texture
	floor_light.texture_scale = 8.0
	floor_light.shadow_enabled = true
	floor_light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF13
	floor_light.shadow_filter_smooth = 6.0
	floor_light.shadow_color = Color(0.02, 0.02, 0.06, 0.3)
	floor_light.blend_mode = Light2D.BLEND_MODE_ADD
	light_container.add_child(floor_light)

	# Create floating dust particles in the light
	_create_dust_particles()

	# Apply initial lighting based on time and blinds state
	_update_lighting()

	print("[ZoomManager] Lighting system created")


func _create_light_switch() -> void:
	# Create a wall light switch to the left of the lava lamp
	# LavaLamp is at offset_left = -600 from center, so switch is around -700

	var switch_x = -720
	var switch_y = -50  # Wall height, accessible

	# White faceplate
	var faceplate = ColorRect.new()
	faceplate.name = "LightSwitchPlate"
	faceplate.set_anchors_preset(Control.PRESET_CENTER)
	faceplate.size = Vector2(40, 70)
	faceplate.position = Vector2(switch_x, switch_y)
	faceplate.color = Color(0.92, 0.9, 0.88)  # Off-white plastic
	room_elements.add_child(faceplate)

	# Faceplate border shadow
	var plate_border = ColorRect.new()
	plate_border.name = "LightSwitchBorder"
	plate_border.set_anchors_preset(Control.PRESET_CENTER)
	plate_border.size = Vector2(36, 66)
	plate_border.position = Vector2(switch_x + 2, switch_y + 2)
	plate_border.color = Color(0.82, 0.8, 0.78)
	room_elements.add_child(plate_border)

	# Inner plate
	var plate_inner = ColorRect.new()
	plate_inner.name = "LightSwitchInner"
	plate_inner.set_anchors_preset(Control.PRESET_CENTER)
	plate_inner.size = Vector2(32, 62)
	plate_inner.position = Vector2(switch_x + 4, switch_y + 4)
	plate_inner.color = Color(0.94, 0.92, 0.9)
	room_elements.add_child(plate_inner)

	# Toggle switch slot (dark background)
	var switch_slot = ColorRect.new()
	switch_slot.name = "SwitchSlot"
	switch_slot.set_anchors_preset(Control.PRESET_CENTER)
	switch_slot.size = Vector2(16, 30)
	switch_slot.position = Vector2(switch_x + 12, switch_y + 20)
	switch_slot.color = Color(0.15, 0.12, 0.1)
	room_elements.add_child(switch_slot)

	# The clickable toggle switch
	light_switch = Control.new()
	light_switch.name = "LightSwitch"
	light_switch.set_anchors_preset(Control.PRESET_CENTER)
	light_switch.size = Vector2(40, 70)
	light_switch.position = Vector2(switch_x, switch_y)
	light_switch.mouse_filter = Control.MOUSE_FILTER_STOP
	light_switch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	room_elements.add_child(light_switch)

	# Toggle lever (visible part)
	light_switch_toggle = ColorRect.new()
	light_switch_toggle.name = "SwitchToggle"
	light_switch_toggle.set_anchors_preset(Control.PRESET_CENTER)
	light_switch_toggle.size = Vector2(12, 18)
	light_switch_toggle.position = Vector2(switch_x + 14, switch_y + 28)  # Down position (off)
	light_switch_toggle.color = Color(0.85, 0.83, 0.8)
	room_elements.add_child(light_switch_toggle)

	# Connect click handler
	light_switch.gui_input.connect(_on_light_switch_input)

	# Create overhead light (off-screen above bookshelf area)
	_create_overhead_light()

	print("[ZoomManager] Light switch created")


func _create_overhead_light() -> void:
	# Create gradient texture for overhead light
	var gradient = Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.add_point(0.2, Color(1, 1, 1, 0.8))
	gradient.add_point(0.5, Color(1, 1, 1, 0.4))
	gradient.add_point(0.8, Color(1, 1, 1, 0.1))
	gradient.set_offset(gradient.get_point_count() - 1, 1.0)
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))

	var texture = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 512
	texture.height = 512
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	# Overhead ceiling light - positioned centrally to illuminate entire scene
	overhead_light = PointLight2D.new()
	overhead_light.name = "OverheadLight"
	overhead_light.position = Vector2(0, -600)  # Central position, above desk area
	overhead_light.texture = texture
	overhead_light.texture_scale = 30.0  # Very large coverage for whole room
	overhead_light.color = Color(1.0, 0.95, 0.85)  # Warm incandescent
	overhead_light.energy = 0.0  # Start off
	overhead_light.enabled = false
	overhead_light.shadow_enabled = false  # No shadows from overhead room light
	overhead_light.blend_mode = Light2D.BLEND_MODE_ADD
	light_container.add_child(overhead_light)

	print("[ZoomManager] Overhead light created")


func _on_light_switch_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_overhead_light()


func _toggle_overhead_light() -> void:
	overhead_light_on = not overhead_light_on

	if overhead_light_on:
		# Turn on - move toggle up, enable light
		if light_switch_toggle:
			light_switch_toggle.position.y -= 10  # Move toggle up
		if overhead_light:
			overhead_light.enabled = true
			var tween = create_tween()
			tween.tween_property(overhead_light, "energy", 0.7, 0.2)  # Balanced brightness
		print("[ZoomManager] Overhead light ON")
	else:
		# Turn off - move toggle down, disable light
		if light_switch_toggle:
			light_switch_toggle.position.y += 10  # Move toggle down
		if overhead_light:
			var tween = create_tween()
			tween.tween_property(overhead_light, "energy", 0.0, 0.15)
			tween.tween_callback(func(): overhead_light.enabled = false)
		print("[ZoomManager] Overhead light OFF")


func _create_dust_particles() -> void:
	# Floating dust motes visible in the light
	dust_particles = GPUParticles2D.new()
	dust_particles.name = "DustParticles"
	dust_particles.position = Vector2(100, -50)  # Slightly right of center (toward window light)
	dust_particles.amount = 80
	dust_particles.lifetime = 12.0
	dust_particles.preprocess = 6.0  # Pre-fill so particles exist at start
	dust_particles.randomness = 0.5
	dust_particles.visibility_rect = Rect2(-800, -500, 1600, 800)

	# Create the particle material
	var material = ParticleProcessMaterial.new()

	# Emission - spread across a large area
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(600, 350, 0)

	# Movement - slow, gentle floating
	material.direction = Vector3(0, -0.3, 0)  # Slight upward drift
	material.spread = 180.0  # All directions
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 8.0

	# Add some turbulence/randomness
	material.gravity = Vector3(0, -2, 0)  # Very slight lift
	material.turbulence_enabled = true
	material.turbulence_noise_strength = 1.5
	material.turbulence_noise_scale = 4.0
	material.turbulence_influence_min = 0.1
	material.turbulence_influence_max = 0.3

	# Size - tiny specks
	material.scale_min = 0.5
	material.scale_max = 1.5

	# Fade in and out
	material.alpha_curve = _create_dust_alpha_curve()

	# Color - warm light color, will be modulated by lighting
	material.color = Color(1.0, 0.95, 0.85, 0.6)

	dust_particles.process_material = material

	# Simple circular texture for particles
	var particle_texture = _create_dust_texture()
	dust_particles.texture = particle_texture

	light_container.add_child(dust_particles)  # Add to center-anchored container


func _create_dust_alpha_curve() -> Curve:
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.0))    # Start invisible
	curve.add_point(Vector2(0.1, 0.8))    # Fade in
	curve.add_point(Vector2(0.5, 1.0))    # Full visibility
	curve.add_point(Vector2(0.9, 0.8))    # Start fading
	curve.add_point(Vector2(1.0, 0.0))    # End invisible
	return curve


func _create_dust_texture() -> ImageTexture:
	# Create a small soft circle for dust particles
	var size = 8
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2.0, size / 2.0)
	var radius = size / 2.0

	for x in range(size):
		for y in range(size):
			var dist = Vector2(x, y).distance_to(center)
			var alpha = clamp(1.0 - (dist / radius), 0.0, 1.0)
			alpha = alpha * alpha  # Softer falloff
			image.set_pixel(x, y, Color(1, 1, 1, alpha))

	var texture = ImageTexture.create_from_image(image)
	return texture


func _create_celestial_texture() -> ImageTexture:
	# Create a soft circular glow for sun/moon
	var size = 64
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2.0, size / 2.0)
	var radius = size / 2.0

	for x in range(size):
		for y in range(size):
			var dist = Vector2(x, y).distance_to(center)
			var alpha = clamp(1.0 - (dist / radius), 0.0, 1.0)
			# Soft glow falloff
			alpha = pow(alpha, 0.5)  # Softer edge
			image.set_pixel(x, y, Color(1, 1, 1, alpha))

	var texture = ImageTexture.create_from_image(image)
	return texture


func _create_light_occluders() -> void:
	# Container for occluders using center anchoring (like scene elements)
	var occluder_control = Control.new()
	occluder_control.name = "OccluderContainer"
	occluder_control.set_anchors_preset(Control.PRESET_CENTER)
	occluder_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_container.add_child(occluder_control)

	light_occluder_container = Node2D.new()
	light_occluder_container.name = "LightOccluders"
	occluder_control.add_child(light_occluder_container)

	# Positions are now relative to center (like PRESET_CENTER elements)
	# Computer monitor occluder - casts shadow to the left onto wall/desk
	_add_box_occluder("MonitorOccluder", Vector2(-50, -180), Vector2(300, 220))

	# Computer base unit occluder
	_add_box_occluder("BaseUnitOccluder", Vector2(-50, 80), Vector2(280, 100))

	# Keyboard occluder
	_add_box_occluder("KeyboardOccluder", Vector2(-50, 130), Vector2(320, 30))

	# Shelf occluders (shelves are on the left side)
	_add_box_occluder("Shelf1Occluder", Vector2(-500, -300), Vector2(400, 15))
	_add_box_occluder("Shelf2Occluder", Vector2(-500, -190), Vector2(400, 15))

	# Lava lamp occluder
	_add_box_occluder("LavaLampOccluder", Vector2(-450, -50), Vector2(40, 120))

	# Desk phone occluder
	_add_box_occluder("PhoneOccluder", Vector2(-380, 50), Vector2(60, 80))

	# Poster occluder (poster is on left wall)
	_add_box_occluder("PosterOccluder", Vector2(380, -220), Vector2(100, 140))

	print("[ZoomManager] Light occluders created")


func _add_box_occluder(occ_name: String, pos: Vector2, size: Vector2) -> void:
	var occluder = LightOccluder2D.new()
	occluder.name = occ_name
	occluder.position = pos

	var polygon = OccluderPolygon2D.new()
	var half_w = size.x / 2
	var half_h = size.y / 2
	polygon.polygon = PackedVector2Array([
		Vector2(-half_w, -half_h),
		Vector2(half_w, -half_h),
		Vector2(half_w, half_h),
		Vector2(-half_w, half_h)
	])
	occluder.occluder = polygon

	light_occluder_container.add_child(occluder)


func _get_current_hour() -> float:
	if force_time_hour >= 0:
		return force_time_hour
	var time_dict = Time.get_time_dict_from_system()
	return time_dict.hour + (time_dict.minute / 60.0)


func _get_time_period(hour: float) -> String:
	if hour < 5.5 or hour >= 20.5:
		return "night"
	elif hour < 7.0:
		return "dawn"
	elif hour < 10.0:
		return "morning"
	elif hour < 15.0:
		return "midday"
	elif hour < 18.0:
		return "afternoon"
	elif hour < 20.5:
		return "dusk"
	else:
		return "night"


func _lerp_color(a: Color, b: Color, t: float) -> Color:
	return Color(
		lerp(a.r, b.r, t),
		lerp(a.g, b.g, t),
		lerp(a.b, b.b, t),
		lerp(a.a, b.a, t)
	)


func _get_blended_lighting() -> Dictionary:
	var hour = _get_current_hour()
	var period = _get_time_period(hour)
	var preset = LIGHTING_PRESETS[period]

	# Get transition factor for smooth blending between periods
	var blend_factor = 0.0
	var next_preset = preset

	# Define period boundaries and blend zones
	if hour >= 5.5 and hour < 7.0:  # dawn
		blend_factor = (hour - 5.5) / 1.5
		next_preset = LIGHTING_PRESETS["morning"] if hour >= 6.25 else LIGHTING_PRESETS["night"]
		preset = LIGHTING_PRESETS["night"] if hour < 6.25 else LIGHTING_PRESETS["dawn"]
	elif hour >= 18.0 and hour < 20.5:  # dusk
		blend_factor = (hour - 18.0) / 2.5
		next_preset = LIGHTING_PRESETS["night"] if hour >= 19.25 else LIGHTING_PRESETS["dusk"]
		preset = LIGHTING_PRESETS["afternoon"] if hour < 19.25 else LIGHTING_PRESETS["dusk"]

	# Blend between presets if in transition
	if blend_factor > 0:
		return {
			"light_color": _lerp_color(preset["light_color"], next_preset["light_color"], blend_factor),
			"light_energy": lerp(preset["light_energy"], next_preset["light_energy"], blend_factor),
			"ambient": _lerp_color(preset["ambient"], next_preset["ambient"], blend_factor),
			"sky_color": _lerp_color(preset["sky_color"], next_preset["sky_color"], blend_factor),
			"celestial_color": _lerp_color(preset["celestial_color"], next_preset["celestial_color"], blend_factor),
		}

	return preset


func _is_daytime() -> bool:
	if force_day_night == 1:
		return true
	elif force_day_night == 0:
		return false
	else:
		var hour = _get_current_hour()
		return hour >= 6 and hour < 18


func _calculate_room_lighting() -> Dictionary:
	# Get base lighting from time of day
	var time_lighting = _get_blended_lighting()

	# Get blinds factor
	var blinds_factor = BLINDS_LIGHT_FACTOR[blinds_state]

	# Calculate effective light energy (time-based * blinds factor)
	var effective_energy = time_lighting["light_energy"] * blinds_factor

	# Calculate ambient - brighter when blinds open, darker when closed
	# Base ambient is dim, window light adds to it
	var base_ambient = Color(0.08, 0.08, 0.1)  # Very dark base
	var lit_ambient = time_lighting["ambient"]
	var effective_ambient = _lerp_color(base_ambient, lit_ambient, blinds_factor)

	return {
		"light_color": time_lighting["light_color"],
		"light_energy": effective_energy,
		"floor_energy": effective_energy * 0.6,
		"ambient": effective_ambient,
		"sky_color": time_lighting["sky_color"],
		"celestial_color": time_lighting["celestial_color"],
		"blinds_factor": blinds_factor,
	}


func _calculate_room_lighting_for_state(state: int) -> Dictionary:
	# Calculate lighting for a specific blinds state (for transitions)
	var time_lighting = _get_blended_lighting()
	var blinds_factor = BLINDS_LIGHT_FACTOR[state]
	var effective_energy = time_lighting["light_energy"] * blinds_factor

	var base_ambient = Color(0.08, 0.08, 0.1)
	var lit_ambient = time_lighting["ambient"]
	var effective_ambient = _lerp_color(base_ambient, lit_ambient, blinds_factor)

	return {
		"light_color": time_lighting["light_color"],
		"light_energy": effective_energy,
		"floor_energy": effective_energy * 0.6,
		"ambient": effective_ambient,
		"sky_color": time_lighting["sky_color"],
		"celestial_color": time_lighting["celestial_color"],
		"blinds_factor": blinds_factor,
	}


func _animate_lighting_transition(tween: Tween, from_lighting: Dictionary, to_lighting: Dictionary, duration: float) -> void:
	# Animate window light
	if window_light:
		tween.parallel().tween_property(window_light, "color", to_lighting["light_color"], duration)
		tween.parallel().tween_property(window_light, "energy", to_lighting["light_energy"], duration)

	# Animate floor light
	if floor_light:
		tween.parallel().tween_property(floor_light, "color", to_lighting["light_color"], duration)
		tween.parallel().tween_property(floor_light, "energy", to_lighting["floor_energy"], duration)

	# Animate ambient light (this creates the overall room brightness change)
	if ambient_light:
		tween.parallel().tween_property(ambient_light, "color", to_lighting["ambient"], duration)


func _update_lighting() -> void:
	var lighting = _calculate_room_lighting()

	# Compensate light intensity for zoom level
	# At Room View (0.5x), lights need to be stronger to appear the same
	# At Monitor View (2.0x), lights need to be weaker
	var zoom_scale = ZOOM_SCALES[current_level].x
	var intensity_compensation = 1.0 / zoom_scale  # Inverse of zoom scale

	# Update window light
	if window_light:
		window_light.color = lighting["light_color"]
		window_light.energy = lighting["light_energy"] * intensity_compensation
		# Also compensate texture scale so light covers consistent area
		window_light.texture_scale = 12.0 / zoom_scale

	# Update floor light
	if floor_light:
		floor_light.color = lighting["light_color"]
		floor_light.energy = lighting["floor_energy"] * intensity_compensation
		floor_light.texture_scale = 8.0 / zoom_scale

	# Update ambient light (affects whole scene)
	if ambient_light:
		ambient_light.color = lighting["ambient"]

	# Update window glass (sky color)
	if window_glass:
		window_glass.color = lighting["sky_color"]

	# Update sun/moon (TextureRect uses modulate for color)
	if sun_moon_sprite:
		var celestial_color = lighting["celestial_color"]
		# Preserve current alpha when updating color
		var current_alpha = sun_moon_sprite.modulate.a
		sun_moon_sprite.modulate = Color(celestial_color.r, celestial_color.g, celestial_color.b, current_alpha)
		# Size based on whether sun or moon
		var is_day = _is_daytime()
		if is_day:
			sun_moon_sprite.size = Vector2(120, 120)
			sun_moon_sprite.position = Vector2(200, 150)
		else:
			sun_moon_sprite.size = Vector2(80, 80)
			sun_moon_sprite.position = Vector2(220, 180)

	# Update blind gap colors based on lighting
	var gap_intensity = lighting["blinds_factor"] * 0.6 + 0.1
	var gap_color = _lerp_color(
		Color(0.1, 0.1, 0.15, 0.2),
		Color(lighting["light_color"].r, lighting["light_color"].g, lighting["light_color"].b, 0.6),
		gap_intensity
	)
	for slat_data in blind_slats:
		var gap_node: ColorRect = slat_data["gap"]
		if gap_node:
			gap_node.color = gap_color

	# Update dust particles - more visible when more light
	if dust_particles:
		var dust_alpha = lighting["blinds_factor"] * 0.8  # More dust visible with more light
		var dust_color = Color(
			lighting["light_color"].r,
			lighting["light_color"].g,
			lighting["light_color"].b,
			dust_alpha
		)
		dust_particles.modulate = dust_color
		# Also adjust amount based on light level
		dust_particles.amount = int(40 + 60 * lighting["blinds_factor"])

	print("[ZoomManager] Lighting updated - blinds: %s, energy: %.2f" % [
		["CLOSED", "TILTED", "OPEN"][blinds_state],
		lighting["light_energy"]
	])


func toggle_day_night() -> void:
	# Cycle through test times: auto -> morning (9am) -> midday (12pm) -> dusk (19pm) -> night (23pm) -> auto
	if force_time_hour < 0:
		force_time_hour = 9.0
		print("[ZoomManager] Test mode: MORNING (9:00)")
	elif force_time_hour < 11:
		force_time_hour = 12.0
		print("[ZoomManager] Test mode: MIDDAY (12:00)")
	elif force_time_hour < 15:
		force_time_hour = 19.0
		print("[ZoomManager] Test mode: DUSK (19:00)")
	elif force_time_hour < 21:
		force_time_hour = 23.0
		print("[ZoomManager] Test mode: NIGHT (23:00)")
	else:
		force_time_hour = -1.0
		print("[ZoomManager] Test mode: AUTO (system time)")

	_update_lighting()


func _input(event: InputEvent) -> void:
	# F5 to cycle through time presets for testing
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_F5:
			toggle_day_night()
		# F6 to manually step time forward by 1 hour
		elif event.keycode == KEY_F6:
			if force_time_hour < 0:
				force_time_hour = _get_current_hour()
			force_time_hour = fmod(force_time_hour + 1.0, 24.0)
			print("[ZoomManager] Time: %.1f:00" % force_time_hour)
			_update_lighting()


func _instant_zoom_to_room() -> void:
	# Instantly set to ROOM level without animation (for startup)
	if not zoom_container:
		return

	var level = ZoomLevel.ROOM
	var viewport_size = main_node.get_viewport_rect().size

	# Set scale and pivot instantly
	zoom_container.scale = ZOOM_SCALES[level]
	zoom_container.pivot_offset = viewport_size * ZOOM_PIVOTS[level]

	# Show room elements instantly
	if room_elements:
		room_elements.visible = true
		room_elements.modulate.a = 1.0

	if desk_extensions:
		desk_extensions.visible = true
		desk_extensions.modulate.a = 1.0

	current_level = level
	target_level = level
	_update_lighting()
	zoom_changed.emit(level)
	print("[ZoomManager] Started at ROOM level")


func zoom_to(level: int) -> void:
	if level == target_level:
		return

	# If currently transitioning, queue this level for after transition ends
	if is_transitioning:
		queued_level = level
		return

	target_level = level
	queued_level = -1  # Clear any queued level since we're processing this one

	if not zoom_container:
		print("[ZoomManager] No zoom container - cannot zoom")
		return

	print("[ZoomManager] Zooming from level %d to level %d" % [current_level, level])
	is_transitioning = true

	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Get target values
	var target_scale = ZOOM_SCALES[level]

	# Calculate pivot based on viewport size
	var viewport_size = main_node.get_viewport_rect().size
	var target_pivot = viewport_size * ZOOM_PIVOTS[level]

	# Animate scale
	tween.tween_property(zoom_container, "scale", target_scale, TRANSITION_DURATION)

	# Animate pivot offset for smooth centering
	tween.parallel().tween_property(zoom_container, "pivot_offset", target_pivot, TRANSITION_DURATION)

	# Handle room elements visibility
	if room_elements:
		if level == ZoomLevel.ROOM and current_level != ZoomLevel.ROOM:
			# Zooming out to room - fade in room elements
			room_elements.visible = true
			tween.parallel().tween_property(room_elements, "modulate:a", 1.0, TRANSITION_DURATION)
		elif level != ZoomLevel.ROOM and current_level == ZoomLevel.ROOM:
			# Zooming in from room - fade out room elements
			tween.parallel().tween_property(room_elements, "modulate:a", 0.0, TRANSITION_DURATION)
			tween.tween_callback(func(): room_elements.visible = false)

	# Handle desk extensions visibility (same as room elements but separate container)
	if desk_extensions:
		if level == ZoomLevel.ROOM and current_level != ZoomLevel.ROOM:
			# Zooming out to room - fade in desk extensions
			desk_extensions.visible = true
			tween.parallel().tween_property(desk_extensions, "modulate:a", 1.0, TRANSITION_DURATION)
		elif level != ZoomLevel.ROOM and current_level == ZoomLevel.ROOM:
			# Zooming in from room - fade out desk extensions
			tween.parallel().tween_property(desk_extensions, "modulate:a", 0.0, TRANSITION_DURATION)
			tween.tween_callback(func(): desk_extensions.visible = false)

	# Handle monitor zoom level - fade out keyboard/peripherals
	_handle_peripheral_visibility(tween, level)

	# Handle SCREEN level - show/hide fullscreen viewport overlay
	if screen_overlay:
		if level == ZoomLevel.SCREEN:
			# Show overlay (viewport texture auto-syncs, shows terminal + editor)
			screen_overlay.visible = true
			screen_overlay.modulate.a = 0.0
			tween.parallel().tween_property(screen_overlay, "modulate:a", 1.0, TRANSITION_DURATION)
			# Hide the zoomed scene behind the overlay
			tween.parallel().tween_property(zoom_container, "modulate:a", 0.0, TRANSITION_DURATION)
		elif current_level == ZoomLevel.SCREEN:
			# Leaving SCREEN level - fade out overlay, show scene
			tween.parallel().tween_property(screen_overlay, "modulate:a", 0.0, TRANSITION_DURATION)
			tween.parallel().tween_property(zoom_container, "modulate:a", 1.0, TRANSITION_DURATION)
			tween.tween_callback(func(): screen_overlay.visible = false)

	# Complete transition
	tween.tween_callback(func():
		is_transitioning = false
		current_level = level
		# Update lighting to compensate for new zoom level
		_update_lighting()
		zoom_changed.emit(level)
		print("[ZoomManager] Zoom complete - now at level %d" % level)

		# Check for queued zoom level (if user pressed Tab during transition)
		if queued_level > 0 and queued_level != level:
			var next_level = queued_level
			queued_level = -1
			# Use call_deferred to process next frame
			call_deferred("zoom_to", next_level)
	)


func _handle_peripheral_visibility(tween: Tween, target_level: int) -> void:
	# Get references to elements that should fade at monitor zoom
	if not zoom_container:
		return

	var computer_frame = zoom_container.get_node_or_null("ComputerFrame")
	if not computer_frame:
		return

	var keyboard = computer_frame.get_node_or_null("Keyboard")
	var base_unit = computer_frame.get_node_or_null("BaseUnit")
	var hayes_modem = zoom_container.get_node_or_null("HayesModem")
	var desk_phone = zoom_container.get_node_or_null("DeskPhone")
	var lava_lamp = zoom_container.get_node_or_null("LavaLamp")

	if target_level == ZoomLevel.MONITOR:
		# Fade out peripheral elements when zooming to monitor
		if keyboard:
			tween.parallel().tween_property(keyboard, "modulate:a", 0.2, TRANSITION_DURATION)
		if base_unit:
			tween.parallel().tween_property(base_unit, "modulate:a", 0.2, TRANSITION_DURATION)
		if hayes_modem:
			tween.parallel().tween_property(hayes_modem, "modulate:a", 0.2, TRANSITION_DURATION)
		if desk_phone:
			tween.parallel().tween_property(desk_phone, "modulate:a", 0.0, TRANSITION_DURATION)
		if lava_lamp:
			tween.parallel().tween_property(lava_lamp, "modulate:a", 0.0, TRANSITION_DURATION)
	else:
		# Restore visibility when not at monitor zoom
		if keyboard:
			tween.parallel().tween_property(keyboard, "modulate:a", 1.0, TRANSITION_DURATION)
		if base_unit:
			tween.parallel().tween_property(base_unit, "modulate:a", 1.0, TRANSITION_DURATION)
		if hayes_modem:
			tween.parallel().tween_property(hayes_modem, "modulate:a", 1.0, TRANSITION_DURATION)
		if desk_phone:
			tween.parallel().tween_property(desk_phone, "modulate:a", 1.0, TRANSITION_DURATION)
		if lava_lamp:
			tween.parallel().tween_property(lava_lamp, "modulate:a", 1.0, TRANSITION_DURATION)


func zoom_in() -> void:
	if current_level < ZoomLevel.SCREEN:
		zoom_to(current_level + 1)


func zoom_out() -> void:
	if current_level > ZoomLevel.ROOM:
		zoom_to(current_level - 1)


func cycle_zoom() -> void:
	# Cycle: 1 -> 2 -> 3 -> 4 -> 1
	# Use target_level to allow queuing next level during transitions
	var next_level = (target_level % 4) + 1
	zoom_to(next_level)


func get_current_level() -> int:
	return current_level


func get_level_name() -> String:
	match current_level:
		ZoomLevel.ROOM:
			return "Room"
		ZoomLevel.DESKTOP:
			return "Desktop"
		ZoomLevel.MONITOR:
			return "Monitor"
		_:
			return "Unknown"


func _on_blinds_clicked() -> void:
	if blinds_transitioning:
		return

	# Cycle through states: CLOSED -> TILTED -> OPEN -> CLOSED
	match blinds_state:
		BlindsState.CLOSED:
			_tilt_blinds()
		BlindsState.TILTED:
			_open_blinds()
		BlindsState.OPEN:
			_close_blinds()


func _tilt_blinds() -> void:
	# Twist the blinds to let light through (like turning the rod)
	blinds_transitioning = true
	var old_state = blinds_state
	blinds_state = BlindsState.TILTED

	# Get lighting values for animation
	var old_lighting = _calculate_room_lighting_for_state(old_state)
	var new_lighting = _calculate_room_lighting_for_state(blinds_state)

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_SINE)

	# Animate each slat to tilt (shrink height to show gaps)
	for i in range(blind_slats.size()):
		var slat_data = blind_slats[i]
		var slat: ColorRect = slat_data["slat"]
		var gap: ColorRect = slat_data["gap"]
		var original_height = slat_data["original_height"]

		var delay = i * 0.01

		# Shrink slat height to simulate tilting open
		var tilted_height = original_height * 0.4
		tween.parallel().tween_property(slat, "size:y", tilted_height, 0.4).set_delay(delay)

		# Make gaps brighter (more light coming through)
		tween.parallel().tween_property(gap, "modulate", Color(1.5, 1.5, 1.3, 1.0), 0.4).set_delay(delay)

	# Slightly show sun/moon
	if sun_moon_sprite:
		tween.parallel().tween_property(sun_moon_sprite, "modulate:a", 0.3, 0.5)

	# Animate lighting transition
	_animate_lighting_transition(tween, old_lighting, new_lighting, 0.5)

	tween.tween_callback(func(): blinds_transitioning = false)

	print("[ZoomManager] Blinds tilted open")


func _open_blinds() -> void:
	# Fully open - collapse blinds at top
	blinds_transitioning = true
	var old_state = blinds_state
	blinds_state = BlindsState.OPEN

	# Get lighting values for animation
	var old_lighting = _calculate_room_lighting_for_state(old_state)
	var new_lighting = _calculate_room_lighting_for_state(blinds_state)

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Animate each slat to collapse upward
	for i in range(blind_slats.size()):
		var slat_data = blind_slats[i]
		var slat: ColorRect = slat_data["slat"]
		var gap: ColorRect = slat_data["gap"]

		# Calculate collapsed position (all slats bunch up at the top)
		var collapsed_y = i * 3
		var delay = i * 0.02

		# Animate slat moving up and shrinking
		tween.parallel().tween_property(slat, "position:y", collapsed_y, 0.6).set_delay(delay)
		tween.parallel().tween_property(slat, "size:y", 2.0, 0.6).set_delay(delay)
		tween.parallel().tween_property(slat, "modulate:a", 0.7, 0.6).set_delay(delay)

		# Fade out the gap indicators
		tween.parallel().tween_property(gap, "modulate:a", 0.0, 0.4).set_delay(delay)

	# Fade in sun/moon fully
	if sun_moon_sprite:
		tween.parallel().tween_property(sun_moon_sprite, "modulate:a", 1.0, 0.8).set_delay(0.3)

	# Animate lighting transition - brighten the room
	_animate_lighting_transition(tween, old_lighting, new_lighting, 0.7)

	tween.tween_callback(func(): blinds_transitioning = false)

	print("[ZoomManager] Blinds fully open")


func _close_blinds() -> void:
	# Close blinds completely
	blinds_transitioning = true
	var old_state = blinds_state
	blinds_state = BlindsState.CLOSED

	# Get lighting values for animation
	var old_lighting = _calculate_room_lighting_for_state(old_state)
	var new_lighting = _calculate_room_lighting_for_state(blinds_state)

	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Fade out sun/moon first
	if sun_moon_sprite:
		tween.tween_property(sun_moon_sprite, "modulate:a", 0.0, 0.3)

	# Animate each slat to return to original position
	for i in range(blind_slats.size()):
		var slat_data = blind_slats[i]
		var slat: ColorRect = slat_data["slat"]
		var gap: ColorRect = slat_data["gap"]
		var original_y = slat_data["original_y"]
		var original_height = slat_data["original_height"]

		var delay = (blind_slats.size() - i) * 0.015

		# Animate slat returning to original position and size
		tween.parallel().tween_property(slat, "position:y", original_y, 0.5).set_delay(delay)
		tween.parallel().tween_property(slat, "size:y", original_height, 0.5).set_delay(delay)
		tween.parallel().tween_property(slat, "modulate:a", 1.0, 0.5).set_delay(delay)

		# Reset gap color and fade in
		tween.parallel().tween_property(gap, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4).set_delay(delay + 0.1)

	# Animate lighting transition - darken the room
	_animate_lighting_transition(tween, old_lighting, new_lighting, 0.6)

	tween.tween_callback(func(): blinds_transitioning = false)

	print("[ZoomManager] Blinds closed")
