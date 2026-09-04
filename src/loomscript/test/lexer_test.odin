package loomscript_test

import "core:mem"
import "core:mem/virtual"
import "core:testing"

import "../"

make_test_arena :: proc(t: ^testing.T) -> mem.Allocator {
	arena := new(virtual.Arena, context.temp_allocator)
	err := virtual.arena_init_growing(arena)
	testing.expect_value(t, err, virtual.Allocator_Error.None)
	return virtual.arena_allocator(arena)
}

@(test)
test_tokenize_simple_expr :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	tokens := loomscript.tokenize("12 + (3 * 4)", arena)

	expected := []loomscript.Token_Kind{
		.IntLit, .Plus, .LParen, .IntLit, .Mult, .IntLit, .RParen, .EOF,
	}

	testing.expect_value(t, len(tokens), len(expected))
	for kind, i in expected {
		if i >= len(tokens) do break
		testing.expect_value(t, tokens[i].kind, kind)
	}
}

@(test)
test_tokenize_int_lit_text :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	tokens := loomscript.tokenize("42", arena)

	testing.expect_value(t, len(tokens), 2) // Int_Lit + EOF
	testing.expect_value(t, tokens[0].kind, loomscript.Token_Kind.IntLit)
	testing.expect_value(t, tokens[0].text, "42")
	testing.expect_value(t, tokens[0].pos, 0)
}

@(test)
test_tokenize_empty :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	tokens := loomscript.tokenize("", arena)

	testing.expect_value(t, len(tokens), 1) // just EOF
	testing.expect_value(t, tokens[0].kind, loomscript.Token_Kind.EOF)
}

@(test)
test_tokenize_ident :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	tokens := loomscript.tokenize("health_2", arena)

	testing.expect_value(t, len(tokens), 2) // Ident + EOF
	testing.expect_value(t, tokens[0].kind, loomscript.Token_Kind.Identifier)
	testing.expect_value(t, tokens[0].text, "health_2")
}

@(test)
test_tokenize_let_keyword :: proc(t: ^testing.T) {
	// "let" is a keyword, distinct from an identifier that merely starts
	// with the same letters ("letter" must stay an Ident).
	arena := make_test_arena(t)
	defer free_all(arena)

	tokens := loomscript.tokenize("let letter", arena)

	testing.expect_value(t, len(tokens), 3) // Let, Ident, EOF
	testing.expect_value(t, tokens[0].kind, loomscript.Token_Kind.Let)
	testing.expect_value(t, tokens[1].kind, loomscript.Token_Kind.Identifier)
	testing.expect_value(t, tokens[1].text, "letter")
}

@(test)
test_tokenize_assign :: proc(t: ^testing.T) {
	arena := make_test_arena(t)
	defer free_all(arena)

	tokens := loomscript.tokenize("x = 5", arena)

	expected := []loomscript.Token_Kind{
		.Identifier, .Assign, .IntLit, .EOF,
	}
	testing.expect_value(t, len(tokens), len(expected))
	for kind, i in expected {
		if i >= len(tokens) do break
		testing.expect_value(t, tokens[i].kind, kind)
	}
}

@(test)
test_tokenize_division_operators :: proc(t: ^testing.T) {
	// '/' and '//' must stay distinct, and greedily prefer the longer form
	// ('//' over two '/' tokens).
	arena := make_test_arena(t)
	defer free_all(arena)

	tokens := loomscript.tokenize("a / b // c % d", arena)

	expected := []loomscript.Token_Kind{
		.Identifier, .Div, .Identifier, .IntDiv, .Identifier, .Modulo, .Identifier, .EOF,
	}

	testing.expect_value(t, len(tokens), len(expected))
	for kind, i in expected {
		if i >= len(tokens) do break
		testing.expect_value(t, tokens[i].kind, kind)
	}
}

@(test)
test_tokenize_comparison_operators :: proc(t: ^testing.T) {
	// '=' vs '==' and '!' + '=' (there is no bare '!') must resolve to
	// distinct single tokens, same greedy-longest-match rule as division.
	arena := make_test_arena(t)
	defer free_all(arena)

	tokens := loomscript.tokenize("a == b != c < d <= e > f >= g", arena)

	expected := []loomscript.Token_Kind{
		.Identifier, .Eq,
		.Identifier, .Neq,
		.Identifier, .Lt,
		.Identifier, .LtEq,
		.Identifier, .Gt,
		.Identifier, .GtEq,
		.Identifier, .EOF,
	}

	testing.expect_value(t, len(tokens), len(expected))
	for kind, i in expected {
		if i >= len(tokens) do break
		testing.expect_value(t, tokens[i].kind, kind)
	}
}

@(test)
test_tokenize_token_len_matches_text :: proc(t: ^testing.T) {
	// len is derived from the same start/end offsets as text in every
	// make_token call — spot-check a single-byte and multi-byte token so
	// that invariant has at least one direct assertion.
	arena := make_test_arena(t)
	defer free_all(arena)

	tokens := loomscript.tokenize("+ ==", arena)

	testing.expect_value(t, tokens[0].kind, loomscript.Token_Kind.Plus)
	testing.expect_value(t, tokens[0].len, 1)

	testing.expect_value(t, tokens[1].kind, loomscript.Token_Kind.Eq)
	testing.expect_value(t, tokens[1].len, 2)
}

@(test)
test_tokenize_compound_assign_operators :: proc(t: ^testing.T) {
	// '//=' is three bytes and must not be split into '//' + '=' or
	// '/' + '/='.
	arena := make_test_arena(t)
	defer free_all(arena)

	tokens := loomscript.tokenize("a += b -= c *= d /= e //= f %= g", arena)

	expected := []loomscript.Token_Kind{
		.Identifier, .PlusAssign,
		.Identifier, .MinusAssign,
		.Identifier, .MultAssign,
		.Identifier, .DivAssign,
		.Identifier, .IntDivAssign,
		.Identifier, .ModuloAssign,
		.Identifier, .EOF,
	}

	testing.expect_value(t, len(tokens), len(expected))
	for kind, i in expected {
		if i >= len(tokens) do break
		testing.expect_value(t, tokens[i].kind, kind)
	}

	int_div_assign := tokens[9]
	testing.expect_value(t, int_div_assign.text, "//=")
	testing.expect_value(t, int_div_assign.len, 3)
}

@(test)
test_tokenize_newline_is_significant :: proc(t: ^testing.T) {
	// Unlike other whitespace, '\n' must survive as its own token —
	// it is the statement separator.
	arena := make_test_arena(t)
	defer free_all(arena)

	tokens := loomscript.tokenize("1\n2", arena)

	expected := []loomscript.Token_Kind{
		.IntLit, .Newline, .IntLit, .EOF,
	}
	testing.expect_value(t, len(tokens), len(expected))
	for kind, i in expected {
		if i >= len(tokens) do break
		testing.expect_value(t, tokens[i].kind, kind)
	}
}
