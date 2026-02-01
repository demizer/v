// Copyright (c) 2026 Jesus Alvarez. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module cbuilder

import os
import time
import v.util
import v.builder
import v.gen.c
import sync.pool

// local_cache_cc implements module-based caching for faster incremental builds
fn local_cache_cc(mut b builder.Builder, result c.GenOutput) ! {
	sw_total := time.new_stopwatch()
	defer {
		eprint_time(sw_total, @METHOD)
	}

	// Use current working directory for cache (where v is invoked from)
	// Create subdirectory per target (e.g., .vcache/cad/, .vcache/tests/)
	target_name := os.base(b.compiled_dir)
	cache_dir := os.join_path(os.getwd(), '.vcache', target_name)
	os.mkdir_all(cache_dir) or {}

	vhash := @VHASH
	mut lc := builder.new_local_cache(cache_dir, vhash, b.pref.build_options)

	// Group files by module
	mut module_files := map[string][]string{}
	for pf in b.parsed_files {
		module_files[pf.mod.name] << pf.path
	}

	// Extract module-specific code from output
	module_code := extract_module_code(result)

	// Compute hashes and determine rebuild set
	// Process in dependency order (b.table.modules is topologically sorted)
	mut module_hashes := map[string]string{}
	mut needs_rebuild := map[string]bool{}
	mut dep_changed := map[string]bool{}

	for mod_name in b.table.modules {
		if mod_name == 'main' {
			needs_rebuild[mod_name] = true // Main always recompiles
			continue
		}

		// Only track modules that have generated code output
		if mod_name !in module_code {
			continue
		}

		files := module_files[mod_name] or { continue }
		if files.len == 0 {
			continue
		}

		current_hash := lc.compute_module_hash(mod_name, files)
		module_hashes[mod_name] = current_hash

		// Check if any dependency changed (only consider deps that have code output)
		mut any_dep_changed := false
		for pf in b.parsed_files {
			if pf.mod.name != mod_name {
				continue
			}
			for imp in pf.imports {
				// Only consider dependencies that produce separate code output
				if imp.mod in module_code && dep_changed[imp.mod] {
					any_dep_changed = true
					break
				}
			}
			if any_dep_changed {
				break
			}
		}

		if lc.needs_rebuild(mod_name, current_hash, any_dep_changed) {
			needs_rebuild[mod_name] = true
			dep_changed[mod_name] = true // Propagate to dependents
		}
	}

	// Count what needs rebuilding vs cached
	mut rebuild_count := 0
	mut cached_count := 0
	for mod_name in b.table.modules {
		if mod_name !in module_code {
			continue // No code for this module
		}
		if mod_name == 'main' || needs_rebuild[mod_name] {
			rebuild_count++
		} else {
			cached_count++
		}
	}
	eprintln('> Local cache: ${rebuild_count} modules to rebuild, ${cached_count} cached')

	// Split header into declarations-only, implementation defines, and .c includes
	// - Implementation defines (#define XXX_IMPLEMENTATION) go BEFORE header include
	// - Implementation .c includes go AFTER header include
	header_decl, impl_defines, impl_c_includes := split_header_implementations(result.header)

	// Write declarations-only header for modules
	// Process header to:
	// - Remove VV_LOC from declarations (end with ;) so functions are visible across modules
	// - Keep VV_LOC for definitions (have {) so inline helpers stay static (avoid duplicates)
	header_decl_modified := process_header_for_separate_compilation(header_decl)
	header_decl_path := os.join_path(cache_dir, 'out_decl.h')
	os.write_file(header_decl_path, header_decl_modified) or {
		return error('Failed to write out_decl.h: ${err}')
	}

	// Write main module (always recompiled)
	main_c_path := os.join_path(cache_dir, 'main.c')
	mut main_code := ''
	// Add implementation defines BEFORE the header (for STB-style headers)
	if impl_defines.len > 0 {
		main_code += impl_defines
		main_code += '\n'
	}
	// Now include the header (which will see the _IMPLEMENTATION defines)
	main_code += '#include "out_decl.h"\n\n'
	// Add implementation .c includes AFTER the header
	if impl_c_includes.len > 0 {
		main_code += impl_c_includes
		main_code += '\n'
	}
	// Add helpers that go with main
	main_code += result.out0_str
	main_code += '\n'
	// Add extern declarations
	main_code += result.extern_str
	main_code += '\n'
	// Add main module code
	// Remove VV_LOC (static) so functions are visible across modules
	if main_mod_code := module_code['main'] {
		main_code += main_mod_code.replace('VV_LOC ', '')
	}
	os.write_file(main_c_path, main_code) or { return error('Failed to write main.c: ${err}') }

	// Write .c files for modules that need rebuild
	for mod_name, code in module_code {
		if mod_name == 'main' {
			continue // Already handled
		}
		if !needs_rebuild[mod_name] {
			continue
		}
		c_path := os.join_path(cache_dir, '${mod_name.replace('.', '_')}.c')
		// Redefine VV_LOC as empty before including header
		// This makes all function declarations non-static
		// Then include header, then add extern declarations, then module code
		// Remove VV_LOC from module code so functions are non-static (linkable)
		// Header keeps VV_LOC=static so inline header functions avoid duplicates
		code_no_static := code.replace('VV_LOC ', '')
		mod_code := '#include "out_decl.h"\n\n${result.extern_str}\n${code_no_static}'
		os.write_file(c_path, mod_code) or { continue }
	}

	// Use V's default compiler (tcc)
	cc := os.quoted_path(b.pref.ccompiler)

	// Get compile args but filter out -o, source files, and .o files
	// since we'll specify our own -o and -c arguments
	// .o files should only go to the linker, not individual compilations
	mut compile_args := []string{}
	mut extra_obj_files := []string{}
	mut skip_next := false
	for arg in b.get_compile_args() {
		if skip_next {
			skip_next = false
			continue
		}
		if arg == '-o' {
			skip_next = true // Skip next arg (the output file)
			continue
		}
		if arg.starts_with('-o') {
			continue // Skip -oFILE style
		}
		if arg.ends_with('.tmp.c') || arg.ends_with('.c"') || arg.ends_with(".c'") {
			continue // Skip source file
		}
		// Collect .o files for linking, don't pass to compilation
		if arg.ends_with('.o') || arg.ends_with('.o"') || arg.ends_with(".o'") {
			extra_obj_files << arg
			continue
		}
		compile_args << arg
	}

	linker_args := b.get_linker_args()

	scompile_args := compile_args.join(' ')
	slinker_args := linker_args.join(' ')

	// Compile changed modules in parallel
	mut obj_files := []string{}
	mut compile_cmds := []string{}

	// Always compile main
	main_o_path := os.join_path(cache_dir, 'main.o')
	obj_files << main_o_path
	compile_cmds << '${cc} ${scompile_args} -w -o ${os.quoted_path(main_o_path)} -c ${os.quoted_path(main_c_path)}'

	// Add module compilations
	for mod_name in b.table.modules {
		if mod_name == 'main' {
			continue
		}
		if mod_name !in module_code {
			continue // No code generated for this module
		}

		o_path := os.join_path(cache_dir, '${mod_name.replace('.', '_')}.o')
		obj_files << o_path

		if needs_rebuild[mod_name] {
			c_path := os.join_path(cache_dir, '${mod_name.replace('.', '_')}.c')
			compile_cmds << '${cc} ${scompile_args} -w -o ${os.quoted_path(o_path)} -c ${os.quoted_path(c_path)}'
		}
	}

	// Run compilations in parallel
	// TCC needs to run from vroot to find its headers (relative paths)
	original_dir := os.getwd()
	os.chdir(b.pref.vroot) or {}
	defer {
		os.chdir(original_dir) or {}
	}

	if compile_cmds.len > 0 {
		sw := time.new_stopwatch()
		mut pp := pool.new_pool_processor(callback: build_parallel_o_cb)
		pp.set_max_jobs(util.nr_jobs)
		pp.work_on_items(compile_cmds)

		mut failed := 0
		for x in pp.get_results[os.Result]() {
			failed += if x.exit_code == 0 { 0 } else { 1 }
		}
		eprint_time(sw, 'C compilation on ${util.nr_jobs} thread(s), processing ${compile_cmds.len} commands, failed: ${failed}')

		if failed > 0 {
			return error_with_code('failed local cache C compilation', failed)
		}
	}

	// Update manifest for rebuilt modules
	for mod_name, hash in module_hashes {
		if needs_rebuild[mod_name] {
			o_path := os.join_path(cache_dir, '${mod_name.replace('.', '_')}.o')
			files := module_files[mod_name] or { []string{} }
			// Get deps from parsed files
			mut deps := []string{}
			for pf in b.parsed_files {
				if pf.mod.name == mod_name {
					for imp in pf.imports {
						deps << imp.mod
					}
				}
			}
			lc.update_module(mod_name, hash, files, deps, o_path)
		}
	}
	lc.save_manifest()

	// Link all object files
	scompile_args_for_linker := compile_args.filter(it != '-x objective-c').join(' ')
	quoted_obj_files := obj_files.map(os.quoted_path(it)).join(' ')
	sextra_obj_files := extra_obj_files.join(' ')

	link_cmd := '${cc} ${scompile_args_for_linker} -o ${os.quoted_path(b.pref.out_name)} ${quoted_obj_files} ${sextra_obj_files} ${slinker_args}'

	sw_link := time.new_stopwatch()
	link_res := os.execute(link_cmd)
	eprint_time(sw_link, 'link_cmd')

	if link_res.exit_code != 0 {
		eprintln('Link failed: ${link_res.output}')
		return error_with_code('failed to link after local cache C compilation', 1)
	}
}

