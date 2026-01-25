extends Node
class_name BBSDialer
## BBS Dialer - Full-featured BBS client with registration, messages, and file downloads

var terminal: Terminal

enum State {
	PHONEBOOK,
	ADD_ENTRY,
	DIALING,
	BBS_LOGIN,
	BBS_REGISTER,
	BBS_MAIN,
	BBS_MESSAGES,
	BBS_THREAD,
	BBS_FILES,
	BBS_DOWNLOAD,
	BBS_POSTING,
	BBS_OFFLINE
}

var state: State = State.PHONEBOOK

# Default BBS list
const DEFAULT_BBS_LIST = [
	{"name": "THE UNDERGROUND", "number": "555-0142", "description": "Elite hacking BBS"},
	{"name": "SILICON DREAMS", "number": "555-0199", "description": "General purpose BBS"},
	{"name": "PIRATE'S COVE", "number": "555-0167", "description": "Warez trading"},
]

# Phonebook
var phonebook: Array = []
var current_bbs: Dictionary = {}
var connected_system: Dictionary = {}

# BBS Session
var bbs_username: String = ""
var bbs_access_level: int = 0  # 0=guest, 1=user, 2=validated, 3=elite
var current_board: String = ""
var current_thread: int = -1

# Registration flow
var reg_step: int = 0
var reg_data: Dictionary = {}

# Add entry flow
var add_entry_step: int = 0
var new_entry: Dictionary = {}

# Login flow
var login_step: int = 0
var login_handle: String = ""

# Message viewing
var message_index: int = 0

# File section
var current_file_section: String = ""

signal program_exit


func _ready() -> void:
	pass


func start() -> void:
	state = State.PHONEBOOK
	_load_phonebook()
	_show_banner()
	_show_phonebook()


func stop() -> void:
	state = State.PHONEBOOK
	bbs_username = ""
	bbs_access_level = 0


func handle_input(input: String) -> void:
	match state:
		State.PHONEBOOK:
			_handle_phonebook_input(input.strip_edges().to_upper())
		State.ADD_ENTRY:
			_handle_add_input(input)
		State.DIALING:
			_handle_dialing_input(input.strip_edges().to_upper())
		State.BBS_OFFLINE:
			_handle_offline_input(input.strip_edges().to_upper())
		State.BBS_LOGIN:
			_handle_login_input(input)
		State.BBS_REGISTER:
			_handle_register_input(input)
		State.BBS_MAIN:
			_handle_main_menu_input(input.strip_edges().to_upper())
		State.BBS_MESSAGES:
			_handle_messages_input(input.strip_edges().to_upper())
		State.BBS_THREAD:
			_handle_thread_input(input.strip_edges().to_upper())
		State.BBS_FILES:
			_handle_files_input(input.strip_edges().to_upper())


# ============================================================
# PHONEBOOK MANAGEMENT
# ============================================================

func _load_phonebook() -> void:
	if GameState.dynamic_files.has("PHONEBK.DAT"):
		var data = GameState.dynamic_files["PHONEBK.DAT"]
		if data.has("bbs_entries"):
			phonebook = data.bbs_entries.duplicate(true)
			return
	phonebook = DEFAULT_BBS_LIST.duplicate(true)
	_save_phonebook()


func _save_phonebook() -> void:
	if not GameState.dynamic_files.has("PHONEBK.DAT"):
		GameState.create_file("PHONEBK.DAT", "; BBS Phonebook\n", "phonebook")
	GameState.dynamic_files["PHONEBK.DAT"].bbs_entries = phonebook.duplicate(true)


func _show_banner() -> void:
	terminal.print_line("")
	terminal.print_line("╔════════════════════════════════════════════════════════╗")
	terminal.print_line("║              B B S   D I A L E R   v1.0                 ║")
	terminal.print_line("║           Bulletin Board System Connector              ║")
	terminal.print_line("╚════════════════════════════════════════════════════════╝")
	terminal.print_line("")


