extends Node

const Other := preload("res://Other.gd")
const OtherNode := preload("res://OtherNode.gd")

signal formatting()

var other_node := OtherNode.new(self)
var other := Other.new()
var _initted := false
var _ready_value := '0'

func _init():
	_initted = true

# Called when the node enters the scene tree for the first time.
func _ready():
	_ready_value = '1'

func fmt(value: String) -> String:
	emit_signal('formatting')
	return other_node.fmt(other.fmt('%s:%s:%s' % [_initted, _ready_value, value]))
