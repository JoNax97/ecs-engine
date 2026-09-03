package loomscript

Expr :: union {
	^Expr_Int_Lit,
	^Expr_Binary,
	^Expr_Unary,
}

Expr_Int_Lit :: struct {
	pos:   int,
	value: int,
}

Expr_Binary :: struct {
	pos:   int, // pos of the operator token
	op:    Token_Kind, // Plus, Minus, Star
	left:  Expr,
	right: Expr,
}

Expr_Unary :: struct {
	pos:     int, // pos of the operator token
	op:      Token_Kind, // Plus, Minus
	operand: Expr,
}
