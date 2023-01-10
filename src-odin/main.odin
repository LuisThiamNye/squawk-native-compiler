package main

import "core:fmt"
import "core:os"
import "core:io"
// import "bytecode_runner"
import "numbers"
import "parser"
import "./ast"

main :: proc() {
	// bytecode_runner.run()
	// numbers.test_bignums()
	codebuf, ok := os.read_entire_file_from_filename("samples/controlflowideas.sq")
	// codebuf, ok := os.read_entire_file_from_filename("samples/test.edn")
	if !ok {panic("not okay")}
	parser_ctx := parser.init_parser(codebuf)
	ast_builder := ast.make_parser_builder()
	line := 1
	loop: for {
		msg := parser.step(parser_ctx)
		#partial switch msg.tag {
		case .none:
			break loop
		case .eof:
			break loop
		case .error:
			fmt.printf("Parser error at line %v, idx %v:\n", line, msg.start_idx)
			fmt.println(msg.message)
			break loop
		case .newline:
			line+=1
		case:
			ast.builder_accept_parser_msg(ast_builder, parser_ctx, msg)
		}
		// fmt.println(line, msg.tag)
		// fmt.printf("%v %s\n", line, parser_ctx.buf[msg.start_idx:msg.end_idx])
	}

	nodes := ast.builder_to_astnodes(ast_builder)

	writer := io.to_writer(os.stream_from_handle(os.stdout))
	for node in nodes {
		ast.pr_ast(writer, node)
		fmt.println()
	}

	fmt.println("done")
}