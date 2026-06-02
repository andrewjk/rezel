//
//  Tree.swift
//  Rezel
//
//  Created on 2025-06-02.
//

import Foundation

/// The default maximum length of a `TreeBuffer` node.
public let defaultBufferLength = 1024

nonisolated(unsafe) fileprivate var nextPropID = 0

public struct Range: Equatable, Hashable {
    public let from: Int
    public let to: Int
    
    public init(from: Int, to: Int) {
        self.from = from
        self.to = to
    }
}

/// Each node type or individual tree can have metadata associated with
/// it in props. Instances of this class represent prop names.
public protocol NodePropProtocol {
    var id: Int { get }
    var perNode: Bool { get }
}

public final class NodeProp<T>: NodePropProtocol {
    /// @internal
    public let id: Int

    /// Indicates whether this prop is stored per node type or per tree node.
    public let perNode: Bool

    /// A method that deserializes a value of this prop from a string.
    /// Can be used to allow a prop to be directly written in a grammar file.
    let deserialize: (String) -> T

    /// @internal
    let combine: ((T, T) -> T)?
    
    /// Create a new node prop type.
    public init(
        config: NodePropConfig<T> = NodePropConfig()
    ) {
        self.id = nextPropID
        nextPropID += 1
        self.perNode = config.perNode
        self.deserialize = config.deserialize ?? { _ in
            fatalError("This node type doesn't define a deserialize function")
        }
        self.combine = config.combine
    }
    
    /// This is meant to be used with NodeSet.extend or
    /// LRParser.configure to compute prop values for each node type in the set.
    public func add(match: MatchType<T>) -> NodePropSource {
        if perNode {
            fatalError("Can't add per-node props to node types")
        }
        
        let matchFunc: (NodeType) -> T?
        
        switch match {
        case .object(let dict):
            matchFunc = NodeType.match(map: dict)
        case .function(let fn):
            matchFunc = fn
        }
        
        return { type in
            let result = matchFunc(type)
            if result == nil {
                return nil
            }
            return (self, result! as Any)
        }
    }
}

/// Prop that is used to describe matching delimiters. For opening
/// delimiters, this holds an array of node names for the node types
/// of closing delimiters that match it.
public nonisolated(unsafe) let nodePropClosedBy = NodeProp<[String]>(
    config: NodePropConfig(deserialize: { $0.components(separatedBy: " ") })
)

/// The inverse of closedBy. This is attached to closing delimiters,
/// holding an array of node names of types of matching opening delimiters.
public nonisolated(unsafe) let nodePropOpenedBy = NodeProp<[String]>(
    config: NodePropConfig(deserialize: { $0.components(separatedBy: " ") })
)

/// Used to assign node types to groups (for example, all node
/// types that represent an expression could be tagged with an
/// `"Expression"` group).
public nonisolated(unsafe) let nodePropGroup = NodeProp<[String]>(
    config: NodePropConfig(deserialize: { $0.components(separatedBy: " ") })
)

/// Attached to nodes to indicate these should be displayed in a
/// bidirectional text isolate, so that direction-neutral characters
/// on their sides don't incorrectly get associated with surrounding text.
public nonisolated(unsafe) let nodePropIsolate = NodeProp<IsolateType>(
    config: NodePropConfig(deserialize: { value in
        if !value.isEmpty && value != "rtl" && value != "ltr" && value != "auto" {
            fatalError("Invalid value for isolate: \(value)")
        }
        return value.isEmpty ? "auto" : value
    })
)

/// The hash of the context that the node was parsed in, if any.
/// Used to limit reuse of contextual nodes.
public nonisolated(unsafe) let nodePropContextHash = NodeProp<Int>(config: NodePropConfig(perNode: true))

/// The distance beyond the end of the node that the tokenizer
/// looked ahead for any of the tokens inside the node.
public nonisolated(unsafe) let nodePropLookAhead = NodeProp<Int>(config: NodePropConfig(perNode: true))

/// This per-node prop is used to replace a given node, or part of a
/// node, with another tree. This is useful to include trees from
/// different languages in mixed-language parsers.
public nonisolated(unsafe) let nodePropMounted = NodeProp<MountedTree>(config: NodePropConfig(perNode: true))

public enum MatchType<T> {
    case object([String: T])
    case function((NodeType) -> T?)
}

public struct NodePropConfig<T> {
    let deserialize: ((String) -> T)?
    let combine: ((T, T) -> T)?
    let perNode: Bool
    
    public init(
        deserialize: ((String) -> T)? = nil,
        combine: ((T, T) -> T)? = nil,
        perNode: Bool = false
    ) {
        self.deserialize = deserialize
        self.combine = combine
        self.perNode = perNode
    }
}

public typealias IsolateType = String

/// A mounted tree, which can be stored on a tree node to indicate that
/// parts of its content are represented by another tree.
public final class MountedTree {
    /// The inner tree.
    public let tree: Tree
    
    /// If this is nil, this tree replaces the entire node (it will
    /// be included in the regular iteration instead of its host
    /// node). If not, only the given ranges are considered to be
    /// covered by this tree. This is used for trees that are mixed in
    /// a way that isn't strictly hierarchical.
    public let overlay: [Range]?
    
    /// The parser used to create this subtree.
    public let parser: any Parser
    
    /// Indicates that the nested content is delineated with some kind
    /// of bracket token.
    public let bracketed: Bool
    
    public init(
        tree: Tree,
        overlay: [Range]? = nil,
        parser: any Parser,
        bracketed: Bool = false
    ) {
        self.tree = tree
        self.overlay = overlay
        self.parser = parser
        self.bracketed = bracketed
    }
    
    /// @internal
    public static func get(tree: Tree?) -> MountedTree? {
        return tree?.props?[nodePropMounted.id] as? MountedTree
    }
}

/// Type returned by NodeProp.add. Describes whether a prop should be
/// added to a given node type in a node set, and what value it should have.
public typealias NodePropSource = (NodeType) -> (any NodeProp<Any>, Any)?

internal enum NodeFlag: Int {
    case top = 1
    case skipped = 2
    case error = 4
    case anonymous = 8
}

internal nonisolated(unsafe) let noProps: [Int: Any] = [:]

/// Each node in a syntax tree has a node type associated with it.
public final class NodeType {
    /// @internal
    public let name: String
    
    /// @internal
    public let props: [Int: Any]
    
    /// The id of this node in its set. Corresponds to the term ids
    /// used in the parser.
    public let id: Int
    
    /// @internal
    public let flags: Int
    
    public init(
        name: String,
        props: [Int: Any],
        id: Int,
        flags: Int = 0
    ) {
        self.name = name
        self.props = props
        self.id = id
        self.flags = flags
    }
    
    /// Define a node type.
    public static func define(spec: NodeTypeSpec) -> NodeType {
        var props = spec.props != nil && !spec.props!.isEmpty ? [:] : noProps
        let flags = (spec.top ? NodeFlag.top.rawValue : 0) |
                    (spec.skipped ? NodeFlag.skipped.rawValue : 0) |
                    (spec.error ? NodeFlag.error.rawValue : 0) |
                    (spec.name == nil ? NodeFlag.anonymous.rawValue : 0)
        
        let type = NodeType(name: spec.name ?? "", props: props, id: spec.id, flags: flags)
        
        if let specProps = spec.props {
            for src in specProps {
                let propSource: NodePropSource
                if let dict = src as? [String: Any] {
                    propSource = { nodeType in
                        if let value = dict[nodeType.name] {
                            return (nodePropContextHash as any NodeProp<Any>, value)
                        }
                        return nil
                    }
                } else if let fn = src as? NodePropSource {
                    propSource = fn
                } else {
                    continue
                }

                if let result = propSource(type) {
                    let prop = result.0
                    let value = result.1
                    if let propAny = prop as? any NodePropProtocol {
                        if propAny.perNode {
                            fatalError("Can't store a per-node prop on a node type")
                        }
                        props[propAny.id] = value
                    }
                }
            }
        }
                        return nil
                    }
                } else if let fn = src as? NodePropSource {
                    propSource = fn
                } else {
                    continue
                }

                if let result = propSource(type) {
                    let prop = result.0
                    let value = result.1
                    if prop.perNode {
                        fatalError("Can't store a per-node prop on a node type")
                    }
                    props[prop.id] = value
                }
            }
        }
        
        return type
    }
    
    /// Retrieves a node prop for this type. Will return `nil` if
    /// the prop isn't present on this node.
    public func prop<T>(prop: NodeProp<T>) -> T? {
        return props[prop.id] as? T
    }
    
    /// True when this is the top node of a grammar.
    public var isTop: Bool {
        return (flags & NodeFlag.top.rawValue) > 0
    }
    
    /// True when this node is produced by a skip rule.
    public var isSkipped: Bool {
        return (flags & NodeFlag.skipped.rawValue) > 0
    }
    
    /// Indicates whether this is an error node.
    public var isError: Bool {
        return (flags & NodeFlag.error.rawValue) > 0
    }
    
    /// When true, this node type doesn't correspond to a user-declared
    /// named node, for example because it is used to cache repetition.
    public var isAnonymous: Bool {
        return (flags & NodeFlag.anonymous.rawValue) > 0
    }
    
    /// Returns true when this node's name or one of its groups matches
    /// the given string.
    public func `is`(_ name: StringOrInt) -> Bool {
        switch name {
        case .string(let str):
            if self.name == str {
                return true
            }
            if let group = prop(prop: nodePropGroup) {
                return group.contains(str)
            }
            return false
        case .int(let int):
            return self.id == int
        }
    }
    
    /// An empty dummy node type to use when no actual type is available.
    public static nonisolated(unsafe) let none = NodeType(name: "", props: noProps, id: 0, flags: NodeFlag.anonymous.rawValue)
    
    /// Create a function from node types to arbitrary values by
    /// specifying an object whose property names are node or group names.
    public static func match<T>(map: [String: T]) -> (NodeType) -> T? {
        var direct: [String: T] = [:]
        for (prop, value) in map {
            for name in prop.components(separatedBy: " ") {
                direct[name] = value
            }
        }
        
        return { node in
            if let groups = node.prop(prop: nodePropGroup) {
                for group in groups {
                    if let found = direct[group] {
                        return found
                    }
                }
            }
            return direct[node.name]
        }
    }
}