func _show_phonebook() -> void:
	terminal.print_line("PHONEBOOK: %d entries" % phonebook.size())
	terminal.print_line("-" .repeat(50))
	terminal.print_line("")
	
	if phonebook.is_empty():
		terminal.print_line("  (No BBS entries)")
	else:
		var idx = 1
		for entry in phonebook:
			terminal.print_line("  %d. %-20s %s" % [idx, entry.name, entry.number])
			idx += 1
	terminal.print_line("")
	terminal.print_line("Commands: [#] Dial | ADD | DEL # | QUIT")
	terminal.print_line("")
	terminal.request_input("[BBSDIAL]> ")


func _handle_phonebook_input(cmd: String) -> void:
	if cmd == "QUIT" or cmd == "EXIT" or cmd == "Q":
		terminal.print_line("")
		terminal.print_line("Returning to DOS...")
		terminal.stop_program()
		return
	
	if cmd == "ADD":
		state = State.ADD_ENTRY
		add_entry_step = 0
		new_entry = {}
		terminal.print_line("")
		terminal.print_line("Enter BBS name (or CANCEL):")
		terminal.request_input("> ")
		return
	
	if cmd.begins_with("DEL "):
		var num_str = cmd.substr(4).strip_edges()
		if num_str.is_valid_int():
			var idx = num_str.to_int() - 1
			if idx >= 0 and idx < phonebook.size():
				var removed = phonebook[idx]
				phonebook.remove_at(idx)
				_save_phonebook()
				terminal.print_line("Deleted: %s" % removed.name)
				terminal.print_line("")
				_show_phonebook()
				return
		terminal.print_line("Invalid entry.")
		terminal.request_input("[BBSDIAL]> ")
		return
	
	if cmd.is_valid_int():
		var idx = cmd.to_int() - 1
		if idx >= 0 and idx < phonebook.size():
			_dial_bbs(phonebook[idx])
			return
	
	terminal.print_line("Unknown command.")
	terminal.request_input("[BBSDIAL]> ")


func _handle_add_input(input: String) -> void:
	var text = input.strip_edges()
	
	if text.to_upper() == "CANCEL":
		state = State.PHONEBOOK
		terminal.print_line("Cancelled.")
		terminal.print_line("")
		_show_phonebook()
		return
	
	match add_entry_step:
		0:
			if text.is_empty():
				terminal.print_line("Name required.")
				terminal.request_input("> ")
				return
			new_entry.name = text.to_upper().substr(0, 20)
			add_entry_step = 1
			terminal.print_line("Enter phone number:")
			terminal.request_input("> ")
		1:
			if text.length() < 7:
				terminal.print_line("Invalid number.")
				terminal.request_input("> ")
				return
			new_entry.number = text
			new_entry.description = ""
			phonebook.append(new_entry)
			_save_phonebook()
			terminal.print_line("Added: %s" % new_entry.name)
			terminal.print_line("")
			state = State.PHONEBOOK
			_show_phonebook()


# ============================================================
# DIALING AND CONNECTION
# ============================================================

func _dial_bbs(bbs: Dictionary) -> void:
	current_bbs = bbs
	state = State.DIALING
	bbs_username = ""
	bbs_access_level = 0
	
	terminal.print_line("")
	terminal.print_line("Dialing %s..." % bbs.number)
	
	GameState.modem_dialing_started.emit()
	await get_tree().create_timer(1.5).timeout
	
	terminal.print_line("RINGING...")
	await get_tree().create_timer(1.5).timeout
	
	# Check for discovered modem with system
	var modem_data = GameState.get_modem_data(bbs.number)
	if not modem_data.is_empty():
		var system_id = modem_data.get("system_id", "")
		if system_id != "" and system_id.begins_with("bbs_"):
			var SystemTemplates = load("res://scripts/system_templates.gd")
			connected_system = SystemTemplates.get_system_by_id(system_id)
			if not connected_system.is_empty():
				GameState.modem_connected.emit()
				GameState.mark_modem_connected(bbs.number)
				_show_bbs_welcome()
				return
	
	# Generic offline BBS
	GameState.modem_connected.emit()
	terminal.print_line("")
	terminal.print_line("CONNECT 2400")
	terminal.print_line("")
	terminal.print_line("*** %s ***" % bbs.name)
	terminal.print_line("")
	terminal.print_line("This BBS is currently offline.")
	terminal.print_line("Try discovering active systems with a WarDialer!")
	terminal.print_line("")
	terminal.print_line("Type HANGUP to disconnect.")
	state = State.BBS_OFFLINE
	terminal.request_input("> ")


