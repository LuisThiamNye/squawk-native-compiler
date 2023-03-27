package vis

/*
Assumptions:
- Nesting is small
- Tokens are short
- Strings are not absurdly long
*/

import "core:fmt"
import "core:mem"
import "core:math"
import "core:strings"
import "core:time"
import "core:os"
import "core:slice"
import "core:io"
import "core:unicode/utf8"

import sk "../skia"
import rp "../rope"


CursorPosition :: struct #raw_union {
	idx: int, // >= 0
	place: enum int {before=-1, after=-2},
	coll_place: enum int{open_pre=0, open_post=1, close_pre=2, close_post=3},
}

Cursor :: struct {
	path: []int,
	using position: CursorPosition,
}

Region :: struct {
	using _cursors: struct #raw_union {
		using _tofrom: struct {
			to: Cursor,
			from: Cursor,
		},
		cursors: [2]Cursor,
	},
	xpos: f32,
	invalidate_xpos: bool,
}

region_is_point :: proc(using region: Region) -> bool {
	if (len(to.path) != len(from.path)) {return false}
	for i in 0..<len(to.path) {
		if to.path[i] != from.path[i] {return false}
	}
	if from.idx != to.idx {return false}
	return true
}

CodeNode_Tag :: enum {
	coll,
	token,
	string,
	newline,
}

CodeNode :: struct {
	tag: CodeNode_Tag,
	using node: struct #raw_union {
		coll: CodeNode_Coll,
		token: CodeNode_Token,
		string: CodeNode_String,
		newline: CodeNode_Newline,
	},
	pos: [2]f32,
	flags: bit_set[enum {insert_before, insert_after, insert_first_child}],
}

delete_codenode :: proc(node: CodeNode) {
	if node.tag==.token {
		delete(node.token.text)
	} else if node.tag==.string {
		rp.delete_rope(node.string.text)
	} else if node.tag==.coll {
		for child in node.coll.children {
			delete_codenode(child)
		}
		delete(node.coll.children)
	}
}

delete_codenode_shallow :: proc(node: CodeNode) {
	if node.tag==.coll {
	} else {
		delete_codenode(node)
	}
}

CodeCollType :: enum {round, curly, square}

CodeNodeBasic_Coll :: struct {
	coll_type: CodeCollType,
}

CodeNode_Coll :: struct {
	using _basic: CodeNodeBasic_Coll,
	prefix: bool,
	children: [dynamic]CodeNode,
	close_pos: [2]f32,
}

CodeNodeBasic_Token :: struct {
	text: []u8,
	prefix: bool,
}

CodeNode_Token :: struct {
	using _basic: CodeNodeBasic_Token,
}

CodeNodeBasic_String :: struct {
	text: string,
}

CodeNode_String :: struct {
	text: rp.RopeNode,
	lines: []struct{width: f32, text: string},
	prefix: bool,
}

CodeNode_Newline :: struct {
	after_pos: [2]f32,
}

CodeEditor :: struct {
	initP: bool,
	regions_changed: bool,
	regions: [dynamic]Region,
	roots: [dynamic]CodeNode,
	font: sk.SkFont, // one frame lifetime
	file_path: string,

	view_rect: Rect_i32,
	contents_rect: Rect_i32,
	scroll_offset: [2]i32,
	smooth_scroll: struct {
		latest_time: i64, // ms
		prev_event_dts: [2]u16, // ms, newest from right to left; times between scroll events
		duration: u16, // ms
		start_pos: [2]i32, // relative to view_rect
		control_point1s: [2][2]f32,
	},

	space_width: f32,
	line_height: f32,

	transactions: [dynamic]CodeEditor_Tx,
	pending_edit_tx_deltas: [dynamic]EditTxDelta,
}

CodeEditor_Tx :: struct {
	regions_tx: RegionsTx,
	edit_tx: EditTx,
}

RegionsTx :: struct {
	snapshots: []RegionTxSnapshot,
}

RegionTxSnapshot :: struct {
	to: CursorTxSnapshot,
	from: CursorTxSnapshot,
	xpos: f32,
}
CursorTxSnapshot :: struct {
	position: CursorPosition,
	flat_idx: i32,
}

EditTx :: struct {
	deltas: []EditTxDelta,
}

CodeNodeBasic :: struct {
	tag: CodeNode_Tag,
	using alt: struct #raw_union {
		coll: CodeNodeBasic_Coll,
		token: CodeNodeBasic_Token,
		string: CodeNodeBasic_String,
	},
}

EditTxDelta :: struct {
	tag: enum {insert_nodes},
	reversed: bool,
	using alt: struct #raw_union {
		insert_nodes: struct {
			index: i32, // insertion index
			flat_node_idx: i32, // location of the parent node. 0 = root
			flat_node_array: CodeNodeBasic_Flat_Encoded_Array,
		},
	},
}

codenode_has_prefix :: proc(node: ^CodeNode) -> bool {
	if node.tag==.coll {
		return node.coll.prefix
	} else if node.tag==.string {
		return node.string.prefix
	} else {
		return false
	}
}

codenode_set_prefix :: proc(node: ^CodeNode, prefix: bool) {
	if node.tag==.coll {
		node.coll.prefix = prefix
	} else if node.tag==.string {
		node.string.prefix = prefix
	}
}

dbg_println_cursor :: proc(cursor: Cursor) {
	fmt.print("Cursor:", cursor.path, "")
	if cursor.idx>=0 {
		fmt.print("idx:", cursor.idx)
	} else {
		fmt.print("place:", cursor.place)
	}
	fmt.println()
}

cursor_move_right :: proc(editor: ^CodeEditor, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil {
		if len(editor.roots)>0 {
			cursor_path_append(cursor, 0)
			cursor.idx=0
		}
		return
	}
	node_idx := path[len(path)-1]
	prefix := false

	switch node.tag {

	case .newline:
		if cursor.place==.after {
			siblings := get_siblings_of_codenode(editor, path)
			if node_idx+1<len(siblings) {
				right_node := &siblings[node_idx+1]
				if right_node.tag == .newline {
					cursor.path[len(cursor.path)-1] += 1
					cursor.idx = 0
					node_idx += 1
					node = right_node
					break
				}
			}
		}
		break

	case .token:
		token := node.token
		if cursor.place==.after || cursor.idx == len(token.text) {
			if token.prefix {prefix=true}
			break
		} else if cursor.idx>=0 {
			text_idx := cursor.idx
			_, size := utf8.decode_rune_in_bytes(token.text[text_idx:])
			cursor.idx += size
		} else {
			cursor.idx=0
		}
		return

	case .string:
		text := node.string.text
		if cursor.place==.after || cursor.idx == rp.get_count(text)+2 {
			break
		} else if cursor.idx>0 {
			text_idx := cursor.idx-1
			if text_idx < rp.get_count(text) {
				text := rp.to_string(&text, context.temp_allocator)
				_, size := utf8.decode_rune_in_string(text[text_idx:])
				cursor.idx += size
			} else {
				cursor.idx += 1
			}
		} else {
			cursor.idx += 1
		}
		return

	case .coll:
		if cursor.coll_place==.close_post || cursor.place==.after {
			break
		} else if cursor.coll_place==.open_post {
			if len(node.coll.children)>0 {
				cursor_path_append(cursor, 0)
				cursor.idx = 0
			} else {
				cursor.coll_place=.close_post
			}
		} else {
			if cursor.coll_place==.open_pre && len(node.coll.children)>0 {
				cursor_path_append(cursor, 0)
				cursor.idx = 0
			} else {
				cursor.idx += 1
			}
		}
		return
	}
	// go to next node
	on_newline := node.tag==.newline
	siblings := get_siblings_of_codenode(editor, path)
	for {
		if node_idx<len(siblings)-1 {
			node_idx += 1
			target_node := &siblings[node_idx]
			cursor.path[len(path)-1] = node_idx
			if target_node.tag==.newline && !on_newline{
				on_newline = true
				continue
			}
			cursor.idx = 0
			if prefix {
				cursor_move_right(editor, cursor)
			}
		} else if len(path)>0 {
			if siblings[node_idx].tag==.newline && cursor.place != .after {
				cursor.place = .after
			} else {
				zip := get_codezip_at_path(editor, path)
				defer delete_codezip(zip)
				codezip_to_parent(&zip)
				if zip.node != nil {
					delete(cursor.path)
					cursor.path = codezip_path(zip)
					cursor.coll_place = .close_post
				}
			}
		}
		break
	}
}

