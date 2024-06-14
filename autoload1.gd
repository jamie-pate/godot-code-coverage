extends Node

signal formatting

const Other := preload("res://other.gd")
const OtherNode := preload("res://other_node.gd")

var other_node := OtherNode.new(self)
var other := Other.new()
var _initted := false


func _init():
	_initted = true


func fmt(value: String) -> String:
	emit_signal("formatting")
	return other_node.fmt(other.fmt("%s:%s:%s" % [_initted, ready, value]).value)
