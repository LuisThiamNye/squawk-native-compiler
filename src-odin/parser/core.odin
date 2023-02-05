package parser

import "core:fmt"
import "core:strings"

CollType :: enum {
	list, vector, map_, set,
}

StackFrame :: struct {
	coll_type: CollType,
}

Ctx :: struct {
	next_idx: int,
	buf: []u8,
	stack: [dynamic]StackFrame,
}

MessageTag :: enum {
	none = 0,
	eof,
	error,
	newline,
	tag,
	keyword,
	symbol,
	number,
	string,
	char,
	comment,
	quote,
	meta,
	coll_start,
	coll_end,
	discard,
}

Message :: struct {
	tag: MessageTag,
	start_idx: int,
	end_idx: int,
	message: string,
	coll_type: CollType,
}

Macro :: enum {
	none = 0, string, comment, quote, meta, list, vector, map_, unmatched_delim, char, dispatch,
}

init_parser :: proc(buf: []u8) -> ^Ctx {
	ret := new(Ctx)
	ret^ = {buf=buf, stack=[dynamic]StackFrame{}}
	return ret
}

get_macro :: proc(char: u8) -> Macro {
	switch char {
	case '"': return .string
	case ';': return .comment
	case '\'': return .quote
	case '(': return .list
	case ')': return .unmatched_delim
	case '[': return .vector
	case ']': return .unmatched_delim
	case '{': return .map_
	case '}': return .unmatched_delim
	case '#': return .dispatch
	case: return .none
	}
}

whitespaceP :: proc(ch: u8) -> bool {
	return ch==' ' || ch=='\n' || ch=='\t' || ch=='\r' || ch==11 || ch==12 // vertical tab, formfeed
}

digitP :: #force_inline proc(ch: u8) -> bool {
	return '0' <= ch && ch <= '9'
}

terminating_macroP :: proc(ch: u8) -> bool {
	return ch!='#' && ch!='\'' && ch!='%' && get_macro(ch)!=.none
}

read_to_nonws :: proc(using p: ^Ctx) -> (_ch: u8, _eof: bool) {
	endx := len(buf)
	i := next_idx
	for {
		if endx == i {
			next_idx = i
			return 0, true
		}
		ch := buf[i]
		if whitespaceP(ch) && ch!='\n' {
			i+=1
			continue
		} else {
			next_idx = i
			return ch, false
		}
	}
}

read_token :: proc(using p: ^Ctx, ch0: u8) -> (end_idx: int) {
	endx := len(buf)
	i := next_idx
	for {
		if endx == i {break}
		ch := buf[i]
		if whitespaceP(ch) || terminating_macroP(ch) {
			break
		}
		i+=1
	}
	return i
}

parse_string :: proc(using p: ^Ctx) -> Message {
	endx := len(buf)
	start_idx := next_idx
	i := next_idx+1
	ret : Message
	for {
		if endx == i {
			ret = {tag=.eof}
			break
		}
		ch := buf[i]
		i+=1
		if ch=='"' {
			ret = {tag=.string, start_idx=start_idx, end_idx=i}
			break
		}
		if ch=='\\' {
			if endx<=i {
				ret = {tag=.eof}
				break
			}
			ch2 := buf[i]
			i+=1
		}
	}
	return ret
}

parse_comment :: proc(using p: ^Ctx) -> Message {
	endx := len(buf)
	i := next_idx
	start_idx := i-1
	for {
		if endx == i {break}
		ch := buf[i]
		if ch=='\n' {break}
		i+=1
	}
	return {tag=.comment, start_idx=start_idx, end_idx=i}
}

parse_coll :: proc(using p: ^Ctx, coll_type: CollType, start_idx: int) -> Message {
	append(&stack, StackFrame{coll_type=coll_type})
	length := 2 if coll_type==.set else 1
	return {tag=.coll_start, start_idx=start_idx, end_idx=next_idx+length, coll_type=coll_type}
}

error_msgf :: proc(idx: int, args: ..any) -> Message {
	sb := strings.builder_make()
	fmt.sbprint(&sb, ..args)
	return {tag=.error, start_idx=idx, message=strings.to_string(sb)}
}

eofP :: #force_inline proc(using p: ^Ctx) -> bool {
	return len(buf) <= next_idx
}

parse_dispatch :: proc(using p: ^Ctx) -> Message {
	if eofP(p) {return {tag=.eof}}
	i := next_idx
	next_i := i+1
	ch := buf[next_i]
	switch ch {
	case '{':
		return parse_coll(p, .set, i)
	case '!':
		panic("not impl")
	case '_':
		return {tag=.discard, start_idx=i, end_idx=next_i+1}
	case:
		if ('A'<=ch && ch<='Z') || ('a'<=ch && ch<='z') {
			return {tag=.tag, start_idx=i, end_idx=read_token(p, ch)}
		}
		return error_msgf(next_i, "no dispatch: %c at %v", buf[i], i)
	}
}

parse_macro :: proc(using p: ^Ctx, macro: Macro) -> Message {
	#partial switch macro {
	case .string: return parse_string(p)
	case .comment: return parse_comment(p)
	case .list: return parse_coll(p, .list, next_idx)
	case .vector: return parse_coll(p, .vector, next_idx)
	case .map_: return parse_coll(p, .map_, next_idx)
	case .unmatched_delim: panic("unmatched delim")
	case .dispatch: return parse_dispatch(p)
	case .none: panic("no macro")
	case: panic("unhandled macro")
	}
}

parse_number :: proc(using p: ^Ctx, ch: u8, start_idx: int) -> Message {
	return {tag=.number, start_idx=start_idx, end_idx=read_token(p, ch)}
}

read_next_form :: proc(using p: ^Ctx) -> Message {
	ch, eof := read_to_nonws(p)
	if eof {return {tag=.eof}}
	start_idx := next_idx
	if ch=='\n' {
		length := 1
		idx2 := start_idx+1
		if idx2<len(buf) && buf[idx2]=='\r' {length+=1}
		return {tag=.newline, start_idx=start_idx, end_idx=start_idx+length}
	}

	// coll end
	if 0 < len(stack) {
		frame := stack[len(stack)-1]
		end_ch : u8
		coll_type := frame.coll_type
		switch coll_type {
		case .list: end_ch=')'
		case .vector: end_ch=']'
		case .map_: end_ch='}'
		case .set: end_ch='}'
		}
		if ch==end_ch {
			pop(&stack)
			return {tag=.coll_end, start_idx=start_idx, end_idx=start_idx+1, coll_type=coll_type}
		}
	}
	
	if digitP(ch) {return parse_number(p, ch, start_idx)}
	macro := get_macro(ch)
	if macro != .none {return parse_macro(p, macro)}

	// signed number
	if (ch=='-' || ch=='+') && next_idx < len(buf) {
		ch2 := buf[next_idx]
		if digitP(ch2) {return parse_number(p, ch, start_idx)}
	}
	// symbol/keyword
	end_idx := read_token(p, ch)
	if start_idx==end_idx {return error_msgf(start_idx, "zero token length")}
	if buf[start_idx]==':' {
		return {tag=.keyword, start_idx=start_idx, end_idx=end_idx}
	} else {
		return {tag=.symbol, start_idx=start_idx, end_idx=end_idx}
	}
}

step :: proc(using p: ^Ctx) -> Message {
	msg := read_next_form(p)
	next_idx = msg.end_idx
	return msg
}