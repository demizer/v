// Copyright (c) 2026 Jesus Alvarez. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module builder

import json
import os
import crypto.sha256
import v.ast

// FileCacheEntry stores metadata about a cached parsed file
struct FileCacheEntry {
	content_hash string // SHA256 of file contents
	mtime        i64    // File modification time for quick check
	cache_file   string // Path to .cache file
}

// ParseCacheManifest stores the complete parse cache state
struct ParseCacheManifest {
	vhash string                    // V compiler version hash
	files map[string]FileCacheEntry // source_path -> entry
}

// ParseCacheStats tracks cache performance
pub struct ParseCacheStats {
pub mut:
	hits   int
	misses int
}

// ParseCache manages cached parsed AST files
pub struct ParseCache {
pub mut:
	cache_dir string
	manifest  ParseCacheManifest
	vhash     string // V compiler version hash
	enabled   bool
	stats     ParseCacheStats
}

// new_parse_cache creates a new ParseCache instance
pub fn new_parse_cache(cache_dir string, vhash string) &ParseCache {
	parse_dir := os.join_path(cache_dir, 'parse')
	mut pc := &ParseCache{
		cache_dir: parse_dir
		vhash:     vhash
		enabled:   true
	}
	pc.init()
	return pc
}

// init initializes the parse cache directory and loads manifest
fn (mut pc ParseCache) init() {
	// Create cache directory if needed
	if !os.exists(pc.cache_dir) {
		os.mkdir_all(pc.cache_dir) or {}
	}
	pc.load_manifest()
}

// compute_file_hash computes SHA256 hash of file contents
fn compute_file_hash(content string) string {
	return sha256.hexhash(content)
}

// get_cache_path returns the cache file path for a source file
pub fn (pc &ParseCache) get_cache_path(source_path string) string {
	// Use relative path for portability, replace path separators
	rel_path := os.real_path(source_path).replace(os.getwd() + os.path_separator, '')
	safe_name := rel_path.replace(os.path_separator, '_').replace(':', '_')
	return os.join_path(pc.cache_dir, '${safe_name}.cache')
}

// is_valid checks if cache is valid for a file using mtime quick check
pub fn (pc &ParseCache) is_valid(source_path string, file_mtime i64) bool {
	entry := pc.manifest.files[source_path] or { return false }

	// Quick check: mtime unchanged means file unchanged
	if entry.mtime == file_mtime {
		// Verify cache file exists
		return os.exists(entry.cache_file)
	}
	return false
}

// is_valid_with_hash checks cache validity, computing hash if mtime changed
pub fn (pc &ParseCache) is_valid_with_hash(source_path string, file_mtime i64, content string) bool {
	entry := pc.manifest.files[source_path] or { return false }

	// Quick check: mtime unchanged
	if entry.mtime == file_mtime {
		return os.exists(entry.cache_file)
	}

	// mtime changed, check content hash
	current_hash := compute_file_hash(content)
	if entry.content_hash == current_hash {
		return os.exists(entry.cache_file)
	}

	return false
}

// CachedFile holds both the AST and its table contributions
pub struct CachedFile {
pub:
	file          &ast.File
	contributions ast.TableContributions
}

// load_contributions loads only the table contributions from a cached file (for two-pass loading)
pub fn (mut pc ParseCache) load_contributions(source_path string) ?ast.TableContributions {
	entry := pc.manifest.files[source_path] or { return none }

	// Read cached data
	data := os.read_bytes(entry.cache_file) or { return none }

	// Create reader and skip past AST data to get contributions
	mut r := ast.new_ast_reader(data)
	file_size := r.read_u32()
	r.pos += int(file_size) // Skip AST data

	// Read and return contributions
	return r.read_table_contributions()
}

