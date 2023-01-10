package semantics

import "../ast"
AstNode :: ast.AstNode

SpecialFormTag :: enum {
	do,
	assign,
	let,
	ifbranch,
}

Local :: struct {

}

ScopeBinding :: struct {
	symbol: string,
	local: ^Local,
}

ScopeStackFrame :: struct {
	bindings: []ScopeBinding,
}

NodeAnalyser :: union {

}

AstStackFrame :: struct {
	ast: ^AstNode,
	analyser: NodeAnalyser,
}

SemCtx :: struct {
	sf_map: map[string]SpecialFormTag,
	ret_spec: Spec,
	scope_stack: ^[dynamic]ScopeStackFrame,
	ast_stack: []AstStackFrame,
	ast_stack_cursor: int,
}

make_semctx :: proc(astnode: ^AstNode, max_depth: int) -> ^SemCtx {
	c := new(SemCtx)
	stack := make([]AstStackFrame, max_depth)
	stack[0] = {ast=astnode}
	c = {scope_stack=[dynamic]ScopeStackFrame{}, ast_stack=stack}
	return c
}

Message :: union {

}

init_ana_for_ast_node :: proc(ctx: ^SemCtx, ast: ^AstNode) -> NodeAnalyser {
	#partial switch ast.tag {
	case .list:
		if 0==len(ast.children) {panic("no list children")}
		child1 := ast.children[0]
		#partial switch child1.tag {
		case .symbol:
			if sf, ok := ctx.sf_map[child1.token]; ok {
				switch sf {
				case .equal:
					return Ana_Equal{cursor=1}
				}
			} else {
				panic("unknown symbol")
			}
		case:
			panic("unsupported list 1")
		}
	// case .symbol:
	case:
		panic("unsupported")
	}
}

sem_step :: proc(using sem: ^SemCtx) -> Message {
	frame := ast_stack[len(ast_stack)-1]
	astnode := frame.ast

} 
