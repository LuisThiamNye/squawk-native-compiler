package interpreter

import "core:mem"
import "core:fmt"


Type_Info :: struct {
	tag: enum {
		void, pointer,
		bool, integer, float,
		// procedure,
		static_array, struct_, enum_,
		// any,
	},
	using alt: struct {
		integer: Type_Integer,
		float: Type_Float,
		pointer: Type_Pointer,
		// procedure: Type_Procedure,
		struct_: Type_Struct,
		static_array: Type_Static_Array,
		enum_: Type_Enum,
	},
}

Type_Integer :: struct {
	nbits: u16,
	signedP: bool,
}

Type_Float :: struct {
	nbits: u16,
}

Type_Pointer :: struct {
	value_type: ^Type_Info,
}

// Type_Procedure :: struct {
// 	param_types: []^Type_Info,
// 	return_types: []^Type_Info,
// }

Type_Struct :: struct {
	name: string,
	members: []Type_Struct_Member,
}

Type_Struct_Member :: struct {
	name: string,
	type: ^Type_Info,
	byte_offset: int,
}

Type_Static_Array :: struct {
	count: int,
	item_type: ^Type_Info,
}

Type_Enum :: struct {
	backing_type: ^Type_Info,
}

Rt_Any :: struct {
	type: ^Type_Info,
	data: rawptr,
}

Rt_Counted_Array :: struct {
	count: int,
	data: rawptr,
}

Rt_Keyword :: struct {
	symbol: ^InternedSymbol,
}

type_byte_size :: proc(info: ^Type_Info) -> int {
	shift_right_rounding_up :: #force_inline proc(#any_int x: int, $n: uint) -> int {
		addee :: (1<<n)-1
		return (x+addee)>>n
	}
	switch info.tag {
	case .void: return 0
	case .bool: return 8
	case .pointer: return size_of(rawptr)
	case .integer: return shift_right_rounding_up(info.integer.nbits, 3)
	case .float: return shift_right_rounding_up(info.float.nbits, 3)
	case .struct_:
		total := 0
		for member in info.struct_.members {
			total += type_byte_size(member.type)
		}
		return total
	case .static_array:
		item_size := type_byte_size(info.static_array.item_type)
		return item_size * info.static_array.count
	case .enum_: return type_byte_size(info.enum_.backing_type)
	case:
		fmt.panicf("unreachable, unexpected data %v\n", info)
	}
}

print_rt_any :: proc(val: Rt_Any, indent_level := 0) {
	print_indent :: proc(level: int) {
		for _ in 0..<level {fmt.print(" ")}
	}
	info := val.type
	switch info.tag {
	case .void: fmt.println("void")
	case .pointer:
		data := cast(^rawptr) val.data
		fmt.print("*")
		fmt.print(data^)
	case .bool:
		fmt.print((cast(^bool) val.data)^)
	case .integer:
		if info.integer.signedP {
			fmt.print((cast(^i64) val.data)^)
		} else {
			fmt.print((cast(^u64) val.data)^)
		}
	case .float:
		fmt.println((cast(^f64) val.data)^)
	case .struct_:
		var := info.struct_
		fmt.print("#")
		fmt.print(var.name)
		fmt.print("{\n")
		level := indent_level+2
		for member, i in var.members {
			if i != 0 {
				fmt.print(",\n")
			}
			print_indent(level)
			fmt.print(":")
			fmt.print(member.name)
			fmt.print(" ")
			print_rt_any({
				type=member.type,
				data=mem.ptr_offset(cast(^u8) val.data, member.byte_offset)},
				level)
		}
		fmt.print(" }")
	case .static_array:
		fmt.print("[")
		base := val.data
		var := info.static_array
		item_size := type_byte_size(var.item_type)
		for i in 0..<var.count {
			data := mem.ptr_offset(cast(^u8) base, i*item_size)
			print_rt_any({type=var.item_type, data=data})
		}
		fmt.print("]")
	case .enum_: print_rt_any({type=info.enum_.backing_type, data=val.data})
	}
}

init_standard_string_typeinfo :: proc(ti: ^Type_Info) {
	ti1 := new(Type_Info)
	ti1.tag = .integer
	ti1.integer = Type_Integer{nbits=64, signedP=true}
	ti2 := new(Type_Info)
	ti2.tag = .pointer
	tv := new(Type_Info)
	tv.tag = .void
	ti2.pointer = Type_Pointer{value_type=tv}
	ti_mem_1 := new(Type_Struct_Member)
	ti_mem_1^ = {name="count", type=ti1, byte_offset=0}
	ti_mem_2 := new(Type_Struct_Member)
	ti_mem_2^ = {name="data", type=ti2, byte_offset=8}
	members := make([]Type_Struct_Member, 2)
	members[0] = ti_mem_1^
	members[1] = ti_mem_2^

	ti.tag = .struct_
	ti.struct_ = Type_Struct{name="String", members=members}
}

str_to_typeinfo :: proc(s: string) -> (ret: ^Type_Info) {
	ret = new(Type_Info)
	if s[0]=='*' {
		inner := s[1:]
		v := str_to_typeinfo(inner)
		ret.tag = .pointer
		ret.pointer = Type_Pointer{value_type=v}
	}
	switch s {
	case "u8":
		ret.tag = .integer
		ret.integer = Type_Integer{signedP=false, nbits=8}
	case "u16":
		ret.tag = .integer
		ret.integer = Type_Integer{signedP=false, nbits=16}
	case "u32":
		ret.tag = .integer
		ret.integer = Type_Integer{signedP=false, nbits=32}
	case "u64":
		ret.tag = .integer
		ret.integer = Type_Integer{signedP=false, nbits=64}
	case "s8":
		ret.tag = .integer
		ret.integer = Type_Integer{signedP=true, nbits=8}
	case "s16":
		ret.tag = .integer
		ret.integer = Type_Integer{signedP=true, nbits=16}
	case "s32":
		ret.tag = .integer
		ret.integer = Type_Integer{signedP=true, nbits=32}
	case "s64":
		ret.tag = .integer
		ret.integer = Type_Integer{signedP=true, nbits=64}
	case "uint":
		ret.tag = .integer
		ret.integer = Type_Integer{signedP=false, nbits=64}
	case "int":
		ret.tag = .integer
		ret.integer = Type_Integer{signedP=true, nbits=64}
	case "rawptr":
		ret.tag = .integer
		ret.integer = Type_Integer{signedP=true, nbits=64}
	case "String":
		init_standard_string_typeinfo(ret)
	case:
		panic("unsupported string to typeinfo")
	}
	return
}

typeinfo_get_member :: proc(typeinfo: ^Type_Info, member_name: string) -> ^Type_Struct_Member {
	#partial switch typeinfo.tag {
	case .struct_:
		ti := typeinfo.struct_
		for mem in &ti.members {
			if mem.name == member_name {
				return &mem
			}
		}
	case:
		panic("!!!")
	}
	panic("unreachable")
}