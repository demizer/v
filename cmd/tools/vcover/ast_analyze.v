// ast_analyze.v - AST-based line classification for coverage analysis
module main

import os
import v.ast
import v.parser
import v.pref

// analyze_file parses a V source file and returns line classifications and type information.
// Returns an error if the file cannot be parsed.
fn analyze_file(path string) !AstAnalysis {
	// Read the file to count lines
	content := os.read_file(path) or { return error('cannot read file: ${path}') }
	lines := content.split_into_lines()
	num_lines := lines.len

	// Setup parser
	mut table := ast.new_table()
	mut prefs := pref.new_preferences()
	prefs.is_fmt = true // more permissive parsing

	// Parse the file
	file := parser.parse_file(path, mut table, .skip_comments, prefs)

	// Initialize classifications array (1-indexed, so len = num_lines + 1)
	mut classifications := []LineCoverage{len: num_lines + 1}

	// First pass: mark blank lines and classify based on content
	for i, line in lines {
		line_num := i + 1 // 1-indexed
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			classifications[line_num].line_type = .blank
			classifications[line_num].status = .not_code
		} else if trimmed.starts_with('//') {
			classifications[line_num].line_type = .comment
			classifications[line_num].status = .not_code
		}
	}

	// Collect type declarations and usages
	mut type_decls := []TypeDecl{}
	mut type_usages := []TypeUsage{}

	// Walk the AST to classify statements
	for stmt in file.stmts {
		classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages, table)
	}

	return AstAnalysis{
		num_lines:       num_lines
		classifications: classifications
		type_decls:      type_decls
		type_usages:     type_usages
	}
}

// classify_stmt recursively classifies a statement and its children
fn classify_stmt(stmt ast.Stmt, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, table &ast.Table) {
	match stmt {
		ast.FnDecl {
			classify_fn_decl(stmt, mut classifications, mut type_decls, mut type_usages,
				table)
		}
		ast.ForStmt {
			classify_for_stmt(stmt, mut classifications, mut type_decls, mut type_usages,
				table)
		}
		ast.ForInStmt {
			classify_for_in_stmt(stmt, mut classifications, mut type_decls, mut type_usages,
				table)
		}
		ast.ForCStmt {
			classify_for_c_stmt(stmt, mut classifications, mut type_decls, mut type_usages,
				table)
		}
		ast.StructDecl {
			classify_struct_decl(stmt, mut classifications, mut type_decls)
		}
		ast.EnumDecl {
			classify_enum_decl(stmt, mut classifications, mut type_decls)
		}
		ast.ExprStmt {
			classify_expr_stmt(stmt, mut classifications, mut type_decls, mut type_usages,
				table)
		}
		ast.AssignStmt {
			classify_assign_stmt(stmt, mut classifications, mut type_decls, mut type_usages,
				table)
		}
		ast.Return {
			line := stmt.pos.line_nr + 1
			if line > 0 && line < classifications.len {
				if classifications[line].line_type == .blank {
					classifications[line].line_type = .code
				}
			}
			// Check for type usages in return expressions
			for expr in stmt.exprs {
				collect_type_usages(expr, mut type_usages, table)
			}
		}
		ast.Module {
			line := stmt.pos.line_nr + 1
			if line > 0 && line < classifications.len {
				classifications[line].line_type = .other
				classifications[line].status = .not_code
			}
		}
		ast.Import {
			line := stmt.pos.line_nr + 1
			if line > 0 && line < classifications.len {
				classifications[line].line_type = .other
				classifications[line].status = .not_code
			}
		}
		ast.ConstDecl {
			// Constants are declarations, mark as other (not executable)
			for field in stmt.fields {
				line := field.pos.line_nr + 1
				if line > 0 && line < classifications.len {
					classifications[line].line_type = .other
					classifications[line].status = .not_code
				}
				collect_type_usages(field.expr, mut type_usages, table)
			}
		}
		ast.GlobalDecl {
			for field in stmt.fields {
				line := field.pos.line_nr + 1
				if line > 0 && line < classifications.len {
					classifications[line].line_type = .other
					classifications[line].status = .not_code
				}
			}
		}
		ast.DeferStmt {
			line := stmt.pos.line_nr + 1
			if line > 0 && line < classifications.len {
				if classifications[line].line_type == .blank {
					classifications[line].line_type = .code
				}
			}
			for s in stmt.stmts {
				classify_stmt(s, mut classifications, mut type_decls, mut type_usages,
					table)
			}
		}
		ast.AssertStmt {
			line := stmt.pos.line_nr + 1
			if line > 0 && line < classifications.len {
				if classifications[line].line_type == .blank {
					classifications[line].line_type = .code
				}
			}
			collect_type_usages(stmt.expr, mut type_usages, table)
		}
		ast.Block {
			for s in stmt.stmts {
				classify_stmt(s, mut classifications, mut type_decls, mut type_usages,
					table)
			}
		}
		else {
			// Other statements are code
			line := stmt.pos.line_nr + 1
			if line > 0 && line < classifications.len {
				if classifications[line].line_type == .blank {
					classifications[line].line_type = .code
				}
			}
		}
	}
}

