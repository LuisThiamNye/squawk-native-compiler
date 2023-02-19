package dyncall

// Note: C's int could be 32 or 64 bits depending
// on how the library was compiled.
// Dyncall "encapsulates function call invocation semantics that
// depend on the compiler, operating system and architectur".
// Parameter types get promoted according to the calling convention.

foreign import dyncall_lib "dyncall_s.lib"

DCCallVM :: distinct rawptr
DCaggr :: distinct rawptr

/* Supported Calling Convention Modes */

/* default */
CALL_C_DEFAULT ::            0   /* C default (platform native) */
CALL_C_DEFAULT_THIS ::      99   /* for C++ calls where first param is hidden this ptr (platform native) */
CALL_C_ELLIPSIS ::         100   /* to be set for vararg calls' non-hidden (e.g. C++ this ptr), named arguments */
CALL_C_ELLIPSIS_VARARGS :: 101   /* to be set for vararg calls' non-hidden (e.g. C++ this ptr), variable arguments (in ... part) */
/* platform specific */
CALL_C_X86_CDECL ::          1
CALL_C_X86_WIN32_STD ::      2
CALL_C_X86_WIN32_FAST_MS ::  3
CALL_C_X86_WIN32_FAST_GNU :: 4
CALL_C_X86_WIN32_THIS_MS ::  5
CALL_C_X86_WIN32_THIS_GNU :: CALL_C_X86_CDECL /* alias - identical to cdecl (w/ this-ptr as 1st arg) */
CALL_C_X64_WIN64 ::          7
CALL_C_X64_WIN64_THIS ::    70   /* only needed when using aggregate by value as return type */
CALL_C_X64_SYSV ::           8
CALL_C_X64_SYSV_THIS ::      CALL_C_X64_SYSV  /* alias */
CALL_C_PPC32_DARWIN ::       9
CALL_C_PPC32_OSX ::         CALL_C_PPC32_DARWIN /* alias */
CALL_C_ARM_ARM_EABI ::      10
CALL_C_ARM_THUMB_EABI ::    11
CALL_C_ARM_ARMHF ::         30
CALL_C_MIPS32_EABI ::       12
CALL_C_MIPS32_PSPSDK ::     CALL_C_MIPS32_EABI /* alias - deprecated. */
CALL_C_PPC32_SYSV ::        13
CALL_C_PPC32_LINUX ::       CALL_C_PPC32_SYSV /* alias */
CALL_C_ARM_ARM ::           14
CALL_C_ARM_THUMB ::         15
CALL_C_MIPS32_O32 ::        16
CALL_C_MIPS64_N32 ::        17
CALL_C_MIPS64_N64 ::        18
CALL_C_X86_PLAN9 ::         19
CALL_C_SPARC32 ::           20
CALL_C_SPARC64 ::           21
CALL_C_ARM64 ::             22
CALL_C_PPC64 ::             23
CALL_C_PPC64_LINUX ::       CALL_C_PPC64 /* alias */
/* syscalls, default */
CALL_SYS_DEFAULT ::        200
/* syscalls, platform specific */
CALL_SYS_X86_INT80H_LINUX::201
CALL_SYS_X86_INT80H_BSD::  202
CALL_SYS_X64_SYSCALL_SYSV::204
CALL_SYS_PPC32::           210
CALL_SYS_PPC64::           211

/* Error codes. */

ERROR_NONE ::              0
ERROR_UNSUPPORTED_MODE :: -1

