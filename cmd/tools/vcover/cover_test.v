// vtest retry: 2
import os

const vexe = @VEXE
const vroot = os.dir(vexe)
const tfolder = os.join_path(os.vtmp_dir(), 'cover_test')

const t1 = np(os.join_path(tfolder, 't1'))
const t2 = np(os.join_path(tfolder, 't2'))
const t3 = np(os.join_path(tfolder, 't3'))
const t_match = np(os.join_path(tfolder, 't_match'))
const t_if = np(os.join_path(tfolder, 't_if'))

fn testsuite_begin() {
	os.setenv('VCOLORS', 'never', true)
	os.chdir(vroot)!
	os.rmdir_all(tfolder) or {}
	os.mkdir(tfolder) or {}
}

fn testsuite_end() {
	os.rmdir_all(tfolder) or {}
}

fn test_help() {
	res := execute('${os.quoted_path(vexe)} cover -h')
	assert res.exit_code == 0
	assert res.output.contains('Usage: v cover')
	assert res.output.contains('Description: Analyze & make reports')
	assert res.output.contains('Options:')
	assert res.output.contains('-h, --help                Show this help text.')
	assert res.output.contains('-v, --verbose             Be more verbose while processing the coverages.')
	assert res.output.contains('-H, --hotspots            Show most frequently executed covered lines.')
	assert res.output.contains('-P, --percentages         Show coverage percentage per file.')
	assert res.output.contains('-S, --show_test_files     Show `_test.v` files as well (normally filtered).')
	assert res.output.contains('-A, --absolute            Use absolute paths for all files')
	assert res.output.contains('-o, --out <string>        Generate an HTML report')
	assert res.output.contains('--view                    Open the generated HTML report in the default browser.')
}

fn np(path string) string {
	return path.replace('\\', '/')
}

