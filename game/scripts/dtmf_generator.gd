extends Node
class_name DTMFGenerator
## Generates DTMF (Dual-Tone Multi-Frequency) tones for phone dialing
## Based on standard DTMF frequencies used in touch-tone phones

# DTMF frequency constants (Hz)
const ROW_FREQS = [697.0, 770.0, 852.0, 941.0]
const COL_FREQS = [1209.0, 1336.0, 1477.0, 1633.0]

# DTMF keypad mapping: [row_index, col_index]
const DTMF_MAP = {
	"1": [0, 0], "2": [0, 1], "3": [0, 2], "A": [0, 3],
	"4": [1, 0], "5": [1, 1], "6": [1, 2], "B": [1, 3],
	"7": [2, 0], "8": [2, 1], "9": [2, 2], "C": [2, 3],
	"*": [3, 0], "0": [3, 1], "#": [3, 2], "D": [3, 3],
}

# Audio settings
const SAMPLE_RATE = 44100
const TONE_DURATION = 0.15  # Duration of each DTMF tone in seconds
const TONE_GAP = 0.08  # Gap between tones in seconds
const DIAL_TONE_DURATION = 1.8  # Duration of dial tone before dialing

signal dialing_started()
signal digit_dialed(digit: String)
signal dialing_complete(number: String)

var _audio_player: AudioStreamPlayer
var _dial_tone_player: AudioStreamPlayer
var _dial_tone_sound: AudioStream
var _is_dialing: bool = false
var _current_number: String = ""


func _ready() -> void:
	# Set up DTMF tone player
	_audio_player = AudioStreamPlayer.new()
	_audio_player.volume_db = -6.0
	add_child(_audio_player)
	
	# Set up dial tone player
	_dial_tone_sound = load("res://assets/dial-tone-89734.mp3")
	_dial_tone_player = AudioStreamPlayer.new()
	_dial_tone_player.volume_db = -6.0
	_dial_tone_player.stream = _dial_tone_sound
	add_child(_dial_tone_player)


## Dial a phone number with DTMF tones
## Plays dial tone first, then each digit
func dial_number(number: String) -> void:
	if _is_dialing:
		return
	
	_is_dialing = true
	_current_number = number
	
	emit_signal("dialing_started")
	
	# Play dial tone first
	if _dial_tone_player and _dial_tone_player.stream:
		_dial_tone_player.play()
	
	# Wait for dial tone duration, then start DTMF
	await get_tree().create_timer(DIAL_TONE_DURATION).timeout
	
	# Stop dial tone
	if _dial_tone_player:
		_dial_tone_player.stop()
	
	# Dial each digit
	for digit in number:
		if digit == "-" or digit == " " or digit == "()" or digit == ")":
			continue  # Skip formatting characters
		
		await _play_dtmf_tone(digit.to_upper())
		emit_signal("digit_dialed", digit)
		
		# Gap between tones
		await get_tree().create_timer(TONE_GAP).timeout
	
	_is_dialing = false
	emit_signal("dialing_complete", number)


## Generate and play a single DTMF tone for a digit
func _play_dtmf_tone(digit: String) -> void:
	if not DTMF_MAP.has(digit):
		print("Invalid DTMF digit: ", digit)
		return
	
	var indices = DTMF_MAP[digit]
	var row_freq = ROW_FREQS[indices[0]]
	var col_freq = COL_FREQS[indices[1]]
	
	# Generate the tone
	var audio = _generate_dual_tone(row_freq, col_freq, TONE_DURATION)
	
	_audio_player.stream = audio
	_audio_player.play()
	
	# Wait for tone to finish
	await get_tree().create_timer(TONE_DURATION).timeout


## Generate a dual-tone audio stream (two sine waves mixed)
func _generate_dual_tone(freq1: float, freq2: float, duration: float) -> AudioStreamWAV:
	var samples = int(SAMPLE_RATE * duration)
	
	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = SAMPLE_RATE
	audio.stereo = false
	
	var data = PackedByteArray()
	data.resize(samples * 2)  # 2 bytes per sample for 16-bit
	
	for i in samples:
		var t = float(i) / SAMPLE_RATE
		
		# Generate two sine waves and mix them
		var sample1 = sin(t * freq1 * TAU)
		var sample2 = sin(t * freq2 * TAU)
		
		# Mix at equal levels, reduce amplitude to prevent clipping
		var mixed = (sample1 + sample2) * 0.4
		
		# Apply a slight envelope to reduce clicks at start/end
		var envelope = 1.0
		var fade_samples = int(SAMPLE_RATE * 0.005)  # 5ms fade
		if i < fade_samples:
			envelope = float(i) / fade_samples
		elif i > samples - fade_samples:
			envelope = float(samples - i) / fade_samples
		
		mixed *= envelope
		
		# Convert to 16-bit signed integer
		var sample_int = int(clamp(mixed * 32767, -32768, 32767))
		
		# Store as little-endian 16-bit
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	
	audio.data = data
	return audio


## Check if currently dialing
func is_dialing() -> bool:
	return _is_dialing


## Stop current dialing
func stop_dialing() -> void:
	_is_dialing = false
	if _audio_player:
		_audio_player.stop()
	if _dial_tone_player:
		_dial_tone_player.stop()
