module iftest

// Test if statement coverage - the if header has hits, so closing brace should be covered
pub fn check_length(arr []int) int {
	if arr.len < 4 {
		// This branch is never taken in our test
		return -1
	}

	return arr.len
}

// Test if expression used as assignment value - both branches should show exact coverage
pub fn if_expr_then_branch(val int) int {
	// Takes the then branch when val > 0
	result := if val > 0 {
		val * 2
	} else {
		-1
	}
	return result
}

pub fn if_expr_else_branch(val int) int {
	// Takes the else branch when val <= 0
	result := if val > 0 {
		val * 2
	} else {
		-1
	}
	return result
}

pub fn if_expr_both_branches(val int) int {
	// Tests coverage when both branches are taken across different calls
	result := if val > 0 {
		val * 2
	} else {
		val - 1
	}
	return result
}
