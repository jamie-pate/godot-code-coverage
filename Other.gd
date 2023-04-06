extends Reference

var _initted = 0

func _init():
	_initted += 1

func fmt(value: String):
	return '(%s)' % [value]

func static_fmt(value:String):
	return 'static(%s)'
