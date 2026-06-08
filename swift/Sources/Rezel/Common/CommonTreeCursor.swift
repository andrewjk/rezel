public final class TreeCursor: SyntaxNodeRef {
	public var type: NodeType
	public var from: Int
	public var to: Int
	public var name: String {
		type.name
	}

	public var _tree: TreeNode
	public var buffer: BufferContext?
	var stack: [Int] = []
	public var index: Int = 0
	var bufferNode: BufferNode?
	public let mode: IterMode

	public init(node: SyntaxNode, mode: IterMode = []) {
		self.mode = mode.subtracting(.enterBracketed)
		if let treeNode = node as? TreeNode {
			_tree = treeNode
			type = treeNode.type
			from = treeNode.from
			to = treeNode.to
			buffer = nil
		} else if let bufNode = node as? BufferNode {
			_tree = bufNode.context.parent
			buffer = bufNode.context
			type = bufNode.type
			from = bufNode.from
			to = bufNode.to
			index = bufNode.index
			var n: BufferNode? = bufNode._parent
			while let p = n {
				stack.insert(p.index, at: 0)
				n = p._parent
			}
			bufferNode = bufNode
		} else {
			fatalError("Unknown node type")
		}
	}

	@inline(__always)
	func yieldNode(_ node: TreeNode?) -> Bool {
		guard let node = node else { return false }
		_tree = node
		type = node.type
		from = node.from
		to = node.to
		return true
	}

	@inline(__always)
	func yieldBuf(_ index: Int, typeOverride: NodeType? = nil) -> Bool {
		self.index = index
		guard let buf = buffer else { return false }
		type = typeOverride ?? buf.buffer.set.types[Int(buf.buffer.buffer[index])]
		from = buf.start + Int(buf.buffer.buffer[index + 1])
		to = buf.start + Int(buf.buffer.buffer[index + 2])
		return true
	}

	@inline(__always)
	public func yield(_ node: SyntaxNode?) -> Bool {
		guard let node = node else { return false }
		if let treeNode = node as? TreeNode {
			buffer = nil
			return yieldNode(treeNode)
		}
		if let bufNode = node as? BufferNode {
			buffer = bufNode.context
			return yieldBuf(bufNode.index, typeOverride: bufNode.type)
		}
		return false
	}

	public var ref: SyntaxNodeRef {
		return self
	}

	public var tree: Tree? {
		return buffer != nil ? nil : _tree._tree
	}

	public var node: SyntaxNode {
		if buffer == nil { return _tree }
		let cache = bufferNode
		var result: BufferNode? = nil
		var depth = 0
		if let cache = cache, cache.context === buffer! {
			var idx = index
			var d = stack.count
			scan: while d >= 0 {
				var c: BufferNode? = cache
				while let cc = c {
					if cc.index == idx {
						if idx == index { return cc }
						result = cc
						depth = d + 1
						break scan
					}
					c = cc._parent
				}
				d -= 1
				if d >= 0 { idx = stack[d] }
			}
		}
		for i in depth ..< stack.count {
			result = BufferNode(context: buffer!, parent: result, index: stack[i])
		}
		let bn = BufferNode(context: buffer!, parent: result, index: index)
		bufferNode = bn
		return bn
	}

	public func matchContext(_ context: [String]) -> Bool {
		if buffer == nil { return matchNodeContext(node.parent, context: context) }
		let buf = buffer!
		let types = buf.buffer.set.types
		var i = context.count - 1
		var d = stack.count - 1
		while i >= 0 {
			if d < 0 { return matchNodeContext(_tree, context: context, startAt: i) }
			let t = types[Int(buf.buffer.buffer[stack[d]])]
			if !t.isAnonymous {
				if !context[i].isEmpty && context[i] != t.name { return false }
				i -= 1
			}
			d -= 1
		}
		return true
	}

	@inline(__always)
	func enterChild(_ dir: Int, pos: Int, side: Side) -> Bool {
		if buffer == nil {
			let children = _tree._tree.children
			return yield(_tree.nextChild(
				dir < 0 ? children.count - 1 : 0,
				dir: dir, pos: pos, side: side, mode: mode
			))
		}
		guard let buf = buffer else { return false }
		let idx = buf.buffer.findChild(
			startIndex: index + 4,
			endIndex: Int(buf.buffer.buffer[index + 3]),
			dir: dir,
			pos: pos - buf.start,
			side: side
		)
		if idx < 0 { return false }
		stack.append(index)
		return yieldBuf(idx)
	}

	public func firstChild() -> Bool {
		enterChild(1, pos: 0, side: .dontCare)
	}

	public func lastChild() -> Bool {
		enterChild(-1, pos: 0, side: .dontCare)
	}

	public func childAfter(_ pos: Int) -> Bool {
		enterChild(1, pos: pos, side: .after)
	}

	public func childBefore(_ pos: Int) -> Bool {
		enterChild(-1, pos: pos, side: .before)
	}

	public func enter(_ pos: Int, side: Int, mode: IterMode? = nil) -> Bool {
		let mode = mode ?? self.mode
		if buffer == nil { return yield(_tree.enter(pos, side: side, mode: mode)) }
		if mode.contains(.excludeBuffers) { return false }
		return enterChild(1, pos: pos, side: Side(rawValue: side) ?? .around)
	}

	@discardableResult
	public func parent() -> Bool {
		if buffer == nil {
			let p = mode.contains(.includeAnonymous) ? _tree._parent : _tree.parent
			return yieldNode(p as? TreeNode)
		}
		if !stack.isEmpty { return yieldBuf(stack.removeLast()) }
		let p = mode.contains(.includeAnonymous)
			? buffer!.parent
			: buffer!.parent.nextSignificantParent()
		buffer = nil
		return yieldNode(p)
	}

	@inline(__always)
	func sibling(_ dir: Int) -> Bool {
		if buffer == nil {
			guard _tree._parent != nil else { return false }
			if _tree.index < 0 { return false }
			return yield(_tree._parent!.nextChild(
				_tree.index + dir, dir: dir, pos: 0, side: .dontCare, mode: mode
			))
		}
		guard let buf = buffer else { return false }
		let d = stack.count - 1
		if dir < 0 {
			let parentStart = d < 0 ? 0 : stack[d] + 4
			if index != parentStart {
				return yieldBuf(buf.buffer.findChild(startIndex: parentStart, endIndex: index, dir: -1, pos: 0, side: .dontCare))
			}
		} else {
			let after = Int(buf.buffer.buffer[index + 3])
			let parentEnd = d < 0 ? buf.buffer.buffer.count : Int(buf.buffer.buffer[stack[d] + 3])
			if after < parentEnd { return yieldBuf(after) }
		}
		if d < 0 {
			return yield(buf.parent.nextChild(buf.index + dir, dir: dir, pos: 0, side: .dontCare, mode: mode))
		}
		return false
	}

	public func nextSibling() -> Bool {
		sibling(1)
	}

	public func prevSibling() -> Bool {
		sibling(-1)
	}

	func atLastNode(_ dir: Int) -> Bool {
		var idx: Int
		var parent: TreeNode?
		if let buf = buffer {
			if dir > 0 {
				if index < buf.buffer.buffer.count { return false }
			} else {
				for i in 0 ..< index {
					if Int(buf.buffer.buffer[i + 3]) < index { return false }
				}
			}
			idx = buf.index
			parent = buf.parent
		} else {
			idx = _tree.index
			parent = _tree._parent
		}
		while let p = parent {
			if idx > -1 {
				let e = dir < 0 ? -1 : p._tree.children.count
				var i = idx + dir
				while i != e {
					let child = p._tree.children[i]
					if mode.contains(.includeAnonymous) ||
						child is TreeBuffer ||
						!(child as! Tree).type.isAnonymous ||
						hasChild(tree: child as! Tree)
					{
						return false
					}
					i += dir
				}
			}
			idx = p.index
			parent = p._parent
		}
		return true
	}

	@inline(__always)
	func move(_ dir: Int, enter: Bool) -> Bool {
		if enter && enterChild(dir, pos: 0, side: .dontCare) { return true }
		while true {
			if sibling(dir) { return true }
			if atLastNode(dir) || !parent() { return false }
		}
	}

	@inline(__always)
	public func next(_ enter: Bool = true) -> Bool {
		move(1, enter: enter)
	}

	public func prev(_ enter: Bool = true) -> Bool {
		move(-1, enter: enter)
	}

	@discardableResult
	public func moveTo(pos: Int, side: Int = 0) -> Self {
		while from == to ||
			(side < 1 ? from >= pos : from > pos) ||
			(side > -1 ? to <= pos : to < pos)
		{
			if !parent() { break }
		}
		while enterChild(1, pos: pos, side: Side(rawValue: side) ?? .around) {}
		return self
	}

	public func iterate(enter: (SyntaxNodeRef) -> Bool, leave: ((SyntaxNodeRef) -> Void)? = nil) {
		var depth = 0
		while true {
			var mustLeave = false
			if type.isAnonymous || enter(self) != false {
				if firstChild() { depth += 1; continue }
				if !type.isAnonymous { mustLeave = true }
			}
			while true {
				if mustLeave, let leave = leave { leave(self) }
				mustLeave = type.isAnonymous
				if depth == 0 { return }
				if nextSibling() { break }
				parent()
				depth -= 1
				mustLeave = true
			}
		}
	}
}
