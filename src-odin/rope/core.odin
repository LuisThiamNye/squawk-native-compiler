package rope


import "core:fmt"
import "core:mem"


RopeNode :: struct {
	count: int, // -1 if leaf node
	using value: struct #raw_union {
		str: []u8, // leaf
		using children: struct {
			left: ^RopeNode,
			right: ^RopeNode,
		},
	},
}

of_string :: proc(str: string) -> RopeNode {
	node : RopeNode
	node.str = make([]u8, len(str))
	copy(node.str, str)
	node.count = -1
	return node
}

delete_rope :: proc(node: RopeNode, allocator:=context.allocator) {
	if node.count<0 {
		delete(node.str, allocator)
	} else {
		if node.left!=nil {free_rope(node.left, allocator)}
		if node.right!=nil {free_rope(node.right, allocator)}
	}
}

free_rope :: proc(node: ^RopeNode, allocator:=context.allocator) {
	delete_rope(node^)
	free(node, allocator)
}

// `right` is consumed; result is `left`
concat_right :: proc(left: ^RopeNode, right: ^RopeNode) {
	balance_node(left)
	left2 := new_clone(left^)
	left.left = left2
	left.right = right
	left.count = get_count(left2) + get_count(right)
	balance_node(left)
	assert_rope(left)
}
// `left` is consumed; result is `right`
concat_left :: proc(left: ^RopeNode, right: ^RopeNode) {
	balance_node(right)
	right2 := new_clone(right^)
	right.left = left
	right.right = right2
	right.count = get_count(right2) + get_count(left)
	balance_node(right)
	assert_rope(right)
}

// take a slice starting at index `start`
right_slice :: proc(node: ^RopeNode, start: int, allocator:=context.allocator) {
	if start==0 {

	} else if node.count<0 { // leaf
		if start==len(node.str) { // delete entire string
			delete(node.str, allocator)
			node.str = {}
		} else { // slice
			node.str = slice_resize(node.str, start, len(node.str))
		}

	} else if start==node.count { // compound, delete entire string
		free_rope(node.left, allocator)
		free_rope(node.right, allocator)
		node^ = {}
		node.count = -1
		assert_rope(node)

	} else { // compound, slice
		node.count -= start
		lcount := get_count(node.left)
		if lcount <= start {
			free_rope(node.left, allocator)
			right := node.right
			right_slice(right, start-lcount)
			node^ = right^
			free(right, allocator)
			assert_rope(node)
		} else {
			right_slice(node.left, start)
			assert_rope(node)
		}
	}
}

// end is exclusive
left_slice :: proc(node: ^RopeNode, end: int, allocator:=context.allocator) {
	assert_rope(node)
	if end==0 { // delete entire node
		delete_rope(node^, allocator)
		node^ = {}
		node.count = -1
		assert_rope(node)

	} else if node.count<0 { // leaf
		if end < len(node.str) {
			node.str = slice_resize(node.str, 0, end)
			assert_rope(node)
		}

	} else if end < node.count { // compound, slice
		node.count = end
		lcount := get_count(node.left)
		if end <= lcount {
			left := node.left
			free_rope(node.right, allocator)
			left_slice(left, end)
			node^ = left^
			free(left, allocator)
			assert_rope(node)
		} else {
			left_slice(node.right, end-lcount)
			assert_rope(node)
		}
	}
}

slice :: proc(node: ^RopeNode, start: int, end: int, allocator:=context.allocator) {
	left_slice(node, end, allocator)
	right_slice(node, start, allocator)
}

get_count :: proc{get_count__p, get_count__v}
get_count__p :: #force_inline proc(node: ^RopeNode, allocator:=context.allocator) -> int {
	return get_count__v(node^, allocator)
}
get_count__v :: #force_inline proc(node: RopeNode, allocator:=context.allocator) -> int {
	if node.count<0 {
		return len(node.str)
	} else {
		return node.count
	}
}

at :: proc(node: ^RopeNode, idx: int) -> u8 {
	if node.count<0 {
		return node.str[idx]
	} else {
		lcount := get_count(node.left)
		if idx<lcount {
			return at(node.left, idx)
		} else {
			return at(node.right, idx-lcount)
		}
	}
}

remove_range :: proc(node: ^RopeNode, start: int, end: int, allocator:=context.allocator) {
	assert_rope(node)
	if start==0 {
		right_slice(node, end, allocator)
		assert_rope(node)
	} else if end==get_count(node) {
		left_slice(node, start, allocator)
		assert_rope(node)
	} else {
		if node.count<0 {
			node.str = slice_remove_range(node.str, start, end, allocator)
		} else {
			lcount := get_count(node.left)
			if end<=lcount {
				remove_range(node.left, start, end, allocator)
				node.count=get_count(node.left)+get_count(node.right)
			} else if start>=lcount {
				remove_range(node.right, start-lcount, end-lcount, allocator)
				node.count=lcount+get_count(node.right)
			} else {
				right_slice(node.left, start, allocator)
				left_slice(node.right, end-lcount, allocator)
				node.count=get_count(node.left)+get_count(node.right)
			}
			assert_rope(node)
		}
	}
}

import "core:strings"

slice_resize :: proc(array: []$E, start: int, end: int, allocator := context.allocator) -> []E {
	n2 := end-start
	new_array := make([]E, n2, allocator)
	defer delete(array, allocator)
	copy(new_array, array[start:end])
	return new_array
}

