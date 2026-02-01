// FlatBuffers Builder for V - constructs FlatBuffer objects
// Ported from https://github.com/google/flatbuffers/blob/master/go/builder.go
module flatbuffers

// Builder is a state machine for creating FlatBuffer objects.
// Use a Builder to construct object(s) starting from leaf nodes.
// A Builder constructs byte buffers in a last-first manner for simplicity and performance.
pub struct Builder {
pub mut:
	// bytes gives raw access to the buffer. Most users will want to use
	// finished_bytes() instead.
	bytes []u8
mut:
	minalign       int
	vtable         []UOffsetT
	object_end     UOffsetT
	vtables        []UOffsetT
	head           UOffsetT
	nested         bool
	finished       bool
	shared_strings map[string]UOffsetT
}

pub const file_identifier_length = 4
pub const size_prefix_length = 4

// new_builder initializes a Builder of size `initial_size`.
// The internal buffer is grown as needed.
pub fn new_builder(initial_size int) &Builder {
	size := if initial_size <= 0 { 1 } else { initial_size }
	mut b := &Builder{
		bytes:    []u8{len: size}
		minalign: 1
		vtables:  []UOffsetT{cap: 16}
	}
	b.head = u32(size)
	return b
}

// reset truncates the underlying Builder buffer, facilitating alloc-free
// reuse of a Builder. It also resets bookkeeping data.
pub fn (mut b Builder) reset() {
	if b.bytes.len > 0 {
		b.bytes = b.bytes[..b.bytes.cap]
	}
	b.vtables.clear()
	b.vtable.clear()
	b.shared_strings.clear()
	b.head = u32(b.bytes.len)
	b.minalign = 1
	b.nested = false
	b.finished = false
}

// finished_bytes returns a pointer to the written data in the byte buffer.
// Panics if the builder is not in a finished state (which is caused by calling `finish()`).
pub fn (b &Builder) finished_bytes() []u8 {
	b.assert_finished()
	return b.bytes[b.head()..]
}

// start_object initializes bookkeeping for writing a new object.
pub fn (mut b Builder) start_object(numfields int) {
	b.assert_not_nested()
	b.nested = true

	// use 32-bit offsets so that arithmetic doesn't overflow.
	if b.vtable.cap < numfields || b.vtable.len == 0 {
		b.vtable = []UOffsetT{len: numfields}
	} else {
		// Resize to numfields
		if b.vtable.len < numfields {
			for _ in b.vtable.len .. numfields {
				b.vtable << UOffsetT(0)
			}
		} else {
			b.vtable = b.vtable[..numfields]
		}
		for i in 0 .. b.vtable.len {
			b.vtable[i] = 0
		}
	}
	b.object_end = b.offset()
}

// write_vtable serializes the vtable for the current object, if applicable.
// Before writing out the vtable, this checks pre-existing vtables for equality.
// If an equal vtable is found, point the object to the existing vtable and return.
pub fn (mut b Builder) write_vtable() UOffsetT {
	// Prepend a zero scalar to the object. Later in this function we'll
	// write an offset here that points to the object's vtable:
	b.prepend_s_offset_t(0)

	object_offset := b.offset()
	mut existing_vtable := UOffsetT(0)

	// Trim vtable of trailing zeroes.
	mut i := b.vtable.len - 1
	for i >= 0 && b.vtable[i] == 0 {
		i--
	}
	b.vtable = b.vtable[..i + 1]

	// Search backwards through existing vtables, because similar vtables
	// are likely to have been recently appended.
	for j := b.vtables.len - 1; j >= 0; j-- {
		// Find the other vtable:
		vt2_offset := b.vtables[j]
		vt2_start := b.bytes.len - int(vt2_offset)
		vt2_len := get_v_offset_t(b.bytes[vt2_start..])

		metadata := vtable_metadata_fields * size_v_offset_t
		vt2_end := vt2_start + int(vt2_len)
		vt2 := b.bytes[vt2_start + metadata..vt2_end]

		// Compare the other vtable to the one under consideration.
		if vtable_equal(b.vtable, object_offset, vt2) {
			existing_vtable = vt2_offset
			break
		}
	}

	if existing_vtable == 0 {
		// Did not find a vtable, so write this one to the buffer.
		// Write out the current vtable in reverse, because
		// serialization occurs in last-first order:
		for k := b.vtable.len - 1; k >= 0; k-- {
			mut off := UOffsetT(0)
			if b.vtable[k] != 0 {
				// Forward reference to field:
				off = object_offset - b.vtable[k]
			}
			b.prepend_v_offset_t(VOffsetT(off))
		}

		// The two metadata fields are written last.
		// First, store the object bytesize:
		object_size := object_offset - b.object_end
		b.prepend_v_offset_t(VOffsetT(object_size))

		// Second, store the vtable bytesize:
		v_bytes := (b.vtable.len + vtable_metadata_fields) * size_v_offset_t
		b.prepend_v_offset_t(u16(v_bytes))

		// Next, write the offset to the new vtable in the
		// already-allocated SOffsetT at the beginning of this object:
		object_start := SOffsetT(b.bytes.len) - SOffsetT(object_offset)
		mut slice := b.bytes[int(object_start)..]
		write_s_offset_t(mut slice, SOffsetT(b.offset()) - SOffsetT(object_offset))

		// Finally, store this vtable in memory for future deduplication:
		b.vtables << b.offset()
	} else {
		// Found a duplicate vtable.
		object_start := SOffsetT(b.bytes.len) - SOffsetT(object_offset)
		b.head = UOffsetT(object_start)

		// Write the offset to the found vtable:
		mut slice := b.bytes[b.head..]
		write_s_offset_t(mut slice, SOffsetT(existing_vtable) - SOffsetT(object_offset))
	}

	b.vtable.clear()
	return object_offset
}

