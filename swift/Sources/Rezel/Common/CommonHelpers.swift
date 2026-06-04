func resolveNode(_ node: SyntaxNode, pos: Int, side: Int, overlays: Bool) -> SyntaxNode {
    var node = node
    while node.from == node.to ||
          (side < 1 ? node.from >= pos : node.from > pos) ||
          (side > -1 ? node.to <= pos : node.to < pos) {
        let parent: SyntaxNode? = !overlays && node is TreeNode && (node as! TreeNode).index < 0
            ? nil
            : node.parent
        guard let p = parent else { return node }
        node = p
    }

    let mode: IterMode = overlays ? [] : .ignoreOverlays

    if overlays {
        var scan: SyntaxNode? = node
        while let s = scan, let parent = s.parent {
            if let tn = s as? TreeNode, tn.index < 0 {
                if let entered = parent.enter(pos, side: side, mode: mode), entered.from != s.from {
                    node = parent
                }
            }
            scan = parent
        }
    }

    while true {
        guard let inner = node.enter(pos, side: side, mode: mode) else { return node }
        node = inner
    }
}

func CommonGetChildren(_ node: SyntaxNode, type: Any, before: Any?, after: Any?) -> [SyntaxNode] {
    let cur = node.cursor(mode: nil)
    var result: [SyntaxNode] = []
    if !cur.firstChild() { return result }
    if let before = before {
        var found = false
        while !found {
            found = cur.type.is(before)
            if !cur.nextSibling() { return result }
        }
    }
    while true {
        if let after = after, cur.type.is(after) { return result }
        if cur.type.is(type) { result.append(cur.node) }
        if !cur.nextSibling() { return after == nil ? result : [] }
    }
}

func matchNodeContext(_ node: SyntaxNode?, context: [String], startAt i: Int? = nil) -> Bool {
    var i = i ?? context.count - 1
    var p: SyntaxNode? = node
    while i >= 0 {
        guard let current = p else { return false }
        if !current.type.isAnonymous {
            if !context[i].isEmpty && context[i] != current.name { return false }
            i -= 1
        }
        p = current.parent
    }
    return true
}

func hasChild(tree: Tree) -> Bool {
    return tree.children.contains { ch in
        if ch is TreeBuffer { return true }
        if let t = ch as? Tree { return !t.type.isAnonymous || hasChild(tree: t) }
        return false
    }
}

func iterStack(_ heads: [SyntaxNode]) -> NodeIterator? {
    if heads.isEmpty { return nil }
    var pick = 0
    var picked = heads[0]
    for i in 1..<heads.count {
        let node = heads[i]
        if node.from > picked.from || node.to < picked.to {
            picked = node
            pick = i
        }
    }
    let next: SyntaxNode?
    if let tn = picked as? TreeNode, tn.index < 0 {
        next = nil
    } else {
        next = picked.parent
    }
    var newHeads = heads
    if let n = next {
        newHeads[pick] = n
    } else {
        newHeads.remove(at: pick)
    }
    return NodeIterator(node: picked, next: iterStack(newHeads))
}

func stackIterator(tree: Tree, pos: Int, side: Int) -> NodeIterator? {
    let inner = tree.resolveInner(pos: pos, side: side)
    var layers: [SyntaxNode]? = nil
    var scan: TreeNode? = inner is TreeNode
        ? (inner as! TreeNode)
        : (inner as! BufferNode).context.parent
    var skipMountCheck = false

    while let s = scan {
        if s.index < 0 {
            let parent = s._parent!
            if layers == nil { layers = [inner] }
            layers!.append(parent.resolve(pos, side: side))
            scan = parent
            skipMountCheck = true
        } else {
            if !skipMountCheck {
                let mount = MountedTree.get(s._tree)
                if let mount = mount, mount.overlay != nil,
                   mount.overlay![0].from <= pos,
                   mount.overlay![mount.overlay!.count - 1].to >= pos {
                    let root = TreeNode(tree: mount.tree, from: mount.overlay![0].from + s.from, index: -1, parent: s)
                    if layers == nil { layers = [inner] }
                    layers!.append(resolveNode(root, pos: pos, side: side, overlays: false))
                }
            }
            skipMountCheck = false
            scan = s._parent
        }
    }
    if let layers = layers { return iterStack(layers) }
    return nil
}