func _handle_dialing_input(cmd: String) -> void:
	if cmd == "HANGUP" or cmd == "CANCEL":
		_disconnect()


func _handle_offline_input(cmd: String) -> void:
	if cmd == "HANGUP" or cmd == "BYE" or cmd == "QUIT":
		_disconnect()
	else:
		terminal.print_line("Type HANGUP to disconnect.")
		terminal.request_input("> ")


func _disconnect() -> void:
	GameState.modem_hangup.emit()
	terminal.print_line("")
	await terminal.print_slow("\nNO CARRIER\n\n", 2400)
	
	await get_tree().create_timer(1.5).timeout
	
	state = State.PHONEBOOK
	current_bbs = {}
	connected_system = {}
	bbs_username = ""
	bbs_access_level = 0
	
	terminal.clear_screen()
	_show_banner()
	_show_phonebook()


# ============================================================
# BBS LOGIN SYSTEM
# ============================================================

func _show_bbs_welcome() -> void:
	state = State.BBS_LOGIN
	login_step = 0
	
	terminal.print_line("")
	terminal.print_line("CONNECT 2400")
	terminal.print_line("")
	
	# Show BBS banner
	var banner = connected_system.get("banner", "")
	if banner != "":
		terminal.print_line(banner)
	else:
		terminal.print_line("=" .repeat(50))
		terminal.print_line("  Welcome to %s" % connected_system.get("organization", current_bbs.name))
		terminal.print_line("=" .repeat(50))
	
	terminal.print_line("")
	terminal.print_line("Enter your handle, or NEW to register:")
	terminal.request_input("Handle: ")


func _handle_login_input(input: String) -> void:
	var text = input.strip_edges()
	var cmd = text.to_upper()
	
	if cmd == "HANGUP" or cmd == "BYE" or cmd == "QUIT":
		_disconnect()
		return
	
	match login_step:
		0:  # Handle entry
			if cmd == "NEW":
				_start_registration()
				return
			if cmd == "GUEST" and connected_system.get("guest_access", false):
				bbs_username = "GUEST"
				bbs_access_level = 0
				terminal.print_line("")
				terminal.print_line("Logged in as GUEST (limited access)")
				terminal.print_line("")
				_show_bbs_main_menu()
				return
			if text.is_empty():
				terminal.request_input("Handle: ")
				return
			login_handle = text
			var accounts = _get_bbs_accounts()
			if accounts.has(login_handle.to_upper()):
				login_step = 1
				terminal.request_input("Password: ")
			else:
				terminal.print_line("")
				terminal.print_line("Unknown user. Type NEW to register.")
				terminal.print_line("")
				terminal.request_input("Handle: ")
		
		1:  # Password
			var accounts = _get_bbs_accounts()
			var account = accounts.get(login_handle.to_upper(), {})
			if account.get("password", "") == text:
				bbs_username = login_handle
				bbs_access_level = account.get("access_level", 1)
				login_step = 0
				terminal.print_line("")
				terminal.print_line("Welcome back, %s!" % bbs_username)
				terminal.print_line("Access Level: %d" % bbs_access_level)
				terminal.print_line("")
				_show_bbs_main_menu()
			else:
				terminal.print_line("")
				terminal.print_line("Invalid password.")
				terminal.print_line("")
				login_step = 0
				terminal.request_input("Handle: ")


func _start_registration() -> void:
	state = State.BBS_REGISTER
	reg_step = 0
	reg_data = {}
	terminal.print_line("")
	terminal.print_line("=== NEW USER REGISTRATION ===")
	terminal.print_line("")
	terminal.print_line("Choose a handle (username):")
	terminal.request_input("> ")


