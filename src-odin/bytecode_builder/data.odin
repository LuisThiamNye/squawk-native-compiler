
SpecialisedNode :: union {
	Node_Do,
	Node_Branch,
	Node_BranchCmp,
	Node_AL2,
	Node_ProcInvoke,
}

NodeJumpExit :: struct {
	jump_id: u16,
}

NodeRetExit :: struct {
	res: u16,
}

NodeType :: struct {
}

Node :: struct {
	type: NodeType,
	using specialisation: SpecialisedNode,
	// one jump or return per terminating branch
	jump_exits: []NodeJumpExit,
	ret_exits: []NodeRetExit,
}

Node_Do :: struct {
	nodes: []Node,
}

Node_Branch :: struct {
	test_node: ^Node,
	then_node: ^Node,
	else_node: ^Node,
}

Branch_Cmp :: enum {
	eq,
	neq,
	gt,
	gte,
	lt,
	lte,
	gtu,
	gteu,
	ltu,
	lteu,
}

Node_BranchCmp :: struct {
	comparison: Branch_Cmp,
	using branch: Node_Branch	
}

AL2_Op :: enum {
	add,
	sub,
	mul,
	div,
	mod,
	and,
	or,
	xor,
	shiftl,
	shiftr,
	ashiftr,

	eq,
	neq,
	gt,
	gte,
	lt,
	lte,
	gtu,
	gteu,
	ltu,
	lteu,
}

Node_AL2 :: struct {
	op: AL2_Op,
	x1_node: ^Node,
	x2_node: ^Node,
}

ProcInfo :: struct {

}

Node_ProcInvoke :: struct {
	proc_info: ^ProcInfo
	arg_nodes: []Node,
}