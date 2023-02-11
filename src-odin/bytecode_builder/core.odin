package bytecode_builder

import "core:fmt"
import sem "../semantics"
import br "../bytecode_runner"

Temp :: struct {
	idx: u8,
	nwords: int,
	stackvar: ^StackVar,
}

StackVar :: struct {
	byte_offset: int,
	nbytes: int,
}

ConstantEntry :: struct {
	byte_offset: int,
	data: rawptr,
	nbytes: int,
}

LocalTempTableEntry :: struct{temp:^Temp, local:^sem.Local}

JumpIdxsTableEntry :: struct{jump_target:^sem.JumpTarget, idxs: ^[dynamic]int}

BcBuilder :: struct {
	codes: [dynamic]u8,

	temps: [dynamic]^Temp,
	next_temp_idx: int,
	arg_temps: []^Temp,
	local_temp_table: [dynamic]LocalTempTableEntry,

	stackvars: [dynamic]^StackVar,
	next_stackvar_byte_offset: int,
	local_stackvar_map: map[^sem.Local]^StackVar,

	jump_idxs_table: [dynamic]JumpIdxsTableEntry, 
	constants: [dynamic]ConstantEntry,

	procedure_ids: [dynamic]^SemNode,
	procedures: [dynamic]^ProcInfo,
	procid_to_procinfo: ^map[^SemNode]^ProcInfo,
	// foreign_proc_ids: [dynamic]sem.Decl_ForeignProc,
	foreign_procs: [dynamic]br.ForeignProc,
	// foreign_libs: [dynamic]^sem.Decl_ForeignLib,
}

append_bytecode :: proc(builder: ^BcBuilder, code: u8) {
	append(&builder.codes, code)
}

ProcInfo :: br.ProcInfo
ProcConstantPool :: br.ProcConstantPool
Opcode :: br.Opcode

SemNode :: sem.SemNode

builder_allocate_temp :: proc(using builder: ^BcBuilder, #any_int nwords: int = 1) -> ^Temp {
	idx := cast(u8) next_temp_idx
	o := len(temps)
	temp := new(Temp)
	temp.idx = idx
	temp.nwords = nwords
	append(&temps, temp)
	next_temp_idx += nwords
	return temps[o]
}

builder_allocate_stackvar :: proc(using builder: ^BcBuilder, #any_int nbytes: int) -> ^StackVar {
	byte_offset := next_stackvar_byte_offset
	stackvar := new(StackVar)
	stackvar.byte_offset = byte_offset
	stackvar.nbytes = nbytes
	append(&stackvars, stackvar)
	next_stackvar_byte_offset += nbytes
	return stackvars[len(stackvars)-1]
}

get_pool_nbytes :: proc(constants: [dynamic]ConstantEntry) -> int {
	nbytes := 0
	if len(constants)>0 {
		c := constants[len(constants)-1]
		nbytes = c.byte_offset
		nbytes += c.nbytes
	}
	return nbytes
}

reference_procedure_idx :: proc(using builder: ^BcBuilder, id: ^SemNode) -> int {
	idx := 0
	for it_id in &procedure_ids {
		if it_id == id {
			return idx
		}
		idx += 1
	}
	// create entry if does not exist
	append(&procedure_ids, id)
	append(&procedures, procid_to_procinfo[id])
	return idx
}

import dc "../dyncall"

reference_foreign_proc_idx :: proc(using builder: ^BcBuilder, decl: sem.Decl_ForeignProc) -> int {
	idx := 0
	symbol := decl.name
	lib_path := decl.lib.lib_name

	for it_id in &foreign_procs {
		// if it_id == decl {
		// 	return idx
		// }
		idx += 1
	}
	// create entry if does not exist
	prc := br.ForeignProc{lib_path=lib_path, symbol=symbol}
	prc.convention = dc.CALL_C_X86_WIN32_STD
	prc.ret_type = decl.ret_type
	prc.param_types = decl.param_types
	prc.nparams = len(prc.param_types)

	append(&foreign_procs, prc)
	return idx
}

