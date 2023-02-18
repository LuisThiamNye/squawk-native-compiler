package interpreter

import "../ast"
import "core:fmt"
import "core:mem"
import "core:strconv"
import "../numbers"
import "core:strings"
import "core:io"
import "core:os"
// import sem "../semantics"



InternedSymbol :: struct {
	name: string,
}

Var :: struct {
	symbol: ^InternedSymbol,
	initialised: bool,
	value: Rt_Any,
}

Interp :: struct {
	var_map: map[^InternedSymbol]^Var,
	var_interp_map: map[^Var]^VarInterp,
	symbol_map: map[string]^InternedSymbol,
}

find_interned_symbol :: proc(using interp: ^Interp, str: string) -> (^InternedSymbol, bool) {
	sym, found := symbol_map[str]
	return sym, found
}

get_interned_symbol :: proc(using interp: ^Interp, str: string) -> (^InternedSymbol) {
	sym, found := find_interned_symbol(interp, str)
	if !found {
		sym = new(InternedSymbol)
		sym.name = str
		interp.symbol_map[str] = sym
	}
	return sym
}

AstStackFrame :: struct {
	ast_node: ^ast.AstNode,
	cursor: int,
	tag: enum{none, invoke, intrinsic_proc, dynproc,},
	data: rawptr,
	host_data: rawptr,
	// variant: struct #raw_union {
	// 	invoke: struct {

	// 	},
	// },
}

LexicalBinding :: struct {
	value: Rt_Any,
}

VarInterp :: struct {
	unit_interp: ^Interp,
	blocked_by_var: ^Var,
	ast_stack: []AstStackFrame,
	ast_stack_endx: int,
	last_result: Rt_Any,
	lexical_binding_syms: [dynamic]^InternedSymbol,
	lexical_bindings: [dynamic]LexicalBinding,
}

globals_initialised := false

typeinfo_of_var : ^Type_Info
typeinfo_of_dynproc : ^Type_Info
typeinfo_of_intrinsic_proc : ^Type_Info
typeinfo_of_typeinfo : ^Type_Info
typeinfo_of_void : ^Type_Info
typeinfo_of_any : ^Type_Info
typeinfo_of_keyword : ^Type_Info

rtany_void : Rt_Any

init_globals :: proc() {
	globals_initialised = true

	// ti1 := new(Type_Info)
	// ti1^ = Type_Integer{nbits=64, signedP=true}
	// ti_mem_1 := new(Type_Struct_Member)
	// ti_mem_1^ = {name="count", type=ti1, byte_offset=0}
	// ti2 := new(Type_Info)
	// ti2^ = Type_Pointer{value_type=auto_cast new(Type_Void)}
	// ti_mem_2 := new(Type_Struct_Member)
	// ti_mem_2^ = {name="data", type=ti2, byte_offset=8}
	members := make([]Type_Struct_Member, 2)
	// members[0] = ti_mem_1^
	// members[1] = ti_mem_2^
	{
		ti : Type_Struct
		ti.name="Var"
		ti.members=members
		typeinfo_of_var = new(Type_Info)
		typeinfo_of_var.tag = .struct_
		typeinfo_of_var.struct_ = ti

		typeinfo_of_void = new(Type_Info)
		typeinfo_of_void.tag = .void
	}

	// FIXME
	typeinfo_of_dynproc = new(Type_Info)
	typeinfo_of_intrinsic_proc = new(Type_Info)

	t : Type_Static_Array
	t.count=size_of(Type_Info)
	it : Type_Integer
	it.nbits = 8
	t.item_type = new(Type_Info)
	t.item_type.tag = .integer
	t.item_type.integer = it
	typeinfo_of_typeinfo = new(Type_Info)
	typeinfo_of_typeinfo.tag = .static_array
	typeinfo_of_typeinfo.static_array = t

	{
		ms := make([]Type_Struct_Member, 2)
		ms[0].name = "type"
		ms[0].byte_offset = 0
		ms[0].type = typeinfo_of_typeinfo
		ms[1].name = "value"
		ms[1].byte_offset = 8
		ms[1].type = new(Type_Info)
		ms[1].type.tag = .pointer
		ms[1].type.pointer.value_type = typeinfo_of_void

		ti : Type_Struct
		ti.name = "Rt-Any"
		ti.members = ms

		typeinfo := new(Type_Info)
		typeinfo.tag = .struct_
		typeinfo.struct_ = ti
		typeinfo_of_any = typeinfo
	}

	{
		ms := make([]Type_Struct_Member, 1)
		ms[0].name = "symbol"
		ms[0].byte_offset = 8
		ms[0].type = new(Type_Info)
		ms[0].type.tag = .pointer
		ms[0].type.pointer.value_type = typeinfo_of_void

		ti : Type_Struct
		ti.name = "Rt-Any"
		ti.members = ms

		typeinfo := new(Type_Info)
		typeinfo.tag = .struct_
		typeinfo.struct_ = ti
		typeinfo_of_keyword = typeinfo
	}

	rtany_void = Rt_Any{type=typeinfo_of_void, data=typeinfo_of_void}
}

