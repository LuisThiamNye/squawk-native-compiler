package semantics

import "../ast"
import "core:fmt"
import "core:mem"
import "core:strconv"
import "../numbers"
import "core:strings"

AstNode :: ast.AstNode

SpecialFormTag :: enum {
	doblock,
	assign,
	access_path,
	let,
	ifbranch,
	jumppad,
	equal,
	add,
	goto,
	defn,
	defstruct,
	foreign_lib,
	foreign_members,
	use,
	caster,

	mem_copy,
}

NodeAnalyser :: union {
	Ana_Equal,
	Ana_Binop,
	Ana_Number,
	Ana_String,
	Ana_Do,
	Ana_Let,
	Ana_LocalUse,
	Ana_If,
	Ana_Assign,
	Ana_Jumppad,
	Ana_Goto,
	Ana_Defn,
	Ana_Defstruct,
	Ana_Invoke,
	Ana_Intrinsic,
	Ana_UnresolvedList,
	Ana_ForeignLib,
	Ana_ForeignMembers,
	Ana_Use,
	Ana_Cast,
	Ana_AccessPath,
}

make_default_sf_map :: proc() -> map[string]SpecialFormTag {
	m := make(map[string]SpecialFormTag)
	m["="] = .equal
	m["+"] = .add
	m["do"] = .doblock
	m["let"] = .let
	m["if"] = .ifbranch
	m["set"] = .assign
	m["jumppad"] = .jumppad
	m["goto"] = .goto
	m["defn"] = .defn
	m["defstruct"] = .defstruct
	m["def-foreign-lib"] = .foreign_lib
	m["declare-foreigns"] = .foreign_members
	m["use"] = .use
	m["cast"] = .caster
	m[":"] = .access_path

	m["memcopy"] = .mem_copy
	return m
}

SemNode_Variant :: union {
	Sem_Equal, Sem_Number, Sem_String, Sem_Do, Sem_Let,
	Sem_LocalUse, Sem_If, Sem_Assign, Sem_Jumppad, Sem_Goto,
	Sem_Defn, Sem_Invoke, Sem_ForeignLib, Sem_ForeignMembers,
	Sem_Defstruct, Sem_Use, Sem_Cast, Sem_Binop, Sem_AccessPath,
	Sem_Intrinsic,
}

Local :: struct {
	spec: ^Spec,
	decl_tag: enum {let, param,},
}

ScopeBinding :: struct {
	symbol: string,
	tag: enum {local, alias},
	local: ^Local,
	alias: struct {binding: ^ScopeBinding, member_name: string},
}

