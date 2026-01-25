extends Node
class_name AIForum
## AI-powered BBS forum system
## Generates dynamic forum posts using OpenAI API

signal posts_generated(board_name: String, posts: Array)
signal post_generated(post: Dictionary)
signal generation_error(message: String)

const API_URL = "https://api.openai.com/v1/chat/completions"
const MODEL = "gpt-4o-mini"

var _http_request: HTTPRequest

# Forum boards for hacker BBSes
const FORUM_BOARDS = {
	"general": "General Discussion - Random hacker talk",
	"wardialing": "War Dialing - Tips for finding systems",
	"vax_vms": "VAX/VMS Hacking - DEC system exploration",
	"unix": "Unix Hacking - BSD and System V",
	"phreaking": "Phone Phreaking - Telco exploration",
	"warez": "Warez Trading - Software exchange"
}


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = 60.0
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


## Generate posts for a board
func generate_posts(board_name: String, bbs_name: String, existing_posts: Array = []) -> void:
	if not SettingsManager.has_openai_key():
		generation_error.emit("No API key configured")
		return
	
	var board_desc = FORUM_BOARDS.get(board_name, "General discussion")
	
	var system_prompt = _build_forum_system_prompt(bbs_name, board_name, board_desc)
	var messages = [{"role": "system", "content": system_prompt}]
	
	# Add existing posts as context
	if not existing_posts.is_empty():
		var context = "Previous posts in this thread:\n"
		for post in existing_posts.slice(-5):  # Last 5 posts
			context += "\n[%s] %s:\n%s\n" % [post.date, post.author, post.content]
		messages.append({"role": "user", "content": context + "\nGenerate 2-3 new follow-up posts."})
	else:
		messages.append({"role": "user", "content": "Generate 3-4 posts to start this board."})
	
	var body = {
		"model": MODEL,
		"messages": messages,
		"max_tokens": 1200,
		"temperature": 0.9,
		"response_format": {"type": "json_object"}
	}
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + SettingsManager.openai_api_key
	]
	
	_http_request.request(API_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))


func _build_forum_system_prompt(bbs_name: String, board_name: String, board_desc: String) -> String:
	return """You are generating forum posts for a 1980s hacker BBS called "%s".
The board is: %s - %s

Generate realistic forum posts from the perspective of 1980s hackers/phreakers.
- Use period-appropriate slang and terminology
- Reference real 1980s systems, phreaking techniques, BBSes
- Include realistic handles like "The Mentor", "Acid Phreak", "Phiber Optik"
- Posts should be in all caps or mixed case (80s style)
- Keep posts short (2-4 lines typical)
- Include some drama, bragging, and hacker culture

Respond with JSON in this exact format:
{
  "posts": [
    {
      "author": "HandleName",
      "date": "03-15-87",
      "content": "Post content here..."
    }
  ]
}

Generate authentic-feeling 1980s BBS content. Be creative but period-accurate.""" % [bbs_name, board_name, board_desc]


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		generation_error.emit("Connection failed")
		return
	
	if response_code != 200:
		generation_error.emit("API error: " + str(response_code))
		return
	
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		generation_error.emit("Parse error")
		return
	
	var data = json.data
	if not data.has("choices") or data.choices.is_empty():
		generation_error.emit("Invalid response")
		return
	
	var content = data.choices[0].message.content
	
	# Parse the JSON posts
	var posts_json = JSON.new()
	if posts_json.parse(content) != OK:
		generation_error.emit("Failed to parse posts JSON")
		return
	
	var posts_data = posts_json.data
	if posts_data.has("posts"):
		posts_generated.emit("", posts_data.posts)
	else:
		generation_error.emit("No posts in response")
