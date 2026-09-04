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

// format_program renders a Program as a flat list of statement subtrees.
format_program :: proc(program: Program, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	for stmt in program {
		write_statement(&b, stmt, 0)
	}
	return strings.to_string(b)
}

@(private)
write_statement :: proc(b: ^strings.Builder, stmt: Statement, depth: int) {
	for _ in 0 ..< depth {
		strings.write_string(b, "  ")
	}

	switch node in stmt {
		case ^Statement_Declaration:
			fmt.sbprintfln(b, "Let %s", node.name)
			write_expr(b, node.value, depth + 1)

		case ^Statement_Assignment:
			fmt.sbprintfln(b, "Assign %s", node.name)
			write_expr(b, node.value, depth + 1)

		case ^Statement_Expression:
			fmt.sbprintfln(b, "Expression")
			write_expr(b, node.expr, depth + 1)

		case ^Statement_If:
			fmt.sbprintfln(b, "If")
			write_expr(b, node.cond, depth + 1)
			for s in node.then_body {
				write_statement(b, s, depth + 1)
			}
			if node.else_body != nil {
				for _ in 0 ..< depth {
					strings.write_string(b, "  ")
				}
				fmt.sbprintfln(b, "Else")
				for s in node.else_body {
					write_statement(b, s, depth + 1)
				}
			}

		case nil:
			fmt.sbprintfln(b, "<nil>")
	}
}

@(private)
write_expr :: proc(b: ^strings.Builder, expr: Expr, depth: int) {
	for _ in 0 ..< depth {
		strings.write_string(b, "  ")
	}

	switch node in expr {
	case ^Expression_IntLit:
		fmt.sbprintfln(b, "IntLit %d", node.value)

	case ^Expression_BinaryOp:
		fmt.sbprintfln(b, "Binary %v", node.op)
		write_expr(b, node.left, depth + 1)
		write_expr(b, node.right, depth + 1)

	case ^Expression_UnaryOp:
		fmt.sbprintfln(b, "Unary %v", node.op)
		write_expr(b, node.operand, depth + 1)

	case ^Expression_Identifier:
		fmt.sbprintfln(b, "Identifier %s", node.name)

	case nil:
		fmt.sbprintfln(b, "<nil>")
	}
}