cursor_move_left :: proc(editor: ^CodeEditor, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil{return}
	node_idx := path[len(path)-1]

	switch node.tag{

	case .newline:
		if cursor.place==.after {
			cursor.idx=0
			if node_idx>0 {
				siblings := get_siblings_of_codenode(editor, path)
				if siblings[node_idx-1].tag != .newline {
					break
				}
			}
		} else {
			break
		}
		return

	case .token:
		token := node.token
		if cursor.place == .after {
			cursor.idx = len(token.text)
		} else if cursor.idx > 0 {
			text_idx := cursor.idx
			_, size := utf8.decode_last_rune(token.text[:text_idx])
			cursor.idx -= size
		} else {
			break
		}
		return

	case .string:
		text := node.string.text
		if cursor.place == .after {
			cursor.idx = rp.get_count(text)+2
		} else if cursor.idx > 0 {
			text_idx := cursor.idx-1
			if text_idx > 0 && text_idx<=rp.get_count(text) {
				text := rp.to_string(&text, context.temp_allocator)
				_, size := utf8.decode_last_rune(text[:text_idx])
				cursor.idx -= size
			} else {
				cursor.idx -= 1
				if node.string.prefix && cursor.idx==0 {break}
			}
		} else {
			break
		}
		return

	case .coll:
		if cursor.coll_place==.open_pre || cursor.place==.before{
			break
		} else if cursor.place==.after {
			cursor.coll_place=.close_post
		} else if cursor.coll_place==.close_post {
			children := &node.coll.children
			if len(children) > 0 {
				child_idx := len(children)-1
				cursor_path_append(cursor, child_idx)
				child := &children[child_idx]
				cursor.idx = last_idx_of_node(child)
				if child.tag==.newline {
					cursor.place = .after
				}
			} else {
				cursor.coll_place = .open_post
			}
		} else {
			cursor.idx -= 1
		}
		if node.coll.prefix && cursor.coll_place==.open_pre {break}
		return
	}
	// go to prev node
	siblings := get_siblings_of_codenode(editor, path)
	for {
		if node_idx>0 {
			node_idx -= 1
			target_node := &siblings[node_idx]
			cursor.path[len(path)-1] = node_idx
			if target_node.tag==.newline {
				if node_idx>0 && siblings[node_idx-1].tag!=.newline {
					continue
				}
				cursor.idx=0
			} else {
				cursor.idx = last_idx_of_node(target_node)
			}
		} else if len(path)>0 {
			zip := get_codezip_at_path(editor, path)
			defer delete_codezip(zip)
			codezip_to_parent(&zip)
			if zip.node != nil {
				delete(cursor.path)
				cursor.path = codezip_path(zip)
				cursor.coll_place = .open_pre
				if zip.node.coll.prefix {
					cursor_move_left(editor, cursor)
				}
			}
		}
		break
	}
}

cursor_move_right_token_end :: proc(editor: ^CodeEditor, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil {
		if len(editor.roots)>0 {
			cursor_path_append(cursor, 0)
			cursor.idx=0
			node = &editor.roots[0]
		} else {
			return
		}
	}

	switch node.tag {

	case .newline: break

	case .token:
		token := node.token
		if cursor.place==.after || cursor.idx == len(token.text) {
			break
		} else {
			cursor.idx = len(token.text)
		}
		return

	case .string:
		if cursor.place==.after || cursor.idx == last_idx_of_node(node) {
			break
		} else {
			cursor.idx = last_idx_of_node(node)
		}
		return

	case .coll: break
	}
	// go to next node
	zip := get_codezip_at_path(editor, path)
	defer delete_codezip(zip)
	delete(cursor.path)
	if zip.node!=nil&&zip.node.tag==.coll&&
	(cursor.coll_place==.close_pre||cursor.coll_place==.close_post||
		cursor.place==.after) {
		codezip_to_next(&zip)
	} else {
		codezip_to_next_in(&zip)
	}
	for {
		if zip.node==nil {
			cursor.path = make(type_of(cursor.path), 1)
			cursor.path[0]=len(editor.roots)-1
			cursor.idx = last_idx_of_node(&editor.roots[cursor.path[0]])
			return
		} else if zip.node.tag==.token || zip.node.tag==.string {
			cursor.path = codezip_path(zip)
			cursor.idx = last_idx_of_node(zip.node)
			return
		}
		codezip_to_next_in(&zip)
	}
}

cursor_move_left_token_start :: proc(editor: ^CodeEditor, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil {return}

	switch node.tag {

	case .newline: break

	case .token:
		token := node.token
		if cursor.place==.before || cursor.idx == 0 {
			break
		} else {
			cursor.idx = 0
		}
		return

	case .string:
		if cursor.place==.before||cursor.idx==0{
			break
		} else {
			cursor.idx = 0
		}
		return

	case .coll: break
	}
	// go to next node
	zip := get_codezip_at_path(editor, path)
	defer delete_codezip(zip)
	if zip.node!=nil&&zip.node.tag==.coll&&
	(cursor.coll_place==.close_pre||cursor.coll_place==.close_post||
		cursor.place==.after) {
		codezip_to_prev_in(&zip)
	} else {
		codezip_to_prev(&zip)
	}
	delete(cursor.path)
	for {
		if zip.node==nil {
			cursor.path = make(type_of(cursor.path), 1)
			cursor.path[0]=0
			cursor.idx = 0
			return
		} else if zip.node.tag==.token || zip.node.tag==.string {
			cursor.path = codezip_path(zip)
			cursor.idx = 0
			return
		}
		codezip_to_prev_in(&zip)
	}
}

