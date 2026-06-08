import Foundation
@testable import Rezel
import Testing

private func p(_ text: String) -> LRParser {
	return try! buildParser(text, options: BuildOptions(warn: { msg in
		fatalError(msg)
	}))
}

private func shared(_ a: Tree, _ b: Tree) -> Int {
	var inA = Set<ObjectIdentifier>()
	var sharedLen = 0

	func register(_ obj: Any) {
		if let tree = obj as? Tree {
			let mounted = MountedTree.get(tree)
			let target = (mounted != nil && mounted!.overlay == nil) ? mounted!.tree : tree
			for ch in target.children {
				register(ch)
			}
			inA.insert(ObjectIdentifier(target))
		} else if let buf = obj as? TreeBuffer {
			inA.insert(ObjectIdentifier(buf))
		}
	}

	func scan(_ obj: Any) {
		if let tree = obj as? Tree {
			if inA.contains(ObjectIdentifier(tree)) {
				sharedLen += tree.length
			} else {
				let mounted = MountedTree.get(tree)
				let target = (mounted != nil && mounted!.overlay == nil) ? mounted!.tree : tree
				for ch in target.children {
					scan(ch)
				}
			}
		} else if let buf = obj as? TreeBuffer {
			if inA.contains(ObjectIdentifier(buf)) {
				sharedLen += buf.length
			}
		}
	}

	register(a)
	scan(b)
	return b.length > 0 ? Int(round(100.0 * Double(sharedLen) / Double(b.length))) : 0
}

private struct Change {
	let fromA: Int, toA: Int, fromB: Int, toB: Int

	init(_ fromA: Int, _ toA: Int, _ fromB: Int? = nil, _ toB: Int? = nil) {
		self.fromA = fromA
		self.toA = toA
		self.fromB = fromB ?? fromA
		self.toB = toB ?? toA
	}
}

private func fragments(_ tree: Tree, _ changes: Change...) -> [TreeFragment] {
	return TreeFragment.applyChanges(
		TreeFragment.addTree(tree),
		changes: changes.map { ChangedRange(fromA: $0.fromA, toA: $0.toA, fromB: $0.fromB, toB: $0.toB) },
		minGap: 2
	)
}

private func qq(_ ast: Tree) -> (String, Int) -> (from: Int, to: Int) {
	return { query, offset in
		var remaining = offset
		let cursor = ast.cursor()
		repeat {
			if cursor.name == query {
				remaining -= 1
				if remaining == 0 { return (from: cursor.from, to: cursor.to) }
			}
		} while cursor.next()
		fatalError("Couldn't find \(query)")
	}
}

private func depth(_ tree: Any) -> Int {
	if let t = tree as? Tree {
		return t.children.reduce(1) { max($0, depth($1) + 1) }
	}
	return 1
}

private func breadth(_ tree: Any) -> Int {
	if let t = tree as? Tree {
		return t.children.reduce(t.children.count) { max($0, breadth($1)) }
	}
	return 0
}

private let p1Grammar = """
@precedence { call }
@top T { statement* }
statement { Cond | Loop | Block | expression ";" }
Cond { kw<"if"> expression statement }
Block { "{" statement* "}" }
Loop { kw<"while"> expression statement }
expression { Call | Num | Var | "!" expression }
Call { expression !call "(" expression* ")" }
kw<value> { @specialize<Var, value> }
@tokens { Num { @digit+ } Var { @asciiLetter+ } whitespace { @whitespace+ } }
@skip { whitespace }
"""

@Suite(.serialized)
struct ParsingTests {
	@Test("can parse a simple expression")
	func simpleParse() throws {
		let simpleParser = try buildParser("""
		@top T { "a"+ }
		""")
		let ast = simpleParser.parse(input: "aaa")
		#expect(ast.length == 3)
	}

