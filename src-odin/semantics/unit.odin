package semantics

import "core:fmt"
import "core:io"
import "core:os"
import "../ast"

import br "../bytecode_runner"

CompilationNode :: struct {
	semantics: ^SemCtx,
	ast: ^AstNode,
}

SemProcedure :: struct {
	name: string,
	sem_node: ^SemNode,
	nparams: u8,
	nreturns: u8,
	param_locals: []^Local,
}

Decl_ForeignLib :: struct {
	lib_name: string,
}

Decl_ForeignProc :: struct {
	name: string,
	lib: ^Decl_ForeignLib,
	param_types: []br.ForeignProc_C_Type,
	ret_type: br.ForeignProc_C_Type,
}

CompilationUnit :: struct {
	top_level_nodes: [dynamic]^CompilationNode,
	symbol_map: map[string]SymbolDeclaration,
	procedures: [dynamic]SemProcedure,
	foreign_procs: [dynamic]Decl_ForeignProc,
	foreign_libs: [dynamic]Decl_ForeignLib,
}

SymbolDeclaration :: struct {
	tag: enum {procedure, foreign_lib, foreign_proc},
	using val: struct #raw_union {
		procedure: ^SemProcedure,
		foreign_lib: ^Decl_ForeignLib,
		foreign_proc: ^Decl_ForeignProc,
	},
}

cu_analyse_node_maximally :: proc(cnode: ^CompilationNode) -> bool {
	node := cnode.ast^
	semctx := cnode.semantics

	fmt.print("analysing ast node: ")
	writer := io.to_writer(os.stream_from_handle(os.stdout))
	ast.pr_ast(writer, node)
	fmt.println()

	is_done := false
	msg : Message
	if semctx.ast_stack_endx==0 { // init
		node_ := node
		msg_, _err0 := step_push_node(semctx, &node_, Spec_NonVoid{})
		msg = msg_
	} else {
		msg = sem_step(semctx)
	}
	msgloop: for {
		// fmt.println("Msg: ", msg)
		switch m in msg {
		case Msg_Analyse:
			msg = sem_step(semctx)
		case Msg_AnalyseChild:
			msg_, _err := step_push_node(semctx, m.ast, m.ret_spec)
			msg = msg_
			break
		case Msg_ResolveSymbol:
			semctx.unresolved_symbol = m.name
			break msgloop
		case Msg_DoneNode:
			sem_complete_node(semctx, m.node)
			if semctx.ast_stack_endx==0 {
				is_done = true
				break msgloop
			}
			msg = sem_step(semctx)
		}
	}
	return is_done
}

cu_analyse_all :: proc(using unit: ^CompilationUnit) {
	for i in 0..<len(top_level_nodes) {
		cu_analyse_node_maximally(top_level_nodes[i])
	}
	for i in 0..<len(top_level_nodes) {
		cnode := top_level_nodes[i]
		semctx := cnode.semantics
		if semctx.unresolved_symbol != "" {
			if semctx.unresolved_symbol in symbol_map {
				done := cu_analyse_node_maximally(cnode)
				if !done {
					panic("did not finish")
				}
			} else {
				fmt.panicf("could not find symbol: %v", semctx.unresolved_symbol)
			}
		}
	}
}

cu_define_global_symbol :: proc(using unit: ^CompilationUnit,
	sym: string, decl: SymbolDeclaration) {
	symbol_map[sym] = decl
}