make_varinterp :: proc(interp: ^Interp, ast_node: ^ast.AstNode, max_depth: int) -> ^VarInterp {
	vi := new(VarInterp)
	stack := make([]AstStackFrame, max_depth+1)
	vi.unit_interp = interp
	vi.ast_stack = stack
	vi.ast_stack_endx = 0
	vi_push_frame(vi, ast_node)
	return vi
}

set_var :: proc(var: ^Var, val: Rt_Any) {
	assert(val.data != nil)
	var.value = val
	var.initialised = true
}

make_interp_from_ast_nodes :: proc(ast_nodes: []ast.AstNode, max_depth: int) -> ^Interp {
	if !globals_initialised {init_globals()}
	interp := new(Interp)

	for ast_node in ast_nodes {
		if !(ast_node.tag==.list) {panic("not list at top level")}
		children := ast_node.children
		if len(children)!=3 {panic("wrong number of children at top level")}

		head_ast := &children[0]
		if head_ast.tag != .symbol {
			panic("expected symbol")
		}
		if head_ast.token != "def" {
			fmt.panicf("expected 'def' got '%v'", head_ast.token)
		}

		sym_ast := &children[1]
		if sym_ast.tag != .symbol {
			panic("expected symbol")
		}

		ctor := &children[2]
		vi := make_varinterp(interp, ctor, max_depth)
		sym := get_interned_symbol(interp, sym_ast.token)
		var := new(Var)
		var.symbol = sym
		interp.var_map[sym] = var
		interp.var_interp_map[var] = vi
	}
	init_var :: proc(interp: ^Interp, name: string, val: Rt_Any) {
		sym := get_interned_symbol(interp, name)
		var := new(Var)
		var.symbol = sym
		interp.var_map[sym] = var

		set_var(var, val)
	}
	reg_intrinsic :: proc(interp: ^Interp, mode: Intrinsic_Proc_Mode, name: string, ptr: rawptr) {
		val : Rt_Any
		val.type = typeinfo_of_intrinsic_proc
		ip := new(Intrinsic_Proc)
		ip.mode = mode
		switch mode {
		case .ast:
			ip.ast_mode = cast(IntrinsicAstModeProc) ptr
		case .dyn:
			ip.dyn_mode = cast(IntrinsicDynModeProc) ptr
		}
		val.data = ip
		init_var(interp, name, val)
	}
	reg_intrinsic_ast :: proc(interp: ^Interp, name: string, ptr: IntrinsicAstModeProc) {
		reg_intrinsic(interp, .ast, name, auto_cast ptr)
	}
	reg_intrinsic_dyn :: proc(interp: ^Interp, name: string, ptr: IntrinsicDynModeProc) {
		reg_intrinsic(interp, .dyn, name, auto_cast ptr)
	}
	reg_type :: proc(interp: ^Interp, name: string) {
		ti := str_to_typeinfo("int")
		val : Rt_Any
		val.type = typeinfo_of_typeinfo
		val.data = cast(^Type_Info) ti
		init_var(interp, name, val)
	}
	reg_intrinsic_ast(interp, "fn", intrinsic_fndecl)
	reg_intrinsic_ast(interp, "do", intrinsic_doblock)
	reg_intrinsic_ast(interp, "let", intrinsic_let)
	reg_intrinsic_ast(interp, "set", intrinsic_set)
	reg_intrinsic_ast(interp, "struct", intrinsic_structdecl)
	reg_intrinsic_ast(interp, "new", intrinsic_new)
	reg_intrinsic_dyn(interp, "enum", intrinsic_type_enum)
	reg_intrinsic_dyn(interp, "tArr", intrinsic_type_counted_array)
	reg_intrinsic_dyn(interp, "make-arr", intrinsic_make_counted_array)
	reg_intrinsic_dyn(interp, "+", intrinsic_add)

	reg_type(interp, "uint")
	reg_type(interp, "int")
	reg_type(interp, "u8")
	reg_type(interp, "u32")
	reg_type(interp, "u64")
	reg_type(interp, "s64")
	reg_type(interp, "rawptr")

	{
		a : Rt_Any
		a.type = typeinfo_of_typeinfo
		a.data = typeinfo_of_typeinfo
		init_var(interp, "Type-Info", a)
	}

	return interp
}