ScopeStackFrame :: struct {
	bindings: []ScopeBinding,
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
	compilation_unit: ^CompilationUnit,
	compilation_node: ^CompilationNode,
	unresolved_symbol: string,
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

initial_ana_for_ast_node :: proc(ctx: ^SemCtx, ast: ^AstNode) ->
	(ret_ana: NodeAnalyser, ret_msg: Message) {
	#partial switch ast.tag {
	case .list:
		if 0==len(ast.children) {panic("no list children")}
		child1 := ast.children[0]
		#partial switch child1.tag {
		case .symbol:
			if sf, ok := ctx.sf_map[child1.token]; ok {
				switch sf {
				case .equal:
					ret_ana = Ana_Equal{cursor=1}
				case .add:
					ret_ana = Ana_Binop{cursor=1, op=.add}
				case .doblock:
					ret_ana =  Ana_Do{cursor=1}
				case .let:
					ret_ana =  Ana_Let{cursor=1}
				case .assign:
					ret_ana =  Ana_Assign{cursor=1}
				case .ifbranch:
					ret_ana =  Ana_If{cursor=1}
				case .jumppad:
					ret_ana =  Ana_Jumppad{cursor=1}
				case .goto:
					ret_ana =  Ana_Goto{cursor=1}
				case .defn:
					ret_ana =  Ana_Defn{cursor=1}
				case .defstruct:
					ret_ana =  Ana_Defstruct{cursor=1}
				case .foreign_lib:
					ret_ana =  Ana_ForeignLib{cursor=1}
				case .foreign_members:
					ret_ana =  Ana_ForeignMembers{cursor=1}
				case .use:
					ret_ana =  Ana_Use{cursor=1}
				case .caster:
					ret_ana =  Ana_Cast{cursor=1}
				case .access_path:
					ret_ana =  Ana_AccessPath{cursor=1}

				case .mem_copy:
					ret_ana =  Ana_Intrinsic{cursor=1, op=.mem_copy}
				case:
					panic("unreachable")
				}
				return
			} else {
				decl, found := ctx.compilation_unit.symbol_map[child1.token]
				if !found {
					return Ana_UnresolvedList{}, Msg_ResolveSymbol{name=child1.token, ctx=.invoke}
				}
				#partial switch decl.tag {
				case .procedure:
					prc := decl.procedure
					ret_ana = Ana_Invoke{cursor=1, proc_decl={species=.procedure, proc_decl={procedure=prc^}}}
					return
				case .foreign_proc:
					prc := decl.foreign_proc
					ret_ana = Ana_Invoke{cursor=1, proc_decl={species=.foreign_proc, proc_decl={foreign_proc=prc^}}}
					return
				case: panic("invalid type for first list child")
				}
			}
		case:
			panic("unsupported first child in list")
		}
	case .symbol:
		token := ast.token

		slash_idx := strings.index_byte(token, '/')
		members : []string
		target_sym : string
		if slash_idx>=0 {
			if slash_idx==len(token)-1 {
				panic("delimiter can't be at the end")
			}
			target_sym = token[0:slash_idx]
			members = make([]string, 1)
			members[0] = token[slash_idx+1:]
		} else {
			target_sym = token
		}

		ss_loop: for i:=len(ctx.scope_stack)-1; i>=0; i-=1 {
			scope_frame := ctx.scope_stack[i]
			bindings := scope_frame.bindings
			for j:=len(bindings)-1; j>=0; j-=1 {
				sym := bindings[j].symbol
				if sym == target_sym {
					ret_ana = Ana_LocalUse{local=bindings[j].local, members=members}
					return
				}
			}
		}
		fmt.panicf("unresolved symbol : %v\n", token)
	case .number:
		ret_ana = Ana_Number{ast=ast}
		return
	case .string:
		ret_ana = Ana_String{ast=ast}
		return
	case:
		fmt.panicf("unsupported node type: %v", ast.tag)
	}
	// panic("!!")
}

step_push_node :: proc(ctx: ^SemCtx, ast: ^AstNode, ret_spec: Spec) -> (_msg: Message, err: bool) {
	ana, msg0 := initial_ana_for_ast_node(ctx, ast)
	// if msg0 != nil {return msg0, true}
	frame := AstStackFrame{ast=ast,analyser=ana, ret_spec=ret_spec}
	next_idx := ctx.ast_stack_endx
	ctx.ast_stack[next_idx] = frame
	ctx.ast_stack_endx = next_idx+1
	if msg0 != nil {return msg0, false}
	return Msg_Analyse{}, false
}

sem_complete_node :: proc(ctx: ^SemCtx, node: SemNode) {
	ctx.latest_semnode=node
	ctx.ast_stack_endx -= 1
}

Message :: union {
	Msg_DoneNode,
	Msg_AnalyseChild,
	Msg_Analyse,
	Msg_ResolveSymbol,
}

Msg_DoneNode :: struct {
	node: SemNode,
}

Msg_AnalyseChild :: struct {
	ast: ^AstNode,
	ret_spec: Spec,
}

Msg_Analyse :: struct {}

Msg_ResolveSymbol :: struct {
	name: string,
	ctx: enum {floating=0, invoke},
}

SemNode :: struct {
	spec: ^Spec,
	variant: SemNode_Variant,
}