// extract_module_code extracts code for each module from the generated output
fn extract_module_code(result c.GenOutput) map[string]string {
	mut module_code := map[string]string{}

	if result.module_fn_positions.len == 0 {
		// No module tracking, put everything in main
		module_code['main'] = result.out_str
		return module_code
	}

	// Sort positions by start_pos to process in order
	mut positions := result.module_fn_positions.clone()
	positions.sort(a.start_pos < b.start_pos)

	// Extract code for each function and group by module
	mut mod_builders := map[string][]string{}

	// Capture code BEFORE the first tracked function (typeof support, etc.)
	// This goes into 'main' since it's runtime support code
	if positions.len > 0 && positions[0].start_pos > 0 {
		prefix_code := result.out_str[0..positions[0].start_pos]
		if prefix_code.trim_space().len > 0 {
			mod_builders['main'] << prefix_code
		}
	}

	for i, pos in positions {
		// Determine end position (next function's start or end of string)
		end_pos := if i + 1 < positions.len {
			positions[i + 1].start_pos
		} else {
			result.out_str.len
		}

		if pos.start_pos >= result.out_str.len || end_pos > result.out_str.len {
			continue
		}

		fn_code := result.out_str[pos.start_pos..end_pos]
		mod_builders[pos.mod] << fn_code
	}

	// Combine code for each module
	for mod_name, code_parts in mod_builders {
		module_code[mod_name] = balance_preprocessor_directives(code_parts.join(''))
	}

	return module_code
}

