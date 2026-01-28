module iftest

fn test_check_length() {
	// Call with array length >= 4, so the if body is never executed
	// but the if header is checked (covered)
	assert check_length([1, 2, 3, 4, 5]) == 5
}