	@Test("can parse incrementally")
	func incrementalParse() throws {
		let p1 = p(p1Grammar)
		let doc = String(repeating: "if true { print(1); hello; } while false { if 1 do(something 1 2 3); }", count: 10)
		let ast = p1.configure(bufferLength: 2).parse(input: doc)
		let content =
			"Cond(Var,Block(Call(Var,Num),Var)),Loop(Var,Block(Cond(Num,Call(Var,Var,Num,Num,Num))))"
		let expected = "T(" + repeatStr(content + ",", 9) + content + ")"
		try testTree(ast, expected)
		#expect(ast.length == 700)
		let pos = try doc.distance(from: doc.startIndex, to: #require(doc.range(of: "false")?.lowerBound))
		let doc2 = String(doc[..<doc.index(doc.startIndex, offsetBy: pos)]) + "x" + String(doc[doc.index(doc.startIndex, offsetBy: pos + 5)...])
		let ast2 = p1.configure(bufferLength: 2).parse(
			input: doc2,
			fragments: fragments(ast, Change(pos, pos + 5, pos, pos + 1))
		)
		try testTree(ast2, expected)
		#expect(shared(ast, ast2) > 40)
		#expect(ast2.length == 696)
	}

	@Test("assigns the correct node positions")
	func nodePositions() {
		let p1 = p(p1Grammar)
		let doc = "if 1 { while 2 { foo(bar(baz bug)); } }"
		let ast = p1.configure(strict: true, bufferLength: 10).parse(input: doc)
		let q = qq(ast)
		#expect(ast.length == 39)
		let cond = q("Cond", 1), one = q("Num", 1)
		#expect(cond.from == 0)
		#expect(cond.to == 39)
		#expect(one.from == 3)
		#expect(one.to == 4)
		let loop = q("Loop", 1), two = q("Num", 2)
		#expect(loop.from == 7)
		#expect(loop.to == 37)
		#expect(two.from == 13)
		#expect(two.to == 14)
		let call = q("Call", 1), inner = q("Call", 2)
		#expect(call.from == 17)
		#expect(call.to == 34)
		#expect(inner.from == 21)
		#expect(inner.to == 33)
		let bar = q("Var", 2), bug = q("Var", 4)
		#expect(bar.from == 21)
		#expect(bar.to == 24)
		#expect(bug.from == 29)
		#expect(bug.to == 32)
	}

	private static let resolveDoc = "while 111 { one; two(three 20); }"

	private func testResolve(bufferLength: Int) throws {
		let p1 = p(p1Grammar)
		let ast = p1.configure(strict: true, bufferLength: bufferLength).parse(input: Self.resolveDoc)

		let cx111 = ast.cursorAt(pos: 7)
		#expect(cx111.name == "Num")
		#expect(cx111.from == 6)
		#expect(cx111.to == 9)
		cx111.parent()
		#expect(cx111.name == "Loop")
		#expect(cx111.from == 0)
		#expect(cx111.to == 33)

		let cxThree = ast.cursorAt(pos: 22)
		#expect(cxThree.name == "Var")
		#expect(cxThree.from == 21)
		#expect(cxThree.to == 26)
		cxThree.parent()
		#expect(cxThree.name == "Call")
		#expect(cxThree.from == 17)
		#expect(cxThree.to == 30)

		let branch = cxThree.moveTo(pos: 18)
		#expect(branch.name == "Var")
		#expect(branch.from == 17)
		#expect(branch.to == 20)

		#expect(ast.cursorAt(pos: 6).name == "Loop")
		#expect(ast.cursorAt(pos: 9).name == "Loop")

		let c = ast.cursorAt(pos: 20)
		#expect(c.firstChild())
		#expect(c.name == "Var")
		#expect(c.nextSibling())
		#expect(c.name == "Var")
		#expect(c.nextSibling())
		#expect(c.name == "Num")
		#expect(!c.nextSibling())
	}

	@Test("can resolve positions in buffers")
	func resolveBuffers() throws {
		try testResolve(bufferLength: 1024)
	}

	@Test("can resolve positions in trees")
	func resolveTrees() throws {
		try testResolve(bufferLength: 2)
	}

	private static let iterDoc = "while 1 { a; b; c(d e); } while 2 { f; }"
	private static let iterSeq = [
		"T", "0", "Loop", "0", "Num", "6", "/Num", "7", "Block", "8",
		"Var", "10", "/Var", "11", "Var", "13", "/Var", "14",
		"Call", "16", "Var", "16", "/Var", "17", "Var", "18", "/Var", "19",
		"Var", "20", "/Var", "21", "/Call", "22", "/Block", "25", "/Loop", "25",
		"Loop", "26", "Num", "32", "/Num", "33", "Block", "34",
		"Var", "36", "/Var", "37", "/Block", "40", "/Loop", "40", "/T", "40",
	]
	private static let partialSeq = [
		"T", "0", "Loop", "0", "Block", "8",
		"Var", "13", "/Var", "14",
		"Call", "16", "Var", "16", "/Var", "17", "Var", "18", "/Var", "19",
		"/Call", "22", "/Block", "25", "/Loop", "25", "/T", "40",
	]

	private func testIter(bufferLength: Int, partial: Bool) throws {
		let parser = p(p1Grammar)
		var output: [String] = []
		let ast = parser.configure(strict: true, bufferLength: bufferLength).parse(input: Self.iterDoc)
		ast.iterate(
			from: partial ? 13 : 0,
			to: partial ? 19 : ast.length,
			enter: { n in
				output.append(n.name)
				output.append(String(n.from))
				return true
			},
			leave: { n in
				output.append("/" + n.name)
				output.append(String(n.to))
			}
		)
		let expected = partial ? Self.partialSeq : Self.iterSeq
		#expect(output.joined(separator: ",") == expected.joined(separator: ","))
	}

	@Test("supports forward iteration in buffers")
	func forwardIterBuffers() throws {
		try testIter(bufferLength: 1024, partial: false)
	}

	@Test("supports forward iteration in trees")
	func forwardIterTrees() throws {
		try testIter(bufferLength: 2, partial: false)
	}

	@Test("supports partial forward iteration in buffers")
	func partialIterBuffers() throws {
		try testIter(bufferLength: 1024, partial: true)
	}

	@Test("supports partial forward iteration in trees")
	func partialIterTrees() throws {
		try testIter(bufferLength: 2, partial: true)
	}

	@Test("can skip individual nodes during iteration")
	func skipNodesIteration() {
		let p1 = p(p1Grammar)
		let ast = p1.parse(input: "foo(baz(baz), bug(quux)")
		var ids = 0
		ast.iterate(enter: { n in
			if n.name == "Var" { ids += 1 }
			return n.from == 4 && n.name == "Call" ? false : true
		})
		#expect(ids == 3)
	}

	@Test("doesn't incorrectly reuse nodes")
	func noIncorrectReuse() throws {
		let parser = try buildParser("""
		@precedence { times @left, plus @left }
		@top T { expr+ }
		expr { Bin | Var }
		Bin { expr !plus "+" expr | expr !times "*" expr }
		@skip { space }
		@tokens { space { " "+ } Var { "x" } "*"[@name=Times] "+"[@name=Plus] }
		""")
		let configured = parser.configure(strict: true, bufferLength: 2)
		let ast = configured.parse(input: "x + x + x")
		try testTree(ast, "T(Bin(Bin(Var,Plus,Var),Plus,Var))")
		let ast2 = configured.parse(
			input: "x * x + x + x",
			fragments: fragments(ast, Change(0, 0, 0, 4))
		)
		try testTree(ast2, "T(Bin(Bin(Bin(Var,Times,Var),Plus,Var),Plus,Var))")
	}

	@Test("can cache skipped content")
	func cacheSkippedContent() {
		let comments = p("""
		@top T { "x"+ }
		@skip { space | Comment }
		@skip {} {
		  Comment { commentStart (Comment | commentContent)* commentEnd }
		}
		@tokens {
		  space { " "+ }
		  commentStart { "(" }
		  commentEnd { ")" }
		  commentContent { ![()]+ }
		}
		""")
		let doc = "x  (one (two) (three " + String(repeating: "(y)", count: 500) + ")) x"
		let ast = comments.configure(strict: true, bufferLength: 10).parse(input: doc)
		let doc2 = String(doc[doc.index(doc.startIndex, offsetBy: 1)...])
		let ast2 = comments.configure(bufferLength: 10).parse(
			input: doc2,
			fragments: fragments(ast, Change(0, 1, 0, 0))
		)
		#expect(shared(ast, ast2) > 80)
	}

	@Test("doesn't get slow on long invalid input")
	func invalidInput() throws {
		let p1 = p(p1Grammar)
		let t0 = Date()
		let ast = p1.parse(input: String(repeating: "#", count: 2000))
		let elapsed = Date().timeIntervalSince(t0) * 1000
		#expect(elapsed < 500, "Parsing took \(elapsed)ms, expected < 500ms")
		try testTree(ast, "T(⚠)")
	}

	@Test("supports input ranges")
	func inputRanges() throws {
		let p1 = p(p1Grammar)
		let tree = p1.parse(
			input: "if 1{{x}}0{{y}}0 foo {{z}};",
			fragments: [],
			ranges: [
				CommonRange(from: 0, to: 4),
				CommonRange(from: 9, to: 10),
				CommonRange(from: 15, to: 21),
				CommonRange(from: 26, to: 27),
			]
		)
		try testTree(tree, "T(Cond(Num,Var))")
	}

	@Test("doesn't reuse nodes whose tokens looked ahead beyond the unchanged fragments")
	func noReuseLookaheadBeyondFragments() throws {
		let comments = try buildParser("""
		@top Top { (Group | Char)* }
		@tokens {
		  Group { "(" ![)]* ")" }
		  Char { _ }
		}
		""").configure(bufferLength: 10)
		let doc = "xxx(" + String(repeating: "x", count: 996)
		let tree1 = comments.parse(input: doc)
		let tree2 = comments.parse(
			input: doc + ")",
			fragments: TreeFragment.applyChanges(TreeFragment.addTree(tree1), changes: [
				ChangedRange(fromA: 1000, toA: 1000, fromB: 1000, toB: 1001),
			])
		)
		try testTree(tree2, "Top(Char,Char,Char,Group)")
	}
}

@Suite(.serialized)
struct SequencesTests {
	private nonisolated(unsafe) static let p1: LRParser = p("""
	@top T { (X | Y)+ }
	@skip { C }
	C { "c" }
	X { "x" }
	Y { "y" ";"* }
	""")