Intrinsic_Proc_Mode :: enum {ast, dyn,}
Intrinsic_Proc :: struct {
	mode: Intrinsic_Proc_Mode,
	using variant: struct #raw_union {
		ast_mode: IntrinsicAstModeProc,
		dyn_mode: IntrinsicDynModeProc,
	},
}

find_var :: proc(interp: ^Interp, str: string) -> (^Var, bool) {
	sym, sym_found := find_interned_symbol(interp, str)
	if !sym_found {return nil, false}
	var, found := interp.var_map[sym]
	return var, found
}


Proc_Param :: struct {
	symbol: ^InternedSymbol,
	typeinfo: ^Type_Info,
}

Proc_Return :: struct {
	symbol: ^InternedSymbol,
	typeinfo: ^Type_Info,
}

DynProc :: struct {
	params: []Proc_Param,
	returns: []Proc_Return,
	code_ast_node: ^ast.AstNode,
}



Lazy_Member_Access_Access :: struct #raw_union {
	ptr_deref: bool,
	byte_offset: int,
}

Lazy_Member_Access :: struct {
	object: Rt_Any,
	accesses: []Lazy_Member_Access_Access,
	typeinfo: ^Type_Info,
}

vi_interp_frame :: proc(vi: ^VarInterp, using frame: ^AstStackFrame) {

	#partial switch ast_node.tag {

	case .list:
		if frame.tag == .none {	
			if cursor == 0 {
				children := ast_node.children
				if len(children)==0 {panic("can't have empty children")}
		
				head_ast := &children[0]
				vi_push_frame(vi, head_ast)
				cursor += 1
				return
			} else {
				head := vi.last_result
				if head.type == typeinfo_of_dynproc {
					dynproc := cast(^DynProc) head.data
					host_data = dynproc
					cursor = 0
					frame.tag = .dynproc
				} else if head.type == typeinfo_of_intrinsic_proc {
					ip := cast(^Intrinsic_Proc) head.data
					host_data = ip
					cursor = 0
					frame.tag = .intrinsic_proc
				} else {
					fmt.println("\nERROR\n - ast:")
					writer := io.to_writer(os.stream_from_handle(os.stdout))
					ast.pr_ast(writer, ast_node.children[0])
					fmt.println("\n\n - value:")
					print_rt_any(head)
					fmt.println()
					fmt.panicf("invalid type for list head: %v\n", head.type.tag)
				}
			}
		}
		#partial switch frame.tag {
		case .intrinsic_proc:
			ip := cast(^Intrinsic_Proc) host_data
			switch ip.mode {
			case .ast:
				ip.ast_mode(vi, frame)
			case .dyn:
				nargs := len(ast_node.children)-1
				args := cast(^[]Rt_Any) frame.data
				if cursor==0 {
					args = new([]Rt_Any)
				 	args^ = make([]Rt_Any, nargs)
				 	frame.data = args
				 	cursor += 1
				}
				arg_idx := cursor-1
				if arg_idx <= nargs {
					if arg_idx>0 {
						args[arg_idx-1]=vi.last_result
					}
					if arg_idx < nargs {
						arg_ast := &ast_node.children[cursor]
						vi_push_frame(vi, arg_ast)
						cursor += 1
						return
					}
				}
				ip.dyn_mode(vi, args^)
			}
		case .dynproc:
			dynproc := cast(^DynProc) host_data
			// @Copypaste of intrinsic_proc
			nargs := len(ast_node.children)-1
			args := cast(^[]Rt_Any) frame.data
			if cursor==0 {
				args = new([]Rt_Any)
			 	args^ = make([]Rt_Any, nargs)
			 	frame.data = args
			 	cursor += 1
			}
			arg_idx := cursor-1
			if arg_idx <= nargs {
				if arg_idx>0 {
					args[arg_idx-1]=vi.last_result
				}
				if arg_idx < nargs {
					arg_ast := &ast_node.children[cursor]
					vi_push_frame(vi, arg_ast)
					cursor += 1
					return
				}
			}
			if nargs != len(dynproc.params) {
				panic("invalid number of args to dynproc")
			}
			// for arg, i in args {
			// 	param := dynproc.params[i]
			// 	// TODO check type
			// }
			res := execute_invoke_dynproc(vi.unit_interp, dynproc, args^)
			vi_frame_return(vi, res)

		case:
			panic("unsupported")
		}

	case .symbol:
		val : Rt_Any
		has_val := false
		if cursor == 0 {
			frame.data = nil
			str := ast_node.token
			// Handle member access
			slash_idx := strings.index_byte(str, '/')
			members : []string
			target_name : string
			if slash_idx>=0 {
				if slash_idx==len(str)-1 {
					panic("delimiter can't be at the end")
				}
				target_name = str[0:slash_idx]
				members = make([]string, 1)
				members[0] = str[slash_idx+1:]

				frame.data = &members
			} else {
				target_name = str
			}

			// Simple symbol
			target_sym := get_interned_symbol(vi.unit_interp, target_name)

			// TODO fix asymmetry between returning vars and values of locals
			resolve_target_val: {
				// try local
				for lsym, i in vi.lexical_binding_syms {
					if lsym == target_sym {
						lb := vi.lexical_bindings[i]
						val = lb.value
						has_val = true
						break resolve_target_val
					}
				}
			
				// try var
				var, found := vi.unit_interp.var_map[target_sym]
				if found {
					if !var.initialised {
						vi.blocked_by_var = var
						cursor += 1
						return
					}
					val = var.value
					has_val = true
					break resolve_target_val
				}

				fmt.panicf("unresolved symbol: %v\n", str)
			}
		}

		if !has_val {
			val = vi.last_result
		}

		if frame.data != nil {
			members := cast(^[]string) frame.data

			// lazy := new(Lazy_Member_Access)
			// lazy.object = val
			// accesses : [dynamic]Lazy_Member_Access_Access

			// t := val.type
			// for memb_name in members {
			// 	for {
			// 		if t.tag==.pointer {
			// 			a : Lazy_Member_Access_Access
			// 			a.ptr_deref = true
			// 			append(&accesses, a)
			// 			t = t.pointer.value_type
			// 		} else {break}
			// 	}

			// 	memb_info := typeinfo_get_member(t, memb_name)
			// 	a : Lazy_Member_Access_Access
			// 	a.byte_offset = memb_info.byte_offset
			// 	append(&accesses, a)
			// 	t = memb_info.type
			// }
			
			// ma := new(Lazy_Member_Access)
			// ma.object = val
			// ma.accesses = accesses[:]
			// ma.typeinfo = t

			// val.type = new(Type_Info)
			// val.type.tag = .intrinsic
			// val.type.intrinsic.tag = .member_access
			// val.data = ma



			needs_deref := false
			ptr := val.data
			t := val.type
			for memb_name in members {
				for {
					if t.tag==.pointer {
						needs_deref = true
						if t.pointer.value_type.tag == .pointer{
							if ptr==nil {
								panic("object pointer is nil when trying to access member")
							}
							ptr = (cast(^rawptr) ptr)^
						}
						t = t.pointer.value_type
					} else {break}
				}
				memb_info := typeinfo_get_member(t, memb_name)
				ptr = mem.ptr_offset(cast(^u8) ptr, memb_info.byte_offset)
				t = memb_info.type
			}
			if needs_deref {
				val.type = new(Type_Info)
				val.type.tag = .pointer
				val.type.pointer.value_type = t
			} else {
				val.type = t
			}
			val.data = ptr
		}


		vi_frame_return(vi, val)

	case .vector:
		nargs := len(ast_node.children)
		ary := cast(^[]Rt_Any) frame.data
		if cursor==0 {
			ary = new([]Rt_Any)
		 	ary^ = make([]Rt_Any, nargs)
		 	frame.data = ary
		 	cursor += 1
		} else {
			ary[cursor-1]=vi.last_result
		}
		if cursor < nargs {
			arg_ast := &ast_node.children[cursor]
			vi_push_frame(vi, arg_ast)
			cursor += 1
			return
		}

		arr := new(Rt_Counted_Array)
		arr.count = len(ary)
		arr.data = raw_data(ary^)

		result : Rt_Any
		result.type = typeinfo_of_counted_array(typeinfo_of_any)
		result.data = arr
		vi_frame_return(vi, result)

	case .keyword:
		kw := new(Rt_Keyword)
		kw.symbol = get_interned_symbol(vi.unit_interp, ast_node.token)
		result : Rt_Any
		result.type = typeinfo_of_keyword
		result.data = kw
		vi_frame_return(vi, result)

	case .string:
		text := ast_node.token
		s := new(Rt_Counted_Array)
		s.count = len(text)
		s.data = raw_data(text)
		result : Rt_Any
		result.type = typeinfo_of_counted_array(str_to_typeinfo("u8"))
		result.data = s
		vi_frame_return(vi, result)

	case .number:
		token := ast_node.token
		// TODO improve
		_negP := token[0]=='-'
		int_mag := numbers.int_str_to_mag(u64, u128, token, 10)
		value : i64 = 0
		if len(int_mag)>0 {
			value = cast(i64) int_mag[0]
		}
		res : Rt_Any
		res.type = str_to_typeinfo("s64")
		v := new(i64)
		v^ = value
		res.data = v
		vi_frame_return(vi, res)

	case:
		fmt.panicf("unsupported: %v\n", ast_node.tag)
	}
}

