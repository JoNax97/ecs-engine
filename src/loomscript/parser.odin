package loomscript

import "core:mem"

Parse_Error :: struct {
	msg: string,
	pos: int,
	len: int, // pos+len spans the offending token, for underlining
}

Parser :: struct {
	tokens:    []Token,
	pos:       int,
	errors:    [dynamic]Parse_Error,
	allocator: mem.Allocator,
}

// parse parses a whole file: a flat list of statements separated by one or
// more newlines. Blank lines (runs of Newline tokens) are tolerated anywhere.
// A single bare expression is valid input too — it just parses as a
// one-statement Program holding a Statement_Expr.
parse :: proc(tokens: []Token, allocator := context.allocator) -> (program: Program, errors: []Parse_Error) {
	p := Parser{
		tokens    = tokens,
		pos       = 0,
		errors    = make([dynamic]Parse_Error, allocator),
		allocator = allocator,
	}

	statements := make([dynamic]Statement, allocator)

	skip_newlines(&p)
	for peek(&p).kind != .EOF {
		errors_before := len(p.errors)
		stmt := parse_statement(&p)
		if stmt != nil {
			append(&statements, stmt)
		}

		tok := peek(&p)
		if tok.kind == .EOF {
			break
		}

		if tok.kind != .Newline {
			// Only report "expected newline" if the statement itself parsed
			// cleanly — if parse_Statement already pushed an error, the parser's
			// position is already unsynced because of that error, and a
			// second error here would just be noise pointing at the same
			// root cause.
			if len(p.errors) == errors_before {
				push_error(&p, "expected newline after statement", tok)
			}
			// recovery: skip to the next newline (or EOF) so one bad
			// statement doesn't cascade errors through the rest of the file.
			// This can only synchronize on a newline — two statements
			// crammed onto one line with no separator at all will have the
			// second one silently swallowed by this skip, since there is no
			// other sync point to recover on.
			for peek(&p).kind != .Newline && peek(&p).kind != .EOF {
				advance(&p)
			}
		}
		skip_newlines(&p)
	}

	return statements[:], p.errors[:]
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
peek_at :: proc(p: ^Parser, offset: int) -> Token {
	i := p.pos + offset
	if i >= len(p.tokens) {
		return p.tokens[len(p.tokens) - 1] // EOF is always last
	}
	return p.tokens[i]
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
skip_newlines :: proc(p: ^Parser) {
	for peek(p).kind == .Newline {
		advance(p)
	}
}

@(private)
push_error :: proc(p: ^Parser, msg: string, tok: Token) {
	append(&p.errors, Parse_Error{msg = msg, pos = tok.pos, len = tok.len})
}

// binary_precedence returns the binding power of a binary operator token;
// ok is false for non-operator tokens. Higher binds tighter.
@(private)
binary_precedence :: proc(kind: Token_Kind) -> (prec: int, ok: bool) {
	#partial switch kind {
	case .EqEq, .NotEq, .Lt, .LtEq, .Gt, .GtEq:
		return 1, true
	case .Plus, .Minus:
		return 2, true
	case .Mult:
		return 3, true
	case:
		return 0, false
	}
}

// precedence climbing: parses a unary, then repeatedly folds in any binary
// operator whose precedence is >= min_prec, recursing at prec+1 for the
// right-hand side so operators are left-associative.
@(private)
parse_binary_op :: proc(p: ^Parser, min_prec: int) -> Expr {
	left := parse_unary_op(p)

	for {
		tok := peek(p)
		prec, ok := binary_precedence(tok.kind)
		if !ok || prec < min_prec {
			break
		}
		advance(p)
		right := parse_binary_op(p, prec + 1)

		node := new(Expression_BinaryOp, p.allocator)
		node^ = Expression_BinaryOp{
			pos   = tok.pos,
			op    = tok.kind,
			left  = left,
			right = right,
			span  = Span{start = expr_span(left).start, end = expr_span(right).end},
		}
		left = node
	}

	return left
}

// unary := ('+' | '-') unary | operand
// Binds tighter than any binary operator (so "-2 * 3" is "(-2) * 3", not
// "-(2 * 3)"); recurses on itself, not operand, so "--4" chains.
@(private)
parse_unary_op :: proc(p: ^Parser) -> Expr {
	tok := peek(p)

	#partial switch tok.kind {
	case .Plus, .Minus:
		advance(p)
		operand := parse_unary_op(p)

		end := tok.pos + tok.len
		if operand != nil {
			end = expr_span(operand).end
		}

		node := new(Expression_UnaryOp, p.allocator)
		node^ = Expression_UnaryOp{
			pos     = tok.pos,
			op      = tok.kind,
			operand = operand,
			span    = Span{start = tok.pos, end = end},
		}
		return node

	case:
		return parse_operand(p)
	}
}

// operand := Int_Lit | Identifier | '(' expr ')'
@(private)
parse_operand :: proc(p: ^Parser) -> Expr {
	tok := peek(p)

	#partial switch tok.kind {
	case .IntLiteral:
		advance(p)
		value, ok := parse_int_literal(tok.text)
		if !ok {
			push_error(p, "integer literal too large", tok)
		}
		node := new(Expression_IntLiteral, p.allocator)
		node^ = Expression_IntLiteral{pos = tok.pos, value = value, span = Span{tok.pos, tok.pos + tok.len}}
		return node

	case .Identifier:
		advance(p)
		node := new(Expression_Identifier, p.allocator)
		node^ = Expression_Identifier{pos = tok.pos, name = tok.text, span = Span{tok.pos, tok.pos + tok.len}}
		return node

	case .LParen:
		advance(p)
		inner := parse_binary_op(p, 0)
		closing := peek(p)
		if closing.kind != .RParen {
			push_error(p, "expected ')'", closing)
			return inner
		}
		advance(p)
		return inner

	case:
		push_error(p, "expected expression", tok)
		advance(p)
		return nil
	}
}

