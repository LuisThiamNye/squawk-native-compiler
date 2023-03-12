package main

import "core:fmt"
import "core:dynlib"
import "vis"
import "core:runtime"
import "core:os"

import dc "dyncall"

import win "core:sys/windows"

import "rope"

main :: proc() {
	win.timeBeginPeriod(1) // higher resolution timings

	win.AddVectoredExceptionHandler(1, exception_handler)

	vis.main()
	// vis.compile_sample()

	// rope.rope_investigation()

	fmt.println("Done.")
}

exception_handler :: proc "stdcall" (exinfo: ^win.EXCEPTION_POINTERS) -> win.LONG {
	context = runtime.default_context()
	using win
	er := exinfo.ExceptionRecord
	switch er.ExceptionCode {
	case EXCEPTION_DATATYPE_MISALIGNMENT,
		EXCEPTION_ACCESS_VIOLATION,
		// EXCEPTION_ILLEGAL_INSTRUCTION, // used for panics
		// EXCEPTION_ARRAY_BOUNDS_EXCEEDED,
		EXCEPTION_STACK_OVERFLOW:

		fmt.println("\n\n** SYSTEM EXCEPTION **")
		switch exinfo.ExceptionRecord.ExceptionCode {
		case EXCEPTION_DATATYPE_MISALIGNMENT:
			fmt.println("datatype misalignment")
		case EXCEPTION_ACCESS_VIOLATION:
			rw := cast(uintptr) er.ExceptionInformation[0]
			addr := er.ExceptionInformation[1]

			fmt.println("access violation:")
			switch rw {
			case 0:
				fmt.println("Read.")
			case 1:
				fmt.println("Write.")
			case 8:
				fmt.println("User-mode data execution prevention (DEP)")
			}
			fmt.print("Address: ")
			fmt.println(addr)
		case EXCEPTION_ILLEGAL_INSTRUCTION:
			fmt.println("illegal instruction")
		}
		// return EXCEPTION_EXECUTE_HANDLER
	}
	
	return EXCEPTION_CONTINUE_SEARCH
}