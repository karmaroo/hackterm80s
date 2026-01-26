extends Control
## Main game controller - Manages the computer frame, terminal, modem, and audio

# Computer state
enum ComputerState { OFF, BOOTING, ON }
var computer_state: ComputerState = ComputerState.OFF  # Player must turn it on

@onready var terminal = $ComputerFrame/Monitor/TerminalView/SubViewport/Terminal
@onready var terminal_view: SubViewportContainer = $ComputerFrame/Monitor/TerminalView
@onready var screen_off_overlay: ColorRect = $ComputerFrame/Monitor/ScreenOffOverlay
@onready var power_button: Panel = $ComputerFrame/Monitor/ControlPanel/PowerButton
@onready var power_led: ColorRect = $ComputerFrame/Monitor/ControlPanel/PowerLED
@onready var keyboard: Control = $ComputerFrame/Keyboard
@onready var monitor_light: PointLight2D = $ComputerFrame/Monitor/MonitorLight

# Lava lamp
@onready var lava_lamp = $LavaLamp

# Modem LEDs (Hayes Modem) - all 8 LEDs
@onready var led_hs: ColorRect = $HayesModem/Body/LEDPanel/LED_HS  # High Speed
@onready var led_aa: ColorRect = $HayesModem/Body/LEDPanel/LED_AA  # Auto Answer
@onready var led_cd: ColorRect = $HayesModem/Body/LEDPanel/LED_CD  # Carrier Detect
@onready var led_oh: ColorRect = $HayesModem/Body/LEDPanel/LED_OH  # Off Hook
@onready var led_rd: ColorRect = $HayesModem/Body/LEDPanel/LED_RD  # Receive Data
@onready var led_sd: ColorRect = $HayesModem/Body/LEDPanel/LED_SD  # Send Data
@onready var led_tr: ColorRect = $HayesModem/Body/LEDPanel/LED_TR  # Terminal Ready
@onready var led_mr: ColorRect = $HayesModem/Body/LEDPanel/LED_MR  # Modem Ready

# Drive LEDs
@onready var floppy_a_led: ColorRect = $ComputerFrame/BaseUnit/FloppyBayA/DriveLED
@onready var floppy_b_led: ColorRect = $ComputerFrame/BaseUnit/FloppyBayB/DriveLED
@onready var hdd_led: ColorRect = $ComputerFrame/BaseUnit/LEDPanel/HDDLED
@onready var base_power_led: ColorRect = $ComputerFrame/BaseUnit/LEDPanel/PowerLED
@onready var turbo_led: ColorRect = $ComputerFrame/BaseUnit/TurboBtn/TurboLED

# Audio players
@onready var keyboard_click: AudioStreamPlayer = $AudioPlayers/KeyboardClick
@onready var floppy_insert: AudioStreamPlayer = $AudioPlayers/FloppyInsert
@onready var floppy_read: AudioStreamPlayer = $AudioPlayers/FloppyRead
@onready var hdd_startup: AudioStreamPlayer = $AudioPlayers/HDDStartup
@onready var floppy_eject: AudioStreamPlayer = $AudioPlayers/FloppyEject

# LED colors
const LED_OFF = Color(0.12, 0.08, 0.06, 1)
const LED_GREEN = Color(0.15, 0.85, 0.25, 1)
const LED_RED = Color(0.9, 0.15, 0.1, 1)
const LED_ORANGE = Color(0.9, 0.5, 0.1, 1)

# Modem state
var modem_connected: bool = false

# CRT curvature toggle
var crt_curvature_enabled: bool = false
const CRT_CURVATURE_VALUE: float = 0.1

