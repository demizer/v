module main

import os
import os.cmdline
import testing
import v.pref

struct Context {
mut:
	verbose          bool
	fail_fast        bool
	run_only         []string
	coverage_sources []string // directories to cover
	coverage_report  string   // report format:path (e.g., "html:report/")
	coverage_dir     string   // where coverage data is stored
}

fn main() {
	args := os.args.clone()
	if os.args.last() == 'test' {
		show_usage()
		return
	}
	args_to_executable := args[1..]
	mut args_before := cmdline.options_before(args_to_executable, ['test'])
	mut args_after := cmdline.options_after(args_to_executable, ['test'])
	mut ctx := Context{}
	ctx.fail_fast = extract_flag_bool('-fail-fast', mut args_after, testing.fail_fast)
	ctx.verbose = extract_flag_bool('-v', mut args_after, false)
	ctx.run_only = extract_flag_string_array('-run-only', mut args_after, testing.test_only_fn)
	os.setenv('VTEST_ONLY_FN', ctx.run_only.join(','), true)
	if args_after == ['v'] {
		eprintln('`v test v` has been deprecated.')
		eprintln('Use `v test-all` instead.')
		exit(1)
	}
	backend_pos := args_before.index('-b')
	backend := if backend_pos == -1 { '.c' } else { args_before[backend_pos + 1] }

	mut ts := testing.new_test_session(args_before.join(' '), true)
	ts.exec_mode = .compile_and_run
	ts.fail_fast = ctx.fail_fast
	for targ in args_after {
		if os.is_dir(targ) {
			// Fetch all tests from the directory
			files, skip_files := ctx.should_test_dir(targ.trim_right(os.path_separator), backend)
			ts.files << files
			ts.skip_files << skip_files
			continue
		} else if os.exists(targ) {
			match ctx.should_test(targ, backend) {
				.test {
					ts.files << targ
					continue
				}
				.skip {
					if ctx.run_only.len > 0 {
						continue
					}
					ts.files << targ
					ts.skip_files << os.abs_path(targ)
					continue
				}
				.ignore {}
			}
		} else {
			eprintln('\nUnrecognized test file `${targ}`.\n `v test` can only be used with folders and/or _test.v files.\n')
			show_usage()
			exit(1)
		}
	}
	// Parse coverage flags from args_before
	ctx.parse_coverage_flags(args_before)

	ts.session_start('Testing...')
	ts.test()
	ts.session_stop('all V _test.v files')

	// Generate coverage report if requested
	if ctx.coverage_sources.len > 0 && ctx.coverage_report != '' {
		ctx.generate_coverage_report()
	}

	if ts.failed_cmds.len > 0 {
		exit(1)
	}
}

fn show_usage() {
	println('Usage:')
	println('   A)')
	println('      v test folder/ : run all v tests in the given folder.')
	println('      v -stats test folder/ : the same, but print more stats.')
	println('   B)')
	println('      v test file_test.v : run test functions in a given test file.')
	println('      v -stats test file_test.v : as above, but with more stats.')
	println('')
	println('Coverage options:')
	println('   -cov <dir>              : include directory in coverage analysis (can be used multiple times)')
	println('   -cov-data-dir <path>    : where to store coverage data (default: .coverage/)')
	println('   -cov-report <fmt:path>  : generate report (formats: html, term)')
	println('   -cov-append             : append to existing coverage data')
	println('   -cov-reset              : clear previous coverage data first')
	println('')
	println('Coverage examples:')
	println('   v -cov src/ test folder/')
	println('   v -cov src/ -cov lib/ -cov-report html:report/ test .')
	println('   v -cov src/ -cov-report term test .')
	println('   v -cov src/ -cov-data-dir /tmp/mycov -cov-append test .')
	println('')
	println('Note: you can also give many and mixed folder/ file_test.v arguments after `v test`.')
	println('')
}

pub fn (mut ctx Context) should_test_dir(path string, backend string) ([]string, []string) { // return is (files, skip_files)
	mut files := os.ls(path) or { return []string{}, []string{} }
	mut local_path_separator := os.path_separator
	if path.ends_with(os.path_separator) {
		local_path_separator = ''
	}
	mut res_files := []string{}
	mut skip_files := []string{}
	for file in files {
		p := path + local_path_separator + file
		if os.is_dir(p) && !os.is_link(p) {
			if file == 'testdata' {
				continue
			}
			ret_files, ret_skip_files := ctx.should_test_dir(p, backend)
			res_files << ret_files
			skip_files << ret_skip_files
		} else if os.exists(p) {
			match ctx.should_test(p, backend) {
				.test {
					res_files << p
				}
				.skip {
					if ctx.run_only.len > 0 {
						continue
					}
					res_files << p
					skip_files << os.abs_path(p)
				}
				.ignore {}
			}
		}
	}
	return res_files, skip_files
}

enum ShouldTestStatus {
	test   // do test, print OK or FAIL, depending on if it passes
	skip   // print SKIP for the test
	ignore // just ignore the file, so it will not be printed at all in the list of tests
}

