extends Node
class_name EditorProgram
## DOS-style full-screen text editor (like EDIT.COM)
## Curses-like interface with fixed header/footer and scrolling content area

var terminal: Terminal

# Editor state
var filename: String = ""
var filepath: String = ""
var lines: Array[String] = [""]
var cursor_row: int = 0
var cursor_col: int = 0
var scroll_offset: int = 0  # First visible line
var horizontal_offset: int = 0  # First visible column
var is_modified: bool = false
var insert_mode: bool = true  # true = insert, false = overwrite

# Dynamic display dimensions (calculated from terminal)
var screen_cols: int = 60
var screen_rows: int = 20
var content_rows: int = 17  # screen_rows - 3 (header, border, status)

# Box drawing characters (ncurses style)
const BOX_H: String = "─"      # Horizontal line U+2500
const BOX_V: String = "│"      # Vertical line U+2502
const BOX_TL: String = "┌"     # Top-left corner U+250C
const BOX_TR: String = "┐"     # Top-right corner U+2510
const BOX_BL: String = "└"     # Bottom-left corner U+2514
const BOX_BR: String = "┘"     # Bottom-right corner U+2518

# Cursor blink
var _blink_timer: float = 0.0
var _cursor_visible: bool = true

# UI state
var _showing_help: bool = false
var _find_mode: bool = false
var _find_input: String = ""
var _message: String = ""
var _message_timer: float = 0.0
var word_wrap: bool = true  # Enable word wrapping


func start(args: Array = []) -> void:
	# Calculate actual terminal dimensions
	_calculate_dimensions()

	# Hide terminal scrollbar for full-screen mode
	if terminal and terminal.output:
		var scrollbar = terminal.output.get_v_scroll_bar()
		if scrollbar:
			scrollbar.modulate.a = 0
		# Disable scroll following
		terminal.output.scroll_following = false

	if args.size() > 0:
		filename = args[0].to_upper()
		filepath = terminal._get_full_path(filename)
		_load_file()
	else:
		filename = "UNTITLED.TXT"
		filepath = ""
		lines = [""]

	_refresh_screen()


func stop() -> void:
	# Restore terminal scrollbar and scroll following
	if terminal and terminal.output:
		var scrollbar = terminal.output.get_v_scroll_bar()
		if scrollbar:
			scrollbar.modulate.a = 1
		terminal.output.scroll_following = true


func _calculate_dimensions() -> void:
	if not terminal or not terminal.output:
		return

	# Get the RichTextLabel's size
	var output_size = terminal.output.size

	# Get font metrics - assume monospace DOS font
	var font = terminal.output.get_theme_font("normal_font")
	var font_size = terminal.output.get_theme_font_size("normal_font_size")

	if font:
		# Get character width (use 'M' as reference for monospace)
		var char_width = font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var line_height = font.get_height(font_size)

		# Calculate available space (less conservative - use more screen)
		var available_width = output_size.x - 8
		var available_height = output_size.y - 4

		screen_cols = int(available_width / char_width) if char_width > 0 else 65
		screen_rows = int(available_height / line_height) if line_height > 0 else 22
	else:
		# Fallback: estimate based on typical DOS font at size 14
		screen_cols = int((output_size.x - 8) / 8)
		screen_rows = int((output_size.y - 4) / 16)

	# Clamp to reasonable values - allow more space
	screen_cols = clamp(screen_cols, 40, 90)
	screen_rows = clamp(screen_rows, 12, 25)

	# Content area: total rows minus header(2) and footer(2)
	content_rows = screen_rows - 4


func _process(delta: float) -> void:
	# Cursor blink
	_blink_timer += delta
	if _blink_timer >= 0.5:
		_blink_timer = 0.0
		_cursor_visible = not _cursor_visible
		_refresh_screen()

	# Clear message after 2 seconds
	if _message_timer > 0:
		_message_timer -= delta
		if _message_timer <= 0:
			_message = ""
			_refresh_screen()


func handle_input(text: String) -> void:
	pass  # We handle everything via handle_key and handle_char


