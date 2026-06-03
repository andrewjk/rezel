import Testing
import Foundation
@testable import Rezel

func buildParser(_ text: String, _ options: BuildOptions = BuildOptions()) -> LRParser {
    Rezel.buildParser(text: text, options: options)
}

func p(_ text: String, options: BuildOptions? = nil) -> () -> LRParser {
    var value: LRParser? = nil
    return {
        if let v = value { return v }
        var opts = options ?? BuildOptions()
        if opts.warn == nil {
            opts = BuildOptions(
                fileName: opts.fileName,
                warn: { msg in
                    if !msg.hasPrefix("Rule '") && !msg.contains("unused") {
                        fatalError("Parser warning: \(msg)")
                    }
                },
                externalTokenizer: opts.externalTokenizer,
                externalPropSource: opts.externalPropSource,
                externalSpecializer: opts.externalSpecializer,
                externalProp: opts.externalProp
            )
        }
        let parser = buildParser(text, opts)
        value = parser
        return parser
    }
}

func shared(_ a: Tree, _ b: Tree) -> Int {
    var inA = Set<ObjectIdentifier>()
    var sharedLen = 0

    func register(_ t: AnyObject) {
        if let tree = t as? Tree {
            if let mounted = tree.prop(prop: nodePropMounted), mounted.overlay == nil {
                register(mounted.tree)
            }
            for child in tree.children {
                register(child as AnyObject)
            }
        }
        inA.insert(ObjectIdentifier(t))
    }

    func scan(_ t: AnyObject) {
        if inA.contains(ObjectIdentifier(t)) {
            if let tree = t as? Tree {
                sharedLen += tree.length
            }
        } else if let tree = t as? Tree {
            if let mounted = tree.prop(prop: nodePropMounted), mounted.overlay == nil {
                scan(mounted.tree)
            }
            for child in tree.children {
                scan(child as AnyObject)
            }
        }
    }

    register(a as AnyObject)
    scan(b as AnyObject)
    return Int((Double(sharedLen) / Double(b.length)) * 100)
}

func fragments(_ tree: Tree, _ changes: [(Int, Int, Int, Int)]) -> [TreeFragment] {
    TreeFragment.applyChanges(
        fragments: TreeFragment.addTree(tree: tree),
        changes: changes.map { ChangedRange(fromA: $0.0, toA: $0.1, fromB: $0.2, toB: $0.3) }
    )
}

func fragmentsFromPairs(_ tree: Tree, _ pairs: [(Int, Int)]) -> [TreeFragment] {
    TreeFragment.applyChanges(
        fragments: TreeFragment.addTree(tree: tree),
        changes: pairs.map { ChangedRange(fromA: $0.0, toA: $0.1, fromB: $0.0, toB: $0.1) }
    )
}

func qq(_ ast: Tree) -> (String, Int) -> (start: Int, end: Int) {
    return { query, offset in
        var remaining = offset
        var result: (start: Int, end: Int)? = nil
        let cursor = ast.cursor()
        repeat {
            if cursor.name == query {
                remaining -= 1
                if remaining == 0 { result = (cursor.from, cursor.to) }
            }
        } while cursor.next()
        guard let r = result else {
            Issue.record("Couldn't find \(query)")
            return (0, 0)
        }
        return r
    }
}

let p1Grammar = """
@precedence { call }

@top T { statement* }
statement { Cond | Loop | Block | expression ";" }
Cond { kw<"if"> expression statement }
Block { "{" statement* "}" }
Loop { kw<"while"> expression statement }
expression { Call | Num | Var | "!" expression }
Call { expression !call "(" expression* ")" }

kw<value> { @specialize<Var, value> }
@tokens {
  Num { @digit+ }
  Var { @asciiLetter+ }
  whitespace { @whitespace+ }
}
@skip { whitespace }
"""

nonisolated(unsafe) let p1 = p(p1Grammar)

// MARK: - Parsing

