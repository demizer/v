// AST Serialization for V Parse Cache
// Uses sequential binary format for efficient storage
module ast

import encoding.flatbuffers as fb
import v.token

// Magic bytes for cache file identification
const cache_magic = [u8(`V`), `A`, `S`, `T`]
const cache_version = u32(9)

// ExprKind discriminator for Expr sumtype variants
pub enum ExprKind as u8 {
	node_error = 0
	anon_fn
	array_decompose
	array_init
	as_cast
	assoc
	at_expr
	bool_literal
	c_temp_var
	call_expr
	cast_expr
	chan_init
	char_literal
	comment
	comptime_call
	comptime_selector
	comptime_type
	concat_expr
	dump_expr
	empty_expr
	enum_val
	float_literal
	go_expr
	ident
	if_expr
	if_guard_expr
	index_expr
	infix_expr
	integer_literal
	is_ref_type
	lambda_expr
	likely
	lock_expr
	map_init
	match_expr
	nil_expr
	none_expr
	offset_of
	or_expr
	par_expr
	postfix_expr
	prefix_expr
	range_expr
	select_expr
	selector_expr
	size_of
	spawn_expr
	sql_expr
	string_inter_literal
	string_literal
	struct_init
	type_node
	type_of
	unsafe_expr
}

// StmtKind discriminator for Stmt sumtype variants
pub enum StmtKind as u8 {
	asm_stmt = 0
	assert_stmt
	assign_stmt
	block
	branch_stmt
	comptime_for
	const_decl
	debugger_stmt
	defer_stmt
	empty_stmt
	enum_decl
	expr_stmt
	fn_decl
	for_c_stmt
	for_in_stmt
	for_stmt
	global_decl
	goto_label
	goto_stmt
	hash_stmt
	import_stmt
	interface_decl
	module_stmt
	node_error
	return_stmt
	semicolon_stmt
	sql_stmt
	struct_decl
	type_decl
}

// AstWriter handles serialization of AST to binary format
pub struct AstWriter {
pub mut:
	buf   []u8
	table &Table = unsafe { nil } // Reference to type table for name lookups
}

// AstReader handles deserialization of binary format to AST
pub struct AstReader {
pub:
	data []u8
pub mut:
	table                &Table = unsafe { nil } // Reference to type table for name resolution (mut for on-demand type registration)
	pos                  int
	unresolved_type_err  bool // Set to true if any type failed to resolve
	skip_type_resolution bool // When true, read_type returns Type(0) without resolving (for contribution loading)
}

// new_ast_writer creates a new AST writer with the given initial buffer size
pub fn new_ast_writer(initial_size int) AstWriter {
	return AstWriter{
		buf: []u8{cap: initial_size}
	}
}

// new_ast_writer_with_table creates a new AST writer with table reference
pub fn new_ast_writer_with_table(initial_size int, table &Table) AstWriter {
	return AstWriter{
		buf:   []u8{cap: initial_size}
		table: table
	}
}

// new_ast_reader creates a new AST reader from serialized data
pub fn new_ast_reader(data []u8) AstReader {
	return AstReader{
		data: data
	}
}

// new_ast_reader_with_table creates a new AST reader with table reference
pub fn new_ast_reader_with_table(data []u8, table &Table) AstReader {
	return AstReader{
		data:  data
		table: table
	}
}

// --- Primitive Writers ---

// write_bool writes a boolean value
fn (mut w AstWriter) write_bool(b bool) {
	w.buf << if b { u8(1) } else { u8(0) }
}

// write_u8 writes a u8 value
fn (mut w AstWriter) write_u8(n u8) {
	w.buf << n
}

// write_u16 writes a u16 value (little-endian)
fn (mut w AstWriter) write_u16(n u16) {
	w.buf << u8(n)
	w.buf << u8(n >> 8)
}

// write_u32 writes a u32 value (little-endian)
pub fn (mut w AstWriter) write_u32(n u32) {
	w.buf << u8(n)
	w.buf << u8(n >> 8)
	w.buf << u8(n >> 16)
	w.buf << u8(n >> 24)
}

// write_i32 writes an i32 value (little-endian)
fn (mut w AstWriter) write_i32(n i32) {
	w.write_u32(u32(n))
}

// write_i64 writes an i64 value (little-endian)
fn (mut w AstWriter) write_i64(n i64) {
	w.write_u32(u32(n))
	w.write_u32(u32(n >> 32))
}

// write_string writes a length-prefixed string
fn (mut w AstWriter) write_string(s string) {
	w.write_u32(u32(s.len))
	for c in s {
		w.buf << c
	}
}

// write_type writes a Type as name + flags for stable serialization
fn (mut w AstWriter) write_type(t Type) {
	// Extract index and flags
	idx := t.idx()
	flags := u32(t) & 0xffff0000 // Upper 16 bits contain flags

	// Look up type name from table
	mut name := ''
	table_valid := w.table != unsafe { nil }
	if table_valid && idx > 0 && idx < w.table.type_symbols.len {
		if ts := w.table.type_symbols[idx] {
			name = ts.name
		}
	}

	// Debug output for all types with idx > 0
	if idx > 0 {
		ts_len := if table_valid { w.table.type_symbols.len } else { -1 }
		if name.len == 0 {
			eprintln('DEBUG write_type: idx=${idx} -> EMPTY NAME! table_valid=${table_valid} ts_len=${ts_len}')
		}
	}

	// Write name and flags
	w.write_string(name)
	w.write_u32(flags)
}

// --- Primitive Readers ---

// read_bool reads a boolean value
fn (mut r AstReader) read_bool() bool {
	result := r.data[r.pos] != 0
	r.pos += 1
	return result
}

// read_u8 reads a u8 value
fn (mut r AstReader) read_u8() u8 {
	result := r.data[r.pos]
	r.pos += 1
	return result
}

// read_u16 reads a u16 value (little-endian)
fn (mut r AstReader) read_u16() u16 {
	result := fb.get_u16(r.data[r.pos..])
	r.pos += 2
	return result
}

// read_u32 reads a u32 value (little-endian)
pub fn (mut r AstReader) read_u32() u32 {
	result := fb.get_u32(r.data[r.pos..])
	r.pos += 4
	return result
}

// read_i32 reads an i32 value (little-endian)
fn (mut r AstReader) read_i32() i32 {
	result := fb.get_i32(r.data[r.pos..])
	r.pos += 4
	return result
}

// read_i64 reads an i64 value (little-endian)
fn (mut r AstReader) read_i64() i64 {
	result := fb.get_i64(r.data[r.pos..])
	r.pos += 8
	return result
}

// read_string reads a length-prefixed string
fn (mut r AstReader) read_string() string {
	len := r.read_u32()
	if len == 0 {
		return ''
	}
	s := unsafe { tos(r.data[r.pos..].data, int(len)) }.clone()
	r.pos += int(len)
	return s
}

// read_type reads a Type (u32 index)
// read_type reads a Type name and resolves it to current table index
fn (mut r AstReader) read_type() Type {
	// Read name and flags
	name := r.read_string()
	flags := r.read_u32()

	// Skip resolution if requested (for contribution loading where types are remapped later)
	if r.skip_type_resolution {
		// Return Type(0) with flags - the actual type will be remapped from type_names
		return Type(flags)
	}

	// Resolve name to current index
	mut idx := 0
	if r.table != unsafe { nil } && name.len > 0 {
		if found_idx := r.table.type_idxs[name] {
			idx = found_idx
		} else {
			// Try to register compound types on-demand
			idx = try_register_type_by_name(mut r.table, name)
			if idx == 0 {
				// Type couldn't be resolved - mark as error for fallback
				r.unresolved_type_err = true
			}
		}
	}

	// Combine index with flags
	return Type(u32(idx) | flags)
}

// try_register_type_by_name attempts to register a compound type by parsing its name
// Returns the type index if successful, 0 otherwise
fn try_register_type_by_name(mut table Table, name string) int {
	// Handle array types: []T
	if name.starts_with('[]') {
		elem_name := name[2..]
		elem_idx := resolve_type_name(mut table, elem_name)
		if elem_idx > 0 {
			arr_idx := table.find_or_register_array(new_type(elem_idx))
			return arr_idx
		}
	}
	// Handle fixed array types: [N]T
	else if name.starts_with('[') && name.contains(']') {
		bracket_end := name.index(']') or { return 0 }
		size_str := name[1..bracket_end]
		size := size_str.int()
		if size > 0 || size_str == '0' {
			elem_name := name[bracket_end + 1..]
			elem_idx := resolve_type_name(mut table, elem_name)
			if elem_idx > 0 {
				arr_idx := table.find_or_register_array_fixed(new_type(elem_idx), size,
					empty_expr, false)
				return arr_idx
			}
		}
	}
	// Handle map types: map[K]V
	else if name.starts_with('map[') {
		// Find the matching ] for the key type
		mut depth := 0
		mut key_end := -1
		for i, c in name[4..] {
			if c == `[` {
				depth++
			} else if c == `]` {
				if depth == 0 {
					key_end = i + 4
					break
				}
				depth--
			}
		}
		if key_end > 4 {
			key_name := name[4..key_end]
			value_name := name[key_end + 1..]
			key_idx := resolve_type_name(mut table, key_name)
			value_idx := resolve_type_name(mut table, value_name)
			if key_idx > 0 && value_idx > 0 {
				map_idx := table.find_or_register_map(new_type(key_idx), new_type(value_idx))
				return map_idx
			}
		}
	}
	// Handle channel types: chan T
	else if name.starts_with('chan ') {
		elem_name := name[5..]
		elem_idx := resolve_type_name(mut table, elem_name)
		if elem_idx > 0 {
			chan_idx := table.find_or_register_chan(new_type(elem_idx), false)
			return chan_idx
		}
	}
	// Handle thread types: thread T
	else if name.starts_with('thread ') {
		elem_name := name[7..]
		elem_idx := resolve_type_name(mut table, elem_name)
		if elem_idx > 0 {
			thread_idx := table.find_or_register_thread(new_type(elem_idx))
			return thread_idx
		}
	}
	// Handle function types: fn (params) return
	else if name.starts_with('fn ') || name.starts_with('fn(') {
		// Function types are complex - skip detailed parsing
		// They're typically C callback types that we can't easily recreate
		return 0
	}
	// Handle multi-return types: (T1, T2)
	else if name.starts_with('(') && name.ends_with(')') && name.contains(',') {
		inner := name[1..name.len - 1]
		parts := inner.split(', ')
		mut types := []Type{}
		for part in parts {
			idx := resolve_type_name(mut table, part.trim_space())
			if idx > 0 {
				types << new_type(idx)
			} else {
				return 0
			}
		}
		if types.len > 0 {
			mr_idx := table.find_or_register_multi_return(types)
			return mr_idx
		}
	}

	return 0
}

// resolve_type_name looks up a type name, registering compound types if needed
fn resolve_type_name(mut table Table, name string) int {
	// First check if it exists
	if idx := table.type_idxs[name] {
		return idx
	}
	// Try to register it
	return try_register_type_by_name(mut table, name)
}

// --- Position Serialization ---

// write_pos writes a token.Pos
fn (mut w AstWriter) write_pos(pos token.Pos) {
	w.write_i32(pos.len)
	w.write_i32(pos.line_nr)
	w.write_i32(pos.pos)
	w.write_u16(pos.col)
	w.write_i32(i32(pos.file_idx))
	w.write_i32(pos.last_line)
}

// read_pos reads a token.Pos
fn (mut r AstReader) read_pos() token.Pos {
	len := r.read_i32()
	line_nr := r.read_i32()
	pos := r.read_i32()
	col := r.read_u16()
	file_idx := i16(r.read_i32())
	last_line := r.read_i32()
	return token.Pos{
		len:       len
		line_nr:   line_nr
		pos:       pos
		col:       col
		file_idx:  file_idx
		last_line: last_line
	}
}

// --- Array Serialization Helpers ---

// write_string_array writes an array of strings
fn (mut w AstWriter) write_string_array(arr []string) {
	w.write_u32(u32(arr.len))
	for s in arr {
		w.write_string(s)
	}
}

// read_string_array reads an array of strings
fn (mut r AstReader) read_string_array() []string {
	len := r.read_u32()
	mut arr := []string{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_string()
	}
	return arr
}

// write_type_array writes an array of Types
fn (mut w AstWriter) write_type_array(arr []Type) {
	w.write_u32(u32(arr.len))
	for t in arr {
		w.write_type(t)
	}
}

// read_type_array reads an array of Types
fn (mut r AstReader) read_type_array() []Type {
	len := r.read_u32()
	mut arr := []Type{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_type()
	}
	return arr
}

// write_u8_array writes an array of u8
fn (mut w AstWriter) write_u8_array(arr []u8) {
	w.write_u32(u32(arr.len))
	for b in arr {
		w.buf << b
	}
}

// read_u8_array reads an array of u8
fn (mut r AstReader) read_u8_array() []u8 {
	len := r.read_u32()
	if len == 0 {
		return []
	}
	arr := r.data[r.pos..r.pos + int(len)].clone()
	r.pos += int(len)
	return arr
}

// --- Attr Serialization ---

// write_attr writes an Attr
fn (mut w AstWriter) write_attr(attr Attr) {
	w.write_string(attr.name)
	w.write_bool(attr.has_arg)
	w.write_string(attr.arg)
	w.write_u8(u8(attr.kind))
	w.write_bool(attr.ct_opt)
	w.write_pos(attr.pos)
	w.write_bool(attr.has_at)
	// Skip ct_expr, ct_evaled, ct_skip - these are checker-set
}

// read_attr reads an Attr
fn (mut r AstReader) read_attr() Attr {
	name := r.read_string()
	has_arg := r.read_bool()
	arg := r.read_string()
	kind := unsafe { AttrKind(r.read_u8()) }
	ct_opt := r.read_bool()
	pos := r.read_pos()
	has_at := r.read_bool()
	return Attr{
		name:    name
		has_arg: has_arg
		arg:     arg
		kind:    kind
		ct_opt:  ct_opt
		pos:     pos
		has_at:  has_at
	}
}

// write_attr_array writes an array of Attrs
fn (mut w AstWriter) write_attr_array(attrs []Attr) {
	w.write_u32(u32(attrs.len))
	for attr in attrs {
		w.write_attr(attr)
	}
}

// read_attr_array reads an array of Attrs
fn (mut r AstReader) read_attr_array() []Attr {
	len := r.read_u32()
	mut arr := []Attr{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_attr()
	}
	return arr
}

// --- Comment Serialization ---

// write_comment writes a Comment
fn (mut w AstWriter) write_comment(c Comment) {
	w.write_string(c.text)
	w.write_bool(c.is_multi)
	w.write_pos(c.pos)
}

// read_comment reads a Comment
fn (mut r AstReader) read_comment() Comment {
	text := r.read_string()
	is_multi := r.read_bool()
	pos := r.read_pos()
	return Comment{
		text:     text
		is_multi: is_multi
		pos:      pos
	}
}

// write_comment_array writes an array of Comments
fn (mut w AstWriter) write_comment_array(comments []Comment) {
	w.write_u32(u32(comments.len))
	for c in comments {
		w.write_comment(c)
	}
}

// read_comment_array reads an array of Comments
fn (mut r AstReader) read_comment_array() []Comment {
	len := r.read_u32()
	mut arr := []Comment{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_comment()
	}
	return arr
}

// --- ImportSymbol Serialization ---

// write_import_symbol writes an ImportSymbol
fn (mut w AstWriter) write_import_symbol(sym ImportSymbol) {
	w.write_pos(sym.pos)
	w.write_string(sym.name)
}

// read_import_symbol reads an ImportSymbol
fn (mut r AstReader) read_import_symbol() ImportSymbol {
	pos := r.read_pos()
	name := r.read_string()
	return ImportSymbol{
		pos:  pos
		name: name
	}
}

// --- Module Serialization ---

// write_module writes a Module
fn (mut w AstWriter) write_module(mod Module) {
	w.write_string(mod.name)
	w.write_string(mod.short_name)
	w.write_attr_array(mod.attrs)
	w.write_pos(mod.pos)
	w.write_pos(mod.name_pos)
	w.write_bool(mod.is_skipped)
}

// read_module reads a Module
fn (mut r AstReader) read_module() Module {
	name := r.read_string()
	short_name := r.read_string()
	attrs := r.read_attr_array()
	pos := r.read_pos()
	name_pos := r.read_pos()
	is_skipped := r.read_bool()
	return Module{
		name:       name
		short_name: short_name
		attrs:      attrs
		pos:        pos
		name_pos:   name_pos
		is_skipped: is_skipped
	}
}

// --- Import Serialization ---

// write_import writes an Import
fn (mut w AstWriter) write_import(imp Import) {
	w.write_string(imp.source_name)
	w.write_string(imp.mod)
	w.write_string(imp.alias)
	w.write_pos(imp.pos)
	w.write_pos(imp.mod_pos)
	w.write_pos(imp.alias_pos)
	w.write_pos(imp.syms_pos)
	// Write import symbols
	w.write_u32(u32(imp.syms.len))
	for sym in imp.syms {
		w.write_import_symbol(sym)
	}
	w.write_comment_array(imp.comments)
	w.write_comment_array(imp.next_comments)
}

// read_import reads an Import
fn (mut r AstReader) read_import() Import {
	source_name := r.read_string()
	mod := r.read_string()
	alias := r.read_string()
	pos := r.read_pos()
	mod_pos := r.read_pos()
	alias_pos := r.read_pos()
	syms_pos := r.read_pos()
	// Read import symbols
	syms_len := r.read_u32()
	mut syms := []ImportSymbol{cap: int(syms_len)}
	for _ in 0 .. syms_len {
		syms << r.read_import_symbol()
	}
	comments := r.read_comment_array()
	next_comments := r.read_comment_array()

	return Import{
		source_name:   source_name
		mod:           mod
		alias:         alias
		pos:           pos
		mod_pos:       mod_pos
		alias_pos:     alias_pos
		syms_pos:      syms_pos
		syms:          syms
		comments:      comments
		next_comments: next_comments
	}
}