# Key mapping for keyboard animation
var key_map: Dictionary = {
	KEY_ESCAPE: "FunctionKeys/Esc",
	KEY_F1: "FunctionKeys/F1", KEY_F2: "FunctionKeys/F2", KEY_F3: "FunctionKeys/F3", KEY_F4: "FunctionKeys/F4",
	KEY_F5: "FunctionKeys/F5", KEY_F6: "FunctionKeys/F6", KEY_F7: "FunctionKeys/F7", KEY_F8: "FunctionKeys/F8",
	KEY_F9: "FunctionKeys/F9", KEY_F10: "FunctionKeys/F10", KEY_F11: "FunctionKeys/F11", KEY_F12: "FunctionKeys/F12",
	KEY_QUOTELEFT: "NumberRow/K", KEY_1: "NumberRow/K1", KEY_2: "NumberRow/K2", KEY_3: "NumberRow/K3",
	KEY_4: "NumberRow/K4", KEY_5: "NumberRow/K5", KEY_6: "NumberRow/K6", KEY_7: "NumberRow/K7",
	KEY_8: "NumberRow/K8", KEY_9: "NumberRow/K9", KEY_0: "NumberRow/K0",
	KEY_MINUS: "NumberRow/KM", KEY_EQUAL: "NumberRow/KE", KEY_BACKSPACE: "NumberRow/Bksp",
	KEY_TAB: "QWERTYRow/Tab",
	KEY_Q: "QWERTYRow/Q", KEY_W: "QWERTYRow/W", KEY_E: "QWERTYRow/E", KEY_R: "QWERTYRow/R",
	KEY_T: "QWERTYRow/T", KEY_Y: "QWERTYRow/Y", KEY_U: "QWERTYRow/U", KEY_I: "QWERTYRow/I",
	KEY_O: "QWERTYRow/O", KEY_P: "QWERTYRow/P",
	KEY_BRACKETLEFT: "QWERTYRow/LB", KEY_BRACKETRIGHT: "QWERTYRow/RB", KEY_BACKSLASH: "QWERTYRow/BS",
	KEY_CAPSLOCK: "ASDFRow/Caps",
	KEY_A: "ASDFRow/A", KEY_S: "ASDFRow/S", KEY_D: "ASDFRow/D", KEY_F: "ASDFRow/F",
	KEY_G: "ASDFRow/G", KEY_H: "ASDFRow/H", KEY_J: "ASDFRow/J", KEY_K: "ASDFRow/K",
	KEY_L: "ASDFRow/L2", KEY_SEMICOLON: "ASDFRow/Semi", KEY_APOSTROPHE: "ASDFRow/Quote",
	KEY_ENTER: "ASDFRow/Enter",
	KEY_SHIFT: "ZXCVRow/LShift",
	KEY_Z: "ZXCVRow/Z", KEY_X: "ZXCVRow/X", KEY_C: "ZXCVRow/C", KEY_V: "ZXCVRow/V",
	KEY_B: "ZXCVRow/B", KEY_N: "ZXCVRow/N", KEY_M: "ZXCVRow/M",
	KEY_COMMA: "ZXCVRow/Comma", KEY_PERIOD: "ZXCVRow/Period", KEY_SLASH: "ZXCVRow/Slash",
	KEY_CTRL: "SpaceRow/Ctrl", KEY_ALT: "SpaceRow/Alt", KEY_SPACE: "SpaceRow/Space",
}

# Track original key positions for animation
var _key_original_positions: Dictionary = {}

func _ready() -> void:
	print("[Main] _ready called - main.gd is running")
	# Setup audio
	_setup_audio()
	
	# Connect power button
	if power_button:
		power_button.gui_input.connect(_on_power_button_input)
		print("[Main] Power button connected")
	else:
		print("[Main] WARNING: Power button not found!")
	
	# Lava lamp handles its own power button via lava_lamp.gd script
	
	# Initialize computer state
	_update_power_state()
	print("[Main] Computer state: ", computer_state)
	
	# Connect to game state signals
	if GameState.has_signal("modem_connected"):
		GameState.modem_connected.connect(_on_modem_connected)
	if GameState.has_signal("modem_hangup"):
		GameState.modem_hangup.connect(_on_modem_hangup)
	if GameState.has_signal("modem_dialing_started"):
		GameState.modem_dialing_started.connect(_on_modem_dialing)
	if GameState.has_signal("modem_dialing_complete"):
		GameState.modem_dialing_complete.connect(_on_modem_dialing_complete)
	if GameState.has_signal("modem_send_data"):
		GameState.modem_send_data.connect(_on_modem_send)
	if GameState.has_signal("modem_receive_data"):
		GameState.modem_receive_data.connect(_on_modem_receive)
	if GameState.has_signal("floppy_reading"):
		GameState.floppy_reading.connect(_on_floppy_reading)

	# Initialize all LEDs to off
	_reset_modem_leds()