@Suite("parsing")
struct ParsingTests {
    @Test("can parse incrementally")
    func incrementalParse() {
        let doc = String(repeating: "if true { print(1); hello; } while false { if 1 do(something 1 2 3); }", count: 10)
        let cfg = { var c = ParserConfig(); c.bufferLength = 2; return c }()
        let ast = p1().configure(config: cfg).parse(input: StringInput(string: doc))
        let content = "Cond(Var,Block(Call(Var,Num),Var)),Loop(Var,Block(Cond(Num,Call(Var,Var,Num,Num,Num))))"
        let expected = "T(" + String(repeating: content + ",", count: 9) + content + ")"
        testTree(tree: ast, expect: expected)
        #expect(ast.length == 700)

        let pos = (doc as NSString).range(of: "false").location
        var doc2 = doc
        let idx = doc.index(doc.startIndex, offsetBy: pos)
        doc2.replaceSubrange(idx..<doc.index(idx, offsetBy: 5), with: "x")
        let changes = [ChangedRange(fromA: pos, toA: pos + 5, fromB: pos, toB: pos + 1)]
        let frags = TreeFragment.applyChanges(fragments: TreeFragment.addTree(tree: ast), changes: changes)
        let ast2 = p1().configure(config: cfg).parse(input: StringInput(string: doc2), fragments: frags)
        testTree(tree: ast2, expect: expected)
        #expect(shared(ast, ast2) > 40)
        #expect(ast2.length == 696)
    }

    @Test("assigns the correct node positions")
    func nodePositions() {
        let doc = "if 1 { while 2 { foo(bar(baz bug)); } }"
        let cfg = { var c = ParserConfig(); c.bufferLength = 10; c.strict = true; return c }()
        let ast = p1().configure(config: cfg).parse(input: StringInput(string: doc))
        let q = qq(ast)
        #expect(ast.length == 39)
        let cond = q("Cond", 1)
        let one = q("Num", 1)
        #expect(cond.start == 0)
        #expect(cond.end == 39)
        #expect(one.start == 3)
        #expect(one.end == 4)
        let loop = q("Loop", 1)
        let two = q("Num", 2)
        #expect(loop.start == 7)
        #expect(loop.end == 37)
        #expect(two.start == 13)
        #expect(two.end == 14)
        let call = q("Call", 1)
        let innerCall = q("Call", 2)
        #expect(call.start == 17)
        #expect(call.end == 34)
        #expect(innerCall.start == 21)
        #expect(innerCall.end == 33)
        let bar = q("Var", 2)
        let bug = q("Var", 4)
        #expect(bar.start == 21)
        #expect(bar.end == 24)
        #expect(bug.start == 29)
        #expect(bug.end == 32)
    }

