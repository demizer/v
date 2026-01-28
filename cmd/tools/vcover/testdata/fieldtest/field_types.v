module fieldtest

struct Inner {
	value int
	name  string
}

struct Outer {
	inner Inner
	count int
}

pub fn create_and_access() int {
	o := Outer{
		inner: Inner{
			value: 42
			name:  'test'
		}
		count: 1
	}
	// Access fields - these should be tracked
	x := o.inner.value // Outer.inner and Inner.value
	y := o.count // Outer.count
	return x + y
}
