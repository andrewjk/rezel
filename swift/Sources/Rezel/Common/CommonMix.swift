//
//  Mix.swift
//  Rezel
//
//  Created on 2025-06-02.
//

import Foundation

prefix operator !--

infix operator !--: AssignmentPrecedence

prefix func !--(value: inout Int) -> Int {
    value -= 1
    return value
}

/// Objects returned by the function passed to parseMixed should conform to this
/// interface.
public struct NestedParse {
    /// The parser to use for the inner region.
    public let parser: any Parser
    
    /// When this property is not given, the entire node is parsed with
    /// this parser, and it is mounted as a non-overlay node, replacing
    /// its host node in tree iteration.
    ///
    /// When an array of ranges is given, only those ranges are parsed,
    /// and the tree is mounted as an overlay.
    ///
    /// When a function is given, that function will be called for
    /// descendant nodes of the target node, not including child nodes
    /// that are covered by another nested parse, to determine the
    /// overlay ranges. When it returns true, the entire descendant is
    /// included, otherwise just the range given. The mixed parser will
    /// optimize range-finding in reused nodes, which means it's a good
    /// idea to use a function here when the target node is expected to
    /// have a large, deep structure.
    public let overlay: OverlayType?
    
    /// When `true`, indicates that this nested language is surrounded
    /// by some kind of bracket token, which can be used to make
    /// iteration eagerly enter such trees.
    public let bracketed: Bool
    
    public enum OverlayType {
        case ranges([Range])
        case predicate((SyntaxNodeRef) -> OverlayResult)
    }
    
    public struct OverlayResult {
        public let from: Int
        public let to: Int
        
        public init(from: Int, to: Int) {
            self.from = from
            self.to = to
        }
    }
    
    public init(
        parser: any Parser,
        overlay: OverlayType? = nil,
        bracketed: Bool = false
    ) {
        self.parser = parser
        self.overlay = overlay
        self.bracketed = bracketed
    }
}

/// Create a parse wrapper that, after the inner parse completes,
/// scans its tree for mixed language regions with the `nest`
/// function, runs the resulting inner parses,
/// and then mounts their results onto the tree.
public func parseMixed(
    nest: @escaping (SyntaxNodeRef, any Input) -> NestedParse?
) -> ParseWrapper {
    return { parse, input, fragments, ranges in
        return MixedParse(
            base: parse,
            nest: nest,
            input: input,
            fragments: fragments,
            ranges: ranges
        )
    }
}

internal final class InnerParse {
    let parser: any Parser
    let parse: any PartialParse
    let overlay: [Range]?
    let bracketed: Bool
    let target: Tree
    let from: Int
    
    init(
        parser: any Parser,
        parse: any PartialParse,
        overlay: [Range]?,
        bracketed: Bool,
        target: Tree,
        from: Int
    ) {
        self.parser = parser
        self.parse = parse
        self.overlay = overlay
        self.bracketed = bracketed
        self.target = target
        self.from = from
    }
}

internal func checkRanges(ranges: [Range]) {
    if ranges.isEmpty || ranges.contains(where: { $0.from >= $0.to }) {
        fatalError("Invalid inner parse ranges given: \(ranges)")
    }
}

internal final class ActiveOverlay {
    var depth = 0
    var ranges: [Range] = []
    
    let parser: any Parser
    let predicate: (SyntaxNodeRef) -> NestedParse.OverlayResult
    let mounts: [ReusableMount]
    let index: Int
    let start: Int
    let bracketed: Bool
    let target: Tree
    let prev: ActiveOverlay?
    
    init(
        parser: any Parser,
        predicate: @escaping (SyntaxNodeRef) -> NestedParse.OverlayResult,
        mounts: [ReusableMount],
        index: Int,
        start: Int,
        bracketed: Bool,
        target: Tree,
        prev: ActiveOverlay?
    ) {
        self.parser = parser
        self.predicate = predicate
        self.mounts = mounts
        self.index = index
        self.start = start
        self.bracketed = bracketed
        self.target = target
        self.prev = prev
    }
}

