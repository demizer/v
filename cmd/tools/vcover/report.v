// Copyright (c) 2024 Felipe Pena and Delyan Angelov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module main

import os

// generate_html_report creates HTML coverage report in the specified directory.
fn (ctx &Context) generate_html_report() ! {
	files_dir := '${ctx.out_dir}/files'
	os.mkdir_all(files_dir) or {}

	// Calculate overall stats
	filters := ctx.filter.split(',').filter(it != '')
	mut total_covered_count := 0
	mut total_lines_count := 0
	mut files_to_report := []string{}

	for file, _ in ctx.lines_per_file {
		// Apply test file filter
		if !ctx.show_test_files {
			if file.ends_with('_test.v') || file.ends_with('_test.c.v') {
				continue
			}
		}
		// Apply path filter
		if filters.len > 0 {
			if !filters.any(file.contains(it)) {
				continue
			}
		}
		files_to_report << file
		file_all_lines := ctx.all_lines_per_file[file]
		total_lines_count += file_all_lines.len
		for line in file_all_lines {
			if ctx.counters['${file}:${line}:'] > 0 {
				total_covered_count++
			}
		}
	}

	files_to_report.sort()

	overall_pct := if total_lines_count > 0 {
		'${f64(total_covered_count) / f64(total_lines_count) * 100.0:.2}'
	} else {
		'0.00'
	}

	pct_class := get_pct_class(total_covered_count, total_lines_count)
	covered_lines := total_covered_count.str()
	total_lines := total_lines_count.str()
	file_count := files_to_report.len.str()

	mut file_rows_list := []string{}
	for file in files_to_report {
		file_rows_list << ctx.render_file_row(file)
		ctx.generate_file_html(file)!
	}
	file_rows := file_rows_list.join('\n')

	html := $tmpl('templates/index.html')
	os.write_file('${ctx.out_dir}/index.html', html)!
	ctx.verbose('HTML report generated in ${ctx.out_dir}')
}

fn (ctx &Context) render_file_row(file string) string {
	file_all_lines := ctx.all_lines_per_file[file]
	total_count := file_all_lines.len
	mut covered_count := 0
	for line in file_all_lines {
		if ctx.counters['${file}:${line}:'] > 0 {
			covered_count++
		}
	}

	rel_path := if ctx.use_absolute_paths {
		normalize_path(file)
	} else {
		file.all_after_first('${ctx.working_folder}/')
	}
	file_link := 'files/${rel_path}.html'
	covered := covered_count.str()
	total := total_count.str()
	pct := if total_count > 0 {
		'${f64(covered_count) / f64(total_count) * 100.0:.1}'
	} else {
		'0.0'
	}
	pct_class := get_pct_class(covered_count, total_count)
	row_class := if total_count == 0 { 'no-coverage' } else { '' }

	return $tmpl('templates/file_row.html')
}

fn (ctx &Context) generate_file_html(file string) ! {
	rel_path := if ctx.use_absolute_paths {
		normalize_path(file)
	} else {
		file.all_after_first('${ctx.working_folder}/')
	}

	file_dir := '${ctx.out_dir}/files/${os.dir(rel_path)}'
	os.mkdir_all(file_dir) or {}

	file_all_lines := ctx.all_lines_per_file[file]
	total_count := file_all_lines.len
	mut covered_count := 0
	for line in file_all_lines {
		if ctx.counters['${file}:${line}:'] > 0 {
			covered_count++
		}
	}

	pct := if total_count > 0 {
		'${f64(covered_count) / f64(total_count) * 100.0:.1}'
	} else {
		'0.0'
	}
	pct_class := get_pct_class(covered_count, total_count)
	covered := covered_count.str()
	total := total_count.str()

	depth := rel_path.count('/') + 1
	mut back_parts := []string{}
	for _ in 0 .. depth {
		back_parts << '../'
	}
	back_path := back_parts.join('') + 'index.html'

	// Read source file
	source_content := os.read_file(file) or { '' }
	source_file_lines := source_content.split_into_lines()

	// Build a set of instrumented lines for quick lookup
	mut instrumented_lines := map[int]bool{}
	for line in file_all_lines {
		instrumented_lines[line] = true
	}

	mut source_lines_list := []string{}
	for i, src_line in source_file_lines {
		line_num := i + 1
		hits := ctx.counters['${file}:${line_num}:']
		is_instrumented := instrumented_lines[line_num]
		source_lines_list << render_source_line(line_num, src_line, hits, is_instrumented)
	}
	source_lines := source_lines_list.join('\n')

	html := $tmpl('templates/file.html')
	os.write_file('${ctx.out_dir}/files/${rel_path}.html', html)!
}

fn render_source_line(line_num int, line string, hits u64, is_instrumented bool) string {
	code := html_escape(line)
	line_class := if is_instrumented {
		if hits > 0 { 'covered' } else { 'uncovered' }
	} else {
		''
	}
	hits_str := if is_instrumented {
		if hits > 0 { '${hits}x' } else { '0x' }
	} else {
		''
	}

	return $tmpl('templates/source_line.html')
}

fn get_pct_class(covered int, total int) string {
	if total == 0 {
		return 'pct-low'
	}
	pct := f64(covered) / f64(total) * 100.0
	return if pct >= 80.0 {
		'pct-high'
	} else if pct >= 50.0 {
		'pct-med'
	} else {
		'pct-low'
	}
}

fn html_escape(s string) string {
	return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
}