sem_step :: proc(using sem: ^SemCtx) -> Message {
	ast_stack_cursor := ast_stack_endx-1
	frame := &ast_stack[ast_stack_cursor]
	analyser := frame.analyser
	// fmt.println(analyser)
	switch _ana in analyser {
	case Ana_Equal:
		return step_equal(sem, frame)
	case Ana_Binop:
		return step_binop(sem, frame)
	case Ana_Number:
		return step_number(sem, frame)
	case Ana_String:
		return step_string(sem, frame)
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
	case Ana_Defn:
		return step_defn(sem, frame)
	case Ana_Defstruct:
		return step_defstruct(sem, frame)
	case Ana_Invoke:
		return step_invoke(sem, frame)
	case Ana_UnresolvedList:
		return step_unresolved_list(sem, frame)
	case Ana_ForeignLib:
		return step_foreign_lib(sem, frame)
	case Ana_ForeignMembers:
		return step_foreign_members(sem, frame)
	case Ana_Use:
		return step_use(sem, frame)
	case Ana_Cast:
		return step_cast(sem, frame)
	case Ana_AccessPath:
		return step_access_path(sem, frame)
	case Ana_Intrinsic:
		return step_intrinsic(sem, frame)
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

Binop :: enum {add, sub, mul, div, equal}

Sem_Binop :: struct {
	op: Binop,
	args: []SemNode,
}

Ana_Binop :: struct {
	cursor: int,
	op: Binop,
	result: ^Sem_Binop,
}

step_binop :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_Binop)
	if ana.cursor == 1 {
		ana.result = new(Sem_Binop)
		ana.result.args = make([]SemNode, len(ast.children)-1)
		ana.result.op = ana.op
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
			spec, ok := spec_coerce_to_equal_types(specs)
			if !ok {
				fmt.println(specs)
				panic("could not coerce specs")
			}
			variant := ana.result^
			return Msg_DoneNode{node={spec=spec, variant=variant}}
		}
	}

	idx := ana.cursor
	ana.cursor = idx+1
	trait_invalid :: 0
	return Msg_AnalyseChild{ast=&ast.children[idx], ret_spec=Spec_Trait{id=trait_invalid}}
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
	initialiser_tag: enum {set_value, type_default},
	val_node: ^SemNode,
	typeinfo: ^TypeInfo, // only valid when type_default
}

Ana_Let :: struct {
	cursor: int,
	local_name: string,
	result: ^Sem_Let,
	type_creationP: bool,
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

		// for when initialising a default type
		valexpr := ast.children[idx]
		if valexpr.tag == .symbol && valexpr.token[len(valexpr.token)-1]=='.' {
			typestr := valexpr.token[0:len(valexpr.token)-1]

			ana.result.initialiser_tag=.type_default

			// resolve type
			dt, found := sem.compilation_unit.datatypes_map[typestr]
			if !found {
				panic("could not resolve type for let initialiser")
			}
			typeinfo := &dt.typeinfo
			ana.result.typeinfo = typeinfo
			return Msg_Analyse{}
		}

		return Msg_AnalyseChild{ast=&ast.children[idx], ret_spec=Spec_NonVoid{}}
	} else {
		spec : ^Spec
		switch ana.result.initialiser_tag {
		case .set_value:
			ana.result.val_node^ = sem.latest_semnode
			spec = ana.result.val_node.spec
		case .type_default:
			spec = new(Spec)
			spec^ = Spec_Fixed{typeinfo=ana.result.typeinfo^}
		}

		local := new(Local)
		local.spec = spec
		ana.result.local = local

		bindings := make([]ScopeBinding, 1)
		bindings[0] = ScopeBinding{symbol=ana.local_name, local=local, tag=.local}
		scope_frame := ScopeStackFrame{bindings=bindings}
		append(&sem.scope_stack, scope_frame)

		return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
	}
}


Sem_Assign :: struct {
	// local: ^Local,
	val_node: ^SemNode,
	// binding: ^ScopeBinding,
	target_node: ^SemNode,
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
		ana.result.target_node = new(SemNode)
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
		return Msg_AnalyseChild{ast=&ast.children[idx], ret_spec=Spec_NonVoid{}}
		// astnode := ast.children[idx]
		// if astnode.tag != .symbol {
		// 	panic("'set' target must have symbol")
		// }
		// token := astnode.token
		// ss_loop: for i:=len(sem.scope_stack)-1; i>=0; i-=1 {
		// 	scope_frame := sem.scope_stack[i]
		// 	bindings := scope_frame.bindings
		// 	for j:=len(bindings)-1; j>=0; j-=1 {
		// 		sym := bindings[j].symbol
		// 		if sym == token {
		// 			// switch bindings[j].tag {
		// 			// case .local:
		// 			// 	ana.result.local = bindings[j].local
		// 			// case .alias:
		// 			// }
		// 			ana.result.binding = &bindings[j]
		// 			return Msg_Analyse{}
		// 		}
		// 	}
		// }
		// fmt.println()
		// fmt.println(sem.scope_stack)
		// fmt.panicf("could not resolve local to 'set': %v\n", token)
	} else if idx == 2 { // valexpr
		ana.result.target_node^ = sem.latest_semnode
		return Msg_AnalyseChild{ast=&ast.children[idx], ret_spec=Spec_NonVoid{}}
	} else {
		ana.result.val_node^ = sem.latest_semnode
		spec := &void_spec

		return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
	}
}


