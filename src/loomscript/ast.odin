package loomscript

// A program is a flat list of statements; there is no enclosing node.
Program :: []Statement

Statement :: union {
	^Statement_Declaration,
	^Statement_Assignment,
	^Statement_Expression,
}

Statement_Declaration :: struct {
	pos:   int, // pos of 'let'
	name:  string,
	value: Expr,
}

Statement_Assignment :: struct {
	pos:   int, // pos of the identifier
	name:  string,
	value: Expr,
}

Statement_Expression :: struct {
	pos:  int,
	expr: Expr,
}
Expr :: union {
	^Expression_IntLiteral,
	^Expression_BinaryOp,
	^Expression_UnaryOp,
	^Expression_Identifier,
}

Expression_IntLiteral :: struct {
	pos:   int,
	value: int,
}

Expression_BinaryOp :: struct {
	pos:   int, // pos of the operator token
	op:    Token_Kind, // Plus, Minus, Star
	left:  Expr,
	right: Expr,
}

Expression_UnaryOp :: struct {
	pos:     int, // pos of the operator token
	op:      Token_Kind, // Plus, Minus
	operand: Expr,
}

Expression_Identifier :: struct {
	pos:  int,
	name: string,
}