// classify_fn_decl classifies a function declaration
fn classify_fn_decl(fn_decl &ast.FnDecl, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, table &ast.Table) {
	start_line := fn_decl.pos.line_nr + 1

	// Calculate end_line from AST position info first
	mut end_line := if fn_decl.end_pos.last_line > 0 {
		fn_decl.end_pos.last_line + 1
	} else if fn_decl.pos.last_line > 0 {
		fn_decl.pos.last_line + 1
	} else {
		start_line
	}

	// If end_line equals start_line (single-line or fallback), try to calculate from body
	if end_line == start_line && fn_decl.stmts.len > 0 {
		last_stmt := fn_decl.stmts.last()
		stmt_end := last_stmt.pos.last_line + 1
		if stmt_end > start_line {
			end_line = stmt_end + 1 // +1 for closing brace
		}
	}

	// Recursively classify body statements first to detect nested structures
	for stmt in fn_decl.stmts {
		classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages, table)
	}

	// After classifying body, find the actual closing brace line
	// by looking for the first unclassified line after the last body statement
	if fn_decl.stmts.len > 0 {
		last_stmt := fn_decl.stmts.last()
		stmt_end := last_stmt.pos.last_line + 1
		// Scan forward to find the function's closing brace
		for i in (stmt_end + 1) .. classifications.len {
			if classifications[i].line_type == .blank {
				end_line = i
				break
			}
		}
	}

	// Mark signature line(s)
	if start_line > 0 && start_line < classifications.len {
		classifications[start_line].line_type = .fn_signature
		classifications[start_line].block_end = end_line
	}

	// Mark closing brace
	if end_line > 0 && end_line < classifications.len && end_line != start_line {
		classifications[end_line].line_type = .fn_closing_brace
		classifications[end_line].block_start = start_line
	}
}

// classify_for_stmt classifies a for loop
fn classify_for_stmt(for_stmt &ast.ForStmt, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, table &ast.Table) {
	start_line := for_stmt.pos.line_nr + 1

	// Find end line from statements
	mut end_line := start_line
	if for_stmt.stmts.len > 0 {
		last_stmt := for_stmt.stmts.last()
		stmt_end := last_stmt.pos.last_line + 1
		if stmt_end > end_line {
			end_line = stmt_end + 1 // +1 for closing brace
		}
	}

	// Mark header
	if start_line > 0 && start_line < classifications.len {
		classifications[start_line].line_type = .for_header
		classifications[start_line].block_end = end_line
	}

	// Mark closing brace (estimate)
	if end_line > 0 && end_line < classifications.len && end_line != start_line {
		classifications[end_line].line_type = .for_closing_brace
		classifications[end_line].block_start = start_line
	}

	// Check condition for type usages
	collect_type_usages(for_stmt.cond, mut type_usages, table)

	// Recursively classify body
	for stmt in for_stmt.stmts {
		classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages, table)
	}
}