func _process(_delta: float) -> void:
	# Update monitor light based on screen content (dynamic CRT glow)
	if (computer_state == ComputerState.ON or computer_state == ComputerState.BOOTING) and monitor_light and terminal:
		if terminal.has_method("get_screen_brightness"):
			var brightness = terminal.get_screen_brightness()
			# Range 0.3 (nearly empty) to 3.0 (full screen of text)
			monitor_light.energy = 0.3 + (brightness * 2.7)


func _on_power_button_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("[Main] Power button clicked!")
			_toggle_power()

func _toggle_power() -> void:
	print("[Main] Toggle power called, current state: ", computer_state)
	match computer_state:
		ComputerState.OFF:
			print("[Main] Turning ON...")
			_boot_aborted = false
			computer_state = ComputerState.BOOTING
			_update_power_state()
			_start_boot_sequence()
		ComputerState.ON, ComputerState.BOOTING:
			print("[Main] Turning OFF...")
			_boot_aborted = true  # Signal boot sequence to abort
			_awaiting_registration = false  # Cancel any registration input
			computer_state = ComputerState.OFF
			_stop_all_audio()
			_update_power_state()
			# Clear terminal if it exists
			if terminal:
				terminal.clear_screen()


func _update_power_state() -> void:
	print("[Main] Updating power state: ", computer_state)

	match computer_state:
		ComputerState.OFF:
			# Show screen off overlay (black screen)
			if screen_off_overlay:
				screen_off_overlay.visible = true
				print("[Main] Screen overlay shown")
			# Hide terminal when off
			if terminal_view:
				terminal_view.visible = false
			# Power LEDs off
			if power_led:
				power_led.color = LED_OFF
			if base_power_led:
				base_power_led.color = LED_OFF
			# Turn off modem LEDs when computer is off
			_reset_modem_leds()
			# Turn off monitor light (CRT glow)
			if monitor_light:
				monitor_light.enabled = false
		ComputerState.BOOTING, ComputerState.ON:
			# Hide screen off overlay
			if screen_off_overlay:
				screen_off_overlay.visible = false
				print("[Main] Screen overlay hidden")
			# Show terminal when on
			if terminal_view:
				terminal_view.visible = true
			# Power LEDs on
			if power_led:
				power_led.color = LED_GREEN
			if base_power_led:
				base_power_led.color = LED_GREEN
			# Turn on modem ready LEDs (MR and TR) when computer is on
			if computer_state == ComputerState.ON:
				_set_modem_ready_leds()
			# Turn on monitor light (green CRT glow) when screen is on
			if monitor_light:
				monitor_light.energy = 0.3  # Start dim, will adjust based on content
				monitor_light.enabled = true


# Registration state (for boot sequence input handling)
var _awaiting_registration: bool = false
var _registration_input: String = ""
var _registration_complete_signal: Signal

# Boot sequence abort flag
var _boot_aborted: bool = false

