package loomscript

Token_Kind :: enum {
	IntLit,
	Identifier,
	Let,
	If,
	Else,
	End,
	Plus,
	Minus,
	Mult,
	Div,
	IntDiv,
	Modulo,
	Assign,
	PlusAssign,
	MinusAssign,
	MultAssign,
	DivAssign,
	IntDivAssign,
	ModuloAssign,
	Eq,
	Neq,
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
	len:  int,    // byte length in source; pos+len spans the token, for underlining
}
