module orblocktest

fn test_error_path_taken() {
	result := test_or_block_taken()
	assert result == -1
}

fn test_success_path() {
	result := test_or_block_not_taken()
	assert result == 42
}

fn test_expr_value() {
	result := test_or_block_with_expr()
	assert result == 0
}

fn test_nested() {
	result := test_nested_or_block()
	assert result == 42
}