Sem_LocalUse :: struct {
	local: ^Local,
	members: []string,
}

Ana_LocalUse :: struct {
	local: ^Local,
	members: []string,
}

step_localuse :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_LocalUse)
	local := ana.local

	sem := Sem_LocalUse{local=local}
	sem.members=ana.members
	spec : ^Spec
	if len(ana.members)==0 {
		spec = local.spec
	} else {
		member_name := ana.members[0]
		spec = spec_get_member(local.spec, member_name)
	}
	return Msg_DoneNode{node={spec=spec, variant=sem}}
}


Sem_AccessPath :: struct {
	// local: ^Local,
	binding: ^ScopeBinding,
	member_nodes: []SemNode,
}

Ana_AccessPath :: struct {
	cursor: int,
	result: ^Sem_AccessPath,
}

step_access_path :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_AccessPath)
	if ana.cursor == 1 { // init
		ana.result = new(Sem_AccessPath)
		ana.result.member_nodes = make([]SemNode, len(ast.children)-2)
		if len(ast.children) < 3 {
			panic("too few children to access_path")
		}
	}
	idx := ana.cursor
	ana.cursor = idx+1

	if idx == 1 { // sym
		astnode := ast.children[idx]
		if astnode.tag != .symbol {
			panic("target must have symbol")
		}
		token := astnode.token
		ss_loop: for i:=len(sem.scope_stack)-1; i>=0; i-=1 {
			scope_frame := sem.scope_stack[i]
			bindings := scope_frame.bindings
			for j:=len(bindings)-1; j>=0; j-=1 {
				sym := bindings[j].symbol
				if sym == token {
					// switch bindings[j].tag {
					// case .local:
					// 	ana.result.local = bindings[j].local
					// case .alias:
					// }
					ana.result.binding = &bindings[j]
					return Msg_Analyse{}
				}
			}
		}
		fmt.println()
		fmt.println(sem.scope_stack)
		fmt.panicf("could not resolve target's local: %v\n", token)
	} else if idx < len(ast.children) { // members
		if idx >= 2 {
			ana.result.member_nodes[idx-2] = sem.latest_semnode
		}
		return Msg_AnalyseChild{ast=&ast.children[idx], ret_spec=Spec_NonVoid{}}
	} else {
		spec := &void_spec // FIXME
		return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
	}
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


Sem_String :: struct {
	value: string,
}

Ana_String :: struct {ast: ^AstNode}

step_string :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_String)
	token := ana.ast.token

	sem := Sem_String{value=token}

	spec := new(Spec)
	spec^ = Spec_String{}
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

Sem_Defn_Param :: struct {
	local: ^Local,
}

Sem_Defn :: struct {
	name: string,
	proc_node: ^SemNode,
	params: []Sem_Defn_Param,
}

Ana_Defn :: struct {
	cursor: int,
	result: ^Sem_Defn,
}

