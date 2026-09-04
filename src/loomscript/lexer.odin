package loomscript

import "core:unicode"

tokenize :: proc(src: string, allocator := context.allocator) -> []Token {
	tokens := make([dynamic]Token, allocator)

	pos := 0
	for pos < len(src) {
		c := src[pos]

		if c == ' ' || c == '\t' || c == '\r' {
			pos += 1
			continue
		}

		start := pos

		switch {
		case c == '\n':
			pos += 1
			append(&tokens, Token{kind = .Newline, text = src[start:pos], pos = start})

		case unicode.is_digit(rune(c)):
			for pos < len(src) && unicode.is_digit(rune(src[pos])) {
				pos += 1
			}
			append(&tokens, Token{kind = .IntLiteral, text = src[start:pos], pos = start})

		case is_ident_start(rune(c)):
			for pos < len(src) && is_ident_continue(rune(src[pos])) {
				pos += 1
			}
			text := src[start:pos]
			kind := Token_Kind.Identifier
			if text == "let" {
				kind = .Let
			}
			append(&tokens, Token{kind = kind, text = text, pos = start})

		case c == '+':
			pos += 1
			append(&tokens, Token{kind = .Plus, text = src[start:pos], pos = start})

		case c == '-':
			pos += 1
			append(&tokens, Token{kind = .Minus, text = src[start:pos], pos = start})

		case c == '*':
			pos += 1
			append(&tokens, Token{kind = .Star, text = src[start:pos], pos = start})

		case c == '(':
			pos += 1
			append(&tokens, Token{kind = .LParen, text = src[start:pos], pos = start})

		case c == ')':
			pos += 1
			append(&tokens, Token{kind = .RParen, text = src[start:pos], pos = start})

		case c == '=':
			pos += 1
			append(&tokens, Token{kind = .Assign, text = src[start:pos], pos = start})

		case:
			// unknown byte, skip for now (no error handling yet)
			pos += 1
		}
	}

	append(&tokens, Token{kind = .EOF, text = "", pos = pos})
	return tokens[:]
}

@(private)
is_ident_start :: proc(r: rune) -> bool {
	return r == '_' || unicode.is_alpha(r)
}

@(private)
is_ident_continue :: proc(r: rune) -> bool {
	return r == '_' || unicode.is_alpha(r) || unicode.is_digit(r)
}
