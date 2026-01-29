extends Control
class_name Terminal
## DOS-style terminal emulator for Shadow System
## Emulates a DOS environment with filesystem, executables, and commands

# Terminal settings
@export var typing_speed: float = 0.02

# DOS Prompt
var current_drive: String = "C:"
var current_path: String = "\\"

# Virtual filesystem structure (C: drive - hard disk)
# File attributes: R=Read-only, H=Hidden, S=System, A=Archive
var filesystem := {
	"C:\\": {
		"type": "dir",
		"attr": "S",
		"contents": ["DOS", "GAMES", "UTILS", "AUTOEXEC.BAT", "CONFIG.SYS"]
	},
	"C:\\DOS": {
		"type": "dir",
		"attr": "S",
		"contents": ["COMMAND.COM", "FORMAT.COM", "CHKDSK.COM", "MORE.COM", "FIND.EXE", "SORT.EXE", "TREE.COM", "ATTRIB.EXE"]
	},
	"C:\\DOS\\COMMAND.COM": {"type": "exe", "program": "command", "attr": "RS"},
	"C:\\DOS\\FORMAT.COM": {"type": "exe", "program": "format", "attr": "RS"},
	"C:\\DOS\\CHKDSK.COM": {"type": "exe", "program": "chkdsk", "attr": "RS"},
	"C:\\DOS\\MORE.COM": {"type": "exe", "program": "more", "attr": "RS"},
	"C:\\DOS\\FIND.EXE": {"type": "exe", "program": "find", "attr": "RS"},
	"C:\\DOS\\SORT.EXE": {"type": "exe", "program": "sort", "attr": "RS"},
	"C:\\DOS\\TREE.COM": {"type": "exe", "program": "tree", "attr": "RS"},
	"C:\\DOS\\ATTRIB.EXE": {"type": "exe", "program": "attrib", "attr": "RS"},
	"C:\\GAMES": {
		"type": "dir",
		"contents": ["README.TXT"]
	},
	"C:\\GAMES\\README.TXT": {"type": "file", "content": "No games installed.\nInsert game disk in A: drive.", "attr": "A"},
	"C:\\UTILS": {
		"type": "dir",
		"attr": "S",
		"contents": ["MODEM.COM", "EDIT.COM"]
	},
	"C:\\UTILS\\MODEM.COM": {"type": "exe", "program": "modem", "attr": "RS"},
	"C:\\UTILS\\EDIT.COM": {"type": "exe", "program": "edit"},
	"C:\\AUTOEXEC.BAT": {"type": "file", "content": "@ECHO OFF\nPROMPT $P$G\nPATH C:\\DOS;C:\\UTILS\nECHO.\nECHO Welcome to SHADOW-DOS\n", "attr": "RS"},
	"C:\\CONFIG.SYS": {"type": "file", "content": "FILES=20\nBUFFERS=30\nDEVICE=HIMEM.SYS\n", "attr": "RS"},
}

# Default system filesystem (protected from server sync overwrites)
# File attributes: R=Read-only, H=Hidden, S=System, A=Archive
const DEFAULT_FILESYSTEM := {
	"C:\\": {
		"type": "dir",
		"attr": "S",
		"contents": ["DOS", "GAMES", "UTILS", "AUTOEXEC.BAT", "CONFIG.SYS"]
	},
	"C:\\DOS": {
		"type": "dir",
		"attr": "S",
		"contents": ["COMMAND.COM", "FORMAT.COM", "CHKDSK.COM", "MORE.COM", "FIND.EXE", "SORT.EXE", "TREE.COM", "ATTRIB.EXE"]
	},
	"C:\\DOS\\COMMAND.COM": {"type": "exe", "program": "command", "attr": "RS"},
	"C:\\DOS\\FORMAT.COM": {"type": "exe", "program": "format", "attr": "RS"},
	"C:\\DOS\\CHKDSK.COM": {"type": "exe", "program": "chkdsk", "attr": "RS"},
	"C:\\DOS\\MORE.COM": {"type": "exe", "program": "more", "attr": "RS"},
	"C:\\DOS\\FIND.EXE": {"type": "exe", "program": "find", "attr": "RS"},
	"C:\\DOS\\SORT.EXE": {"type": "exe", "program": "sort", "attr": "RS"},
	"C:\\DOS\\TREE.COM": {"type": "exe", "program": "tree", "attr": "RS"},
	"C:\\DOS\\ATTRIB.EXE": {"type": "exe", "program": "attrib", "attr": "RS"},
	"C:\\GAMES": {
		"type": "dir",
		"contents": ["README.TXT"]
	},
	"C:\\GAMES\\README.TXT": {"type": "file", "content": "No games installed.\nInsert game disk in A: drive.", "attr": "A"},
	"C:\\UTILS": {
		"type": "dir",
		"attr": "S",
		"contents": ["MODEM.COM", "EDIT.COM"]
	},
	"C:\\UTILS\\MODEM.COM": {"type": "exe", "program": "modem", "attr": "RS"},
	"C:\\UTILS\\EDIT.COM": {"type": "exe", "program": "edit"},
	"C:\\AUTOEXEC.BAT": {"type": "file", "content": "@ECHO OFF\nPROMPT $P$G\nPATH C:\\DOS;C:\\UTILS\nECHO.\nECHO Welcome to SHADOW-DOS\n", "attr": "RS"},
	"C:\\CONFIG.SYS": {"type": "file", "content": "FILES=20\nBUFFERS=30\nDEVICE=HIMEM.SYS\n", "attr": "RS"},
}

# Protected path prefixes that are never overwritten by server sync (system files)
const PROTECTED_PREFIXES := ["C:\\DOS", "C:\\UTILS", "C:\\AUTOEXEC.BAT", "C:\\CONFIG.SYS"]

# File attribute constants
const ATTR_READONLY := "R"
const ATTR_HIDDEN := "H"
const ATTR_SYSTEM := "S"
const ATTR_ARCHIVE := "A"

# Environment variables
var env_vars := {
	"PATH": "C:\\DOS;C:\\UTILS",
	"PROMPT": "$P$G",
	"COMSPEC": "C:\\DOS\\COMMAND.COM"
}

# Volume label
var volume_label := "SHADOW"

# Floppy disk filesystem (A: drive - populated when disk inserted)
var floppy_filesystem := {}
var floppy_disk_inserted: bool = false
var floppy_disk_label: String = ""

# Node references
var output: RichTextLabel
var terminal_view: Control

# Terminal state
var command_history: Array[String] = []
var history_index: int = -1
var current_program: Node = null
var is_typing: bool = false
var is_ready: bool = false
var current_input: String = ""
var cursor_visible: bool = true
var _terminal_started: bool = false
var _slow_print_active: bool = false

# Raw input mode - for connected systems where we just append input to end
var raw_input_mode: bool = false
var _last_output_text: String = ""

# Passthrough mode - simple scrolling terminal for remote connections
var passthrough_mode: bool = false
var _passthrough_base_text: String = ""

# Program input mode - explicit prompt management for reliable input display
var _program_input_mode: bool = false
var _program_output_buffer: String = ""
var _program_prompt: String = ""

# Base display text - everything before the current input line (tracked manually)
var _display_base: String = ""
# Track all output text manually to avoid get_parsed_text() encoding issues
var _output_text: String = ""

# Handle/email check state (used during registration)
var _handle_check_received: bool = false
var _handle_check_available: bool = false
var _email_check_received: bool = false
var _email_check_available: bool = false

# Registration state
var _registration_received: bool = false
var _registration_success: bool = false
var _registration_data: Dictionary = {}

# Signals
signal command_entered(command: String)
signal program_requested(program_name: String, args: Array)
signal program_exit()

# Built-in DOS commands - initialized in _ready()
var builtin_commands := {}

# Flag to prevent remote changes from triggering re-sync
var _applying_remote_change: bool = false

# Flag to control auto-scroll behavior - only scroll when new content added
var _should_scroll_to_bottom: bool = true

# Track if user has scrolled away from bottom (to skip cursor blink refreshes)
var _user_scrolled_away: bool = false


func _get_prompt() -> String:
	return current_drive + current_path + ">"


func _ready() -> void:
	# Initialize built-in commands dictionary
	builtin_commands = {
		"dir": _cmd_dir,
		"cls": _cmd_cls,
		"clear": _cmd_cls,
		"type": _cmd_type,
		"del": _cmd_del,
		"date": _cmd_date,
		"time": _cmd_time,
		"ver": _cmd_ver,
		"help": _cmd_help,
		"mem": _cmd_mem,
		"history": _cmd_history,
		"session": _cmd_session,
		"apikey": _cmd_apikey,
		"exit": _cmd_exit,
		"quit": _cmd_exit,
		"cd": _cmd_cd,
		"chdir": _cmd_cd,
		"md": _cmd_md,
		"mkdir": _cmd_md,
		"rd": _cmd_rd,
		"rmdir": _cmd_rd,
		"copy": _cmd_copy,
		"ren": _cmd_rename,
		"rename": _cmd_rename,
		"echo": _cmd_echo,
		"set": _cmd_set,
		"path": _cmd_path,
		"prompt": _cmd_prompt,
		"more": _cmd_more,
		"find": _cmd_find,
		"sort": _cmd_sort,
		"attrib": _cmd_attrib,
		"tree": _cmd_tree,
		"vol": _cmd_vol,
		"label": _cmd_label,
		"chkdsk": _cmd_chkdsk,
		"format": _cmd_format,
		"crt": _cmd_crt,
		"version": _cmd_version,
		"edit": _cmd_edit,
	}

	terminal_view = get_node_or_null("../TerminalView")
	if terminal_view:
		output = terminal_view.get_node_or_null("TerminalOutput")

	if not output:
		output = get_node_or_null("Output")

	# Hide scrollbar but keep mouse scrolling functional
	if output:
		var scrollbar = output.get_v_scroll_bar()
		if scrollbar:
			scrollbar.modulate.a = 0  # Make invisible but still functional

	# Connect to OnlineManager signals for real-time sync
	OnlineManager.file_changed_remote.connect(_on_remote_file_change)
	OnlineManager.file_deleted_remote.connect(_on_remote_file_delete)
	OnlineManager.versions_received.connect(_on_versions_received)
	OnlineManager.version_restored.connect(_on_version_restored)

	# Input is now handled directly by main.gd - no LineEdit needed


