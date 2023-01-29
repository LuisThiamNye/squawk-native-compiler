package bytecode_builder

import "core:fmt"
import sem "../semantics"
import "../bytecode_runner"

Temp :: struct {
	idx: u8,
}

ConstantEntry :: struct {
	byte_offset: int,
	value: any,
}

LocalTempTableEntry :: struct{temp:^Temp, local:^sem.Local}

JumpIdxsTableEntry :: struct{jump_target:^sem.JumpTarget, idxs: ^[dynamic]int}

BcBuilder :: struct {
	codes: [dynamic]u8,
	temps: [dynamic]Temp,
	local_temp_table: [dynamic]LocalTempTableEntry,
	jump_idxs_table: [dynamic]JumpIdxsTableEntry, 
	constants: [dynamic]ConstantEntry,
}

append_bytecode :: proc(builder: ^BcBuilder, code: u8) {
	append(&builder.codes, code)
}

ProcInfo :: bytecode_runner.ProcInfo
ProcConstantPool :: bytecode_runner.ProcConstantPool
Opcode :: bytecode_runner.Opcode

SemNode :: sem.SemNode

builder_allocate_temp :: proc(using builder: ^BcBuilder) -> ^Temp {
	idx := cast(u8) len(builder.temps)
	append(&temps, Temp{idx=idx})
	return &temps[idx]
}

get_pool_nbytes :: proc(constants: [dynamic]ConstantEntry) -> int {
	nbytes := 0
	if len(constants)>0 {
		c := constants[len(constants)-1]
		nbytes = c.byte_offset
		nbytes += type_info_of(c.value.id).size
	}
	return nbytes
}

builder_emit_constant :: proc(using builder: ^BcBuilder, value: any, temp: ^Temp) -> int {
	id := len(constants)
	byte_offset := get_pool_nbytes(builder.constants)
	append(&constants, ConstantEntry{value=value, byte_offset=byte_offset})
	nbytes := type_info_of(value.id).size
	append_elems(&codes, cast(u8) Opcode.ldc_raw,
	  cast(u8) (byte_offset >> 8),
	  cast(u8) byte_offset, 
	  cast(u8) nbytes,
	  temp.idx)
	return id
}

builder_emit_expr_to_temp :: proc(builder: ^BcBuilder, rettemp: ^Temp, using semnode: ^SemNode) {
	#partial switch node in variant {
	case sem.Sem_Equal:
		nargs := len(node.args)
		npairs := nargs-1
		temp1 := builder_allocate_temp(builder)
		builder_emit_expr_to_temp(builder, temp1, &node.args[0])
		for i in 0..<npairs {
			temp2 := builder_allocate_temp(builder)
			builder_emit_expr_to_temp(builder, temp2, &node.args[i+1])
			builder_emit_binary_op(builder, temp1, temp2, rettemp)
			temp1 = temp2
		}
	case sem.Sem_Number:
		v := new(i64)
		v^ = node.value
		builder_emit_constant(builder, v^, rettemp)
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
		builder_emit_expr_to_temp(builder, temp, node.val_node)
		append(&builder.local_temp_table, LocalTempTableEntry{temp=temp, local=local})
	case sem.Sem_LocalUse:
		local := node.local
		temp : ^Temp
		for e in builder.local_temp_table {
			if e.local==local {
				temp = e.temp
			}
		}
		if temp==nil {
			fmt.panicf("no temp found for local %v\nin %v", local, builder.local_temp_table)
		}
		append_elems(&builder.codes, cast(u8) Opcode.copy, temp.idx, rettemp.idx)
	case sem.Sem_Assign:
		local := node.local
		temp : ^Temp
		for e in builder.local_temp_table {
			if e.local==local {
				temp = e.temp
			}
		}
		if temp==nil {
			fmt.panicf("no temp found for local %v\nin %v", local, builder.local_temp_table)
		}
		val_temp := builder_allocate_temp(builder)
		builder_emit_expr_to_temp(builder, val_temp, node.val_node)
		append_elems(&builder.codes, cast(u8) Opcode.copy, val_temp.idx, temp.idx)
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

builder_emit_binary_op :: proc(using builder: ^BcBuilder, temp1: ^Temp, temp2: ^Temp, rettemp: ^Temp) {
	// append_elems(&codes, cast(u8) Opcode.add, temp1.idx, temp2.idx, rettemp.idx)
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
}

import "core:mem"

build_proc_from_semnode :: proc(semnode: ^SemNode) -> ^ProcInfo {
	procinfo := new(ProcInfo)
	procinfo.nparams=0
	procinfo.nreturns=1
	constant_pool := &procinfo.constant_pool

	builder := new(BcBuilder)
	rettemp := builder_allocate_temp(builder)
	builder_emit_expr_to_temp(builder, rettemp, semnode)
	append_elems(&builder.codes, cast(u8) Opcode.ret, rettemp.idx)

	cpool_size := get_pool_nbytes(builder.constants)
	constant_pool.raw_data = mem.alloc(size=cpool_size, allocator=context.temp_allocator)
	for ce in builder.constants {
		nbytes := type_info_of(ce.value.id).size
		ptr := mem.ptr_offset(cast(^u8) constant_pool.raw_data, ce.byte_offset)
		mem.copy(ptr, ce.value.data, nbytes)
	}

	procinfo.code = builder.codes[:]
	procinfo.memory_nwords = len(builder.temps)

	return procinfo
}