slice_remove_range :: proc(array: []$E, start: int, end: int, allocator := context.allocator) -> []E {
	n1 := len(array)
	n2 := n1-(end-start)
	new_array := make([]E, n2, allocator)
	defer delete(array, allocator)
	copy(new_array, array[:start])
	if end<len(array) {copy(new_array[start:], array[end:])}
	fmt.println(">>>", array)
	fmt.println(new_array)
	// new_data := mem.resize(ptr=raw_data(array), old_size=n1, new_size=n2, allocator=allocator)
	// new_array := mem.slice_ptr(cast(^E) new_data, n2)
	return new_array
}

slice_inject_at :: proc(array: ^[]$E, index: int, extra: $A, allocator:=context.allocator) {
	s2 := make([]E, len(array)+len(extra), allocator)
	copy(s2, array[:index])
	copy(s2[index:], extra)
	if index<len(array) {
		copy(s2[index+len(extra):], array[index:])
	}
	delete(array^, allocator)
	array^ = s2
}

slice_append :: proc(array: []$E, extra: $A, allocator:=context.allocator) -> []E {
	s2 := make([]E, len(array)+len(extra), allocator)
	copy(s2, array)
	copy(s2[len(array):], extra)
	delete(array, allocator)
	return s2
}

slice_pop :: proc(array: ^[]$E, allocator:=context.allocator) {
	s2 := make([]E, len(array)-1, allocator)
	copy(s2, array[:len(array)-1])
	delete(array^, allocator)
	array^ = s2
}

insert_text :: proc(node: ^RopeNode, index: int, text: string, allocator:=context.allocator) {
	assert_rope(node)
	if len(text)==0 {return}

	if index==0 {
		left := new(RopeNode)
		left^ = of_string(strings.clone(text))
		concat_left(left, node)
	} else if index==get_count(node) {
		right := new(RopeNode)
		right^ = of_string(strings.clone(text))
		concat_right(node, right)
	} else {
		if node.count<0 {
			slice_inject_at(&node.str, index, text, allocator)
		} else {
			lcount := get_count(node.left)
			if index<=lcount {
				insert_text(node.left, index, text)
				node.count=get_count(node.left)+get_count(node.right)
			} else {
				insert_text(node.right, index-lcount, text)
				node.count=lcount+get_count(node.right)
			}
		}
	}
	assert_rope(node)
}

max_leaf_string_count :: 4//64

rebalance_threshold :: 1//16

balance_node :: proc(node: ^RopeNode, allocator:=context.allocator) {
	if node.count==-1 {return}
	left := node.left
	right := node.right
	left_leaf := left.count == -1
	right_leaf := right.count == -1

	if left_leaf && right_leaf && node.count<=max_leaf_string_count {
		left.str = slice_append(node.left.str, node.right.str, allocator)
		node^ = left^
		free(left, allocator)
		free_rope(right, allocator)

	} else {
		left_excess := get_count(left) - get_count(right)
		if left_excess > rebalance_threshold { // left -> right
			if left.count==-1 {return}
			concat_left(left.right, right)
			node.left = left.left

		} else if -left_excess > rebalance_threshold { // left <- right
			if right.count==-1 {return}
			concat_right(left, right.left)
			node.right = right.right
		}
	}
}

RopeByteIterator_Frame :: struct {
	rope: ^RopeNode,
	count: int,
	cur: int,
}

RopeByteIterator :: struct {
	stack: [dynamic]RopeByteIterator_Frame,
}

byte_iterator_push_frame :: proc(it: ^RopeByteIterator, node: ^RopeNode) {
	assert(node!=nil)
	frame : RopeByteIterator_Frame
	frame.cur = -1
	frame.rope = node
	if node.count<0 {
		frame.count = len(node.str)
	} else {
		frame.count = 2
	}
	append(&it.stack, frame)
}

assert_rope :: proc(node: ^RopeNode, loc := #caller_location) {
	assert(node.count<1000, "count unreasonably high", loc)
	if node.count<0 {
		assert(node.count==-1, "bad count", loc)
	} else {
		assert(node.left != nil, "left nil", loc)
		assert(node.left != cast(rawptr) cast(uintptr) 0xfeeefeeefeeefeee, "left free", loc)
		assert(node.right != nil, "right nil", loc)	
		assert(node.right != cast(rawptr) cast(uintptr) 0xfeeefeeefeeefeee, "left free", loc)
		assert_rope(node.left, loc)
		assert_rope(node.right, loc)
	}
}

byte_iterator :: proc(node: ^RopeNode) -> RopeByteIterator {
	assert_rope(node)
	it : RopeByteIterator
	byte_iterator_push_frame(&it, node)
	return it
}

iter_next :: proc(using it: ^RopeByteIterator) -> (ret: u8, ok: bool) {
	frame := &stack[len(stack)-1]
	assert_rope(frame.rope)
	frame.cur += 1
	if frame.cur>=frame.count { // go up the stack
		if len(stack)==1 {
			ok = false
			return
		} else {
			pop(&stack)
			return iter_next(it)
		}
	} else {
		if frame.rope.count<0 {
			ret = frame.rope.str[frame.cur]
			ok = true
			return
		} else if frame.cur==0 {
			byte_iterator_push_frame(it, frame.rope.left)
			return iter_next(it)
		}	else if frame.cur==1 {
			byte_iterator_push_frame(it, frame.rope.right)
			return iter_next(it)
		} else {panic("unreachable")}
	}
}


to_string :: proc(rope: ^RopeNode) -> string {
	b := strings.builder_make()
	it := byte_iterator(rope)
	for {
		ch, ok := iter_next(&it)
		if ok {
			strings.write_byte(&b, ch)
		} else {
			return strings.to_string(b)
		}
	}
}


import "core:io"

write_rope :: proc(w: io.Writer, rope: ^RopeNode) {
	it := byte_iterator(rope)
	for {
		ch, ok := iter_next(&it)
		if ok {
			io.write_byte(w, ch)
		} else {
			return
		}
	}
}