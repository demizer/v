module builder

import os
import v.ast
import v.token

fn testsuite_begin() {
	// Clean up any existing test cache
	os.rmdir_all('/tmp/vcache_test') or {}
}

fn testsuite_end() {
	// Clean up test cache
	os.rmdir_all('/tmp/vcache_test') or {}
}

fn test_new_parse_cache() {
	pc := new_parse_cache('/tmp/vcache_test', 'test_v_hash')
	assert pc.cache_dir == '/tmp/vcache_test/parse'
	assert pc.vhash == 'test_v_hash'
	assert pc.enabled == true
	assert os.exists('/tmp/vcache_test/parse')
}

fn test_get_cache_path() {
	pc := new_parse_cache('/tmp/vcache_test', 'test_v_hash')
	// The cache path should be based on the source file path
	cache_path := pc.get_cache_path('/some/path/to/file.v')
	assert cache_path.ends_with('.cache')
	assert cache_path.starts_with('/tmp/vcache_test/parse/')
}

fn test_is_valid_empty_cache() {
	pc := new_parse_cache('/tmp/vcache_test', 'test_v_hash')
	// Empty cache should return false
	assert pc.is_valid('/nonexistent/file.v', 12345) == false
}

fn test_save_and_load() {
	mut pc := new_parse_cache('/tmp/vcache_test', 'test_v_hash')

	// Create a minimal file
	file := &ast.File{
		nr_lines:  10
		nr_bytes:  100
		nr_tokens: 50
		is_test:   false
		mod:       ast.Module{
			name:       'test'
			short_name: 'test'
		}
	}

	source_path := '/tmp/vcache_test/test_source.v'
	content := 'module test\nfn main() {}'
	mtime := i64(1234567890)

	// Save to cache
	pc.save(source_path, content, mtime, file)

	// Check it's valid
	assert pc.is_valid(source_path, mtime) == true

	// Load from cache
	loaded := pc.load(source_path) or {
		assert false, 'failed to load cached file'
		return
	}

	assert loaded.nr_lines == file.nr_lines
	assert loaded.nr_bytes == file.nr_bytes
	assert loaded.mod.name == file.mod.name
}

fn test_is_valid_mtime_changed() {
	mut pc := new_parse_cache('/tmp/vcache_test', 'test_v_hash')

	file := &ast.File{
		nr_lines: 5
		mod:      ast.Module{
			name:       'mtime_test'
			short_name: 'mtime_test'
		}
	}

	source_path := '/tmp/vcache_test/mtime_test.v'
	content := 'module mtime_test'
	mtime := i64(1000)

	pc.save(source_path, content, mtime, file)
	assert pc.is_valid(source_path, mtime) == true

	// Different mtime should return false (unless content hash matches)
	assert pc.is_valid(source_path, mtime + 1) == false
}

fn test_is_valid_with_hash_same_content() {
	mut pc := new_parse_cache('/tmp/vcache_test', 'test_v_hash')

	file := &ast.File{
		nr_lines: 5
		mod:      ast.Module{
			name:       'hash_test'
			short_name: 'hash_test'
		}
	}

	source_path := '/tmp/vcache_test/hash_test.v'
	content := 'module hash_test'
	mtime := i64(2000)

	pc.save(source_path, content, mtime, file)

	// Same content but different mtime - should still be valid when checking hash
	assert pc.is_valid_with_hash(source_path, mtime + 100, content) == true
}

fn test_is_valid_with_hash_different_content() {
	mut pc := new_parse_cache('/tmp/vcache_test', 'test_v_hash')

	file := &ast.File{
		nr_lines: 5
		mod:      ast.Module{
			name:       'hash_test2'
			short_name: 'hash_test2'
		}
	}

	source_path := '/tmp/vcache_test/hash_test2.v'
	content := 'module hash_test2'
	mtime := i64(3000)

	pc.save(source_path, content, mtime, file)

	// Different content - should be invalid
	assert pc.is_valid_with_hash(source_path, mtime + 100, 'module changed') == false
}

fn test_manifest_persistence() {
	source_path := '/tmp/vcache_test/persist_test.v'
	content := 'module persist'
	mtime := i64(4000)

	// Create and save
	{
		mut pc := new_parse_cache('/tmp/vcache_test', 'persist_hash')
		file := &ast.File{
			nr_lines: 1
			mod:      ast.Module{
				name:       'persist'
				short_name: 'persist'
			}
		}
		pc.save(source_path, content, mtime, file)
		pc.save_manifest()
	}

	// Load fresh and verify
	{
		pc := new_parse_cache('/tmp/vcache_test', 'persist_hash')
		assert pc.is_valid(source_path, mtime) == true
	}
}

fn test_manifest_invalidation_on_vhash_change() {
	source_path := '/tmp/vcache_test/vhash_test.v'
	content := 'module vhash'
	mtime := i64(5000)

	// Create with one vhash
	{
		mut pc := new_parse_cache('/tmp/vcache_test', 'vhash_1')
		file := &ast.File{
			nr_lines: 1
			mod:      ast.Module{
				name:       'vhash'
				short_name: 'vhash'
			}
		}
		pc.save(source_path, content, mtime, file)
		pc.save_manifest()
	}

	// Load with different vhash - should invalidate cache
	{
		pc := new_parse_cache('/tmp/vcache_test', 'vhash_2')
		assert pc.is_valid(source_path, mtime) == false
	}
}

fn test_stats() {
	mut pc := new_parse_cache('/tmp/vcache_test', 'stats_hash')

	file := &ast.File{
		nr_lines: 1
		mod:      ast.Module{
			name:       'stats'
			short_name: 'stats'
		}
	}

	source_path := '/tmp/vcache_test/stats_test.v'
	content := 'module stats'
	mtime := i64(6000)

	pc.save(source_path, content, mtime, file)

	// Load should increment hits
	_ := pc.load(source_path) or { &ast.File{} }
	assert pc.stats.hits == 1
	assert pc.stats.misses == 0

	// Load non-existent should increment misses
	_ := pc.load('/nonexistent.v') or { &ast.File{} }
	assert pc.stats.hits == 1
	assert pc.stats.misses == 1
}

fn test_clear() {
	mut pc := new_parse_cache('/tmp/vcache_test', 'clear_hash')

	file := &ast.File{
		nr_lines: 1
		mod:      ast.Module{
			name:       'clear'
			short_name: 'clear'
		}
	}

	source_path := '/tmp/vcache_test/clear_test.v'
	content := 'module clear'
	mtime := i64(7000)

	pc.save(source_path, content, mtime, file)
	assert pc.is_valid(source_path, mtime) == true

	pc.clear()
	assert pc.is_valid(source_path, mtime) == false
	assert pc.stats.hits == 0
	assert pc.stats.misses == 0
}
