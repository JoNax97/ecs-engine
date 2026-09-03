package loomscript

import "core:fmt"
import "core:strings"

// format_expr renders an Expr as an indented tree, for manual inspection
// (CLI dump, test failure output). Not part of the language's I/O surface.
format_expr :: proc(expr: Expr, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	write_expr(&b, expr, 0)
	return strings.to_string(b)
}

@(private)
write_expr :: proc(b: ^strings.Builder, expr: Expr, depth: int) {
	for _ in 0 ..< depth {
		strings.write_string(b, "  ")
	}

	switch node in expr {
	case ^Expr_Int_Lit:
		fmt.sbprintfln(b, "Int_Lit %d (pos=%d)", node.value, node.pos)

	case ^Expr_Binary:
		fmt.sbprintfln(b, "Binary %v (pos=%d)", node.op, node.pos)
		write_expr(b, node.left, depth + 1)
		write_expr(b, node.right, depth + 1)

	case ^Expr_Unary:
		fmt.sbprintfln(b, "Unary %v (pos=%d)", node.op, node.pos)
		write_expr(b, node.operand, depth + 1)

	case nil:
		fmt.sbprintfln(b, "<nil>")
	}
}
