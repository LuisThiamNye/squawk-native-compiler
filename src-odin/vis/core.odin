package vis

import "core:fmt"
import "core:runtime"
import "core:mem"

import c_ "core:c"
import win "core:sys/windows"

import sk "../skia"

println :: fmt.println

// TODO - control frame rate properly (SetTimer ?)

Graphics :: struct {
	width: i32,
	height: i32,

	bm_size: int,
	bitmap_info: ^win.BITMAPINFO,
	
	surface: sk.SkSurface,
	scale: f32,
	frame_requested: bool,
}

Window :: struct {
	graphics: Graphics,
	app: ^AppState,
	// event_delta: ^EventDelta,
	latest_hwnd: win.HWND, // may change, so only use from message loop
}

// EventDelta :: struct {
// 	events: [dynamic]Event,
// }

EventTag :: enum {key}

Event :: struct {
	tag: EventTag,
	using event: struct #raw_union {
		keydown: Event_Key,
		keyup: Event_Key,
	},
}

Event_Key :: struct {
	key: int,
}

resize_buffer :: proc(using self: ^Graphics, new_width: i32, new_height: i32) {
	using win

	self.width = new_width==0 ? 1 : new_width
	self.height = new_height==0 ? 1 : new_height

	chunk_size_pow :: 18
	bmmem : rawptr = bitmap_info
	required_size := cast(int) (size_of(BITMAPINFO) + width*height*size_of(u32))
	if required_size > bm_size {
		new_nchunks := 1+((required_size-1) >> chunk_size_pow)
		if bm_size>0 {
			// mem.free_with_size(bmmem, bm_size)
			mem.free(bmmem)
		}
		bm_size = new_nchunks << chunk_size_pow
		bmmem = mem.alloc(bm_size)
	}

	bitmap_info = auto_cast bmmem

	bitmap_info.bmiHeader.biSize=size_of(BITMAPINFOHEADER)
	bitmap_info.bmiHeader.biWidth=width
	bitmap_info.bmiHeader.biHeight=-height
	bitmap_info.bmiHeader.biPlanes=1
	bitmap_info.bmiHeader.biBitCount=32
	bitmap_info.bmiHeader.biCompression=BI_RGB
}

get_window_scale :: proc(hwnd: win.HWND) -> f32 {
	using win
	monitor := MonitorFromWindow(hwnd, Monitor_From_Flags.MONITOR_DEFAULTTOPRIMARY)
	scale_factor:  DEVICE_SCALE_FACTOR
	GetScaleFactorForMonitor(monitor, &scale_factor)
	if scale_factor==Device_Scale_Factor.DEVICE_SCALE_FACTOR_INVALID {
		scale_factor = Device_Scale_Factor.SCALE_100_PERCENT
	}
	return cast(f32) scale_factor/100
}

winmsg_request_frame :: win.WM_USER

request_frame :: proc(window: ^Window) {
	using win
	InvalidateRect(window.latest_hwnd, nil, false)
}