// can_load_ast tests if an AST can be loaded by checking if all type names can be resolved
// Uses the actual table to check type resolution without registering new types
pub fn (mut pc ParseCache) can_load_ast(source_path string, table &ast.Table) bool {
	entry := pc.manifest.files[source_path] or { return false }

	// Read cached data
	data := os.read_bytes(entry.cache_file) or { return false }

	// Create reader
	mut r := ast.new_ast_reader(data)

	// Read AST file size and data
	file_size := r.read_u32()
	file_data := data[r.pos..r.pos + int(file_size)]

	// Test deserialization using a copy of the table to avoid side effects
	// Create a minimal test table that shares type_idxs for lookup but discards new registrations
	return ast.can_deserialize_file(file_data, table)
}

// load_ast loads only the AST from a cached file (for two-pass loading, after contributions registered)
pub fn (mut pc ParseCache) load_ast(source_path string, table &ast.Table) ?&ast.File {
	entry := pc.manifest.files[source_path] or {
		pc.stats.misses++
		return none
	}

	// Read cached data
	data := os.read_bytes(entry.cache_file) or {
		pc.stats.misses++
		return none
	}

	// Create reader
	mut r := ast.new_ast_reader(data)

	// Read AST file size and data
	file_size := r.read_u32()
	file_data := data[r.pos..r.pos + int(file_size)]

	// Deserialize AST with table for type resolution
	file := ast.deserialize_file(file_data, table) or {
		eprintln('> load_ast failed for ${source_path}: ${err}')
		pc.stats.misses++
		return none
	}

	pc.stats.hits++
	return file
}

// load attempts to load a cached AST file and its table contributions (single-pass, for compatibility)
pub fn (mut pc ParseCache) load(source_path string, table &ast.Table) ?CachedFile {
	entry := pc.manifest.files[source_path] or {
		pc.stats.misses++
		return none
	}

	// Read cached data
	data := os.read_bytes(entry.cache_file) or {
		pc.stats.misses++
		return none
	}

	// Create reader for contributions (skip type resolution - they'll be remapped)
	mut r := ast.new_ast_reader(data)
	r.skip_type_resolution = true

	// Read AST file size and data
	file_size := r.read_u32()
	file_data := data[r.pos..r.pos + int(file_size)]
	r.pos += int(file_size)

	// Read table contributions (with type resolution skipped)
	contributions := r.read_table_contributions()

	// Deserialize AST with table for type resolution (NOT skipped)
	file := ast.deserialize_file(file_data, table) or {
		pc.stats.misses++
		return none
	}

	pc.stats.hits++
	return CachedFile{
		file:          file
		contributions: contributions
	}
}

// save saves a parsed AST file and its table contributions to cache
pub fn (mut pc ParseCache) save(source_path string, content string, file_mtime i64, file &ast.File, contributions &ast.TableContributions, table &ast.Table) {
	cache_path := pc.get_cache_path(source_path)
	content_hash := compute_file_hash(content)

	// Serialize AST and contributions together - use table for type name serialization
	mut w := ast.new_ast_writer_with_table(4096, table)

	// Write AST file with table for type name serialization
	file_data := ast.serialize_file(file, table)
	w.write_u32(u32(file_data.len))
	for b in file_data {
		w.buf << b
	}

	// Write table contributions (also uses table for type name serialization)
	w.write_table_contributions(contributions)

	// Write cache file
	os.write_file_array(cache_path, w.buf) or { return }

	// Update manifest
	pc.update_entry(source_path, content_hash, file_mtime, cache_path)
}

// update_entry updates the manifest entry for a file
fn (mut pc ParseCache) update_entry(source_path string, content_hash string, mtime i64, cache_file string) {
	mut files := pc.manifest.files.clone()
	files[source_path] = FileCacheEntry{
		content_hash: content_hash
		mtime:        mtime
		cache_file:   cache_file
	}
	pc.manifest = ParseCacheManifest{
		vhash: pc.vhash
		files: files
	}
}

