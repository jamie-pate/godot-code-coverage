extends Node

var _counter = "0"


# Called when the node enters the scene tree for the first time.
func _ready():
	_counter = "2"
	var err := Autoload1.connect("formatting", Callable(self, "_on_autoload1_formatting"))
	assert(err == OK)


func fmt(value: String):
	return Autoload1.fmt("%s:%s" % [_counter, value])


func _on_autoload1_formatting():
	_counter = "3"