@(default_calling_convention="c", link_prefix="dc")
foreign dyncall_lib {

	NewCallVM     :: proc(size: DCsize) -> DCCallVM ---
	Free          :: proc(vm: DCCallVM) ---
	Reset         :: proc(vm: DCCallVM) ---

	Mode          :: proc(vm: DCCallVM, mode: DCint) ---

	BeginCallAggr :: proc(vm: DCCallVM, ag: DCaggr) ---

	ArgBool       :: proc(vm: DCCallVM, value: bool    ) ---
	ArgChar       :: proc(vm: DCCallVM, value: DCchar    ) ---
	ArgShort      :: proc(vm: DCCallVM, value: DCshort   ) ---
	ArgInt        :: proc(vm: DCCallVM, value: DCint     ) ---
	ArgLong       :: proc(vm: DCCallVM, value: DClong    ) ---
	ArgLongLong   :: proc(vm: DCCallVM, value: DClonglong) ---
	ArgFloat      :: proc(vm: DCCallVM, value: DCfloat   ) ---
	ArgDouble     :: proc(vm: DCCallVM, value: DCdouble  ) ---
	ArgPointer    :: proc(vm: DCCallVM, value: rawptr ) ---
	ArgAggr       :: proc(vm: DCCallVM, ag: DCaggr, value: rawptr) ---

	CallVoid      :: proc(vm: DCCallVM, funcptr: rawptr) ---
	CallBool      :: proc(vm: DCCallVM, funcptr: rawptr) -> bool ---
	CallChar      :: proc(vm: DCCallVM, funcptr: rawptr) -> DCchar ---
	CallShort     :: proc(vm: DCCallVM, funcptr: rawptr) -> DCshort ---
	CallInt       :: proc(vm: DCCallVM, funcptr: rawptr) -> DCint ---
	CallLong      :: proc(vm: DCCallVM, funcptr: rawptr) -> DClong ---
	CallLongLong  :: proc(vm: DCCallVM, funcptr: rawptr) -> DClonglong ---
	CallFloat     :: proc(vm: DCCallVM, funcptr: rawptr) -> DCfloat ---
	CallDouble    :: proc(vm: DCCallVM, funcptr: rawptr) -> DCdouble ---
	CallPointer   :: proc(vm: DCCallVM, funcptr: rawptr) -> rawptr ---
	/* retval is written to *ret, returns ret */
	CallAggr      :: proc(vm: DCCallVM, funcptr: rawptr, ag: DCaggr, ret: rawptr) -> rawptr ---

	GetError      :: proc(vm: DCCallVM) -> DCint ---

	NewAggr       :: proc(maxFieldCount: DCsize, size: DCsize) -> DCaggr ---
	FreeAggr      :: proc(ag: DCaggr) ---
	/* if type == DC_SIGCHAR_AGGREGATE, pass DCaggr* of nested struct/union in ...  */
	AggrField     :: proc(ag: DCaggr, type: DCsigchar, offset: DCint, array_len: ..DCsize) ---
	CloseAggr     :: proc(ag: DCaggr) ---   /* to indicate end of struct definition, required */	
}

// Types

import c_ "core:c"

DCchar :: c_.char
DCuchar :: c_.uchar
DCshort :: c_.short
DCushort :: c_.ushort
DCint :: c_.int
DCuint :: c_.uint
DClong :: c_.long
DCulong :: c_.ulong
DClonglong :: c_.longlong
DCulonglong :: c_.ulonglong
DCfloat :: c_.float
DCdouble :: c_.double
DCstring :: cstring
DCsize :: c_.size_t

// dyncall signature

DCsigchar :: c_.char

SIGCHAR_VOID ::         'v'
SIGCHAR_BOOL ::         'B'
SIGCHAR_CHAR ::         'c'
SIGCHAR_UCHAR ::        'C'
SIGCHAR_SHORT ::        's'
SIGCHAR_USHORT ::       'S'
SIGCHAR_INT ::          'i'
SIGCHAR_UINT ::         'I'
SIGCHAR_LONG ::         'j'
SIGCHAR_ULONG ::        'J'
SIGCHAR_LONGLONG ::     'l'
SIGCHAR_ULONGLONG ::    'L'
SIGCHAR_FLOAT ::        'f'
SIGCHAR_DOUBLE ::       'd'
SIGCHAR_POINTER ::      'p' /* also used for arrays, as such args decay to ptrs */
SIGCHAR_STRING ::       'Z' /* in theory same as 'p', but convenient to disambiguate */
SIGCHAR_AGGREGATE ::    'A' /* aggregate (struct/union described out-of-band via DCaggr) */
SIGCHAR_ENDARG ::       ')'

/* calling convention / mode signatures */

SIGCHAR_CC_PREFIX ::           '_' /* announces next char to be one of the below calling convention mode chars */
SIGCHAR_CC_DEFAULT ::          ':' /* default calling conv (platform native) */
SIGCHAR_CC_THISCALL ::         '*' /* C++ this calls (platform native) */
SIGCHAR_CC_ELLIPSIS ::         'e'
SIGCHAR_CC_ELLIPSIS_VARARGS :: '.'
SIGCHAR_CC_CDECL ::            'c' /* x86 specific */
SIGCHAR_CC_STDCALL ::          's' /* x86 specific */
SIGCHAR_CC_FASTCALL_MS ::      'F' /* x86 specific */
SIGCHAR_CC_FASTCALL_GNU ::     'f' /* x86 specific */
SIGCHAR_CC_THISCALL_MS ::      '+' /* x86 specific, MS C++ this calls */
SIGCHAR_CC_THISCALL_GNU ::     '#' /* x86 specific, GNU C++ this calls are cdecl, but keep specific sig char for clarity */
SIGCHAR_CC_ARM_ARM ::          'A'
SIGCHAR_CC_ARM_THUMB ::        'a'
SIGCHAR_CC_SYSCALL ::          '$'



/*
Bindings adapted from header files of dyncall library with the license:

   Copyright (c) 2007-2022 Daniel Adler <dadler@uni-goettingen.de>,
                           Tassilo Philipp <tphilipp@potion-studios.com>

   Permission to use, copy, modify, and distribute this software for any
   purpose with or without fee is hereby granted, provided that the above
   copyright notice and this permission notice appear in all copies.

   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

*/