step_defn :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_Defn)
	if ana.cursor == 1 { // init
		ana.result = new(Sem_Defn)
		ana.result.proc_node = new(SemNode)
		if len(ast.children) > 6 {
			panic("too many children to 'defn'")
		}
		if len(ast.children) < 6 {
			panic("too few children to 'defn'")
		}
	}
	idx := ana.cursor
	ana.cursor = idx+1

	if idx == 1 { // sym
		astnode := ast.children[idx]
		if astnode.tag != .symbol {
			panic("'defn' must have symbol")
		}
		ana.result.name = astnode.token

		// define global symbol
		procs := &sem.compilation_unit.procedures
		append(procs, SemProcedure{sem_node=ana.result.proc_node, name=ana.result.name})
		prc := &procs[len(procs)-1]
		name := astnode.token
		cu_define_global_symbol(sem.compilation_unit, name, {tag=.procedure, val={procedure=prc}})


		idx := ana.cursor
		ana.cursor = idx+1

		// parameters

		params_ast := &ast.children[idx]
		expect_ast_tag(.vector, params_ast)
		nparams := len(params_ast.children)
		bindings := make([]ScopeBinding, nparams)
		params := make([]Sem_Defn_Param, nparams)
		ana.result.params = params
		prc.nparams = auto_cast nparams
		prc.nreturns = 1
		prc.param_locals = make([]^Local, nparams)

		for param_ast,i in &params_ast.children {
			expect_ast_tag(.list, &param_ast)
			if len(param_ast.children)!=2{panic("bad number of children")}

			name_ast := &param_ast.children[0]
			expect_ast_tag(.symbol, name_ast)
			name := name_ast.token

			local := new(Local)
			local.spec = new(Spec)
			local.spec^ = Spec_NonVoid{}
			bindings[i] = ScopeBinding{symbol=name, local=local, tag=.local}
			params[i].local=local
			prc.param_locals[i]=local
		}

		for param_ast,i in &params_ast.children {
			type_ast := &param_ast.children[1]
			expect_ast_tag(.symbol, type_ast)

			local := bindings[i].local
			local.spec^ = str_to_spec(type_ast.token)
		}

		scope_frame := ScopeStackFrame{bindings=bindings}
		append(&sem.scope_stack, scope_frame)
		return Msg_Analyse{}
	} else if idx == 3 {
		astnode := ast.children[idx]
		if astnode.tag != .symbol || astnode.token != "->" {
			panic("expected '->'")
		}

		idx := ana.cursor
		ana.cursor = idx+1

		// return type
		// TODO

		return Msg_Analyse{}
	} else if idx == 5 { // valexpr
		return Msg_AnalyseChild{ast=&ast.children[idx], ret_spec=Spec_NonVoid{}}
	} else { // done
		ana.result.proc_node^ = sem.latest_semnode
		spec := new(Spec)
		spec^ = void_spec
		return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
	}
}


Sem_Defstruct :: struct {
	name: string,
}

Ana_Defstruct :: struct {
	cursor: int,
	result: ^Sem_Defstruct,
}

step_defstruct :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_Defstruct)
	if ana.cursor == 1 {
		ana.result = new(Sem_Defstruct)
		if len(ast.children) < 3 {
			panic("too few children to 'defn'")
		}
	}
	idx := ana.cursor
	ana.cursor = idx+1

	if idx == 1 { // sym
		astnode := ast.children[idx]
		if astnode.tag != .symbol {
			panic("'def' must have symbol")
		}
		name := astnode.token
		ana.result.name = name

		// define global symbol
		decl := new(Decl_Datatype)
		decl.name=name
		sem.compilation_unit.datatypes_map[name]=decl
		cu_define_global_symbol(sem.compilation_unit, name, {tag=.datatype, val={datatype=decl}})


		idx := ana.cursor
		ana.cursor = idx+1

		// members

		for i in idx..<len(ast.children) {
			mem_ast := ast.children[i]
			expect_ast_tag(.list, &mem_ast)
			if len(mem_ast.children)!=2{panic("bad number of children")}

			name_ast := &mem_ast.children[0]
			expect_ast_tag(.symbol, name_ast)
			name := name_ast.token

		}

		typeinfo := Type_Struct{name=name}
		nmembers := len(ast.children)-idx
		members := make([]Type_Struct_Member, nmembers)
		byte_offset := 0
		for i in idx..<len(ast.children) {
			mem_ast := ast.children[i]
			name_ast := &mem_ast.children[0]
			expect_ast_tag(.symbol, name_ast)
			type_ast := &mem_ast.children[1]

			

			// resolve type

			resolve_type :: proc(sem: ^SemCtx, type_ast: ^AstNode) -> ^TypeInfo {
				mem_typeinfo : ^TypeInfo
				if type_ast.tag == .symbol {
					typestr := type_ast.token
					dt, found := sem.compilation_unit.datatypes_map[typestr]
					if !found {
						panic("could not resolve type")
					}
					mem_typeinfo = &dt.typeinfo
				} else if type_ast.tag == .vector {
					expect_nchildren_equals(type_ast, 2)
					item_ast := &type_ast.children[0]
					item_type := resolve_type(sem, item_ast)

					count_ast := &type_ast.children[1]
					expect_ast_tag(.number, count_ast)
					count, ok := strconv.parse_int(count_ast.token)
					if !ok {panic("not okay parsing")}

					mem_typeinfo = new(TypeInfo)
					mem_typeinfo^ = Type_Static_Array{count=count, item_type=item_type}
				} else {
					fmt.panicf("bad ast tag for type specification %v\n", type_ast)
				}
				return mem_typeinfo
			}

			mem_typeinfo := resolve_type(sem, type_ast)


			members[i-idx].name = name_ast.token
			members[i-idx].type = mem_typeinfo
			members[i-idx].byte_offset = byte_offset
			byte_offset += type_byte_size(mem_typeinfo)
		}
		typeinfo.members = members
		decl.typeinfo = typeinfo

	// 	return Msg_Analyse{}
	// } else { // done
		spec := new(Spec)
		spec^ = void_spec
		return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
	} else {panic("unreachable")}
}

