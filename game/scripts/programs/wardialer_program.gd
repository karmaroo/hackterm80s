extends Node
class_name WarDialerProgram
## War Dialer Terminal Program - Interactive interface for the war dialer

var terminal: Terminal
var war_dialer: WarDialer
var is_running: bool = false
var awaiting_input: String = ""  # What input we're waiting for: "menu", "area", "prefix", "start", "end"

# Scan parameters
var scan_area_code: String = "555"
var scan_prefix: String = "01"
var scan_start: int = 0
var scan_end: int = 99

# Current scan log file
var current_log_file: String = ""

# AI Host support
var ai_host: Node = null
var is_ai_connection: bool = false
var force_next_ai_host: bool = false  # Debug: press '.' during scan to force AI host
const AIHostScript = preload("res://scripts/ai_host.gd")


func _ready() -> void:
	name = "WarDialer"
	
	# Create war dialer instance
	war_dialer = WarDialer.new()
	add_child(war_dialer)
	
	# Connect signals
	war_dialer.scan_started.connect(_on_scan_started)
	war_dialer.number_dialing.connect(_on_number_dialing)
	war_dialer.number_result.connect(_on_number_result)
	war_dialer.scan_complete.connect(_on_scan_complete)
	war_dialer.scan_stopped.connect(_on_scan_stopped)


func start() -> void:
	is_running = true
	_show_banner()
	_show_menu()


func stop() -> void:
	is_running = false
	if war_dialer:
		war_dialer.stop_scan()


func handle_input(input: String) -> void:
	if not is_running:
		return
	
	var cmd = input.strip_edges().to_upper()
	
	match awaiting_input:
		"menu":
			_handle_menu_input(cmd)
		"area":
			_handle_area_input(input.strip_edges())
		"prefix":
			_handle_prefix_input(input.strip_edges())
		"start":
			_handle_start_input(input.strip_edges())
		"end":
			_handle_end_input(input.strip_edges())
		"scanning":
			_handle_scanning_input(cmd)


func _show_banner() -> void:
	terminal.print_line("")
	terminal.print_line("=" .repeat(50))
	terminal.print_line("    ██╗    ██╗ █████╗ ██████╗ ")
	terminal.print_line("    ██║    ██║██╔══██╗██╔══██╗")
	terminal.print_line("    ██║ █╗ ██║███████║██████╔╝")
	terminal.print_line("    ██║███╗██║██╔══██║██╔══██╗")
	terminal.print_line("    ╚███╔███╔╝██║  ██║██║  ██║")
	terminal.print_line("     ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝")
	terminal.print_line("        D I A L E R  v2.1")
	terminal.print_line("=" .repeat(50))
	terminal.print_line("   Automatic Modem/Computer Scanner")
	terminal.print_line("   (C) 1987 Shadow Systems Inc.")
	terminal.print_line("=" .repeat(50))
	terminal.print_line("")


func _show_menu() -> void:
	terminal.print_line("CURRENT SCAN RANGE: %s-%s-%02d to %s-%s-%02d" % [
		scan_area_code, scan_prefix, scan_start,
		scan_area_code, scan_prefix, scan_end
	])
	terminal.print_line("")
	terminal.print_line("OPTIONS:")
	terminal.print_line("  [1] START SCAN")
	terminal.print_line("  [2] SET AREA CODE    (Current: %s)" % scan_area_code)
	terminal.print_line("  [3] SET PREFIX       (Current: %s)" % scan_prefix)
	terminal.print_line("  [4] SET START NUMBER (Current: %02d)" % scan_start)
	terminal.print_line("  [5] SET END NUMBER   (Current: %02d)" % scan_end)
	terminal.print_line("  [6] VIEW RESULTS")
	terminal.print_line("  [Q] QUIT PROGRAM")
	terminal.print_line("")
	terminal.print_text("SELECT OPTION: ")
	awaiting_input = "menu"


func _handle_menu_input(cmd: String) -> void:
	terminal.print_line("")
	
	match cmd:
		"1":
			_start_scan()
		"2":
			terminal.print_text("ENTER AREA CODE: ")
			awaiting_input = "area"
		"3":
			terminal.print_text("ENTER PREFIX: ")
			awaiting_input = "prefix"
		"4":
			terminal.print_text("ENTER START NUMBER (00-99): ")
			awaiting_input = "start"
		"5":
			terminal.print_text("ENTER END NUMBER (00-99): ")
			awaiting_input = "end"
		"6":
			_show_results()
			_show_menu()
		"Q", "QUIT", "EXIT":
			terminal.print_line("EXITING WAR DIALER...")
			terminal.stop_program()
		_:
			terminal.print_line("INVALID OPTION.")
			_show_menu()


func _handle_area_input(input: String) -> void:
	if input.length() == 3 and input.is_valid_int():
		scan_area_code = input
		terminal.print_line("AREA CODE SET TO: %s" % scan_area_code)
	else:
		terminal.print_line("INVALID AREA CODE. MUST BE 3 DIGITS.")
	terminal.print_line("")
	_show_menu()


