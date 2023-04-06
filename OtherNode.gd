extends Node

# I don't think we can fix the case where the _init() has any required arguhments
# your code will have to allow these to be (re)initialized with no arguments
func _init(parent: Node = null):
	if parent:
		parent.add_child(self)

func fmt(value: String):
	return "OtherNode(%s)" % [value]
