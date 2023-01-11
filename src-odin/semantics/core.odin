package semantics

import "../ast"
import "core:fmt"
AstNode :: ast.AstNode

SpecialFormTag :: enum {
	// do,
	assign,
	let,
	ifbranch,
	equal,
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
	Ana_Equal,
	Ana_Number,
}

AstStackFrame :: struct {
	ast: ^AstNode,
	analyser: NodeAnalyser,
	ret_spec: Spec,
}

SemCtx :: struct {
	sf_map: map[string]SpecialFormTag,
	scope_stack: ^[dynamic]ScopeStackFrame,
	ast_stack: []AstStackFrame,
	ast_stack_cursor: int,
	latest_semnode: SemNode,
}

make_default_sf_map :: proc() -> map[string]SpecialFormTag {
	m := make(map[string]SpecialFormTag)
	m["="] = .equal
	return m	
}

make_semctx :: proc(astnode: ^AstNode, max_depth: int) -> ^SemCtx {
	c := new(SemCtx)
	stack := make([]AstStackFrame, max_depth)
	stack[0] = {ast=astnode}
	c^ = {scope_stack=&[dynamic]ScopeStackFrame{}, ast_stack=stack, sf_map=make_default_sf_map()}
	return c
}

initial_ana_for_ast_node :: proc(ctx: ^SemCtx, ast: ^AstNode) -> NodeAnalyser {
	#partial switch ast.tag {
	case .list:
		if 0==len(ast.children) {panic("no list children")}
		child1 := ast.children[0]
		#partial switch child1.tag {
		case .symbol:
			if sf, ok := ctx.sf_map[child1.token]; ok {
				#partial switch sf {
				case .equal:
					return Ana_Equal{cursor=1}
				}
			} else {
				fmt.panicf("unknown symbol %v", child1.token)
			}
		case:
			panic("unsupported list 1")
		}
	// case .symbol:
	case .number:
		return Ana_Number{}
	case:
		fmt.panicf("unsupported: %v", ast.tag)
	}
	panic("!!")
}

step_push_node :: proc(ctx: ^SemCtx, ast: ^AstNode, ret_spec: Spec) -> Message {
	ana := initial_ana_for_ast_node(ctx, ast)
	frame := AstStackFrame{ast=ast,analyser=ana, ret_spec=ret_spec}
	ctx.ast_stack[ctx.ast_stack_cursor] = frame
	ctx.ast_stack_cursor += 1
	return Msg_Analyse{}
}

sem_complete_node :: proc(ctx: ^SemCtx, node: SemNode) {
	ctx.latest_semnode=node
	ctx.ast_stack_cursor -= 1
}

Message :: union {
	Msg_DoneNode,
	Msg_AnalyseChild,
	Msg_Analyse,
}

Msg_DoneNode :: struct {
	node: SemNode,
}

Msg_AnalyseChild :: struct {
	ast: ^AstNode,
	ret_spec: Spec,
}

Msg_Analyse :: struct {}

SemNode :: struct {
	spec: ^Spec,
	variant: union {Sem_Equal, Sem_Number},
}

sem_step :: proc(using sem: ^SemCtx) -> Message {
	frame := ast_stack[len(ast_stack)-1]
	analyser := frame.analyser
	switch _ana in analyser {
	case Ana_Equal:
		return step_equal(sem, &frame)
	case Ana_Number:
		return step_number(sem, &frame)
	}
	panic("invalid ana")
} 


Sem_Equal :: struct {
	args: []SemNode,
}

Ana_Equal :: struct {
	cursor: int,
	result: ^Sem_Equal,
}

get_bool_type :: proc(sem: ^SemCtx) -> TypeInfo {
	t := new(TypeInfo)
	t^ = Type_Integer{nbits=1}
	return Type_Alias{backing_type=t}
}

step_equal :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := analyser.(Ana_Equal)
	if ana.cursor == 1 { // init
		ana.result = new(Sem_Equal)
		ana.result.args = make([]SemNode, len(ast.children)-1)
	} else {
		ana.result.args[ana.cursor-2]=sem.latest_semnode
	}
	if ana.cursor >= len(ast.children) { // end
		if ana.cursor < 3 {
			panic("insufficient input")
		} else {
			specs := make([]^Spec, len(ana.result.args))
			for semnode, i in ana.result.args {
				specs[i] = semnode.spec
			}
			spec_coerce_to_equal_types(specs)
			spec := new(Spec)
			spec^ = Spec_Fixed{typeinfo=get_bool_type(sem)}
			variant := ana.result^
			return Msg_DoneNode{node={spec=spec, variant=variant}}
		}
	}
	idx := ana.cursor
	ana.cursor = idx+1
	trait_equal_id :: 0
	return Msg_AnalyseChild{ast=&ast.children[idx], ret_spec=Spec_Trait{id=trait_equal_id}}
}

Sem_Number :: struct {}

Ana_Number :: struct {}

step_number :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	spec := new(Spec)
	spec^ = Spec_Number{}
	return Msg_DoneNode{node={spec=spec}}
}