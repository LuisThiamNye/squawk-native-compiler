package bytecode_runner

import "core:fmt"
import "core:mem"

import dc "../dyncall"

print_codes :: proc(using procinfo: ^ProcInfo) {
	pc := 0
	for {
		if pc == len(code) {
			return
		}
		if pc > len(code) {
			fmt.println("error: ran out of bytes at pc", pc, ", len ", len(code))
			return
		}

		op := cast(Opcode) code[pc]
		fmt.printf("% 3d: %-10v ", pc, op)
		#partial switch op {

		// src1 reg, src2 reg, dest reg
		case .add_int, .sub_int, .mul_int, .div_sint, .div_uint, .rem_sint, .rem_uint,
		.and, .or, .xor, .shiftl, .shiftr, .ashiftr:
			fmt.printf("r%v, r%v -> r%v", code[pc+1], code[pc+2], code[pc+3])
			pc+=3

		// src1 reg, immediate(2), dest reg
		case .addi_int:
			imm := (cast(int) code[pc+2]<<8) | cast(int) code[pc+3]
			fmt.printf("r%v, '%v -> r%v", code[pc+1], imm, code[pc+4])
			pc+=4

		// src1 reg, imm, dest reg
		case .andi, .ori, .xori, .shiftli, .shiftri, .ashiftri:
			fmt.printf("r%v, '%v -> r%v", code[pc+1], code[pc+2], code[pc+3])
			pc+=3

		// pool offset(2), nbytes, leftmost dest reg
		case .ldc_raw: 
			pool_offset := (cast(int) code[pc+1]<<8) | cast(int) code[pc+2]
			nbytes := code[pc+3]
			left_word_offset := code[pc+4]
			fmt.printf("c%v, %vB -> r%v ;", pool_offset, nbytes, left_word_offset)

			data_ptr := mem.ptr_offset(cast(^u8) constant_pool.raw_data, pool_offset)
			nwords := ((nbytes-1)>>3)+1

			assert(nbytes>0)
			byte_idx := 0
			word_idx := 0
			for {
				word : u64 = 0
				i : uint = 0
				for {
					word |= cast(u64) mem.ptr_offset(data_ptr, byte_idx)^<<(i*8)
					byte_idx += 1
					if byte_idx == cast(int) nbytes || i==7 {break}
					i += 1
				}
				fmt.print("",word)
				word_idx += 1
				if word_idx==cast(int)nwords {break}
			}

			pc+=4

		// pool offset(2), nbytes, leftmost dest reg
		case .ldc_ptr: 
			pool_offset := (cast(int) code[pc+1]<<8) | cast(int) code[pc+2]
			left_word_offset := code[pc+3]
			fmt.printf("c%v -> r%v ;", pool_offset, left_word_offset)

			pc+=3

		// ptr reg, imm offset (2, s16), dest reg
		case .load_64, .load_32, .load_u32, .load_16, .load_u16, .load_8, .load_u8:
			imm := (cast(int) code[pc+2]<<8) | cast(int) code[pc+3]
			fmt.printf("@r%v, offset '%v -> r%v", code[pc+1], imm, code[pc+4])

		// src reg, ptr reg, imm offset (2, s16)
		case .store_64, .store_32, .store_16, .store_8:
			imm := (cast(int) code[pc+3]<<8) | cast(int) code[pc+4]
			fmt.printf("r%v -> @r%v, offset '%v", code[pc+1], code[pc+2], imm)
			pc+=4

		case .copy: // from reg, to reg
			fmt.printf("r%v -> r%v", code[pc+1], code[pc+2])
			pc+=2

		case .call: // proc idx (2), arg reg... ret reg...
			pc+=2
			proc_idx := cast(int) code[pc-1] + (cast(int) code[pc]<<8)
			subprocinfo := constant_pool.procedures[proc_idx]

			for i in 0..<subprocinfo.nparams { // load args into memory array
				pc+=1
				fmt.printf("r%v ", code[pc])
			}
			fmt.print("->")
			for i in 0..<subprocinfo.nreturns { // give subframe reg to set returns in
				pc+=1
				fmt.printf(" r%v", code[pc])
			}

		case .call_c: // foreign proc idx (2), arg reg... ret reg
			pc+=2
			proc_idx := cast(int) code[pc-1] + (cast(int) code[pc]<<8)
			subprocinfo := foreign_procs[proc_idx]

			for i in 0..<subprocinfo.nparams {
				pc+=1
				fmt.printf("r%v ", code[pc])
			}
			pc+=1
			fmt.print("->", code[pc])
			fmt.print(" ;", subprocinfo.symbol)
			fmt.print("(")
			for t, i in subprocinfo.param_types {
				if i!=0 {
					fmt.print(" ")
				}
				fmt.print(t)
			}
			fmt.print(")")
			if subprocinfo.ret_type!=.void {
				fmt.printf(" -> %v", subprocinfo.ret_type)
			}

		case .ret: // ret registers...
			for i in 0..<nreturns {
				pc+=1
				fmt.printf("r%v ", code[pc])
			}

		case .goto: // new pc(3)
			target := (cast(int) code[pc+1]<<16) + (cast(int) code[pc+2]<<8) + cast(int) code[pc+3]
			fmt.print(target)
			pc += 3

		// rs1, rs2, new pc(3)
		case .beq, .bne, .bge, .bgeu, .blt, .bltu:
			target := (cast(int) code[pc+3]<<16) + (cast(int) code[pc+4]<<8) + cast(int) code[pc+5]
			fmt.printf("r%v, r%v goto '%v", code[pc+1], code[pc+2], target) 
			pc+=5

		case:
			fmt.println("error: invalid bytecode op", op, cast(u8) op)
			return
		}
		fmt.println()
		pc+=1
	}
}

