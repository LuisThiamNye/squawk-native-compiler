package interpreter

import "core:mem"
import "core:fmt"


Type_Info_Tag :: enum {
	nil, // invalid value
	void, pointer,
	bool, integer, float,
	// procedure,
	static_array, struct_, enum_,
	// any,
	intrinsic,

	// untyped
	nilptr,
}

Type_Info :: struct {
	tag: Type_Info_Tag,
	using alt: struct {
		integer: Type_Integer,
		float: Type_Float,
		pointer: Type_Pointer,
		// procedure: Type_Procedure,
		struct_: Type_Struct,
		static_array: Type_Static_Array,
		enum_: Type_Enum,
		intrinsic: Type_Intrinsic,
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
	count: i64,
	item_type: ^Type_Info,
}

Type_Enum :: struct {
	backing_type: ^Type_Info,
}



Type_Intrinsic :: struct {
	tag: enum {member_access,},
}



Rt_Any :: struct {
	type: ^Type_Info,
	data: rawptr,
}

Rt_Counted_Array :: struct {
	count: i64,
	data: rawptr,
}

Rt_Keyword :: struct {
	symbol: ^InternedSymbol,
}

Rt_String :: struct {
	count: i64,
	data: rawptr,
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
		return item_size * auto_cast info.static_array.count
	case .enum_: return type_byte_size(info.enum_.backing_type)
	case .nilptr: panic("!!")
	case .nil: panic("!!")
	case .intrinsic: fallthrough
	case:
		fmt.panicf("unreachable, unexpected data %v\n", info)
	}
	panic("unreachable")
}

typeinfo_equiv :: proc(info1: ^Type_Info, info2: ^Type_Info) -> bool {
	
	if info1 == info2 {return true}
	tag := info1.tag
	if tag != info2.tag {return false}

	return false
	// switch tag {
	// case .void: return true
	// case .bool: return true
	// case .pointer:
	// 	return typeinfo_equiv(info1.pointer.value_type, info2.pointer.value_type)
	// case .integer:
	// 	return info1.integer.signedP==info2.integer.signedP &&
	// 		info1.integer.nbits==info2.integer.nbits
	// case .float:
	// 	return info1.float.nbits==info2.float.nbits
	// case .struct_:
	// 	s1 := info1.struct_
	// 	s2 := info2.struct_
	// 	if s1.name!=s2.name {return false}
	// 	if len(s1.members) != len(s2.members) {return false}
	// 	for m1, i in s1.members {
	// 		m2 := s2.members[i]
	// 		if m1.byte_offset != m2.byte_offset ||
	// 			m1.name != m2.name {return false}
	// 		if !typeinfo_equiv(m1.type, m2.type) {return false}
	// 	}
	// 	return true

	// case .static_array:
	// 	panic("unsupported; TODO")
	// case .enum_:
	// 	return typeinfo_equiv(info1.enum_.backing_type, info2.enum_.backing_type)
	// case .intrinsic: fallthrough
	// case:
	// 	fmt.panicf("unreachable, unexpected data %v\n", tag)
	// }
	// panic("unreachable")
}

wrap_data_in_any :: proc(ptr_to_val: rawptr, val_type: ^Type_Info) -> Rt_Any {
	ma : Rt_Any
	ma.type = val_type
	if val_type.tag==.pointer {
		ma.data = (cast(^rawptr) ptr_to_val)^
	} else {
		// spills
		ma.data = ptr_to_val
	}
	return ma
}

get_pointer_to_member :: proc(val: Rt_Any, member: Type_Struct_Member) -> rawptr {
	return mem.ptr_offset(cast(^u8) val.data, member.byte_offset)
}

get_member_value :: proc(val: Rt_Any, member: Type_Struct_Member) -> Rt_Any {
	data := get_pointer_to_member(val, member)
	return wrap_data_in_any(data, member.type)
}

