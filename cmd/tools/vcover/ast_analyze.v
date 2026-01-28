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
	mut field_usages := []FieldUsage{}

	// Walk the AST to classify statements
	for stmt in file.stmts {
		classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages, mut
			field_usages, table)
	}

	// Second pass: collect field usages with variable type tracking
	// Build struct field type lookup from type_decls
	mut struct_fields := map[string]map[string]string{} // struct_name -> (field_name -> field_type)
	for decl in type_decls {
		if decl.kind == 'struct' {
			struct_fields[decl.name] = decl.field_type_map.clone()
		}
	}

	// Walk function bodies again to track variable types and collect field usages
	for stmt in file.stmts {
		if stmt is ast.FnDecl {
			mut var_types := map[string]string{} // variable_name -> struct_type
			collect_field_usages_in_fn(stmt, struct_fields, mut var_types, mut field_usages,
				table)
		}
	}

	return AstAnalysis{
		num_lines:       num_lines
		classifications: classifications
		type_decls:      type_decls
		type_usages:     type_usages
		field_usages:    field_usages
	}
}

// classify_stmt recursively classifies a statement and its children
fn classify_stmt(stmt ast.Stmt, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, mut field_usages []FieldUsage, table &ast.Table) {
	match stmt {
		ast.FnDecl {
			classify_fn_decl(stmt, mut classifications, mut type_decls, mut type_usages, mut
				field_usages, table)
		}
		ast.ForStmt {
			classify_for_stmt(stmt, mut classifications, mut type_decls, mut type_usages, mut
				field_usages, table)
		}
		ast.ForInStmt {
			classify_for_in_stmt(stmt, mut classifications, mut type_decls, mut type_usages, mut
				field_usages, table)
		}
		ast.ForCStmt {
			classify_for_c_stmt(stmt, mut classifications, mut type_decls, mut type_usages, mut
				field_usages, table)
		}
		ast.StructDecl {
			classify_struct_decl(stmt, mut classifications, mut type_decls, mut type_usages,
				table)
		}
		ast.EnumDecl {
			classify_enum_decl(stmt, mut classifications, mut type_decls)
		}
		ast.ExprStmt {
			classify_expr_stmt(stmt, mut classifications, mut type_decls, mut type_usages, mut
				field_usages, table)
		}
		ast.AssignStmt {
			classify_assign_stmt(stmt, mut classifications, mut type_decls, mut type_usages, mut
				field_usages, table)
		}
		ast.Return {
			line := stmt.pos.line_nr + 1
			if line > 0 && line < classifications.len {
				if classifications[line].line_type == .blank {
					classifications[line].line_type = .code
				}
			}
			// Check for match/if/call expressions in return and classify their branches
			for expr in stmt.exprs {
				match expr {
					ast.MatchExpr {
						classify_match_expr(expr, mut classifications, mut type_decls, mut
							type_usages, mut field_usages, table)
					}
					ast.IfExpr {
						classify_if_expr(expr, mut classifications, mut type_decls, mut
							type_usages, mut field_usages, table)
					}
					ast.CallExpr {
						classify_call_expr(expr, mut classifications, mut type_decls, mut
							type_usages, mut field_usages, table)
					}
					else {
						collect_type_usages(expr, mut type_usages, mut field_usages, table)
					}
				}
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
				collect_type_usages(field.expr, mut type_usages, mut field_usages, table)
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
				classify_stmt(s, mut classifications, mut type_decls, mut type_usages, mut
					field_usages, table)
			}
		}
		ast.AssertStmt {
			line := stmt.pos.line_nr + 1
			if line > 0 && line < classifications.len {
				if classifications[line].line_type == .blank {
					classifications[line].line_type = .code
				}
			}
			collect_type_usages(stmt.expr, mut type_usages, mut field_usages, table)
		}
		ast.Block {
			for s in stmt.stmts {
				classify_stmt(s, mut classifications, mut type_decls, mut type_usages, mut
					field_usages, table)
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
fn classify_fn_decl(fn_decl &ast.FnDecl, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, mut field_usages []FieldUsage, table &ast.Table) {
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
		classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages, mut
			field_usages, table)
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
fn classify_for_stmt(for_stmt &ast.ForStmt, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, mut field_usages []FieldUsage, table &ast.Table) {
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
	collect_type_usages(for_stmt.cond, mut type_usages, mut field_usages, table)

	// Recursively classify body
	for stmt in for_stmt.stmts {
		classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages, mut
			field_usages, table)
	}
}

// classify_for_in_stmt classifies a for-in loop
fn classify_for_in_stmt(for_stmt &ast.ForInStmt, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, mut field_usages []FieldUsage, table &ast.Table) {
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
	collect_type_usages(for_stmt.cond, mut type_usages, mut field_usages, table)
	collect_type_usages(for_stmt.high, mut type_usages, mut field_usages, table)

	// Recursively classify body
	for stmt in for_stmt.stmts {
		classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages, mut
			field_usages, table)
	}
}

// classify_for_c_stmt classifies a C-style for loop
fn classify_for_c_stmt(for_stmt &ast.ForCStmt, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, mut field_usages []FieldUsage, table &ast.Table) {
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
	collect_type_usages(for_stmt.cond, mut type_usages, mut field_usages, table)

	// Recursively classify body
	for stmt in for_stmt.stmts {
		classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages, mut
			field_usages, table)
	}
}

// classify_struct_decl classifies a struct declaration
fn classify_struct_decl(decl &ast.StructDecl, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, table &ast.Table) {
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

	// Track field types and field lines
	mut field_types := []string{}
	mut fields := map[string]int{}
	mut field_type_map := map[string]string{}

	// Mark field lines
	for field in decl.fields {
		line := field.pos.line_nr + 1
		if line > 0 && line < classifications.len && line != start_line && line != end_line {
			classifications[line].line_type = .struct_field
			classifications[line].type_name = decl.name
		}
		// Track field name -> line mapping
		fields[field.name] = line
		// Track field type if it's a struct/enum
		add_type_usage_if_struct(field.typ, line, mut type_usages, mut field_types, table)
		// Track field name -> type name for chained access tracking
		if field.typ != 0 {
			sym := table.sym(field.typ)
			if sym.kind == .struct || sym.kind == .enum {
				field_type_map[field.name] = sym.name
			}
		}
	}

	// Mark closing brace
	if end_line > 0 && end_line < classifications.len && end_line != start_line {
		classifications[end_line].line_type = .struct_closing
		classifications[end_line].block_start = start_line
		classifications[end_line].type_name = decl.name
	}

	// Record type declaration with field info
	type_decls << TypeDecl{
		name:           decl.name
		kind:           'struct'
		start_line:     start_line
		end_line:       end_line
		field_types:    field_types
		fields:         fields
		field_type_map: field_type_map
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
fn classify_expr_stmt(stmt &ast.ExprStmt, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, mut field_usages []FieldUsage, table &ast.Table) {
	line := stmt.pos.line_nr + 1

	match stmt.expr {
		ast.IfExpr {
			classify_if_expr(stmt.expr, mut classifications, mut type_decls, mut type_usages, mut
				field_usages, table)
		}
		ast.MatchExpr {
			classify_match_expr(stmt.expr, mut classifications, mut type_decls, mut type_usages, mut
				field_usages, table)
		}
		ast.CallExpr {
			// Mark the call line as code
			if line > 0 && line < classifications.len {
				if classifications[line].line_type == .blank {
					classifications[line].line_type = .code
				}
			}
			classify_call_expr(stmt.expr, mut classifications, mut type_decls, mut type_usages, mut
				field_usages, table)
		}
		else {
			// Regular expression statement
			if line > 0 && line < classifications.len {
				if classifications[line].line_type == .blank {
					classifications[line].line_type = .code
				}
			}
			collect_type_usages(stmt.expr, mut type_usages, mut field_usages, table)
		}
	}
}

// classify_assign_stmt classifies an assignment statement
fn classify_assign_stmt(stmt &ast.AssignStmt, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, mut field_usages []FieldUsage, table &ast.Table) {
	line := stmt.pos.line_nr + 1
	if line > 0 && line < classifications.len {
		if classifications[line].line_type == .blank {
			classifications[line].line_type = .code
		}
	}

	// Check right-hand side for match/if/call expressions and classify their branches
	for expr in stmt.right {
		match expr {
			ast.MatchExpr {
				classify_match_expr(expr, mut classifications, mut type_decls, mut type_usages, mut
					field_usages, table)
			}
			ast.IfExpr {
				classify_if_expr(expr, mut classifications, mut type_decls, mut type_usages, mut
					field_usages, table)
			}
			ast.CallExpr {
				classify_call_expr(expr, mut classifications, mut type_decls, mut type_usages, mut
					field_usages, table)
			}
			else {
				collect_type_usages(expr, mut type_usages, mut field_usages, table)
			}
		}
	}
}

// classify_if_expr classifies an if expression and its branches
fn classify_if_expr(if_expr &ast.IfExpr, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, mut field_usages []FieldUsage, table &ast.Table) {
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
		collect_type_usages(branch.cond, mut type_usages, mut field_usages, table)

		// Classify body statements
		for stmt in branch.stmts {
			classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages, mut
				field_usages, table)
		}
	}
}

// classify_match_expr classifies a match expression and its branches
fn classify_match_expr(match_expr &ast.MatchExpr, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, mut field_usages []FieldUsage, table &ast.Table) {
	start_line := match_expr.pos.line_nr + 1

	// Check matched expression for type usages
	collect_type_usages(match_expr.cond, mut type_usages, mut field_usages, table)

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
			collect_type_usages(expr, mut type_usages, mut field_usages, table)
		}

		// Classify body statements
		for stmt in branch.stmts {
			classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages, mut
				field_usages, table)
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

// classify_call_expr classifies a call expression's or_block statements
fn classify_call_expr(call_expr &ast.CallExpr, mut classifications []LineCoverage, mut type_decls []TypeDecl, mut type_usages []TypeUsage, mut field_usages []FieldUsage, table &ast.Table) {
	// Collect type usages from arguments
	for arg in call_expr.args {
		collect_type_usages(arg.expr, mut type_usages, mut field_usages, table)
	}

	// Classify statements inside or_block
	if call_expr.or_block.stmts.len > 0 {
		for stmt in call_expr.or_block.stmts {
			classify_stmt(stmt, mut classifications, mut type_decls, mut type_usages, mut
				field_usages, table)
		}
	}
}

// add_type_usage_if_struct extracts struct/enum type from an ast.Type and adds it to usages
fn add_type_usage_if_struct(typ ast.Type, line int, mut type_usages []TypeUsage, mut field_types []string, table &ast.Table) {
	if typ == 0 {
		return
	}
	sym := table.sym(typ)
	// Only track struct and enum types (not built-in types)
	if sym.kind == .struct || sym.kind == .enum {
		type_usages << TypeUsage{
			type_name: sym.name
			line:      line
		}
		// Also track as field type if we're tracking field types
		if sym.name !in field_types {
			field_types << sym.name
		}
	}
}

// collect_type_usages walks an expression and collects struct instantiations and enum value usages
fn collect_type_usages(expr ast.Expr, mut type_usages []TypeUsage, mut field_usages []FieldUsage, table &ast.Table) {
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
				collect_type_usages(field.expr, mut type_usages, mut field_usages, table)
			}
		}
		ast.EnumVal {
			type_usages << TypeUsage{
				type_name: expr.enum_name
				line:      expr.pos.line_nr + 1
			}
		}
		ast.CallExpr {
			line := expr.pos.line_nr + 1
			// Check arguments for type usages
			for arg in expr.args {
				collect_type_usages(arg.expr, mut type_usages, mut field_usages, table)
				// Also check the resolved type of each argument
				mut dummy := []string{}
				add_type_usage_if_struct(arg.typ, line, mut type_usages, mut dummy, table)
			}
			// Check expected argument types (for generics like json.decode(T, ...))
			for expected_type in expr.expected_arg_types {
				mut dummy := []string{}
				add_type_usage_if_struct(expected_type, line, mut type_usages, mut dummy,
					table)
			}
			// Check return type
			mut dummy := []string{}
			add_type_usage_if_struct(expr.return_type, line, mut type_usages, mut dummy,
				table)
			// Check the call target
			collect_type_usages(expr.left, mut type_usages, mut field_usages, table)
		}
		ast.InfixExpr {
			collect_type_usages(expr.left, mut type_usages, mut field_usages, table)
			collect_type_usages(expr.right, mut type_usages, mut field_usages, table)
		}
		ast.PrefixExpr {
			collect_type_usages(expr.right, mut type_usages, mut field_usages, table)
		}
		ast.IndexExpr {
			collect_type_usages(expr.left, mut type_usages, mut field_usages, table)
			collect_type_usages(expr.index, mut type_usages, mut field_usages, table)
		}
		ast.SelectorExpr {
			// Track field access (check if type is valid first)
			if expr.expr_type != 0 {
				sym := table.sym(expr.expr_type)
				if sym.kind == .struct {
					field_usages << FieldUsage{
						struct_name: sym.name
						field_name:  expr.field_name
						line:        expr.pos.line_nr + 1
					}
				}
			}
			collect_type_usages(expr.expr, mut type_usages, mut field_usages, table)
		}
		ast.ArrayInit {
			for elem in expr.exprs {
				collect_type_usages(elem, mut type_usages, mut field_usages, table)
			}
			collect_type_usages(expr.len_expr, mut type_usages, mut field_usages, table)
			collect_type_usages(expr.cap_expr, mut type_usages, mut field_usages, table)
			collect_type_usages(expr.init_expr, mut type_usages, mut field_usages, table)
		}
		ast.MapInit {
			for key in expr.keys {
				collect_type_usages(key, mut type_usages, mut field_usages, table)
			}
			for val in expr.vals {
				collect_type_usages(val, mut type_usages, mut field_usages, table)
			}
		}
		ast.CastExpr {
			// Track the target type of the cast
			line := expr.pos.line_nr + 1
			mut dummy := []string{}
			add_type_usage_if_struct(expr.typ, line, mut type_usages, mut dummy, table)
			collect_type_usages(expr.expr, mut type_usages, mut field_usages, table)
		}
		ast.IfExpr {
			for branch in expr.branches {
				collect_type_usages(branch.cond, mut type_usages, mut field_usages, table)
			}
		}
		ast.MatchExpr {
			collect_type_usages(expr.cond, mut type_usages, mut field_usages, table)
			for branch in expr.branches {
				for e in branch.exprs {
					collect_type_usages(e, mut type_usages, mut field_usages, table)
				}
			}
		}
		ast.ParExpr {
			collect_type_usages(expr.expr, mut type_usages, mut field_usages, table)
		}
		ast.UnsafeExpr {
			collect_type_usages(expr.expr, mut type_usages, mut field_usages, table)
		}
		ast.OrExpr {
			// or blocks
		}
		else {}
	}
}