cursor_move_right_sibling :: proc(editor: ^CodeEditor, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil {
		if len(editor.roots)>0 {
			cursor_path_append(cursor, 0)
			cursor.idx=0
			node = &editor.roots[0]
		} else {
			return
		}
	}

	switch node.tag {

	case .newline: break

	case .token:
		token := node.token
		if cursor.place==.after || cursor.idx == len(token.text) {
			if token.prefix {
				cursor.path[len(path)-1]+=1
				cursor.idx = 0
				node = get_node_at_path(editor, path)
			}
			break
		} else {
			cursor.idx = len(token.text)
		}
		return

	case .string:
		if cursor.place==.after || cursor.idx == last_idx_of_node(node) {
			break
		} else {
			cursor.idx = last_idx_of_node(node)
		}
		return

	case .coll: break
	}
	// go to next node
	zip := get_codezip_at_path(editor, path)
	defer delete_codezip(zip)

	siblings := codezip_siblings(zip)
	node_idx := path[len(path)-1]
	if node_idx==len(siblings)-1 { // last child
		if node.tag==.coll {
			if cursor.coll_place != .close_post {
				cursor.coll_place=.close_post
			}
			return
		} else if node.tag==.token {
			return
		} else { return }
	}

	delete(cursor.path)
	if zip.node!=nil && zip.node.tag==.coll && cursor.coll_place==.open_post {
		codezip_to_next_in(&zip)
	} else {
		codezip_to_next(&zip)
	}
	for {
		if zip.node==nil {
			cursor.path = make(type_of(cursor.path), 1)
			cursor.path[0]=len(editor.roots)-1
			cursor.idx = last_idx_of_node(&editor.roots[cursor.path[0]])
			return
		} else if zip.node.tag != .newline {
			if zip.node.tag==.coll {
				cursor.path = codezip_path(zip)
				cursor.idx = 0
			} else {
				cursor.path = codezip_path(zip)
				cursor.idx = last_idx_of_node(zip.node)
			}
			return
		}
		codezip_to_next(&zip)
	}
}

cursor_move_left_sibling :: proc(editor: ^CodeEditor, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil {return}

	switch node.tag {

	case .newline: break

	case .token:
		token := node.token
		if cursor.place==.before || cursor.idx == 0 {
			break
		} else {
			cursor.idx = 0
		}
		return

	case .string:
		if cursor.place==.before||cursor.idx==0{
			break
		} else {
			cursor.idx = 0
		}
		return

	case .coll:
		if cursor.coll_place==.close_post {
			cursor.coll_place = .open_pre
			if node.coll.prefix {cursor_move_left(editor, cursor)}
			return
		}
	}
	// go to next node
	zip := get_codezip_at_path(editor, path)
	defer delete_codezip(zip)

	node_idx := path[len(path)-1]

	if node_idx==0 && node.tag != .newline {
		return
	}

	if zip.node!=nil && zip.node.tag==.coll && cursor.coll_place==.close_pre {
		codezip_to_prev_in(&zip)
	} else {
		codezip_to_prev(&zip)
	}
	delete(cursor.path)
	for {
		if zip.node==nil {
			cursor.path = make(type_of(cursor.path), 1)
			cursor.path[0]=0
			cursor.idx = 0
			cursor_move_left(editor, cursor)
			return
		} else if zip.node.tag != .newline {
			if zip.node.tag==.coll && zip.node.coll.prefix {
				codezip_to_prev(&zip)
			}
			cursor.path = codezip_path(zip)
			cursor.idx = 0
			return
		}
		codezip_to_prev(&zip)
	}
}

cursor_move_to_start_of_coll :: proc(editor: ^CodeEditor, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil {return}

	if node.tag==.string {
		text_idx := cursor.idx-1
		if text_idx >= 0 {
			c := 0
			c2 := 0
			for line in node.string.lines {
				c2 += 1+len(line.text)
				if text_idx < c2 {
					break
				}
				c = c2
			}
			if text_idx < c2 {
				cursor.idx = 1+c
				return
			}
		}
	}

	zip := get_codezip_at_path(editor, path)
	defer delete_codezip(zip)
	codezip_to_parent(&zip)
	parent := zip.node
	if parent == nil {
		delete(path)
		cursor.path = make(type_of(path), 1)
		cursor.path[0] = 0
	} else {
		if cursor.path[len(path)-1]==0 && cursor.idx==0 {
			delete(path)
			cursor.path = codezip_path(zip)
		}
		cursor.path[len(path)-1]=0
	}
	cursor.idx = 0
}

cursor_move_out_to_insert_newline :: proc(editor: ^CodeEditor, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil {
		if len(editor.roots)>0 {
			cursor_path_append(cursor, 0)
			cursor.idx=0
		} else {
			return
		}
	}

	node_idx := path[len(path)-1]

	move_out := true

	switch node.tag {

	case .newline:
	case .token:
	case .string:

	case .coll:
		if cursor.coll_place==.open_pre || cursor.coll_place==.open_post ||
		cursor.coll_place==.close_pre {
			cursor.place = .after
			move_out = false
		}
	}

	target_node : ^CodeNode
	siblings := get_siblings_of_codenode(editor, cursor.path)

	// go to next node
	if move_out {
		zip := get_codezip_at_path(editor, cursor.path)
		defer delete_codezip(zip)
		codezip_to_parent(&zip)
		parent := zip.node
		delete(cursor.path)
		if parent==nil {
			cursor.path = make(type_of(cursor.path), 1)
			cursor.path[0]=len(editor.roots)-1
			last_node := &siblings[cursor.path[0]]
			cursor.idx = last_idx_of_node(last_node)
			target_node = last_node
		} else { // parent is the coll to append after
			cursor.path = codezip_path(zip)
			cursor.place = .after
			target_node = parent
		}
	}

	// handle newline insertion
	outer_siblings := get_siblings_of_codenode(editor, cursor.path)

	should_remove_newline := node.tag==.newline && siblings!=outer_siblings
	if should_remove_newline {
		delete_codenode(node^)
		ordered_remove(siblings, node_idx)
	}

	outer_node_idx := cursor.path[len(cursor.path)-1]
	should_newline := (node.tag!=.newline||siblings!=outer_siblings)&& (
		outer_node_idx==len(outer_siblings)-1 ||
		outer_siblings[outer_node_idx+1].tag==.newline)

	if should_newline {
		nl : CodeNode
		nl.tag = .newline
		inject_at(outer_siblings, outer_node_idx+1, nl)
		cursor.path[len(cursor.path)-1] = outer_node_idx+1
		cursor.idx=0

	}
}

cursor_to_parent :: proc(cursor: ^Cursor) {
	rp.slice_pop(&cursor.path)
	if len(cursor.path)==0 {
		cursor.idx = 0
	} else {
		cursor.coll_place = .open_post
	}
}