fn (mut ctx Context) should_test(path string, backend string) ShouldTestStatus {
	if path.ends_with('_test.v') {
		return ctx.should_test_when_it_contains_matching_fns(path, backend)
	}
	if path.ends_with('_test.c.v') {
		return ctx.should_test_when_it_contains_matching_fns(path, backend)
	}
	if path.ends_with('_test.js.v') {
		if testing.is_node_present {
			return ctx.should_test_when_it_contains_matching_fns(path, backend)
		}
		return .skip
	}
	if path.ends_with('.v') && path.count('.') == 2 {
		if !path.all_before_last('.v').all_before_last('.').ends_with('_test') {
			return .ignore
		}
		backend_arg := path.all_before_last('.v').all_after_last('.')
		arch := pref.arch_from_string(backend_arg) or { pref.Arch._auto }
		if arch == pref.get_host_arch() {
			return ctx.should_test_when_it_contains_matching_fns(path, backend)
		} else if arch == ._auto {
			if backend_arg == 'c' { // .c.v
				return if backend == 'c' {
					ctx.should_test_when_it_contains_matching_fns(path, backend)
				} else {
					ShouldTestStatus.skip
				}
			}
			if backend_arg == 'js' {
				return if backend == 'js' {
					ctx.should_test_when_it_contains_matching_fns(path, backend)
				} else {
					ShouldTestStatus.skip
				}
			}
		} else {
			return .skip
		}
	}
	return .ignore
}

fn (mut ctx Context) should_test_when_it_contains_matching_fns(path string, _backend string) ShouldTestStatus {
	if ctx.run_only.len == 0 {
		// no filters set, so just compile and test
		return .test
	}
	lines := os.read_lines(path) or { return .ignore }
	for line in lines {
		if line.match_glob('fn test_*') || line.match_glob('pub fn test_*') {
			tname := line.replace_each(['pub fn ', '', 'fn ', '']).all_before('(')
			for pattern in ctx.run_only {
				mut pat := pattern.clone()
				if pat.contains('.') {
					pat = pat.all_after_last('.')
				}
				if tname.match_glob(pat) {
					if ctx.verbose {
						println('> compiling path: ${path}, since test fn `${tname}` matches glob pattern `${pat}`')
					}
					return .test
				}
			}
		}
	}
	return .ignore
}

fn extract_flag_bool(flag_name string, mut after []string, flag_default bool) bool {
	mut res := flag_default
	orig_after :=
		after.clone() // workaround for after.filter() codegen bug, when `mut after []string`
	matches_after := orig_after.filter(it != flag_name)
	if matches_after.len < after.len {
		after = matches_after.clone()
		res = true
	}
	return res
}

fn extract_flag_string_array(flag_name string, mut after []string, flag_default []string) []string {
	mut res := flag_default.clone()
	mut found := after.index(flag_name)
	if found > -1 {
		if found + 1 < after.len {
			res = after[found + 1].split_any(',')
			after.delete(found)
		}
		after.delete(found)
	}
	return res
}

// parse_coverage_flags extracts coverage-related flags from compiler args
fn (mut ctx Context) parse_coverage_flags(args []string) {
	mut i := 0
	for i < args.len {
		arg := args[i]
		if arg in ['-cov', '-coverage'] && i + 1 < args.len {
			ctx.coverage_sources << os.real_path(args[i + 1])
			i += 2
		} else if arg == '-cov-data-dir' && i + 1 < args.len {
			ctx.coverage_dir = args[i + 1]
			i += 2
		} else if arg == '-cov-report' && i + 1 < args.len {
			ctx.coverage_report = args[i + 1]
			i += 2
		} else {
			i++
		}
	}
	// Set default coverage directory
	if ctx.coverage_sources.len > 0 && ctx.coverage_dir == '' {
		ctx.coverage_dir = os.join_path(os.getwd(), '.coverage')
	}
}

// generate_coverage_report runs vcover to generate the coverage report
fn (ctx &Context) generate_coverage_report() {
	if ctx.coverage_dir == '' || !os.exists(ctx.coverage_dir) {
		eprintln('Coverage data directory not found: ${ctx.coverage_dir}')
		return
	}

	// Parse report format and path from -cov-report value
	// Format: "html:path" or "term" or "json:path"
	parts := ctx.coverage_report.split_nth(':', 2)
	report_format := parts[0]
	report_path := if parts.len > 1 { parts[1] } else { '' }

	mut vcover_args := [ctx.coverage_dir]

	// Add filter for coverage sources
	if ctx.coverage_sources.len > 0 {
		filters := ctx.coverage_sources.map(it.replace(os.getwd() + os.path_separator,
			''))
		vcover_args << '-f'
		vcover_args << filters.join(',')
	}

	// Always show test files in coverage reports since we're running tests
	vcover_args << '-S'

	match report_format {
		'html' {
			if report_path != '' {
				vcover_args << '-o'
				vcover_args << report_path
			}
			println('\nGenerating HTML coverage report...')
		}
		'term', 'terminal' {
			vcover_args << '-P'
			println('\nCoverage report:')
		}
		'json' {
			// JSON output would need to be added to vcover
			println('\nJSON coverage report format not yet implemented')
			return
		}
		else {
			eprintln('Unknown coverage report format: ${report_format}')
			return
		}
	}

	// Run vcover
	vexe := os.getenv('VEXE')
	vcover_cmd := '${vexe} cover ${vcover_args.join(' ')}'
	if ctx.verbose {
		println('Running: ${vcover_cmd}')
	}
	result := os.execute(vcover_cmd)
	if result.exit_code != 0 {
		eprintln('Coverage report generation failed:')
		eprintln(result.output)
	} else {
		print(result.output)
		if report_format == 'html' && report_path != '' {
			println('Coverage report generated at: ${os.real_path(report_path)}/index.html')
		}
	}
}
