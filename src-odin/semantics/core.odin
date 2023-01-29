package semantics

import "../ast"
import "core:fmt"
import "core:mem"
import "../numbers"

AstNode :: ast.AstNode

SpecialFormTag :: enum {
	doblock,
	assign,
	let,
	ifbranch,
	jumppad,
	equal,
	goto,
}

Local :: struct {
	spec: ^Spec,
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
	Ana_Do,
	Ana_Let,
	Ana_LocalUse,
	Ana_If,
	Ana_Assign,
	Ana_Jumppad,
	Ana_Goto,
}

AstStackFrame :: struct {
	ast: ^AstNode,
	analyser: NodeAnalyser,
	ret_spec: Spec,
}

JumpTarget :: struct {
	data: int,
}

SemCtx :: struct {
	sf_map: map[string]SpecialFormTag,
	scope_stack: [dynamic]ScopeStackFrame,
	ast_stack: []AstStackFrame,
	ast_stack_endx: int,
	latest_semnode: SemNode,
	jump_targets: map[string]^JumpTarget,
}

make_default_sf_map :: proc() -> map[string]SpecialFormTag {
	m := make(map[string]SpecialFormTag)
	m["="] = .equal
	m["do"] = .doblock
	m["let"] = .let
	m["if"] = .ifbranch
	m["set"] = .assign
	m["jumppad"] = .jumppad
	m["goto"] = .goto
	return m
}

// push_special_form :: proc(sem: ^SemCtx, name: string, )

make_semctx :: proc(astnode: ^AstNode, max_depth: int) -> ^SemCtx {
	c := new(SemCtx)
	stack := make([]AstStackFrame, max_depth+1)
	scope_stack := make([dynamic]ScopeStackFrame, 0)
	c^ = {scope_stack=scope_stack, ast_stack=stack, sf_map=make_default_sf_map(),
		jump_targets=make(map[string]^JumpTarget)}
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
				switch sf {
				case .equal:
					return Ana_Equal{cursor=1}
				case .doblock:
					return Ana_Do{cursor=1}
				case .let:
					return Ana_Let{cursor=1}
				case .assign:
					return Ana_Assign{cursor=1}
				case .ifbranch:
					return Ana_If{cursor=1}
				case .jumppad:
					return Ana_Jumppad{cursor=1}
				case .goto:
					return Ana_Goto{cursor=1}
				case:
					panic("unreachable")
				}
			} else {
				fmt.panicf("unknown symbol %v", child1.token)
			}
		case:
			panic("unsupported list 1")
		}
	case .symbol:
		token := ast.token
		ss_loop: for i:=len(ctx.scope_stack)-1; i>=0; i-=1 {
			scope_frame := ctx.scope_stack[i]
			bindings := scope_frame.bindings
			for j:=len(bindings)-1; j>=0; j-=1 {
				sym := bindings[j].symbol
				if sym == token {
					return Ana_LocalUse{local=bindings[j].local}
				}
			}
		}
		fmt.panicf("unresolved symbol : %v\n", ast.token)
	case .number:
		return Ana_Number{ast=ast}
	case:
		fmt.panicf("unsupported: %v", ast.tag)
	}
	// panic("!!")
}

step_push_node :: proc(ctx: ^SemCtx, ast: ^AstNode, ret_spec: Spec) -> Message {
	ana := initial_ana_for_ast_node(ctx, ast)
	frame := AstStackFrame{ast=ast,analyser=ana, ret_spec=ret_spec}
	next_idx := ctx.ast_stack_endx
	ctx.ast_stack[next_idx] = frame
	ctx.ast_stack_endx = next_idx+1
	return Msg_Analyse{}
}

sem_complete_node :: proc(ctx: ^SemCtx, node: SemNode) {
	ctx.latest_semnode=node
	ctx.ast_stack_endx -= 1
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
	variant: union {Sem_Equal, Sem_Number, Sem_Do, Sem_Let, Sem_LocalUse, Sem_If, Sem_Assign, Sem_Jumppad, Sem_Goto},
}