internal class CoverInfo {
    var ranges: [Range]
    var depth: Int
    weak var prev: CoverInfo?
    
    init(ranges: [Range], depth: Int, prev: CoverInfo?) {
        self.ranges = ranges
        self.depth = depth
        self.prev = prev
    }
}

nonisolated(unsafe) internal let stoppedInner = NodeProp<Int>(config: NodePropConfig(perNode: true))

internal final class MixedParse: PartialParse {
    var baseParse: (any PartialParse)?
    var inner: [InnerParse] = []
    var innerDone = 0
    var baseTree: Tree?
    var stoppedAt: Int?
    
    let nest: (SyntaxNodeRef, any Input) -> NestedParse?
    let input: any Input
    let fragments: [TreeFragment]
    let ranges: [Range]
    
    init(
        base: any PartialParse,
        nest: @escaping (SyntaxNodeRef, any Input) -> NestedParse?,
        input: any Input,
        fragments: [TreeFragment],
        ranges: [Range]
    ) {
        self.baseParse = base
        self.nest = nest
        self.input = input
        self.fragments = fragments
        self.ranges = ranges
    }
    
    func advance() -> Tree? {
        if let baseParse = baseParse {
            let done = baseParse.advance()
            if done == nil {
                return nil
            }
            self.baseParse = nil
            self.baseTree = done
            startInner()
            if let stoppedAt = stoppedAt {
                for inner in self.inner {
                    inner.parse.stopAt(pos: stoppedAt)
                }
            }
        }
        
        if innerDone == inner.count {
            var result = baseTree!
            if let stoppedAt = stoppedAt {
                let propValues = result.propValues + [PropPair(propId: stoppedInner.id, value: stoppedAt)]
                result = Tree(
                    type: result.type,
                    children: result.children,
                    positions: result.positions,
                    length: result.length,
                    props: propValues
                )
            }
            return result
        }
        
        let inner = self.inner[self.innerDone]
        let done = inner.parse.advance()
        if let done = done {
            self.innerDone += 1
            var props = inner.target.props ?? [:]
            let mountedTree = MountedTree(
                tree: done,
                overlay: inner.overlay,
                parser: inner.parser,
                bracketed: inner.bracketed
            )
            props[nodePropMounted.id] = mountedTree
            inner.target.props = props
        }
        return nil
    }
    
    var parsedPos: Int {
        if baseParse != nil {
            return 0
        }
        var pos = input.length
        for i in innerDone..<inner.count {
            if inner[i].from < pos {
                pos = min(pos, inner[i].parse.parsedPos)
            }
        }
        return pos
    }
    
    func stopAt(pos: Int) {
        stoppedAt = pos
        if let baseParse = baseParse {
            baseParse.stopAt(pos: pos)
        } else {
            for i in innerDone..<inner.count {
                inner[i].parse.stopAt(pos: pos)
            }
        }
    }
    
