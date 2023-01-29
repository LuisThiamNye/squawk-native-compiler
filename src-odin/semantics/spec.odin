package semantics

import "core:mem"

// relates to memory layout in the program
Spec :: union {
	Spec_Fixed,
	Spec_Jump,
	Spec_Trait,
	Spec_Indeterminate,
	Spec_Intersection,
	Spec_NonVoid,
	Spec_Number,
}

void_spec : Spec = Spec_Fixed{typeinfo=Type_Void{}}
boolean_spec : Spec = Spec_Fixed{typeinfo=Type_Integer{}} // FIXME proper bools

Spec_Number :: struct {}

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
	Type_Alias,
	Type_Integer,
	Type_Float,
	Type_Struct,
	Type_Void,
}

Type_Void :: struct {}

// TypeId :: int
// typeid_boolC : TypeId = 0

Type_Alias :: struct {
	// id: TypeId,
	backing_type: ^TypeInfo,
}

Type_Integer :: struct {
	nbits: u8,
}

Type_Float :: struct {
	nbits: u8,
}

Type_Struct :: struct {
	// members: []Type_Struct_Member
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