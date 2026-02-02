module ast

import v.token

// Test basic primitive serialization
fn test_primitives() {
	mut w := new_ast_writer(64)

	// Write primitives
	w.write_bool(true)
	w.write_bool(false)
	w.write_u8(42)
	w.write_u16(1234)
	w.write_u32(0x12345678)
	w.write_i32(-999)
	w.write_i64(0x123456789ABCDEF0)
	w.write_string('hello')

	// Read them back
	mut r := new_ast_reader(w.buf)

	assert r.read_bool() == true
	assert r.read_bool() == false
	assert r.read_u8() == 42
	assert r.read_u16() == 1234
	assert r.read_u32() == 0x12345678
	assert r.read_i32() == -999
	assert r.read_i64() == 0x123456789ABCDEF0
	assert r.read_string() == 'hello'
}

// Test position serialization
fn test_pos() {
	mut w := new_ast_writer(64)

	pos := token.Pos{
		len:       10
		line_nr:   42
		pos:       100
		col:       5
		file_idx:  1
		last_line: 42
	}
	w.write_pos(pos)

	mut r := new_ast_reader(w.buf)
	read_pos := r.read_pos()

	assert read_pos.len == pos.len
	assert read_pos.line_nr == pos.line_nr
	assert read_pos.pos == pos.pos
	assert read_pos.col == pos.col
	assert read_pos.file_idx == pos.file_idx
	assert read_pos.last_line == pos.last_line
}

// Test Comment serialization
fn test_comment() {
	mut w := new_ast_writer(64)

	c := Comment{
		text:     '// hello world'
		is_multi: false
		pos:      token.Pos{
			len:       14
			line_nr:   1
			pos:       0
			col:       0
			file_idx:  0
			last_line: 1
		}
	}
	w.write_comment(c)

	mut r := new_ast_reader(w.buf)
	read_c := r.read_comment()

	assert read_c.text == c.text
	assert read_c.is_multi == c.is_multi
	assert read_c.pos.len == c.pos.len
}

// Test Attr serialization
fn test_attr() {
	mut w := new_ast_writer(64)

	attr := Attr{
		name:    'unsafe'
		has_arg: false
		arg:     ''
		kind:    .plain
		ct_opt:  false
		pos:     token.Pos{
			len:     8
			line_nr: 1
		}
		has_at:  true
	}
	w.write_attr(attr)

	mut r := new_ast_reader(w.buf)
	read_attr := r.read_attr()

	assert read_attr.name == attr.name
	assert read_attr.has_arg == attr.has_arg
	assert read_attr.kind == attr.kind
	assert read_attr.has_at == attr.has_at
}

// Test Module serialization
fn test_module() {
	mut w := new_ast_writer(256)

	mod := Module{
		name:       'encoding.json'
		short_name: 'json'
		attrs:      []
		pos:        token.Pos{
			len:     12
			line_nr: 1
		}
		name_pos:   token.Pos{
			len:     4
			line_nr: 1
		}
		is_skipped: false
	}
	w.write_module(mod)

	mut r := new_ast_reader(w.buf)
	read_mod := r.read_module()

	assert read_mod.name == mod.name
	assert read_mod.short_name == mod.short_name
	assert read_mod.is_skipped == mod.is_skipped
}

// Test Import serialization
fn test_import() {
	mut w := new_ast_writer(256)

	imp := Import{
		source_name:   'os'
		mod:           'os'
		alias:         ''
		pos:           token.Pos{
			len:     9
			line_nr: 3
		}
		syms:          []
		comments:      []
		next_comments: []
	}
	w.write_import(imp)

	mut r := new_ast_reader(w.buf)
	read_imp := r.read_import()

	assert read_imp.source_name == imp.source_name
	assert read_imp.mod == imp.mod
	assert read_imp.alias == imp.alias
}

// Test string array serialization
fn test_string_array() {
	mut w := new_ast_writer(128)

	arr := ['hello', 'world', 'test']
	w.write_string_array(arr)

	mut r := new_ast_reader(w.buf)
	read_arr := r.read_string_array()

	assert read_arr == arr
}

