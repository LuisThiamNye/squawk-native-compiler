package bytecode_runner

import "core:fmt"
import "core:mem"

run_frame :: proc(frame: ^StackFrame) {
	using frame
	
	for {
		if pc >= len(code) {
			fmt.println("error: ran out of bytes")
			return
		}

		op := cast(Opcode) code[pc]
		#partial switch op {

		case .add_int: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 + x2

		case .addi_int: // src1 reg, immediate(2), dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := (cast(u64) code[pc]<<8)+ cast(u64) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 + x2

		case .sub_int: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 - x2

		case .mul_int: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 * x2

		case .div_sint: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^i64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^i64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^i64) memory, code[pc])^ = x1 / x2

		case .div_uint: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 / x2

		case .rem_sint: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^i64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^i64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^i64) memory, code[pc])^ = x1 % x2

		case .rem_uint: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 % x2


		case .and: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 & x2

		case .or: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 | x2

		case .xor: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 ~ x2

		case .andi: // src1 reg, imm, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := cast(u64) code[pc]
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 & x2

		case .ori: // src1 reg, imm, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := cast(u64) code[pc]
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 | x2

		case .xori: // src1 reg, imm, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := cast(u64) code[pc]
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 ~ x2

		case .shiftl: // src1 reg, src2 reg, dest reg
			pc+=1
			x := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			shift := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x << shift

		case .shiftr: // src1 reg, src2 reg, dest reg
			pc+=1
			x := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			shift := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x >> shift

		case .ashiftr: // src1 reg, src2 reg, dest reg
			pc+=1
			x := mem.ptr_offset(cast(^i64) memory, code[pc])^
			pc+=1
			shift := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^i64) memory, code[pc])^ = x >> shift

		case .shiftli: // src1 reg, imm shift, dest reg
			pc+=1
			x := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			shift := code[pc]
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x << shift

		case .shiftri: // src1 reg, imm shift, dest reg
			pc+=1
			x := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			shift := code[pc]
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x >> shift

		case .ashiftri: // src1 reg, imm shift, dest reg
			pc+=1
			x := mem.ptr_offset(cast(^i64) memory, code[pc])^
			pc+=1
			shift := code[pc]
			pc+=1
			mem.ptr_offset(cast(^i64) memory, code[pc])^ = x >> shift

		case .ldc_raw: // pool offset(2), nbytes, leftmost dest reg
			pc+=2
			pool_offset := (cast(int) code[pc-1]<<8) + cast(int) code[pc]
			pc+=1
			nbytes := code[pc]
			data_ptr := mem.ptr_offset(cast(^u8) constant_pool.raw_data, pool_offset)
			nwords := ((nbytes-1)>>3)+1

			pc+=1
			left_word_offset := code[pc]
			byte_idx := nbytes
			assert(byte_idx>0)
			word_idx := nwords
			word_loop: for {
				word_idx -= 1
				word : u64 = 0
				i : uint = 0
				for {
					byte_idx -= 1
					word |= cast(u64) mem.ptr_offset(data_ptr, byte_idx)^<<(i*8)
					if byte_idx == 0 || i==7 {break}
					i += 1
				}
				mem.ptr_offset(cast(^u64) memory, left_word_offset+word_idx)^ = word
				if word_idx == 0 {break}
			}

		case .load_64: // ptr reg, imm offset (2, s16), dest reg
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^i64) memory, code[pc])^
			pc+=1
			offset := (cast(int) code[pc]<<8) + cast(int) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^i64) memory, code[pc])^ = mem.ptr_offset(base_ptr, offset)^

		case .load_32: // ptr reg, imm offset (2, s16), dest reg
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^i32) memory, code[pc])^
			pc+=1
			offset := (cast(int) code[pc]<<8) + cast(int) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^i32) memory, code[pc])^ = mem.ptr_offset(base_ptr, offset)^

		case .load_u32: // ptr reg, imm offset (2, s16), dest reg
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^u32) memory, code[pc])^
			pc+=1
			offset := (cast(int) code[pc]<<8) + cast(int) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^u32) memory, code[pc])^ = mem.ptr_offset(base_ptr, offset)^

		case .load_16: // ptr reg, imm offset (2, s16), dest reg
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^i16) memory, code[pc])^
			pc+=1
			offset := (cast(int) code[pc]<<8) + cast(int) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^i16) memory, code[pc])^ = mem.ptr_offset(base_ptr, offset)^

		case .load_u16: // ptr reg, imm offset (2, s16), dest reg
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^u16) memory, code[pc])^
			pc+=1
			offset := (cast(int) code[pc]<<8) + cast(int) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^u16) memory, code[pc])^ = mem.ptr_offset(base_ptr, offset)^

		case .load_8: // ptr reg, imm offset (2, s16), dest reg
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^i8) memory, code[pc])^
			pc+=1
			offset := (cast(int) code[pc]<<8) + cast(int) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^i8) memory, code[pc])^ = mem.ptr_offset(base_ptr, offset)^

		case .load_u8: // ptr reg, imm offset (2, s16), dest reg
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^u8) memory, code[pc])^
			pc+=1
			offset := (cast(int) code[pc]<<8) + cast(int) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^u8) memory, code[pc])^ = mem.ptr_offset(base_ptr, offset)^

		case .store_64: // src reg, ptr reg, imm offset (2, s16)
			pc+=1
			data := mem.ptr_offset(cast(^i64) memory, code[pc])^
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^i64) memory, code[pc])^
			pc+=1
			offset_high := cast(int) code[pc]<<8
			pc+=1
			offset := offset_high + cast(int) code[pc]
			mem.ptr_offset(base_ptr, offset)^ = data

		case .store_32: // src reg, ptr reg, imm offset (2, s16)
			pc+=1
			data := mem.ptr_offset(cast(^i32) memory, code[pc]+4)^
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^i32) memory, code[pc])^
			pc+=1
			offset_high := cast(int) code[pc]<<8
			pc+=1
			offset := offset_high + cast(int) code[pc]
			mem.ptr_offset(base_ptr, offset)^ = data

		case .store_16: // src reg, ptr reg, imm offset (2, s16)
			pc+=1
			data := mem.ptr_offset(cast(^i16) memory, code[pc]+6)^
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^i16) memory, code[pc])^
			pc+=1
			offset_high := cast(int) code[pc]<<8
			pc+=1
			offset := offset_high + cast(int) code[pc]
			mem.ptr_offset(base_ptr, offset)^ = data

		case .store_8: // src reg, ptr reg, imm offset (2, s16)
			pc+=1
			data := mem.ptr_offset(cast(^i8) memory, code[pc]+7)^
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^i8) memory, code[pc])^
			pc+=1
			offset_high := cast(int) code[pc]<<8
			pc+=1
			offset := offset_high + cast(int) code[pc]
			mem.ptr_offset(base_ptr, offset)^ = data

		case .copy: // from reg, to reg
			mem.ptr_offset(cast(^u64) memory, code[pc+1])^ = mem.ptr_offset(cast(^u64) memory, code[pc+2])^
			pc+=2

		case .call: // proc idx (2), arg reg... ret reg...
			fmt.println("call")
			pc+=2
			proc_idx := (cast(int) code[pc-1]<<8) + cast(int) code[pc]
			procinfo := constant_pool.procedures[proc_idx]
			nargs := procinfo.nparams

			return_offsets := make([]u8, procinfo.nreturns)
			frame := make_frame(procinfo.memory_nwords, procinfo.code, memory, return_offsets)
			frame.constant_pool = procinfo.constant_pool

			for i in 0..<nargs { // load args into memory array
				pc+=1
				mem.ptr_offset(cast(^u64) frame.memory, i)^ = mem.ptr_offset(cast(^u64) memory, code[pc])^
			}
			for i in 0..<procinfo.nreturns { // give subframe reg to set returns in
				pc+=1
				return_offsets[i]=code[pc]
			}
			run_frame(frame)

		case .ret: // ret registers...
			fmt.println("return")
			pc+=1
			nreturns := len(return_offsets)
			for i in 0..<nreturns {
				result := mem.ptr_offset(cast(^u64) memory, code[pc+i])^
				mem.ptr_offset(cast(^u64) return_memory, return_offsets[i])^ = result
			}

			return

		case .goto: // new pc(3)
			pc = (cast(int) code[pc+1]<<16) + (cast(int) code[pc+2]<<8) + cast(int) code[pc+3]

		case .beq: // rs1, rs2, new pc(3)
			pc+=1
			if mem.ptr_offset(cast(^u64) memory, code[pc])^ == mem.ptr_offset(cast(^u64) memory, code[pc+1])^ {
				pc+=2
				pc = (cast(int) code[pc]<<16) + (cast(int) code[pc+1]<<8) + cast(int) code[pc+2]
			} else {
				pc += 4
			}

		case .bne: // rs1, rs2, new pc(3)
			pc+=1
			if mem.ptr_offset(cast(^u64) memory, code[pc])^ != mem.ptr_offset(cast(^u64) memory, code[pc+1])^ {
				pc+=2
				pc = (cast(int) code[pc]<<16) + (cast(int) code[pc+1]<<8) + cast(int) code[pc+2]
			} else {
				pc += 4
			}

		case .bge: // rs1, rs2, new pc(3)
			pc+=1
			if mem.ptr_offset(cast(^i64) memory, code[pc])^ >= mem.ptr_offset(cast(^i64) memory, code[pc+1])^ {
				pc+=2
				pc = (cast(int) code[pc]<<16) + (cast(int) code[pc+1]<<8) + cast(int) code[pc+2]
			} else {
				pc += 4
			}

		case .bgeu: // rs1, rs2, new pc(3)
			pc+=1
			if mem.ptr_offset(cast(^u64) memory, code[pc])^ >= mem.ptr_offset(cast(^u64) memory, code[pc+1])^ {
				pc+=2
				pc = (cast(int) code[pc]<<16) + (cast(int) code[pc+1]<<8) + cast(int) code[pc+2]
			} else {
				pc += 4
			}

		case .blt: // rs1, rs2, new pc(3)
			pc+=1
			if mem.ptr_offset(cast(^i64) memory, code[pc])^ < mem.ptr_offset(cast(^i64) memory, code[pc+1])^ {
				pc+=2
				pc = (cast(int) code[pc]<<16) + (cast(int) code[pc+1]<<8) + cast(int) code[pc+2]
			} else {
				pc += 4
			}

		case .bltu: // rs1, rs2, new pc(3)
			pc+=1
			if mem.ptr_offset(cast(^u64) memory, code[pc])^ < mem.ptr_offset(cast(^u64) memory, code[pc+1])^ {
				pc+=2
				pc = (cast(int) code[pc]<<16) + (cast(int) code[pc+1]<<8) + cast(int) code[pc+2]
			} else {
				pc += 4
			}

		case:
			fmt.println("error: invalid bytecode op", op, cast(u8) op)
			return
		}
		pc+=1
	}
}

