module structtest

fn test_create_outer() {
	o := create_outer()
	assert o.inner.value == 42
	assert o.name == 'test'
	assert o.count == 1
}

fn test_get_value() {
	o := create_outer()
	v := get_value(o)
	assert v == 43
}
