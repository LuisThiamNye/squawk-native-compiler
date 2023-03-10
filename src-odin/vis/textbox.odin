package vis

import "core:fmt"
import "core:math"
import sk "../skia"


Ui_Textbox_Cursor :: struct #raw_union {
	using tofrom: struct {from: int, to: int,},
	tuple: [2]int,
}

Ui_Textbox :: struct {
	init: bool,

	rect: Rect,
	cursor: Ui_Textbox_Cursor,
	text: [dynamic]u8,
	text_left_coord: f32,

	drag_level: enum {none, char, word, line},
	scroll_x: int,
	prev_click_ns: i64,
	prev_click_pos: [2]int,
	prev_click_offset: int,

	event_flags: bit_set[enum {scroll_in_cursor}],

	using style: struct {
		font: sk.SkFont,
		font_size: f32,
		border_colour: [4]u8,
		text_colour: [4]u8,
		h_padding: f32,
		cursor_scroll_margin: f32,
	},
}

rect_grow :: proc(using rect: Rect, amount: f32) -> Rect {
	rect_ := rect
	rect_.left -= amount
	rect_.top -= amount
	rect_.right += amount
	rect_.bottom += amount
	return rect_
}

draw_textbox :: proc(using box: ^Ui_Textbox, cnv: sk.SkCanvas, scale: f32) {
	using sk

	border_width : f32 = 1*scale
	active_colour : u32 = 0xff007ACC

	h_padding = 5*scale
	cursor_scroll_margin = rect.bottom-rect.top

	if !box.init {
		// require caller to set: font
		box.init = true

		metrics : SkFontMetrics
		line_spacing := font_get_metrics(font, &metrics)

		box.rect.ltrb = {0, 0, 200*scale, math.ceil(line_spacing)}

		for c in "The quick brown thing jumped over the thing" {
			append(&box.text, cast(u8) c)
		}
	}

	metrics : SkFontMetrics
	line_spacing := font_get_metrics(font, &metrics)
	text_view_left := rect.left+h_padding

	cursor_width : f32
	cursor_height : f32
	cursor_x_mid : f32

	// Prior calculations
	for {
		text_left_coord = text_view_left+auto_cast scroll_x

		cursor_width = 2*scale
		cursor_height = line_spacing
		cursor_x_mid = text_left_coord+math.round(measure_text_width(font, text[:box.cursor.to]))

		// scroll in cursor
		if .scroll_in_cursor in event_flags {
			event_flags -= {.scroll_in_cursor}
			window_right := rect.right - h_padding - cursor_scroll_margin
			window_left := text_view_left
			if scroll_x!=0 {window_left += cursor_scroll_margin}
			if window_right < text_view_left {window_right = text_view_left}
			if window_right < window_left {window_left = window_right}
			if cursor_x_mid > window_right {
				diff := cursor_x_mid - window_right
				scroll_x -= auto_cast math.round(diff)
			} else if cursor_x_mid < window_left {
				diff := window_left - cursor_x_mid
				scroll_x += auto_cast math.round(diff)
				if scroll_x>0 {scroll_x = 0}
			}
			continue
		}
		break
	}

	// Draw stuff

	paint := make_paint()
	
	// draw border

	paint_set_colour(paint, transmute(u32) box.border_colour)
	paint_set_stroke(paint, true)
	paint_set_stroke_width(paint, border_width)

	border_rect := rect_grow(rect, -border_width/2)
	canvas_draw_rect(cnv, border_rect, paint)

	// Clip rect
	csave := canvas_save(cnv)
	defer canvas_restore_to_count(cnv, csave)
	canvas_clip_rect(cnv, &box.rect)

	// draw selection
	
	if cursor.to != cursor.from {
		selection_colour : u32 = 0xFFB4D8FD
		paint_set_colour(paint, selection_colour)
		paint_set_stroke(paint, false)

		start, end := sorted_cursor_idxs(cursor)

		start_coord := math.round(measure_text_width(font, text[:start]))
		end_coord := math.round(measure_text_width(font, text[:end]))
		sel_rect : Rect
		sel_rect.left = text_left_coord + start_coord
		sel_rect.right = text_left_coord + end_coord
		sel_rect.top = rect.top
		sel_rect.bottom = rect.bottom

		canvas_draw_rect(cnv, sel_rect, paint)
	}

	// draw text

	blob := make_textblob_from_text(string(text[:]), font)

	paint_set_colour(paint, transmute(u32) text_colour)
	paint_set_stroke(paint, false)

	canvas_draw_text_blob(cnv, blob, text_left_coord, rect.top-metrics.ascent, paint)

	{ // draw cursor
		x := cursor_x_mid
		y := rect.top
		dl := cursor_width/2
		dr := cursor_width-dl

		paint_set_colour(paint, active_colour)
		canvas_draw_rect(cnv, sk_rect(l=x-dl, r=x+dr, t=y, b=y+cursor_height), paint)
	}

}