func init() -> void:
	"""Called by main.gd after BIOS boot sequence completes"""
	if _terminal_started:
		return
	call_deferred("_boot_sequence")


func _process(_delta: float) -> void:
	# Skip terminal processing when a program has taken over the screen
	if current_program:
		return

	# Track if user scrolled away from bottom
	if output:
		var scroll_bar = output.get_v_scroll_bar()
		var at_bottom = scroll_bar.value >= scroll_bar.max_value - 20
		if not at_bottom and not _should_scroll_to_bottom:
			_user_scrolled_away = true
		elif at_bottom:
			_user_scrolled_away = false

	# Blink cursor every 0.5 seconds
	if is_ready and not is_typing:
		var blink_time := fmod(Time.get_ticks_msec() / 500.0, 2.0)
		var new_cursor_visible := blink_time < 1.0
		if new_cursor_visible != cursor_visible:
			cursor_visible = new_cursor_visible
			# Skip full refresh if user has scrolled away - they can't see cursor anyway
			if not _user_scrolled_away:
				_refresh_display()


func _boot_sequence() -> void:
	clear_screen()

	await type_line("SHADOW-DOS Version 1.0", 0.02)
	await type_line("(C) Copyright Shadow Systems Inc 1987", 0.02)
	await type_line("")

	# Show modem registration status
	if OnlineManager.is_registered:
		await type_line("Modem registered to " + OnlineManager.player_handle, 0.02)
		await type_line("Dial-in number: " + OnlineManager.player_phone, 0.02)

		# Sync filesystem from server for returning players
		if OnlineManager.is_online and not OnlineManager.session_token.is_empty():
			await type_line("")
			await type_line("Synchronizing files...", 0.02)
			await _fetch_and_apply_filesystem()
			await type_line("Done.", 0.02)

		await type_line("")
	else:
		# First boot - need to register
		await _first_boot_registration()

	is_ready = true
	_terminal_started = true
	_show_prompt()


func _first_boot_registration() -> void:
	"""Handle first-boot registration or recovery with Shadow Network"""
	print_line("========================================")
	print_line("     *** SHADOW NETWORK ACCESS ***")
	print_line("========================================")
	print_line("No local identity found.")
	print_line("[R] Register new modem")
	print_line("[C] Recover existing registration")

	# Enable input for choice
	is_ready = true
	_terminal_started = true
	_display_base = _output_text + "Choice: "
	current_input = ""
	_refresh_display()

	# Wait for R or C
	var choice = ""
	while choice != "R" and choice != "C":
		var input = await _wait_for_registration_input()
		choice = input.strip_edges().to_upper()
		if choice != "R" and choice != "C":
			print_line("Please enter R or C.")
			_display_base = _output_text + "Choice: "
			current_input = ""
			_refresh_display()

	is_ready = false

	if choice == "C":
		await _first_boot_recovery()
	else:
		await _first_boot_register()


func _first_boot_register() -> void:
	"""Handle new modem registration"""
	# Check network first
	if not OnlineManager.is_online:
		print_line("ERROR: Network connection required.")
		await get_tree().create_timer(2.0).timeout
		await _first_boot_registration()
		return

	print_line("Enter handle (3-12 chars).")

	# Enable input for handle
	is_ready = true
	_display_base = _output_text + "Handle: "
	current_input = ""
	_refresh_display()

	var handle = await _wait_for_registration_input()
	is_ready = false

	# Validate handle length
	if handle.length() < 3 or handle.length() > 12:
		print_line("ERROR: Handle must be 3-12 characters.")
		await get_tree().create_timer(1.0).timeout
		await _first_boot_register()
		return

	# Check if handle is available BEFORE asking for email
	_handle_check_received = false
	_handle_check_available = false
	OnlineManager.handle_check_complete.connect(_on_handle_check_complete, CONNECT_ONE_SHOT)
	OnlineManager.check_handle_available(handle)

	var check_start = Time.get_ticks_msec()
	while not _handle_check_received and (Time.get_ticks_msec() - check_start) < 5000:
		await get_tree().create_timer(0.1).timeout

	if not _handle_check_received:
		print_line("ERROR: Network timeout.")
		await get_tree().create_timer(1.0).timeout
		await _first_boot_register()
		return

	if not _handle_check_available:
		print_line("ERROR: Handle '" + handle + "' already taken.")
		await get_tree().create_timer(1.0).timeout
		await _first_boot_register()
		return

	# Get email
	print_line("Enter email (for recovery code).")

	is_ready = true
	_display_base = _output_text + "Email: "
	current_input = ""
	_refresh_display()

	var email = await _wait_for_registration_input()
	is_ready = false
	email = email.strip_edges()

	# Basic email validation
	if not "@" in email or not "." in email or email.length() < 5:
		print_line("ERROR: Invalid email address.")
		await get_tree().create_timer(1.0).timeout
		await _first_boot_register()
		return

	# Check if email is available
	_email_check_received = false
	_email_check_available = false
	OnlineManager.email_check_complete.connect(_on_email_check_complete, CONNECT_ONE_SHOT)
	OnlineManager.check_email_available(email)

	var email_check_start = Time.get_ticks_msec()
	while not _email_check_received and (Time.get_ticks_msec() - email_check_start) < 5000:
		await get_tree().create_timer(0.1).timeout

	if not _email_check_received:
		print_line("ERROR: Network timeout.")
		await get_tree().create_timer(1.0).timeout
		await _first_boot_register()
		return

	if not _email_check_available:
		print_line("ERROR: Email already registered.")
		print_line("Use [C] Recover to restore account.")
		await get_tree().create_timer(1.5).timeout
		await _first_boot_registration()
		return

	# Try to register with server
	print_line("Registering...")

	_registration_received = false
	_registration_success = false
	_registration_data = {}
	OnlineManager.registration_complete.connect(_on_registration_complete, CONNECT_ONE_SHOT)
	OnlineManager.register_player(handle, email)

	# Wait for response with timeout
	var timeout = 10.0
	var start_time = Time.get_ticks_msec()

	while not _registration_received and (Time.get_ticks_msec() - start_time) < timeout * 1000:
		await get_tree().create_timer(0.1).timeout

	if _registration_received and _registration_success:
		print_line("REGISTERED!")
		print_line("========================================")
		print_line("Handle: " + OnlineManager.player_handle)
		print_line("Phone:  " + OnlineManager.player_phone)
		print_line("Code:   " + OnlineManager.recovery_code)
		print_line("========================================")
		print_line("Recovery code emailed to: " + email)
		print_line("Use SESSION RECOVER <code> to restore.")
	elif _registration_received and not _registration_success:
		var error = _registration_data.get("error", "UNKNOWN")
		if error == "HANDLE_TAKEN":
			print_line("ERROR: Handle already taken.")
		elif error == "EMAIL_TAKEN":
			print_line("ERROR: Email already registered.")
		elif error == "INVALID_EMAIL":
			print_line("ERROR: Invalid email address.")
		else:
			print_line("ERROR: " + _registration_data.get("message", "Registration failed"))
		await get_tree().create_timer(1.5).timeout
		await _first_boot_register()
	else:
		print_line("ERROR: Network timeout.")
		await get_tree().create_timer(1.5).timeout
		await _first_boot_registration()


func _on_handle_check_complete(available: bool, data: Dictionary) -> void:
	"""Signal handler for handle availability check"""
	_handle_check_received = true
	_handle_check_available = available


func _on_email_check_complete(available: bool, data: Dictionary) -> void:
	"""Signal handler for email availability check"""
	_email_check_received = true
	_email_check_available = available


func _on_registration_complete(success: bool, data: Dictionary) -> void:
	"""Signal handler for registration"""
	_registration_received = true
	_registration_success = success
	_registration_data = data


func _first_boot_recovery() -> void:
	"""Handle recovery of existing registration during boot"""
	# Check network first
	if not OnlineManager.is_online:
		print_line("")
		print_line("ERROR: Network connection required.")
		print_line("Check connection and try again.")
		print_line("")
		await get_tree().create_timer(2.0).timeout
		await _first_boot_registration()
		return

	print_line("")
	print_line("Enter your recovery code.")
	print_line("Example: SHADOW-7X9K-M2P1")
	print_line("")

	# Enable input for code
	is_ready = true
	_display_base = _output_text + "Code: "
	current_input = ""
	_refresh_display()

	var code = await _wait_for_registration_input()
	is_ready = false
	code = code.strip_edges().to_upper()

	if code.is_empty():
		print_line("")
		print_line("No code entered.")
		print_line("")
		await get_tree().create_timer(1.0).timeout
		await _first_boot_registration()
		return

	print_line("")
	print_line("Contacting Shadow Network...")

	OnlineManager.recover_session(code)

	# Wait for response with timeout
	var timeout = 10.0
	var start_time = Time.get_ticks_msec()
	var result_received = false
	var result_success = false
	var result_data = {}

	OnlineManager.recovery_complete.connect(
		func(success: bool, data: Dictionary):
			result_received = true
			result_success = success
			result_data = data,
		CONNECT_ONE_SHOT
	)

	while not result_received and (Time.get_ticks_msec() - start_time) < timeout * 1000:
		await get_tree().create_timer(0.1).timeout

	if result_received and result_success:
		print_line("")
		print_line("Identity restored!")
		print_line("")
		print_line("Handle: " + OnlineManager.player_handle)
		print_line("Phone:  " + OnlineManager.player_phone)
		print_line("")
		print_line("Syncing filesystem...")
		await _fetch_and_apply_filesystem()
		print_line("Done.")
		print_line("")
	elif result_received:
		var error = result_data.get("error", "UNKNOWN")
		print_line("")
		if error == "INVALID_CODE":
			print_line("ERROR: Recovery code not found.")
		else:
			print_line("ERROR: " + result_data.get("message", "Recovery failed"))
		print_line("")
		await get_tree().create_timer(1.5).timeout
		await _first_boot_registration()
	else:
		print_line("")
		print_line("ERROR: Network timeout.")
		print_line("")
		await get_tree().create_timer(1.5).timeout
		await _first_boot_registration()


