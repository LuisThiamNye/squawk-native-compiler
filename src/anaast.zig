const specN = @import("spec.zig");
const Spec = specN.Spec;


pub const Local = struct {
	name: []u8,
};

pub const AnaNode = struct {
	spec: Spec,
	kind: Kind,

	pub const Kind = union(enum) {
		void,
		do: Do,
		assign_local: AssignLocal,
		let: Let,
		keyword: Keyword,
		integer: Integer,
		char: Char,
		string: String,
		if_true: IfTrue,
	};
};

pub const Do = struct {
	children: []AnaNode,
};

pub const AssignLocal = struct {
	local: *Local,
	val: AnaNode,
	returnP: bool,
};

pub const Let = struct {
	local: *Local,
	local_val: AnaNode,
	child: AnaNode,
};

pub const Bool = struct {
	trueP: bool,
};

pub const Keyword = struct {
	token: []u8,
};

pub const String = struct {
	text: []u8,
};

pub const Char = struct {
	value: u32,
};

const bigint_word_type = u8;
pub const Integer = struct {
	// big-endian; most significant word at index 0
	// there must not be leading zero words
	magnitude: []bigint_word_type,
};

pub const IfTrue = struct {
	cond: AnaNode,
	then: AnaNode,
	fail: AnaNode,
};

pub const NumCmp2 = struct {
	op: Op,
	ref: bool,
	arg1: AnaNode,
	arg2: AnaNode,

	pub const Op = enum {
		equal,
		lt,
		lte,
		gt,
		gte,
	};
};