run_frame :: proc(using frame: ^StackFrame) {
	
	for {
		if pc >= len(code) {
			fmt.println("error: ran out of bytes at pc", pc, ", len ", len(code))
			return
		}

		op := cast(Opcode) code[pc]
		fmt.printf("Op %v: %v\n", pc, op)
		#partial switch op {

		case .add_int: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 + x2
			pc += 1

		case .addi_int: // src1 reg, immediate(2), dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := (cast(u64) code[pc]<<8)+ cast(u64) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 + x2
			pc += 1

		case .sub_int: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 - x2
			pc += 1

		case .mul_int: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 * x2
			pc += 1

		case .div_sint: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^i64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^i64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^i64) memory, code[pc])^ = x1 / x2
			pc += 1

		case .div_uint: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 / x2
			pc += 1

		case .rem_sint: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^i64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^i64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^i64) memory, code[pc])^ = x1 % x2
			pc += 1

		case .rem_uint: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 % x2
			pc += 1


		case .and: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 & x2
			pc += 1

		case .or: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 | x2
			pc += 1

		case .xor: // src1 reg, src2 reg, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 ~ x2
			pc += 1

		case .andi: // src1 reg, imm, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := cast(u64) code[pc]
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 & x2
			pc += 1

		case .ori: // src1 reg, imm, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := cast(u64) code[pc]
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 | x2
			pc += 1

		case .xori: // src1 reg, imm, dest reg
			pc+=1
			x1 := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			x2 := cast(u64) code[pc]
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x1 ~ x2
			pc += 1

		case .shiftl: // src1 reg, src2 reg, dest reg
			pc+=1
			x := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			shift := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x << shift
			pc += 1

		case .shiftr: // src1 reg, src2 reg, dest reg
			pc+=1
			x := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			shift := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x >> shift
			pc += 1

		case .ashiftr: // src1 reg, src2 reg, dest reg
			pc+=1
			x := mem.ptr_offset(cast(^i64) memory, code[pc])^
			pc+=1
			shift := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			mem.ptr_offset(cast(^i64) memory, code[pc])^ = x >> shift
			pc += 1

		case .shiftli: // src1 reg, imm shift, dest reg
			pc+=1
			x := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			shift := code[pc]
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x << shift
			pc += 1

		case .shiftri: // src1 reg, imm shift, dest reg
			pc+=1
			x := mem.ptr_offset(cast(^u64) memory, code[pc])^
			pc+=1
			shift := code[pc]
			pc+=1
			mem.ptr_offset(cast(^u64) memory, code[pc])^ = x >> shift
			pc += 1

		case .ashiftri: // src1 reg, imm shift, dest reg
			pc+=1
			x := mem.ptr_offset(cast(^i64) memory, code[pc])^
			pc+=1
			shift := code[pc]
			pc+=1
			mem.ptr_offset(cast(^i64) memory, code[pc])^ = x >> shift
			pc += 1

		case .ldc_raw: // pool offset(2), nbytes, leftmost dest reg
			pc+=2
			pool_offset := (cast(int) code[pc-1]<<8) + cast(int) code[pc]
			pc+=1
			nbytes := code[pc]
			data_ptr := mem.ptr_offset(cast(^u8) constant_pool.raw_data, pool_offset)
			nwords := ((nbytes-1)>>3)+1
			
			pc+=1
			left_word_offset := code[pc]
			assert(nbytes>0)
			byte_idx := 0
			word_idx := 0
			for {
				word : u64 = 0
				i : uint = 0
				for {
					word |= cast(u64) mem.ptr_offset(data_ptr, byte_idx)^<<(i*8)
					byte_idx += 1
					if byte_idx == cast(int)nbytes || i==7 {break}
					i += 1
				}
				mem.ptr_offset(cast(^u64) memory, cast(int)left_word_offset+word_idx)^ = word
				word_idx += 1
				if word_idx == cast(int)nwords {break}
			}
			pc += 1

		case .ldc_ptr: // pool offset(2), dest reg
			pc+=2
			pool_offset := (cast(int) code[pc-1]<<8) + cast(int) code[pc]
			data_ptr := mem.ptr_offset(cast(^u8) constant_pool.raw_data, pool_offset)
			
			pc+=1
			dest_reg_offset := code[pc]
			mem.ptr_offset(cast(^rawptr) memory, cast(int)dest_reg_offset)^ = data_ptr

			pc += 1

		case .load_64: // ptr reg, imm offset (2, s16), dest reg
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^i64) memory, code[pc])^
			pc+=1
			offset := (cast(int) code[pc]<<8) + cast(int) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^i64) memory, code[pc])^ = mem.ptr_offset(base_ptr, offset)^
			pc += 1

		case .load_32: // ptr reg, imm offset (2, s16), dest reg
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^i32) memory, code[pc])^
			pc+=1
			offset := (cast(int) code[pc]<<8) + cast(int) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^i32) memory, code[pc])^ = mem.ptr_offset(base_ptr, offset)^
			pc += 1

		case .load_u32: // ptr reg, imm offset (2, s16), dest reg
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^u32) memory, code[pc])^
			pc+=1
			offset := (cast(int) code[pc]<<8) + cast(int) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^u32) memory, code[pc])^ = mem.ptr_offset(base_ptr, offset)^
			pc += 1

		case .load_16: // ptr reg, imm offset (2, s16), dest reg
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^i16) memory, code[pc])^
			pc+=1
			offset := (cast(int) code[pc]<<8) + cast(int) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^i16) memory, code[pc])^ = mem.ptr_offset(base_ptr, offset)^
			pc += 1

		case .load_u16: // ptr reg, imm offset (2, s16), dest reg
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^u16) memory, code[pc])^
			pc+=1
			offset := (cast(int) code[pc]<<8) + cast(int) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^u16) memory, code[pc])^ = mem.ptr_offset(base_ptr, offset)^
			pc += 1

		case .load_8: // ptr reg, imm offset (2, s16), dest reg
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^i8) memory, code[pc])^
			pc+=1
			offset := (cast(int) code[pc]<<8) + cast(int) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^i8) memory, code[pc])^ = mem.ptr_offset(base_ptr, offset)^
			pc += 1

		case .load_u8: // ptr reg, imm offset (2, s16), dest reg
			pc+=1
			base_ptr := mem.ptr_offset(cast(^^u8) memory, code[pc])^
			pc+=1
			offset := (cast(int) code[pc]<<8) + cast(int) code[pc+1]
			pc+=2
			mem.ptr_offset(cast(^u8) memory, code[pc])^ = mem.ptr_offset(base_ptr, offset)^
			pc += 1

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
			pc += 1

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
			pc += 1

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
			pc += 1

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
			pc += 1

		case .copy: // from reg, to reg
			mem.ptr_offset(cast(^u64) memory, code[pc+2])^ = mem.ptr_offset(cast(^u64) memory, code[pc+1])^
			pc+=3

		case .call: // proc idx (2), arg reg... ret reg...
			pc+=2
			proc_idx := cast(int) code[pc-1] + (cast(int) code[pc]<<8)
			procinfo := constant_pool.procedures[proc_idx]
			nargs := procinfo.nparams

			return_offsets := make([]u8, procinfo.nreturns)
			frame := make_frame(procinfo.memory_nwords, procinfo.code, memory, return_offsets, &procinfo)

			for i in 0..<nargs { // load args into memory array
				pc+=1
				mem.ptr_offset(cast(^u64) frame.memory, i)^ = mem.ptr_offset(cast(^u64) memory, code[pc])^
			}
			for i in 0..<procinfo.nreturns { // give subframe reg to set returns in
				pc+=1
				return_offsets[i]=code[pc]
			}
			run_frame(frame)
			pc += 1

		case .call_c: // foreign proc idx (2), arg reg... ret reg
			pc+=2
			proc_idx := cast(int) code[pc-1] + (cast(int) code[pc]<<8)
			fp := foreign_procs[proc_idx]
			nargs := fp.nparams

			// TODO move out into storage
			max_stack_size :: 0x1000
			dcvm := dc.NewCallVM(max_stack_size)
			defer dc.Free(dcvm)

			dc.Reset(dcvm)
			dc.Mode(dcvm, auto_cast fp.convention)

			// load arguments
			for i in 0..<nargs {
				pc+=1
				arg := mem.ptr_offset(cast(^u64) memory, code[pc])^
				arg_type := fp.param_types[i]
				switch arg_type {
					case .void:
						panic("invalid arg type")
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

			// give subframe reg to set returns in
			pc+=1
			ret_reg:=code[pc]

			// execute
			fptr := fp.proc_ptr

			// @Debug
			if fptr==nil {panic("nil procedure pointer")}

			switch fp.ret_type {
			case .void:
				dc.CallVoid(dcvm, fptr)
			case .bool:
				 mem.ptr_offset(cast(^u64) memory, ret_reg)^ = auto_cast dc.CallBool(dcvm, fptr)
			case .char:
				 mem.ptr_offset(cast(^u64) memory, ret_reg)^ = auto_cast dc.CallChar(dcvm, fptr)
			case .short:
				 mem.ptr_offset(cast(^u64) memory, ret_reg)^ = auto_cast dc.CallShort(dcvm, fptr)
			case .int:
				 mem.ptr_offset(cast(^u64) memory, ret_reg)^ = auto_cast dc.CallInt(dcvm, fptr)
			case .long:
				 mem.ptr_offset(cast(^u64) memory, ret_reg)^ = auto_cast dc.CallLong(dcvm, fptr)
			case .longlong:
				 mem.ptr_offset(cast(^u64) memory, ret_reg)^ = auto_cast dc.CallLongLong(dcvm, fptr)
			case .float:
				 mem.ptr_offset(cast(^u64) memory, ret_reg)^ = auto_cast dc.CallFloat(dcvm, fptr)
			case .double:
				 mem.ptr_offset(cast(^u64) memory, ret_reg)^ = auto_cast dc.CallDouble(dcvm, fptr)
			case .pointer:
				 mem.ptr_offset(cast(^rawptr) memory, ret_reg)^ = dc.CallPointer(dcvm, fptr)
			case .aggregate:
				 // mem.ptr_offset(cast(^rawptr) memory, ret_reg)^ = dc.CallAggr(dcvm, fptr)
				 panic("unsupported")
			}

			pc += 1

		case .ret: // ret registers...
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
				pc += 5
			}

		case .bne: // rs1, rs2, new pc(3)
			pc+=1
			if mem.ptr_offset(cast(^u64) memory, code[pc])^ != mem.ptr_offset(cast(^u64) memory, code[pc+1])^ {
				pc+=2
				pc = (cast(int) code[pc]<<16) + (cast(int) code[pc+1]<<8) + cast(int) code[pc+2]
			} else {
				pc += 5
			}

		case .bge: // rs1, rs2, new pc(3)
			pc+=1
			if mem.ptr_offset(cast(^i64) memory, code[pc])^ >= mem.ptr_offset(cast(^i64) memory, code[pc+1])^ {
				pc+=2
				pc = (cast(int) code[pc]<<16) + (cast(int) code[pc+1]<<8) + cast(int) code[pc+2]
			} else {
				pc += 5
			}

		case .bgeu: // rs1, rs2, new pc(3)
			pc+=1
			if mem.ptr_offset(cast(^u64) memory, code[pc])^ >= mem.ptr_offset(cast(^u64) memory, code[pc+1])^ {
				pc+=2
				pc = (cast(int) code[pc]<<16) + (cast(int) code[pc+1]<<8) + cast(int) code[pc+2]
			} else {
				pc += 5
			}

		case .blt: // rs1, rs2, new pc(3)
			pc+=1
			if mem.ptr_offset(cast(^i64) memory, code[pc])^ < mem.ptr_offset(cast(^i64) memory, code[pc+1])^ {
				pc+=2
				pc = (cast(int) code[pc]<<16) + (cast(int) code[pc+1]<<8) + cast(int) code[pc+2]
			} else {
				pc += 5
			}

		case .bltu: // rs1, rs2, new pc(3)
			pc+=1
			if mem.ptr_offset(cast(^u64) memory, code[pc])^ < mem.ptr_offset(cast(^u64) memory, code[pc+1])^ {
				pc+=2
				pc = (cast(int) code[pc]<<16) + (cast(int) code[pc+1]<<8) + cast(int) code[pc+2]
			} else {
				pc += 5
			}

		case:
			fmt.println("error: invalid bytecode op", op, cast(u8) op)
			return
		}
	}
}

