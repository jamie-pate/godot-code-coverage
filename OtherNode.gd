extends Node

var ready_value := false

func _init(parent: Node):
	if parent:
		parent.add_child(self)

func _ready():
	ready_value = true

func fmt(value: String):
	return "OtherNode(%s)" % [value]
