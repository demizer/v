module structtest

// Inner is a nested struct used as a field type
struct Inner {
	value int
}

// Outer contains Inner as a field - Inner should be covered when Outer is used
struct Outer {
	inner Inner
	name  string
	count int
}

// Unused is never instantiated or used
struct Unused {
	data string
}

// create_outer creates an Outer struct with an Inner
pub fn create_outer() Outer {
	return Outer{
		inner: Inner{
			value: 42
		}
		name:  'test'
		count: 1
	}
}

// get_value accesses fields of Outer and Inner
pub fn get_value(o Outer) int {
	return o.inner.value + o.count
}