// Test File serialization header
fn test_file_header() {
	// Create a minimal file
	file := &File{
		nr_lines:       100
		nr_bytes:       5000
		nr_tokens:      500
		is_test:        false
		is_generated:   false
		is_translated:  false
		language:       .v
		mod:            Module{
			name:       'main'
			short_name: 'main'
		}
		imports:        []
		auto_imports:   []
		embedded_files: []
		stmts:          []
	}

	// Serialize and deserialize
	data := serialize_file(file)
	assert data.len > 0

	// Check magic bytes
	assert data[0] == `V`
	assert data[1] == `A`
	assert data[2] == `S`
	assert data[3] == `T`

	// Deserialize
	read_file := deserialize_file(data) or {
		assert false, 'deserialize failed: ${err}'
		return
	}

	assert read_file.nr_lines == file.nr_lines
	assert read_file.nr_bytes == file.nr_bytes
	assert read_file.nr_tokens == file.nr_tokens
	assert read_file.is_test == file.is_test
	assert read_file.mod.name == file.mod.name
}

// Test integer literal expression
fn test_expr_integer_literal() {
	mut w := new_ast_writer(64)

	expr := IntegerLiteral{
		val: '42'
		pos: token.Pos{
			len:     2
			line_nr: 1
			pos:     0
		}
	}
	w.write_expr(expr)

	mut r := new_ast_reader(w.buf)
	read_expr := r.read_expr()

	if read_expr is IntegerLiteral {
		assert read_expr.val == '42'
		assert read_expr.pos.len == 2
	} else {
		assert false, 'expected IntegerLiteral'
	}
}

// Test string literal expression
fn test_expr_string_literal() {
	mut w := new_ast_writer(64)

	expr := StringLiteral{
		val:      'hello world'
		is_raw:   false
		language: .v
		pos:      token.Pos{
			len:     13
			line_nr: 1
		}
	}
	w.write_expr(expr)

	mut r := new_ast_reader(w.buf)
	read_expr := r.read_expr()

	if read_expr is StringLiteral {
		assert read_expr.val == 'hello world'
		assert read_expr.is_raw == false
		assert read_expr.language == .v
	} else {
		assert false, 'expected StringLiteral'
	}
}

// Test Ident expression
fn test_expr_ident() {
	mut w := new_ast_writer(64)

	expr := Ident{
		name:     'foo'
		mod:      'main'
		pos:      token.Pos{
			len:     3
			line_nr: 1
		}
		tok_kind: .name
		language: .v
		is_mut:   false
	}
	w.write_expr(expr)

	mut r := new_ast_reader(w.buf)
	read_expr := r.read_expr()

	if read_expr is Ident {
		assert read_expr.name == 'foo'
		assert read_expr.mod == 'main'
		assert read_expr.tok_kind == .name
	} else {
		assert false, 'expected Ident'
	}
}

// Test InfixExpr
fn test_expr_infix() {
	mut w := new_ast_writer(256)

	expr := InfixExpr{
		op:      .plus
		pos:     token.Pos{
			len:     1
			line_nr: 1
		}
		is_stmt: false
		left:    IntegerLiteral{
			val: '1'
			pos: token.Pos{
				len: 1
			}
		}
		right:   IntegerLiteral{
			val: '2'
			pos: token.Pos{
				len: 1
			}
		}
	}
	w.write_expr(expr)

	mut r := new_ast_reader(w.buf)
	read_expr := r.read_expr()

	if read_expr is InfixExpr {
		assert read_expr.op == .plus
		if read_expr.left is IntegerLiteral {
			assert read_expr.left.val == '1'
		}
		if read_expr.right is IntegerLiteral {
			assert read_expr.right.val == '2'
		}
	} else {
		assert false, 'expected InfixExpr'
	}
}

// Test empty statement
fn test_stmt_empty() {
	mut w := new_ast_writer(64)

	stmt := EmptyStmt{
		pos: token.Pos{
			len:     0
			line_nr: 1
		}
	}
	w.write_stmt(stmt)

	mut r := new_ast_reader(w.buf)
	read_stmt := r.read_stmt()

	if read_stmt is EmptyStmt {
		assert read_stmt.pos.line_nr == 1
	} else {
		assert false, 'expected EmptyStmt'
	}
}

// Test Return statement
fn test_stmt_return() {
	mut w := new_ast_writer(128)

	stmt := Return{
		pos:   token.Pos{
			len:     6
			line_nr: 5
		}
		scope: unsafe { nil }
		exprs: [Expr(IntegerLiteral{
			val: '42'
			pos: token.Pos{
				len: 2
			}
		})]
	}
	w.write_stmt(stmt)

	mut r := new_ast_reader(w.buf)
	read_stmt := r.read_stmt()

	if read_stmt is Return {
		assert read_stmt.pos.line_nr == 5
		assert read_stmt.exprs.len == 1
		e := read_stmt.exprs[0]
		if e is IntegerLiteral {
			assert e.val == '42'
		}
	} else {
		assert false, 'expected Return'
	}
}

