const std = @import("std");
const mem = std.mem;
const compast = @import("compast.zig");
const anaast = @import("anaast.zig");
const numbers = @import("numbers.zig");
const specN = @import("spec.zig");
const Spec = specN.Spec;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const StringHashMap = std.hash_map.StringHashMap;
const assert = std.debug.assert;

const Coll = compast.Coll;
const ca = compast;
const AnaNode = anaast.AnaNode;
const ast = anaast;

pub const SpecialFormTag = enum {
    do,
    assign,
    let,
    ifbranch,
};

pub fn make_sf_map(allocator: Allocator) StringHashMap {
    var m = StringHashMap().init(allocator, SpecialFormTag);
    m.put("do", .do);
    m.put("set!", .assign);
    m.put("let", .let);
    m.put("if", .ifbranch);
    m.put("==", .identicalP);
    m.put("=", .equal);
    m.put("<=", .lte);
    m.put("<", .lt);
    m.put(">=", .gte);
    m.put(">", .gt);
    return m;
}

pub const ScopeBinding = union(enum) {
    local: ast.Local,
};

pub const ScopeStackFrame = struct {
    bindings: []ScopeBinding,
};

pub const AnaCtx = struct {
    sf_map: StringHashMap,
    result_ctx: ResultCtx,
    scope_stack: ArrayList(ScopeStackFrame),
    allocator: Allocator,

    pub const ResultCtx = union(enum) {
        statement,
        expression,
    };

    pub fn init(allocator: Allocator) AnaCtx {
        return AnaCtx{
            .sf_map = make_sf_map(allocator),
            .result_ctx = .expression,
            .allocator = allocator,
        };
    }

    pub fn resolve_special_form_tag(self: *AnaCtx, sym: []u8) ?SpecialFormTag {
        return self.sf_map.get(sym);
    }

    pub fn resolve_local_binding(self: *AnaCtx, name: []u8) ?ScopeBinding {}

    pub fn push_local(self: *AnaCtx, local: ast.Local) void {}

    pub fn pop_local(self: *AnaCtx, local: ast.Local) void {}
};

pub fn analyse_body(ctx: AnaCtx, nodes: []ca.Node) !AnaNode {
    if (nodes.len == 0) return .void;
    var anas = ctx.allocator.alloc(AnaNode, nodes.len);

    // Body
    const prev_result_ctx = ctx.result_ctx;
    ctx.result_ctx = .statement;
    const tail_idx = nodes.len - 1;
    var i = 0;
    while (i < tail_idx) : (i += 1) {
        anas[i] = try analyse_node(ctx, nodes[i]);
    }
    // Tail
    ctx.result_ctx = prev_result_ctx;
    anas[tail_idx] = try analyse_node(ctx, nodes[tail_idx]);
    return .{ .do = .{ .children = anas } };
}

pub fn analyse_do(ctx: AnaCtx, nodes: []ca.Node) !AnaNode {
    return analyse_body(ctx, nodes[1..]);
}

pub fn analyse_assign(ctx: AnaCtx, nodes: []ca.Node) !AnaNode {
    const children = nodes.children;
    if (children.len != 3) return error.SetMustHaveTwoArgs;
    const target = children[1];
    const valdecl = children[2];

    if (target == .symbol) {
        const sym = target.symbol.token;
        const noretP = ctx.result_ctx == .statement;
        const binding = ctx.resolve_local_binding(sym);
        switch (binding) {
            .local => |*local| {
                ctx.result_ctx = .expression;
                const v = try analyse_node(ctx, valdecl);
                return .{ .assign_local = .{
                    .local = local,
                    .val = v,
                    .returnP = !noretP,
                } };
            },
            else => return error.UnsupportedAssignBinding,
        }
    }

    return error.CouldNotResolveSetTarget;
}

