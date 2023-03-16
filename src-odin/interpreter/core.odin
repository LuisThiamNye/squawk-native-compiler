package interpreter

import "../ast"
import "core:fmt"
import "core:mem"
import "core:strconv"
// import "core:math/big"
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
	data_invokers: map[^Type_Info]^DynProc,

	typeinfo_interns: struct{
		string: ^Type_Info,
		bool: ^Type_Info,
		u8: ^Type_Info,
		u32: ^Type_Info,
		u64: ^Type_Info,
		s64: ^Type_Info,
		rawptr: ^Type_Info,

		counted_arrays: map[^Type_Info]^Type_Info,
		pointers: map[^Type_Info]^Type_Info,
	},
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
	tag: enum{none, invoke, intrinsic_proc, dynproc, data_invoker},
	data_tag: enum{nil, jumps},
	data: rawptr,
	host_data: rawptr,
	scopeP: bool,
	lb_start_idx: int,
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

	var: ^Var,
}

print_vi_stack :: proc(using vi: ^VarInterp) {
	fmt.println("\nStack:")
	for i in 0..<ast_stack_endx {
		s := ast_stack[i]
		fmt.println("...")
		if s.ast_node!=nil {
			ast_println(s.ast_node^)
		} else {
			fmt.println("<nil> ast node")
		}
		fmt.printf("cursor=%v, tag=%v\n", s.cursor, s.tag)
	}
}

globals_initialised := false

typeinfo_of_var : ^Type_Info
typeinfo_of_dynproc : ^Type_Info
typeinfo_of_intrinsic_proc : ^Type_Info
typeinfo_of_typeinfop : ^Type_Info
typeinfo_of_typeinfo : ^Type_Info
typeinfo_of_void : ^Type_Info
typeinfo_of_any : ^Type_Info
typeinfo_of_keyword : ^Type_Info

rtany_void : Rt_Any

