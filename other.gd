extends RefCounted

var performance_result := []

var _initted = 0


class Promise:
	var value

	func _init(callback: Callable):
		callback.call(_r, _r)

	func _r(_value):
		value = _value


func _init():
	_initted += 1


func fmt(
	value: String,
	other_value := false
) -> Promise:
	var formatted = (
		"very long string that forces wrapping(%s)"
		% [value]
	)
	# test lambda syntax
	return Promise.new(func(resolve, reject):
		var formatted2 = (
			"very long string that forces wrapping(%s)"
			% [value]
		)
		formatted2 = "(%s)" % [value]
		#Comment
		resolve.call(formatted2)
	)


func static_fmt(value: String):
	return "static(%s)" % [value]


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