vi_push_frame :: proc(using vi: ^VarInterp, ast_node: ^ast.AstNode) {
	frame : AstStackFrame
	frame.ast_node=ast_node
	next_idx := vi.ast_stack_endx
	vi.ast_stack[next_idx] = frame
	vi.ast_stack_endx = next_idx+1
}

vi_frame_return :: proc(vi: ^VarInterp, result: Rt_Any) {
	assert(result.data != nil || result.type.tag==.pointer)
	vi.last_result=result
	// fmt.println("RET:", result)
	vi.ast_stack_endx -= 1
}

vi_interp :: proc(using vi: ^VarInterp) {
	for {
		if vi.blocked_by_var != nil {
			if !vi.blocked_by_var.initialised {
				panic("Var has not since been initialised on re-visit")
			}
			vi.blocked_by_var = nil
		}

		ast_stack_cursor := ast_stack_endx-1
		frame := &ast_stack[ast_stack_cursor]
		vi_interp_frame(vi, frame)

		if vi.ast_stack_endx==0 {
			break
		}
		if vi.blocked_by_var != nil {
			break
		}
	}
}

interp_from_varinterp :: proc(var_interp: ^VarInterp) {
	vi := var_interp
	stack : [dynamic]^VarInterp
	for {
		vi_interp(vi)
		if vi.blocked_by_var != nil {
			fmt.println("blocked by:", vi.blocked_by_var.symbol.name)
			for v in &stack {
				if v == vi {
					fmt.println("ERROR: circular dependency:")
					for s in stack {
						fmt.println(s.blocked_by_var.symbol.name)
					}
					fmt.println(vi.blocked_by_var.symbol.name)
					panic("^")
				}
			}
			append(&stack, vi)
			vi_, found := var_interp.unit_interp.var_interp_map[vi.blocked_by_var]
			vi = vi_
			if !found {
				panic("couldn't find varinterp")
			}
		} else {
			if len(stack)==0 {break}
			prev := stack[len(stack)-1]
			prev.blocked_by_var.initialised = true
			prev.blocked_by_var.value = vi.last_result
			// fmt.println("Done with", prev.blocked_by_var.symbol.name)
			prev.blocked_by_var = nil
			prev.last_result = vi.last_result
			pop(&stack)
			vi = prev
		}
	}
}