func handle_key(keycode: int, shift: bool, ctrl: bool) -> bool:
	"""Handle special keys. Returns true if key was handled."""

	# Clear any message on keypress
	if not _message.is_empty():
		_message = ""
		_message_timer = 0

	if _showing_help:
		_showing_help = false
		_refresh_screen()
		return true

	if _find_mode:
		return _handle_find_key(keycode)

	# Function keys
	match keycode:
		KEY_F1:
			_show_help()
			return true
		KEY_F2:
			_save_file()
			return true
		KEY_F5:
			_start_find()
			return true
		KEY_F10, KEY_ESCAPE:
			_exit_editor()
			return true
		KEY_INSERT:
			insert_mode = not insert_mode
			_refresh_screen()
			return true

	# Navigation keys
	match keycode:
		KEY_UP:
			_move_cursor(-1, 0)
			return true
		KEY_DOWN:
			_move_cursor(1, 0)
			return true
		KEY_LEFT:
			_move_cursor(0, -1)
			return true
		KEY_RIGHT:
			_move_cursor(0, 1)
			return true
		KEY_HOME:
			if ctrl:
				cursor_row = 0
				cursor_col = 0
				scroll_offset = 0
				horizontal_offset = 0
			else:
				cursor_col = 0
			_ensure_cursor_visible()
			_refresh_screen()
			return true
		KEY_END:
			if ctrl:
				cursor_row = lines.size() - 1
				cursor_col = lines[cursor_row].length()
				_ensure_cursor_visible()
			else:
				cursor_col = lines[cursor_row].length()
			_ensure_cursor_visible()
			_refresh_screen()
			return true
		KEY_PAGEUP:
			cursor_row = max(0, cursor_row - content_rows)
			_ensure_cursor_visible()
			_refresh_screen()
			return true
		KEY_PAGEDOWN:
			cursor_row = min(lines.size() - 1, cursor_row + content_rows)
			_ensure_cursor_visible()
			_refresh_screen()
			return true

	# Editing keys
	match keycode:
		KEY_BACKSPACE:
			_handle_backspace()
			return true
		KEY_DELETE:
			_handle_delete()
			return true
		KEY_ENTER:
			_handle_enter()
			return true
		KEY_TAB:
			_insert_char("    ")
			return true

	return false


func handle_char(char_text: String) -> void:
	"""Handle printable character input."""
	if _showing_help:
		_showing_help = false
		_refresh_screen()
		return

	if _find_mode:
		_find_input += char_text
		_refresh_screen()
		return

	if char_text.length() > 0 and char_text.unicode_at(0) >= 32:
		_insert_char(char_text)


# ============ FILE OPERATIONS ============

func _load_file() -> void:
	var fs = terminal.filesystem if filepath.begins_with("C:") else terminal.floppy_filesystem

	if fs.has(filepath) and fs[filepath].type == "file":
		var content = fs[filepath].get("content", "")
		if content.is_empty():
			lines = [""]
		else:
			lines = Array(content.split("\n"), TYPE_STRING, "", null)
		is_modified = false
	else:
		lines = [""]
		is_modified = false


func _save_file() -> void:
	if filepath.is_empty():
		filepath = terminal._get_full_path(filename)

	if terminal._is_readonly(filepath) or terminal._is_system(filepath):
		_show_message("Access denied - File is protected")
		return

	var content = "\n".join(lines)
	var fs = terminal.filesystem if filepath.begins_with("C:") else terminal.floppy_filesystem

	if fs.has(filepath):
		fs[filepath]["content"] = content
	else:
		fs[filepath] = {
			"type": "file",
			"content": content,
			"attr": "A"
		}
		var parent = terminal._get_dos_dir(filepath)
		var fname = terminal._get_dos_filename(filepath)
		if fs.has(parent) and fs[parent].type == "dir":
			if fname not in fs[parent].contents:
				fs[parent].contents.append(fname)

	if terminal.current_drive == "C:" and OnlineManager.is_online and OnlineManager.is_registered:
		var metadata = terminal._build_file_metadata(filepath)
		OnlineManager.create_or_update_file(filepath, content, "file", "", metadata)

	terminal._notify_filesystem_change()
	is_modified = false
	_show_message("Saved: " + filename)