init_globals :: proc() {
	globals_initialised = true

	members := make([]Type_Struct_Member, 2)
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
	typeinfo_of_typeinfop = new(Type_Info)
	typeinfo_of_typeinfop.tag = .pointer
	typeinfo_of_typeinfop.pointer.value_type = typeinfo_of_typeinfo

	{
		ms := make([]Type_Struct_Member, 2)
		ms[0].name = "type"
		ms[0].byte_offset = 0
		ms[0].type = typeinfo_of_typeinfop
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
	// assert(val.type.tag != .nil)
	if val.type.tag ==.struct_ && val.type.struct_.name=="" {
		val.type.struct_.name = var.symbol.name
	}
	if val.type == typeinfo_of_dynproc {
		d := cast(^DynProc) val.data
		if d.name == "" {
			d.name = var.symbol.name
		}
	}
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
		vi.var = var
		interp.var_map[sym] = var
		interp.var_interp_map[var] = vi
	}
	init_var :: proc(interp: ^Interp, name: string, val: Rt_Any) -> ^Var {
		sym := get_interned_symbol(interp, name)
		var := new(Var)
		var.symbol = sym
		interp.var_map[sym] = var

		set_var(var, val)
		return var
	}
	reg_intrinsic :: proc(interp: ^Interp, mode: Intrinsic_Proc_Mode, name: string, ptr: rawptr) {
		ip := new(Intrinsic_Proc)
		ip.mode = mode
		switch mode {
		case .ast:
			ip.ast_mode = cast(IntrinsicAstModeProc) ptr
		case .dyn:
			ip.dyn_mode = cast(IntrinsicDynModeProc) ptr
		}
		val := wrap_data_in_any(ip, typeinfo_of_intrinsic_proc)
		init_var(interp, name, val)
	}
	reg_intrinsic_ast :: proc(interp: ^Interp, name: string, ptr: IntrinsicAstModeProc) {
		reg_intrinsic(interp, .ast, name, auto_cast ptr)
	}
	reg_intrinsic_dyn :: proc(interp: ^Interp, name: string, ptr: IntrinsicDynModeProc) {
		reg_intrinsic(interp, .dyn, name, auto_cast ptr)
	}
	reg_type :: proc(interp: ^Interp, name: string) -> (^Type_Info) {
		ti := str_to_new_typeinfo(name)
		val := wrap_data_in_any(&ti, typeinfo_of_typeinfop)
		var := init_var(interp, name, val)
		return ti
	}
	reg_intrinsic_ast(interp, "fn", intrinsic_fndecl)
	reg_intrinsic_ast(interp, "do", intrinsic_doblock)
	reg_intrinsic_ast(interp, "jumps", intrinsic_jumps)
	reg_intrinsic_ast(interp, "goto", intrinsic_goto)
	reg_intrinsic_ast(interp, "if", intrinsic_ifbranch)
	reg_intrinsic_ast(interp, "let", intrinsic_let)
	reg_intrinsic_ast(interp, "set", intrinsic_set)
	reg_intrinsic_ast(interp, "struct", intrinsic_structdecl)
	reg_intrinsic_ast(interp, "new", intrinsic_new)
	reg_intrinsic_dyn(interp, "enum", intrinsic_type_enum)
	reg_intrinsic_dyn(interp, "tArr", intrinsic_type_counted_array)
	reg_intrinsic_dyn(interp, "make-arr", intrinsic_make_counted_array)
	reg_intrinsic_dyn(interp, "+", intrinsic_add)
	reg_intrinsic_dyn(interp, "mul", intrinsic_multiply)
	reg_intrinsic_dyn(interp, "<", intrinsic_lt)
	reg_intrinsic_dyn(interp, "=", intrinsic_equal)
	reg_intrinsic_dyn(interp, "b-and", intrinsic_bit_and)
	reg_intrinsic_dyn(interp, "cast", intrinsic_cast)
	reg_intrinsic_dyn(interp, "bootstrap-register-data-invoker", intrinsic_register_data_invoker)
	reg_intrinsic_dyn(interp, "bootstrap-foreign-dyncall", intrinsic_foreign_dyncall)
	reg_intrinsic_dyn(interp, "prn", intrinsic_dbgprn)
	reg_intrinsic_dyn(interp, "memcopy", intrinsic_memcopy)
	reg_intrinsic_dyn(interp, "panic!", intrinsic_panic)
	reg_intrinsic_dyn(interp, "ptr-offset", intrinsic_ptr_offset)
	reg_intrinsic_dyn(interp, "deref", intrinsic_deref)

	interp.typeinfo_interns.bool = reg_type(interp, "bool")
	interp.typeinfo_interns.u8 = reg_type(interp, "u8")
	reg_type(interp, "u16")
	interp.typeinfo_interns.u32 = reg_type(interp, "u32")
	interp.typeinfo_interns.u64 = reg_type(interp, "u64")
	reg_type(interp, "s32")
	interp.typeinfo_interns.s64 = reg_type(interp, "s64")
	interp.typeinfo_interns.rawptr = reg_type(interp, "rawptr")
	init_var(interp, "int", resolve_var_value(interp, "s64"))
	init_var(interp, "uint", resolve_var_value(interp, "u64"))
	init_var(interp, "uintptr", resolve_var_value(interp, "u64"))

	{
		t := new(Type_Info)
		t.tag = .nilptr
		a := wrap_data_in_any(nil, t)
		init_var(interp, "nil", a)
	}
	{
		a := wrap_data_in_any(&typeinfo_of_typeinfo, typeinfo_of_typeinfop)
		init_var(interp, "Type-Info", a)
	}
	{
		a := wrap_data_in_any(&typeinfo_of_any, typeinfo_of_typeinfop)
		init_var(interp, "Any", a)
	}

	{
		// a := resolve_var_value(interp, "String")
		// if a.type != typeinfo_of_typeinfo {panic("not a typeinfo")}
		// interp.typeinfo_interns.string = cast(^Type_Info) a.data

		ti := typeinfo_of_counted_array(interp, interp.typeinfo_interns.u8)
		val := wrap_data_in_any(&ti, typeinfo_of_typeinfop)
		init_var(interp, "String", val)
		interp.typeinfo_interns.string = ti
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

	name: string,
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

Data_Invoker_Frame :: struct {
	dynproc: ^DynProc,
	head: Rt_Any,
}

vi_interp_frame :: proc(vi: ^VarInterp, using frame: ^AstStackFrame) {

	#partial switch ast_node.tag {

	case .list:
		if frame.tag == .none {	
			if cursor == 0 {
				children := ast_node.children
				if len(children)==0 {
					print_vi_stack(vi)
					panic("can't have empty children")
				}
		
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
					ivk, found := vi.unit_interp.data_invokers[head.type]
					if found {
						f := new(Data_Invoker_Frame)
						f.dynproc = ivk
						f.head = head
						host_data = f
						cursor = 0
						frame.tag = .data_invoker
						return
					}

					fmt.println("Invokers:")
					for x in vi.unit_interp.data_invokers {
						fmt.printf("%p", x)
					}
					fmt.println()
					fmt.println("\nERROR\n - ast:")
					writer := io.to_writer(os.stream_from_handle(os.stdout))
					ast.pr_ast(writer, ast_node.children[0])
					fmt.println("\n\n - value:")
					print_rt_any(head)
					fmt.println()
					fmt.panicf("invalid type for list head: %v %p\n", head.type.tag, head.type)
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
				fmt.println("\nERROR: invalid number of args to dynproc:", dynproc.name)
				fmt.println("Got:", nargs)
				fmt.println("Wanted:", len(dynproc.params))
				panic("")
			}
			// for arg, i in args {
			// 	param := dynproc.params[i]
			// 	// TODO check type
			// }
			res := execute_invoke_dynproc(vi.unit_interp, dynproc, args^)
			vi_frame_return(vi, res)

		case .data_invoker:
			using bl := cast(^Data_Invoker_Frame) host_data

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
			// for arg, i in args {
			// 	param := dynproc.params[i]
			// 	// TODO check type
			// }
			full_args := make([]Rt_Any, 2)
			full_args[0] = head
			full_args[1].type = typeinfo_of_counted_array(vi.unit_interp, typeinfo_of_any)
			full_args[1].data = args
			if 2 != len(dynproc.params) {
				fmt.println("\nERROR: invalid number of args to dynproc:", dynproc.name)
				fmt.println("Got:", nargs)
				fmt.println("Wanted:", 2)
				panic("")
			}
			res_val := execute_invoke_dynproc(vi.unit_interp, dynproc, full_args)
			if res_val.type != typeinfo_of_any {
				panic("expected 'any'")
			}
			res := (cast(^Rt_Any) res_val.data)^
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
			nmembers := 0
			for i := 0; i < len(str); i += 1 {
				if str[i] == '/' {
					nmembers += 1
				}
			}
			members : []string
			target_name : string
			if nmembers>0 {
				if str[len(str)-1]=='/' {
					panic("delimiter can't be at the end")
				}
				members = make([]string, nmembers)
				prev := 0
				n := 0
				for i := 0; i < len(str); i += 1 {
					if str[i] == '/' {
						if n==0 {
							target_name = str[prev:i]
						} else {
							members[n-1] = str[prev:i]
						}
						prev = i+1
						n += 1
					}
				}
				members[nmembers-1] = str[prev:len(str)]

				frame.data = &members
			} else {
				target_name = str
			}

			// Object symbol
			nstars := 0
			if target_name[0]=='*' {
				nstars += 1
				target_name = target_name[1:]
			}
			target_sym := get_interned_symbol(vi.unit_interp, target_name)

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

				print_vi_stack(vi)
				fmt.panicf("unresolved symbol: %v (target %v)\n", str, target_name)
			}
		}

		if !has_val {
			val = vi.last_result
		}

		nstars := 0
		if ast_node.token[0]=='*' {
			nstars += 1
		}
		if nstars > 0 {
			if val.type == typeinfo_of_typeinfop {
				v := cast(^Type_Info) val.data
				vp := typeinfo_wrap_pointer(vi.unit_interp, v)
				val.data = vp

			} else {
				panic("stars but is not typeinfo")
			}
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
			ptr : rawptr = nil
			part := val
			for memb_name in members {
				for {
					if part.type.tag==.pointer {
						needs_deref = true
						ptr = part.data
						part = wrap_data_in_any(part.data, part.type.pointer.value_type)
					} else {break}
				}
				memb_info := typeinfo_get_member(part.type, memb_name)
				ptr = get_pointer_to_member(part, memb_info^)
				part = wrap_data_in_any(ptr, memb_info.type)
			}
			if needs_deref {
				ti := typeinfo_wrap_pointer(vi.unit_interp, part.type)
				val = wrap_data_in_any(&ptr, ti)
			} else {
				val = part
			}
		}
		// if ast_node.token=="r/ret-typeinfo"{
		// 	fmt.println("EXPR", ast_node.token)
		// 	fmt.println("we have")
		// 	print_typeinfo(val.type)
		// 	fmt.println("we have")
		// 	print_rt_any(val)
		// 	fmt.println()
		// }


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
		arr.count = auto_cast len(ary)
		arr.data = raw_data(ary^)

		ti := typeinfo_of_counted_array(vi.unit_interp, typeinfo_of_any)
		result := wrap_data_in_any(arr, ti)
		vi_frame_return(vi, result)

	case .keyword:
		kw := new(Rt_Keyword)
		kw.symbol = get_interned_symbol(vi.unit_interp, ast_node.token)
		result := wrap_data_in_any(kw, typeinfo_of_keyword)
		vi_frame_return(vi, result)

	case .string:
		text := ast_node.token
		s := new(Rt_Counted_Array)
		s.count = auto_cast len(text)
		s.data = raw_data(text)
		ti := typeinfo_of_counted_array(vi.unit_interp, vi.unit_interp.typeinfo_interns.u8)
		result := wrap_data_in_any(s, ti)
		vi_frame_return(vi, result)

	case .number:
		token := ast_node.token
		// TODO improve
		_negP := token[0]=='-'
		value, ok := strconv.parse_i64_maybe_prefixed(token)
		if !ok {panic("couldn't parse number")}
		v := new(i64)
		v^ = value
		res := wrap_data_in_any(v, vi.unit_interp.typeinfo_interns.s64)
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
	if !(result.data != nil ||
		(result.type != nil &&
			(result.type.tag==.pointer ||
				result.type.tag==.nilptr))) {
		fmt.println("\nERROR")
		fmt.println("type:")
		print_typeinfo(result.type)
		fmt.println("\nval:")
		print_rt_any(result)
		fmt.println()
		panic("invalid return value for frame")
	}
	vi.last_result=result
	// fmt.println("RET:", result)
	vi.ast_stack_endx -= 1
	destroy_frame_scope(vi, &vi.ast_stack[vi.ast_stack_endx])
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
			set_var(prev.blocked_by_var, vi.last_result)

			if prev.var != nil {
				fmt.println("<", prev.var.symbol.name)
			} else {
				fmt.println("< (anonymous)")
			}

			prev.blocked_by_var = nil
			prev.last_result = vi.last_result
			pop(&stack)
			vi = prev
		}
	}
}

