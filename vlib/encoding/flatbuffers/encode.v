// FlatBuffers encoding primitives for V
// Ported from https://github.com/google/flatbuffers/blob/master/go/encode.go
module flatbuffers

import math

// Offset types
pub type SOffsetT = i32 // Signed offset into arbitrary data
pub type UOffsetT = u32 // Unsigned offset into vector data
pub type VOffsetT = u16 // Offset in vtable

// Size constants
pub const size_u8 = 1
pub const size_u16 = 2
pub const size_u32 = 4
pub const size_u64 = 8
pub const size_i8 = 1
pub const size_i16 = 2
pub const size_i32 = 4
pub const size_i64 = 8
pub const size_f32 = 4
pub const size_f64 = 8
pub const size_bool = 1
pub const size_u_offset_t = 4
pub const size_s_offset_t = 4
pub const size_v_offset_t = 2

// Vtable metadata: [vtable_size: u16, object_size: u16]
pub const vtable_metadata_fields = 2

// --- Read functions (little-endian) ---

// get_bool decodes a little-endian bool from a byte slice.
@[inline]
pub fn get_bool(buf []u8) bool {
	return buf[0] != 0
}

// get_u8 decodes a little-endian u8 from a byte slice.
@[inline]
pub fn get_u8(buf []u8) u8 {
	return buf[0]
}

// get_u16 decodes a little-endian u16 from a byte slice.
@[inline]
pub fn get_u16(buf []u8) u16 {
	return u16(buf[0]) | (u16(buf[1]) << 8)
}

// get_u32 decodes a little-endian u32 from a byte slice.
@[inline]
pub fn get_u32(buf []u8) u32 {
	return u32(buf[0]) | (u32(buf[1]) << 8) | (u32(buf[2]) << 16) | (u32(buf[3]) << 24)
}

// get_u64 decodes a little-endian u64 from a byte slice.
@[inline]
pub fn get_u64(buf []u8) u64 {
	return u64(buf[0]) | (u64(buf[1]) << 8) | (u64(buf[2]) << 16) | (u64(buf[3]) << 24) | (u64(buf[4]) << 32) | (u64(buf[5]) << 40) | (u64(buf[6]) << 48) | (u64(buf[7]) << 56)
}

// get_i8 decodes a little-endian i8 from a byte slice.
@[inline]
pub fn get_i8(buf []u8) i8 {
	return i8(buf[0])
}

// get_i16 decodes a little-endian i16 from a byte slice.
@[inline]
pub fn get_i16(buf []u8) i16 {
	return i16(u16(buf[0]) | (u16(buf[1]) << 8))
}

// get_i32 decodes a little-endian i32 from a byte slice.
@[inline]
pub fn get_i32(buf []u8) i32 {
	return i32(u32(buf[0]) | (u32(buf[1]) << 8) | (u32(buf[2]) << 16) | (u32(buf[3]) << 24))
}

// get_i64 decodes a little-endian i64 from a byte slice.
@[inline]
pub fn get_i64(buf []u8) i64 {
	return i64(get_u64(buf))
}

// get_f32 decodes a little-endian f32 from a byte slice.
@[inline]
pub fn get_f32(buf []u8) f32 {
	return math.f32_from_bits(get_u32(buf))
}

// get_f64 decodes a little-endian f64 from a byte slice.
@[inline]
pub fn get_f64(buf []u8) f64 {
	return math.f64_from_bits(get_u64(buf))
}

// get_u_offset_t decodes a little-endian UOffsetT from a byte slice.
@[inline]
pub fn get_u_offset_t(buf []u8) UOffsetT {
	return UOffsetT(get_u32(buf))
}

// get_s_offset_t decodes a little-endian SOffsetT from a byte slice.
@[inline]
pub fn get_s_offset_t(buf []u8) SOffsetT {
	return SOffsetT(get_i32(buf))
}

// get_v_offset_t decodes a little-endian VOffsetT from a byte slice.
@[inline]
pub fn get_v_offset_t(buf []u8) VOffsetT {
	return VOffsetT(get_u16(buf))
}

// --- Write functions (little-endian) ---

// write_bool encodes a little-endian bool into a byte slice.
@[inline]
pub fn write_bool(mut buf []u8, b bool) {
	buf[0] = if b { u8(1) } else { u8(0) }
}

// write_u8 encodes a little-endian u8 into a byte slice.
@[inline]
pub fn write_u8(mut buf []u8, n u8) {
	buf[0] = n
}

// write_u16 encodes a little-endian u16 into a byte slice.
@[inline]
pub fn write_u16(mut buf []u8, n u16) {
	buf[0] = u8(n)
	buf[1] = u8(n >> 8)
}

// write_u32 encodes a little-endian u32 into a byte slice.
@[inline]
pub fn write_u32(mut buf []u8, n u32) {
	buf[0] = u8(n)
	buf[1] = u8(n >> 8)
	buf[2] = u8(n >> 16)
	buf[3] = u8(n >> 24)
}

// write_u64 encodes a little-endian u64 into a byte slice.
@[inline]
pub fn write_u64(mut buf []u8, n u64) {
	buf[0] = u8(n)
	buf[1] = u8(n >> 8)
	buf[2] = u8(n >> 16)
	buf[3] = u8(n >> 24)
	buf[4] = u8(n >> 32)
	buf[5] = u8(n >> 40)
	buf[6] = u8(n >> 48)
	buf[7] = u8(n >> 56)
}

// write_i8 encodes a little-endian i8 into a byte slice.
@[inline]
pub fn write_i8(mut buf []u8, n i8) {
	buf[0] = u8(n)
}

// write_i16 encodes a little-endian i16 into a byte slice.
@[inline]
pub fn write_i16(mut buf []u8, n i16) {
	buf[0] = u8(n)
	buf[1] = u8(n >> 8)
}

// write_i32 encodes a little-endian i32 into a byte slice.
@[inline]
pub fn write_i32(mut buf []u8, n i32) {
	buf[0] = u8(n)
	buf[1] = u8(n >> 8)
	buf[2] = u8(n >> 16)
	buf[3] = u8(n >> 24)
}

// write_i64 encodes a little-endian i64 into a byte slice.
@[inline]
pub fn write_i64(mut buf []u8, n i64) {
	write_u64(mut buf, u64(n))
}

// write_f32 encodes a little-endian f32 into a byte slice.
@[inline]
pub fn write_f32(mut buf []u8, n f32) {
	write_u32(mut buf, math.f32_bits(n))
}

// write_f64 encodes a little-endian f64 into a byte slice.
@[inline]
pub fn write_f64(mut buf []u8, n f64) {
	write_u64(mut buf, math.f64_bits(n))
}

// write_v_offset_t encodes a little-endian VOffsetT into a byte slice.
@[inline]
pub fn write_v_offset_t(mut buf []u8, n VOffsetT) {
	write_u16(mut buf, u16(n))
}

// write_s_offset_t encodes a little-endian SOffsetT into a byte slice.
@[inline]
pub fn write_s_offset_t(mut buf []u8, n SOffsetT) {
	write_i32(mut buf, i32(n))
}

// write_u_offset_t encodes a little-endian UOffsetT into a byte slice.
@[inline]
pub fn write_u_offset_t(mut buf []u8, n UOffsetT) {
	write_u32(mut buf, u32(n))
}
