import Testing
import Foundation
@testable import Rezel

private func makeTestTypes() -> (types: [NodeType], nodeSet: NodeSet, repeatType: NodeType) {
    let names = ["T", "a", "b", "c", "Pa", "Br"]
    var types: [NodeType] = []
    for (i, s) in names.enumerated() {
        let isAtom = s == "a" || s == "b" || s == "c"
        types.append(NodeType.define(spec: NodeType.DefineSpec(
            id: i,
            name: s,
            props: isAtom ? [nodePropGroup.add(match: ["atom": ["atom"]])] as [Any] : nil
        )))
    }
    let repeatType = NodeType.define(spec: NodeType.DefineSpec(id: types.count))
    types.append(repeatType)
    return (types, NodeSet(types: types), repeatType)
}

nonisolated(unsafe) private let testEnv = makeTestTypes()
nonisolated(unsafe) private let testTypes = testEnv.types
nonisolated(unsafe) private let testNodeSet = testEnv.nodeSet

private func id(_ n: String) -> Int {
    testTypes.first(where: { $0.name == n })!.id
}

private func mk(_ spec: String) -> Tree {
    var starts: [Int] = []
    var buffer: [Int] = []
    let chars = Array(spec)
    var pos = 0
    while pos < chars.count {
        let ch = chars[pos]
        if ch == "a" || ch == "b" || ch == "c" {
            let bufStart = buffer.count
            let groupStart = pos
            var i = 0
            while pos < chars.count {
                let c = chars[pos]
                guard c == "a" || c == "b" || c == "c" else { break }
                buffer.append(id(String(c)))
                buffer.append(pos)
                buffer.append(pos + 1)
                buffer.append(4)
                if i > 0 {
                    let curLen = buffer.count
                    buffer.append(testEnv.repeatType.id)
                    buffer.append(groupStart)
                    buffer.append(pos + 1)
                    buffer.append(curLen + 4 - bufStart)
                }
                i += 1
                pos += 1
            }
        } else if ch == "[" || ch == "(" {
            starts.append(buffer.count)
            starts.append(pos)
            pos += 1
        } else if ch == "]" || ch == ")" {
            let stringStart = starts.removeLast()
            let bufStartOff = starts.removeLast()
            let nodeName = ch == ")" ? "Pa" : "Br"
            let curLen = buffer.count
            buffer.append(id(nodeName))
            buffer.append(stringStart)
            buffer.append(pos + 1)
            buffer.append(curLen + 4 - bufStartOff)
            pos += 1
        } else {
            pos += 1
        }
    }
    return Tree.build(data: BuildData(
        buffer: buffer,
        nodeSet: testNodeSet,
        topID: 0,
        maxBufferLength: 10,
        minRepeatType: testEnv.repeatType.id
    ))
}

private func buildRecurSpec() -> String {
    func build(_ depth: Int) -> String {
        if depth > 0 {
            let inner = build(depth - 1)
            return "(" + inner + ")[" + inner + "]"
        } else {
            var result = ""
            for i in 0..<20 { result += ["a", "b", "c"][i % 3] }
            return result
        }
    }
    return build(6)
}

private let _recurLock = NSLock()
nonisolated(unsafe) private var _recur: Tree? = nil
private func recur() -> Tree {
    _recurLock.lock()
    defer { _recurLock.unlock() }
    if _recur == nil { _recur = mk(buildRecurSpec()) }
    return _recur!
}

private let _simpleLock = NSLock()
nonisolated(unsafe) private var _simple: Tree? = nil
private func simple() -> Tree {
    _simpleLock.lock()
    defer { _simpleLock.unlock() }
    if _simple == nil { _simple = mk("aaaa(bbb[ccc][aaa][()])") }
    return _simple!
}

nonisolated(unsafe) private let anonTree = Tree(
    type: testNodeSet.types[0],
    children: [
        Tree(
            type: NodeType.none,
            children: [
                Tree(type: testNodeSet.types[1], children: [], positions: [], length: 1),
                Tree(type: testNodeSet.types[2], children: [], positions: [], length: 1)
            ],
            positions: [0, 1],
            length: 2
        )
    ],
    positions: [0],
    length: 2
)

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
    func resolveLarge() {
        var c: SyntaxNode? = recur().resolve(pos: 10, side: 1)
        var depth = 1
        while c != nil { c = c!.parent; depth += 1 }
        #expect(depth == 9)
    }

    @Test("caches resolved parents")
    func cachesResolvedParents() {
        let a = recur().resolve(pos: 3, side: 1)
        let b = recur().resolve(pos: 3, side: 1)
        #expect(a as AnyObject === b as AnyObject)
    }

    @Test("skips anonymous nodes")
    func skipsAnonymous() {
        #expect(anonTree.description == "T(a,b)")
        #expect(anonTree.resolve(pos: 1).name == "T")
        #expect(anonTree.topNode.lastChild!.name == "b")
        #expect(anonTree.topNode.firstChild!.name == "a")
        #expect(anonTree.topNode.childAfter(1)!.name == "b")
    }

    @Test("allows access to the underlying tree")
    func accessTree() {
        let tree = mk("aaa[bbbbb(bb)bbbbbbb]aaa")
        var node = tree.topNode.firstChild!
        while node.name != "Br" { node = node.nextSibling! }
        #expect(node.tree != nil)
        #expect(node.tree!.type.name == "Br")
        node = node.firstChild!
        while node.name != "Pa" { node = node.nextSibling! }
        #expect(node.tree == nil)
        #expect(node.toTree().description == "Pa(b,b)")
        node = node.firstChild!
        #expect(node.name == "b")
        #expect(node.toTree().description == "b")
        #expect(node.toTree().children.count == 0)
    }
}

