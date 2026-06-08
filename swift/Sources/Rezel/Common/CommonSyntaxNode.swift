public protocol SyntaxNodeRef {
	var from: Int { get }
	var to: Int { get }
	var type: NodeType { get }
	var name: String { get }
	var tree: Tree? { get }
	var node: SyntaxNode { get }
	func matchContext(_ context: [String]) -> Bool
}

public protocol SyntaxNode: SyntaxNodeRef {
	var parent: SyntaxNode? { get }
	var firstChild: SyntaxNode? { get }
	var lastChild: SyntaxNode? { get }
	func childAfter(_ pos: Int) -> SyntaxNode?
	func childBefore(_ pos: Int) -> SyntaxNode?
	func enter(_ pos: Int, side: Int, mode: IterMode?) -> SyntaxNode?
	var nextSibling: SyntaxNode? { get }
	var prevSibling: SyntaxNode? { get }
	func prop<T>(_ prop: NodeProp<T>) -> T?
	func cursor(mode: IterMode?) -> TreeCursor
	func resolve(_ pos: Int, side: Int) -> SyntaxNode
	func resolveInner(_ pos: Int, side: Int) -> SyntaxNode
	func enterUnfinishedNodesBefore(_ pos: Int) -> SyntaxNode
	func toTree() -> Tree
	func getChild(_ type: Any, before: Any?, after: Any?) -> SyntaxNode?
	func getChildren(_ type: Any, before: Any?, after: Any?) -> [SyntaxNode]
}

public extension SyntaxNode {
	func getChild(_ type: Any, before: Any? = nil, after: Any? = nil) -> SyntaxNode? {
		let r = getChildren(type, before: before, after: after)
		return r.first
	}
}

public class NodeIterator {
	public let node: SyntaxNode
	public let next: NodeIterator?

	public init(node: SyntaxNode, next: NodeIterator? = nil) {
		self.node = node
		self.next = next
	}
}