func _start_boot_sequence() -> void:
	# Play HDD startup sound
	if hdd_startup and hdd_startup.stream:
		hdd_startup.play()

	# Clear screen and show initial cursor blinking for 5 seconds
	if terminal and terminal.has_method("clear_screen"):
		terminal.clear_screen()

	# Show blinking cursor at top-left for realistic POST delay
	# The terminal cursor handles the blinking, we just wait
	if terminal:
		terminal._display_base = ""
		terminal.current_input = ""
		terminal._output_text = ""
		terminal._refresh_display()

	# Initial POST delay - cursor blinking in top left corner
	await get_tree().create_timer(5.0).timeout
	if _boot_aborted: return

	# Flash HDD LED during boot
	if hdd_led:
		hdd_led.color = LED_RED

	# BIOS header with slower typing
	await _boot_print_slow("SHADOW SYSTEMS BIOS v2.1")
	if _boot_aborted: return
	await get_tree().create_timer(0.3).timeout
	if _boot_aborted: return
	await _boot_print_slow("Copyright (C) 1983 Shadow Systems Inc.")
	if _boot_aborted: return
	await _boot_print("")
	await get_tree().create_timer(0.8).timeout
	if _boot_aborted: return

	# CPU detection - realistic delay
	await _boot_print_slow("Detecting CPU...")
	if _boot_aborted: return
	await get_tree().create_timer(0.5).timeout
	if _boot_aborted: return
	await _boot_print_slow("Intel 8088 @ 4.77 MHz")
	if _boot_aborted: return
	await get_tree().create_timer(0.6).timeout
	if _boot_aborted: return
	await _boot_print_slow("CPU Test: PASSED")
	if _boot_aborted: return
	await get_tree().create_timer(0.4).timeout
	if _boot_aborted: return

	# Memory test with realistic counting display (overwrites previous value)
	await _boot_print("")
	if _boot_aborted: return
	if terminal:
		var base_text = terminal._output_text + "Testing Memory: "
		for kb in [64, 128, 192, 256, 320, 384, 448, 512, 576, 640]:
			if _boot_aborted: return
			terminal._output_text = base_text + str(kb) + "K"
			terminal._update_display()
			await get_tree().create_timer(0.10).timeout
		if _boot_aborted: return
		terminal._output_text = base_text + "640K OK"
		terminal._update_display()
		terminal.print_line("")

	await get_tree().create_timer(0.4).timeout
	if _boot_aborted: return

	# Memory totals
	await _boot_print("")
	if _boot_aborted: return
	await _boot_print_slow("Base Memory:  640K")
	if _boot_aborted: return
	await _boot_print_slow("Ext. Memory:    0K")
	if _boot_aborted: return
	await get_tree().create_timer(0.6).timeout
	if _boot_aborted: return

	# Hardware detection - one at a time with realistic delays
	await _boot_print("")
	if _boot_aborted: return
	await _boot_print_slow("Detecting Hardware...")
	if _boot_aborted: return
	await get_tree().create_timer(0.5).timeout
	if _boot_aborted: return

	await _boot_print_slow("  Floppy Drive A: 5.25\" 360K")
	if _boot_aborted: return
	await get_tree().create_timer(0.3).timeout
	if _boot_aborted: return
	await _boot_print_slow("  Floppy Drive B: 3.5\" 720K")
	if _boot_aborted: return
	await get_tree().create_timer(0.3).timeout
	if _boot_aborted: return

	# HDD detection with head seek sound
	if terminal:
		for c in "  Hard Disk C:    ":
			if _boot_aborted: return
			terminal.print_text(c)
			await get_tree().create_timer(0.02).timeout
	if _boot_aborted: return
	await get_tree().create_timer(0.4).timeout
	if _boot_aborted: return
	await _boot_print("20MB")
	if _boot_aborted: return
	await get_tree().create_timer(0.3).timeout
	if _boot_aborted: return

	await _boot_print_slow("  Serial Port:    COM1 - 2400 BAUD MODEM")
	if _boot_aborted: return
	await get_tree().create_timer(0.3).timeout
	if _boot_aborted: return
	await _boot_print_slow("  Video:          CGA Monochrome")
	if _boot_aborted: return
	await get_tree().create_timer(0.6).timeout
	if _boot_aborted: return

	# Modem initialization
	await _boot_print("")
	if _boot_aborted: return
	await _boot_print_slow("Initializing Modem...")
	if _boot_aborted: return
	await get_tree().create_timer(0.4).timeout
	if _boot_aborted: return
	await _boot_print_slow("  ATZ OK")
	if _boot_aborted: return
	await get_tree().create_timer(0.2).timeout
	if _boot_aborted: return
	await _boot_print_slow("  ATE1V1 OK")
	if _boot_aborted: return
	await get_tree().create_timer(0.3).timeout
	if _boot_aborted: return

	# Boot complete
	await _boot_print("")
	if _boot_aborted: return
	await _boot_print("Starting SHADOW-DOS...")
	if _boot_aborted: return
	await get_tree().create_timer(0.5).timeout
	if _boot_aborted: return

	if hdd_led:
		hdd_led.color = LED_OFF

	computer_state = ComputerState.ON
	_update_power_state()

	# Clear and show DOS prompt
	if terminal:
		terminal.clear_screen()
		if terminal.has_method("init"):
			terminal.init()