fn test_simple() {
	assert !os.exists(t1), t1
	assert !os.exists(t2), t2
	assert !os.exists(t3), t3

	r1 := execute('${os.quoted_path(vexe)} -no-skip-unused -cov-data-dir ${os.quoted_path(t1)} cmd/tools/vcover/testdata/simple/t1_test.v')
	assert r1.exit_code == 0, r1.str()
	assert r1.output.trim_space() == '10', r1.str()
	assert os.exists(t1), t1
	cmd := '${os.quoted_path(vexe)} cover ${os.quoted_path(t1)} --filter vcover/testdata/simple/'
	filter1 := execute(cmd)
	assert filter1.exit_code == 0, filter1.output
	assert filter1.output.contains('cmd/tools/vcover/testdata/simple/simple.v'), filter1.output
	// AST-based counting with closing braces: 10 covered / 19 total code lines = 52.63%
	assert filter1.output.trim_space().ends_with('|     10 |     19 |  52.63%'), filter1.output
	hfilter1 := execute('${os.quoted_path(vexe)} cover ${os.quoted_path(t1)} --filter vcover/testdata/simple/ -H -P false')
	assert hfilter1.exit_code == 0, hfilter1.output
	assert !hfilter1.output.contains('%'), hfilter1.output
	houtput1 := hfilter1.output.trim_space().split_into_lines()
	zeros1 := houtput1.filter(it.starts_with('0 '))
	nzeros1 := houtput1.filter(!it.starts_with('0 '))
	assert zeros1.len > 0
	assert zeros1.any(it.contains('simple.v:12')), zeros1.str()
	assert zeros1.any(it.contains('simple.v:14')), zeros1.str()
	assert zeros1.any(it.contains('simple.v:17')), zeros1.str()
	assert zeros1.any(it.contains('simple.v:18')), zeros1.str()
	assert zeros1.any(it.contains('simple.v:19')), zeros1.str()
	assert nzeros1.len > 0
	assert nzeros1.any(it.contains('simple.v:4')), nzeros1.str()
	assert nzeros1.any(it.contains('simple.v:6')), nzeros1.str()
	assert nzeros1.any(it.contains('simple.v:8')), nzeros1.str()
	assert nzeros1.any(it.contains('simple.v:25')), nzeros1.str()

	r2 := execute('${os.quoted_path(vexe)} -no-skip-unused -cov-data-dir ${os.quoted_path(t2)} cmd/tools/vcover/testdata/simple/t2_test.v')
	assert r2.exit_code == 0, r2.str()
	assert r2.output.trim_space() == '24', r2.str()
	assert os.exists(t2), t2
	filter2 := execute('${os.quoted_path(vexe)} cover ${os.quoted_path(t2)} --filter vcover/testdata/simple')
	assert filter2.exit_code == 0, filter2.output
	assert filter2.output.contains('cmd/tools/vcover/testdata/simple/simple.v')
	// AST-based counting with closing braces: mul() covered, 12 covered / 19 total = 63.16%
	assert filter2.output.trim_space().ends_with('|     12 |     19 |  63.16%'), filter2.output
	hfilter2 := execute('${os.quoted_path(vexe)} cover ${os.quoted_path(t2)} --filter testdata/simple -H -P false')
	assert hfilter2.exit_code == 0, hfilter2.output
	assert !hfilter2.output.contains('%'), hfilter2.output
	houtput2 := hfilter2.output.trim_space().split_into_lines()
	zeros2 := houtput2.filter(it.starts_with('0 '))
	nzeros2 := houtput2.filter(!it.starts_with('0 '))
	assert zeros2.len > 0
	assert zeros2.any(it.contains('simple.v:4')), zeros2.str()
	assert zeros2.any(it.contains('simple.v:6')), zeros2.str()
	assert zeros2.any(it.contains('simple.v:8')), zeros2.str()
	assert nzeros2.len > 0
	assert nzeros2.any(it.contains('simple.v:17')), nzeros2.str()
	assert nzeros2.any(it.contains('simple.v:18')), nzeros2.str()
	assert nzeros2.any(it.contains('simple.v:19')), nzeros2.str()
	assert nzeros2.any(it.contains('simple.v:25')), nzeros2.str()

	// Run both tests. The coverage should be combined and == 100%
	r3 := execute('${os.quoted_path(vexe)} -no-skip-unused -cov-data-dir ${os.quoted_path(t3)} test cmd/tools/vcover/testdata/simple/')
	assert r3.exit_code == 0, r3.str()
	assert r3.output.trim_space().contains('Summary for all V _test.v files: '), r3.str()
	assert os.exists(t3), t3
	filter3 := execute('${os.quoted_path(vexe)} cover ${os.quoted_path(t3)} --filter simple/')
	assert filter3.exit_code == 0, filter3.str()
	assert filter3.output.contains('cmd/tools/vcover/testdata/simple/simple.v'), filter3.str()
	// AST-based counting with closing braces: all 19 code lines covered = 100%
	assert filter3.output.trim_space().match_glob('*cmd/tools/vcover/testdata/simple/simple.v *|     19 |     19 | 100.00%'), filter3.str()
}

fn test_html_report() {
	// Use t3 data (combined tests = 100% coverage)
	html_dir := np(os.join_path(tfolder, 'html_report'))
	os.rmdir_all(html_dir) or {}

	// Ensure t3 coverage data exists
	if !os.exists(t3) {
		r := execute('${os.quoted_path(vexe)} -no-skip-unused -cov-data-dir ${os.quoted_path(t3)} test cmd/tools/vcover/testdata/simple/')
		assert r.exit_code == 0, r.str()
	}

	// Generate HTML report
	r := execute('${os.quoted_path(vexe)} cover ${os.quoted_path(t3)} --out ${os.quoted_path(html_dir)} --filter simple/')
	assert r.exit_code == 0, r.output

	// Verify output files exist
	assert os.exists(os.join_path(html_dir, 'index.html')), 'index.html should exist'
	assert os.exists(os.join_path(html_dir, 'files')), 'files directory should exist'

	// Check index.html content
	index := os.read_file(os.join_path(html_dir, 'index.html')) or { '' }
	assert index.contains('V Coverage Report'), 'should contain title'
	assert index.contains('simple.v'), 'should contain file name'
	assert index.contains('100'), 'should show 100% coverage'
	assert index.contains('pct-high'), 'should have green color class'
	// AST-based counting with closing braces: 19 total code lines
	assert index.contains('19 / 19'), 'should show 19/19 lines'

	// Check individual file report exists
	file_html_path := os.join_path(html_dir, 'files', 'cmd', 'tools', 'vcover', 'testdata',
		'simple', 'simple.v.html')
	assert os.exists(file_html_path), 'file HTML should exist at: ${file_html_path}'

	// Check file HTML content
	file_html := os.read_file(file_html_path) or { '' }
	assert file_html.contains('covered'), 'should have covered lines'
	// Source code is syntax highlighted, so function names are in spans
	assert file_html.contains('tok-function">sum'), 'should contain source code with sum function'
	assert file_html.contains('index.html'), 'should have back link'
}

