package loomscript_test

import "core:mem"
import "core:testing"

import "../"

@(private = "file")
parse_prog_src :: proc(t: ^testing.T, arena: mem.Allocator, src: string) -> (loomscript.Program, []loomscript.Parse_Error) {
	tokens := loomscript.tokenize(src, arena)
	return loomscript.parse(tokens, arena)
}

@(test)
test_parse_program_let_statement :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	program, errors := parse_prog_src(t, arena, "let x = 5")
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(program), 1)

	stmt, ok := program[0].(^loomscript.Statement_Declaration)
	testing.expect(t, ok, "expected Statement_Declaration")
	testing.expect_value(t, stmt.name, "x")

	value, ok2 := stmt.value.(^loomscript.Expression_IntLit)
	testing.expect(t, ok2, "expected Expression_IntLit")
	testing.expect_value(t, value.value, 5)
}

@(test)
test_parse_program_assign_statement :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	program, errors := parse_prog_src(t, arena, "x = 6")
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(program), 1)

	stmt, ok := program[0].(^loomscript.Statement_Assignment)
	testing.expect(t, ok, "expected Statement_Assignment")
	testing.expect_value(t, stmt.name, "x")
}

@(test)
test_parse_program_bare_expression_statement :: proc(t: ^testing.T) {
	// A bare identifier, not followed by '=', is an expression statement
	// (reads the variable), not an assignment.
	arena := make_test_arena(t)
	defer free_all(arena)

	program, errors := parse_prog_src(t, arena, "x")
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(program), 1)

	stmt, ok := program[0].(^loomscript.Statement_Expression)
	testing.expect(t, ok, "expected Statement_Expression")

	ident, ok2 := stmt.expr.(^loomscript.Expression_Identifier)
	testing.expect(t, ok2, "expected Expression_Identifier")
	testing.expect_value(t, ident.name, "x")
}

@(test)
test_parse_program_multiple_statements :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	program, errors := parse_prog_src(t, arena, "let x = 5\nx = 6\nx + 1")
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(program), 3)

	_, ok1 := program[0].(^loomscript.Statement_Declaration)
	testing.expect(t, ok1, "statement 0: expected Statement_Declaration")

	_, ok2 := program[1].(^loomscript.Statement_Assignment)
	testing.expect(t, ok2, "statement 1: expected Statement_Assignment")

	_, ok3 := program[2].(^loomscript.Statement_Expression)
	testing.expect(t, ok3, "statement 2: expected Statement_Expression")
}

@(test)
test_parse_program_blank_lines_are_tolerated :: proc(t: ^testing.T) {
	// Leading, trailing, and repeated blank lines between statements must
	// not produce empty statements or errors.
	arena := make_test_arena(t)
	defer free_all(arena)

	program, errors := parse_prog_src(t, arena, "\n\nlet x = 5\n\n\nx = 6\n\n")
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(program), 2)
}

@(test)
test_parse_program_empty_input :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	program, errors := parse_prog_src(t, arena, "")
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(program), 0)
}

@(test)
test_parse_program_missing_newline_between_statements_errors :: proc(t: ^testing.T) {
	// Two statements on the same line with no separator: the first parses
	// fine, then errors on hitting the second 'let' where a newline was
	// expected. Recovery only knows how to sync on a Newline/EOF, and
	// there isn't one anywhere in this input — so the second statement is
	// swallowed by the recovery skip rather than being recovered. This is
	// a known, accepted limitation: the grammar has exactly one statement
	// separator (newline), and the spec never puts two statements on one
	// line, so sync-on-statement-start recovery isn't worth building yet.
	arena := make_test_arena(t)
	defer free_all(arena)

	program, errors := parse_prog_src(t, arena, "let x = 5 let y = 6")
	testing.expect_value(t, len(errors), 1)
	testing.expect_value(t, errors[0].msg, "expected newline after statement")
	testing.expect_value(t, len(program), 1)
}

@(test)
test_parse_program_let_missing_value_errors :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	program, errors := parse_prog_src(t, arena, "let x =")
	testing.expect_value(t, len(errors), 1)
	testing.expect_value(t, errors[0].msg, "expected expression")
}

@(test)
test_parse_program_let_rejects_compound_assign :: proc(t: ^testing.T) {
	// A fresh 'let' declaration has nothing to compound against — only
	// plain '=' is valid after the name, never '+=' or its siblings.
	arena := make_test_arena(t)
	defer free_all(arena)

	_, errors := parse_prog_src(t, arena, "let x += 1")
	testing.expect_value(t, len(errors), 1)
	testing.expect_value(t, errors[0].msg, "expected '=' in let statement")
}

@(test)
test_parse_program_let_missing_ident_errors :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	program, errors := parse_prog_src(t, arena, "let = 5")
	testing.expect_value(t, len(errors), 1)
	testing.expect_value(t, errors[0].msg, "expected identifier after 'let'")
	testing.expect_value(t, errors[0].pos, 4) // the '=' the parser choked on
	testing.expect_value(t, errors[0].len, 1)
}

@(test)
test_parse_program_if_statement :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	program, errors := parse_prog_src(t, arena, "if x > 0\n\tx = 1\nend")
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(program), 1)

	stmt, ok := program[0].(^loomscript.Statement_If)
	testing.expect(t, ok, "expected Statement_If")
	if !ok do return

	cond, ok2 := stmt.cond.(^loomscript.Expression_BinaryOp)
	testing.expect(t, ok2, "expected condition to be Expression_BinaryOp")
	if ok2 {
		testing.expect_value(t, cond.op, loomscript.Token_Kind.Gt)
	}

	testing.expect_value(t, len(stmt.then_body), 1)
	testing.expect(t, stmt.else_body == nil, "expected no else_body")
}