// balance_preprocessor_directives ensures #if/#endif are balanced in extracted code
// This is needed because the code extraction may split in the middle of preprocessor blocks
fn balance_preprocessor_directives(code string) string {
	// Count #if (including #ifdef, #ifndef) and #endif
	mut if_count := 0
	mut endif_count := 0

	mut i := 0
	for i < code.len {
		if code[i] == `#` {
			// Look for #if, #ifdef, #ifndef, or #endif
			rest := code[i..]
			if rest.starts_with('#if ') || rest.starts_with('#if\t') || rest.starts_with('#ifdef ')
				|| rest.starts_with('#ifndef ') || rest.starts_with('#if(') {
				if_count++
			} else if rest.starts_with('#endif') {
				endif_count++
			}
		}
		i++
	}

	// Balance the directives
	mut result := code
	if endif_count > if_count {
		// Add #if 1 at the beginning for each extra #endif
		prefix := '#if 1\n'.repeat(endif_count - if_count)
		result = prefix + result
	} else if if_count > endif_count {
		// Add #endif at the end for each extra #if
		suffix := '\n#endif'.repeat(if_count - endif_count)
		result = result + suffix
	}

	return result
}

// split_header_implementations separates implementation includes from declarations
// Returns (declarations_only, impl_defines, impl_c_includes)
// - declarations_only: header without _IMPLEMENTATION defines and .c includes
// - impl_defines: #define XXX_IMPLEMENTATION lines (need to go BEFORE the header include)
// - impl_c_includes: #include of .c files (need to go AFTER the header include)
fn split_header_implementations(header string) (string, string, string) {
	mut decl_lines := []string{}
	mut impl_defines := []string{}
	mut impl_c_includes := []string{}
	mut in_impl_block := false
	mut impl_block_depth := 0

	lines := header.split('\n')
	for line := 0; line < lines.len; line++ {
		l := lines[line]
		trimmed := l.trim_space()

		// Check for _IMPLEMENTATION define (STB-style)
		// These defines trigger implementation code in the following #include
		// They need to be defined BEFORE the header is included
		if trimmed.starts_with('#define') && trimmed.contains('_IMPLEMENTATION') {
			impl_defines << l
			continue
		}

		// Check for start of implementation include block
		// Pattern: #if ... followed by #include "something.c"
		if trimmed.starts_with('#if') && !trimmed.starts_with('#ifndef') && !in_impl_block {
			// Look ahead for .c include
			if line + 1 < lines.len || line + 2 < lines.len {
				next_lines := if line + 2 < lines.len {
					lines[line + 1] + lines[line + 2]
				} else if line + 1 < lines.len {
					lines[line + 1]
				} else {
					''
				}
				if next_lines.contains('.c"') || next_lines.contains(".c'") {
					in_impl_block = true
					impl_block_depth = 1
					impl_c_includes << l
					continue // Don't process this line again in the in_impl_block section
				}
			}
		}

		if in_impl_block {
			impl_c_includes << l
			// Track #if/#endif nesting
			if trimmed.starts_with('#if') {
				impl_block_depth++
			} else if trimmed.starts_with('#endif') {
				impl_block_depth--
				if impl_block_depth == 0 {
					in_impl_block = false
				}
			}
		} else {
			// Check for direct .c include without #if guard
			if trimmed.starts_with('#include')
				&& (trimmed.contains('.c"') || trimmed.contains(".c'")) {
				impl_c_includes << l
			} else {
				decl_lines << l
			}
		}
	}

	return decl_lines.join('\n'), impl_defines.join('\n'), impl_c_includes.join('\n')
}

// process_header_for_separate_compilation modifies the header for separate compilation:
// - Removes VV_LOC from function declarations (ending with ;) so they're visible across modules
// - Keeps VV_LOC for function definitions (with { body) so inline helpers stay static
fn process_header_for_separate_compilation(header string) string {
	lines := header.split('\n')
	mut result := []string{cap: lines.len}

	for line in lines {
		trimmed := line.trim_space()
		// Check if this is a VV_LOC function declaration (ends with ;) vs definition (has {)
		if trimmed.starts_with('VV_LOC ') && trimmed.ends_with(';') {
			// This is a declaration - remove VV_LOC to make it extern
			result << line.replace('VV_LOC ', '')
		} else {
			// Keep as-is (including definitions with VV_LOC which should stay static)
			result << line
		}
	}

	return result.join('\n')
}
