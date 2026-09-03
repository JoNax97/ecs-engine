package loomscript

import "core:unicode"

tokenize :: proc(src: string, allocator := context.allocator) -> []Token {
	tokens := make([dynamic]Token, allocator)

	pos := 0
	for pos < len(src) {
		c := src[pos]

		if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
			pos += 1
			continue
		}

		start := pos

		switch {
		case unicode.is_digit(rune(c)):
			for pos < len(src) && unicode.is_digit(rune(src[pos])) {
				pos += 1
			}
			append(&tokens, Token{kind = .Int_Lit, text = src[start:pos], pos = start})

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

		case:
			// unknown byte, skip for now (no error handling yet)
			pos += 1
		}
	}

	append(&tokens, Token{kind = .EOF, text = "", pos = pos})
	return tokens[:]
}
