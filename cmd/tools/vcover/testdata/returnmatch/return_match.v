module returnmatch

enum ButtonType {
	ok
	ok_cancel
	yes_no
	yes_no_cancel
}

// get_labels returns button labels - uses single-line match arms in return
pub fn get_labels(btn ButtonType) []string {
	return match btn {
		.ok { ['OK'] }
		.ok_cancel { ['OK', 'Cancel'] }
		.yes_no { ['Yes', 'No'] }
		.yes_no_cancel { ['Yes', 'No', 'Cancel'] }
	}
}

// get_count uses assignment with match
pub fn get_count(btn ButtonType) int {
	count := match btn {
		.ok { 1 }
		.ok_cancel { 2 }
		.yes_no { 2 }
		.yes_no_cancel { 3 }
	}
	return count
}