// Test AssignStmt
fn test_stmt_assign() {
	mut w := new_ast_writer(256)

	stmt := AssignStmt{
		op:    .decl_assign
		pos:   token.Pos{
			len:     2
			line_nr: 1
		}
		left:  [Expr(Ident{
			name: 'x'
			pos:  token.Pos{
				len: 1
			}
		})]
		right: [Expr(IntegerLiteral{
			val: '10'
			pos: token.Pos{
				len: 2
			}
		})]
	}
	w.write_stmt(stmt)

	mut r := new_ast_reader(w.buf)
	read_stmt := r.read_stmt()

	if read_stmt is AssignStmt {
		assert read_stmt.op == .decl_assign
		assert read_stmt.left.len == 1
		assert read_stmt.right.len == 1
		left := read_stmt.left[0]
		if left is Ident {
			assert left.name == 'x'
		}
	} else {
		assert false, 'expected AssignStmt'
	}
}

// Test ExprStmt
fn test_stmt_expr() {
	mut w := new_ast_writer(128)

	stmt := ExprStmt{
		pos:     token.Pos{
			len:     8
			line_nr: 1
		}
		expr:    IntegerLiteral{
			val: '123'
			pos: token.Pos{
				len: 3
			}
		}
		is_expr: false
	}
	w.write_stmt(stmt)

	mut r := new_ast_reader(w.buf)
	read_stmt := r.read_stmt()

	if read_stmt is ExprStmt {
		assert read_stmt.is_expr == false
		if read_stmt.expr is IntegerLiteral {
			assert read_stmt.expr.val == '123'
		}
	} else {
		assert false, 'expected ExprStmt'
	}
}

// Test ForStmt
fn test_stmt_for() {
	mut w := new_ast_writer(256)

	stmt := ForStmt{
		is_inf: true
		pos:    token.Pos{
			len:     3
			line_nr: 10
		}
		cond:   BoolLiteral{
			val: true
			pos: token.Pos{
				len: 4
			}
		}
		stmts:  []
		label:  ''
	}
	w.write_stmt(stmt)

	mut r := new_ast_reader(w.buf)
	read_stmt := r.read_stmt()

	if read_stmt is ForStmt {
		assert read_stmt.is_inf == true
		assert read_stmt.pos.line_nr == 10
	} else {
		assert false, 'expected ForStmt'
	}
}

// Test Block statement
fn test_stmt_block() {
	mut w := new_ast_writer(256)

	stmt := Block{
		is_unsafe: true
		pos:       token.Pos{
			len:     10
			line_nr: 1
		}
		scope:     unsafe { nil }
		stmts:     [
			Stmt(EmptyStmt{
				pos: token.Pos{
					len: 0
				}
			}),
		]
	}
	w.write_stmt(stmt)

	mut r := new_ast_reader(w.buf)
	read_stmt := r.read_stmt()

	if read_stmt is Block {
		assert read_stmt.is_unsafe == true
		assert read_stmt.stmts.len == 1
	} else {
		assert false, 'expected Block'
	}
}

// Test File with statements
fn test_file_with_stmts() {
	file := &File{
		nr_lines:       10
		nr_bytes:       100
		nr_tokens:      50
		is_test:        true
		is_generated:   false
		is_translated:  false
		language:       .v
		mod:            Module{
			name:       'test'
			short_name: 'test'
		}
		imports:        []
		auto_imports:   []
		embedded_files: []
		stmts:          [
			Stmt(ExprStmt{
				pos:     token.Pos{
					len:     5
					line_nr: 1
				}
				expr:    IntegerLiteral{
					val: '42'
					pos: token.Pos{
						len: 2
					}
				}
				is_expr: false
			}),
			Stmt(Return{
				pos:   token.Pos{
					len:     6
					line_nr: 2
				}
				scope: unsafe { nil }
				exprs: []
			}),
		]
	}

	data := serialize_file(file)
	read_file := deserialize_file(data) or {
		assert false, 'deserialize failed: ${err}'
		return
	}

	assert read_file.is_test == true
	assert read_file.mod.name == 'test'
	assert read_file.stmts.len == 2

	stmt0 := read_file.stmts[0]
	if stmt0 is ExprStmt {
		e := stmt0.expr
		if e is IntegerLiteral {
			assert e.val == '42'
		}
	}

	stmt1 := read_file.stmts[1]
	if stmt1 is Return {
		assert stmt1.pos.line_nr == 2
	}
}
