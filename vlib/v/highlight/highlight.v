// Copyright (c) 2024 Felipe Pena and Delyan Angelov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
//
// V source code syntax highlighting for HTML output
module highlight

import encoding.html
import strings
import v.scanner
import v.ast
import v.token
import v.pref

pub const builtin_types = ['bool', 'string', 'i8', 'i16', 'int', 'i64', 'i128', 'isize', 'byte',
	'u8', 'u16', 'u32', 'u64', 'usize', 'u128', 'rune', 'f32', 'f64', 'byteptr', 'voidptr', 'any']

pub enum TokenType {
	unone
	boolean
	builtin
	char
	comment
	function
	keyword
	name
	number
	operator
	punctuation
	string
	opening_string
	string_interp
	partial_string
	closing_string
	symbol
	none_
	module_
	prefix
}

fn write_token(tok token.Token, typ TokenType, mut buf strings.Builder) {
	match typ {
		.unone, .operator, .punctuation {
			buf.write_string(tok.kind.str())
		}
		.string_interp {
			buf.write_byte(`$`)
		}
		.opening_string {
			buf.write_string("'${tok.lit}")
		}
		.closing_string {
			buf.write_string("${tok.lit}'")
		}
		.string {
			buf.write_string("'${tok.lit}'")
		}
		.char {
			buf.write_string('`${tok.lit}`')
		}
		.comment {
			buf.write_string('//')
			if tok.lit != '' && tok.lit[0] == 1 {
				buf.write_string(tok.lit[1..])
			} else {
				buf.write_string(tok.lit)
			}
		}
		else {
			buf.write_string(tok.lit)
		}
	}
}

// v_html returns syntax-highlighted HTML for V source code.
// Uses CSS class prefix 'tok-' (e.g., tok-keyword, tok-string).
// If tb (type table) is provided, it's used for better type detection.
pub fn v_html(code string, tb &ast.Table) string {
	mut s := scanner.new_scanner(code, .parse_comments, &pref.Preferences{ output_mode: .silent })
	mut tok := s.scan()
	mut prev_tok := tok
	mut next_tok := s.scan()
	mut buf := strings.new_builder(200)
	mut i := 0
	mut inside_string_interp := false
	for i < code.len {
		if i != tok.pos {
			buf.write_u8(code[i])
			i++
			continue
		}

		mut tok_typ := TokenType.unone
		match tok.kind {
			.name {
				if tok.lit in builtin_types || (tb != unsafe { nil } && tb.known_type(tok.lit)) {
					tok_typ = .builtin
				} else if next_tok.kind == .lcbr {
					tok_typ = .symbol
				} else if next_tok.kind == .lpar
					|| (tok.lit.len > 0 && !tok.lit[0].is_capital() && next_tok.kind == .lt
					&& next_tok.pos == tok.pos + tok.lit.len) {
					tok_typ = .function
				} else if tok.lit.len > 0 && tok.lit[0].is_capital() {
					tok_typ = .symbol
				} else {
					tok_typ = .name
				}
			}
			.comment {
				tok_typ = .comment
			}
			.chartoken {
				tok_typ = .char
			}
			.str_dollar {
				tok_typ = .string_interp
				inside_string_interp = true
			}
			.string {
				if inside_string_interp {
					if next_tok.kind == .str_dollar {
						tok_typ = .partial_string
					} else {
						tok_typ = .closing_string
					}
				} else if next_tok.kind == .str_dollar {
					tok_typ = .opening_string
				} else {
					tok_typ = .string
				}
			}
			.number {
				tok_typ = .number
			}
			.key_true, .key_false {
				tok_typ = .boolean
			}
			.lpar, .lcbr, .rpar, .rcbr, .lsbr, .rsbr, .semicolon, .colon, .comma, .dot, .dotdot,
			.ellipsis {
				tok_typ = .punctuation
			}
			else {
				if token.is_key(tok.lit) || token.is_decl(tok.kind) {
					tok_typ = .keyword
				} else if tok.kind.is_assign() || tok.is_unary() || tok.kind.is_relational()
					|| tok.kind.is_infix() || tok.kind.is_postfix() {
					tok_typ = .operator
				}
			}
		}

		if tok_typ in [.unone, .name] {
			write_token(tok, tok_typ, mut buf)
		} else {
			if tok_typ in [.partial_string, .closing_string] && inside_string_interp {
				if tok.lit.len != 0 {
					write_token(token.Token{ kind: .rcbr }, .unone, mut buf)
				}
				inside_string_interp = false
			}

			final_tok_typ := match tok_typ {
				.opening_string, .partial_string, .closing_string { TokenType.string }
				else { tok_typ }
			}

			buf.write_string('<span class="tok-${final_tok_typ}">')
			if tok_typ == .string {
				buf.write_string("'${html.escape(tok.lit.str())}'")
			} else {
				if final_tok_typ == .string && prev_tok.lit == 'return' {
					buf.write_string(' ')
				}
				write_token(tok, tok_typ, mut buf)
			}
			buf.write_string('</span>')
		}

		if next_tok.kind == .eof {
			break
		}

		i = tok.pos + tok.len

		if i - 1 == next_tok.pos {
			i--
		}
		prev_tok = tok
		tok = next_tok
		next_tok = s.scan()
	}
	return buf.str()
}

// v_html_simple is a convenience wrapper that doesn't require a type table.
pub fn v_html_simple(code string) string {
	return v_html(code, unsafe { nil })
}

// css returns the default CSS styles for syntax highlighting.
pub fn css() string {
	return '.tok-comment { color: #93a1a1; font-style: italic; }
.tok-punctuation { color: #999999; }
.tok-number, .tok-symbol { color: #702459; }
.tok-string, .tok-char, .tok-builtin { color: #38a169; }
.tok-operator { color: #a67f59; }
.tok-boolean, .tok-keyword { color: #2b6cb0; font-weight: 500; }
.tok-function { color: #319795; }'
}
