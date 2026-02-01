// Copyright (c) 2024 Felipe Pena and Delyan Angelov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module main

import os
import log
import flag
import json
import arrays
import encoding.csv

// program options, storage etc
struct Context {
mut:
	show_help          bool
	show_hotspots      bool
	show_percentages   bool
	show_test_files    bool
	show_hits          bool
	use_absolute_paths bool
	be_verbose         bool
	filters            []string
	working_folder     string
	out_dir            string
	view               bool

	targets            []string
	meta               map[string]MetaData // aggregated meta data, read from all .json files
	all_lines_per_file map[string][]int    // aggregated by load_meta
	coverage_sources   []string            // directories specified with -cov (for holistic view)
	all_source_files   []string            // all .v files in coverage_sources

	counters         map[string]u64         // incremented by process_target, based on each .csv file
	lines_per_file   map[string]map[int]int // incremented by process_target, based on each .csv file
	processed_points u64
}

const metadata_extension = '.json'
const vcounter_glob_pattern = 'vcounters_*.csv'

fn (mut ctx Context) load_meta(folder string) {
	for omfile in os.walk_ext(folder, metadata_extension) {
		mfile := omfile.replace('\\', '/')
		content := os.read_file(mfile) or { '' }
		meta := os.file_name(mfile.replace(metadata_extension, ''))
		data := json.decode(MetaData, content) or {
			log.error('${@METHOD} failed to load ${mfile}')
			continue
		}
		ctx.meta[meta] = data
		mut lines_per_file := ctx.all_lines_per_file[data.file]
		lines_per_file << data.points
		ctx.all_lines_per_file[data.file] = arrays.distinct(lines_per_file)
	}
}

fn (mut ctx Context) post_process_all_metas() {
	ctx.verbose('${@METHOD}')
	for _, m in ctx.meta {
		lines_per_file := ctx.all_lines_per_file[m.file]
		for line in lines_per_file {
			ctx.counters['${m.file}:${line}:'] = 0
		}
		// Extract -cov directories from build_options for holistic view
		ctx.extract_coverage_sources(m.build_options)
	}
	// Scan coverage sources for all .v files (holistic view)
	ctx.scan_coverage_sources()
}

// extract_coverage_sources parses build_options to find -cov directories
fn (mut ctx Context) extract_coverage_sources(build_options string) {
	parts := build_options.split(' ')
	mut i := 0
	for i < parts.len {
		if parts[i] in ['-cov', '-coverage'] && i + 1 < parts.len {
			src := parts[i + 1]
			if src !in ctx.coverage_sources {
				ctx.coverage_sources << src
				ctx.verbose('Found coverage source: ${src}')
			}
			i += 2
		} else {
			i++
		}
	}
}

// scan_coverage_sources finds all .v files in coverage source directories
fn (mut ctx Context) scan_coverage_sources() {
	for src_dir in ctx.coverage_sources {
		if !os.exists(src_dir) {
			ctx.verbose('Coverage source directory does not exist: ${src_dir}')
			continue
		}
		// Walk the directory and find all .v files
		for vfile in os.walk_ext(src_dir, '.v') {
			real_path := os.real_path(vfile).replace('\\', '/')
			if real_path !in ctx.all_source_files {
				ctx.all_source_files << real_path
				// Add to lines_per_file with empty map if not already present
				if real_path !in ctx.lines_per_file {
					ctx.lines_per_file[real_path] = map[int]int{}
				}
			}
		}
	}
	ctx.verbose('Total source files from -cov directories: ${ctx.all_source_files.len}')
}

fn (mut ctx Context) post_process_all_targets() {
	ctx.verbose('${@METHOD}')
	ctx.verbose('ctx.processed_points: ${ctx.processed_points}')
}

fn (ctx &Context) verbose(msg string) {
	if ctx.be_verbose {
		log.info(msg)
	}
}

