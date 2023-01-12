
# Experiment: Compiler

This project contains the exploration of developing a compiler for a programming language with the following characteristics:
- Compiles to machine code or bytecode (for a custom VM)
- No garbage collector
- Strongly typed
- Imperative & data-oriented
- Clojure-like syntax

## Background

This work supersedes my work on an experimental JVM language, *Squawk*, in Project Chic.

Some observations from that experiment:
- Having to specify types in many random places makes programming painful and code needlessly verbose. If a type of an integer literal can't be inferred, a default should be used.
- Best approach for Squawk code was to put functions/procedures in static classes, which can be reloaded independently of data structure classes.

Problems:
- Compiler (implemented in Clojure) was slow.
- JVM's class loader system is difficult to work with, and it was impossible to do things I wanted to do in a non-clunky way.
- The JVM is drowned in unnecessary complexity, especially apparent when working with bytecode and its flawed object model.
	- JVM's method overloading and varargs were a notable annoyance and source of complexity for the compiler.

Upon reflection, I have determined that the JVM is no longer a desirable compilation target.
While project Valhalla will bring improvements with regard to speed and memory, the JVM is decades old and full of bad decisions and complexity.
On one hand, avoiding breaking changes is good. On the other hand, problems in the foundations serve to waste countless hours of people's time in serveral ways, including: trying to understand the JVM, developing on and working around contraints of the JVM, and being slowed down by suboptimal performance.

### Performance

Performance is a real issue, as a slow compiler breaks the flow of development, deacreases human wellbeing, and wastes an unacceptable amount of time in the long-term. Starting up a modestly-sized Clojure project takes an unacceptable amount of time. *Squawk* was partially an attempt to make a faster version of Clojure, but even the JVM alone is a highly inefficient use of modern computer hardware.

A common dogma in computer programming is that you should not be optimising for performance until you know your performance requirements and bottlenecks. To a large extent that is true, but it is not an excuse for things that are slow for no good reason; these things, polluted with junk, can be made faster without sacrificing a good programming experience, and in fact the experience will be improved.

As soon as you choose to use something like the JVM, you have accepted a significant performance and memory penalty. If people don't think about performance from the beginning, we end up with a proliferation of slow software (the world we live in). You may take steps to optimise the program (which naturally makes it more brittle), but you will always have the foundational issue of running on a suboptimal, managed VM.

Programs should be fast by default — and the language should push the programmer in the direction of something that is not horribly inefficient. At the very least, there should be a pathway to transform the program into something that makes reasonably efficient use of the hardware. Rewriting a JVM program in another language is not an acceptable solution.

Also, if you are developing a library, you should assume highly strict performance criteria, since you do not know in which contexts your library may be used. Pouring a huge volume of effort into a fundamentally slow technology may waste the time of your users. But it will also cut off those users for whom the library is too slow, thus their time is wasted by not being able to do what they want to do without reimplementing the library features.

In the case of a desktop applications, it is imperative that they be fast and responsive, out of respect of the user. It should be normal that it be fast and responsive, without any special effort. Computers are incredibly fast — fast enough to drive interactive 3D worlds with complicated graphics — yet even simple programs struggle to meet reasonable performance expectations. Even if you do make the program feel responsive, its inefficiencies can still impact the user experience. For instance, you may consume an absurd amount of memory that reduces the user's multitasking potential. Additionally, through excessive CPU usage, you could bring real discomfort to the user due to increased fan noise.

### Is the JVM needed?

So, what are the real benefits of the JVM? Things that come to mind:
- cross-platform
- variety of libraries
- dynamic code loading
- garbage collection

An abstraction layer over specific hardware is not unique to the JVM and can be provided by LLVM, so let's cross that off the list.

#### Libraries, ecosystem, code

As for the ecosystem of libraries, I value that much less now than I used to. Building upon layers of abstraction can often be harmful due to the additional constraints of that abstraction. Using libraries specifically, the problem is that your specific use-case does not fit the mould of the library (which are usually designed generally for a variety of cases). Because of this, when you go to do something specific, you may be outright prevented from doing that by the library without forking it and modifying the source – an undesirable outcome. On the less exteme end, the API of a library may push you towards a design that is not optimal for the problem you are trying to solve. Source code you don't own or understand is a liability; it's good to keep things minimal.

Furthermore, I don't tend to use a large number of third-party libraries, and many of the ones I do use could be feasibly reimplemented myself. I'd say writing that extra code is worth it in many cases, especially where the library in question is simple or only a small subset of it is used. As a bonus, the code you write is tailored to your needs. In any case, I'm of the philosophy that you shouldn't be afraid to throw away code often. An implication of this is that code should be easy to write and refactor, and a reason for this practice is that the more you work on a project, the better of an idea you get about what your program should look like. Rather than being held back by old, uninformed code, you should have the freedom to rebuild substantial pieces from a simpler foundation backed by experience. A library is analogous to the old informed code you wrote before you fully understood your needs.

#### Dynamic programming

For me, the most compelling feature of the JVM is the ability to dynamically modify and inspect the live program. That said, with some work, simple hot code loading could be implemented in an unmanaged language. By not having to deal with the class loader system, perhaps I could end up with a language with a much better system for dynamically loading code, since I would make close to it how I want it. In fact, it may turn out that the simpler solution overall is to implement this stuff directly and bypass the complexity put forth by the JVM.