// end_object writes data necessary to finish object construction.
pub fn (mut b Builder) end_object() UOffsetT {
	b.assert_nested()
	n := b.write_vtable()
	b.nested = false
	return n
}

// grow_byte_buffer doubles the size of the byteslice, and copies the old data towards the
// end of the new byteslice (since we build the buffer backwards).
fn (mut b Builder) grow_byte_buffer() {
	if (i64(b.bytes.len) & i64(0xC0000000)) != 0 {
		panic('flatbuffers: cannot grow buffer beyond 2 gigabytes')
	}
	mut new_len := b.bytes.len * 2
	if new_len == 0 {
		new_len = 1
	}

	if b.bytes.cap >= new_len {
		b.bytes = b.bytes[..new_len]
	} else {
		mut new_bytes := []u8{len: new_len}
		copy(mut new_bytes[new_len / 2..], b.bytes)
		b.bytes = new_bytes
		return
	}

	middle := new_len / 2
	copy(mut b.bytes[middle..], b.bytes[..middle])
}

// head gives the start of useful data in the underlying byte buffer.
// Note: unlike other functions, this value is interpreted as from the left.
pub fn (b &Builder) head() UOffsetT {
	return b.head
}

// offset relative to the end of the buffer.
pub fn (b &Builder) offset() UOffsetT {
	return u32(b.bytes.len) - b.head
}

// pad places zeros at the current offset.
pub fn (mut b Builder) pad(n int) {
	for _ in 0 .. n {
		b.place_u8(0)
	}
}

// prep prepares to write an element of `size` after `additional_bytes`
// have been written, e.g. if you write a string, you need to align such
// the int length field is aligned to size_i32, and the string data follows it directly.
// If all you need to do is align, `additional_bytes` will be 0.
pub fn (mut b Builder) prep(size int, additional_bytes int) {
	// Track the biggest thing we've ever aligned to.
	if size > b.minalign {
		b.minalign = size
	}
	// Find the amount of alignment needed such that `size` is properly
	// aligned after `additional_bytes`:
	mut align_size := (~(b.bytes.len - int(b.head) + additional_bytes)) + 1
	align_size &= (size - 1)

	// Reallocate the buffer if needed:
	for int(b.head) <= align_size + size + additional_bytes {
		old_buf_size := b.bytes.len
		b.grow_byte_buffer()
		b.head += u32(b.bytes.len - old_buf_size)
	}
	b.pad(align_size)
}

// prepend_s_offset_t prepends an SOffsetT, relative to where it will be written.
pub fn (mut b Builder) prepend_s_offset_t(off SOffsetT) {
	b.prep(size_s_offset_t, 0)
	if !(UOffsetT(off) <= b.offset()) {
		panic('flatbuffers: unreachable: off <= b.offset()')
	}
	off2 := SOffsetT(b.offset()) - off + SOffsetT(size_s_offset_t)
	b.place_s_offset_t(off2)
}

// prepend_u_offset_t prepends an UOffsetT, relative to where it will be written.
pub fn (mut b Builder) prepend_u_offset_t(off UOffsetT) {
	b.prep(size_u_offset_t, 0)
	if !(off <= b.offset()) {
		panic('flatbuffers: unreachable: off <= b.offset()')
	}
	off2 := b.offset() - off + UOffsetT(size_u_offset_t)
	b.place_u_offset_t(off2)
}

