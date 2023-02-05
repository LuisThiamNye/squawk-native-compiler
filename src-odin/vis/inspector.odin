package vis

import sk "../skia"
import "core:fmt"
import "core:strings"
import "core:mem"

InspectorFrame :: struct {
	specimen: any, 
}

InspectorState :: struct {
	stack: [dynamic]InspectorFrame,
}

draw_inspector :: proc(window: ^Window, cnv: sk.SkCanvas, using inspector: ^InspectorState) {
	using sk

	paint := make_paint()
	paint_set_colour(paint, 0xFF000000)
	title_bg_paint := make_paint()
	paint_set_colour(title_bg_paint, 0xFFd0d0d0)

	for frame in stack {
		using frame
		text := strings.concatenate({"draw inspector frame", fmt.aprint(specimen.id)})

		x := 10
		y := 10

		using window.graphics
		font := get_default_font(window, scale*15)
		line_spacing := font_get_metrics(font, nil)

		canvas_draw_rect(cnv, sk_rect(x, y, x+700, (cast(f32) y)+line_spacing), title_bg_paint)

		blob := make_textblob_from_text(text, font)
		canvas_draw_text_blob(cnv, blob, auto_cast x, auto_cast y+line_spacing, paint)
	}
}

dbg_inspect :: proc(data: any) {
	window := the_only_window
	if window == nil {
		fmt.println("Inspect:", data)
		return
	}
	using window.app.inspector
	append(&stack, InspectorFrame{specimen=data})

	request_frame(window)
}