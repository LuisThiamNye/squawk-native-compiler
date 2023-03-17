package rope

import "core:fmt"

println_rope :: proc(rope: ^RopeNode) {
	print_rope(rope)
	fmt.println()
}
print_rope :: proc(rope: ^RopeNode) {
	// fmt.println("rope.count =", rope.count)
	// if rope.count<0 {
	// 	fmt.println("rope.str =", string(rope.str))
	// } else {
	// 	fmt.println("rope.left = {")
	// 	println_rope(rope.left)
	// 	fmt.println("}")
	// 	fmt.println("rope.right = {")
	// 	println_rope(rope.right)
	// 	fmt.println("}")
	// }

	if rope.count==-1 {
		fmt.printf("\"%v\"", string(rope.str))
	} else {
		fmt.print("[")
		fmt.print(rope.count)
		fmt.print(" ")
		print_rope(rope.left)
		fmt.print(" ")
		print_rope(rope.right)
		fmt.print("]")
	}
}

rope_investigation :: proc() {
	/*{ // Append test
		rope := of_string("")
		fmt.println("Rope:")
		fmt.println("rope.count =", rope.count)
		fmt.println("rope.str =", string(rope.str))
	
		fmt.println("\nAppend 'ab'")
		insert_text(&rope, get_count(rope), "ab")
		println_rope(&rope)
	
		// fmt.println("\nAppend 'b'")
		// insert_text(&rope, get_count(rope), "b")
		// println_rope(&rope)
	
		fmt.println("Total count:", get_count(rope))
		fmt.println("\nPop")
		remove_range(&rope, get_count(rope)-1, get_count(rope))
		println_rope(&rope)
	}*/

	// insert test
	{
		rope := of_string("**")
		println_rope(&rope)
	
		fmt.println("\nInsert 'x' at 1")
		insert_text(&rope, 1, "x")
		println_rope(&rope)
	
		fmt.println("\nRemove range [1, 1]")
		remove_range(&rope, 1, 2)
		println_rope(&rope)
	}

	{ // Append delete within test
		fmt.println("Rope:")
		rope := of_string("x")
		println_rope(&rope)
	
		fmt.println("\nAppend 'a'")
		insert_text(&rope, get_count(rope), "a")
		println_rope(&rope)

		fmt.println("\nAppend 'b'")
		insert_text(&rope, get_count(rope), "b")
		println_rope(&rope)
	
		fmt.println("\nRemove range [1, 1]")
		remove_range(&rope, 1, 2)
		println_rope(&rope)
	}

	{ // Unicode
		fmt.println("Rope for Λ")
		rope := of_string("Λ")
		println_rope(&rope)

		fmt.println("to string:", to_string(&rope))
	
		fmt.println("\nAppend →")
		insert_text(&rope, get_count(rope), "→")
		println_rope(&rope)

		fmt.println("to string:", to_string(&rope))
	}
}