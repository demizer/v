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
				// If header with instrumented hits is already covered, keep it
				// Otherwise infer from body coverage
				if lines[i].source != .instrumented {
					end := lines[i].block_end
					if any_covered_in_range(lines, i + 1, end - 1) {
						lines[i].status = .covered
						lines[i].source = .inferred
					} else if has_any_code_in_range(lines, i + 1, end - 1) {
						lines[i].status = .uncovered
					}
				}
			}
			.else_header {
				// Else header with instrumented hits is already covered, keep it
				// Otherwise infer from body coverage
				if lines[i].source != .instrumented {
					end := lines[i].block_end
					if any_covered_in_range(lines, i + 1, end - 1) {
						lines[i].status = .covered
						lines[i].source = .inferred
					} else if has_any_code_in_range(lines, i + 1, end - 1) {
						lines[i].status = .uncovered
					}
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
				// Match header with instrumented hits keeps instrumented source
				// Only infer if no instrumented data is available
				if lines[i].source != .instrumented {
					// Match header is covered if ANY arm has hits
					end := lines[i].block_end
					if any_covered_in_range(lines, i + 1, end - 1) {
						lines[i].status = .covered
						lines[i].source = .inferred
					} else if has_any_code_in_range(lines, i + 1, end - 1) {
						lines[i].status = .uncovered
					}
				}
			}
			.match_arm {
				// Match arm coverage comes from instrumentation (commit 509e1a374)
				// Only infer if no instrumented data is available
				if lines[i].source != .instrumented {
					// Use block_end if available, otherwise find next arm/closing brace
					mut arm_end := lines[i].block_end
					if arm_end == 0 {
						arm_end = i + 1
						for j in (i + 1) .. lines.len {
							if lines[j].line_type == .match_arm
								|| lines[j].line_type == .match_closing_brace {
								arm_end = j - 1
								break
							}
						}
					}
					if any_covered_in_range(lines, i + 1, arm_end - 1) {
						lines[i].status = .covered
						lines[i].source = .inferred
					} else if has_any_code_in_range(lines, i + 1, arm_end - 1) {
						lines[i].status = .uncovered
					}
				}
			}
			.match_arm_closing {
				// Arm closing brace inherits from its arm header
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

	// Third pass: Apply type coverage (with field type propagation and field hit counting)
	mark_type_coverage(mut lines, analysis.type_decls, analysis.type_usages, analysis.field_usages,
		instrumented)

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

	// Fifth pass: Propagate coverage to comments and blank lines for visual coloring
	// They inherit coverage status from surrounding code (doesn't affect counts)
	// Only color those inside function bodies, not at file scope
	// IMPORTANT: Skip lines that already have instrumented data (e.g., or_block statements)
	for i in 1 .. lines.len {
		if lines[i].line_type == .comment || lines[i].line_type == .blank {
			// Skip lines that already have instrumented coverage data
			if lines[i].source == .instrumented {
				continue
			}

			// Check if this line is at file scope by looking at surrounding context
			// Find the previous non-comment, non-blank line
			mut prev_type := LineType.blank
			for j := i - 1; j >= 1; j-- {
				if lines[j].line_type != .comment && lines[j].line_type != .blank {
					prev_type = lines[j].line_type
					break
				}
			}

			// Skip file-scope lines: those after closing braces of top-level constructs
			// or at the start of the file (before any code)
			if prev_type == .fn_closing_brace || prev_type == .struct_closing
				|| prev_type == .enum_closing || prev_type == .other || prev_type == .blank {
				continue
			}

			// Look for nearest non-comment, non-blank line with coverage info
			// First check previous lines
			mut found := false
			for j := i - 1; j >= 1; j-- {
				if lines[j].line_type != .comment && lines[j].line_type != .blank {
					if lines[j].status == .covered || lines[j].status == .uncovered {
						lines[i].status = lines[j].status
						lines[i].source = .inferred
						found = true
					}
					break
				}
			}
			// If not found, check next lines
			if !found {
				for j in (i + 1) .. lines.len {
					if lines[j].line_type != .comment && lines[j].line_type != .blank {
						if lines[j].status == .covered || lines[j].status == .uncovered {
							lines[i].status = lines[j].status
							lines[i].source = .inferred
						}
						break
					}
				}
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
fn mark_type_coverage(mut lines []LineCoverage, type_decls []TypeDecl, type_usages []TypeUsage, field_usages []FieldUsage, instrumented map[int]u64) {
	// Build a map of type name -> whether it's used on a covered line
	mut type_covered := map[string]bool{}

	// Pass 1: Mark types covered by direct usage (instantiation, generic calls, etc.)
	for usage in type_usages {
		// Check if this usage line is covered
		if usage.line in instrumented && instrumented[usage.line] > 0 {
			type_covered[usage.type_name] = true
		}
	}

	// Build a map of type name -> TypeDecl for propagation
	mut decl_map := map[string]TypeDecl{}
	for decl in type_decls {
		decl_map[decl.name] = decl
	}

	// Pass 2: Propagate coverage through field types (iterate until stable)
	// If a struct is covered and has a field of another struct type, that type is also covered
	mut changed := true
	for changed {
		changed = false
		for decl in type_decls {
			if type_covered[decl.name] {
				for field_type in decl.field_types {
					if !type_covered[field_type] {
						type_covered[field_type] = true
						changed = true
					}
				}
			}
		}
	}

	// Pass 3: Count field access hits
	// Build map of (struct_name, field_name) -> total hits on covered lines
	mut field_hits := map[string]u64{}
	for usage in field_usages {
		if usage.line in instrumented && instrumented[usage.line] > 0 {
			key := '${usage.struct_name}.${usage.field_name}'
			field_hits[key] = field_hits[key] + instrumented[usage.line]
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

		// Apply field hits to field declaration lines
		for field_name, field_line in decl.fields {
			key := '${decl.name}.${field_name}'
			if hits := field_hits[key] {
				if field_line > 0 && field_line < lines.len {
					lines[field_line].hits = hits
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