// classify_for_in_stmt classifies a for-in loop
fn classify_for_in_stmt(for_stmt &ast.ForInStmt, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, table &ast.Table) {
	start_line := for_stmt.pos.line_nr + 1

	// Find end line
	mut end_line := start_line
	if for_stmt.stmts.len > 0 {
		last_stmt := for_stmt.stmts.last()
		stmt_end := last_stmt.pos.last_line + 1
		if stmt_end > end_line {
			end_line = stmt_end + 1
		}
	}

	// Mark header
	if start_line > 0 && start_line < classifications.len {
		classifications[start_line].line_type = .for_header
		classifications[start_line].block_end = end_line
	}

	// Mark closing brace
	if end_line > 0 && end_line < classifications.len && end_line != start_line {
		classifications[end_line].line_type = .for_closing_brace
		classifications[end_line].block_start = start_line
	}

	// Check iterator expression for type usages
	collect_type_usages(for_stmt.cond, mut type_usages, table)
	collect_type_usages(for_stmt.high, mut type_usages, table)

	// Recursively classify body
	for stmt in for_stmt.stmts {
		classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages, table)
	}
}

// classify_for_c_stmt classifies a C-style for loop
fn classify_for_c_stmt(for_stmt &ast.ForCStmt, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, table &ast.Table) {
	start_line := for_stmt.pos.line_nr + 1

	// Find end line
	mut end_line := start_line
	if for_stmt.stmts.len > 0 {
		last_stmt := for_stmt.stmts.last()
		stmt_end := last_stmt.pos.last_line + 1
		if stmt_end > end_line {
			end_line = stmt_end + 1
		}
	}

	// Mark header
	if start_line > 0 && start_line < classifications.len {
		classifications[start_line].line_type = .for_header
		classifications[start_line].block_end = end_line
	}

	// Mark closing brace
	if end_line > 0 && end_line < classifications.len && end_line != start_line {
		classifications[end_line].line_type = .for_closing_brace
		classifications[end_line].block_start = start_line
	}

	// Check condition for type usages
	collect_type_usages(for_stmt.cond, mut type_usages, table)

	// Recursively classify body
	for stmt in for_stmt.stmts {
		classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages, table)
	}
}

// classify_struct_decl classifies a struct declaration
fn classify_struct_decl(decl &ast.StructDecl, mut classifications []LineCoverage, mut type_decls []TypeDecl) {
	start_line := decl.pos.line_nr + 1

	// Find end line
	mut end_line := start_line
	if decl.pos.last_line > 0 {
		end_line = decl.pos.last_line + 1
	} else if decl.fields.len > 0 {
		last_field := decl.fields.last()
		end_line = last_field.pos.line_nr + 2 // +1 for closing brace
	}

	// Mark declaration start
	if start_line > 0 && start_line < classifications.len {
		classifications[start_line].line_type = .struct_decl
		classifications[start_line].block_end = end_line
		classifications[start_line].type_name = decl.name
	}

	// Mark field lines
	for field in decl.fields {
		line := field.pos.line_nr + 1
		if line > 0 && line < classifications.len && line != start_line && line != end_line {
			classifications[line].line_type = .struct_field
			classifications[line].type_name = decl.name
		}
	}

	// Mark closing brace
	if end_line > 0 && end_line < classifications.len && end_line != start_line {
		classifications[end_line].line_type = .struct_closing
		classifications[end_line].block_start = start_line
		classifications[end_line].type_name = decl.name
	}

	// Record type declaration
	type_decls << TypeDecl{
		name:       decl.name
		kind:       'struct'
		start_line: start_line
		end_line:   end_line
	}
}

