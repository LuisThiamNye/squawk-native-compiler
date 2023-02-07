package semantics

import "core:mem"
import "core:fmt"

// relates to memory layout in the program
Spec :: union {
	Spec_Fixed,
	Spec_Jump,
	Spec_Trait,
	Spec_Indeterminate,
	Spec_Intersection,
	Spec_NonVoid,
	Spec_Number,
	Spec_String,
}

void_spec : Spec = Spec_Fixed{typeinfo=Type_Void{}}
boolean_spec : Spec = Spec_Fixed{typeinfo=Type_Integer{}} // FIXME proper bools

Spec_Number :: struct {}
Spec_String :: struct {}

Spec_NonVoid :: struct {}

Spec_Indeterminate :: struct {
	specs: []Spec, // result must be one of thesse
}

Spec_Intersection :: struct {
	specs: []Spec,
}

Spec_Jump :: struct {}

Spec_Trait :: struct {
	id: int,
}

Spec_Fixed :: struct {
	typeinfo: TypeInfo,
}

TypeInfo :: union {
	Type_Void,
	Type_Pointer,
	Type_Bool,
	Type_Integer,
	Type_Float,
	Type_Struct,
	Type_Alias,
}

Type_Void :: struct {}
Type_Bool :: struct {}


Type_Integer :: struct {
	nbits: u16,
	signedP: bool,
}

Type_Float :: struct {
	nbits: u16,
}

Type_Pointer :: struct {
	value_type: ^TypeInfo,
}

Type_Struct :: struct {
	name: string,
	members: []Type_Struct_Member,
}

Type_Struct_Member :: struct {
	name: string,
	type: ^TypeInfo,
	byte_offset: int,
}

Type_Alias :: struct {
	backing_type: ^TypeInfo,
}

Rt_Any :: struct {
	type: ^TypeInfo,
	data: rawptr,
}

type_byte_size :: proc(info: ^TypeInfo) -> int {
	shift_right_rounding_up :: #force_inline proc(#any_int x: int, $n: uint) -> int {
		addee :: (1<<n)-1
		return (x+addee)>>n
	}
	switch var in info {
	case Type_Void: return 0
	case Type_Pointer: return size_of(rawptr)
	case Type_Bool: return 1
	case Type_Integer: return shift_right_rounding_up(var.nbits, 3)
	case Type_Float: return shift_right_rounding_up(var.nbits, 3)
	case Type_Struct:
		total := 0
		for member in var.members {
			total += type_byte_size(member.type)
		}
		return total
	case Type_Alias: return type_byte_size(var.backing_type)
	case: panic("unreachable")
	}
}

print_rt_any :: proc(val: Rt_Any) {
	switch var in val.type {
	case Type_Void: fmt.println("void")
	case Type_Pointer:
		data := cast(^rawptr) val.data
		fmt.print("*")
		fmt.println(data^)
	case Type_Bool:
		fmt.println((cast(^bool) val.data)^)
	case Type_Integer:
		if var.signedP {
			fmt.println((cast(^i64) val.data)^)
		} else {
			fmt.println((cast(^u64) val.data)^)
		}
	case Type_Float:
		fmt.println((cast(^f64) val.data)^)
	case Type_Struct:
		fmt.print("#")
		fmt.print(var.name)
		fmt.print("{")
		for member, i in var.members {
			if i != 0 {fmt.print(", ")}
			fmt.print(":")
			fmt.print(member.name)
			fmt.print(" ")
			print_rt_any({
				type=member.type,
				data=mem.ptr_offset(cast(^u8) val.data, member.byte_offset)})
		}
		fmt.println("}")
	case Type_Alias: print_rt_any({type=var.backing_type, data=val.data})
	}
}

spec_to_typeinfo :: proc(spec: ^Spec) -> ^TypeInfo {
	#partial switch sp in spec {
	case Spec_Fixed:
		return &sp.typeinfo
	case Spec_String:
		ti1 := new(TypeInfo)
		ti1^ = Type_Integer{nbits=64, signedP=true}
		ti2 := new(TypeInfo)
		ti2^ = Type_Pointer{value_type=auto_cast new(Type_Void)}
		ti_mem_1 := new(Type_Struct_Member)
		ti_mem_1^ = {name="count", type=ti1, byte_offset=0}
		ti_mem_2 := new(Type_Struct_Member)
		ti_mem_2^ = {name="data", type=ti2, byte_offset=8}
		members := make([]Type_Struct_Member, 2)
		members[0] = ti_mem_1^
		members[1] = ti_mem_2^

		ti := new(TypeInfo)
		ti^ = Type_Struct{name="String", members=members}
		return ti
	case: fmt.panicf("unhandled case for spec->typeinfo: %v\n", spec)
	}
}


spec_coerce_to_equal_types :: proc(specs: []^Spec) -> (_spec: ^Spec, ok: bool) {
	if len(specs)==1 {
		return specs[0], true
	} else if len(specs)==0 {
		panic("zero specs provided")
	}
	equal := true
	prev_spec := specs[0]
	for i in 1..<len(specs) {
		spec := specs[i]

		eq := false
		#partial switch s in spec {
		case Spec_Jump:
			continue
		case Spec_Number:
			#partial switch ps in prev_spec {
			case Spec_Number:
				eq = true
			}
		}

		if eq {
			prev_spec = spec
		} else {
			equal=false
			break
		}
	}
	if equal {
		return prev_spec, true
	}
	return nil, false
}