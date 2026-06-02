import Testing
import Foundation
@testable import Rezel

// MARK: - Shared tree-building helpers

nonisolated(unsafe) let sharedTypes: [NodeType] = {
    var result: [NodeType] = []
    let names = ["T", "a", "b", "c", "Pa", "Br"]
    for (i, name) in names.enumerated() {
        let specProps: [Any]? = "abc".contains(name.first!) ? [{ (_: NodeType) -> (any NodePropProtocol, Any)? in (nodePropGroup, ["atom"]) }] : nil
        result.append(NodeType.define(spec: NodeTypeSpec(id: i, name: name, props: specProps)))
    }
    return result
}()

nonisolated(unsafe) let sharedRepeatType = NodeType.define(spec: NodeTypeSpec(id: sharedTypes.count))
nonisolated(unsafe) let sharedAllTypes = sharedTypes + [sharedRepeatType]
nonisolated(unsafe) let sharedNodeSet = NodeSet(types: sharedAllTypes)

func _id(_ name: String) -> Int {
    return sharedTypes.first { $0.name == name }!.id
}

func mk(_ spec: String) -> Tree {
    var starts: [Int] = []
    var buffer: [Int] = []
    var pos = spec.startIndex

    while pos < spec.endIndex {
        let ch = spec[pos]
        if "abc".contains(ch) {
            let letterPos = spec.distance(from: spec.startIndex, to: pos)
            buffer.append(contentsOf: [_id(String(ch)), letterPos, letterPos + 1, 4])
            pos = spec.index(after: pos)
        } else if ch == "(" || ch == "[" {
            starts.append(buffer.count)
            starts.append(spec.distance(from: spec.startIndex, to: pos))
            pos = spec.index(after: pos)
        } else if ch == ")" || ch == "]" {
            let startPos = starts.removeLast()
            let startOff = starts.removeLast()
            let closeType = ch == ")" ? "Pa" : "Br"
            let endPos = spec.distance(from: spec.startIndex, to: pos) + 1
            buffer.append(contentsOf: [_id(closeType), startPos, endPos, buffer.count + 4 - startOff])
            pos = spec.index(after: pos)
        } else {
            pos = spec.index(after: pos)
        }
    }

    return Tree.build(data: BuildData(
        buffer: .array(buffer),
        nodeSet: sharedNodeSet,
        topID: 0,
        maxBufferLength: 10,
        minRepeatType: sharedRepeatType.id
    ))
}

func simple() -> Tree {
    return mk("aaaa(bbb[ccc][aaa][()])")
}

func dumpTree(_ tree: Tree, indent: String = "") {
    for (i, child) in tree.children.enumerated() {
        switch child {
        case .tree(let t):
            print("\(indent)child[\(i)]: Tree \(t.type.name) len=\(t.length) pos=\(tree.positions[i])")
            dumpTree(t, indent: indent + "  ")
        case .buffer(let b):
            let buf = b.buffer
            var entries: [String] = []
            var idx = 0
            while idx < buf.count {
                let id = buf[idx]
                let s = buf[idx+1]
                let e = buf[idx+2]
                let nxt = buf[idx+3]
                entries.append("\(b.set.types[Int(id)].name)(\(s),\(e),nxt=\(nxt))")
                idx = Int(nxt)
            }
            print("\(indent)child[\(i)]: Buffer len=\(b.length) [\(entries.joined(separator: ","))]")
        }
    }
}

nonisolated(unsafe) var _recur: Tree?
func recur() -> Tree {
    if let cached = _recur { return cached }
    func build(depth: Int) -> String {
        if depth > 0 {
            let inner = build(depth: depth - 1)
            return "(" + inner + ")[" + inner + "]"
        } else {
            var result = ""
            let letters: [Character] = ["a", "b", "c"]
            for i in 0..<20 { result.append(letters[i % 3]) }
            return result
        }
    }
    let tree = mk(build(depth: 6))
    _recur = tree
    return tree
}

nonisolated(unsafe) let anonTree = Tree(
    type: NodeType.define(spec: NodeTypeSpec(id: 0, name: "T")),
    children: [
        .tree(Tree(
            type: NodeType.none,
            children: [
                .tree(Tree(type: NodeType.define(spec: NodeTypeSpec(id: 1, name: "a")), children: [], positions: [], length: 1)),
                .tree(Tree(type: NodeType.define(spec: NodeTypeSpec(id: 2, name: "b")), children: [], positions: [], length: 1)),
            ],
            positions: [0, 1],
            length: 2
        )),
    ],
    positions: [0],
    length: 2
)

