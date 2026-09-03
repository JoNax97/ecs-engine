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
		.Int_Lit, .Plus, .LParen, .Int_Lit, .Star, .Int_Lit, .RParen, .EOF,
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
	testing.expect_value(t, tokens[0].kind, loomscript.Token_Kind.Int_Lit)
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