// --- EmbeddedFile Serialization ---

// write_embedded_file writes an EmbeddedFile
fn (mut w AstWriter) write_embedded_file(ef EmbeddedFile) {
	w.write_string(ef.compression_type)
	w.write_string(ef.rpath)
	w.write_string(ef.apath)
	w.write_bool(ef.is_compressed)
	w.write_u8_array(ef.bytes)
	w.write_i32(i32(ef.len))
}

// read_embedded_file reads an EmbeddedFile
fn (mut r AstReader) read_embedded_file() EmbeddedFile {
	compression_type := r.read_string()
	rpath := r.read_string()
	apath := r.read_string()
	is_compressed := r.read_bool()
	bytes := r.read_u8_array()
	len := int(r.read_i32())
	return EmbeddedFile{
		compression_type: compression_type
		rpath:            rpath
		apath:            apath
		is_compressed:    is_compressed
		bytes:            bytes
		len:              len
	}
}

// --- Param Serialization ---

fn (mut w AstWriter) write_param(p Param) {
	w.write_pos(p.pos)
	w.write_string(p.name)
	w.write_bool(p.is_mut)
	w.write_bool(p.is_shared)
	w.write_bool(p.is_atomic)
	w.write_pos(p.type_pos)
	w.write_bool(p.is_hidden)
	w.write_bool(p.on_newline)
	w.write_type(p.typ)
}

fn (mut r AstReader) read_param() Param {
	pos := r.read_pos()
	name := r.read_string()
	is_mut := r.read_bool()
	is_shared := r.read_bool()
	is_atomic := r.read_bool()
	type_pos := r.read_pos()
	is_hidden := r.read_bool()
	on_newline := r.read_bool()
	typ := r.read_type()
	return Param{
		pos:        pos
		name:       name
		is_mut:     is_mut
		is_shared:  is_shared
		is_atomic:  is_atomic
		type_pos:   type_pos
		is_hidden:  is_hidden
		on_newline: on_newline
		typ:        typ
	}
}

fn (mut w AstWriter) write_param_array(params []Param) {
	w.write_u32(u32(params.len))
	for p in params {
		w.write_param(p)
	}
}

fn (mut r AstReader) read_param_array() []Param {
	len := r.read_u32()
	mut arr := []Param{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_param()
	}
	return arr
}

// --- StructField Serialization ---

fn (mut w AstWriter) write_struct_field(f StructField) {
	w.write_pos(f.pos)
	w.write_pos(f.type_pos)
	w.write_pos(f.option_pos)
	w.write_comment_array(f.pre_comments)
	w.write_comment_array(f.comments)
	w.write_i32(i32(f.i))
	w.write_bool(f.has_default_expr)
	w.write_bool(f.has_prev_newline)
	w.write_bool(f.has_break_line)
	w.write_bool(f.is_pub)
	w.write_string(f.default_val)
	w.write_bool(f.is_mut)
	w.write_bool(f.is_global)
	w.write_bool(f.is_volatile)
	w.write_bool(f.is_deprecated)
	w.write_bool(f.is_embed)
	w.write_attr_array(f.attrs)
	w.write_comment_array(f.next_comments)
	w.write_type(f.typ)
	w.write_string(f.name)
	if f.has_default_expr {
		w.write_expr(f.default_expr)
	}
}

fn (mut r AstReader) read_struct_field() StructField {
	pos := r.read_pos()
	type_pos := r.read_pos()
	option_pos := r.read_pos()
	pre_comments := r.read_comment_array()
	comments := r.read_comment_array()
	i := int(r.read_i32())
	has_default_expr := r.read_bool()
	has_prev_newline := r.read_bool()
	has_break_line := r.read_bool()
	is_pub := r.read_bool()
	default_val := r.read_string()
	is_mut := r.read_bool()
	is_global := r.read_bool()
	is_volatile := r.read_bool()
	is_deprecated := r.read_bool()
	is_embed := r.read_bool()
	attrs := r.read_attr_array()
	next_comments := r.read_comment_array()
	typ := r.read_type()
	name := r.read_string()
	default_expr := if has_default_expr { r.read_expr() } else { empty_expr }

	return StructField{
		pos:              pos
		type_pos:         type_pos
		option_pos:       option_pos
		pre_comments:     pre_comments
		comments:         comments
		i:                i
		has_default_expr: has_default_expr
		has_prev_newline: has_prev_newline
		has_break_line:   has_break_line
		is_pub:           is_pub
		default_val:      default_val
		is_mut:           is_mut
		is_global:        is_global
		is_volatile:      is_volatile
		is_deprecated:    is_deprecated
		is_embed:         is_embed
		attrs:            attrs
		next_comments:    next_comments
		typ:              typ
		name:             name
		default_expr:     default_expr
	}
}

fn (mut w AstWriter) write_struct_field_array(fields []StructField) {
	w.write_u32(u32(fields.len))
	for f in fields {
		w.write_struct_field(f)
	}
}

fn (mut r AstReader) read_struct_field_array() []StructField {
	len := r.read_u32()
	mut arr := []StructField{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_struct_field()
	}
	return arr
}

// --- TypeNode Serialization ---

fn (mut w AstWriter) write_type_node(tn TypeNode) {
	w.write_pos(tn.pos)
	w.write_type(tn.typ)
	w.write_comment_array(tn.end_comments)
}

fn (mut r AstReader) read_type_node() TypeNode {
	pos := r.read_pos()
	typ := r.read_type()
	end_comments := r.read_comment_array()
	return TypeNode{
		pos:          pos
		typ:          typ
		end_comments: end_comments
	}
}

fn (mut w AstWriter) write_type_node_array(arr []TypeNode) {
	w.write_u32(u32(arr.len))
	for tn in arr {
		w.write_type_node(tn)
	}
}

fn (mut r AstReader) read_type_node_array() []TypeNode {
	len := r.read_u32()
	mut arr := []TypeNode{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_type_node()
	}
	return arr
}

// --- Embed Serialization ---

fn (mut w AstWriter) write_embed(e Embed) {
	w.write_type(e.typ)
	w.write_pos(e.pos)
	w.write_comment_array(e.comments)
}

fn (mut r AstReader) read_embed() Embed {
	typ := r.read_type()
	pos := r.read_pos()
	comments := r.read_comment_array()
	return Embed{
		typ:      typ
		pos:      pos
		comments: comments
	}
}

fn (mut w AstWriter) write_embed_array(arr []Embed) {
	w.write_u32(u32(arr.len))
	for e in arr {
		w.write_embed(e)
	}
}

fn (mut r AstReader) read_embed_array() []Embed {
	len := r.read_u32()
	mut arr := []Embed{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_embed()
	}
	return arr
}

// --- ConstField Serialization ---

fn (mut w AstWriter) write_const_field(f ConstField) {
	w.write_string(f.mod)
	w.write_string(f.name)
	w.write_bool(f.is_pub)
	w.write_bool(f.is_markused)
	w.write_bool(f.is_exported)
	w.write_pos(f.pos)
	w.write_attr_array(f.attrs)
	w.write_bool(f.is_virtual_c)
	w.write_expr(f.expr)
	w.write_type(f.typ)
	w.write_comment_array(f.comments)
	w.write_comment_array(f.end_comments)
}

fn (mut r AstReader) read_const_field() ConstField {
	mod := r.read_string()
	name := r.read_string()
	is_pub := r.read_bool()
	is_markused := r.read_bool()
	is_exported := r.read_bool()
	pos := r.read_pos()
	attrs := r.read_attr_array()
	is_virtual_c := r.read_bool()
	expr := r.read_expr()
	typ := r.read_type()
	comments := r.read_comment_array()
	end_comments := r.read_comment_array()
	return ConstField{
		mod:          mod
		name:         name
		is_pub:       is_pub
		is_markused:  is_markused
		is_exported:  is_exported
		pos:          pos
		attrs:        attrs
		is_virtual_c: is_virtual_c
		expr:         expr
		typ:          typ
		comments:     comments
		end_comments: end_comments
	}
}

fn (mut w AstWriter) write_const_field_array(arr []ConstField) {
	w.write_u32(u32(arr.len))
	for f in arr {
		w.write_const_field(f)
	}
}

fn (mut r AstReader) read_const_field_array() []ConstField {
	len := r.read_u32()
	mut arr := []ConstField{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_const_field()
	}
	return arr
}

// --- GlobalField Serialization ---

fn (mut w AstWriter) write_global_field(f GlobalField) {
	w.write_string(f.name)
	w.write_bool(f.has_expr)
	w.write_pos(f.pos)
	w.write_pos(f.typ_pos)
	w.write_bool(f.is_markused)
	w.write_bool(f.is_volatile)
	w.write_bool(f.is_exported)
	w.write_bool(f.is_weak)
	w.write_bool(f.is_hidden)
	w.write_u8(u8(f.language))
	w.write_bool(f.is_extern)
	w.write_type(f.typ)
	w.write_comment_array(f.comments)
	if f.has_expr {
		w.write_expr(f.expr)
	}
}

fn (mut r AstReader) read_global_field() GlobalField {
	name := r.read_string()
	has_expr := r.read_bool()
	pos := r.read_pos()
	typ_pos := r.read_pos()
	is_markused := r.read_bool()
	is_volatile := r.read_bool()
	is_exported := r.read_bool()
	is_weak := r.read_bool()
	is_hidden := r.read_bool()
	language := unsafe { Language(r.read_u8()) }
	is_extern := r.read_bool()
	typ := r.read_type()
	comments := r.read_comment_array()
	expr := if has_expr { r.read_expr() } else { empty_expr }

	return GlobalField{
		name:        name
		has_expr:    has_expr
		pos:         pos
		typ_pos:     typ_pos
		is_markused: is_markused
		is_volatile: is_volatile
		is_exported: is_exported
		is_weak:     is_weak
		is_hidden:   is_hidden
		language:    language
		is_extern:   is_extern
		typ:         typ
		comments:    comments
		expr:        expr
	}
}

fn (mut w AstWriter) write_global_field_array(arr []GlobalField) {
	w.write_u32(u32(arr.len))
	for f in arr {
		w.write_global_field(f)
	}
}

fn (mut r AstReader) read_global_field_array() []GlobalField {
	len := r.read_u32()
	mut arr := []GlobalField{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_global_field()
	}
	return arr
}

// --- EnumField Serialization ---

fn (mut w AstWriter) write_enum_field(f EnumField) {
	w.write_string(f.name)
	w.write_string(f.source_name)
	w.write_pos(f.pos)
	w.write_comment_array(f.pre_comments)
	w.write_comment_array(f.comments)
	w.write_comment_array(f.next_comments)
	w.write_bool(f.has_expr)
	w.write_bool(f.has_prev_newline)
	w.write_bool(f.has_break_line)
	w.write_attr_array(f.attrs)
	if f.has_expr {
		w.write_expr(f.expr)
	}
}

fn (mut r AstReader) read_enum_field() EnumField {
	name := r.read_string()
	source_name := r.read_string()
	pos := r.read_pos()
	pre_comments := r.read_comment_array()
	comments := r.read_comment_array()
	next_comments := r.read_comment_array()
	has_expr := r.read_bool()
	has_prev_newline := r.read_bool()
	has_break_line := r.read_bool()
	attrs := r.read_attr_array()
	expr := if has_expr { r.read_expr() } else { empty_expr }

	return EnumField{
		name:             name
		source_name:      source_name
		pos:              pos
		pre_comments:     pre_comments
		comments:         comments
		next_comments:    next_comments
		has_expr:         has_expr
		has_prev_newline: has_prev_newline
		has_break_line:   has_break_line
		attrs:            attrs
		expr:             expr
	}
}

fn (mut w AstWriter) write_enum_field_array(arr []EnumField) {
	w.write_u32(u32(arr.len))
	for f in arr {
		w.write_enum_field(f)
	}
}

fn (mut r AstReader) read_enum_field_array() []EnumField {
	len := r.read_u32()
	mut arr := []EnumField{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_enum_field()
	}
	return arr
}

// --- InterfaceEmbedding Serialization ---

fn (mut w AstWriter) write_interface_embedding(e InterfaceEmbedding) {
	w.write_string(e.name)
	w.write_type(e.typ)
	w.write_pos(e.pos)
	w.write_comment_array(e.comments)
}

fn (mut r AstReader) read_interface_embedding() InterfaceEmbedding {
	name := r.read_string()
	typ := r.read_type()
	pos := r.read_pos()
	comments := r.read_comment_array()
	return InterfaceEmbedding{
		name:     name
		typ:      typ
		pos:      pos
		comments: comments
	}
}

fn (mut w AstWriter) write_interface_embedding_array(arr []InterfaceEmbedding) {
	w.write_u32(u32(arr.len))
	for e in arr {
		w.write_interface_embedding(e)
	}
}

fn (mut r AstReader) read_interface_embedding_array() []InterfaceEmbedding {
	len := r.read_u32()
	mut arr := []InterfaceEmbedding{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_interface_embedding()
	}
	return arr
}

// --- Statement Array Serialization ---

fn (mut w AstWriter) write_stmt_array(stmts []Stmt) {
	w.write_u32(u32(stmts.len))
	for stmt in stmts {
		w.write_stmt(stmt)
	}
}

fn (mut r AstReader) read_stmt_array() []Stmt {
	len := r.read_u32()
	mut arr := []Stmt{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_stmt()
	}
	return arr
}

// --- Expression Array Serialization ---

fn (mut w AstWriter) write_expr_array(exprs []Expr) {
	w.write_u32(u32(exprs.len))
	for expr in exprs {
		w.write_expr(expr)
	}
}

fn (mut r AstReader) read_expr_array() []Expr {
	len := r.read_u32()
	mut arr := []Expr{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_expr()
	}
	return arr
}

// --- Statement Serialization ---

