package vis

/*
TODO
- Strings
- newlines
*/

import "core:fmt"
import "core:mem"
import "core:math"
import "core:strings"

import sk "../skia"
import rp "../rope"


Cursor :: struct {
	path: []int,
	using _idx: struct #raw_union {
		idx: int, // >= 0
		place: enum int {before=-1, after=-2},
		coll_place: enum int{open_pre=0, open_post=1, close_pre=2, close_post=3},
	},
}

Region :: struct #raw_union {
	using tofrom: struct {
		to: Cursor,
		from: Cursor,
	},
	cursors: [2]Cursor,
}

region_is_point :: proc(using region: Region) -> bool {
	if (len(to.path) != len(from.path)) {return false}
	for i in 0..<len(to.path) {
		if to.path[i] != from.path[i] {return false}
	}
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
	},
	pos: [2]f32,
	flags: bit_set[enum {insert_before, insert_after}],
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

CodeCollType :: enum {round, curly, square}

CodeNode_Coll :: struct {
	coll_type: CodeCollType,
	children: [dynamic]CodeNode,
}

CodeNode_Token :: struct {
	text: []u8,
}

CodeNode_String :: struct {
	text: rp.RopeNode,
	lines: []struct{width: f32, text: string},
}

CodeEditor :: struct {
	initP: bool,
	regions: [dynamic]Region,
	roots: [dynamic]CodeNode,
	font: sk.SkFont, // one frame lifetime
}