// load_manifest loads the cache manifest from disk
fn (mut pc ParseCache) load_manifest() {
	manifest_path := os.join_path(pc.cache_dir, 'manifest.json')
	content := os.read_file(manifest_path) or { return }
	manifest := json.decode(ParseCacheManifest, content) or { return }

	// Check if V version changed - if so, invalidate entire cache
	if manifest.vhash != pc.vhash {
		return
	}
	pc.manifest = manifest
}

// save_manifest saves the cache manifest to disk
pub fn (pc &ParseCache) save_manifest() {
	manifest_path := os.join_path(pc.cache_dir, 'manifest.json')
	content := json.encode(pc.manifest)
	os.write_file(manifest_path, content) or {}
}

// clear removes all cached files and resets manifest
pub fn (mut pc ParseCache) clear() {
	os.rmdir_all(pc.cache_dir) or {}
	os.mkdir_all(pc.cache_dir) or {}
	pc.manifest = ParseCacheManifest{
		vhash: pc.vhash
		files: map[string]FileCacheEntry{}
	}
	pc.stats = ParseCacheStats{}
}

// print_stats prints cache statistics
pub fn (pc &ParseCache) print_stats() {
	total := pc.stats.hits + pc.stats.misses
	if total > 0 {
		println('Parse cache: ${pc.stats.hits} hits, ${pc.stats.misses} misses (${total} files)')
	}
}

// register_contributions registers cached table contributions back into the table
pub fn register_contributions(mut table ast.Table, contributions &ast.TableContributions) {
	eprintln('> register_contributions: ${contributions.type_symbols.len} types, ${contributions.functions.len} fns')

	// Build remap table: old_idx -> new_idx
	mut remap := map[int]int{}
	for old_idx, type_name in contributions.type_names {
		// Look up the type name in the current table
		if new_idx := table.type_idxs[type_name] {
			remap[old_idx] = new_idx
		}
	}
	eprintln('> register_contributions: remap built')

	// Register type symbols with remapped types
	for ts in contributions.type_symbols {
		// Check if already registered by name
		if ts.name in table.type_idxs {
			continue
		}
		// Remap types in the TypeSymbol and register
		remapped_ts := remap_type_symbol(ts, remap)
		table.register_sym(remapped_ts)
	}
	eprintln('> register_contributions: types registered')

	// Register functions with remapped types
	for i, f in contributions.functions {
		remapped_f := remap_fn(f, remap)
		fkey := if remapped_f.is_method {
			'${int(remapped_f.receiver_type)}.${remapped_f.name}'
		} else {
			'${remapped_f.mod}.${remapped_f.name}'
		}
		// Check if already registered
		if fkey in table.fns {
			continue
		}
		if f.name == 'is_empty' {
			eprintln('> registering is_empty: orig_recv=${int(f.receiver_type)} -> remapped_recv=${int(remapped_f.receiver_type)}, fkey=${fkey}')
		}
		table.fns[fkey] = remapped_f
	}
	eprintln('> register_contributions: fns registered')
}

// remap_type remaps a Type index using the remap table
fn remap_type(t ast.Type, remap map[int]int) ast.Type {
	idx := t.idx()
	if idx <= 0 {
		return t
	}
	if new_idx := remap[idx] {
		// Preserve type flags (ptr, optional, etc) using derive
		return ast.new_type(new_idx).derive(t)
	}
	return t
}

// remap_type_array remaps an array of types
fn remap_type_array(types []ast.Type, remap map[int]int) []ast.Type {
	mut result := []ast.Type{cap: types.len}
	for t in types {
		result << remap_type(t, remap)
	}
	return result
}