func _handle_register_input(input: String) -> void:
	var text = input.strip_edges()
	
	if text.to_upper() == "CANCEL":
		state = State.BBS_LOGIN
		login_step = 0
		terminal.print_line("")
		terminal.print_line("Registration cancelled.")
		terminal.print_line("")
		terminal.request_input("Handle: ")
		return
	
	match reg_step:
		0:  # Handle
			if text.length() < 3:
				terminal.print_line("Handle must be at least 3 characters.")
				terminal.request_input("> ")
				return
			var accounts = _get_bbs_accounts()
			if accounts.has(text.to_upper()):
				terminal.print_line("That handle is taken.")
				terminal.request_input("> ")
				return
			reg_data.handle = text
			reg_step = 1
			terminal.print_line("Choose a password:")
			terminal.request_input("> ")
		
		1:  # Password
			if text.length() < 4:
				terminal.print_line("Password must be at least 4 characters.")
				terminal.request_input("> ")
				return
			reg_data.password = text
			reg_step = 2
			terminal.print_line("Enter your location (city/state):")
			terminal.request_input("> ")
		
		2:  # Location
			reg_data.location = text if not text.is_empty() else "Unknown"
			_create_bbs_account(reg_data.handle, reg_data.password, reg_data.location)
			terminal.print_line("")
			terminal.print_line("████████████████████████████████████████")
			terminal.print_line("  Registration Complete!")
			terminal.print_line("  Handle: %s" % reg_data.handle)
			terminal.print_line("  Access Level: 1 (New User)")
			terminal.print_line("████████████████████████████████████████")
			terminal.print_line("")
			bbs_username = reg_data.handle
			bbs_access_level = 1
			state = State.BBS_MAIN
			_show_bbs_main_menu()


func _get_bbs_accounts() -> Dictionary:
	var bbs_id = connected_system.get("id", current_bbs.number)
	var key = "BBS_ACCOUNTS_" + bbs_id
	if GameState.dynamic_files.has(key):
		return GameState.dynamic_files[key].get("accounts", {})
	return {}


func _create_bbs_account(handle: String, password: String, location: String) -> void:
	var bbs_id = connected_system.get("id", current_bbs.number)
	var key = "BBS_ACCOUNTS_" + bbs_id
	
	if not GameState.dynamic_files.has(key):
		GameState.dynamic_files[key] = {"accounts": {}, "content": "", "type": "bbs_data"}
	
	GameState.dynamic_files[key].accounts[handle.to_upper()] = {
		"password": password,
		"access_level": 1,
		"location": location,
		"registered": GameState.get_dos_date()
	}


# ============================================================
# BBS MAIN MENU
# ============================================================

func _show_bbs_main_menu() -> void:
	state = State.BBS_MAIN
	var bbs_name = connected_system.get("organization", current_bbs.name)
	
	terminal.print_line("")
	terminal.print_line("╔" + "═".repeat(46) + "╗")
	terminal.print_line("║  %-42s  ║" % bbs_name.substr(0, 42).to_upper())
	terminal.print_line("╚" + "═".repeat(46) + "╝")
	terminal.print_line("")
	terminal.print_line("  [M] Message Boards")
	terminal.print_line("  [F] File Section")
	terminal.print_line("  [W] Who's Online")
	terminal.print_line("  [G] Goodbye (Logoff)")
	terminal.print_line("")
	terminal.request_input("[MAIN]> ")


func _handle_main_menu_input(cmd: String) -> void:
	match cmd:
		"M", "MESSAGES", "MSG":
			_show_message_boards()
		"F", "FILES", "FILE":
			_show_file_section()
		"W", "WHO":
			_show_whos_online()
		"G", "GOODBYE", "BYE", "QUIT", "LOGOFF", "HANGUP":
			_disconnect()
		_:
			terminal.print_line("Unknown command.")
			terminal.request_input("[MAIN]> ")