func _exit_editor() -> void:
	terminal.stop_program()


# ============ CURSOR MOVEMENT ============

func _move_cursor(row_delta: int, col_delta: int) -> void:
	cursor_row = clamp(cursor_row + row_delta, 0, lines.size() - 1)

	if col_delta != 0:
		cursor_col += col_delta
		if cursor_col < 0:
			if cursor_row > 0:
				cursor_row -= 1
				cursor_col = lines[cursor_row].length()
			else:
				cursor_col = 0
		elif cursor_col > lines[cursor_row].length():
			if cursor_row < lines.size() - 1:
				cursor_row += 1
				cursor_col = 0
			else:
				cursor_col = lines[cursor_row].length()
	else:
		cursor_col = min(cursor_col, lines[cursor_row].length())

	_ensure_cursor_visible()
	_refresh_screen()


func _ensure_cursor_visible() -> void:
	# Vertical scrolling
	if cursor_row < scroll_offset:
		scroll_offset = cursor_row
	elif cursor_row >= scroll_offset + content_rows:
		scroll_offset = cursor_row - content_rows + 1

	# Horizontal scrolling (no side borders)
	if cursor_col < horizontal_offset:
		horizontal_offset = cursor_col
	elif cursor_col >= horizontal_offset + screen_cols:
		horizontal_offset = cursor_col - screen_cols + 1


# ============ TEXT EDITING ============

func _insert_char(char_text: String) -> void:
	var line = lines[cursor_row]

	while cursor_col > line.length():
		line += " "

	if insert_mode:
		line = line.substr(0, cursor_col) + char_text + line.substr(cursor_col)
	else:
		if cursor_col < line.length():
			line = line.substr(0, cursor_col) + char_text + line.substr(cursor_col + char_text.length())
		else:
			line += char_text

	lines[cursor_row] = line
	cursor_col += char_text.length()
	is_modified = true
	_ensure_cursor_visible()
	_refresh_screen()


func _handle_backspace() -> void:
	if cursor_col > 0:
		var line = lines[cursor_row]
		lines[cursor_row] = line.substr(0, cursor_col - 1) + line.substr(cursor_col)
		cursor_col -= 1
		is_modified = true
	elif cursor_row > 0:
		cursor_col = lines[cursor_row - 1].length()
		lines[cursor_row - 1] += lines[cursor_row]
		lines.remove_at(cursor_row)
		cursor_row -= 1
		is_modified = true
	_ensure_cursor_visible()
	_refresh_screen()


func _handle_delete() -> void:
	var line = lines[cursor_row]
	if cursor_col < line.length():
		lines[cursor_row] = line.substr(0, cursor_col) + line.substr(cursor_col + 1)
		is_modified = true
	elif cursor_row < lines.size() - 1:
		lines[cursor_row] += lines[cursor_row + 1]
		lines.remove_at(cursor_row + 1)
		is_modified = true
	_refresh_screen()


func _handle_enter() -> void:
	var line = lines[cursor_row]
	var before = line.substr(0, cursor_col)
	var after = line.substr(cursor_col)

	lines[cursor_row] = before
	lines.insert(cursor_row + 1, after)
	cursor_row += 1
	cursor_col = 0
	is_modified = true
	_ensure_cursor_visible()
	_refresh_screen()


# ============ FIND ============

func _start_find() -> void:
	_find_mode = true
	_find_input = ""
	_refresh_screen()


func _handle_find_key(keycode: int) -> bool:
	match keycode:
		KEY_ESCAPE:
			_find_mode = false
			_find_input = ""
			_refresh_screen()
			return true
		KEY_ENTER:
			_execute_find()
			return true
		KEY_BACKSPACE:
			if _find_input.length() > 0:
				_find_input = _find_input.substr(0, _find_input.length() - 1)
				_refresh_screen()
			return true
	return false