// write_stmt writes a Stmt
fn (mut w AstWriter) write_stmt(stmt Stmt) {
	match stmt {
		EmptyStmt {
			w.write_u8(u8(StmtKind.empty_stmt))
			w.write_pos(stmt.pos)
		}
		SemicolonStmt {
			w.write_u8(u8(StmtKind.semicolon_stmt))
			w.write_pos(stmt.pos)
		}
		NodeError {
			w.write_u8(u8(StmtKind.node_error))
			w.write_i32(i32(stmt.idx))
			w.write_pos(stmt.pos)
		}
		GotoLabel {
			w.write_u8(u8(StmtKind.goto_label))
			w.write_string(stmt.name)
			w.write_pos(stmt.pos)
		}
		GotoStmt {
			w.write_u8(u8(StmtKind.goto_stmt))
			w.write_string(stmt.name)
			w.write_pos(stmt.pos)
		}
		DebuggerStmt {
			w.write_u8(u8(StmtKind.debugger_stmt))
			w.write_pos(stmt.pos)
		}
		BranchStmt {
			w.write_u8(u8(StmtKind.branch_stmt))
			w.write_u8(u8(stmt.kind))
			w.write_string(stmt.label)
			w.write_pos(stmt.pos)
		}
		ExprStmt {
			w.write_u8(u8(StmtKind.expr_stmt))
			w.write_pos(stmt.pos)
			w.write_comment_array(stmt.comments)
			w.write_expr(stmt.expr)
			w.write_bool(stmt.is_expr)
		}
		Return {
			w.write_u8(u8(StmtKind.return_stmt))
			w.write_pos(stmt.pos)
			w.write_comment_array(stmt.comments)
			w.write_expr_array(stmt.exprs)
		}
		AssertStmt {
			w.write_u8(u8(StmtKind.assert_stmt))
			w.write_pos(stmt.pos)
			w.write_pos(stmt.extra_pos)
			w.write_expr(stmt.expr)
			w.write_expr(stmt.extra)
		}
		Block {
			w.write_u8(u8(StmtKind.block))
			w.write_bool(stmt.is_unsafe)
			w.write_pos(stmt.pos)
			w.write_stmt_array(stmt.stmts)
		}
		DeferStmt {
			w.write_u8(u8(StmtKind.defer_stmt))
			w.write_pos(stmt.pos)
			w.write_u8(u8(stmt.mode))
			w.write_stmt_array(stmt.stmts)
		}
		HashStmt {
			w.write_u8(u8(StmtKind.hash_stmt))
			w.write_string(stmt.mod)
			w.write_pos(stmt.pos)
			w.write_string(stmt.source_file)
			w.write_bool(stmt.is_use_once)
			w.write_string(stmt.val)
			w.write_string(stmt.kind)
			w.write_string(stmt.main)
			w.write_string(stmt.msg)
			w.write_attr_array(stmt.attrs)
		}
		ForStmt {
			w.write_u8(u8(StmtKind.for_stmt))
			w.write_bool(stmt.is_inf)
			w.write_pos(stmt.pos)
			w.write_comment_array(stmt.comments)
			w.write_expr(stmt.cond)
			w.write_stmt_array(stmt.stmts)
			w.write_string(stmt.label)
		}
		ForInStmt {
			w.write_u8(u8(StmtKind.for_in_stmt))
			w.write_string(stmt.key_var)
			w.write_string(stmt.val_var)
			w.write_bool(stmt.is_range)
			w.write_pos(stmt.pos)
			w.write_pos(stmt.kv_pos)
			w.write_pos(stmt.vv_pos)
			w.write_comment_array(stmt.comments)
			w.write_bool(stmt.val_is_mut)
			w.write_expr(stmt.cond)
			w.write_expr(stmt.high)
			w.write_string(stmt.label)
			w.write_stmt_array(stmt.stmts)
		}
		ForCStmt {
			w.write_u8(u8(StmtKind.for_c_stmt))
			w.write_bool(stmt.has_init)
			w.write_bool(stmt.has_cond)
			w.write_bool(stmt.has_inc)
			w.write_bool(stmt.is_multi)
			w.write_pos(stmt.pos)
			w.write_comment_array(stmt.comments)
			if stmt.has_init {
				w.write_stmt(stmt.init)
			}
			if stmt.has_cond {
				w.write_expr(stmt.cond)
			}
			if stmt.has_inc {
				w.write_stmt(stmt.inc)
			}
			w.write_stmt_array(stmt.stmts)
			w.write_string(stmt.label)
		}
		AssignStmt {
			w.write_u8(u8(StmtKind.assign_stmt))
			w.write_u8(u8(stmt.op))
			w.write_pos(stmt.pos)
			w.write_comment_array(stmt.end_comments)
			w.write_expr_array(stmt.right)
			w.write_expr_array(stmt.left)
			w.write_bool(stmt.is_static)
			w.write_bool(stmt.is_volatile)
			w.write_bool(stmt.is_simple)
			w.write_bool(stmt.has_cross_var)
			w.write_attr(stmt.attr)
		}
		ConstDecl {
			w.write_u8(u8(StmtKind.const_decl))
			w.write_bool(stmt.is_pub)
			w.write_pos(stmt.pos)
			w.write_attr_array(stmt.attrs)
			w.write_const_field_array(stmt.fields)
			w.write_comment_array(stmt.end_comments)
			w.write_bool(stmt.is_block)
		}
		GlobalDecl {
			w.write_u8(u8(StmtKind.global_decl))
			w.write_string(stmt.mod)
			w.write_pos(stmt.pos)
			w.write_bool(stmt.is_block)
			w.write_attr_array(stmt.attrs)
			w.write_global_field_array(stmt.fields)
			w.write_comment_array(stmt.end_comments)
		}
		EnumDecl {
			w.write_u8(u8(StmtKind.enum_decl))
			w.write_string(stmt.name)
			w.write_bool(stmt.is_pub)
			w.write_bool(stmt.is_flag)
			w.write_bool(stmt.is_multi_allowed)
			w.write_comment_array(stmt.comments)
			w.write_enum_field_array(stmt.fields)
			w.write_attr_array(stmt.attrs)
			w.write_type(stmt.typ)
			w.write_pos(stmt.typ_pos)
			w.write_pos(stmt.pos)
		}
		StructDecl {
			w.write_u8(u8(StmtKind.struct_decl))
			w.write_pos(stmt.pos)
			w.write_string(stmt.name)
			w.write_string(stmt.scoped_name)
			w.write_type_array(stmt.generic_types)
			w.write_bool(stmt.is_pub)
			w.write_i32(i32(stmt.mut_pos))
			w.write_i32(i32(stmt.pub_pos))
			w.write_i32(i32(stmt.pub_mut_pos))
			w.write_i32(i32(stmt.global_pos))
			w.write_i32(i32(stmt.module_pos))
			w.write_bool(stmt.is_union)
			w.write_bool(stmt.is_option)
			w.write_bool(stmt.is_aligned)
			w.write_attr_array(stmt.attrs)
			w.write_comment_array(stmt.pre_comments)
			w.write_comment_array(stmt.end_comments)
			w.write_embed_array(stmt.embeds)
			w.write_bool(stmt.is_implements)
			w.write_type_node_array(stmt.implements_types)
			w.write_u8(u8(stmt.language))
			w.write_struct_field_array(stmt.fields)
		}
		InterfaceDecl {
			w.write_u8(u8(StmtKind.interface_decl))
			w.write_string(stmt.name)
			w.write_type(stmt.typ)
			w.write_pos(stmt.name_pos)
			w.write_u8(u8(stmt.language))
			w.write_string_array(stmt.field_names)
			w.write_bool(stmt.is_pub)
			w.write_i32(i32(stmt.mut_pos))
			w.write_pos(stmt.pos)
			w.write_comment_array(stmt.pre_comments)
			w.write_type_array(stmt.generic_types)
			w.write_attr_array(stmt.attrs)
			w.write_struct_field_array(stmt.fields)
			w.write_interface_embedding_array(stmt.embeds)
			// Methods are FnDecl - write separately
			w.write_u32(u32(stmt.methods.len))
			for m in stmt.methods {
				w.write_fn_decl(m)
			}
		}
		FnDecl {
			w.write_u8(u8(StmtKind.fn_decl))
			w.write_fn_decl(stmt)
		}
		Module {
			w.write_u8(u8(StmtKind.module_stmt))
			w.write_module(stmt)
		}
		Import {
			w.write_u8(u8(StmtKind.import_stmt))
			w.write_import(stmt)
		}
		TypeDecl {
			w.write_u8(u8(StmtKind.type_decl))
			w.write_type_decl(stmt)
		}
		ComptimeFor {
			w.write_u8(u8(StmtKind.comptime_for))
			w.write_string(stmt.val_var)
			w.write_u8(u8(stmt.kind))
			w.write_pos(stmt.pos)
			w.write_pos(stmt.typ_pos)
			w.write_stmt_array(stmt.stmts)
			w.write_type(stmt.typ)
			w.write_expr(stmt.expr)
		}
		AsmStmt {
			w.write_u8(u8(StmtKind.asm_stmt))
			w.write_asm_stmt(stmt)
		}
		SqlStmt {
			w.write_u8(u8(StmtKind.sql_stmt))
			w.write_sql_stmt(stmt)
		}
	}
}

// read_stmt reads a Stmt
fn (mut r AstReader) read_stmt() Stmt {
	kind := unsafe { StmtKind(r.read_u8()) }
	match kind {
		.empty_stmt {
			return EmptyStmt{
				pos: r.read_pos()
			}
		}
		.semicolon_stmt {
			return SemicolonStmt{
				pos: r.read_pos()
			}
		}
		.node_error {
			idx := int(r.read_i32())
			pos := r.read_pos()
			return NodeError{
				idx: idx
				pos: pos
			}
		}
		.goto_label {
			name := r.read_string()
			pos := r.read_pos()
			return GotoLabel{
				name: name
				pos:  pos
			}
		}
		.goto_stmt {
			name := r.read_string()
			pos := r.read_pos()
			return GotoStmt{
				name: name
				pos:  pos
			}
		}
		.debugger_stmt {
			pos := r.read_pos()
			return DebuggerStmt{
				pos: pos
			}
		}
		.branch_stmt {
			branch_kind := unsafe { token.Kind(r.read_u8()) }
			label := r.read_string()
			pos := r.read_pos()
			return BranchStmt{
				kind:  branch_kind
				label: label
				scope: unsafe { nil }
				pos:   pos
			}
		}
		.expr_stmt {
			pos := r.read_pos()
			comments := r.read_comment_array()
			expr := r.read_expr()
			is_expr := r.read_bool()
			return ExprStmt{
				pos:      pos
				comments: comments
				expr:     expr
				is_expr:  is_expr
			}
		}
		.return_stmt {
			pos := r.read_pos()
			comments := r.read_comment_array()
			exprs := r.read_expr_array()
			return Return{
				scope:    unsafe { nil }
				pos:      pos
				comments: comments
				exprs:    exprs
			}
		}
		.assert_stmt {
			pos := r.read_pos()
			extra_pos := r.read_pos()
			expr := r.read_expr()
			extra := r.read_expr()
			return AssertStmt{
				pos:       pos
				extra_pos: extra_pos
				expr:      expr
				extra:     extra
			}
		}
		.block {
			is_unsafe := r.read_bool()
			pos := r.read_pos()
			stmts := r.read_stmt_array()
			return Block{
				is_unsafe: is_unsafe
				pos:       pos
				scope:     unsafe { nil }
				stmts:     stmts
			}
		}
		.defer_stmt {
			pos := r.read_pos()
			mode := unsafe { DeferMode(r.read_u8()) }
			stmts := r.read_stmt_array()
			return DeferStmt{
				pos:   pos
				scope: unsafe { nil }
				mode:  mode
				stmts: stmts
			}
		}
		.hash_stmt {
			mod := r.read_string()
			pos := r.read_pos()
			source_file := r.read_string()
			is_use_once := r.read_bool()
			val := r.read_string()
			hash_kind := r.read_string()
			main := r.read_string()
			msg := r.read_string()
			attrs := r.read_attr_array()
			return HashStmt{
				mod:         mod
				pos:         pos
				source_file: source_file
				is_use_once: is_use_once
				val:         val
				kind:        hash_kind
				main:        main
				msg:         msg
				attrs:       attrs
			}
		}
		.for_stmt {
			is_inf := r.read_bool()
			pos := r.read_pos()
			comments := r.read_comment_array()
			cond := r.read_expr()
			stmts := r.read_stmt_array()
			label := r.read_string()
			return ForStmt{
				is_inf:   is_inf
				pos:      pos
				comments: comments
				cond:     cond
				stmts:    stmts
				label:    label
			}
		}
		.for_in_stmt {
			key_var := r.read_string()
			val_var := r.read_string()
			is_range := r.read_bool()
			pos := r.read_pos()
			kv_pos := r.read_pos()
			vv_pos := r.read_pos()
			comments := r.read_comment_array()
			val_is_mut := r.read_bool()
			cond := r.read_expr()
			high := r.read_expr()
			label := r.read_string()
			stmts := r.read_stmt_array()
			return ForInStmt{
				key_var:    key_var
				val_var:    val_var
				is_range:   is_range
				pos:        pos
				kv_pos:     kv_pos
				vv_pos:     vv_pos
				comments:   comments
				val_is_mut: val_is_mut
				cond:       cond
				high:       high
				label:      label
				stmts:      stmts
			}
		}
		.for_c_stmt {
			has_init := r.read_bool()
			has_cond := r.read_bool()
			has_inc := r.read_bool()
			is_multi := r.read_bool()
			pos := r.read_pos()
			comments := r.read_comment_array()
			init := if has_init { r.read_stmt() } else { empty_stmt }
			cond := if has_cond { r.read_expr() } else { empty_expr }
			inc := if has_inc { r.read_stmt() } else { empty_stmt }
			stmts := r.read_stmt_array()
			label := r.read_string()
			return ForCStmt{
				has_init: has_init
				has_cond: has_cond
				has_inc:  has_inc
				is_multi: is_multi
				pos:      pos
				comments: comments
				init:     init
				cond:     cond
				inc:      inc
				stmts:    stmts
				label:    label
			}
		}
		.assign_stmt {
			op := unsafe { token.Kind(r.read_u8()) }
			pos := r.read_pos()
			end_comments := r.read_comment_array()
			right := r.read_expr_array()
			left := r.read_expr_array()
			is_static := r.read_bool()
			is_volatile := r.read_bool()
			is_simple := r.read_bool()
			has_cross_var := r.read_bool()
			attr := r.read_attr()
			return AssignStmt{
				op:            op
				pos:           pos
				end_comments:  end_comments
				right:         right
				left:          left
				is_static:     is_static
				is_volatile:   is_volatile
				is_simple:     is_simple
				has_cross_var: has_cross_var
				attr:          attr
			}
		}
		.const_decl {
			is_pub := r.read_bool()
			pos := r.read_pos()
			attrs := r.read_attr_array()
			fields := r.read_const_field_array()
			end_comments := r.read_comment_array()
			is_block := r.read_bool()
			return ConstDecl{
				is_pub:       is_pub
				pos:          pos
				attrs:        attrs
				fields:       fields
				end_comments: end_comments
				is_block:     is_block
			}
		}
		.global_decl {
			mod := r.read_string()
			pos := r.read_pos()
			is_block := r.read_bool()
			attrs := r.read_attr_array()
			fields := r.read_global_field_array()
			end_comments := r.read_comment_array()
			return GlobalDecl{
				mod:          mod
				pos:          pos
				is_block:     is_block
				attrs:        attrs
				fields:       fields
				end_comments: end_comments
			}
		}
		.enum_decl {
			name := r.read_string()
			is_pub := r.read_bool()
			is_flag := r.read_bool()
			is_multi_allowed := r.read_bool()
			comments := r.read_comment_array()
			fields := r.read_enum_field_array()
			attrs := r.read_attr_array()
			typ := r.read_type()
			typ_pos := r.read_pos()
			pos := r.read_pos()
			return EnumDecl{
				name:             name
				is_pub:           is_pub
				is_flag:          is_flag
				is_multi_allowed: is_multi_allowed
				comments:         comments
				fields:           fields
				attrs:            attrs
				typ:              typ
				typ_pos:          typ_pos
				pos:              pos
			}
		}
		.struct_decl {
			pos := r.read_pos()
			name := r.read_string()
			scoped_name := r.read_string()
			generic_types := r.read_type_array()
			is_pub := r.read_bool()
			mut_pos := int(r.read_i32())
			pub_pos := int(r.read_i32())
			pub_mut_pos := int(r.read_i32())
			global_pos := int(r.read_i32())
			module_pos := int(r.read_i32())
			is_union := r.read_bool()
			is_option := r.read_bool()
			is_aligned := r.read_bool()
			attrs := r.read_attr_array()
			pre_comments := r.read_comment_array()
			end_comments := r.read_comment_array()
			embeds := r.read_embed_array()
			is_implements := r.read_bool()
			implements_types := r.read_type_node_array()
			language := unsafe { Language(r.read_u8()) }
			fields := r.read_struct_field_array()
			return StructDecl{
				pos:              pos
				name:             name
				scoped_name:      scoped_name
				generic_types:    generic_types
				is_pub:           is_pub
				mut_pos:          mut_pos
				pub_pos:          pub_pos
				pub_mut_pos:      pub_mut_pos
				global_pos:       global_pos
				module_pos:       module_pos
				is_union:         is_union
				is_option:        is_option
				is_aligned:       is_aligned
				attrs:            attrs
				pre_comments:     pre_comments
				end_comments:     end_comments
				embeds:           embeds
				is_implements:    is_implements
				implements_types: implements_types
				language:         language
				fields:           fields
			}
		}
		.interface_decl {
			name := r.read_string()
			typ := r.read_type()
			name_pos := r.read_pos()
			language := unsafe { Language(r.read_u8()) }
			field_names := r.read_string_array()
			is_pub := r.read_bool()
			mut_pos := int(r.read_i32())
			pos := r.read_pos()
			pre_comments := r.read_comment_array()
			generic_types := r.read_type_array()
			attrs := r.read_attr_array()
			fields := r.read_struct_field_array()
			embeds := r.read_interface_embedding_array()
			// Read methods
			methods_len := r.read_u32()
			mut methods := []FnDecl{cap: int(methods_len)}
			for _ in 0 .. methods_len {
				methods << r.read_fn_decl()
			}
			return InterfaceDecl{
				name:          name
				typ:           typ
				name_pos:      name_pos
				language:      language
				field_names:   field_names
				is_pub:        is_pub
				mut_pos:       mut_pos
				pos:           pos
				pre_comments:  pre_comments
				generic_types: generic_types
				attrs:         attrs
				fields:        fields
				embeds:        embeds
				methods:       methods
			}
		}
		.fn_decl {
			return r.read_fn_decl()
		}
		.module_stmt {
			return r.read_module()
		}
		.import_stmt {
			return r.read_import()
		}
		.type_decl {
			return r.read_type_decl()
		}
		.comptime_for {
			val_var := r.read_string()
			comptime_kind := unsafe { ComptimeForKind(r.read_u8()) }
			pos := r.read_pos()
			typ_pos := r.read_pos()
			stmts := r.read_stmt_array()
			typ := r.read_type()
			expr := r.read_expr()
			return ComptimeFor{
				val_var: val_var
				kind:    comptime_kind
				pos:     pos
				typ_pos: typ_pos
				stmts:   stmts
				typ:     typ
				expr:    expr
			}
		}
		.asm_stmt {
			return r.read_asm_stmt()
		}
		.sql_stmt {
			return r.read_sql_stmt()
		}
	}
}

// --- FnDecl Serialization ---

fn (mut w AstWriter) write_fn_decl(f FnDecl) {
	w.write_string(f.name)
	w.write_string(f.short_name)
	w.write_string(f.mod)
	w.write_u8(u8(f.kind))
	w.write_bool(f.is_deprecated)
	w.write_bool(f.is_pub)
	w.write_bool(f.is_c_variadic)
	w.write_bool(f.is_c_extern)
	w.write_bool(f.is_variadic)
	w.write_bool(f.is_anon)
	w.write_bool(f.is_weak)
	w.write_bool(f.is_noreturn)
	w.write_bool(f.is_manualfree)
	w.write_bool(f.is_main)
	w.write_bool(f.is_test)
	w.write_bool(f.is_conditional)
	w.write_bool(f.is_exported)
	w.write_bool(f.is_keep_alive)
	w.write_bool(f.is_unsafe)
	w.write_bool(f.is_must_use)
	w.write_bool(f.is_markused)
	w.write_bool(f.is_ignore_overflow)
	w.write_bool(f.is_file_translated)
	w.write_bool(f.is_closure)
	w.write_struct_field(f.receiver)
	w.write_pos(f.receiver_pos)
	w.write_bool(f.is_method)
	w.write_bool(f.is_static_type_method)
	w.write_pos(f.static_type_pos)
	w.write_pos(f.method_type_pos)
	w.write_i32(i32(f.method_idx))
	w.write_bool(f.rec_mut)
	w.write_bool(f.has_prev_newline)
	w.write_bool(f.has_break_line)
	w.write_u8(u8(f.rec_share))
	w.write_u8(u8(f.language))
	w.write_u8(u8(f.file_mode))
	w.write_bool(f.no_body)
	w.write_bool(f.is_builtin)
	w.write_pos(f.name_pos)
	w.write_pos(f.body_pos)
	w.write_string(f.file)
	w.write_string_array(f.generic_names)
	w.write_bool(f.is_direct_arr)
	w.write_attr_array(f.attrs)
	w.write_i32(i32(f.ctdefine_idx))
	w.write_param_array(f.params)
	w.write_stmt_array(f.stmts)
	w.write_type(f.return_type)
	w.write_pos(f.return_type_pos)
	w.write_comment_array(f.comments)
	w.write_comment_array(f.end_comments)
}

