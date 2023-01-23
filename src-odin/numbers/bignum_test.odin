package numbers

import "core:fmt"
import "core:testing"

expect :: testing.expect
expect_value :: testing.expect_value
// println :: fmt.println

@(test)
test_bignums :: proc(t: ^testing.T) {
	expect(t, 1==shift_right_rounding_up(8, 3))
	expect(t, 3402==bits_per_digit_scaled_up(10))
	expect(t, 9==digits_per_integer(31, 10))
	expect(t, 9==digits_per_integer(32, 10))
	expect(t, 18==digits_per_integer(63, 10))
	expect(t, 19==digits_per_integer(64, 10))
	expect_value(t, radix_of_int(32, 10), 0x3b9aca00)
	expect_value(t, radix_of_int(64, 10), 0x8AC7230489E80000)

	mag1 := int_str_to_mag(u64, u128, "0", 10)
	expect_value(t, len(mag1), 0)

	mag2 := int_str_to_mag(u64, u128, "10", 10)
	expect_value(t, len(mag2), 1)
	expect_value(t, mag2[0], 10)

	mag3 := int_str_to_mag(u64, u128, "18446744073709551615", 10)
	expect_value(t, len(mag3), 1)
	expect_value(t, mag3[0], 18446744073709551615)

	mag4 := int_str_to_mag(u64, u128, "18446744073709551616", 10)
	expect_value(t, len(mag4), 2)
	expect_value(t, mag4[0], 1)
	expect_value(t, mag4[1], 0)

}

// @(test)
// run_tests :: proc(t: ^testing.T) {
// 	test_bignums(t)
// }