func _execute_find() -> void:
	_find_mode = false
	if _find_input.is_empty():
		return

	var query = _find_input.to_upper()
	_find_input = ""

	for i in range(cursor_row, lines.size()):
		var start_col = cursor_col + 1 if i == cursor_row else 0
		var pos = lines[i].to_upper().find(query, start_col)
		if pos >= 0:
			cursor_row = i
			cursor_col = pos
			_ensure_cursor_visible()
			_refresh_screen()
			return

	for i in range(0, cursor_row + 1):
		var end_col = cursor_col if i == cursor_row else lines[i].length()
		var pos = lines[i].to_upper().substr(0, end_col).find(query)
		if pos >= 0:
			cursor_row = i
			cursor_col = pos
			_ensure_cursor_visible()
			_refresh_screen()
			return

	_show_message("Not found: " + query)


# ============ UI ============

func _show_help() -> void:
	_showing_help = true
	_refresh_screen()


func _show_message(msg: String) -> void:
	_message = msg
	_message_timer = 3.0
	_refresh_screen()


func _refresh_screen() -> void:
	if not terminal or not terminal.output:
		return

	terminal.output.clear()

	var screen_text: String
	if _showing_help:
		screen_text = _build_help_screen()
	else:
		screen_text = _build_editor_screen()

	terminal.output.add_text(screen_text)

	# Force scroll to top to show full-screen interface
	if terminal.output.get_v_scroll_bar():
		terminal.output.get_v_scroll_bar().value = 0


func _wrap_line(text: String, width: int) -> Array[String]:
	"""Wrap a line of text to fit within width."""
	if text.length() <= width:
		return [text]

	var wrapped: Array[String] = []
	var remaining = text

	while remaining.length() > width:
		# Try to find a space to break at
		var break_pos = width
		var space_pos = remaining.rfind(" ", width)
		if space_pos > 0 and space_pos > width / 2:
			break_pos = space_pos

		wrapped.append(remaining.substr(0, break_pos))
		remaining = remaining.substr(break_pos).strip_edges(true, false)

	if remaining.length() > 0:
		wrapped.append(remaining)

	return wrapped


func _get_display_lines() -> Array:
	"""Get wrapped display lines with metadata about source line."""
	var display: Array = []  # Each entry: {text: String, line_idx: int, wrap_idx: int}

	for line_idx in range(lines.size()):
		var line_text = lines[line_idx].replace("\t", "    ")

		if word_wrap and line_text.length() > screen_cols:
			var wrapped = _wrap_line(line_text, screen_cols)
			for wrap_idx in range(wrapped.size()):
				display.append({
					"text": wrapped[wrap_idx],
					"line_idx": line_idx,
					"wrap_idx": wrap_idx
				})
		else:
			display.append({
				"text": line_text,
				"line_idx": line_idx,
				"wrap_idx": 0
			})

	return display


func _get_cursor_display_pos(display_lines: Array) -> Dictionary:
	"""Find where the cursor should appear in display coordinates."""
	var display_row = 0
	var display_col = cursor_col

	for i in range(display_lines.size()):
		var entry = display_lines[i]
		if entry.line_idx == cursor_row:
			if word_wrap:
				# Calculate which wrapped line the cursor is on
				var col_offset = 0
				for j in range(i, display_lines.size()):
					var e = display_lines[j]
					if e.line_idx != cursor_row:
						break
					var line_len = e.text.length()
					if cursor_col <= col_offset + line_len or e.wrap_idx == 0 and j == i:
						display_row = j
						display_col = cursor_col - col_offset
						if display_col < 0:
							display_col = 0
						return {"row": display_row, "col": display_col}
					col_offset += line_len
				# Cursor at end of wrapped lines
				display_row = i
				display_col = cursor_col
			else:
				display_row = i
				display_col = cursor_col
			break
		display_row = i + 1

	return {"row": display_row, "col": display_col}