fn (mut ctx Context) process_target(tfile string) ! {
	ctx.verbose('${@METHOD} ${tfile}')
	mut reader := csv.new_reader_from_file(tfile)!
	header := reader.read()!
	if header != ['meta', 'point', 'hits'] {
		return error('invalid header in .csv file')
	}
	for {
		row := reader.read() or { break }
		mut cline := CounterLine{
			meta:  row[0]
			point: row[1].int()
			hits:  row[2].u64()
		}
		m := ctx.meta[cline.meta] or {
			ctx.verbose('> skipping invalid meta: ${cline.meta} in file: ${cline.file}, csvfile: ${tfile}')
			continue
		}
		cline.file = m.file
		cline.line = m.points[cline.point] or {
			ctx.verbose('> skipping invalid point: ${cline.point} in file: ${cline.file}, meta: ${cline.meta}, csvfile: ${tfile}')
			continue
		}
		ctx.counters['${cline.file}:${cline.line}:'] += cline.hits
		mut lines := ctx.lines_per_file[cline.file].move()
		lines[cline.line]++
		ctx.lines_per_file[cline.file] = lines.move()
		// dump( ctx.lines_per_file[cline.meta][cline.point] )
		ctx.processed_points++
	}
}

// get_instrumented_lines returns a map of line number -> hit count for a specific file
fn (ctx &Context) get_instrumented_lines(file string) map[int]u64 {
	mut result := map[int]u64{}
	// Get all instrumented lines for this file
	lines := ctx.all_lines_per_file[file]
	for line in lines {
		key := '${file}:${line}:'
		hits := ctx.counters[key]
		result[line] = hits
	}
	return result
}

// build_ast_file_coverage builds a FileCoverage using AST analysis for accurate line counting
fn (ctx &Context) build_ast_file_coverage(file string) FileCoverage {
	// Get instrumented coverage data for this file
	instrumented := ctx.get_instrumented_lines(file)

	// Try to build AST-based coverage
	fc := build_file_coverage(file, instrumented) or {
		// If AST parsing fails, fall back to basic coverage
		ctx.verbose('Warning: could not parse ${file} for AST analysis: ${err}')
		return ctx.build_basic_file_coverage(file)
	}

	return FileCoverage{
		...fc
		path: file
	}
}

// build_basic_file_coverage builds a FileCoverage using only instrumented points (fallback)
fn (ctx &Context) build_basic_file_coverage(file string) FileCoverage {
	instrumented := ctx.get_instrumented_lines(file)
	total := instrumented.len
	mut covered := 0
	for _, hits in instrumented {
		if hits > 0 {
			covered++
		}
	}
	return FileCoverage{
		path:         file
		lines:        []
		total_code:   total
		covered_code: covered
	}
}

struct Filters {
	include []string
	exclude []string
}

fn (ctx &Context) get_filters() Filters {
	// Flatten filters: each -f can have comma-separated values
	// Patterns starting with ! are exclusions
	mut include := []string{}
	mut exclude := []string{}
	for f in ctx.filters {
		for part in f.split(',') {
			trimmed := part.trim_space()
			if trimmed != '' {
				if trimmed.starts_with('!') {
					exclude << trimmed[1..]
				} else {
					include << trimmed
				}
			}
		}
	}
	return Filters{include, exclude}
}

fn (f &Filters) matches(path string) bool {
	// If there are include filters, path must match at least one
	if f.include.len > 0 {
		if !f.include.any(path.contains(it)) {
			return false
		}
	}
	// If path matches any exclude filter, reject it
	if f.exclude.len > 0 {
		if f.exclude.any(path.contains(it)) {
			return false
		}
	}
	return true
}

fn (mut ctx Context) show_report() ! {
	filters := ctx.get_filters()
	if ctx.show_hotspots {
		for location, hits in ctx.counters {
			if !filters.matches(location) {
				continue
			}
			mut final_path := normalize_path(location)
			if !ctx.use_absolute_paths {
				final_path = location.all_after_first('${ctx.working_folder}/')
			}
			println('${hits:-8} ${final_path}')
		}
	}
	if ctx.show_percentages {
		for file, _ in ctx.lines_per_file {
			if !ctx.show_test_files {
				if file.ends_with('_test.v') || file.ends_with('_test.c.v') {
					continue
				}
			}
			if !filters.matches(file) {
				continue
			}
			// Use AST-based coverage for accurate line counting
			fc := ctx.build_ast_file_coverage(file)
			coverage_percent := fc.coverage_percentage()
			mut final_path := normalize_path(file)
			if !ctx.use_absolute_paths {
				final_path = file.all_after_first('${ctx.working_folder}/')
			}
			println('${final_path:-80s} | ${fc.covered_code:6} | ${fc.total_code:6} | ${coverage_percent:6.2f}%')
		}
	}
}

