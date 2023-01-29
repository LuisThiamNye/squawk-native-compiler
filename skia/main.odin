package skia

import "core:os"
import "core:fmt"
import "core:mem"
import "core:strings"
import "sq:ast"
import "sq:parser"

chunked_array_chunk_size :: 1<<14

ChunkedArray :: struct {
	chunks: [dynamic][^]u8,
	last_chunk_len: int,
}

ca_append_slice :: proc(using ca: ^ChunkedArray, s: []u8) {
	chunk_idx := len(chunks)-1
	navailable := chunked_array_chunk_size-last_chunk_len
	nitems := len(s)
	for {
		if nitems <= navailable {
			mem.copy(&chunks[chunk_idx][last_chunk_len], raw_data(s), nitems)
			last_chunk_len += nitems
			return
		} else {
			mem.copy(&chunks[chunk_idx][last_chunk_len], raw_data(s), navailable)
			last_chunk_len=0
			nitems -= navailable
			navailable = chunked_array_chunk_size
			chunk_idx += 1
			chunk := make([^]u8, chunked_array_chunk_size)
			append(&chunks, chunk)
		}
	}
}

ca_append_string :: proc(ca: ^ChunkedArray, s: string) {
	ca_append_slice(ca, transmute([]u8) s)
}

ca_append_byte :: proc(using ca: ^ChunkedArray, b: u8) {
	chunk_idx := len(chunks)-1
	if last_chunk_len < chunked_array_chunk_size {
		chunks[chunk_idx][last_chunk_len]=b
		last_chunk_len += 1
	} else {
		last_chunk_len=0
		chunk := make([^]u8, chunked_array_chunk_size)
		chunk[0]=b
		append(&chunks, chunk)
	}
}

ca_append_rune :: proc(using ca: ^ChunkedArray, r: rune) {
	ca_append_byte(ca, cast(u8) r)
	// ca_append_byte(ca, cast(u8) r>>8)
	// ca_append_byte(ca, cast(u8) r>>16)
	// ca_append_byte(ca, cast(u8) r>>24)
}

ca_append :: proc{ca_append_slice, ca_append_string, ca_append_byte, ca_append_rune}

BindGen :: struct {
	code: ChunkedArray,
	type_aliases: map[string]string,
}

make_codebuf :: proc() -> ChunkedArray {
	chunk0 := make([^]u8, chunked_array_chunk_size)
	chunks := make([dynamic][^]u8,1)
	chunks[0] = chunk0
	return {chunks=chunks}
}

write_codebuf_to_file :: proc(fd: os.Handle, code: ^ChunkedArray) {
	for _, i in code.chunks {
		n := chunked_array_chunk_size
		if i==len(code.chunks)-1 {
			n=code.last_chunk_len
		}
		data_slice := code.chunks[i][:n]
		_n, err := os.write(fd, data_slice)
		assert(0==err)
	}
}