func _build_editor_screen() -> String:
	var output: PackedStringArray = []

	# === HEADER ROW 1: Title text ===
	var modified_str = " *" if is_modified else ""
	var title = " EDIT: " + filename + modified_str + " "
	var title_padding = screen_cols - title.length()
	if title_padding < 0:
		title = title.substr(0, screen_cols)
		title_padding = 0
	var left_pad = title_padding / 2
	var right_pad = title_padding - left_pad
	output.append(" ".repeat(left_pad) + title + " ".repeat(right_pad))

	# === HEADER ROW 2: Border line ===
	output.append(BOX_H.repeat(screen_cols))

	# === CONTENT AREA (with word wrap) ===
	var display_lines = _get_display_lines()
	var cursor_pos = _get_cursor_display_pos(display_lines)

	# Adjust scroll offset based on cursor display position
	if cursor_pos.row < scroll_offset:
		scroll_offset = cursor_pos.row
	elif cursor_pos.row >= scroll_offset + content_rows:
		scroll_offset = cursor_pos.row - content_rows + 1

	for i in range(content_rows):
		var display_idx = scroll_offset + i
		var line_content = ""

		if display_idx < display_lines.size():
			line_content = display_lines[display_idx].text

		# Show cursor on this line
		if display_idx == cursor_pos.row and _cursor_visible and not _find_mode:
			var display_col = cursor_pos.col
			if display_col >= 0 and display_col < screen_cols:
				while line_content.length() <= display_col:
					line_content += " "
				var before = line_content.substr(0, display_col)
				var after = line_content.substr(display_col + 1) if display_col + 1 < line_content.length() else ""
				line_content = before + "█" + after

		# Truncate/pad to fit screen width
		if line_content.length() > screen_cols:
			line_content = line_content.substr(0, screen_cols)
		else:
			line_content = line_content + " ".repeat(screen_cols - line_content.length())

		output.append(line_content)

	# === FOOTER ROW 1: Border line ===
	output.append(BOX_H.repeat(screen_cols))

	# === FOOTER ROW 2: Status text ===
	var status_left: String
	if _find_mode:
		status_left = "Find: " + _find_input + "_"
	elif not _message.is_empty():
		status_left = _message
	else:
		status_left = "F1:Help F2:Save F5:Find Esc:Exit"

	var mode_str = "INS" if insert_mode else "OVR"
	var status_right = "L%d C%d %s" % [cursor_row + 1, cursor_col + 1, mode_str]
	var status_padding = screen_cols - status_left.length() - status_right.length()

	var status_line: String
	if status_padding > 0:
		status_line = status_left + " ".repeat(status_padding) + status_right
	else:
		status_line = (status_left + " " + status_right).substr(0, screen_cols)

	output.append(status_line)

	return "\n".join(output)


func _build_help_screen() -> String:
	var output: PackedStringArray = []

	# Header row 1: Title
	var title = " EDIT HELP "
	var title_padding = screen_cols - title.length()
	var left_pad = title_padding / 2
	var right_pad = title_padding - left_pad
	output.append(" ".repeat(left_pad) + title + " ".repeat(right_pad))

	# Header row 2: Border
	output.append(BOX_H.repeat(screen_cols))

	var help_lines = [
		"",
		" NAVIGATION",
		"   Arrow Keys ... Move cursor",
		"   Home/End ..... Line start/end",
		"   PgUp/PgDn .... Scroll page",
		"",
		" EDITING",
		"   Type ......... Insert text",
		"   Backspace .... Delete left",
		"   Delete ....... Delete right",
		"   Enter ........ New line",
		"",
		" COMMANDS",
		"   F1=Help  F2=Save  F5=Find",
		"   Esc=Exit",
		"",
		" Press any key to continue...",
	]

	for i in range(content_rows):
		var line = help_lines[i] if i < help_lines.size() else ""
		if line.length() > screen_cols:
			line = line.substr(0, screen_cols)
		else:
			line = line + " ".repeat(screen_cols - line.length())
		output.append(line)

	# Footer row 1: Border
	output.append(BOX_H.repeat(screen_cols))

	# Footer row 2: Empty status line
	output.append(" ".repeat(screen_cols))

	return "\n".join(output)
