module iftest

// Test if statement coverage - the if header has hits, so closing brace should be covered
pub fn check_length(arr []int) int {
	if arr.len < 4 {
		// This branch is never taken in our test
		return -1
	}

	return arr.len
}
