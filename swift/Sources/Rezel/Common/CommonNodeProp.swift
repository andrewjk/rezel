private nonisolated(unsafe) var _nextPropID: Int = 0

public class NodePropBase: @unchecked Sendable {
	public let id: Int
	public let perNode: Bool
	public let combine: ((Any, Any) -> Any)?

	init(perNode: Bool = false, combine: ((Any, Any) -> Any)? = nil) {
		id = _nextPropID
		_nextPropID += 1
		self.perNode = perNode
		self.combine = combine
	}
}

public final class NodeProp<T>: NodePropBase {
	public let deserialize: (String) -> T

	public init(
		deserialize: @escaping (String) -> T,
		combine: ((T, T) -> T)? = nil,
		perNode: Bool = false
	) {
		self.deserialize = deserialize
		super.init(
			perNode: perNode,
			combine: combine.map { fn in { a, b in fn(a as! T, b as! T) } }
		)
	}

	public init(perNode: Bool = false) {
		deserialize = { _ in fatalError("This node type doesn't define a deserialize function") }
		super.init(perNode: perNode)
	}

	public func add(match: @escaping (NodeType) -> T?) -> NodePropSource {
		if perNode { fatalError("Can't add per-node props to node types") }
		return { [self] type in
			guard let result = match(type) else { return nil }
			return (self, result)
		}
	}

	public func add(match: [String: T]) -> NodePropSource {
		if perNode { fatalError("Can't add per-node props to node types") }
		let fn = NodeType.match(map: match)
		return { [self] type in
			guard let result = fn(type) else { return nil }
			return (self, result)
		}
	}
}

public let nodePropClosedBy = NodeProp<[String]>(deserialize: { $0.split(separator: " ").map(String.init) })
public let nodePropOpenedBy = NodeProp<[String]>(deserialize: { $0.split(separator: " ").map(String.init) })
public let nodePropGroup = NodeProp<[String]>(deserialize: { $0.split(separator: " ").map(String.init) })
public let nodePropIsolate = NodeProp<String>(deserialize: { value in
	if !value.isEmpty && value != "rtl" && value != "ltr" && value != "auto" {
		fatalError("Invalid value for isolate: \(value)")
	}
	return value.isEmpty ? "auto" : value
})
public let nodePropContextHash = NodeProp<Int>(perNode: true)
public let nodePropLookAhead = NodeProp<Int>(perNode: true)
public let nodePropMounted = NodeProp<MountedTree>(perNode: true)

public let nodePropByName: [String: NodePropBase] = [
	"closedBy": nodePropClosedBy,
	"openedBy": nodePropOpenedBy,
	"group": nodePropGroup,
	"isolate": nodePropIsolate,
]