    func startInner() {
        let fragmentCursor = FragmentCursor(fragments: fragments)
        var overlay: ActiveOverlay? = nil
        var covered: CoverInfo? = nil
        let treeNode = TreeNode(tree: baseTree!, from: ranges[0].from, index: 0, parent: nil)
        let cursor = TreeCursor(
            treeNode: treeNode,
            bufferNode: nil,
            mode: IterMode.includeAnonymous.union(IterMode.ignoreMounts)
        )
        
        scan: while true {
            var enter = true
            
            if let stoppedAt = stoppedAt, cursor.from >= stoppedAt {
                enter = false
            } else if fragmentCursor.hasNode(node: cursor) {
                if let overlay = overlay {
                    if let match = overlay.mounts.first(where: { m in
                        m.frag.from <= cursor.from && m.frag.to >= cursor.to && m.mount.overlay != nil
                    }) {
                        if let mountOverlay = match.mount.overlay {
                            for r in mountOverlay {
                                let from = r.from + match.pos
                                let to = r.to + match.pos
                                if from >= cursor.from && to <= cursor.to && !overlay.ranges.contains(where: { r in
                                    r.from < to && r.to > from
                                }) {
                                    overlay.ranges.append(Range(from: from, to: to))
                                }
                            }
                        }
                    }
                }
                enter = false
            } else if let covered = covered,
                      let isCovered = checkCover(covered: covered.ranges, from: cursor.from, to: cursor.to) {
                enter = isCovered != .full
            } else if !cursor.type.isAnonymous,
                      let nest = nest(cursor, input),
                      (cursor.from < cursor.to || nest.overlay == nil) {
                if cursor.tree == nil {
                    materialize(cursor: cursor)
                    if overlay != nil {
                        overlay!.depth += 1
                    }
                    if covered != nil {
                        covered!.depth += 1
                    }
                }
                
                let oldMounts = fragmentCursor.findMounts(pos: cursor.from, parser: nest.parser)
                
                if case .predicate(let predicate) = nest.overlay {
                    overlay = ActiveOverlay(
                        parser: nest.parser,
                        predicate: predicate,
                        mounts: oldMounts,
                        index: inner.count,
                        start: cursor.from,
                        bracketed: nest.bracketed,
                        target: cursor.tree!,
                        prev: overlay
                    )
                } else {
                    var overlayRanges: [Range] = []
                    if case .ranges(let ranges) = nest.overlay {
                        overlayRanges = ranges
                    } else if cursor.from < cursor.to {
                        overlayRanges = [Range(from: cursor.from, to: cursor.to)]
                    }
                    
                    let ranges = punchRanges(outer: self.ranges, ranges: overlayRanges)
                    if !ranges.isEmpty {
                        checkRanges(ranges: ranges)
                    }
                    
                    if !ranges.isEmpty || nest.overlay == nil {
                        let fragmentsToUse: [TreeFragment]
                        if ranges.isEmpty {
                            fragmentsToUse = []
                        } else {
                            fragmentsToUse = enterFragments(mounts: oldMounts, ranges: ranges)
                        }
                        
                        let parse: any PartialParse
                        if ranges.isEmpty {
                            parse = nest.parser.startParse(input: StringInput(string: ""))
                        } else {
                            parse = nest.parser.startParse(input: input, fragments: fragmentsToUse, ranges: ranges)
                        }
                        
                        let mappedOverlay: [Range]?
                        if case .ranges(let overlay) = nest.overlay {
                            mappedOverlay = overlay.map { r in
                                Range(from: r.from - cursor.from, to: r.to - cursor.from)
                            }
                        } else {
                            mappedOverlay = nil
                        }
                        
                        inner.append(InnerParse(
                            parser: nest.parser,
                            parse: parse,
                            overlay: mappedOverlay,
                            bracketed: nest.bracketed,
                            target: cursor.tree!,
                            from: ranges.isEmpty ? cursor.from : ranges[0].from
                        ))
                    }
                    
                    if nest.overlay == nil {
                        enter = false
                    } else if !ranges.isEmpty {
                        covered = CoverInfo(ranges: ranges, depth: 0, prev: covered)
                    }
                }
            } else if let overlay = overlay {
                let rangeResult = overlay.predicate(cursor)
                if rangeResult.from < rangeResult.to {
                    let last = overlay.ranges.count - 1
                    if last >= 0 && overlay.ranges[last].to == rangeResult.from {
                        overlay.ranges[last] = Range(from: overlay.ranges[last].from, to: rangeResult.to)
                    } else {
                        overlay.ranges.append(Range(from: rangeResult.from, to: rangeResult.to))
                    }
                }
            }
            
            if enter && cursor.firstChild() {
                if overlay != nil {
                    overlay!.depth += 1
                }
                if covered != nil {
                    covered!.depth += 1
                }
            } else {
                while true {
                    if cursor.nextSibling() {
                        break
                    }
                    if !cursor.parent() {
                        break scan
                    }
                    
                    if let currentOverlay = overlay {
                        currentOverlay.depth -= 1
                        if currentOverlay.depth == 0 {
                            let sortedRanges = currentOverlay.ranges.sorted { $0.from < $1.from }
                            let ranges = punchRanges(outer: self.ranges, ranges: sortedRanges)
                            if !ranges.isEmpty {
                                checkRanges(ranges: ranges)
                                let fragmentsToUse = enterFragments(mounts: currentOverlay.mounts, ranges: ranges)
                                let parse = currentOverlay.parser.startParse(input: input, fragments: fragmentsToUse, ranges: ranges)
                                let mappedRanges = sortedRanges.map { r in
                                    Range(from: r.from - currentOverlay.start, to: r.to - currentOverlay.start)
                                }
                                
                                let innerParse = InnerParse(
                                    parser: currentOverlay.parser,
                                    parse: parse,
                                    overlay: mappedRanges,
                                    bracketed: currentOverlay.bracketed,
                                    target: currentOverlay.target,
                                    from: ranges[0].from
                                )
                                
                                inner.insert(innerParse, at: currentOverlay.index)
                            }
                            overlay = currentOverlay.prev
                        }
                    }
                    
                    if let currentCovered = covered {
                        currentCovered.depth -= 1
                        if currentCovered.depth == 0 {
                            covered = currentCovered.prev
                        }
                    }
                }
            }
        }
    }
}