// classify_enum_decl classifies an enum declaration
fn classify_enum_decl(decl &ast.EnumDecl, mut classifications []LineCoverage, mut type_decls []TypeDecl) {
	start_line := decl.pos.line_nr + 1

	// Find end line
	mut end_line := start_line
	if decl.pos.last_line > 0 {
		end_line = decl.pos.last_line + 1
	} else if decl.fields.len > 0 {
		last_field := decl.fields.last()
		end_line = last_field.pos.line_nr + 2
	}

	// Mark declaration start
	if start_line > 0 && start_line < classifications.len {
		classifications[start_line].line_type = .enum_decl
		classifications[start_line].block_end = end_line
		classifications[start_line].type_name = decl.name
	}

	// Mark field lines
	for field in decl.fields {
		line := field.pos.line_nr + 1
		if line > 0 && line < classifications.len && line != start_line && line != end_line {
			classifications[line].line_type = .enum_field
			classifications[line].type_name = decl.name
		}
	}

	// Mark closing brace
	if end_line > 0 && end_line < classifications.len && end_line != start_line {
		classifications[end_line].line_type = .enum_closing
		classifications[end_line].block_start = start_line
		classifications[end_line].type_name = decl.name
	}

	// Record type declaration
	type_decls << TypeDecl{
		name:       decl.name
		kind:       'enum'
		start_line: start_line
		end_line:   end_line
	}
}

// classify_expr_stmt classifies an expression statement (which may contain if/match expressions)
fn classify_expr_stmt(stmt &ast.ExprStmt, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, table &ast.Table) {
	line := stmt.pos.line_nr + 1

	match stmt.expr {
		ast.IfExpr {
			classify_if_expr(stmt.expr, mut classifications, mut type_decls, mut type_usages,
				table)
		}
		ast.MatchExpr {
			classify_match_expr(stmt.expr, mut classifications, mut type_decls, mut type_usages,
				table)
		}
		else {
			// Regular expression statement
			if line > 0 && line < classifications.len {
				if classifications[line].line_type == .blank {
					classifications[line].line_type = .code
				}
			}
			collect_type_usages(stmt.expr, mut type_usages, table)
		}
	}
}

// classify_assign_stmt classifies an assignment statement
fn classify_assign_stmt(stmt &ast.AssignStmt, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, table &ast.Table) {
	line := stmt.pos.line_nr + 1
	if line > 0 && line < classifications.len {
		if classifications[line].line_type == .blank {
			classifications[line].line_type = .code
		}
	}

	// Check right-hand side for type usages
	for expr in stmt.right {
		collect_type_usages(expr, mut type_usages, table)
	}
}

// classify_if_expr classifies an if expression and its branches
fn classify_if_expr(if_expr &ast.IfExpr, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, table &ast.Table) {
	for i, branch in if_expr.branches {
		branch_line := branch.pos.line_nr + 1

		// Find end line of branch
		mut end_line := branch_line
		if branch.stmts.len > 0 {
			last_stmt := branch.stmts.last()
			stmt_end := last_stmt.pos.last_line + 1
			if stmt_end > end_line {
				end_line = stmt_end + 1
			}
		}

		// Determine if this is an if or else branch
		if branch_line > 0 && branch_line < classifications.len {
			if i == 0 {
				classifications[branch_line].line_type = .if_header
			} else if branch.cond is ast.EmptyExpr {
				// This is an else branch (no condition)
				classifications[branch_line].line_type = .else_header
			} else {
				// This is an else if branch
				classifications[branch_line].line_type = .if_header
			}
			classifications[branch_line].block_end = end_line
		}

		// Mark closing brace (if not same line)
		if end_line > 0 && end_line < classifications.len && end_line != branch_line {
			if classifications[end_line].line_type == .blank {
				classifications[end_line].line_type = .if_closing_brace
				classifications[end_line].block_start = branch_line
			}
		}

		// Check condition for type usages
		collect_type_usages(branch.cond, mut type_usages, table)

		// Classify body statements
		for stmt in branch.stmts {
			classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages,
				table)
		}
	}
}

