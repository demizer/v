// Copyright (c) 2024 Felipe Pena and Delyan Angelov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module main

import os
import v.highlight

// generate_html_report creates HTML coverage report in the specified directory.
fn (ctx &Context) generate_html_report() ! {
	files_dir := '${ctx.out_dir}/files'
	os.mkdir_all(files_dir) or {}

	// Calculate overall stats using AST-based coverage
	filters := ctx.get_filters()
	mut total_covered_count := 0
	mut total_lines_count := 0
	mut files_to_report := []string{}
	mut file_coverages := map[string]FileCoverage{}

	for file, _ in ctx.lines_per_file {
		// Apply test file filter
		if !ctx.show_test_files {
			if file.ends_with('_test.v') || file.ends_with('_test.c.v') {
				continue
			}
		}
		// Apply path filter
		if !filters.matches(file) {
			continue
		}
		files_to_report << file
		// Build AST-based file coverage
		fc := ctx.build_ast_file_coverage(file)
		file_coverages[file] = fc
		total_lines_count += fc.total_code
		total_covered_count += fc.covered_code
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
		fc := file_coverages[file]
		file_rows_list << ctx.render_file_row_with_coverage(file, fc)
		ctx.generate_file_html_with_coverage(file, fc)!
	}
	file_rows := file_rows_list.join('\n')

	html := $tmpl('templates/index.html')
	os.write_file('${ctx.out_dir}/index.html', html)!

	// Copy assets to output directory
	veasel_data := $embed_file('../../../examples/vweb_fullstack/src/assets/veasel.png')
	os.write_bytes('${ctx.out_dir}/veasel.png', veasel_data.to_bytes())!
	favicon_data := $embed_file('../vdoc/theme/favicons/favicon.ico')
	os.write_bytes('${ctx.out_dir}/favicon.ico', favicon_data.to_bytes())!
	common_css := $embed_file('templates/common.css')
	os.write_file('${ctx.out_dir}/common.css', common_css.to_string())!
	common_js := $embed_file('templates/common.js')
	os.write_file('${ctx.out_dir}/common.js', common_js.to_string())!

	ctx.verbose('HTML report generated in ${ctx.out_dir}')
}

fn (ctx &Context) render_file_row(file string) string {
	fc := ctx.build_ast_file_coverage(file)
	return ctx.render_file_row_with_coverage(file, fc)
}

fn (ctx &Context) render_file_row_with_coverage(file string, fc FileCoverage) string {
	rel_path := if ctx.use_absolute_paths {
		normalize_path(file)
	} else {
		file.all_after_first('${ctx.working_folder}/')
	}
	file_link := 'files/${rel_path}.html'
	covered := fc.covered_code.str()
	total := fc.total_code.str()
	pct := if fc.total_code > 0 {
		'${fc.coverage_percentage():.1}'
	} else {
		'0.0'
	}
	pct_class := get_pct_class(fc.covered_code, fc.total_code)
	row_class := if fc.total_code == 0 { 'no-coverage' } else { '' }

	return $tmpl('templates/file_row.html')
}

fn (ctx &Context) generate_file_html(file string) ! {
	fc := ctx.build_ast_file_coverage(file)
	ctx.generate_file_html_with_coverage(file, fc)!
}

fn (ctx &Context) generate_file_html_with_coverage(file string, fc FileCoverage) ! {
	rel_path := if ctx.use_absolute_paths {
		normalize_path(file)
	} else {
		file.all_after_first('${ctx.working_folder}/')
	}

	file_dir := '${ctx.out_dir}/files/${os.dir(rel_path)}'
	os.mkdir_all(file_dir) or {}

	pct := if fc.total_code > 0 {
		'${fc.coverage_percentage():.1}'
	} else {
		'0.0'
	}
	pct_class := get_pct_class(fc.covered_code, fc.total_code)
	covered := fc.covered_code.str()
	total := fc.total_code.str()

	depth := rel_path.count('/') + 1
	mut back_parts := []string{}
	for _ in 0 .. depth {
		back_parts << '../'
	}
	root_path := back_parts.join('').trim_right('/')
	back_path := root_path + '/index.html'
	favicon_path := root_path + '/favicon.ico'
	_ = favicon_path
	_ = root_path

	// Control hits column visibility (used in template)
	hits_display := if ctx.show_hits { '' } else { 'display: none;' }
	_ = hits_display

	// Read source file
	source_content := os.read_file(file) or { '' }
	source_file_lines := source_content.split_into_lines()

	mut source_lines_list := []string{}
	for i, src_line in source_file_lines {
		line_num := i + 1
		// Get coverage info from FileCoverage if available
		if fc.lines.len > line_num {
			lc := fc.lines[line_num]
			source_lines_list << render_source_line_with_coverage(line_num, src_line,
				lc)
		} else {
			// Fallback for lines beyond FileCoverage data
			source_lines_list << render_source_line_basic(line_num, src_line)
		}
	}
	source_lines := source_lines_list.join('\n')

	html := $tmpl('templates/file.html')
	os.write_file('${ctx.out_dir}/files/${rel_path}.html', html)!
}

fn render_source_line(line_num int, line string, hits u64, is_instrumented bool) string {
	code := highlight.v_html_simple(line)
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

fn render_source_line_with_coverage(line_num int, line string, lc LineCoverage) string {
	code := highlight.v_html_simple(line)

	// Determine line class based on coverage status
	line_class := match lc.status {
		.covered { 'covered' }
		.uncovered { 'uncovered' }
		.not_code { '' }
	}

	// Determine hits display
	hits_str := match lc.source {
		.instrumented {
			if lc.hits > 0 { '${lc.hits}x' } else { '0x' }
		}
		.inferred, .type_usage {
			// Show ~ for all inferred lines (covered or uncovered)
			if lc.status == .covered || lc.status == .uncovered { '~' } else { '' }
		}
		.not_available {
			''
		}
	}

	return $tmpl('templates/source_line.html')
}

fn render_source_line_basic(line_num int, line string) string {
	code := highlight.v_html_simple(line)
	line_class := ''
	hits_str := ''
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