pub fn analyse_let(ctx: AnaCtx, nodes: []ca.Node) !AnaNode {
    const children = nodes.children;
    if (children.len != 4) return error.WrongNumberOfChildren;

    const symdecl = children[1];
    if (symdecl != .symbol) return error.BindingNotSymbol;
    const valdecl = children[2];
    const childdecl = children[3];

    const local = ast.Local{ .name = symdecl.symbol.token };

    const local_val = try analyse_node_with_res(.expression, ctx, valdecl);
    ctx.push_local(local);
    const child = try analyse_node(ctx, childdecl);
    ctx.pop_local(local);

    return .{ .let = .{
        .local = local,
        .local_val = local_val,
        .child = child,
    } };
}

pub fn analyse_symbol(ctx: AnaCtx, node: ca.Symbol) !AnaNode {
    const text = node.token;
    if (mem.eql(u8, text, "nil")) return .void;
    if (mem.eql(u8, text, "true")) return .{ .bool = .{ .trueP = true } };
    if (mem.eql(u8, text, "false")) return .{ .bool = .{ .trueP = false } };

    if (ctx.resolve_local_binding(text)) |binding| {
        switch (binding) {
            .local => |*local| return .{ .local_use = .{ .local = local } },
        }
    }
    return error.CouldNotResolveSymbol;
}

pub fn analyse_keyword(ctx: AnaCtx, node: ca.Keyword) !AnaNode {
    _ = ctx;
    return .{ .keyword = .{ .token = node.token } };
}

pub fn analyse_kwlookup(ctx: AnaCtx, node: ca.Keyword) !AnaNode {
    _ = ctx;
    _ = node;
    return error.Unsupported;
}

pub fn analyse_number(ctx: AnaCtx, node: ca.Number) !AnaNode {
    const text = node.token;
    const n = text.len;
    if (text[0] == '0') {
        if (n < 3) return error.ShortNumberInput;
        if (text[1] == 'x') {
            // hex
            const hexstr = text[2..];
            const mag = try numbers.int_str_to_array(ast.bigint_word_type, hexstr, 16, ctx.allocator);
            return .{ .integer = .{ .magnitude = mag } };
        } else {
            return error.InvalidAfterZero;
        }
    }
    // base 10
    const mag = try numbers.int_str_to_array(ast.bigint_word_type, text, 10, ctx.allocator);
    return .{ .integer = .{ .magnitude = mag } };
}

pub fn analyse_string(ctx: AnaCtx, node: ca.String) !AnaNode {
    _ = ctx;
    return .{ .string = .{ .text = node.token } };
}

pub fn analyse_char(ctx: AnaCtx, node: ca.Char) !AnaNode {
    _ = ctx;
    _ = node;
    var ch: u32 = undefined;
    const text = node.token;
    if (text.len == 1) {
        text = text[0];
    } else if (mem.eql(text, "newline")) {
        char = '\n';
    } else {
        return error.InvalidChar;
    }
    return .{ .kind = .{ .char = .{ .value = ch } }, .spec = .{ .class = .{ .char = ch } }, .spec = .{ .class = .char } };
}

// pub fn coerce_and_join_branches(ctx: AnaCtx, nodes: []ca.Node) !Spec {
//     assert(nodes.len > 0);
//     // all jumps -> jump
//     // at least one void, rest are jumps -> void
//     // var nvoids = 0;
//     var njumps = 0;
//     var first_noret_idx = 0;
//     var i = 0;
//     while (true) : (i += 1) {
//         if (i < nodes.len) {
//             const node = nodes[i];
//             const spec = node.spec;
//             switch (spec) {
//                 .void => {}, //nvoids+=1,
//                 .jump => njumps += 1,
//                 else => {
//                     first_noret_idx = i;
//                     break;
//                 },
//             }
//         } else {
//             if (njumps == nodes.len) return .jump;
//             return .void;
//         }
//     }
// }

pub fn analyse_ifbranch(ctx: AnaCtx, nodes: []ca.Node) !AnaNode {
    if (nodes.len != 4) return error.WrongNumberOfChildren;
    const cond = try analyse_node_with_res(.expression, ctx, nodes[1]);
    const then = try analyse_node(ctx, nodes[2]);
    const fail = try analyse_node(ctx, nodes[3]);

    const spec = Spec.unify(.{ then.spec, fail.spec });
    return .{ //
        .kind = .{ .if_true = .{ .cond = cond, .then = then, .fail = fail } },
        .spec = spec,
    };
}

