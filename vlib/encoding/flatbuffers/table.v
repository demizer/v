// FlatBuffers Table for V - read access to serialized data
// Ported from https://github.com/google/flatbuffers/blob/master/go/table.go
module flatbuffers

// Table wraps a byte slice and provides read access to its data.
// The field `pos` indicates the root of the FlatBuffers object therein.
pub struct Table {
pub mut:
	bytes []u8
	pos   UOffsetT // Always < 1<<31
}

// offset provides access into the Table's vtable.
// Fields which are deprecated are ignored by checking against the vtable's length.
pub fn (t &Table) offset(vtable_offset VOffsetT) VOffsetT {
	vtable := UOffsetT(SOffsetT(t.pos) - t.get_s_offset_t(t.pos))
	if vtable_offset < t.get_v_offset_t(vtable) {
		return t.get_v_offset_t(vtable + UOffsetT(vtable_offset))
	}
	return 0
}

// indirect retrieves the relative offset stored at `off`.
pub fn (t &Table) indirect(off UOffsetT) UOffsetT {
	return off + get_u_offset_t(t.bytes[off..])
}

// string_ gets a string from data stored inside the flatbuffer.
pub fn (t &Table) string_(off UOffsetT) string {
	b := t.byte_vector(off)
	if b.len == 0 {
		return ''
	}
	return unsafe { tos(b.data, b.len) }
}

// byte_vector gets a byte slice from data stored inside the flatbuffer.
// If the offset is invalid or out of bounds, returns empty slice.
pub fn (t &Table) byte_vector(off UOffsetT) []u8 {
	n := u32(t.bytes.len)
	u := u32(size_u_offset_t)
	// Need at least size_u_offset_t bytes to read the relative vector offset.
	if n < u || off > n - u {
		return []
	}
	off2 := off + get_u_offset_t(t.bytes[off..])
	// Need at least size_u_offset_t bytes to read the vector length.
	if n < u || off2 > n - u {
		return []
	}
	start := off2 + UOffsetT(size_u_offset_t)
	length := get_u_offset_t(t.bytes[off2..])
	// Avoid overflow by checking the length against the remaining buffer space.
	if length > n - start {
		return []
	}
	return t.bytes[start..start + length]
}

// vector_len retrieves the length of the vector whose offset is stored at
// "off" in this object.
pub fn (t &Table) vector_len(off UOffsetT) int {
	off2 := off + t.pos
	off3 := off2 + get_u_offset_t(t.bytes[off2..])
	return int(get_u_offset_t(t.bytes[off3..]))
}

// vector retrieves the start of data of the vector whose offset is stored
// at "off" in this object.
pub fn (t &Table) vector(off UOffsetT) UOffsetT {
	off2 := off + t.pos
	x := off2 + get_u_offset_t(t.bytes[off2..])
	// data starts after metadata containing the vector length
	return x + UOffsetT(size_u_offset_t)
}

// union_ initializes any Table-derived type to point to the union at the given offset.
pub fn (t &Table) union_(mut t2 Table, off UOffsetT) {
	off2 := off + t.pos
	t2.pos = off2 + t.get_u_offset_t(off2)
	t2.bytes = t.bytes
}

// --- Scalar getters ---

// get_bool retrieves a bool at the given offset.
@[inline]
pub fn (t &Table) get_bool(off UOffsetT) bool {
	return get_bool(t.bytes[off..])
}

// get_u8 retrieves a u8 at the given offset.
@[inline]
pub fn (t &Table) get_u8(off UOffsetT) u8 {
	return get_u8(t.bytes[off..])
}

// get_u16 retrieves a u16 at the given offset.
@[inline]
pub fn (t &Table) get_u16(off UOffsetT) u16 {
	return get_u16(t.bytes[off..])
}

// get_u32 retrieves a u32 at the given offset.
@[inline]
pub fn (t &Table) get_u32(off UOffsetT) u32 {
	return get_u32(t.bytes[off..])
}

// get_u64 retrieves a u64 at the given offset.
@[inline]
pub fn (t &Table) get_u64(off UOffsetT) u64 {
	return get_u64(t.bytes[off..])
}

// get_i8 retrieves an i8 at the given offset.
@[inline]
pub fn (t &Table) get_i8(off UOffsetT) i8 {
	return get_i8(t.bytes[off..])
}

// get_i16 retrieves an i16 at the given offset.
@[inline]
pub fn (t &Table) get_i16(off UOffsetT) i16 {
	return get_i16(t.bytes[off..])
}

// get_i32 retrieves an i32 at the given offset.
@[inline]
pub fn (t &Table) get_i32(off UOffsetT) i32 {
	return get_i32(t.bytes[off..])
}

// get_i64 retrieves an i64 at the given offset.
@[inline]
pub fn (t &Table) get_i64(off UOffsetT) i64 {
	return get_i64(t.bytes[off..])
}

// get_f32 retrieves an f32 at the given offset.
@[inline]
pub fn (t &Table) get_f32(off UOffsetT) f32 {
	return get_f32(t.bytes[off..])
}

// get_f64 retrieves an f64 at the given offset.
@[inline]
pub fn (t &Table) get_f64(off UOffsetT) f64 {
	return get_f64(t.bytes[off..])
}