var _awaiting_registration_input: bool = false
var _registration_handle: String = ""

func _wait_for_registration_input() -> String:
	"""Wait for user to enter a handle during registration"""
	_awaiting_registration_input = true
	_registration_handle = ""

	while _awaiting_registration_input:
		await get_tree().create_timer(0.05).timeout

	return _registration_handle


func _registration_handle_enter() -> void:
	"""Called when enter is pressed during registration input"""
	_registration_handle = current_input.strip_edges()
	_awaiting_registration_input = false
	# Preserve the prompt and input in _output_text before moving on
	_output_text = _display_base + current_input + "\n"
	_update_display()


func _show_prompt() -> void:
	if not is_ready:
		return
	# Store current output as base, then add prompt
	_display_base = _output_text + _get_prompt()
	current_input = ""
	_should_scroll_to_bottom = true
	_user_scrolled_away = false  # New prompt, return to bottom
	_refresh_display()


## Called by main.gd when a character is typed
func handle_char_input(char_str: String) -> void:
	if not is_ready or is_typing:
		return
	current_input += char_str
	_should_scroll_to_bottom = true
	_user_scrolled_away = false  # User is typing, return to bottom
	_refresh_display()


## Called by main.gd when backspace is pressed
func handle_backspace() -> void:
	if not is_ready or is_typing:
		return
	if current_input.length() > 0:
		current_input = current_input.substr(0, current_input.length() - 1)
		_refresh_display()


## Called by main.gd when enter is pressed
func handle_enter() -> void:
	if not is_ready or is_typing:
		return
	_should_scroll_to_bottom = true
	_user_scrolled_away = false  # User pressed enter, return to bottom
	# Check if we're waiting for registration input
	if _awaiting_registration_input:
		_registration_handle_enter()
		return
	_process_command()


## Called by main.gd to clear input
func handle_escape() -> void:
	if not is_ready or is_typing:
		return
	current_input = ""
	_refresh_display()


func _process_command() -> void:
	if is_typing or not is_ready:
		return
	
	var raw_text := current_input.strip_edges()
	var command := raw_text.to_upper()
	
	current_input = ""
	
	# Check if a program is running
	if current_program and current_program.has_method("handle_input"):
		# Program input mode - commit prompt + input to buffer
		if _program_input_mode:
			_program_output_buffer += _program_prompt + raw_text + "\n"
			output.clear()
			_add_text_with_newlines(_program_output_buffer)
			_program_input_mode = false
			_program_prompt = ""
		# Passthrough mode - append input (AI host sessions)
		elif passthrough_mode:
			_passthrough_base_text += raw_text + "\n"
			output.clear()
			_add_text_with_newlines(_passthrough_base_text)
		# Raw input mode
		elif raw_input_mode:
			_last_output_text += raw_text + "\n"
			output.clear()
			_add_text_with_newlines(_last_output_text)
		else:
			print_line("")
		
		current_program.handle_input(raw_text)
		return
	
	# Handle empty command - just show new prompt (DOS behavior)
	# Commit the current prompt line to output, then show new prompt
	if command.is_empty():
		_output_text += _get_prompt() + "\n"
		_show_prompt()
		return

	# Echo prompt and command to output (commit what user typed)
	_output_text += _get_prompt() + raw_text + "\n"
	_update_display()

	# Add to history
	command_history.append(command)
	history_index = command_history.size()
	GameState.add_to_history(command)
	
	# Parse command
	var parts := command.split(" ", false)
	if parts.is_empty():
		_show_prompt()
		return
	
	var cmd_name := parts[0].to_lower()
	var args := parts.slice(1)
	
	# Drive switching
	if command == "A:" or command == "A":
		if floppy_disk_inserted:
			current_drive = "A:"
			current_path = "\\"
			print_line("")
		else:
			print_line("")
			print_line("Not ready reading drive A")
			print_line("")
		_show_prompt()
		return
	elif command == "C:" or command == "C":
		current_drive = "C:"
		current_path = "\\"
		print_line("")
		_show_prompt()
		return
	
	# Check built-in commands
	if builtin_commands.has(cmd_name):
		await builtin_commands[cmd_name].call(args)
		_show_prompt()
		return
	
	# Try to run as executable
	if await _try_run_executable(cmd_name, args):
		return
	
	print_line("Bad command or file name")
	print_line("")
	_show_prompt()


func _try_run_executable(cmd: String, args: Array) -> bool:
	var exe_names = [cmd.to_upper() + ".EXE", cmd.to_upper() + ".COM"]

	for exe_name in exe_names:
		var file_key = current_drive + current_path.trim_suffix("\\") + "\\" + exe_name
		if file_key.begins_with("C:\\\\"):
			file_key = "C:\\" + exe_name

		var fs_to_check = filesystem if current_drive == "C:" else floppy_filesystem

		if fs_to_check.has(file_key):
			var file_data = fs_to_check[file_key]
			if file_data.type == "exe" and file_data.has("program"):
				_run_executable(file_data.program, args)
				return true

	# Also check PATH directories
	var path_dirs = env_vars.get("PATH", "").split(";")
	for dir in path_dirs:
		if dir.is_empty():
			continue
		for exe_name in exe_names:
			var file_key = dir + "\\" + exe_name
			file_key = file_key.replace("\\\\", "\\")
			var fs_to_check = filesystem if file_key.begins_with("C:") else floppy_filesystem
			if fs_to_check.has(file_key):
				var file_data = fs_to_check[file_key]
				if file_data.type == "exe" and file_data.has("program"):
					_run_executable(file_data.program, args)
					return true

	return false


func _run_executable(program_name: String, args: Array = []) -> void:
	match program_name:
		"wardialer":
			var scene = load("res://scenes/programs/wardialer.tscn")
			if scene:
				print_line("")
				_start_program(scene, args)
		"bbsdialer":
			var scene = load("res://scenes/programs/bbs_dialer.tscn")
			if scene:
				print_line("")
				_start_program(scene, args)
		"edit":
			var scene = load("res://scenes/programs/editor.tscn")
			if scene:
				_start_program(scene, args)
		_:
			print_line("")
			print_line("Program not implemented: " + program_name)
			print_line("")
			_show_prompt()


func _start_program(scene: PackedScene, args: Array = []) -> void:
	if current_program:
		stop_program()

	current_program = scene.instantiate()
	current_program.terminal = self
	add_child(current_program)

	if current_program.has_method("start"):
		current_program.start(args)


func stop_program() -> void:
	if current_program:
		if current_program.has_method("stop"):
			current_program.stop()
		current_program.queue_free()
		current_program = null
	print_line("")
	_show_prompt()


## Mount a floppy disk - populates A: drive filesystem
func mount_floppy(disk_files: Dictionary, label: String = "FLOPPY") -> void:
	floppy_filesystem = {}
	floppy_filesystem["A:\\"] = {"type": "dir", "contents": []}
	
	for filename in disk_files:
		var file_data = disk_files[filename]
		floppy_filesystem["A:\\" + filename] = file_data
		floppy_filesystem["A:\\"].contents.append(filename)
	
	floppy_disk_inserted = true
	floppy_disk_label = label


func eject_floppy() -> void:
	floppy_filesystem = {}
	floppy_disk_inserted = false
	floppy_disk_label = ""
	
	if current_drive == "A:":
		current_drive = "C:"
		current_path = "\\"


func set_raw_input_mode(enabled: bool) -> void:
	raw_input_mode = enabled
	if enabled:
		_last_output_text = output.get_parsed_text() if output else ""

func set_passthrough_mode(enabled: bool) -> void:
	passthrough_mode = enabled
	if enabled:
		_passthrough_base_text = output.get_parsed_text() if output else ""

func get_passthrough_base() -> String:
	return _passthrough_base_text

func update_passthrough_base(text: String) -> void:
	_passthrough_base_text = text

func request_input(prompt: String) -> void:
	"""Programs call this when they want input with a specific prompt."""
	_program_input_mode = true
	_program_output_buffer = output.get_parsed_text() if output else ""
	_program_prompt = prompt
	if output:
		output.append_text(prompt)
	_refresh_input_line()

func end_input_mode() -> void:
	"""Called to exit program input mode"""
	_program_input_mode = false
	_program_prompt = ""
	_program_output_buffer = ""

func _add_text_with_newlines(text: String) -> void:
	"""Helper to add text while properly handling newlines"""
	var lines = text.split("\n")
	for i in range(lines.size()):
		output.push_paragraph(HORIZONTAL_ALIGNMENT_LEFT)
		if lines[i].length() > 0:
			output.add_text(lines[i])
		else:
			output.add_text(" ")  # Space for empty lines
		output.pop()


