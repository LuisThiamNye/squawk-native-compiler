package vis


import "core:fmt"
import "core:mem"
import "core:math"
import "core:strings"
import "core:io"
import "core:os"
import "core:slice"

import rp "../rope"

CodeNodeBasic_Flat_Encoded_Coll ::    struct{node: CodeNodeBasic_Coll,   idx: i32}
CodeNodeBasic_Flat_Encoded_Token ::   struct{node: CodeNodeBasic_Token,  idx: i32}
CodeNodeBasic_Flat_Encoded_String ::  struct{node: CodeNodeBasic_String, idx: i32}
CodeNodeBasic_Flat_Encoded_Newline :: struct{idx: i32}

CodeNodeBasic_Flat_Encoded_Array :: struct {
	// One number per node, flattened
	// -1 for simple node, otherwise the number of children.
	dynamic_pool: mem.Dynamic_Pool,
	max_depth: i32, // number of layers of siblings
	tree_shape: []i32,
	colls:    []CodeNodeBasic_Flat_Encoded_Coll,
	tokens:   []CodeNodeBasic_Flat_Encoded_Token,
	strings:  []CodeNodeBasic_Flat_Encoded_String,
	newlines: []CodeNodeBasic_Flat_Encoded_Newline,
}

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

read_string_node_from_escaped_string :: proc(input: string) -> (CodeNodeBasic_String, int, bool) {
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

	node : CodeNodeBasic_String
	node.text = strings.to_string(sb)
	return node, end_idx, true
}

codenodes_from_string :: proc(input: string) -> (result: CodeNodeBasic_Flat_Encoded_Array, ok: bool) {
	StackFrame :: struct {
		delimiter: u8,
		nchildren: i32,
		left_token_idx: int,
		parent_node_tree_idx: int,
	}

	dyn_pool : mem.Dynamic_Pool
	mem.dynamic_pool_init(&dyn_pool)

	// Use a custom allocator to make it easy to free everything if things go wrong
	context.allocator = mem.dynamic_pool_allocator(&dyn_pool)

	max_depth := 1
	tree_shape: [dynamic]i32
	colls:    [dynamic]CodeNodeBasic_Flat_Encoded_Coll
	tokens:   [dynamic]CodeNodeBasic_Flat_Encoded_Token
	strings:  [dynamic]CodeNodeBasic_Flat_Encoded_String
	newlines: [dynamic]CodeNodeBasic_Flat_Encoded_Newline

	append(&tree_shape, -2) // to be replaced

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
			append(&newlines, CodeNodeBasic_Flat_Encoded_Newline{idx=auto_cast len(tree_shape)})
			append(&tree_shape, -1)
			nchildren += 1
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
				left_node := &tokens[left_token_idx].node
				left_node.prefix = true
			}
			append(&strings, CodeNodeBasic_Flat_Encoded_String{idx=auto_cast len(tree_shape), node=node})
			append(&tree_shape, -1)
			nchildren += 1
			i = text_start + str_count + 1
		} else {
			try_coll: {
				closer : u8
				coll_type : CodeCollType
				if ch=='(' {
					coll_type = .round
					closer = ')'
				} else if ch=='[' {
					coll_type = .square
					closer = ']'
				} else if ch=='{' {
					coll_type = .curly
					closer = '}'
				} else {
					break try_coll
				}
				if i == last_token_end_i { // has prefix
					left_node := &tokens[left_token_idx].node
					left_node.prefix = true
				}
				node : CodeNodeBasic_Coll
				node.coll_type = coll_type
				append(&colls, CodeNodeBasic_Flat_Encoded_Coll{idx=auto_cast len(tree_shape), node=node})
				append(&tree_shape, -2) // to be replaced later
				nchildren += 1

				new_frame : StackFrame
				new_frame.delimiter = closer
				new_frame.parent_node_tree_idx = len(tree_shape)-1
				append(&stack, new_frame)
				if len(stack)>max_depth {
					max_depth = len(stack)
				}
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
				node : CodeNodeBasic_Token
				node.text = clone_slice(transmute([]u8) segment)
				append(&tokens, CodeNodeBasic_Flat_Encoded_Token{idx=auto_cast len(tree_shape), node=node})
				append(&tree_shape, -1)
				nchildren += 1
				left_token_idx = len(tokens)-1
				last_token_end_i = i

			} else if ch==frame.delimiter {
				tree_shape[parent_node_tree_idx] = nchildren
				pop(&stack)
				i += 1

			} else {
				fmt.println("unexpected character", ch)
				ok = false
				break
			}
		}
	}

	if !ok {
		mem.dynamic_pool_free_all(&dyn_pool)
		mem.dynamic_pool_destroy(&dyn_pool)
		return
	} else {
		tree_shape[0] = stack[0].nchildren
		assert(tree_shape[0] >= 0)
		result.dynamic_pool = dyn_pool
		result.max_depth = auto_cast max_depth
		result.tree_shape = tree_shape[:]
		result.colls = colls[:]
		result.tokens = tokens[:]
		result.strings = strings[:]
		result.newlines = newlines[:]
		return
	}
}

destroy_codenodebasic_flat_encoded_array :: proc(using ary: ^CodeNodeBasic_Flat_Encoded_Array) {
	mem.dynamic_pool_free_all(&dynamic_pool)
	mem.dynamic_pool_destroy(&dynamic_pool)
}