builder_emit_constant_ptr :: proc(using builder: ^BcBuilder, data: rawptr, nbytes: int, temp: ^Temp) -> int {
	id := len(constants)
	byte_offset := get_pool_nbytes(builder.constants)
	append(&constants, ConstantEntry{data=data, nbytes=nbytes, byte_offset=byte_offset})
	append_elems(&codes, cast(u8) Opcode.ldc_ptr,
	  cast(u8) (byte_offset >> 8),
	  cast(u8) byte_offset, 
	  temp.idx)
	return id
}

builder_emit_constant_raw :: proc(using builder: ^BcBuilder, data: rawptr, nbytes: int, temp: ^Temp) -> int {
	id := len(constants)
	byte_offset := get_pool_nbytes(builder.constants)
	append(&constants, ConstantEntry{data=data, nbytes=nbytes, byte_offset=byte_offset})
	append_elems(&codes, cast(u8) Opcode.ldc_raw,
	  cast(u8) (byte_offset >> 8),
	  cast(u8) byte_offset, 
	  cast(u8) nbytes,
	  temp.idx)
	return id
}

builder_emit_constant :: proc(using builder: ^BcBuilder, value: any, temp: ^Temp) -> int {
	nbytes := type_info_of(value.id).size
	// fmt.println(type_info_of(value.id))  // @DEV
	return builder_emit_constant_raw(builder, value.data, nbytes, temp)
}

builder_emit_load_stk_ptr :: proc(using builder: ^BcBuilder, sv: ^StackVar, temp: ^Temp, byte_offset: int = 0) {
	bo := sv.byte_offset + byte_offset
	append(&codes, auto_cast Opcode.get_stack_addr)
	append(&codes, auto_cast bo)
	append(&codes, auto_cast (bo>>8))
	append(&codes, auto_cast (bo>>16))
	append(&codes, temp.idx)
}

builder_emit_op :: proc(using builder: ^BcBuilder, op: br.Opcode, args: ..u8) {
	append(&codes, auto_cast op)
	append_elems(array=&codes, args=args)
}

typeinfo_spillsP :: proc(typeinfo: ^sem.TypeInfo) -> bool {
	nbytes := sem.type_byte_size(typeinfo)
	return nbytes > 8
}

builder_emit_tranfer_stk_value :: proc(using builder: ^BcBuilder, code: br.Opcode, stackvar: ^StackVar, temp: ^Temp, byte_offset: int = 0) {
	bo := stackvar.byte_offset + byte_offset
	stktemp := builder_allocate_temp(builder)
	// if bo < size_of(u16) {
	// 	lo := cast(u8) bo
	// 	hi := cast(u8) (bo>>8)
	// 	builder_emit_load_stk_ptr(builder, stackvar, stktemp)
	// 	append_elems(&codes, cast(u8) code, stktemp.idx, temp.idx, lo, hi)
	// } else {
		builder_emit_load_stk_ptr(builder, stackvar, stktemp, bo)
		append_elems(&codes, cast(u8) code, stktemp.idx, temp.idx, 0, 0)
	// }
}