// start_vector initializes bookkeeping for writing a new vector.
// A vector has the following format:
//   <UOffsetT: number of elements in this vector>
//   <T: data>+, where T is the type of elements of this vector.
pub fn (mut b Builder) start_vector(elem_size int, num_elems int, alignment int) UOffsetT {
	b.assert_not_nested()
	b.nested = true
	b.prep(size_u32, elem_size * num_elems)
	b.prep(alignment, elem_size * num_elems) // Just in case alignment > int.
	return b.offset()
}

// end_vector writes data necessary to finish vector construction.
pub fn (mut b Builder) end_vector(vector_num_elems int) UOffsetT {
	b.assert_nested()
	// we already made space for this, so write without prepend_u32
	b.place_u_offset_t(u32(vector_num_elems))
	b.nested = false
	return b.offset()
}

// create_vector_of_tables serializes slice of table offsets into a vector.
pub fn (mut b Builder) create_vector_of_tables(offsets []UOffsetT) UOffsetT {
	b.assert_not_nested()
	b.start_vector(4, offsets.len, 4)
	for i := offsets.len - 1; i >= 0; i-- {
		b.prepend_u_offset_t(offsets[i])
	}
	return b.end_vector(offsets.len)
}

// create_shared_string checks if the string is already written
// to the buffer before calling create_string
pub fn (mut b Builder) create_shared_string(s string) UOffsetT {
	if v := b.shared_strings[s] {
		return v
	}
	off := b.create_string(s)
	b.shared_strings[s] = off
	return off
}

// create_string writes a null-terminated string as a vector.
pub fn (mut b Builder) create_string(s string) UOffsetT {
	b.assert_not_nested()
	b.nested = true

	b.prep(int(size_u_offset_t), (s.len + 1) * size_u8)
	b.place_u8(0)

	l := u32(s.len)
	b.head -= l
	unsafe {
		vmemcpy(&b.bytes[b.head], s.str, s.len)
	}

	return b.end_vector(s.len)
}

// create_byte_string writes a byte slice as a string (null-terminated).
pub fn (mut b Builder) create_byte_string(s []u8) UOffsetT {
	b.assert_not_nested()
	b.nested = true

	b.prep(int(size_u_offset_t), (s.len + 1) * size_u8)
	b.place_u8(0)

	l := u32(s.len)
	b.head -= l
	copy(mut b.bytes[b.head..], s)

	return b.end_vector(s.len)
}

// create_byte_vector writes a ubyte vector.
pub fn (mut b Builder) create_byte_vector(v []u8) UOffsetT {
	b.assert_not_nested()
	b.nested = true

	b.prep(int(size_u_offset_t), v.len * size_u8)

	l := u32(v.len)
	b.head -= l
	copy(mut b.bytes[b.head..], v)

	return b.end_vector(v.len)
}

fn (b &Builder) assert_nested() {
	if !b.nested {
		panic('flatbuffers: incorrect creation order: must be inside object.')
	}
}

fn (b &Builder) assert_not_nested() {
	if b.nested {
		panic('flatbuffers: incorrect creation order: object must not be nested.')
	}
}

fn (b &Builder) assert_finished() {
	if !b.finished {
		panic("flatbuffers: incorrect use of finished_bytes(): must call 'finish' first.")
	}
}

// --- Slot methods (prepend with default value checking) ---

// prepend_bool_slot prepends a bool onto the object at vtable slot `o`.
pub fn (mut b Builder) prepend_bool_slot(o int, x bool, d bool) {
	if x != d {
		b.prepend_bool(x)
		b.slot(o)
	}
}

// prepend_u8_slot prepends a u8 onto the object at vtable slot `o`.
pub fn (mut b Builder) prepend_u8_slot(o int, x u8, d u8) {
	if x != d {
		b.prepend_u8(x)
		b.slot(o)
	}
}

// prepend_u16_slot prepends a u16 onto the object at vtable slot `o`.
pub fn (mut b Builder) prepend_u16_slot(o int, x u16, d u16) {
	if x != d {
		b.prepend_u16(x)
		b.slot(o)
	}
}

// prepend_u32_slot prepends a u32 onto the object at vtable slot `o`.
pub fn (mut b Builder) prepend_u32_slot(o int, x u32, d u32) {
	if x != d {
		b.prepend_u32(x)
		b.slot(o)
	}
}

// prepend_u64_slot prepends a u64 onto the object at vtable slot `o`.
pub fn (mut b Builder) prepend_u64_slot(o int, x u64, d u64) {
	if x != d {
		b.prepend_u64(x)
		b.slot(o)
	}
}