internal enum Cover: Int {
    case none = 0
    case partial = 1
    case full = 2
}

internal func checkCover(covered: [Range], from: Int, to: Int) -> Cover? {
    for range in covered {
        if range.from >= to {
            break
        }
        if range.to > from {
            return range.from <= from && range.to >= to ? .full : .partial
        }
    }
    return Cover.none
}

internal func sliceBuf(
    buf: TreeBuffer,
    startI: Int,
    endI: Int,
    nodes: inout [TreeOrBuffer],
    positions: inout [Int],
    off: Int
) {
    if startI < endI {
        let from = Int(buf.buffer[startI + 1])
        nodes.append(.buffer(buf.slice(startI: startI, endI: endI, from: from)))
        positions.append(from - off)
    }
}

internal func materialize(cursor: TreeCursor) {
    let node = cursor.node
    var stack: [Int] = []
    let buffer = (node as! BufferNode).context.buffer
    
    repeat {
        stack.append(cursor.index)
        _ = cursor.parent()
    } while cursor.tree == nil
    
    let base = cursor.tree!
    let i = base.children.firstIndex(of: .buffer(buffer))!
    guard case .buffer(let buf) = base.children[i] else { fatalError("Expected buffer") }
    let b = buf.buffer
    var newStack: [Int] = [i]
    
    func split(
        startI: Int,
        endI: Int,
        type: NodeType,
        innerOffset: Int,
        length: Int,
        stackPos: Int
    ) -> Tree {
        let targetI = stack[stackPos]
        var children: [TreeOrBuffer] = []
        var positions: [Int] = []
        
        sliceBuf(buf: buf, startI: startI, endI: targetI, nodes: &children, positions: &positions, off: innerOffset)
        
        let from = Int(b[targetI + 1])
        let to = Int(b[targetI + 2])
        newStack.append(children.count)
        
        let child: TreeOrBuffer
        if stackPos > 0 {
            let childTree = split(
                startI: targetI + 4,
                endI: Int(b[targetI + 3]),
                type: buf.set.types[Int(b[targetI])],
                innerOffset: from,
                length: to - from,
                stackPos: stackPos - 1
            )
            child = .tree(childTree)
        } else {
            child = .tree(node.toTree())
        }
        
        children.append(child)
        positions.append(from - innerOffset)
        
        sliceBuf(buf: buf, startI: Int(b[targetI + 3]), endI: endI, nodes: &children, positions: &positions, off: innerOffset)
        
        return Tree(type: type, children: children, positions: positions, length: length)
    }
    
    base.children[i] = .tree(split(startI: 0, endI: b.count, type: NodeType.none, innerOffset: 0, length: buf.length, stackPos: stack.count - 1))
    
    for index in newStack {
        if case .tree(let tree) = cursor.tree!.children[index] {
            let pos = cursor.tree!.positions[index]
            _ = cursor.yield(treeNode: TreeNode(tree: tree, from: pos + cursor.from, index: index, parent: cursor._tree), bufferNode: nil)
        }
    }
}