func _refresh_display() -> void:
	if not output or is_typing or _slow_print_active:
		return

	var cursor_char := "_" if cursor_visible else " "

	# Save scroll position before clearing (to preserve user's scroll position)
	var scroll_bar = output.get_v_scroll_bar()
	var old_scroll = scroll_bar.value
	var was_at_bottom = old_scroll >= scroll_bar.max_value - 20

	# Program input mode
	if _program_input_mode and current_program:
		output.clear()
		_add_text_with_newlines(_program_output_buffer + _program_prompt + current_input + cursor_char)
		_restore_scroll(old_scroll, was_at_bottom)
		return

	# Passthrough mode (AI hosts)
	if passthrough_mode:
		output.clear()
		_add_text_with_newlines(_passthrough_base_text + current_input + cursor_char)
		_restore_scroll(old_scroll, was_at_bottom)
		return

	# Raw input mode
	if raw_input_mode and current_program:
		output.clear()
		_add_text_with_newlines(_last_output_text + current_input + cursor_char)
		_restore_scroll(old_scroll, was_at_bottom)
		return

	# Program running but not waiting for input
	if current_program:
		return

	# Normal DOS prompt mode - use stored base text
	output.clear()
	_add_text_with_newlines(_display_base + current_input + cursor_char)
	_restore_scroll(old_scroll, was_at_bottom)


func _restore_scroll(old_scroll: float, was_at_bottom: bool) -> void:
	"""Restore scroll position after display refresh"""
	# If new content was explicitly added, scroll to bottom
	if _should_scroll_to_bottom:
		output.get_v_scroll_bar().value = output.get_v_scroll_bar().max_value
		_should_scroll_to_bottom = false
		return

	# Otherwise restore the previous scroll position
	# Use call_deferred to ensure it happens after the RichTextLabel updates
	if was_at_bottom:
		call_deferred("_scroll_to_bottom_deferred")
	else:
		call_deferred("_set_scroll_deferred", old_scroll)


func _scroll_to_bottom_deferred() -> void:
	if output:
		output.get_v_scroll_bar().value = output.get_v_scroll_bar().max_value


func _set_scroll_deferred(scroll_value: float) -> void:
	if output:
		output.get_v_scroll_bar().value = scroll_value


# Legacy alias for compatibility
func _refresh_input_line() -> void:
	_refresh_display()


# ===== OUTPUT FUNCTIONS =====

func _update_display() -> void:
	"""Update the RichTextLabel with current output text"""
	if output:
		output.clear()
		# Use paragraph system to avoid font glyph issues with newlines
		var lines = _output_text.split("\n")
		for i in range(lines.size()):
			output.push_paragraph(HORIZONTAL_ALIGNMENT_LEFT)
			if lines[i].length() > 0:
				output.add_text(lines[i])
			else:
				output.add_text(" ")  # Add space for empty lines to ensure line height
			output.pop()
		_scroll_to_bottom()


func print_line(text: String) -> void:
	_output_text += text + "\n"
	_should_scroll_to_bottom = true
	_update_display()


func print_text(text: String) -> void:
	_output_text += text
	_should_scroll_to_bottom = true
	_update_display()


func type_line(text: String, speed: float = -1.0) -> void:
	if speed < 0:
		speed = typing_speed

	is_typing = true
	_should_scroll_to_bottom = true

	for c in text:
		_output_text += c
		_update_display()
		await get_tree().create_timer(speed).timeout

	_output_text += "\n"
	_update_display()
	is_typing = false


func print_slow(text: String, baud: int = 1200) -> void:
	is_typing = true
	_slow_print_active = true
	_should_scroll_to_bottom = true
	var char_delay = 10.0 / float(baud)

	for c in text:
		_output_text += c
		_update_display()
		await get_tree().create_timer(char_delay).timeout

	is_typing = false
	_slow_print_active = false


func clear_screen() -> void:
	_output_text = ""
	_display_base = ""
	_should_scroll_to_bottom = true
	if output:
		output.clear()


func get_screen_brightness() -> float:
	"""Returns a value 0.0-1.0 based on how much visible text is on screen"""
	if not output:
		return 0.05

	# Get only the visible portion of text
	var visible_lines = output.get_visible_line_count()
	var total_lines = output.get_line_count()
	var scroll_bar = output.get_v_scroll_bar()

	# Calculate which lines are visible based on scroll position
	var scroll_ratio = 0.0
	if scroll_bar and scroll_bar.max_value > 0:
		scroll_ratio = scroll_bar.value / scroll_bar.max_value

	# Get the text lines
	var lines = _output_text.split("\n")
	var start_line = 0
	var end_line = lines.size()

	# Estimate visible range (take last N lines if at bottom, or calculate from scroll)
	if lines.size() > visible_lines:
		if scroll_ratio >= 0.95:  # At or near bottom
			start_line = lines.size() - visible_lines
		else:
			start_line = int(scroll_ratio * (lines.size() - visible_lines))
		end_line = min(start_line + visible_lines, lines.size())

	# Count visible characters in only the visible lines
	var visible_chars = 0
	for i in range(start_line, end_line):
		if i < lines.size():
			for c in lines[i]:
				if c != " " and c != "\t":
					visible_chars += 1

	# Full screen is 2000 visible characters (80x25)
	# Scale from 0.05 (nearly empty/cursor only) to 1.0 (full)
	var fill_ratio = clamp(float(visible_chars) / 2000.0, 0.0, 1.0)
	return 0.05 + (fill_ratio * 0.95)


func _scroll_to_bottom(force: bool = false) -> void:
	if output and (force or _should_scroll_to_bottom):
		output.scroll_to_line(output.get_line_count())
		_should_scroll_to_bottom = false


# ===== BUILT-IN COMMANDS =====

func _cmd_dir(args: Array) -> void:
	var target_drive = current_drive
	var target_path = current_path
	var show_all = false  # /A switch to show hidden/system files

	# Parse arguments
	for arg in args:
		var upper_arg = arg.to_upper()
		if upper_arg == "/A" or upper_arg == "/AH" or upper_arg == "/AS":
			show_all = true
		elif upper_arg == "A:" or upper_arg == "A":
			target_drive = "A:"
			target_path = "\\"
		elif upper_arg == "C:" or upper_arg == "C":
			target_drive = "C:"
			target_path = "\\"
		elif upper_arg.begins_with("A:\\"):
			target_drive = "A:"
			target_path = "\\" + upper_arg.substr(3)
		elif upper_arg.begins_with("C:\\"):
			target_drive = "C:"
			target_path = "\\" + upper_arg.substr(3)
		elif not upper_arg.begins_with("/"):
			# Relative path (not a switch)
			target_path = _resolve_path(upper_arg)

	if target_drive == "A:" and not floppy_disk_inserted:
		print_line("")
		print_line("Not ready reading drive A")
		print_line("")
		return

	var fs_to_use = filesystem if target_drive == "C:" else floppy_filesystem
	var vol_label = volume_label if target_drive == "C:" else floppy_disk_label

	# Build full directory key
	var dir_key = target_drive + target_path
	if not dir_key.ends_with("\\"):
		dir_key += "\\"
	# Clean up double backslashes
	dir_key = dir_key.replace("\\\\", "\\")
	if dir_key.ends_with("\\") and dir_key.length() > 3:
		dir_key = dir_key.trim_suffix("\\")

	print_line("")
	print_line(" Volume in drive %s is %s" % [target_drive.trim_suffix(":"), vol_label])
	print_line(" Directory of " + dir_key)
	print_line("")

	if not fs_to_use.has(dir_key):
		print_line("Invalid directory")
		print_line("")
		return

	if fs_to_use[dir_key].type != "dir":
		print_line("Invalid directory")
		print_line("")
		return

	var file_count = 0
	var dir_count = 0

	# Show . and .. for non-root directories
	if target_path != "\\":
		print_line(".              <DIR>        03-15-87  12:00a")
		print_line("..             <DIR>        03-15-87  12:00a")

	for item in fs_to_use[dir_key].contents:
		var file_key = dir_key
		if not file_key.ends_with("\\"):
			file_key += "\\"
		file_key += item

		# Skip hidden files unless /A switch used
		if not show_all and _is_hidden(file_key):
			continue

		if fs_to_use.has(file_key):
			if fs_to_use[file_key].type == "dir":
				print_line("%-14s <DIR>        03-15-87  12:00a" % [item])
				dir_count += 1
			else:
				var size_val = 1024
				if fs_to_use[file_key].type == "exe":
					size_val = 8192
				elif fs_to_use[file_key].has("content"):
					size_val = fs_to_use[file_key].content.length()
				print_line("%-14s %7d      03-15-87  12:00a" % [item, size_val])
				file_count += 1
		else:
			# File exists in contents but no explicit entry - assume file
			print_line("%-14s %7d      03-15-87  12:00a" % [item, 1024])
			file_count += 1

	print_line("       %d File(s)" % file_count)
	if dir_count > 0:
		print_line("       %d Dir(s)" % dir_count)


func _cmd_cls(_args: Array) -> void:
	clear_screen()
	_refresh_display()


func _cmd_type(args: Array) -> void:
	if args.is_empty():
		print_line("Required parameter missing")
		print_line("")
		return

	var filename = args[0].to_upper()
	var file_key = _get_full_path(filename)
	var fs_to_use = filesystem if current_drive == "C:" else floppy_filesystem

	if fs_to_use.has(file_key) and fs_to_use[file_key].type == "file":
		print_line("")
		for line in fs_to_use[file_key].get("content", "").split("\n"):
			print_line(line)
		print_line("")
	else:
		print_line("File not found - " + filename)
		print_line("")


