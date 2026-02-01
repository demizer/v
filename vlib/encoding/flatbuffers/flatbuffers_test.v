module flatbuffers

// Tests ported from FlatBuffers Go test suite
// https://github.com/google/flatbuffers/blob/master/tests/go_test.go

// Test basic encoding/decoding of scalars
fn test_encode_decode_scalars() {
	mut buf := []u8{len: 8}

	// Test u8
	write_u8(mut buf, 0x42)
	assert get_u8(buf) == 0x42

	// Test u16
	write_u16(mut buf, 0x1234)
	assert get_u16(buf) == 0x1234

	// Test u32
	write_u32(mut buf, 0x12345678)
	assert get_u32(buf) == 0x12345678

	// Test u64
	write_u64(mut buf, 0x123456789ABCDEF0)
	assert get_u64(buf) == 0x123456789ABCDEF0

	// Test i8
	write_i8(mut buf, -42)
	assert get_i8(buf) == -42

	// Test i16
	write_i16(mut buf, -1234)
	assert get_i16(buf) == -1234

	// Test i32
	write_i32(mut buf, -12345678)
	assert get_i32(buf) == -12345678

	// Test i64
	write_i64(mut buf, -123456789)
	assert get_i64(buf) == -123456789

	// Test bool
	write_bool(mut buf, true)
	assert get_bool(buf) == true
	write_bool(mut buf, false)
	assert get_bool(buf) == false

	// Test f32
	write_f32(mut buf, 3.14159)
	assert get_f32(buf) - 3.14159 < 0.00001

	// Test f64
	write_f64(mut buf, 3.141592653589793)
	assert get_f64(buf) == 3.141592653589793
}

// Test 1: numbers - verifies exact byte layout matches FlatBuffers spec
fn test_byte_layout_numbers() {
	mut b := new_builder(0)
	assert b.bytes[b.head()..] == []

	b.prepend_bool(true)
	assert b.bytes[b.head()..] == [u8(1)]

	b.prepend_i8(-127)
	assert b.bytes[b.head()..] == [u8(129), 1]

	b.prepend_u8(255)
	assert b.bytes[b.head()..] == [u8(255), 129, 1]

	b.prepend_i16(-32222)
	assert b.bytes[b.head()..] == [u8(0x22), 0x82, 0, 255, 129, 1] // first pad

	b.prepend_u16(0xFEEE)
	assert b.bytes[b.head()..] == [u8(0xEE), 0xFE, 0x22, 0x82, 0, 255, 129, 1] // no pad

	b.prepend_i32(-53687092)
	assert b.bytes[b.head()..] == [u8(204), 204, 204, 252, 0xEE, 0xFE, 0x22, 0x82, 0, 255, 129,
		1]

	b.prepend_u32(0x98765432)
	assert b.bytes[b.head()..] == [u8(0x32), 0x54, 0x76, 0x98, 204, 204, 204, 252, 0xEE, 0xFE,
		0x22, 0x82, 0, 255, 129, 1]
}

// Test 1b: 64-bit numbers
fn test_byte_layout_numbers_64bit() {
	mut b := new_builder(0)
	b.prepend_u64(0x1122334455667788)
	assert b.bytes[b.head()..] == [u8(0x88), 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11]
}

// Test 2: 1xbyte vector
fn test_byte_layout_1xbyte_vector() {
	mut b := new_builder(0)
	assert b.bytes[b.head()..] == []

	b.start_vector(size_u8, 1, 1)
	assert b.bytes[b.head()..] == [u8(0), 0, 0] // align to 4 bytes

	b.prepend_u8(1)
	assert b.bytes[b.head()..] == [u8(1), 0, 0, 0]

	b.end_vector(1)
	assert b.bytes[b.head()..] == [u8(1), 0, 0, 0, 1, 0, 0, 0] // length prefix
}

// Test 3: 2xbyte vector
fn test_byte_layout_2xbyte_vector() {
	mut b := new_builder(0)
	b.start_vector(size_u8, 2, 1)
	assert b.bytes[b.head()..] == [u8(0), 0] // align to 4 bytes

	b.prepend_u8(1)
	assert b.bytes[b.head()..] == [u8(1), 0, 0]

	b.prepend_u8(2)
	assert b.bytes[b.head()..] == [u8(2), 1, 0, 0]

	b.end_vector(2)
	assert b.bytes[b.head()..] == [u8(2), 0, 0, 0, 2, 1, 0, 0] // length prefix
}

