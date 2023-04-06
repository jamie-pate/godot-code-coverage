extends Node

const Other := preload("res://Other.gd")

signal formatting()

var other := Other.new()
var _initted := false
var _ready := '0'

func _init():
	_initted = true
# Called when the node enters the scene tree for the first time.
func _ready():
	_ready = '1'

func fmt(value: String):
	emit_signal('formatting')
	return other.fmt('%s:%s:%s' % [_initted, _ready, value])