fn normalize_path(path string) string {
	return path.replace(os.path_separator, '/')
}

fn main() {
	log.use_stdout()
	mut ctx := Context{}
	ctx.working_folder = normalize_path(os.real_path(os.getwd()))
	mut fp := flag.new_flag_parser(os.args#[1..])
	fp.application('v cover')
	fp.version('0.4')
	fp.description('Analyze & make reports, based on cover files, produced by running programs and tests, compiled with `--cov-data-dir folder/`')
	fp.arguments_description('[folder1/ file2 ...]')
	fp.skip_executable()
	ctx.show_help = fp.bool('help', `h`, false, 'Show this help text.')
	ctx.be_verbose = fp.bool('verbose', `v`, false, 'Be more verbose while processing the coverages.')
	ctx.show_hotspots = fp.bool('hotspots', `H`, false, 'Show most frequently executed covered lines.')
	ctx.show_percentages = fp.bool('percentages', `P`, true, 'Show coverage percentage per file.')
	ctx.show_test_files = fp.bool('show_test_files', `S`, false, 'Show `_test.v` files as well (normally filtered).')
	ctx.show_hits = fp.bool('showhits', 0, false, 'Show hit counts for each line in HTML report.')
	ctx.use_absolute_paths = fp.bool('absolute', `A`, false, 'Use absolute paths for all files, no matter the current folder. By default, files inside the current folder, are shown with a relative path.')
	ctx.filters = fp.string_multi('filter', `f`, 'Filter source paths (repeatable, comma-separated, !pattern to exclude).')
	ctx.out_dir = fp.string('out', `o`, '', 'Generate an HTML report in the specified directory.')
	ctx.view = fp.bool('view', 0, false, 'Open the generated HTML report in the default browser.')
	// Compatibility flags (same as compiler flags for consistency)
	cov_data_dir := fp.string('cov-data-dir', 0, '', 'Coverage data directory (alias for positional argument).')
	cov_report := fp.string('cov-report', 0, '', 'Report format:path (e.g., html:report/). Sets output directory.')
	if ctx.show_help {
		println(fp.usage())
		exit(0)
	}
	mut targets := fp.finalize() or {
		log.error(fp.usage())
		exit(1)
	}
	// Handle --cov-data-dir flag (adds to targets)
	if cov_data_dir != '' {
		targets << cov_data_dir
	}
	// Handle --cov-report flag (parses format:path)
	if cov_report != '' {
		parts := cov_report.split_nth(':', 2)
		report_format := parts[0]
		if report_format == 'html' {
			if parts.len > 1 && parts[1] != '' {
				ctx.out_dir = parts[1]
			} else {
				ctx.out_dir = 'coverage_report'
			}
		} else if report_format == 'term' || report_format == 'terminal' {
			// Terminal output is default, no special handling needed
		} else {
			log.error('Unknown report format: ${report_format}. Use html:path or term.')
			exit(1)
		}
	}
	ctx.verbose('Targets: ${targets}')
	for t in targets {
		if !os.exists(t) {
			log.error('Skipping ${t}, since it does not exist')
			continue
		}
		if os.is_dir(t) {
			found_counter_files := os.walk_ext(t, '.csv')
			if found_counter_files.len == 0 {
				log.error('Skipping ${t}, since there are 0 ${vcounter_glob_pattern} files in it')
				continue
			}
			for counterfile in found_counter_files {
				ctx.targets << counterfile
				ctx.load_meta(t)
			}
		} else {
			ctx.targets << t
			ctx.load_meta(os.dir(t))
		}
	}
	ctx.post_process_all_metas()
	ctx.verbose('Final ctx.targets.len: ${ctx.targets.len}')
	ctx.verbose('Final ctx.meta.len: ${ctx.meta.len}')
	f := ctx.get_filters()
	ctx.verbose('Final filters - include: ${f.include}, exclude: ${f.exclude}')
	if ctx.targets.len == 0 {
		log.error('0 cover targets')
		exit(1)
	}
	for t in ctx.targets {
		ctx.process_target(t)!
	}
	ctx.post_process_all_targets()
	ctx.show_report()!
	if ctx.out_dir != '' {
		ctx.generate_html_report()!
		if ctx.view {
			os.open_uri('file://${os.real_path(ctx.out_dir)}/index.html') or {
				log.error('Failed to open browser: ${err}')
			}
		}
	}
}
