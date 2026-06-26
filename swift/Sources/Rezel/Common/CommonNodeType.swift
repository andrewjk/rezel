public typealias NodePropSource = (NodeType) -> (NodePropBase, Any)?

public struct NodeFlag: OptionSet, Sendable {
	public let rawValue: Int
	public init(rawValue: Int) {
		self.rawValue = rawValue
	}

	public static let top = NodeFlag(rawValue: 1)
	public static let skipped = NodeFlag(rawValue: 2)
	public static let error = NodeFlag(rawValue: 4)
	public static let anonymous = NodeFlag(rawValue: 8)
}

public final class NodeType: @unchecked Sendable {
	public let name: String
	public let props: [Int: Any]
	public let id: Int
	public let flags: Int

	public init(name: String, props: [Int: Any], id: Int, flags: Int = 0) {
		self.name = name
		self.props = props
		self.id = id
		self.flags = flags
	}

	public struct DefineSpec {
		public let id: Int
		public let name: String?
		public let props: [Any]?
		public let top: Bool
		public let error: Bool
		public let skipped: Bool

		public init(id: Int, name: String? = nil, props: [Any]? = nil, top: Bool = false, error: Bool = false, skipped: Bool = false) {
			self.id = id
			self.name = name
			self.props = props
			self.top = top
			self.error = error
			self.skipped = skipped
		}
	}

	public static func define(spec: DefineSpec) -> NodeType {
		var props: [Int: Any] = [:]
		var flags = 0
		if spec.top { flags |= NodeFlag.top.rawValue }
		if spec.skipped { flags |= NodeFlag.skipped.rawValue }
		if spec.error { flags |= NodeFlag.error.rawValue }
		if spec.name == nil { flags |= NodeFlag.anonymous.rawValue }

		let type = NodeType(name: spec.name ?? "", props: props, id: spec.id, flags: flags)
		if let specProps = spec.props {
			for src in specProps {
				if let source = src as? NodePropSource {
					if let add = source(type) {
						if add.0.perNode { fatalError("Can't store a per-node prop on a node type") }
						props[add.0.id] = add.1
					}
				}
			}
		}
		return type
	}

	public func prop<T>(_ prop: NodeProp<T>) -> T? {
		return props[prop.id] as? T
	}

	public var isTop: Bool {
		(flags & NodeFlag.top.rawValue) > 0
	}

	public var isSkipped: Bool {
		(flags & NodeFlag.skipped.rawValue) > 0
	}

	public var isError: Bool {
		(flags & NodeFlag.error.rawValue) > 0
	}

	public var isAnonymous: Bool {
		(flags & NodeFlag.anonymous.rawValue) > 0
	}

	public func `is`(_ name: String) -> Bool {
		if self.name == name { return true }
		if let group = prop(nodePropGroup) {
			return group.contains(name)
		}
		return false
	}

	public func `is`(_ id: Int) -> Bool {
		return self.id == id
	}

	public static let none = NodeType(name: "", props: [:], id: 0, flags: NodeFlag.anonymous.rawValue)

	public static func match<T>(map: [String: T]) -> (NodeType) -> T? {
		var direct: [String: T] = [:]
		for (prop, value) in map {
			for name in prop.split(separator: " ") {
				direct[String(name)] = value
			}
		}
		return { node in
			if let found = direct[node.name] { return found }
			if let groups = node.prop(nodePropGroup) {
				for group in groups {
					if let found = direct[group] { return found }
				}
			}
			return nil
		}
	}
}