// collect_field_usages_in_fn walks a function body to collect field usages with variable type tracking
fn collect_field_usages_in_fn(fn_decl &ast.FnDecl, struct_fields map[string]map[string]string, mut var_types map[string]string, mut field_usages []FieldUsage, table &ast.Table) {
	// Record function parameter types
	for param in fn_decl.params {
		if param.typ != 0 {
			sym := table.sym(param.typ)
			if sym.kind == .struct {
				var_types[param.name] = sym.name
			}
		}
	}

	// Walk function body
	for stmt in fn_decl.stmts {
		collect_field_usages_in_stmt(stmt, struct_fields, mut var_types, mut field_usages,
			table)
	}
}

// collect_field_usages_in_stmt walks a statement to collect field usages
fn collect_field_usages_in_stmt(stmt ast.Stmt, struct_fields map[string]map[string]string, mut var_types map[string]string, mut field_usages []FieldUsage, table &ast.Table) {
	match stmt {
		ast.AssignStmt {
			// Check for struct initialization: x := StructName{...}
			for i, right in stmt.right {
				if right is ast.StructInit {
					if i < stmt.left.len {
						left := stmt.left[i]
						if left is ast.Ident {
							// Record variable type
							sym := table.sym(right.typ)
							if sym.kind == .struct {
								var_types[left.name] = sym.name
							}
						}
					}
				}
				// Collect field usages in the expression
				collect_field_usages_in_expr(right, struct_fields, var_types, mut field_usages,
					table)
			}
		}
		ast.ExprStmt {
			collect_field_usages_in_expr(stmt.expr, struct_fields, var_types, mut field_usages,
				table)
		}
		ast.Return {
			for expr in stmt.exprs {
				collect_field_usages_in_expr(expr, struct_fields, var_types, mut field_usages,
					table)
			}
		}
		ast.ForStmt {
			collect_field_usages_in_expr(stmt.cond, struct_fields, var_types, mut field_usages,
				table)
			for s in stmt.stmts {
				collect_field_usages_in_stmt(s, struct_fields, mut var_types, mut field_usages,
					table)
			}
		}
		ast.ForInStmt {
			collect_field_usages_in_expr(stmt.cond, struct_fields, var_types, mut field_usages,
				table)
			for s in stmt.stmts {
				collect_field_usages_in_stmt(s, struct_fields, mut var_types, mut field_usages,
					table)
			}
		}
		ast.ForCStmt {
			for s in stmt.stmts {
				collect_field_usages_in_stmt(s, struct_fields, mut var_types, mut field_usages,
					table)
			}
		}
		else {}
	}
}

