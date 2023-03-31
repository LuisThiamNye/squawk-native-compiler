package vis

import "core:runtime"
import "core:intrinsics"
import "core:strings"
import "core:slice"

clone_slice :: proc(src: []$E, allocator := context.allocator) -> (dst: []E, err: runtime.Allocator_Error) #optional_allocator_error {
	n := len(src)
	if n==0 {return}
	dst = make([]E, n, allocator)
	intrinsics.mem_copy_non_overlapping(raw_data(dst), raw_data(src), n*size_of(E))
	return
}

clone_string :: proc(src: string, allocator := context.allocator) -> (dst: string, err: runtime.Allocator_Error) #optional_allocator_error {
	r, e := clone_slice(transmute([]u8) src)
	dst = string(r)
	err = e
	return
}

append_new :: #force_inline proc(array: ^[dynamic]$E) -> ^E {
	append_nothing(array)
	return &array[len(array)-1]
}

slice_equal :: proc(s1: []$A, s2: []$B) -> bool {
	if len(s1)==0 && len(s2)==0 {return true}
	return slice.equal(s1, s2)
}


Key :: enum {
	// windows virtual key codes
	lbutton = 1,
	rbutton,
	cancel,
	middle_button,
	x1_button,
	x2_button,
	backspace = 0x8,
	tab,
	clear = 0xc,
	enter,
	shift = 0x10,
	control,
	alt,
	pause,
	caps_lock,
	kana,
	hanguel,
	ime_on,
	junja,
	final,
	hanja = 0x19,
	kanji = 0x19,
	ime_off,
	escape,
	convert,
	nonconvert,
	accept,
	mode_change,
	space,
	page_up,
	page_down,
	end,
	home,
	left_arrow,
	up_arrow,
	right_arrow,
	down_arrow,
	select,
	print,
	execute,
	print_screen,
	insert,
	delete,
	help,
	n0,
	n1,
	n2,
	n3,
	n4,
	n5,
	n6,
	n7,
	n8,
	n9,
	a = 0x41,
	b,
	c,
	d,
	e,
	f,
	g,
	h,
	i,
	j,
	k,
	l,
	m,
	n,
	o,
	p,
	q,
	r,
	s,
	t,
	u,
	v,
	w,
	x,
	y,
	z,
	lwin,
	rwin,
	apps,
	sleep = 0x5,
	keypad0,
	keypad1,
	keypad2,
	keypad3,
	keypad4,
	keypad5,
	keypad6,
	keypad7,
	keypad8,
	keypad9,
	multiply,
	add,
	separator,
	subtract,
	decimal,
	divide,
	f1,
	f2,
	f3,
	f4,
	f5,
	f6,
	f7,
	f8,
	f9,
	f10,
	f11,
	f12,
	f13,
	f14,
	f15,
	f16,
	f17,
	f18,
	f19,
	f20,
	f21,
	f22,
	f23,
	f24,
	num_lock = 0x90,
	scroll_lock,
	lshift = 0xa0,
	rshift,
	lcontrol,
	rcontrol,
	lalt,
	ralt,

}