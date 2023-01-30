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

AppState :: struct {
	phase: int,
	colour: int,
}

Window :: struct {
	graphics: Graphics,
	app: ^AppState,
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

handle_window_message :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT,
	wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	using win
	context = runtime.default_context()
	window := cast(^Window) GetPropW(hwnd, utf8_to_wstring("SQ"))
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

			canvas_clear(cnv, 0xFFffffff)

			// paint := paint_new()
			paint := cast(SkPaint) mem.alloc(size_of_SkPaint)
			paint_init(paint)
			defer {
				paint_deinit(paint)
				mem.free(paint)
			}
			// paint_set_colour(paint, 0xFFaa4400)
			app.colour+=1
			paint_set_colour(paint, 0xFF000000 | auto_cast app.colour)

			if app.phase>cast(int) width {
				app.phase=0
			} else {
				app.phase += 1
			}
			canvas_draw_circle(cnv, auto_cast app.phase, 15, 20, paint)
			if scale<1.5 {canvas_draw_rect(cnv, {left=5, right=50, top=20, bottom=40}, paint)}

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
		InvalidateRect(hwnd, nil, false)
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
	case WM_KEYDOWN:
		break
	case WM_KEYUP:
		break
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
    	CreateWindowExW(0,
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

    graphics := Graphics{}
    rect: RECT
	GetClientRect(hwnd, &rect)
    resize_buffer(&graphics, rect.right-rect.left, rect.bottom-rect.top)

    window := new(Window)
    window^ = {graphics=graphics, app=new(AppState)}
    SetPropW(hwnd, utf8_to_wstring("SQ"), auto_cast window)

    window.graphics.scale = get_window_scale(hwnd)

    ShowWindow(hwnd, SW_RESTORE)

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