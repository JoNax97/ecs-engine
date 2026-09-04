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
			append(&tokens, make_token(.Newline, src, start, pos))

		case unicode.is_digit(rune(c)):
			for pos < len(src) && unicode.is_digit(rune(src[pos])) {
				pos += 1
			}
			append(&tokens, make_token(.IntLiteral, src, start, pos))

		case is_ident_start(rune(c)):
			for pos < len(src) && is_ident_continue(rune(src[pos])) {
				pos += 1
			}
			kind := Token_Kind.Identifier
			switch src[start:pos] {
			case "let":
				kind = .Let
			case "if":
				kind = .If
			case "else":
				kind = .Else
			case "end":
				kind = .End
			}
			append(&tokens, make_token(kind, src, start, pos))

		case c == '+':
			pos += 1
			append(&tokens, make_token(.Plus, src, start, pos))

		case c == '-':
			pos += 1
			append(&tokens, make_token(.Minus, src, start, pos))

		case c == '*':
			pos += 1
			append(&tokens, make_token(.Mult, src, start, pos))

		case c == '(':
			pos += 1
			append(&tokens, make_token(.LParen, src, start, pos))

		case c == ')':
			pos += 1
			append(&tokens, make_token(.RParen, src, start, pos))

		case c == '=':
			pos += 1
			kind := Token_Kind.Assign
			if pos < len(src) && src[pos] == '=' {
				pos += 1
				kind = .EqEq
			}
			append(&tokens, make_token(kind, src, start, pos))

		case c == '!' && pos + 1 < len(src) && src[pos + 1] == '=':
			pos += 2
			append(&tokens, make_token(.NotEq, src, start, pos))

		case c == '<':
			pos += 1
			kind := Token_Kind.Lt
			if pos < len(src) && src[pos] == '=' {
				pos += 1
				kind = .LtEq
			}
			append(&tokens, make_token(kind, src, start, pos))

		case c == '>':
			pos += 1
			kind := Token_Kind.Gt
			if pos < len(src) && src[pos] == '=' {
				pos += 1
				kind = .GtEq
			}
			append(&tokens, make_token(kind, src, start, pos))

		case:
			// unknown byte, skip for now (no error handling yet)
			pos += 1
		}
	}

	append(&tokens, make_token(.EOF, src, pos, pos))
	return tokens[:]
}

// make_token builds a token spanning src[start:end], deriving text/pos/len
// from the same two offsets so they can never drift apart.
@(private)
make_token :: proc(kind: Token_Kind, src: string, start, end: int) -> Token {
	return Token{kind = kind, text = src[start:end], pos = start, len = end - start}
}

@(private)
is_ident_start :: proc(r: rune) -> bool {
	return r == '_' || unicode.is_alpha(r)
}

@(private)
is_ident_continue :: proc(r: rune) -> bool {
	return r == '_' || unicode.is_alpha(r) || unicode.is_digit(r)
}