// collect_field_usages_in_expr walks an expression to collect field usages
fn collect_field_usages_in_expr(expr ast.Expr, struct_fields map[string]map[string]string, var_types map[string]string, mut field_usages []FieldUsage, table &ast.Table) {
	match expr {
		ast.SelectorExpr {
			// Try to resolve the struct type of the base expression
			struct_type := resolve_selector_struct_type(expr, struct_fields, var_types,
				table)
			if struct_type != '' {
				field_usages << FieldUsage{
					struct_name: struct_type
					field_name:  expr.field_name
					line:        expr.pos.line_nr + 1
				}
			}
			// Recurse into the base expression
			collect_field_usages_in_expr(expr.expr, struct_fields, var_types, mut field_usages,
				table)
		}
		ast.CallExpr {
			for arg in expr.args {
				collect_field_usages_in_expr(arg.expr, struct_fields, var_types, mut field_usages,
					table)
			}
			// Check or_block
			for s in expr.or_block.stmts {
				// Create a mutable copy for the or block scope
				mut or_var_types := var_types.clone()
				collect_field_usages_in_stmt(s, struct_fields, mut or_var_types, mut field_usages,
					table)
			}
		}
		ast.InfixExpr {
			collect_field_usages_in_expr(expr.left, struct_fields, var_types, mut field_usages,
				table)
			collect_field_usages_in_expr(expr.right, struct_fields, var_types, mut field_usages,
				table)
		}
		ast.PrefixExpr {
			collect_field_usages_in_expr(expr.right, struct_fields, var_types, mut field_usages,
				table)
		}
		ast.IndexExpr {
			collect_field_usages_in_expr(expr.left, struct_fields, var_types, mut field_usages,
				table)
			collect_field_usages_in_expr(expr.index, struct_fields, var_types, mut field_usages,
				table)
		}
		ast.IfExpr {
			for branch in expr.branches {
				collect_field_usages_in_expr(branch.cond, struct_fields, var_types, mut
					field_usages, table)
				for s in branch.stmts {
					mut branch_var_types := var_types.clone()
					collect_field_usages_in_stmt(s, struct_fields, mut branch_var_types, mut
						field_usages, table)
				}
			}
		}
		ast.MatchExpr {
			collect_field_usages_in_expr(expr.cond, struct_fields, var_types, mut field_usages,
				table)
			for branch in expr.branches {
				for s in branch.stmts {
					mut branch_var_types := var_types.clone()
					collect_field_usages_in_stmt(s, struct_fields, mut branch_var_types, mut
						field_usages, table)
				}
			}
		}
		ast.StructInit {
			for field in expr.init_fields {
				collect_field_usages_in_expr(field.expr, struct_fields, var_types, mut
					field_usages, table)
			}
		}
		ast.ArrayInit {
			for elem in expr.exprs {
				collect_field_usages_in_expr(elem, struct_fields, var_types, mut field_usages,
					table)
			}
		}
		ast.ParExpr {
			collect_field_usages_in_expr(expr.expr, struct_fields, var_types, mut field_usages,
				table)
		}
		ast.CastExpr {
			collect_field_usages_in_expr(expr.expr, struct_fields, var_types, mut field_usages,
				table)
		}
		else {}
	}
}

// resolve_selector_struct_type tries to determine the struct type being accessed in a SelectorExpr
fn resolve_selector_struct_type(expr &ast.SelectorExpr, struct_fields map[string]map[string]string, var_types map[string]string, table &ast.Table) string {
	// First check if expr_type is available (from semantic analysis)
	if expr.expr_type != 0 {
		sym := table.sym(expr.expr_type)
		if sym.kind == .struct {
			return sym.name
		}
	}

	// Otherwise, try to resolve from our tracked variable types
	base_expr := expr.expr
	match base_expr {
		ast.Ident {
			// Direct variable access: x.field
			if var_type := var_types[base_expr.name] {
				return var_type
			}
		}
		ast.SelectorExpr {
			// Chained access: x.inner.field
			// First resolve the type of x.inner
			parent_type := resolve_selector_struct_type(base_expr, struct_fields, var_types,
				table)
			if parent_type != '' {
				// Look up the field type in the parent struct
				if fields := struct_fields[parent_type] {
					if field_type := fields[base_expr.field_name] {
						return field_type
					}
				}
			}
		}
		else {}
	}
	return ''
}