builder_emit_expr_to_temp :: proc(builder: ^BcBuilder, rettemp: ^Temp, using semnode: ^SemNode) {
	// fmt.println("building for sem node", semnode)

	#partial switch node in variant {
	case sem.Sem_Equal:
		nargs := len(node.args)
		npairs := nargs-1
		temp1 := builder_allocate_temp(builder)
		builder_emit_expr_to_temp(builder, temp1, &node.args[0])
		for i in 0..<npairs {
			temp2 := builder_allocate_temp(builder)
			builder_emit_expr_to_temp(builder, temp2, &node.args[i+1])
			builder_emit_binary_op(builder, .equal, temp1, temp2, rettemp)
			temp1 = temp2
		}
	case sem.Sem_Binop:
		nargs := len(node.args)
		npairs := nargs-1
		temp1 := builder_allocate_temp(builder)
		builder_emit_expr_to_temp(builder, temp1, &node.args[0])
		for i in 0..<npairs {
			temp2 := builder_allocate_temp(builder)
			builder_emit_expr_to_temp(builder, temp2, &node.args[i+1])
			builder_emit_binary_op(builder, node.op, temp1, temp2, rettemp)
			temp1 = temp2
		}
	case sem.Sem_Number:
		v := new(i64)
		v^ = node.value
		builder_emit_constant(builder, v^, rettemp)
	case sem.Sem_String:
		using builder
		str := node.value
		temp := builder_allocate_temp(builder)
		stkvar := builder_allocate_stackvar(builder, 16)

		// count
		n := new(int)
		n^ = len(str)
		builder_emit_constant(builder, n^, temp)
		builder_emit_tranfer_stk_value(builder, .store_64, stkvar, temp)
		// data
		builder_emit_constant_ptr(builder, raw_data(str), len(str), temp)
		builder_emit_tranfer_stk_value(builder, .store_64, stkvar, temp, 8)

		builder_emit_load_stk_ptr(builder, stkvar, rettemp)
		rettemp.stackvar = stkvar
	case sem.Sem_Do:

		children := node.children
		for i in 0..<len(children)-1 {
			temp := builder_allocate_temp(builder)
			builder_emit_expr_to_temp(builder, temp, &children[i])
		}
		builder_emit_expr_to_temp(builder, rettemp, &children[len(children)-1])
	case sem.Sem_Let:
		local := node.local
		temp := builder_allocate_temp(builder)

		switch node.initialiser_tag {
		case .set_value:
			builder_emit_expr_to_temp(builder, temp, node.val_node)
			if temp.stackvar != nil {
				builder.local_stackvar_map[local] = temp.stackvar
			}
		case .type_default:
			typeinfo := node.typeinfo
			assert(typeinfo!=nil)
			spillP := typeinfo_spillsP(typeinfo)
			if spillP {
				sv := builder_allocate_stackvar(builder, sem.type_byte_size(typeinfo))
				builder_emit_load_stk_ptr(builder, sv, temp)
				builder.local_stackvar_map[local] = sv
			} else {
				builder_emit_constant(builder, 0, temp)
			}
		}

		append(&builder.local_temp_table, LocalTempTableEntry{temp=temp, local=local})
	case sem.Sem_LocalUse:
		local := node.local
		members := node.members

		temp : ^Temp
		for e in builder.local_temp_table {
			if e.local==local {
				temp = e.temp
			}
		}
		if temp==nil {
			fmt.panicf("no temp found for local %v\nin %v", local, builder.local_temp_table)
		}

		if len(members)==0 {

			for i_ in 0..<temp.nwords {
				i := cast(u8) i_
				append_elems(&builder.codes, cast(u8) Opcode.copy, temp.idx+i, rettemp.idx+i)
			}
		} else {

			member_name := members[0]
			typeinfo := sem.spec_to_typeinfo(local.spec)
			member := sem.typeinfo_get_member(typeinfo, member_name)
			spillsP := typeinfo_spillsP(member.type)
			
			if spillsP {
				builder_emit_op(builder, .addi_int, auto_cast member.byte_offset, 0, rettemp.idx)
			} else {
				switch sem.type_byte_size(member.type) {
				case 8:
					builder_emit_op(builder, .load_64, temp.idx, rettemp.idx, auto_cast member.byte_offset, 0)
				case:
					panic("!!!")
				}
			}


			// stackvar, ok := builder.local_stackvar_map[local]
			// if !ok {panic("local stackvar not found")}

			// if spillsP {
			// 	builder_emit_load_stk_ptr(builder, stackvar, rettemp, member.byte_offset)
			// } else {
			// 	switch sem.type_byte_size(member.type) {
			// 	case 8:
			// 		builder_emit_tranfer_stk_value(builder, .load_64, stackvar, rettemp, member.byte_offset)
			// 	case:
			// 		panic("!!!")
			// 	}
			// }
		}
	case sem.Sem_Assign:
		{
			target_temp := builder_allocate_temp(builder)
			builder_emit_expr_to_temp(builder, target_temp, node.target_node)
			ref_typeinfo := sem.spec_to_typeinfo(node.target_node.spec)

			typeinfo : ^sem.TypeInfo
			#partial switch rti in ref_typeinfo {
			case sem.Type_Pointer:
				typeinfo = rti.value_type
			case:
				fmt.panicf("bad target type %v\n", ref_typeinfo)
			}

			val_temp := builder_allocate_temp(builder)
			builder_emit_expr_to_temp(builder, val_temp, node.val_node)

			switch sem.type_byte_size(typeinfo) {
				case 8:
					builder_emit_op(builder, .store_64, target_temp.idx, val_temp.idx, 0, 0)
				case 0: // @Temporary
					builder_emit_op(builder, .store_8, target_temp.idx, val_temp.idx, 0, 0)
				case:
					fmt.println(typeinfo)
					panic("!!!")
			}
		}
	case sem.Sem_If:
		using builder
		temp := builder_allocate_temp(builder)
		builder_emit_expr_to_temp(builder, temp, node.test_node)

		temp_zero := builder_allocate_temp(builder)
		zero := new(u8)
		zero^ = 0
		builder_emit_constant(builder, zero^, temp_zero)
		append_elems(&codes, cast(u8) Opcode.beq, temp.idx, temp_zero.idx)
		else_jump_idx := code_append_jumploc(&codes)
		builder_emit_expr_to_temp(builder, rettemp, node.then_node)
		append_elems(&codes, cast(u8) Opcode.goto)
		end_jump_idx := code_append_jumploc(&codes)

		write_jumploc(&codes, else_jump_idx, len(codes))
		builder_emit_expr_to_temp(builder, rettemp, node.else_node)
		write_jumploc(&codes, end_jump_idx, len(codes))
	case sem.Sem_Jumppad:
		using builder

		jumps := make([][dynamic]int, len(node.dest_nodes))
		for _jump, i in jumps {
			entry := JumpIdxsTableEntry{jump_target=&node.jump_targets[i], idxs=&jumps[i]}
			append(&jump_idxs_table, entry)
		}

		init_node := node.init_node
		if init_node != nil {
			builder_emit_expr_to_temp(builder, rettemp, init_node)
		}
		jump_targets := make([]int, len(node.dest_nodes))
		for _sub, i in node.dest_nodes {
			jump_targets[i] = len(codes)
			builder_emit_expr_to_temp(builder, rettemp, &node.dest_nodes[i])
		}
		for jump_idxs, i in jumps {
			for jump_idx in jump_idxs {
				write_jumploc(&codes, jump_idx, jump_targets[i])
			}
		}
		fmt.println(jumps)
	case sem.Sem_Goto:
		using builder
		for jump, i in jump_idxs_table {
			if jump.jump_target==node.target {
				append(&codes, cast(u8) Opcode.goto)
				jump_idx := code_append_jumploc(&codes)
				append(jump_idxs_table[i].idxs, jump_idx)
				return
			}
		}
		panic("no jump target")
	case sem.Sem_Invoke:
		using builder
		// compute args
		children := node.args
		param_specs := node.proc_decl.procedure
		subarg_temps := make([]^Temp, len(children))
		temp_sizes := make([]int, len(children))
		for i in 0..<len(children) {
			nwords: int
			switch node.proc_decl.species {
			case .procedure:
				spec := node.proc_decl.procedure.param_locals[i].spec
				nwords = shift_right_rounding_up(sem.type_byte_size(sem.spec_to_typeinfo(spec)), 3)
			case .foreign_proc:
				ctype := node.proc_decl.foreign_proc.param_types[i]
				nwords = shift_right_rounding_up(br.foreign_proc_c_type_byte_size(ctype), 3)
			}

			temp_sizes[i]=nwords
			temp := builder_allocate_temp(builder, nwords)
			subarg_temps[i]=temp
			builder_emit_expr_to_temp(builder, temp, &children[i])
		}
		// op
		switch node.proc_decl.species {
		case .procedure:
			append(&codes, cast(u8) Opcode.call)
			proc_idx := reference_procedure_idx(builder, node.proc_decl.procedure.sem_node)
			append(&codes, cast(u8) proc_idx)
			append(&codes, cast(u8) proc_idx>>8)
		case .foreign_proc:
			append(&codes, cast(u8) Opcode.call_c)
			proc_idx := reference_foreign_proc_idx(builder, node.proc_decl.foreign_proc)
			append(&codes, cast(u8) proc_idx)
			append(&codes, cast(u8) proc_idx>>8)
		}
		// param regs
		for temp,i in subarg_temps {
			// for j in 0..<temp_sizes[i] {
			// 	append(&codes, temp.idx+auto_cast j)
			// }
			append(&codes, temp.idx)
		}

		// return regs
		nwords: int
		switch node.proc_decl.species {
			case .procedure:
				spec := node.proc_decl.procedure.sem_node.spec
				nwords = shift_right_rounding_up(sem.type_byte_size(sem.spec_to_typeinfo(spec)), 3)
			case .foreign_proc:
				ctype := node.proc_decl.foreign_proc.ret_type
				nwords = shift_right_rounding_up(br.foreign_proc_c_type_byte_size(ctype), 3)
			}
		// for i in 0..<nwords {
		// 	append(&codes, rettemp.idx+auto_cast i)
		// }
		append(&codes, rettemp.idx)
	case sem.Sem_Intrinsic:
		#partial switch node.op {
		case .mem_copy:
			src_temp := builder_allocate_temp(builder)
			dst_temp := builder_allocate_temp(builder)
			len_temp := builder_allocate_temp(builder)
			builder_emit_expr_to_temp(builder, dst_temp, &node.args[0])
			builder_emit_expr_to_temp(builder, src_temp, &node.args[1])
			builder_emit_expr_to_temp(builder, len_temp, &node.args[2])
			
			builder_emit_op(builder, .mem_copy, src_temp.idx, dst_temp.idx, len_temp.idx, 0) // FIXME 2 byte length
		case:
			panic("!!!")
		}

	case sem.Sem_Cast:
		builder_emit_expr_to_temp(builder, rettemp, node.child)

	case sem.Sem_Use:

	case:
		fmt.panicf("unsupported bytecode semnode thing %v", variant)
	}
}

