package vis

import "core:fmt"
import "core:runtime"
import "core:mem"

import c_ "core:c"
import win "core:sys/windows"
foreign import sk "skia:skia.lib"
// foreign import "system:Opengl32.lib"

println :: fmt.println

SkPaint :: distinct rawptr
SkImageInfo :: distinct rawptr

@(default_calling_convention="c", link_prefix="sk_")
foreign sk {
	// sk_get_canvas :: proc() -> c_.size_t ---;
	paint_new :: proc() -> c_.size_t ---;
	paint_init :: proc(SkPaint) -> SkPaint ---;
	paint_deinit :: proc(SkPaint) ---;

	imageinfo_init :: proc(SkImageInfo) -> SkImageInfo ---;
	imageinfo_deinit :: proc(SkImageInfo) ---;
}

handle_window_message :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT,
	wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	using win
	context = runtime.default_context()

	switch msg {
	case WM_TIMER:
		return 0
	case WM_ENTERSIZEMOVE:
		break
	case WM_EXITSIZEMOVE:
		break
	case WM_SIZE:
		break
	case WM_MOVE:
		break
	case WM_ERASEBKGND:
        return 1
	case WM_PAINT:
		ps: PAINTSTRUCT
		if BeginPaint(hwnd, &ps) != nil {
			rect: RECT
			GetClientRect(hwnd, &rect)

			image_info := cast(SkImageInfo) mem.alloc(size_of_SkImageInfo)
			imageinfo_init(image_info)
			fmt.println("paint")

			// fill := paint_new()

			// fill := make([]u8, 100)
			// fmt.println(fill)
			// paint_init(auto_cast &fill[0])
			// fmt.println(fill)
			// paint_deinit(auto_cast &fill[0])
			// fmt.println(fill)

			EndPaint(hwnd, &ps)
		}
		break
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
	class_name := new(cstring)
	class_name^ = "SQ_WINDOW"
	wc.lpszClassName = auto_cast &class_name

	if 0 == RegisterClassExW(&wc) {
		panic("failed to register window class")
	}

	// create window

	window_name := new(cstring)
	window_name^ = "My window"
	x : i32 = 0
	y : i32 = 0
	w : i32 = 500
	h : i32 = 400
    hwnd :=
    	CreateWindowExW(0,
                        auto_cast &class_name,
                        auto_cast &window_name,
                        WS_OVERLAPPEDWINDOW | WS_CAPTION | WS_CLIPSIBLINGS | WS_CLIPCHILDREN,
                        x, y, w, h,
                        nil, nil,
                        auto_cast GetModuleHandleW(nil),
                        nil)

    if hwnd == nil {
    	panic("failed to create hwnd")
    }

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

	println("hei")
}