fn test_html_report_partial_coverage() {
	// Use t1 data (partial coverage = 44.44%)
	html_dir := np(os.join_path(tfolder, 'html_partial'))
	os.rmdir_all(html_dir) or {}

	// Ensure t1 coverage data exists
	if !os.exists(t1) {
		r := execute('${os.quoted_path(vexe)} -no-skip-unused -cov-data-dir ${os.quoted_path(t1)} cmd/tools/vcover/testdata/simple/t1_test.v')
		assert r.exit_code == 0, r.str()
	}

	// Generate HTML report
	r := execute('${os.quoted_path(vexe)} cover ${os.quoted_path(t1)} --out ${os.quoted_path(html_dir)} --filter simple/')
	assert r.exit_code == 0, r.output

	// Check index.html shows partial coverage
	index := os.read_file(os.join_path(html_dir, 'index.html')) or { '' }
	// AST-based counting with closing braces: 10 covered / 19 total = 52.63%
	assert index.contains('52'), 'should show ~52% coverage'
	assert index.contains('pct-med'), 'should have medium color class for 50-80%'
	assert index.contains('10 / 19'), 'should show 10/19 lines'

	// Check file HTML has both covered and uncovered lines
	file_html_path := os.join_path(html_dir, 'files', 'cmd', 'tools', 'vcover', 'testdata',
		'simple', 'simple.v.html')
	file_html := os.read_file(file_html_path) or { '' }
	assert file_html.contains('covered'), 'should have covered lines'
	assert file_html.contains('uncovered'), 'should have uncovered lines'
}