interp_from_var :: proc(var: ^Var, vi: ^VarInterp) {
	interp_from_varinterp(vi)
	set_var(var, vi.last_result)
}


IntrinsicAstModeProc :: proc(vi: ^VarInterp, using frame: ^AstStackFrame)


intrinsic_doblock :: proc(vi: ^VarInterp, using frame: ^AstStackFrame) {
	children := ast_node.children
	if len(children)==0 {panic("!!")}
	if cursor==0 {cursor = 1}

	if cursor < len(children) {
		child := &children[cursor]
		cursor += 1
		vi_push_frame(vi, child)
		return
	}

	vi_frame_return(vi, vi.last_result)
}



intrinsic_let :: proc(vi: ^VarInterp, using frame: ^AstStackFrame) {
	children := ast_node.children
	if len(children)!=3 {panic("!!")}

	if cursor == 0 {
		val_ast := &children[2]
		cursor += 1
		vi_push_frame(vi, val_ast)
		return
	}

	val := vi.last_result

	sym_ast := &children[1]
	expect_ast_tag(.symbol, sym_ast)
	sym := get_interned_symbol(vi.unit_interp, sym_ast.token)

	lb : LexicalBinding
	lb.value = val
	append(&vi.lexical_bindings, lb)
	append(&vi.lexical_binding_syms, sym)

	vi_frame_return(vi, rtany_void)
}


