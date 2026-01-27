// infer.v - Coverage inference logic based on AST analysis
module main

// infer_coverage applies coverage inference to AST classifications based on instrumented coverage data.
// It returns a complete FileCoverage with all lines classified and coverage status determined.
fn infer_coverage(analysis AstAnalysis, instrumented map[int]u64) FileCoverage {
	mut lines := analysis.classifications.clone()

	// First pass: Apply instrumented coverage data
	for line_num, hits in instrumented {
		if line_num > 0 && line_num < lines.len {
			lines[line_num].hits = hits
			lines[line_num].source = .instrumented
			if hits > 0 {
				lines[line_num].status = .covered
			} else {
				// Only mark as uncovered if it's a code line
				if lines[line_num].line_type.is_code() {
					lines[line_num].status = .uncovered
				}
			}
		}
	}

	// Second pass: Infer coverage for headers and closing braces
	for i in 1 .. lines.len {
		match lines[i].line_type {
			.fn_signature {
				// Function signature is covered if ANY body line has hits
				end := lines[i].block_end
				if any_covered_in_range(lines, i + 1, end - 1) {
					lines[i].status = .covered
					lines[i].source = .inferred
				} else if has_any_code_in_range(lines, i + 1, end - 1) {
					lines[i].status = .uncovered
				} else {
					// Empty function body - consider it not_code
					lines[i].status = .not_code
				}
			}
			.fn_closing_brace {
				// Closing brace inherits from opener
				opener := lines[i].block_start
				if opener > 0 && opener < lines.len {
					if lines[opener].status == .covered {
						lines[i].status = .covered
						lines[i].source = .inferred
					} else if lines[opener].status == .uncovered {
						lines[i].status = .uncovered
					}
				}
			}
			.for_header {
				// For header is covered if ANY body line has hits
				end := lines[i].block_end
				if any_covered_in_range(lines, i + 1, end - 1) {
					lines[i].status = .covered
					lines[i].source = .inferred
				} else if has_any_code_in_range(lines, i + 1, end - 1) {
					lines[i].status = .uncovered
				}
			}
			.for_closing_brace {
				// Closing brace inherits from opener
				opener := lines[i].block_start
				if opener > 0 && opener < lines.len {
					if lines[opener].status == .covered {
						lines[i].status = .covered
						lines[i].source = .inferred
					} else if lines[opener].status == .uncovered {
						lines[i].status = .uncovered
					}
				}
			}
			.if_header {
				// If header is covered if ANY body line in this branch has hits
				end := lines[i].block_end
				if any_covered_in_range(lines, i + 1, end - 1) {
					lines[i].status = .covered
					lines[i].source = .inferred
				} else if has_any_code_in_range(lines, i + 1, end - 1) {
					lines[i].status = .uncovered
				}
			}
			.else_header {
				// Else header is covered if ANY body line has hits
				end := lines[i].block_end
				if any_covered_in_range(lines, i + 1, end - 1) {
					lines[i].status = .covered
					lines[i].source = .inferred
				} else if has_any_code_in_range(lines, i + 1, end - 1) {
					lines[i].status = .uncovered
				}
			}
			.if_closing_brace {
				// Closing brace inherits from opener
				opener := lines[i].block_start
				if opener > 0 && opener < lines.len {
					if lines[opener].status == .covered {
						lines[i].status = .covered
						lines[i].source = .inferred
					} else if lines[opener].status == .uncovered {
						lines[i].status = .uncovered
					}
				}
			}
			.match_header {
				// Match header is covered if ANY arm has hits
				end := lines[i].block_end
				if any_covered_in_range(lines, i + 1, end - 1) {
					lines[i].status = .covered
					lines[i].source = .inferred
				} else if has_any_code_in_range(lines, i + 1, end - 1) {
					lines[i].status = .uncovered
				}
			}
			.match_arm {
				// Match arm coverage comes from instrumentation
				// If not already covered by instrumentation, check body
				if lines[i].status != .covered {
					// Find next match arm or closing brace to determine arm range
					mut arm_end := i + 1
					for j in (i + 1) .. lines.len {
						if lines[j].line_type == .match_arm
							|| lines[j].line_type == .match_closing_brace {
							arm_end = j - 1
							break
						}
					}
					if any_covered_in_range(lines, i + 1, arm_end) {
						lines[i].status = .covered
						lines[i].source = .inferred
					} else if has_any_code_in_range(lines, i + 1, arm_end) {
						lines[i].status = .uncovered
					}
				}
			}
			.match_closing_brace {
				// Closing brace inherits from opener
				opener := lines[i].block_start
				if opener > 0 && opener < lines.len {
					if lines[opener].status == .covered {
						lines[i].status = .covered
						lines[i].source = .inferred
					} else if lines[opener].status == .uncovered {
						lines[i].status = .uncovered
					}
				}
			}
			else {}
		}
	}

	// Third pass: Apply type coverage
	mark_type_coverage(mut lines, analysis.type_decls, analysis.type_usages, instrumented)

	// Fourth pass: Mark remaining code lines without coverage data
	for i in 1 .. lines.len {
		if lines[i].line_type.is_code() && lines[i].status != .covered
			&& lines[i].status != .uncovered {
			// Code line with no coverage info - check if it's in a covered context
			// For now, mark as uncovered if it's actual code
			if lines[i].source == .not_available {
				lines[i].status = .uncovered
			}
		}
	}

	// Count totals
	mut total_code := 0
	mut covered_code := 0
	for i in 1 .. lines.len {
		if lines[i].line_type.is_code() && lines[i].status != .not_code {
			total_code++
			if lines[i].status == .covered {
				covered_code++
			}
		}
	}

	return FileCoverage{
		path:         ''
		lines:        lines
		total_code:   total_code
		covered_code: covered_code
	}
}

