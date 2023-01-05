const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;
const ArrayList = std.ArrayList;

const TokenNode = struct {
    text: []u8,
};

pub const Parser = struct {
    ch: u8,
    buf: []u8,
    next_idx: usize,
    msg: Message,
    allocator: std.mem.Allocator,
    coll_stack: ArrayList(CollStackType),

    pub fn init(buf: []u8, allocator: mem.Allocator) Parser {
        return Parser{
            .ch = 0,
            .buf = buf,
            .next_idx = 0,
            .msg = .none,
            .allocator = allocator,
            .coll_stack = ArrayList(CollStackType).init(allocator),
        };
    }

    const Macro = enum(u8) {
        none,
        string,
        comment,
        quote,
        meta,
        list,
        vector,
        map,
        unmatched_delim,
        char,
        dispatch,
    };

    pub const Message = union(enum) {
        none,
        keyword: TokenNode,
        symbol: TokenNode,
        number: TokenNode,
        string: TokenNode,
        char: TokenNode,
        comment: TokenNode,
        special_comment: TokenNode,
        quote,
        meta,
        coll_start: struct { variant: CollStackType },
        coll_end,
        discard,
    };

    pub const CollStackType = enum { list, vector, map, set };

    pub fn read_next_byte(self: *Parser) !u8 {
        if (self.next_idx < self.buf.len) {
            const b = self.buf[self.next_idx];
            self.next_idx += 1;
            return b;
        } else {
            return error.EndOfStream;
        }
    }

    pub fn read(self: *Parser) !void {
        const byte = self.read_next_byte() catch |err| switch (err) {
            error.EndOfStream => {
                self.ch = 0;
                return;
            },
        };
        self.ch = byte;
        return;
    }

    pub fn whitespaceP(ch: u8) bool {
        return ascii.isWhitespace(ch);
    }

    pub fn terminating_macroP(ch: u8) bool {
        return (ch != '#' and ch != '\'' and ch != '%' and get_macro(ch) != .none);
    }

    pub fn eofP(self: *Parser) bool {
        return self.ch == 0;
    }

    pub fn read_token(self: *Parser) ![]u8 {
        var sb = std.ArrayList(u8).init(self.allocator);
        try sb.append(self.ch);
        var i = self.next_idx;
        while (true) : (i += 1) {
            if (i >= self.buf.len) {
                self.next_idx = i;
                self.ch = 0;
                break;
            }
            const ch = self.buf[i];
            if (whitespaceP(ch) or terminating_macroP(ch)) {
                self.next_idx = i;
                self.ch = self.buf[i - 1];
                break;
            } else {
                try sb.append(ch);
            }
        }
        return try sb.toOwnedSlice();
    }

    pub fn read_string_esc(self: *Parser) !u8 {
        try self.read();
        return switch (self.ch) {
            't' => '\t',
            'r' => '\r',
            'n' => '\n',
            '\\' => '\\',
            '"' => '"',
            'b' => ascii.control_code.bs,
            'f' => ascii.control_code.ff,
            else => error.UnsupportedEscapeSequence,
        };
    }

    pub fn parse_string(self: *Parser) !void {
        var sb = std.ArrayList(u8).init(self.allocator);
        while (true) {
            try self.read();
            if (self.ch == '"') break;
            if (self.ch == '\\') {
                const ch = try self.read_string_esc();
                try sb.append(ch);
            } else {
                try sb.append(self.ch);
            }
        }
        self.msg = .{ .string = .{ .text = try sb.toOwnedSlice() } };
    }

    pub fn parse_comment(self: *Parser) !void {
        var sb = std.ArrayList(u8).init(self.allocator);
        while (true) {
            try self.read();
            if (self.ch == '\n') break;
            try sb.append(self.ch);
        }
        self.msg = .{ .comment = .{ .text = try sb.toOwnedSlice() } };
    }

    pub fn parse_special_comment(self: *Parser) !void {
        var sb = std.ArrayList(u8).init(self.allocator);
        while (true) {
            try self.read();
            if (self.ch == '\n') break;
            try sb.append(self.ch);
        }
        self.msg = .{ .special_comment = .{ .text = try sb.toOwnedSlice() } };
    }

    pub fn parse_quote(self: *Parser) !void {
        self.msg = .quote;
    }

    pub fn parse_char(self: *Parser) !void {
        try self.read();
        const token = try self.read_token();
        self.msg = .{ .char = .{ .text = token } };
    }

    pub fn parse_meta(self: *Parser) !void {
        self.msg = .meta;
    }

    pub fn parse_coll(self: *Parser, variant: CollStackType) !void {
        try self.coll_stack.append(variant);
        self.msg = .{ .coll_start = .{ .variant = variant } };
    }

    pub fn parse_unmatched_delim(self: *Parser) !void {
        _ = self;
        return error.UnmatchedDelimiter;
    }

    pub fn parse_discard(self: *Parser) !void {
        self.msg = .discard;
    }

    pub fn parse_dispatch(self: *Parser) !void {
        try self.read();
        try switch (self.ch) {
            '{' => self.parse_coll(.set),
            '!' => self.parse_special_comment(),
            '_' => self.parse_discard(),
            else => return error.NoDispatch,
        };
    }

    pub fn read_macro(self: *Parser, macro: Macro) !void {
        try switch (macro) {
            .string => self.parse_string(),
            .comment => self.parse_comment(),
            .quote => self.parse_quote(),
            .meta => self.parse_meta(),
            .list => self.parse_coll(.list),
            .unmatched_delim => self.parse_string(),
            .vector => self.parse_coll(.vector),
            .map => self.parse_coll(.map),
            .char => self.parse_char(),
            .dispatch => self.parse_dispatch(),
            .none => return error.NoMacro,
        };
    }

    const macro_table = init: {
        var a: [256]Macro = undefined;
        a['"'] = .string;
        a[';'] = .comment;
        a['\''] = .quote;
        a['^'] = .meta;
        a['('] = .list;
        a[')'] = .unmatched_delim;
        a['['] = .vector;
        a[']'] = .unmatched_delim;
        a['{'] = .map;
        a['}'] = .unmatched_delim;
        a['\\'] = .char;
        a['#'] = .dispatch;
        break :init a;
    };

    pub fn get_macro(ch: u8) Macro {
        return macro_table[ch];
    }

    pub fn parse_number(self: *Parser) !void {
        const token = try self.read_token();
        self.msg = .{ .number = .{ .text = token } };
    }

    pub fn parse_delimited_list_end(self: *Parser) !bool {
        const variant = self.coll_stack.items[self.coll_stack.items.len - 1];
        const end_ch: u8 = switch (variant) {
            .list => ')',
            .vector => ']',
            .map => '}',
            .set => '}',
            // else => return error.Error,
        };
        if (self.ch == end_ch) {
            _ = self.coll_stack.pop();
            self.msg = .coll_end;
            return true;
        }
        return false;
    }

    pub fn peek_next_byte(self: *Parser) u8 {
        if (self.next_idx < self.buf.len) {
            return self.buf[self.next_idx];
        } else {
            return 0;
        }
    }

    pub fn read_to_nonws(self: *Parser) !void {
        while (true) {
            const byte = self.read_next_byte() catch |err| switch (err) {
                error.EndOfStream => {
                    self.ch = 0;
                    break;
                },
            };
            if (!whitespaceP(byte)) {
                self.ch = byte;
                return;
            }
        }
    }

    pub fn read_next_form_now(self: *Parser) !void {
        if (ascii.isDigit(self.ch)) {
            try self.parse_number();
            return;
        }
        if (0 < self.coll_stack.items.len) {
            const at_end = try self.parse_delimited_list_end();
            if (at_end) return;
        }

        const macro = get_macro(self.ch);
        if (macro != .none) {
            try self.read_macro(macro);
            return;
        }

        const ch = self.ch;
        if (ch == '-' or ch == '+') {
            const ch2 = self.peek_next_byte();
            if (ascii.isDigit(ch2)) {
                try self.parse_number();
                return;
            }
        }

        const token = try self.read_token();
        if (0 < token.len and token[0] == ':') {
            self.msg = .{ .keyword = .{ .text = token } };
            return;
        } else {
            self.msg = .{ .symbol = .{ .text = token } };
            return;
        }
    }

    pub fn next(self: *Parser) !Message {
        self.msg = .none;
        try self.read_to_nonws();
        if (self.eofP()) return self.msg;
        try self.read_next_form_now();
        return self.msg;
    }
};