intrinsic_set :: proc(vi: ^VarInterp, using frame: ^AstStackFrame) {
	children := ast_node.children
	if len(children)!=3 {panic("!!")}


	if cursor == 0 {
		target_ast := &children[1]
		cursor += 1
		vi_push_frame(vi, target_ast)
		return
	}
	if cursor == 1 {
		target_ptr := new(Rt_Any)
		target_ptr^ = vi.last_result
		frame.data = target_ptr

		val_ast := &children[2]
		cursor += 1
		vi_push_frame(vi, val_ast)
		return
	}

	target := cast(^Rt_Any) frame.data
	val := vi.last_result

	if target.type.tag == .pointer {
		if target.data == nil {
			panic("Exception: 'set' object is nil")
		}
		if val.type.tag==.pointer {
			(cast(^rawptr) target.data)^ = val.data
		}
		size := type_byte_size(target.type)
		mem.copy(target.data, val.data, size)
	} else {
		panic("invalid target type for 'set'")
	}


	vi_frame_return(vi, rtany_void)
}


intrinsic_add :: proc(vi: ^VarInterp, args: []Rt_Any) {
	sum : i64 = 0
	for arg in args {
		if !(arg.type.tag == .integer && arg.type.integer.nbits<=64) {
			fmt.panicf("invalid type to add: %v\n", arg.type.tag)
		}
		x := cast(^i64) arg.data
		sum += x^
	}

	ret : Rt_Any
	ret.type = str_to_typeinfo("s64")
	v := new(i64)
	v^ = sum
	ret.data = v
	vi_frame_return(vi, ret)
}



Intrinsic_Fndecl_Builder :: struct {
	prc: ^DynProc,
}

