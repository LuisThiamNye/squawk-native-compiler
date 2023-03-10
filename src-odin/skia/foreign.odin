package skia

import c_ "core:c"
foreign import sklib "skia:skia.lib"


SkPaint :: distinct rawptr
SkFont :: distinct rawptr
SkTextBlob :: distinct rawptr
SkTypeface :: distinct rawptr
SkFontStyle :: distinct [size_of_SkFontStyle]u8
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

SkTextEncoding :: enum u32 {
	UTF8,
	UTF16,
	UTF32,
	GlyphID,
}

SkFontStyle_Slant :: enum {
	upright,
	italic,
	oblique,
}

SkFontStyle_Weight :: enum i32 {
	invisible=0,
	thin=100,
	extra_light=200,
	light=300,
	normal=400,
	medium=500,
	semi_bold=600,
	bold=700,
	extra_bold=800,
	black=900,
	extra_black=1000,
}

SkFontStyle_Width :: enum i32 {
	ultra_condensed=1,
	extra_condensed=2,
	condensed=3,
	semi_condensed=4,
	normal=5,
	semi_expanded=6,
	expanded=7,
	extra_expanded=8,
	ultra_expanded=9,
}

SkGlyphID :: c_.uint16_t

SkFontMetrics :: struct {
	flags: bit_set[enum {
		underline_thickness_is_valid,
		underline_position_is_valid,
		strikeout_thickness_is_valid,
		strikeout_position_is_valid,
		bounds_invalid,
	}; u32],
    top: SkScalar,
    ascent: SkScalar,
    descent: SkScalar,
    bottom: SkScalar,
    leading: SkScalar,
    avg_char_width: SkScalar,
    max_char_width: SkScalar,
    x_min: SkScalar,
    x_max: SkScalar,
    x_height: SkScalar,
    cap_height: SkScalar,
    underline_thickness: SkScalar,
    underline_position: SkScalar,
    strikeout_thickness: SkScalar,
    strikeout_position: SkScalar,
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
	canvas_draw_text_blob :: proc(SkCanvas, SkTextBlob, SkScalar, SkScalar, SkPaint) ---
	canvas_save :: proc(SkCanvas) -> c_.int ---
	canvas_restore_to_count :: proc(SkCanvas, c_.int) ---
	canvas_scale :: proc(SkCanvas, c_.float, c_.float) ---
	canvas_translate :: proc(SkCanvas, c_.float, c_.float) ---
	canvas_rotate :: proc(SkCanvas, c_.float) ---
	canvas_clip_rect :: proc(cnv: SkCanvas, rect: ^SkRect, anti_alias: bool = false) ---

	// paint_new :: proc() -> SkPaint ---
	paint_init :: proc(SkPaint) -> SkPaint ---
	paint_deinit :: proc(SkPaint) ---
	paint_set_colour :: proc(SkPaint, SkColor) ---
	paint_set_stroke :: proc(SkPaint, bool) ---
	paint_set_stroke_width :: proc(SkPaint, SkScalar) ---

	imageinfo_init :: proc(SkImageInfo) -> SkImageInfo ---
	imageinfo_deinit :: proc(SkImageInfo) ---
	imageinfo_make :: proc(c_.int, c_.int, SkColorType, SkAlphaType, SkColorSpace) -> SkImageInfo ---

	surface_make_raster_direct :: proc(^SkImageInfo, rawptr, c_.size_t, SkSurfaceProps) -> SkSurface ---

	textblob_make_from_text :: proc(rawptr, c_.size_t, SkFont, SkTextEncoding) -> SkTextBlob ---

	typeface_make_default :: proc() -> SkTypeface ---
	typeface_make_from_name :: proc(cstring, SkFontStyle) -> SkTypeface ---

	fontstyle_init :: proc(^SkFontStyle, SkFontStyle_Weight, SkFontStyle_Width, SkFontStyle_Slant) -> ^SkFontStyle ---

	font_init :: proc(SkFont, SkTypeface, SkScalar) -> SkFont ---
	font_text_to_glyphs :: proc(font: SkFont, text: rawptr, nbytes: c_.size_t, encoding: SkTextEncoding, glyphs: [^]SkGlyphID, max_glyphs: c_.int) -> c_.int ---
	font_get_metrics :: proc(SkFont, ^SkFontMetrics) -> SkScalar ---
	font_measure_text :: proc(font: SkFont, text: rawptr, nbytes: c_.size_t, encoding: SkTextEncoding, bounds: ^SkRect = nil, paint: ^SkPaint = nil) -> SkScalar ---
}