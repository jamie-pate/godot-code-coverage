@tool
class_name Spatial1 extends Node3D

signal done

const Other = preload("./other.gd")
const CustomLabel = preload("./custom_label.gd")

var auto_quit := true


class Inner:
	extends RefCounted

	class InnerEmpty:
		extends RefCounted

	static func fmt(value: String):
		return "Inner(%s)" % [value]


class InnerExtends:
	extends RefCounted

	func fmt(value: String):
		return "InterExtends(%s)" % [value]


# Called when the node enters the scene tree for the first time.
func _ready():
	var other := Other.new()
	$Label.text = InnerExtends.new().fmt(Inner.fmt(other.fmt("hello world").value))


func _on_Timer_timeout():
	print("add child")
	var custom_label := CustomLabel.new()
	add_child(custom_label)
	custom_label.offset_top = 20
	var other := Other.new()
	var text := Autoload1.fmt("timeout")
	$Label.text = text
	custom_label.custom_text = $Label.text
	for i in range(2):
		await get_tree().process_frame
		if i == 0:
			$Label.text = other.fmt(str(i)).value
		elif i == 1:
			$Label.text = (other.fmt(str(i * 1)).value)
		else:
			var x = {a = 1}
			$Label.text = other.fmt(str(i * 2) + str(x)).value
		match i:
			0:
				$Label.text = other.fmt(str(i)).value
			# 1
			1:
				$Label.text = other.fmt(str(i * 1)).value
			3:
				$Label.text = other.fmt(str(i * 1)).value
		custom_label.custom_text = $Label.text
	await get_tree().process_frame
	assert(
		Autoload2._counter == "3",
		"Autoload2 counter should be 3 because Autoload1 'formatting' signal fired"
	)
	$Label.text = Autoload2.fmt("done")
	custom_label.custom_text = $Label.text
	await get_tree().create_timer(.5).timeout
	print("Performance takes %sus" % [Other.new().performance_test()])
	emit_signal("done")
	if auto_quit:
		print("This line is not covered in the unit tests")
		get_tree().quit()
	else:
		print("This line is not covered in the CoverageTree tests")