// classify_match_expr classifies a match expression and its branches
fn classify_match_expr(match_expr &ast.MatchExpr, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, table &ast.Table) {
	start_line := match_expr.pos.line_nr + 1

	// Check matched expression for type usages
	collect_type_usages(match_expr.cond, mut type_usages, table)

	// Track the last arm's closing brace line to find the match closing brace
	mut last_arm_end := start_line

	// Classify each branch
	for branch in match_expr.branches {
		branch_line := branch.pos.line_nr + 1

		// Find end line of this arm
		mut arm_end := branch_line
		if branch.stmts.len > 0 {
			last_stmt := branch.stmts.last()
			stmt_end := last_stmt.pos.last_line + 1
			if stmt_end > arm_end {
				arm_end = stmt_end + 1 // +1 for closing brace
			}
		}

		// Track the furthest arm end
		if arm_end > last_arm_end {
			last_arm_end = arm_end
		}

		// Mark branch arm header
		if branch_line > 0 && branch_line < classifications.len {
			classifications[branch_line].line_type = .match_arm
			classifications[branch_line].block_end = arm_end
		}

		// Mark arm closing brace
		if arm_end > 0 && arm_end < classifications.len && arm_end != branch_line {
			classifications[arm_end].line_type = .match_arm_closing
			classifications[arm_end].block_start = branch_line
		}

		// Check branch expressions for type usages
		for expr in branch.exprs {
			collect_type_usages(expr, mut type_usages, table)
		}

		// Classify body statements
		for stmt in branch.stmts {
			classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages,
				table)
		}
	}

	// Match closing brace is one line after the last arm's closing brace
	end_line := last_arm_end + 1

	// Mark match header with correct end_line
	if start_line > 0 && start_line < classifications.len {
		classifications[start_line].line_type = .match_header
		classifications[start_line].block_end = end_line
	}

	// Mark match closing brace
	if end_line > 0 && end_line < classifications.len && end_line != start_line {
		classifications[end_line].line_type = .match_closing_brace
		classifications[end_line].block_start = start_line
	}
}

// collect_type_usages walks an expression and collects struct instantiations and enum value usages
fn collect_type_usages(expr ast.Expr, mut type_usages []TypeUsage, table &ast.Table) {
	match expr {
		ast.StructInit {
			// Get type name from the table
			sym := table.sym(expr.typ)
			type_usages << TypeUsage{
				type_name: sym.name
				line:      expr.pos.line_nr + 1
			}
			// Also check field values for type usages
			for field in expr.init_fields {
				collect_type_usages(field.expr, mut type_usages, table)
			}
		}
		ast.EnumVal {
			type_usages << TypeUsage{
				type_name: expr.enum_name
				line:      expr.pos.line_nr + 1
			}
		}
		ast.CallExpr {
			// Check arguments for type usages
			for arg in expr.args {
				collect_type_usages(arg.expr, mut type_usages, table)
			}
			// Check the call target
			collect_type_usages(expr.left, mut type_usages, table)
		}
		ast.InfixExpr {
			collect_type_usages(expr.left, mut type_usages, table)
			collect_type_usages(expr.right, mut type_usages, table)
		}
		ast.PrefixExpr {
			collect_type_usages(expr.right, mut type_usages, table)
		}
		ast.IndexExpr {
			collect_type_usages(expr.left, mut type_usages, table)
			collect_type_usages(expr.index, mut type_usages, table)
		}
		ast.SelectorExpr {
			collect_type_usages(expr.expr, mut type_usages, table)
		}
		ast.ArrayInit {
			for elem in expr.exprs {
				collect_type_usages(elem, mut type_usages, table)
			}
			collect_type_usages(expr.len_expr, mut type_usages, table)
			collect_type_usages(expr.cap_expr, mut type_usages, table)
			collect_type_usages(expr.init_expr, mut type_usages, table)
		}
		ast.MapInit {
			for key in expr.keys {
				collect_type_usages(key, mut type_usages, table)
			}
			for val in expr.vals {
				collect_type_usages(val, mut type_usages, table)
			}
		}
		ast.CastExpr {
			collect_type_usages(expr.expr, mut type_usages, table)
		}
		ast.IfExpr {
			for branch in expr.branches {
				collect_type_usages(branch.cond, mut type_usages, table)
			}
		}
		ast.MatchExpr {
			collect_type_usages(expr.cond, mut type_usages, table)
			for branch in expr.branches {
				for e in branch.exprs {
					collect_type_usages(e, mut type_usages, table)
				}
			}
		}
		ast.ParExpr {
			collect_type_usages(expr.expr, mut type_usages, table)
		}
		ast.UnsafeExpr {
			collect_type_usages(expr.expr, mut type_usages, table)
		}
		ast.OrExpr {
			// or blocks
		}
		else {}
	}
}