	@Test("balances parsed sequences")
	func balancesSequences() {
		let ast = Self.p1.configure(strict: true, bufferLength: 10).parse(input: String(repeating: "x", count: 1000))
		let d = depth(ast), b = breadth(ast)
		#expect(d <= 6)
		#expect(d >= 4)
		#expect(b >= 5)
		#expect(b <= 10)
	}

	@Test("creates a tree for long content-less repeats")
	func longContentLessRepeats() throws {
		let parser = try buildParser("""
		@top T { (A | B { "[" b+ "]" })+ }
		@tokens {
		  A { "a" }
		  b { "b" }
		}
		""").configure(bufferLength: 10)
		let tree = parser.parse(input: "a[" + String(repeating: "b", count: 500) + "]")
		try testTree(tree, "T(A,B)")
		#expect(depth(tree) >= 5)
	}

	@Test("balancing doesn't get confused by skipped nodes")
	func balancingSkippedNodes() {
		let ast = Self.p1.configure(strict: true, bufferLength: 10).parse(input: String(repeating: "xc", count: 1000))
		let d = depth(ast), b = breadth(ast)
		#expect(d <= 6)
		#expect(d >= 4)
		#expect(b >= 5)
		#expect(b <= 10)
	}

	@Test("caches parts of sequences")
	func cachesPartsOfSequences() {
		let doc = String(repeating: "x", count: 1000)
		let parser = Self.p1.configure(bufferLength: 10)
		let ast = parser.parse(input: doc)
		let full = parser.parse(input: doc, fragments: TreeFragment.addTree(ast))
		#expect(shared(ast, full) > 99)
		let front = parser.parse(input: doc, fragments: fragments(ast, Change(900, 1000)))
		#expect(shared(ast, front) > 50)
		let back = parser.parse(input: doc, fragments: fragments(ast, Change(0, 100)))
		#expect(shared(ast, back) > 50)
		let middle = parser.parse(input: doc, fragments: fragments(ast, Change(0, 100), Change(900, 1000)))
		#expect(shared(ast, middle) > 50)
		let sides = parser.parse(input: doc, fragments: fragments(ast, Change(450, 550)))
		#expect(shared(ast, sides) > 50)
	}