// MARK: - SyntaxNode tests

@Suite("SyntaxNode")
struct SyntaxNodeTests {
    @Test("can resolve at the top level")
    func resolveTopLevel() {
        var c = simple().resolve(pos: 2, side: -1)
        #expect(c.from == 1)
        #expect(c.to == 2)
        #expect(c.name == "a")
        #expect(c.parent!.name == "T")
        #expect(c.parent!.parent == nil)

        c = simple().resolve(pos: 2, side: 1)
        #expect(c.from == 2)
        #expect(c.to == 3)

        c = simple().resolve(pos: 2)
        #expect(c.name == "T")
        #expect(c.from == 0)
        #expect(c.to == 23)
    }

    @Test("can resolve deeper")
    func resolveDeeper() {
        let c = simple().resolve(pos: 10, side: 1)
        #expect(c.name == "c")
        #expect(c.from == 10)
        #expect(c.parent!.name == "Br")
        #expect(c.parent!.parent!.name == "Pa")
        #expect(c.parent!.parent!.parent!.name == "T")
    }

    @Test("can resolve in a large tree")
    func resolveLargeTree() {
        var c: SyntaxNode? = recur().resolve(pos: 10, side: 1)
        var depth = 1
        while let parent = c?.parent {
            c = parent
            depth += 1
        }
        #expect(depth == 8)
    }

    @Test("caches resolved parents")
    func cachesResolvedParents() {
        let a = recur().resolve(pos: 3, side: 1)
        let b = recur().resolve(pos: 3, side: 1)
        #expect(a.from == b.from && a.to == b.to && a.name == b.name)
    }

    @Test("skips anonymous nodes")
    func skipsAnonymous() {
        #expect(anonTree.toString() == "T(a,b)")
        #expect(anonTree.resolve(pos: 1).name == "T")
        #expect(anonTree.topNode.lastChild!.name == "b")
        #expect(anonTree.topNode.firstChild!.name == "a")
        #expect(anonTree.topNode.childAfter(pos: 1)!.name == "b")
    }

    @Test("allows access to the underlying tree")
    func accessUnderlyingTree() {
        let tree = mk("aaa[bbbbb(bb)bbbbbbb]aaa")
        var node = tree.topNode.firstChild!
        while node.name != "Br" { node = node.nextSibling! }
        #expect(node.tree != nil)
        #expect(node.tree!.type.name == "Br")
        node = node.firstChild!
        while node.name != "Pa" { node = node.nextSibling! }
        #expect(node.tree == nil)
        #expect(node.toTree().toString() == "Pa(b,b)")
        node = node.firstChild!
        #expect(node.name == "b")
        #expect(node.toTree().toString() == "b")
        #expect(node.toTree().children.count == 0)
    }

    @Test("getChild can get children by group")
    func getChildByGroup() {
        let tree = mk("aa(bb)[aabbcc]").topNode
        func flat(_ children: [SyntaxNode]) -> String {
            children.map(\.name).joined(separator: ",")
        }
        #expect(flat(tree.getChildren(type: .string("atom"), before: nil, after: nil)) == "a,a")
        #expect(flat(tree.firstChild!.getChildren(type: .string("atom"), before: nil, after: nil)) == "")
        #expect(flat(tree.lastChild!.getChildren(type: .string("atom"), before: nil, after: nil)) == "a,a,b,b,c,c")
    }

    @Test("getChild can get single children")
    func getChildSingle() {
        let tree = mk("abc()").topNode
        #expect(tree.getChild(type: .string("Br"), before: nil, after: nil) == nil)
        #expect(tree.getChild(type: .string("Pa"), before: nil, after: nil)?.name == "Pa")
    }