func _cmd_del(args: Array) -> void:
	if args.is_empty():
		print_line("Required parameter missing")
		print_line("")
		return

	var filename = args[0].to_upper()
	var file_key = _get_full_path(filename)
	var fs_to_use = filesystem if current_drive == "C:" else floppy_filesystem

	if not fs_to_use.has(file_key):
		print_line("File not found - " + filename)
		print_line("")
		return

	if fs_to_use[file_key].type == "dir":
		print_line("Invalid file name")
		print_line("Use RD to remove directories")
		print_line("")
		return

	# Check if it's a protected file
	if _is_readonly(file_key):
		print_line("Access denied - File is read-only")
		print_line("")
		return
	if _is_system(file_key):
		print_line("Access denied - System file")
		print_line("")
		return

	# Remove from parent directory contents
	var parent_key = _get_dos_dir(file_key)
	var file_name_only = _get_dos_filename(file_key)
	if fs_to_use.has(parent_key) and fs_to_use[parent_key].type == "dir":
		var idx = fs_to_use[parent_key].contents.find(file_name_only)
		if idx >= 0:
			fs_to_use[parent_key].contents.remove_at(idx)

	# Remove the file
	fs_to_use.erase(file_key)

	_notify_filesystem_change()

	# Sync via WebSocket (only for C: drive)
	if current_drive == "C:" and OnlineManager.is_online and OnlineManager.is_registered:
		OnlineManager.delete_file(file_key)

	print_line("")


func _cmd_date(_args: Array) -> void:
	print_line("Current date is " + GameState.get_formatted_date())
	print_line("")


func _cmd_time(_args: Array) -> void:
	var time = Time.get_time_dict_from_system()
	print_line("Current time is %02d:%02d:%02d.00" % [time.hour, time.minute, time.second])
	print_line("")


func _cmd_ver(_args: Array) -> void:
	print_line("")
	print_line("SHADOW-DOS Version 1.0")
	print_line("(C) Copyright Shadow Systems Inc 1987")
	print_line("")


func _cmd_help(_args: Array) -> void:
	print_line("")
	print_line("SHADOW-DOS Commands:")
	print_line("")
	print_line("File Commands:")
	print_line("  DIR [/A]     - Display directory (/A=show hidden)")
	print_line("  CD/CHDIR     - Change current directory")
	print_line("  MD/MKDIR     - Create a directory")
	print_line("  RD/RMDIR     - Remove a directory")
	print_line("  COPY         - Copy files")
	print_line("  REN/RENAME   - Rename a file")
	print_line("  DEL          - Delete files")
	print_line("  TYPE         - Display file contents")
	print_line("  ATTRIB       - Display/change file attributes")
	print_line("  TREE         - Display directory tree")
	print_line("  VERSION      - File version history")
	print_line("")
	print_line("System Commands:")
	print_line("  CLS          - Clear screen")
	print_line("  DATE         - Display current date")
	print_line("  TIME         - Display current time")
	print_line("  VER          - Display DOS version")
	print_line("  MEM          - Display memory usage")
	print_line("  VOL          - Display volume label")
	print_line("  LABEL        - Set volume label")
	print_line("  CHKDSK       - Check disk status")
	print_line("  FORMAT       - Format a disk")
	print_line("")
	print_line("Text Commands:")
	print_line("  ECHO         - Display text")
	print_line("  MORE         - Display file page by page")
	print_line("  FIND         - Search for text in files")
	print_line("  SORT         - Sort file contents")
	print_line("")
	print_line("Environment:")
	print_line("  SET          - Display/set environment variables")
	print_line("  PATH         - Display/set search path")
	print_line("  PROMPT       - Change command prompt")
	print_line("")
	print_line("Session:")
	print_line("  HISTORY      - Show command history")
	print_line("  SESSION      - Manage saved sessions")
	print_line("  APIKEY       - Configure AI host API key")
	print_line("  A: or C:     - Switch to drive")
	print_line("")
	print_line("Programs:")
	print_line("  EDIT         - Full-screen text editor")
	print_line("  WD.EXE       - War Dialer (from floppy)")
	print_line("")


func _cmd_mem(_args: Array) -> void:
	print_line("")
	print_line("Memory Type        Total      Used      Free")
	print_line("---------------  --------  --------  --------")
	print_line("Conventional       640K       128K      512K")
	print_line("Extended           384K         0K      384K")
	print_line("")


func _cmd_history(_args: Array) -> void:
	if command_history.is_empty():
		print_line("No command history.")
		return
	
	print_line("")
	print_line("Command History:")
	var start = max(0, command_history.size() - 20)
	for i in range(start, command_history.size()):
		print_line("  %3d: %s" % [i + 1, command_history[i]])
	print_line("")


func _cmd_session(args: Array) -> void:
	if args.is_empty():
		print_line("")
		print_line("Current Session: " + SessionManager.current_session_id)
		if OnlineManager.is_registered:
			print_line("Player Handle:   " + OnlineManager.player_handle)
			print_line("Phone Number:    " + OnlineManager.player_phone)
			print_line("Network Status:  " + ("ONLINE" if OnlineManager.is_online else "OFFLINE"))
		else:
			print_line("Network Status:  NOT REGISTERED")
		print_line("")
		print_line("Usage:")
		print_line("  SESSION SAVE         - Save current session")
		print_line("  SESSION LIST         - List all sessions")
		print_line("  SESSION LOAD <id>    - Load a session")
		print_line("  SESSION NEW          - Start new session")
		print_line("  SESSION RECOVER <code> - Restore player identity")
		print_line("")
		return

	var subcmd = args[0].to_upper()
	match subcmd:
		"SAVE":
			SessionManager.save_session()
			print_line("Session saved.")
		"LIST":
			var sessions = SessionManager.get_saved_sessions()
			print_line("")
			print_line("Saved Sessions:")
			for s in sessions:
				var current = " <--" if s.session_id == SessionManager.current_session_id else ""
				print_line("  %s - %d modems%s" % [s.session_id, s.modem_count, current])
			print_line("")
		"NEW":
			SessionManager.create_new_session()
			print_line("New session created: " + SessionManager.current_session_id)
		"LOAD":
			if args.size() > 1:
				if SessionManager.load_session(args[1]):
					print_line("Session loaded: " + args[1])
				else:
					print_line("Failed to load session.")
			else:
				print_line("Usage: SESSION LOAD <session_id>")
		"RECOVER":
			await _session_recover(args)
		_:
			print_line("Unknown session command.")


func _session_recover(args: Array) -> void:
	"""Recover player identity using recovery code"""
	if args.size() < 2:
		print_line("")
		print_line("Usage: SESSION RECOVER <recovery-code>")
		print_line("Example: SESSION RECOVER SHADOW-7X9K-M2P1")
		print_line("")
		return

	var code = args[1].to_upper()
	print_line("")
	print_line("Contacting Shadow Network...")

	OnlineManager.recover_session(code)

	# Wait for response with timeout
	var timeout = 5.0
	var start_time = Time.get_ticks_msec()
	var result_received = false
	var result_success = false
	var result_data = {}

	OnlineManager.recovery_complete.connect(
		func(success: bool, data: Dictionary):
			result_received = true
			result_success = success
			result_data = data,
		CONNECT_ONE_SHOT
	)

	while not result_received and (Time.get_ticks_msec() - start_time) < timeout * 1000:
		await get_tree().create_timer(0.1).timeout

	if result_received and result_success:
		print_line("")
		print_line("Identity restored!")
		print_line("")
		print_line("Handle: " + OnlineManager.player_handle)
		print_line("Phone:  " + OnlineManager.player_phone)
		print_line("")
		print_line("Syncing filesystem...")
		await _fetch_and_apply_filesystem()
		print_line("Sync complete.")
		print_line("")
	elif result_received:
		var error = result_data.get("error", "UNKNOWN")
		if error == "INVALID_CODE":
			print_line("ERROR: Recovery code not found.")
		else:
			print_line("ERROR: " + result_data.get("message", "Recovery failed"))
		print_line("")
	else:
		print_line("ERROR: Network unreachable.")
		print_line("")


func _cmd_apikey(args: Array) -> void:
	if args.is_empty():
		if SettingsManager.has_openai_key():
			print_line("API key is configured.")
		else:
			print_line("No API key configured.")
		print_line("")
		print_line("Usage: APIKEY <your-openai-key>")
		return
	
	SettingsManager.set_openai_key(args[0])
	print_line("API key saved.")


func _cmd_exit(_args: Array) -> void:
	if current_program:
		stop_program()
	else:
		print_line("No program running.")


# ===== PATH RESOLUTION HELPER =====

func _resolve_path(path: String) -> String:
	"""Resolve a relative or absolute path to an absolute path"""
	path = path.to_upper().replace("/", "\\")

	# Already absolute
	if path.begins_with("\\"):
		return path

	# Handle .. and .
	var parts = Array(path.split("\\", false))
	var current_parts = Array(current_path.split("\\", false))

	for part in parts:
		if part == "..":
			if current_parts.size() > 0:
				current_parts.pop_back()
		elif part == ".":
			pass  # Stay in current
		else:
			current_parts.append(part)

	if current_parts.is_empty():
		return "\\"
	return "\\" + "\\".join(current_parts)


func _get_full_path(path: String) -> String:
	"""Get full path including drive letter"""
	var resolved = _resolve_path(path)
	return current_drive + resolved


func _notify_filesystem_change() -> void:
	"""Notify that the filesystem has changed - triggers local save"""
	# Don't re-sync when applying remote changes
	if _applying_remote_change:
		return

	# Mark session dirty for local save
	SessionManager.mark_dirty()
	# Note: Individual file operations now sync via WebSocket, not full filesystem sync


func _get_dos_filename(path: String) -> String:
	"""Get the filename from a DOS path (backslash separated)"""
	var parts = path.split("\\")
	if parts.size() > 0:
		return parts[parts.size() - 1]
	return path


func _get_dos_dir(path: String) -> String:
	"""Get the directory from a DOS path (backslash separated)"""
	var parts = path.split("\\")
	if parts.size() > 1:
		parts.resize(parts.size() - 1)
		var result = "\\".join(parts)
		if result == "C:" or result == "A:":
			return result + "\\"
		return result
	return path


# ===== FILE ATTRIBUTE HELPERS =====

func _get_file_attr(path: String) -> String:
	"""Get the attributes string for a file/directory"""
	var fs_to_use = filesystem if path.begins_with("C:") else floppy_filesystem
	if fs_to_use.has(path):
		return fs_to_use[path].get("attr", "")
	return ""


