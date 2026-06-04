public struct ChangedRange {
    public let fromA: Int
    public let toA: Int
    public let fromB: Int
    public let toB: Int

    public init(fromA: Int, toA: Int, fromB: Int, toB: Int) {
        self.fromA = fromA
        self.toA = toA
        self.fromB = fromB
        self.toB = toB
    }
}

struct Open: OptionSet {
    let rawValue: Int
    static let start = Open(rawValue: 1)
    static let end = Open(rawValue: 2)
}

public final class TreeFragment {
    public let open: Int
    public let from: Int
    public let to: Int
    public let tree: Tree
    public let offset: Int

    public init(from: Int, to: Int, tree: Tree, offset: Int, openStart: Bool = false, openEnd: Bool = false) {
        self.from = from
        self.to = to
        self.tree = tree
        self.offset = offset
        self.open = (openStart ? Open.start.rawValue : 0) | (openEnd ? Open.end.rawValue : 0)
    }

    public var openStart: Bool { (open & Open.start.rawValue) > 0 }
    public var openEnd: Bool { (open & Open.end.rawValue) > 0 }

    public static func addTree(_ tree: Tree, fragments: [TreeFragment] = [], partial: Bool = false) -> [TreeFragment] {
        var result = [TreeFragment(from: 0, to: tree.length, tree: tree, offset: 0, openStart: false, openEnd: partial)]
        for f in fragments {
            if f.to > tree.length { result.append(f) }
        }
        return result
    }

    public static func applyChanges(_ fragments: [TreeFragment], changes: [ChangedRange], minGap: Int = 128) -> [TreeFragment] {
        if changes.isEmpty { return fragments }
        var result: [TreeFragment] = []
        var fI = 1
        var nextF: TreeFragment? = fragments.isEmpty ? nil : fragments[0]
        var pos = 0
        var off = 0
        var cI = 0

        while true {
            let nextC = cI < changes.count ? changes[cI] : nil
            let nextPos = nextC != nil ? nextC!.fromA : Int(1e9)
            if nextPos - pos >= minGap {
                while let nf = nextF, nf.from < nextPos {
                    var cut: TreeFragment? = nf
                    if pos >= cut!.from || nextPos <= cut!.to || off != 0 {
                        let fFrom = max(cut!.from, pos) - off
                        let fTo = min(cut!.to, nextPos) - off
                        cut = fFrom >= fTo
                            ? nil
                            : TreeFragment(from: fFrom, to: fTo, tree: cut!.tree, offset: cut!.offset + off, openStart: cI > 0, openEnd: nextC != nil)
                    }
                    if let cut = cut { result.append(cut) }
                    if nf.to > nextPos { break }
                    nextF = fI < fragments.count ? fragments[fI] : nil
                    fI += 1
                }
            }
            guard let nextC = nextC else { break }
            pos = nextC.toA
            off = nextC.toA - nextC.toB
            cI += 1
        }
        return result
    }
}