Another consideration is: how dynamic do you need to be? By using self-describing objects just about everywhere, the JVM is highly dynamic, at the expense of performance. Is that tradeoff worth it? I lean towards 'no', having dipped my toes in modern mid-level languages. It may work better to opt-in to these dynamic runtime features in the places and times you need them. Ideally, no changes to the source code should be necessary to compile a more dynamic and introspective version of the program compared to a completely static version (to an extent). Additionally, in the spirit of mouldable development, it should be cheap to create ad hoc tools for live visualisation, debugging, and modification of the program. The video games industry has some good examples of in-house tooling being used.

#### Garbage collection

Garbage collection is a valuable feature for dynamic languages, I assume. Persistent data structures also benefit from it. However, ignoring that for now, a GC is not needed in most cases, and there are ways to make manual memory management ergonomic for the programmer.

### Another path is better

I have been impressed by a modern programming language, Jai, and its ability to create high performance software while providing relatively high-level abstractions that make programming more pleasant. As a result, I think the ethically correct decision is to abandon the JVM in order to move towards a world in which most software is not terrible, because abandoning the JVM is doable.

If we want a world full of good software, the first step we need to make is to refuse to indefinitely perpetuate the complexity and bad decisions of the past.

Moreover, if we want to make the most of the hardware we have, then building upon inscrutable towers of abstractions is not the way to go. A simpler solution is more favourable.

## Vision

The aim of this project is to explore the development of a programming language under the name "Squawk" that compiles from Clojure-like source code to machine code. Key features will include:
- Imperative and data-oriented (with ability to build functional abstractions etc on top)
- No garbage collector
- Strongly typed, with bidirectional type inference, to some extent
- Easy to refactor, fewer dependencies in the structure of code
- High performance
- Simplicity
- Flexible; gives the programmer power to do potentially dangerous things; does not impose an intrusive model of programming like OO or FP
- Metaprogrammability far beyond Clojure
- Conciseness (as much as can reasonably be achieved in a Clojure dialect)

It should allow you to work closely with the hardware, thus enabling the development of things like drivers and operating systems.

For metaprogramming, I would essentially like a way for the programmer to extend the compiler without much hassle. That is, they get access to information that the compiler has (such as inferred type information) and output an intermediate representation of code. This would be an improvement over traditional Lisp macros. A problem with Lisp macros is that they output Lisp code, which is designed to be a conveient interface for a human programmer, not a computer program. Consequently, more complicated macros may get further complicated by translating its output into a suitable code form, which is wasted work since the compiler has to analyse that output for itself. Instead, the macro should give the compiler as much useful information as it has about the code it wants to generate.

If that weren't enough, I would also be curious to explore macros that operate minimally-processed source code before things like parsing numbers has happened. This would allow the programmer to do strange things like custom number literals in certain contexts, such as `3+4i` for a complex number. Unlike Clojure macros, which receive processed number objects, these new macros would receive a node containing a string that must be parsed for oneself. Of course, this means it would be important to have options of which level in the compiler your macro runs at.

## Direction

Bytecode interpreter:
- Bytecode is an easy short-term compilation target
- Based around 64-bit registers only; no stack
- Can be used to facilitate metaprogramming features

Ideas for the long-term target:
- LLVM is the most practical option for cross-platform compilation and heavy optimisations. Problems: compilation speed, does not seem fun to work with.
- maybe: unoptimised x64 machine code, if it makes compilation much faster.
- I will not make any substantial effort to specifically support Apple hardware
- RISC-V RV64I machine code: if the industry goes this way

Questions:
- What are the capabilities of the type system?
- Rules for implicit type conversion
- Polymorphic procedures

Vague compiler overview:
- Parser
- AST builder
- Semantic analyser
	- Creates a node for each node in the AST. Gives meaning to the code, including type information, and resolves references. Enough for an IDE.
	- Each source item (eg procedure) is to be analysed until it can't progress, and will continue after getting enough information from analysing enough of its dependencies.
- Bytecode builder
- Bytecode runner

### Implementation language

A self-hosted compiler is a non-goal as the final language syntax and features are unknown, and it is important to compile without relying on a rare binary executable. Since speed is important, a GC-free, natively-compiled language will be used. Current work is being done with Odin.

Other candidates:

Zig: tried it out a bit. It has nice features, but I did not agree with a number of design decisions. Typing semi-colons in many places was annoying. Error handling is a bit weird. Making unused variables a compile error is silly. `comptime` is a nice touch, but lacks more powerful metaprogramming. Lacks good features present in Jai & Odin like struct polymorphism. Compiler feels slow.

Odin: I agree more with the decisions in this language than Zig. Synax is pleasant to type (no semi-colons) and is more minimal than Zig. Features struct polymorphism. No enforced error handling. Implicit context makes allocations convenient. Negatives: Lacks metaprogramming; Source file organisation and package system is weird.

Jai: would be my language of choice if it were publicly accessible. It is well designed and full of good ideas.


Question: why does Zig force you to handle allocation errors while that seems mostly ignored in Odin/Jai?

## Status

- Implemented basic bytecode interpreter
- Implemented AST builder from text source
- Working on semantic analysis