func _has_attr(path: String, attr: String) -> bool:
	"""Check if a file has a specific attribute"""
	return _get_file_attr(path).contains(attr)


func _is_readonly(path: String) -> bool:
	"""Check if file is read-only (R attribute)"""
	return _has_attr(path, ATTR_READONLY)


func _is_hidden(path: String) -> bool:
	"""Check if file is hidden (H attribute)"""
	return _has_attr(path, ATTR_HIDDEN)


func _is_system(path: String) -> bool:
	"""Check if file is a system file (S attribute)"""
	return _has_attr(path, ATTR_SYSTEM)


func _set_file_attr(path: String, attr: String) -> bool:
	"""Set the attributes string for a file. Returns true if successful."""
	var fs_to_use = filesystem if path.begins_with("C:") else floppy_filesystem
	if not fs_to_use.has(path):
		return false
	fs_to_use[path]["attr"] = attr
	return true


func _add_attr(path: String, attr: String) -> bool:
	"""Add an attribute to a file. Returns true if successful."""
	var current = _get_file_attr(path)
	if current.contains(attr):
		return true  # Already has it
	return _set_file_attr(path, current + attr)


func _remove_attr(path: String, attr: String) -> bool:
	"""Remove an attribute from a file. Returns true if successful."""
	var current = _get_file_attr(path)
	if not current.contains(attr):
		return true  # Already doesn't have it
	return _set_file_attr(path, current.replace(attr, ""))


func _format_attr_display(attr: String) -> String:
	"""Format attributes for display like DOS ATTRIB command"""
	var r = "R" if attr.contains(ATTR_READONLY) else " "
	var a = "A" if attr.contains(ATTR_ARCHIVE) else " "
	var s = "S" if attr.contains(ATTR_SYSTEM) else " "
	var h = "H" if attr.contains(ATTR_HIDDEN) else " "
	return "%s  %s%s%s" % [a, s, h, r]


func _build_file_metadata(path: String) -> Dictionary:
	"""Build metadata dictionary for server sync, including attr"""
	var metadata := {}
	var attr = _get_file_attr(path)
	if not attr.is_empty():
		metadata["attr"] = attr
	return metadata


# ===== FILESYSTEM SYNC HELPERS =====

func _is_protected_path(path: String) -> bool:
	"""Check if a path is protected (read-only or system attribute)"""
	if path == "C:\\":
		return true
	# Check file attributes - R or S means protected
	if _is_readonly(path) or _is_system(path):
		return true
	return false


func _rebuild_directory_contents(fs: Dictionary) -> Dictionary:
	"""Rebuild contents arrays for directories from flat filesystem data"""
	var result := {}

	# Deep copy all entries
	for path in fs.keys():
		result[path] = fs[path].duplicate(true) if fs[path] is Dictionary else fs[path]

	# Initialize contents arrays for all directories
	for path in result.keys():
		if result[path] is Dictionary and result[path].get("type") == "dir":
			result[path]["contents"] = []

	# Populate contents based on child paths
	for path in result.keys():
		if path == "C:\\" or path == "A:\\":
			continue
		var parent_path := _get_dos_dir(path)
		var filename := _get_dos_filename(path)
		if result.has(parent_path) and result[parent_path] is Dictionary and result[parent_path].get("type") == "dir":
			if filename not in result[parent_path].contents:
				result[parent_path].contents.append(filename)

	return result


func apply_fetched_filesystem(fetched: Dictionary) -> void:
	"""Apply filesystem from server, preserving protected system files"""
	if fetched.is_empty():
		print("[Terminal] No filesystem data to apply")
		return

	# Rebuild contents arrays from flat server data
	var processed := _rebuild_directory_contents(fetched)

	# Start with default system files
	var new_fs := {}
	for path in DEFAULT_FILESYSTEM.keys():
		new_fs[path] = DEFAULT_FILESYSTEM[path].duplicate(true)

	# Apply fetched entries, skipping protected paths
	for path in processed.keys():
		if _is_protected_path(path):
			continue
		new_fs[path] = processed[path]

	# Rebuild root directory contents to include all top-level items
	var root_contents: Array = []
	for path in new_fs.keys():
		if path == "C:\\":
			continue
		# Check if direct child of root
		var relative = path.substr(3)  # Remove "C:\"
		if "\\" not in relative and relative.length() > 0:
			if relative not in root_contents:
				root_contents.append(relative)
	new_fs["C:\\"]["contents"] = root_contents

	# Replace filesystem
	filesystem = new_fs
	print("[Terminal] Applied filesystem: %d entries" % filesystem.size())


func _fetch_and_apply_filesystem() -> void:
	"""Fetch filesystem from server and apply it"""
	if not OnlineManager.is_online or OnlineManager.session_token.is_empty():
		return

	OnlineManager.fetch_filesystem()

	# Wait for response with timeout
	var timeout = 5.0
	var start_time = Time.get_ticks_msec()
	var result_received = false
	var result_filesystem = {}

	OnlineManager.filesystem_fetched.connect(
		func(success: bool, fs: Dictionary):
			result_received = true
			if success:
				result_filesystem = fs,
		CONNECT_ONE_SHOT
	)

	while not result_received and (Time.get_ticks_msec() - start_time) < timeout * 1000:
		await get_tree().create_timer(0.1).timeout

	if result_received and not result_filesystem.is_empty():
		apply_fetched_filesystem(result_filesystem)


# ===== REMOTE CHANGE HANDLERS =====

func _on_remote_file_change(path: String, content: String, file_type: String, program: String, metadata: Dictionary) -> void:
	"""Handle file change from another device via WebSocket"""
	if _is_protected_path(path):
		return  # Don't allow remote changes to protected paths

	_applying_remote_change = true

	# Update local filesystem
	var entry := {"type": file_type}
	if file_type == "file":
		entry["content"] = content
	elif file_type == "exe" and not program.is_empty():
		entry["program"] = program
	elif file_type == "dir":
		entry["contents"] = []

	# Apply attributes from metadata
	if metadata.has("attr"):
		entry["attr"] = metadata.get("attr", "")

	filesystem[path] = entry

	# Update parent directory contents
	var parent_path = _get_dos_dir(path)
	var filename = _get_dos_filename(path)
	if filesystem.has(parent_path) and filesystem[parent_path].type == "dir":
		if filename not in filesystem[parent_path].contents:
			filesystem[parent_path].contents.append(filename)

	print("[Terminal] Remote change applied: %s" % path)
	_applying_remote_change = false


func _on_remote_file_delete(path: String) -> void:
	"""Handle file deletion from another device via WebSocket"""
	if _is_protected_path(path):
		return  # Don't allow remote deletions of protected paths

	_applying_remote_change = true

	if filesystem.has(path):
		# Remove from parent directory contents
		var parent_path = _get_dos_dir(path)
		var filename = _get_dos_filename(path)
		if filesystem.has(parent_path) and filesystem[parent_path].type == "dir":
			var idx = filesystem[parent_path].contents.find(filename)
			if idx >= 0:
				filesystem[parent_path].contents.remove_at(idx)

		# Remove the file/directory
		filesystem.erase(path)
		print("[Terminal] Remote delete applied: %s" % path)

	_applying_remote_change = false


# Variables for VERSION command async handling
var _pending_version_path: String = ""

func _on_versions_received(path: String, current: Dictionary, versions: Array) -> void:
	"""Handle version history response"""
	if path != _pending_version_path:
		return

	print_line("")
	print_line("File: " + path)
	if current and not current.is_empty():
		print_line("Current size: %d bytes" % current.get("file_size", 0))
	else:
		print_line("File not found (may have been deleted)")
	print_line("")

	if versions.is_empty():
		print_line("No version history available.")
	else:
		print_line("Version History:")
		for v in versions:
			var size_str = "%d bytes" % v.get("file_size", 0)
			print_line("  %d. %s  (%s)" % [v.get("version", 0), v.get("created_at", ""), size_str])

	print_line("")
	print_line("Use VERSION <file> RESTORE <n> to restore.")
	print_line("")
	_pending_version_path = ""
	_show_prompt()


func _on_version_restored(path: String, version: int) -> void:
	"""Handle version restore confirmation"""
	print_line("")
	print_line("Restored %s to version %d" % [path, version])
	print_line("")

	# Refresh from server
	OnlineManager.fetch_filesystem()


# ===== NEW DOS COMMANDS =====

func _cmd_cd(args: Array) -> void:
	if args.is_empty():
		# Just show current directory
		print_line(current_drive + current_path)
		print_line("")
		return

	var target = args[0].to_upper()

	# Handle drive letter in path
	var target_drive = current_drive
	if target.begins_with("A:\\") or target.begins_with("C:\\"):
		target_drive = target.substr(0, 2) + ":"
		target = target.substr(3)
	elif target == ".." or target.begins_with("..\\"):
		pass  # Handle relative
	elif target == "\\":
		current_path = "\\"
		print_line("")
		return

	var new_path = _resolve_path(target)

	# Root directory is always valid
	if new_path == "\\" or new_path.length() == 1:
		current_path = "\\"
		current_drive = target_drive
		return

	# Verify directory exists
	var dir_key = target_drive + new_path
	if dir_key.ends_with("\\") and dir_key.length() > 3:
		dir_key = dir_key.trim_suffix("\\")

	var fs_to_use = filesystem if target_drive == "C:" else floppy_filesystem

	if target_drive == "A:" and not floppy_disk_inserted:
		print_line("Not ready reading drive A")
		print_line("")
		return

	if not fs_to_use.has(dir_key) or fs_to_use[dir_key].type != "dir":
		print_line("Invalid directory")
		print_line("")
		return

	current_path = new_path
	if current_path != "\\" and not current_path.ends_with("\\"):
		pass  # Keep without trailing slash
	print_line("")


