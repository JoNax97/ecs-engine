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

	value, ok2 := stmt.value.(^loomscript.Expression_IntLiteral)
	testing.expect(t, ok2, "expected Expression_IntLiteral")
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
test_parse_program_let_missing_ident_errors :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	program, errors := parse_prog_src(t, arena, "let = 5")
	testing.expect_value(t, len(errors), 1)
	testing.expect_value(t, errors[0].msg, "expected identifier after 'let'")
}