import "core:dynlib"

link_procinfo :: proc(procinfo: ^ProcInfo) {
	for fp in &procinfo.foreign_procs {
		proc_symbol := fp.symbol
		lib_path := fp.lib_path

		lib, oklib := dynlib.load_library(lib_path, true)
		if !oklib {panic("could not load foreign library")}
		proc_ptr, okaddr := dynlib.symbol_address(lib, proc_symbol)
		if !okaddr {panic("could not find symbol in foreign library")}

		fp.proc_ptr = proc_ptr
	}
}

make_frame :: proc(nwords: int, code: []u8, return_memory: rawptr, return_offsets: []u8, procinfo: ^ProcInfo) -> ^StackFrame {
	// Note: each word is 8 bytes
	memory := mem.alloc(size=nwords*8, allocator=context.temp_allocator)
	frame := new(StackFrame, context.temp_allocator)
	frame^ = {pc=0, code=code, memory=memory, return_memory=return_memory,
		return_offsets = return_offsets}
	frame.constant_pool = procinfo.constant_pool
	frame.foreign_procs = procinfo.foreign_procs
	return frame
}

make_frame_from_procinfo :: proc(using procinfo: ^ProcInfo) -> ^StackFrame {
	memory := mem.alloc(size=memory_nwords, allocator=context.temp_allocator)
	return_offsets := make([]u8, nreturns)
	for i in 0..<nreturns {
		return_offsets[i]=i
	}
	frame := make_frame(memory_nwords, code[:], memory, return_offsets, procinfo)
	return frame
}

