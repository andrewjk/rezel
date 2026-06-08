public class BufferNode: SyntaxNode {
	public let type: NodeType
	public var name: String {
		type.name
	}

	public var from: Int {
		context.start + Int(context.buffer.buffer[index + 1])
	}

	public var to: Int {
		context.start + Int(context.buffer.buffer[index + 2])
	}

	public let context: BufferContext
	public let _parent: BufferNode?
	public let index: Int

	public init(context: BufferContext, parent: BufferNode?, index: Int) {
		self.context = context
		_parent = parent
		self.index = index
		type = context.buffer.set.types[Int(context.buffer.buffer[index])]
	}

	func child(_ dir: Int, pos: Int, side: Side) -> BufferNode? {
		let buffer = context.buffer
		let idx = buffer.findChild(
			startIndex: index + 4,
			endIndex: Int(buffer.buffer[index + 3]),
			dir: dir,
			pos: pos - context.start,
			side: side
		)
		return idx < 0 ? nil : BufferNode(context: context, parent: self, index: idx)
	}

	public var firstChild: SyntaxNode? {
		child(1, pos: 0, side: .dontCare)
	}

	public var lastChild: SyntaxNode? {
		child(-1, pos: 0, side: .dontCare)
	}

	public func childAfter(_ pos: Int) -> SyntaxNode? {
		child(1, pos: pos, side: .after)
	}

	public func childBefore(_ pos: Int) -> SyntaxNode? {
		child(-1, pos: pos, side: .before)
	}

	public func prop<T>(_ prop: NodeProp<T>) -> T? {
		type.prop(prop)
	}

	public func enter(_ pos: Int, side: Int, mode: IterMode? = nil) -> SyntaxNode? {
		let mode = mode ?? []
		if mode.contains(.excludeBuffers) { return nil }
		let buffer = context.buffer
		let idx = buffer.findChild(
			startIndex: index + 4,
			endIndex: Int(buffer.buffer[index + 3]),
			dir: side > 0 ? 1 : -1,
			pos: pos - context.start,
			side: Side(rawValue: side) ?? .around
		)
		return idx < 0 ? nil : BufferNode(context: context, parent: self, index: idx)
	}

	public var parent: SyntaxNode? {
		return _parent ?? context.parent.nextSignificantParent()
	}

	func externalSibling(_ dir: Int) -> SyntaxNode? {
		if _parent != nil { return nil }
		return context.parent.nextChild(context.index + dir, dir: dir, pos: 0, side: .dontCare)
	}

	public var nextSibling: SyntaxNode? {
		let buffer = context.buffer
		let after = Int(buffer.buffer[index + 3])
		let parentEnd = _parent != nil ? Int(buffer.buffer[_parent!.index + 3]) : buffer.buffer.count
		if after < parentEnd {
			return BufferNode(context: context, parent: _parent, index: after)
		}
		return externalSibling(1)
	}

	public var prevSibling: SyntaxNode? {
		let buffer = context.buffer
		let parentStart = _parent != nil ? _parent!.index + 4 : 0
		if index == parentStart { return externalSibling(-1) }
		let idx = buffer.findChild(startIndex: parentStart, endIndex: index, dir: -1, pos: 0, side: .dontCare)
		return BufferNode(context: context, parent: _parent, index: idx)
	}

	public var tree: Tree? {
		nil
	}

	public func toTree() -> Tree {
		var children: [Any] = []
		var positions: [Int] = []
		let buffer = context.buffer
		let startI = index + 4
		let endI = Int(buffer.buffer[index + 3])
		if endI > startI {
			let from = Int(buffer.buffer[index + 1])
			children.append(buffer.slice(startI: startI, endI: endI, from: from))
			positions.append(0)
		}
		return Tree(type: type, children: children, positions: positions, length: to - from)
	}

	public var node: SyntaxNode {
		self
	}

	public func matchContext(_ context: [String]) -> Bool {
		return matchNodeContext(parent, context: context)
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

	public func getChild(_ type: Any, before: Any? = nil, after: Any? = nil) -> SyntaxNode? {
		let r = getChildren(type, before: before, after: after)
		return r.first
	}

	public func getChildren(_ type: Any, before: Any? = nil, after: Any? = nil) -> [SyntaxNode] {
		return CommonGetChildren(self, type: type, before: before, after: after)
	}
}
