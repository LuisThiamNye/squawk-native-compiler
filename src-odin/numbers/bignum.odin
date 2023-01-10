package numbers

import "core:fmt"
import "core:math"
import "core:intrinsics"
import "core:strconv"
import "core:runtime"
import "core:mem"

BigInt :: struct {
	magnitude: []u64,
}

// integer division by power of 2 rounding up
shift_right_rounding_up :: #force_inline proc(x: $X, n: uint) -> X {
	addee := cast(X) (1<<n)-1 // @Nextgen make constant
	return (x+addee)>>n
}

bits_per_digit_shift_number :: 10

bits_per_digit_scaled_up :: #force_inline proc($radix: u64) -> u64 {
	// @Nextgen make result a constant
	asfloat := math.log2(cast(f64) radix)
	ret := cast(u64) math.ceil(asfloat*(1<<bits_per_digit_shift_number))
	return ret
}

// the maximum number of digits that will always fit within the integer type
digits_per_integer :: #force_inline proc(bits_per_word: int, $radix: u64) -> int {
	// @Nextgen make result a constant
	bits_per_digit := math.log2(cast(f64) radix)
	res := cast(int) math.floor(cast(f64)bits_per_word / bits_per_digit)
	return res
}

// radix if each digit were fully represented by the type T and
// where each digit would map to the number of digits of digits_per_integer
radix_of_int :: #force_inline proc(bits_per_word: int, $radix: u64) -> u64 {
	// @Nextgen make result a constant
	res := math.pow(cast(f64) radix, cast(f64) digits_per_integer(bits_per_word, radix))
	return cast(u64) res
}

int_array_mul_then_add :: proc($D: typeid, bits_per_word: uint, slice: []$T, coeff: T, increment: T) {
	count := len(slice)

	// multiply
	carry : T = 0
	i := count-1
	for i>=0 {
		product := cast(D) coeff * cast(D) slice[i] + cast(D) carry
		slice[i] = cast(T) product // truncate
		carry = cast(T) (product >> bits_per_word)
		i-=1
	}

	// add
	carry = increment
	i = count-1
	for i>=0 {
		sum := cast(D) slice[i] + cast(D) carry
		slice[i] = cast(T) sum // truncate
		carry = cast(T) (sum >> bits_per_word)
		i-=1
	}
}

Type_Info_Integer :: runtime.Type_Info_Integer

int_str_to_slice :: proc($TWord: typeid, $TDouble: typeid, str: string, $radix: u64) -> []TWord
	where
		intrinsics.type_is_integer(TWord) {
		// @Nextgen make constant
		// !type_info_of(TWord).variant.(Type_Info_Integer).signed,
		// type_info_of(TDouble).size >= 2*type_info_of(TWord).size,
		// type_info_of(TWord).size <= 64
		 // {
	ndigits := len(str)
    // may get overflow if exceeding some unknown limit
	if ndigits>100 {panic("too long")}
	if radix>16 {panic("radix too big")}

	// setup types
	bits_per_word := type_info_of(TWord).size*8 // @Nextgen make constant
	word_bits_pow := math.log2(cast(f64) bits_per_word) // @Nextgen make constant

    // estimate upper bound for number of bytes to allocate
	max_bits := shift_right_rounding_up(
		cast(u64) ndigits*bits_per_digit_scaled_up(radix),
		bits_per_digit_shift_number)
	nwords1 := shift_right_rounding_up(max_bits, cast(uint) word_bits_pow)
	// fmt.println("nwords", nwords1, "max bits", max_bits, "bpw", bits_per_word)

	mag1 := make([]TWord, nwords1)

    // process the potentially non-full-sized segment
	digits_per_word := digits_per_integer(bits_per_word, radix)
	seg1_len := ndigits % digits_per_word
	if seg1_len==0 {seg1_len = digits_per_word}
	seg1 := str[0:seg1_len]
	word1, ok := strconv.parse_u64_of_base(seg1, cast(int) radix)
	if !ok {panic("failed to parse int")}
    // assign to least significant slot
	mag1[nwords1-1] = cast(TWord) word1

    // process segments of digits from left to right.
	super_radix := radix_of_int(bits_per_word, radix)
	i := seg1_len
	for i < ndigits {
		seg_len := digits_per_word
		seg := str[i:i+seg_len]
		word, ok := strconv.parse_u64_of_base(seg, cast(int) radix)
		if !ok {panic("failed to parse int")}
		int_array_mul_then_add(TDouble, cast(uint) bits_per_word, mag1, super_radix, word)

		i+=seg_len
	}
	n_zero_words := 0
	for word in mag1 {
		if (word==0) {
			n_zero_words+=1
		} else {
			break
		}
	}
	if n_zero_words == 0 {return mag1}
	// fmt.println("zeros", mag1, n_zero_words)
	new_len := len(mag1)-n_zero_words
	mem.copy(raw_data(mag1), mem.ptr_offset(raw_data(mag1), n_zero_words), new_len*8)
	mem.resize(raw_data(mag1), len(mag1), new_len)
	mag2 := mem.slice_ptr(raw_data(mag1), new_len)
	return mag2
}