// get_u_offset_t retrieves a UOffsetT at the given offset.
@[inline]
pub fn (t &Table) get_u_offset_t(off UOffsetT) UOffsetT {
	return get_u_offset_t(t.bytes[off..])
}

// get_v_offset_t retrieves a VOffsetT at the given offset.
@[inline]
pub fn (t &Table) get_v_offset_t(off UOffsetT) VOffsetT {
	return get_v_offset_t(t.bytes[off..])
}

// get_s_offset_t retrieves a SOffsetT at the given offset.
@[inline]
pub fn (t &Table) get_s_offset_t(off UOffsetT) SOffsetT {
	return get_s_offset_t(t.bytes[off..])
}

// --- Slot getters (with default values) ---

// get_bool_slot retrieves the bool that the given vtable location
// points to. If the vtable value is zero, the default value `d` will be returned.
pub fn (t &Table) get_bool_slot(slot VOffsetT, d bool) bool {
	off := t.offset(slot)
	if off == 0 {
		return d
	}
	return t.get_bool(t.pos + UOffsetT(off))
}

// get_u8_slot retrieves the u8 that the given vtable location
// points to. If the vtable value is zero, the default value `d` will be returned.
pub fn (t &Table) get_u8_slot(slot VOffsetT, d u8) u8 {
	off := t.offset(slot)
	if off == 0 {
		return d
	}
	return t.get_u8(t.pos + UOffsetT(off))
}

// get_i8_slot retrieves the i8 that the given vtable location
// points to. If the vtable value is zero, the default value `d` will be returned.
pub fn (t &Table) get_i8_slot(slot VOffsetT, d i8) i8 {
	off := t.offset(slot)
	if off == 0 {
		return d
	}
	return t.get_i8(t.pos + UOffsetT(off))
}

// get_u16_slot retrieves the u16 that the given vtable location
// points to. If the vtable value is zero, the default value `d` will be returned.
pub fn (t &Table) get_u16_slot(slot VOffsetT, d u16) u16 {
	off := t.offset(slot)
	if off == 0 {
		return d
	}
	return t.get_u16(t.pos + UOffsetT(off))
}

// get_i16_slot retrieves the i16 that the given vtable location
// points to. If the vtable value is zero, the default value `d` will be returned.
pub fn (t &Table) get_i16_slot(slot VOffsetT, d i16) i16 {
	off := t.offset(slot)
	if off == 0 {
		return d
	}
	return t.get_i16(t.pos + UOffsetT(off))
}

// get_u32_slot retrieves the u32 that the given vtable location
// points to. If the vtable value is zero, the default value `d` will be returned.
pub fn (t &Table) get_u32_slot(slot VOffsetT, d u32) u32 {
	off := t.offset(slot)
	if off == 0 {
		return d
	}
	return t.get_u32(t.pos + UOffsetT(off))
}

// get_i32_slot retrieves the i32 that the given vtable location
// points to. If the vtable value is zero, the default value `d` will be returned.
pub fn (t &Table) get_i32_slot(slot VOffsetT, d i32) i32 {
	off := t.offset(slot)
	if off == 0 {
		return d
	}
	return t.get_i32(t.pos + UOffsetT(off))
}

// get_u64_slot retrieves the u64 that the given vtable location
// points to. If the vtable value is zero, the default value `d` will be returned.
pub fn (t &Table) get_u64_slot(slot VOffsetT, d u64) u64 {
	off := t.offset(slot)
	if off == 0 {
		return d
	}
	return t.get_u64(t.pos + UOffsetT(off))
}

// get_i64_slot retrieves the i64 that the given vtable location
// points to. If the vtable value is zero, the default value `d` will be returned.
pub fn (t &Table) get_i64_slot(slot VOffsetT, d i64) i64 {
	off := t.offset(slot)
	if off == 0 {
		return d
	}
	return t.get_i64(t.pos + UOffsetT(off))
}

// get_f32_slot retrieves the f32 that the given vtable location
// points to. If the vtable value is zero, the default value `d` will be returned.
pub fn (t &Table) get_f32_slot(slot VOffsetT, d f32) f32 {
	off := t.offset(slot)
	if off == 0 {
		return d
	}
	return t.get_f32(t.pos + UOffsetT(off))
}

// get_f64_slot retrieves the f64 that the given vtable location
// points to. If the vtable value is zero, the default value `d` will be returned.
pub fn (t &Table) get_f64_slot(slot VOffsetT, d f64) f64 {
	off := t.offset(slot)
	if off == 0 {
		return d
	}
	return t.get_f64(t.pos + UOffsetT(off))
}

// --- Helper functions ---

// get_root_as returns a Table for the root object in the buffer.
pub fn get_root_as(buf []u8) Table {
	n := get_u_offset_t(buf)
	return Table{
		bytes: buf
		pos:   n
	}
}

// get_size_prefixed_root_as returns a Table for the root object in a size-prefixed buffer.
pub fn get_size_prefixed_root_as(buf []u8) Table {
	n := get_u_offset_t(buf[size_u32..])
	return Table{
		bytes: unsafe { buf[size_u32..] }
		pos:   n
	}
}