fn (mut r AstReader) read_fn_decl() FnDecl {
	name := r.read_string()
	short_name := r.read_string()
	mod := r.read_string()
	kind := unsafe { CallKind(r.read_u8()) }
	is_deprecated := r.read_bool()
	is_pub := r.read_bool()
	is_c_variadic := r.read_bool()
	is_c_extern := r.read_bool()
	is_variadic := r.read_bool()
	is_anon := r.read_bool()
	is_weak := r.read_bool()
	is_noreturn := r.read_bool()
	is_manualfree := r.read_bool()
	is_main := r.read_bool()
	is_test := r.read_bool()
	is_conditional := r.read_bool()
	is_exported := r.read_bool()
	is_keep_alive := r.read_bool()
	is_unsafe := r.read_bool()
	is_must_use := r.read_bool()
	is_markused := r.read_bool()
	is_ignore_overflow := r.read_bool()
	is_file_translated := r.read_bool()
	is_closure := r.read_bool()
	receiver := r.read_struct_field()
	receiver_pos := r.read_pos()
	is_method := r.read_bool()
	is_static_type_method := r.read_bool()
	static_type_pos := r.read_pos()
	method_type_pos := r.read_pos()
	method_idx := int(r.read_i32())
	rec_mut := r.read_bool()
	has_prev_newline := r.read_bool()
	has_break_line := r.read_bool()
	rec_share := unsafe { ShareType(r.read_u8()) }
	language := unsafe { Language(r.read_u8()) }
	file_mode := unsafe { Language(r.read_u8()) }
	no_body := r.read_bool()
	is_builtin := r.read_bool()
	name_pos := r.read_pos()
	body_pos := r.read_pos()
	file := r.read_string()
	generic_names := r.read_string_array()
	is_direct_arr := r.read_bool()
	attrs := r.read_attr_array()
	ctdefine_idx := int(r.read_i32())
	params := r.read_param_array()
	stmts := r.read_stmt_array()
	return_type := r.read_type()
	return_type_pos := r.read_pos()
	comments := r.read_comment_array()
	end_comments := r.read_comment_array()

	return FnDecl{
		name:                  name
		short_name:            short_name
		mod:                   mod
		kind:                  kind
		is_deprecated:         is_deprecated
		is_pub:                is_pub
		is_c_variadic:         is_c_variadic
		is_c_extern:           is_c_extern
		is_variadic:           is_variadic
		is_anon:               is_anon
		is_weak:               is_weak
		is_noreturn:           is_noreturn
		is_manualfree:         is_manualfree
		is_main:               is_main
		is_test:               is_test
		is_conditional:        is_conditional
		is_exported:           is_exported
		is_keep_alive:         is_keep_alive
		is_unsafe:             is_unsafe
		is_must_use:           is_must_use
		is_markused:           is_markused
		is_ignore_overflow:    is_ignore_overflow
		is_file_translated:    is_file_translated
		is_closure:            is_closure
		receiver:              receiver
		receiver_pos:          receiver_pos
		is_method:             is_method
		is_static_type_method: is_static_type_method
		static_type_pos:       static_type_pos
		method_type_pos:       method_type_pos
		method_idx:            method_idx
		rec_mut:               rec_mut
		has_prev_newline:      has_prev_newline
		has_break_line:        has_break_line
		rec_share:             rec_share
		language:              language
		file_mode:             file_mode
		no_body:               no_body
		is_builtin:            is_builtin
		name_pos:              name_pos
		body_pos:              body_pos
		file:                  file
		generic_names:         generic_names
		is_direct_arr:         is_direct_arr
		attrs:                 attrs
		ctdefine_idx:          ctdefine_idx
		params:                params
		stmts:                 stmts
		return_type:           return_type
		return_type_pos:       return_type_pos
		comments:              comments
		end_comments:          end_comments
	}
}

// --- TypeDecl Serialization ---

// TypeDeclKind discriminator
enum TypeDeclKind as u8 {
	alias_type_decl
	fn_type_decl
	sum_type_decl
}

fn (mut w AstWriter) write_type_decl(td TypeDecl) {
	match td {
		AliasTypeDecl {
			w.write_u8(u8(TypeDeclKind.alias_type_decl))
			w.write_string(td.name)
			w.write_string(td.mod)
			w.write_bool(td.is_pub)
			w.write_type(td.typ)
			w.write_pos(td.pos)
			w.write_pos(td.type_pos)
			w.write_comment_array(td.comments)
			w.write_attr_array(td.attrs)
		}
		FnTypeDecl {
			w.write_u8(u8(TypeDeclKind.fn_type_decl))
			w.write_string(td.name)
			w.write_string(td.mod)
			w.write_bool(td.is_pub)
			w.write_type(td.typ)
			w.write_pos(td.pos)
			w.write_pos(td.type_pos)
			w.write_comment_array(td.comments)
			w.write_type_array(td.generic_types)
			w.write_attr_array(td.attrs)
			w.write_bool(td.is_markused)
		}
		SumTypeDecl {
			w.write_u8(u8(TypeDeclKind.sum_type_decl))
			w.write_string(td.name)
			w.write_string(td.mod)
			w.write_bool(td.is_pub)
			w.write_pos(td.pos)
			w.write_pos(td.name_pos)
			w.write_type(td.typ)
			w.write_type_array(td.generic_types)
			w.write_attr_array(td.attrs)
			w.write_type_node_array(td.variants)
		}
	}
}

fn (mut r AstReader) read_type_decl() TypeDecl {
	kind := unsafe { TypeDeclKind(r.read_u8()) }
	match kind {
		.alias_type_decl {
			return AliasTypeDecl{
				name:     r.read_string()
				mod:      r.read_string()
				is_pub:   r.read_bool()
				typ:      r.read_type()
				pos:      r.read_pos()
				type_pos: r.read_pos()
				comments: r.read_comment_array()
				attrs:    r.read_attr_array()
			}
		}
		.fn_type_decl {
			return FnTypeDecl{
				name:          r.read_string()
				mod:           r.read_string()
				is_pub:        r.read_bool()
				typ:           r.read_type()
				pos:           r.read_pos()
				type_pos:      r.read_pos()
				comments:      r.read_comment_array()
				generic_types: r.read_type_array()
				attrs:         r.read_attr_array()
				is_markused:   r.read_bool()
			}
		}
		.sum_type_decl {
			return SumTypeDecl{
				name:          r.read_string()
				mod:           r.read_string()
				is_pub:        r.read_bool()
				pos:           r.read_pos()
				name_pos:      r.read_pos()
				typ:           r.read_type()
				generic_types: r.read_type_array()
				attrs:         r.read_attr_array()
				variants:      r.read_type_node_array()
			}
		}
	}
}

// --- AsmStmt Serialization (simplified - complex asm is rare) ---

fn (mut w AstWriter) write_asm_stmt(a AsmStmt) {
	// Write basic fields - full asm serialization is complex, simplify for now
	w.write_bool(a.is_basic)
	w.write_bool(a.is_volatile)
	w.write_bool(a.is_goto)
	w.write_pos(a.pos)
	w.write_string_array(a.global_labels)
	w.write_string_array(a.local_labels)
	// Skip templates, output, input, clobbered for now - complex types
}

fn (mut r AstReader) read_asm_stmt() AsmStmt {
	is_basic := r.read_bool()
	is_volatile := r.read_bool()
	is_goto := r.read_bool()
	pos := r.read_pos()
	global_labels := r.read_string_array()
	local_labels := r.read_string_array()
	return AsmStmt{
		is_basic:      is_basic
		is_volatile:   is_volatile
		is_goto:       is_goto
		pos:           pos
		global_labels: global_labels
		local_labels:  local_labels
	}
}

// --- SqlStmt Serialization (simplified) ---

fn (mut w AstWriter) write_sql_stmt(s SqlStmt) {
	w.write_pos(s.pos)
	w.write_expr(s.db_expr)
	// Skip lines and or_expr for simplicity
}

fn (mut r AstReader) read_sql_stmt() SqlStmt {
	pos := r.read_pos()
	db_expr := r.read_expr()
	return SqlStmt{
		pos:     pos
		db_expr: db_expr
	}
}

// --- OrExpr Serialization ---

fn (mut w AstWriter) write_or_expr(o OrExpr) {
	w.write_u8(u8(o.kind))
	w.write_pos(o.pos)
	w.write_stmt_array(o.stmts)
}

fn (mut r AstReader) read_or_expr() OrExpr {
	kind := unsafe { OrKind(r.read_u8()) }
	pos := r.read_pos()
	stmts := r.read_stmt_array()
	return OrExpr{
		kind:  kind
		pos:   pos
		scope: unsafe { nil }
		stmts: stmts
	}
}

// --- CallArg Serialization ---

fn (mut w AstWriter) write_call_arg(a CallArg) {
	w.write_bool(a.is_mut)
	w.write_u8(u8(a.share))
	w.write_comment_array(a.comments)
	w.write_expr(a.expr)
	w.write_pos(a.pos)
}

fn (mut r AstReader) read_call_arg() CallArg {
	is_mut := r.read_bool()
	share := unsafe { ShareType(r.read_u8()) }
	comments := r.read_comment_array()
	expr := r.read_expr()
	pos := r.read_pos()
	return CallArg{
		is_mut:   is_mut
		share:    share
		comments: comments
		expr:     expr
		pos:      pos
	}
}

fn (mut w AstWriter) write_call_arg_array(args []CallArg) {
	w.write_u32(u32(args.len))
	for a in args {
		w.write_call_arg(a)
	}
}

fn (mut r AstReader) read_call_arg_array() []CallArg {
	len := r.read_u32()
	mut arr := []CallArg{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_call_arg()
	}
	return arr
}

// --- IfBranch Serialization ---

fn (mut w AstWriter) write_if_branch(b IfBranch) {
	w.write_pos(b.pos)
	w.write_pos(b.body_pos)
	w.write_comment_array(b.comments)
	w.write_expr(b.cond)
	w.write_stmt_array(b.stmts)
}

fn (mut r AstReader) read_if_branch() IfBranch {
	pos := r.read_pos()
	body_pos := r.read_pos()
	comments := r.read_comment_array()
	cond := r.read_expr()
	stmts := r.read_stmt_array()
	return IfBranch{
		pos:      pos
		body_pos: body_pos
		comments: comments
		cond:     cond
		stmts:    stmts
		scope:    unsafe { nil }
	}
}

fn (mut w AstWriter) write_if_branch_array(branches []IfBranch) {
	w.write_u32(u32(branches.len))
	for b in branches {
		w.write_if_branch(b)
	}
}

fn (mut r AstReader) read_if_branch_array() []IfBranch {
	len := r.read_u32()
	mut arr := []IfBranch{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_if_branch()
	}
	return arr
}

// --- MatchBranch Serialization ---

fn (mut w AstWriter) write_match_branch(b MatchBranch) {
	w.write_pos(b.pos)
	w.write_bool(b.is_else)
	w.write_comment_array(b.post_comments)
	w.write_pos(b.branch_pos)
	w.write_stmt_array(b.stmts)
	w.write_expr_array(b.exprs)
}

fn (mut r AstReader) read_match_branch() MatchBranch {
	pos := r.read_pos()
	is_else := r.read_bool()
	post_comments := r.read_comment_array()
	branch_pos := r.read_pos()
	stmts := r.read_stmt_array()
	exprs := r.read_expr_array()
	return MatchBranch{
		pos:           pos
		is_else:       is_else
		post_comments: post_comments
		branch_pos:    branch_pos
		stmts:         stmts
		exprs:         exprs
		scope:         unsafe { nil }
	}
}

fn (mut w AstWriter) write_match_branch_array(branches []MatchBranch) {
	w.write_u32(u32(branches.len))
	for b in branches {
		w.write_match_branch(b)
	}
}

fn (mut r AstReader) read_match_branch_array() []MatchBranch {
	len := r.read_u32()
	mut arr := []MatchBranch{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_match_branch()
	}
	return arr
}

// --- StructInitField Serialization ---

fn (mut w AstWriter) write_struct_init_field(f StructInitField) {
	w.write_pos(f.pos)
	w.write_pos(f.name_pos)
	w.write_comment_array(f.pre_comments)
	w.write_comment_array(f.end_comments)
	w.write_comment_array(f.next_comments)
	w.write_bool(f.has_prev_newline)
	w.write_bool(f.has_break_line)
	w.write_bool(f.is_embed)
	w.write_expr(f.expr)
	w.write_string(f.name)
}

fn (mut r AstReader) read_struct_init_field() StructInitField {
	pos := r.read_pos()
	name_pos := r.read_pos()
	pre_comments := r.read_comment_array()
	end_comments := r.read_comment_array()
	next_comments := r.read_comment_array()
	has_prev_newline := r.read_bool()
	has_break_line := r.read_bool()
	is_embed := r.read_bool()
	expr := r.read_expr()
	name := r.read_string()
	return StructInitField{
		pos:              pos
		name_pos:         name_pos
		pre_comments:     pre_comments
		end_comments:     end_comments
		next_comments:    next_comments
		has_prev_newline: has_prev_newline
		has_break_line:   has_break_line
		is_embed:         is_embed
		expr:             expr
		name:             name
	}
}

fn (mut w AstWriter) write_struct_init_field_array(fields []StructInitField) {
	w.write_u32(u32(fields.len))
	for f in fields {
		w.write_struct_init_field(f)
	}
}

fn (mut r AstReader) read_struct_init_field_array() []StructInitField {
	len := r.read_u32()
	mut arr := []StructInitField{cap: int(len)}
	for _ in 0 .. len {
		arr << r.read_struct_init_field()
	}
	return arr
}

// --- Expression Serialization ---