// run :: proc() {
// 	fmt.println("Start")
	
// 	proc_add := ProcInfo{nparams=2, nreturns=1, memory_nwords=2}
// 	proc_add.code = [dynamic]u8{
// 		cast(u8) Opcode.add_int, 0, 1, 0,
// 	 	cast(u8) Opcode.ret, 0}[:]
// 	proc_add.constant_pool = ProcConstantPool{raw_data=nil, pointers=nil}

// 	// main program

// 	magic_num := new(i64)
// 	magic_num^ = 59
// 	magic_ret := new(i64)

// 	code := [dynamic]u8{
// 		cast(u8) Opcode.ldc_raw, 0, 1, 1, 1,
// 		cast(u8) Opcode.store_64, 1, 2, 0, 0,

// 		cast(u8) Opcode.ldc_raw, 0, 0, 1, 0,
// 		cast(u8) Opcode.load_64, 3, 0, 0, 1,
// 		cast(u8) Opcode.call, 0, 0, 1, 0, 0,
// 	 	cast(u8) Opcode.ret, 0}[:]

// 	// Constant pool
// 	// pool_entries := [dynamic]ConstantPoolEntry{ProcSig{0,1}}
// 	// pool := ConstantPool {pool_entries=pool_entries[:]}
// 	raw_data := mem.alloc(size=2, allocator=context.temp_allocator)
// 	mem.ptr_offset(cast(^u8) raw_data, 0)^ = 5
// 	mem.ptr_offset(cast(^u8) raw_data, 1)^ = 2
// 	pool := ProcConstantPool{raw_data=raw_data, pointers=nil, procedures={proc_add}}
	
// 	// initialise root stack frame
// 	mem_size := 4
// 	memory := mem.alloc(size=mem_size, allocator=context.temp_allocator)
// 	frame := make_frame(mem_size, code[:], memory, {0})
// 	frame.constant_pool = pool

// 	mem.ptr_offset(cast(^^i64) frame.memory, 3)^ = magic_num
// 	mem.ptr_offset(cast(^^i64) frame.memory, 2)^ = magic_ret

// 	run_frame(frame)

// 	result := mem.ptr_offset(cast(^u64) memory, 0)^
// 	fmt.println("Done:", result, "magic", magic_ret^)
// }