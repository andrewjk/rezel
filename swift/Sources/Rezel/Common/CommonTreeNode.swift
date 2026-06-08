public class TreeNode: SyntaxNode {
	let _tree: Tree
	public let from: Int
	public let index: Int
	public let _parent: TreeNode?

	public init(tree: Tree, from: Int, index: Int, parent: TreeNode?) {
		_tree = tree
		self.from = from
		self.index = index
		_parent = parent
	}

	public var type: NodeType {
		_tree.type
	}

	public var name: String {
		_tree.type.name
	}

	public var to: Int {
		from + _tree.length
	}

	public var tree: Tree? {
		_tree
	}

	public var node: SyntaxNode {
		self
	}

	func nextChild(
		_ i: Int, dir: Int, pos: Int, side: Side, mode: IterMode = []
	) -> SyntaxNode? {
		var parent: TreeNode = self
		var i = i
		while true {
			let children = parent._tree.children
			let positions = parent._tree.positions
			let e = dir > 0 ? children.count : -1
			while i != e {
				let next = children[i]
				let start = positions[i] + parent.from

				if mode.contains(.enterBracketed),
				   let treeNext = next as? Tree,
				   let mounted = MountedTree.get(treeNext),
				   mounted.overlay == nil,
				   mounted.bracketed,
				   pos >= start,
				   pos <= start + treeNext.length
				{
					// Enter bracketed
				} else if !checkSide(side, pos: pos, from: start, to: start + (next is Tree ? (next as! Tree).length : (next as! TreeBuffer).length)) {
					i += dir
					continue
				}

				if let buf = next as? TreeBuffer {
					if mode.contains(.excludeBuffers) { i += dir; continue }
					let index = buf.findChild(startIndex: 0, endIndex: buf.buffer.count, dir: dir, pos: pos - start, side: side)
					if index > -1 {
						let ctx = BufferContext(parent: parent, buffer: buf, index: i, start: start)
						return BufferNode(context: ctx, parent: nil, index: index)
					}
				} else if let treeNext = next as? Tree {
					if !mode.contains(.includeAnonymous) && treeNext.type.isAnonymous && !hasChild(tree: treeNext) {
						i += dir
						continue
					}
					if !mode.contains(.ignoreMounts), let mounted = MountedTree.get(treeNext), mounted.overlay == nil {
						return TreeNode(tree: mounted.tree, from: start, index: i, parent: parent)
					}
					let inner = TreeNode(tree: treeNext, from: start, index: i, parent: parent)
					if mode.contains(.includeAnonymous) || !inner.type.isAnonymous {
						return inner
					}
					return inner.nextChild(dir < 0 ? treeNext.children.count - 1 : 0, dir: dir, pos: pos, side: side, mode: mode)
				}
				i += dir
			}

			if mode.contains(.includeAnonymous) || !parent.type.isAnonymous { return nil }
			if parent.index >= 0 {
				i = parent.index + dir
			} else {
				i = dir < 0 ? -1 : parent._parent!._tree.children.count
			}
			guard let p = parent._parent else { return nil }
			parent = p
		}
	}

	public var firstChild: SyntaxNode? {
		return nextChild(0, dir: 1, pos: 0, side: .dontCare)
	}

	public var lastChild: SyntaxNode? {
		return nextChild(_tree.children.count - 1, dir: -1, pos: 0, side: .dontCare)
	}

	public func childAfter(_ pos: Int) -> SyntaxNode? {
		return nextChild(0, dir: 1, pos: pos, side: .after)
	}

	public func childBefore(_ pos: Int) -> SyntaxNode? {
		return nextChild(_tree.children.count - 1, dir: -1, pos: pos, side: .before)
	}

	public func prop<T>(_ prop: NodeProp<T>) -> T? {
		return _tree.prop(prop)
	}

	public func enter(_ pos: Int, side: Int, mode: IterMode? = nil) -> SyntaxNode? {
		let mode = mode ?? []
		if !mode.contains(.ignoreOverlays), let mounted = MountedTree.get(_tree), mounted.overlay != nil {
			let rPos = pos - from
			let enterBracketed = mode.contains(.enterBracketed) && mounted.bracketed
			for range in mounted.overlay! {
				let ok1 = side > 0 || enterBracketed ? range.from <= rPos : range.from < rPos
				let ok2 = side < 0 || enterBracketed ? range.to >= rPos : range.to > rPos
				if ok1, ok2 {
					return TreeNode(tree: mounted.tree, from: mounted.overlay![0].from + from, index: -1, parent: self)
				}
			}
		}
		return nextChild(0, dir: 1, pos: pos, side: Side(rawValue: side) ?? .around, mode: mode)
	}

	func nextSignificantParent() -> TreeNode {
		var val: TreeNode = self
		while val.type.isAnonymous, let p = val._parent {
			val = p
		}
		return val
	}

	public var parent: SyntaxNode? {
		return _parent?._parent != nil ? _parent!.nextSignificantParent() : _parent
	}

	public var nextSibling: SyntaxNode? {
		guard let p = _parent, index >= 0 else { return nil }
		return p.nextChild(index + 1, dir: 1, pos: 0, side: .dontCare)
	}

	public var prevSibling: SyntaxNode? {
		guard let p = _parent, index >= 0 else { return nil }
		return p.nextChild(index - 1, dir: -1, pos: 0, side: .dontCare)
	}

	public func toTree() -> Tree {
		_tree
	}

	public func cursor(mode: IterMode? = nil) -> TreeCursor {
		return TreeCursor(node: self, mode: mode ?? [])
	}

	public func resolve(_ pos: Int, side: Int = 0) -> SyntaxNode {
		return resolveNode(self, pos: pos, side: side, overlays: false)
	}

	public func resolveInner(_ pos: Int, side: Int = 0) -> SyntaxNode {
		return resolveNode(self, pos: pos, side: side, overlays: true)
	}

	public func enterUnfinishedNodesBefore(_ pos: Int) -> SyntaxNode {
		var scan = childBefore(pos)
		var node: SyntaxNode = self
		while let s = scan {
			guard let last = s.lastChild else { break }
			if last.to != s.to { break }
			if last.type.isError && last.from == last.to {
				node = s
				scan = last.prevSibling
			} else {
				scan = last
			}
		}
		return node
	}

	public func matchContext(_ context: [String]) -> Bool {
		return matchNodeContext(parent, context: context)
	}

	public func getChild(_ type: Any, before: Any? = nil, after: Any? = nil) -> SyntaxNode? {
		let r = getChildren(type, before: before, after: after)
		return r.first
	}

	public func getChildren(_ type: Any, before: Any? = nil, after: Any? = nil) -> [SyntaxNode] {
		return CommonGetChildren(self, type: type, before: before, after: after)
	}
}