public enum StringOrInt {
    case string(String)
    case int(Int)
}

public struct NodeTypeSpec {
    public let id: Int
    public let name: String?
    public let props: [Any]?
    public let top: Bool
    public let error: Bool
    public let skipped: Bool
    
    public init(
        id: Int,
        name: String? = nil,
        props: [Any]? = nil,
        top: Bool = false,
        error: Bool = false,
        skipped: Bool = false
    ) {
        self.id = id
        self.name = name
        self.props = props
        self.top = top
        self.error = error
        self.skipped = skipped
    }
}

/// A node set holds a collection of node types. It is used to
/// compactly represent trees by storing their type ids, rather than a
/// full pointer to the type object, in a numeric array.
public final class NodeSet {
    /// Create a set with the given types. The `id` property of each
    /// type should correspond to its position within the array.
    public let types: [NodeType]
    
    public init(types: [NodeType]) {
        self.types = types
        for (i, type) in types.enumerated() {
            if type.id != i {
                fatalError("Node type ids should correspond to array positions when creating a node set")
            }
        }
    }
    
    /// Create a copy of this set with some node properties added.
    public func extend(_ props: NodePropSource...) -> NodeSet {
        var newTypes: [NodeType] = []
        for type in types {
            var newProps: [Int: Any]? = nil
            for source in props {
                if let add = source(type) {
                    if newProps == nil {
                        newProps = type.props
                    }
                    let value = add.1
                    if let prop = add.0 as? NodeProp<Any> {
                        let propId = prop.id
                        if let combine = prop.combine, newProps![propId] != nil {
                            newProps![propId] = combine(newProps![propId] as! Any, value)
                        } else {
                            newProps![propId] = value
                        }
                    }
                }
            }
            
            if let newProps = newProps {
                newTypes.append(NodeType(name: type.name, props: newProps, id: type.id, flags: type.flags))
            } else {
                newTypes.append(type)
            }
        }
        return NodeSet(types: newTypes)
    }
}

/// Options that control iteration. Can be combined with the `|`
/// operator to enable multiple ones.
public struct IterMode: OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// When enabled, iteration will only visit Tree objects, not nodes
    /// packed into TreeBuffers.
    public static nonisolated(unsafe) let excludeBuffers = IterMode(rawValue: 1)
    
    /// Enable this to make iteration include anonymous nodes.
    public static nonisolated(unsafe) let includeAnonymous = IterMode(rawValue: 2)
    
    /// By default, regular mounted nodes replace their base node in
    /// iteration. Enable this to ignore them instead.
    public static nonisolated(unsafe) let ignoreMounts = IterMode(rawValue: 4)
    
    /// This option only applies in enter-style methods. It tells the
    /// library to not enter mounted overlays if one covers the given position.
    public static nonisolated(unsafe) let ignoreOverlays = IterMode(rawValue: 8)
    
    /// When set, positions on the boundary of a mounted overlay tree
    /// that has its bracketed flag set will enter that tree regardless of side.
    public static nonisolated(unsafe) let enterBracketed = IterMode(rawValue: 16)
}

/// A piece of syntax tree. Syntax trees are stored as a tree of `Tree`
/// and `TreeBuffer` objects. By packing detail information into
/// `TreeBuffer` leaf nodes, the representation is made a lot more memory-efficient.
///
/// However, when you want to actually work with tree nodes, this
/// representation is very awkward, so most client code will want to
/// use the `TreeCursor` or `SyntaxNode` interface instead.
public final class Tree {
    /// @internal
    public var props: [Int: Any]? = nil
    
    /// The type of the top node.
    public let type: NodeType
    
    /// This node's child nodes.
    public let children: [TreeOrBuffer]
    
    /// The positions (offsets relative to the start of this tree) of
    /// the children.
    public let positions: [Int]
    
    /// The total length of this tree
    public let length: Int
    
    /// Construct a new tree.
    public init(
        type: NodeType,
        children: [TreeOrBuffer],
        positions: [Int],
        length: Int,
        props: [PropPair]? = nil
    ) {
        self.type = type
        self.children = children
        self.positions = positions
        self.length = length
        
        if let props = props, !props.isEmpty {
            self.props = [:]
            for prop in props {
                self.props![prop.propId] = prop.value
            }
        }
    }
    
    /// @internal
    public func toString() -> String {
        if let mounted = MountedTree.get(tree: self), mounted.overlay == nil {
            return mounted.tree.toString()
        }
        
        var childrenStr = ""
        for ch in children {
            let str = ch.toString()
            if !str.isEmpty {
                if !childrenStr.isEmpty {
                    childrenStr += ","
                }
                childrenStr += str
            }
        }
        
        if type.name.isEmpty {
            return childrenStr
        }
        
        let name: String
        let needsQuotes = type.name.range(of: #"\W"#, options: .regularExpression) != nil && !type.isError
        name = needsQuotes ? "\"\(type.name.replacingOccurrences(of: "\"", with: "\\\""))\"" : type.name
        
