package bytecode_runner

// 64-bit little endian architecture

Opcode :: enum u8 {
	// RISC-V inspiration
	// arithmetric operations on registers (64-bit)
	add_int,
	addi_int, // add immediate
	sub_int,
	mul_int,
	// mul_i32,
	div_sint,
	// div_s32,
	div_uint,
	// div_u32,
	rem_sint, // modulo
	// rem_s32,
	rem_uint,
	// rem_u32,

	// set less than
	// slt,
	// slti,
	// sltu,
	// sltiu,

	// Binary Logic
	and,
	or,
	xor,
	andi,
	ori,
	xori,
	shiftl,
	shiftr,
	ashiftr, // arithmetic shift preserves sign
	shiftli,
	shiftri,
	ashiftri,

	ldc_raw,
	ldc_ptr,
	// signed or unsigned load correspond to sign extension
	load_64,
	load_32,
	load_u32,
	load_16,
	load_u16,
	load_8,
	load_u8,
	store_64,
	store_32, // stores copy the least significant bytes
	store_16,
	store_8,
	copy,

	goto,
	beq,
	bne,
	bge,
	bgeu,
	blt,
	bltu,

	call,
	ret,

	// floating point
	add_f32,
	sub_f32,
	mul_f32,
	div_f32,
	sqrt_f32,
	min_f32,
	max_f32,

	eq_f32,
	lt_f32,
	le_f32,
	// class_f32,

	f32_to_s64,
	s64_to_f32,

	eq_f64,
	lt_f64,
	le_f64,
	// class_f64,

	f64_to_s64,
	s64_to_f64,
	f32_to_f64,
	f64_to_f32,
}

StackFrame :: struct {
	pc: int,
	code: []u8,
	memory: rawptr,
	constant_pool: ProcConstantPool,

	// nreturns: u8,
	return_memory: rawptr,
	return_offsets: []u8,
}

ProcInfo :: struct {
	nparams: u8,
	nreturns: u8,
	code: []u8,
	memory_nwords: int,
	constant_pool: ProcConstantPool,
}

ProcConstantPool :: struct {
	// raw_data_size: u16
	raw_data: rawptr,
	pointers: []rawptr,
	procedures: []ProcInfo,
}

// TypeInfoTag :: enum {
// 	integer,
// 	float,
// 	pointer,
// 	struct,
// 	union,
// 	string,
// 	array
// }

// TypeInfo :: struct {

// }

// Proc_Type :: struct {
// 	param_types: []TypeInfo,
// 	ret_types: []TypeInfo,
// }

// ProcedureStackFrameInfo :: struct {
// 	memory_nwords: int,
// }

// CpEntry_Bytes :: struct {
// 	msb_offset: u16,
// 	lsb_offset: u16,
// }

// CpEntry_

// ConstantPoolEntry :: union {
// 	ProcSig,
// 	CpEntry_Byte,
// }

// Process :: struct {
// 	stack: [dynamic]StackFrame,
// 	constant_pool: ConstantPool,
// }