func _cmd_md(args: Array) -> void:
	if args.is_empty():
		print_line("Required parameter missing")
		print_line("")
		return

	var dirname = args[0].to_upper()
	var parent_key = current_drive + current_path
	if parent_key.ends_with("\\") and parent_key.length() > 3:
		parent_key = parent_key.trim_suffix("\\")

	var new_dir_key = parent_key
	if not new_dir_key.ends_with("\\"):
		new_dir_key += "\\"
	new_dir_key += dirname

	var fs_to_use = filesystem if current_drive == "C:" else floppy_filesystem

	if fs_to_use.has(new_dir_key):
		print_line("Directory already exists")
		print_line("")
		return

	# Create new directory locally
	fs_to_use[new_dir_key] = {"type": "dir", "contents": []}

	# Add to parent contents
	if fs_to_use.has(parent_key):
		fs_to_use[parent_key].contents.append(dirname)

	_notify_filesystem_change()

	# Sync via WebSocket (only for C: drive)
	if current_drive == "C:" and OnlineManager.is_online and OnlineManager.is_registered:
		OnlineManager.create_directory(new_dir_key)

	print_line("")


func _cmd_rd(args: Array) -> void:
	if args.is_empty():
		print_line("Required parameter missing")
		print_line("")
		return

	var dirname = args[0].to_upper()
	var parent_key = current_drive + current_path
	if parent_key.ends_with("\\") and parent_key.length() > 3:
		parent_key = parent_key.trim_suffix("\\")

	var dir_key = parent_key
	if not dir_key.ends_with("\\"):
		dir_key += "\\"
	dir_key += dirname

	var fs_to_use = filesystem if current_drive == "C:" else floppy_filesystem

	if not fs_to_use.has(dir_key):
		print_line("Invalid directory")
		print_line("")
		return

	if fs_to_use[dir_key].type != "dir":
		print_line("Invalid directory")
		print_line("")
		return

	# Check if it's a protected directory
	if _is_readonly(dir_key):
		print_line("Access denied - Directory is read-only")
		print_line("")
		return
	if _is_system(dir_key):
		print_line("Access denied - System directory")
		print_line("")
		return

	if fs_to_use[dir_key].contents.size() > 0:
		print_line("Invalid path, not directory,")
		print_line("or directory not empty")
		print_line("")
		return

	# Remove directory
	fs_to_use.erase(dir_key)

	# Remove from parent contents
	if fs_to_use.has(parent_key):
		var idx = fs_to_use[parent_key].contents.find(dirname)
		if idx >= 0:
			fs_to_use[parent_key].contents.remove_at(idx)

	_notify_filesystem_change()

	# Sync via WebSocket (only for C: drive)
	if current_drive == "C:" and OnlineManager.is_online and OnlineManager.is_registered:
		OnlineManager.remove_directory(dir_key)

	print_line("")


func _cmd_copy(args: Array) -> void:
	if args.size() < 2:
		print_line("Required parameter missing")
		print_line("")
		return

	var source = args[0].to_upper()
	var dest = args[1].to_upper()

	var source_key = _get_full_path(source)
	var fs_to_use = filesystem if current_drive == "C:" else floppy_filesystem

	if not fs_to_use.has(source_key):
		print_line("File not found - " + source)
		print_line("")
		return

	if fs_to_use[source_key].type == "dir":
		print_line("Cannot copy a directory")
		print_line("")
		return

	var dest_key = _get_full_path(dest)

	# Check if destination is a protected file (only if it exists)
	if fs_to_use.has(dest_key):
		if _is_readonly(dest_key):
			print_line("Access denied - Destination is read-only")
			print_line("")
			return
		if _is_system(dest_key):
			print_line("Access denied - Cannot overwrite system file")
			print_line("")
			return

	# Copy the file
	fs_to_use[dest_key] = fs_to_use[source_key].duplicate()

	# Extract filename for parent directory
	var dest_filename = _get_dos_filename(dest_key)
	var dest_dir = _get_dos_dir(dest_key)
	if fs_to_use.has(dest_dir) and fs_to_use[dest_dir].type == "dir":
		if not dest_filename in fs_to_use[dest_dir].contents:
			fs_to_use[dest_dir].contents.append(dest_filename)

	_notify_filesystem_change()

	# Sync via WebSocket (only for C: drive)
	if current_drive == "C:" and OnlineManager.is_online and OnlineManager.is_registered:
		var file_data = fs_to_use[dest_key]
		var content = file_data.get("content", "")
		var file_type = file_data.get("type", "file")
		var program = file_data.get("program", "")
		var metadata = _build_file_metadata(dest_key)
		OnlineManager.create_or_update_file(dest_key, content, file_type, program, metadata)

	print_line("        1 file(s) copied")
	print_line("")


func _cmd_rename(args: Array) -> void:
	if args.size() < 2:
		print_line("Required parameter missing")
		print_line("")
		return

	var oldname = args[0].to_upper()
	var newname = args[1].to_upper()

	var old_key = _get_full_path(oldname)
	var fs_to_use = filesystem if current_drive == "C:" else floppy_filesystem

	if not fs_to_use.has(old_key):
		print_line("File not found - " + oldname)
		print_line("")
		return

	# Check if it's a protected file
	if _is_readonly(old_key):
		print_line("Access denied - File is read-only")
		print_line("")
		return
	if _is_system(old_key):
		print_line("Access denied - System file")
		print_line("")
		return

	# Create new entry with new name
	var parent_key = _get_dos_dir(old_key)
	var new_key = parent_key
	if not new_key.ends_with("\\"):
		new_key += "\\"
	new_key += newname

	var file_data = fs_to_use[old_key].duplicate()
	fs_to_use[new_key] = file_data
	fs_to_use.erase(old_key)

	# Update parent contents
	var old_filename = _get_dos_filename(old_key)
	if fs_to_use.has(parent_key) and fs_to_use[parent_key].type == "dir":
		var idx = fs_to_use[parent_key].contents.find(old_filename)
		if idx >= 0:
			fs_to_use[parent_key].contents[idx] = newname

	_notify_filesystem_change()

	# Sync via WebSocket (only for C: drive) - rename = delete old + create new
	if current_drive == "C:" and OnlineManager.is_online and OnlineManager.is_registered:
		OnlineManager.delete_file(old_key)
		var content = file_data.get("content", "")
		var file_type = file_data.get("type", "file")
		var program = file_data.get("program", "")
		var metadata = _build_file_metadata(new_key)
		OnlineManager.create_or_update_file(new_key, content, file_type, program, metadata)

	print_line("")


func _cmd_echo(args: Array) -> void:
	if args.is_empty():
		print_line("ECHO is on")
		print_line("")
		return

	var text = " ".join(args)
	print_line(text)
	print_line("")


func _cmd_set(args: Array) -> void:
	if args.is_empty():
		# Show all environment variables
		print_line("")
		for key in env_vars:
			print_line("%s=%s" % [key, env_vars[key]])
		print_line("")
		return

	var arg = " ".join(args)
	var eq_pos = arg.find("=")
	if eq_pos > 0:
		var key = arg.substr(0, eq_pos).to_upper()
		var value = arg.substr(eq_pos + 1)
		env_vars[key] = value
	else:
		# Show specific variable
		var key = arg.to_upper()
		if env_vars.has(key):
			print_line("%s=%s" % [key, env_vars[key]])
		else:
			print_line("Environment variable %s not defined" % key)
	print_line("")


func _cmd_path(args: Array) -> void:
	if args.is_empty():
		print_line("PATH=" + env_vars.get("PATH", ""))
		print_line("")
		return

	env_vars["PATH"] = " ".join(args).to_upper()
	print_line("")


func _cmd_prompt(args: Array) -> void:
	if args.is_empty():
		print_line("Current prompt: " + env_vars.get("PROMPT", "$P$G"))
		print_line("")
		return

	env_vars["PROMPT"] = " ".join(args)
	print_line("")


func _cmd_more(args: Array) -> void:
	if args.is_empty():
		print_line("Required parameter missing")
		print_line("")
		return

	var filename = args[0].to_upper()
	var file_key = _get_full_path(filename)
	var fs_to_use = filesystem if current_drive == "C:" else floppy_filesystem

	if not fs_to_use.has(file_key) or fs_to_use[file_key].type != "file":
		print_line("File not found - " + filename)
		print_line("")
		return

	var content = fs_to_use[file_key].get("content", "")
	var lines = content.split("\n")

	print_line("")
	for i in range(lines.size()):
		print_line(lines[i])
		# In a real implementation, we'd pause every 24 lines
		# For simplicity, just show all content
	print_line("")


func _cmd_find(args: Array) -> void:
	if args.size() < 2:
		print_line("Required parameter missing")
		print_line("Usage: FIND \"text\" filename")
		print_line("")
		return

	var search_text = args[0].trim_prefix("\"").trim_suffix("\"")
	var filename = args[1].to_upper()

	var file_key = _get_full_path(filename)
	var fs_to_use = filesystem if current_drive == "C:" else floppy_filesystem

	if not fs_to_use.has(file_key) or fs_to_use[file_key].type != "file":
		print_line("File not found - " + filename)
		print_line("")
		return

	print_line("")
	print_line("---------- " + filename)

	var content = fs_to_use[file_key].get("content", "")
	var lines = content.split("\n")
	var found = false

	for line in lines:
		if line.to_upper().contains(search_text.to_upper()):
			print_line(line)
			found = true

	if not found:
		print_line("(no matches found)")
	print_line("")


func _cmd_sort(args: Array) -> void:
	if args.is_empty():
		print_line("Required parameter missing")
		print_line("")
		return

	var filename = args[0].to_upper()
	var file_key = _get_full_path(filename)
	var fs_to_use = filesystem if current_drive == "C:" else floppy_filesystem

	if not fs_to_use.has(file_key) or fs_to_use[file_key].type != "file":
		print_line("File not found - " + filename)
		print_line("")
		return

	var content = fs_to_use[file_key].get("content", "")
	var lines = content.split("\n")
	lines.sort()

	print_line("")
	for line in lines:
		print_line(line)
	print_line("")