remove_sibling_codenodes :: proc(using editor: ^CodeEditor, start_path: []int, n: int) {
	if n==0 {return}
	siblings := get_siblings_of_codenode(editor, start_path)
	level := len(start_path)-1
	start_node_idx := start_path[level]
	end_node_idx := start_node_idx+n
	parent_path := start_path[:level]

	// move cursors
	for region in &regions {
		for cursor in &region.cursors {
			if level<len(cursor.path) && slice.equal(cursor.path[:level], parent_path) && start_node_idx<=cursor.path[level] { // cursor affected
				cursor_node_idx := cursor.path[level]
				if end_node_idx<=cursor_node_idx { // cursors to the right get shifted left
					cursor.path[level] -= n
				} else { // cursors on deleted nodes get moved away
					if start_node_idx > 0 { // cursor moves left
						cursor.path[level] = start_node_idx-1
						next_node := &siblings[start_node_idx-1]
						cursor.idx = last_idx_of_node(next_node)
					} else {
						// cursor moves to parent; inserting first child
						if len(cursor.path)==1 && len(siblings)>n { // stay down to avoid the root
							cursor.path[len(cursor.path)-1] = 0
							cursor.idx = 0
						} else {
							cursor_to_parent(&cursor)
						}
					}
				}
			}
		}
	}

	// delete nodes
	for i in 0..<n {
		remove_node_from_siblings(editor, siblings, start_node_idx)
	}
}

codenode_remove :: proc(editor: ^CodeEditor, node: ^CodeNode, cursor: ^Cursor) {
	remove_sibling_codenodes(editor, cursor.path, 1)
}

codenode_remove2 :: proc(editor: ^CodeEditor, node: ^CodeNode, path: []int, node_idx: int) {
	siblings := get_siblings_of_codenode(editor, path)
	remove_node_from_siblings(editor, siblings, node_idx)
}

remove_node_from_siblings :: proc(editor: ^CodeEditor, siblings: ^[dynamic]CodeNode, node_idx: int) {
	node := &siblings[node_idx]
	if node.tag==.token && node.token.prefix {
		codenode_set_prefix(&siblings[node_idx+1], false)
	} else if codenode_has_prefix(node) {
		siblings[node_idx-1].token.prefix = false
	}
	delete_codenode(node^) // must delete before removing
	ordered_remove(siblings, node_idx)
}

cursor_delete_left :: proc(editor: ^CodeEditor, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil {return}

	if node.tag==.newline && cursor.place==.after {
		codenode_remove(editor, node, cursor)
	} else
	// Delete before
	if cursor.place==.before || cursor.idx==0 {
		node_idx := path[len(path)-1]
		if node_idx == 0 {
			if len(path)>1 {
				cursor_to_parent(cursor)
				cursor_delete_left(editor, cursor)
			}
		} else {
			siblings := get_siblings_of_codenode(editor, path)
			left_node := &siblings[node_idx-1]
			if left_node.tag==.newline {
				codenode_remove2(editor, left_node, path, node_idx-1)
				cursor.path[len(path)-1] -= 1
			} else {
				cursor_move_left(editor, cursor)
			}
		}
	} else {
		switch node.tag {

		case .newline: panic("unreachable: already handled")

		case .token:
			token := node.token
			if cursor.place == .after {
				cursor.idx = len(token.text) // move left

			} else if cursor.idx > 0 {
				// delete a char
				text := &node.token.text
				text_idx := cursor.idx
				_, size := utf8.decode_last_rune(text[:text_idx])

				if len(token.text)==size { // delete the node
					codenode_remove(editor, node, cursor)
					if token.prefix {
						cursor_move_right(editor, cursor)
					}
				} else {
					text2 := make([]u8, len(text)-size)
					copy(text2, text[:cursor.idx-size])
					if cursor.idx < len(text) {
						copy(text2[cursor.idx-size:], text[cursor.idx:])
					}
					delete(text^)
					text^ = text2
					cursor.idx -= size
				}
			}
			return

		case .string:
			text_idx := cursor.idx-1
			if cursor.place == .after {
				cursor.idx = rp.get_count(node.string.text)+2 // move left
			} else if cursor.idx==1 || text_idx>rp.get_count(node.string.text) { // delete the node
				codenode_remove(editor, node, cursor)
			} else if text_idx>0 {
				// delete a char
				text := &node.string.text
				text_str := rp.to_string(text, context.temp_allocator)
				_, size := utf8.decode_last_rune(text_str[:text_idx])
				rp.remove_range(text, text_idx-size, text_idx)
				cursor.idx -= size
			}
			return

		case .coll:
			if cursor.place==.after {
				cursor.idx=2 // move left
			} else if cursor.coll_place==.open_post { // splice
				children := &node.coll.children
				if len(children) > 0 {
					siblings := get_siblings_of_codenode(editor, cursor.path)
					node_idx := path[len(path)-1]
					node_value := node^ // the next instruction will invalidate the node pointer
					children = &node_value.coll.children
					replace_span(siblings, node_idx, node_idx+1, children[:])

					delete(children^)
					delete_codenode_shallow(node_value)

					cursor.idx = 0
				} else {
					codenode_remove(editor, node, cursor)
				}
			}
			return
		}
	}
}

replace_span :: proc(array: ^[dynamic]$E, start: int, end: int, extras: []$A, loc := #caller_location) -> bool #no_bounds_check {
	n_extras := len(extras)
	new_size := len(array) - (end-start) + n_extras
	if new_size > len(array) {
		if !resize(array, new_size, loc) {
			return false
		}
		if end<len(array) {
			copy(array[start+n_extras:], array[end:])
		}
	} else {
		if end<len(array) {
			copy(array[start+n_extras:], array[end:])
		}
		if !resize(array, new_size, loc) {
			return false
		}
	}
	copy(array[start:], extras)
	return true
}


cursor_move_up :: proc(editor: ^CodeEditor, region: ^Region, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil{return}
	switch node.tag{

	case .newline: break

	case .token:
		// return

	case .string:
		text := node.string.text
		if cursor.idx > 0 {
			font := editor.font
			lines := node.string.lines
			char_count := -1
			for line, i in lines {
				char_count += 1
				text_idx := cursor.idx-1-char_count
				line_text := line.text
				char_count += len(line_text)
				if 0 <= text_idx && text_idx <= len(line_text) {
					if region.xpos==-1 {
						region.xpos = measure_text_width(font, line_text[:text_idx])
					}
					if i>0 {
						target_line_text := transmute([]u8) lines[i-1].text
						target_line_idx := get_offset_at_coord(font, target_line_text, region.xpos)
						cursor.idx -= 1+text_idx+(len(target_line_text)-target_line_idx)
					} else {
						cursor.idx = 1
					}
					region.invalidate_xpos = false
					break
				}
			}
			if cursor.idx==char_count+2 {
				break
			}
		} else {
			break
		}
		return

	case .coll:
		// return
	}

	cursor_move_left_sibling(editor, cursor)
}