func _show_whos_online() -> void:
	terminal.print_line("")
	terminal.print_line("=== WHO'S ONLINE ===")
	terminal.print_line("")
	terminal.print_line("  Node 1: %s" % bbs_username)
	terminal.print_line("  Node 2: (idle)")
	terminal.print_line("  Node 3: (idle)")
	terminal.print_line("")
	terminal.request_input("[MAIN]> ")


# ============================================================
# MESSAGE BOARDS
# ============================================================

const MESSAGE_BOARDS = {
	"general": {
		"name": "General Discussion",
		"threads": [
			{"title": "Welcome to the board!", "author": "SYSOP", "date": "03/12/87", "replies": 3,
			 "messages": [
				{"author": "SYSOP", "date": "03/12/87", "text": "Welcome to the BBS! Please read the rules and enjoy your stay."},
				{"author": "DARKSTAR", "date": "03/13/87", "text": "Thanks for setting this up! Great board."},
				{"author": "PHANTOM", "date": "03/14/87", "text": "Been looking for a good local BBS. This rocks!"},
			]},
		]
	},
	"hacking": {
		"name": "Hacking & Phreaking",
		"access_level": 2,
		"threads": [
			{"title": "War Dialer tips", "author": "PHOENIX", "date": "03/10/87", "replies": 2,
			 "messages": [
				{"author": "PHOENIX", "date": "03/10/87", "text": "Pro tip: scan during business hours for corporate systems."},
				{"author": "MENTOR", "date": "03/11/87", "text": "Also check the 1-800 numbers. Free calling AND interesting systems."},
			]},
		]
	},
}


func _show_message_boards() -> void:
	state = State.BBS_MESSAGES
	
	terminal.print_line("")
	terminal.print_line("=== MESSAGE BOARDS ===")
	terminal.print_line("")
	
	var idx = 1
	for board_id in MESSAGE_BOARDS:
		var board = MESSAGE_BOARDS[board_id]
		var required_level = board.get("access_level", 0)
		var locked = " [LOCKED]" if bbs_access_level < required_level else ""
		var thread_count = board.threads.size()
		terminal.print_line("  %d. %-20s (%d threads)%s" % [idx, board.name, thread_count, locked])
		idx += 1
	
	terminal.print_line("")
	terminal.print_line("Enter # to read, or Q to return:")
	terminal.request_input("[MSG]> ")


func _handle_messages_input(cmd: String) -> void:
	if cmd == "Q" or cmd == "QUIT" or cmd == "BACK":
		_show_bbs_main_menu()
		return
	
	if cmd.is_valid_int():
		var idx = cmd.to_int() - 1
		var boards = MESSAGE_BOARDS.keys()
		if idx >= 0 and idx < boards.size():
			var board_id = boards[idx]
			var board = MESSAGE_BOARDS[board_id]
			var required_level = board.get("access_level", 0)
			if bbs_access_level < required_level:
				terminal.print_line("")
				terminal.print_line("Access denied. Need level %d." % required_level)
				terminal.print_line("")
				terminal.request_input("[MSG]> ")
				return
			current_board = board_id
			_show_thread_list(board)
			return
	
	terminal.print_line("Invalid selection.")
	terminal.request_input("[MSG]> ")


func _show_thread_list(board: Dictionary) -> void:
	state = State.BBS_THREAD
	terminal.print_line("")
	terminal.print_line("=== %s ===" % board.name.to_upper())
	terminal.print_line("")
	
	var idx = 1
	for thread in board.threads:
		terminal.print_line("  %d. %s" % [idx, thread.title])
		terminal.print_line("     By: %-12s  Replies: %d" % [thread.author, thread.replies])
		idx += 1
	
	terminal.print_line("")
	terminal.print_line("Enter # to read, or Q to return:")
	terminal.request_input("[%s]> " % current_board.to_upper().substr(0, 6))