// write_expr writes an Expr
fn (mut w AstWriter) write_expr(expr Expr) {
	match expr {
		EmptyExpr {
			w.write_u8(u8(ExprKind.empty_expr))
		}
		NodeError {
			w.write_u8(u8(ExprKind.node_error))
			w.write_i32(i32(expr.idx))
			w.write_pos(expr.pos)
		}
		IntegerLiteral {
			w.write_u8(u8(ExprKind.integer_literal))
			w.write_string(expr.val)
			w.write_pos(expr.pos)
		}
		FloatLiteral {
			w.write_u8(u8(ExprKind.float_literal))
			w.write_string(expr.val)
			w.write_pos(expr.pos)
		}
		StringLiteral {
			w.write_u8(u8(ExprKind.string_literal))
			w.write_string(expr.val)
			w.write_bool(expr.is_raw)
			w.write_u8(u8(expr.language))
			w.write_pos(expr.pos)
		}
		CharLiteral {
			w.write_u8(u8(ExprKind.char_literal))
			w.write_string(expr.val)
			w.write_pos(expr.pos)
		}
		BoolLiteral {
			w.write_u8(u8(ExprKind.bool_literal))
			w.write_bool(expr.val)
			w.write_pos(expr.pos)
		}
		Ident {
			w.write_u8(u8(ExprKind.ident))
			w.write_ident(expr)
		}
		Comment {
			w.write_u8(u8(ExprKind.comment))
			w.write_string(expr.text)
			w.write_bool(expr.is_multi)
			w.write_pos(expr.pos)
		}
		InfixExpr {
			w.write_u8(u8(ExprKind.infix_expr))
			w.write_u8(u8(expr.op))
			w.write_pos(expr.pos)
			w.write_bool(expr.is_stmt)
			w.write_expr(expr.left)
			w.write_expr(expr.right)
			w.write_or_expr(expr.or_block)
			w.write_comment_array(expr.before_op_comments)
			w.write_comment_array(expr.after_op_comments)
		}
		PrefixExpr {
			w.write_u8(u8(ExprKind.prefix_expr))
			w.write_u8(u8(expr.op))
			w.write_pos(expr.pos)
			w.write_expr(expr.right)
			w.write_or_expr(expr.or_block)
			w.write_bool(expr.is_option)
		}
		PostfixExpr {
			w.write_u8(u8(ExprKind.postfix_expr))
			w.write_u8(u8(expr.op))
			w.write_pos(expr.pos)
			w.write_bool(expr.is_c2v_prefix)
			w.write_expr(expr.expr)
		}
		IndexExpr {
			w.write_u8(u8(ExprKind.index_expr))
			w.write_pos(expr.pos)
			w.write_expr(expr.index)
			w.write_or_expr(expr.or_expr)
			w.write_expr(expr.left)
			w.write_bool(expr.is_setter)
			w.write_bool(expr.is_option)
			w.write_bool(expr.is_direct)
			w.write_bool(expr.is_gated)
		}
		SelectorExpr {
			w.write_u8(u8(ExprKind.selector_expr))
			w.write_pos(expr.pos)
			w.write_string(expr.field_name)
			w.write_bool(expr.is_mut)
			w.write_pos(expr.mut_pos)
			w.write_u8(u8(expr.next_token))
			w.write_expr(expr.expr)
			w.write_or_expr(expr.or_block)
		}
		CallExpr {
			w.write_u8(u8(ExprKind.call_expr))
			w.write_pos(expr.pos)
			w.write_pos(expr.name_pos)
			w.write_string(expr.mod)
			w.write_u8(u8(expr.kind))
			w.write_string(expr.name)
			w.write_bool(expr.is_method)
			w.write_bool(expr.is_field)
			w.write_bool(expr.is_fn_var)
			w.write_bool(expr.is_fn_a_const)
			w.write_bool(expr.is_keep_alive)
			w.write_bool(expr.is_noreturn)
			w.write_bool(expr.is_ctor_new)
			w.write_bool(expr.is_file_translated)
			w.write_bool(expr.is_static_method)
			w.write_bool(expr.is_variadic)
			w.write_bool(expr.is_c_variadic)
			w.write_call_arg_array(expr.args)
			w.write_u8(u8(expr.language))
			w.write_or_expr(expr.or_block)
			w.write_expr(expr.left)
			w.write_type_array(expr.concrete_types)
			w.write_comment_array(expr.comments)
		}
		ParExpr {
			w.write_u8(u8(ExprKind.par_expr))
			w.write_pos(expr.pos)
			w.write_expr(expr.expr)
			w.write_comment_array(expr.comments)
		}
		IfExpr {
			w.write_u8(u8(ExprKind.if_expr))
			w.write_bool(expr.is_comptime)
			w.write_u8(u8(expr.tok_kind))
			w.write_pos(expr.pos)
			w.write_comment_array(expr.post_comments)
			w.write_expr(expr.left)
			w.write_if_branch_array(expr.branches)
			w.write_bool(expr.is_expr)
			w.write_bool(expr.has_else)
		}
		MatchExpr {
			w.write_u8(u8(ExprKind.match_expr))
			w.write_bool(expr.is_comptime)
			w.write_u8(u8(expr.tok_kind))
			w.write_pos(expr.pos)
			w.write_comment_array(expr.comments)
			w.write_expr(expr.cond)
			w.write_match_branch_array(expr.branches)
			w.write_bool(expr.is_expr)
		}
		ArrayInit {
			w.write_u8(u8(ExprKind.array_init))
			w.write_pos(expr.pos)
			w.write_pos(expr.elem_type_pos)
			w.write_comment_array(expr.pre_cmnts)
			w.write_bool(expr.is_fixed)
			w.write_bool(expr.is_option)
			w.write_bool(expr.has_val)
			w.write_string(expr.mod)
			w.write_bool(expr.has_len)
			w.write_bool(expr.has_cap)
			w.write_bool(expr.has_init)
			w.write_bool(expr.has_index)
			w.write_expr_array(expr.exprs)
			if expr.has_len {
				w.write_expr(expr.len_expr)
			}
			if expr.has_cap {
				w.write_expr(expr.cap_expr)
			}
			if expr.has_init {
				w.write_expr(expr.init_expr)
			}
			w.write_type(expr.elem_type)
			w.write_type(expr.typ)
		}
		MapInit {
			w.write_u8(u8(ExprKind.map_init))
			w.write_pos(expr.pos)
			w.write_comment_array(expr.pre_cmnts)
			w.write_expr_array(expr.keys)
			w.write_expr_array(expr.vals)
			w.write_bool(expr.has_update_expr)
			if expr.has_update_expr {
				w.write_expr(expr.update_expr)
				w.write_pos(expr.update_expr_pos)
				w.write_comment_array(expr.update_expr_comments)
			}
		}
		StructInit {
			w.write_u8(u8(ExprKind.struct_init))
			w.write_pos(expr.pos)
			w.write_pos(expr.name_pos)
			w.write_bool(expr.no_keys)
			w.write_bool(expr.is_short_syntax)
			w.write_bool(expr.is_anon)
			w.write_comment_array(expr.pre_comments)
			w.write_string(expr.typ_str)
			w.write_bool(expr.has_update_expr)
			if expr.has_update_expr {
				w.write_expr(expr.update_expr)
				w.write_pos(expr.update_expr_pos)
				w.write_comment_array(expr.update_expr_comments)
			}
			w.write_struct_init_field_array(expr.init_fields)
			w.write_type_array(expr.generic_types)
			w.write_u8(u8(expr.language))
		}
		RangeExpr {
			w.write_u8(u8(ExprKind.range_expr))
			w.write_bool(expr.has_high)
			w.write_bool(expr.has_low)
			w.write_pos(expr.pos)
			w.write_bool(expr.is_gated)
			if expr.has_low {
				w.write_expr(expr.low)
			}
			if expr.has_high {
				w.write_expr(expr.high)
			}
		}
		CastExpr {
			w.write_u8(u8(ExprKind.cast_expr))
			w.write_type(expr.typ)
			w.write_pos(expr.pos)
			w.write_expr(expr.expr)
			w.write_string(expr.typname)
			w.write_bool(expr.has_arg)
			if expr.has_arg {
				w.write_expr(expr.arg)
			}
		}
		AsCast {
			w.write_u8(u8(ExprKind.as_cast))
			w.write_type(expr.typ)
			w.write_pos(expr.pos)
			w.write_expr(expr.expr)
		}
		TypeNode {
			w.write_u8(u8(ExprKind.type_node))
			w.write_pos(expr.pos)
			w.write_type(expr.typ)
			w.write_comment_array(expr.end_comments)
		}
		TypeOf {
			w.write_u8(u8(ExprKind.type_of))
			w.write_pos(expr.pos)
			w.write_expr(expr.expr)
		}
		SizeOf {
			w.write_u8(u8(ExprKind.size_of))
			w.write_pos(expr.pos)
			w.write_bool(expr.is_type)
			w.write_expr(expr.expr)
			w.write_type(expr.typ)
		}
		OffsetOf {
			w.write_u8(u8(ExprKind.offset_of))
			w.write_pos(expr.pos)
			w.write_type(expr.struct_type)
			w.write_string(expr.field)
		}
		UnsafeExpr {
			w.write_u8(u8(ExprKind.unsafe_expr))
			w.write_pos(expr.pos)
			w.write_expr(expr.expr)
		}
		Nil {
			w.write_u8(u8(ExprKind.nil_expr))
			w.write_pos(expr.pos)
		}
		None {
			w.write_u8(u8(ExprKind.none_expr))
			w.write_pos(expr.pos)
		}
		OrExpr {
			w.write_u8(u8(ExprKind.or_expr))
			w.write_or_expr(expr)
		}
		EnumVal {
			w.write_u8(u8(ExprKind.enum_val))
			w.write_string(expr.enum_name)
			w.write_string(expr.val)
			w.write_pos(expr.pos)
		}
		AtExpr {
			w.write_u8(u8(ExprKind.at_expr))
			w.write_string(expr.name)
			w.write_pos(expr.pos)
			w.write_u8(u8(expr.kind))
			w.write_string(expr.val)
		}
		DumpExpr {
			w.write_u8(u8(ExprKind.dump_expr))
			w.write_pos(expr.pos)
			w.write_expr(expr.expr)
		}
		ConcatExpr {
			w.write_u8(u8(ExprKind.concat_expr))
			w.write_expr_array(expr.vals)
			w.write_pos(expr.pos)
		}
		LambdaExpr {
			w.write_u8(u8(ExprKind.lambda_expr))
			w.write_pos(expr.pos)
			w.write_expr(expr.expr)
		}
		AnonFn {
			w.write_u8(u8(ExprKind.anon_fn))
			w.write_fn_decl(expr.decl)
			w.write_type(expr.typ)
		}
		GoExpr {
			w.write_u8(u8(ExprKind.go_expr))
			w.write_pos(expr.pos)
			w.write_bool(expr.is_expr)
			// CallExpr is written inline
			w.write_pos(expr.call_expr.pos)
			w.write_string(expr.call_expr.name)
		}
		SpawnExpr {
			w.write_u8(u8(ExprKind.spawn_expr))
			w.write_pos(expr.pos)
			w.write_bool(expr.is_expr)
		}
		Likely {
			w.write_u8(u8(ExprKind.likely))
			w.write_pos(expr.pos)
			w.write_expr(expr.expr)
			w.write_bool(expr.is_likely)
		}
		IsRefType {
			w.write_u8(u8(ExprKind.is_ref_type))
			w.write_pos(expr.pos)
			w.write_bool(expr.is_type)
			w.write_expr(expr.expr)
			w.write_type(expr.typ)
		}
		ArrayDecompose {
			w.write_u8(u8(ExprKind.array_decompose))
			w.write_pos(expr.pos)
			w.write_expr(expr.expr)
		}
		ChanInit {
			w.write_u8(u8(ExprKind.chan_init))
			w.write_pos(expr.pos)
			w.write_bool(expr.has_cap)
			if expr.has_cap {
				w.write_expr(expr.cap_expr)
			}
			w.write_type(expr.typ)
			w.write_type(expr.elem_type)
		}
		Assoc {
			w.write_u8(u8(ExprKind.assoc))
			w.write_string(expr.var_name)
			w.write_string_array(expr.fields)
			w.write_pos(expr.pos)
			w.write_expr_array(expr.exprs)
		}
		IfGuardExpr {
			w.write_u8(u8(ExprKind.if_guard_expr))
			w.write_expr(expr.expr)
			// Write vars array
			w.write_u32(u32(expr.vars.len))
			for v in expr.vars {
				w.write_string(v.name)
				w.write_bool(v.is_mut)
				w.write_pos(v.pos)
			}
		}
		// Complex expressions - serialize minimally for now
		LockExpr {
			w.write_u8(u8(ExprKind.lock_expr))
			w.write_pos(expr.pos)
		}
		SelectExpr {
			w.write_u8(u8(ExprKind.select_expr))
			w.write_pos(expr.pos)
		}
		ComptimeCall {
			w.write_u8(u8(ExprKind.comptime_call))
			w.write_pos(expr.pos)
		}
		ComptimeSelector {
			w.write_u8(u8(ExprKind.comptime_selector))
			w.write_pos(expr.pos)
		}
		ComptimeType {
			w.write_u8(u8(ExprKind.comptime_type))
			w.write_pos(expr.pos)
		}
		SqlExpr {
			w.write_u8(u8(ExprKind.sql_expr))
			w.write_pos(expr.pos)
		}
		StringInterLiteral {
			w.write_u8(u8(ExprKind.string_inter_literal))
			w.write_pos(expr.pos)
		}
		CTempVar {
			w.write_u8(u8(ExprKind.c_temp_var))
		}
	}
}

// read_expr reads an Expr
fn (mut r AstReader) read_expr() Expr {
	kind := unsafe { ExprKind(r.read_u8()) }
	match kind {
		.empty_expr {
			return empty_expr
		}
		.node_error {
			return NodeError{
				idx: int(r.read_i32())
				pos: r.read_pos()
			}
		}
		.integer_literal {
			return IntegerLiteral{
				val: r.read_string()
				pos: r.read_pos()
			}
		}
		.float_literal {
			return FloatLiteral{
				val: r.read_string()
				pos: r.read_pos()
			}
		}
		.string_literal {
			return StringLiteral{
				val:      r.read_string()
				is_raw:   r.read_bool()
				language: unsafe { Language(r.read_u8()) }
				pos:      r.read_pos()
			}
		}
		.char_literal {
			return CharLiteral{
				val: r.read_string()
				pos: r.read_pos()
			}
		}
		.bool_literal {
			return BoolLiteral{
				val: r.read_bool()
				pos: r.read_pos()
			}
		}
		.ident {
			return r.read_ident()
		}
		.comment {
			return Comment{
				text:     r.read_string()
				is_multi: r.read_bool()
				pos:      r.read_pos()
			}
		}
		.infix_expr {
			op := unsafe { token.Kind(r.read_u8()) }
			pos := r.read_pos()
			is_stmt := r.read_bool()
			left := r.read_expr()
			right := r.read_expr()
			or_block := r.read_or_expr()
			before_op_comments := r.read_comment_array()
			after_op_comments := r.read_comment_array()
			return InfixExpr{
				op:                 op
				pos:                pos
				is_stmt:            is_stmt
				left:               left
				right:              right
				or_block:           or_block
				before_op_comments: before_op_comments
				after_op_comments:  after_op_comments
			}
		}
		.prefix_expr {
			op := unsafe { token.Kind(r.read_u8()) }
			pos := r.read_pos()
			right := r.read_expr()
			or_block := r.read_or_expr()
			is_option := r.read_bool()
			return PrefixExpr{
				op:        op
				pos:       pos
				right:     right
				or_block:  or_block
				is_option: is_option
			}
		}
		.postfix_expr {
			op := unsafe { token.Kind(r.read_u8()) }
			pos := r.read_pos()
			is_c2v_prefix := r.read_bool()
			expr := r.read_expr()
			return PostfixExpr{
				op:            op
				pos:           pos
				is_c2v_prefix: is_c2v_prefix
				expr:          expr
			}
		}
		.index_expr {
			pos := r.read_pos()
			index := r.read_expr()
			or_expr := r.read_or_expr()
			left := r.read_expr()
			is_setter := r.read_bool()
			is_option := r.read_bool()
			is_direct := r.read_bool()
			is_gated := r.read_bool()
			return IndexExpr{
				pos:       pos
				index:     index
				or_expr:   or_expr
				left:      left
				is_setter: is_setter
				is_option: is_option
				is_direct: is_direct
				is_gated:  is_gated
			}
		}
		.selector_expr {
			pos := r.read_pos()
			field_name := r.read_string()
			is_mut := r.read_bool()
			mut_pos := r.read_pos()
			next_token := unsafe { token.Kind(r.read_u8()) }
			expr := r.read_expr()
			or_block := r.read_or_expr()
			return SelectorExpr{
				pos:        pos
				field_name: field_name
				is_mut:     is_mut
				mut_pos:    mut_pos
				next_token: next_token
				expr:       expr
				or_block:   or_block
			}
		}
		.call_expr {
			pos := r.read_pos()
			name_pos := r.read_pos()
			mod := r.read_string()
			call_kind := unsafe { CallKind(r.read_u8()) }
			name := r.read_string()
			is_method := r.read_bool()
			is_field := r.read_bool()
			is_fn_var := r.read_bool()
			is_fn_a_const := r.read_bool()
			is_keep_alive := r.read_bool()
			is_noreturn := r.read_bool()
			is_ctor_new := r.read_bool()
			is_file_translated := r.read_bool()
			is_static_method := r.read_bool()
			is_variadic := r.read_bool()
			is_c_variadic := r.read_bool()
			args := r.read_call_arg_array()
			language := unsafe { Language(r.read_u8()) }
			or_block := r.read_or_expr()
			left := r.read_expr()
			concrete_types := r.read_type_array()
			comments := r.read_comment_array()
			return CallExpr{
				pos:                pos
				name_pos:           name_pos
				mod:                mod
				kind:               call_kind
				name:               name
				is_method:          is_method
				is_field:           is_field
				is_fn_var:          is_fn_var
				is_fn_a_const:      is_fn_a_const
				is_keep_alive:      is_keep_alive
				is_noreturn:        is_noreturn
				is_ctor_new:        is_ctor_new
				is_file_translated: is_file_translated
				is_static_method:   is_static_method
				is_variadic:        is_variadic
				is_c_variadic:      is_c_variadic
				args:               args
				language:           language
				or_block:           or_block
				left:               left
				concrete_types:     concrete_types
				comments:           comments
			}
		}
		.par_expr {
			pos := r.read_pos()
			expr := r.read_expr()
			comments := r.read_comment_array()
			return ParExpr{
				pos:      pos
				expr:     expr
				comments: comments
			}
		}
		.if_expr {
			is_comptime := r.read_bool()
			tok_kind := unsafe { token.Kind(r.read_u8()) }
			pos := r.read_pos()
			post_comments := r.read_comment_array()
			left := r.read_expr()
			branches := r.read_if_branch_array()
			is_expr := r.read_bool()
			has_else := r.read_bool()
			return IfExpr{
				is_comptime:   is_comptime
				tok_kind:      tok_kind
				pos:           pos
				post_comments: post_comments
				left:          left
				branches:      branches
				is_expr:       is_expr
				has_else:      has_else
			}
		}
		.match_expr {
			is_comptime := r.read_bool()
			tok_kind := unsafe { token.Kind(r.read_u8()) }
			pos := r.read_pos()
			comments := r.read_comment_array()
			cond := r.read_expr()
			branches := r.read_match_branch_array()
			is_expr := r.read_bool()
			return MatchExpr{
				is_comptime: is_comptime
				tok_kind:    tok_kind
				pos:         pos
				comments:    comments
				cond:        cond
				branches:    branches
				is_expr:     is_expr
			}
		}
		.array_init {
			pos := r.read_pos()
			elem_type_pos := r.read_pos()
			pre_cmnts := r.read_comment_array()
			is_fixed := r.read_bool()
			is_option := r.read_bool()
			has_val := r.read_bool()
			mod := r.read_string()
			has_len := r.read_bool()
			has_cap := r.read_bool()
			has_init := r.read_bool()
			has_index := r.read_bool()
			exprs := r.read_expr_array()
			len_expr := if has_len { r.read_expr() } else { empty_expr }
			cap_expr := if has_cap { r.read_expr() } else { empty_expr }
			init_expr := if has_init { r.read_expr() } else { empty_expr }
			elem_type := r.read_type()
			typ := r.read_type()
			return ArrayInit{
				pos:           pos
				elem_type_pos: elem_type_pos
				pre_cmnts:     pre_cmnts
				is_fixed:      is_fixed
				is_option:     is_option
				has_val:       has_val
				mod:           mod
				has_len:       has_len
				has_cap:       has_cap
				has_init:      has_init
				has_index:     has_index
				exprs:         exprs
				len_expr:      len_expr
				cap_expr:      cap_expr
				init_expr:     init_expr
				elem_type:     elem_type
				typ:           typ
			}
		}
		.map_init {
			pos := r.read_pos()
			pre_cmnts := r.read_comment_array()
			keys := r.read_expr_array()
			vals := r.read_expr_array()
			has_update_expr := r.read_bool()
			mut update_expr := empty_expr
			mut update_expr_pos := token.Pos{}
			mut update_expr_comments := []Comment{}
			if has_update_expr {
				update_expr = r.read_expr()
				update_expr_pos = r.read_pos()
				update_expr_comments = r.read_comment_array()
			}
			return MapInit{
				pos:                  pos
				pre_cmnts:            pre_cmnts
				keys:                 keys
				vals:                 vals
				has_update_expr:      has_update_expr
				update_expr:          update_expr
				update_expr_pos:      update_expr_pos
				update_expr_comments: update_expr_comments
			}
		}
		.struct_init {
			pos := r.read_pos()
			name_pos := r.read_pos()
			no_keys := r.read_bool()
			is_short_syntax := r.read_bool()
			is_anon := r.read_bool()
			pre_comments := r.read_comment_array()
			typ_str := r.read_string()
			has_update_expr := r.read_bool()
			mut update_expr := empty_expr
			mut update_expr_pos := token.Pos{}
			mut update_expr_comments := []Comment{}
			if has_update_expr {
				update_expr = r.read_expr()
				update_expr_pos = r.read_pos()
				update_expr_comments = r.read_comment_array()
			}
			init_fields := r.read_struct_init_field_array()
			generic_types := r.read_type_array()
			language := unsafe { Language(r.read_u8()) }
			return StructInit{
				pos:                  pos
				name_pos:             name_pos
				no_keys:              no_keys
				is_short_syntax:      is_short_syntax
				is_anon:              is_anon
				pre_comments:         pre_comments
				typ_str:              typ_str
				has_update_expr:      has_update_expr
				update_expr:          update_expr
				update_expr_pos:      update_expr_pos
				update_expr_comments: update_expr_comments
				init_fields:          init_fields
				generic_types:        generic_types
				language:             language
			}
		}
		.range_expr {
			has_high := r.read_bool()
			has_low := r.read_bool()
			pos := r.read_pos()
			is_gated := r.read_bool()
			low := if has_low { r.read_expr() } else { empty_expr }
			high := if has_high { r.read_expr() } else { empty_expr }
			return RangeExpr{
				has_high: has_high
				has_low:  has_low
				pos:      pos
				is_gated: is_gated
				low:      low
				high:     high
			}
		}
		.cast_expr {
			typ := r.read_type()
			pos := r.read_pos()
			expr := r.read_expr()
			typname := r.read_string()
			has_arg := r.read_bool()
			arg := if has_arg { r.read_expr() } else { empty_expr }
			return CastExpr{
				typ:     typ
				pos:     pos
				expr:    expr
				typname: typname
				has_arg: has_arg
				arg:     arg
			}
		}
		.as_cast {
			typ := r.read_type()
			pos := r.read_pos()
			expr := r.read_expr()
			return AsCast{
				typ:  typ
				pos:  pos
				expr: expr
			}
		}
		.type_node {
			pos := r.read_pos()
			typ := r.read_type()
			end_comments := r.read_comment_array()
			return TypeNode{
				pos:          pos
				typ:          typ
				end_comments: end_comments
			}
		}
		.type_of {
			pos := r.read_pos()
			expr := r.read_expr()
			return TypeOf{
				pos:  pos
				expr: expr
			}
		}
		.size_of {
			pos := r.read_pos()
			is_type := r.read_bool()
			expr := r.read_expr()
			typ := r.read_type()
			return SizeOf{
				pos:     pos
				is_type: is_type
				expr:    expr
				typ:     typ
			}
		}
		.offset_of {
			pos := r.read_pos()
			struct_type := r.read_type()
			field := r.read_string()
			return OffsetOf{
				pos:         pos
				struct_type: struct_type
				field:       field
			}
		}
		.unsafe_expr {
			pos := r.read_pos()
			expr := r.read_expr()
			return UnsafeExpr{
				pos:  pos
				expr: expr
			}
		}
		.nil_expr {
			return Nil{
				pos: r.read_pos()
			}
		}
		.none_expr {
			return None{
				pos: r.read_pos()
			}
		}
		.or_expr {
			return r.read_or_expr()
		}
		.enum_val {
			enum_name := r.read_string()
			val := r.read_string()
			pos := r.read_pos()
			return EnumVal{
				enum_name: enum_name
				val:       val
				pos:       pos
			}
		}
		.at_expr {
			name := r.read_string()
			pos := r.read_pos()
			at_kind := unsafe { token.AtKind(r.read_u8()) }
			val := r.read_string()
			return AtExpr{
				name: name
				pos:  pos
				kind: at_kind
				val:  val
			}
		}
		.dump_expr {
			pos := r.read_pos()
			expr := r.read_expr()
			return DumpExpr{
				pos:  pos
				expr: expr
			}
		}
		.concat_expr {
			vals := r.read_expr_array()
			pos := r.read_pos()
			return ConcatExpr{
				vals: vals
				pos:  pos
			}
		}
		.lambda_expr {
			pos := r.read_pos()
			expr := r.read_expr()
			return LambdaExpr{
				pos:  pos
				expr: expr
			}
		}
		.anon_fn {
			decl := r.read_fn_decl()
			typ := r.read_type()
			return AnonFn{
				decl: decl
				typ:  typ
			}
		}
		.go_expr {
			pos := r.read_pos()
			is_expr := r.read_bool()
			call_pos := r.read_pos()
			call_name := r.read_string()
			return GoExpr{
				pos:       pos
				is_expr:   is_expr
				call_expr: CallExpr{
					pos:  call_pos
					name: call_name
				}
			}
		}
		.spawn_expr {
			pos := r.read_pos()
			is_expr := r.read_bool()
			return SpawnExpr{
				pos:     pos
				is_expr: is_expr
			}
		}
		.likely {
			pos := r.read_pos()
			expr := r.read_expr()
			is_likely := r.read_bool()
			return Likely{
				pos:       pos
				expr:      expr
				is_likely: is_likely
			}
		}
		.is_ref_type {
			pos := r.read_pos()
			is_type := r.read_bool()
			expr := r.read_expr()
			typ := r.read_type()
			return IsRefType{
				pos:     pos
				is_type: is_type
				expr:    expr
				typ:     typ
			}
		}
		.array_decompose {
			pos := r.read_pos()
			expr := r.read_expr()
			return ArrayDecompose{
				pos:  pos
				expr: expr
			}
		}
		.chan_init {
			pos := r.read_pos()
			has_cap := r.read_bool()
			cap_expr := if has_cap { r.read_expr() } else { empty_expr }
			typ := r.read_type()
			elem_type := r.read_type()
			return ChanInit{
				pos:       pos
				has_cap:   has_cap
				cap_expr:  cap_expr
				typ:       typ
				elem_type: elem_type
			}
		}
		.assoc {
			var_name := r.read_string()
			fields := r.read_string_array()
			pos := r.read_pos()
			exprs := r.read_expr_array()
			return Assoc{
				var_name: var_name
				fields:   fields
				pos:      pos
				exprs:    exprs
			}
		}
		.if_guard_expr {
			expr := r.read_expr()
			// Read vars array
			vars_len := r.read_u32()
			mut vars := []IfGuardVar{cap: int(vars_len)}
			for _ in 0 .. vars_len {
				name := r.read_string()
				is_mut := r.read_bool()
				pos := r.read_pos()
				vars << IfGuardVar{
					name:   name
					is_mut: is_mut
					pos:    pos
				}
			}
			return IfGuardExpr{
				vars: vars
				expr: expr
			}
		}
		// Complex expressions - return minimal struct for now
		.lock_expr {
			return LockExpr{
				pos: r.read_pos()
			}
		}
		.select_expr {
			return SelectExpr{
				pos: r.read_pos()
			}
		}
		.comptime_call {
			return ComptimeCall{
				pos: r.read_pos()
			}
		}
		.comptime_selector {
			return ComptimeSelector{
				pos: r.read_pos()
			}
		}
		.comptime_type {
			return ComptimeType{
				pos: r.read_pos()
			}
		}
		.sql_expr {
			return SqlExpr{
				pos: r.read_pos()
			}
		}
		.string_inter_literal {
			return StringInterLiteral{
				pos: r.read_pos()
			}
		}
		.c_temp_var {
			return empty_expr
		}
	}
}