code_append_jumploc :: proc(codes: ^[dynamic]u8) -> int {
	idx := len(codes)
	append_elems(codes, 0, 0, 0)
	return idx
}

write_jumploc :: proc(codes: ^[dynamic]u8, code_idx: int, offset: int) {
	codes[code_idx] = cast(u8) (offset >> 16)
	codes[code_idx+1] = cast(u8) (offset >> 8)
	codes[code_idx+2] = cast(u8) offset
}

builder_emit_binary_op :: proc(using builder: ^BcBuilder, op: sem.Binop, temp1: ^Temp, temp2: ^Temp, rettemp: ^Temp) {
	#partial switch op {
	case .add:
		append_elems(&codes, cast(u8) Opcode.add_int, temp1.idx, temp2.idx, rettemp.idx)
	case .equal:
		append_elems(&codes, cast(u8) Opcode.bne, temp1.idx, temp2.idx)
		else_jump_idx := code_append_jumploc(&codes)
		one := new(u8)
		one^ = 1
		builder_emit_constant(builder, one^, rettemp)
		append_elems(&codes, cast(u8) Opcode.goto)
		end_jump_idx := code_append_jumploc(&codes)
	
		write_jumploc(&codes, else_jump_idx, len(codes))
		zero := new(u8)
		zero^ = 0
		builder_emit_constant(builder, zero^, rettemp)
		write_jumploc(&codes, end_jump_idx, len(codes))
	case:
		panic("unhandled op")
	}
}

