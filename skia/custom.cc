#include "bindings.cc"
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