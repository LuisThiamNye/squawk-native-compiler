package rope

import "core:fmt"
import "core:testing"

@(test)
test_rope :: proc(t: ^testing.T) {
	using testing

	rope := of_string("abc")
	expect_value(t, rope.count, -1)
	expect_value(t, string(rope.str), "abc")
}
