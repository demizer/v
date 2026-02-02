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
pub fn new_parse_cache(cache_dir string, vhash string) ParseCache {
	parse_dir := os.join_path(cache_dir, 'parse')
	mut pc := ParseCache{
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

// load attempts to load a cached AST file
pub fn (mut pc ParseCache) load(source_path string) ?&ast.File {
	entry := pc.manifest.files[source_path] or {
		pc.stats.misses++
		return none
	}

	// Read cached data
	data := os.read_bytes(entry.cache_file) or {
		pc.stats.misses++
		return none
	}

	// Deserialize
	file := ast.deserialize_file(data) or {
		pc.stats.misses++
		return none
	}

	pc.stats.hits++
	return file
}

// save saves a parsed AST file to cache
pub fn (mut pc ParseCache) save(source_path string, content string, file_mtime i64, file &ast.File) {
	cache_path := pc.get_cache_path(source_path)
	content_hash := compute_file_hash(content)

	// Serialize AST
	data := ast.serialize_file(file)

	// Write cache file
	os.write_file_array(cache_path, data) or { return }

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
