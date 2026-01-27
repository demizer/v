// model.v - Core data structures for AST-based coverage analysis
module main

// LineType classifies what kind of V construct a source line represents
enum LineType {
	blank
	comment
	fn_signature
	fn_closing_brace
	for_header
	for_closing_brace
	if_header
	else_header
	if_closing_brace
	match_header
	match_arm
	match_closing_brace
	struct_decl    // struct Foo {
	struct_field   // field lines inside struct
	struct_closing // } closing struct
	enum_decl      // enum Bar {
	enum_field     // enum value lines
	enum_closing   // } closing enum
	code           // regular executable statement
	other          // imports, module, attributes, etc.
}

// CoverageStatus indicates whether a line is covered
enum CoverageStatus {
	covered   // has hits or inferred covered
	uncovered // is code but not covered
	not_code  // blank, comment, etc. - doesn't count toward totals
}

// CoverageSource indicates where coverage information came from
enum CoverageSource {
	instrumented  // from V compiler coverage point
	inferred      // from AST inference (headers, braces)
	type_usage    // inferred from struct/enum usage on covered line
	not_available // not applicable (comments, blanks)
}

// LineCoverage holds coverage information for a single source line
struct LineCoverage {
mut:
	line_type LineType
	status    CoverageStatus
	hits      u64
	source    CoverageSource
	// For headers/openers: where the block ends (1-indexed line number)
	block_end int
	// For closing braces: where the block started (1-indexed line number)
	block_start int
	// For type declarations: the type name
	type_name string
}

// FileCoverage holds aggregated coverage data for a source file
struct FileCoverage {
	path         string
	lines        []LineCoverage // indexed by line number (0 = unused, 1 = first line)
	total_code   int            // lines that are meaningful code
	covered_code int            // code lines that are covered
}

// TypeDecl tracks a struct or enum declaration
struct TypeDecl {
	name       string // fully qualified name (module.TypeName)
	kind       string // 'struct' or 'enum'
	start_line int    // declaration start (1-indexed)
	end_line   int    // declaration end - closing brace (1-indexed)
}

// TypeUsage tracks where a struct is instantiated or enum value is used
struct TypeUsage {
	type_name string // fully qualified type name
	line      int    // line where instantiation/usage occurs (1-indexed)
}

// AstAnalysis holds the results of analyzing a source file's AST
struct AstAnalysis {
	num_lines       int            // total lines in the file
	classifications []LineCoverage // line-by-line classification (1-indexed)
	type_decls      []TypeDecl     // struct/enum declarations found
	type_usages     []TypeUsage    // struct instantiations, enum value usages
}

// coverage_percentage calculates the coverage percentage for a FileCoverage
fn (fc &FileCoverage) coverage_percentage() f64 {
	if fc.total_code == 0 {
		return 0.0
	}
	return 100.0 * f64(fc.covered_code) / f64(fc.total_code)
}

// is_code returns true if this line type counts as executable code
fn (lt LineType) is_code() bool {
	return match lt {
		.blank, .comment, .other { false }
		else { true }
	}
}