make_frame :: proc(nwords: int, code: []u8, return_memory: rawptr, return_offsets: []u8) -> ^StackFrame {
	// Note: each word is 8 bytes
	memory := mem.alloc(size=nwords*8, allocator=context.temp_allocator)
	frame := new(StackFrame, context.temp_allocator)
	frame^ = {pc=0, code=code, memory=memory, return_memory=return_memory,
		return_offsets = return_offsets}
	return frame
}

run :: proc() {
	fmt.println("Start")
	
	proc_add := ProcInfo{nparams=2, nreturns=1, memory_nwords=2}
	proc_add.code = [dynamic]u8{
		cast(u8) Opcode.add_int, 0, 1, 0,
	 	cast(u8) Opcode.ret, 0}[:]
	proc_add.constant_pool = ProcConstantPool{raw_data=nil, pointers=nil}

	// main program

	magic_num := new(i64)
	magic_num^ = 59
	magic_ret := new(i64)

	code := [dynamic]u8{
		cast(u8) Opcode.ldc_raw, 0, 1, 1, 1,
		cast(u8) Opcode.store_64, 1, 2, 0, 0,

		cast(u8) Opcode.ldc_raw, 0, 0, 1, 0,
		cast(u8) Opcode.load_64, 3, 0, 0, 1,
		cast(u8) Opcode.call, 0, 0, 1, 0, 0,
	 	cast(u8) Opcode.ret, 0}[:]

	// Constant pool
	// pool_entries := [dynamic]ConstantPoolEntry{ProcSig{0,1}}
	// pool := ConstantPool {pool_entries=pool_entries[:]}
	raw_data := mem.alloc(size=2, allocator=context.temp_allocator)
	mem.ptr_offset(cast(^u8) raw_data, 0)^ = 5
	mem.ptr_offset(cast(^u8) raw_data, 1)^ = 2
	pool := ProcConstantPool{raw_data=raw_data, pointers=nil, procedures={proc_add}}
	
	// initialise root stack frame
	mem_size := 4
	memory := mem.alloc(size=mem_size, allocator=context.temp_allocator)
	frame := make_frame(mem_size, code[:], memory, {0})
	frame.constant_pool = pool

	mem.ptr_offset(cast(^^i64) frame.memory, 3)^ = magic_num
	mem.ptr_offset(cast(^^i64) frame.memory, 2)^ = magic_ret

	run_frame(frame)

	result := mem.ptr_offset(cast(^u64) memory, 0)^
	fmt.println("Done:", result, "magic", magic_ret^)
}