package loomscript_test

import "core:mem"
import "core:testing"

import "../"

@(private = "file")
as_binary :: proc(t: ^testing.T, e: loomscript.Expr) -> ^loomscript.Expr_Binary {
	node, ok := e.(^loomscript.Expr_Binary)
	testing.expect(t, ok, "expected Expr_Binary")
	return node
}

@(private = "file")
as_int :: proc(t: ^testing.T, e: loomscript.Expr) -> ^loomscript.Expr_Int_Lit {
	node, ok := e.(^loomscript.Expr_Int_Lit)
	testing.expect(t, ok, "expected Expr_Int_Lit")
	return node
}

@(private = "file")
parse_src :: proc(t: ^testing.T, arena: mem.Allocator, src: string) -> (loomscript.Expr, []loomscript.Parse_Error) {
	tokens := loomscript.tokenize(src, arena)
	return loomscript.parse(tokens, arena)
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
	testing.expect_value(t, inner.op, loomscript.Token_Kind.Star)
	testing.expect_value(t, as_int(t, inner.left).value, 3)
	testing.expect_value(t, as_int(t, inner.right).value, 4)
}

@(test)
test_parse_parens_override_precedence :: proc(t: ^testing.T) {
	// "(2 + 3) * 4" must group as (2 + 3) * 4, parens beat operator precedence.
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "(2 + 3) * 4")
	testing.expect_value(t, len(errors), 0)

	outer := as_binary(t, expr)
	testing.expect_value(t, outer.op, loomscript.Token_Kind.Star)
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
test_parse_empty_input :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "")
	testing.expect_value(t, expr, nil)
	testing.expect_value(t, len(errors), 1)
	testing.expect_value(t, errors[0].msg, "expected expression")
	testing.expect_value(t, errors[0].pos, 0)
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

	node, ok := expr.(^loomscript.Expr_Unary)
	testing.expect(t, ok, "expected Expr_Unary")
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
	testing.expect_value(t, outer.op, loomscript.Token_Kind.Star)

	left, ok := outer.left.(^loomscript.Expr_Unary)
	testing.expect(t, ok, "expected Expr_Unary")
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

	outer, ok := expr.(^loomscript.Expr_Unary)
	testing.expect(t, ok, "expected Expr_Unary")
	testing.expect_value(t, outer.op, loomscript.Token_Kind.Minus)

	inner, ok2 := outer.operand.(^loomscript.Expr_Unary)
	testing.expect(t, ok2, "expected inner Expr_Unary")
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

	right, ok := outer.right.(^loomscript.Expr_Unary)
	testing.expect(t, ok, "expected Expr_Unary")
	testing.expect_value(t, right.op, loomscript.Token_Kind.Minus)
	testing.expect_value(t, as_int(t, right.operand).value, 4)
}

@(test)
test_parse_trailing_input_is_rejected :: proc(t: ^testing.T) {
	// "1 2": a full expr parses as just "1", but "2" is leftover garbage
	// that must be reported, not silently dropped.
	arena := make_test_arena(t)
	defer free_all(arena)
	expr, errors := parse_src(t, arena, "1 2")
	testing.expect_value(t, as_int(t, expr).value, 1)
	testing.expect_value(t, len(errors), 1)
	testing.expect_value(t, errors[0].msg, "unexpected trailing input")
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
