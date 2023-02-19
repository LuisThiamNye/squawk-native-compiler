package vis

import "core:mem"
import "core:fmt"
import "core:os"
import "core:io"
import "core:runtime"
import br "../bytecode_runner"
import "../bytecode_builder"
import "../numbers"
import "../parser"
import "../semantics"
import "../ast"
import "../vis"
import "../interpreter"

// sq_src_path :: "samples/test.edn"
sq_src_path :: "samples/eg_linesof2.sq"

compile_sample :: proc() {
	// bytecode_runner.run()
	// numbers.test_bignums()
	// codebuf, ok := os.read_entire_file_from_filename("samples/controlflowideas.sq")
	codebuf, ok := os.read_entire_file_from_filename(sq_src_path)
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


	nodes := ast.builder_to_astnodes(ast_builder)[:]

	interp := interpreter.make_interp_from_ast_nodes(nodes, ast_builder.max_depth)

	main_var, found := interpreter.find_var(interp, "main")
	if !found {panic("main not found")}
	main_var_interp := interp.var_interp_map[main_var]

	interpreter.interp_from_var(main_var, main_var_interp)

	if main_var.value.type!=interpreter.typeinfo_of_dynproc {
		panic("!! 'main' var is not a dynproc")
	}
	interpreter.execute_invoke_dynproc(interp, cast(^interpreter.DynProc) main_var.value.data, {})


	/*
	using semantics

	cunit := new(semantics.CompilationUnit)
	cu_load_standard_types(cunit)
	cnodes := make([dynamic]^semantics.CompilationNode, len(nodes))
	for node, i in nodes {
		using semantics
		cnode := new(semantics.CompilationNode)
		cnodes[i] = cnode
		node_ := &nodes[i]
		cnode.semantics=make_semctx(node_, ast_builder.max_depth)
		cnode.semantics.compilation_node=cnode
		cnode.semantics.compilation_unit=cunit
		cnode.ast = node_
	}

	cunit.top_level_nodes = cnodes
	semantics.cu_analyse_all(cunit)

	fmt.printf("found %v procedures\n", len(cunit.procedures))

	// vis.dbg_inspect(cunit)

	procid_to_procinfo: map[^SemNode]^br.ProcInfo

	for prc in cunit.procedures {
		semnode := prc.sem_node
		procid_to_procinfo[semnode]=new(br.ProcInfo)
	}

	fmt.println("building procinfos")
	all_procinfos := make([]^br.ProcInfo, len(cunit.procedures))
	all_procrefs := make([][]^br.ProcInfo, len(cunit.procedures))
	for prc, i in &cunit.procedures {
		procinfo, procrefs := bytecode_builder.build_proc_from_semnode(&prc, &procid_to_procinfo)
		all_procrefs[i]=procrefs
		all_procinfos[i]=procinfo
	}

	fmt.println("setting constant pools")
	for prc, i in cunit.procedures {
		procs := make([]br.ProcInfo, len(all_procrefs[i]))
		all_procinfos[i].constant_pool.procedures = procs
		for procref, j in all_procrefs[i] {
			procs[j] = procref^
		}
	}

	for procinfo, i in all_procinfos {
		fmt.println()
		fmt.println(cunit.procedures[i].name)
		fmt.printf("mem words: %v; params: %v; returns: %v; max code idx: %v\n",
			procinfo.nregisters, procinfo.nparams, procinfo.nreturns, len(procinfo.code)-1)
		fmt.println("Bytecode:")
		br.print_codes(procinfo)
		fmt.println()

		fmt.println("linking")
		br.link_procinfo(procinfo)
	}

	for prc, i in cunit.procedures {
		if prc.name=="main" {
			procinfo := all_procinfos[i]
			frame := br.make_frame_from_procinfo(procinfo)
			br.run_frame(frame)
			// fmt.println((cast([^]u64) frame.return_memory)[:procinfo.memory_nwords])

			ret_typeinfo := spec_to_typeinfo(prc.sem_node.spec)
			// fmt.println(ret_typeinfo)

			// fmt.println(cunit.procedures[0].sem_node.spec)

			ret0 := mem.ptr_offset(cast(^br.RegisterValue) frame.return_registers, 0)
			wrapper := Rt_Any{data=ret0, type=ret_typeinfo}
			println("Result:")
			print_rt_any(wrapper)

			// retx := cast(^[^]u8) ret0
			// fmt.println(retx[0])
			// fmt.println(retx[1])
			// fmt.println(retx[2])
			// fmt.println(retx[3])
			fmt.println(cast(cstring) ret0.ptr)
		}
	}

	*/
	
}