func _boot_print(text: String) -> void:
	if terminal and terminal.has_method("print_line"):
		terminal.print_line(text)
	await get_tree().create_timer(0.05).timeout


func _boot_print_slow(text: String) -> void:
	"""Print text character by character for realistic BIOS output"""
	if terminal and terminal.has_method("print_text"):
		for c in text:
			if _boot_aborted: return
			terminal.print_text(c)
			await get_tree().create_timer(0.02).timeout
		if _boot_aborted: return
		terminal.print_line("")
	await get_tree().create_timer(0.05).timeout


func _boot_print_no_newline(text: String) -> void:
	if terminal and terminal.has_method("print_text"):
		terminal.print_text(text)
	await get_tree().create_timer(0.01).timeout


func _registration_sequence() -> void:
	"""Display registration screen during boot and get player handle"""
	if not terminal:
		return

	await _boot_print("")
	await _boot_print("========================================")
	await _boot_print("   *** SHADOW NETWORK REGISTRATION ***")
	await _boot_print("========================================")
	await _boot_print("")
	await _boot_print("Your modem is not registered with the")
	await _boot_print("Shadow Network. Registration is required")
	await _boot_print("to access network services.")
	await _boot_print("")
	await _boot_print("Enter your handle (3-12 characters):")
	await _boot_print("")

	# Get handle input during boot
	_awaiting_registration = true
	_registration_input = ""
	_update_registration_display()

	# Wait for registration to complete
	while _awaiting_registration:
		await get_tree().create_timer(0.1).timeout

	var handle = _registration_input.strip_edges()

	# Validate handle
	if handle.length() < 3 or handle.length() > 12:
		await _boot_print("")
		await _boot_print("Invalid handle. Using offline mode.")
		await get_tree().create_timer(1.0).timeout
		OnlineManager.setup_offline_mode("GUEST")
		return

	# Try to register with server
	await _boot_print("")
	await _boot_print("Connecting to Shadow Network...")
	await get_tree().create_timer(0.5).timeout

	OnlineManager.register_player(handle)

	# Wait for response with timeout
	var timeout = 5.0
	var start_time = Time.get_ticks_msec()
	var result_received = false
	var result_success = false
	var result_data = {}

	OnlineManager.registration_complete.connect(
		func(success: bool, data: Dictionary):
			result_received = true
			result_success = success
			result_data = data,
		CONNECT_ONE_SHOT
	)

	while not result_received and (Time.get_ticks_msec() - start_time) < timeout * 1000:
		await get_tree().create_timer(0.1).timeout

	if result_received and result_success:
		# Success!
		await _boot_print("REGISTRATION SUCCESSFUL!")
		await _boot_print("")
		await _boot_print("========================================")
		await _boot_print(" *** SAVE YOUR RECOVERY CODE ***")
		await _boot_print("========================================")
		await _boot_print("")
		await _boot_print(" Code: " + OnlineManager.recovery_code)
		await _boot_print("")
		await _boot_print(" Use SESSION RECOVER <code> to restore")
		await _boot_print(" your identity on another computer.")
		await _boot_print("========================================")
		await _boot_print("")
		await _boot_print("Press any key to continue...")

		# Wait for keypress
		_awaiting_registration = true
		_registration_input = ""
		while _awaiting_registration and _registration_input.is_empty():
			await get_tree().create_timer(0.1).timeout
		_awaiting_registration = false

	elif result_received and not result_success:
		# Server responded with error
		var error = result_data.get("error", "UNKNOWN")
		if error == "HANDLE_TAKEN":
			await _boot_print("ERROR: Handle already taken!")
		else:
			await _boot_print("ERROR: " + result_data.get("message", "Registration failed"))
		await _boot_print("")
		await _boot_print("Using offline mode.")
		await get_tree().create_timer(1.5).timeout
		OnlineManager.setup_offline_mode(handle)
	else:
		# Timeout - server unreachable
		await _boot_print("Network unreachable.")
		await _boot_print("Using offline mode.")
		await get_tree().create_timer(1.0).timeout
		OnlineManager.setup_offline_mode(handle)

	# Clear screen before continuing boot
	if terminal:
		terminal.clear_screen()
		terminal._output_text = ""
		terminal._display_base = ""


