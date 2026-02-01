# vcover HTML Report - Design Decisions

TODO: before ship

- fix -cov-data-dir to match existing style (don't want to rock the boat too much)
- cleanup this doc
- Use it for two weeks
- report text and report html parity
- ask llm for better green and red colors
- move doc to "v cover"
- pretty print templates
- test cov reset and append

This document tracks key design decisions made during the development of the AST-based coverage inference system for vcover HTML reports.

## Overview

The vcover tool generates HTML coverage reports for V code. It uses AST analysis to provide more accurate coverage information than raw instrumentation data alone.

## Key Concepts

### Instrumented Hits vs Inferred Hits

**Instrumented Hits** are actual execution counts measured by the V compiler's coverage instrumentation. When you compile with `-cov-data-dir`, the compiler inserts coverage points at specific locations (function bodies, control flow branches, match arms, etc.). At runtime, these points increment counters each time they're executed. The resulting data shows exactly how many times each instrumented line ran.

**Inferred Hits** are coverage estimates derived from AST analysis and logical deduction, NOT from actual runtime measurement. They fill gaps where instrumentation doesn't place coverage points but we can reasonably determine coverage status:

| Type | Display | Meaning |
|------|---------|---------|
| Instrumented, executed | `1x`, `6x` | Ran exactly N times (measured) |
| Instrumented, not executed | `0x` | Never ran (measured) |
| Inferred covered | `~` | Logically covered based on context |
| Inferred with count | `~3x` | Covered with computed hit count |
| Not code | (empty) | Comments, blank lines, imports |

**Examples of inferred coverage:**
- **Function signatures**: If any line inside a function body is covered, the `fn foo() {` line is inferred as covered
- **Closing braces**: If a function is covered, its `}` is inferred as covered
- **Struct declarations**: If a struct is instantiated on a covered line, its declaration lines are inferred as covered
- **Match closing braces**: If any match arm is covered, the match's `}` is inferred as covered

**Why the distinction matters:**
- Instrumented data is ground truth - it shows what actually executed
- Inferred data provides visual completeness but shouldn't be mistaken for measurement
- The `~` prefix clearly indicates "this is our best estimate, not a measurement"

## Design Decisions

### 1. Closing Brace Coverage Inheritance

**Decision**: Closing braces (`}`) inherit their coverage status from their corresponding opening construct.

**Rationale**:
- If a function body is executed, its closing brace is logically executed
- If a function is never called, its closing brace is never reached
- Same applies to for loops, if/else blocks, and match statements

**Implementation**: Track `block_start` and `block_end` in `LineCoverage` to link openers and closers.

### 2. Comment and Blank Line Coloring

**Decision**: Comments and blank lines inside function bodies inherit coverage color from surrounding code lines, but file-scope comments remain uncolored.

**Rationale**:
- Visual continuity improves readability in covered/uncovered regions
- File-scope comments (between functions, at module level) are not part of any execution context
- Blank lines follow the same rules as comments for consistency

**Implementation**: Fifth pass in `infer_coverage` checks if the previous non-comment/non-blank line is a top-level closing brace before applying color inheritance.

### 3. Inferred Coverage Display

**Decision**: Lines with inferred coverage show `~` in the hits column; instrumented lines show actual hit count (`1x`, `5x`, etc.).

**Rationale**:
- Users should distinguish between measured and inferred coverage
- `~` indicates "approximately" or "inferred"
- Actual counts are valuable for identifying hot paths

**Implementation**: `CoverageSource` enum tracks whether data is `.instrumented`, `.inferred`, or `.type_usage`.

### 4. If Statement Preserves Instrumented Data

**Decision**: When an if/else header has instrumented hits, that data takes precedence over inference.

**Rationale**:
- V's coverage instrumentation places coverage points at if conditions
- If instrumentation says the condition was evaluated, that's more accurate than inference
- Inference should only fill gaps, not override measurements

**Implementation**: Check `lines[i].source != .instrumented` before applying inference to if_header and else_header.

### 5. Struct Coverage via Type Usage

**Decision**: A struct/enum declaration is marked as covered if:
1. It is instantiated on a covered line (`StructName{ ... }`)
2. One of its enum values is used on a covered line (`.SomeValue`)
3. It is used as a type parameter in a generic function call on a covered line
4. It is used as a field type in another struct that is covered (propagation)

**Rationale**:
- Code coverage should reflect whether types are actually used in executed code
- Generic function calls like `json.decode(MyStruct, data)` use the type even without explicit instantiation
- If a struct contains a field of another struct type, using the outer struct implies the inner type is relevant

**Implementation**:
- Extract type info from `CallExpr.expected_arg_types`, `CastExpr.typ`, and struct field declarations
- Iterative propagation in `mark_type_coverage` to handle nested type dependencies

### 6. Match Arm Coverage Preservation

**Decision**: If a match arm line has instrumented coverage data (from commit 509e1a374), preserve that data instead of overwriting with inference.

**Rationale**:
- Commit 509e1a374 added match arm line coverage for V coverage and gcov
- For single-line match arms like `.ok { ['OK'] }`, the compiler places coverage points directly on the arm line
- For multi-line match arms, coverage points are on the body lines (e.g., `return 1`)
- Previously, the inference would check `status != .covered` which could overwrite instrumented data
- Now we check `source != .instrumented` to preserve actual measurements

**Implementation**: Check `lines[i].source != .instrumented` before applying inference to match arms.

### 7. Field Access Hit Counting

**Decision**: When a struct field is directly accessed (e.g., `obj.field_name`), increment a hit counter for that field's declaration line.

**Rationale**:
- Shows which struct fields are actually used in tests
- Helps identify dead code at the field level
- Rendered as `~<count>x` to show it's computed, not instrumented

**Implementation**:
Since `SelectorExpr.expr_type` isn't populated without full semantic analysis, we use a two-pass approach with lightweight variable type tracking:

1. **First pass**: Collect struct declarations and build `field_type_map` (field name -> field type) for each struct in `TypeDecl`

2. **Second pass**: Walk function bodies with variable type tracking:
   - Track variable types when we see `x := StructName{...}` assignments
   - Track function parameter types
   - When we see `x.field`, look up `x` in `var_types` to find its struct type
   - For chained access like `x.inner.value`, resolve through `struct_fields` map

3. **Inference**: In `mark_type_coverage`, aggregate field hits and apply to field declaration lines

**Example**:
```v
struct Inner { value int }
struct Outer { inner Inner }

fn foo() {
    o := Outer{ inner: Inner{ value: 42 } }  // o -> Outer tracked
    x := o.inner.value  // Outer.inner hit, Inner.value hit
}
```
Result: Line `inner Inner` shows `~1x`, line `value int` shows `~1x`

**Key functions**:
- `collect_field_usages_in_fn()` - entry point for function body analysis
- `collect_field_usages_in_stmt()` - walks statements, tracks variable types
- `collect_field_usages_in_expr()` - walks expressions, collects SelectorExpr usages
- `resolve_selector_struct_type()` - resolves struct type from variable tracking or chained access

### 8. Match Header Instrumented Preservation

**Decision**: If a match header line (e.g., `return match x {` or `match x {`) has instrumented coverage data, preserve it instead of overwriting with inference.

**Rationale**:
- The match header line may be instrumented by the compiler
- Previously, the inference would unconditionally set `source = .inferred` for match headers
- This caused lines like `return match buttons {` to show `~1x` instead of `1x`

**Implementation**: Check `lines[i].source != .instrumented` before applying inference to `.match_header` in infer.v.

### 9. Preserving Instrumented Data for Unclassified Lines

**Decision**: Lines that have instrumented coverage data but weren't classified by AST analysis (e.g., statements inside `or { }` blocks) should preserve their instrumented source.

**Rationale**:
- Some code constructs like `or { }` error handling blocks aren't fully traversed by AST analysis
- Lines inside these blocks may have `line_type = .blank` despite being real code
- The fifth pass (comment/blank coloring) was overwriting `source = .inferred` for these lines
- This caused error handling code like `return error('...')` to show `~6x` instead of `6x`

**Implementation**: In the fifth pass of `infer_coverage`, skip lines that already have `source == .instrumented`:
```v
if lines[i].source == .instrumented {
    continue
}
```

**Implementation**: Added `classify_call_expr` function that traverses `CallExpr.or_block.stmts`. Updated `classify_assign_stmt`, `classify_expr_stmt`, and `classify_stmt` (Return case) to handle `ast.CallExpr` with `or_block`.

### 10. Inferred Hits Display Format

**Decision**: Lines with inferred coverage show different formats based on hit information:
- `~` - Inferred covered, no specific hit count (e.g., function signatures, closing braces)
- `~<n>x` - Inferred covered with computed hit count (e.g., field access tracking)
- `<n>x` - Instrumented with actual hit count (e.g., `1x`, `6x`)
- `0x` - Instrumented but uncovered (0 hits)
- (empty) - Not code (comments, blank lines at file scope)

**Rationale**:
- Users should distinguish between measured and inferred coverage
- `~` prefix indicates "approximately" or "inferred"
- Hit counts help identify hot paths and frequently used code

**Implementation**: In `render_source_line_with_coverage` in `report.v`:
```v
hits_str := match lc.source {
    .instrumented {
        if lc.hits > 0 { '${lc.hits}x' } else { '0x' }
    }
    .inferred, .type_usage {
        if lc.hits > 0 {
            '~${lc.hits}x'
        } else if lc.status == .covered || lc.status == .uncovered {
            '~'
        } else {
            ''
        }
    }
    .not_available {
        ''
    }
}
```

### 11. Line Counting Philosophy

**Decision**: Only lines with `LineType.is_code() == true` count toward coverage totals. This includes:
- Function signatures, closing braces
- Control flow headers (for, if, else, match)
- Struct/enum declarations, fields, closing braces
- Regular code statements

**Excluded**:
- Blank lines
- Comments
- Module declarations, imports, attributes

**Rationale**: Coverage percentage should reflect what proportion of meaningful code is tested, not be diluted by whitespace and documentation.

## File Structure

- `model.v` - Core data structures (LineType, LineCoverage, TypeDecl, etc.)
- `ast_analyze.v` - AST parsing and line classification
- `infer.v` - Coverage inference logic
- `report.v` - HTML report generation
- `cover_test.v` - Integration tests
- `testdata/` - Test fixtures for various coverage scenarios

## Command Line Interface

### Usage

```
v cover [options] [folder1/ file2 ...]
```

The tool processes coverage data from directories or individual `.csv` files produced by running programs compiled with `-cov-data-dir`.

### Options

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--help` | `-h` | false | Show help text |
| `--verbose` | `-v` | false | Be more verbose while processing |
| `--hotspots` | `-H` | false | Show most frequently executed covered lines |
| `--percentages` | `-P` | true | Show coverage percentage per file |
| `--show_test_files` | `-S` | false | Include `_test.v` files (normally filtered) |
| `--showhits` | | false | Show hit counts for each line in HTML report |
| `--absolute` | `-A` | false | Use absolute paths for all files |
| `--filter` | `-f` | | Filter source paths (repeatable, see below) |
| `--out` | `-o` | | Generate HTML report in specified directory |
| `--view` | | false | Open generated HTML report in browser |
| `--cov-data-dir` | | | Coverage data directory (alias for positional arg) |
| `--cov-report` | | | Report format:path (e.g., `html:report/`) |

### Filter Option

The `--filter` / `-f` option filters which source files appear in the report:

```bash
# Include only files matching pattern
v cover .coverage --filter ui/designer/

# Exclude files matching pattern (prefix with !)
v cover .coverage --filter '!_test.v'

# Multiple filters (comma-separated or repeated)
v cover .coverage -f ui/ -f '!test'
v cover .coverage --filter 'ui/,!test'
```

### Compatibility Flags

These flags mirror the V compiler's coverage flags for workflow consistency:

- `--cov-data-dir <path>` - Same as passing the path as a positional argument
- `--cov-report <format:path>` - Parses format and sets output directory
  - `html:report/` - Generate HTML report in `report/` directory
  - `term` or `terminal` - Terminal output (default behavior)

### Examples

```bash
# Basic terminal report
v cover .coverage/

# Generate HTML report
v cover .coverage --out coverage_report/

# Generate and open in browser
v cover .coverage --out coverage_report/ --view

# Filter to specific module
v cover .coverage --out report/ --filter lib/ui/

# Using compiler-style flags
v cover --cov-data-dir .coverage --cov-report html:report/

# Verbose output with hotspots
v cover .coverage -v -H
```
