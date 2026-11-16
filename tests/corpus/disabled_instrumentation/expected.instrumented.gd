# basic_statements.gd
extends Node

var bare: int
var initialized: int = 1

func _ready() -> void:
	var x = 1
	x += 1
	print(x)
