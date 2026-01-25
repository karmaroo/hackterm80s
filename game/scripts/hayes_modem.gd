extends Node
class_name HayesModem
## Hayes-compatible modem simulator
## Handles AT commands and modem responses

signal response_received(response: String)
signal connected(baud: int)
signal disconnected()
signal ringing()
signal busy()
signal no_answer()

# Modem state
enum ModemState { IDLE, DIALING, RINGING, CONNECTED, ERROR }
var state: ModemState = ModemState.IDLE
var baud_rate: int = 2400
var speaker_on: bool = true
var echo_on: bool = true

# Current call
var current_number: String = ""
var connection_baud: int = 0


func _ready() -> void:
	pass


## Process AT command
func send_command(cmd: String) -> void:
	var upper_cmd = cmd.to_upper().strip_edges()
	
	# AT prefix required for most commands
	if not upper_cmd.begins_with("AT"):
		if echo_on:
			response_received.emit("ERROR")
		return
	
	var command_part = upper_cmd.substr(2)
	
	# Parse command
	if command_part.is_empty():
		response_received.emit("OK")
	elif command_part.begins_with("D") or command_part.begins_with("DT") or command_part.begins_with("DP"):
		# Dial command
		var number = command_part.substr(1) if command_part.begins_with("D") else command_part.substr(2)
		number = number.replace("T", "").replace("P", "")
		_dial(number)
	elif command_part == "H" or command_part == "H0":
		# Hang up
		_hangup()
	elif command_part == "Z":
		# Reset
		_reset()
	elif command_part.begins_with("S"):
		# S-register (ignore for now)
		response_received.emit("OK")
	elif command_part.begins_with("M"):
		# Speaker control
		speaker_on = not command_part.ends_with("0")
		response_received.emit("OK")
	elif command_part.begins_with("E"):
		# Echo control
		echo_on = not command_part.ends_with("0")
		response_received.emit("OK")
	else:
		response_received.emit("OK")


func _dial(number: String) -> void:
	if state != ModemState.IDLE:
		response_received.emit("ERROR")
		return
	
	current_number = number.replace("-", "").replace(" ", "")
	state = ModemState.DIALING
	
	# Simulate dial sequence
	_simulate_dial()


func _simulate_dial() -> void:
	await get_tree().create_timer(2.0).timeout  # Dialing time
	
	if state != ModemState.DIALING:
		return
	
	# Random outcome
	var roll = randf()
	
	if roll < 0.6:  # 60% connect
		state = ModemState.CONNECTED
		connection_baud = [1200, 2400][randi() % 2]
		response_received.emit("CONNECT %d" % connection_baud)
		connected.emit(connection_baud)
	elif roll < 0.75:  # 15% busy
		state = ModemState.IDLE
		response_received.emit("BUSY")
		busy.emit()
	elif roll < 0.9:  # 15% no answer
		state = ModemState.IDLE
		response_received.emit("NO ANSWER")
		no_answer.emit()
	else:  # 10% no carrier
		state = ModemState.IDLE
		response_received.emit("NO CARRIER")


func _hangup() -> void:
	if state == ModemState.CONNECTED:
		disconnected.emit()
	state = ModemState.IDLE
	current_number = ""
	response_received.emit("OK")


func _reset() -> void:
	state = ModemState.IDLE
	baud_rate = 2400
	speaker_on = true
	echo_on = true
	current_number = ""
	response_received.emit("OK")


## Check if connected
func is_connected() -> bool:
	return state == ModemState.CONNECTED


## Get connection info
func get_connection_info() -> Dictionary:
	return {
		"connected": is_connected(),
		"number": current_number,
		"baud": connection_baud
	}
