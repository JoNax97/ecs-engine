package loomscript

// A program is a flat list of statements; there is no enclosing node.
Program :: []Statement

// Span is a node's full source range [start, end), for underline-style error
// reporting. It is distinct from a node's 'pos', which marks a specific
// token with its own meaning (e.g. a binary op's operator, which sits in
// the middle of its own span, not at the start).
Span :: struct {
	start: int,
	end:   int,
}

// Node_Base is embedded (via 'using') in every Expr/Statement variant, so
// pos/span are defined once instead of per struct, and composite literals
// can still set them with flat 'pos = ...' / 'span = ...' fields.
Node_Base :: struct {
	pos:  int,
	span: Span,
}

// expr_span returns e's span regardless of its concrete variant. nil (a
// failed parse) has no span and reports the zero Span.
expr_span :: proc(e: Expr) -> Span {
	switch node in e {
	case ^Expression_IntLit:
		return node.span
	case ^Expression_BinaryOp:
		return node.span
	case ^Expression_UnaryOp:
		return node.span
	case ^Expression_Identifier:
		return node.span
	case:
		return Span{}
	}
}

// statement_span returns s's span regardless of its concrete variant.
statement_span :: proc(s: Statement) -> Span {
	switch node in s {
	case ^Statement_Declaration:
		return node.span
	case ^Statement_Assignment:
		return node.span
	case ^Statement_Expression:
		return node.span
	case ^Statement_If:
		return node.span
	case:
		return Span{}
	}
}

// block_span_end returns the span end of a statement list's last element,
// or fallback when the list is empty (e.g. an 'if' body with no
// statements — the span still needs to end somewhere sensible).
@(private)
block_span_end :: proc(stmts: []Statement, fallback: int) -> int {
	if len(stmts) == 0 {
		return fallback
	}
	return statement_span(stmts[len(stmts) - 1]).end
}

// Statements

Statement :: union {
	^Statement_Declaration,
	^Statement_Assignment,
	^Statement_Expression,
	^Statement_If,
}

Statement_Declaration :: struct {
	using base: Node_Base, // pos of 'let'
	name:       string,
	value:      Expr,
}

Statement_Assignment :: struct {
	using base: Node_Base, // pos of the identifier
	name:       string,
	value:      Expr,
}

Statement_Expression :: struct {
	using base: Node_Base,
	expr:       Expr,
}

// An 'else if' is represented as a single Statement_If nested in else_body;
// only the outermost if in a chain owns the closing 'end'. else_body is nil
// when there is no 'else' clause. A nested 'else if' node's span covers only
// its own condition and body — the shared closing 'end' belongs to the
// outermost node's span alone, since that's the one that actually consumes it.
Statement_If :: struct {
	using base: Node_Base, // pos of 'if'
	cond:       Expr,
	then_body:  []Statement,
	else_body:  []Statement,
}


// Expressions

Expr :: union {
	^Expression_IntLit,
	^Expression_BinaryOp,
	^Expression_UnaryOp,
	^Expression_Identifier,
}

Expression_IntLit :: struct {
	using base: Node_Base,
	value:      int,
}

Expression_BinaryOp :: struct {
	using base: Node_Base, // pos of the operator token — sits inside the span, not at its start
	op:         Token_Kind, // Plus, Minus, Mult, Div, IntDiv, Modulo, Eq, Neq, Lt, LtEq, Gt, GtEq
	left:       Expr,
	right:      Expr,
}

Expression_UnaryOp :: struct {
	using base: Node_Base, // pos of the operator token
	op:         Token_Kind, // Plus, Minus
	operand:    Expr,
}

Expression_Identifier :: struct {
	using base: Node_Base,
	name:       string,
}
