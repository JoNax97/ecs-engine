package main

import "core:fmt"
import "core:os"
import "core:sys/posix"

import "loomscript"

main :: proc() {
	src, ok := read_source()
	if !ok {
		fmt.eprintln("usage: loomscript_cli <file>   (or pipe source on stdin)")
		os.exit(1)
	}

	fmt.println("-- source --")
	fmt.println(src)

	tokens := loomscript.tokenize(src)

	fmt.println("-- tokens --")
	for tok in tokens {
		fmt.printfln("%-10v %-10q pos=%d len=%d", tok.kind, tok.text, tok.pos, tok.len)
	}

	program, errors := loomscript.parse(tokens)

	fmt.println("-- ast --")
	fmt.print(loomscript.format_program(program))

	if len(errors) > 0 {
		fmt.println("-- errors --")
		for err in errors {
			fmt.printfln("pos=%d len=%d: %s", err.pos, err.len, err.msg)
		}
		os.exit(1)
	}
}

// read_source reads a file named on argv[1], or the whole of stdin when no
// argument is given (so both `loomscript_cli file.lms` and
// `echo '...' | loomscript_cli` / `loomscript_cli < file.lms` work).
read_source :: proc() -> (src: string, ok: bool) {
	if len(os.args) >= 2 {
		data, err := os.read_entire_file(os.args[1], context.allocator)
		if err != nil {
			fmt.eprintfln("error: could not read '%s': %v", os.args[1], err)
			return "", false
		}
		return string(data), true
	}

	// With no file argument, stdin must be piped/redirected data, not an
	// interactive terminal — otherwise read_entire_file blocks waiting for
	// input that will never come (no EOF until the user hits Ctrl+D, which
	// looks like a hang, not an error).
	if posix.isatty(posix.FD(os.fd(os.stdin))) {
		return "", false
	}

	data, err := os.read_entire_file(os.stdin, context.allocator)
	if err != nil {
		fmt.eprintfln("error: could not read stdin: %v", err)
		return "", false
	}
	return string(data), true
}
