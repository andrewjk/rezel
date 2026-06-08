public final class NodeSet {
	public let types: [NodeType]

	public init(types: [NodeType]) {
		self.types = types
		for i in 0 ..< types.count {
			if types[i].id != i {
				fatalError("Node type ids should correspond to array positions when creating a node set")
			}
		}
	}

	public func extend(_ props: NodePropSource...) -> NodeSet {
		var newTypes: [NodeType] = []
		for type in types {
			var newProps: [Int: Any]? = nil
			for source in props {
				if let add = source(type) {
					if newProps == nil { newProps = type.props }
					let value = add.1
					let prop = add.0
					if let combine = prop.combine, let existing = newProps?[prop.id] {
						newProps?[prop.id] = combine(existing, value)
					} else {
						newProps?[prop.id] = value
					}
				}
			}
			if let np = newProps {
				newTypes.append(NodeType(name: type.name, props: np, id: type.id, flags: type.flags))
			} else {
				newTypes.append(type)
			}
		}
		return NodeSet(types: newTypes)
	}
}