Sem_ForeignLib :: struct {
	name: string,
	// library: string,
}

Ana_ForeignLib :: struct {
	cursor: int,
	result: ^Sem_ForeignLib,
	lib: ^Decl_ForeignLib,
}

step_foreign_lib :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_ForeignLib)
	if ana.cursor == 1 {
		ana.result = new(Sem_ForeignLib)
		if len(ast.children) > 3 {
			panic("too many children to 'foreign_lib'")
		}
		if len(ast.children) < 3 {
			panic("too few children to 'foreign_lib'")
		}
	}
	idx := ana.cursor
	ana.cursor = idx+1

	if idx == 1 { // sym
		astnode := ast.children[idx]
		if astnode.tag != .symbol {
			panic("def must have symbol")
		}
		name := astnode.token
		ana.result.name = name

		// define global symbol
		libs := &sem.compilation_unit.foreign_libs
		append(libs, Decl_ForeignLib{})
		ana.lib = &libs[len(libs)-1]
		cu_define_global_symbol(sem.compilation_unit, name, {tag=.foreign_lib, val={foreign_lib=ana.lib}})

		return Msg_Analyse{}
	} else {
		// node := sem.latest_semnode

		astnode := &ast.children[idx]
		expect_ast_tag(.string, astnode)
		lib_name := astnode.token
		ana.lib.lib_name = lib_name
		
		spec := new(Spec)
		spec^ = void_spec
		return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
	}
}

import br "../bytecode_runner"

Sem_ForeignMembers :: struct {
	_name: string,
}

Ana_ForeignMembers :: struct {
	cursor: int,
	result: ^Sem_ForeignMembers,
}

step_foreign_members :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_ForeignMembers)
	if ana.cursor == 1 {
		ana.result = new(Sem_ForeignMembers)
		if len(ast.children) < 3 {
			panic("too few children to 'foreign_members'")
		}
	}
	idx := ana.cursor
	ana.cursor = idx+1

	astnode := ast.children[idx]
	if astnode.tag != .symbol {
		panic("must have symbol for foreign library")
	}
	lib_sym := astnode.token

	symdecl, found := sem.compilation_unit.symbol_map[lib_sym]
	if !found {panic("did not find library")}
	if symdecl.tag != .foreign_lib {panic("this is not a foreign lib")}

	lib := symdecl.foreign_lib

	for i in 2..<len(ast.children) {
		mem_ast := &ast.children[i]
		expect_ast_tag(.list, mem_ast)
		if len(mem_ast.children)<2 {panic("insufficient children for member")}

		mem0 := &mem_ast.children[0]
		expect_ast_tag(.symbol, mem0)
		member_name := mem0.token

		// define global symbol
		procs := &sem.compilation_unit.foreign_procs
		append(procs, Decl_ForeignProc{name=member_name, lib=lib})
		prc := &procs[len(procs)-1]
		cu_define_global_symbol(sem.compilation_unit, member_name, {tag=.foreign_proc, val={foreign_proc=prc}})

		str_to_ctype :: proc(s: string) -> br.ForeignProc_C_Type {
			switch s {
			case "rawptr":
				return .pointer
			case "u32":
				return .int
			case "uint":
				return .longlong
			case:
				fmt.panicf("unhandled c type: %v\n", s)
			}
		}

		// param types
		mem_params := &mem_ast.children[1]
		expect_ast_tag(.vector, mem_params)
		param_types := make([]br.ForeignProc_C_Type, len(mem_params.children))
		for i in 0..<len(mem_params.children) {
			ast := &mem_params.children[i]
			expect_ast_tag(.list, ast)
			if len(ast.children)!=2 {panic("bad number of children")}

			name_ast := &ast.children[0]
			expect_ast_tag(.symbol, name_ast)

			type_ast := &ast.children[1]
			expect_ast_tag(.symbol, type_ast)

			param_types[i] = str_to_ctype(type_ast.token)
		}
		prc.param_types=param_types

		// return type
		if len(mem_ast.children)>2 {
			mem_arrow := &mem_ast.children[2]
			expect_ast_tag(.symbol, mem_arrow)
			if mem_arrow.token != "->" {panic("expected arrow")}

			mem_ret := &mem_ast.children[3]
			expect_ast_tag(.symbol, mem_ret)
			prc.ret_type = str_to_ctype(mem_ret.token)
		} else {
			prc.ret_type = .void
		}
	}
	
	spec := new(Spec)
	spec^ = void_spec
	return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
}

