package vis

import win "core:sys/windows"

foreign import user32 "system:User32.lib"
foreign import shcore "system:Shcore.lib"

@(default_calling_convention="stdcall")
foreign user32 {
	GetPropW :: proc(win.HWND, win.LPCWSTR) -> win.HANDLE ---
	SetPropW :: proc(win.HWND, win.LPCWSTR, win.HANDLE) ---

  OpenClipboard :: proc(win.HWND) -> bool ---
  CloseClipboard :: proc() -> bool ---
  SetClipboardData :: proc(format: win.UINT, mem: win.HANDLE) -> win.HANDLE ---
  IsClipboardFormatAvailable :: proc(format: win.UINT) -> bool ---
  GetClipboardData :: proc(format: win.UINT) -> win.HANDLE ---

  GlobalAlloc :: proc(flags: win.UINT, bytes: win.SIZE_T) -> win.HGLOBAL ---
  GlobalLock :: proc(memory: win.HGLOBAL) -> rawptr ---
  GlobalUnlock :: proc(memory: win.HGLOBAL) -> bool ---
}
foreign shcore {
	GetScaleFactorForMonitor :: proc(win.HMONITOR, ^DEVICE_SCALE_FACTOR) ---
}

Device_Scale_Factor :: enum {
  DEVICE_SCALE_FACTOR_INVALID = 0,
  SCALE_100_PERCENT = 100,
  SCALE_120_PERCENT = 120,
  SCALE_125_PERCENT = 125,
  SCALE_140_PERCENT = 140,
  SCALE_150_PERCENT = 150,
  SCALE_160_PERCENT = 160,
  SCALE_175_PERCENT = 175,
  SCALE_180_PERCENT = 180,
  SCALE_200_PERCENT = 200,
  SCALE_225_PERCENT = 225,
  SCALE_250_PERCENT = 250,
  SCALE_300_PERCENT = 300,
  SCALE_350_PERCENT = 350,
  SCALE_400_PERCENT = 400,
  SCALE_450_PERCENT = 450,
  SCALE_500_PERCENT = 500,
}
DEVICE_SCALE_FACTOR :: Device_Scale_Factor