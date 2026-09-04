package loomscript_test

import "core:mem"
import "core:testing"

import "../"

@(private = "file")
as_binary :: proc(t: ^testing.T, e: loomscript.Expr) -> ^loomscript.Expression_BinaryOp {
	node, ok := e.(^loomscript.Expression_BinaryOp)
	testing.expect(t, ok, "expected Expression_BinaryOp")
	return node
}

@(private = "file")
as_int :: proc(t: ^testing.T, e: loomscript.Expr) -> ^loomscript.Expression_IntLit {
	node, ok := e.(^loomscript.Expression_IntLit)
	testing.expect(t, ok, "expected Expression_IntLit")
	return node
}

// parse_src parses src as a program and unwraps the single expression
// statement it's expected to produce — these tests exercise expression
// parsing specifically (precedence, associativity, error recovery inside an
// expression), not the statement/program layer, which has its own tests in
// program_test.odin.
@(private = "file")
parse_src :: proc(t: ^testing.T, arena: mem.Allocator, src: string) -> (loomscript.Expr, []loomscript.Parse_Error) {
	tokens := loomscript.tokenize(src, arena)
	program, errors := loomscript.parse(tokens, arena)

	testing.expect_value(t, len(program), 1)
	if len(program) != 1 {
		return nil, errors
	}

	stmt, ok := program[0].(^loomscript.Statement_Expression)
	testing.expect(t, ok, "expected Statement_Expression")
	if !ok {
		return nil, errors
	}

	return stmt.expr, errors
}

@(test)
test_parse_single_int_lit :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "42")
	testing.expect_value(t, len(errors), 0)
	node := as_int(t, expr)
	testing.expect_value(t, node.value, 42)
}

@(test)
test_parse_left_associative :: proc(t: ^testing.T) {
	// "1 - 2 - 3" must group as (1 - 2) - 3, not 1 - (2 - 3).
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "1 - 2 - 3")
	testing.expect_value(t, len(errors), 0)

	outer := as_binary(t, expr)
	testing.expect_value(t, outer.op, loomscript.Token_Kind.Minus)
	testing.expect_value(t, as_int(t, outer.right).value, 3)

	inner := as_binary(t, outer.left)
	testing.expect_value(t, inner.op, loomscript.Token_Kind.Minus)
	testing.expect_value(t, as_int(t, inner.left).value, 1)
	testing.expect_value(t, as_int(t, inner.right).value, 2)
}

@(test)
test_parse_same_precedence_left_to_right :: proc(t: ^testing.T) {
	// "10 - 2 + 3": Plus and Minus share precedence, must still be left-assoc.
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "10 - 2 + 3")
	testing.expect_value(t, len(errors), 0)

	outer := as_binary(t, expr)
	testing.expect_value(t, outer.op, loomscript.Token_Kind.Plus)
	testing.expect_value(t, as_int(t, outer.right).value, 3)

	inner := as_binary(t, outer.left)
	testing.expect_value(t, inner.op, loomscript.Token_Kind.Minus)
	testing.expect_value(t, as_int(t, inner.left).value, 10)
	testing.expect_value(t, as_int(t, inner.right).value, 2)
}

@(test)
test_parse_precedence_mul_over_add :: proc(t: ^testing.T) {
	// "2 + 3 * 4" must group as 2 + (3 * 4), not (2 + 3) * 4.
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "2 + 3 * 4")
	testing.expect_value(t, len(errors), 0)

	outer := as_binary(t, expr)
	testing.expect_value(t, outer.op, loomscript.Token_Kind.Plus)
	testing.expect_value(t, as_int(t, outer.left).value, 2)

	inner := as_binary(t, outer.right)
	testing.expect_value(t, inner.op, loomscript.Token_Kind.Mult)
	testing.expect_value(t, as_int(t, inner.left).value, 3)
	testing.expect_value(t, as_int(t, inner.right).value, 4)
}

