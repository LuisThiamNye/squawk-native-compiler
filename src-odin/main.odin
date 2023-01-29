package main

import "core:mem"
import "core:fmt"
import "core:os"
import "core:io"
import br "bytecode_runner"
import "bytecode_builder"
import "numbers"
import "parser"
import "semantics"
import "ast"
import "vis"

println :: fmt.println

compile_sample :: proc() {
	// bytecode_runner.run()
	// numbers.test_bignums()
	// codebuf, ok := os.read_entire_file_from_filename("samples/controlflowideas.sq")
	codebuf, ok := os.read_entire_file_from_filename("samples/test.edn")
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

		node_ := node
		semctx := semantics.make_semctx(&node_, ast_builder.max_depth)
		// fmt.println("max depth", ast_builder.max_depth)
		msg := semantics.step_push_node(semctx, &node_, semantics.Spec_NonVoid{})
		msgloop: for {
			// msg := semantics.sem_step(semctx)
			// fmt.println("Msg: ", msg)
			switch m in msg {
			case semantics.Msg_Analyse:
				// fmt.println("DBG ana")
				// fmt.println(semctx.ast_stack)
				msg = semantics.sem_step(semctx)
				// fmt.println(semctx.ast_stack)
			case semantics.Msg_AnalyseChild:
				msg = semantics.step_push_node(semctx, m.ast, m.ret_spec)
				break
			case semantics.Msg_DoneNode:
				semantics.sem_complete_node(semctx, m.node)
				if semctx.ast_stack_endx==0 {break msgloop}
				msg = semantics.sem_step(semctx)
			}
		}
		semnode := semctx.latest_semnode
		// fmt.println(semnode)
		// fmt.println(msg)
		// fmt.println(semctx)

		procinfo := bytecode_builder.build_proc_from_semnode(&semnode)
		// println(procinfo)
		
		fmt.println("\nBytecode:")
		br.print_codes(procinfo)
		fmt.println()

		frame := br.make_frame_from_procinfo(procinfo)
		// println(frame)
		br.run_frame(frame)
		result := mem.ptr_offset(cast(^u64) frame.memory, 0)^
		println("Result:", result)
	}

	fmt.println("done")
}

main :: proc() {
	vis.main()
}