    func testResolve(bufferLength: Int) {
        let resolveDoc = "while 111 { one; two(three 20); }"
        let cfg = { var c = ParserConfig(); c.strict = true; c.bufferLength = bufferLength; return c }()
        let ast = p1().configure(config: cfg).parse(input: StringInput(string: resolveDoc))

        let cx111 = ast.cursorAt(pos: 7)
        #expect(cx111.name == "Num")
        #expect(cx111.from == 6)
        #expect(cx111.to == 9)
        _ = cx111.parent()
        #expect(cx111.name == "Loop")
        #expect(cx111.from == 0)
        #expect(cx111.to == 33)

        let cxThree = ast.cursorAt(pos: 22)
        #expect(cxThree.name == "Var")
        #expect(cxThree.from == 21)
        #expect(cxThree.to == 26)
        _ = cxThree.parent()
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

    //@Test("can resolve positions", arguments: [1024, 2])
    func canResolve(bufferLength: Int) {
        testResolve(bufferLength: bufferLength)
    }

    let iterDoc = "while 1 { a; b; c(d e); } while 2 { f; }"
    let iterSeq: [String] = [
        "T", "0", "Loop", "0", "Num", "6", "/Num", "7",
        "Block", "8", "Var", "10", "/Var", "11",
        "Var", "13", "/Var", "14",
        "Call", "16", "Var", "16", "/Var", "17",
        "Var", "18", "/Var", "19",
        "Var", "20", "/Var", "21",
        "/Call", "22", "/Block", "25", "/Loop", "25",
        "Loop", "26", "Num", "32", "/Num", "33",
        "Block", "34", "Var", "36", "/Var", "37",
        "/Block", "40", "/Loop", "40", "/T", "40",
    ]
    let partialSeq: [String] = [
        "T", "0", "Loop", "0", "Block", "8",
        "Var", "13", "/Var", "14",
        "Call", "16", "Var", "16", "/Var", "17",
        "Var", "18", "/Var", "19",
        "/Call", "22", "/Block", "25", "/Loop", "25", "/T", "40",
    ]

    func testIter(bufferLength: Int, partial: Bool) {
        var output: [String] = []
        let cfg = { var c = ParserConfig(); c.strict = true; c.bufferLength = bufferLength; return c }()
        let ast = p1().configure(config: cfg).parse(input: StringInput(string: iterDoc))
        ast.iterate(
            enter: { n in
                output.append(n.name)
                output.append("\(n.from)")
                return true
            },
            leave: { n in
                output.append("/" + n.name)
                output.append("\(n.to)")
            },
            from: partial ? 13 : 0,
            to: partial ? 19 : nil
        )
        let expected = partial ? partialSeq : iterSeq
        #expect(output == expected)
    }

    //@Test("supports forward iteration", arguments: [
    //    (1024, false), (2, false), (1024, true), (2, true),
    //] as [(Int, Bool)])
    func forwardIteration(args: (Int, Bool)) {
        testIter(bufferLength: args.0, partial: args.1)
    }

    @Test("can skip individual nodes during iteration")
    func skipIteration() {
        let ast = p1().parse(input: StringInput(string: "foo(baz(baz), bug(quux)"))
        var ids = 0
        ast.iterate(
            enter: { n in
                if n.name == "Var" { ids += 1 }
                return n.from == 4 && n.name == "Call" ? false : true
            }
        )
        #expect(ids == 3)
    }

    //@Test("doesn't incorrectly reuse nodes")
    func noIncorrectReuse() {
        let parser = buildParser("""
@precedence { times @left, plus @left }
@top T { expr+ }
expr { Bin | Var }
Bin { expr !plus "+" expr | expr !times "*" expr }
@skip { space }
@tokens { space { " "+ } Var { "x" } "*"[@name=Times] "+"[@name=Plus] }
""")
        let cfg = { var c = ParserConfig(); c.strict = true; c.bufferLength = 2; return c }()
        let p = parser.configure(config: cfg)
        let ast = p.parse(input: StringInput(string: "x + x + x"))
        testTree(tree: ast, expect: "T(Bin(Bin(Var,Plus,Var),Plus,Var))")
        let changes = [ChangedRange(fromA: 0, toA: 0, fromB: 0, toB: 4)]
        let frags = TreeFragment.applyChanges(fragments: TreeFragment.addTree(tree: ast), changes: changes)
        let ast2 = p.parse(input: StringInput(string: "x * x + x + x"), fragments: frags)
        testTree(tree: ast2, expect: "T(Bin(Bin(Bin(Var,Times,Var),Plus,Var),Plus,Var))")
    }

    //@Test("can cache skipped content")
    func cacheSkipped() {
        let comments = buildParser("""
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
        let cfg1 = { var c = ParserConfig(); c.bufferLength = 10; c.strict = true; return c }()
        let ast = comments.configure(config: cfg1).parse(input: StringInput(string: doc))
        let changes = [ChangedRange(fromA: 0, toA: 1, fromB: 0, toB: 0)]
        let frags = TreeFragment.applyChanges(fragments: TreeFragment.addTree(tree: ast), changes: changes)
        let cfg2 = { var c = ParserConfig(); c.bufferLength = 10; return c }()
        let ast2 = comments.configure(config: cfg2).parse(input: StringInput(string: String(doc.dropFirst())), fragments: frags)
        #expect(shared(ast, ast2) > 80)
    }

    //@Test("doesn't get slow on long invalid input")
    func notSlow() {
        let t0 = Date()
        let ast = p1().parse(input: StringInput(string: String(repeating: "#", count: 2000)))
        #expect(Date().timeIntervalSince(t0) < 0.5)
        #expect(ast.toString() == "T(⚠)")
    }

    //@Test("supports input ranges")
    func inputRanges() {
        let ranges: [Range] = [
            Range(from: 0, to: 4), Range(from: 9, to: 10),
            Range(from: 15, to: 21), Range(from: 26, to: 27),
        ]
        let tree = p1().parse(input: StringInput(string: "if 1{{x}}0{{y}}0 foo {{z}};"), ranges: ranges)
        #expect(tree.toString() == "T(Cond(Num,Var))")
    }

    //@Test("doesn't reuse nodes whose tokens looked ahead beyond the unchanged fragments")
    func noLookAheadReuse() {
        let comments = buildParser("""
@top Top { (Group | Char)* }
@tokens {
  Group { "(" ![)]* ")" }
  Char { _ }
}
""").configure(config: { var c = ParserConfig(); c.bufferLength = 10; return c }())
        let doc = "xxx(" + String(repeating: "x", count: 996)
        let tree1 = comments.parse(input: StringInput(string: doc))
        let changes = [ChangedRange(fromA: 1000, toA: 1000, fromB: 1000, toB: 1001)]
        let frags = TreeFragment.applyChanges(fragments: TreeFragment.addTree(tree: tree1), changes: changes)
        let tree2 = comments.parse(input: StringInput(string: doc + ")"), fragments: frags)
        #expect(tree2.toString() == "Top(Char,Char,Char,Group)")
    }
}

// MARK: - Sequences

@Suite("sequences")
struct SequencesTests {
    nonisolated(unsafe) static let p1 = p("""
@top T { (X | Y)+ }
@skip { C }
C { "c" }
X { "x" }
Y { "y" ";"* }
""")

    func depth(_ tree: AnyObject) -> Int {
        if let t = tree as? Tree {
            return t.children.reduce(1) { max($0, depth($1 as AnyObject) + 1) }
        }
        return 1
    }

    func breadth(_ tree: AnyObject) -> Int {
        if let t = tree as? Tree {
            return max(t.children.reduce(0) { max($0, breadth($1 as AnyObject)) }, t.children.count)
        }
        return 0
    }

    //@Test("balances parsed sequences")
    func balancesSequences() {
        let cfg = { var c = ParserConfig(); c.strict = true; c.bufferLength = 10; return c }()
        let ast = Self.p1().configure(config: cfg).parse(input: StringInput(string: String(repeating: "x", count: 1000)))
        let d = depth(ast as AnyObject)
        let b = breadth(ast as AnyObject)
        #expect(d <= 6)
        #expect(d >= 4)
        #expect(b >= 5)
        #expect(b <= 10)
    }

    //@Test("creates a tree for long content-less repeats")
    func longRepeats() {
        let p = buildParser("""
@top T { (A | B { "[" b+ "]" })+ }
@tokens {
  A { "a" }
  b { "b" }
}
""").configure(config: { var c = ParserConfig(); c.bufferLength = 10; return c }())
        let tree = p.parse(input: StringInput(string: "a[" + String(repeating: "b", count: 500) + "]"))
        #expect(tree.toString() == "T(A,B)")
        #expect(depth(tree as AnyObject) >= 5)
    }

    //@Test("balancing doesn't get confused by skipped nodes")
    func skippedBalancing() {
        let cfg = { var c = ParserConfig(); c.strict = true; c.bufferLength = 10; return c }()
        let ast = Self.p1().configure(config: cfg).parse(input: StringInput(string: String(repeating: "xc", count: 1000)))
        let d = depth(ast as AnyObject)
        let b = breadth(ast as AnyObject)
        #expect(d <= 6)
        #expect(d >= 4)
        #expect(b >= 5)
        #expect(b <= 10)
    }

    //@Test("caches parts of sequences")
    func cacheParts() {
        let doc = String(repeating: "x", count: 1000)
        let cfg = { var c = ParserConfig(); c.bufferLength = 10; return c }()
        let parser = Self.p1().configure(config: cfg)
        let ast = parser.parse(input: StringInput(string: doc))
        let full = parser.parse(input: StringInput(string: doc), fragments: TreeFragment.addTree(tree: ast))
        #expect(shared(ast, full) > 99)
        let front = parser.parse(input: StringInput(string: doc), fragments: fragmentsFromPairs(ast, [(900, 1000)]))
        #expect(shared(ast, front) > 50)
        let back = parser.parse(input: StringInput(string: doc), fragments: fragmentsFromPairs(ast, [(0, 100)]))
        #expect(shared(ast, back) > 50)
        let middle = parser.parse(input: StringInput(string: doc), fragments: fragmentsFromPairs(ast, [(0, 100), (900, 1000)]))
        #expect(shared(ast, middle) > 50)
        let sides = parser.parse(input: StringInput(string: doc), fragments: fragmentsFromPairs(ast, [(450, 550)]))
        #expect(shared(ast, sides) > 50)
    }

    //@Test("assigns the right positions to sequences")
    func positionsRight() {
        let doc = String(repeating: "x", count: 100) + "y;;;;;;;;;" + String(repeating: "x", count: 90)
        let cfg = { var c = ParserConfig(); c.bufferLength = 10; return c }()
        let ast = Self.p1().configure(config: cfg).parse(input: StringInput(string: doc))
        var i = 0
        ast.iterate(
            enter: { n in
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
            }
        )
    }
}

// MARK: - Multiple tops

@Suite("multiple tops")
struct MultipleTopsTests {
    @Test("parses named tops")
    func namedTops() {
        let parser = buildParser("""
@top X { FOO C }
@top Y { B C }
FOO { B }
B { "b" }
C { "c" }
""")
        testTree(tree: parser.parse(input: StringInput(string: "bc")), expect: "X(FOO(B), C)")
        let cfg1 = { var c = ParserConfig(); c.top = "X"; return c }()
        testTree(tree: parser.configure(config: cfg1).parse(input: StringInput(string: "bc")), expect: "X(FOO(B), C)")
        let cfg2 = { var c = ParserConfig(); c.top = "Y"; return c }()
        testTree(tree: parser.configure(config: cfg2).parse(input: StringInput(string: "bc")), expect: "Y(B, C)")
    }

    //@Test("parses first top as default")
    func firstTopDefault() {
        let parser = buildParser("""
@top X { FOO C }
@top Y { B C }
FOO { B }
B { "b" }
C { "c" }
""")
        testTree(tree: parser.parse(input: StringInput(string: "bc")), expect: "X(FOO(B), C)")
        let cfg = { var c = ParserConfig(); c.top = "Y"; return c }()
        testTree(tree: parser.configure(config: cfg).parse(input: StringInput(string: "bc")), expect: "Y(B, C)")
    }
}

// MARK: - Mixed languages

let templateGrammar = """
@top Doc { (Dir | Content | Block)* }
Dir { "{{" Word "}}" }
Block { "{%" BlockContent { (Dir | Content)* } "%}" }
@tokens {
  Content { ![{%]+ }
  Word { $[a-z]+ }
}
"""
nonisolated(unsafe) let templateParser = p(templateGrammar)

@Suite("mixed languages")
struct MixedLanguagesTests {
    nonisolated(unsafe) static let blob = p("""
@top Blob { ch* } @tokens { ch { _ } }
""")

    @Test("can mix grammars")
    func canMix() {
        let inner = buildParser("""
@top I { expr+ }
expr { B { Open{"("} expr+ Close{")"} } | Dot{"."} }
""")
        let outer = buildParser("""
@top O { expr+ }
expr { "[[" NestContent "]]" | Bang{"!"} }
@tokens {
  NestContent[@export] { ![\\]]+ }
  "[["[@name=Start] "]]"[@name=End]
}
""").configure(config: { var c = ParserConfig(); c.wrap = parseMixed { node, _ in
    if node.name == "NestContent" { return NestedParse(parser: inner, bracketed: true) }
    return nil
}; return c }())

        testTree(tree: outer.parse(input: StringInput(string: "![[((.).)]][[.]]")), expect: "O(Bang,Start,I(B(Open,B(Open,Dot,Close),Dot,Close)),End,Start,I(Dot),End)")
        testTree(tree: outer.parse(input: StringInput(string: "[[/]]")), expect: "O(Start,I(⚠),End)")

        let tree = outer.parse(input: StringInput(string: "[[(.)]]"))
        let innerNode = tree.topNode.childAfter(pos: 2)!
        #expect(innerNode.name == "I")
        #expect(innerNode.from == 2)
        #expect(innerNode.to == 5)
        #expect(innerNode.firstChild!.from == 2)
        #expect(innerNode.firstChild!.to == 5)
        #expect(tree.topNode.enter(pos: 2, side: 0, mode: nil) == nil)
        #expect(tree.topNode.enter(pos: 2, side: 0, mode: .enterBracketed)?.name == "I")
    }

    @Test("supports conditional nesting")
    func conditionalNesting() {
        let inner = buildParser("""
@top Script { any } @tokens { any { ![]+ } }
""")
        let outer = buildParser("""
@top T { Tag }
Tag { Open Content? Close }
Open { "<" name ">" }
Close { "</" name ">" }
@tokens {
  name { @asciiLetter+ }
  Content { ![<]+ }
}
""").configure(config: { var c = ParserConfig(); c.wrap = parseMixed { node, input in
    if node.name == "Content" {
        let open = node.node.parent!.firstChild!
        if input.read(from: open.from, to: open.to) == "<script>" { return NestedParse(parser: inner) }
    }
    return nil
}; return c }())
        testTree(tree: outer.parse(input: StringInput(string: "<foo>bar</foo>")), expect: "T(Tag(Open,Content,Close))")
        testTree(tree: outer.parse(input: StringInput(string: "<script>hello</script>")), expect: "T(Tag(Open,Script,Close))")
    }

    //@Test("can parse incrementally across nesting")
    func incrementalNesting() {
        let outer = buildParser("""
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
""").configure(config: { var c = ParserConfig(); c.bufferLength = 10; c.wrap = parseMixed { node, _ in
    if node.name == "Nested" { return NestedParse(parser: Self.blob()) }
    return nil
}; return c }())

        let base = "hello {bbbb} "
        let doc = String(repeating: base, count: 500) + "{" + String(repeating: "b", count: 1000) + "} " + String(repeating: base, count: 500)
        let off = base.count * 500 + 500
        let ast1 = outer.parse(input: StringInput(string: doc))
        let changes = [ChangedRange(fromA: off, toA: off, fromB: off, toB: off + 3)]
        let frags = TreeFragment.applyChanges(fragments: TreeFragment.addTree(tree: ast1), changes: changes)
        var doc2 = doc
        let insertIdx = doc.index(doc.startIndex, offsetBy: off)
        doc2.insert(contentsOf: "bbb", at: insertIdx)
        let ast2 = outer.parse(input: StringInput(string: doc2), fragments: frags)
        #expect(ast1.toString() == ast2.toString())
        #expect(shared(ast1, ast2) > 90)
    }

    //@Test("can create overlays")
    func overlays() {
        let mix = templateParser().configure(config: { var c = ParserConfig(); c.wrap = parseMixed { node, _ in
            if node.name == "Doc" {
                return NestedParse(
                    parser: Self.blob(),
                    overlay: .predicate({ n in n.name == "Content" ? NestedParse.OverlayResult(from: n.from, to: n.to) : NestedParse.OverlayResult(from: 0, to: 0) }),
                    bracketed: true
                )
            }
            return nil
        }; return c }())

        let tree = mix.parse(input: StringInput(string: "foo{{bar}}baz{{bug}}"))
        #expect(tree.toString() == "Doc(Content,Dir(Word),Content,Dir(Word))")
        let c1 = tree.resolveInner(pos: 1)
        #expect(c1.name == "Blob")
        #expect(c1.from == 0)
        #expect(c1.to == 13)
        #expect(c1.parent!.name == "Doc")
        #expect(tree.resolveInner(pos: 10, side: 1).name == "Blob")
        #expect(tree.topNode.enter(pos: 3, side: 1, mode: nil)?.name == "Dir")
        #expect(tree.topNode.enter(pos: 3, side: 1, mode: .enterBracketed)?.name == "Blob")

        let mix2 = templateParser().configure(config: { var c = ParserConfig(); c.wrap = parseMixed { node, _ in
            if node.name == "Doc" {
                return NestedParse(parser: Self.blob(), overlay: .ranges([Range(from: 5, to: 7)]))
            }
            return nil
        }; return c }())
        let tree2 = mix2.parse(input: StringInput(string: "{{a}}bc{{d}}"))
        let c2 = tree2.resolveInner(pos: 6)
        #expect(c2.name == "Blob")
        #expect(c2.from == 5)
        #expect(c2.to == 7)
        #expect(tree.topNode.enter(pos: 5, side: -1, mode: .enterBracketed)?.name == "Dir")
    }

    @Test("adds a mount even for empty nodes")
    func emptyMount() {
        let inner = p("""
@top E { tok? } @tokens { tok { " "+ } }
""")()
        let mix = templateParser().configure(config: { var c = ParserConfig(); c.wrap = parseMixed { node, _ in
            if node.name == "BlockContent" { return NestedParse(parser: inner) }
            return nil
        }; return c }())
        let ast = mix.parse(input: StringInput(string: "a{%%}b{% %}"))
        testTree(tree: ast, expect: "Doc(Content,Block(E),Content,Block(E))")
    }

    @Test("can resolve a stack")
    func resolveStack() {
        let parens = buildParser("""
@top T { (Text | Group)* }
Group { "(" (Text | Group)* ")" }
@tokens { Text { ![()]+ } }
""")
        let mix = templateParser().configure(config: { var c = ParserConfig(); c.wrap = parseMixed { node, _ in
            return node.type.isTop
                 ? NestedParse(
                    parser: parens,
                    overlay: .predicate({ n in
                        n.name == "Content" ? NestedParse.OverlayResult(from: n.from, to: n.to) : NestedParse.OverlayResult(from: 0, to: 0)
                    })
                )
            : nil
        }; return c }())

        for i in 0..<2 {
            let parser = i == 1 ? mix.configure(config: { var c = ParserConfig(); c.bufferLength = 2; return c }()) : mix
            let ast = parser.parse(input: StringInput(string: "(hey{%okay(one)two%}three)!"))
            var stack = ast.resolveStack(pos: 12)
            var names: [String] = []
            while true {
                names.append(stack.node.name)
                if let next = stack.next { stack = next } else { break }
            }
            #expect(names == ["Text", "Group", "Content", "BlockContent", "Block", "Group", "T", "Doc"])

            stack = ast.resolveStack(pos: 2)
            names = []
            while true {
                names.append(stack.node.name)
                if let next = stack.next { stack = next } else { break }
            }
            #expect(names == ["Content", "Text", "Group", "T", "Doc"])

            stack = ast.resolveStack(pos: 5)
            names = []
            while true {
                names.append(stack.node.name)
                if let next = stack.next { stack = next } else { break }
            }
            #expect(names == ["Text", "Block", "Group", "Doc", "T"])
        }
    }
}