func _update_registration_display() -> void:
	"""Update the display during registration input"""
	if not terminal or not _awaiting_registration:
		return

	# Show current input with cursor
	var cursor = "_" if fmod(Time.get_ticks_msec() / 500.0, 2.0) < 1.0 else " "
	var display_text = "> " + _registration_input + cursor

	# We need to update the last line
	var lines = terminal._output_text.split("\n")
	if lines.size() > 0:
		# Check if last line is our input line
		if lines[lines.size() - 1].begins_with(">") or lines[lines.size() - 1] == "":
			lines[lines.size() - 1] = display_text
		else:
			lines.append(display_text)
		terminal._output_text = "\n".join(lines)
		terminal._update_display()


func _handle_registration_key(event: InputEventKey) -> void:
	"""Handle keyboard input during registration"""
	if not _awaiting_registration:
		return

	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		# Submit registration
		_awaiting_registration = false
	elif event.keycode == KEY_BACKSPACE:
		if _registration_input.length() > 0:
			_registration_input = _registration_input.substr(0, _registration_input.length() - 1)
			_update_registration_display()
	elif event.keycode == KEY_ESCAPE:
		_registration_input = ""
		_awaiting_registration = false
	else:
		# Add character if printable and within length limit
		if event.unicode >= 32 and event.unicode < 127 and _registration_input.length() < 12:
			_registration_input += char(event.unicode)
			_update_registration_display()


func _setup_audio() -> void:
	# Try to load audio assets
	var kb_sound = load("res://assets/mech-keyboard-02-102918.mp3")
	if kb_sound and keyboard_click:
		keyboard_click.stream = kb_sound
	
	var insert_sound = load("res://assets/inserting_floppy_disc-93172.mp3")
	if insert_sound and floppy_insert:
		floppy_insert.stream = insert_sound
	
	var read_sound = load("res://assets/reading_floppy_disc_1-93173.mp3")
	if read_sound and floppy_read:
		floppy_read.stream = read_sound
	
	var eject_sound = load("res://assets/removing_floppy_disc-93174.mp3")
	if eject_sound and floppy_eject:
		floppy_eject.stream = eject_sound
	
	var hdd_sound = load("res://assets/hard-disk-drive-start-63229.mp3")
	if hdd_sound and hdd_startup:
		hdd_startup.stream = hdd_sound


func _reset_modem_leds() -> void:
	# Turn off all modem LEDs
	if led_hs: led_hs.color = LED_OFF
	if led_aa: led_aa.color = LED_OFF
	if led_cd: led_cd.color = LED_OFF
	if led_oh: led_oh.color = LED_OFF
	if led_rd: led_rd.color = LED_OFF
	if led_sd: led_sd.color = LED_OFF
	if led_tr: led_tr.color = LED_OFF
	if led_mr: led_mr.color = LED_OFF