interp_from_var :: proc(var: ^Var, vi: ^VarInterp) {
	interp_from_varinterp(vi)
	res := vi.last_result
	set_var(var, res)
}

resolve_var_value :: proc(interp: ^Interp, name: string) -> Rt_Any {
	var, found := find_var(interp, name)
	if !found {panic("var not found")}
	if !var.initialised {
		var_interp, ok := interp.var_interp_map[var]
		assert(ok)
		interp_from_var(var, var_interp)
	}
	return var.value
}


IntrinsicAstModeProc :: proc(vi: ^VarInterp, using frame: ^AstStackFrame)



intrinsic_doblock :: proc(vi: ^VarInterp, using frame: ^AstStackFrame) {
	children := ast_node.children
	if len(children)==0 {panic("!!")}
	if cursor==0 {
		cursor = 1
		frame.scopeP = true
		frame.lb_start_idx = len(vi.lexical_bindings)
	}

	if cursor < len(children) {
		child := &children[cursor]
		cursor += 1
		vi_push_frame(vi, child)
		return
	}

	vi_frame_return(vi, vi.last_result)
}


// FIXME this does not work; need to have 'let' insert a destructor into
// the current scope (like 'defer') to remove the bindings
destroy_frame_scope :: proc(vi: ^VarInterp, using frame: ^AstStackFrame) {
	if !frame.scopeP {return}
	lb_idx := frame.lb_start_idx
	for {
		if len(vi.lexical_bindings)>lb_idx {
			pop(&vi.lexical_bindings)
			pop(&vi.lexical_binding_syms)
		} else {break}
	}
}


Intrinsic_Jumps :: struct {
	jump_syms: []^InternedSymbol,
	jump_codes: []^ast.AstNode,
	init_code: ^ast.AstNode,
}

intrinsic_jumps :: proc(vi: ^VarInterp, using frame: ^AstStackFrame) {
	children := ast_node.children
	bl := cast(^Intrinsic_Jumps) frame.data

	if cursor==0 {
		bl = new(Intrinsic_Jumps)
		frame.data = bl
		frame.data_tag = .jumps

		if len(children)<3 {panic("!!")}

		nargs := len(children)-1
		njumps := nargs/2
		initP := (nargs & 1) ==1

		if initP {bl.init_code=&children[1]}

		bl.jump_syms = make([]^InternedSymbol, njumps)
		bl.jump_codes = make([]^ast.AstNode, njumps)

		label0_idx := 1 + cast(int) initP
		label_idx := label0_idx
		i := 0
		for {
			if label_idx >= len(children) {break}

			label_ast := &children[label_idx]
			expect_ast_tag(.keyword, label_ast)
			sym := get_interned_symbol(vi.unit_interp, label_ast.token)
			bl.jump_syms[i] = sym
			bl.jump_codes[i] = &children[label_idx+1]

			label_idx += 2
			i += 1
		}

		cursor += 1
		if initP {
			vi_push_frame(vi, bl.init_code)
			return
		} else {
			vi_push_frame(vi, bl.jump_codes[0])
			return
		}
	}

	vi_frame_return(vi, vi.last_result)
}

