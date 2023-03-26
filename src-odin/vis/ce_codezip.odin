package vis

import "core:fmt"
import "core:mem"
import "core:math"
import "core:strings"
import "core:time"
import "core:slice"


CodeNode_Zipper :: struct {
	node: ^CodeNode,
	stack: [dynamic]struct {
		idx: int,
		nodes: []CodeNode,
	},
}

delete_codezip :: proc(zip: CodeNode_Zipper) {
	delete(zip.stack)
}

codezip_siblings :: proc(using zip: CodeNode_Zipper) -> []CodeNode {
	return stack[len(stack)-1].nodes
}

get_codezip_at_path :: proc(editor: ^CodeEditor, path: []int) -> (zip: CodeNode_Zipper) {
	if len(path)==0 {return}
	level := 0
	siblings := &editor.roots
	for {
		append_nothing(&zip.stack)
		idx := path[level]
		zip.stack[level].idx = idx
		zip.stack[level].nodes = siblings[:]
		node := &siblings[idx]
		level += 1
		if len(path)==level {
			zip.node = node
			return
		}
		siblings = &node.coll.children
	}
}

codezip_to_next :: proc(using zip: ^CodeNode_Zipper) {
	level := len(stack)-1
	for {
		sf := &stack[level]
		if sf.idx==len(sf.nodes)-1 {
			pop(&stack)
			if level==0 {
				node = nil
				return
			}
			level -= 1
		} else {
			sf.idx += 1
			node = &sf.nodes[sf.idx]
			return
		}
	}
}

codezip_to_next_in :: proc(using zip: ^CodeNode_Zipper) {
	level := len(stack)-1
	for {
		sf := &stack[level]
		switch node.tag {
		case .token, .string, .newline:
			codezip_to_next(zip)
			return
		case .coll:
			children := &node.coll.children
			if len(children)==0 {
				codezip_to_next(zip)
				return
			} else {
				node = &children[0]
				level += 1
				append_nothing(&stack)
				zip.stack[level].idx = 0
				zip.stack[level].nodes = children[:]
				return
			}
		}
	}
}

codezip_to_prev :: proc(using zip: ^CodeNode_Zipper) {
	level := len(stack)-1
	for {
		sf := &stack[level]
		if sf.idx==0 {
			pop(&stack)
			if level==0 {
				node = nil
				return
			}
			level -= 1
		} else {
			sf.idx -= 1
			node = &sf.nodes[sf.idx]
			return
		}
	}
}

codezip_to_prev_in :: proc(using zip: ^CodeNode_Zipper) {
	level := len(stack)-1
	for {
		sf := &stack[level]
		switch node.tag {
		case .token, .string, .newline:
			codezip_to_prev(zip)
			return
		case .coll:
			children := &node.coll.children
			if len(children)==0 {
				codezip_to_prev(zip)
				return
			} else {
				last_idx := len(children)-1
				node = &children[last_idx]
				level += 1
				append_nothing(&stack)
				zip.stack[level].idx = last_idx
				zip.stack[level].nodes = children[:]
				return
			}
		}
	}
}

codezip_to_parent :: proc(using zip: ^CodeNode_Zipper) {
	level := len(stack)-1
	if level==0 {
		node=nil
	} else {
		pop(&stack)
		sf := &stack[level-1]
		node= &sf.nodes[sf.idx]
	}
}

codezip_path :: proc(using zip: CodeNode_Zipper) -> []int {
	path := make([]int, len(stack))
	for sf, i in stack {
		path[i] = sf.idx
	}
	return path
}

codezip_idx :: proc(using zip: CodeNode_Zipper) -> int {
	return stack[len(stack)-1].idx
}

codeeditor_event_mouse_scroll :: proc(window: ^Window, using editor: ^CodeEditor, dx: i32, dy: i32) {
	new_scroll_offset := scroll_offset + {dx, dy}
	request_new_scroll(editor, new_scroll_offset)
}
