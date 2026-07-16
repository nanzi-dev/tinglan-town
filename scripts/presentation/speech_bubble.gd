class_name SpeechBubble
extends Label3D

@export var display_seconds := 4.0
@export var maximum_characters := 48

var _speaker_name := ""
var _line_text := ""
var _hide_timer: Timer


func _ready() -> void:
	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.timeout.connect(hide_line)
	add_child(_hide_timer)
	hide_line()


func show_line(speaker_name: String, line_text: String) -> bool:
	var normalized_speaker := speaker_name.strip_edges()
	var normalized_line := line_text.strip_edges()
	if normalized_speaker.is_empty() or normalized_line.is_empty():
		return false
	if normalized_line.length() > maximum_characters:
		normalized_line = (
			normalized_line.left(maximum_characters - 1) + "…"
		)

	_speaker_name = normalized_speaker
	_line_text = normalized_line
	text = "%s\n%s" % [_speaker_name, _line_text]
	visible = true
	if _hide_timer != null and display_seconds > 0.0:
		_hide_timer.start(display_seconds)
	return true


func hide_line() -> void:
	if _hide_timer != null:
		_hide_timer.stop()
	visible = false


func get_speaker_name() -> String:
	return _speaker_name


func get_line_text() -> String:
	return _line_text