// --- Ident Serialization ---

fn (mut w AstWriter) write_ident(i Ident) {
	w.write_string(i.name)
	w.write_string(i.mod)
	w.write_pos(i.pos)
	w.write_pos(i.mut_pos)
	w.write_u8(u8(i.tok_kind))
	w.write_u8(u8(i.language))
	w.write_bool(i.is_mut)
	w.write_bool(i.comptime)
	// Skip: scope, obj, kind, info - checker-set
}

fn (mut r AstReader) read_ident() Ident {
	// Read in write order to ensure correct field assignment
	name := r.read_string()
	mod := r.read_string()
	pos := r.read_pos()
	mut_pos := r.read_pos()
	tok_kind := unsafe { token.Kind(r.read_u8()) }
	language := unsafe { Language(r.read_u8()) }
	is_mut := r.read_bool()
	comptime := r.read_bool()
	return Ident{
		name:     name
		mod:      mod
		pos:      pos
		mut_pos:  mut_pos
		tok_kind: tok_kind
		language: language
		is_mut:   is_mut
		comptime: comptime
	}
}

// --- File Serialization ---

// serialize_file serializes an ast.File to binary format
pub fn serialize_file(file &File, table &Table) []u8 {
	mut w := new_ast_writer_with_table(4096, table)

	// Write header
	for b in cache_magic {
		w.write_u8(b)
	}
	w.write_u32(cache_version)

	// Write file path info
	w.write_string(file.path)
	w.write_string(file.path_base)

	// Write file metadata
	w.write_i32(file.nr_lines)
	w.write_i32(file.nr_bytes)
	w.write_i32(file.nr_tokens)
	w.write_bool(file.is_test)
	w.write_bool(file.is_generated)
	w.write_bool(file.is_translated)
	w.write_u8(u8(file.language))

	// Write module
	w.write_module(file.mod)

	// Write imports
	w.write_u32(u32(file.imports.len))
	for imp in file.imports {
		w.write_import(imp)
	}

	// Write auto_imports
	w.write_string_array(file.auto_imports)

	// Write used_imports
	w.write_string_array(file.used_imports)

	// Write implied_imports
	w.write_string_array(file.implied_imports)

	// Write imported_symbols map
	w.write_u32(u32(file.imported_symbols.len))
	for key, val in file.imported_symbols {
		w.write_string(key)
		w.write_string(val)
	}

	// Write global_labels
	w.write_string_array(file.global_labels)

	// Write template_paths
	w.write_string_array(file.template_paths)

	// Write unique_prefix
	w.write_string(file.unique_prefix)

	// Write embedded files
	w.write_u32(u32(file.embedded_files.len))
	for ef in file.embedded_files {
		w.write_embedded_file(ef)
	}

	// Write statements
	w.write_u32(u32(file.stmts.len))
	for stmt in file.stmts {
		w.write_stmt(stmt)
	}

	return w.buf
}

// deserialize_file deserializes binary data to an ast.File
pub fn deserialize_file(data []u8, table &Table) !&File {
	mut r := new_ast_reader_with_table(data, table)

	// Verify header
	for b in cache_magic {
		if r.read_u8() != b {
			return error('invalid cache magic')
		}
	}
	version := r.read_u32()
	if version != cache_version {
		return error('cache version mismatch: expected ${cache_version}, got ${version}')
	}

	// Read file path info
	path := r.read_string()
	path_base := r.read_string()

	// Read file metadata
	nr_lines := r.read_i32()
	nr_bytes := r.read_i32()
	nr_tokens := r.read_i32()
	is_test := r.read_bool()
	is_generated := r.read_bool()
	is_translated := r.read_bool()
	language := unsafe { Language(r.read_u8()) }

	// Read module
	mod := r.read_module()

	// Read imports
	imports_len := r.read_u32()
	mut imports := []Import{cap: int(imports_len)}
	for _ in 0 .. imports_len {
		imports << r.read_import()
	}

	// Read auto_imports
	auto_imports := r.read_string_array()

	// Read used_imports
	used_imports := r.read_string_array()

	// Read implied_imports
	implied_imports := r.read_string_array()

	// Read imported_symbols map
	imported_symbols_len := r.read_u32()
	mut imported_symbols := map[string]string{}
	for _ in 0 .. imported_symbols_len {
		key := r.read_string()
		val := r.read_string()
		imported_symbols[key] = val
	}

	// Read global_labels
	global_labels := r.read_string_array()

	// Read template_paths
	template_paths := r.read_string_array()

	// Read unique_prefix
	unique_prefix := r.read_string()

	// Read embedded files
	ef_len := r.read_u32()
	mut embedded_files := []EmbeddedFile{cap: int(ef_len)}
	for _ in 0 .. ef_len {
		embedded_files << r.read_embedded_file()
	}

	// Read statements
	stmts_len := r.read_u32()
	mut stmts := []Stmt{cap: int(stmts_len)}
	for _ in 0 .. stmts_len {
		stmts << r.read_stmt()
	}

	// Check if any types couldn't be resolved - if so, fall back to normal parsing
	if r.unresolved_type_err {
		return error('unresolved type references - fallback to parsing required')
	}

	// Create File with placeholder scopes (will be rebuilt below)
	mut file := &File{
		path:             path
		path_base:        path_base
		nr_lines:         nr_lines
		nr_bytes:         nr_bytes
		nr_tokens:        nr_tokens
		is_test:          is_test
		is_generated:     is_generated
		is_translated:    is_translated
		language:         language
		mod:              mod
		imports:          imports
		auto_imports:     auto_imports
		used_imports:     used_imports
		implied_imports:  implied_imports
		imported_symbols: imported_symbols
		global_labels:    global_labels
		template_paths:   template_paths
		unique_prefix:    unique_prefix
		embedded_files:   embedded_files
		stmts:            stmts
		global_scope:     table.global_scope
		scope:            table.global_scope // placeholder, will be replaced
	}

	// Rebuild scope tree from AST
	// We need mutable access to global_scope to add children
	unsafe {
		mut gs := table.global_scope
		rebuild_scopes(mut file, mut gs)
	}
	return file
}

// --- Scope Reconstruction ---
// Rebuild scope tree from deserialized AST

// ScopeBuilder walks AST and reconstructs scope tree
struct ScopeBuilder {
mut:
	current_scope &Scope = unsafe { nil }
}

// rebuild_scopes reconstructs the scope tree for a deserialized file
pub fn rebuild_scopes(mut file File, mut global_scope Scope) {
	// Create file-level scope
	file_scope := &Scope{
		parent:    global_scope
		start_pos: 0
		end_pos:   file.nr_bytes
	}
	global_scope.children << file_scope
	file.scope = file_scope
	// Force write to immutable global_scope field (pub: fields can't be modified normally)
	unsafe {
		mut ptr := &file.global_scope
		*ptr = global_scope
	}
	mut builder := ScopeBuilder{
		current_scope: file_scope
	}

	// Walk all statements to rebuild scopes
	for mut stmt in file.stmts {
		builder.walk_stmt(mut stmt)
	}
}

fn (mut b ScopeBuilder) open_scope(start_pos int) &Scope {
	new_scope := &Scope{
		parent:    b.current_scope
		start_pos: start_pos
	}
	b.current_scope.children << new_scope
	b.current_scope = new_scope
	return new_scope
}

fn (mut b ScopeBuilder) close_scope(end_pos int) {
	b.current_scope.end_pos = end_pos
	b.current_scope = b.current_scope.parent
}

fn (mut b ScopeBuilder) register_var(v Var) {
	b.current_scope.register(ScopeObject(v))
}

fn (mut b ScopeBuilder) walk_stmt(mut stmt Stmt) {
	match mut stmt {
		FnDecl {
			b.walk_fn_decl(mut stmt)
		}
		ForStmt {
			b.walk_for_stmt(mut stmt)
		}
		ForInStmt {
			b.walk_for_in_stmt(mut stmt)
		}
		ForCStmt {
			b.walk_for_c_stmt(mut stmt)
		}
		ExprStmt {
			b.walk_expr(mut stmt.expr)
		}
		AssignStmt {
			b.walk_assign_stmt(mut stmt)
		}
		Return {
			for mut expr in stmt.exprs {
				b.walk_expr(mut expr)
			}
		}
		Block {
			b.walk_block(mut stmt)
		}
		DeferStmt {
			for mut s in stmt.stmts {
				b.walk_stmt(mut s)
			}
		}
		StructDecl {
			// No scope needed for struct declarations
		}
		EnumDecl {
			// No scope needed for enum declarations
		}
		InterfaceDecl {
			// No scope needed for interface declarations
		}
		ConstDecl {
			// Constants go to global scope, handled elsewhere
		}
		GlobalDecl {
			// Globals go to global scope, handled elsewhere
		}
		Import {
			// No scope needed for imports
		}
		Module {
			// No scope needed for module declaration
		}
		TypeDecl {
			// No scope needed for type declarations
		}
		HashStmt {
			// No scope for hash statements
		}
		ComptimeFor {
			b.walk_comptime_for(mut stmt)
		}
		AssertStmt {
			b.walk_expr(mut stmt.expr)
		}
		AsmStmt {
			// ASM has its own handling
		}
		BranchStmt {
			// break/continue - no scope
		}
		GotoStmt {
			// goto - no scope
		}
		GotoLabel {
			// label - no scope
		}
		SqlStmt {
			// SQL statements
		}
		NodeError {
			// Error node
		}
		EmptyStmt {
			// Empty statement
		}
		SemicolonStmt {
			// Semicolon
		}
		DebuggerStmt {
			// Debugger
		}
	}
}

fn (mut b ScopeBuilder) walk_fn_decl(mut fn_decl FnDecl) {
	// Create scope for function body (FnDecl.scope is immutable - pub: field)
	scope := b.open_scope(fn_decl.body_pos.pos)
	unsafe {
		mut ptr := &fn_decl.scope
		*ptr = scope
	}
	// Register parameters in function scope
	for param in fn_decl.params {
		is_stack_obj := !param.typ.has_flag(.shared_f) && (param.is_mut || param.typ.is_ptr())
		b.register_var(Var{
			name:          param.name
			typ:           param.typ
			is_mut:        param.is_mut
			is_auto_deref: param.is_mut
			is_stack_obj:  is_stack_obj
			is_arg:        true
			pos:           param.pos
		})
	}

	// Register receiver if this is a method
	if fn_decl.is_method && fn_decl.receiver.name.len > 0 {
		b.register_var(Var{
			name:          fn_decl.receiver.name
			typ:           fn_decl.receiver.typ
			is_mut:        fn_decl.receiver.is_mut
			is_auto_deref: fn_decl.receiver.is_mut
			is_arg:        true
			pos:           fn_decl.receiver.pos
		})
	}

	// Walk function body
	for mut stmt in fn_decl.stmts {
		b.walk_stmt(mut stmt)
	}

	b.close_scope(fn_decl.body_pos.pos + fn_decl.body_pos.len)
}

