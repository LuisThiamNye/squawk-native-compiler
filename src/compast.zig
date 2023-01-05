const std = @import("std");
const mem = std.mem;
const parser = @import("parser.zig");
const Parser = parser.Parser;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const Node = union(enum) {
    list: Coll,
    set: Coll,
    vector: Coll,
    map: Coll,
    symbol: Symbol,
    keyword: Keyword,
    number: Number,
    string: String,
    char: Char,
};

pub const Coll = struct {
    children: []Node,
};

pub const Symbol = struct {
    token: []u8,
};

pub const Keyword = struct {
    token: []u8,
};

pub const Number = struct {
    token: []u8,
};

pub const String = struct {
    token: []u8,
};

pub const Char = struct {
    token: []u8,
};

pub fn print_node_children(nodes: []Node, w: anytype) void {
    for (nodes) |node| {
        print_node(node, w) catch {
            std.debug.print("error\n", .{});
            return;
        };
        w.writeByte(' ') catch {
            return;
        };
    }
}

pub fn print_node(node: Node, w: anytype) !void {
    switch (node) {
        .list => |coll| {
            try w.writeByte('(');
            print_node_children(coll.children, w);
            try w.writeByte(')');
        },
        .vector => |coll| {
            try w.writeByte('[');
            print_node_children(coll.children, w);
            try w.writeByte(']');
        },
        .map => |coll| {
            try w.writeByte('{');
            print_node_children(coll.children, w);
            try w.writeByte('}');
        },
        .set => |coll| {
            try w.writeByte('#');
            try w.writeByte('{');
            print_node_children(coll.children, w);
            try w.writeByte('}');
        },
        .keyword => |kw| {
            // try w.writeByte(':');
            try w.writeAll(kw.token);
        },
        .number => |kw| {
            try w.writeAll(kw.token);
        },
        .symbol => |kw| {
            try w.writeAll(kw.token);
        },
        .string => |kw| {
            try w.writeAll(kw.token);
        },
        .char => |kw| {
            try w.writeByte('\\');
            try w.writeAll(kw.token);
        },
    }
}

const NodeBuilder = union(enum) {
    coll: CollBuilder,
    wrapper: WrapperBuilder,
    discard,
    root: RootBuilder,

    pub fn of_coll(allocator: Allocator, tag: CollTag) NodeBuilder {
        return .{ .coll = .{
            .tag = tag,
            .children = ArrayList(Node).init(allocator),
        } };
    }

    pub fn of_wrapper(tag: WrapperTag) NodeBuilder {
        return .{ .wrapper = .{
            .tag = tag,
        } };
    }
};

const CollTag = enum {
    list,
    vector,
    set,
    map,
};

const CollBuilder = struct {
    tag: CollTag,
    children: ArrayList(Node),

    pub fn build(self: *CollBuilder) !Node {
        const children = try self.children.toOwnedSlice();
        const coll = Coll{ .children = children };
        return switch (self.tag) {
            .list => .{ .list = coll },
            .vector => .{ .vector = coll },
            .set => .{ .set = coll },
            .map => .{ .map = coll },
        };
    }
};

// const MetaBuilder = struct {
// 	tags: ArrayList(Node),

// };

const WrapperTag = enum {
    quote,
};

const WrapperBuilder = struct {
    tag: WrapperTag,

    pub fn build(self: *WrapperBuilder, allocator: Allocator, child: Node) !Node {
        const presym = switch (self.tag) {
            .quote => blk: {
                var s: []u8 = try allocator.dupe(u8, "squawk.lang/quote");
                break :blk Node{ .symbol = .{ .token = s } };
            },
        };
        var children = try allocator.alloc(Node, 2);
        children[0] = presym;
        children[1] = child;
        return .{ .list = .{ .children = children } };
    }
};

const RootBuilder = struct {
    children: ArrayList(Node),
};

pub const AstBuilder = struct {
    stack: ArrayList(NodeBuilder),
    current: NodeBuilder,
    allocator: Allocator,

    pub fn init(allocator: Allocator) AstBuilder {
        return .{
            .stack = ArrayList(NodeBuilder).init(allocator),
            .current = .{ .root = .{ .children = ArrayList(Node).init(allocator) } },
            .allocator = allocator,
        };
    }

    pub fn build(self: *AstBuilder) ![]Node {
        if (self.current != .root) return error.NotAtRoot;
        return try self.current.root.children.toOwnedSlice();
    }

    pub fn add_sibling(self: *AstBuilder, node: Node) !void {
        switch (self.current) {
            .root => |*root| try root.children.append(node),
            .coll => |*coll| try coll.children.append(node),
            .wrapper => |*w| {
                const wnode = try w.build(self.allocator, node);
                self.pop();
                try self.add_sibling(wnode);
            },
            .discard => {
                self.pop();
            },
        }
    }

    pub fn push(self: *AstBuilder, node: NodeBuilder) !void {
        try self.stack.append(self.current);
        self.current = node;
    }

    pub fn pop(self: *AstBuilder) void {
        self.current = self.stack.pop();
    }

    pub fn handle_parser_message(self: *AstBuilder, msg: Parser.Message) !void {
        try switch (msg) {
            .none => return,
            .keyword => |token| add_sibling(self, .{ .keyword = .{ .token = token.text } }),
            .symbol => |token| add_sibling(self, .{ .symbol = .{ .token = token.text } }),
            .number => |token| add_sibling(self, .{ .number = .{ .token = token.text } }),
            .string => |token| add_sibling(self, .{ .string = .{ .token = token.text } }),
            .char => |token| add_sibling(self, .{ .char = .{ .token = token.text } }),
            .comment => return,
            .special_comment => return,
            .quote => {
                try push(self, NodeBuilder.of_wrapper(.quote));
            },
            .meta => return,
            .coll_start => |c| push(self, NodeBuilder.of_coll(self.allocator, switch (c.variant) {
                .list => .list,
                .vector => .vector,
                .map => .map,
                .set => .set,
            })),
            .coll_end => {
                const coll = try self.current.coll.build();
                self.pop();
                try self.add_sibling(coll);
            },
            .discard => self.push(.discard),
        };
    }
};
