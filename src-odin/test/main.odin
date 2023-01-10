package test

import "core:testing"
import "../numbers"

main :: proc() {
	t := testing.T{}
	numbers.run_tests(&t)
}