@(test)
test_parse_precedence_div_and_mod_over_add :: proc(t: ^testing.T) {
	// '/', '//', '%' bind as tight as '*' — all above '+'/'-'.
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "2 + 7 // 2 % 3")
	testing.expect_value(t, len(errors), 0)

	outer := as_binary(t, expr)
	testing.expect_value(t, outer.op, loomscript.Token_Kind.Plus)
	testing.expect_value(t, as_int(t, outer.left).value, 2)

	inner := as_binary(t, outer.right)
	testing.expect_value(t, inner.op, loomscript.Token_Kind.Modulo)

	innermost := as_binary(t, inner.left)
	testing.expect_value(t, innermost.op, loomscript.Token_Kind.IntDiv)
	testing.expect_value(t, as_int(t, innermost.left).value, 7)
	testing.expect_value(t, as_int(t, innermost.right).value, 2)
}

@(test)
test_parse_comparison_binds_looser_than_arithmetic :: proc(t: ^testing.T) {
	// "1 + 2 > 3" must group as (1 + 2) > 3, not 1 + (2 > 3).
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "1 + 2 > 3")
	testing.expect_value(t, len(errors), 0)

	outer := as_binary(t, expr)
	testing.expect_value(t, outer.op, loomscript.Token_Kind.Gt)
	testing.expect_value(t, as_int(t, outer.right).value, 3)

	inner := as_binary(t, outer.left)
	testing.expect_value(t, inner.op, loomscript.Token_Kind.Plus)
	testing.expect_value(t, as_int(t, inner.left).value, 1)
	testing.expect_value(t, as_int(t, inner.right).value, 2)
}

@(test)
test_parse_multiplicative_tier_left_to_right :: proc(t: ^testing.T) {
	// "8 / 4 * 2": Mult/Div/IntDiv/Modulo share one precedence tier and
	// must still associate left-to-right, same as Plus/Minus do.
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "8 / 4 * 2")
	testing.expect_value(t, len(errors), 0)

	outer := as_binary(t, expr)
	testing.expect_value(t, outer.op, loomscript.Token_Kind.Mult)
	testing.expect_value(t, as_int(t, outer.right).value, 2)

	inner := as_binary(t, outer.left)
	testing.expect_value(t, inner.op, loomscript.Token_Kind.Div)
	testing.expect_value(t, as_int(t, inner.left).value, 8)
	testing.expect_value(t, as_int(t, inner.right).value, 4)
}

@(test)
test_parse_binary_op_span_covers_full_width_pos_is_operator :: proc(t: ^testing.T) {
	// A binary op's 'pos' marks the operator specifically (the '+' at
	// index 2, in the middle), while 'span' covers the whole expression
	// from the left operand's start to the right operand's end.
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "1 + 22")
	testing.expect_value(t, len(errors), 0)

	node := as_binary(t, expr)
	testing.expect_value(t, node.pos, 2)
	testing.expect_value(t, node.span, loomscript.Span{start = 0, end = 6})
}

@(test)
test_parse_parens_override_precedence :: proc(t: ^testing.T) {
	// "(2 + 3) * 4" must group as (2 + 3) * 4, parens beat operator precedence.
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "(2 + 3) * 4")
	testing.expect_value(t, len(errors), 0)

	outer := as_binary(t, expr)
	testing.expect_value(t, outer.op, loomscript.Token_Kind.Mult)
	testing.expect_value(t, as_int(t, outer.right).value, 4)

	inner := as_binary(t, outer.left)
	testing.expect_value(t, inner.op, loomscript.Token_Kind.Plus)
	testing.expect_value(t, as_int(t, inner.left).value, 2)
	testing.expect_value(t, as_int(t, inner.right).value, 3)
}

@(test)
test_parse_nested_parens :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "((1))")
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, as_int(t, expr).value, 1)
}

@(test)
test_parse_unmatched_open_paren :: proc(t: ^testing.T) {
	// "(2 + 3" never closes: error, but the inner expr still comes back
	// (best-effort partial AST, not a hard abort).
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "(2 + 3")
	testing.expect_value(t, len(errors), 1)
	testing.expect_value(t, errors[0].msg, "expected ')'")

	node := as_binary(t, expr)
	testing.expect_value(t, node.op, loomscript.Token_Kind.Plus)
}

@(test)
test_parse_unmatched_close_paren :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, ")")
	testing.expect_value(t, expr, nil)
	testing.expect_value(t, len(errors), 1)
	testing.expect_value(t, errors[0].msg, "expected expression")
}