cursor_move_down :: proc(editor: ^CodeEditor, region: ^Region, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	try_specific: {
		if node != nil && node.tag==.string{
			text := node.string.text
			if cursor.idx > 0 {
				font := editor.font
				lines := node.string.lines
				char_count := -1
				i : int
				for line, i_ in lines {
					i = i_
					char_count += 1
					text_idx := cursor.idx-1-char_count
					line_text := line.text
					char_count += len(line_text)
					if 0 <= text_idx && text_idx <= len(line_text) {
						if region.xpos==-1 {
							region.xpos = measure_text_width(font, line_text[:text_idx])
						}
						if i<len(lines)-1 {
							target_line_text := transmute([]u8) lines[i+1].text
							target_line_idx := get_offset_at_coord(font, target_line_text, region.xpos)
							cursor.idx += 1+target_line_idx+(len(line_text)-text_idx)
						} else {
							cursor.idx = 1+char_count
						}
						region.invalidate_xpos = false
						break
					}
				}
				if cursor.idx==char_count+2 && i==len(lines)-1{
					break try_specific
				}
			} else {
				break try_specific
			}
			return
		}
	}

	cursor_move_right_sibling(editor, cursor)
}

last_idx_of_node :: proc(node: ^CodeNode) -> int {
	switch node.tag {
	case .token:
		return len(node.token.text)
	case .string:
		return rp.get_count(node.string.text)+2
	case .coll:
		return CursorPosition{coll_place=.close_post}.idx
	case .newline:
		return CursorPosition{place=.after}.idx
		// return 0
	}
	panic("")
}

ordered_cursors :: proc(editor: ^CodeEditor, region: ^Region) -> (left_cursor: ^Cursor, right_cursor: ^Cursor) {
	to := &region.to
	from := &region.from
	to_is_ahead := false

	if len(from.path)==0 {
		to_is_ahead = len(to.path)!=0
	} else if len(to.path)==0 {
		// to_is_ahead = false
	} else {
		from_level := len(from.path)-1
		to_level := len(to.path)-1
		for i := 0; i < len(from.path); i += 1 {
			from_node_idx := from.path[i]
			to_node_idx := to.path[i]

			if from_node_idx < to_node_idx {
				to_is_ahead = true
				break
			} else if to_node_idx < from_node_idx {
				// to_is_ahead = false
				break

			} else if i==from_level && i==to_level { // same node
				if to.place==.after {
					if from.place != .after {
						to_is_ahead = true
					}
				} else if to.place==.before {
					// to_is_ahead = false
				} else if from.idx < to.idx {
					to_is_ahead = true
				}
				break

			} else if i==from_level || i==to_level {
				high_cursor : ^Cursor
				low_cursor : ^Cursor
				container_node : ^CodeNode
				if i==from_level {
					high_cursor = from
					low_cursor = to
					container_node = get_node_at_path(editor, from.path)
				} else {
					high_cursor = to
					low_cursor = from
					container_node = get_node_at_path(editor, to.path)
				}
				container_ahead := false
				switch container_node.tag {
				case .token, .newline, .string:
					fmt.println("i", i, ", from_level", from_level)
					fmt.panicf("unreachable: %v node cannot have cursor at child position. From: %v, To: %v\n", container_node.tag, from.path, to.path)
				case .coll:
					if (high_cursor.place==.after || high_cursor.coll_place==.close_pre ||
						high_cursor.coll_place==.close_post) {
						container_ahead=true
					}
				}
				if container_ahead {
					left_cursor = low_cursor
					right_cursor = high_cursor
				} else {
					left_cursor = high_cursor
					right_cursor = low_cursor
				}
				return

			} else {
				continue
			}
		}
	}

	if to_is_ahead {
		left_cursor = &region.from
		right_cursor = &region.to
	} else {
		left_cursor = &region.to
		right_cursor = &region.from
	}
	return
}

deep_copy :: proc{deep_copy_cursor, deep_copy_region}

deep_copy_region :: proc(dest: ^Region, src: ^Region) {
	mem.copy(dest, src, size_of(Region))
	deep_copy_cursor(&dest.from, &src.from)
	deep_copy_cursor(&dest.to, &src.to)
}

deep_copy_cursor :: proc(dest: ^Cursor, src: ^Cursor) {
	mem.copy(dest, src, size_of(Cursor))
	dest.path = make(type_of(dest.path), len(src.path))
	copy(dest.path, src.path)
}

commit_region_simple_move :: proc(using editor: ^CodeEditor, reset_selection: bool, direction: enum {right, left, down, up, home}) {
	for region in &regions {
		region.invalidate_xpos = true
		lc_, rc_ := ordered_cursors(editor, &region)
		lc := lc_^
		rc := rc_^
		is_point := region_is_point(region)
		collapsing_selection := reset_selection && !is_point
		
		is_block := !reset_selection && region_is_block_selection(editor, &region)
		block_level := region_block_level(region)
		single_block_selection := is_block && region.to.path[block_level]==region.from.path[block_level]
		is_on_from_level := len(region.from.path)-1==block_level

		switch direction {
		case .right:
			if collapsing_selection {
				region.to = rc
				region.from = lc
			} else {
				if is_block && (!single_block_selection || is_on_from_level) {
					node := get_node_at_path(editor, region.to.path)
					if node != nil {
						edge_idx := last_idx_of_node(node)
						if edge_idx != region.to.idx {
							region.to.idx = edge_idx
							if is_point {
								break
							}
						}
					}
				}
				cursor_move_right(editor, &region.to)
			}
		case .left:
			if collapsing_selection {
				region.to = lc
				region.from = rc
			} else {
				if is_block && (!single_block_selection || is_on_from_level) {
					if region.to.idx != 0 {
						region.to.idx = 0
						if is_point {
							break
						}
					}
				}
				cursor_move_left(editor, &region.to)
			}
		case .down:
			cursor_move_down(editor, &region, &region.to)
		case .up:
			cursor_move_up(editor, &region, &region.to)
		case .home:
			cursor_move_to_start_of_coll(editor, &region.to)
		}

		if reset_selection {
			delete_cursor(region.from)
			deep_copy(&region.from, &region.to)
		} else {
			// raise cursor up to block level
			block_level := region_block_level(region)
			n := block_level + 1
			if n < len(region.to.path) {
				rp.slice_resize(&region.to.path, 0, n)
			}

			is_block = is_block || region_is_block_selection(editor, &region)

			lc, rc := ordered_cursors(editor, &region)
			reversed := lc==&region.to

			node := get_node_at_path(editor, region.to.path)
			if node != nil && is_block {
				single_block_selection := region.to.path[block_level]==region.from.path[block_level]
				is_on_from_block := single_block_selection && len(region.from.path)-1==block_level
				if reversed && !(is_on_from_block && region.from.idx == 0) {
					region.to.idx = 0
				} else {
					region.to.idx = last_idx_of_node(node)
				}
			}
		}
		if region.invalidate_xpos {
			region.xpos = -1 // invalidate
		}
	}
	scroll_to_ensure_cursor(editor)

	commit_transaction(editor)
}

region_is_block_selection :: proc(editor: ^CodeEditor, region: ^Region) -> bool {
	block_level := region_block_level(region^)
	lc, rc := ordered_cursors(editor, region)

	is_block := false

	siblings := get_siblings_of_codenode(editor, rc.path[:block_level+1])
	start := lc.path[block_level]
	endinc := rc.path[block_level]
	for node, i in siblings[start:endinc+1] {
		if is_delimited_node(node) {
			is_block = true
			break
		}
	}
	return is_block
}