func _stop_all_audio() -> void:
	# Stop all audio players immediately
	if keyboard_click and keyboard_click.playing:
		keyboard_click.stop()
	if floppy_insert and floppy_insert.playing:
		floppy_insert.stop()
	if floppy_read and floppy_read.playing:
		floppy_read.stop()
	if floppy_eject and floppy_eject.playing:
		floppy_eject.stop()
	if hdd_startup and hdd_startup.playing:
		hdd_startup.stop()


func _set_modem_ready_leds() -> void:
	# MR (Modem Ready) and TR (Terminal Ready) light when computer is on
	if led_mr: led_mr.color = LED_GREEN
	if led_tr: led_tr.color = LED_GREEN


func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.is_echo():
		# Animate keyboard on key press AND release (ignore key repeat)
		_animate_key(event.keycode, event.pressed)

		# Only process these on key press, not release
		if event.pressed:
			# Keyboard click sound on press
			if keyboard_click and keyboard_click.stream:
				keyboard_click.play()

			# Handle registration input during boot
			if _awaiting_registration:
				_handle_registration_key(event)
				return

			# Forward keyboard input to terminal when computer is on
			if computer_state == ComputerState.ON and terminal:
				_forward_key_to_terminal(event)

			# F11 to toggle fullscreen
			if event.keycode == KEY_F11:
				if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			# F12 to toggle power (for testing)
			elif event.keycode == KEY_F12:
				_toggle_power()
			# F9 to toggle CRT curvature
			elif event.keycode == KEY_F9:
				print("[Main] F9 pressed!")
				_toggle_crt_curvature()


func _forward_key_to_terminal(event: InputEventKey) -> void:
	if not terminal:
		return

	# Check if a program is running that wants to handle keys directly
	if terminal.current_program and terminal.current_program.has_method("handle_key"):
		var shift = event.shift_pressed
		var ctrl = event.ctrl_pressed
		var handled = terminal.current_program.handle_key(event.keycode, shift, ctrl)
		if handled:
			return
		# If not handled, check for character input
		if terminal.current_program.has_method("handle_char"):
			if event.unicode >= 32 and event.unicode < 127:
				terminal.current_program.handle_char(char(event.unicode))
				return

	# Handle special keys for terminal
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			terminal.handle_enter()
		KEY_BACKSPACE:
			terminal.handle_backspace()
		KEY_ESCAPE:
			terminal.handle_escape()
		KEY_UP:
			if terminal.has_method("_navigate_history"):
				terminal._navigate_history(-1)
		KEY_DOWN:
			if terminal.has_method("_navigate_history"):
				terminal._navigate_history(1)
		_:
			# Regular character input (printable ASCII)
			if event.unicode >= 32 and event.unicode < 127:
				var char_str := char(event.unicode)
				terminal.handle_char_input(char_str)


func _animate_key(keycode: int, pressed: bool) -> void:
	if not keyboard:
		return
	
	var key_path: String = key_map.get(keycode, "")
	if key_path == "":
		return
	
	var key_node = keyboard.get_node_or_null(key_path)
	if key_node:
		if pressed:
			# Store original position if not already stored
			if not _key_original_positions.has(keycode):
				_key_original_positions[keycode] = key_node.position.y
			# Depress the key - move down and darken
			key_node.position.y = _key_original_positions[keycode] + 2
			key_node.modulate = Color(0.7, 0.7, 0.7, 1.0)
		else:
			# Release the key - restore original position and color
			if _key_original_positions.has(keycode):
				key_node.position.y = _key_original_positions[keycode]
			key_node.modulate = Color(1.0, 1.0, 1.0, 1.0)


var _sd_flash_active: bool = false

func _on_modem_dialing() -> void:
	# Only respond if computer is ON
	if computer_state != ComputerState.ON:
		return
	# OH (Off Hook) lights when dialing
	if led_oh: led_oh.color = LED_RED
	# Start SD flashing during DTMF dialing
	_sd_flash_active = true
	_flash_sd_led()