draw_codeeditor :: proc(window: ^Window, cnv: sk.SkCanvas) {
	using sk
	using code_editor := &window.app.code_editor

	if !initP {
		initP = true

		region : Region
		// region.to.path = make(type_of(region.to.path), 1)
		// region.to.path[0] = 0
		region.to.idx = 0
		region.from=region.to
		append(&code_editor.regions, region)
	}

	active_colour : u32 = 0xff007ACC
	unfocused_cursor_colour : u32 = 0xaFa0a0a0
	selection_colour : u32 = 0xFFB4D8FD
	constants_colour : u32 = 0xFF7A3E9D
	bracket_colour : u32 = 0x75000000
	string_colour : u32 = 0xFFF1FADF
	string_quote_colour : u32 : 0xFF_879e5a
	comment_colour : u32 = 0xFFFFFABC

	paint := make_paint()

	scale := window.graphics.scale
	origin := [2]f32{10, 10}


	font_size : f32 = 15*scale
	font_style := fontstyle_init(auto_cast mem.alloc(size_of_SkFontStyle),
		SkFontStyle_Weight.normal, SkFontStyle_Width.condensed, SkFontStyle_Slant.upright)
	typeface_name : cstring = "Shantell Sans"
	typeface := typeface_make_from_name(typeface_name, font_style^)

	// danger danger !!!
	code_editor.font = font_init(auto_cast mem.alloc(size=size_of_SkFont,
		allocator=context.temp_allocator), typeface, font_size)

	metrics : SkFontMetrics
	line_spacing := font_get_metrics(font, &metrics)
	line_height := line_spacing

	space_width := math.round(measure_text_width(font, " "))

	for region in regions {
		for cursor in region.cursors {
			node := get_node_at_path(code_editor, cursor.path)
			if node==nil {continue}
			if cursor.place == .before {
				node.flags += {.insert_before}
			} else if cursor.place == .after {
				node.flags += {.insert_after}
			}
		}
	}

	blob_round_open := make_textblob_from_text("(", font)
	blob_round_close := make_textblob_from_text(")", font)
	blob_square_open := make_textblob_from_text("[", font)
	blob_square_close := make_textblob_from_text("]", font)
	blob_curly_open := make_textblob_from_text("{", font)
	blob_curly_close := make_textblob_from_text("}", font)
	blob_double_quote := make_textblob_from_text("\"", font)

	{ // Draw nodes
		Frame_DrawNode :: struct{
			node_idx: int,
			coll: struct{
				blob_close: SkTextBlob,
				width_close: f32,
				text_y: f32,
			},
			siblings: ^[dynamic]CodeNode,
			left_start_x: f32,
		}
		stack : [dynamic]Frame_DrawNode
		siblings := &roots
		node_i := 0
		x := origin.x
		y := origin.y
		left_start_x := x
		for {
			if node_i >= len(siblings) {
				if len(stack)==0 {
					break
				} else { // Pop the stack
					frame := stack[len(stack)-1]
					pop(&stack)

					// Post processing for frame

					{ // Draw collection RHS
						using frame.coll
						paint_set_colour(paint, bracket_colour)
						canvas_draw_text_blob(cnv, blob_close, x, y-metrics.ascent, paint)
						x += width_close
					}

					node_i = frame.node_idx + 1
					siblings = frame.siblings
					left_start_x = frame.left_start_x
					continue
				}
			}

			node := &siblings[node_i]
			if node_i>0 && siblings[node_i-1].tag != .newline {
				x += space_width
			}
			if .insert_before in node.flags {
				x += space_width
			}

			node.pos.x = x
			node.pos.y = y

			switch node.tag {

			case .newline:
				x = left_start_x
				y += line_height
				node.pos.x = x
				node.pos.y = y

			case .token:
				text := string(node.token.text)

				blob := make_textblob_from_text(text, font)

				c0 := text[0]
				constantP := c0==':' || ('0' <= c0 && c0 <= '9') || text=="nil" || text=="false" || text=="true"
				if constantP {
					paint_set_colour(paint, constants_colour)
				} else {
					paint_set_colour(paint, 0xFF000000)
				}
				canvas_draw_text_blob(cnv, blob, x, y-metrics.ascent, paint)

				width := measure_text_width(font, text)
				x += width
			case .string:
				text := &node.string.text

				// @debug
				// fmt.printf("string: \"%v\"\n", rp.to_string(text))
				fmt.print("rope: ")
				rp.print_rope(text)
				fmt.println()

				text_lines : [dynamic]string
				{
					line_builder := strings.builder_make()
					it := rp.byte_iterator(text)
					for {
						ch, ok := rp.iter_next(&it)
						if ok {
							if ch=='\n' {
								append(&text_lines, strings.to_string(line_builder))
								line_builder = strings.builder_make()
							} else {
								strings.write_byte(&line_builder, ch)
							}
						} else {
							append(&text_lines, strings.to_string(line_builder))
							break
						}
					}
				}

				ns := &node.string
				delete(ns.lines)
				ns.lines = make(type_of(ns.lines), len(text_lines))

				width_delim := measure_text_width(font, "\"")

				// paint_set_colour(paint, string_colour)
				// canvas_draw_rect(cnv, sk_rect(x, y, x+width_delim, y+line_height), paint)

				paint_set_colour(paint, string_quote_colour)
				canvas_draw_text_blob(cnv, blob_double_quote, x, y-metrics.ascent, paint)
				x += width_delim

				bg_extra_width := width_delim*0.25
				x0 := x
				for line, i in text_lines {
					end_extra_width : f32 = 0
					nl_extra_width : f32 = 0
					if i != 0 {
						y += line_height
						nl_extra_width=bg_extra_width
					}
					if i < len(text_lines)-1 {end_extra_width=bg_extra_width}
					x = x0
					width := measure_text_width(font, line)
					paint_set_colour(paint, string_colour)
					canvas_draw_rect(cnv, sk_rect(x-nl_extra_width, y, x+width+end_extra_width, y+line_height), paint)
					paint_set_colour(paint, 0xFF000000)
					blob := make_textblob_from_text(line, font)
					canvas_draw_text_blob(cnv, blob, x, y-metrics.ascent, paint)
					x += width

					ns.lines[i].width = width
					ns.lines[i].text = line
				}

				// paint_set_colour(paint, string_colour)
				// canvas_draw_rect(cnv, sk_rect(x, y, x+width_delim, y+line_height), paint)

				paint_set_colour(paint, string_quote_colour)
				canvas_draw_text_blob(cnv, blob_double_quote, x, y-metrics.ascent, paint)
				x += width_delim

			case .coll:
				text_y := y-metrics.ascent
				blob_open : SkTextBlob
				blob_close : SkTextBlob
				width_open : f32
				width_close : f32
				switch node.coll.coll_type {
				case .round:
					blob_open = blob_round_open
					blob_close = blob_round_close
					width_open = measure_text_width(font, "(")
					width_close = measure_text_width(font, ")")
				case .square:
					blob_open = blob_square_open
					blob_close = blob_square_close
					width_open = measure_text_width(font, "[")
					width_close = measure_text_width(font, "]")
				case .curly:
					blob_open = blob_curly_open
					blob_close = blob_curly_close
					width_open = measure_text_width(font, "{")
					width_close = measure_text_width(font, "}")
				}

				// Draw collection LHS
				paint_set_colour(paint, bracket_colour)
				canvas_draw_text_blob(cnv, blob_open, x, text_y, paint)
				x += width_open

				frame : Frame_DrawNode
				frame.left_start_x = left_start_x
				frame.node_idx = node_i
				frame.siblings = siblings
				frame.coll.blob_close = blob_close
				frame.coll.text_y = text_y
				frame.coll.width_close = width_close
				append(&stack, frame)
				node_i = 0
				siblings = &node.coll.children
				left_start_x = x
				if node.coll.coll_type==.round {
					left_start_x += space_width
				}
				continue
			}

			// Conclude node
			if .insert_after in node.flags {x += space_width}

			node.flags = {}
			node_i += 1
		}
	}

	{ // Draw cursor
		cursor_width := 2*scale
		dl := cursor_width/2
		dr := cursor_width-dl

		paint_set_colour(paint, active_colour)

		for region in regions {
			for cursor in region.cursors {
				path := cursor.path
				node := get_node_at_path(code_editor, path)
				if node==nil {continue}

				x := node.pos.x
				y := node.pos.y

				switch node.tag {
				case .newline: break
				case .token:
					token := &node.token

					if cursor.idx >= 0{
						widthf := measure_text_width(font, token.text[:cursor.idx])
						x += widthf
					} else if cursor.place == .before {
						x -= space_width
					} else if cursor.place == .after {
						widthf := measure_text_width(font, token.text)
						x += widthf + space_width
					}
				case .string:
					text := &node.string.text
					width_delim := measure_text_width(font, "\"")

					if cursor.place == .before {
						x -= space_width
					} else if cursor.idx==0 {
						break
					} else {
						if cursor.idx != 0 {
							char_count := 0
							x0 := x
							for line, i in node.string.lines {
								x = x0
								text := line.text
								text_idx := cursor.idx-1-char_count
								if i != 0 {y += line_height}

								if 0 <= text_idx && text_idx <= len(text) { // cursor within line
									widthf := measure_text_width(font, text[:text_idx])
									x += width_delim + widthf
									break
								} else if i==len(node.string.lines)-1 { // last line
									if text_idx==len(text)+1 { // post- close delimiter
										widthf := measure_text_width(font, text[:])
										x += widthf + 2*width_delim
										break
									} else if cursor.place == .after {
										widthf := measure_text_width(font, text[:])
										x += widthf + 2*width_delim + space_width
										break
									}
								}
								char_count += len(text)+1
							}
						}
					}
				case .coll:
					width_open : f32
					width_close : f32
					switch node.coll.coll_type {
					case .round:
						width_open = measure_text_width(font, "(")
						width_close = measure_text_width(font, ")")
					case .square:
						width_open = measure_text_width(font, "[")
						width_close = measure_text_width(font, "]")
					case.curly:
						width_open = measure_text_width(font, "{")
						width_close = measure_text_width(font, "}")
					}
					// coll has idx 0-2
					if cursor.place==.before {
						x -= space_width
					} else if cursor.idx == 1 {
						x += width_open
					} else if cursor.idx == 2 {
						x += width_open + width_close
					} else if cursor.place == .after {
						x += width_open + width_close + space_width
					}
				}
				x = math.round(x)
				canvas_draw_rect(cnv, sk_rect(l=x-dl, r=x+dr, t=y, b=y+line_height), paint)
			}
		}
	}
}

