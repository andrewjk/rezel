public final class MountedTree {
    public let tree: Tree
    public let overlay: [Range]?
    public let parser: Parser
    public let bracketed: Bool

    public init(tree: Tree, overlay: [Range]?, parser: Parser, bracketed: Bool = false) {
        self.tree = tree
        self.overlay = overlay
        self.parser = parser
        self.bracketed = bracketed
    }

    public static func get(_ tree: Tree?) -> MountedTree? {
        guard let tree = tree, let props = tree.props else { return nil }
        return props[nodePropMounted.id] as? MountedTree
    }
}
