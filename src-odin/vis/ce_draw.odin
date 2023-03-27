package vis

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

draw_codeeditor :: proc(window: ^Window, cnv: sk.SkCanvas) {
	using sk
	using code_editor := &window.app.code_editor

	if !initP {
		initP = true

		file_path = "/me/prg/fera-db2/cool.sq"

		region : Region
		region.to.idx = 0
		deep_copy(&region.from, &region.to)
		region.xpos = -1
		append(&code_editor.regions, region)

		codeeditor_refresh_from_file(code_editor)
	}

	if len(code_editor.pending_edit_tx_deltas)>0 {
		fmt.println("ERROR: there are", len(code_editor.pending_edit_tx_deltas), "edit deltas that have not been transacted")
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
		if scroll_offset == d.xy {
			smooth_scroll.duration = 1 // stop animation
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
	line_height = math.ceil(line_spacing)

	space_width = math.round(measure_text_width(font, " "))



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

	TextDrawItem :: struct {
		x: f32,
		y: f32,
		blob: sk.SkTextBlob,
		colour: u32,
	}
	text_draw_items := make([dynamic]TextDrawItem, 0, context.temp_allocator)

	{ // Calculate nodes layout
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
		tdi : TextDrawItem
		stack := make([dynamic]Frame_DrawNode, 0, context.temp_allocator)
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
						tdi.x = x
						tdi.y = y-metrics.ascent
						tdi.blob = blob_close
						tdi.colour = bracket_colour
						append(&text_draw_items, tdi)
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
					fmt.println(left_node, node)
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
				node.pos.x = x
				node.pos.y = y
				x = left_start_x
				y += line_height
				node.newline.after_pos.x = x
				node.newline.after_pos.y = y

			case .token:
				text := string(node.token.text)

				blob := make_textblob_from_text(text, font)

				c0 := text[0]
				constantP := c0==':' || ('0' <= c0 && c0 <= '9') || text=="nil" || text=="false" || text=="true"
				colour : u32
				if constantP {
					colour = constants_colour
				} else if node.token.prefix {
					colour = bracket_colour
				} else {
					colour = 0xFF000000
				}
				tdi.x = x
				tdi.y = y-metrics.ascent
				tdi.blob = blob
				tdi.colour = colour
				append(&text_draw_items, tdi)

				width := measure_text_width(font, text)
				x += width
			case .string:
				text := &node.string.text

				text_lines := make([dynamic]string, 0, context.temp_allocator)
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

				tdi.x = x
				tdi.y = y-metrics.ascent
				tdi.blob = blob_double_quote
				tdi.colour = string_quote_colour
				append(&text_draw_items, tdi)

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

					blob := make_textblob_from_text(line, font)

					tdi.x = x
					tdi.y = y-metrics.ascent
					tdi.blob = blob
					tdi.colour = 0xFF000000
					append(&text_draw_items, tdi)

					x += width

					ns.lines[i].width = width
					ns.lines[i].text = line
				}

				tdi.x = x
				tdi.y = y-metrics.ascent
				tdi.blob = blob_double_quote
				tdi.colour = string_quote_colour
				append(&text_draw_items, tdi)

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
				tdi.x = x
				tdi.y = text_y
				tdi.blob = blob_open
				tdi.colour = bracket_colour
				append(&text_draw_items, tdi)

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

	dbg_println_cursor(regions[0].to)

	pos_at_cursor_on_node :: proc(
		using editor: ^CodeEditor, node: ^CodeNode, cursor: CursorPosition,
		origin: [2]f32, mode: enum{selection, caret}) -> (f32, f32) {
		x, y: f32
		if node == nil {
			x = origin.x
			y = origin.y
		} else {
			x = node.pos.x
			y = node.pos.y

			switch node.tag {
			case .newline:
				if cursor.place==.after {
					if mode==.caret {
						x = node.newline.after_pos.x
						y = node.newline.after_pos.y
					} else {
						x += space_width * 0.5
					}
				}
				
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
		return x, y
	}

	// Draw selection background
	{
		for region in &regions {
			if region_is_point(region) {continue}
			lc, rc := ordered_cursors(code_editor, &region)
			is_block := region_is_block_selection(code_editor, &region)
			block_level := region_block_level(region)
			siblings := get_siblings_of_codenode(code_editor, rc.path[:block_level+1])

			paint_set_colour(paint, selection_colour)

		  start := lc.path[block_level]
			end := rc.path[block_level]+1
			n := end-start

			prev_x: f32
			fresh_line := false

			// First node
			{
				node := siblings[start]
				lcpos := is_block ? CursorPosition{idx=0} : lc.position
				rcpos := n>1 || is_block ? CursorPosition{idx=last_idx_of_node(&node)} : rc.position
				l, y := pos_at_cursor_on_node(code_editor, &node, lcpos, origin, .selection)
				r, y2 := pos_at_cursor_on_node(code_editor, &node, rcpos, origin, .selection)
				canvas_draw_rect(cnv, sk_rect(l=l, r=r, t=y, b=y2+line_height), paint)
				prev_x = r
				fresh_line = node.tag==.newline
			}

			if n>1 {
				selected_nodes := siblings[start+1:end-1]
				for node in &selected_nodes {

					r, y2 := pos_at_cursor_on_node(code_editor, &node, CursorPosition{idx=last_idx_of_node(&node)}, origin, .selection)
					y := node.pos.y
					l := node.pos.x
					if !fresh_line {
						l = prev_x
					}
					canvas_draw_rect(cnv, sk_rect(l=l, r=r, t=y, b=y2+line_height), paint)
					prev_x = r
					fresh_line = node.tag==.newline
				}

				// Last node
				node := siblings[end-1]

				l, y := pos_at_cursor_on_node(code_editor, &node, CursorPosition{idx=0}, origin, .selection)
				if !fresh_line {
					l = prev_x
				}
				rcpos := is_block ? CursorPosition{idx=last_idx_of_node(&node)} : rc.position
				r, y2 := pos_at_cursor_on_node(code_editor, &node, rcpos, origin, .selection)
				canvas_draw_rect(cnv, sk_rect(l=l, r=r, t=y, b=y2+line_height), paint)
			}
		}
	}

	{ // Draw nodes
		for item in text_draw_items {
			using item
			paint_set_colour(paint, colour)
			canvas_draw_text_blob(cnv, blob, x, y, paint)
		}
	}

	{ // Draw cursor
		cursor_width := 2*scale
		dl := cursor_width/2
		dr := cursor_width-dl

		paint_set_colour(paint, active_colour)

		for region in &regions {
			// xpos : f32
			cursor := region.to
			path := cursor.path
			node := get_node_at_path(code_editor, path)
			x, y := pos_at_cursor_on_node(code_editor, node, cursor, origin, .caret)
			
			x = math.round(x)
			canvas_draw_rect(cnv, sk_rect(l=x-dl, r=x+dr, t=y, b=y+line_height), paint)

			if regions_changed {
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

	old_contents := contents_rect
	update_contents_rect_to_scroll(code_editor)
	if old_contents != contents_rect {
		request_frame(window)
	}
}