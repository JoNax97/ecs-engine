package loomscript

Token_Kind :: enum {
	IntLiteral,
	Identifier,
	Let,
	If,
	Else,
	End,
	Plus,
	Minus,
	Mult,
	Assign,
	EqEq,
	NotEq,
	Lt,
	LtEq,
	Gt,
	GtEq,
	LParen,
	RParen,
	Newline,
	EOF,
}

Token :: struct {
	kind: Token_Kind,
	text: string, // raw slice from source, e.g. "42"
	pos:  int,    // byte offset in source, for error messages
}