@Suite("TreeCursor")
struct TreeCursorTests {
    static let simpleCount: [String: Int] = ["a": 7, "b": 3, "c": 3, "Br": 3, "Pa": 2, "T": 1]

    @Test("iterates over all nodes")
    func iterateAll() {
        var count: [String: Int] = [:]
        var pos = 0
        let cur = simple().cursor()
        repeat {
            #expect(cur.from >= pos)
            pos = cur.from
            count[cur.name, default: 0] += 1
        } while cur.next()
        for (k, v) in Self.simpleCount {
            #expect(count[k] == v, "\(k): expected \(v), got \(count[k] ?? 0)")
        }
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
        for (k, v) in Self.simpleCount {
            #expect(count[k] == v, "\(k): expected \(v), got \(count[k] ?? 0)")
        }
    }

    @Test("works with internal iteration")
    func internalIteration() {
        var openCount: [String: Int] = [:]
        var closeCount: [String: Int] = [:]
        simple().iterate(enter: { t -> Bool in
            openCount[t.name, default: 0] += 1
            return true
        }, leave: { t in
            closeCount[t.name, default: 0] += 1
        })
        for (k, v) in Self.simpleCount {
            #expect(openCount[k] == v)
            #expect(closeCount[k] == v)
        }
    }

    @Test("handles iterating out of bounds")
    func outOfBounds() {
        var hit = 0
        Tree.empty.iterate(from: 0, to: 200, enter: { _ -> Bool in hit += 1; return true }, leave: { _ in hit += 1 })
        #expect(hit == 0)
    }

    @Test("internal iteration can be limited to a range")
    func limitedRange() {
        var seen: [String] = []
        simple().iterate(from: 3, to: 14, enter: { t -> Bool in
            seen.append(t.name)
            return t.name == "Br" ? false : true
        })
        #expect(seen.joined(separator: ",") == "T,a,a,Pa,b,b,b,Br,Br")
    }

    @Test("can leave nodes")
    func leaveNodes() {
        let c = simple().cursor()
        #expect(!c.parent())
        _ = c.next()
        _ = c.next()
        #expect(c.from == 1)
        #expect(c.parent())
        #expect(c.from == 0)
        for _ in 0..<6 { _ = c.next() }
        #expect(c.from == 5)
        #expect(c.parent())
        #expect(c.from == 4)
        #expect(c.parent())
        #expect(c.from == 0)
        #expect(!c.parent())
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
    func moveIntoParent() {
        let c = simple().cursorAt(pos: 10)
        c.moveTo(pos: 2)
        #expect(c.name == "T")
    }

    @Test("isn't slow")
    func performance() {
        let tree = recur()
        let t0 = Date()
        var count = 0
        for _ in 0..<2000 {
            let c = tree.cursor()
            repeat {
                if c.from < 0 || c.name.isEmpty { Issue.record("BAD"); break }
                count += 1
            } while c.next()
        }
        let elapsed = Date().timeIntervalSince(t0) * 1000
        let perMS = Double(count) / max(elapsed, 1)
        #expect(perMS > 1000, "Performance too low: \(perMS) per ms")
    }

    @Test("can produce nodes")
    func produceNodes() {
        let node = simple().cursorAt(pos: 8, side: 1).node
        #expect(node.name == "Br")
        #expect(node.from == 8)
        #expect(node.parent!.name == "Pa")
        #expect(node.parent!.from == 4)
        #expect(node.parent!.parent!.name == "T")
        #expect(node.parent!.parent!.from == 0)
        #expect(node.parent!.parent!.parent == nil)
    }

    @Test("skips anonymous nodes in cursor")
    func skipsAnonymousCursor() {
        let c = anonTree.cursor()
        c.moveTo(pos: 1)
        #expect(c.name == "T")
        _ = c.firstChild()
        #expect(c.name == "a")
        _ = c.nextSibling()
        #expect(c.name == "b")
        #expect(!c.next())
    }
}

@Suite("matchContext")
struct MatchContextTests {
    @Test("can match on nodes")
    func matchNodes() {
        #expect(simple().resolve(pos: 10, side: 1).matchContext(["T", "Pa", "Br"]))
    }

    @Test("can match wildcards")
    func matchWildcards() {
        #expect(simple().resolve(pos: 10, side: 1).matchContext(["T", "", "Br"]))
    }

    @Test("can mismatch on nodes")
    func mismatchNodes() {
        #expect(!simple().resolve(pos: 10, side: 1).matchContext(["Q", "Br"]))
    }

    @Test("can match on cursor")
    func matchCursor() {
        let cur = simple().cursor()
        for _ in 0..<3 { _ = cur.enter(15, side: -1) }
        #expect(cur.matchContext(["T", "Pa", "Br"]))
    }
}