        return childrenStr.isEmpty ? name : "\(name)(\(childrenStr))"
    }
    
    /// The empty tree
    public static nonisolated(unsafe) let empty = Tree(type: NodeType.none, children: [], positions: [], length: 0)
    
    /// Get a tree cursor positioned at the top of the tree.
    public func cursor(mode: IterMode = []) -> TreeCursor {
        return TreeCursor(treeNode: topNode as! TreeNode, bufferNode: nil, mode: mode)
    }
    
    /// Get a tree cursor pointing into this tree at the given position and side.
    public func cursorAt(pos: Int, side: SideInt = 0, mode: IterMode = []) -> TreeCursor {
        let scope = topNode
        let cursor = TreeCursor(treeNode: scope as! TreeNode, bufferNode: nil, mode: mode)
        cursor.moveTo(pos: pos, side: side)
        cachedNode[self] = cursor._tree
        return cursor
    }
    
    /// Get a syntax node object for the top of the tree.
    public var topNode: SyntaxNode {
        return TreeNode(tree: self, from: 0, index: 0, parent: nil)
    }
    
    /// Get the syntax node at the given position.
    public func resolve(pos: Int, side: SideInt = 0) -> SyntaxNode {
        let node = resolveNode(node: cachedNode[self] ?? topNode, pos: pos, side: side, overlays: false)
        cachedNode[self] = node
        return node
    }
    
    /// Like resolve, but will enter overlaid nodes.
    public func resolveInner(pos: Int, side: SideInt = 0) -> SyntaxNode {
        let node = resolveNode(node: cachedInnerNode[self] ?? topNode, pos: pos, side: side, overlays: true)
        cachedInnerNode[self] = node
        return node
    }
    
    /// In some situations, it can be useful to iterate through all
    /// nodes around a position, including those in overlays that don't
    /// directly cover the position.
    public func resolveStack(pos: Int, side: SideInt = 0) -> NodeIterator {
        return stackIterator(tree: self, pos: pos, side: side)
    }
    
    /// Iterate over the tree and its children.
    public func iterate(
        enter: (SyntaxNodeRef) -> Bool,
        leave: ((SyntaxNodeRef) -> Void)? = nil,
        from: Int = 0,
        to: Int? = nil,
        mode: IterMode = []
    ) {
        let to = to ?? length
        let anon = mode.contains(.includeAnonymous)
        let fullMode = mode.union(.includeAnonymous)
        
        var c = cursor(mode: fullMode)
        
        while true {
            var entered = false
            if c.from <= to && c.to >= from && ((!anon && !c.type.isAnonymous) || enter(c) != false) {
                if c.firstChild() {
                    continue
                }
                entered = true
            }
            
            while true {
                if entered && leave != nil && (anon || !c.type.isAnonymous) {
                    leave!(c)
                }
                
                if c.nextSibling() {
                    break
                }
                
                if !c.parent() {
                    return
                }
                
                entered = true
            }
        }
    }
    
    /// Get the value of the given node prop for this node.
    public func prop<T>(prop: NodeProp<T>) -> T? {
        if !prop.perNode {
            return type.prop(prop: prop)
        }
        return props?[prop.id] as? T
    }
    
    /// Returns the node's per-node props in a format that can be passed
    /// to the Tree constructor.
    public var propValues: [PropPair] {
        guard let props = props else {
            return []
        }
        var result: [PropPair] = []
        for (key, value) in props {
            result.append(PropPair(propId: key, value: value))
        }
        return result
    }
    
    /// Balance the direct children of this tree.
    public func balance(config: BalanceConfig = BalanceConfig()) -> Tree {
        if children.count <= Balance.branchFactor {
            return self
        }
        
        let makeTree = config.makeTree ?? { children, positions, length in
            return Tree(type: NodeType.none, children: children, positions: positions, length: length)
        }
        
        return balanceRange(
            balanceType: NodeType.none,
            children: children,
            positions: positions,
            from: 0,
            to: children.count,
            start: 0,
            length: length,
            mkTop: { children, positions, length in
                return Tree(type: self.type, children: children, positions: positions, length: length, props: self.propValues)
            },
            mkTree: makeTree
        )
    }
    
    /// Build a tree from a postfix-ordered buffer of node information.
    public static func build(data: BuildData) -> Tree {
        return buildTree(data: data)
    }
}

internal nonisolated(unsafe) var cachedNode: WeakMap<Tree, SyntaxNode> = WeakMap()
internal nonisolated(unsafe) var cachedInnerNode: WeakMap<Tree, SyntaxNode> = WeakMap()

public struct BalanceConfig {
    public let makeTree: (([TreeOrBuffer], [Int], Int) -> Tree)?
    
    public init(makeTree: (([TreeOrBuffer], [Int], Int) -> Tree)? = nil) {
        self.makeTree = makeTree
    }
}

internal enum Balance {
    static let branchFactor = 8
}

public struct PropPair {
    public let propId: Int
    public let value: Any

    public init(propId: Int, value: Any) {
        self.propId = propId
        self.value = value
    }
}

public enum TreeOrBuffer: Equatable {
    case tree(Tree)
    case buffer(TreeBuffer)
    
    public static func == (lhs: TreeOrBuffer, rhs: TreeOrBuffer) -> Bool {
        switch (lhs, rhs) {
        case (.tree(let lTree), .tree(let rTree)):
            return lTree === rTree
        case (.buffer(let lBuffer), .buffer(let rBuffer)):
            return lBuffer === rBuffer
        default:
            return false
        }
    }
    
    func toString() -> String {
        switch self {
        case .tree(let tree):
            return tree.toString()
        case .buffer(let buffer):
            return buffer.toString()
        }
    }
    
    var length: Int {
        switch self {
        case .tree(let tree):
            return tree.length
        case .buffer(let buffer):
            return buffer.length
        }
    }
    
    var type: NodeType {
        switch self {
        case .tree(let tree):
            return tree.type
        case .buffer(let buffer):
            return buffer.type
        }
    }
}
/// Represents a sequence of nodes.
public class NodeIterator {
    public let node: SyntaxNode
    public let next: NodeIterator?
    
    public init(node: SyntaxNode, next: NodeIterator?) {
        self.node = node
        self.next = next
    }
}

public struct BuildData {
    public let buffer: BufferCursorOrArray
    public let nodeSet: NodeSet
    public let topID: Int
    public let start: Int
    public let bufferStart: Int
    public let length: Int?
    public let maxBufferLength: Int
    public let reused: [Tree]
    public let minRepeatType: Int
    
    public init(
        buffer: BufferCursorOrArray,
        nodeSet: NodeSet,
        topID: Int,
        start: Int = 0,
        bufferStart: Int = 0,
        length: Int? = nil,
        maxBufferLength: Int = defaultBufferLength,
        reused: [Tree] = [],
        minRepeatType: Int? = nil
    ) {
        self.buffer = buffer
        self.nodeSet = nodeSet
        self.topID = topID
        self.start = start
        self.bufferStart = bufferStart
        self.length = length
        self.maxBufferLength = maxBufferLength
        self.reused = reused
        self.minRepeatType = minRepeatType ?? nodeSet.types.count
    }
}

public enum BufferCursorOrArray {
    case cursor(any BufferCursor)
    case array([Int])
}

/// This is used by Tree.build as an abstraction for iterating over a tree buffer.
public protocol BufferCursor: AnyObject {
    var pos: Int { get }
    var id: Int { get }
    var start: Int { get }
    var end: Int { get }
    var size: Int { get }
    func next()
    func fork() -> any BufferCursor
}

internal final class FlatBufferCursor: BufferCursor {
    let buffer: [Int]
    var index: Int
    
    init(buffer: [Int], index: Int) {
        self.buffer = buffer
        self.index = index
    }
    
    var id: Int {
        return buffer[index - 4]
    }
    
    var start: Int {
        return buffer[index - 3]
    }
    
    var end: Int {
        return buffer[index - 2]
    }
    
    var size: Int {
        return buffer[index - 1]
    }
    
    var pos: Int {
        return index
    }
    
    func next() {
        index -= 4
    }
    
    func fork() -> any BufferCursor {
        return FlatBufferCursor(buffer: buffer, index: index)
    }
}

/// Tree buffers contain (type, start, end, endIndex) quads for each node.
public final class TreeBuffer {
    public let buffer: [UInt16]
    public let length: Int
    public let set: NodeSet
    
    public init(buffer: [UInt16], length: Int, set: NodeSet) {
        self.buffer = buffer
        self.length = length
        self.set = set
    }
    
    /// @internal
    var type: NodeType {
        return NodeType.none
    }
    
    /// @internal
    func toString() -> String {
        var result: [String] = []
        var index = 0
        while index < buffer.count {
            result.append(childString(index: index))
            index = Int(buffer[index + 3])
        }
        return result.joined(separator: ",")
    }
    
