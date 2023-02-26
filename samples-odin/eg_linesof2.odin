package main

import "core:mem"
import "core:fmt"
import "core:strings"
import win "core:sys/windows"

Wstring :: ^u16

str_to_path_wstr :: proc(input: string) -> Wstring {
	using win
	wcount := MAX_PATH
	if wcount==0 {
		panic("failed to convert")
	}
	wstr := cast(Wstring) mem.alloc(wcount*2)
	MultiByteToWideChar(
		CP_UTF8, 0, raw_data(input), cast(i32) len(input), wstr, cast(i32) wcount)
	return wstr
}

wstr_to_str :: proc(input: Wstring, length: i64) -> string{
	using win
	bcount :=
		WideCharToMultiByte(
			CP_UTF8, 0, input, cast(i32) length, nil, 0, nil, nil)
	if bcount==0 {
		panic("failed to convert")
	}
	data := cast(^u8) mem.alloc(cast(int) bcount)
	WideCharToMultiByte(
		CP_UTF8, 0, input, cast(i32) length, data, bcount, nil, nil)
	bstr := strings.string_from_ptr(data, cast(int) bcount)
	return bstr
}

main :: proc() {
	using win
	dir := "."

	// Problem: MAX_PATH may be exceeded on some systems
	search_dir_w : [MAX_PATH]u16

	file_data : WIN32_FIND_DATAW
	// dir_w := str_to_path_wstr(dir)

	depth := 0
	for {
		finder := FindFirstFileW(&search_dir_w, &file_data)
		if INVALID_HANDLE_VALUE == finder {
			if GetLastError()==ERROR_FILE_NOT_FOUND {
				if depth==0 {
					break
				}

				depth -= 1
				continue
			}
			panic("failed to find first file")
		}
	
		file_w := cast(^u16) &file_data.cFileName
		name := wstr_to_str(file_w, cast(i64) MAX_PATH)
		if 0<(FILE_ATTRIBUTE_DIRECTORY & file_data.dwFileAttributes) {
			fmt.println("Directory:", name)
			dir_w^ = file_w^
			depth += 1
			continue
		} else {
			fmt.println("File:", name)
		}
		break
	}
}