expect_ast_tag :: proc(tag: ast.AstNodeTag, node: ^AstNode, loc:=#caller_location) {
	if node.tag != tag {
		fmt.panicf(fmt="expected tag %v, got %v", args={tag, node.tag}, loc=loc)
	}
}

Sem_Invoke_Proc :: struct {
	species: enum {procedure, foreign_proc},
	using proc_decl: struct #raw_union {
		procedure: SemProcedure,
		foreign_proc: Decl_ForeignProc,
	},
}

Sem_Invoke :: struct {
	proc_decl: Sem_Invoke_Proc,
	args: []SemNode,
}

Ana_Invoke :: struct {
	cursor: int,
	proc_decl: Sem_Invoke_Proc,
	result: ^Sem_Invoke,
}

step_invoke :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_Invoke)
	if ana.cursor == 1 {
		ana.result = new(Sem_Invoke)
		ana.result.args = make([]SemNode, len(ast.children)-1)
		ana.result.proc_decl = ana.proc_decl
	} else {
		ana.result.args[ana.cursor-2]=sem.latest_semnode
	}
	if ana.cursor >= len(ast.children) {
		spec : ^Spec
		switch ana.proc_decl.species {
		case .procedure:
			spec = ana.result.proc_decl.procedure.sem_node.spec
		case .foreign_proc:
			ctype_to_typeinfo :: proc(ctype: br.ForeignProc_C_Type) -> ^TypeInfo {
				ti := new(TypeInfo)
				switch ctype {
				case .bool:
					ti^ = Type_Bool{}
				case .char:
					ti^ = Type_Integer{nbits=16}
				case .short:
					ti^ = Type_Integer{nbits=16}
				case .int:
					ti^ = Type_Integer{nbits=32}
				case .long:
					ti^ = Type_Integer{nbits=32}
				case .longlong:
					ti^ = Type_Integer{nbits=64}
				case .float:
					ti^ = Type_Float{nbits=32}
				case .double:
					ti^ = Type_Float{nbits=64}
				case .pointer:
					vt := new(TypeInfo)
					vt^ = Type_Void{}
					ti^ = Type_Pointer{value_type=vt}
				case .void:
					ti^ = Type_Void{}
				case .aggregate:
					panic("!!!")
				}
				return ti
			}

			spec = new(Spec)
			spec^=Spec_Fixed{typeinfo=ctype_to_typeinfo(ana.proc_decl.foreign_proc.ret_type)^}
		}
		return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
	}
	idx := ana.cursor
	ana.cursor = idx+1

	return Msg_AnalyseChild{ast=&ast.children[idx], ret_spec=Spec_NonVoid{}}
}



Sem_Intrinsic :: struct {
	op: br.Opcode,
	args: []SemNode,
}

Ana_Intrinsic :: struct {
	cursor: int,
	op: br.Opcode,
	result: ^Sem_Intrinsic,
}

step_intrinsic :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_Intrinsic)
	if ana.cursor == 1 {
		ana.result = new(Sem_Intrinsic)
		ana.result.args = make([]SemNode, len(ast.children)-1)
		ana.result.op = ana.op
	} else {
		ana.result.args[ana.cursor-2]=sem.latest_semnode
	}
	if ana.cursor >= len(ast.children) {
		spec : ^Spec
		#partial switch ana.op {
		case:
			panic("unhandled intrinsic")
		case .mem_copy:
			expect_nchildren_equals(ast, 4)
			spec=&void_spec
		}
		return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
	}
	idx := ana.cursor
	ana.cursor = idx+1

	return Msg_AnalyseChild{ast=&ast.children[idx], ret_spec=Spec_NonVoid{}}
}