	@Test("assigns the right positions to sequences")
	func rightPositionsSequences() {
		let parser = Self.p1.configure(bufferLength: 10)
		let doc = String(repeating: "x", count: 100) + "y;;;;;;;;;" + String(repeating: "x", count: 90)
		let ast = parser.parse(input: doc)
		var i = 0
		ast.iterate(enter: { n in
			if i == 0 {
				#expect(n.name == "T")
			} else if i == 101 {
				#expect(n.name == "Y")
				#expect(n.from == 100)
				#expect(n.to == 110)
			} else {
				#expect(n.name == "X")
				#expect(n.to == n.from + 1)
				#expect(n.from == (i <= 100 ? i - 1 : i + 8))
			}
			i += 1
			return true
		})
	}
}

@Suite(.serialized)
struct MultipleTopsTests {
	@Test("parses named tops")
	func namedTops() throws {
		let parser = try buildParser("""
		@top X { FOO C }
		@top Y { B C }
		FOO { B }
		B { "b" }
		C { "c" }
		""")
		try testTree(parser.parse(input: "bc"), "X(FOO(B), C)")
		try testTree(parser.configure(top: "X").parse(input: "bc"), "X(FOO(B), C)")
		try testTree(parser.configure(top: "Y").parse(input: "bc"), "Y(B, C)")
	}