is_delimited_node :: proc(node: CodeNode) -> bool {
	return node.tag==.coll || node.tag==.string
}

remove_selected_contents :: proc(editor: ^CodeEditor, region: ^Region) {
	lc, rc := ordered_cursors(editor, region)
	if region_is_block_selection(editor, region) {
		block_level := region_block_level(region^)

		start_path := lc.path[:block_level+1]
		start_idx := start_path[block_level]
		end_idx := rc.path[block_level]+1

		remove_sibling_codenodes(editor, start_path, end_idx-start_idx)
	} else {
		// TODO
	}
}

// returns the path index concerning block selection
// (first index where node index may diverge)
region_block_level :: proc(region: Region) -> int {
	from := region.from
	to := region.to
	n := math.min(len(from.path), len(to.path))
	level := n-1
	for i in 0..<n {
		a := from.path[i]
		b := to.path[i]
		if a != b {
			level = i
		}
	}
	return level
}

codeeditor_event_keydown :: proc(window: ^Window, using editor: ^CodeEditor, using evt: Event_Key) -> bool {
	handled := true

	mods := get_kbd_modifiers()

	if mods=={} {
		#partial switch key {
		case .right_arrow:
			commit_region_simple_move(editor, true, .right)
		case .left_arrow:
			commit_region_simple_move(editor, true, .left)
		case .up_arrow:
			commit_region_simple_move(editor, true, .up)
		case .down_arrow:
			commit_region_simple_move(editor, true, .down)
		case .home:
			commit_region_simple_move(editor, true, .home)
		case .backspace:
			for region in &regions {
				if region_is_point(region) {
					cursor_delete_left(editor, &region.to)
					delete_cursor(region.from)
					deep_copy(&region.from, &region.to)
				} else {
					remove_selected_contents(editor, &region)
				}
				region.xpos = -1
			}
			scroll_to_ensure_cursor(editor)
			commit_transaction(editor)
		case .enter:
			for region in &regions {
				if region_is_point(region) {
					cursor := &region.to
					codeeditor_insert_text(editor, cursor, "\n")

					delete_cursor(region.from)
					deep_copy(&region.from, &region.to)
				}
				region.xpos = -1
			}
			scroll_to_ensure_cursor(editor)
			commit_transaction(editor)
		case:
			handled = false
		}
	} else if mods=={.shift} {
		#partial switch key {
		case .right_arrow:
			commit_region_simple_move(editor, false, .right)
		case .left_arrow:
			commit_region_simple_move(editor, false, .left)
		case .up_arrow:
			commit_region_simple_move(editor, false, .up)
		case .down_arrow:
			commit_region_simple_move(editor, false, .down)
		case .home:
			commit_region_simple_move(editor, false, .home)
		case:
			handled = false
		}
	} else if mods=={.control} {
		#partial switch key {
		case .s: // save
			sb := strings.builder_make()
			w := strings.to_writer(&sb)
			codenode_serialise_write_nodes(w, editor.roots)
			data := transmute([]u8) strings.to_string(sb)
			ok := os.write_entire_file(editor.file_path, data)
			if !ok {
				fmt.println("failed to write file")
			}
		case .v: // paste
			text, ok := clipboard_get_text()
			for region in &regions {
				if !region_is_point(region) {
					remove_selected_contents(editor, &region)
				}
				codeeditor_insert_text(editor, &region.to, text)
				delete_cursor(region.from)
				deep_copy(&region.from, &region.to)
			}
			scroll_to_ensure_cursor(editor)
			commit_transaction(editor)
		case .z: // undo
			try_undo: {
				tx : CodeEditor_Tx
				prev_tx : CodeEditor_Tx
				for i := len(editor.transactions)-1;; i-=1 {
					if i == 0 { // keep an initial transaction
						fmt.println("end of history")
						break try_undo
					}
					tx = editor.transactions[i]
					pop(&editor.transactions)
					if len(tx.edit_tx.deltas) != 0 {
						prev_tx = editor.transactions[i-1]
						break
					}
				}
				for i := len(tx.edit_tx.deltas)-1; i>=0; i-=1 {
					del := tx.edit_tx.deltas[i]
					switch del.tag {
					case .insert_nodes:
						sibling_start_idx := del.insert_nodes.index
						flat_idx := del.insert_nodes.flat_node_idx
						parent_path := flat_idx_to_path(editor, flat_idx)
						siblings := get_children_at_path(editor, parent_path)
						if del.reversed { // insert nodes
							nodes := create_codenodes_from_flat_form(del.insert_nodes.flat_node_array)
							fmt.println("insert", len(nodes), "at", sibling_start_idx)
							inject_at(siblings, auto_cast sibling_start_idx, ..nodes)
						} else { // remove nodes
							n := del.insert_nodes.flat_node_array.tree_shape[0]
							fmt.println("remove", n, "at", sibling_start_idx)
							for i in 0..<n {
								remove_node_from_siblings(editor, siblings, auto_cast sibling_start_idx)
							}
						}
					}
				}
				// regions
				for region in regions {
					for cursor in region.cursors {
						delete_cursor(cursor)
					}
				}
				clear(&regions)
				snapshots := prev_tx.regions_tx.snapshots
				resize(&regions, len(snapshots))
				for snap, i in snapshots {
					regions[i].xpos = snap.xpos
					regions[i].from.position = snap.from.position
					regions[i].from.path = flat_idx_to_path(editor, snap.from.flat_idx)
					regions[i].to.position = snap.to.position
					regions[i].to.path = flat_idx_to_path(editor, snap.to.flat_idx)
				}
			}
		case:
			handled = false
		}
	} else {
		handled = false
	}

	return handled
}

codenode_string_insert_text :: proc(node: ^CodeNode, cursor: ^Cursor, text: string) {
	snode := &node.string
	text_idx := cursor.idx-1
	if text_idx < 0 || text_idx > rp.get_count(snode.text) {return}

	rp.insert_text(&snode.text, text_idx, text)

	cursor.idx += len(text)
}

max_token_length :: 1024

codeeditor_insert_nodes_from_text :: proc(
	editor: ^CodeEditor, input: string, parent_path: []int, nodes0: ^[dynamic]CodeNode, insert_idx: int,
	) -> int {
	flat_nodes, ok := codenodes_from_string(input)
	if !ok {
		fmt.println("parse error")
		return 0
	}
	nodes := create_codenodes_from_flat_form(flat_nodes)
	defer delete(nodes)

	inject_at_elems(nodes0, insert_idx, ..nodes)

	del : EditTxDelta
	del.tag = .insert_nodes
	del.insert_nodes.index = auto_cast insert_idx
	del.insert_nodes.flat_node_idx = auto_cast cursor_path_to_flat_idx(editor, parent_path)
	del.insert_nodes.flat_node_array = flat_nodes
	append(&editor.pending_edit_tx_deltas, del)

	return len(nodes)
}

