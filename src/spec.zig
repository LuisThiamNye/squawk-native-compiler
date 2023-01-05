const std = @import("std");
const mem = std.mem;

const Spec = union(enum) {
    void,
    jump,
    class: JClass,
    unity: Unity,

    pub fn unify(specs: []Spec) Spec {
        return .{ .unity = .{ .specs = specs } };
    }
};

const Unity = struct {
    specs: []Spec,
};

// const Class = union(enum) {
// 	char,
// };

const JClassSpecies = enum {
    bool,
    byte,
    short,
    char,
    int,
    long,
    float,
    double,
    object,
    array,
};

const JClass = union(JClassSpecies) {
    // bool: bool,
    // byte: i8,
    // short: i16,
    // char: u16,
    // int: i32,
    // long: i64,
    // float: JFloat,
    // double: JDouble,
    object: JObject,
    array: JArray,
};

const JObject = struct {
    internal_name: []u8,
};

const JArray = struct {
    object: JObjClass,
    ndims: u8,
};

// const JFloat = union(enum) {
//     nan,
//     pos_inf,
//     neg_inf,
//     value: f32,
// };

// const JDouble = union(enum) {
//     nan,
//     pos_inf,
//     neg_inf,
//     value: f64,
// };
