module returnmatch

fn test_get_labels_yes_no() {
	labels := get_labels(.yes_no)
	assert labels == ['Yes', 'No']
}

fn test_get_count_yes_no() {
	count := get_count(.yes_no)
	assert count == 2
}