intrinsic_goto :: proc(vi: ^VarInterp, using frame: ^AstStackFrame) {
	children := ast_node.children
	if len(children) != 2 {panic("too few children")}
	jtarget_ast := &children[1]
	expect_ast_tag(.keyword, jtarget_ast)
	s := jtarget_ast.token
	sym := get_interned_symbol(vi.unit_interp, s)

	i := vi.ast_stack_endx
	for {
		if i <= 0 {break}
		i -= 1
		f := &vi.ast_stack[i]

		destroy_frame_scope(vi, f)

		if f.data_tag==.jumps {

			bl := cast(^Intrinsic_Jumps) f.data
			assert(bl!=nil)
			for js, jmp_idx in &bl.jump_syms {
				if js == sym {
					// Do the jump
					vi.ast_stack_endx = i+1
					vi_push_frame(vi, bl.jump_codes[jmp_idx])
					return
				}
			}
		}
	}
	panic("could not find the jump target")
}

intrinsic_ifbranch :: proc(vi: ^VarInterp, using frame: ^AstStackFrame) {
	children := ast_node.children

	if cursor==0 {
		if len(children)<3 {panic("!!")}

		vi_push_frame(vi, &children[1])
		cursor += 1
		return
	}
	if cursor == 1 {
		condition_val := vi.last_result
		condition : bool
		if condition_val.type.tag == .bool {
			condition = (cast(^bool) condition_val.data)^
		} else {
			panic("bad type for if condition")
		}
		if condition {
			vi_push_frame(vi, &children[2])
		} else {
			if len(children)>3{
				vi_push_frame(vi, &children[3])
			} else {
				vi_frame_return(vi, rtany_void)
				return
			}
		}
		cursor += 1
		return
	}

	vi_frame_return(vi, vi.last_result)
}



Intrinsic_Let :: struct {
	lb_idx: int,
}

intrinsic_let :: proc(vi: ^VarInterp, using frame: ^AstStackFrame) {
	children := ast_node.children
	if len(children)!=3 {panic("!!")}

	bl := cast(^Intrinsic_Let) frame.data
	if cursor == 0 {
		bl := new(Intrinsic_Let)
		frame.data = bl

		val_ast := &children[2]
		cursor += 1
		vi_push_frame(vi, val_ast)
		return
	}

	val := vi.last_result

	sym_ast := &children[1]
	expect_ast_tag(.symbol, sym_ast)
	sym := get_interned_symbol(vi.unit_interp, sym_ast.token)

	bl.lb_idx = len(vi.lexical_bindings)

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

	// fmt.println("Setting")
	// print_typeinfo(target.type)
	// fmt.println("to")
	// print_typeinfo(val.type)

	if target.type.tag == .pointer {
		required_val_typeinfo := target.type.pointer.value_type
		
		if target.data == nil {
			print_vi_stack(vi)
			fmt.println("\nERROR")
			ast_println(children[1])
			fmt.println("Target:")
			print_typeinfo(required_val_typeinfo)
			fmt.println("\nValue:")
			print_typeinfo(val.type)
			fmt.println()
			panic("Exception: 'set' object is nil")
		}

		if required_val_typeinfo != val.type {
			fmt.println("\nERROR: incompatible types for set:")
			ast_println(children[1])
			fmt.println("Target:")
			print_typeinfo(required_val_typeinfo)
			fmt.println("\nValue:")
			print_typeinfo(val.type)
			fmt.println()
			panic("")
		}

		if val.type.tag==.pointer {
			(cast(^rawptr) target.data)^ = val.data
		} else {
			size := type_byte_size(val.type)
			mem.copy(target.data, val.data, size)
		}
	} else {
		panic("invalid target type for 'set'")
	}


	vi_frame_return(vi, rtany_void)
}


intrinsic_bit_and :: proc(vi: ^VarInterp, args: []Rt_Any) {
	if len(args)<2 {panic("too few args")}
	arg_to_int :: proc(arg: Rt_Any) -> i64 { // @Copypaste
		if !(arg.type.tag == .integer && arg.type.integer.nbits<=64) {
			fmt.panicf("invalid type: %v\n", arg.type.tag)
		}
		x := cast(^i64) arg.data
		return x^
	}
	acc : i64 = arg_to_int(args[0])
	for i in 1..<len(args) {
		x := arg_to_int(args[i])
		acc &= x
	}

	v := new(i64)
	v^ = acc
	ret := wrap_data_in_any(v, vi.unit_interp.typeinfo_interns.s64)
	vi_frame_return(vi, ret)
}


intrinsic_add :: proc(vi: ^VarInterp, args: []Rt_Any) {
	pointer_arithmetic := false

	sum : i64 = 0
	for arg in args {
		x : i64
		if pointer_arithmetic && arg.type.tag==.pointer {
			x = auto_cast cast(uintptr) arg.data
			if x < 0 {panic("pointer is negative; TODO implement add for unsigned numbers")}
		} else if arg.type.tag == .integer && arg.type.integer.nbits<=64 {
			x = (cast(^i64) arg.data)^
		} else {
			print_vi_stack(vi)
			fmt.panicf("invalid type to add: %v\n", arg.type.tag)
		}
		sum += x
	}

	v := new(i64)
	v^ = sum
	ret := wrap_data_in_any(v, vi.unit_interp.typeinfo_interns.s64)
	vi_frame_return(vi, ret)
}


intrinsic_multiply :: proc(vi: ^VarInterp, args: []Rt_Any) {
	sum : i64 = 1
	for arg in args {
		x : i64
		if arg.type.tag == .integer && arg.type.integer.nbits<=64 {
			x = (cast(^i64) arg.data)^
		} else {
			print_vi_stack(vi)
			fmt.panicf("invalid type to mul: %v\n", arg.type.tag)
		}
		sum *= x
	}

	v := new(i64)
	v^ = sum
	ret := wrap_data_in_any(v, vi.unit_interp.typeinfo_interns.s64)
	vi_frame_return(vi, ret)
}