handle_window_message :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT,
	wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	context = runtime.default_context()
	using win
	window := cast(^Window) GetPropW(hwnd, utf8_to_wstring("SQ"))
	if window == nil { // init window
		graphics := Graphics{}
	    rect: RECT
		GetClientRect(hwnd, &rect)
	    resize_buffer(&graphics, rect.right-rect.left, rect.bottom-rect.top)

	    window = new(Window)
	    window^ = {graphics=graphics, app=new(AppState)}
	    SetPropW(hwnd, utf8_to_wstring("SQ"), auto_cast window)

	    the_only_window = window

	    window.graphics.scale = get_window_scale(hwnd)
	}

	window.latest_hwnd = hwnd
	using window

	switch msg {
	case WM_TIMER:
		// return 0
		break
	case WM_WINDOWPOSCHANGED:
		window.graphics.scale=get_window_scale(hwnd)
		break
	case WM_ENTERSIZEMOVE:
		break
	case WM_EXITSIZEMOVE:
		break
	case WM_SIZE:
		if graphics.surface!=nil {
			sk.refcnt_unref(graphics.surface)
			graphics.surface = nil
		}

		content_width := cast(i32) LOWORD(auto_cast lparam)
		content_height := cast(i32) HIWORD(auto_cast lparam)
		resize_buffer(&graphics, content_width, content_height)
		return 0
	case WM_MOVE:
		break
	case WM_ERASEBKGND:
		// return non-zero if program erases the background
		return 1
	case winmsg_request_frame:
		if graphics.frame_requested==false {
			return 0
		}
		graphics.frame_requested = false
		fallthrough
	case WM_PAINT:
		ps: PAINTSTRUCT
		hdc := BeginPaint(hwnd, &ps)
		if hdc != nil {
			using sk
			using graphics

			if surface==nil {
				image_info : SkImageInfo =
					imageinfo_make(width, height, SkColorType.BGRA_8888, SkAlphaType.premul, nil)
				pixels : rawptr = &bitmap_info.bmiColors
				row_bytes := width*size_of(u32)
				surface = surface_make_raster_direct(&image_info, pixels, auto_cast row_bytes, nil)
				if surface==nil {
					fmt.panicf("invalid surface. width=%v height=%v\n", width, height)
				}
			}

			cnv := surface_get_canvas(surface)
			draw_ui_root(window, cnv)
			surface_flush(surface)

			// swap buffers
			StretchDIBits(
				hdc = hdc,
				xDest = 0,
				yDest = 0,
				DestWidth = width,
				DestHeight = height,
				xSrc = 0,
				ySrc = 0,
				SrcWidth = width,
				SrcHeight = height,
				lpBits = &bitmap_info.bmiColors,
				lpbmi = bitmap_info,
				iUsage = DIB_RGB_COLORS,
				rop = SRCCOPY)

			EndPaint(hwnd, &ps)
		}
		// graphics.frame_requested=true
		// PostMessageW(hwnd, winmsg_request_frame, 0, 0)

		// InvalidateRect(hwnd, nil, false)
		return 0
	case WM_MOUSEMOVE:
		break
	case WM_MOUSEWHEEL:
		break
    case WM_LBUTTONDOWN:
    case WM_RBUTTONDOWN:
    case WM_MBUTTONDOWN:
    case WM_XBUTTONDOWN:
    case WM_LBUTTONUP:
    case WM_RBUTTONUP:
    case WM_MBUTTONUP:
    case WM_XBUTTONUP:
    	break
	case WM_SYSKEYDOWN: fallthrough
	case WM_KEYDOWN:
		// event_keydown(window, {key=auto_cast wparam})
		break
	case WM_KEYUP:
		break
	case WM_CHAR:
		mask_nrepeats :: 0b00000000000000001111111111111111
		mask_scancode :: 0b00000000011111110000000000000000
		mask_extkey ::   0b00000000100000000000000000000000
		mask_keystate :: 0b10000000000000000000000000000000
		charcode := cast(int) wparam
		nrepeats := mask_nrepeats & lparam
		event_charinput(window, charcode)
		return 0
	case WM_SETFOCUS:
		break
	case WM_KILLFOCUS:
		break
	case WM_CLOSE:
		// return 0
	case WM_DESTROY:
		PostQuitMessage(0)
		return 0
	}

	return DefWindowProcW(hwnd, msg, wparam, lparam)
}

the_only_window : ^Window

main :: proc() {
	using win
	SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)

	// register window class
	wc: WNDCLASSEXW
	hInstance := GetModuleHandleW(nil)
	wc.cbSize = size_of(wc)
	wc.style = CS_OWNDC | CS_HREDRAW | CS_VREDRAW
	wc.lpfnWndProc = handle_window_message
	wc.hInstance = cast(HINSTANCE) hInstance
	wc.hCursor = LoadCursorW(nil, auto_cast _IDC_ARROW)
	class_name := utf8_to_wstring("SQ_WINDOW")
	wc.lpszClassName = class_name

	if 0 == RegisterClassExW(&wc) {
		panic("failed to register window class")
	}

	// create window

	window_name := utf8_to_wstring("My window")
	x : i32 = 0
	y : i32 = 0
	w : i32 = 500
	h : i32 = 400
    hwnd :=
    	CreateWindowExW(
    		0,
            class_name,
            window_name,
            WS_OVERLAPPEDWINDOW | WS_CAPTION | WS_CLIPSIBLINGS | WS_CLIPCHILDREN,
            x, y, w, h,
            nil, nil,
            auto_cast GetModuleHandleW(nil),
            nil)

    if hwnd == nil {
    	panic("failed to create hwnd")
    }

    ShowWindow(hwnd, SW_RESTORE)

    // DEV
    compile_sample()

    msg: MSG
    for {
    	if !GetMessageW(&msg, nil, 0, 0) {
    		break
    	}
    	if msg.message == WM_CLOSE {
    		return
    	}

    	TranslateMessage(&msg)
    	DispatchMessageW(&msg)
    }

	println("done.")
}

Cursor :: struct {
	path: []int,
}

Region :: struct {
	to: Cursor,
	from: Cursor,
}

region_is_point :: proc(using region: Region) -> bool {
	if (len(to.path) != len(from.path)) {return false}
	for i in 0..<len(to.path) {
		if to.path[i] != from.path[i] {return false}
	}
	return true
}

CodeEditor :: struct {
	regions: [dynamic]Region,
	roots: [dynamic]CodeNode,
}

CodeNode_Tag :: enum {
	coll,
	token,
}

CodeNode :: struct {
	tag: CodeNode_Tag,
	using node: struct #raw_union {
		coll: CodeNode_Coll,
	 	token: CodeNode_Token},
}