internal final class StructureCursor {
    var cursor: TreeCursor
    var done = false
    
    private let offset: Int
    
    init(root: Tree, offset: Int) {
        self.offset = offset
        self.cursor = root.cursor(mode: IterMode.includeAnonymous.union(IterMode.ignoreMounts))
    }
    
    func moveTo(pos: Int) {
        let p = pos - offset
        while !done && cursor.from < p {
            if cursor.to >= pos &&
               cursor.enter(pos: p, side: 1, mode: IterMode.ignoreOverlays.union(IterMode.excludeBuffers)) {
                // Entered
            } else if cursor.to <= pos {
                if !cursor.next(enter: false) {
                    done = true
                }
            } else {
                break
            }
        }
    }
    
    func hasNode(cursor: TreeCursor) -> Bool {
        moveTo(pos: cursor.from)
        if !done && self.cursor.from + offset == cursor.from && self.cursor.tree != nil {
            var tree: Tree? = self.cursor.tree
            while let currentTree = tree {
                if currentTree === cursor.tree {
                    return true
                }
                if !currentTree.children.isEmpty && currentTree.positions[0] == 0 {
                    if case .tree(let childTree) = currentTree.children[0] {
                        tree = childTree
                    } else {
                        break
                    }
                } else {
                    break
                }
            }
        }
        return false
    }
}

internal final class FragmentCursor {
    var curFrag: TreeFragment?
    var curTo = 0
    var fragI = 0
    var inner: StructureCursor?
    
    let fragments: [TreeFragment]
    
    init(fragments: [TreeFragment]) {
        self.fragments = fragments
        if !fragments.isEmpty {
            curFrag = fragments[0]
            curTo = curFrag!.tree.prop(prop: stoppedInner) ?? curFrag!.to
            inner = StructureCursor(root: curFrag!.tree, offset: -curFrag!.offset)
        } else {
            curFrag = nil
            inner = nil
        }
    }
    
    func hasNode(node: TreeCursor) -> Bool {
        while let _ = curFrag, node.from >= curTo {
            nextFrag()
        }
        
        return curFrag != nil &&
               curFrag!.from <= node.from &&
               curTo >= node.to &&
               inner!.hasNode(cursor: node)
    }
    
    func nextFrag() {
        fragI += 1
        if fragI == fragments.count {
            curFrag = nil
            inner = nil
        } else {
            curFrag = fragments[fragI]
            curTo = curFrag!.tree.prop(prop: stoppedInner) ?? curFrag!.to
            inner = StructureCursor(root: curFrag!.tree, offset: -curFrag!.offset)
        }
    }
    
    func findMounts(pos: Int, parser: any Parser) -> [ReusableMount] {
        var result: [ReusableMount] = []
        if let inner = inner {
            _ = inner.cursor.moveTo(pos: pos)
            var posNode: SyntaxNode? = inner.cursor.node
            while let currentPos = posNode {
                if let mount = currentPos.tree?.prop(prop: nodePropMounted),
                   mount.parser === parser {
                    for i in fragI..<fragments.count {
                        let frag = fragments[i]
                        if frag.from >= currentPos.to {
                            break
                        }
                        if frag.tree === curFrag?.tree {
                            result.append(ReusableMount(frag: frag, mount: mount, pos: currentPos.from - frag.offset))
                        }
                    }
                }
                posNode = currentPos.parent
            }
        }
        return result
    }
}

