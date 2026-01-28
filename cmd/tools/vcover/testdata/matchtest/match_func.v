module matchtest

pub fn get_value(name string) int {
	// Comment before match

	match name {
		'one' {
			// Comment in first arm
			return 1
		}
		'two' {
			// Comment in second arm
			return 2
		}
		'three' {
			// Comment in third arm
			return 3
		}
		else {
			// Comment in else arm
			return 0
		}
	}
}

// This is a file-scope doc comment that should NOT be colored
// It describes the uncalled_func function below
pub fn uncalled_func(x int) int {
	// This function is never called
	match x {
		1 {
			// Uncovered comment
			return 10
		}
		2 {
			// Another uncovered comment
			return 20
		}
		else {
			// Else uncovered comment
			return 0
		}
	}
}
