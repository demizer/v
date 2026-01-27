// vtest retry: 2
import os

const vexe = @VEXE
const vroot = os.dir(vexe)
const tfolder = os.join_path(os.vtmp_dir(), 'cover_test')

const t1 = np(os.join_path(tfolder, 't1'))
const t2 = np(os.join_path(tfolder, 't2'))
const t3 = np(os.join_path(tfolder, 't3'))

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
	// AST-based counting: 8 covered (with inference) / 16 total code lines = 50.00%
	assert filter1.output.trim_space().ends_with('|      8 |     16 |  50.00%'), filter1.output
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
	// AST-based counting: mul() covered instead of sum(), 10 covered / 16 total = 62.50%
	assert filter2.output.trim_space().ends_with('|     10 |     16 |  62.50%'), filter2.output
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
	// AST-based counting: all 16 code lines covered = 100%
	assert filter3.output.trim_space().match_glob('*cmd/tools/vcover/testdata/simple/simple.v *|     16 |     16 | 100.00%'), filter3.str()
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
	// AST-based counting: 16 total code lines
	assert index.contains('16 / 16'), 'should show 16/16 lines'

	// Check individual file report exists
	file_html_path := os.join_path(html_dir, 'files', 'cmd', 'tools', 'vcover', 'testdata',
		'simple', 'simple.v.html')
	assert os.exists(file_html_path), 'file HTML should exist at: ${file_html_path}'

	// Check file HTML content
	file_html := os.read_file(file_html_path) or { '' }
	assert file_html.contains('covered'), 'should have covered lines'
	assert file_html.contains('pub fn sum'), 'should contain source code'
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
	// AST-based counting: 8 covered / 16 total = 50.00%
	assert index.contains('50'), 'should show ~50% coverage'
	assert index.contains('pct-med'), 'should have medium color class for 50-80%'
	assert index.contains('8 / 16'), 'should show 8/16 lines'

	// Check file HTML has both covered and uncovered lines
	file_html_path := os.join_path(html_dir, 'files', 'cmd', 'tools', 'vcover', 'testdata',
		'simple', 'simple.v.html')
	file_html := os.read_file(file_html_path) or { '' }
	assert file_html.contains('covered'), 'should have covered lines'
	assert file_html.contains('uncovered'), 'should have uncovered lines'
}

fn execute(cmd string) os.Result {
	eprintln('Executing: ${cmd}')
	return os.execute(cmd)
}