// Test 4: 1xuint16 vector
fn test_byte_layout_1xuint16_vector() {
	mut b := new_builder(0)
	b.start_vector(size_u16, 1, 1)
	assert b.bytes[b.head()..] == [u8(0), 0] // align to 4 bytes

	b.prepend_u16(1)
	assert b.bytes[b.head()..] == [u8(1), 0, 0, 0]

	b.end_vector(1)
	assert b.bytes[b.head()..] == [u8(1), 0, 0, 0, 1, 0, 0, 0]
}

// Test 5: 2xuint16 vector
fn test_byte_layout_2xuint16_vector() {
	mut b := new_builder(0)
	b.start_vector(size_u16, 2, 1)
	assert b.bytes[b.head()..] == [] // already aligned

	b.prepend_u16(0xABCD)
	assert b.bytes[b.head()..] == [u8(0xCD), 0xAB]

	b.prepend_u16(0xDCBA)
	assert b.bytes[b.head()..] == [u8(0xBA), 0xDC, 0xCD, 0xAB]

	b.end_vector(2)
	assert b.bytes[b.head()..] == [u8(2), 0, 0, 0, 0xBA, 0xDC, 0xCD, 0xAB]
}

// Test 6: CreateString
fn test_byte_layout_create_string() {
	mut b := new_builder(0)
	b.create_string('foo')
	assert b.bytes[b.head()..] == [u8(3), 0, 0, 0, `f`, `o`, `o`, 0] // null-terminated, no pad

	b.create_string('moop')
	assert b.bytes[b.head()..] == [u8(4), 0, 0, 0, `m`, `o`, `o`, `p`, 0, 0, 0, 0, // null-terminated, 3-byte pad
	 	3, 0, 0, 0, `f`, `o`, `o`, 0]
}

// Test 6b: CreateString unicode
fn test_byte_layout_create_string_unicode() {
	mut b := new_builder(0)
	// Chinese characters from blog.golang.org/strings
	uni_str := '\u65e5\u672c\u8a9e'
	b.create_string(uni_str)
	assert b.bytes[b.head()..] == [u8(9), 0, 0, 0, 230, 151, 165, 230, 156, 172, 232, 170, 158,
		0, // null-terminated
		 		0, 0] // 2-byte pad
}

// Test 6c: CreateByteString
fn test_byte_layout_create_byte_string() {
	mut b := new_builder(0)
	b.create_byte_string('foo'.bytes())
	assert b.bytes[b.head()..] == [u8(3), 0, 0, 0, `f`, `o`, `o`, 0]

	b.create_byte_string('moop'.bytes())
	assert b.bytes[b.head()..] == [u8(4), 0, 0, 0, `m`, `o`, `o`, `p`, 0, 0, 0, 0, 3, 0, 0, 0,
		`f`, `o`, `o`, 0]
}

// Test 7: empty vtable
fn test_byte_layout_empty_vtable() {
	mut b := new_builder(0)
	b.start_object(0)
	assert b.bytes[b.head()..] == []

	b.end_object()
	assert b.bytes[b.head()..] == [u8(4), 0, 4, 0, 4, 0, 0, 0]
}

// Test 8: vtable with one true bool
fn test_byte_layout_vtable_with_bool() {
	mut b := new_builder(0)
	assert b.bytes[b.head()..] == []

	b.start_object(1)
	assert b.bytes[b.head()..] == []

	b.prepend_bool_slot(0, true, false)
	b.end_object()
	assert b.bytes[b.head()..] == [
		u8(6),
		0, // vtable bytes
		8,
		0, // length of object including vtable offset
		7,
		0, // start of bool value
		6,
		0,
		0,
		0, // offset for start of vtable (int32)
		0,
		0,
		0, // padded to 4 bytes
		1, // bool value
	]
}

// Test 9: vtable with one default bool (should be omitted)
fn test_byte_layout_vtable_default_bool() {
	mut b := new_builder(0)
	b.start_object(1)
	b.prepend_bool_slot(0, false, false) // value == default, should be omitted
	b.end_object()
	assert b.bytes[b.head()..] == [u8(4), 0, 4, 0, 4, 0, 0, 0] // same as empty vtable
}

// Test 10: vtable with one int16
fn test_byte_layout_vtable_with_int16() {
	mut b := new_builder(0)
	b.start_object(1)
	b.prepend_i16_slot(0, 0x789A, 0)
	b.end_object()
	assert b.bytes[b.head()..] == [
		u8(6),
		0, // vtable bytes
		8,
		0, // length of object including vtable offset
		6,
		0, // offset to value
		6,
		0,
		0,
		0, // vtable offset
		0,
		0, // padding
		0x9A,
		0x78, // value (little-endian)
	]
}