func _handle_prefix_input(input: String) -> void:
	if input.length() >= 2 and input.length() <= 3 and input.is_valid_int():
		scan_prefix = input
		terminal.print_line("PREFIX SET TO: %s" % scan_prefix)
	else:
		terminal.print_line("INVALID PREFIX. MUST BE 2-3 DIGITS.")
	terminal.print_line("")
	_show_menu()


func _handle_start_input(input: String) -> void:
	if input.is_valid_int():
		var num = int(input)
		if num >= 0 and num <= 99:
			scan_start = num
			terminal.print_line("START NUMBER SET TO: %02d" % scan_start)
		else:
			terminal.print_line("INVALID NUMBER. MUST BE 00-99.")
	else:
		terminal.print_line("INVALID INPUT.")
	terminal.print_line("")
	_show_menu()


func _handle_end_input(input: String) -> void:
	if input.is_valid_int():
		var num = int(input)
		if num >= 0 and num <= 99:
			scan_end = num
			terminal.print_line("END NUMBER SET TO: %02d" % scan_end)
		else:
			terminal.print_line("INVALID NUMBER. MUST BE 00-99.")
	else:
		terminal.print_line("INVALID INPUT.")
	terminal.print_line("")
	_show_menu()


func _handle_scanning_input(cmd: String) -> void:
	if cmd == "S" or cmd == "STOP":
		war_dialer.stop_scan()
	elif cmd == "P" or cmd == "PAUSE":
		war_dialer.toggle_pause()
		if war_dialer.is_paused:
			terminal.print_line("*** SCAN PAUSED ***")
		else:
			terminal.print_line("*** SCAN RESUMED ***")
	elif cmd == ".":
		# Force next modem to be AI host (hidden feature)
		if SettingsManager.has_openai_key():
			force_next_ai_host = true
			war_dialer.force_next_modem = true
			terminal.print_line("*** AI HOST QUEUED ***")


func _start_scan() -> void:
	if scan_start > scan_end:
		terminal.print_line("ERROR: START NUMBER MUST BE <= END NUMBER")
		terminal.print_line("")
		_show_menu()
		return
	
	# Create or get log file for this scan range
	current_log_file = "SCAN_%s%s.LOG" % [scan_area_code, scan_prefix]
	GameState.create_scan_log(current_log_file, scan_area_code, scan_prefix, scan_start, scan_end)
	
	terminal.print_line("INITIALIZING SCAN...")
	terminal.print_line("PRESS [S] TO STOP, [P] TO PAUSE")
	if SettingsManager.has_openai_key():
		terminal.print_line("PRESS [.] TO FORCE AI HOST ON NEXT MODEM")
	terminal.print_line("-" .repeat(50))
	awaiting_input = "scanning"
	
	war_dialer.start_scan(scan_area_code, scan_prefix, scan_start, scan_end)


func _on_scan_started(start_num: String, end_num: String) -> void:
	terminal.print_line("SCANNING: %s to %s" % [start_num, end_num])
	terminal.print_line("")


func _on_number_dialing(number: String) -> void:
	terminal.print_text("DIALING %s... " % number)


func _on_number_result(number: String, result: String) -> void:
	var result_str = ""
	match result:
		"MODEM":
			result_str = "[MODEM DETECTED!] ***"
			# Add modem to discovered modems log
			var system_id = ""
			if force_next_ai_host:
				system_id = "ai_host"
				force_next_ai_host = false
			GameState.add_modem_to_log(current_log_file, number, system_id)
		"FAX":
			result_str = "[FAX]"
		"VOICE":
			result_str = "[VOICE]"
		"BUSY":
			result_str = "[BUSY]"
		"NO_ANSWER":
			result_str = "[NO ANSWER]"
	
	terminal.print_line(result_str)


func _on_scan_complete(results: Dictionary) -> void:
	terminal.print_line("")
	terminal.print_line("=" .repeat(50))
	terminal.print_line("SCAN COMPLETE!")
	terminal.print_line("=" .repeat(50))
	_print_stats()
	terminal.print_line("")
	_show_menu()


func _on_scan_stopped() -> void:
	terminal.print_line("")
	terminal.print_line("*** SCAN STOPPED BY USER ***")
	_print_stats()
	terminal.print_line("")
	_show_menu()


func _print_stats() -> void:
	var stats = war_dialer.get_stats()
	terminal.print_line("SCAN STATISTICS:")
	terminal.print_line("  Total Scanned: %d" % stats["total"])
	terminal.print_line("  Modems Found:  %d" % stats["modems"])
	terminal.print_line("  Voice Lines:   %d" % stats["voice"])
	terminal.print_line("  Fax Machines:  %d" % stats["fax"])
	terminal.print_line("  Busy Signals:  %d" % stats["busy"])
	terminal.print_line("  No Answer:     %d" % stats["no_answer"])


func _show_results() -> void:
	var modems = war_dialer.scan_results["modems"]
	
	terminal.print_line("")
	terminal.print_line("DISCOVERED MODEMS:")
	terminal.print_line("-" .repeat(30))
	
	if modems.is_empty():
		terminal.print_line("  (No modems found yet)")
	else:
		for number in modems:
			terminal.print_line("  %s" % number)
	
	terminal.print_line("-" .repeat(30))
	terminal.print_line("")