intrinsic_lt :: proc(vi: ^VarInterp, args: []Rt_Any) {
	if len(args)<2 {panic("too few args")}
	arg_to_int :: proc(arg: Rt_Any) -> i64 {
		if !(arg.type.tag == .integer && arg.type.integer.nbits<=64) {
			fmt.panicf("invalid type to add: %v\n", arg.type.tag)
		}
		x := cast(^i64) arg.data
		return x^
	}
	prev := arg_to_int(args[0])
	result := true
	for i in 1..<len(args) {
		arg := args[i]
		x := arg_to_int(arg)
		if prev<x {continue}
		else {
			result = false
			break
		}
	}

	v := new(bool)
	v^ = result
	ret := wrap_data_in_any(v, vi.unit_interp.typeinfo_interns.bool)
	vi_frame_return(vi, ret)
}

import "core:math"

intrinsic_equal :: proc(vi: ^VarInterp, args: []Rt_Any) {
	if len(args)<2 {panic("too few args")}
	
	prev := args[0]
	result := true
	for i in 1..<len(args) {
		arg := args[i]

		if arg.data==prev.data {continue}

		if arg.type.tag==.integer && prev.type.tag==.integer {
			eq : bool
			if arg.type.integer.nbits>64 || prev.type.integer.nbits>64 {
				panic("too big")
			}
			load_x :: proc(x: rawptr, #any_int nbits: int) -> i64 {
				switch nbits {
				case 8:
					return auto_cast (cast(^i8) x)^
				case 16:
					return auto_cast (cast(^i16) x)^
				case 32:
					return auto_cast (cast(^i32) x)^
				case 64:
					return auto_cast (cast(^i64) x)^
				case: panic("unsupported")
				}
			}
			x1 := load_x(arg.data, arg.type.integer.nbits)
			x2 := load_x(prev.data, prev.type.integer.nbits)
			if x1 == x2 {continue}
			else {
				result = false
				break
			}
		} else {
			fmt.println("\nERROR: cannot compare types for equality")
			print_typeinfo(prev.type)
			fmt.println()
			print_typeinfo(arg.type)
			fmt.println()
			panic("")
		}
	}

	v := new(bool)
	v^ = result
	ret := wrap_data_in_any(v, vi.unit_interp.typeinfo_interns.bool)
	vi_frame_return(vi, ret)
}


