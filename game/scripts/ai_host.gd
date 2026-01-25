extends Node
## AI Host - Simulates a computer system using OpenAI's GPT API
## Creates dynamic, unpredictable host experiences

signal response_chunk(text: String)
signal response_complete()
signal connection_error(message: String)

const API_URL = "https://api.openai.com/v1/chat/completions"
const MODEL = "gpt-4o-mini"  # Cost-effective and fast

var _http_request: HTTPRequest
var _conversation: Array = []
var _system_prompt: String = ""
var _is_connected: bool = false

# System personality generated at connection time
var system_type: String = ""
var organization: String = ""
var node_name: String = ""


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = 30.0
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


## Initialize a new AI host session
func connect_to_host() -> Dictionary:
	if not SettingsManager.has_openai_key():
		return {"error": "No API key configured"}
	
	# Generate random system personality
	_generate_system_personality()
	
	# Build system prompt
	_system_prompt = _build_system_prompt()
	
	# Reset conversation
	_conversation = []
	_is_connected = true
	
	# Return system info for display
	return {
		"system_type": system_type,
		"organization": organization,
		"node_name": node_name,
		"banner": ""  # AI will generate its own banner
	}


func disconnect_from_host() -> void:
	_is_connected = false
	_conversation = []
	_http_request.cancel_request()


## Send user input and get AI response
func send_input(user_input: String) -> void:
	if not _is_connected:
		connection_error.emit("Not connected")
		return
	
	if not SettingsManager.has_openai_key():
		connection_error.emit("No API key")
		return
	
	# Add user message to conversation
	_conversation.append({
		"role": "user",
		"content": user_input
	})
	
	# Build request
	var messages = [{"role": "system", "content": _system_prompt}]
	messages.append_array(_conversation)
	
	var body = {
		"model": MODEL,
		"messages": messages,
		"max_tokens": 500,
		"temperature": 0.8
	}
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + SettingsManager.openai_api_key
	]
	
	var json_body = JSON.stringify(body)
	var err = _http_request.request(API_URL, headers, HTTPClient.METHOD_POST, json_body)
	
	if err != OK:
		connection_error.emit("Request failed: " + str(err))


## Get initial banner/prompt from AI
func get_initial_response() -> void:
	# Send empty "connection" message to get the banner
	_conversation.append({
		"role": "user", 
		"content": "[USER HAS JUST CONNECTED VIA MODEM - DISPLAY YOUR LOGIN BANNER/PROMPT]"
	})
	
	var messages = [{"role": "system", "content": _system_prompt}]
	messages.append_array(_conversation)
	
	var body = {
		"model": MODEL,
		"messages": messages,
		"max_tokens": 800,
		"temperature": 0.8
	}
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + SettingsManager.openai_api_key
	]
	
	var json_body = JSON.stringify(body)
	_http_request.request(API_URL, headers, HTTPClient.METHOD_POST, json_body)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		connection_error.emit("Connection failed: " + str(result))
		return
	
	if response_code != 200:
		var error_text = body.get_string_from_utf8()
		print("[AI Host] API Error: ", response_code, " - ", error_text)
		connection_error.emit("API error: " + str(response_code))
		return
	
	# Parse response
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		connection_error.emit("Parse error")
		return
	
	var data = json.data
	if data.has("choices") and data.choices.size() > 0:
		var response_text = data.choices[0].message.content
		
		# Add to conversation history
		_conversation.append({
			"role": "assistant",
			"content": response_text
		})
		
		# Emit the response
		response_chunk.emit(response_text)
		response_complete.emit()
	else:
		connection_error.emit("Invalid response format")


func _generate_system_personality() -> void:
	# Random system types weighted toward interesting ones
	var types = [
		{"type": "VAX/VMS", "weight": 20},
		{"type": "UNIX System V", "weight": 20},
		{"type": "RSTS/E", "weight": 15},
		{"type": "IBM MVS/TSO", "weight": 15},
		{"type": "HP3000/MPE", "weight": 10},
		{"type": "PRIMOS", "weight": 10},
		{"type": "VM/CMS", "weight": 10},
	]
	
	var total_weight = 0
	for t in types:
		total_weight += t.weight
	
	var roll = randi() % total_weight
	var current = 0
	for t in types:
		current += t.weight
		if roll < current:
			system_type = t.type
			break
	
	# Random organizations
	var orgs = [
		"Meridian Research Institute",
		"Pacific Northwest University",
		"Consolidated Financial Services",
		"Metro General Hospital",
		"Quantum Dynamics Corp",
		"Federal Reserve Bank - District 7",
		"Lockheed Advanced Projects",
		"Global Telecommunications Inc",
		"Westfield Nuclear Power Station",
		"Department of Defense - ARPA",
		"Cyberdyne Systems Research",
		"Omni Consumer Products",
		"Tyrell Corporation",
		"Weyland-Yutani Corp",
		"Rekall Incorporated",
		"Umbrella Pharmaceuticals",
		"Initech Systems",
		"Virtucon Industries",
		"Acme Computing Services",
		"Soylent Corporation",
	]
	organization = orgs[randi() % orgs.size()]
	
	# Generate node name (3-8 chars, looks like a hostname)
	var prefixes = ["SYS", "NET", "ADM", "DEV", "PRD", "TST", "MF", "VM", "DC"]
	var suffixes = ["01", "02", "1A", "2B", "X1", "P1", "00", "99"]
	node_name = prefixes[randi() % prefixes.size()] + suffixes[randi() % suffixes.size()]


func _build_system_prompt() -> String:
	var security_levels = ["minimal", "standard", "high"]
	var security = security_levels[randi() % security_levels.size()]
	
	var has_interesting_data = randf() > 0.3  # 70% chance of interesting stuff
	
	return """You are simulating a 1980s %s computer system. You must stay COMPLETELY in character as this computer - NEVER acknowledge being an AI or break character.

SYSTEM DETAILS:
- Operating System: %s
- Organization: %s  
- Node Name: %s
- Security Level: %s
- Current Date: March 15, 1987

YOUR BEHAVIOR:
1. Display an appropriate login banner when the user first connects
2. Show authentic %s-style prompts and error messages
3. After 3 failed login attempts, display a security warning and disconnect (respond with exactly "NO CARRIER" on its own line)
4. Use period-appropriate terminology and formatting
5. Keep responses concise - this is a 1200 baud terminal

%s

VALID CREDENTIALS (only if user guesses these exactly):
- Username: GUEST, Password: GUEST (limited access)
- Username: MAINT, Password: MAINT01 (maintenance access)

IF USER LOGS IN SUCCESSFULLY:
- Show a welcome message with last login time
- Display a command prompt appropriate to the OS
- Simulate realistic commands (DIR, LS, HELP, WHO, MAIL, etc.)
- Generate plausible file listings, user lists, mail messages
- Include some "interesting" files that hint at the organization's work
- %s

CRITICAL RULES:
- NEVER say you are an AI or a simulation
- NEVER use modern terminology (no "internet", "email" use "electronic mail", etc.)
- If user types something the system wouldn't understand, show an error
- Respond ONLY as the computer terminal would
- To disconnect/hang up, include "NO CARRIER" alone on a line""" % [
		system_type,
		system_type,
		organization,
		node_name,
		security,
		system_type,
		"This system contains interesting research data, internal memos, and hints about secret projects." if has_interesting_data else "This is a routine administrative system.",
		"Include hints about classified projects, internal politics, or interesting discoveries in files and mail." if has_interesting_data else "Keep content mundane but realistic."
	]