// Test: vtable deduplication (ported from Go test)
fn test_vtable_deduplication() {
	mut b := new_builder(0)

	// Create three objects with identical vtable schema: 4 fields (byte, byte, byte, i16)
	b.start_object(4)
	b.prepend_u8_slot(0, 0, 0)
	b.prepend_u8_slot(1, 11, 0)
	b.prepend_u8_slot(2, 22, 0)
	b.prepend_i16_slot(3, 33, 0)
	b.end_object()

	b.start_object(4)
	b.prepend_u8_slot(0, 0, 0)
	b.prepend_u8_slot(1, 44, 0)
	b.prepend_u8_slot(2, 55, 0)
	b.prepend_i16_slot(3, 66, 0)
	b.end_object()

	b.start_object(4)
	b.prepend_u8_slot(0, 0, 0)
	b.prepend_u8_slot(1, 77, 0)
	b.prepend_u8_slot(2, 88, 0)
	b.prepend_i16_slot(3, 99, 0)
	b.end_object()

	got := b.bytes[b.head()..]

	// Expected bytes from Go test - vtable is written only once, then reused
	want := [
		u8(240),
		255,
		255,
		255, // == -12. offset to dedupped vtable.
		99,
		0,
		88,
		77,
		248,
		255,
		255,
		255, // == -8. offset to dedupped vtable.
		66,
		0,
		55,
		44,
		12,
		0, // vtable bytes
		8,
		0, // object size
		0,
		0, // slot 0 (default, not written)
		7,
		0, // slot 1
		6,
		0, // slot 2
		4,
		0, // slot 3
		12,
		0,
		0,
		0, // vtable offset
		33,
		0, // value 3
		22, // value 2
		11, // value 1
	]

	assert got == want, 'vtable deduplication failed:\nwant: ${want}\ngot:  ${got}'
}

// Test shared strings
fn test_shared_strings() {
	mut b := new_builder(128)

	s1 := b.create_shared_string('hello')
	s2 := b.create_shared_string('hello')
	s3 := b.create_shared_string('world')

	// Same string should return same offset
	assert s1 == s2
	// Different string should have different offset
	assert s1 != s3
}

// Test builder reset
fn test_builder_reset() {
	mut b := new_builder(64)

	// Build something
	str_offset := b.create_string('test')
	b.start_object(1)
	b.prepend_u_offset_t_slot(0, str_offset, 0)
	root := b.end_object()
	b.finish(root)

	first_data := b.finished_bytes().clone()

	// Reset and build again
	b.reset()

	str_offset2 := b.create_string('test')
	b.start_object(1)
	b.prepend_u_offset_t_slot(0, str_offset2, 0)
	root2 := b.end_object()
	b.finish(root2)

	second_data := b.finished_bytes()

	// Should produce same output
	assert first_data == second_data
}

// Test reading back built data
fn test_read_built_data() {
	mut b := new_builder(64)

	// Create a string
	str_offset := b.create_string('hello world')

	// Start an object with 3 fields
	b.start_object(3)
	b.prepend_u32_slot(0, 12345, 0)
	b.prepend_i16_slot(1, -999, 0)
	b.prepend_u_offset_t_slot(2, str_offset, 0)
	root := b.end_object()

	b.finish(root)

	// Read it back
	data := b.finished_bytes()
	t := get_root_as(data)

	// Field 0 (u32) at vtable offset 4
	off0 := t.offset(4)
	assert off0 != 0
	assert t.get_u32(t.pos + u32(off0)) == 12345

	// Field 1 (i16) at vtable offset 6
	off1 := t.offset(6)
	assert off1 != 0
	assert t.get_i16(t.pos + u32(off1)) == -999

	// Field 2 (string) at vtable offset 8
	off2 := t.offset(8)
	assert off2 != 0
	s := t.string_(t.pos + u32(off2))
	assert s == 'hello world'
}

// Test byte vector round-trip
fn test_byte_vector_roundtrip() {
	mut b := new_builder(64)

	original := [u8(1), 2, 3, 4, 5, 100, 200, 255]
	vec_offset := b.create_byte_vector(original)

	b.start_object(1)
	b.prepend_u_offset_t_slot(0, vec_offset, 0)
	root := b.end_object()

	b.finish(root)

	// Read back
	t := get_root_as(b.finished_bytes())
	off := t.offset(4)
	assert off != 0

	vec := t.byte_vector(t.pos + u32(off))
	assert vec == original
}

// Test vector length
fn test_vector_length() {
	mut b := new_builder(64)

	// Create byte vector with 10 elements
	data := []u8{len: 10, init: u8(index)}
	vec_offset := b.create_byte_vector(data)

	b.start_object(1)
	b.prepend_u_offset_t_slot(0, vec_offset, 0)
	root := b.end_object()
	b.finish(root)

	t := get_root_as(b.finished_bytes())
	off := t.offset(4)
	assert off != 0

	len := t.vector_len(u32(off))
	assert len == 10
}