cursor_move_right :: proc(editor: ^CodeEditor, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil {return}
	switch node.tag {

	case .newline: break

	case .token:
		token := node.token
		if cursor.place==.after || cursor.idx == len(token.text) {
			break
		} else {
			cursor.idx += 1
		}
		return

	case .string:
		text := node.string.text
		if cursor.place==.after || cursor.idx == rp.get_count(text)+2 {
			break
		} else {
			cursor.idx += 1
		}
		return

	case .coll:
		if cursor.coll_place==.close_post || cursor.place==.after {
			break
		} else if cursor.coll_place==.open_post {
			if len(node.coll.children)>0 {
				break
			} else {
				cursor.coll_place=.close_pre
			}
		} else {
			if cursor.coll_place==.open_pre && len(node.coll.children)>0 {
				break
			}
			cursor.idx += 1
		}
		return
	}
	// go to next node
	zip := get_codezip_at_path(editor, cursor.path)
	codezip_to_next_in(&zip)
	if zip.node == nil {return}
	delete(cursor.path)
	cursor.path = codezip_path(zip)
	cursor.idx = 0
}

cursor_move_left :: proc(editor: ^CodeEditor, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil{return}
	switch node.tag{

	case .newline: break

	case .token:
		token := node.token
		if cursor.place == .after {
			cursor.idx = len(token.text)
		} else if cursor.idx > 0 {
			cursor.idx -= 1
		} else {
			break
		}
		return

	case .string:
		text := node.string.text
		if cursor.place == .after {
			cursor.idx = rp.get_count(text)+2
		} else if cursor.idx > 0 {
			cursor.idx -= 1
		} else {
			break
		}
		return

	case .coll:
		if cursor.idx==0 || cursor.place==.before{
			break
		} else if cursor.place==.after {
			cursor.idx=2
		} else {
			cursor.idx -= 1
		}
		return
	}
	// go to prev node
	zip := get_codezip_at_path(editor, cursor.path)
	codezip_to_prev(&zip)
	if zip.node == nil {return}
	delete(cursor.path)
	cursor.path = codezip_path(zip)
	cursor.idx = last_idx_of_node(zip.node)
}