sem_step :: proc(using sem: ^SemCtx) -> Message {
	ast_stack_cursor := ast_stack_endx-1
	frame := &ast_stack[ast_stack_cursor]
	analyser := frame.analyser
	// fmt.println(analyser)
	switch _ana in analyser {
	case Ana_Equal:
		return step_equal(sem, frame)
	case Ana_Number:
		return step_number(sem, frame)
	case Ana_Do:
		return step_doblock(sem, frame)
	case Ana_Let:
		return step_let(sem, frame)
	case Ana_LocalUse:
		return step_localuse(sem, frame)
	case Ana_If:
		return step_ifbranch(sem, frame)
	case Ana_Assign:
		return step_assign(sem, frame)
	case Ana_Jumppad:
		return step_jumppad(sem, frame)
	case Ana_Goto:
		return step_goto(sem, frame)
	}
	fmt.panicf("invalid analyser at stack idx %v for frame %v",
	ast_stack_cursor, frame)
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
	ana := &analyser.(Ana_Equal)
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


Sem_Do :: struct {
	children: []SemNode,
}

Ana_Do :: struct {
	cursor: int,
	result: ^Sem_Do,
}

step_doblock :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_Do)
	if ana.cursor == 1 { // init
		ana.result = new(Sem_Do)
		ana.result.children = make([]SemNode, len(ast.children)-1)
	} else {
		ana.result.children[ana.cursor-2]=sem.latest_semnode
	}
	if ana.cursor >= len(ast.children) {
		if ana.cursor < 2 {
			panic("insufficient input to 'do'")
		}
		spec := ana.result.children[len(ana.result.children)-1].spec
		return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
	}
	idx := ana.cursor
	ana.cursor = idx+1
	child_ret_spec : Spec
	if ana.cursor == len(ast.children) {
		child_ret_spec = frame.ret_spec
	} else {
		child_ret_spec = void_spec
	}
	return Msg_AnalyseChild{ast=&ast.children[idx], ret_spec=child_ret_spec}
}


Sem_Let :: struct {
	local: ^Local,
	val_node: ^SemNode,
}

Ana_Let :: struct {
	cursor: int,
	local_name: string,
	result: ^Sem_Let,
}

step_let :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_Let)
	if ana.cursor == 1 { // init
		ana.result = new(Sem_Let)
		ana.result.val_node = new(SemNode)
		if len(ast.children) > 3 {
			panic("too many children to 'let'")
		}
		if len(ast.children) < 3 {
			panic("too few children to 'let'")
		}
	}
	idx := ana.cursor
	ana.cursor = idx+1

	if idx == 1 { // sym
		astnode := ast.children[idx]
		if astnode.tag != .symbol {
			panic("'let' must have symbol")
		}
		ana.local_name = astnode.token
		return Msg_Analyse{}
	} else if idx == 2 { // valexpr
		return Msg_AnalyseChild{ast=&ast.children[idx], ret_spec=Spec_NonVoid{}}
	} else {
		ana.result.val_node^ = sem.latest_semnode
		spec := ana.result.val_node.spec

		local := new(Local)
		local.spec = spec
		ana.result.local = local

		bindings := make([]ScopeBinding, 1)
		bindings[0] = ScopeBinding{symbol=ana.local_name, local=local}
		scope_frame := ScopeStackFrame{bindings=bindings}
		append(&sem.scope_stack, scope_frame)

		return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
	}
}


Sem_Assign :: struct {
	local: ^Local,
	val_node: ^SemNode,
}

Ana_Assign :: struct {
	cursor: int,
	result: ^Sem_Assign,
}

step_assign :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_Assign)
	if ana.cursor == 1 { // init
		ana.result = new(Sem_Assign)
		ana.result.val_node = new(SemNode)
		if len(ast.children) > 3 {
			panic("too many children to 'set'")
		}
		if len(ast.children) < 3 {
			panic("too few children to 'set'")
		}
	}
	idx := ana.cursor
	ana.cursor = idx+1

	if idx == 1 { // sym
		astnode := ast.children[idx]
		if astnode.tag != .symbol {
			panic("'set' must have symbol")
		}
		token := astnode.token
		ss_loop: for i:=len(sem.scope_stack)-1; i>=0; i-=1 {
			scope_frame := sem.scope_stack[i]
			bindings := scope_frame.bindings
			for j:=len(bindings)-1; j>=0; j-=1 {
				sym := bindings[j].symbol
				if sym == token {
					ana.result.local = bindings[j].local
					return Msg_Analyse{}
				}
			}
		}
		panic("could not resolve local to 'set'")		
	} else if idx == 2 { // valexpr
		return Msg_AnalyseChild{ast=&ast.children[idx], ret_spec=Spec_NonVoid{}}
	} else {
		ana.result.val_node^ = sem.latest_semnode
		spec := &void_spec

		return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
	}
}


Sem_LocalUse :: struct {
	local: ^Local,
}

Ana_LocalUse :: struct {
	local: ^Local,
}

step_localuse :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_LocalUse)
	local := ana.local

	sem := Sem_LocalUse{local=local}
	return Msg_DoneNode{node={spec=local.spec, variant=sem}}
}


Sem_Number :: struct {
	signedP: bool,
	value: i64,
}

Ana_Number :: struct {ast: ^AstNode}

