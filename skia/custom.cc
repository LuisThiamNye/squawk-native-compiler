#include "bindings.cc"
#include "include/core/SkScalar.h"
#include <include/core/SkColorSpace.h>
#include <include/core/SkImageInfo.h>
#include <include/core/SkColorType.h>
#include <include/core/SkSurface.h>
#include <include/core/SkCanvas.h>

extern "C" {

SkImageInfo sk_imageinfo_make(int width, int height, SkColorType ct, SkAlphaType at, SkColorSpace* cs) {
	return SkImageInfo::Make(width, height, ct, at, sk_ref_sp<SkColorSpace>(cs));
}

SkSurface* sk_surface_make_raster_direct(SkImageInfo* imageinfo, void* pixles, size_t rowBytes, SkSurfaceProps* surfaceProps) {
	return SkSurface::MakeRasterDirect(*imageinfo, pixles, rowBytes, surfaceProps).release();
}

}

#include <include/core/SkTextBlob.h>
extern "C" {

SkTextBlob* sk_textblob_make_from_text(void* a0, size_t a1, SkFont* a2, SkTextEncoding a3){
	return SkTextBlob::MakeFromText(a0,a1,*a2,a3).release();}

// void sk_canvas_draw_text_blob(SkCanvas* s, SkTextBlob* blob, SkScalar x, SkScalar y, SkPaint* p) {
// 	sk_sp<SkTextBlob> ref = sk_ref_sp<SkTextBlob>(blob);
// 	s->drawTextBlob(ref, x, y, *p);
// 	// ref.release();
// }

SkFont* sk_font_init(SkFont* s, SkTypeface* t, SkScalar size) {
	sk_sp<SkTypeface> ref = sk_ref_sp<SkTypeface>(t);
	SkFont* ret = new(s)SkFont(ref, size);
	// ref.release();
	return ret;
}

SkTypeface* sk_typeface_make_default() {
	return SkTypeface::MakeDefault().release();
}

SkTypeface* sk_typeface_make_from_name(char n[], SkFontStyle style) {
	return SkTypeface::MakeFromName("Consolas", style).release();
}

}