measure_text_width :: proc{measure_text_width_slice, measure_text_width_string}
measure_text_width_slice :: proc(font: sk.SkFont, text: []u8) -> f32 {
	return measure_text_width_string(font, string(text))

}
measure_text_width_string :: proc(font: sk.SkFont, text: string) -> f32 {
	using sk
	return font_measure_text(font, raw_data(text), auto_cast len(text), SkTextEncoding.UTF8)
}

import "core:unicode/utf8"

get_offset_at_coord :: proc(font: sk.SkFont, text: []u8, x: f32) -> int {
	advance : f32 = 0
	i := 0
	for ; i<len(text) ; {
		if x < advance {return i}
		start_idx := i
		for {
			i += 1
			if i>=len(text) || utf8.rune_start(text[i]) {
				break
			}
		}
		width := measure_text_width(font, text[start_idx:i])
		mid := advance + width/2
		if x < mid {return start_idx}

		advance += width
	}
	return i
}

sorted_cursor_idxs :: proc(cursor: Ui_Textbox_Cursor) -> (start, end: int) {
	if cursor.to > cursor.from {
		start = cursor.from
		end = cursor.to
	} else {
		start = cursor.to
		end = cursor.from
	}
	return
}

rect_contains :: proc(using rect: Rect, x: int, y: int) -> bool {
	x := cast(f32) x
	y := cast(f32) y
	return left <= x && top <= y && x < right && y < bottom
}

textbox_event_mouse_pos :: proc(graphics: ^Graphics, using box: ^Ui_Textbox, x: int, y: int) -> bool {
	if drag_level!=.none {
		coord := cast(f32) x - text_left_coord
		offset := get_offset_at_coord(font, text[:], coord)
		if drag_level == .char {
			cursor.to = offset
		} else if drag_level == .word {
			start, end: int
			if offset > prev_click_offset {
				start = prev_click_offset
				end = offset
			} else {
				start = offset
				end = prev_click_offset
			}
			end_word := textbox_str_word_break_next(text[:], end)
			if end_word<0 {end_word=len(text)}
			start_word := textbox_str_word_break_prev(text[:], start)
			if start_word<0 {start_word=0}
			if offset > prev_click_offset {
				cursor.to = end_word
				cursor.from = start_word
			} else {
				cursor.to = start_word
				cursor.from = end_word
			}
		} else if drag_level == .line {
			if offset > prev_click_offset {
				cursor.to = len(text)
				cursor.from = 0
			} else {
				cursor.to = 0
				cursor.from = len(text)
			}
		}

		event_flags += {.scroll_in_cursor}

		return true
	}
	if rect_contains(rect, x, y) {
		graphics.mouse_cursor=.ibeam
	} else {
		graphics.mouse_cursor=.arrow
	}
	return false
}

textbox_event_mouseup :: proc(graphics: ^Graphics, using box: ^Ui_Textbox, key: Key) -> bool {
	mouse_pos := graphics.mouse_pos
	drag_level = .none
	if rect_contains(rect, mouse_pos.x, mouse_pos.y) {
		graphics.mouse_cursor=.ibeam
	} else {
		graphics.mouse_cursor=.arrow
	}
	return true
}

import "core:time"

textbox_event_mousedown :: proc(graphics: ^Graphics, using box: ^Ui_Textbox, key: Key) -> bool {
	mouse_pos := graphics.mouse_pos
	if rect_contains(rect, mouse_pos.x, mouse_pos.y) {
		#partial switch key {
		case .lbutton:
			current_ns := time.to_unix_nanoseconds(time.now())
			double_click_interval :: 500_000_000

			if (current_ns-prev_click_ns)<double_click_interval &&
			prev_click_pos == graphics.mouse_pos &&
			cursor.to!=len(text) && cursor.from!=0 {
				if cursor.to == cursor.from { // double click
					cursor.to = textbox_str_word_break_next(text[:], cursor.to)
					if cursor.to<0 {cursor.to=len(text)}
					cursor.from = textbox_str_word_break_prev(text[:], cursor.to)
					if cursor.from<0 {cursor.from=0}
					drag_level = .word
				} else { // triple click - entire line
					cursor.to = len(text)
					cursor.from = 0
					drag_level = .line
				}
			} else {
				coord := cast(f32) mouse_pos.x - text_left_coord
				offset := get_offset_at_coord(font, text[:], coord)
				cursor.tuple = {offset, offset}	
				drag_level = .char
				prev_click_offset = offset
			}
			prev_click_ns = current_ns
			prev_click_pos = graphics.mouse_pos
		}
		return true
	} else {
		return false
	}
}

Modifier :: enum {
	shift,
	control,
	alt,
}
Modifier_Set :: bit_set[Modifier]