print_rt_any :: proc(val: Rt_Any, indent_level := 0) {
	print_indent :: proc(level: int) {
		for _ in 0..<level {fmt.print(" ")}
	}
	info := val.type
	if info==typeinfo_of_typeinfo {
		fmt.print("(typeinfo\n")
		level := indent_level+ 2
		print_indent(level)
		assert(val.data!=nil)
		print_typeinfo(cast(^Type_Info) val.data, level)
		fmt.print(")")
		return
	}
	switch info.tag {
	case .void: fmt.println("void")
	case .pointer:
		// data := cast(^rawptr) val.data
		// fmt.print("*")
		// fmt.print(data^)
		if val.data == nil {
			fmt.print("nilptr")
		} else {
			if info.pointer.value_type == typeinfo_of_void {
				fmt.printf("<ptr_0x%p>", val.data)
			} else {
				v : Rt_Any
				v.type = val.type.pointer.value_type
				if v.type.tag == .pointer {
					v.data = (cast(^rawptr) val.data)^
				} else {
					v.data = val.data
				}
				fmt.print("*")
				print_rt_any(v, indent_level+1)
			}
		}
	case .bool:
		fmt.print((cast(^bool) val.data)^)
	case .integer:
		if info.integer.signedP {
			switch info.integer.nbits {
			case 8:
				fmt.print((cast(^i8) val.data)^)
			case 16:
				fmt.print((cast(^i16) val.data)^)
			case 32:
				fmt.print((cast(^i32) val.data)^)
			case 64:
				fmt.print((cast(^i64) val.data)^)
			case: 
				panic("unsupported nbits")
			}
		} else {
			switch info.integer.nbits {
			case 8:
				fmt.print((cast(^u8) val.data)^)
			case 16:
				fmt.print((cast(^u16) val.data)^)
			case 32:
				fmt.print((cast(^u32) val.data)^)
			case 64:
				fmt.print((cast(^u64) val.data)^)
			case: 
				panic("unsupported nbits")
			}
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
			fmt.print(member.byte_offset)
			fmt.print(" ")
			fmt.print(":")
			fmt.print(member.name)
			// fmt.print("\n")
			// print_indent(level+1)
			fmt.print(" ")
			level2 := level+len(member.name)+3
			ma := get_member_value(val, member)
			print_rt_any(ma, level2)
		}
		fmt.print(" }")
	case .static_array:
		fmt.print("[")
		base := val.data
		var := info.static_array
		item_size := type_byte_size(var.item_type)
		for i in 0..<var.count {
			data : rawptr = mem.ptr_offset(cast(^u8) base, i* auto_cast item_size)
			el := wrap_data_in_any(data, var.item_type)
			print_rt_any(el)
			fmt.print(" ")
		}
		fmt.print("]")
	case .enum_:
		assert(info.enum_.backing_type.tag != .pointer)
		print_rt_any({type=info.enum_.backing_type, data=val.data})
	case .intrinsic:
		fmt.print("<intrinsic>")
	case .nilptr:
		fmt.print("nilptr")
	case .nil: panic("!!")
	}
}

init_standard_string_typeinfo :: proc(interp: ^Interp, ti: ^Type_Info) {
	ti1 := interp.typeinfo_interns.s64
	ti2 := typeinfo_wrap_pointer(interp, typeinfo_of_void)
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

str_to_new_typeinfo :: proc(s: string) -> (ret: ^Type_Info) {
	ret = new(Type_Info)
	// if s[0]=='*' {
	// 	inner := s[1:]
	// 	v := str_to_new_typeinfo(inner)
	// 	ret.tag = .pointer
	// 	ret.pointer = Type_Pointer{value_type=v}
	// }
	switch s {
	case "bool":
		ret.tag = .bool
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
		// ret.tag = .integer
		// ret.integer = Type_Integer{signedP=false, nbits=64}
		ret.tag = .pointer
		ret.pointer.value_type = typeinfo_of_void
	case:
		panic("unsupported string to typeinfo")
	}
	return
}

typeinfo_get_member :: proc(typeinfo: ^Type_Info, member_name: string) -> ^Type_Struct_Member {
	#partial switch typeinfo.tag {
	case .struct_:
		ti := typeinfo.struct_
		for member in &ti.members {
			if member.name == member_name {
				return &member
			}
		}
		fmt.panicf("member not found: %v\n", member_name)
	case:
		panic("this type does not support members")
	}
	panic("unreachable")
}

print_typeinfo :: proc(info: ^Type_Info, indent_level := 0) {
	print_indent :: proc(level: int) {
		for _ in 0..<level {fmt.print(" ")}
	}
	if info == typeinfo_of_typeinfo {
		fmt.print("Type-Info")
		return
	}
	switch info.tag {
	case .void: fmt.print("void")
	case .bool: fmt.print("bool")
	case .pointer:
		fmt.print("*")
		print_typeinfo(info.pointer.value_type, indent_level+1)
	case .integer:
		if info.integer.signedP {
			fmt.printf("s%v", info.integer.nbits)
		} else {
			fmt.printf("u%v", info.integer.nbits)
		}
	case .float:
		fmt.printf("f%v", info.float.nbits)
	case .struct_:
		fmt.print("(struct ")
		fmt.print(info.struct_.name)
		level := indent_level+2
		for member in info.struct_.members {
			fmt.println()
			print_indent(level)
			fmt.print(member.byte_offset)
			fmt.print(" ")
			fmt.printf(":%v ", member.name)
			print_typeinfo(member.type, level+len(member.name)+2)
		}
		fmt.print(" )")
	case .static_array:
		fmt.print("[")
		print_typeinfo(info.static_array.item_type, indent_level+1)
		fmt.printf(" %v]", info.static_array.count)

	case .enum_:
		fmt.print("(enum\n")
		level := indent_level+2
		print_indent(level)
		print_typeinfo(info.enum_.backing_type, level)
		fmt.print(" )")
	case .nilptr:
		fmt.print("nilptr")
	case .nil: panic("!! nil type tag")
	case .intrinsic: fallthrough
	case:
		fmt.panicf("unreachable, unexpected data %v\n", info)
	}
}