codeeditor_valid_token_charP :: proc(ch: rune) -> bool {
	return !(ch==' ' || ch<0x20 ||
		ch=='('||ch=='['||ch=='{'||ch==')'||ch==']'||ch=='}'||ch=='"')
}

codeeditor_insert_text :: proc(using editor: ^CodeEditor, cursor: ^Cursor, input_str: string) {
	path := cursor.path
	is_root := len(path)==0

	node := get_node_at_path(editor, path)

	is_inserting_in_gap := cursor.idx<0
	is_inserting_first_child := is_root || (node.tag==.coll && cursor.coll_place==.open_post)

	is_valid_token_string :: proc(input_str: string) -> bool {
		token_input_end := 0
		for ch in input_str {
			if codeeditor_valid_token_charP(ch) {
				token_input_end += 1
			} else {
				break
			}
		}
		return len(input_str) == token_input_end
	}

	if is_inserting_first_child { // Create new first child
		children := &roots
		if !is_root {
			children = &node.coll.children
		}

		n_nodes_added := codeeditor_insert_nodes_from_text(
			editor, input_str, path, children, 0)
		if n_nodes_added > 0 {
			target_node_idx := n_nodes_added-1

			cursor_path_append(cursor, target_node_idx)
			cursor.idx = last_idx_of_node(&children[target_node_idx])
		}
	} else
	if node != nil {
		node_sibling_idx := path[len(path)-1]
		siblings := get_siblings_of_codenode(editor, path)

		// We are inserting before/after
		// Create a new token node from text input
		if is_inserting_in_gap || node.tag==.newline {
			offset : int
			if cursor.place==.after {
				offset = 1
			} else {
				offset = 0
			}
			n_nodes_added := codeeditor_insert_nodes_from_text(
				editor, input_str, path[:len(path)-1], siblings, node_sibling_idx+offset)
			target_node_idx := node_sibling_idx + n_nodes_added + offset - 1
			cursor.path[len(cursor.path)-1] = target_node_idx
			cursor.idx = last_idx_of_node(&siblings[target_node_idx])
		} else
		// add token node before/after string/coll
		if ((node.tag==.string || node.tag==.coll) &&
			(cursor.idx==0 || cursor.idx==last_idx_of_node(node))) {
			if cursor.idx==0 { // assumed that if cursor is here then coll does not have a prefix
				flat_nodes, ok := codenodes_from_string(input_str)
				if !ok {return}
				extra_nodes := create_codenodes_from_flat_form(flat_nodes)
				defer delete(extra_nodes)

				new_node_idx := cursor.path[len(cursor.path)-1]
				node = nil
				inject_at(siblings, new_node_idx, ..extra_nodes)

				del : EditTxDelta
				del.tag = .insert_nodes
				del.insert_nodes.index = auto_cast new_node_idx
				del.insert_nodes.flat_node_idx = auto_cast cursor_path_to_flat_idx(editor, path[:len(path)-1])
				del.insert_nodes.flat_node_array = flat_nodes
				append(&editor.pending_edit_tx_deltas, del)

				if len(extra_nodes)==1 && siblings[new_node_idx].tag==.token { // token prefix
					codenode_set_prefix(&siblings[new_node_idx+1], true)
					new_node := &siblings[new_node_idx]
					new_node.token.prefix = true
					cursor.idx = last_idx_of_node(new_node)

				} else {
					cursor.path[len(cursor.path)-1] += len(extra_nodes)
				}
			} else {
				cursor.place = .after
				codeeditor_insert_text(editor, cursor, input_str)
			}
		} else
		// Insert text to string
		if node.tag==.string {
			codenode_string_insert_text(node, cursor, input_str)
		} else
		// Insert text to text node
		if node.tag==.token {
			token := &node.token
			if cursor.idx < 0 {return}

			if is_valid_token_string(input_str) { // normal text insertion in token
				parent_path := path[:len(path)-1]

				// delta: remove node
				del : EditTxDelta
				del.tag = .insert_nodes
				del.reversed = true
				del.insert_nodes.index = auto_cast node_sibling_idx
				del.insert_nodes.flat_node_idx = auto_cast cursor_path_to_flat_idx(editor, parent_path)
				del.insert_nodes.flat_node_array = codenodes_to_flat_array(siblings[node_sibling_idx:node_sibling_idx+1])
				append(&editor.pending_edit_tx_deltas, del)

				rp.slice_inject_at((cast(^[]u8) &token.text), cursor.idx, transmute([]u8) input_str)
				cursor.idx += len(input_str)

				// delta: replace node
				del.tag = .insert_nodes
				del.reversed = false
				del.insert_nodes.index = auto_cast node_sibling_idx
				del.insert_nodes.flat_node_idx = auto_cast cursor_path_to_flat_idx(editor, parent_path)
				del.insert_nodes.flat_node_array = codenodes_to_flat_array(siblings[node_sibling_idx:node_sibling_idx+1])
				append(&editor.pending_edit_tx_deltas, del)

			} else { // reparse entire token
				text_idx := cursor.idx
				token_length := len(token.text)
				token_str := string(token.text)
				ss := []string{token_str[:text_idx], input_str, ""}
				if text_idx<token_length {
					ss[2] = token_str[text_idx:]
				}
				expanded_str := strings.concatenate(ss, context.temp_allocator)
				parent_path := path[:len(path)-1]
				n_nodes_added := codeeditor_insert_nodes_from_text(
					editor, expanded_str, parent_path, siblings, node_sibling_idx+1)
				if n_nodes_added==0 {
					// parse failure
				} else {

					del : EditTxDelta
					del.tag = .insert_nodes
					del.reversed = true
					del.insert_nodes.index = auto_cast node_sibling_idx
					del.insert_nodes.flat_node_idx = auto_cast cursor_path_to_flat_idx(editor, parent_path)
					del.insert_nodes.flat_node_array = codenodes_to_flat_array(siblings[node_sibling_idx:node_sibling_idx+1])
					append(&editor.pending_edit_tx_deltas, del)

					remove_node_from_siblings(editor, siblings, node_sibling_idx)

					target_node_idx := node_sibling_idx + n_nodes_added - 1

					cursor.path[len(cursor.path)-1] = target_node_idx
					cursor.idx = last_idx_of_node(&siblings[target_node_idx])
					cursor.idx -= token_length-text_idx
				}
			}
		}
	}

	// Bump forwards if landed on newline
	// node2 := get_node_at_path(editor, cursor.path)
	// if node2.tag == .newline {
	// 	node_idx := cursor.path[len(cursor.path)-1]
	// 	siblings2 := get_siblings_of_codenode(editor, cursor.path)
	// 	if node_idx+1 < len(siblings2) {
	// 		right_node := siblings2[node_idx+1]
	// 		if right_node.tag != .newline {
	// 			cursor.path[len(cursor.path)-1] += 1
	// 			cursor.idx = 0
	// 		}
	// 	}
	// }
}

clone_cursor :: proc(cursor: Cursor) -> Cursor {
	c := cursor
	c.path = make([]int, len(c.path))
	copy(c.path, cursor.path)
	return c
}