gen_bindings :: proc() {
	codebuf, ok := os.read_entire_file_from_filename("skia/bindings.sq")
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

	bindgen := BindGen{code=make_codebuf()}
	using bindgen

	type_aliases = make(map[string]string)
	type_aliases["u8"]="uint8_t"
	type_aliases["u32"]="uint32_t"
	// int is supposedly 32-bits on most systems, so force it
	type_aliases["int"]="uint32_t"

	class_prefix := "Sk"
	prefix := "sk_"

	// ca_append(&code, "#include <include/core/SkColor.h>\n")
	// ca_append(&code, "#include <include/core/SkPaint.h>\n")

	resolve_type_str :: proc (using bindgen: ^BindGen, input: string) -> string {
		t := input
		ptrP := false
		if t[0]=='*' {
			t = t[1:]
			ptrP = true
		}
		if t in type_aliases {
			t = type_aliases[t]
		}
		if ptrP {
			t2 := make([]u8, len(t)+1)
			mem.copy(&t2[0], raw_data(t), len(t))
			t2[len(t2)-1] = '*'
			t = string(t2)
		}
		return t
	}

	for node in nodes {
		if node.tag == .list {
			first := node.children[0]
			if first.tag == .symbol {
				if "type"==first.token {
					t := resolve_type_str(&bindgen, node.children[2].token)
					type_aliases[node.children[1].token] = t
				} else if first.token=="class" {
					class_name := node.children[1].token
					ca_append(&code, "#include <include/core/")
					ca_append(&code, class_prefix)
					ca_append(&code, class_name)
					ca_append(&code, ".h>\n")

					ca_append(&code, "extern \"C\" {\n")
					
					staticP := false
					for i in 2..<len(node.children) {
						mdecl := node.children[i]
						if mdecl.tag == .keyword && mdecl.token=="static" {
							staticP = true
						} else if mdecl.tag == .list {
							assert(len(mdecl.children)>=2)
							namedecl := mdecl.children[0]
							name : string = namedecl.token
							initP := false
							deinitP := false
							if namedecl.tag==.keyword {
								if namedecl.token=="init" {
									initP = true
								} else if namedecl.token=="deinit" {
									deinitP = true
								}
							}

							ctorP := namedecl.tag==.keyword && name=="new"

							ret_type := "void"

							sigdecl := mdecl.children[1]
							nargs := len(sigdecl.children)
							for node, i in sigdecl.children {
								if node.token == ">" {
									ret_type = resolve_type_str(&bindgen, sigdecl.children[i+1].token)
									nargs = i
									break
								}
							}

							if ctorP||initP {
								ret_type=strings.concatenate({class_prefix, class_name, "*"})
							}

							// emit code
							ca_append(&code, "\n")
							ca_append(&code, ret_type)
							ca_append(&code, " ")
							ca_append(&code, prefix)
							ca_append(&code, strings.to_lower(class_name))
							ca_append(&code, "_")
							for thech in name {
								ch := thech
								if ch=='-' {ch='_'}
								if ch=='?' {ch='P'}
								ca_append(&code, ch)
							}
							ca_append(&code, "(")
							if !ctorP {
								ca_append(&code, class_prefix)
								ca_append(&code, class_name)
								ca_append(&code, "* s")
							}

							// Parameters
							for i in 0..<nargs {
								node := sigdecl.children[i]
								if node.token == ">" {break}
								if !ctorP {ca_append(&code, ", ")}
								typename := resolve_type_str(&bindgen, node.token)
								ca_append(&code, typename)
								ca_append(&code, " a")
								ca_append(&code, fmt.tprintf("%v", i))
							}
							ca_append(&code, "){\n")

							ca_append(&code, cast(u8) '\t')
							if ret_type != "void" {
								ca_append(&code, "return ")
							}
							// Method invoke
							if ctorP {
								ca_append(&code, "new ")
								ca_append(&code, class_prefix)
								ca_append(&code, class_name)
							} else if initP {
								ca_append(&code, "new(s)")
								ca_append(&code, class_prefix)
								ca_append(&code, class_name)
							}
							else {
								ca_append(&code, "s->")
								if deinitP {
									ca_append(&code, cast(u8) '~')
									ca_append(&code, class_prefix)
									ca_append(&code, class_name)
								} else if len(mdecl.children)>=3 {
									ca_append(&code, mdecl.children[2].token)
								} else {
									method_name := name
									camel_humpP := false
									if method_name[len(name)-1]=='?' {
										ca_append(&code, "is")
										method_name = method_name[:len(method_name)-1]
										camel_humpP = true
									}
									for thech in method_name {
										ch := thech
										if ch=='-' {
											ch='_'
											camel_humpP = true
											continue
										} else if camel_humpP {
											ch-=32 // uppercase
											camel_humpP=false
										}
										ca_append(&code, ch)
									}
								}
							}
							// Method invoke parameters
							ca_append(&code, "(")
							for i in 0..<nargs {
								if i>0 {
									ca_append(&code, ",")
								}
								ca_append(&code, cast(u8) 'a')
								ca_append(&code, fmt.tprintf("%v", i))
							}
							ca_append(&code, ");")
							ca_append(&code, "}\n")
						}
					}
					ca_append(&code, "}\n") // end of extern C
				}
			}
		}
	}

	path := "skia/bindings.cc"
	os.remove(path)
	fd, err := os.open(path, os.O_APPEND|os.O_CREATE)
	assert(0==err)

	write_codebuf_to_file(fd, &code)
	os.close(fd)
}

gen_sizeprog :: proc() {
	filebuf, ok := os.read_entire_file_from_filename("skia/sizes_types.sq")
	if !ok {panic("not okay")}
	if len(filebuf)==0 {return}

	type_names : [dynamic][]u8
	linestart := 0
	i := 0
	for {
		if i<len(filebuf) {
			b := filebuf[i]
			if b!='\n' && b!='\r' {
				i+=1
				continue
			}
		}
		append(&type_names, filebuf[linestart:i])
		if i<len(filebuf) {
			if filebuf[i]=='\r' {i+=1}
			i +=1
			linestart=i
		} else {break}
	}

	code := make_codebuf()
	ca_append(&code, "#include <iostream>\n")
	ca_append(&code, "#include <fstream>\n")
	for class_name in type_names {
		ca_append(&code, "#include <include/core/")
		ca_append(&code, class_name)
		ca_append(&code, ".h>\n")
	}

	ca_append(&code, "\nint main() {\n")
	ca_append(&code, "std::ofstream out(\"_sizes.txt\");\n")
	ca_append(&code, "if (!out.is_open()) ")
	ca_append(&code, "{std::cout << \"unable to open file\"; return 1;}\n")


	for class_name in type_names {
		ca_append(&code, "out << \"")
		ca_append(&code, class_name)
		ca_append(&code, "\" << \" \" << sizeof(")
		ca_append(&code, class_name)
		ca_append(&code, ") << \"\\n\";\n")
	}

	ca_append(&code, "out.close();\n")
	ca_append(&code, "return 0;}\n")

	path := "skia/_sizes_gen.cc"
	os.remove(path)
	fd, err := os.open(path, os.O_APPEND|os.O_CREATE)
	assert(0==err)
	write_codebuf_to_file(fd, &code)
	os.close(fd)
}

main :: proc() {
	gen_bindings()
	gen_sizeprog()
}