module matchtest

fn test_get_value() {
	// Only call with 'one' - other arms stay uncovered
	assert get_value('one') == 1
}
