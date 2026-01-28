module iftest

fn test_check_length() {
	// Call with array length >= 4, so the if body is never executed
	// but the if header is checked (covered)
	assert check_length([1, 2, 3, 4, 5]) == 5
}

fn test_if_expr_then_branch() {
	// Only takes the then branch (val > 0)
	assert if_expr_then_branch(5) == 10
}

fn test_if_expr_else_branch() {
	// Only takes the else branch (val <= 0)
	assert if_expr_else_branch(0) == -1
}

fn test_if_expr_both_branches() {
	// Takes both branches across different calls
	assert if_expr_both_branches(5) == 10
	assert if_expr_both_branches(-3) == -4
}
