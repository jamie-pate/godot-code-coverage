tool
class_name Spatial1 extends Spatial

const Other = preload("./Other.gd")
const CustomLabel = preload("./CustomLabel.gd")

var auto_quit := true

signal done()


class Inner:
	tool
	extends Reference

	class InnerEmpty:
		extends Reference

	static func fmt(value: String):
		return 'Inner(%s)' % [value]

class InnerExtends extends Reference:
	func fmt(value: String):
		return 'InterExtends(%s)' % [value]

# Called when the node enters the scene tree for the first time.
func _ready():
	var other = Other.new()
	$Label.text = InnerExtends.new().fmt(Inner.fmt(other.fmt("hello world")))

func _on_Timer_timeout():
	print('add child')
	var custom_label := CustomLabel.new()
	add_child(custom_label)
	custom_label.margin_top = 20
	var other = Other.new()
	var text := Autoload1.fmt("timeout")
	$Label.text = text
	custom_label.custom_text = \
		$Label.text
	for i in range(2):
		yield(get_tree().create_timer(.5), "timeout")
		if i == 0:
			$Label.text = other.fmt(str(i))
		elif i == 1:
			$Label.text = (
				other.fmt(str(i * 1))
			)
		else:
			var x = {
				a=1
			}
			$Label.text = other.fmt(str(i * 2) + str(x))
		match i:
			0:
				$Label.text = other.fmt(str(i))
			# 1
			1:
				$Label.text = other.fmt(str(i * 1))
			3: $Label.text = other.fmt(str(i * 1))
		custom_label.custom_text = $Label.text
	yield(get_tree().create_timer(.5), "timeout")
	assert(Autoload2._counter == '3', "Autoload2 counter should be 3 because Autoload1 'formatting' signal fired")
	$Label.text = Autoload2.fmt("done")
	custom_label.custom_text = $Label.text
	yield(get_tree().create_timer(.5), "timeout")
	emit_signal("done")
	if auto_quit:
		get_tree().quit()
