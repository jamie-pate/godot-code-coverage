extends Node

var ready := false

func _init(parent: Node):
	if parent:
		parent.add_child(self)

func _ready():
	ready = true

func fmt(value: String):
	return "OtherNode(%s)" % [value]
