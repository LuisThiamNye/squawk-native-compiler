package ast

import "core:fmt"

AstMapEntry :: struct {
	key: AstNode,
	val: AstNode,
}

AstMeta :: struct {
	tags: []AstNode,
	mappings: []AstMapEntry,
}

AstNodeTag :: enum {
	list,
	vector,
	map_,
	set,
	keyword,
	symbol,
	number,
	string,
}

AstNodeValue :: struct #raw_union {
	token: string,
	children: []AstNode,
}

AstNode :: struct {
	tag: AstNodeTag,
	using value: AstNodeValue,
	meta: ^AstMeta,
}

import "core:io"

pr_ast :: proc(w: io.Writer, node: AstNode) {
	switch node.tag {
	case .list:
		io.write_byte(w, '(')
		for i in 0..<len(node.children){
			if i>0 {
				io.write_byte(w, ' ')
			}
			pr_ast(w, node.children[i])
		}
		io.write_byte(w, ')')
	case .vector:
		io.write_byte(w, '[')
		for i in 0..<len(node.children){
			if i>0 {
				io.write_byte(w, ' ')
			}
			pr_ast(w, node.children[i])
		}
		io.write_byte(w, ']')
	case .map_:
		io.write_byte(w, '{')
		for i in 0..<len(node.children){
			if i>0 {
				io.write_byte(w, ' ')
			}
			pr_ast(w, node.children[i])
		}
		io.write_byte(w, '}')
	case .set:
		io.write_byte(w, '#')
		io.write_byte(w, '{')
		for i in 0..<len(node.children){
			if i>0 {
				io.write_byte(w, ' ')
			}
			pr_ast(w, node.children[i])
		}
		io.write_byte(w, '}')
	case .keyword:
		io.write_byte(w, ':')
		io.write_string(w, node.token)
	case .symbol:
		io.write_string(w, node.token)
	case .number:
		io.write_string(w, node.token)
	case .string:
		io.write_byte(w, '"')
		io.write_string(w, node.token)
		io.write_byte(w, '"')
	}
}

NodeBuilder_Coll :: struct {
	tag: AstNodeTag,
	children: ^[dynamic]AstNode,
}

NodeBuilder_Wrapper :: struct {
	tag: enum {quote,},
}

NodeBuilder_Discard :: struct {}

NodeBuilder :: union {
	NodeBuilder_Coll,
	NodeBuilder_Wrapper,
	NodeBuilder_Discard,
}

FromParserBuilder :: struct {
	stack: [dynamic]NodeBuilder,
	current: NodeBuilder,
	max_depth: int,
}

make_parser_builder :: proc() -> ^FromParserBuilder {
	b := new(FromParserBuilder)
	b^ = {current=NodeBuilder_Coll{children=new([dynamic]AstNode)}, max_depth=1}
	return b
}

import "core:strings"
import "../parser"

builder_pop :: proc(builder: ^FromParserBuilder) {
	builder.current = pop(&builder.stack)
}

builder_push :: proc(builder: ^FromParserBuilder, nb: NodeBuilder) {
	append(&builder.stack, builder.current)
	builder.current = nb
}

builder_add_sibling :: proc(builder: ^FromParserBuilder, node: AstNode) {
	switch b in builder.current {
	case NodeBuilder_Coll:
		append(b.children, node)
	case NodeBuilder_Wrapper:
		presym : AstNode
		switch b.tag {
		case .quote:
			s := strings.clone("squawk.lang/quote")
			presym = {tag=.symbol, value={token=s}}
		}
		children := make([]AstNode, 2)
		children[0] = presym
		children[1] = node
		wnode := AstNode{tag=.list, value={children=children}}
		builder_pop(builder)
		builder_add_sibling(builder, wnode)
	case NodeBuilder_Discard:
		builder_pop(builder)
	}
}

coll_type_to_ast_tag :: proc(coll_type: parser.CollType) -> AstNodeTag{
	tag : AstNodeTag
	switch coll_type {
	case .list: tag=.list
	case .vector: tag=.vector
	case .map_: tag=.map_
	case .set: tag=.set
	}
	return tag
}

builder_accept_parser_msg :: proc(builder: ^FromParserBuilder, psr: ^parser.Ctx, msg: parser.Message) {
	tag : AstNodeTag
	#partial switch msg.tag {
	case .keyword: tag=.keyword
	case .symbol: tag=.symbol
	case .string: tag=.string
	case .number: tag=.number
	}
	#partial switch msg.tag {
	case .keyword, .symbol, .number, .string:
		token_start := msg.start_idx
		if msg.tag == .keyword || msg.tag == .string {
			token_start+=1
		}
		token_end := msg.end_idx if msg.tag != .string else msg.end_idx-1
		token := psr.buf[token_start:token_end]
		builder_add_sibling(builder, {tag=tag, value={token=string(token)}})
	case .coll_start:
		depth := len(builder.stack)
		if depth > builder.max_depth {builder.max_depth = depth}
		builder_push(builder, NodeBuilder_Coll{tag=coll_type_to_ast_tag(msg.coll_type), children=new([dynamic]AstNode)})
	case .coll_end:
		children := builder.current.(NodeBuilder_Coll).children[:]
		coll := AstNode{tag=coll_type_to_ast_tag(msg.coll_type), value={children=children}}
		builder_pop(builder)
		builder_add_sibling(builder, coll)
	case .discard:
		builder_push(builder, NodeBuilder_Discard{})
	// case:
	// 	fmt.panicf("invalid message %v", msg)
	}
}

builder_to_astnodes :: proc(builder: ^FromParserBuilder) -> [dynamic]AstNode {
	#partial switch c in builder.current {
	case NodeBuilder_Coll:
		return c.children^
	case:
		panic("bad state")
	}
}