internal func punchRanges(outer: [Range], ranges: [Range]) -> [Range] {
    var copy: [Range]? = nil
    var current = ranges
    
    for i in 1..<outer.count {
        let gapFrom = outer[i - 1].to
        let gapTo = outer[i].from
        var j = 0
        
        while j < current.count {
            let r = current[j]
            if r.from >= gapTo {
                break
            }
            if r.to <= gapFrom {
                j += 1
                continue
            }
            
            if copy == nil {
                current = ranges
                copy = ranges
            }
            
            if r.from < gapFrom {
                copy?[j] = Range(from: r.from, to: gapFrom)
                if r.to > gapTo {
                    copy?.insert(Range(from: gapTo, to: r.to), at: j + 1)
                    j += 2
                } else {
                    j += 1
                }
            } else if r.to > gapTo {
                copy?[j] = Range(from: gapTo, to: r.to)
            } else {
                copy?.remove(at: j)
            }
            
            j += 1
        }
    }
    
    return current
}

internal struct ReusableMount {
    let frag: TreeFragment
    let mount: MountedTree
    let pos: Int
}

internal func findCoverChanges(
    a: [Range],
    b: [Range],
    from: Int,
    to: Int
) -> [Range] {
    var iA = 0
    var iB = 0
    var inA = false
    var inB = false
    var pos = -1_000_000_000
    var result: [Range] = []
    
    while true {
        let nextA = iA == a.count ? 1_000_000_000 : (inA ? a[iA].to : a[iA].from)
        let nextB = iB == b.count ? 1_000_000_000 : (inB ? b[iB].to : b[iB].from)
        
        if inA != inB {
            let start = max(pos, from)
            let end = min(nextA, nextB, to)
            if start < end {
                result.append(Range(from: start, to: end))
            }
        }
        
        pos = min(nextA, nextB)
        if pos == 1_000_000_000 {
            break
        }
        
        if nextA == pos {
            if !inA {
                inA = true
            } else {
                inA = false
                iA += 1
            }
        }
        
        if nextB == pos {
            if !inB {
                inB = true
            } else {
                inB = false
                iB += 1
            }
        }
    }
    
    return result
}

internal func enterFragments(mounts: [ReusableMount], ranges: [Range]) -> [TreeFragment] {
    var result: [TreeFragment] = []
    
    for mount in mounts {
        let startPos = mount.pos + (mount.mount.overlay?[0].from ?? 0)
        let endPos = startPos + mount.mount.tree.length
        let from = max(mount.frag.from, startPos)
        let to = min(mount.frag.to, endPos)
        
        if let overlay = mount.mount.overlay {
            let overlayWithPos = overlay.map { r in
                Range(from: r.from + mount.pos, to: r.to + mount.pos)
            }
            let changes = findCoverChanges(a: ranges, b: overlayWithPos, from: from, to: to)
            var currentPos = from
            
            for (i, change) in changes.enumerated() {
                let last = i == changes.count - 1
                let end = last ? to : change.from
                
                if end > currentPos {
                    result.append(TreeFragment(
                        from: currentPos,
                        to: end,
                        tree: mount.mount.tree,
                        offset: -startPos,
                        openStart: mount.frag.from >= currentPos || mount.frag.openStart,
                        openEnd: mount.frag.to <= end || mount.frag.openEnd
                    ))
                }
                
                if last {
                    break
                }
                currentPos = change.to
            }
        } else {
            result.append(TreeFragment(
                from: from,
                to: to,
                tree: mount.mount.tree,
                offset: -startPos,
                openStart: mount.frag.from >= startPos || mount.frag.openStart,
                openEnd: mount.frag.to <= endPos || mount.frag.openEnd
            ))
        }
    }
    
    return result
}