pub fn anasf_numcmp(ctx: AnaCtx, args: []ca.Node, op: ast.NumCmp2.Op) !AnaNode {
    if (args.len != 2) return error.WrongNumberOfChildren;
    const anas = analyse_args(ctx, args);
    const a1 = anas[0];
    const a2 = anas[1];
    // TODO coerce the pair
    return .{
        .kind = .{ .numcmp2 = .{ .op = op, .ref = false, .arg1 = a1, .arg2 = a2 } },
        .spec = .{ .class = .bool },
    };
}

pub fn anasf_identity_check(ctx: AnaCtx, args: []ca.Node) !AnaNode {
    if (args.len != 2) return error.WrongNumberOfChildren;
    const anas = analyse_args(ctx, args);
    const a1 = anas[0];
    const a2 = anas[1];
    // TODO ensure both are refs
    return .{
        .kind = .{ .numcmp2 = .{ .op = .equal, .ref = true, .arg1 = a1, .arg2 = a2 } },
        .spec = .{ .class = .bool },
    };
}

pub fn analyse_poly_invoke(ctx: AnaCtx, nodes: []ca.Node) !AnaNode {
    _ = ctx;
    _ = nodes;
    return error.Unsupported;
}

pub fn analyse_list(ctx: AnaCtx, node: Coll) !AnaNode {
    if (node.children.len == 0) return error.NoListChildren;
    const child1 = node.children[0];
    switch (child1) {
        .keyword => try analyse_kwlookup(ctx, node),
        .symbol => |sym| {
            if (sym.token[0] == '.') {
                analyse_poly_invoke(node);
            } else {
                const tag = ctx.resolve_special_form_tag(sym.token);
                const children = node.children;
                try switch (tag) {
                    .do => analyse_do(ctx, children),
                    .assign => analyse_assign(ctx, children),
                    .let => analyse_let(ctx, children),
                    .ifbranch => analyse_ifbranch(ctx, children),
                    .identicalP => anasf_identity_check(ctx, children[1..]),
                    .equal => anasf_numcmp(ctx, children[1..], .equal),
                    .lte => anasf_numcmp(ctx, children[1..], .lte),
                    .lt => anasf_numcmp(ctx, children[1..], .lt),
                    .gte => anasf_numcmp(ctx, children[1..], .gte),
                    .gt => anasf_numcmp(ctx, children[1..], .gt),
                };
            }
        },
    }
}

pub fn analyse_node(ctx: AnaCtx, node: ca.Node) !AnaNode {
    const result_ctx = ctx.result_ctx;
    try switch (node) {
        .list => |list| analyse_list(ctx, list),
        // .set => analyse_set(ctx, node),
        // .vector => analyse_vector(ctx, node),
        // .map => analyse_map(ctx, node),
        .symbol => |sym| analyse_symbol(ctx, sym),
        .keyword => |kw| analyse_keyword(ctx, kw),
        .number => |num| analyse_number(ctx, num),
        .string => |s| analyse_string(ctx, s),
        .char => |c| analyse_char(ctx, c),
        else => {},
    };
    ctx.result_ctx = result_ctx;
}

pub inline fn analyse_node_with_res(res: AnaCtx.ResultCtx, ctx: AnaCtx, node: ca.Node) !AnaNode {
    const prev = ctx.result_ctx;
    ctx.result_ctx = res;
    try analyse_node(ctx, node);
    ctx.result_ctx = prev;
}

pub inline fn analyse_args(ctx: AnaCtx, nodes: [_]ca.Node) ![_]AnaNode {
    const prev = ctx.result_ctx;
    ctx.result_ctx = .expression;
    var anas = [nodes.len]AnaNode;
    inline for (nodes) |node, i| {
        anas[i] = try analyse_node_with_res(.expression, ctx, node);
    }
    ctx.result_ctx = prev;
    return anas;
}