codenode_remove :: proc(editor: ^CodeEditor, node: ^CodeNode, cursor: ^Cursor) {
	path := cursor.path

	// move cursor away
	zip := get_codezip_at_path(editor, cursor.path)
	codezip_to_prev(&zip)
	if zip.node == nil {
		zip = get_codezip_at_path(editor, cursor.path)
		codezip_to_next(&zip)
	}
	if zip.node == nil {
		cursor.path = {}
		cursor.idx=0
	} else {
		cursor.path = codezip_path(zip)
		cursor.idx = last_idx_of_node(zip.node)	
	}

	siblings := get_siblings_of_codenode(editor, path)
	delete_codenode(node^) // must delete before removing
	ordered_remove(siblings, path[len(path)-1])
}

cursor_delete_left :: proc(editor: ^CodeEditor, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil {return}

	switch node.tag {

	case .newline:
		if cursor.idx==0 {
			codenode_remove(editor, node, cursor)
		}

	case .token:
		token := node.token
		if cursor.place == .after {
			cursor.idx = len(token.text) // move left
		} else if cursor.idx==1 && len(token.text)==1 { // delete the node

			path := cursor.path
			defer delete(path)

			codenode_remove(editor, node, cursor)
		} else if cursor.idx > 0 {
			// delete a char
			text := &node.token.text
			text2 := make([]u8, len(text)-1)
			copy(text2, text[:cursor.idx-1])
			if cursor.idx < len(text) {
				copy(text2[cursor.idx-1:], text[cursor.idx:])
			}
			delete(text^)
			text^ = text2
			cursor.idx -= 1
		} else {
			// TBD delete before
		}
		return

	case .string:
		text_idx := cursor.idx-1
		if cursor.place == .after {
			cursor.idx = rp.get_count(node.string.text)+2 // move left
		} else if text_idx>0 {
			// delete a char
			text := &node.string.text
			rp.remove_range(text, text_idx-1, text_idx)
			cursor.idx -= 1
		} else if cursor.idx==1 { // delete the node

			path := cursor.path
			defer delete(path)

			codenode_remove(editor, node, cursor)
		} else {
			// TBD delete before
		}
		return

	case .coll:
		if cursor.idx==0 || cursor.place==.before{
			// TBD delete before
		} else if cursor.place==.after {
			cursor.idx=2 // move left
		} else {
			// TBD
		}
		return
	}
}