@(test)
test_parse_trailing_operator :: proc(t: ^testing.T) {
	// "2 +" : left operand parses fine, right side is missing.
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "2 +")
	testing.expect_value(t, len(errors), 1)
	testing.expect_value(t, errors[0].msg, "expected expression")

	node := as_binary(t, expr)
	testing.expect_value(t, node.op, loomscript.Token_Kind.Plus)
	testing.expect_value(t, as_int(t, node.left).value, 2)
	testing.expect_value(t, node.right, nil)
}

@(test)
test_parse_unary_minus :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "-4")
	testing.expect_value(t, len(errors), 0)

	node, ok := expr.(^loomscript.Expression_UnaryOp)
	testing.expect(t, ok, "expected Expression_UnaryOp")
	testing.expect_value(t, node.op, loomscript.Token_Kind.Minus)
	testing.expect_value(t, as_int(t, node.operand).value, 4)
}

@(test)
test_parse_unary_binds_tighter_than_mul :: proc(t: ^testing.T) {
	// "-2 * 3" must group as (-2) * 3, not -(2 * 3).
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "-2 * 3")
	testing.expect_value(t, len(errors), 0)

	outer := as_binary(t, expr)
	testing.expect_value(t, outer.op, loomscript.Token_Kind.Mult)

	left, ok := outer.left.(^loomscript.Expression_UnaryOp)
	testing.expect(t, ok, "expected Expression_UnaryOp")
	testing.expect_value(t, left.op, loomscript.Token_Kind.Minus)
	testing.expect_value(t, as_int(t, left.operand).value, 2)

	testing.expect_value(t, as_int(t, outer.right).value, 3)
}

@(test)
test_parse_unary_chains :: proc(t: ^testing.T) {
	// "--4": double negation, unary recurses on itself.
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "--4")
	testing.expect_value(t, len(errors), 0)

	outer, ok := expr.(^loomscript.Expression_UnaryOp)
	testing.expect(t, ok, "expected Expression_UnaryOp")
	testing.expect_value(t, outer.op, loomscript.Token_Kind.Minus)

	inner, ok2 := outer.operand.(^loomscript.Expression_UnaryOp)
	testing.expect(t, ok2, "expected inner Expression_UnaryOp")
	testing.expect_value(t, inner.op, loomscript.Token_Kind.Minus)
	testing.expect_value(t, as_int(t, inner.operand).value, 4)
}

@(test)
test_parse_binary_op_with_unary_rhs :: proc(t: ^testing.T) {
	// "2 + -4": binary Plus with a unary-minus right operand.
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "2 + -4")
	testing.expect_value(t, len(errors), 0)

	outer := as_binary(t, expr)
	testing.expect_value(t, outer.op, loomscript.Token_Kind.Plus)
	testing.expect_value(t, as_int(t, outer.left).value, 2)

	right, ok := outer.right.(^loomscript.Expression_UnaryOp)
	testing.expect(t, ok, "expected Expression_UnaryOp")
	testing.expect_value(t, right.op, loomscript.Token_Kind.Minus)
	testing.expect_value(t, as_int(t, right.operand).value, 4)
}

@(test)
test_parse_trailing_input_is_rejected :: proc(t: ^testing.T) {
	// "1 2": a full expr parses as just "1", but "2" is leftover garbage on
	// the same line — the statement layer reports it as a missing separator
	// (there's no longer a distinct "trailing input" concept now that
	// expression parsing always runs inside the statement/program layer).
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "1 2")
	testing.expect_value(t, as_int(t, expr).value, 1)
	testing.expect_value(t, len(errors), 1)
	testing.expect_value(t, errors[0].msg, "expected newline after statement")
	testing.expect_value(t, errors[0].pos, 2)
}

@(test)
test_parse_invalid_int_lit_overflow :: proc(t: ^testing.T) {
	// Digits-only per the lexer, but too large for `int` — must be caught
	// by checked accumulation, not silently wrapped.
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "99999999999999999999999999999999")
	testing.expect_value(t, len(errors), 1)
	testing.expect_value(t, errors[0].msg, "integer literal too large")
	_ = as_int(t, expr) // node still produced, best-effort
}