	@Test("parses first top as default")
	func firstTopDefault() throws {
		let parser = try buildParser("""
		@top X { FOO C }
		@top Y { B C }
		FOO { B }
		B { "b" }
		C { "c" }
		""")
		try testTree(parser.parse(input: "bc"), "X(FOO(B), C)")
		try testTree(parser.configure(top: "Y").parse(input: "bc"), "Y(B, C)")
	}
}

@Suite(.serialized)
struct MixedLanguagesTests {
	private nonisolated(unsafe) static let blob: LRParser = p("""
	@top Blob { ch* } @tokens { ch { _ } }
	""")

	private nonisolated(unsafe) static let templateParser: LRParser = p("""
	@top Doc { (Dir | Content | Block)* }
	Dir { "{{" Word "}}" }
	Block { "{%" BlockContent { (Dir | Content)* } "%}" }
	@tokens {
	  Content { ![{%]+ }
	  Word { $[a-z]+ }
	}
	""")

	private func wrapMixed(_ mixed: @escaping (AnyPartialParse, InputProtocol, [TreeFragment], [CommonRange]) -> AnyPartialParse) -> ParseWrapper {
		return { parse, input, fragments, ranges in
			mixed(parse, input, fragments, ranges)
		}
	}

	@Test("can mix grammars")
	func mixGrammars() throws {
		let inner = try buildParser("""
		@top I { expr+ }
		expr { B { Open{"("} expr+ Close{")"} } | Dot{"."} }
		""")
		let outer = try buildParser("""
		@top O { expr+ }
		expr { "[[" NestContent "]]" | Bang{"!"} }
		@tokens {
		  NestContent[@export] { ![\\]]+ }
		  "[["[@name=Start] "]]"[@name=End]
		}
		""").configure(wrap: wrapMixed(parseMixed { node, _ in
			if node.name == "NestContent" { return NestedParse(parser: inner, bracketed: true) }
			return nil
		}))
		let ast = outer.parse(input: "![[((.).)]][[.]]")
		try testTree(
			ast,
			"O(Bang,Start,I(B(Open,B(Open,Dot,Close),Dot,Close)),End,Start,I(Dot),End)"
		)
		try testTree(outer.parse(input: "[[/]]"), "O(Start,I(⚠),End)")

		let tree = outer.parse(input: "[[(.)]]")
		let innerNode = try #require(tree.topNode.childAfter(2))
		#expect(innerNode.name == "I")
		#expect(innerNode.from == 2)
		#expect(innerNode.to == 5)
		#expect(innerNode.firstChild?.from == 2)
		#expect(innerNode.firstChild?.to == 5)
		#expect(tree.topNode.enter(2, side: 0, mode: nil) == nil)
		#expect(tree.topNode.enter(2, side: 0, mode: .enterBracketed)?.name == "I")
	}

	@Test("supports conditional nesting")
	func conditionalNesting() throws {
		let inner = try buildParser("""
		@top Script { any } @tokens { any { ![]+ } }
		""")
		let outer = try buildParser("""
		@top T { Tag }
		Tag { Open Content? Close }
		Open { "<" name ">" }
		Close { "</" name ">" }
		@tokens {
		  name { @asciiLetter+ }
		  Content { ![<]+ }
		}
		""").configure(wrap: wrapMixed(parseMixed { node, input in
			if node.name == "Content" {
				let open = node.node.parent!.firstChild!
				if input.read(from: open.from, to: open.to) == "<script>" {
					return NestedParse(parser: inner)
				}
			}
			return nil
		}))
		try testTree(outer.parse(input: "<foo>bar</foo>"), "T(Tag(Open,Content,Close))")
		try testTree(outer.parse(input: "<script>hello</script>"), "T(Tag(Open,Script,Close))")
	}

