package main

import "core:fmt"
import "core:os"
import "core:strings"

import "loomscript"

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: loomscript_cli <source>")
		os.exit(1)
	}

	src := strings.join(os.args[1:], " ")
	tokens := loomscript.tokenize(src)

	fmt.println("-- tokens --")
	for tok in tokens {
		fmt.printfln("%-10v %-10q pos=%d", tok.kind, tok.text, tok.pos)
	}

	expr, errors := loomscript.parse(tokens)

	fmt.println("-- ast --")
	fmt.print(loomscript.format_expr(expr))

	if len(errors) > 0 {
		fmt.println("-- errors --")
		for err in errors {
			fmt.printfln("pos=%d: %s", err.pos, err.msg)
		}
		os.exit(1)
	}
}