@(test)
test_parse_program_if_else :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	program, errors := parse_prog_src(t, arena, "if x == 0\n\ty = 1\nelse\n\ty = 2\nend")
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(program), 1)

	stmt, ok := program[0].(^loomscript.Statement_If)
	testing.expect(t, ok, "expected Statement_If")
	if !ok do return

	testing.expect_value(t, len(stmt.then_body), 1)
	testing.expect_value(t, len(stmt.else_body), 1)

	_, ok2 := stmt.else_body[0].(^loomscript.Statement_Assignment)
	testing.expect(t, ok2, "expected else body to hold a Statement_Assignment")
}

@(test)
test_parse_program_if_else_if_chain :: proc(t: ^testing.T) {
	// 'else if' is a Statement_If nested in else_body; the whole chain
	// closes on the single trailing 'end', not one per branch.
	arena := make_test_arena(t)
	defer free_all(arena)

	program, errors := parse_prog_src(
		t,
		arena,
		"if x == 0\n\ty = 1\nelse if x == 1\n\ty = 2\nelse\n\ty = 3\nend",
	)
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(program), 1)

	outer, ok := program[0].(^loomscript.Statement_If)
	testing.expect(t, ok, "expected Statement_If")
	if !ok do return
	testing.expect_value(t, len(outer.else_body), 1)

	inner, ok2 := outer.else_body[0].(^loomscript.Statement_If)
	testing.expect(t, ok2, "expected nested Statement_If for 'else if'")
	if !ok2 do return
	testing.expect_value(t, len(inner.then_body), 1)
	testing.expect_value(t, len(inner.else_body), 1)
}

@(test)
test_parse_program_if_else_if_span :: proc(t: ^testing.T) {
	// The outermost node's span runs through the shared closing 'end'
	// (it's the one that actually consumes the token); the nested
	// 'else if' node's span stops at its own body, excluding 'end'.
	arena := make_test_arena(t)
	defer free_all(arena)

	src := "if x == 0\n\ty = 1\nelse if x == 1\n\ty = 2\nelse\n\ty = 3\nend"
	program, errors := parse_prog_src(t, arena, src)
	testing.expect_value(t, len(errors), 0)

	outer, ok := program[0].(^loomscript.Statement_If)
	testing.expect(t, ok, "expected Statement_If")
	if !ok do return
	testing.expect_value(t, outer.span, loomscript.Span{start = 0, end = len(src)})

	inner, ok2 := outer.else_body[0].(^loomscript.Statement_If)
	testing.expect(t, ok2, "expected nested Statement_If for 'else if'")
	if !ok2 do return
	testing.expect_value(t, inner.span.start, 22) // pos of the nested 'if'
	testing.expect(t, inner.span.end < outer.span.end, "nested span must not reach through 'end'")
}

@(test)
test_parse_program_if_missing_end_errors :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	_, errors := parse_prog_src(t, arena, "if x > 0\n\ty = 1")
	testing.expect_value(t, len(errors), 1)
	testing.expect_value(t, errors[0].msg, "expected 'end' to close 'if'")
}

@(test)
test_parse_program_compound_assign_desugars_to_binary_op :: proc(t: ^testing.T) {
	// 'x += 1' must produce the exact same shape as 'x = x + 1': a
	// Statement_Assignment whose value is a BinaryOp with a synthesized
	// Identifier('x') on the left — no dedicated compound-assign node.
	arena := make_test_arena(t)
	defer free_all(arena)

	program, errors := parse_prog_src(t, arena, "x += 1")
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(program), 1)

	stmt, ok := program[0].(^loomscript.Statement_Assignment)
	testing.expect(t, ok, "expected Statement_Assignment")
	if !ok do return
	testing.expect_value(t, stmt.name, "x")

	bin, ok2 := stmt.value.(^loomscript.Expression_BinaryOp)
	testing.expect(t, ok2, "expected value to be Expression_BinaryOp")
	if !ok2 do return
	testing.expect_value(t, bin.op, loomscript.Token_Kind.Plus)

	left, ok3 := bin.left.(^loomscript.Expression_Identifier)
	testing.expect(t, ok3, "expected left operand to be Expression_Identifier")
	if !ok3 do return
	testing.expect_value(t, left.name, "x")
	testing.expect_value(t, left.pos, stmt.pos) // synthesized target reuses the real 'x' token's position

	right, ok4 := bin.right.(^loomscript.Expression_IntLit)
	testing.expect(t, ok4, "expected right operand to be Expression_IntLit")
	if ok4 {
		testing.expect_value(t, right.value, 1)
	}
}

@(test)
test_parse_program_all_compound_assign_operators :: proc(t: ^testing.T) {
	cases := []struct {
		src: string,
		op:  loomscript.Token_Kind,
	}{
		{"x -= 1", loomscript.Token_Kind.Minus},
		{"x *= 1", loomscript.Token_Kind.Mult},
		{"x /= 1", loomscript.Token_Kind.Div},
		{"x //= 1", loomscript.Token_Kind.IntDiv},
		{"x %= 1", loomscript.Token_Kind.Modulo},
	}

	for c in cases {
		arena := make_test_arena(t)

		program, errors := parse_prog_src(t, arena, c.src)
		testing.expect_value(t, len(errors), 0)
		testing.expect_value(t, len(program), 1)

		stmt, ok := program[0].(^loomscript.Statement_Assignment)
		testing.expect(t, ok, "expected Statement_Assignment")
		if ok {
			bin, ok2 := stmt.value.(^loomscript.Expression_BinaryOp)
			testing.expect(t, ok2, "expected value to be Expression_BinaryOp")
			if ok2 {
				testing.expect_value(t, bin.op, c.op)
			}
		}

		free_all(arena)
	}
}
