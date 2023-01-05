const std = @import("std");
const assert = std.debug.assert;

// integer division by power of 2 rounding up
pub inline fn shift_right_rounding_up(
    x: anytype, comptime n: anytype) @TypeOf(x) {
    const addee = comptime (1<<n)-1;
    return (x+addee)>>n;
}

const bits_per_digit_shift_number = 10;

pub inline fn bits_per_digit_scaled_up(comptime radix: usize) usize {
    const asfloat = std.math.log2(radix);
    const ret = comptime std.math.ceil(asfloat*(1<<bits_per_digit_shift_number));
    return ret;
}

// the maximum number of digits that will always fit within the integer type
pub inline fn digits_per_integer(comptime T: type, comptime radix: anytype) usize {
    const bits_per_slot = @typeInfo(T).Int.bits;
    const bits_per_digit = std.math.log2(radix);
    const res = comptime std.math.floor(bits_per_slot/bits_per_digit);
    return res;
}

// radix if each digit were fully represented by the type T and
// where each digit would map to the number of digits of digits_per_integer
pub inline fn radix_of_int(comptime T: type, comptime radix: anytype) usize {
    const res = comptime std.math.powi(radix,digits_per_integer(T, radix))
    catch {@panic("overflow/underflow");};
    return res;
}

pub fn int_array_mul_then_add(
    comptime T: type, comptime Temp: type, array: []T, coeff: Temp, increment: Temp) void {
    const count = array.len;
    const type_nbits = @typeInfo(T).Int.bits;

    // multiply
    var carry: Temp = 0;
    var i = count-1;
    while (0<=i) : (i-=1) {
        const product = coeff * array[i] + carry;
        array[i] = @truncate(T,product);
        carry = product >> type_nbits;
    }

    // add
    carry = increment;
    i = count-1;
    while (0<=i) : (i-=1) {
        const sum = array[i] + carry;
        array[i] = @truncate(T, sum);
        carry = sum >> type_nbits;
    }
}

pub fn int_str_to_array(comptime slot_type: type, str: []u8, radix: u8, allocator: Allocator) ![]slot_type {
    // may get overflow if exceeding some unknown limit
    const ndigits = str.len;
    if (ndigits>100) return error.TooLong;
    if (radix>16) return error.RadixTooBig;

    // setup types
    comptime const slot_bits = @typeInfo(slot_type).Int.bits;
    assert(@typeInfo(slot_type).Int.signedness == .unsigned);
    comptime const slot_bits_pow = std.math.log2_int(slot_bits);
    assert(slot_bits<(65535/2)); // ensure space for the double int type
    const double_type = @Type(std.builtin.Type.Int {.bits = 2*slot_bits, .signedness = .unsigned});

    // estimate upper bound for number of bytes to allocate
    const max_bits =
     shift_right_rounding_up(
        (ndigits*bits_per_digit_scaled_up(radix)),
        bits_per_digit_shift_number);
    const slot_count1 = shift_right_rounding_up(max_bits, slot_bits_pow);

    var slots1 = try allocator.alloc(slot_type, slot_count1);

    // process the potentially non-full-sized segment
    const digits_per_slot = digits_per_integer(slot_type, radix);
    var seg1_len = ndigits % digits_per_slot;
    if (seg1_len==0) seg1_len=digits_per_slot; // fits perfectly, seg is full-sized
    const seg1 = str[0..seg1_len];
    const slot1 = std.fmt.parseInt(slot_type, seg, radix) 
        catch {@panic("failed to parse int");};
    // assign to least significant slot
    slots1[slot_count1-1] = slot1;
    
    // process segments of digits from left to right.
    const super_radix = radix_of_int(slot_type, radix);
    var i = seg1_len;
    while (i<ndigits) {
        const seg_len = digits_per_slot;
        const seg = str[i..i+seg_len];
        const slot: slot_type = std.fmt.parseInt(slot_type, seg, radix) 
        catch {@panic("failed to parse int");};
        int_array_mul_then_add(type, double_type, slots1, super_radix, slot);
        
        i+=seg_len;
    }
    var n_zero_slots = 0;
    for (slots1) |slot| {
        if (slot == 0) {
            n_zero_slots += 1;
        } else {
            break;
        }
    }
    if (n_zero_slots==0) return slots1;
    const slots2 = try allocator.dupe(slot_type, slot, slots1[n_zero_slots..slot_count1]);
    allocator.free(slots1);
    return slots2;
}