func _handle_thread_input(cmd: String) -> void:
	if cmd == "Q" or cmd == "QUIT" or cmd == "BACK":
		current_thread = -1
		_show_message_boards()
		return
	
	if cmd == "N" or cmd == "NEXT":
		if current_thread >= 0:
			_show_next_message()
			return
	
	if cmd.is_valid_int():
		var idx = cmd.to_int() - 1
		var board = MESSAGE_BOARDS.get(current_board, {})
		if idx >= 0 and idx < board.threads.size():
			current_thread = idx
			message_index = 0
			_show_thread_messages(board.threads[idx])
			return
	
	terminal.print_line("Invalid selection.")
	terminal.request_input("[%s]> " % current_board.to_upper().substr(0, 6))


func _show_thread_messages(thread: Dictionary) -> void:
	terminal.print_line("")
	terminal.print_line("═" .repeat(50))
	terminal.print_line("  %s" % thread.title)
	terminal.print_line("═" .repeat(50))
	
	_display_message(thread.messages[0])
	
	if thread.messages.size() > 1:
		terminal.print_line("")
		terminal.print_line("[N]ext message, [Q]uit to list")
	else:
		terminal.print_line("")
		terminal.print_line("[Q]uit to list")
	terminal.request_input("> ")


func _display_message(msg: Dictionary) -> void:
	terminal.print_line("")
	terminal.print_line("From: %-15s  Date: %s" % [msg.author, msg.date])
	terminal.print_line("-" .repeat(50))
	terminal.print_line(msg.text)


func _show_next_message() -> void:
	var board = MESSAGE_BOARDS.get(current_board, {})
	if current_thread < 0 or current_thread >= board.threads.size():
		return
	
	var thread = board.threads[current_thread]
	message_index += 1
	
	if message_index >= thread.messages.size():
		terminal.print_line("")
		terminal.print_line("*** End of thread ***")
		terminal.print_line("")
		state = State.BBS_MESSAGES
		current_thread = -1
		_show_thread_list(board)
		return
	
	_display_message(thread.messages[message_index])
	
	if message_index < thread.messages.size() - 1:
		terminal.print_line("")
		terminal.print_line("[N]ext message, [Q]uit to list")
	else:
		terminal.print_line("")
		terminal.print_line("*** Last message *** [Q]uit to list")
	terminal.request_input("> ")


# ============================================================
# FILE SECTION
# ============================================================

const FILE_SECTIONS = {
	"utils": {
		"name": "Utilities",
		"files": [
			{"name": "PKZIP.EXE", "size": "23K", "desc": "File compression utility", "downloads": null},
		]
	},
	"hacking": {
		"name": "Hacking Tools",
		"access_level": 2,
		"files": [
			{"name": "WARDIAL.ZIP", "size": "34K", "desc": "WarDialer v1.0 - Phone scanner", "downloads": "wardialer"},
		]
	},
	"elite": {
		"name": "Elite Section",
		"access_level": 3,
		"files": [
			{"name": "WARDIAL2.ZIP", "size": "48K", "desc": "WarDialer v2.0 - Advanced scanner", "downloads": "wardialer_v2"},
		]
	}
}


func _show_file_section() -> void:
	state = State.BBS_FILES
	current_file_section = ""
	
	terminal.print_line("")
	terminal.print_line("=== FILE SECTIONS ===")
	terminal.print_line("")
	
	var idx = 1
	for section_id in FILE_SECTIONS:
		var section = FILE_SECTIONS[section_id]
		var required_level = section.get("access_level", 0)
		var locked = " [LEVEL %d REQUIRED]" % required_level if bbs_access_level < required_level else ""
		var file_count = section.files.size()
		terminal.print_line("  %d. %-15s (%d files)%s" % [idx, section.name, file_count, locked])
		idx += 1
	
	terminal.print_line("")
	terminal.print_line("Enter # to browse, or Q to return:")
	terminal.request_input("[FILES]> ")


