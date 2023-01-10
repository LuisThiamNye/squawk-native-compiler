
Type_NumberSpecies :: enum {
	integer, float,
}

Type_Number :: struct {
	species: Type_NumberSpecies,
	nbits: u8,
}

Type_Float :: struct {

}

Spec_TypeTag :: enum

Spec_Fixed_Tag :: enum {
	void, jump, unity, single,
}

Spec_Fixed :: union {

}

NodeSpec :: union {
	Spec_Dependent,
	Spec_Fixed,
}