intrinsic_fndecl :: proc(vi: ^VarInterp, using frame: ^AstStackFrame) {
	using bl := cast(^Intrinsic_Fndecl_Builder) frame.data

	if cursor==0 {
		bl = new(Intrinsic_Fndecl_Builder)
		frame.data = bl

		prc = new(DynProc)

		expect_nchildren_equals(ast_node, 5)

		// First do some analysis

		idx := 1

		params_ast := &ast_node.children[idx]
		expect_ast_tag(.vector, params_ast)
		nparams := len(params_ast.children)
		prc.params = make([]Proc_Param, nparams)

		idx += 1

		arrow_astnode := ast_node.children[idx]
		if arrow_astnode.tag != .symbol || arrow_astnode.token != "->" {
			panic("expected '->'")
		}

		idx += 1

		returns_ast := &ast_node.children[idx]
		expect_ast_tag(.vector, returns_ast)
		nreturns := len(returns_ast.children)
		prc.returns = make([]Proc_Return, nreturns)

		idx += 1

		prc.code_ast_node = &ast_node.children[idx]

		cursor += 1
	}

	param_asts := &ast_node.children[1].children
	param_idx := cursor-1

	if 0<=param_idx && param_idx<=len(param_asts) {
		

		if param_idx != 0 { // complete previous param
			type_result := vi.last_result
			if type_result.type == typeinfo_of_typeinfo {
				typeinfo := cast(^Type_Info) type_result.data
				prc.params[param_idx-1].typeinfo = typeinfo
			} else {
				panic("bad type for type expression")
			}
		}

		if param_idx < len(param_asts) {
			param_ast := param_asts[param_idx]
			expect_ast_tag(.list, &param_ast)
			if len(param_ast.children)!=2{panic("bad number of children")}

			name_ast := &param_ast.children[0]
			expect_ast_tag(.symbol, name_ast)
			name := name_ast.token

			param := &prc.params[param_idx]
			param.symbol = get_interned_symbol(vi.unit_interp, name)

			vi_push_frame(vi, &param_ast.children[1])
			cursor += 1
			return
		}

		cursor += 1
	}

	// TODO returns

	ret : Rt_Any
	ret.type = typeinfo_of_dynproc
	ret.data = prc
	vi_frame_return(vi, ret)
}

execute_invoke_dynproc :: proc(interp: ^Interp, dp: ^DynProc, args: []Rt_Any) -> Rt_Any {
	assert(dp.code_ast_node != nil)
	vi := make_varinterp(interp, dp.code_ast_node, 100)

	// Load args into locals
	for param, i in dp.params {
		arg := args[i]

		lb : LexicalBinding
		lb.value = arg
		append(&vi.lexical_bindings, lb)
		append(&vi.lexical_binding_syms, param.symbol)
	}

	interp_from_varinterp(vi)
	fmt.println("dynproc returned:", vi.last_result)
	return vi.last_result
}


Intrinsic_Structdecl__Member :: struct {
	symbol: string,
	type: ^Type_Info,
}

Intrinsic_Structdecl :: struct {
	// member: struct {
	// 	cursor: int,
	// },
	members: []Intrinsic_Structdecl__Member,
}

intrinsic_structdecl :: proc(vi: ^VarInterp, using frame: ^AstStackFrame) {
	bl := cast(^Intrinsic_Structdecl) frame.data

	// Initial Analysis

	children := &ast_node.children

	nmembers := len(children)-1

	if cursor==0 {
		bl := new(Intrinsic_Structdecl)
		frame.data = bl

		bl.members = make([]Intrinsic_Structdecl__Member, nmembers)

		for i in 0..<nmembers {
			mem_ast := &children[i+1]
			expect_ast_tag(.list, mem_ast)
			expect_nchildren_equals(mem_ast, 2)

			mem_name_ast := &mem_ast.children[0]
			expect_ast_tag(.symbol, mem_name_ast)
			mem_name := mem_name_ast.token

			// bl.members[i].symbol = get_interned_symbol(vi.unit_interp, mem_name)
			bl.members[i].symbol = mem_name
		}
		cursor += 1
	}
	if cursor<=len(children) {
		// Process previously eval'd type
		mem_idx := cursor-1
		if mem_idx>0 {
			res := vi.last_result
			if res.type != typeinfo_of_typeinfo {
				panic("expected typeinfo for struct member")
			}
			bl.members[mem_idx-1].type = cast(^Type_Info) res.data
		}
		// Process next member type
		if mem_idx<nmembers {
			mem_ast := &children[mem_idx+1]
			mem_type_ast := &mem_ast.children[1]

			vi_push_frame(vi, mem_type_ast)
			cursor += 1
			return
		}
	}


	// build the struct typeinfo
	ti : Type_Struct
	ti.name = "ANONYMOUS-STRUCT"
	ti.members = make([]Type_Struct_Member, len(bl.members))
	byte_offset := 0
	for mem, i in bl.members {
		tim := &ti.members[i]
		tim.name = mem.symbol
		assert(len(tim.name)>0)
		tim.byte_offset = byte_offset
		tim.type = mem.type

		byte_offset = type_byte_size(mem.type)
	}

	ret : Rt_Any
	ret.type = typeinfo_of_typeinfo
	typeinfo := new(Type_Info)
	typeinfo.tag = .struct_
	typeinfo.struct_ = ti
	ret.data = typeinfo
	vi_frame_return(vi, ret)
}



