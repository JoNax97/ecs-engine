package loomscript

Token_Kind :: enum {
	Int_Lit,
	Plus,
	Minus,
	Star,
	LParen,
	RParen,
	EOF,
}

Token :: struct {
	kind: Token_Kind,
	text: string, // raw slice from source, e.g. "42"
	pos:  int,    // byte offset in source, for error messages
}