step_number :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_Number)
	token := ana.ast.token

	// TODO improve
	_negP := token[0]=='-'
	int_mag := numbers.int_str_to_mag(u64, u128, token, 10)
	value : i64 = 0
	if len(int_mag)>0 {
		value = cast(i64) int_mag[0]
	}
	sem := Sem_Number{signedP=true, value=value}

	spec := new(Spec)
	spec^ = Spec_Number{}
	return Msg_DoneNode{node={spec=spec, variant=sem}}
}


Sem_If :: struct {
	test_node: ^SemNode,
	then_node: ^SemNode,
	else_node: ^SemNode,
}

Ana_If :: struct {
	cursor: int,
	result: ^Sem_If,
}

step_ifbranch :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_If)
	if ana.cursor == 1 { // init
		ana.result = new(Sem_If)
		ana.result.test_node = new(SemNode)
		ana.result.then_node = new(SemNode)
		ana.result.else_node = new(SemNode)
	}
	
	idx := ana.cursor
	ana.cursor = idx+1

	child_ret_spec : Spec
	if idx==1 { // test
		child_ret_spec = boolean_spec
	} else if idx==2 { // then
		ana.result.test_node^=sem.latest_semnode
		child_ret_spec = frame.ret_spec
	} else if idx==3 { // else
		ana.result.then_node^=sem.latest_semnode
		child_ret_spec = frame.ret_spec
	} else {
		ana.result.else_node^=sem.latest_semnode
		if ana.cursor <= 2 {
			panic("insufficient input to 'do'")
		}
		// TODO
		spec, ok := spec_coerce_to_equal_types({ana.result.then_node.spec, ana.result.else_node.spec})
		if !ok {
			panic("could not coerce specs of 'if'")
		}
		return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
	}

	return Msg_AnalyseChild{ast=&ast.children[idx], ret_spec=child_ret_spec}
}


Sem_Jumppad :: struct {
	init_node: ^SemNode, // nilable
	dest_names: []string,
	dest_nodes: []SemNode,
	jump_targets: []JumpTarget,
}

Ana_Jumppad :: struct {
	cursor: int,
	result: ^Sem_Jumppad,
}

step_jumppad :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_Jumppad)
	idx := ana.cursor
	if idx == 1 {
		ndests := (len(ast.children)-1)/2
		ana.result = new(Sem_Jumppad)
		ana.result.dest_names = make([]string, ndests)
		ana.result.dest_nodes = make([]SemNode, ndests)
		ana.result.jump_targets = make([]JumpTarget, ndests)

		has_init := len(ast.children)&1 == 0
		if has_init {idx+=1}

		// read labels
		i_dest := 0
		for i := idx; i<len(ast.children); i+=2 {
			target_label := ast.children[i]
			if target_label.tag != .keyword {
				fmt.panicf("target label at idx %v must be a keyword, got %v", i, target_label)
			}
			ana.result.dest_names[i_dest]=target_label.token
			target := &ana.result.jump_targets[i_dest]
			target^ = JumpTarget{}
			sem.jump_targets[target_label.token]=target

			i_dest += 1
		}

		// init code
		if len(ast.children)&1 == 0 {
			return Msg_AnalyseChild{ast=&ast.children[1], ret_spec=frame.ret_spec}
		}
		idx += 1
	}
	ana.cursor = idx+2

	if idx == 3 { // after init
		ana.result.init_node = new(SemNode)
		ana.result.init_node^=sem.latest_semnode
	} else if idx > 3 { // after destination
		ana.result.dest_nodes[idx/2 -2]=sem.latest_semnode
	}

	if idx >= len(ast.children) { // complete
		specs := make([]^Spec, len(ana.result.dest_nodes))
		for sn, i in ana.result.dest_nodes {
			specs[i]=sn.spec
		}
		spec, ok := spec_coerce_to_equal_types(specs)
		if !ok {
			panic("could not coerce specs of 'jumppad'")
		}
		return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
	}
	
	return Msg_AnalyseChild{ast=&ast.children[idx], ret_spec=frame.ret_spec}
}


Sem_Goto :: struct {
	target: ^JumpTarget,
}

Ana_Goto :: struct {
	cursor: int,
	result: ^Sem_Goto,
}

step_goto :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_Goto)
	ana.result = new(Sem_Goto)

	if len(ast.children) != 2 {
		panic("wrong number of children to 'goto'")
	}

	target_label := ast.children[1]
	if target_label.tag != .keyword {
		panic("target label must be a keyword")
	}

	target := sem.jump_targets[target_label.token]
	if target == nil {
		fmt.panicf("could not resolve jump target: '%v'", target_label.token)
	}
	ana.result.target=target
	spec := new(Spec)
	spec^ = Spec_Jump{}
	return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
}