import "core:mem"

shift_right_rounding_up :: #force_inline proc(#any_int x: int, $n: uint) -> int {
	if x==0 {return 0}
	addee :: (1<<n)-1
	return (x+addee)>>n
}

build_proc_from_semnode :: proc(proc_decl: ^sem.SemProcedure, procid_to_procinfo: ^map[^SemNode]^ProcInfo) ->
(_procinfo: ^ProcInfo, _proc_refs: []^ProcInfo) {
	semnode := proc_decl.sem_node

	// procinfo := new(ProcInfo)
	procinfo, ok := procid_to_procinfo[semnode]
	assert(ok)
	constant_pool := &procinfo.constant_pool

	builder := new(BcBuilder)
	builder.procid_to_procinfo = procid_to_procinfo
	// builder.local_stackvar_map = map[^sem.Local]^StackVar{}

	// params
	nparams := proc_decl.nparams
	builder.arg_temps = make([]^Temp, nparams)
	n_param_words := 0
	for i in 0..<nparams {
		local := proc_decl.param_locals[i]
		typeinfo := sem.spec_to_typeinfo(local.spec)
		param_size := shift_right_rounding_up(sem.type_byte_size(typeinfo), 3)
		n_param_words += param_size

		param_temp := builder_allocate_temp(builder, param_size)
		builder.arg_temps[i]=param_temp
		append(&builder.local_temp_table, LocalTempTableEntry{temp=param_temp, local=local})
	}
	// procinfo.nparams=auto_cast n_param_words
	// if n_param_words>255 {panic("cast")}
	procinfo.nparams = nparams

	// compute bytecode
	nreturns := proc_decl.nreturns
	rettemp := builder_allocate_temp(builder, nreturns)
	builder_emit_expr_to_temp(builder, rettemp, semnode)

	append_elems(&builder.codes, cast(u8) Opcode.ret)
	n_ret_words := 0
	for i in 0..<nreturns {
		typeinfo := sem.spec_to_typeinfo(semnode.spec)
		nbytes := sem.type_byte_size(typeinfo)
		ret_size := shift_right_rounding_up(nbytes, 3)

		// for j in 0..<ret_size {
		// 	append(&builder.codes, rettemp.idx+cast(u8) j)
		// }
		append(&builder.codes, rettemp.idx)

		n_ret_words += ret_size
	}
	// procinfo.nreturns = auto_cast n_ret_words
	// if n_ret_words>255 {panic("cast")}
	procinfo.nreturns = nreturns

	// finish up
	cpool_size := get_pool_nbytes(builder.constants)
	constant_pool.raw_data = mem.alloc(size=cpool_size, allocator=context.temp_allocator)
	for ce in builder.constants {
		nbytes := ce.nbytes
		ptr := mem.ptr_offset(cast(^u8) constant_pool.raw_data, ce.byte_offset)
		mem.copy(ptr, ce.data, nbytes)
	}

	procinfo.foreign_procs = builder.foreign_procs[:]

	procinfo.code = builder.codes[:]
	mem_size := 0
	for temp in builder.temps {
		mem_size += temp.nwords
	}
	procinfo.nregisters = mem_size
	stack_nbytes := 0
	for sv in builder.stackvars {
		stack_nbytes += sv.nbytes
	}
	procinfo.stack_nwords = auto_cast (1+stack_nbytes/8)

	return procinfo, builder.procedures[:]
}