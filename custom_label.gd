extends Label

var custom_text: String:
	set = _set_custom_text


func _set_custom_text(value: String) -> void:
	text = "custom(%s)" % [value]
