extends Spatial

const Other = preload("./Other.gd")
const CustomLabel = preload("./CustomLabel.gd")
# Called when the node enters the scene tree for the first time.
func _ready():
	var other = Other.new()
	$Label.text = other.fmt("hello world")

func _on_Timer_timeout():
	print('add child')
	var custom_label := CustomLabel.new()
	add_child(custom_label)
	custom_label.margin_top = 20
	var other = Other.new()
	$Label.text = other.fmt("timeout")
	custom_label.custom_text = $Label.text
	for i in range(2):
		yield(get_tree().create_timer(.5), "timeout")
		$Label.text = other.fmt(str(i))
		custom_label.custom_text = $Label.text
	yield(get_tree().create_timer(.5), "timeout")
	$Label.text = other.fmt("done")
	custom_label.custom_text = $Label.text
	yield(get_tree().create_timer(.5), "timeout")
	get_tree().quit()