    /// @internal
    func childString(index: Int) -> String {
        let id = buffer[index]
        let endIndex = buffer[index + 3]
        let type = set.types[Int(id)]
        var result = type.name
        let needsQuotes = type.name.range(of: #"\W"#, options: .regularExpression) != nil && !type.isError
        if needsQuotes {
            result = "\"\(type.name.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        
        var i = index + 4
        if endIndex == UInt16(i) {
            return result
        }
        
        var children: [String] = []
        while i < Int(endIndex) {
            children.append(childString(index: i))
            i = Int(buffer[i + 3])
        }
        return "\(result)(\(children.joined(separator: ",")))"
    }
    
    /// @internal
    func findChild(startIndex: Int, endIndex: Int, dir: Int, pos: Int, side: Side) -> Int {
        var pick = -1
        var i = startIndex
        while i != endIndex {
            if checkSide(side: side, pos: pos, from: Int(buffer[i + 1]), to: Int(buffer[i + 2])) {
                pick = i
                if dir > 0 {
                    break
                }
            }
            i = Int(buffer[i + 3])
        }
        return pick
    }
    
    /// @internal
    func slice(startI: Int, endI: Int, from: Int) -> TreeBuffer {
        var copy = [UInt16](repeating: 0, count: endI - startI)
        var len = 0
        var i = startI
        var j = 0
        
        while i < endI {
            copy[j] = buffer[i]
            j += 1
            copy[j] = UInt16(Int(buffer[i + 1]) - from)
            j += 1
            let to = Int(buffer[i + 2]) - from
            copy[j] = UInt16(to)
            j += 1
            copy[j] = UInt16(Int(buffer[i + 3]) - startI)
            j += 1
            len = max(len, to)
            i += 4
        }
        
        return TreeBuffer(buffer: copy, length: len, set: set)
    }
}

/// The set of properties provided by both SyntaxNode and TreeCursor.
public protocol SyntaxNodeRef {
    var from: Int { get }
    var to: Int { get }
    var type: NodeType { get }
    var name: String { get }
    var tree: Tree? { get }
    var node: SyntaxNode { get }
    func matchContext(context: [String]) -> Bool
}

internal class BaseNode: SyntaxNodeRef {
    public var node: SyntaxNode {
        return self as! SyntaxNode
    }

    func cursor(mode: IterMode?) -> TreeCursor {
        return TreeCursor(treeNode: self as? TreeNode, bufferNode: self as? BufferNode, mode: mode ?? [])
    }

    func getChild(type: StringOrInt, before: StringOrInt? = nil, after: StringOrInt? = nil) -> SyntaxNode? {
        let r = getChildren(type: type, before: before, after: after)
        return r.first
    }

    func getChildren(type: StringOrInt, before: StringOrInt? = nil, after: StringOrInt? = nil) -> [SyntaxNode] {
        return Rezel.getChildren(node: self, type: type, before: before, after: after)
    }

    func resolve(pos: Int, side: SideInt? = nil) -> SyntaxNode {
        return resolveNode(node: self, pos: pos, side: side ?? 0, overlays: false)
    }

    func resolveInner(pos: Int, side: SideInt? = nil) -> SyntaxNode {
        return resolveNode(node: self, pos: pos, side: side ?? 0, overlays: true)
    }

    func matchContext(context: [String]) -> Bool {
        return matchNodeContext(node: (self as! SyntaxNode).parent, context: context)
    }

    func enterUnfinishedNodesBefore(pos: Int) -> SyntaxNode {
        var scan = (self as! SyntaxNode).childBefore(pos: pos)
        var currentNode: SyntaxNode = self as! SyntaxNode

        while let currentScan = scan {
            let last = currentScan.lastChild
            if last == nil || last!.to != currentScan.to {
                break
            }
            if last!.type.isError && last!.from == last!.to {
                currentNode = currentScan
                scan = last!.prevSibling
            } else {
                scan = last
            }
        }

        return currentNode
    }

    // Abstract properties and methods to be implemented by subclasses
}

public final class TreeNode: BaseNode {
    let _tree: Tree
    public let _from: Int
    public let index: Int
    public let _parent: TreeNode?
    
    public init(tree: Tree, from: Int, index: Int, parent: TreeNode?) {
        self._tree = tree
        self._from = from
        self.index = index
        self._parent = parent
    }
    
    public override var from: Int {
        return _from
    }
    
    public override var type: NodeType {
        return _tree.type
    }
    
    public override var name: String {
        return _tree.type.name
    }
    
    public override var to: Int {
        return from + _tree.length
    }
    
    public override var tree: Tree? {
        return _tree
    }
    
    func prop<T>(prop: NodeProp<T>) -> T? {
        return _tree.prop(prop: prop)
    }
    
    func toTree() -> Tree {
        return _tree
    }
    
    func toString() -> String {
        return _tree.toString()
    }
    
    func nextSignificantParent() -> TreeNode {
        var val: TreeNode = self
        while val.type.isAnonymous, let parent = val._parent {
            val = parent
        }
        return val
    }
    
    var parent: SyntaxNode? {
        return _parent?.nextSignificantParent()
    }
    
    var nextSibling: SyntaxNode? {
        guard let parent = _parent, index >= 0 else {
            return nil
        }
        return parent.nextChild(i: index + 1, dir: 1, pos: 0, side: .dontCare)
    }
    
    var prevSibling: SyntaxNode? {
        guard let parent = _parent, index >= 0 else {
            return nil
        }
        return parent.nextChild(i: index - 1, dir: -1, pos: 0, side: .dontCare)
    }
    
    var firstChild: SyntaxNode? {
        return nextChild(i: 0, dir: 1, pos: 0, side: .dontCare)
    }
    
    var lastChild: SyntaxNode? {
        return nextChild(i: _tree.children.count - 1, dir: -1, pos: 0, side: .dontCare)
    }
    
    func childAfter(pos: Int) -> SyntaxNode? {
        return nextChild(i: 0, dir: 1, pos: pos, side: .after)
    }
    
    func childBefore(pos: Int) -> SyntaxNode? {
        return nextChild(i: _tree.children.count - 1, dir: -1, pos: pos, side: .before)
    }
    
    func nextChild(i: Int, dir: Int, pos: Int, side: Side, mode: IterMode = []) -> SyntaxNode? {
        var parent = self
        
        while true {
            let children = parent._tree.children
            let positions = parent._tree.positions
            let end = dir > 0 ? children.count : -1
            
            var currentI = i
            while currentI != end {
                let next = children[currentI]
                let start = positions[currentI] + parent.from
                
                let shouldContinue: Bool
                if let nextTree = next.asTree,
                   mode.contains(.enterBracketed),
                   let mounted = MountedTree.get(tree: nextTree),
                   mounted.overlay == nil,
                   mounted.bracketed,
                   pos >= start,
                   pos <= start + nextTree.length {
                    shouldContinue = false
                } else if !checkSide(side: side, pos: pos, from: start, to: start + next.length) {
                    shouldContinue = true
                } else {
                    shouldContinue = false
                }
                
                if !shouldContinue {
                    if case .buffer(let buffer) = next {
                        if mode.contains(.excludeBuffers) {
                            currentI += dir
                            continue
                        }
                        let index = buffer.findChild(startIndex: 0, endIndex: buffer.buffer.count, dir: dir, pos: pos - start, side: side)
                        if index >= 0 {
                            return BufferNode(context: BufferContext(parent: parent, buffer: buffer, index: currentI, start: start), parent: nil, index: index)
                        }
                    } else if mode.contains(.includeAnonymous) || !next.type.isAnonymous || hasChild(treeOrBuffer: next) {
                        if let nextTree = next.asTree,
                           !mode.contains(.ignoreMounts),
                           let mounted = MountedTree.get(tree: nextTree),
                           mounted.overlay == nil {
                            return TreeNode(tree: mounted.tree, from: start, index: currentI, parent: parent)
                        }
                        
                        let inner = TreeNode(tree: next.asTree!, from: start, index: currentI, parent: parent)
                        
                        if mode.contains(.includeAnonymous) || !inner.type.isAnonymous {
                            return inner
                        } else {
                            let nextChildIndex = dir < 0 ? next.asTree!.children.count - 1 : 0
                            return inner.nextChild(i: nextChildIndex, dir: dir, pos: pos, side: side, mode: mode)
                        }
                    }
                }
                
                currentI += dir
            }
            
            if mode.contains(.includeAnonymous) || !parent.type.isAnonymous {
                return nil
            }
            
            let nextIndex = parent.index >= 0 ? parent.index + dir : (dir < 0 ? -1 : parent._parent!._tree.children.count)
            guard let nextParent = parent._parent else {
                return nil
            }
            parent = nextParent
            
            i = nextIndex
        }
    }
    
    func enter(pos: Int, side: SideInt, mode: IterMode = []) -> SyntaxNode? {
        if let mounted = MountedTree.get(tree: _tree), let overlay = mounted.overlay, !mode.contains(.ignoreOverlays) {
            let rPos = pos - from
            let enterBracketed = mode.contains(.enterBracketed) && mounted.bracketed
            
            for range in overlay {
                let shouldEnter: Bool
                if side > 0 || enterBracketed {
                    shouldEnter = range.from <= rPos
                } else {
                    shouldEnter = range.from < rPos
                }
                
                let shouldEnter2: Bool
                if side < 0 || enterBracketed {
                    shouldEnter2 = range.to >= rPos
                } else {
                    shouldEnter2 = range.to > rPos
                }
                
                if shouldEnter && shouldEnter2 {
                    return TreeNode(tree: mounted.tree, from: overlay[0].from + from, index: -1, parent: self)
                }
            }
        }
        
        return nextChild(i: 0, dir: 1, pos: pos, side: Side(rawValue: side) ?? .around, mode: mode)
    }
}

internal func getChildren(node: SyntaxNode, type: StringOrInt, before: StringOrInt?, after: StringOrInt?) -> [SyntaxNode] {
    let cur = node.cursor(mode: [])
    var result: [SyntaxNode] = []
    
    if !cur.firstChild() {
        return result
    }
    
    if let before = before {
        var found = false
        while !found {
            found = cur.type.is(before)
            if !cur.nextSibling() {
                return result
            }
        }
    }
    
    while true {
        if let after = after, cur.type.is(after) {
            return result
        }
        
        if cur.type.is(type) {
            result.append(cur.node)
        }
        
        if !cur.nextSibling() {
            return after == nil ? result : []
        }
    }
}

internal func matchNodeContext(node: SyntaxNode?, context: [String], i: Int = context.count - 1) -> Bool {
    var currentI = i
    var currentNode = node
    
    while currentI >= 0 {
        guard let p = currentNode else {
            return false
        }
        
        if !p.type.isAnonymous {
            if !context[currentI].isEmpty && context[currentI] != p.name {
                return false
            }
            currentI -= 1
        }
        
        currentNode = p.parent
    }
    
    return true
}

internal final class BufferContext {
    let parent: TreeNode
    let buffer: TreeBuffer
    let index: Int
    let start: Int
    
    init(parent: TreeNode, buffer: TreeBuffer, index: Int, start: Int) {
        self.parent = parent
        self.buffer = buffer
        self.index = index
        self.start = start
    }
}

public final class BufferNode: BaseNode {
    let context: BufferContext
    let _parent: BufferNode?
    let index: Int
    
    var type: NodeType {
        return context.buffer.set.types[Int(context.buffer.buffer[index])]
    }
    
    var name: String {
        return type.name
    }
    
    var from: Int {
        return context.start + Int(context.buffer.buffer[index + 1])
    }
    
    var to: Int {
        return context.start + Int(context.buffer.buffer[index + 2])
    }
    
    var tree: Tree? {
        return nil
    }
    
    init(context: BufferContext, parent: BufferNode?, index: Int) {
        self.context = context
        self._parent = parent
        self.index = index
    }
    
    func toTree() -> Tree {
        var children: [TreeOrBuffer] = []
        var positions: [Int] = []
        
        let startI = index + 4
        let endI = Int(context.buffer.buffer[index + 3])
        
        if endI > startI {
            let from = Int(context.buffer.buffer[index + 1])
            children.append(.buffer(context.buffer.slice(startI: startI, endI: endI, from: from)))
            positions.append(0)
        }
        
        return Tree(type: type, children: children, positions: positions, length: to - from)
    }
    
    func toString() -> String {
        return context.buffer.childString(index: index)
    }
    
    func prop<T>(prop: NodeProp<T>) -> T? {
        return type.prop(prop: prop)
    }
    
    var parent: SyntaxNode? {
        return _parent ?? context.parent.nextSignificantParent()
    }
    
    var firstChild: SyntaxNode? {
        return child(dir: 1, pos: 0, side: .dontCare)
    }
    
    var lastChild: SyntaxNode? {
        return child(dir: -1, pos: 0, side: .dontCare)
    }
    
    func childAfter(pos: Int) -> SyntaxNode? {
        return child(dir: 1, pos: pos, side: .after)
    }
    
    func childBefore(pos: Int) -> SyntaxNode? {
        return child(dir: -1, pos: pos, side: .before)
    }
    
    func enter(pos: Int, side: SideInt, mode: IterMode = []) -> SyntaxNode? {
        if mode.contains(.excludeBuffers) {
            return nil
        }
        
        let foundIndex = context.buffer.findChild(
            startIndex: index + 4,
            endIndex: Int(context.buffer.buffer[index + 3]),
            dir: side > 0 ? 1 : -1,
            pos: pos - context.start,
            side: Side(rawValue: side) ?? .around
        )
        
        return foundIndex < 0 ? nil : BufferNode(context: context, parent: self, index: foundIndex)
    }
    
    func child(dir: Int, pos: Int, side: Side) -> BufferNode? {
        let index = context.buffer.findChild(
            startIndex: index + 4,
            endIndex: Int(context.buffer.buffer[index + 3]),
            dir: dir,
            pos: pos - context.start,
            side: side
        )
        
        return index < 0 ? nil : BufferNode(context: context, parent: self, index: index)
    }
    
    var nextSibling: SyntaxNode? {
        let after = Int(context.buffer.buffer[index + 3])
        let parentEnd = _parent != nil ? Int(context.buffer.buffer[(_parent?.index)! + 3]) : context.buffer.buffer.count
        
        if after < parentEnd {
            return BufferNode(context: context, parent: _parent, index: after)
        }
        
        return externalSibling(dir: 1)
    }
    
    var prevSibling: SyntaxNode? {
        let parentStart = _parent != nil ? _parent!.index + 4 : 0
        
        if index == parentStart {
            return externalSibling(dir: -1)
        }
        
        let foundIndex = context.buffer.findChild(
            startIndex: parentStart,
            endIndex: index,
            dir: -1,
            pos: 0,
            side: .dontCare
        )
        
        return BufferNode(context: context, parent: _parent, index: foundIndex)
    }
    
    func externalSibling(dir: Int) -> SyntaxNode? {
        if _parent != nil {
            return nil
        }
        return context.parent.nextChild(i: context.index + dir, dir: dir, pos: 0, side: .dontCare)
    }
}

internal final class StackIterator {
    let heads: [SyntaxNode]
    let node: SyntaxNode
    
    init(heads: [SyntaxNode], node: SyntaxNode) {
        self.heads = heads
        self.node = node
    }
    
    var next: NodeIterator? {
        return iterStack(heads: heads)
    }
}

internal func iterStack(heads: [SyntaxNode]) -> NodeIterator? {
    if heads.isEmpty {
        return nil
    }
    
    var pick = 0
    var picked = heads[0]
    
    for i in 1..<heads.count {
        let node = heads[i]
        if node.from > picked.from || node.to < picked.to {
            picked = node
            pick = i
        }
    }
    
    let next = (picked is TreeNode && (picked as! TreeNode).index < 0) ? nil : picked.parent
    var newHeads = heads
    if let next = next {
        newHeads[pick] = next
    } else {
        newHeads.remove(at: pick)
    }
    
    return NodeIterator(node: picked, next: StackIterator(heads: newHeads, node: picked).next)
}

internal func stackIterator(tree: Tree, pos: Int, side: Int) -> NodeIterator {
    let inner = tree.resolveInner(pos: pos, side: side)
    var layers: [SyntaxNode]? = nil
    
    var scan: TreeNode? = (inner as? TreeNode) ?? (inner as? BufferNode)?.context.parent
    
    while let currentScan = scan {
        if currentScan.index < 0 {
            let parent = currentScan.parent!
            if layers == nil {
                layers = [inner]
            }
            layers!.append(parent.resolve(pos: pos, side: side))
            scan = parent as? TreeNode
        } else {
            if let mount = MountedTree.get(tree: currentScan.tree),
               let overlay = mount.overlay,
               overlay[0].from <= pos,
               overlay[overlay.count - 1].to >= pos {
                let root = TreeNode(tree: mount.tree, from: overlay[0].from + currentScan.from, index: -1, parent: currentScan)
                if layers == nil {
                    layers = [inner]
                }
                layers!.append(resolveNode(node: root, pos: pos, side: side, overlays: false))
            }
        }
        scan = currentScan.parent as? TreeNode
    }
    
    return layers != nil ? iterStack(heads: layers!)! : NodeIterator(node: inner, next: nil)
}

/// A tree cursor object focuses on a given node in a syntax tree, and allows you to move to adjacent nodes.
public final class TreeCursor: SyntaxNodeRef {
    var type: NodeType!
    var from: Int!
    var to: Int!
    var _tree: TreeNode!
    var buffer: BufferContext? = nil
    private var stack: [Int] = []
    var index: Int = 0
    private var bufferNode: BufferNode? = nil
    let mode: IterMode
    
    init(treeNode: TreeNode?, bufferNode: BufferNode?, mode: IterMode = []) {
        self.mode = mode.subtracting(.enterBracketed)
        
        if let treeNode = treeNode {
            yieldNode(node: treeNode)
        } else if let bufferNode = bufferNode {
            _tree = bufferNode.context.parent
            buffer = bufferNode.context
            var n: BufferNode? = bufferNode
            while let current = n {
                stack.insert(current.index, at: 0)
                n = current._parent
            }
            self.bufferNode = bufferNode
            yieldBuf(index: bufferNode.index)
        } else {
            fatalError("Either treeNode or bufferNode must be provided")
        }
    }
    
    convenience init(node: SyntaxNode, mode: IterMode = []) {
        if let treeNode = node as? TreeNode {
            self.init(treeNode: treeNode, bufferNode: nil, mode: mode)
        } else if let bufferNode = node as? BufferNode {
            self.init(treeNode: nil, bufferNode: bufferNode, mode: mode)
        } else {
            fatalError("Node must be TreeNode or BufferNode")
        }
    }
    
    private func yieldNode(node: TreeNode?) -> Bool {
        guard let node = node else {
            return false
        }
        _tree = node
        type = node.type
        from = node.from
        to = node.to
        return true
    }
    
    private func yieldBuf(index: Int, type: NodeType? = nil) -> Bool {
        self.index = index
        let start = buffer!.start
        let buffer = buffer!.buffer
        self.type = type ?? buffer.set.types[Int(buffer.buffer[index])]
        from = start + Int(buffer.buffer[index + 1])
        to = start + Int(buffer.buffer[index + 2])
        return true
    }
    
    func yield(treeNode: TreeNode?, bufferNode: BufferNode?) -> Bool {
        if let treeNode = treeNode {
            buffer = nil
            return yieldNode(node: treeNode)
        } else if let bufferNode = bufferNode {
            buffer = bufferNode.context
            return yieldBuf(index: bufferNode.index, type: bufferNode.type)
        }
        
        return false
    }
    
    func toString() -> String {
        return buffer != nil ? buffer!.buffer.childString(index: index) : _tree.toString()
    }
    
    func enterChild(dir: Int, pos: Int, side: Side) -> Bool {
        if buffer == nil {
            let nextChildIndex = dir < 0 ? _tree._tree.children.count - 1 : 0
            return yield(node: _tree.nextChild(i: nextChildIndex, dir: dir, pos: pos, side: side, mode: mode))
        }
        
        let buf = buffer!.buffer
        let index = buf.findChild(
            startIndex: index + 4,
            endIndex: Int(buf.buffer[index + 3]),
            dir: dir,
            pos: pos - buffer!.start,
            side: side
        )
        
        if index < 0 {
            return false
        }
        
        stack.append(index)
        return yieldBuf(index: index)
    }
    
    func firstChild() -> Bool {
        return enterChild(dir: 1, pos: 0, side: .dontCare)
    }
    
    func lastChild() -> Bool {
        return enterChild(dir: -1, pos: 0, side: .dontCare)
    }
    
    func childAfter(pos: Int) -> Bool {
        return enterChild(dir: 1, pos: pos, side: .after)
    }
    
    func childBefore(pos: Int) -> Bool {
        return enterChild(dir: -1, pos: pos, side: .before)
    }
    
    func enter(pos: Int, side: SideInt = 0, mode: IterMode? = nil) -> Bool {
        let actualMode = mode ?? self.mode
        if buffer == nil {
            return yield(node: _tree.enter(pos: pos, side: side, mode: actualMode))
        }
        
        if actualMode.contains(.excludeBuffers) {
            return false
        }
        
        return enterChild(dir: 1, pos: pos, side: Side(rawValue: side) ?? .around)
    }
    
    func parent() -> Bool {
        if buffer == nil {
            let parent = mode.contains(.includeAnonymous) ? _tree._parent : _tree.parent
            return yieldNode(node: parent as? TreeNode)
        }
        
        if !stack.isEmpty {
            return yieldBuf(index: stack.removeLast())
        }
        
        let parent = mode.contains(.includeAnonymous) ? buffer!.parent : buffer!.parent.nextSignificantParent()
        buffer = nil
        return yieldNode(node: parent as? TreeNode)
    }
    
    func sibling(dir: Int) -> Bool {
        if buffer == nil {
            guard let parent = _tree._parent else {
                return false
            }
            
            if _tree.index < 0 {
                return yield(node: nil)
            }
            
            return yield(node: parent.nextChild(i: _tree.index + dir, dir: dir, pos: 0, side: .dontCare, mode: mode))
        }
        
        let buf = buffer!.buffer
        let d = stack.count - 1
        
        if dir < 0 {
            let parentStart = d < 0 ? 0 : stack[d] + 4
            if index != parentStart {
                let foundIndex = buf.findChild(startIndex: parentStart, endIndex: index, dir: -1, pos: 0, side: .dontCare)
                return yieldBuf(index: foundIndex)
            }
        } else {
            let after = Int(buf.buffer[index + 3])
            let parentEnd = d < 0 ? buf.buffer.count : Int(buf.buffer[stack[d] + 3])
            
            if after < parentEnd {
                return yieldBuf(index: after)
            }
        }
        
        if d < 0 {
            return yield(node: buffer!.parent.nextChild(i: buffer!.index + dir, dir: dir, pos: 0, side: .dontCare, mode: mode))
        }
        
        return false
    }
    
    func nextSibling() -> Bool {
        return sibling(dir: 1)
    }
    
    func prevSibling() -> Bool {
        return sibling(dir: -1)
    }
    
    private func atLastNode(dir: Int) -> Bool {
        var index: Int
        var parent: TreeNode?
        let buffer = self.buffer
        
        if let buffer = buffer {
            if dir > 0 {
                if index < buffer.buffer.buffer.count {
                    return false
                }
            } else {
                for i in 0..<index {
                    if buffer.buffer.buffer[i + 3] < index {
                        return false
                    }
                }
            }
            parent = buffer.parent
        } else {
            index = _tree.index
            parent = _tree._parent
        }
        
        while let currentParent = parent {
            if index > -1 {
                let start = dir < 0 ? -1 : 0
                let end = dir < 0 ? index + 1 : currentParent._tree.children.count
                
                for i in stride(from: index + dir, through: end, by: dir) {
                    if i < 0 || i >= currentParent._tree.children.count {
                        continue
                    }
                    
                    let child = currentParent._tree.children[i]
                    
                    if mode.contains(.includeAnonymous) ||
                       case .buffer = child ||
                       !child.type.isAnonymous ||
                       hasChild(treeOrBuffer: child) {
                        return false
                    }
                }
            }
            
            index = currentParent.index
            parent = currentParent._parent
        }
        
        return true
    }
    
    private func move(dir: Int, enter: Bool) -> Bool {
        if enter && enterChild(dir: dir, pos: 0, side: .dontCare) {
            return true
        }
        
        while true {
            if sibling(dir: dir) {
                return true
            }
            if atLastNode(dir: dir) || !parent() {
                return false
            }
        }
    }
    
    func next(enter: Bool = true) -> Bool {
        return move(dir: 1, enter: enter)
    }
    
    func prev(enter: Bool = true) -> Bool {
        return move(dir: -1, enter: enter)
    }
    
    func moveTo(pos: Int, side: SideInt = 0) -> TreeCursor {
        while from == to ||
              (side < 1 ? from >= pos : from > pos) ||
              (side > -1 ? to <= pos : to < pos) {
            if !parent() {
                break
            }
        }
        
        while enterChild(dir: 1, pos: pos, side: Side(rawValue: side) ?? .around) {
            // Keep entering
        }
        
        return self
    }
    
    var node: SyntaxNode {
        if buffer == nil {
            return _tree
        }
        
        let cache = bufferNode
        var result: BufferNode? = nil
        var depth = 0
        
        if let cache = cache, cache.context === buffer {
            var currentIndex = index
            var currentDepth = stack.count
            
            scan: while currentDepth >= 0 {
                var c: BufferNode? = cache
                while let current = c {
                    if current.index == currentIndex {
                        if currentIndex == index {
                            return current
                        }
                        result = current
                        depth = currentDepth + 1
                        break scan
                    }
                    c = current._parent
                }
                
                currentDepth -= 1
                if currentDepth >= 0 {
                    currentIndex = stack[currentDepth]
                }
            }
        }
        
        for i in depth..<stack.count {
            result = BufferNode(context: buffer!, parent: result, index: stack[i])
        }
        
        bufferNode = BufferNode(context: buffer!, parent: result, index: index)
        return bufferNode!
    }
    
    var tree: Tree? {
        return buffer == nil ? _tree._tree : nil
    }
    
    func iterate(enter: (SyntaxNodeRef) -> Bool, leave: ((SyntaxNodeRef) -> Void)? = nil) {
        var depth = 0
        
        while true {
            var mustLeave = false
            
            if type.isAnonymous || enter(self) != false {
                if firstChild() {
                    depth += 1
                    continue
                }
                if !type.isAnonymous {
                    mustLeave = true
                }
            }
            
            while true {
                if mustLeave, let leave = leave {
                    leave(self)
                }
                
                mustLeave = type.isAnonymous
                
                if depth == 0 {
                    return
                }
                
                if nextSibling() {
                    break
                }
                
                _ = parent()
                depth -= 1
                mustLeave = true
            }
        }
    }
    
    func matchContext(context: [String]) -> Bool {
        if buffer == nil {
            return matchNodeContext(node: node.parent, context: context)
        }
        
        let buffer = self.buffer!
        let types = buffer.buffer.set.types
        var i = context.count - 1
        var d = stack.count - 1
        
        while i >= 0 {
            if d < 0 {
                return matchNodeContext(node: _tree, context: context, i: i)
            }
            
            let type = types[Int(buffer.buffer.buffer[stack[d]])]
            
            if !type.isAnonymous {
                if !context[i].isEmpty && context[i] != type.name {
                    return false
                }
                i -= 1
            }
            
            d -= 1
        }
        
        return true
    }
    
    var name: String {
        return type.name
    }
}

internal func hasChild(treeOrBuffer: TreeOrBuffer) -> Bool {
    switch treeOrBuffer {
    case .tree(let tree):
        return tree.children.contains { child in
            switch child {
            case .buffer:
                return true
            case .tree(let t):
                return !t.type.isAnonymous || hasChild(treeOrBuffer: .tree(t))
            }
        }
    case .buffer:
        return false
    }
}

internal func buildTree(data: BuildData) -> Tree {
    let cursor: any BufferCursor
    switch data.buffer {
    case .cursor(let c):
        cursor = c
    case .array(let arr):
        cursor = FlatBufferCursor(buffer: arr, index: arr.count)
    }
    
    let types = data.nodeSet.types
    var contextHash = 0
    var lookAhead = 0
    
    func takeNode(
        parentStart: Int,
        minPos: Int,
        children: inout [TreeOrBuffer],
        positions: inout [Int],
        inRepeat: Int,
        depth: Int
    ) {
        let lookAheadAtStart = lookAhead
        let contextAtStart = contextHash
        let size = cursor.size
        
        if size < 0 {
            cursor.next()
            
            enum SpecialRecord: Int {
                case reuse = -1
                case contextChange = -3
                case lookAhead = -4
            }
            
            if size == SpecialRecord.reuse.rawValue {
                let node = data.reused[cursor.id]
                children.append(.tree(node))
                positions.append(cursor.start - parentStart)
                return
            } else if size == SpecialRecord.contextChange.rawValue {
                contextHash = cursor.id
                return
            } else if size == SpecialRecord.lookAhead.rawValue {
                lookAhead = cursor.id
                return
            } else {
                fatalError("Unrecognized record size: \(size)")
            }
        }
        
        let type = types[cursor.id]
        let startPos = cursor.start - parentStart
        let end = cursor.end
        let start = cursor.start
        
        if end - start <= data.maxBufferLength {
            var node: TreeOrBuffer?
            
            if let bufferSize = findBufferSize(maxSize: cursor.pos - minPos, inRepeat: inRepeat) {
                let dataArr = [UInt16](repeating: 0, count: bufferSize.size - bufferSize.skip)
                var endPos = cursor.pos - bufferSize.size
                var index = dataArr.count
                
                while cursor.pos > endPos {
                    index = copyToBuffer(bufferStart: bufferSize.start, buffer: &dataArr, index: index)
                }
                
                let newBuffer = TreeBuffer(buffer: dataArr, length: end - bufferSize.start, set: data.nodeSet)
                node = .buffer(newBuffer)
                let newStartPos = bufferSize.start - parentStart
                children.append(node!)
                positions.append(newStartPos)
                return
            }
        }
        
        let endPos = cursor.pos - size
        cursor.next()
        
        var localChildren: [TreeOrBuffer] = []
        var localPositions: [Int] = []
        let localInRepeat = cursor.id >= data.minRepeatType ? cursor.id : -1
        var lastGroup = 0
        var lastEnd = end
        
        while cursor.pos > endPos {
            if localInRepeat >= 0 && cursor.id == localInRepeat && cursor.size >= 0 {
                if cursor.end <= lastEnd - data.maxBufferLength {
                    makeRepeatLeaf(
                        children: &localChildren,
                        positions: &localPositions,
                        base: start,
                        i: lastGroup,
                        from: cursor.end,
                        to: lastEnd,
                        type: localInRepeat,
                        lookAhead: lookAheadAtStart,
                        contextHash: contextAtStart
                    )
                    lastGroup = localChildren.count
                    lastEnd = cursor.end
                }
                cursor.next()
            } else if depth > 2500 {
                takeFlatNode(
                    parentStart: start,
                    minPos: endPos,
                    children: &localChildren,
                    positions: &localPositions
                )
            } else {
                takeNode(
                    parentStart: start,
                    minPos: endPos,
                    children: &localChildren,
                    positions: &localPositions,
                    inRepeat: localInRepeat,
                    depth: depth + 1
                )
            }
        }
        
        if localInRepeat >= 0 && lastGroup > 0 && lastGroup < localChildren.count {
            makeRepeatLeaf(
                children: &localChildren,
                positions: &localPositions,
                base: start,
                i: lastGroup,
                from: start,
                to: lastEnd,
                type: localInRepeat,
                lookAhead: lookAheadAtStart,
                contextHash: contextAtStart
            )
        }
        
        localChildren.reverse()
        localPositions.reverse()
        
        let nodeTree: Tree
        if localInRepeat > -1 && lastGroup > 0 {
            let make = makeBalanced(type: type, contextHash: contextAtStart)
            nodeTree = balanceRange(
                balanceType: type,
                children: localChildren,
                positions: localPositions,
                from: 0,
                to: localChildren.count,
                start: 0,
                length: end - start,
                mkTop: make,
                mkTree: make
            )
        } else {
            nodeTree = makeTree(
                type: type,
                children: localChildren,
                positions: localPositions,
                length: end - start,
                lookAhead: lookAheadAtStart - end,
                contextHash: contextAtStart
            )
        }
        
        children.append(.tree(nodeTree))
        positions.append(startPos)
    }
    
    func takeFlatNode(
        parentStart: Int,
        minPos: Int,
        children: inout [TreeOrBuffer],
        positions: inout [Int]
    ) {
        var nodes: [Int] = []
        var nodeCount = 0
        var stopAt = -1
        
        while cursor.pos > minPos {
            let size = cursor.size
            
            if size > 4 {
                cursor.next()
            } else if stopAt > -1 && cursor.start < stopAt {
                break
            } else {
                if stopAt < 0 {
                    stopAt = cursor.end - data.maxBufferLength
                }
                nodes.append(cursor.id)
                nodes.append(cursor.start)
                nodes.append(cursor.end)
                nodeCount += 1
                cursor.next()
            }
        }
        
        if nodeCount > 0 {
            var buffer = [UInt16](repeating: 0, count: nodeCount * 4)
            let startPos = nodes[nodes.count - 2]
            var j = 0
            
            for i in stride(from: nodes.count - 3, through: 0, by: -3) {
                buffer[j] = UInt16(nodes[i])
                j += 1
                buffer[j] = UInt16(nodes[i + 1] - startPos)
                j += 1
                buffer[j] = UInt16(nodes[i + 2] - startPos)
                j += 1
                buffer[j] = UInt16(j)
                j += 1
            }
            
            children.append(.buffer(TreeBuffer(
                buffer: buffer,
                length: nodes[2] - startPos,
                set: data.nodeSet
            )))
            positions.append(startPos - parentStart)
        }
    }
    
    func makeBalanced(type: NodeType, contextHash: Int) -> ([TreeOrBuffer], [Int], Int) -> Tree {
        return { children, positions, length in
            var lookAhead = 0
            var lastI = children.count - 1
            var last: Tree?
            var lookAheadProp: Int?
            
            if lastI >= 0, case .tree(let tree) = children[lastI] {
                last = tree
                if lastI == 0 && last!.type == type && last!.length == length {
                    return last!
                }
                lookAheadProp = last!.prop(prop: nodePropLookAhead)
                if let lookAheadProp = lookAheadProp {
                    lookAhead = positions[lastI] + last!.length + lookAheadProp
                }
            }
            
            return makeTree(
                type: type,
                children: children,
                positions: positions,
                length: length,
                lookAhead: lookAhead,
                contextHash: contextHash
            )
        }
    }
    
    func makeRepeatLeaf(
        children: inout [TreeOrBuffer],
        positions: inout [Int],
        base: Int,
        i: Int,
        from: Int,
        to: Int,
        type: Int,
        lookAhead: Int,
        contextHash: Int
    ) {
        var localChildren: [TreeOrBuffer] = []
        var localPositions: [Int] = []
        
        while children.count > i {
            localChildren.append(children.removeLast())
            localPositions.append(positions.removeLast() + base - from)
        }
        
        localChildren.reverse()
        localPositions.reverse()
        
        children.append(.tree(makeTree(
            type: data.nodeSet.types[type],
            children: localChildren,
            positions: localPositions,
            length: to - from,
            lookAhead: lookAhead - to,
            contextHash: contextHash
        )))
        positions.append(from - base)
    }
    
    func makeTree(
        type: NodeType,
        children: [TreeOrBuffer],
        positions: [Int],
        length: Int,
        lookAhead: Int,
        contextHash: Int,
        props: [PropPair]? = nil
    ) -> Tree {
        var finalProps = props
        
        if contextHash != 0 {
            let pair = PropPair(propId: nodePropContextHash.id, value: contextHash)
            if finalProps == nil {
                finalProps = [pair]
            } else {
                finalProps!.insert(pair, at: 0)
            }
        }

        if lookAhead > 25 {
            let pair = PropPair(propId: nodePropLookAhead.id, value: lookAhead)
            if finalProps == nil {
                finalProps = [pair]
            } else {
                finalProps!.insert(pair, at: 0)
            }
        }
        
        return Tree(type: type, children: children, positions: positions, length: length, props: finalProps)
    }
    
    func findBufferSize(maxSize: Int, inRepeat: Int) -> (size: Int, start: Int, skip: Int)? {
        let fork = cursor.fork()
        var size = 0
        var start = 0
        var skip = 0
        let minStart = fork.end - data.maxBufferLength
        var result: (size: Int, start: Int, skip: Int)? = (size: 0, start: 0, skip: 0)
        
        var minPos = fork.pos - maxSize
        
        while fork.pos > minPos {
            let nodeSize = fork.size
            
            if fork.id == inRepeat && nodeSize >= 0 {
                result = (size: size, start: start, skip: skip)
                skip += 4
                size += 4
                fork.next()
                continue
            }
            
            let startPos = fork.pos - nodeSize
            
            if nodeSize < 0 || startPos < minPos || fork.start < minStart {
                break
            }
            
            var localSkipped = fork.id >= data.minRepeatType ? 4 : 0
            let nodeStart = fork.start
            fork.next()
            
            while fork.pos > startPos {
                let size = fork.size
                if size < 0 {
                    if size == -3 || size == -4 {
                        localSkipped += 4
                    } else {
                        return result?.size ?? 0 > 4 ? result : nil
                    }
                } else if fork.id >= data.minRepeatType {
                    localSkipped += 4
                }
                fork.next()
            }
            
            start = nodeStart
            size += nodeSize
            skip += localSkipped
        }
        
        if inRepeat < 0 || size == maxSize {
            result = (size: size, start: start, skip: skip)
        }
        
        return (result?.size ?? 0) > 4 ? result : nil
    }
    
    func copyToBuffer(bufferStart: Int, buffer: inout [UInt16], index: Int) -> Int {
        let id = cursor.id
        let start = cursor.start
        let end = cursor.end
        let size = cursor.size
        
        cursor.next()
        
        var currentIndex = index
        
        if size >= 0 && id < data.minRepeatType {
            let startIndex = currentIndex
            
            if size > 4 {
                let endPos = cursor.pos - (size - 4)
                while cursor.pos > endPos {
                    currentIndex = copyToBuffer(bufferStart: bufferStart, buffer: &buffer, index: currentIndex)
                }
            }
            
            buffer[currentIndex - 1] = UInt16(startIndex)
            buffer[currentIndex - 2] = UInt16(end - bufferStart)
            buffer[currentIndex - 3] = UInt16(start - bufferStart)
            buffer[currentIndex - 4] = UInt16(id)
        }
        
        return currentIndex
    }
    
    var children: [TreeOrBuffer] = []
    var positions: [Int] = []
    
    while cursor.pos > 0 {
        takeNode(
            parentStart: data.start,
            minPos: data.bufferStart,
            children: &children,
            positions: &positions,
            inRepeat: -1,
            depth: 0
        )
    }
    
    let length = data.length ?? (children.isEmpty ? 0 : positions[0] + children[0].length)
    
    return Tree(
        type: types[data.topID],
        children: children.reversed(),
        positions: positions.reversed(),
        length: length
    )
}

internal var nodeSizeCache: WeakMap<Tree, Int> = WeakMap()

internal func nodeSize(balanceType: NodeType, node: TreeOrBuffer) -> Int {
    if !balanceType.isAnonymous {
        return 1
    }
    
    switch node {
    case .buffer:
        return 1
    case .tree(let tree):
        if tree.type != balanceType {
            return 1
        }
        
        if let cached = nodeSizeCache[tree] {
            return cached
        }
        
        var size = 1
        for child in tree.children {
            if child.type != balanceType || case .buffer = child {
                size = 1
                break
            }
            size += nodeSize(balanceType: balanceType, node: child)
        }
        
        nodeSizeCache[tree] = size
        return size
    }
}

internal func balanceRange(
    balanceType: NodeType,
    children: [TreeOrBuffer],
    positions: [Int],
    from: Int,
    to: Int,
    start: Int,
    length: Int,
    mkTop: (([TreeOrBuffer], [Int], Int) -> Tree)?,
    mkTree: ([TreeOrBuffer], [Int], Int) -> Tree
) -> Tree {
    var total = 0
    for i in from..<to {
        total += nodeSize(balanceType: balanceType, node: children[i])
    }
    
    let maxChild = Int(ceil(Double(total * 1.5) / Double(Balance.branchFactor)))
    var localChildren: [TreeOrBuffer] = []
    var localPositions: [Int] = []
    
    func divide(
        children: [TreeOrBuffer],
        positions: [Int],
        from: Int,
        to: Int,
        offset: Int
    ) {
        var i = from
        while i < to {
            let groupFrom = i
            let groupStart = positions[i]
            var groupSize = nodeSize(balanceType: balanceType, node: children[i])
            i += 1
            
            while i < to {
                let nextSize = nodeSize(balanceType: balanceType, node: children[i])
                if groupSize + nextSize >= maxChild {
                    break
                }
                groupSize += nextSize
                i += 1
            }
            
            if i == groupFrom + 1 {
                if groupSize > maxChild, case .tree(let only) = children[groupFrom] {
                    divide(
                        children: only.children,
                        positions: only.positions,
                        from: 0,
                        to: only.children.count,
                        offset: positions[groupFrom] + offset
                    )
                    continue
                }
                localChildren.append(children[groupFrom])
            } else {
                let groupLength = positions[i - 1] + children[i - 1].length - groupStart
                localChildren.append(balanceRange(
                    balanceType: balanceType,
                    children: children,
                    positions: positions,
                    from: groupFrom,
                    to: i,
                    start: groupStart,
                    length: groupLength,
                    mkTop: nil,
                    mkTree: mkTree
                ))
            }
            
            localPositions.append(groupStart + offset - start)
        }
    }
    
    divide(children: children, positions: positions, from: from, to: to, offset: 0)
    
    let finalMkTop = mkTop ?? mkTree
    return finalMkTop(localChildren, localPositions, length)
}

/// Provides a way to associate values with pieces of trees.
public final class NodeWeakMap<T> {
    private var treeMap: WeakMap<Tree, T> = WeakMap()
    private var bufferMap: WeakMap<TreeBuffer, [Int: T]> = WeakMap()
    
    private func setBuffer(buffer: TreeBuffer, index: Int, value: T) {
        var inner = bufferMap[buffer]
        if inner == nil {
            inner = [:]
            bufferMap[buffer] = inner!
        }
        inner![index] = value
    }
    
    private func getBuffer(buffer: TreeBuffer, index: Int) -> T? {
        return bufferMap[buffer]?[index]
    }
    
    public func set(node: SyntaxNode, value: T) {
        if let bufferNode = node as? BufferNode {
            setBuffer(buffer: bufferNode.context.buffer, index: bufferNode.index, value: value)
        } else if let treeNode = node as? TreeNode {
            treeMap[treeNode.tree] = value
        }
    }
    
    public func get(node: SyntaxNode) -> T? {
        if let bufferNode = node as? BufferNode {
            return getBuffer(buffer: bufferNode.context.buffer, index: bufferNode.index)
        } else if let treeNode = node as? TreeNode {
            return treeMap[treeNode.tree]
        }
        return nil
    }
    
    public func cursorSet(cursor: TreeCursor, value: T) {
        if let buffer = cursor.buffer {
            setBuffer(buffer: buffer.buffer, index: cursor.index, value: value)
        } else if let tree = cursor.tree {
            treeMap[tree] = value
        }
    }
    
    public func cursorGet(cursor: TreeCursor) -> T? {
        if let buffer = cursor.buffer {
            return getBuffer(buffer: buffer.buffer, index: cursor.index)
        } else if let tree = cursor.tree {
            return treeMap[tree]
        }
        return nil
    }
}

// Helper extensions
extension TreeOrBuffer {
    var asTree: Tree? {
        if case .tree(let tree) = self {
            return tree
        }
        return nil
    }
}

// WeakMap implementation
internal final class WeakMap<Key: AnyObject, Value> {
    private struct WeakBox {
        weak var value: Key?
    }
    
    private var boxes: [WeakBox] = []
    private var values: [ObjectIdentifier: Value] = [:]
    
    subscript(key: Key) -> Value? {
        get {
            return values[ObjectIdentifier(key)]
        }
        set {
            let id = ObjectIdentifier(key)
            if let newValue = newValue {
                if values[id] == nil {
                    boxes.append(WeakBox(value: key))
                }
                values[id] = newValue
            } else {
                values.removeValue(forKey: id)
            }
        }
    }
    
    init() {}
}