delete_cursor :: proc(cursor: Cursor) {
	delete(cursor.path)
}

scroll_to_ensure_cursor :: proc(editor: ^CodeEditor, ) {
	editor.regions_changed = true
}

codeeditor_event_charinput :: proc(window: ^Window, editor: ^CodeEditor, ch: int) {
	using editor

	if ch < 0x20 {return}

	if ch > 255 { // long unicode character
		for region in &regions {
			if !region_is_point(region) {continue}
			cursor := &region.to

			input_str := utf8.runes_to_string({cast(rune) ch}, context.temp_allocator)
			codeeditor_insert_text(editor, cursor, input_str)
			region.from = region.to
			region.xpos = -1
		}
		scroll_to_ensure_cursor(editor)
		commit_transaction(editor)
		return
	}

	for region in &regions {
		if !region_is_point(region) {continue}
		cursor := &region.to
		path := cursor.path

		node := get_node_at_path(editor, path)

		is_inserting_in_gap := cursor.idx<0
		is_inserting_first_child := len(path)==0 || (node.tag==.coll && cursor.coll_place==.open_post)
		is_inserting_macro := len(path)==0 || cursor.idx==last_idx_of_node(node) || is_inserting_in_gap || is_inserting_first_child

		defer {
			delete_cursor(region.from)
			deep_copy(&region.from, &region.to)
		}

		if ch==';' {
			cursor_move_out_to_insert_newline(editor, cursor)
			return
		}
		
		// Insert collection
		try_insert_collection: {
			if is_inserting_macro {
	 			new_node : CodeNode
	 			if ch=='('||ch=='['||ch=='{' {
	 				new_node.tag = .coll
	 				if ch=='(' {
	 					new_node.coll.coll_type = .round
	 				} else if ch=='[' {
	 					new_node.coll.coll_type = .square
	 				} else if ch=='{' {
	 					new_node.coll.coll_type = .curly
	 				}
	 			} else
	 			// Insert string
	 			if ch=='"' {
	 				new_node.tag = .string
	 				new_node.string.text = rp.of_string("")
	 
	 			} else {
	 				break try_insert_collection
	 			}
	 
	 			if is_inserting_first_child {
	 				children := &roots
	 				if len(path)>0 {
	 					children = &node.coll.children
	 				}
	 
	 				inject_at(children, 0, new_node)
	 				cursor_path_append(cursor, 0)
	 			} else {
	 				node_sibling_idx := path[len(path)-1]
	 				siblings := get_siblings_of_codenode(editor, path)
	 				target_node_idx : int
	 				if cursor.place==.before || (node.tag==.newline && cursor.idx==0) {
	 					target_node_idx = node_sibling_idx
	 				} else {
	 					target_node_idx = node_sibling_idx+1
		 				if node.tag==.token {
		 					if node.token.prefix { // shouldn't insert between prefix and coll
		 						delete_codenode(new_node)
		 						return
		 					} else if cursor.place!=.after { // token becomes prefix
			 					node.token.prefix = true
			 					if new_node.tag==.coll {
			 						new_node.coll.prefix=true
			 					} else if new_node.tag==.string {
			 						new_node.string.prefix=true
			 					}
			 				}
			 			}
	 				}
	 				inject_at(siblings, target_node_idx, new_node)
	 				cursor.path[len(cursor.path)-1] = target_node_idx
	 			}
	 			cursor.idx = 1
		 		return
	 		}
	 	}
		// inserting first child
		{
			cheese: {
				if node != nil {
	
					// start inserting
					if ch==' ' {
						if node.tag==.token && node.token.prefix {
							node.token.prefix = false
							siblings := get_siblings_of_codenode(editor, path)
							node_idx := path[len(path)-1]
							codenode_set_prefix(&siblings[node_idx+1], false)
							break
						} else if cursor.idx==last_idx_of_node(node) {
							cursor.place = .after
							break cheese
						} else if cursor.idx == 0 {
							cursor.place = .before
							break cheese
						}
					}
				}

				// General text insertion
				input_str := utf8.runes_to_string({cast(rune) ch}, context.temp_allocator)
				codeeditor_insert_text(editor, cursor, input_str)
			}
		}
		region.xpos = -1
	}
	scroll_to_ensure_cursor(editor)
	commit_transaction(editor)
}

cursor_path_append :: proc(cursor: ^Cursor, idx: int) {
	path := cursor.path
	p := make(type_of(path), len(path)+1)
	copy(p, path)
	p[len(p)-1] = idx

	delete(path)
	cursor.path = p
}

get_node_at_path :: proc(code_editor: ^CodeEditor, path: []int) ->  ^CodeNode {
	if len(path)==0 {return nil}
	level := 0
	siblings := &code_editor.roots
	for {
		idx := path[level]
		node := &siblings[idx]
		level += 1
		if len(path)==level {return node}
		siblings = &node.coll.children
	}
}

get_siblings_of_codenode :: proc(editor: ^CodeEditor, path: []int) -> ^[dynamic]CodeNode {
	if len(path)==0 {panic("tried to get siblings of the root")}
	return get_children_at_path(editor, path[:len(path)-1])
}

get_children_at_path :: proc(editor: ^CodeEditor, path: []int) -> ^[dynamic]CodeNode {
	level := 0
	children := &editor.roots
	for {
		if len(path)==level {
			return children
		}
		idx := path[level]
		node := &children[idx]
		children = &node.coll.children
		level += 1
	}
}

cursor_path_to_flat_idx  :: proc(editor: ^CodeEditor, path: []int) -> int {
	if len(path)==0 {return 0}
	target_node := get_node_at_path(editor, path)
	zip := get_codezip_at_path(editor, {0})
	defer delete_codezip(zip)
	flat_idx := 1
	for {
		if zip.node == target_node {break}
		codezip_to_next_in(&zip)
		flat_idx += 1
	}
	return flat_idx
}

flat_idx_to_path :: proc(editor: ^CodeEditor, #any_int index: int) -> []int {
	if index==0 {return {}}
	zip := get_codezip_at_path(editor, {0})
	defer delete_codezip(zip)
	flat_idx := 1
	for {
		if flat_idx == index {break}
		codezip_to_next_in(&zip)
		flat_idx += 1
	}
	return codezip_path(zip)
}

commit_transaction :: proc(editor: ^CodeEditor) {
	// edits
	append_nothing(&editor.transactions)
	tx := &editor.transactions[len(editor.transactions)-1]
	tx.edit_tx.deltas = clone_slice(editor.pending_edit_tx_deltas[:])
	clear(&editor.pending_edit_tx_deltas)

	// regions
	rs := make([]RegionTxSnapshot, len(editor.regions))
	for region, i in editor.regions {
		rs[i].xpos = region.xpos
		rs[i].from.position = region.from.position
		rs[i].from.flat_idx = auto_cast cursor_path_to_flat_idx(editor, region.from.path)
		rs[i].to.position = region.to.position
		rs[i].to.flat_idx = auto_cast cursor_path_to_flat_idx(editor, region.to.path)
	}
	tx.regions_tx.snapshots = rs
}