module orblocktest

// Test or {} block coverage - statements inside or blocks should show exact hits

pub fn might_fail(should_fail bool) !int {
	if should_fail {
		return error('intentional failure')
	}
	return 42
}

pub fn test_or_block_taken() int {
	// This or block WILL be taken (error path)
	result := might_fail(true) or {
		println('error caught')
		return -1
	}
	return result
}

pub fn test_or_block_not_taken() int {
	// This or block will NOT be taken (success path)
	result := might_fail(false) or {
		println('should not print')
		return -1
	}
	return result
}

pub fn test_or_block_with_expr() int {
	// or block with expression value (not return)
	result := might_fail(true) or { 0 }
	return result
}

pub fn test_nested_or_block() int {
	// Nested or blocks
	outer := might_fail(true) or {
		inner := might_fail(false) or {
			println('inner error')
			return -2
		}
		inner
	}
	return outer
}
