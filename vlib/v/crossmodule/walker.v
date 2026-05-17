// Copyright (c) 2026 Jesus Alvarez. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module crossmodule

import v.ast

struct Walker {
	table &ast.Table
mut:
	result  &ast.CrossModuleInfo
	cur_mod string // current module being walked
}

fn (mut w Walker) walk_file(file &ast.File) {
	w.cur_mod = file.mod.name
	for stmt in file.stmts {
		w.stmt(stmt)
	}
}

fn (mut w Walker) stmt(stmt ast.Stmt) {
	match stmt {
		ast.FnDecl {
			w.stmts(stmt.stmts)
		}
		ast.Block {
			w.stmts(stmt.stmts)
		}
		ast.ExprStmt {
			w.expr(stmt.expr)
		}
		ast.AssignStmt {
			w.exprs(stmt.left)
			w.exprs(stmt.right)
		}
		ast.Return {
			w.exprs(stmt.exprs)
		}
		ast.ForStmt {
			if !stmt.is_inf {
				w.expr(stmt.cond)
			}
			w.stmts(stmt.stmts)
		}
		ast.ForInStmt {
			w.expr(stmt.cond)
			w.expr(stmt.high)
			w.stmts(stmt.stmts)
		}
		ast.ForCStmt {
			if stmt.has_init {
				w.stmt(stmt.init)
			}
			if stmt.has_cond {
				w.expr(stmt.cond)
			}
			if stmt.has_inc {
				w.stmt(stmt.inc)
			}
			w.stmts(stmt.stmts)
		}
		ast.DeferStmt {
			w.stmts(stmt.stmts)
		}
		ast.ComptimeFor {
			w.stmts(stmt.stmts)
		}
		ast.ConstDecl {
			for field in stmt.fields {
				w.expr(field.expr)
			}
		}
		ast.GlobalDecl {
			for field in stmt.fields {
				if field.has_expr {
					w.expr(field.expr)
				}
			}
		}
		ast.AssertStmt {
			w.expr(stmt.expr)
		}
		else {}
	}
}

fn (mut w Walker) stmts(stmts []ast.Stmt) {
	for stmt in stmts {
		w.stmt(stmt)
	}
}

fn (mut w Walker) expr(expr ast.Expr) {
	match expr {
		ast.CallExpr {
			w.call_expr(expr)
			// Also walk arguments
			for arg in expr.args {
				w.expr(arg.expr)
			}
			w.expr(expr.left)
			w.expr(expr.or_block)
		}
		ast.AnonFn {
			w.stmts(expr.decl.stmts)
		}
		ast.ArrayInit {
			w.expr(expr.len_expr)
			w.expr(expr.cap_expr)
			w.expr(expr.init_expr)
			w.exprs(expr.exprs)
		}
		ast.Assoc {
			w.exprs(expr.exprs)
		}
		ast.ArrayDecompose {
			w.expr(expr.expr)
		}
		ast.CastExpr {
			w.expr(expr.expr)
			w.expr(expr.arg)
		}
		ast.ChanInit {
			w.expr(expr.cap_expr)
		}
		ast.ComptimeCall {
			w.expr(expr.left)
			for arg in expr.args {
				w.expr(arg.expr)
			}
		}
		ast.ComptimeSelector {
			w.expr(expr.left)
			w.expr(expr.field_expr)
		}
		ast.ConcatExpr {
			w.exprs(expr.vals)
		}
		ast.DumpExpr {
			w.expr(expr.expr)
		}
		ast.GoExpr {
			w.expr(expr.call_expr)
		}
		ast.SpawnExpr {
			w.expr(expr.call_expr)
		}
		ast.IfExpr {
			w.expr(expr.left)
			for branch in expr.branches {
				w.expr(branch.cond)
				w.stmts(branch.stmts)
			}
		}
		ast.IfGuardExpr {
			w.expr(expr.expr)
		}
		ast.IndexExpr {
			w.expr(expr.left)
			w.expr(expr.index)
			w.expr(expr.or_expr)
		}
		ast.InfixExpr {
			w.expr(expr.left)
			w.expr(expr.right)
			w.expr(expr.or_block)
		}
		ast.Likely {
			w.expr(expr.expr)
		}
		ast.LockExpr {
			w.stmts(expr.stmts)
		}
		ast.MapInit {
			w.exprs(expr.keys)
			w.exprs(expr.vals)
			if expr.has_update_expr {
				w.expr(expr.update_expr)
			}
		}
		ast.MatchExpr {
			w.expr(expr.cond)
			for branch in expr.branches {
				w.exprs(branch.exprs)
				w.stmts(branch.stmts)
			}
		}
		ast.OrExpr {
			w.stmts(expr.stmts)
		}
		ast.ParExpr {
			w.expr(expr.expr)
		}
		ast.PostfixExpr {
			w.expr(expr.expr)
		}
		ast.PrefixExpr {
			w.expr(expr.right)
		}
		ast.RangeExpr {
			if expr.has_low {
				w.expr(expr.low)
			}
			if expr.has_high {
				w.expr(expr.high)
			}
		}
		ast.SelectExpr {
			for branch in expr.branches {
				w.stmt(branch.stmt)
				w.stmts(branch.stmts)
			}
		}
		ast.SelectorExpr {
			w.expr(expr.expr)
			w.expr(expr.or_block)
		}
		ast.SizeOf, ast.IsRefType {
			w.expr(expr.expr)
		}
		ast.SqlExpr {
			w.expr(expr.db_expr)
			w.expr(expr.where_expr)
			w.expr(expr.order_expr)
			w.expr(expr.limit_expr)
			w.expr(expr.offset_expr)
		}
		ast.StringInterLiteral {
			w.exprs(expr.exprs)
		}
		ast.StructInit {
			if expr.has_update_expr {
				w.expr(expr.update_expr)
			}
			for field in expr.init_fields {
				w.expr(field.expr)
			}
		}
		ast.TypeOf {
			w.expr(expr.expr)
		}
		ast.UnsafeExpr {
			w.expr(expr.expr)
		}
		ast.LambdaExpr {
			w.expr(expr.func)
		}
		ast.Ident {
			// Check if this is a function reference passed as value
			if expr.kind == .function {
				w.check_fn_reference(expr)
			}
		}
		else {}
	}
}

fn (mut w Walker) exprs(exprs []ast.Expr) {
	for expr in exprs {
		w.expr(expr)
	}
}

fn (mut w Walker) call_expr(node ast.CallExpr) {
	// Determine the callee's module
	callee_mod := w.get_callee_module(node)

	// If calling into a different module, mark as extern
	if callee_mod != w.cur_mod && callee_mod.len > 0 {
		fkey := node.fkey()
		if fkey.len > 0 {
			w.result.extern_fns[fkey] = true
		}
	}
}

fn (mut w Walker) get_callee_module(node ast.CallExpr) string {
	if node.is_method && node.receiver_type != 0 {
		// For methods, get module from receiver type
		sym := w.table.sym(node.receiver_type)
		return sym.mod
	}
	// For regular functions, use the mod field
	return node.mod
}

fn (mut w Walker) check_fn_reference(ident ast.Ident) {
	// Function passed as value (e.g., callback) - may be called from anywhere
	// Extract module from function name
	if ident.name.contains('.') {
		parts := ident.name.split('.')
		if parts.len >= 2 {
			fn_mod := parts[0..parts.len - 1].join('.')
			if fn_mod != w.cur_mod && fn_mod.len > 0 {
				// Mark as extern since it's being passed to another module
				w.result.extern_fns[ident.name] = true
			}
		}
	}
}