cursor_move_up :: proc(editor: ^CodeEditor, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil{return}
	switch node.tag{

	case .newline: break

	case .token:
		return

	case .string:
		text := node.string.text
		if cursor.idx >= 0 {
			font := editor.font
			lines := node.string.lines
			char_count := 0
			for line, i in lines {
				line_text := line.text
				text_idx := cursor.idx-1-char_count
				if 0 <= text_idx && text_idx <= len(line_text) {
					pixel_offset := measure_text_width(font, line_text[:text_idx])
					if i>0 {
						target_line_text := transmute([]u8) lines[i-1].text
						target_line_idx := get_offset_at_coord(font, target_line_text, pixel_offset)
						cursor.idx -= 1+text_idx+(len(target_line_text)-target_line_idx)
					}
					break
				}
				char_count += len(line_text)+1
			}
		}
		return

	case .coll:
		return
	}
}

cursor_move_down :: proc(editor: ^CodeEditor, using cursor: ^Cursor) {
	node := get_node_at_path(editor, path)
	if node==nil{return}
	switch node.tag{

	case .newline: break

	case .token:
		return

	case .string:
		text := node.string.text
		if cursor.idx >= 0 {
			font := editor.font
			lines := node.string.lines
			char_count := 0
			for line, i in lines {
				line_text := line.text
				text_idx := cursor.idx-1-char_count
				if 0 <= text_idx && text_idx <= len(line_text) {
					pixel_offset := measure_text_width(font, line_text[:text_idx])
					if i<len(lines)-1 {
						target_line_text := transmute([]u8) lines[i+1].text
						target_line_idx := get_offset_at_coord(font, target_line_text, pixel_offset)
						cursor.idx += 1+target_line_idx+(len(line_text)-text_idx)
					}
					break
				}
				char_count += len(line_text)+1
			}
		}
		return

	case .coll:
		return
	}
}

last_idx_of_node :: proc(node: ^CodeNode) -> int {
	switch node.tag {
	case .token:
		return len(node.token.text)
	case .string:
		return rp.get_count(node.string.text)+2
	case .coll:
		return 2
	case .newline:
		return 0
	}
	panic("")
}

codeeditor_event_keydown :: proc(window: ^Window, using editor: ^CodeEditor, using evt: Event_Key) -> bool {
	handled := true

	mods := get_kbd_modifiers()

	if mods=={} {
		#partial switch key {
		case .right_arrow:
			for region in &regions {
				if region_is_point(region) {
					cursor_move_right(editor, &region.to)
					region.from=region.to
				}
			}
		case .left_arrow:
			for region in &regions {
				if region_is_point(region) {
					cursor_move_left(editor, &region.to)
					region.from=region.to
				}
			}
		case .up_arrow:
			for region in &regions {
				if region_is_point(region) {
					cursor_move_up(editor, &region.to)
					region.from=region.to
				}
			}
		case .down_arrow:
			for region in &regions {
				if region_is_point(region) {
					cursor_move_down(editor, &region.to)
					region.from=region.to
				}
			}
		case .backspace:
			for region in &regions {
				if region_is_point(region) {
					cursor_delete_left(editor, &region.to)
					region.from=region.to
				}
			}
		case .enter:
			for region in &regions {
				if region_is_point(region) {
					cursor := &region.to
					path := cursor.path
					node := get_node_at_path(editor, path)
					if node==nil {continue}

					cursor_on_left := cursor.place==.before || cursor.idx==0

					if cursor_on_left || cursor.place==.after || cursor.idx==last_idx_of_node(node) {
						nl_node : CodeNode
						nl_node.tag = .newline

						siblings := get_siblings_of_codenode(editor, cursor.path)
						target_node_idx := cursor.path[len(cursor.path)-1]
						if !cursor_on_left || node.tag==.newline {target_node_idx += 1}

						inject_at(siblings, target_node_idx, nl_node)
						cursor.path[len(cursor.path)-1] = target_node_idx
						cursor.idx = 0

					} else if node.tag ==.string {
						codenode_string_insert_text(node, cursor, "\n")
					} else if node.tag ==.token {

					} else if node.tag == .coll {
						nl_node : CodeNode
						nl_node.tag = .newline

						siblings := &node.coll.children
						target_node_idx := 0

						inject_at(siblings, target_node_idx, nl_node)
						cursor_path_append(cursor, target_node_idx)
						cursor.idx = 0
					}
					region.from=region.to
				}
			}
		}
	}

	return handled
}