// any_covered_in_range checks if any line in the given range (inclusive) is covered
fn any_covered_in_range(lines []LineCoverage, start int, end int) bool {
	for i in start .. (end + 1) {
		if i > 0 && i < lines.len {
			if lines[i].status == .covered {
				return true
			}
		}
	}
	return false
}

// has_any_code_in_range checks if there's any code line in the given range
fn has_any_code_in_range(lines []LineCoverage, start int, end int) bool {
	for i in start .. (end + 1) {
		if i > 0 && i < lines.len {
			if lines[i].line_type.is_code() {
				return true
			}
		}
	}
	return false
}

// mark_type_coverage marks struct/enum declarations as covered if their usages are on covered lines
fn mark_type_coverage(mut lines []LineCoverage, type_decls []TypeDecl, type_usages []TypeUsage, instrumented map[int]u64) {
	// Build a map of type name -> whether it's used on a covered line
	mut type_covered := map[string]bool{}

	for usage in type_usages {
		// Check if this usage line is covered
		if usage.line in instrumented && instrumented[usage.line] > 0 {
			type_covered[usage.type_name] = true
		}
	}

	// Mark type declaration lines based on usage coverage
	for decl in type_decls {
		is_covered := type_covered[decl.name]

		// Mark all lines of this type declaration
		for i in decl.start_line .. (decl.end_line + 1) {
			if i > 0 && i < lines.len {
				lt := lines[i].line_type
				if lt == .struct_decl || lt == .struct_field || lt == .struct_closing
					|| lt == .enum_decl || lt == .enum_field || lt == .enum_closing {
					if is_covered {
						lines[i].status = .covered
						lines[i].source = .type_usage
					} else {
						lines[i].status = .uncovered
					}
				}
			}
		}
	}
}

// build_file_coverage creates a FileCoverage for a source file using AST analysis and instrumented data
fn build_file_coverage(path string, instrumented map[int]u64) !FileCoverage {
	// Analyze the file's AST
	analysis := analyze_file(path)!

	// Apply inference
	mut fc := infer_coverage(analysis, instrumented)
	fc = FileCoverage{
		...fc
		path: path
	}

	return fc
}