// prepend_i8_slot prepends an i8 onto the object at vtable slot `o`.
pub fn (mut b Builder) prepend_i8_slot(o int, x i8, d i8) {
	if x != d {
		b.prepend_i8(x)
		b.slot(o)
	}
}

// prepend_i16_slot prepends an i16 onto the object at vtable slot `o`.
pub fn (mut b Builder) prepend_i16_slot(o int, x i16, d i16) {
	if x != d {
		b.prepend_i16(x)
		b.slot(o)
	}
}

// prepend_i32_slot prepends an i32 onto the object at vtable slot `o`.
pub fn (mut b Builder) prepend_i32_slot(o int, x i32, d i32) {
	if x != d {
		b.prepend_i32(x)
		b.slot(o)
	}
}

// prepend_i64_slot prepends an i64 onto the object at vtable slot `o`.
pub fn (mut b Builder) prepend_i64_slot(o int, x i64, d i64) {
	if x != d {
		b.prepend_i64(x)
		b.slot(o)
	}
}

// prepend_f32_slot prepends an f32 onto the object at vtable slot `o`.
pub fn (mut b Builder) prepend_f32_slot(o int, x f32, d f32) {
	if x != d {
		b.prepend_f32(x)
		b.slot(o)
	}
}

// prepend_f64_slot prepends an f64 onto the object at vtable slot `o`.
pub fn (mut b Builder) prepend_f64_slot(o int, x f64, d f64) {
	if x != d {
		b.prepend_f64(x)
		b.slot(o)
	}
}

// prepend_u_offset_t_slot prepends an UOffsetT onto the object at vtable slot `o`.
pub fn (mut b Builder) prepend_u_offset_t_slot(o int, x UOffsetT, d UOffsetT) {
	if x != d {
		b.prepend_u_offset_t(x)
		b.slot(o)
	}
}

// prepend_struct_slot prepends a struct onto the object at vtable slot `o`.
// Structs are stored inline, so nothing additional is being added.
pub fn (mut b Builder) prepend_struct_slot(voffset int, x UOffsetT, d UOffsetT) {
	if x != d {
		b.assert_nested()
		if x != b.offset() {
			panic('flatbuffers: inline data write outside of object')
		}
		b.slot(voffset)
	}
}

// slot sets the vtable key `voffset` to the current location in the buffer.
pub fn (mut b Builder) slot(slotnum int) {
	b.vtable[slotnum] = b.offset()
}

// finish_with_file_identifier finalizes a buffer, pointing to the given `root_table`
// as well as applies a file identifier.
pub fn (mut b Builder) finish_with_file_identifier(root_table UOffsetT, fid []u8) {
	if fid.len != file_identifier_length {
		panic('flatbuffers: incorrect file identifier length')
	}
	b.prep(b.minalign, size_i32 + file_identifier_length)
	for i := file_identifier_length - 1; i >= 0; i-- {
		b.place_u8(fid[i])
	}
	b.finish(root_table)
}

// finish_size_prefixed finalizes a buffer, pointing to the given `root_table`.
// The buffer is prefixed with the size of the buffer, excluding the size of the prefix itself.
pub fn (mut b Builder) finish_size_prefixed(root_table UOffsetT) {
	b.finish_impl(root_table, true)
}

// finish finalizes a buffer, pointing to the given `root_table`.
pub fn (mut b Builder) finish(root_table UOffsetT) {
	b.finish_impl(root_table, false)
}

// finish_impl finalizes a buffer, pointing to the given `root_table` with an optional size prefix.
fn (mut b Builder) finish_impl(root_table UOffsetT, size_prefix bool) {
	b.assert_not_nested()

	if size_prefix {
		b.prep(b.minalign, size_u_offset_t + size_prefix_length)
	} else {
		b.prep(b.minalign, size_u_offset_t)
	}

	b.prepend_u_offset_t(root_table)

	if size_prefix {
		b.place_u32(u32(b.offset()))
	}

	b.finished = true
}

// vtable_equal compares an unwritten vtable to a written vtable.
fn vtable_equal(a []UOffsetT, object_start UOffsetT, b []u8) bool {
	if a.len * size_v_offset_t != b.len {
		return false
	}

	for i in 0 .. a.len {
		x := get_v_offset_t(b[i * size_v_offset_t..(i + 1) * size_v_offset_t])

		// Skip vtable entries that indicate a default value.
		if x == 0 && a[i] == 0 {
			continue
		}

		y := SOffsetT(object_start) - SOffsetT(a[i])
		if SOffsetT(x) != y {
			return false
		}
	}
	return true
}