codenode_string_insert_text :: proc(node: ^CodeNode, cursor: ^Cursor, text: string) {
	snode := &node.string
	text_idx := cursor.idx-1
	if text_idx < 0 || text_idx > rp.get_count(snode.text) {return}

	rp.insert_text(&snode.text, text_idx, text)

	cursor.idx += 1
}

max_token_length :: 1024

codeeditor_insert_nodes_from_text :: proc
(editor: ^CodeEditor, input: string, nodes0: ^[dynamic]CodeNode, insert_idx: int) -> int {
	nodes := make([dynamic]CodeNode, insert_idx)

	n_nodes_added := 0

	token_start_idx := 0
	whitespace := true
	for i := 0; ; i+=1 {
		c : u8
		if i < len(input) {c=input[i]}
		if c==' ' || i==len(input) {
			if !whitespace {
				segment := input[token_start_idx:i]
 				if len(segment) > max_token_length {
 					n_nodes_added = 0
 					break
 				}
				node : CodeNode
 				node.tag = .token
 				node.token.text = make(type_of(node.token.text), len(segment))
 				copy(node.token.text, segment)
 				append(&nodes, node)
 				n_nodes_added += 1
 			}
			if i==len(input) {
				break
			}
			token_start_idx = i+1
		} else if !codeeditor_valid_token_charP(cast(rune) c) {
			n_nodes_added = 0
			break
		}
		whitespace = false
	}

	if n_nodes_added==0 {
		fmt.println("parse error")
		for node in nodes {
			delete_codenode(node)
		}
		return 0
	}

	if insert_idx < len(nodes0) {
		append_elems(&nodes, ..nodes0[insert_idx:])
	}
	copy(nodes[:], nodes0[:insert_idx])

	delete(nodes0^)
	nodes0^ = nodes

	return n_nodes_added
}

import "core:unicode/utf8"

codeeditor_valid_token_charP :: proc(ch: rune) -> bool {
	return !(ch==' ' || ch<0x20)
}