// remap_type_symbol remaps all Type values in a TypeSymbol
fn remap_type_symbol(ts ast.TypeSymbol, remap map[int]int) ast.TypeSymbol {
	// Remap parent_idx if present
	mut new_parent_idx := ts.parent_idx
	if ts.parent_idx > 0 {
		if new_idx := remap[ts.parent_idx] {
			new_parent_idx = new_idx
		}
	}
	return ast.TypeSymbol{
		parent_idx:    new_parent_idx
		kind:          ts.kind
		name:          ts.name
		cname:         ts.cname
		rname:         ts.rname
		ngname:        ts.ngname
		mod:           ts.mod
		is_pub:        ts.is_pub
		is_builtin:    ts.is_builtin
		language:      ts.language
		idx:           ts.idx
		size:          ts.size
		align:         ts.align
		generic_types: remap_type_array(ts.generic_types, remap)
		methods:       remap_fn_array(ts.methods, remap)
		info:          remap_type_info(ts.info, remap)
	}
}

// remap_fn remaps all Type values in a Fn
fn remap_fn(f ast.Fn, remap map[int]int) ast.Fn {
	return ast.Fn{
		is_variadic:                    f.is_variadic
		is_c_variadic:                  f.is_c_variadic
		language:                       f.language
		is_pub:                         f.is_pub
		is_ctor_new:                    f.is_ctor_new
		is_deprecated:                  f.is_deprecated
		is_noreturn:                    f.is_noreturn
		is_unsafe:                      f.is_unsafe
		is_must_use:                    f.is_must_use
		is_placeholder:                 f.is_placeholder
		is_main:                        f.is_main
		is_test:                        f.is_test
		is_keep_alive:                  f.is_keep_alive
		is_method:                      f.is_method
		is_static_type_method:          f.is_static_type_method
		no_body:                        f.no_body
		is_file_translated:             f.is_file_translated
		mod:                            f.mod
		file:                           f.file
		file_mode:                      f.file_mode
		pos:                            f.pos
		name_pos:                       f.name_pos
		return_type_pos:                f.return_type_pos
		return_type:                    remap_type(f.return_type, remap)
		receiver_type:                  remap_type(f.receiver_type, remap)
		name:                           f.name
		params:                         remap_params(f.params, remap)
		usages:                         f.usages
		generic_names:                  f.generic_names
		dep_names:                      f.dep_names
		attrs:                          f.attrs
		is_conditional:                 f.is_conditional
		ctdefine_idx:                   f.ctdefine_idx
		from_embedded_type:             remap_type(f.from_embedded_type, remap)
		is_expand_simple_interpolation: f.is_expand_simple_interpolation
	}
}

// remap_fn_array remaps an array of Fns
fn remap_fn_array(fns []ast.Fn, remap map[int]int) []ast.Fn {
	mut result := []ast.Fn{cap: fns.len}
	for f in fns {
		result << remap_fn(f, remap)
	}
	return result
}

// remap_params remaps types in function parameters
fn remap_params(params []ast.Param, remap map[int]int) []ast.Param {
	mut result := []ast.Param{cap: params.len}
	for p in params {
		result << ast.Param{
			pos:        p.pos
			name:       p.name
			is_mut:     p.is_mut
			is_shared:  p.is_shared
			is_atomic:  p.is_atomic
			type_pos:   p.type_pos
			is_hidden:  p.is_hidden
			on_newline: p.on_newline
			typ:        remap_type(p.typ, remap)
		}
	}
	return result
}

// remap_struct_fields remaps types in struct fields
fn remap_struct_fields(fields []ast.StructField, remap map[int]int) []ast.StructField {
	mut result := []ast.StructField{cap: fields.len}
	for fld in fields {
		result << ast.StructField{
			pos:              fld.pos
			name:             fld.name
			typ:              remap_type(fld.typ, remap)
			default_expr:     fld.default_expr
			has_default_expr: fld.has_default_expr
			default_val:      fld.default_val
			attrs:            fld.attrs
			is_pub:           fld.is_pub
			is_mut:           fld.is_mut
			is_global:        fld.is_global
			is_volatile:      fld.is_volatile
			is_deprecated:    fld.is_deprecated
			anon_struct_decl: fld.anon_struct_decl
			comments:         fld.comments
			i:                fld.i
		}
	}
	return result
}