func _handle_files_input(cmd: String) -> void:
	if cmd == "Q" or cmd == "QUIT" or cmd == "BACK":
		if current_file_section.is_empty():
			_show_bbs_main_menu()
		else:
			current_file_section = ""
			_show_file_section()
		return
	
	# If in a section, handle download commands
	if not current_file_section.is_empty():
		if cmd.begins_with("D ") or cmd.begins_with("DOWNLOAD "):
			var parts = cmd.split(" ", false)
			if parts.size() > 1:
				_download_file(parts[1])
				return
		
		if cmd.is_valid_int():
			var idx = cmd.to_int() - 1
			var section = FILE_SECTIONS.get(current_file_section, {})
			if idx >= 0 and idx < section.files.size():
				_download_file(section.files[idx].name)
				return
	
	# Section selection
	if cmd.is_valid_int():
		var idx = cmd.to_int() - 1
		var sections = FILE_SECTIONS.keys()
		if idx >= 0 and idx < sections.size():
			var section_id = sections[idx]
			var section = FILE_SECTIONS[section_id]
			var required_level = section.get("access_level", 0)
			if bbs_access_level < required_level:
				terminal.print_line("")
				terminal.print_line("Access denied. Need level %d." % required_level)
				terminal.print_line("")
				terminal.request_input("[FILES]> ")
				return
			current_file_section = section_id
			_show_file_list(section)
			return
	
	terminal.print_line("Invalid selection.")
	terminal.request_input("[FILES]> ")


func _show_file_list(section: Dictionary) -> void:
	terminal.print_line("")
	terminal.print_line("=== %s ===" % section.name.to_upper())
	terminal.print_line("")
	terminal.print_line("  #  FILENAME      SIZE   DESCRIPTION")
	terminal.print_line("  " + "-".repeat(45))
	
	var idx = 1
	for f in section.files:
		var owned = " [OWNED]" if f.downloads != null and GameState.has_disk(f.downloads) else ""
		terminal.print_line("  %d. %-12s %5s  %s%s" % [idx, f.name, f.size, f.desc, owned])
		idx += 1
	
	terminal.print_line("")
	terminal.print_line("Enter # to download, Q to go back:")
	terminal.request_input("[%s]> " % current_file_section.to_upper().substr(0, 6))


func _download_file(filename: String) -> void:
	var section = FILE_SECTIONS.get(current_file_section, {})
	var found_file = null
	
	for f in section.files:
		if f.name.to_upper().begins_with(filename.to_upper()):
			found_file = f
			break
	
	if found_file == null:
		terminal.print_line("File not found: %s" % filename)
		terminal.request_input("[%s]> " % current_file_section.to_upper().substr(0, 6))
		return
	
	if found_file.downloads == null:
		terminal.print_line("")
		terminal.print_line("Downloading %s..." % found_file.name)
		await get_tree().create_timer(1.0).timeout
		terminal.print_line("Download complete.")
		terminal.print_line("")
		terminal.request_input("[%s]> " % current_file_section.to_upper().substr(0, 6))
		return
	
	var disk_id = found_file.downloads
	
	if GameState.has_disk(disk_id):
		terminal.print_line("")
		terminal.print_line("You already have this in your floppy collection.")
		terminal.print_line("")
		terminal.request_input("[%s]> " % current_file_section.to_upper().substr(0, 6))
		return
	
	terminal.print_line("")
	terminal.print_line("Downloading %s to floppy disk..." % found_file.name)
	terminal.print_line("")
	
	# Simulate download progress
	for i in range(10):
		await get_tree().create_timer(0.2).timeout
		var progress = (i + 1) * 10
		terminal.print_line("  [" + "█".repeat(i + 1) + "░".repeat(9 - i) + "] %d%%" % progress)
	
	if GameState.add_disk_to_inventory(disk_id):
		terminal.print_line("")
		terminal.print_line("████████████████████████████████████████")
		terminal.print_line("  DOWNLOAD COMPLETE!")
		terminal.print_line("")
		terminal.print_line("  Saved to your floppy disk collection!")
		terminal.print_line("  Insert the disk to use it.")
		terminal.print_line("████████████████████████████████████████")
	else:
		terminal.print_line("Download failed.")
	
	terminal.print_line("")
	terminal.request_input("[%s]> " % current_file_section.to_upper().substr(0, 6))
