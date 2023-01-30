package skia

import c_ "core:c"
foreign import sklib "skia:skia.lib"


SkPaint :: distinct rawptr
SkCanvas :: distinct rawptr
SkColorSpace :: distinct rawptr
SkSurface :: distinct rawptr
SkSurfaceProps :: distinct rawptr
SkImageInfo :: distinct [size_of_SkImageInfo]u8
SkColor :: c_.uint32_t
SkScalar :: c_.float

SkRect :: struct {
	left: c_.float,
	top: c_.float,
	right: c_.float,
	bottom: c_.float,
}

SkColorType :: enum c_.int {
	BGRA_8888=6,
}

SkAlphaType :: enum c_.int {
	unknown=0,
	opaque,
	premul,
	unpremul,
}

@(default_calling_convention="c", link_prefix="sk_")
foreign sklib {
	refcnt_ref :: proc(rawptr) ---
	refcnt_unref :: proc(rawptr) ---

	surface_get_canvas :: proc(SkSurface) -> SkCanvas ---
	surface_flush :: proc(SkSurface) ---

	canvas_clear :: proc(SkCanvas, SkColor) ---
	canvas_draw_circle :: proc(SkCanvas, SkScalar, SkScalar, SkScalar, SkPaint) ---
	canvas_draw_rect :: proc(SkCanvas, SkRect, SkPaint) ---

	// paint_new :: proc() -> SkPaint ---
	paint_init :: proc(SkPaint) -> SkPaint ---
	paint_deinit :: proc(SkPaint) ---
	paint_set_colour :: proc(SkPaint, SkColor) ---

	imageinfo_init :: proc(SkImageInfo) -> SkImageInfo ---
	imageinfo_deinit :: proc(SkImageInfo) ---
	imageinfo_make :: proc(c_.int, c_.int, SkColorType, SkAlphaType, SkColorSpace) -> SkImageInfo ---
	surface_make_raster_direct :: proc(^SkImageInfo, rawptr, c_.size_t, SkSurfaceProps) -> SkSurface ---
}