fn (mut b ScopeBuilder) walk_for_stmt(mut for_stmt ForStmt) {
	for_stmt.scope = b.open_scope(for_stmt.pos.pos)

	// Walk condition
	b.walk_expr(mut for_stmt.cond)

	// Walk body
	for mut stmt in for_stmt.stmts {
		b.walk_stmt(mut stmt)
	}

	b.close_scope(for_stmt.pos.pos + for_stmt.pos.len)
}

fn (mut b ScopeBuilder) walk_for_in_stmt(mut for_in ForInStmt) {
	for_in.scope = b.open_scope(for_in.pos.pos)

	// Register loop variables
	if for_in.key_var.len > 0 && for_in.key_var != '_' {
		b.register_var(Var{
			name:         for_in.key_var
			typ:          for_in.key_type
			pos:          for_in.pos
			is_tmp:       true
			is_stack_obj: true
		})
	}

	if for_in.val_var.len > 0 && for_in.val_var != '_' {
		b.register_var(Var{
			name:          for_in.val_var
			typ:           for_in.val_type
			is_mut:        for_in.val_is_mut
			is_auto_deref: for_in.val_is_mut
			pos:           for_in.pos
			is_tmp:        true
			is_stack_obj:  true
		})
	}

	// Walk body
	for mut stmt in for_in.stmts {
		b.walk_stmt(mut stmt)
	}

	b.close_scope(for_in.pos.pos + for_in.pos.len)
}

fn (mut b ScopeBuilder) walk_for_c_stmt(mut for_c ForCStmt) {
	for_c.scope = b.open_scope(for_c.pos.pos)

	// Walk init, cond, inc
	if for_c.has_init {
		b.walk_stmt(mut for_c.init)
	}
	if for_c.has_cond {
		b.walk_expr(mut for_c.cond)
	}
	if for_c.has_inc {
		b.walk_stmt(mut for_c.inc)
	}

	// Walk body
	for mut stmt in for_c.stmts {
		b.walk_stmt(mut stmt)
	}

	b.close_scope(for_c.pos.pos + for_c.pos.len)
}

fn (mut b ScopeBuilder) walk_block(mut block Block) {
	scope := b.open_scope(block.pos.pos)
	// Block.scope is immutable (pub: field)
	unsafe {
		mut ptr := &block.scope
		*ptr = scope
	}
	for mut stmt in block.stmts {
		b.walk_stmt(mut stmt)
	}

	b.close_scope(block.pos.pos + block.pos.len)
}

fn (mut b ScopeBuilder) walk_comptime_for(mut cf ComptimeFor) {
	// ComptimeFor.scope is immutable (pub: field)
	scope := b.open_scope(cf.pos.pos)
	unsafe {
		mut ptr := &cf.scope
		*ptr = scope
	}
	// Register comptime loop variable
	if cf.val_var.len > 0 {
		b.register_var(Var{
			name: cf.val_var
			typ:  cf.typ
			pos:  cf.pos
		})
	}

	// Walk body
	for mut stmt in cf.stmts {
		b.walk_stmt(mut stmt)
	}

	b.close_scope(cf.pos.pos + cf.pos.len)
}

fn (mut b ScopeBuilder) walk_assign_stmt(mut assign AssignStmt) {
	// Walk right side first
	for mut expr in assign.right {
		b.walk_expr(mut expr)
	}

	// For declaration assignments (:=), register new variables
	if assign.op == .decl_assign {
		for i, left in assign.left {
			if left is Ident {
				ident := left as Ident
				if ident.name != '_' {
					mut typ := void_type
					if i < assign.right_types.len {
						typ = assign.right_types[i]
					}
					v := Var{
						name:   ident.name
						typ:    typ
						is_mut: ident.is_mut
						pos:    ident.pos
						expr:   if i < assign.right.len { assign.right[i] } else { empty_expr }
					}
					b.register_var(v)
				}
			}
		}
	}
}

fn (mut b ScopeBuilder) walk_expr(mut expr Expr) {
	match mut expr {
		IfExpr {
			b.walk_if_expr(mut expr)
		}
		MatchExpr {
			b.walk_match_expr(mut expr)
		}
		LambdaExpr {
			b.walk_lambda_expr(mut expr)
		}
		AnonFn {
			b.walk_anon_fn(mut expr)
		}
		OrExpr {
			b.walk_or_expr(mut expr)
		}
		CallExpr {
			for mut arg in expr.args {
				b.walk_expr(mut arg.expr)
			}
			b.walk_expr(mut expr.left)
			b.walk_or_expr(mut expr.or_block)
		}
		IndexExpr {
			b.walk_expr(mut expr.left)
			b.walk_expr(mut expr.index)
			b.walk_or_expr(mut expr.or_expr)
		}
		SelectorExpr {
			b.walk_expr(mut expr.expr)
			b.walk_or_expr(mut expr.or_block)
		}
		InfixExpr {
			b.walk_expr(mut expr.left)
			b.walk_expr(mut expr.right)
			b.walk_or_expr(mut expr.or_block)
		}
		PrefixExpr {
			b.walk_expr(mut expr.right)
			b.walk_or_expr(mut expr.or_block)
		}
		PostfixExpr {
			b.walk_expr(mut expr.expr)
		}
		ParExpr {
			b.walk_expr(mut expr.expr)
		}
		CastExpr {
			b.walk_expr(mut expr.expr)
		}
		ArrayInit {
			for mut e in expr.exprs {
				b.walk_expr(mut e)
			}
			b.walk_expr(mut expr.len_expr)
			b.walk_expr(mut expr.cap_expr)
			b.walk_expr(mut expr.init_expr)
		}
		MapInit {
			for mut k in expr.keys {
				b.walk_expr(mut k)
			}
			for mut v in expr.vals {
				b.walk_expr(mut v)
			}
		}
		StructInit {
			for mut init_field in expr.init_fields {
				b.walk_expr(mut init_field.expr)
			}
		}
		ComptimeCall {
			for mut arg in expr.args {
				b.walk_expr(mut arg.expr)
			}
		}
		ComptimeSelector {
			b.walk_expr(mut expr.left)
		}
		ConcatExpr {
			for mut val in expr.vals {
				b.walk_expr(mut val)
			}
		}
		StringInterLiteral {
			for mut e in expr.exprs {
				b.walk_expr(mut e)
			}
		}
		UnsafeExpr {
			b.walk_expr(mut expr.expr)
		}
		LockExpr {
			b.walk_lock_expr(mut expr)
		}
		SelectExpr {
			b.walk_select_expr(mut expr)
		}
		GoExpr {
			b.walk_expr(mut expr.call_expr)
		}
		SpawnExpr {
			b.walk_expr(mut expr.call_expr)
		}
		RangeExpr {
			b.walk_expr(mut expr.low)
			b.walk_expr(mut expr.high)
		}
		OffsetOf {
			// No nested expressions
		}
		SizeOf {
			b.walk_expr(mut expr.expr)
		}
		TypeOf {
			b.walk_expr(mut expr.expr)
		}
		IsRefType {
			b.walk_expr(mut expr.expr)
		}
		DumpExpr {
			b.walk_expr(mut expr.expr)
		}
		Likely {
			b.walk_expr(mut expr.expr)
		}
		AsCast {
			b.walk_expr(mut expr.expr)
		}
		SqlExpr {
			// SQL expressions
		}
		Assoc {
			for mut e in expr.exprs {
				b.walk_expr(mut e)
			}
		}
		AtExpr {
			// @ expressions
		}
		CharLiteral {
			// Literal
		}
		BoolLiteral {
			// Literal
		}
		IntegerLiteral {
			// Literal
		}
		FloatLiteral {
			// Literal
		}
		StringLiteral {
			// Literal
		}
		Ident {
			// Identifier
		}
		EnumVal {
			// Enum value
		}
		TypeNode {
			// Type node
		}
		None {
			// None literal
		}
		Nil {
			// Nil literal
		}
		ComptimeType {
			// Comptime type
		}
		ArrayDecompose {
			b.walk_expr(mut expr.expr)
		}
		IfGuardExpr {
			// IfGuardVar has no expr field, only expr.expr
			b.walk_expr(mut expr.expr)
		}
		ChanInit {
			b.walk_expr(mut expr.cap_expr)
		}
		EmptyExpr {
			// Empty
		}
		CTempVar {
			// Comptime temp var
		}
		NodeError {
			// Error node
		}
		Comment {
			// Comment
		}
	}
}

fn (mut b ScopeBuilder) walk_if_expr(mut if_expr IfExpr) {
	for mut branch in if_expr.branches {
		branch.scope = b.open_scope(branch.pos.pos)

		// If this is an if-guard, register the variables
		if branch.cond is IfGuardExpr {
			guard := branch.cond as IfGuardExpr
			for var in guard.vars {
				b.register_var(Var{
					name:   var.name
					is_mut: var.is_mut
					pos:    var.pos
				})
			}
		}

		// Walk condition
		b.walk_expr(mut branch.cond)

		// Walk body
		for mut stmt in branch.stmts {
			b.walk_stmt(mut stmt)
		}

		b.close_scope(branch.pos.pos + branch.pos.len)
	}
}

fn (mut b ScopeBuilder) walk_match_expr(mut match_expr MatchExpr) {
	// Walk the condition being matched
	b.walk_expr(mut match_expr.cond)

	for mut branch in match_expr.branches {
		branch.scope = b.open_scope(branch.pos.pos)

		// Walk body
		for mut stmt in branch.stmts {
			b.walk_stmt(mut stmt)
		}

		b.close_scope(branch.pos.pos + branch.pos.len)
	}
}

fn (mut b ScopeBuilder) walk_lambda_expr(mut lambda LambdaExpr) {
	lambda.scope = b.open_scope(lambda.pos.pos)

	// Register lambda parameters
	for param in lambda.params {
		b.register_var(Var{
			name:         param.name
			is_mut:       param.is_mut
			is_stack_obj: true
			pos:          param.pos
			is_used:      true
		})
	}

	// Walk lambda body expression
	b.walk_expr(mut lambda.expr)

	b.close_scope(lambda.pos.pos + lambda.pos.len)
}

fn (mut b ScopeBuilder) walk_anon_fn(mut anon AnonFn) {
	// Anonymous functions have their own fn_decl
	b.walk_fn_decl(mut anon.decl)
}

fn (mut b ScopeBuilder) walk_or_expr(mut or_expr OrExpr) {
	if or_expr.stmts.len == 0 {
		return
	}

	// OrExpr.scope is immutable (pub: field)
	scope := b.open_scope(or_expr.pos.pos)
	unsafe {
		mut ptr := &or_expr.scope
		*ptr = scope
	}
	// Register 'err' variable in or-block scope
	if or_expr.kind == .block {
		b.register_var(Var{
			name:         'err'
			typ:          error_type
			pos:          or_expr.pos
			is_used:      false
			is_stack_obj: true
		})
	}

	for mut stmt in or_expr.stmts {
		b.walk_stmt(mut stmt)
	}

	b.close_scope(or_expr.pos.pos + or_expr.pos.len)
}

fn (mut b ScopeBuilder) walk_lock_expr(mut lock_expr LockExpr) {
	lock_expr.scope = b.open_scope(lock_expr.pos.pos)

	for mut stmt in lock_expr.stmts {
		b.walk_stmt(mut stmt)
	}

	b.close_scope(lock_expr.pos.pos + lock_expr.pos.len)
}

fn (mut b ScopeBuilder) walk_select_expr(mut select_expr SelectExpr) {
	for mut branch in select_expr.branches {
		// SelectBranch.scope is immutable (pub: field)
		scope := b.open_scope(branch.pos.pos)
		unsafe {
			mut ptr := &branch.scope
			*ptr = scope
		}
		// Walk body
		for mut stmt in branch.stmts {
			b.walk_stmt(mut stmt)
		}

		b.close_scope(branch.pos.pos + branch.pos.len)
	}
}

// --- Table Contributions Serialization ---
// These are the types/functions that a file contributes to the shared ast.Table

// TableContributions holds what a file contributes to ast.Table
pub struct TableContributions {
pub mut:
	type_symbols []TypeSymbol   // types defined in this file
	functions    []Fn           // functions defined in this file
	type_names   map[int]string // type index -> fully qualified name (for remapping)
}

// TypeInfoKind enum for serialization dispatch
enum TypeInfoKind as u8 {
	unknown
	alias
	array
	array_fixed
	chan_
	enum_
	fn_type
	generic_inst
	interface_
	map_
	multi_return
	struct_
	sum_type
	thread
	aggregate
}

// write_table_contributions serializes table contributions
pub fn (mut w AstWriter) write_table_contributions(tc &TableContributions) {
	// Write type symbols
	w.write_u32(u32(tc.type_symbols.len))
	for ts in tc.type_symbols {
		w.write_type_symbol(ts)
	}
	// Write functions
	w.write_u32(u32(tc.functions.len))
	for f in tc.functions {
		w.write_fn(f)
	}
	// Write type_names map for type index remapping
	w.write_u32(u32(tc.type_names.len))
	for idx, name in tc.type_names {
		w.write_i32(idx)
		w.write_string(name)
	}
}

// read_table_contributions deserializes table contributions
pub fn (mut r AstReader) read_table_contributions() TableContributions {
	// Read type symbols
	ts_len := r.read_u32()
	mut type_symbols := []TypeSymbol{cap: int(ts_len)}
	for _ in 0 .. ts_len {
		type_symbols << r.read_type_symbol()
	}
	// Read functions
	fn_len := r.read_u32()
	mut functions := []Fn{cap: int(fn_len)}
	for _ in 0 .. fn_len {
		functions << r.read_fn()
	}
	// Read type_names map
	tn_len := r.read_u32()
	mut type_names := map[int]string{}
	for _ in 0 .. tn_len {
		idx := r.read_i32()
		name := r.read_string()
		type_names[idx] = name
	}
	return TableContributions{
		type_symbols: type_symbols
		functions:    functions
		type_names:   type_names
	}
}

// --- TypeSymbol Serialization ---

fn (mut w AstWriter) write_type_symbol(ts TypeSymbol) {
	w.write_i32(ts.parent_idx)
	w.write_u8(u8(ts.kind))
	w.write_string(ts.name)
	w.write_string(ts.cname)
	w.write_string(ts.rname)
	w.write_string(ts.ngname)
	w.write_string(ts.mod)
	w.write_bool(ts.is_pub)
	w.write_bool(ts.is_builtin)
	w.write_u8(u8(ts.language))
	w.write_i32(ts.idx)
	w.write_i32(ts.size)
	w.write_i32(ts.align)
	// Write generic_types
	w.write_type_array(ts.generic_types)
	// Write methods
	w.write_u32(u32(ts.methods.len))
	for m in ts.methods {
		w.write_fn(m)
	}
	// Write TypeInfo
	w.write_type_info(ts.info)
}

fn (mut r AstReader) read_type_symbol() TypeSymbol {
	parent_idx := r.read_i32()
	kind := unsafe { Kind(r.read_u8()) }
	name := r.read_string()
	cname := r.read_string()
	rname := r.read_string()
	ngname := r.read_string()
	mod := r.read_string()
	is_pub := r.read_bool()
	is_builtin := r.read_bool()
	language := unsafe { Language(r.read_u8()) }
	idx := r.read_i32()
	size := r.read_i32()
	align := r.read_i32()
	generic_types := r.read_type_array()
	// Read methods
	methods_len := r.read_u32()
	mut methods := []Fn{cap: int(methods_len)}
	for _ in 0 .. methods_len {
		methods << r.read_fn()
	}
	info := r.read_type_info()
	return TypeSymbol{
		parent_idx:    parent_idx
		kind:          kind
		name:          name
		cname:         cname
		rname:         rname
		ngname:        ngname
		mod:           mod
		is_pub:        is_pub
		is_builtin:    is_builtin
		language:      language
		idx:           idx
		size:          size
		align:         align
		generic_types: generic_types
		methods:       methods
		info:          info
	}
}

// --- TypeInfo Serialization ---