	@Test("can parse incrementally across nesting")
	func incrementalAcrossNesting() throws {
		let blob = Self.blob.configure(bufferLength: 10)
		let outer = try buildParser("""
		@top Program { (Nest | Name)* }
		@skip { space }
		@skip {} {
		  Nest { "{" Nested "}" }
		  Nested { nestedChar* }
		}
		@tokens {
		  space { @whitespace+ }
		  nestedChar { ![}] }
		  Name { $[a-z]+ }
		}
		""").configure(
			wrap: wrapMixed(parseMixed { node, _ in
				node.name == "Nested" ? NestedParse(parser: blob) : nil
			}),
			bufferLength: 10
		)
		let base = "hello {bbbb} "
		let doc = repeatStr(base, 500) + "{" + String(repeating: "b", count: 1000) + "} " + repeatStr(base, 500)
		let off = base.count * 500 + 500
		let ast1 = outer.parse(input: doc)
		let doc2 = String(doc[..<doc.index(doc.startIndex, offsetBy: off)]) + "bbb" + String(doc[doc.index(doc.startIndex, offsetBy: off)...])
		let ast2 = outer.parse(
			input: doc2,
			fragments: TreeFragment.applyChanges(TreeFragment.addTree(ast1), changes: [
				ChangedRange(fromA: off, toA: off, fromB: off, toB: off + 3),
			])
		)
		#expect(ast1.description == ast2.description)
		#expect(shared(ast1, ast2) > 90)
	}

	@Test("can create overlays")
	func createOverlays() throws {
		let blob = Self.blob
		let mix = Self.templateParser.configure(
			wrap: wrapMixed(parseMixed { node, _ in
				if node.name == "Doc" {
					return NestedParse(
						parser: blob,
						overlay: { (n: SyntaxNodeRef) -> Any in n.name == "Content" },
						bracketed: true
					)
				}
				return nil
			})
		)
		let tree = mix.parse(input: "foo{{bar}}baz{{bug}}")
		try testTree(tree, "Doc(Content,Dir(Word),Content,Dir(Word))")
		let c1 = tree.resolveInner(pos: 1)
		#expect(c1.name == "Blob")
		#expect(c1.from == 0)
		#expect(c1.to == 13)
		#expect(c1.parent?.name == "Doc")
		#expect(tree.resolveInner(pos: 10, side: 1).name == "Blob")
		#expect(tree.topNode.enter(3, side: 1, mode: nil)?.name == "Dir")
		#expect(tree.topNode.enter(3, side: 1, mode: .enterBracketed)?.name == "Blob")

		let mix2 = Self.templateParser.configure(
			wrap: wrapMixed(parseMixed { node, _ in
				if node.name == "Doc" {
					return NestedParse(
						parser: blob,
						overlay: [CommonRange(from: 5, to: 7)]
					)
				}
				return nil
			})
		)
		let tree2 = mix2.parse(input: "{{a}}bc{{d}}")
		let c2 = tree2.resolveInner(pos: 6)
		#expect(c2.name == "Blob")
		#expect(c2.from == 5)
		#expect(c2.to == 7)
		#expect(tree.topNode.enter(5, side: -1, mode: .enterBracketed)?.name == "Dir")
	}

	@Test("adds a mount even for empty nodes")
	func mountEmptyNodes() throws {
		let inner = p("""
		@top E { tok? } @tokens { tok { " "+ } }
		""")
		let mix = Self.templateParser.configure(
			wrap: wrapMixed(parseMixed { node, _ in
				node.name == "BlockContent" ? NestedParse(parser: inner) : nil
			})
		)
		let ast = mix.parse(input: "a{%%}b{% %}")
		try testTree(ast, "Doc(Content,Block(E),Content,Block(E))")
	}