fn test_match_arm_closing_braces_and_comments() {
	// Test that match arm closing braces and comments inherit coverage
	html_dir := np(os.join_path(tfolder, 'html_match'))
	os.rmdir_all(html_dir) or {}

	// Run test to generate coverage data
	r := execute('${os.quoted_path(vexe)} -no-skip-unused -cov-data-dir ${os.quoted_path(t_match)} test cmd/tools/vcover/testdata/matchtest/')
	assert r.exit_code == 0, r.str()
	assert os.exists(t_match), t_match

	// Generate HTML report
	r2 := execute('${os.quoted_path(vexe)} cover ${os.quoted_path(t_match)} --out ${os.quoted_path(html_dir)} --filter matchtest/')
	assert r2.exit_code == 0, r2.output

	// Check file HTML for covered and uncovered lines
	file_html_path := os.join_path(html_dir, 'files', 'cmd', 'tools', 'vcover', 'testdata',
		'matchtest', 'match_func.v.html')
	file_html := os.read_file(file_html_path) or { '' }

	// The HTML structure uses <div class="line covered"> or <div class="line uncovered">
	// followed by the content on subsequent lines. We need to track the current div's class
	// and check what content follows it.

	lines := file_html.split_into_lines()
	mut current_class := ''
	mut found_covered_arm_closing := false
	mut found_uncovered_func := false
	mut found_comment_in_covered := false
	mut found_comment_in_uncovered := false
	mut found_file_scope_comment_uncolored := false
	mut found_blank_line_in_covered := false
	mut found_file_scope_blank_uncolored := false
	mut found_match_arm_instrumented_hits := false // Check match arm has real hits not ~

	for line in lines {
		// Track div class
		if line.contains('<div class="line ') {
			if line.contains('covered') && !line.contains('uncovered') {
				current_class = 'covered'
			} else if line.contains('uncovered') {
				current_class = 'uncovered'
			} else {
				current_class = ''
			}
		}

		// Check for covered arm closing brace (line 9 - closing } of 'one' arm)
		// The closing brace should be marked covered since the arm was executed
		if line.contains('</span>') && line.contains('tok-punctuation') && line.contains('}')
			&& current_class == 'covered' {
			found_covered_arm_closing = true
		}

		// Check for uncovered function signature
		if line.contains('uncalled_func') && current_class == 'uncovered' {
			found_uncovered_func = true
		}

		// Check for comment in covered context
		if line.contains('Comment in first arm') && current_class == 'covered' {
			found_comment_in_covered = true
		}

		// Check for comment in uncovered context
		if line.contains('Uncovered comment') && current_class == 'uncovered' {
			found_comment_in_uncovered = true
		}

		// Check for file-scope doc comment (should NOT be colored)
		if line.contains('file-scope doc comment') && current_class == '' {
			found_file_scope_comment_uncolored = true
		}

		// Check for blank line inside covered function (line 5 - between comment and match)
		// Blank lines are <pre class="code"></pre> with no content
		if line.contains('line-num">5<') && current_class == 'covered' {
			found_blank_line_in_covered = true
		}

		// Check for file-scope blank line (line 25 - between functions, should NOT be colored)
		if line.contains('line-num">25<') && current_class == '' {
			found_file_scope_blank_uncolored = true
		}

		// Check that covered match arm (line 7: 'one' {) has instrumented hits (1x not ~1x)
		// This verifies commit 509e1a374 match arm line coverage is preserved
		if line.contains('hits">1x<') && current_class == 'covered' {
			found_match_arm_instrumented_hits = true
		}
	}

	assert found_covered_arm_closing, 'Closing brace of covered arm should be marked covered'
	assert found_uncovered_func, 'Uncalled function should be marked uncovered'
	assert found_comment_in_covered, 'Comments in covered code should be marked covered'
	assert found_comment_in_uncovered, 'Comments in uncovered code should be marked uncovered'
	assert found_file_scope_comment_uncolored, 'File-scope doc comments should NOT be colored'
	assert found_blank_line_in_covered, 'Blank lines inside covered code should be marked covered'
	assert found_file_scope_blank_uncolored, 'File-scope blank lines should NOT be colored'
	assert found_match_arm_instrumented_hits, 'Match arm should show instrumented hits (1x) not inferred (~)'
}

fn test_if_statement_coverage() {
	// Test that if header with hits marks itself and closing brace as covered
	// even when the body is not executed
	html_dir := np(os.join_path(tfolder, 'html_if'))
	os.rmdir_all(html_dir) or {}

	// Run test to generate coverage data
	r := execute('${os.quoted_path(vexe)} -no-skip-unused -cov-data-dir ${os.quoted_path(t_if)} test cmd/tools/vcover/testdata/iftest/')
	assert r.exit_code == 0, r.str()
	assert os.exists(t_if), t_if

	// Generate HTML report
	r2 := execute('${os.quoted_path(vexe)} cover ${os.quoted_path(t_if)} --out ${os.quoted_path(html_dir)} --filter iftest/')
	assert r2.exit_code == 0, r2.output

	// Check file HTML
	file_html_path := os.join_path(html_dir, 'files', 'cmd', 'tools', 'vcover', 'testdata',
		'iftest', 'if_func.v.html')
	file_html := os.read_file(file_html_path) or { '' }

	lines := file_html.split_into_lines()
	mut current_class := ''
	mut found_if_header_covered := false
	mut found_if_closing_covered := false
	mut found_if_body_uncovered := false

	for line in lines {
		// Track div class
		if line.contains('<div class="line ') {
			if line.contains('covered') && !line.contains('uncovered') {
				current_class = 'covered'
			} else if line.contains('uncovered') {
				current_class = 'uncovered'
			} else {
				current_class = ''
			}
		}

		// Line 5: if header should be covered (has 1x hits)
		if line.contains('line-num">5<') && current_class == 'covered' {
			found_if_header_covered = true
		}

		// Line 7: return -1 should be uncovered (never executed)
		if line.contains('line-num">7<') && current_class == 'uncovered' {
			found_if_body_uncovered = true
		}

		// Line 8: closing brace should be covered (inherits from if header)
		if line.contains('line-num">8<') && current_class == 'covered' {
			found_if_closing_covered = true
		}
	}

	assert found_if_header_covered, 'If header with hits should be marked covered'
	assert found_if_body_uncovered, 'If body that was never executed should be uncovered'
	assert found_if_closing_covered, 'If closing brace should inherit covered from header'
}