intrinsic_new :: proc(vi: ^VarInterp, using frame: ^AstStackFrame) {
	children := ast_node.children
	if len(children)!=2 {panic("!!")}

	if cursor == 0 {
		type_ast := &children[1]
		cursor += 1
		vi_push_frame(vi, type_ast)
		return
	}

	type_val := vi.last_result
	if type_val.type != typeinfo_of_typeinfo {
		panic("invalid arg type for new")
	}
	typeinfo := cast(^Type_Info) type_val.data
	nbytes := type_byte_size(typeinfo)
	memory := mem.alloc(nbytes)

	ti := new(Type_Info)
	ti.tag = .pointer
	ti.pointer.value_type = typeinfo
	ret : Rt_Any
	ret.type = ti
	ret.data = memory
	vi_frame_return(vi, ret)
}



intrinsic_make_counted_array :: proc(vi: ^VarInterp, args: []Rt_Any) {
	if len(args)!=2 {panic("invalid number of args to make-arr")}

	type_val := args[0]
	if type_val.type != typeinfo_of_typeinfo {
		panic("invalid type for arg 'type'")
	}
	item_typeinfo := cast(^Type_Info) type_val.data
	item_nbytes := type_byte_size(item_typeinfo)

	count_val := args[1]
	if !(count_val.type.tag == .integer && count_val.type.integer.nbits<=64) {
		panic("invalid type for arg 'count'")
	}

	count := (cast(^i64) count_val.data)^
	memory := mem.alloc(auto_cast ((cast(i64) item_nbytes)*count))

	typeinfo := typeinfo_of_counted_array(item_typeinfo)

	ret : Rt_Any
	ret.type = typeinfo
	ret.data = memory
	vi_frame_return(vi, ret)
}



IntrinsicDynModeProc :: proc(vi: ^VarInterp, args: []Rt_Any)

intrinsic_type_counted_array :: proc(vi: ^VarInterp, args: []Rt_Any) {
	if len(args)!=1{panic("!!")}

	typeinfo := typeinfo_of_counted_array(typeinfo_of_void)
	ret : Rt_Any
	ret.type = typeinfo_of_typeinfo
	ret.data = typeinfo
	vi_frame_return(vi, ret)
}

typeinfo_of_counted_array :: proc(item_type: ^Type_Info) -> ^Type_Info {
	ms := make([]Type_Struct_Member, 2)
	ms[0].name = "count"
	ms[0].byte_offset = 0
	ms[0].type = str_to_typeinfo("int")
	ms[1].name = "data"
	ms[1].byte_offset = 8
	ms[1].type = new(Type_Info)
	ms[1].type.tag = .pointer
	ms[1].type.pointer.value_type = item_type

	ti : Type_Struct
	ti.name = "Counted-Array"
	ti.members = ms

	typeinfo := new(Type_Info)
	typeinfo.tag = .struct_
	typeinfo.struct_ = ti
	return typeinfo
}


intrinsic_type_enum :: proc(vi: ^VarInterp, args: []Rt_Any) {
	if len(args)!=1{panic("!!")}

	backing_type := new(Type_Info)
	backing_type.tag = .integer
	backing_type.integer.nbits = 64

	ti : Type_Enum
	ti.backing_type = backing_type

	typeinfo := new(Type_Info)
	typeinfo.tag = .enum_
	typeinfo.enum_ = ti
	ret : Rt_Any
	ret.type = typeinfo_of_typeinfo
	ret.data = typeinfo
	vi_frame_return(vi, ret)
}




expect_ast_tag :: proc(tag: ast.AstNodeTag, node: ^ast.AstNode, loc:=#caller_location) {
	if node.tag != tag {
		fmt.panicf(fmt="expected tag %v, got %v", args={tag, node.tag}, loc=loc)
	}
}

expect_nchildren_equals :: proc(ast: ^ast.AstNode, n: int, loc := #caller_location) {
	if len(ast.children)!=n{
		panic("invalid number of children", loc)
	}
}