codeeditor_insert_text :: proc(using editor: ^CodeEditor, cursor: ^Cursor, input_str: string) {
	path := cursor.path
	node := get_node_at_path(editor, path)
	if node==nil {return}

	node_sibling_idx := path[len(path)-1]
	parent_level := len(path)-2
	siblings := get_siblings_of_codenode(editor, path)

	// We are inserting before/after
	// Create a new token node from text input
	if cursor.place==.after || cursor.place==.before || node.tag==.newline {
		offset : int
		if cursor.place==.before {
			offset = 0
		} else {
			offset = 1
		}
		n_nodes_added := codeeditor_insert_nodes_from_text(
			editor, input_str, siblings, node_sibling_idx+offset)
		target_node_idx := node_sibling_idx + n_nodes_added + offset - 1
		cursor.path[len(cursor.path)-1] = target_node_idx
		cursor.idx = last_idx_of_node(&siblings[target_node_idx])

	// Insert text to current node
	} else {
		if node.tag==.string {
			codenode_string_insert_text(node, cursor, input_str)
			
		// Insert text to text node
		} else if node.tag==.token {
			token := &node.token
			if cursor.idx < 0 {return}

			token_input_end := 0
			for ch in input_str {
				if codeeditor_valid_token_charP(ch) {
					token_input_end += 1
				} else {
					break
				}
			}

			if len(input_str) == token_input_end { // normal text insertion in token
				rp.slice_inject_at((cast(^[]u8) &token.text), cursor.idx, transmute([]u8) input_str)
				cursor.idx += len(input_str)

			} else { // reparse entire token
				text_idx := cursor.idx
				token_length := len(token.text)
				token_str := string(token.text)
				ss := []string{token_str[:text_idx], input_str, ""}
				if text_idx<token_length {
					ss[2] = token_str[text_idx:]
				}
				expanded_str := strings.concatenate(ss)
				saved_cursor := clone_cursor(cursor^)
				codenode_remove(editor, node, cursor)
				n_nodes_added := codeeditor_insert_nodes_from_text(
					editor, expanded_str, siblings, node_sibling_idx)
				target_node_idx := node_sibling_idx + n_nodes_added - 1

				delete_cursor(cursor^)
				cursor^ = saved_cursor
				cursor.path[len(cursor.path)-1] = target_node_idx
				cursor.idx = last_idx_of_node(&siblings[target_node_idx])
				cursor.idx -= token_length-text_idx
			}

		// Insert text on coll
		} else if node.tag==.coll {
			coll := &node.coll

			if cursor.idx==1 { // Create new first child
				n_nodes_added := codeeditor_insert_nodes_from_text(
					editor, input_str, &coll.children, 0)
				target_node_idx := n_nodes_added-1
				if target_node_idx<0 {panic("nope")}

				cursor_path_append(cursor, target_node_idx)
				cursor.idx = last_idx_of_node(&coll.children[target_node_idx])
			}
		}
	}
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

codeeditor_event_charinput :: proc(window: ^Window, editor: ^CodeEditor, ch: int) {
	if ch > 255 {return}
	if ch < 0x20 {return}
	using editor

	for region in &regions {
		fmt.print("Cursor:", region.to.path, "")
		if region.to.idx>=0 {
			fmt.print("idx:", region.to.idx)
		} else {
			fmt.print("place:", region.to.place)
		}
		fmt.println()

		if !region_is_point(region) {continue}
		cursor := &region.to
		path := cursor.path

		if len(roots)==0 {
			if ch==' ' {return}
			ary := make([]u8,1)
			ary[0]=auto_cast ch
			append(&roots, CodeNode{tag=.token, node={token={text=ary}}})


			p := make(type_of(path), len(path)+1)
			copy(p, path)
			p[len(p)-1] = 0

			delete(cursor.path)
			cursor.path = p
			cursor.idx = 1
			region.from=region.to

		} else {
			node := get_node_at_path(editor, path)
			if node==nil {return}

			node_sibling_idx := path[len(path)-1]
			siblings := get_siblings_of_codenode(editor, path)

			// Insert collection
			if ch=='('||ch=='['||ch=='{' {
				if cursor.idx==last_idx_of_node(node) || cursor.idx<0 {
					coll : CodeNode
					coll.tag = .coll
					if ch=='(' {
						coll.coll.coll_type = .round
					} else if ch=='[' {
						coll.coll.coll_type = .square
					} else if ch=='{' {
						coll.coll.coll_type = .curly
					}
					target_node_idx : int
					if cursor.place==.before {
						target_node_idx = node_sibling_idx
					} else {
						target_node_idx = node_sibling_idx+1
					}
					inject_at(siblings, target_node_idx, coll)
					cursor.path[len(cursor.path)-1] = target_node_idx
					cursor.idx = 1
				}

			// Insert string
			} else if ch=='"' &&
			(cursor.idx==last_idx_of_node(node) || cursor.idx<0) {
				str_node : CodeNode
				str_node.tag = .string
				str_node.string.text = rp.of_string("")

				// @copypaste from insert coll
				target_node_idx : int
				if cursor.place==.before {
					target_node_idx = node_sibling_idx
				} else {
					target_node_idx = node_sibling_idx+1
				}
				inject_at(siblings, target_node_idx, str_node)
				cursor.path[len(cursor.path)-1] = target_node_idx
				cursor.idx = 1

			// start inserting
			} else if ch==' ' && cursor.idx==last_idx_of_node(node) {
				cursor.place = .after
			} else if ch==' ' && cursor.idx == 0 {
				cursor.place = .before
			
			// General text insertion
			} else {
				input_str := utf8.runes_to_string({cast(rune) ch}, context.temp_allocator)
				codeeditor_insert_text(editor, cursor, input_str)
			}

			region.from=region.to
		}
	}
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
	if len(path)==0 {panic("nope")}
	level := 0
	siblings := &editor.roots
	for {
		idx := path[level]
		node := &siblings[idx]
		level += 1
		if len(path)==level {
			return siblings
		}
		siblings = &node.coll.children
	}
}

CodeNode_Zipper :: struct {
	node: ^CodeNode,
	stack: [dynamic]struct {
		idx: int,
		nodes: []CodeNode,
	},
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
				child := &children[0]
				node = child
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

codezip_to_parent :: proc(using zip: ^CodeNode_Zipper) {
	level := len(stack)-1
	if level==0 {
		node=nil
	} else {
		pop(&stack)
		sf := &stack[level]
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