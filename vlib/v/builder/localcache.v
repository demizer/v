// Copyright (c) 2026 Jesus Alvarez. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module builder

import json
import os
import hash

// ModuleInfo stores metadata about a cached module
struct ModuleInfo {
	hash     string   // Hash of source files + options + V version
	files    []string // Source files in this module
	deps     []string // Modules this depends on
	obj_file string   // Path to .o file
}

// LocalCacheManifest stores the complete cache state
struct LocalCacheManifest {
	vhash   string                // V compiler version hash
	vopts   string                // Build options string
	modules map[string]ModuleInfo // module_name -> info
}

// LocalCache manages local project-specific module caching
pub struct LocalCache {
mut:
	cache_dir string
	manifest  LocalCacheManifest
	vhash     string // V compiler version hash
	vopts     string // Build options string
}

// new_local_cache creates a new LocalCache instance
pub fn new_local_cache(cache_dir string, vhash string, build_opts []string) LocalCache {
	mut lc := LocalCache{
		cache_dir: cache_dir
		vhash:     vhash
		vopts:     build_opts.join('|')
	}
	lc.load_manifest()
	return lc
}

// compute_module_hash computes a hash for a module based on its files and build options
pub fn (lc &LocalCache) compute_module_hash(mod_name string, files []string) string {
	// Sort files for deterministic hash
	mut sorted := files.clone()
	sorted.sort()

	mut h := hash.sum64_string(lc.vhash, 0)
	h = hash.sum64_string(lc.vopts, h)
	h = hash.sum64_string(mod_name, h)

	for f in sorted {
		// Use relative path for portability
		rel_path := os.real_path(f).replace(os.getwd() + os.path_separator, '')
		h = hash.sum64_string(rel_path, h)

		// Include file content in hash
		content := os.read_file(f) or { '' }
		h = hash.sum64_string(content, h)
	}
	return h.hex()
}

// needs_rebuild returns true if a module needs to be rebuilt
pub fn (lc &LocalCache) needs_rebuild(mod_name string, current_hash string, dep_changed bool) bool {
	if dep_changed {
		return true // Dependency changed, must rebuild
	}
	info := lc.manifest.modules[mod_name] or { return true }
	if info.hash != current_hash {
		return true // Source changed
	}
	if !os.exists(info.obj_file) {
		return true // Object file missing
	}
	return false
}

// update_module updates the manifest entry for a module
pub fn (mut lc LocalCache) update_module(mod_name string, current_hash string, files []string, deps []string, obj_file string) {
	mut modules := lc.manifest.modules.clone()
	modules[mod_name] = ModuleInfo{
		hash:     current_hash
		files:    files
		deps:     deps
		obj_file: obj_file
	}
	lc.manifest = LocalCacheManifest{
		vhash:   lc.vhash
		vopts:   lc.vopts
		modules: modules
	}
}

// load_manifest loads the cache manifest from disk
fn (mut lc LocalCache) load_manifest() {
	manifest_path := os.join_path(lc.cache_dir, 'manifest.json')
	content := os.read_file(manifest_path) or { return }
	manifest := json.decode(LocalCacheManifest, content) or { return }

	// Check if vhash or vopts changed - if so, invalidate entire cache
	if manifest.vhash != lc.vhash || manifest.vopts != lc.vopts {
		return
	}
	lc.manifest = manifest
}

// save_manifest saves the cache manifest to disk
pub fn (lc &LocalCache) save_manifest() {
	manifest_path := os.join_path(lc.cache_dir, 'manifest.json')
	content := json.encode(lc.manifest)
	os.write_file(manifest_path, content) or {}
}

// get_obj_file returns the path to the object file for a module
pub fn (lc &LocalCache) get_obj_file(mod_name string) string {
	return os.join_path(lc.cache_dir, '${mod_name.replace('.', '_')}.o')
}

// get_c_file returns the path to the C file for a module
pub fn (lc &LocalCache) get_c_file(mod_name string) string {
	return os.join_path(lc.cache_dir, '${mod_name.replace('.', '_')}.c')
}

// is_cached returns true if a module has a valid cached object file
pub fn (lc &LocalCache) is_cached(mod_name string) bool {
	info := lc.manifest.modules[mod_name] or { return false }
	return os.exists(info.obj_file)
}

// get_cached_modules returns list of modules that have valid cache
pub fn (lc &LocalCache) get_cached_modules() []string {
	mut cached := []string{}
	for mod_name, info in lc.manifest.modules {
		if os.exists(info.obj_file) {
			cached << mod_name
		}
	}
	return cached
}

// clear removes all cached files and resets manifest
pub fn (mut lc LocalCache) clear() {
	os.rmdir_all(lc.cache_dir) or {}
	lc.manifest = LocalCacheManifest{
		vhash:   lc.vhash
		vopts:   lc.vopts
		modules: map[string]ModuleInfo{}
	}
}
