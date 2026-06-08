import Foundation

public class Tree: CustomStringConvertible {
	public var props: [Int: Any]?

	public let type: NodeType
	public var children: [Any]
	public var positions: [Int]
	public let length: Int

	nonisolated(unsafe) var cachedNode: SyntaxNode?
	nonisolated(unsafe) var cachedInnerNode: SyntaxNode?

	public init(
		type: NodeType,
		children: [Any],
		positions: [Int],
		length: Int,
		props: [(Any, Any)]? = nil
	) {
		self.type = type
		self.children = children
		self.positions = positions
		self.length = length
		if let props = props, !props.isEmpty {
			self.props = [:]
			for (prop, value) in props {
				if let nodeProp = prop as? NodePropBase {
					self.props![nodeProp.id] = value
				} else if let id = prop as? Int {
					self.props![id] = value
				}
			}
		}
	}

	public var description: String {
		let mounted = MountedTree.get(self)
		if let mounted = mounted, mounted.overlay == nil {
			return mounted.tree.description
		}
		var childStr = ""
		for ch in children {
			let s = "\(ch)"
			if !s.isEmpty {
				if !childStr.isEmpty { childStr += "," }
				childStr += s
			}
		}
		if type.name.isEmpty { return childStr }
		let name = type.name
		let nonWord = name.unicodeScalars.contains { !CharacterSet.alphanumerics.contains($0) }
		if nonWord && !type.isError {
			return "\"\(name)\"" + (childStr.isEmpty ? "" : "(\(childStr))")
		}
		return name + (childStr.isEmpty ? "" : "(\(childStr))")
	}

	public nonisolated(unsafe) static let empty = Tree(type: NodeType.none, children: [], positions: [], length: 0)

	public func cursor(mode: IterMode = []) -> TreeCursor {
		return TreeCursor(node: topNode, mode: mode)
	}

	public func cursorAt(pos: Int, side: Int = 0, mode _: IterMode = []) -> TreeCursor {
		let scope = cachedNode ?? topNode
		let cursor = TreeCursor(node: scope)
		cursor.moveTo(pos: pos, side: side)
		cachedNode = cursor._tree
		return cursor
	}

	public var topNode: SyntaxNode {
		return TreeNode(tree: self, from: 0, index: 0, parent: nil)
	}

	public func resolve(pos: Int, side: Int = 0) -> SyntaxNode {
		let node = resolveNode(cachedNode ?? topNode, pos: pos, side: side, overlays: false)
		cachedNode = node
		return node
	}

	public func resolveInner(pos: Int, side: Int = 0) -> SyntaxNode {
		let node = resolveNode(cachedInnerNode ?? topNode, pos: pos, side: side, overlays: true)
		cachedInnerNode = node
		return node
	}

	public func resolveStack(pos: Int, side: Int = 0) -> NodeIterator? {
		return stackIterator(tree: self, pos: pos, side: side)
	}

	public func iterate(
		from: Int = 0,
		to: Int? = nil,
		mode: IterMode = [],
		enter: (SyntaxNodeRef) -> Bool,
		leave: ((SyntaxNodeRef) -> Void)? = nil
	) {
		let to = to ?? length
		let anon = mode.contains(.includeAnonymous)
		let c = cursor(mode: mode.union(.includeAnonymous))
		while true {
			var entered = false
			if c.from <= to, c.to >= from, (!anon && c.type.isAnonymous) || enter(c.ref) != false {
				if c.firstChild() { continue }
				entered = true
			}
			while true {
				if entered, leave != nil, anon || !c.type.isAnonymous {
					leave!(c.ref)
				}
				if c.nextSibling() { break }
				if !c.parent() { return }
				entered = true
			}
		}
	}

	public func prop<T>(_ prop: NodeProp<T>) -> T? {
		if !prop.perNode {
			return type.prop(prop)
		}
		return props?[prop.id] as? T
	}

	public var propValues: [(Any, Any)] {
		var result: [(Any, Any)] = []
		if let props = props {
			for (id, value) in props {
				result.append((id, value))
			}
		}
		return result
	}

	public func balance(makeTree: (([Any], [Int], Int) -> Tree)? = nil) -> Tree {
		if children.count <= Balance.branchFactor {
			return self
		}
		return balanceRange(
			balanceType: NodeType.none,
			children: children,
			positions: positions,
			from: 0,
			to: children.count,
			start: 0,
			length: length,
			mkTop: { ch, pos, len in
				Tree(type: self.type, children: ch, positions: pos, length: len, props: self.propValues)
			},
			mkTree: makeTree ?? { ch, pos, len in
				Tree(type: NodeType.none, children: ch, positions: pos, length: len)
			}
		)
	}

	public static func build(data: BuildData) -> Tree {
		return buildTree(data: data)
	}
}