expect_nchildren_equals :: proc(ast: ^AstNode, n: int, loc := #caller_location) {
	if len(ast.children)!=n{
		panic("invalid number of children", loc)
	}
}


Ana_UnresolvedList :: struct {}

step_unresolved_list :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	name := frame.ast.children[0].token
	decl, found := sem.compilation_unit.symbol_map[name]
	if !found {
		return Msg_ResolveSymbol{name=name, ctx=.invoke}
	}

	ana, msg0 := initial_ana_for_ast_node(sem, ast)
	frame2 := AstStackFrame{ast=ast,analyser=ana, ret_spec=ret_spec}
	stack_idx := sem.ast_stack_endx-1
	sem.ast_stack[stack_idx] = frame2
	if msg0 != nil {return msg0}
	return Msg_Analyse{}
}


Sem_Use :: struct {
}

Ana_Use :: struct {
	cursor: int,
	result: ^Sem_Use,
}

step_use :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_Use)
	if ana.cursor == 1 {
		ana.result = new(Sem_Use)
		if len(ast.children) > 2 {
			panic("too many children to 'use'")
		}
		if len(ast.children) < 2 {
			panic("too few children to 'use'")
		}
	}
	idx := ana.cursor
	// ana.cursor = idx+1

	astnode := ast.children[idx]
	if astnode.tag != .symbol {
		panic("'use' must have symbol")
	}
	target_name := astnode.token
	good := false
	binding : ^ScopeBinding
	for i := len(sem.scope_stack)-1; i>=0; i-=1 {
		scope_frame := sem.scope_stack[i]
		bindings := scope_frame.bindings
		for j:=len(bindings)-1; j>=0; j-=1 {
			sym := bindings[j].symbol
			if sym == target_name {
				good = true
				binding = &bindings[j]
			}
		}
	}
	if !good {panic("could not resolve local to 'use'")}

	typeinfo := spec_to_typeinfo(binding.local.spec)

	#partial switch ti in typeinfo {
	case Type_Struct:
		members := ti.members

		bindings := make([]ScopeBinding, len(members))
		for member, i in members {
			alias_binding : ScopeBinding
			alias_binding.symbol = member.name
			alias_binding.tag = .alias
			alias_binding.alias.binding = binding
			alias_binding.alias.member_name = member.name
			bindings[i] = alias_binding
		}

		scope_frame := ScopeStackFrame{bindings=bindings}
		append(&sem.scope_stack, scope_frame)
	case:
		fmt.panicf("invalid type for use: %v\n", ti)
	}

	spec := &void_spec

	return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
}


Sem_Cast :: struct {
	typeinfo: ^TypeInfo,
	child: ^SemNode,
}

Ana_Cast :: struct {
	cursor: int,
	result: ^Sem_Cast,
}

step_cast :: proc(sem: ^SemCtx, using frame: ^AstStackFrame) -> Message {
	ana := &analyser.(Ana_Cast)
	if ana.cursor == 1 {
		ana.result = new(Sem_Cast)
		ana.result.child = new(SemNode)
		if len(ast.children) > 3 {
			panic("too many children to 'cast'")
		}
		if len(ast.children) < 3 {
			panic("too few children to 'cast'")
		}
	}
	idx := ana.cursor
	ana.cursor = idx+1

	if idx == 1 {
		astnode := ast.children[idx]
		if astnode.tag != .symbol {
			panic("'use' must have symbol")
		}
		type_name := astnode.token
	
		typeinfo := str_to_typeinfo(type_name)
		ti := new(TypeInfo)
		ti^ = typeinfo
		ana.result.typeinfo = ti

		return Msg_AnalyseChild{ast=&ast.children[2], ret_spec=Spec_Fixed{typeinfo=typeinfo}}
	} else {
		ana.result.child^ = sem.latest_semnode

		spec := ana.result.child.spec
		// spec := new(Spec)
		// spec^ = Spec_Fixed{typeinfo=typeinfo}
		return Msg_DoneNode{node={spec=spec, variant=ana.result^}}
	}
}