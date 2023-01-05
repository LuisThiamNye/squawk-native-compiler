const std = @import("std");
const fs = std.fs;
const io = std.io;
const parser = @import("parser.zig");
const compast = @import("compast.zig");
const analyser = @import("analyser.zig");

pub fn main() !void {
    var file = try fs.cwd().openFile("samples/test.edn", .{});
    defer file.close();

    var parser_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer parser_arena.deinit();
    const parser_allocator = parser_arena.allocator();
    const max_bytes = 200_000;
    const bytes = try file.readToEndAlloc(parser_allocator, max_bytes);

    var parse_result_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer parse_result_arena.deinit();
    const parse_result_allocator = parse_result_arena.allocator();
    var p = parser.Parser.init(bytes, parse_result_allocator);

    var ast_builder = compast.AstBuilder.init(parse_result_allocator);

    while (true) {
        const msg = try p.next();
        // std.debug.print("{}\n", .{msg});
        try ast_builder.handle_parser_message(msg);
        if (msg == .none) {
            break;
        }
    }

    const ast = try ast_builder.build();
    var bw = io.bufferedWriter(io.getStdErr().writer());
    compast.print_node_children(ast, bw.writer());

    analyser.analyse_node(ast[0]);

    try bw.flush();

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.

    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();
    // try bw.flush(); // don't forget to flush!
}
