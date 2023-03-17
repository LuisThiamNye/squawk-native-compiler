package vis

import "core:fmt"
import "core:mem"
import "core:runtime"

import c_ "core:c"
import win "core:sys/windows"

import sk "../skia"

Rect :: struct #raw_union {
	using ltrb: sk.SkRect,
	coords: [4]f32,
}

println :: fmt.println

// TODO - control frame rate properly (SetTimer ?)

Graphics :: struct {
	width: i32,
	height: i32,
	mouse_pos: [2]int,
	mouse_cursor: Sys_Mouse_Cursor_Type,

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
	key: Key,
}

Event_Mousebutton_Key :: enum {
	lbutton,
	rbutton,
	shift,
	control,
	mbutton,
	xbutton1,
	xbutton2,
}

Event_Mousebutton_Keyset :: bit_set[Event_Mousebutton_Key]

get_keyboard_state :: proc() -> [256]u8 {
	ks : [256]u8
	win.GetKeyboardState(auto_cast &ks)
	return ks
}

keyboard_key_pressed :: proc(kbd: [256]u8, key: Key) -> bool{
	return (kbd[key] & (1<<7))>0
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

set_cursor :: proc(cursor: Sys_Mouse_Cursor_Type) {
	c : cstring
	switch cursor {
	case .arrow:
		c = win.IDC_ARROW
	case .ibeam:
		c = win.IDC_IBEAM
	case: panic("invalid")
	}
	hc := win.LoadCursorW(nil, auto_cast cast(rawptr) c)
	win.SetCursor(hc)
}

handle_window_message :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT,
	wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	context = runtime.default_context()
	using win
	window := cast(^Window) GetPropW(hwnd, utf8_to_wstring("SQ"))
	if window == nil { // init window
		graphics : Graphics
	    rect: RECT
		GetClientRect(hwnd, &rect)
	    resize_buffer(&graphics, rect.right-rect.left, rect.bottom-rect.top)

	    // Init window state
	    window = new(Window)
	    window.graphics = graphics
	    window.app = new(AppState)

	    SetPropW(hwnd, utf8_to_wstring("SQ"), auto_cast window)
	    the_only_window = window

	    window.graphics.scale = get_window_scale(hwnd)
	}

	window.latest_hwnd = hwnd
	using window

	switch msg {
	case WM_SETCURSOR:
		cursor_area := lparam & 0xFFFF
		if HTCLIENT==cursor_area {
			set_cursor(graphics.mouse_cursor)

			return 1
		}
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
		// MK_CONTROL :: 0x0008
		// MK_LBUTTON :: 0x0001
		// MK_MBUTTON :: 0x0010
		// MK_RBUTTON :: 0x0002
		// MK_SHIFT :: 0x0004
		// MK_XBUTTON1 :: 0x0020
		// MK_XBUTTON2 :: 0x0040
		// keys_down := wparam
		x := cast(int) cast(i16) lparam
		y := lparam >> 16
		graphics.mouse_pos = {x, y}

		handled := event_mouse_pos(window, x, y)
		if handled {InvalidateRect(hwnd, nil, false)}
		return cast(int) !handled
	case WM_MOUSELEAVE:
		fmt.println("WE HAVE LEFT")
	case WM_MOUSEWHEEL:
		break
    case WM_LBUTTONDOWN: fallthrough
    case WM_RBUTTONDOWN: fallthrough
    case WM_MBUTTONDOWN: fallthrough
    case WM_XBUTTONDOWN:
    	key : Key
    	switch msg {
    	case WM_LBUTTONDOWN:
    		key = .lbutton
	    case WM_RBUTTONDOWN:
    		key = .rbutton
	    case WM_MBUTTONDOWN:
    		key = .middle_button
	    case WM_XBUTTONDOWN:
    		if wparam>>16==1 {
    			key = .x1_button
    		} else {
    			key = .x2_button
    		}
    	}
    	x := cast(int) cast(i16) lparam
		y := lparam >> 16
		graphics.mouse_pos = {x, y}

    	handled := event_mousedown(window, key)
		if handled {InvalidateRect(hwnd, nil, false)}
		set_cursor(graphics.mouse_cursor)

		SetCapture(hwnd) // listen for mouse events outside the window

		return cast(int) !handled
    case WM_LBUTTONUP: fallthrough
    case WM_RBUTTONUP: fallthrough
    case WM_MBUTTONUP: fallthrough
    case WM_XBUTTONUP:
    	key : Key
    	switch msg {
	    case WM_LBUTTONUP:
    		key = .lbutton
	    case WM_RBUTTONUP:
    		key = .lbutton
	    case WM_MBUTTONUP:
    		key = .middle_button
	    case WM_XBUTTONUP:
    		if wparam>>16==1 {
    			key = .x1_button
    		} else {
    			key = .x2_button
    		}
    	}
    	x := cast(int) cast(i16) lparam
		y := lparam >> 16
		graphics.mouse_pos = {x, y}

    	handled := event_mouseup(window, key)
		if handled {InvalidateRect(hwnd, nil, false)}
		set_cursor(graphics.mouse_cursor)

		keys_down := transmute(Event_Mousebutton_Keyset) cast(u8) (wparam & 0xFFFF)
		mouse_buttons : Event_Mousebutton_Keyset
		mouse_buttons = {.lbutton, .rbutton, .mbutton, .xbutton1, .xbutton2}
		if (keys_down & mouse_buttons)=={} {
			// all mouse buttons are unpressed => stop capturing
			ReleaseCapture()
		}

		return cast(int) !handled
	case WM_SYSKEYDOWN: fallthrough
	case WM_KEYDOWN:
		handled := event_keydown(window, {key=auto_cast wparam})
		if handled {InvalidateRect(hwnd, nil, false)}
		if handled {return 0}
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
		InvalidateRect(hwnd, nil, false)
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
    // compile_sample()

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

AppState :: struct {
	initialised: bool,
	code_editor: CodeEditor,
	inspector: InspectorState,
	textbox: Ui_Textbox,
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

	// free at start of frame so that data is available for event handling
	mem.free_all(context.temp_allocator)

	canvas_clear(cnv, 0xFFffffff)

	// draw_inspector(window, cnv, &window.app.inspector)
	draw_codeeditor(window, cnv)


	// using window.app
	// textbox.font_size = 15*scale
	// // uses temp allocator
	// textbox.font = get_default_font(window, textbox.font_size)
	// if !window.app.textbox.init {
	// 	textbox.border_colour = {200,200,200,255}
	// 	textbox.text_colour = {50,44,40,255}
	// }
	// draw_textbox(&window.app.textbox, cnv, window.graphics.scale)
}

event_keydown :: proc(window: ^Window, using evt: Event_Key) -> bool {
	// fmt.println(evt)
	// return textbox_event_keydown(&window.graphics, &window.app.textbox, evt)
	return codeeditor_event_keydown(window, &window.app.code_editor, evt)
}

event_charinput :: proc(window: ^Window, ch: int) {
	// textbox_event_charinput(&window.app.textbox, ch)
	codeeditor_event_charinput(window, &window.app.code_editor, ch)
}

event_mousedown :: proc(window: ^Window, key: Key) -> bool {
	// return textbox_event_mousedown(&window.graphics, &window.app.textbox, key)
	return false
}

event_mouseup :: proc(window: ^Window, key: Key) -> bool {
	// return textbox_event_mouseup(&window.graphics, &window.app.textbox, key)
	return false
}

event_mouse_pos :: proc(window: ^Window, x: int, y: int) -> bool {
	// return textbox_event_mouse_pos(&window.graphics, &window.app.textbox, x, y)
	return false
}



Sys_Mouse_Cursor_Type :: enum {
	arrow,
	ibeam,
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

CF_UNICODETEXT :: 13

clipboard_set_text :: proc(text: string) -> bool {
	using win
	OpenClipboard(nil) or_return
	defer CloseClipboard()

	wstr := utf8_to_utf16(text)
	nbytes := len(wstr)*size_of(u16)

	GMEM_MOVEABLE :: 2
	h_data := GlobalAlloc(GMEM_MOVEABLE, auto_cast nbytes+size_of(u16))
	if h_data==nil {return false}
	{
		data := GlobalLock(h_data)
		defer GlobalUnlock(h_data)
		mem.copy(data, raw_data(wstr), nbytes)
	}
	res_data := SetClipboardData(CF_UNICODETEXT, auto_cast h_data)
	if res_data==nil {return false}
	return true
}

clipboard_get_text :: proc() -> (out: string, ok: bool) {
	using win

	OpenClipboard(nil) or_return
	defer CloseClipboard()

	IsClipboardFormatAvailable(CF_UNICODETEXT) or_return

	handle := cast(HGLOBAL) GetClipboardData(CF_UNICODETEXT)
	if handle==nil {return}

	data := cast([^]u16) GlobalLock(handle)
	if data==nil {return}
	defer GlobalUnlock(handle)

	out_, err := wstring_to_utf8(data, -1)
	if err!=.None {return}
	out = out_
	ok = true
	return
}