create_codenodes_from_flat_form :: proc(using ary: CodeNodeBasic_Flat_Encoded_Array) -> []CodeNode {
	n_nodes := len(tree_shape)
	if n_nodes==1 {return {}}
	node_ptrs := make([]^CodeNode, n_nodes)

	root_nodes := make([]CodeNode, tree_shape[0])

	StackFrame :: struct {
		siblings: []CodeNode,
		sibling_idx: int,
	}
	stack := make([]StackFrame, max_depth)
	defer delete(stack)

	using frame := &stack[0]
	siblings = root_nodes
	level := 0
	for i := 1 ;; {
		if sibling_idx==len(siblings) {
			level -= 1
			frame = &stack[level]
			continue
		}
		nchildren := tree_shape[i]

		node := &siblings[sibling_idx]
		node_ptrs[i] = node
		sibling_idx += 1
		if nchildren >= 0 {
			nodes := make([dynamic]CodeNode, nchildren)
			node.coll.children = nodes

			level += 1
			stack[level] = {siblings=nodes[:], sibling_idx=0}
			frame = &stack[level]
		}
		i += 1
		if i == len(tree_shape) {break}
	}

	for item in colls {
		node := node_ptrs[item.idx]
		node.tag = .coll
		node.coll.coll_type = item.node.coll_type
	}

	for item in strings {
		node := node_ptrs[item.idx]
		node.tag = .string
		node.string.text = rp.of_string(item.node.text)
	}

	for item in tokens {
		node := node_ptrs[item.idx]
		node.tag = .token
		node.token.text = clone_slice(item.node.text)
		node.token.prefix = item.node.prefix

		if item.node.prefix {
			right_node := node_ptrs[item.idx+1]
			assert(right_node.tag==.string || right_node.tag==.coll)
			codenode_set_prefix(right_node, true)
		}
	}

	for item in newlines {
		node := node_ptrs[item.idx]
		node.tag = .newline
	}

	return root_nodes
}

codeeditor_refresh_from_file :: proc(editor: ^CodeEditor) {
	text, ok := os.read_entire_file_from_filename(editor.file_path)
	if !ok {return}
	flat_nodes, n_ok := codenodes_from_string(string(text))
	if !n_ok {
		fmt.println("error parsing nodes from file")
	}

	nodes := create_codenodes_from_flat_form(flat_nodes)
	defer delete(nodes)
	for node in editor.roots {
		delete_codenode(node)
	}
	clear(&editor.roots)
	append(&editor.roots, ..nodes)

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

	commit_transaction(editor)
}

codenodes_to_flat_array :: proc(roots: []CodeNode) -> (result: CodeNodeBasic_Flat_Encoded_Array) {
	StackFrame :: struct {
		sibling_idx: int,
		siblings: []CodeNode,
	}

	dyn_pool : mem.Dynamic_Pool
	mem.dynamic_pool_init(&dyn_pool)

	// Use a custom allocator to make it easy to free everything
	context.allocator = mem.dynamic_pool_allocator(&dyn_pool)

	max_depth := 1
	tree_shape: [dynamic]i32
	colls:    [dynamic]CodeNodeBasic_Flat_Encoded_Coll
	tokens:   [dynamic]CodeNodeBasic_Flat_Encoded_Token
	strings:  [dynamic]CodeNodeBasic_Flat_Encoded_String
	newlines: [dynamic]CodeNodeBasic_Flat_Encoded_Newline

	append(&tree_shape, auto_cast len(roots))

	stack : [dynamic]StackFrame
	defer delete(stack)
	append(&stack, StackFrame{siblings=roots, sibling_idx=0})

	using frame := &stack[0]
	for {
		if sibling_idx == len(siblings){
			if len(stack)==1 {
				break
			} else {
				pop(&stack)
				frame = &stack[len(stack)-1]
				continue
			}
		}

		live_node := &siblings[sibling_idx]

		switch live_node.tag {
		case .newline:
			append(&newlines, CodeNodeBasic_Flat_Encoded_Newline{idx=auto_cast len(tree_shape)})
			append(&tree_shape, -1)
			sibling_idx += 1
		case .string:
			node : CodeNodeBasic_String
			node.text = rp.to_string(&live_node.string.text)
			append(&strings, CodeNodeBasic_Flat_Encoded_String{idx=auto_cast len(tree_shape), node=node})
			append(&tree_shape, -1)
			sibling_idx += 1
		case .coll:
			node : CodeNodeBasic_Coll
			node.coll_type = live_node.coll.coll_type
			append(&colls, CodeNodeBasic_Flat_Encoded_Coll{idx=auto_cast len(tree_shape), node=node})
			append(&tree_shape, auto_cast len(live_node.coll.children))
			sibling_idx += 1

			new_frame : StackFrame
			new_frame.siblings = live_node.coll.children[:]
			new_frame.sibling_idx = 0
			append(&stack, new_frame)
			if len(stack)>max_depth {
				max_depth = len(stack)
			}
			frame = &stack[len(stack)-1]
		case .token:
			node : CodeNodeBasic_Token
			node.prefix = live_node.token.prefix
			node.text = clone_slice(live_node.token.text)
			append(&tokens, CodeNodeBasic_Flat_Encoded_Token{idx=auto_cast len(tree_shape), node=node})
			append(&tree_shape, -1)
			sibling_idx += 1
		}
	}

	result.dynamic_pool = dyn_pool
	result.max_depth = auto_cast max_depth
	result.tree_shape = tree_shape[:]
	result.colls = colls[:]
	result.tokens = tokens[:]
	result.strings = strings[:]
	result.newlines = newlines[:]
	return
}