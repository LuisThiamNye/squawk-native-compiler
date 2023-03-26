package vis


import "core:fmt"
import "core:mem"
import "core:math"
import "core:strings"
import "core:io"
import "core:os"
import "core:slice"

import rp "../rope"

write_escaped_string_node_rope :: proc(w: io.Writer, rope: ^rp.RopeNode) {
	it := rp.byte_iterator(rope)
	for {
		ch, ok := rp.iter_next(&it)
		if ok {
			if ch=='"' || ch=='\\' {
				io.write_byte(w, '\\')
			}
			io.write_byte(w, ch)
		} else {
			return
		}
	}
}

codenode_serialise_write_nodes :: proc(w: io.Writer, nodes: [dynamic]CodeNode, indent_level := 0, child_indent_level := 0) -> int {
	write_indent :: proc(w: io.Writer, indent_level: int) {
		for i in 0..<indent_level {
			io.write_byte(w, ' ')
		}
	}
	acc := 0
	active_child_indent_level := indent_level
	n := len(nodes)
	nodes := nodes
	for child, i in &nodes {
		acc += codenode_serialise_write(w, &child, acc+active_child_indent_level)
		if child.tag == .newline {
			active_child_indent_level = child_indent_level
			acc = 0
			write_indent(w, acc+active_child_indent_level)
		} else {
			if i<n-1 && !(child.tag==.token&&child.token.prefix) {
				io.write_byte(w, ' ')
				acc += 1
			}
		}
	}
	return acc
}

codenode_serialise_write :: proc(w: io.Writer, node: ^CodeNode, indent_level := 0) -> int {
	switch node.tag {
	case .coll:
		opener : u8
		closer : u8
		switch node.coll.coll_type {
		case .round:
			opener='('
			closer=')'
		case .square:
			opener='['
			closer=']'
		case .curly:
			opener='{'
			closer='}'
		}
		child_indent_level : int
		if node.coll.coll_type==.round {
			child_indent_level = indent_level + 2
		} else {
			child_indent_level = indent_level + 1
		}
		io.write_byte(w, opener)
		acc := codenode_serialise_write_nodes(w, node.coll.children, indent_level+1, child_indent_level)
		io.write_byte(w, closer)
		return 2+acc
	case .newline:
		io.write_byte(w, '\n')
		return 1
	case .string:
		io.write_byte(w, '\"')
		write_escaped_string_node_rope(w, &node.string.text)
		io.write_byte(w, '\"')
		return 2+rp.get_count(node.string.text)
	case .token:
		io.write(w, node.token.text)
		return len(node.token.text)
	case:
		panic("!!!")
	}
}

read_string_node_from_escaped_string :: proc(input: string) -> (CodeNode, int, bool) {
	sb := strings.builder_make()
	end_idx := -1
	for i:=0; i<len(input); i+=1{
		ch := input[i]
		if ch=='\\' {
			i += 1
			ch = input[i]
		} else if ch=='"' {
			end_idx = i
			break
		}
		strings.write_byte(&sb, ch)
	}
	if end_idx == -1 {
		return {}, -1, false
	}

	node : CodeNode
	node.tag = .string
	node.string.text = rp.of_string(strings.to_string(sb))
	return node, end_idx, true
}

codenodes_from_string :: proc(input: string) -> (result: []CodeNode, ok: bool) {
	StackFrame :: struct {
		delimiter: u8,
		prefix: bool,
		nodes : [dynamic]CodeNode,
	}

	stack : [dynamic]StackFrame
	defer delete(stack)
	append(&stack, StackFrame{})

	last_token_end_i := -1
	ok = true
	for i:=0; ; {
		using frame := &stack[len(stack)-1]

		if i>=len(input){
			if len(stack)>1 {
				ok=false
			}
			break
		}

		ch := input[i]
		if ch==' '||ch=='\r'||ch=='\t'||ch==13||ch==14 { // eat whitespace
			i += 1
		} else if ch=='\n' {
			node : CodeNode
			node.tag = .newline
			append(&nodes, node)
			i += 1
		} else if ch=='"' {
			text_start := i+1
			if text_start>=len(input) {
				ok = false
				break
			}
			node, str_count, s_ok := read_string_node_from_escaped_string(input[text_start:])
			if !s_ok {
				fmt.println("string failure")
				ok = false
				break
			}
			if i == last_token_end_i { // has prefix
				left_node := &nodes[len(nodes)-1]
				left_node.token.prefix = true
				node.string.prefix = true
			}
			append(&nodes, node)
			i = text_start + str_count + 1
		} else {
			try_coll: {
				closer : u8
				if ch=='(' {
					closer = ')'
				} else if ch=='[' {
					closer = ']'
				} else if ch=='{' {
					closer = '}'
				} else {
					break try_coll
				}
				append(&stack, StackFrame{delimiter=closer, prefix=(i == last_token_end_i)})
				i += 1
				continue
			}
			// Try token
			if codeeditor_valid_token_charP(cast(rune) ch) {
				token_start_idx := i
				for {
					i += 1
					if i < len(input) {
						ch = input[i]
						if codeeditor_valid_token_charP(cast(rune) ch) {
							continue
						}
					}
					break
				}
				segment := input[token_start_idx:i]
 				if len(segment) > max_token_length {
 					ok = false
 					break
 				}
				node : CodeNode
				node.tag = .token
				node.token.text = make(type_of(node.token.text), len(segment))
				copy(node.token.text, segment)
				append(&nodes, node)
				last_token_end_i = i

			} else if ch==frame.delimiter {
				coll_type : CodeCollType
				switch ch {
				case ')':
					coll_type = .round
				case ']':
					coll_type = .square
				case '}':
					coll_type = .curly
				case:
					panic("!!!")
				}
				node : CodeNode
				node.tag = .coll
				node.coll.coll_type = coll_type
				node.coll.children = nodes
				pop(&stack)
				nodes := &stack[len(stack)-1].nodes
				if prefix {
					left_node := &nodes[len(nodes)-1]
					assert(left_node.tag==.token)
					left_node.token.prefix = true
					node.coll.prefix = true
				}
				append(nodes, node)
				i += 1

			} else {
				fmt.println("unexpected character", ch)
				ok = false
				break
			}
		}
	}

	if !ok {
		for frame in stack {
			for node in frame.nodes {
				delete_codenode(node)
			}
			delete(frame.nodes)
		}
		return
	} else {
		result = stack[0].nodes[:]
		return
	}
}

codeeditor_refresh_from_file :: proc(editor: ^CodeEditor) {
	text, ok := os.read_entire_file_from_filename(editor.file_path)
	if !ok {return}
	nodes, n_ok := codenodes_from_string(string(text))
	if !n_ok {
		fmt.println("error parsing nodes from file")
	}

	editor.roots = slice.to_dynamic(nodes)

	using editor
	// Reset cursors
	for region in regions {
		delete_cursor(region.from)
		delete_cursor(region.to)
	}
	clear(&regions)

	region : Region
	region.to.idx = 0

	if len(roots)>0 {
		region.to.path = make(type_of(region.to.path), 1)
		region.to.path[0] = 0
	}

	deep_copy(&region.from, &region.to)
	region.xpos = -1
	append(&regions, region)
}