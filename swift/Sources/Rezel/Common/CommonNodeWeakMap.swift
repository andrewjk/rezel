public final class NodeWeakMap<T> {
	private var map: [ObjectIdentifier: Any] = [:]

	private func setBuffer(_ buffer: TreeBuffer, index: Int, value: T) {
		let key = ObjectIdentifier(buffer)
		var inner = map[key] as? [Int: T] ?? [:]
		inner[index] = value
		map[key] = inner
	}

	private func getBuffer(_ buffer: TreeBuffer, index: Int) -> T? {
		guard let inner = map[ObjectIdentifier(buffer)] as? [Int: T] else { return nil }
		return inner[index]
	}

	public func set(_ node: SyntaxNode, value: T) {
		if let buf = node as? BufferNode {
			setBuffer(buf.context.buffer, index: buf.index, value: value)
		} else if let tn = node as? TreeNode {
			map[ObjectIdentifier(tn._tree)] = value
		}
	}

	public func get(_ node: SyntaxNode) -> T? {
		if let buf = node as? BufferNode {
			return getBuffer(buf.context.buffer, index: buf.index)
		} else if let tn = node as? TreeNode {
			return map[ObjectIdentifier(tn._tree)] as? T
		}
		return nil
	}

	public func cursorSet(_ cursor: TreeCursor, value: T) {
		if let buf = cursor.buffer {
			setBuffer(buf.buffer, index: cursor.index, value: value)
		} else {
			map[ObjectIdentifier(cursor.tree!)] = value
		}
	}

	public func cursorGet(_ cursor: TreeCursor) -> T? {
		if let buf = cursor.buffer {
			return getBuffer(buf.buffer, index: cursor.index)
		}
		guard let tree = cursor.tree else { return nil }
		return map[ObjectIdentifier(tree)] as? T
	}
}