fn test_struct_coverage_propagation() {
	// Test that structs used as field types are marked as covered when their containing struct is used
	t_struct := np(os.join_path(tfolder, 't_struct'))
	os.rmdir_all(t_struct) or {}

	html_dir := np(os.join_path(tfolder, 'html_struct'))
	os.rmdir_all(html_dir) or {}

	// Run test to generate coverage data
	r := execute('${os.quoted_path(vexe)} -no-skip-unused -cov-data-dir ${os.quoted_path(t_struct)} test cmd/tools/vcover/testdata/structtest/')
	assert r.exit_code == 0, r.str()
	assert os.exists(t_struct), t_struct

	// Generate HTML report
	r2 := execute('${os.quoted_path(vexe)} cover ${os.quoted_path(t_struct)} --out ${os.quoted_path(html_dir)} --filter structtest/')
	assert r2.exit_code == 0, r2.output

	// Check file HTML
	file_html_path := os.join_path(html_dir, 'files', 'cmd', 'tools', 'vcover', 'testdata',
		'structtest', 'struct_types.v.html')
	file_html := os.read_file(file_html_path) or { '' }

	lines := file_html.split_into_lines()
	mut current_class := ''
	mut inner_struct_covered := false
	mut outer_struct_covered := false
	mut unused_struct_uncovered := false

	for line in lines {
		// Track div class
		if line.contains('<div class="line ') {
			if line.contains('covered') && !line.contains('uncovered') {
				current_class = 'covered'
			} else if line.contains('uncovered') {
				current_class = 'uncovered'
			} else {
				current_class = ''
			}
		}

		// Line 4: Inner struct declaration should be covered (used as field type in Outer)
		if line.contains('line-num">4<') && current_class == 'covered' {
			inner_struct_covered = true
		}

		// Line 9: Outer struct declaration should be covered (instantiated)
		if line.contains('line-num">9<') && current_class == 'covered' {
			outer_struct_covered = true
		}

		// Line 16: Unused struct declaration should be uncovered
		if line.contains('line-num">16<') && current_class == 'uncovered' {
			unused_struct_uncovered = true
		}
	}

	assert inner_struct_covered, 'Inner struct used as field type should be marked covered'
	assert outer_struct_covered, 'Outer struct that is instantiated should be marked covered'
	assert unused_struct_uncovered, 'Unused struct should be marked uncovered'
}

