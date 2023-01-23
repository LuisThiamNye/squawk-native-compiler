package semantics

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

spec_coerce_to_equal_types :: proc(specs: []^Spec) -> (ok: bool) {
	// TODO
	return false
}