	@Test("can resolve a stack")
	func resolveStack() throws {
		let parens = try buildParser("""
		@top T { (Text | Group)* }
		Group { "(" (Text | Group)* ")" }
		@tokens { Text { ![()]+ } }
		""")
		let mix = Self.templateParser.configure(
			wrap: wrapMixed(parseMixed { node, _ in
				node.type.isTop
					? NestedParse(parser: parens, overlay: { (n: SyntaxNodeRef) -> Any in n.name == "Content" })
					: nil
			})
		)
		func trail(_ stack: NodeIterator?) -> String {
			var result: [String] = []
			var current = stack
			while let c = current {
				result.append(c.node.name)
				current = c.next
			}
			return result.joined(separator: " ")
		}
		for i in 0 ..< 2 {
			let parser = i == 1 ? mix.configure(bufferLength: 2) : mix
			let ast = parser.parse(input: "(hey{%okay(one)two%}three)!")
			#expect(trail(ast.resolveStack(pos: 12)) == "Text Group Content BlockContent Block Group T Doc")
			#expect(trail(ast.resolveStack(pos: 2)) == "Content Text Group T Doc")
			#expect(trail(ast.resolveStack(pos: 5)) == "Text Block Group Doc T")
		}
	}

	@Test("reuses ranges from previous parses")
	func reusesRangesFromPreviousParses() throws {
		let blob = Self.blob
		var queried: [Int] = []

		let outer = try buildParser("""
		@top Doc { expr* }
		expr {
		  Paren { "(" expr* ")" } |
		  Array { "[" expr* "]" } |
		  Number |
		  String
		}
		@skip { space }
		@tokens {
		  Number { $[0-9]+ }
		  String { "'" ![']* "'" }
		  space { $[ \\n]+ }
		}
		""").configure(
			wrap: wrapMixed(parseMixed { node, _ in
				if node.name == "Array" {
					return NestedParse(
						parser: blob,
						overlay: { (n: SyntaxNodeRef) -> Any in
							if n.name == "String" {
								queried.append(n.from)
								return true
							}
							return false
						}
					)
				}
				return nil
			}),
			bufferLength: 2
		)

		let doc =
			" (100) (() [50] 123456789012345678901234 ((['one' 123456789012345678901234 (('two'))]) ['three'])) "
		let tree = outer.parse(input: doc)
		try testTree(
			tree,
			"Doc(Paren(Number),Paren(Paren,Array(Number),Number,Paren(Paren(Array(String,Number,Paren(Paren(String)))),Array(String))))"
		)
		let inOne = tree.resolveInner(pos: 45)
		#expect(inOne.name == "Blob")
		#expect(inOne.from == 44)
		#expect(inOne.to == 82)
		#expect(inOne.nextSibling == nil)
		#expect(inOne.prevSibling == nil)
		#expect(inOne.parent?.name == "Array")
		#expect(tree.resolveInner(pos: 89).name == "Blob")
		#expect(queried.map { String($0) }.joined(separator: ",") == "44,77,88")
		queried.removeAll()

		let doc2 = String(doc[..<doc.index(doc.startIndex, offsetBy: 45)]) + "x" + String(doc[doc.index(doc.startIndex, offsetBy: 46)...])
		let tree2 = outer.parse(input: doc2, fragments: fragments(tree, Change(45, 46)))
		#expect(queried.map { String($0) }.joined(separator: ",") == "44")
		#expect(shared(tree, tree2) > 20)
	}

	@Test("properly handles fragment offsets")
	func fragmentOffsets() throws {
		let inner = try buildParser("""
		@top Text { (Word | " ")* } @tokens { Word { ![ ]+ } }
		""").configure(bufferLength: 2)
		let outer = try buildParser("""
		@top Doc { expr* }
		expr { Wrap { "(" expr* ")" } | Templ { "[" expr* "]" } | Number | String }
		@skip { space }
		@tokens {
		  Number { $[0-9]+ }
		  String { "'" ![']* "'" }
		  space { $[ \\n]+ }
		}
		""").configure(
			wrap: wrapMixed(parseMixed { node, _ in
				if node.name == "Templ" {
					return NestedParse(
						parser: inner,
						overlay: { (n: SyntaxNodeRef) -> Any in
							return n.name == "String" ? CommonRange(from: n.from + 1, to: n.to - 1) : false
						}
					)
				}
				return nil
			}),
			bufferLength: 2
		)

		let doc =
			" 0123456789012345678901234 (['123456789 123456789 12345 stuff' 123456789 (('123456789 123456789 12345 other' 4))] 200)"
		let tree = outer.parse(input: doc)

		let tree1 = outer.parse(input: "88" + doc, fragments: fragments(tree, Change(0, 0, 0, 2)))
		#expect(tree.resolveInner(pos: 50).tree === tree1.resolveInner(pos: 52).tree)

		let doc2 = "88" + String(doc[..<doc.index(doc.startIndex, offsetBy: 30)]) + String(doc[doc.index(doc.startIndex, offsetBy: 31)...])
		let tree2 = outer.parse(
			input: doc2,
			fragments: fragments(tree, Change(0, 0, 0, 2), Change(30, 31, 32, 32))
		)
		#expect(shared(tree, tree2) > 20)
		#expect(try shared(#require(tree.resolveInner(pos: 49).tree), #require(tree2.resolveInner(pos: 50).tree)) > 20)
		let other = tree2.resolveInner(pos: 103, side: 1)
		#expect(other.from == 103)
		#expect(other.to == 108)
	}