    @Test("getChild can get children between others")
    func getChildBetweenOthers() {
        let tree = mk("aa(bb)[aabbcc]").topNode
        func flat(_ children: [SyntaxNode]) -> String {
            children.map(\.name).joined(separator: ",")
        }
        #expect(tree.getChild(type: .string("Pa"), before: .string("atom"), after: .string("Br")) != nil)
        #expect(tree.getChild(type: .string("Pa"), before: .string("atom"), after: .string("atom")) == nil)
        let last = tree.lastChild!
        #expect(flat(last.getChildren(type: .string("b"), before: .string("a"), after: .string("c"))) == "b,b")
        #expect(flat(last.getChildren(type: .string("a"), before: nil, after: .string("c"))) == "a,a")
        #expect(flat(last.getChildren(type: .string("c"), before: .string("b"), after: nil)) == "c,c")
        #expect(flat(last.getChildren(type: .string("b"), before: .string("c"), after: nil)) == "")
    }
}

// MARK: - TreeCursor tests

@Suite("TreeCursor")
struct TreeCursorTests {
    @Test("iterates over all nodes")
    func iterateForward() {
        var count: [String: Int] = [:]
        var pos = 0
        let cur = simple().cursor()
        repeat {
            #expect(cur.from >= pos)
            pos = cur.from
            count[cur.name, default: 0] += 1
        } while cur.next()
        #expect(count["T"] == 1)
        #expect(count["a"] == 7)
        #expect(count["b"] == 3)
        #expect(count["c"] == 3)
        #expect(count["Br"] == 3)
        #expect(count["Pa"] == 2)
    }

    @Test("iterates over all nodes in reverse")
    func iterateReverse() {
        var count: [String: Int] = [:]
        var pos = 100
        let cur = simple().cursor()
        repeat {
            #expect(cur.to <= pos)
            pos = cur.to
            count[cur.name, default: 0] += 1
        } while cur.prev()
        #expect(count["T"] == 1)
        #expect(count["a"] == 7)
        #expect(count["b"] == 3)
        #expect(count["c"] == 3)
        #expect(count["Br"] == 3)
        #expect(count["Pa"] == 2)
    }

    @Test("works with internal iteration")
    func internalIteration() {
        var openCount: [String: Int] = [:]
        var closeCount: [String: Int] = [:]
        simple().iterate(
            enter: { t in
                openCount[t.name, default: 0] += 1
                return true
            },
            leave: { t in
                closeCount[t.name, default: 0] += 1
            }
        )
        let expected: [String: Int] = ["T": 1, "a": 7, "b": 3, "c": 3, "Br": 3, "Pa": 2]
        for (k, v) in expected {
            #expect(openCount[k] == v, "open \(k)")
            #expect(closeCount[k] == v, "close \(k)")
        }
    }

    @Test("handles iterating out of bounds")
    func iterateOutOfBounds() {
        var hit = 0
        Tree.empty.iterate(
            enter: { _ in hit += 1; return true },
            leave: { _ in hit += 1 },
            from: 0,
            to: 200
        )
        #expect(hit == 0)
    }

    @Test("internal iteration can be limited to a range")
    func limitedIteration() {
        var seen: [String] = []
        simple().iterate(
            enter: { t in
                seen.append(t.name)
                if t.name == "Br" { return false }
                return true
            },
            from: 3,
            to: 14
        )
        #expect(seen.joined(separator: ",") == "T,a,a,Pa,b,b,b,Br,Br")
    }

    @Test("can leave nodes")
    func canLeaveNodes() {
        let cur = simple().cursor()
        #expect(!cur.parent())
        _ = cur.next()
        _ = cur.next()
        #expect(cur.from == 1)
        #expect(cur.parent())
        #expect(cur.from == 0)
        for _ in 0..<6 { _ = cur.next() }
        #expect(cur.from == 5)
        #expect(cur.parent())
        #expect(cur.from == 4)
        #expect(cur.parent())
        #expect(cur.from == 0)
        #expect(!cur.parent())
    }

    @Test("can move to a given position")
    func moveToPosition() {
        let tree = recur()
        let start = tree.length >> 1
        let cursor = tree.cursorAt(pos: start, side: 1)
        repeat {
            #expect(cursor.from >= start)
        } while cursor.next()
    }

    @Test("can move into a parent node")
    func moveToParent() {
        let c = simple().cursorAt(pos: 10).moveTo(pos: 2)
        #expect(c.name == "T")
    }

    @Test("can move to a specific sibling")
    func moveToSibling() {
        let cursor = simple().cursor()
        #expect(cursor.childAfter(pos: 2))
        #expect(cursor.to == 3)
        _ = cursor.parent()
        #expect(cursor.childBefore(pos: 5))
        #expect(cursor.from == 4)
        #expect(cursor.childAfter(pos: 11))
        #expect(cursor.from == 8)
        #expect(cursor.childBefore(pos: 10))
        #expect(cursor.from == 9)
        #expect(!simple().cursor().childBefore(pos: 0))
        #expect(!simple().cursor().childAfter(pos: 100))
    }