func _on_modem_dialing_complete() -> void:
	# Stop SD flashing when dialing completes
	_sd_flash_active = false
	if led_sd: led_sd.color = LED_OFF


func _flash_sd_led() -> void:
	if not _sd_flash_active:
		return
	if led_sd:
		led_sd.color = LED_GREEN if led_sd.color == LED_OFF else LED_OFF
	# Continue flashing while active
	if _sd_flash_active:
		get_tree().create_timer(0.1).timeout.connect(_flash_sd_led)


func _on_modem_connected() -> void:
	# Only respond if computer is ON
	if computer_state != ComputerState.ON:
		return
	modem_connected = true
	# CD (Carrier Detect) lights when connected
	if led_cd: led_cd.color = LED_GREEN
	# OH stays lit while connected
	if led_oh: led_oh.color = LED_RED
	# HS (High Speed) lights for 1200 baud connection
	if led_hs: led_hs.color = LED_RED


func _on_modem_hangup() -> void:
	modem_connected = false
	_sd_flash_active = false
	# Reset activity LEDs but keep MR/TR on if computer is on
	if led_hs: led_hs.color = LED_OFF
	if led_aa: led_aa.color = LED_OFF
	if led_cd: led_cd.color = LED_OFF
	if led_oh: led_oh.color = LED_OFF
	if led_rd: led_rd.color = LED_OFF
	if led_sd: led_sd.color = LED_OFF
	# Keep MR and TR on if computer is still on
	if computer_state == ComputerState.ON:
		_set_modem_ready_leds()


func _on_modem_send() -> void:
	# Only respond if computer is ON
	if computer_state != ComputerState.ON:
		return
	if led_sd: led_sd.color = LED_GREEN
	# Reset after brief flash
	get_tree().create_timer(0.1).timeout.connect(func(): if led_sd and not _sd_flash_active: led_sd.color = LED_OFF)


func _on_modem_receive() -> void:
	# Only respond if computer is ON
	if computer_state != ComputerState.ON:
		return
	if led_rd: led_rd.color = LED_GREEN
	# Reset after brief flash
	get_tree().create_timer(0.1).timeout.connect(func(): if led_rd: led_rd.color = LED_OFF)


func _on_floppy_reading() -> void:
	if floppy_read and floppy_read.stream:
		floppy_read.play()
	# Flash floppy LED
	if floppy_a_led:
		floppy_a_led.color = LED_GREEN
		get_tree().create_timer(0.2).timeout.connect(func(): if floppy_a_led: floppy_a_led.color = LED_OFF)


## Play floppy insert sound
func play_floppy_insert() -> void:
	if floppy_insert and floppy_insert.stream:
		floppy_insert.play()


## Play floppy eject sound
func play_floppy_eject() -> void:
	if floppy_eject and floppy_eject.stream:
		floppy_eject.play()


## Flash HDD LED during disk activity
func flash_hdd_led() -> void:
	if hdd_led:
		hdd_led.color = LED_RED
		get_tree().create_timer(0.1).timeout.connect(func(): if hdd_led: hdd_led.color = LED_OFF)


## Toggle CRT screen curvature effect
func _toggle_crt_curvature() -> void:
	crt_curvature_enabled = not crt_curvature_enabled
	var curvature_value = CRT_CURVATURE_VALUE if crt_curvature_enabled else 0.0
	print("[Main] Toggling CRT curvature to: %s (value: %f)" % [crt_curvature_enabled, curvature_value])
	if terminal_view:
		print("[Main] terminal_view exists")
		if terminal_view.material:
			print("[Main] terminal_view.material exists, setting shader param")
			terminal_view.material.set_shader_parameter("curvature", curvature_value)
			print("[Main] CRT curvature: %s" % ("ON" if crt_curvature_enabled else "OFF"))
		else:
			print("[Main] ERROR: terminal_view.material is null!")
	else:
		print("[Main] ERROR: terminal_view is null!")