// Statement := let_Statement | assign_Statement | Expression_Statement
@(private)
parse_statement :: proc(p: ^Parser) -> Statement {
	tok := peek(p)

	#partial switch tok.kind {
	case .Let:
		return parse_let_Statement(p)

	case .If:
		return parse_if_statement(p)

	case .Identifier:
		if peek_at(p, 1).kind == .Assign {
			return parse_assign_Statement(p)
		}
		return parse_statement_expression(p)

	case:
		return parse_statement_expression(p)
	}
}

// let_Statement := 'let' Ident '=' expr
@(private)
parse_let_Statement :: proc(p: ^Parser) -> Statement {
	let_tok := advance(p) // 'let'

	name_tok := peek(p)
	if name_tok.kind != .Identifier {
		push_error(p, "expected identifier after 'let'", name_tok)
		return nil
	}
	advance(p)

	eq_tok := peek(p)
	if eq_tok.kind != .Assign {
		push_error(p, "expected '=' in let statement", eq_tok)
		return nil
	}
	advance(p)

	value := parse_binary_op(p, 0)

	end := eq_tok.pos + eq_tok.len
	if value != nil {
		end = expr_span(value).end
	}

	node := new(Statement_Declaration, p.allocator)
	node^ = Statement_Declaration{
		pos   = let_tok.pos,
		name  = name_tok.text,
		value = value,
		span  = Span{start = let_tok.pos, end = end},
	}
	return node
}

// assign_Statement := Ident '=' expr
@(private)
parse_assign_Statement :: proc(p: ^Parser) -> Statement {
	name_tok := advance(p) // Ident
	eq_tok := advance(p) // '='

	value := parse_binary_op(p, 0)

	end := eq_tok.pos + eq_tok.len
	if value != nil {
		end = expr_span(value).end
	}

	node := new(Statement_Assignment, p.allocator)
	node^ = Statement_Assignment{
		pos   = name_tok.pos,
		name  = name_tok.text,
		value = value,
		span  = Span{start = name_tok.pos, end = end},
	}
	return node
}

// if_Statement := 'if' expr Newline block ('else' 'if' expr Newline block)* ('else' Newline block)? 'end'
// Only the outermost call consumes the closing 'end' — parse_if_head builds
// an 'else if' chain as nested Statement_If values in else_body and returns
// without touching 'end', so the whole chain closes on one 'end' token.
@(private)
parse_if_statement :: proc(p: ^Parser) -> Statement {
	node := parse_if_head(p)

	if peek(p).kind == .End {
		end_tok := advance(p)
		// Only the outermost node's span extends through 'end' — it's the
		// one that actually consumed the token; nested 'else if' nodes keep
		// spans covering just their own condition and body.
		node.span.end = end_tok.pos + end_tok.len
	} else {
		push_error(p, "expected 'end' to close 'if'", peek(p))
	}

	return node
}

@(private)
parse_if_head :: proc(p: ^Parser) -> ^Statement_If {
	if_tok := advance(p) // 'if'

	cond := parse_binary_op(p, 0)

	if peek(p).kind == .Newline {
		skip_newlines(p)
	} else {
		push_error(p, "expected newline after 'if' condition", peek(p))
	}

	node := new(Statement_If, p.allocator)
	node^ = Statement_If{pos = if_tok.pos, cond = cond, then_body = parse_block(p)}
	node.span = Span{
		start = if_tok.pos,
		end   = block_span_end(node.then_body, expr_span(cond).end),
	}

	if peek(p).kind == .Else {
		advance(p) // 'else'
		if peek(p).kind == .If {
			nested := parse_if_head(p)
			// composite-literal slices default to context.allocator, not
			// p.allocator (the caller's arena) — build it with make() so the
			// single-element else_body outlives this call the same way
			// then_body/parse_block's slices already do.
			else_body := make([]Statement, 1, p.allocator)
			else_body[0] = nested
			node.else_body = else_body
			node.span.end = statement_span(nested).end
		} else {
			skip_newlines(p)
			node.else_body = parse_block(p)
			node.span.end = block_span_end(node.else_body, node.span.end)
		}
	}

	return node
}

// parse_block parses newline-separated statements until it sees 'else',
// 'end', or EOF, without consuming that terminator.
@(private)
parse_block :: proc(p: ^Parser) -> []Statement {
	statements := make([dynamic]Statement, p.allocator)

	skip_newlines(p)
	for {
		tok := peek(p)
		if tok.kind == .Else || tok.kind == .End || tok.kind == .EOF {
			break
		}

		errors_before := len(p.errors)
		stmt := parse_statement(p)
		if stmt != nil {
			append(&statements, stmt)
		}

		tok = peek(p)
		if tok.kind == .Else || tok.kind == .End || tok.kind == .EOF {
			break
		}

		if tok.kind != .Newline {
			if len(p.errors) == errors_before {
				push_error(p, "expected newline after statement", tok)
			}
			for peek(p).kind != .Newline && peek(p).kind != .Else && peek(p).kind != .End && peek(p).kind != .EOF {
				advance(p)
			}
		}
		skip_newlines(p)
	}

	return statements[:]
}

// Expression_Statement := expr
@(private)
parse_statement_expression :: proc(p: ^Parser) -> Statement {
	tok := peek(p)
	expr := parse_binary_op(p, 0)

	end := tok.pos + tok.len
	if expr != nil {
		end = expr_span(expr).end
	}

	node := new(Statement_Expression, p.allocator)
	node^ = Statement_Expression{pos = tok.pos, expr = expr, span = Span{start = tok.pos, end = end}}
	return node
}