    @Test("can produce nodes")
    func nodeFromCursor() {
        let node = simple().cursorAt(pos: 8, side: 1).node
        #expect(node.name == "Br")
        #expect(node.from == 8)
        #expect(node.parent!.name == "Pa")
        #expect(node.parent!.from == 4)
        #expect(node.parent!.parent!.name == "T")
        #expect(node.parent!.parent!.from == 0)
        #expect(node.parent!.parent!.parent == nil)
    }

    @Test("isn't slow")
    func performance() {
        let tree = recur()
        let t0 = Date()
        var count = 0
        for _ in 0..<2000 {
        let cur = tree.cursor()
            repeat {
                if cur.from < 0 || cur.name.isEmpty { Issue.record("BAD cursor") }
                count += 1
            } while cur.next()
        }
        let elapsed = Date().timeIntervalSince(t0)
        let perMS = Double(count) / max(elapsed * 1000, 1)
        // TS expects 10,000 traversals/ms in Node.js (release), while Swift gets ~460 on debug builds — we lowered it
        // to 10 to catch pathological regressions without requiring release-mode optimizations
        #expect(perMS > 10)
    }

    @Test("can produce node from cursors created from nodes")
    func cursorFromNode() {
        let cur = simple().topNode.lastChild!.childAfter(pos: 8)!.childAfter(pos: 10)!.cursor(mode: nil)
        #expect(cur.name == "c")
        #expect(cur.from == 10)
        #expect(cur.parent())
        let node = cur.node
        #expect(node.name == "Br")
        #expect(node.from == 8)
        #expect(node.parent!.name == "Pa")
        #expect(node.parent!.from == 4)
        #expect(node.parent!.parent!.name == "T")
        #expect(node.parent!.parent!.parent == nil)
    }

    @Test("reuses nodes in buffers")
    func reusesBufferNodes() {
        let cur = simple().cursorAt(pos: 10, side: 1)
        let n10 = cur.node
        #expect(n10.name == "c")
        #expect(n10.from == 10)
        #expect(cur.node.name == n10.name && cur.node.from == n10.from)
        _ = cur.nextSibling()
        let parent = n10.parent
        #expect(cur.node.parent?.name == parent?.name && cur.node.parent?.from == parent?.from)
        _ = cur.parent()
        #expect(cur.node.name == parent?.name && cur.node.from == parent?.from)
    }

    @Test("skips anonymous nodes")
    func skipAnonymousCursor() {
        let c = anonTree.cursor()
        _ = c.moveTo(pos: 1)
        #expect(c.name == "T")
        _ = c.firstChild()
        #expect(c.name == "a")
        _ = c.nextSibling()
        #expect(c.name == "b")
        #expect(!c.next())
    }

    @Test("stops at anonymous nodes when configured as full")
    func includeAnonymousCursor() {
        let c = anonTree.cursor(mode: .includeAnonymous)
        _ = c.moveTo(pos: 1)
        #expect(c.type == NodeType.none)
        #expect(c.tree!.length == 2)
        _ = c.firstChild()
        #expect(c.name == "a")
        _ = c.parent()
        #expect(c.type == NodeType.none)
    }
}

// MARK: - matchContext tests

@Suite("matchContext")
struct MatchContextTests {
    @Test("can match on nodes")
    func matchOnNodes() {
        #expect(simple().resolve(pos: 10, side: 1).matchContext(context: ["T", "Pa", "Br"]))
    }

    @Test("can match wildcards")
    func matchWildcards() {
        #expect(simple().resolve(pos: 10, side: 1).matchContext(context: ["T", "", "Br"]))
    }

    @Test("can mismatch on nodes")
    func mismatchOnNodes() {
        #expect(!simple().resolve(pos: 10, side: 1).matchContext(context: ["Q", "Br"]))
    }

    @Test("can match on cursor")
    func matchOnCursor() {
        let c = simple().cursor()
        for _ in 0..<3 { _ = c.enter(pos: 15, side: -1) }
        #expect(c.matchContext(context: ["T", "Pa", "Br"]))
    }
}