func _cmd_attrib(args: Array) -> void:
	"""Display or change file attributes.
	Usage: ATTRIB [+R|-R] [+A|-A] [+S|-S] [+H|-H] [filename]
	  +R/-R  Set/clear Read-only attribute
	  +A/-A  Set/clear Archive attribute
	  +S/-S  Set/clear System attribute
	  +H/-H  Set/clear Hidden attribute
	"""
	if args.is_empty():
		# Show attributes for all files in current directory
		var dir_key = current_drive + current_path
		if dir_key.ends_with("\\") and dir_key.length() > 3:
			dir_key = dir_key.trim_suffix("\\")

		var fs_to_use = filesystem if current_drive == "C:" else floppy_filesystem

		print_line("")
		if fs_to_use.has(dir_key) and fs_to_use[dir_key].type == "dir":
			for item in fs_to_use[dir_key].contents:
				var file_key = dir_key
				if not file_key.ends_with("\\"):
					file_key += "\\"
				file_key += item
				var attr_str = _get_file_attr(file_key)
				var display = _format_attr_display(attr_str)
				print_line("%s  %s" % [display, file_key])
		print_line("")
		return

	# Parse arguments for attribute changes and filename
	var add_attrs: Array[String] = []
	var remove_attrs: Array[String] = []
	var filename = ""

	for arg in args:
		var upper_arg = arg.to_upper()
		if upper_arg.begins_with("+"):
			var attr = upper_arg.substr(1)
			if attr in [ATTR_READONLY, ATTR_ARCHIVE, ATTR_SYSTEM, ATTR_HIDDEN]:
				add_attrs.append(attr)
			else:
				print_line("Invalid attribute: " + arg)
				print_line("")
				return
		elif upper_arg.begins_with("-"):
			var attr = upper_arg.substr(1)
			if attr in [ATTR_READONLY, ATTR_ARCHIVE, ATTR_SYSTEM, ATTR_HIDDEN]:
				remove_attrs.append(attr)
			else:
				print_line("Invalid attribute: " + arg)
				print_line("")
				return
		else:
			filename = upper_arg

	# If no filename specified, show usage
	if filename.is_empty() and (add_attrs.size() > 0 or remove_attrs.size() > 0):
		print_line("Required parameter missing")
		print_line("")
		return

	var file_key = _get_full_path(filename) if not filename.is_empty() else ""
	var fs_to_use = filesystem if current_drive == "C:" else floppy_filesystem

	# If just filename, show its attributes
	if add_attrs.is_empty() and remove_attrs.is_empty():
		if not filename.is_empty():
			if fs_to_use.has(file_key):
				var attr_str = _get_file_attr(file_key)
				var display = _format_attr_display(attr_str)
				print_line("")
				print_line("%s  %s" % [display, file_key])
				print_line("")
			else:
				print_line("File not found - " + filename)
				print_line("")
		return

	# Modifying attributes
	if not fs_to_use.has(file_key):
		print_line("File not found - " + filename)
		print_line("")
		return

	# Check if trying to modify system file's S attribute
	if ATTR_SYSTEM in remove_attrs and _is_system(file_key):
		# Allow removing S only if not in DEFAULT_FILESYSTEM
		if DEFAULT_FILESYSTEM.has(file_key):
			print_line("Access denied - Cannot modify system file")
			print_line("")
			return

	# Apply attribute changes
	for attr in remove_attrs:
		_remove_attr(file_key, attr)
	for attr in add_attrs:
		_add_attr(file_key, attr)

	_notify_filesystem_change()

	# Sync attribute change to server
	if current_drive == "C:" and OnlineManager.is_online and OnlineManager.is_registered:
		var file_data = fs_to_use[file_key]
		var content = file_data.get("content", "")
		var file_type = file_data.get("type", "file")
		var program = file_data.get("program", "")
		var metadata = _build_file_metadata(file_key)
		OnlineManager.create_or_update_file(file_key, content, file_type, program, metadata)

	print_line("")


func _cmd_tree(args: Array) -> void:
	var target_drive = current_drive
	if args.size() > 0 and (args[0].to_upper() == "A:" or args[0].to_upper() == "C:"):
		target_drive = args[0].to_upper()

	if target_drive == "A:" and not floppy_disk_inserted:
		print_line("Not ready reading drive A")
		print_line("")
		return

	var fs_to_use = filesystem if target_drive == "C:" else floppy_filesystem

	print_line("")
	print_line("Directory PATH listing for Volume %s" % volume_label if target_drive == "C:" else floppy_disk_label)
	print_line(target_drive + "\\")

	_print_tree(fs_to_use, target_drive + "\\", "")
	print_line("")


func _print_tree(fs: Dictionary, dir_key: String, prefix: String) -> void:
	"""Recursively print directory tree"""
	if not fs.has(dir_key) or fs[dir_key].type != "dir":
		return

	var contents = fs[dir_key].contents
	for i in range(contents.size()):
		var item = contents[i]
		var file_key = dir_key
		if not file_key.ends_with("\\"):
			file_key += "\\"
		file_key += item

		var is_last = (i == contents.size() - 1)
		var connector = "`---" if is_last else "+---"
		var new_prefix = prefix + ("    " if is_last else "|   ")

		if fs.has(file_key) and fs[file_key].type == "dir":
			print_line(prefix + connector + item)
			_print_tree(fs, file_key, new_prefix)


func _cmd_vol(_args: Array) -> void:
	var vol_label = volume_label if current_drive == "C:" else floppy_disk_label
	print_line("")
	print_line(" Volume in drive %s is %s" % [current_drive.trim_suffix(":"), vol_label])
	print_line("")


func _cmd_label(args: Array) -> void:
	if args.is_empty():
		print_line(" Volume in drive %s is %s" % [current_drive.trim_suffix(":"), volume_label if current_drive == "C:" else floppy_disk_label])
		print_line("")
		return

	var new_label = args[0].to_upper()
	if current_drive == "C:":
		volume_label = new_label
	else:
		floppy_disk_label = new_label
	print_line("")


func _cmd_chkdsk(_args: Array) -> void:
	print_line("")
	print_line("Volume SHADOW       created 03-15-87  12:00a")
	print_line("")
	print_line("  21,309,440 bytes total disk space")
	print_line("      73,728 bytes in 3 hidden files")
	print_line("      24,576 bytes in 8 directories")
	print_line("   4,194,304 bytes in 42 user files")
	print_line("  17,016,832 bytes available on disk")
	print_line("")
	print_line("     655,360 bytes total memory")
	print_line("     524,288 bytes free")
	print_line("")


func _cmd_format(args: Array) -> void:
	if args.is_empty():
		print_line("Required parameter missing")
		print_line("Usage: FORMAT drive:")
		print_line("")
		return

	var drive = args[0].to_upper()
	if drive == "C:" or drive == "C":
		print_line("")
		print_line("WARNING: ALL DATA ON NON-REMOVABLE DISK")
		print_line("DRIVE C: WILL BE LOST!")
		print_line("Proceed with Format (Y/N)?")
		print_line("")
		print_line("Format terminated.")
		print_line("")
	elif drive == "A:" or drive == "A":
		if not floppy_disk_inserted:
			print_line("Not ready reading drive A")
		else:
			print_line("Format not available in this version")
		print_line("")
	else:
		print_line("Invalid drive specification")
		print_line("")


# CRT curvature state
var _crt_curvature_enabled: bool = false
const _CRT_CURVATURE_VALUE: float = 0.1

func _cmd_crt(_args: Array) -> void:
	"""Toggle CRT screen curvature effect"""
	_crt_curvature_enabled = not _crt_curvature_enabled
	var curvature_value = _CRT_CURVATURE_VALUE if _crt_curvature_enabled else 0.0

	# Get the terminal view's shader material
	var terminal_view = get_parent().get_parent()  # SubViewport -> TerminalView
	if terminal_view and terminal_view.material:
		terminal_view.material.set_shader_parameter("curvature", curvature_value)
		if _crt_curvature_enabled:
			print_line("CRT curvature: ON")
		else:
			print_line("CRT curvature: OFF")
	else:
		print_line("Error: Could not access CRT shader")
	print_line("")


func _cmd_edit(args: Array) -> void:
	"""Launch the full-screen text editor"""
	var scene = load("res://scenes/programs/editor.tscn")
	if scene:
		_start_program(scene, args)
	else:
		print_line("Error: Editor not found")
		print_line("")


func _cmd_version(args: Array) -> void:
	"""Show file version history or restore a previous version"""
	if args.is_empty():
		print_line("Usage: VERSION <filename>")
		print_line("       VERSION <filename> RESTORE <n>")
		print_line("")
		print_line("Shows version history for a file or restores")
		print_line("a previous version.")
		print_line("")
		return

	if not OnlineManager.is_online or not OnlineManager.is_registered:
		print_line("Error: Must be online to access version history")
		print_line("")
		return

	var filename = args[0].to_upper()
	var file_key = _get_full_path(filename)

	# Check for RESTORE subcommand
	if args.size() >= 3 and args[1].to_upper() == "RESTORE":
		var version_num = int(args[2])
		if version_num < 1 or version_num > 5:
			print_line("Invalid version number (1-5)")
			print_line("")
			return

		print_line("Restoring %s to version %d..." % [filename, version_num])
		OnlineManager.restore_file_version(file_key, version_num)
		# Response handled by _on_version_restored signal
		return

	# Request version history
	print_line("Fetching version history for %s..." % filename)
	_pending_version_path = file_key
	OnlineManager.get_file_versions(file_key)
	# Response handled by _on_versions_received signal - prompt shown there
