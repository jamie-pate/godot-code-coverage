extends RefCounted

var _initted = 0
var performance_result := []

func _init():
	_initted += 1

func fmt(value: String):
	return '(%s)' % [value]

func static_fmt(value:String):
	return 'static(%s)'

func performance_test() -> int:
	var result := 0xFFFFFF
	for j in range(10):
		var start := Time.get_ticks_usec()
		var n := []
		var repeat = 10000
		for i in range(repeat):
			n.append(1)
			n[i] *= 2
			n[i] -= 1
			n[i] /= 2
		# paranoia, the interpreter doesn't optimize yet
		# but someday it might optimize the whole loop out if n is discarded
		performance_result = n
		var duration := Time.get_ticks_usec() - start
		if duration < result:
			result = duration
	return result