CodeCollType :: enum {round, curly, square}

CodeNode_Coll :: struct {
	coll_type: CodeCollType,
	children: [dynamic]CodeNode,
}

CodeNode_Token :: struct {
	text: string,
}

Point :: struct {
	x: int,
	y: int,
}

AppState :: struct {
	initialised: bool,
	code_editor: ^CodeEditor,
	inspector: InspectorState,
}	

sk_rect :: proc(l: $L, t: $T, r: $R, b: $B) -> sk.SkRect {
	return {left=cast(f32) l, top=cast(f32) t,
		right=cast(f32) r, bottom=cast(f32) b}
}

make_paint :: proc() -> sk.SkPaint {
	using sk
	paint := cast(SkPaint) mem.alloc(size=size_of_SkPaint, allocator=context.temp_allocator)
	paint_init(paint)
	return paint
}

draw_ui_root :: proc(window: ^Window, cnv: sk.SkCanvas) {
	using sk, window, graphics

	if !app.initialised {
		app.initialised = true
		app.code_editor = new(CodeEditor)
		append(&app.code_editor.regions, Region{})
	}

	canvas_clear(cnv, 0xFFffffff)

	draw_inspector(window, cnv, &window.app.inspector)

	mem.free_all(context.temp_allocator)
}

get_default_font :: proc(window: ^Window, font_size: $S) -> sk.SkFont {
	using window, sk, graphics
	font_size : f32 = cast(f32) font_size
	font_style := fontstyle_init(auto_cast mem.alloc(size_of_SkFontStyle),
		SkFontStyle_Weight.normal, SkFontStyle_Width.normal, SkFontStyle_Slant.upright)
	typeface := typeface_make_from_name(nil, font_style^)
	font := font_init(auto_cast mem.alloc(size=size_of_SkFont, allocator=context.temp_allocator), typeface, font_size)
	return font
}

make_textblob_from_text :: proc(text: string, font: sk.SkFont) -> sk.SkTextBlob {
	using sk
	nglyphs := font_text_to_glyphs(font, raw_data(text), len(text), SkTextEncoding.UTF8, nil, 0)
	glyphs := cast([^]SkGlyphID) mem.alloc(size=cast(int) nglyphs*size_of(SkGlyphID),
		allocator=context.temp_allocator)
	font_text_to_glyphs(font, raw_data(text), len(text), SkTextEncoding.UTF8, glyphs, nglyphs)
	blob := textblob_make_from_text(glyphs, auto_cast nglyphs*size_of(SkGlyphID),
		font, SkTextEncoding.GlyphID)
	return blob
}

draw_codeeditor :: proc(window: ^Window, cnv: sk.SkCanvas) {
	using window, sk, graphics

	active_colour : u32 = 0xff007ACC
	paint := make_paint()
	paint_set_colour(paint, 0xFF000000)
	active_paint := make_paint()
	paint_set_colour(active_paint, 0xFF000000 | auto_cast active_colour)

	line_height := 15
	origin := Point{x=10,y=10}

	{
		using app.code_editor
		for root in roots {
			#partial switch root.tag {
			case .token:
				x := 50
				y := line_height
				token := root.token
				text := token.text
				font_size : f32 = 20
				font_style := fontstyle_init(auto_cast mem.alloc(size_of_SkFontStyle),
					SkFontStyle_Weight.normal, SkFontStyle_Width.normal, SkFontStyle_Slant.upright)
				typeface := typeface_make_from_name(nil, font_style^)
				font := font_init(auto_cast mem.alloc(size=size_of_SkFont, allocator=context.temp_allocator), typeface, font_size)

				blob := make_textblob_from_text(text, font)

				canvas_draw_text_blob(cnv, blob, auto_cast x, auto_cast y, paint)
			}
		}
	}

	{
		cursor_width := 2
		x := origin.x
		y := origin.y
		dl := cursor_width/2
		dr := cursor_width-dl
		csave := canvas_save(cnv)
		canvas_scale(cnv, scale, scale)
		canvas_draw_rect(cnv, sk_rect(l=x-dl, r=x+dr, t=y, b=y+line_height), active_paint)
		canvas_restore_to_count(cnv, csave)
	}
}

event_keydown :: proc(window: ^Window, using evt: Event_Key) {
	fmt.println(evt)
}

event_charinput :: proc(window: ^Window, ch: int) {
	code_editor := window.app.code_editor
	using code_editor
	for region in regions {
		if !region_is_point(region) {break}
		path := region.to.path

		if len(roots)==0 {
			ary := make([]u8,1)
			ary[0]=auto_cast ch
			str := string(ary)
			append(&roots, CodeNode{tag=.token, node={token={text=str}}})

			// p := make()
			// p[0]=
			// region.to.path := 
		}
	}
	request_frame(window)
}