// remap_type_info remaps Type values in TypeInfo
fn remap_type_info(info ast.TypeInfo, remap map[int]int) ast.TypeInfo {
	match info {
		ast.Alias {
			return ast.Alias{
				parent_type: remap_type(info.parent_type, remap)
				language:    info.language
				is_import:   info.is_import
				name_pos:    info.name_pos
			}
		}
		ast.Array {
			return ast.Array{
				nr_dims:   info.nr_dims
				elem_type: remap_type(info.elem_type, remap)
			}
		}
		ast.ArrayFixed {
			return ast.ArrayFixed{
				size:      info.size
				elem_type: remap_type(info.elem_type, remap)
				is_fn_ret: info.is_fn_ret
			}
		}
		ast.Chan {
			return ast.Chan{
				elem_type: remap_type(info.elem_type, remap)
				is_mut:    info.is_mut
			}
		}
		ast.Enum {
			return ast.Enum{
				vals:             info.vals
				is_flag:          info.is_flag
				is_multi_allowed: info.is_multi_allowed
				uses_exprs:       info.uses_exprs
				typ:              remap_type(info.typ, remap)
				name_pos:         info.name_pos
			}
		}
		ast.FnType {
			return ast.FnType{
				is_anon:  info.is_anon
				has_decl: info.has_decl
				func:     remap_fn(info.func, remap)
			}
		}
		ast.GenericInst {
			return ast.GenericInst{
				parent_idx:     info.parent_idx
				concrete_types: remap_type_array(info.concrete_types, remap)
			}
		}
		ast.Interface {
			return ast.Interface{
				types:          remap_type_array(info.types, remap)
				fields:         remap_struct_fields(info.fields, remap)
				methods:        remap_fn_array(info.methods, remap)
				embeds:         remap_type_array(info.embeds, remap)
				is_generic:     info.is_generic
				is_markused:    info.is_markused
				generic_types:  remap_type_array(info.generic_types, remap)
				concrete_types: remap_type_array(info.concrete_types, remap)
				parent_type:    remap_type(info.parent_type, remap)
				name_pos:       info.name_pos
			}
		}
		ast.Map {
			return ast.Map{
				key_type:   remap_type(info.key_type, remap)
				value_type: remap_type(info.value_type, remap)
				name_pos:   info.name_pos
			}
		}
		ast.MultiReturn {
			return ast.MultiReturn{
				types: remap_type_array(info.types, remap)
			}
		}
		ast.Struct {
			return ast.Struct{
				attrs:          info.attrs
				scoped_name:    info.scoped_name
				embeds:         remap_type_array(info.embeds, remap)
				fields:         remap_struct_fields(info.fields, remap)
				is_typedef:     info.is_typedef
				is_union:       info.is_union
				is_heap:        info.is_heap
				is_minify:      info.is_minify
				is_anon:        info.is_anon
				is_generic:     info.is_generic
				is_shared:      info.is_shared
				is_markused:    info.is_markused
				has_option:     info.has_option
				generic_types:  remap_type_array(info.generic_types, remap)
				concrete_types: remap_type_array(info.concrete_types, remap)
				parent_type:    remap_type(info.parent_type, remap)
				name_pos:       info.name_pos
			}
		}
		ast.SumType {
			return ast.SumType{
				fields:         remap_struct_fields(info.fields, remap)
				found_fields:   info.found_fields
				is_anon:        info.is_anon
				is_generic:     info.is_generic
				variants:       remap_type_array(info.variants, remap)
				generic_types:  remap_type_array(info.generic_types, remap)
				concrete_types: remap_type_array(info.concrete_types, remap)
				parent_type:    remap_type(info.parent_type, remap)
				name_pos:       info.name_pos
			}
		}
		ast.Thread {
			return ast.Thread{
				return_type: remap_type(info.return_type, remap)
			}
		}
		ast.Aggregate {
			return ast.Aggregate{
				sum_type: remap_type(info.sum_type, remap)
				types:    remap_type_array(info.types, remap)
			}
		}
		else {
			return info
		}
	}
}
