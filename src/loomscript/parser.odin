package loomscript

import "core:mem"

Parse_Error :: struct {
	msg: string,
	pos: int,
}

Parser :: struct {
	tokens:    []Token,
	pos:       int,
	errors:    [dynamic]Parse_Error,
	allocator: mem.Allocator,
}

parse :: proc(tokens: []Token, allocator := context.allocator) -> (expr: Expr, errors: []Parse_Error) {
	p := Parser{
		tokens    = tokens,
		pos       = 0,
		errors    = make([dynamic]Parse_Error, allocator),
		allocator = allocator,
	}

	expr = parse_binary(&p, 0)

	trailing := peek(&p)
	if trailing.kind != .EOF {
		push_error(&p, "unexpected trailing input", trailing.pos)
	}

	return expr, p.errors[:]
}

// parse_int_literal accumulates digits with an overflow check on each step
// (strconv.parse_int does not detect overflow, it wraps silently). text is
// assumed digits-only per the lexer's Int_Lit contract.
@(private)
parse_int_literal :: proc(text: string) -> (value: int, ok: bool) {
	cutoff :: max(int) / 10
	limit :: max(int) % 10

	for c in text {
		d := int(c) - int('0')
		if value > cutoff || (value == cutoff && d > limit) {
			return 0, false
		}
		value = value * 10 + d
	}
	return value, true
}

@(private)
peek :: proc(p: ^Parser) -> Token {
	return p.tokens[p.pos]
}

@(private)
advance :: proc(p: ^Parser) -> Token {
	tok := p.tokens[p.pos]
	if tok.kind != .EOF {
		p.pos += 1
	}
	return tok
}

@(private)
push_error :: proc(p: ^Parser, msg: string, pos: int) {
	append(&p.errors, Parse_Error{msg = msg, pos = pos})
}

// binary_precedence returns the binding power of a binary operator token;
// ok is false for non-operator tokens. Higher binds tighter.
@(private)
binary_precedence :: proc(kind: Token_Kind) -> (prec: int, ok: bool) {
	#partial switch kind {
	case .Plus, .Minus:
		return 1, true
	case .Star:
		return 2, true
	case:
		return 0, false
	}
}

// precedence climbing: parses a unary, then repeatedly folds in any binary
// operator whose precedence is >= min_prec, recursing at prec+1 for the
// right-hand side so operators are left-associative.
@(private)
parse_binary :: proc(p: ^Parser, min_prec: int) -> Expr {
	left := parse_unary(p)

	for {
		tok := peek(p)
		prec, ok := binary_precedence(tok.kind)
		if !ok || prec < min_prec {
			break
		}
		advance(p)
		right := parse_binary(p, prec + 1)

		node := new(Expr_Binary, p.allocator)
		node^ = Expr_Binary{pos = tok.pos, op = tok.kind, left = left, right = right}
		left = node
	}

	return left
}

// unary := ('+' | '-') unary | primary
// Binds tighter than any binary operator (so "-2 * 3" is "(-2) * 3", not
// "-(2 * 3)"); recurses on itself, not primary, so "--4" chains.
@(private)
parse_unary :: proc(p: ^Parser) -> Expr {
	tok := peek(p)

	#partial switch tok.kind {
	case .Plus, .Minus:
		advance(p)
		operand := parse_unary(p)

		node := new(Expr_Unary, p.allocator)
		node^ = Expr_Unary{pos = tok.pos, op = tok.kind, operand = operand}
		return node

	case:
		return parse_primary(p)
	}
}

// primary := Int_Lit | '(' expr ')'
@(private)
parse_primary :: proc(p: ^Parser) -> Expr {
	tok := peek(p)

	#partial switch tok.kind {
	case .Int_Lit:
		advance(p)
		value, ok := parse_int_literal(tok.text)
		if !ok {
			push_error(p, "integer literal too large", tok.pos)
		}
		node := new(Expr_Int_Lit, p.allocator)
		node^ = Expr_Int_Lit{pos = tok.pos, value = value}
		return node

	case .LParen:
		advance(p)
		inner := parse_binary(p, 0)
		closing := peek(p)
		if closing.kind != .RParen {
			push_error(p, "expected ')'", closing.pos)
			return inner
		}
		advance(p)
		return inner

	case:
		push_error(p, "expected expression", tok.pos)
		advance(p)
		return nil
	}
}