get_kbd_modifiers :: proc() -> Modifier_Set {
	kbd := get_keyboard_state()

	mods : Modifier_Set
	if keyboard_key_pressed(kbd, Key.control) {
		mods += {.control}
	}
	if keyboard_key_pressed(kbd, Key.shift) {
		mods += {.shift}
	}

	return mods
} 

textbox_event_keydown :: proc(graphics: ^Graphics, using box: ^Ui_Textbox, using evt: Event_Key) -> bool {
	handled := true
	prev_cursor := cursor

	mods := get_kbd_modifiers()

	// Control
	if mods=={.control} {

		#partial switch key {
		case .left_arrow:
			x := textbox_str_word_break_prev(text[:], cursor.to)
			if x < 0 {break}
			cursor.tuple = {x, x}
		case .right_arrow:
			x := textbox_str_word_break_next(text[:], cursor.to)
			if x < 0 {break}
			cursor.tuple = {x, x}
		case .a:
			cursor.to=len(text)
			cursor.from=0
		// Copy / paste
		case .c:
			selection : []u8
			if cursor.to==cursor.from {
				selection = text[:]
			} else {
				s, e := sorted_cursor_idxs(cursor)
				selection = text[s:e]
			}
			clipboard_set_text(string(selection))
		case .v:
			s, ok := clipboard_get_text()
			if !ok {break}
			if cursor.to!=cursor.from { // delete selection
				s, e := sorted_cursor_idxs(cursor)
				remove_range(&text, s, e)
				cursor.tuple = {s,s}
			}
			inject_at_elems(&text, cursor.to, ..(transmute([]u8)s))
			x := len(s)
			cursor.tuple += x
		case:
			handled = false
		}
	} else
	// Shift
	if mods=={.shift} {

		#partial switch key {
		case .left_arrow:
			if cursor.to <= 0 {break}
			cursor.to -= 1
		case .right_arrow:
			if cursor.to >= len(text) {break}
			cursor.to += 1
		case .home:
			cursor.to = 0
		case .end:
			cursor.to = len(text)
		case:
			handled = false
		}
	} else
	// Control + Shift
	if mods=={.control, .shift} {

		#partial switch key {
		case .left_arrow:
			x := textbox_str_word_break_prev(text[:], cursor.to)
			if x < 0 {break}
			cursor.to = x
		case .right_arrow:
			x := textbox_str_word_break_next(text[:], cursor.to)
			if x < 0 {break}
			cursor.to = x
		case:
			handled = false
		}
	} else{
		#partial switch key {
		case .left_arrow:
			if cursor.to <= 0 {break
			} else if cursor.to!=cursor.from {
				x := math.min(cursor.to, cursor.from)
				cursor.tuple = {x, x}
			} else {
				cursor.to -= 1
				cursor.from = cursor.to
			}
		case .right_arrow:
			if cursor.to >= len(text) {break}
			if cursor.to!=cursor.from {
				x := math.max(cursor.to, cursor.from)
				cursor.tuple = {x, x}
			} else {
				cursor.to += 1
				cursor.from = cursor.to	
			}
		case .backspace:
			if cursor.to!=cursor.from { // delete selection
				s, e := sorted_cursor_idxs(cursor)
				remove_range(&text, s, e)
				cursor.tuple = {s,s}
			} else if cursor.to <= 0 {break
			} else {
				ordered_remove(&text, cursor.to-1)
				cursor.to -= 1
				cursor.from = cursor.to	
			}
		case .home:
			cursor.tuple = {0,0}
		case .end:
			x := len(text)
			cursor.tuple = {x, x}
		case:
			handled = false
		}
	}
	if cursor.to != prev_cursor.to {
		event_flags += {.scroll_in_cursor}
	}
	return handled
}

textbox_event_charinput :: proc(using box: ^Ui_Textbox, ch: int) {
	if ch > 255 {return}
	if ch < 0x20 {return}

	if cursor.to != cursor.from {
		s, e := sorted_cursor_idxs(cursor)
		remove_range(&text, s, e)
		cursor.tuple = {s,s}
	}

	inject_at(&text, cursor.to, cast(u8) ch)
	cursor.to += 1
	cursor.from = cursor.to

	event_flags += {.scroll_in_cursor}
}

textbox_str_word_break_next :: proc(str: []u8, start: int) -> int {
	if start>=len(str) {return -1}
	prev : u8
	if start > 0 {prev=str[start]}
	for i in start+1..<len(str) {
		ch := str[i]
		if prev!=' ' && ch==' ' {return i}
		prev = ch
	}
	return len(str)
}

textbox_str_word_break_prev :: proc(str: []u8, start: int) -> int {
	start := start-1
	if start<0 {return -1}
	prev : u8
	if start < len(str) {prev=str[start]}
	for i := start-1; i>=0; i-=1 {
		ch := str[i]
		if prev!=' ' && ch==' ' {return i+1}
		prev = ch
	}
	return 0
}