fn (mut w AstWriter) write_type_info(info TypeInfo) {
	match info {
		UnknownTypeInfo {
			w.write_u8(u8(TypeInfoKind.unknown))
		}
		Alias {
			w.write_u8(u8(TypeInfoKind.alias))
			w.write_type(info.parent_type)
			w.write_u8(u8(info.language))
			w.write_bool(info.is_import)
			w.write_pos(info.name_pos)
		}
		Array {
			w.write_u8(u8(TypeInfoKind.array))
			w.write_i32(info.nr_dims)
			w.write_type(info.elem_type)
		}
		ArrayFixed {
			w.write_u8(u8(TypeInfoKind.array_fixed))
			w.write_i32(info.size)
			w.write_type(info.elem_type)
			w.write_bool(info.is_fn_ret)
			// Skip size_expr for now (complex)
		}
		Chan {
			w.write_u8(u8(TypeInfoKind.chan_))
			w.write_type(info.elem_type)
			w.write_bool(info.is_mut)
		}
		Enum {
			w.write_u8(u8(TypeInfoKind.enum_))
			w.write_string_array(info.vals)
			w.write_bool(info.is_flag)
			w.write_bool(info.is_multi_allowed)
			w.write_bool(info.uses_exprs)
			w.write_type(info.typ)
			w.write_pos(info.name_pos)
			// Skip attrs map for now
		}
		FnType {
			w.write_u8(u8(TypeInfoKind.fn_type))
			w.write_bool(info.is_anon)
			w.write_bool(info.has_decl)
			w.write_fn(info.func)
		}
		GenericInst {
			w.write_u8(u8(TypeInfoKind.generic_inst))
			w.write_i32(info.parent_idx)
			w.write_type_array(info.concrete_types)
		}
		Interface {
			w.write_u8(u8(TypeInfoKind.interface_))
			w.write_type_array(info.types)
			w.write_struct_field_array(info.fields)
			w.write_u32(u32(info.methods.len))
			for m in info.methods {
				w.write_fn(m)
			}
			w.write_type_array(info.embeds)
			w.write_bool(info.is_generic)
			w.write_bool(info.is_markused)
			w.write_type_array(info.generic_types)
			w.write_type_array(info.concrete_types)
			w.write_type(info.parent_type)
			w.write_pos(info.name_pos)
		}
		Map {
			w.write_u8(u8(TypeInfoKind.map_))
			w.write_type(info.key_type)
			w.write_type(info.value_type)
			w.write_pos(info.name_pos)
		}
		MultiReturn {
			w.write_u8(u8(TypeInfoKind.multi_return))
			w.write_type_array(info.types)
		}
		Struct {
			w.write_u8(u8(TypeInfoKind.struct_))
			w.write_attr_array(info.attrs)
			w.write_string(info.scoped_name)
			w.write_type_array(info.embeds)
			w.write_struct_field_array(info.fields)
			w.write_bool(info.is_typedef)
			w.write_bool(info.is_union)
			w.write_bool(info.is_heap)
			w.write_bool(info.is_minify)
			w.write_bool(info.is_anon)
			w.write_bool(info.is_generic)
			w.write_bool(info.is_shared)
			w.write_bool(info.is_markused)
			w.write_bool(info.has_option)
			w.write_type_array(info.generic_types)
			w.write_type_array(info.concrete_types)
			w.write_type(info.parent_type)
			w.write_pos(info.name_pos)
		}
		SumType {
			w.write_u8(u8(TypeInfoKind.sum_type))
			w.write_struct_field_array(info.fields)
			w.write_bool(info.found_fields)
			w.write_bool(info.is_anon)
			w.write_bool(info.is_generic)
			w.write_type_array(info.variants)
			w.write_type_array(info.generic_types)
			w.write_type_array(info.concrete_types)
			w.write_type(info.parent_type)
			w.write_pos(info.name_pos)
		}
		Thread {
			w.write_u8(u8(TypeInfoKind.thread))
			w.write_type(info.return_type)
		}
		Aggregate {
			w.write_u8(u8(TypeInfoKind.aggregate))
			w.write_struct_field_array(info.fields)
			w.write_type(info.sum_type)
			w.write_type_array(info.types)
		}
	}
}

fn (mut r AstReader) read_type_info() TypeInfo {
	info_kind := unsafe { TypeInfoKind(r.read_u8()) }
	match info_kind {
		.unknown {
			return UnknownTypeInfo{}
		}
		.alias {
			parent_type := r.read_type()
			language := unsafe { Language(r.read_u8()) }
			is_import := r.read_bool()
			name_pos := r.read_pos()
			return Alias{
				parent_type: parent_type
				language:    language
				is_import:   is_import
				name_pos:    name_pos
			}
		}
		.array {
			nr_dims := r.read_i32()
			elem_type := r.read_type()
			return Array{
				nr_dims:   nr_dims
				elem_type: elem_type
			}
		}
		.array_fixed {
			size := r.read_i32()
			elem_type := r.read_type()
			is_fn_ret := r.read_bool()
			return ArrayFixed{
				size:      size
				elem_type: elem_type
				is_fn_ret: is_fn_ret
			}
		}
		.chan_ {
			elem_type := r.read_type()
			is_mut := r.read_bool()
			return Chan{
				elem_type: elem_type
				is_mut:    is_mut
			}
		}
		.enum_ {
			vals := r.read_string_array()
			is_flag := r.read_bool()
			is_multi_allowed := r.read_bool()
			uses_exprs := r.read_bool()
			typ := r.read_type()
			name_pos := r.read_pos()
			return Enum{
				vals:             vals
				is_flag:          is_flag
				is_multi_allowed: is_multi_allowed
				uses_exprs:       uses_exprs
				typ:              typ
				name_pos:         name_pos
			}
		}
		.fn_type {
			is_anon := r.read_bool()
			has_decl := r.read_bool()
			func := r.read_fn()
			return FnType{
				is_anon:  is_anon
				has_decl: has_decl
				func:     func
			}
		}
		.generic_inst {
			parent_idx := r.read_i32()
			concrete_types := r.read_type_array()
			return GenericInst{
				parent_idx:     parent_idx
				concrete_types: concrete_types
			}
		}
		.interface_ {
			types := r.read_type_array()
			fields := r.read_struct_field_array()
			methods_len := r.read_u32()
			mut methods := []Fn{cap: int(methods_len)}
			for _ in 0 .. methods_len {
				methods << r.read_fn()
			}
			embeds := r.read_type_array()
			is_generic := r.read_bool()
			is_markused := r.read_bool()
			generic_types := r.read_type_array()
			concrete_types := r.read_type_array()
			parent_type := r.read_type()
			name_pos := r.read_pos()
			return Interface{
				types:          types
				fields:         fields
				methods:        methods
				embeds:         embeds
				is_generic:     is_generic
				is_markused:    is_markused
				generic_types:  generic_types
				concrete_types: concrete_types
				parent_type:    parent_type
				name_pos:       name_pos
			}
		}
		.map_ {
			key_type := r.read_type()
			value_type := r.read_type()
			name_pos := r.read_pos()
			return Map{
				key_type:   key_type
				value_type: value_type
				name_pos:   name_pos
			}
		}
		.multi_return {
			types := r.read_type_array()
			return MultiReturn{
				types: types
			}
		}
		.struct_ {
			attrs := r.read_attr_array()
			scoped_name := r.read_string()
			embeds := r.read_type_array()
			fields := r.read_struct_field_array()
			is_typedef := r.read_bool()
			is_union := r.read_bool()
			is_heap := r.read_bool()
			is_minify := r.read_bool()
			is_anon := r.read_bool()
			is_generic := r.read_bool()
			is_shared := r.read_bool()
			is_markused := r.read_bool()
			has_option := r.read_bool()
			generic_types := r.read_type_array()
			concrete_types := r.read_type_array()
			parent_type := r.read_type()
			name_pos := r.read_pos()
			return Struct{
				attrs:          attrs
				scoped_name:    scoped_name
				embeds:         embeds
				fields:         fields
				is_typedef:     is_typedef
				is_union:       is_union
				is_heap:        is_heap
				is_minify:      is_minify
				is_anon:        is_anon
				is_generic:     is_generic
				is_shared:      is_shared
				is_markused:    is_markused
				has_option:     has_option
				generic_types:  generic_types
				concrete_types: concrete_types
				parent_type:    parent_type
				name_pos:       name_pos
			}
		}
		.sum_type {
			fields := r.read_struct_field_array()
			found_fields := r.read_bool()
			is_anon := r.read_bool()
			is_generic := r.read_bool()
			variants := r.read_type_array()
			generic_types := r.read_type_array()
			concrete_types := r.read_type_array()
			parent_type := r.read_type()
			name_pos := r.read_pos()
			return SumType{
				fields:         fields
				found_fields:   found_fields
				is_anon:        is_anon
				is_generic:     is_generic
				variants:       variants
				generic_types:  generic_types
				concrete_types: concrete_types
				parent_type:    parent_type
				name_pos:       name_pos
			}
		}
		.thread {
			return_type := r.read_type()
			return Thread{
				return_type: return_type
			}
		}
		.aggregate {
			fields := r.read_struct_field_array()
			sum_type := r.read_type()
			types := r.read_type_array()
			return Aggregate{
				fields:   fields
				sum_type: sum_type
				types:    types
			}
		}
	}
}

// --- Fn Serialization ---

fn (mut w AstWriter) write_fn(f Fn) {
	w.write_bool(f.is_variadic)
	w.write_bool(f.is_c_variadic)
	w.write_u8(u8(f.language))
	w.write_bool(f.is_pub)
	w.write_bool(f.is_ctor_new)
	w.write_bool(f.is_deprecated)
	w.write_bool(f.is_noreturn)
	w.write_bool(f.is_unsafe)
	w.write_bool(f.is_must_use)
	w.write_bool(f.is_placeholder)
	w.write_bool(f.is_main)
	w.write_bool(f.is_test)
	w.write_bool(f.is_keep_alive)
	w.write_bool(f.is_method)
	w.write_bool(f.is_static_type_method)
	w.write_bool(f.no_body)
	w.write_bool(f.is_file_translated)
	w.write_string(f.mod)
	w.write_string(f.file)
	w.write_u8(u8(f.file_mode))
	w.write_pos(f.pos)
	w.write_pos(f.name_pos)
	w.write_pos(f.return_type_pos)
	w.write_type(f.return_type)
	w.write_type(f.receiver_type)
	w.write_string(f.name)
	w.write_param_array(f.params)
	w.write_i32(f.usages)
	w.write_string_array(f.generic_names)
	w.write_string_array(f.dep_names)
	w.write_attr_array(f.attrs)
	w.write_bool(f.is_conditional)
	w.write_i32(f.ctdefine_idx)
	w.write_type(f.from_embedded_type)
	w.write_bool(f.is_expand_simple_interpolation)
}

// extract_table_contributions extracts what a file contributes to the table
// by walking its declarations (structs, enums, functions, etc.)
pub fn extract_table_contributions(file &File, table &Table) TableContributions {
	mut tc := TableContributions{}

	for stmt in file.stmts {
		match stmt {
			StructDecl {
				// Get the type symbol for this struct from the table
				if idx := table.type_idxs[stmt.name] {
					if ts := table.type_symbols[idx] {
						tc.type_symbols << *ts
					}
				}
			}
			EnumDecl {
				if idx := table.type_idxs[stmt.name] {
					if ts := table.type_symbols[idx] {
						tc.type_symbols << *ts
					}
				}
			}
			InterfaceDecl {
				if idx := table.type_idxs[stmt.name] {
					if ts := table.type_symbols[idx] {
						tc.type_symbols << *ts
					}
				}
			}
			FnDecl {
				// Get function from table
				fkey := stmt.fkey()
				if f := table.fns[fkey] {
					tc.functions << f
				}
			}
			TypeDecl {
				// Type aliases and sumtypes - need full module-qualified name
				short_name := match stmt {
					AliasTypeDecl { stmt.name }
					SumTypeDecl { stmt.name }
					FnTypeDecl { stmt.name }
				}
				mod_name := match stmt {
					AliasTypeDecl { stmt.mod }
					SumTypeDecl { stmt.mod }
					FnTypeDecl { stmt.mod }
				}
				// Construct full name: mod.name (unless it's a C type or builtin)
				full_name := if short_name.starts_with('C.') || mod_name == 'builtin'
					|| mod_name == '' {
					short_name
				} else {
					'${mod_name}.${short_name}'
				}
				if idx := table.type_idxs[full_name] {
					if ts := table.type_symbols[idx] {
						tc.type_symbols << *ts
					}
				} else if idx := table.type_idxs[short_name] {
					// Fallback to short name for builtin types
					if ts := table.type_symbols[idx] {
						tc.type_symbols << *ts
					}
				}
			}
			else {}
		}
	}

	// Build type_names map from all Type values used in contributions
	tc.type_names = build_type_names_map(tc, table)

	return tc
}

// build_type_names_map collects all Type values from contributions and maps them to names
fn build_type_names_map(tc TableContributions, table &Table) map[int]string {
	mut type_names := map[int]string{}

	// Collect types from TypeSymbols
	for ts in tc.type_symbols {
		// generic_types
		for gt in ts.generic_types {
			record_type(gt, table, mut type_names)
		}
		// methods return types and params
		for m in ts.methods {
			record_type(m.return_type, table, mut type_names)
			record_type(m.receiver_type, table, mut type_names)
			record_type(m.from_embedded_type, table, mut type_names)
			for p in m.params {
				record_type(p.typ, table, mut type_names)
			}
		}
		// TypeInfo types
		match ts.info {
			Alias {
				record_type(ts.info.parent_type, table, mut type_names)
			}
			Array {
				record_type(ts.info.elem_type, table, mut type_names)
			}
			ArrayFixed {
				record_type(ts.info.elem_type, table, mut type_names)
			}
			Chan {
				record_type(ts.info.elem_type, table, mut type_names)
			}
			Enum {
				record_type(ts.info.typ, table, mut type_names)
			}
			FnType {
				record_type(ts.info.func.return_type, table, mut type_names)
				record_type(ts.info.func.receiver_type, table, mut type_names)
				for p in ts.info.func.params {
					record_type(p.typ, table, mut type_names)
				}
			}
			GenericInst {
				for ct in ts.info.concrete_types {
					record_type(ct, table, mut type_names)
				}
			}
			Interface {
				for t in ts.info.types {
					record_type(t, table, mut type_names)
				}
				for e in ts.info.embeds {
					record_type(e, table, mut type_names)
				}
				for gt in ts.info.generic_types {
					record_type(gt, table, mut type_names)
				}
				for ct in ts.info.concrete_types {
					record_type(ct, table, mut type_names)
				}
				record_type(ts.info.parent_type, table, mut type_names)
				for fld in ts.info.fields {
					record_type(fld.typ, table, mut type_names)
				}
			}
			Map {
				record_type(ts.info.key_type, table, mut type_names)
				record_type(ts.info.value_type, table, mut type_names)
			}
			MultiReturn {
				for t in ts.info.types {
					record_type(t, table, mut type_names)
				}
			}
			Struct {
				for e in ts.info.embeds {
					record_type(e, table, mut type_names)
				}
				for gt in ts.info.generic_types {
					record_type(gt, table, mut type_names)
				}
				for ct in ts.info.concrete_types {
					record_type(ct, table, mut type_names)
				}
				record_type(ts.info.parent_type, table, mut type_names)
				for fld in ts.info.fields {
					record_type(fld.typ, table, mut type_names)
				}
			}
			SumType {
				for v in ts.info.variants {
					record_type(v, table, mut type_names)
				}
				for gt in ts.info.generic_types {
					record_type(gt, table, mut type_names)
				}
				for ct in ts.info.concrete_types {
					record_type(ct, table, mut type_names)
				}
				record_type(ts.info.parent_type, table, mut type_names)
				for fld in ts.info.fields {
					record_type(fld.typ, table, mut type_names)
				}
			}
			Thread {
				record_type(ts.info.return_type, table, mut type_names)
			}
			Aggregate {
				record_type(ts.info.sum_type, table, mut type_names)
				for t in ts.info.types {
					record_type(t, table, mut type_names)
				}
			}
			else {}
		}
	}

	// Collect types from Functions
	for f in tc.functions {
		record_type(f.return_type, table, mut type_names)
		record_type(f.receiver_type, table, mut type_names)
		record_type(f.from_embedded_type, table, mut type_names)
		for p in f.params {
			record_type(p.typ, table, mut type_names)
		}
	}

	return type_names
}

// record_type adds a type to the type_names map if not already present
fn record_type(t Type, table &Table, mut type_names map[int]string) {
	idx := t.idx()
	if idx <= 0 || idx in type_names {
		return
	}
	if idx >= table.type_symbols.len {
		return
	}
	ts := table.type_symbols[idx] or { return }
	type_names[idx] = ts.name
}

fn (mut r AstReader) read_fn() Fn {
	is_variadic := r.read_bool()
	is_c_variadic := r.read_bool()
	language := unsafe { Language(r.read_u8()) }
	is_pub := r.read_bool()
	is_ctor_new := r.read_bool()
	is_deprecated := r.read_bool()
	is_noreturn := r.read_bool()
	is_unsafe := r.read_bool()
	is_must_use := r.read_bool()
	is_placeholder := r.read_bool()
	is_main := r.read_bool()
	is_test := r.read_bool()
	is_keep_alive := r.read_bool()
	is_method := r.read_bool()
	is_static_type_method := r.read_bool()
	no_body := r.read_bool()
	is_file_translated := r.read_bool()
	mod := r.read_string()
	file := r.read_string()
	file_mode := unsafe { Language(r.read_u8()) }
	pos := r.read_pos()
	name_pos := r.read_pos()
	return_type_pos := r.read_pos()
	return_type := r.read_type()
	receiver_type := r.read_type()
	name := r.read_string()
	params := r.read_param_array()
	usages := r.read_i32()
	generic_names := r.read_string_array()
	dep_names := r.read_string_array()
	attrs := r.read_attr_array()
	is_conditional := r.read_bool()
	ctdefine_idx := r.read_i32()
	from_embedded_type := r.read_type()
	is_expand_simple_interpolation := r.read_bool()
	return Fn{
		is_variadic:                    is_variadic
		is_c_variadic:                  is_c_variadic
		language:                       language
		is_pub:                         is_pub
		is_ctor_new:                    is_ctor_new
		is_deprecated:                  is_deprecated
		is_noreturn:                    is_noreturn
		is_unsafe:                      is_unsafe
		is_must_use:                    is_must_use
		is_placeholder:                 is_placeholder
		is_main:                        is_main
		is_test:                        is_test
		is_keep_alive:                  is_keep_alive
		is_method:                      is_method
		is_static_type_method:          is_static_type_method
		no_body:                        no_body
		is_file_translated:             is_file_translated
		mod:                            mod
		file:                           file
		file_mode:                      file_mode
		pos:                            pos
		name_pos:                       name_pos
		return_type_pos:                return_type_pos
		return_type:                    return_type
		receiver_type:                  receiver_type
		name:                           name
		params:                         params
		usages:                         usages
		generic_names:                  generic_names
		dep_names:                      dep_names
		attrs:                          attrs
		is_conditional:                 is_conditional
		ctdefine_idx:                   ctdefine_idx
		from_embedded_type:             from_embedded_type
		is_expand_simple_interpolation: is_expand_simple_interpolation
	}
}
