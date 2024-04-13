extends Node


func _init(parent: Node):
	if parent:
		parent.add_child(self)


func fmt(value: String):
	return "OtherNode(%s)" % [value]