fn test_return_match_arm_instrumentation() {
	// Test that single-line match arms in return statements have instrumented hits (not inferred)
	t_returnmatch := np(os.join_path(tfolder, 't_returnmatch'))
	os.rmdir_all(t_returnmatch) or {}

	html_dir := np(os.join_path(tfolder, 'html_returnmatch'))
	os.rmdir_all(html_dir) or {}

	// Run test to generate coverage data
	r := execute('${os.quoted_path(vexe)} -no-skip-unused -cov-data-dir ${os.quoted_path(t_returnmatch)} test cmd/tools/vcover/testdata/returnmatch/')
	assert r.exit_code == 0, r.str()
	assert os.exists(t_returnmatch), t_returnmatch

	// Generate HTML report
	r2 := execute('${os.quoted_path(vexe)} cover ${os.quoted_path(t_returnmatch)} --out ${os.quoted_path(html_dir)} --filter returnmatch/')
	assert r2.exit_code == 0, r2.output

	// Check file HTML
	file_html_path := os.join_path(html_dir, 'files', 'cmd', 'tools', 'vcover', 'testdata',
		'returnmatch', 'return_match.v.html')
	file_html := os.read_file(file_html_path) or { '' }

	lines := file_html.split_into_lines()
	mut found_yes_no_instrumented := false
	mut found_ok_instrumented := false

	for i, line in lines {
		// Line 15 (.yes_no arm) should show 1x (instrumented) not ~1x (inferred)
		if line.contains('line-num">15<') {
			if i + 1 < lines.len {
				hits_line := lines[i + 1]
				// Should be exactly "1x" not "~1x"
				if hits_line.contains('hits">1x<') {
					found_yes_no_instrumented = true
				}
			}
		}

		// Line 13 (.ok arm) should show 0x (instrumented with 0 hits) not ~ (inferred)
		if line.contains('line-num">13<') {
			if i + 1 < lines.len {
				hits_line := lines[i + 1]
				// Should be exactly "0x" not "~"
				if hits_line.contains('hits">0x<') {
					found_ok_instrumented = true
				}
			}
		}
	}

	assert found_yes_no_instrumented, 'Match arm .yes_no should show instrumented hits (1x) not inferred (~1x)'
	assert found_ok_instrumented, 'Match arm .ok should show instrumented 0x not inferred ~'
}

fn test_field_access_hit_counting() {
	// Test that struct field accesses are tracked and show inferred hits (~nx)
	t_fieldtest := np(os.join_path(tfolder, 't_fieldtest'))
	os.rmdir_all(t_fieldtest) or {}

	html_dir := np(os.join_path(tfolder, 'html_fieldtest'))
	os.rmdir_all(html_dir) or {}

	// Run test to generate coverage data
	r := execute('${os.quoted_path(vexe)} -no-skip-unused -cov-data-dir ${os.quoted_path(t_fieldtest)} test cmd/tools/vcover/testdata/fieldtest/')
	assert r.exit_code == 0, r.str()
	assert os.exists(t_fieldtest), t_fieldtest

	// Generate HTML report
	r2 := execute('${os.quoted_path(vexe)} cover ${os.quoted_path(t_fieldtest)} --out ${os.quoted_path(html_dir)} --filter fieldtest/')
	assert r2.exit_code == 0, r2.output

	// Check file HTML
	file_html_path := os.join_path(html_dir, 'files', 'cmd', 'tools', 'vcover', 'testdata',
		'fieldtest', 'field_types.v.html')
	file_html := os.read_file(file_html_path) or { '' }

	lines := file_html.split_into_lines()
	mut found_value_field_hit := false
	mut found_inner_field_hit := false
	mut found_count_field_hit := false

	for i, line in lines {
		// Line 4 (value int) should show ~1x (inferred field access)
		if line.contains('line-num">4<') {
			if i + 1 < lines.len {
				hits_line := lines[i + 1]
				if hits_line.contains('hits">~1x<') {
					found_value_field_hit = true
				}
			}
		}

		// Line 9 (inner Inner) should show ~1x (inferred field access)
		if line.contains('line-num">9<') {
			if i + 1 < lines.len {
				hits_line := lines[i + 1]
				if hits_line.contains('hits">~1x<') {
					found_inner_field_hit = true
				}
			}
		}

		// Line 10 (count int) should show ~1x (inferred field access)
		if line.contains('line-num">10<') {
			if i + 1 < lines.len {
				hits_line := lines[i + 1]
				if hits_line.contains('hits">~1x<') {
					found_count_field_hit = true
				}
			}
		}
	}

	assert found_value_field_hit, 'Field Inner.value should show inferred hit (~1x)'
	assert found_inner_field_hit, 'Field Outer.inner should show inferred hit (~1x)'
	assert found_count_field_hit, 'Field Outer.count should show inferred hit (~1x)'
}

fn execute(cmd string) os.Result {
	eprintln('Executing: ${cmd}')
	return os.execute(cmd)
}
