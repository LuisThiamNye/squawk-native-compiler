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
import "core:time"
import "core:os"
import "core:slice"

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
	is_block: bool,
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

CodeNode_Coll :: struct {
	coll_type: CodeCollType,
	prefix: bool,
	children: [dynamic]CodeNode,
	close_pos: [2]f32,
	// TODO support a prefix token
}

CodeNode_Token :: struct {
	text: []u8,
	prefix: bool,
}

CodeNode_String :: struct {
	text: rp.RopeNode,
	lines: []struct{width: f32, text: string},
	prefix: bool,
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
}

codeeditor_refresh_from_file :: proc(editor: ^CodeEditor) {
	text, ok := os.read_entire_file_from_filename(editor.file_path)
	if !ok {return}
	nodes, n_ok := codenodes_from_string(string(text))
	if !n_ok {
		fmt.println("error parsing nodes from file")
	}

	editor.roots = slice.to_dynamic(nodes)
}

draw_codeeditor :: proc(window: ^Window, cnv: sk.SkCanvas) {
	using sk
	using code_editor := &window.app.code_editor

	if !initP {
		initP = true

		file_path = "/me/prg/fera-db2/cool.sq"

		region : Region
		// region.to.path = make(type_of(region.to.path), 1)
		// region.to.path[0] = 0
		region.to.idx = 0
		deep_copy(&region.from, &region.to)
		region.xpos = -1
		append(&code_editor.regions, region)

		codeeditor_refresh_from_file(code_editor)
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

	view_rect.left = 0
	view_rect.top = 0
	view_rect.right = window.graphics.width
	view_rect.bottom = window.graphics.height

	{ // scroll
		using smooth_scroll

		pos : [2]i32
		current_time := time.to_unix_nanoseconds(time.now())/1e6
		if current_time > latest_time+auto_cast duration { // animation done
			pos = scroll_offset
		} else {
			p1s := control_point1s
			p2 := scroll_control_point2
			k := f32(current_time-latest_time)/auto_cast duration

			tx := get_bezier_t_for_x(k, p1s.x.x, p2.x)
			ty := get_bezier_t_for_x(k, p1s.y.x, p2.x)
			bx := calc_bezier(tx, control_point1s.x.y, p2.y)
			by := calc_bezier(ty, control_point1s.y.y, p2.y)

			pos.x = start_pos.x + i32(math.round(bx*f32(scroll_offset.x-start_pos.x)))
			pos.y = start_pos.y + i32(math.round(by*f32(scroll_offset.y-start_pos.y)))

			request_frame(window)

		}

		dx := view_rect.left+pos.x-contents_rect.left
		contents_rect.left += dx
		contents_rect.right += dx
		dy := view_rect.top+pos.y-contents_rect.top
		contents_rect.top += dy
		contents_rect.bottom += dy
	}

	update_contents_rect_to_scroll :: proc(using editor: ^CodeEditor) {
		// If the contents rect is found somewhere it shouldn't be,
		// then snap it back to a valid position and stop scrolling
		d := contents_rect.coords-view_rect.coords
		dl := d[0]; dt := d[1]; dr := d[2]; db := d[3]
		if dr-dl<0 { // if contents fit, do not scroll
			contents_rect.right -= dl
			contents_rect.left -= dl
			scroll_offset.x = 0
			smooth_scroll.start_pos.x=0
		} else if dr<0 { // ensure contents fill the view
			contents_rect.right -= dr
			contents_rect.left -= dr
			scroll_offset.x = contents_rect.left
			smooth_scroll.start_pos.x = scroll_offset.x
		} else if dl>0 {
			contents_rect.right -= dl
			contents_rect.left -= dl
			scroll_offset.x = 0
			smooth_scroll.start_pos.x=0
		}
		if db-dt<0 { // if contents fit, do not scroll
			contents_rect.bottom -= dt
			contents_rect.top -= dt
			scroll_offset.y = 0
			smooth_scroll.start_pos.y=0
		} else if db<0 { // ensure contents fill the view
			contents_rect.bottom -= db
			contents_rect.top -= db
			scroll_offset.y = contents_rect.top
			smooth_scroll.start_pos.y = scroll_offset.y
		} else if dt>0 {
			contents_rect.bottom -= dt
			contents_rect.top -= dt
			scroll_offset.y = 0
			smooth_scroll.start_pos.y=0
		}
	}

	update_contents_rect_to_scroll(code_editor)

	padding : Rect_i32
	padding.coords = {10, 10, 10, 10}
	origin : [2]f32
	origin.x = cast(f32) (padding.left + contents_rect.left)
	origin.y = cast(f32) (padding.top + contents_rect.top)



	font_size : f32 = 15*scale
	font_style := fontstyle_init(auto_cast mem.alloc(size_of_SkFontStyle),
		SkFontStyle_Weight.normal, SkFontStyle_Width.condensed, SkFontStyle_Slant.upright)
	// typeface_name : cstring = "Shantell Sans"
	typeface_name : cstring = "Input Sans"
	typeface := typeface_make_from_name(typeface_name, font_style^)

	// danger danger !!!
	code_editor.font = font_init(auto_cast mem.alloc(size=size_of_SkFont,
		allocator=context.temp_allocator), typeface, font_size)

	metrics : SkFontMetrics
	line_spacing := font_get_metrics(font, &metrics)
	line_height := line_spacing

	space_width := math.round(measure_text_width(font, " "))



	for region in &regions {
		// dbg_println_cursor(region.to)
		for cursor in &region.cursors {
			if len(cursor.path)==0 && len(code_editor.roots)>0 && code_editor.roots[0].tag!=.newline {
				cursor_path_append(&cursor, 0)
				cursor.idx = 0
			}

			node := get_node_at_path(code_editor, cursor.path)
			if node==nil {continue}
			if cursor.place == .before {
				node.flags += {.insert_before}
			} else if cursor.place == .after {
				node.flags += {.insert_after}
			} else if node.tag==.coll && cursor.coll_place == .open_post {
				node.flags += {.insert_first_child}
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

	// Draw selection background
	{
		//
	}

	{ // Draw nodes
		max_x : f32 = 0

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
			if x>max_x {max_x=x}
			
			if node_i>0 {
				left_node := &siblings[node_i-1]
				if .insert_after in left_node.flags {x += space_width}
				left_node.flags = {}
			}
			if node_i >= len(siblings) {
				if len(stack)==0 {
					break
				} else { // Pop the stack
					frame := stack[len(stack)-1]
					pop(&stack)

					// Post processing for frame

					node_i = frame.node_idx + 1
					siblings = frame.siblings
					left_start_x = frame.left_start_x

					node := &siblings[frame.node_idx]
					node.coll.close_pos.x = x
					node.coll.close_pos.y = y

					{ // Draw collection RHS
						using frame.coll
						paint_set_colour(paint, bracket_colour)
						canvas_draw_text_blob(cnv, blob_close, x, y-metrics.ascent, paint)
						x += width_close
					}

					continue
				}
			}

			node := &siblings[node_i]
			if node_i>0 {
				left_node := &siblings[node_i-1]
				has_prefix := codenode_has_prefix(node)
				if left_node.tag != .newline && !has_prefix {
					x += space_width
				}
				left_is_prefix := left_node.tag==.token && left_node.token.prefix
				if left_is_prefix && !has_prefix {
					panic("left node is prefix, but this node does not have a prefix")
				} else if has_prefix && !left_is_prefix {
					panic("this node has a prefix, but left node is not a prefix")
				}
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
				} else if node.token.prefix {
					paint_set_colour(paint, bracket_colour)
				} else {
					paint_set_colour(paint, 0xFF000000)
				}
				canvas_draw_text_blob(cnv, blob, x, y-metrics.ascent, paint)

				width := measure_text_width(font, text)
				x += width
			case .string:
				text := &node.string.text

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

				if .insert_first_child in node.flags && len(node.coll.children)>0 {
					x += space_width
				}

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
			}

			if node.tag != .coll {
				node_i += 1
			}
		}
		contents_rect.right = (auto_cast max_x + padding.right)
		contents_rect.bottom = (
			auto_cast y + auto_cast line_height + padding.bottom)
	}


	{ // Draw cursor
		cursor_width := 2*scale
		dl := cursor_width/2
		dr := cursor_width-dl

		paint_set_colour(paint, active_colour)

		for region in &regions {
			// xpos : f32
			for cursor, cursor_i in region.cursors {
				is_to_cursor := cursor_i == 0
				path := cursor.path
				node := get_node_at_path(code_editor, path)
				x, y: f32
				if node == nil {
					x = origin.x
					y = origin.y
				} else {
					x = node.pos.x
					y = node.pos.y
	
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
						
						if cursor.place==.before {
							x -= space_width
						} else if cursor.coll_place == .open_post {
							x += width_open
						} else if cursor.coll_place == .close_pre {
							pos := node.coll.close_pos
							x = pos.x
							y = pos.y
						} else if cursor.coll_place == .close_post {
							pos := node.coll.close_pos
							x = pos.x + width_close
							y = pos.y
						} else if cursor.place == .after {
							pos := node.coll.close_pos
							x = pos.x + width_close + space_width
							y = pos.y
						}
					}
				}
				x = math.round(x)
				canvas_draw_rect(cnv, sk_rect(l=x-dl, r=x+dr, t=y, b=y+line_height), paint)

				if regions_changed && is_to_cursor {
					regions_changed = false
					new_offset := scroll_offset
					yi := cast(i32) y
					v_margin := cast(i32) (line_height*0.2)
					if yi-v_margin < view_rect.top {
						new_offset.y = contents_rect.top - yi+v_margin
					} else if yi + cast(i32) line_height + v_margin > view_rect.bottom {
						new_offset.y = contents_rect.top - yi - cast(i32) line_height - v_margin + view_rect.bottom-view_rect.top
					}
					xi := cast(i32) x
					dli := cast(i32) dl
					dri := cast(i32) dr
					h_margin := cast(i32) space_width
					if xi-dli-h_margin<view_rect.left {
						new_offset.x = contents_rect.left - xi+dli+h_margin
					} else if xi+dri+h_margin > view_rect.right {
						new_offset.x = contents_rect.left - xi-dri-h_margin + view_rect.right-view_rect.left
					}
					if new_offset != scroll_offset {
						request_new_scroll(code_editor, new_offset)
						request_frame(window)

						// because of margins, we may end up requesting scrolls
						// every frame if the cursor is on the first or last lines
						// because it can't scroll any more
						// HOWEVER: this is not the case because scrolls will only happen
						// when regions_changed=true, i.e. only once when the
						// user provided input that may have moved the cursor
					}
				}
			}
		}
	}

	old_contents := contents_rect
	update_contents_rect_to_scroll(code_editor)
	if old_contents != contents_rect {
		request_frame(window)
	}
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
	prefix := false

	switch node.tag {

	case .newline: break

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
	for {
		node_idx := path[len(path)-1]
		siblings := get_siblings_of_codenode(editor, path)
		if node_idx<len(siblings)-1 {
			target_node := &siblings[node_idx+1]
			cursor.path[len(path)-1] = node_idx+1
			if target_node.tag==.newline && node_idx<len(siblings)-2 &&
			siblings[node_idx+2].tag!=.newline {
				path = cursor.path
				continue
			}
			cursor.idx = 0
			if prefix {
				cursor_move_right(editor, cursor)
			}
		} else if len(path)>0 {
			zip := get_codezip_at_path(editor, path)
			defer delete_codezip(zip)
			codezip_to_parent(&zip)
			if zip.node != nil {
				delete(cursor.path)
				cursor.path = codezip_path(zip)
				cursor.coll_place = .close_post
			}
		}
		break
	}
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
				cursor.idx = last_idx_of_node(&children[child_idx])
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
	on_newline := node.tag==.newline
	for {
		node_idx := path[len(path)-1]
		if node_idx>0 {
			siblings := get_siblings_of_codenode(editor, path)
			target_node := &siblings[node_idx-1]
			cursor.path[len(path)-1] = node_idx-1
			if target_node.tag==.newline && !on_newline {
				on_newline=true
				path = cursor.path
				continue
			}
			cursor.idx = last_idx_of_node(target_node)
		} else if len(path)>0 {
			zip := get_codezip_at_path(editor, path)
			defer delete_codezip(zip)
			codezip_to_parent(&zip)
			delete(cursor.path)
			if zip.node != nil {
				cursor.path = codezip_path(zip)
				cursor.coll_place = .open_pre
				if zip.node.coll.prefix {
					cursor_move_left(editor, cursor)
				}
			} else {
				cursor.path = {}
				cursor.idx=0
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

codenode_remove :: proc(editor: ^CodeEditor, node: ^CodeNode, cursor: ^Cursor) {
	path := cursor.path
	node_idx := path[len(path)-1]

	// move cursor away
	sibling_idx := path[len(path)-1]
	if sibling_idx > 0 { // curor moves left
		cursor.path[len(path)-1] -= 1
		next_node := get_node_at_path(editor, path)
		cursor.idx = last_idx_of_node(next_node)
	} else {
		siblings := get_siblings_of_codenode(editor, path)
		// if len(siblings) > 1 { // cursor moves to right node
		// 	next_node := &siblings[1]
		// 	cursor.idx = last_idx_of_node(next_node)
		// } else
		{ // cursor moves to parent; inserting first child
			cursor_to_parent(cursor)
		}
	}

	codenode_remove2(editor, node, path)
}

codenode_remove2 :: proc(editor: ^CodeEditor, node: ^CodeNode, path: []int) {
	node_idx := path[len(path)-1]

	siblings := get_siblings_of_codenode(editor, path)
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

	switch node.tag {

	case .newline:
		if cursor.idx==0 {
			codenode_remove(editor, node, cursor)
		}

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

		} else if cursor.idx==0 { // delete before
			node_idx := path[len(path)-1]
			if node_idx == 0 {
				cursor_to_parent(cursor)
				cursor_delete_left(editor, cursor)
			} else {
				cursor_move_left(editor, cursor)
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
		} else {
			// TBD delete before
		}
		return

	case .coll:
		if cursor.coll_place==.open_pre || cursor.place==.before{
			cursor_move_left(editor, cursor)
		} else if cursor.place==.after {
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
		return 3
	case .newline:
		return 0
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

region_simple_move :: proc(using editor: ^CodeEditor, reset_selection: bool, direction: enum {right, left, down, up, home}) {
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
		switch direction {
		case .right:
			if collapsing_selection {
				region.to = rc
				region.from = lc
			} else {
				if is_block && !single_block_selection {
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
				if is_block && !single_block_selection {
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
				if reversed && !(single_block_selection && region.from.idx == 0) {
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
}

region_is_block_selection :: proc(editor: ^CodeEditor, region: ^Region) -> bool {
	block_level := region_block_level(region^)
	lc, rc := ordered_cursors(editor, region)

	is_block := false

	siblings := get_siblings_of_codenode(editor, region.to.path[:block_level+1])
	if siblings==nil {
		fmt.println("nil: unsupported")
		is_block = false
	} else if block_level<len(lc.path) && block_level<len(rc.path) {
		start := lc.path[block_level]
		endinc := rc.path[block_level]
		for node, i in siblings[start:endinc+1] {
			if is_delimited_node(node) {
				is_block = true
				break
			}
		}
	}
	return is_block
}

is_delimited_node :: proc(node: CodeNode) -> bool {
	return node.tag==.coll || node.tag==.string
}

remove_selected_contents :: proc(editor: ^CodeEditor, region: ^Region) {
	lc, rc := ordered_cursors(editor, region)
	if region.is_block {
		start_path : type_of(region.to.path)
		count : int
		for i := 0;; i+=1 {
			if i < len(lc.path) && i < len(rc.path) {
				lc_idx := lc.path[i]
				rc_idx := rc.path[i]
				if lc_idx == rc_idx {
					continue
				} else {
					start_path = rc.path[:i+1]
					count = rc_idx - lc_idx
					break
				}
			} else { // delete the node at the prior level
				start_path = lc.path[:i]
				count = 1
				break
			}
		}
		if len(start_path) == 0 {
			// TODO root node; what does this mean?
		} else {
			for i in 0..<count {
				node := get_node_at_path(editor, start_path)
				codenode_remove2(editor, node, start_path)
			}
		}
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
			region_simple_move(editor, true, .right)
		case .left_arrow:
			region_simple_move(editor, true, .left)
		case .up_arrow:
			region_simple_move(editor, true, .up)
		case .down_arrow:
			region_simple_move(editor, true, .down)
		case .backspace:
			for region in &regions {
				if region_is_point(region) {
					cursor_delete_left(editor, &region.to)
					delete_cursor(region.from)
					deep_copy(&region.from, &region.to)
				}
				region.xpos = -1
			}
			scroll_to_ensure_cursor(editor)
		case .home:
			region_simple_move(editor, true, .home)
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
					delete_cursor(region.from)
					deep_copy(&region.from, &region.to)
				}
				region.xpos = -1
			}
			scroll_to_ensure_cursor(editor)
		case:
			handled = false
		}
	} else if mods=={.shift} {
		#partial switch key {
		case .right_arrow:
			region_simple_move(editor, false, .right)
		case .left_arrow:
			region_simple_move(editor, false, .left)
		case:
			handled = false
		}
	} else if mods=={.control} {
		#partial switch key {
		case .s:
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
		case:
			handled = false
		}
	} else {
		handled = false
	}

	return handled
}

import "core:io"

codenode_string_insert_text :: proc(node: ^CodeNode, cursor: ^Cursor, text: string) {
	snode := &node.string
	text_idx := cursor.idx-1
	if text_idx < 0 || text_idx > rp.get_count(snode.text) {return}

	rp.insert_text(&snode.text, text_idx, text)

	cursor.idx += len(text)
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
		} else {
			whitespace = false
		}
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
	return !(ch==' ' || ch<0x20 ||
		ch=='('||ch=='['||ch=='{'||ch==')'||ch==']'||ch=='}'||ch=='"')
}

codeeditor_insert_text :: proc(using editor: ^CodeEditor, cursor: ^Cursor, input_str: string) {
	path := cursor.path
	is_root := len(path)==0

	node := get_node_at_path(editor, path)

	is_inserting_in_gap := cursor.idx<0
	is_inserting_first_child := is_root || (node.tag==.coll && cursor.coll_place==.open_post)

	if is_inserting_first_child { // Create new first child
		children := &roots
		if !is_root {
			children = &node.coll.children
		}

		n_nodes_added := codeeditor_insert_nodes_from_text(
			editor, input_str, children, 0)
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
		} else
		// add token node before/after string/coll
		if (node.tag==.string || node.tag==.coll) &&
		(cursor.idx==0 || cursor.idx==last_idx_of_node(node)) {
			if cursor.idx==0 {
				cursor.place = .before
				codeeditor_insert_text(editor, cursor, input_str)
				node = nil
				siblings := get_siblings_of_codenode(editor, cursor.path)
				new_node_idx := cursor.path[len(cursor.path)-1]
				new_node := &siblings[new_node_idx]
				if new_node.tag==.token {
					codenode_set_prefix(&siblings[new_node_idx+1], true)
					new_node.token.prefix = true
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
	 				if cursor.place==.before {
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

request_new_scroll :: proc(using editor: ^CodeEditor, new_scroll_offset: [2]i32) {
	current_time := time.to_unix_nanoseconds(time.now())/1e6

	using smooth_scroll

	already_scrolling := current_time<=latest_time+auto_cast duration

	// determine new duration
	new_duration : type_of(duration)
	{
		// interval_ratio :: 200 // default for firefox general.smoothScroll.durationToIntervalRatio
		interval_ratio :: 50
		min_duration :: 100
		max_duration :: 150

		if !already_scrolling { // not scrolling
			new_duration = max_duration
			max_delta := u16(max_duration/interval_ratio)
			prev_event_dts[0] = max_delta
			prev_event_dts[1] = max_delta
		} else { // currently scrolling
			latest_delta := u16(current_time-latest_time)
			average_delta := (prev_event_dts[0]+prev_event_dts[1]+latest_delta)/3
			prev_event_dts[0] = prev_event_dts[1]
			prev_event_dts[1] = latest_delta

			new_duration = clamp(average_delta*interval_ratio, min_duration, max_duration)
		}
	}

	velocity: [2]i32 // pixels per second
	{
		progress := f32(current_time-latest_time)/auto_cast duration
		if progress >= 1 {
			velocity = {0, 0}
		} else {
			p2 := scroll_control_point2
			p1s := control_point1s
			x_t := get_bezier_t_for_x(progress, p1s.x.x, p2.x)
			y_t := get_bezier_t_for_x(progress, p1s.y.x, p2.x)
			x_grad := calc_bezier_grad(x_t, p1s.x, p2)
			y_grad := calc_bezier_grad(y_t, p1s.y, p2)
			get_velocity :: #force_inline proc(grad: [2]f32, multiplier: f32) -> i32 {
				dt := grad.x
				dr := grad.y
				if dt==0 {
					return dr>=0 ? max(i32) : min(i32)
				}
				// pixels/ms -> pixels/s
				return i32(math.round(dr/dt * multiplier * 1000))
			}
			velocity.x = get_velocity(x_grad, f32(scroll_offset.x - start_pos.x)/f32(duration))
			velocity.y = get_velocity(y_grad, f32(scroll_offset.y - start_pos.y)/f32(duration))
		}
	}

	get_control_point1 :: #force_inline proc(total_distance: i32, #any_int duration: int, velocity: i32) -> (p1: [2]f32) {
		// Ensure that initial velocity equals the current velocity for smooth experience:
		// initial velocity = initialrve (normalised), grad0  *  scaling factor
		// maxe the initial gradient:
		if total_distance==0 {return {0,0}}
		grad0 := (f32(velocity)/1000) * (f32(duration) / f32(total_distance))
		
		// First control point p1 is (dt, dr) where dt and dr are normalised time and distance
		// Thus the initial gradient grad0 = dr/dt
		// For scroll_velocity_coeff to represent the distance |p1-p0| independent of current velocity,
		// dt and dr must be points on a circle
		p1.x = scroll_velocity_coeff / math.sqrt(1+grad0*grad0)
		p1.y = p1.x * grad0
		return 
	}

	// update the scroll destination
	scroll_offset = new_scroll_offset
	start_pos = contents_rect.coords.xy-view_rect.coords.xy
	latest_time = current_time
	duration = new_duration

	control_point1s.x = get_control_point1((scroll_offset.x-start_pos.x), duration, velocity.x)
	control_point1s.y = get_control_point1((scroll_offset.y-start_pos.y), duration, velocity.y)
}

// equivalent parameters to Firefox/Gecko's
scroll_velocity_coeff :: 0.15 // default is 0.25 for general.smoothScroll.currentVelocityWeighting
scroll_deceleration_coeff :: 0.4 // default is 0.4 for  general.smoothScroll.stopDecelerationWeighting

scroll_control_point2 :: [2]f32{1-scroll_deceleration_coeff, 1}

// also see keySplines https://www.w3.org/TR/smil-animation/
// and https://www.desmos.com/calculator/wex6j3vcwb
// start and end control points p0=(0,0) and p3=(1,1)
// cubic Bézier curve

// returns the point on the Bezier curve at t with control points p1, p2
// p1 and p2 are either (x,y) points or the x or y components
// ie returns x(t) when p1=x1, p2=x2
calc_bezier :: proc(t: f32, p1: $P, p2: P) -> P {
	// use Horner's method for optimal evaluation
	return t*((3*p1) + t*((3*p2-6*p1) + t*(1-3*p2+3*p1)))
}
calc_bezier_grad :: proc(t: f32, p1: $P, p2: P) -> P {
	return 3*p1 + t*((6*p2-12*p1) + t*(3-9*p2+9*p1))
}

// the curve is monotonically increasing from (0,0) to (1,1)
get_bezier_t_for_x :: proc(x: f32, p1: f32, p2: f32) -> f32 {
	if x==1 {return 1}

	t := x // initial guess

	grad := calc_bezier_grad(t, p1, p2)
	if grad >= 0.02 { // Newton-Raphson method
		n_its :: 5
		min_grad :: 0.02
		for i in 0..<n_its {
			err := calc_bezier(t, p1, p2)-x
			grad = calc_bezier_grad(t, p1, p2)
			if grad==0 {break}
			t -= err/grad
		}

	} else { // Binary search
		max_err :: 0.0000001
		max_its :: 10
		t1 : f32 = 0
		t2 : f32 = 1
		n_its := 1
		for {
			err := calc_bezier(t, p1, p2)-x
			if err>0 {
				t2 = t
			} else {
				t1 = t
			}
			if math.abs(err)<=max_err || n_its==max_its {
				break
			}
			t = (t1+t2)/2
			n_its += 1
		}
	}
	return t
}