intrinsic_cast :: proc(vi: ^VarInterp, args: []Rt_Any) {
	if len(args)!=2 {panic("bad number of args")}

	type_arg := args[0]
	val_arg := args[1]

	check_arg_type(type_arg, typeinfo_of_typeinfop)

	target_typeinfo := cast(^Type_Info) type_arg.data
	ptr_to_val : rawptr

	if target_typeinfo.tag==.pointer && val_arg.type.tag==.pointer {
		ptr_to_val = &val_arg.data
	} else if target_typeinfo.tag==.integer && val_arg.type.tag==.integer {
		ptr_to_val = val_arg.data
		t1 := target_typeinfo.integer
		t2 := val_arg.type.integer
		// if t1.signedP != t2.signedP {
		// 	panic("cannot convert between unsigned and signed")
		// }
		bytes1 := t1.nbits/8
		bytes2 := t2.nbits/8
		if bytes1 > bytes2 {
			m := mem.alloc(auto_cast bytes1)
			mem.copy(m, ptr_to_val, auto_cast bytes2)
			ptr_to_val = m
		}
	} else {
		panic("type combination not supported right now")
	}

	ret := wrap_data_in_any(ptr_to_val, target_typeinfo)
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

		if len(ast_node.children)<3{panic("too few children")}

		// First do some analysis

		idx := 1

		params_ast := &ast_node.children[idx]
		expect_ast_tag(.vector, params_ast)
		nparams := len(params_ast.children)
		prc.params = make([]Proc_Param, nparams)

		idx += 1

		arrow_astnode := ast_node.children[idx]
		if arrow_astnode.tag == .symbol && arrow_astnode.token == "->" {
			if len(ast_node.children)<5{panic("too few children")}
			idx += 1

			returns_ast := &ast_node.children[idx]
			// FIXME
			// expect_ast_tag(.vector, returns_ast)
			// nreturns := len(returns_ast.children)
			nreturns := 1
			prc.returns = make([]Proc_Return, nreturns)
	
			idx += 1
			assert(idx==4)
		} else {
			assert(idx==2)
		}
		prc.code_ast_node = &ast_node.children[idx]

		cursor += 1
	}

	param_asts := &ast_node.children[1].children
	param_base_cursor := 1
	param_idx := cursor-param_base_cursor

	if 0<=param_idx && param_idx<=len(param_asts) {
		

		if param_idx != 0 { // complete previous param
			type_result := vi.last_result
			if type_result.type == typeinfo_of_typeinfop {
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

	// Returns

	if len(prc.returns)>0 {
		ret_base_cursor := param_base_cursor+len(param_asts)+1
		ret_idx := cursor-ret_base_cursor
		ast_ret_idx := 3
		if ret_idx == 0 {
			ret_ast := &ast_node.children[ast_ret_idx+ret_idx]
			#partial switch ret_ast.tag {
			case .list:
				expect_nchildren_equals(ret_ast, 2)
				type_ast := &ret_ast.children[1]
				vi_push_frame(vi, type_ast)
				cursor += 1
				return
			case .symbol:
				vi_push_frame(vi, ret_ast)
				cursor += 1
				return
			case:
				ast_println(ret_ast^)
				fmt.panicf("bad ast type for ret type specification: %v\n", ret_ast.tag)
				
			}
		} else {
			type_result := vi.last_result
			if type_result.type == typeinfo_of_typeinfop {
				typeinfo := cast(^Type_Info) type_result.data
				prc.returns[0].typeinfo = typeinfo
			} else {
				fmt.panicf("bad type for type expression: %v\n", type_result.type.tag)
			}
		}
	}




	ret := wrap_data_in_any(prc, typeinfo_of_dynproc)
	vi_frame_return(vi, ret)
}

execute_invoke_dynproc :: proc(interp: ^Interp, dp: ^DynProc, args: []Rt_Any) -> Rt_Any {
	assert(dp.code_ast_node != nil)
	vi := make_varinterp(interp, dp.code_ast_node, 100)

	try_coercion :: proc(target_type: ^Type_Info, val: Rt_Any) -> (Rt_Any, bool) {
		value := val
		for {
			if !typeinfo_equiv(value.type, target_type) {

				if value.type.tag==.pointer {
					value = wrap_data_in_any(value.data, value.type.pointer.value_type)
					continue
				}
				if value.type.tag==.nilptr && target_type.tag==.pointer {
					a : Rt_Any
					a.type = target_type
					a.data = nil
					return a, true
				}

				return {}, false
			} else {
				break
			}
		}
		return value, true
	}

	// Load args into locals
	for param, i in dp.params {
		arg := args[i]

		argc, ok := try_coercion(param.typeinfo, arg)
		if !ok {
			fmt.printf("\n\nERROR: arg type does not match procedure signature (idx %v):\n", i)
			fmt.println("Proc:", dp.name)
			fmt.printf("Got: %v %p\n", arg.type.tag, arg.type)
			print_typeinfo(arg.type)
			fmt.printf("\nWanted: %v %p\n", param.typeinfo.tag, param.typeinfo)
			print_typeinfo(param.typeinfo)
			fmt.println("\nValue:")
			print_rt_any(arg)
			fmt.println()
			panic("")
		}

		lb : LexicalBinding
		lb.value = argc
		append(&vi.lexical_bindings, lb)
		append(&vi.lexical_binding_syms, param.symbol)
	}

	interp_from_varinterp(vi)
	res := vi.last_result

	// Check return type and do coercions

	if len(dp.returns)>0 {
		target_type := dp.returns[0].typeinfo
		result, ok := try_coercion(target_type, res)
		if !ok {
			fmt.println("\n\nERROR: returned type does not match procedure signature:")
			fmt.println("Proc:", dp.name)
			fmt.println("Got:", res.type.tag)
			print_typeinfo(res.type)
			fmt.println("\nWanted:", target_type.tag)
			print_typeinfo(target_type)
			fmt.println("\nValue:")
			print_rt_any(res)
			fmt.println()
			panic("")
		}

		return result
	} else {
		return rtany_void
	}
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
			if res.type != typeinfo_of_typeinfop {
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
	ti.name = ""
	ti.members = make([]Type_Struct_Member, len(bl.members))
	byte_offset := 0
	for mem, i in bl.members {
		tim := &ti.members[i]
		tim.name = mem.symbol
		assert(len(tim.name)>0)
		tim.byte_offset = byte_offset
		tim.type = mem.type

		byte_offset += type_byte_size(mem.type)
	}

	typeinfo := new(Type_Info)
	typeinfo.tag = .struct_
	typeinfo.struct_ = ti
	ret := wrap_data_in_any(&typeinfo, typeinfo_of_typeinfop)

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
	if type_val.type != typeinfo_of_typeinfop {
		panic("invalid arg type for new")
	}
	typeinfo := cast(^Type_Info) type_val.data
	nbytes := type_byte_size(typeinfo)
	memory := mem.alloc(nbytes)

	ti := typeinfo_wrap_pointer(vi.unit_interp, typeinfo)
	ret : Rt_Any
	ret.type = ti
	ret.data = memory
	vi_frame_return(vi, ret)
}



intrinsic_make_counted_array :: proc(vi: ^VarInterp, args: []Rt_Any) {
	if len(args)!=2 {
		panic("invalid number of args to make-arr")
	}

	type_val := args[0]
	if type_val.type != typeinfo_of_typeinfop {
		panic("invalid type for arg 'type'")
	}
	item_typeinfo := cast(^Type_Info) type_val.data
	item_nbytes := type_byte_size(item_typeinfo)

	count_val := args[1]
	if !(count_val.type.tag == .integer && count_val.type.integer.nbits<=64) {
		panic("invalid type for arg 'count'")
	}

	count := (cast(^i64) count_val.data)^
	data_memory := mem.alloc(auto_cast ((cast(i64) item_nbytes)*count))

	typeinfo := typeinfo_of_counted_array(vi.unit_interp, item_typeinfo)
	v := new(Rt_Counted_Array)
	v.count = count
	v.data = data_memory

	ret : Rt_Any
	ret.type = typeinfo
	ret.data = v
	vi_frame_return(vi, ret)
}



IntrinsicDynModeProc :: proc(vi: ^VarInterp, args: []Rt_Any)

intrinsic_type_counted_array :: proc(vi: ^VarInterp, args: []Rt_Any) {
	if !(len(args)==1 || len(args)==2) {panic("!!")}

	item_arg := args[0]
	if item_arg.type != typeinfo_of_typeinfop {panic("expected typeinfo arg")}
	item_typeinfo := cast(^Type_Info) item_arg.data

	typeinfo : ^Type_Info

	if len(args)>=2 {
		count_arg := args[1]
		if count_arg.type.tag != .integer {panic("expected integer count")}
		if count_arg.type.integer.nbits>64 {panic("count: int too big")}
		count := (cast(^i64) count_arg.data)^
		if count<0 {panic("count can't be <0")}
		typeinfo = new(Type_Info)
		typeinfo.tag = .static_array
		typeinfo.static_array.count = count
		typeinfo.static_array.item_type = item_typeinfo
	} else {
		typeinfo = typeinfo_of_counted_array(vi.unit_interp, item_typeinfo)
	}

	ret : Rt_Any
	ret.type = typeinfo_of_typeinfop
	ret.data = typeinfo
	vi_frame_return(vi, ret)
}

typeinfo_of_counted_array :: proc(interp: ^Interp, item_type: ^Type_Info) -> ^Type_Info {
	existing, found := interp.typeinfo_interns.counted_arrays[item_type]
	if found {
		return existing
	}
	ms := make([]Type_Struct_Member, 2)
	ms[0].name = "count"
	ms[0].byte_offset = 0
	ms[0].type = interp.typeinfo_interns.s64
	ms[1].name = "data"
	ms[1].byte_offset = 8
	ms[1].type = typeinfo_wrap_pointer(interp, item_type)

	ti : Type_Struct
	ti.name = "Counted-Array"
	ti.members = ms

	typeinfo := new(Type_Info)
	typeinfo.tag = .struct_
	typeinfo.struct_ = ti

	interp.typeinfo_interns.counted_arrays[item_type] = typeinfo
	return typeinfo
}

typeinfo_wrap_pointer :: proc(interp: ^Interp, value_type: ^Type_Info) -> ^Type_Info {
	if (value_type == typeinfo_of_typeinfo) {
		return typeinfo_of_typeinfop
	}
	existing, found := interp.typeinfo_interns.pointers[value_type]
	if found {return existing}

	ret := new(Type_Info)
	ret.tag = .pointer
	ret.pointer.value_type = value_type

	interp.typeinfo_interns.pointers[value_type]=ret

	return ret
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
	ret.type = typeinfo_of_typeinfop
	ret.data = typeinfo
	vi_frame_return(vi, ret)
}


intrinsic_register_data_invoker :: proc(vi: ^VarInterp, args: []Rt_Any) {
	if len(args)!=2{panic("!!")}

	dt := args[0]
	if dt.type != typeinfo_of_typeinfop {
		panic("not typeinfo")
	}
	typeinfo := cast(^Type_Info) dt.data

	p := args[1]
	if p.type != typeinfo_of_dynproc {
		panic("not a dynproc")
	}
	prc := cast(^DynProc) p.data

	vi.unit_interp.data_invokers[typeinfo] = prc

	vi_frame_return(vi, rtany_void)
}

intrinsic_dbgprn :: proc(vi: ^VarInterp, args: []Rt_Any) {
	fmt.println("\nDBG:")
	for arg in args {
		// fmt.println("- Type:")
		// print_typeinfo(arg.type)
		// fmt.println("\n- Value:")

		if arg.type == vi.unit_interp.typeinfo_interns.string {
			rts := cast(^Rt_String) arg.data
			s := sq_string_to_odin(rts^)
			fmt.println("String; count", rts.count)
			fmt.print(s)
		} else {
			print_rt_any(arg)
		}
		fmt.println()
	}
	fmt.println("END DBG\n")
	vi_frame_return(vi, rtany_void)
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

ast_println :: proc(a: ast.AstNode) {
	writer := io.to_writer(os.stream_from_handle(os.stdout))
	ast.pr_ast(writer, a)
	fmt.println()
}



sq_string_to_odin :: proc(s: Rt_String) -> string {
	assert(s.count==0 || s.data!=nil)
	return strings.string_from_ptr(cast(^u8) s.data, auto_cast s.count)
}

report_bad_arg_type :: proc(arg: Rt_Any, t: ^Type_Info, idx: int) {
	fmt.println("\nBAD ARG TYPE at", idx)
	fmt.println("Expected:")
	print_typeinfo(t)
	fmt.println("\nGot:")
	print_typeinfo(arg.type)
	fmt.println()
	panic("bad arg type")
}

check_arg_type :: proc(arg: Rt_Any, t: ^Type_Info) {
	if arg.type != t {
		report_bad_arg_type(arg, t, -1)
	}
}

check_arg_type_tag :: proc(arg: Rt_Any, tag: Type_Info_Tag, loc := #caller_location) {
	if arg.type.tag != tag {
		fmt.println("\nBAD ARG TYPE")
		fmt.println("Expected:", tag)
		fmt.println("\nGot:")
		print_typeinfo(arg.type)
		fmt.println()
		panic(message="bad arg type", loc=loc)
	}
}

report_bad_arg :: proc(arg: Rt_Any, msg: string, idx: int) {
	fmt.println("\nBAD ARG TYPE at", idx)
	fmt.println("Expected:", msg)
	fmt.println("Got:")
	print_typeinfo(arg.type)
	fmt.println()
	panic("bad arg type")
}

intrinsic_memcopy :: proc(vi: ^VarInterp, args: []Rt_Any) {
	if len(args)!=3 {panic("bad number of args")}

	dst_arg := args[0]
	src_arg := args[1]
	nbytes_arg := args[2]

	if dst_arg.type.tag!=.pointer {report_bad_arg(dst_arg, "pointer", 0)}
	if src_arg.type.tag!=.pointer {report_bad_arg(src_arg, "pointer", 1)}
	if nbytes_arg.type.tag!=.integer {panic("nbytes: expected integer")}
	if nbytes_arg.type.integer.nbits>64 {panic("nbytes: too big")}

	dst := dst_arg.data
	src := src_arg.data
	nbytes : u64
	if nbytes_arg.type.integer.signedP {
		nbytes_s := (cast(^i64) nbytes_arg.data)^
		if nbytes<0 {
			panic("nbytes can't be negative")
		}
		nbytes = cast(u64) nbytes_s
	} else {
		nbytes = (cast(^u64) nbytes_arg.data)^
	}



	mem.copy_non_overlapping(dst, src, auto_cast nbytes)

	vi_frame_return(vi, rtany_void)
}



import dc "../dyncall"
import "core:dynlib"
import c_ "core:c"

ForeignProc_C_Type :: enum {
	void, bool, char, short, int, long, longlong, float, double, pointer, aggregate,
}

intrinsic_foreign_dyncall :: proc(vi: ^VarInterp, args: []Rt_Any) {
	if len(args)!=5 {panic("bad number of args")}

	lib_path_arg := args[0]
	proc_name_arg := args[1]
	convention_arg := args[2]
	call_args_arg := args[3]
	ret_type_arg := args[4]

	check_arg_type(lib_path_arg, vi.unit_interp.typeinfo_interns.string)
	check_arg_type(proc_name_arg, vi.unit_interp.typeinfo_interns.string)
	check_arg_type(convention_arg, vi.unit_interp.typeinfo_interns.s64)
	check_arg_type(call_args_arg, typeinfo_of_counted_array(vi.unit_interp, typeinfo_of_any))
	check_arg_type(ret_type_arg, typeinfo_of_typeinfop)

	lib_path := sq_string_to_odin((cast(^Rt_String) lib_path_arg.data)^)
	proc_name := sq_string_to_odin((cast(^Rt_String) proc_name_arg.data)^)
	convention := (cast(^i64) convention_arg.data)^
	call_args := (cast(^[]Rt_Any) call_args_arg.data)^
	ret_typeinfo := cast(^Type_Info) ret_type_arg.data

	// Get the procedure pointer
	lib, oklib := dynlib.load_library(lib_path, true)
	if !oklib {fmt.panicf("could not load foreign library: %v\n", lib_path)}
	proc_ptr, okaddr := dynlib.symbol_address(lib, proc_name)
	if !okaddr {fmt.panicf("could not find symbol in foreign library: %v\n", proc_name)}


	max_stack_size :: 0x1000
	dcvm := dc.NewCallVM(max_stack_size)
	defer dc.Free(dcvm)

	dc.Reset(dcvm)
	dc.Mode(dcvm, auto_cast convention)


	typeinfo_to_c_type :: proc(ti: ^Type_Info) -> (c_type: ForeignProc_C_Type) {
		#partial switch ti.tag {
		case .void: c_type=.void
		case .bool: c_type=.bool
		case .integer:
			nbits := ti.integer.nbits
			if nbits <= 8 {
				c_type = .char
			} else if nbits <= 16 {
				c_type = .short
			} else if nbits <= 32 {
				c_type = .int
			} else if nbits <= 64 {
				c_type = .longlong
			} else {
				fmt.panicf("int too big: %v bits\n", nbits)
			}
		case .float:
			nbits := ti.float.nbits
			if nbits <= 32 {
				c_type = .float
			} else if nbits <= 64 {
				c_type = .double
			} else {
				panic("int too big")
			}
		case .pointer: c_type=.pointer
		case .nilptr: c_type=.pointer
		case:
			fmt.printf("unsupported type: %v\n", ti.tag)
			print_typeinfo(ti)
			fmt.println()
			panic("")
		}
		return
	}

	fmt.println("Foreign call:", proc_name)

	// load arguments
	for arg_val, i in call_args {
		ti := arg_val.type
		// FIXME we should not be using runtime values for determining types
		c_type := typeinfo_to_c_type(ti)
		arg : u64
		if arg_val.type.tag==.pointer || arg_val.type.tag==.nilptr{
			arg = cast(u64) cast(uintptr) arg_val.data
		} else {
			arg = (cast(^u64) arg_val.data)^
		}
		fmt.println("loading arg type:", c_type)
		switch c_type {
			case .void:
				print_vi_stack(vi)
				fmt.println("Arg value:")
				print_rt_any(arg_val)
				fmt.panicf("invalid arg type (void) at idx %v\n", i)
			case .bool:
				dc.ArgBool(dcvm, auto_cast arg)
			case .char:
				dc.ArgChar(dcvm, auto_cast arg)
			case .short:
				dc.ArgShort(dcvm, auto_cast arg)
			case .int:
				dc.ArgInt(dcvm, auto_cast arg)
			case .long:
				dc.ArgLong(dcvm, auto_cast arg)
			case .longlong:
				dc.ArgLongLong(dcvm, auto_cast arg)
			case .float:
				dc.ArgFloat(dcvm, auto_cast arg)
			case .double:
				dc.ArgDouble(dcvm, auto_cast arg)
			case .pointer:
				dc.ArgPointer(dcvm, auto_cast cast(uintptr) arg)
			case .aggregate:
				 panic("unsupported")
		}
	}

	v := new(u64)
	ret_c_type := typeinfo_to_c_type(ret_typeinfo)
	fmt.println("calling type:", ret_c_type)
	switch ret_c_type {
	case .void:
		dc.CallVoid(dcvm, proc_ptr)
	case .bool:
		(cast(^bool) v)^ = dc.CallBool(dcvm, proc_ptr) 
	case .char:
		(cast(^u8) v)^ = dc.CallChar(dcvm, proc_ptr) 
	case .short:
		(cast(^i16) v)^ = dc.CallShort(dcvm, proc_ptr) 
	case .int:
		(cast(^c_.int) v)^ = dc.CallInt(dcvm, proc_ptr) 
	case .long:
		(cast(^c_.long) v)^ = dc.CallLong(dcvm, proc_ptr) 
	case .longlong:
		(cast(^i64) v)^ = dc.CallLongLong(dcvm, proc_ptr) 
	case .float:
		(cast(^f32) v)^ = dc.CallFloat(dcvm, proc_ptr) 
	case .double:
		(cast(^f64) v)^ = dc.CallDouble(dcvm, proc_ptr) 
	case .pointer:
		(cast(^rawptr) v)^ = dc.CallPointer(dcvm, proc_ptr)
	case .aggregate:
		 // mem.ptr_offset(cast(^rawptr) memory, ret_reg)^ = dc.CallAggr(dcvm, proc_ptr)
		 panic("unsupported")
	}
	ret := wrap_data_in_any(v, ret_typeinfo)

	// fmt.printf("\n\nsuccessful call to %v with:\n", proc_name)
	// print_rt_any(ret)
	// fmt.println()
	// fmt.println()

	// @Temporary workaround
	r := new(Rt_Any)
	r^ = ret
	r2 := wrap_data_in_any(r, typeinfo_of_any)
	vi_frame_return(vi, r2)
}


intrinsic_panic :: proc(vi: ^VarInterp, args: []Rt_Any) {
	msg : string
	if len(args)>=1 {
		arg := args[0]
		if arg.type==vi.unit_interp.typeinfo_interns.string {
			rts := cast(^Rt_String) arg.data
			msg = sq_string_to_odin(rts^)
		}
	}

	fmt.println()
	fmt.println("PANIC:", msg)
	panic("User panic")
}


intrinsic_ptr_offset :: proc(vi: ^VarInterp, args: []Rt_Any) {
	ptr_arg := args[0]
	offset_arg := args[1]

	check_arg_type_tag(ptr_arg, .pointer)
	check_arg_type_tag(offset_arg, .integer)

	ptr := ptr_arg.data
	offset := (cast(^int) offset_arg.data)^

	item_size := type_byte_size(ptr_arg.type.pointer.value_type)
	ptr2 := mem.ptr_offset(cast(^u8) ptr, offset*item_size)

	ret := wrap_data_in_any(&ptr2, ptr_arg.type)
	// print_rt_any(ret)
	vi_frame_return(vi, ret)
}

intrinsic_deref :: proc(vi: ^VarInterp, args: []Rt_Any) {
	ptr_arg := args[0]
	check_arg_type_tag(ptr_arg, .pointer)
	ptr := ptr_arg.data

	val_type := ptr_arg.type.pointer.value_type

	ret := wrap_data_in_any(ptr, val_type)
	vi_frame_return(vi, ret)
}