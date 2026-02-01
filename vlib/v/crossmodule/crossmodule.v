// Copyright (c) 2026 Jesus Alvarez. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module crossmodule

import v.ast

// analyze walks the AST and identifies functions called across module boundaries.
// This is used by -local-cache to determine which functions need extern vs static linkage.
pub fn analyze(table &ast.Table, files []&ast.File) &ast.CrossModuleInfo {
	mut info := &ast.CrossModuleInfo{}

	mut w := Walker{
		table:  table
		result: info
	}

	for file in files {
		w.walk_file(file)
	}

	// Add known cross-module calls that are generated directly in cgen (not from AST).
	// These are called from _vinit/_vcleanup which is in the main module.
	add_generated_cross_module_calls(table, mut info)

	return info
}

// add_generated_cross_module_calls registers functions that are called from generated code
// (like _vinit, _vcleanup) rather than from AST CallExpr nodes.
fn add_generated_cross_module_calls(table &ast.Table, mut info ast.CrossModuleInfo) {
	// Builtin functions and methods are frequently called from generated code
	// (operator overloading, array operations, string concatenation, etc.)
	// Mark all builtin functions/methods as extern to avoid linker issues.
	for fname, f in table.fns {
		if f.mod == 'builtin' {
			info.extern_fns[fname] = true
		}
	}

	// Also mark builtin methods on builtin types
	for _, sym in table.type_symbols {
		if sym.mod == 'builtin' {
			for _, method in sym.methods {
				info.extern_fns[method.fkey()] = true
			}
		}
	}

	// Module init/cleanup functions are called from _vinit/_vcleanup
	for mod_name in table.modules {
		init_fn_name := '${mod_name}.init'
		if f := table.find_fn(init_fn_name) {
			info.extern_fns[f.fkey()] = true
		}
		cleanup_fn_name := '${mod_name}.cleanup'
		if f := table.find_fn(cleanup_fn_name) {
			info.extern_fns[f.fkey()] = true
		}
	}

	// Interface method implementations need to be extern because they're called
	// through interface dispatch from any module that uses the interface.
	add_interface_method_impls(table, mut info)
}

// add_interface_method_impls marks methods that implement interface methods as extern.
// These can be called through interface dispatch from any module.
fn add_interface_method_impls(table &ast.Table, mut info ast.CrossModuleInfo) {
	// Find all interface types
	for _, sym in table.type_symbols {
		if sym.info is ast.Interface {
			// For each method in the interface, mark all implementations as extern
			for _, iface_method in sym.methods {
				// Find all types that implement this interface method
				for _, impl_sym in table.type_symbols {
					if impl_sym.kind == .interface {
						continue
					}
					// Check if this type has a method with the same name
					for _, method in impl_sym.methods {
						if method.name == iface_method.name {
							info.extern_fns[method.fkey()] = true
						}
					}
				}
			}
		}
	}
}