// --- Prepend methods (with alignment) ---

pub fn (mut b Builder) prepend_bool(x bool) {
	b.prep(size_bool, 0)
	b.place_bool(x)
}

pub fn (mut b Builder) prepend_u8(x u8) {
	b.prep(size_u8, 0)
	b.place_u8(x)
}

pub fn (mut b Builder) prepend_u16(x u16) {
	b.prep(size_u16, 0)
	b.place_u16(x)
}

pub fn (mut b Builder) prepend_u32(x u32) {
	b.prep(size_u32, 0)
	b.place_u32(x)
}

pub fn (mut b Builder) prepend_u64(x u64) {
	b.prep(size_u64, 0)
	b.place_u64(x)
}

pub fn (mut b Builder) prepend_i8(x i8) {
	b.prep(size_i8, 0)
	b.place_i8(x)
}

pub fn (mut b Builder) prepend_i16(x i16) {
	b.prep(size_i16, 0)
	b.place_i16(x)
}

pub fn (mut b Builder) prepend_i32(x i32) {
	b.prep(size_i32, 0)
	b.place_i32(x)
}

pub fn (mut b Builder) prepend_i64(x i64) {
	b.prep(size_i64, 0)
	b.place_i64(x)
}

pub fn (mut b Builder) prepend_f32(x f32) {
	b.prep(size_f32, 0)
	b.place_f32(x)
}

pub fn (mut b Builder) prepend_f64(x f64) {
	b.prep(size_f64, 0)
	b.place_f64(x)
}

pub fn (mut b Builder) prepend_v_offset_t(x VOffsetT) {
	b.prep(size_v_offset_t, 0)
	b.place_v_offset_t(x)
}

// --- Place methods (without alignment, direct write) ---

pub fn (mut b Builder) place_bool(x bool) {
	b.head -= UOffsetT(size_bool)
	mut slice := b.bytes[b.head..]
	write_bool(mut slice, x)
}

pub fn (mut b Builder) place_u8(x u8) {
	b.head -= UOffsetT(size_u8)
	mut slice := b.bytes[b.head..]
	write_u8(mut slice, x)
}

pub fn (mut b Builder) place_u16(x u16) {
	b.head -= UOffsetT(size_u16)
	mut slice := b.bytes[b.head..]
	write_u16(mut slice, x)
}

pub fn (mut b Builder) place_u32(x u32) {
	b.head -= UOffsetT(size_u32)
	mut slice := b.bytes[b.head..]
	write_u32(mut slice, x)
}

pub fn (mut b Builder) place_u64(x u64) {
	b.head -= UOffsetT(size_u64)
	mut slice := b.bytes[b.head..]
	write_u64(mut slice, x)
}

pub fn (mut b Builder) place_i8(x i8) {
	b.head -= UOffsetT(size_i8)
	mut slice := b.bytes[b.head..]
	write_i8(mut slice, x)
}

pub fn (mut b Builder) place_i16(x i16) {
	b.head -= UOffsetT(size_i16)
	mut slice := b.bytes[b.head..]
	write_i16(mut slice, x)
}

pub fn (mut b Builder) place_i32(x i32) {
	b.head -= UOffsetT(size_i32)
	mut slice := b.bytes[b.head..]
	write_i32(mut slice, x)
}

pub fn (mut b Builder) place_i64(x i64) {
	b.head -= UOffsetT(size_i64)
	mut slice := b.bytes[b.head..]
	write_i64(mut slice, x)
}

pub fn (mut b Builder) place_f32(x f32) {
	b.head -= UOffsetT(size_f32)
	mut slice := b.bytes[b.head..]
	write_f32(mut slice, x)
}

pub fn (mut b Builder) place_f64(x f64) {
	b.head -= UOffsetT(size_f64)
	mut slice := b.bytes[b.head..]
	write_f64(mut slice, x)
}

pub fn (mut b Builder) place_v_offset_t(x VOffsetT) {
	b.head -= UOffsetT(size_v_offset_t)
	mut slice := b.bytes[b.head..]
	write_v_offset_t(mut slice, x)
}

pub fn (mut b Builder) place_s_offset_t(x SOffsetT) {
	b.head -= UOffsetT(size_s_offset_t)
	mut slice := b.bytes[b.head..]
	write_s_offset_t(mut slice, x)
}

pub fn (mut b Builder) place_u_offset_t(x UOffsetT) {
	b.head -= UOffsetT(size_u_offset_t)
	mut slice := b.bytes[b.head..]
	write_u_offset_t(mut slice, x)
}