	@Test("supports nested overlays")
	func nestedOverlays() throws {
		let blob = Self.blob
		let outer = try buildParser("""
		@top Doc { expr* }
		expr {
		  Paren { "(" expr* ")" } |
		  Array { "[" expr* "]" } |
		  Number |
		  String
		}
		@skip { space }
		@tokens {
		  Number { $[0-9]+ }
		  String { "'" ![']* "'" }
		  space { $[ \\n]+ }
		}
		""").configure(bufferLength: 2)

		func testMixed(_ parser: LRParser) throws {
			let tree = parser.parse(input: "['x' 100 (['xxx' 20 ('xx')] 'xxx')]")
			let blob1 = tree.resolveInner(pos: 2, side: 1)
			#expect(blob1.name == "Blob")
			#expect(blob1.from == 2)
			#expect(blob1.to == 32)
			let blob2 = tree.resolveInner(pos: 12, side: 1)
			#expect(blob2.name == "Blob")
			#expect(blob2.from == 12)
			#expect(blob2.to == 24)
		}

		try testMixed(
			outer.configure(
				wrap: wrapMixed(parseMixed { node, _ in
					if node.name == "Array" {
						return NestedParse(
							parser: blob,
							overlay: { (n: SyntaxNodeRef) -> Any in
								return n.name == "String" ? CommonRange(from: n.from + 1, to: n.to - 1) : false
							}
						)
					}
					return nil
				})
			)
		)

		try testMixed(
			outer.configure(
				wrap: wrapMixed(parseMixed { node, _ in
					if node.name != "Array" { return nil }
					var ranges: [CommonRange] = []
					func scan(_ node: SyntaxNode) {
						if node.name == "String" {
							ranges.append(CommonRange(from: node.from + 1, to: node.to - 1))
						} else {
							var ch = node.firstChild
							while let c = ch {
								if c.name != "Array" { scan(c) }
								ch = c.nextSibling
							}
						}
					}
					scan(node.node)
					return NestedParse(parser: blob, overlay: ranges)
				})
			)
		)
	}

	@Test("re-parses cut-off inner parses even if the outer tree was finished")
	func reparseCutOffInnerParses() throws {
		let inner = try buildParser("""
		@top Phrase { "<" ch* ">" } @tokens { ch { ![>] } }
		""").configure(bufferLength: 2)
		let parser = try buildParser("""
		@top Doc { Section* }
		Section { "{" SectionContent? "}" }
		@tokens { SectionContent { ![}]+ } }
		""").configure(
			wrap: wrapMixed(parseMixed { node, _ in
				node.name == "SectionContent" ? NestedParse(parser: inner) : nil
			}),
			bufferLength: 2
		)
		let input = "{" + "<" + String(repeating: "x", count: 100) + ">}" + "{<xxxx>}"
		var parse = parser.startParse(input: input)
		while parse.parsedPos < 50 {
			_ = parse.advance()
		}
		parse.stopAt(parse.parsedPos)
		var tree1: Tree? = nil
		while true {
			if let t = parse.advance() { tree1 = t; break }
		}
		try testTree(#require(tree1), "Doc(Section(Phrase(⚠)),Section(Phrase(⚠)))")
		let tree2 = try parser.parse(input: input, fragments: TreeFragment.addTree(#require(tree1)))
		try testTree(tree2, "Doc(Section(Phrase),Section(Phrase))")
	}
}

private func repeatStr(_ s: String, _ count: Int) -> String {
	return String(repeating: s, count: count)
}
