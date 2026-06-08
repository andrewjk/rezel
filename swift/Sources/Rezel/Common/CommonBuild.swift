import Foundation

enum Balance {
	static let branchFactor = 8
}

enum CutOff {
	// Cut off at a shallower point than JS, because Swift's stack has less room?
	static let depth = 150
}

enum SpecialRecord {
	static let reuse = -1
	static let contextChange = -3
	static let lookAhead = -4
}

public struct BuildData {
	public var buffer: Any
	public var nodeSet: NodeSet
	public var topID: Int
	public var start: Int?
	public var bufferStart: Int?
	public var length: Int?
	public var maxBufferLength: Int?
	public var reused: [Tree]?
	public var minRepeatType: Int?

	public init(
		buffer: Any,
		nodeSet: NodeSet,
		topID: Int,
		start: Int? = nil,
		bufferStart: Int? = nil,
		length: Int? = nil,
		maxBufferLength: Int? = nil,
		reused: [Tree]? = nil,
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
		self.minRepeatType = minRepeatType
	}
}

public protocol BufferCursorProtocol {
	var pos: Int { get }
	var id: Int { get }
	var start: Int { get }
	var end: Int { get }
	var size: Int { get }
	mutating func next()
	mutating func fork() -> BufferCursorProtocol
}

public final class FlatBufferCursor: BufferCursorProtocol {
	public let buffer: [Int]
	public var index: Int

	public init(buffer: [Int], index: Int) {
		self.buffer = buffer
		self.index = index
	}

	public var id: Int {
		buffer[index - 4]
	}

	public var start: Int {
		buffer[index - 3]
	}

	public var end: Int {
		buffer[index - 2]
	}

	public var size: Int {
		buffer[index - 1]
	}

	public var pos: Int {
		index
	}

	public func next() {
		index -= 4
	}

	public func fork() -> BufferCursorProtocol {
		return FlatBufferCursor(buffer: buffer, index: index)
	}
}

func buildTree(data: BuildData) -> Tree {
	let maxBufferLength = data.maxBufferLength ?? defaultBufferLength
	let reused = data.reused ?? []
	let minRepeatType = data.minRepeatType ?? data.nodeSet.types.count
	let types = data.nodeSet.types
	let buildNodeSet = data.nodeSet

	var cursor: BufferCursorProtocol
	if let arr = data.buffer as? [Int] {
		cursor = FlatBufferCursor(buffer: arr, index: arr.count)
	} else if let bc = data.buffer as? BufferCursorProtocol {
		cursor = bc
	} else {
		fatalError("BuildData.buffer must be [Int] or BufferCursorProtocol")
	}

	var contextHash = 0
	var lookAhead = 0

	func takeNode(
		parentStart: Int, minPos: Int,
		children: inout [Any], positions: inout [Int],
		inRepeat: Int, depth: Int
	) {
		let id = cursor.id
		let start = cursor.start
		let end = cursor.end
		let size = cursor.size
		let lookAheadAtStart = lookAhead
		let contextAtStart = contextHash

		if size < 0 {
			cursor.next()
			if size == SpecialRecord.reuse {
				let node = reused[id]
				children.append(node)
				positions.append(start - parentStart)
				return
			} else if size == SpecialRecord.contextChange {
				contextHash = id
				return
			} else if size == SpecialRecord.lookAhead {
				lookAhead = id
				return
			} else {
				fatalError("Unrecognized record size: \(size)")
			}
		}

		let type = types[id]
		var node: Any
		let startPos: Int

		if end - start <= maxBufferLength,
		   let bufInfo = findBufferSize(cursor.pos - minPos, inRepeat: inRepeat)
		{
			var bufferData = [UInt16](repeating: 0, count: bufInfo.size - bufInfo.skip)
			let endPos = cursor.pos - bufInfo.size
			var idx = bufferData.count
			while cursor.pos > endPos {
				idx = copyToBuffer(bufferStart: bufInfo.start, buffer: &bufferData, index: idx)
			}
			node = TreeBuffer(buffer: bufferData, length: end - bufInfo.start, set: buildNodeSet)
			startPos = bufInfo.start - parentStart
		} else {
			let endPos = cursor.pos - size
			cursor.next()
			var localChildren: [Any] = []
			var localPositions: [Int] = []
			let localInRepeat = id >= minRepeatType ? id : -1
			var lastGroup = 0
			var lastEnd = end

			while cursor.pos > endPos {
				if localInRepeat >= 0 && cursor.id == localInRepeat && cursor.size >= 0 {
					if cursor.end <= lastEnd - maxBufferLength {
						makeRepeatLeaf(
							children: &localChildren, positions: &localPositions,
							base: start, i: lastGroup, from: cursor.end, to: lastEnd,
							type: localInRepeat, lookAhead: lookAheadAtStart, contextHash: contextAtStart
						)
						lastGroup = localChildren.count
						lastEnd = cursor.end
					}
					cursor.next()
				} else if depth > CutOff.depth {
					takeFlatNode(parentStart: start, minPos: endPos, children: &localChildren, positions: &localPositions)
				} else {
					takeNode(parentStart: start, minPos: endPos, children: &localChildren, positions: &localPositions, inRepeat: localInRepeat, depth: depth + 1)
				}
			}

			if localInRepeat >= 0 && lastGroup > 0 && lastGroup < localChildren.count {
				makeRepeatLeaf(
					children: &localChildren, positions: &localPositions,
					base: start, i: lastGroup, from: start, to: lastEnd,
					type: localInRepeat, lookAhead: lookAheadAtStart, contextHash: contextAtStart
				)
			}
			localChildren.reverse()
			localPositions.reverse()

			if localInRepeat > -1 && lastGroup > 0 {
				let make = makeBalanced(type: type, contextHash: contextAtStart)
				node = balanceRange(
					balanceType: type, children: localChildren, positions: localPositions,
					from: 0, to: localChildren.count, start: 0, length: end - start,
					mkTop: make, mkTree: make
				)
			} else {
				node = makeTreeInternal(
					type: type, children: localChildren, positions: localPositions,
					length: end - start, lookAhead: lookAheadAtStart - end, contextHash: contextAtStart
				)
			}
			startPos = start - parentStart
		}

		children.append(node)
		positions.append(startPos)
	}

	func takeFlatNode(
		parentStart: Int, minPos: Int,
		children: inout [Any], positions: inout [Int]
	) {
		var nodes: [Int] = []
		var nodeCount = 0
		var stopAt = -1
		while cursor.pos > minPos {
			let id = cursor.id
			let start = cursor.start
			let end = cursor.end
			let size = cursor.size
			if size > 4 {
				cursor.next()
			} else if stopAt > -1 && start < stopAt {
				break
			} else {
				if stopAt < 0 { stopAt = end - maxBufferLength }
				nodes.append(id)
				nodes.append(start)
				nodes.append(end)
				nodeCount += 1
				cursor.next()
			}
		}
		if nodeCount > 0 {
			var buffer = [UInt16](repeating: 0, count: nodeCount * 4)
			let start = nodes[nodes.count - 2]
			var j = 0
			var i = nodes.count - 3
			while i >= 0 {
				buffer[j] = UInt16(nodes[i]); j += 1
				buffer[j] = UInt16(nodes[i + 1] - start); j += 1
				buffer[j] = UInt16(nodes[i + 2] - start); j += 1
				buffer[j] = UInt16(j); j += 1
				i -= 3
			}
			children.append(TreeBuffer(buffer: buffer, length: nodes[2] - start, set: data.nodeSet))
			positions.append(start - parentStart)
		}
	}

	func makeBalanced(type: NodeType, contextHash: Int) -> ([Any], [Int], Int) -> Tree {
		return { children, positions, length in
			var lookAheadVal = 0
			let lastI = children.count - 1
			if lastI >= 0, let last = children[lastI] as? Tree {
				if lastI == 0 && last.type === type && last.length == length { return last }
				if let lookAheadProp = last.prop(nodePropLookAhead) {
					lookAheadVal = positions[lastI] + last.length + lookAheadProp
				}
			}
			return makeTreeInternal(
				type: type, children: children, positions: positions,
				length: length, lookAhead: lookAheadVal, contextHash: contextHash
			)
		}
	}

	func makeRepeatLeaf(
		children: inout [Any], positions: inout [Int],
		base: Int, i: Int, from: Int, to: Int,
		type: Int, lookAhead: Int, contextHash: Int
	) {
		var localChildren: [Any] = []
		var localPositions: [Int] = []
		while children.count > i {
			localChildren.append(children.removeLast())
			localPositions.append(positions.removeLast() + base - from)
		}
		children.append(makeTreeInternal(
			type: types[type], children: localChildren, positions: localPositions,
			length: to - from, lookAhead: lookAhead - to, contextHash: contextHash
		))
		positions.append(from - base)
	}

	func makeTreeInternal(
		type: NodeType, children: [Any], positions: [Int],
		length: Int, lookAhead: Int, contextHash: Int,
		props: [(Any, Any)]? = nil
	) -> Tree {
		var props = props
		if contextHash != 0 {
			let pair: (Any, Any) = (nodePropContextHash, contextHash)
			props = props != nil ? [pair] + props! : [pair]
		}
		if lookAhead > 25 {
			let pair: (Any, Any) = (nodePropLookAhead, lookAhead)
			props = props != nil ? [pair] + props! : [pair]
		}
		return Tree(type: type, children: children, positions: positions, length: length, props: props)
	}

	func findBufferSize(_ maxSize: Int, inRepeat: Int) -> (size: Int, start: Int, skip: Int)? {
		var fork = cursor.fork()
		var size = 0
		var start = 0
		var skip = 0
		let minStart = fork.end - maxBufferLength
		var result = (size: 0, start: 0, skip: 0)
		let minPos = fork.pos - maxSize

		while fork.pos > minPos {
			let nodeSize = fork.size
			if fork.id == inRepeat && nodeSize >= 0 {
				result = (size, start, skip)
				skip += 4; size += 4
				fork.next()
				continue
			}
			let startPos = fork.pos - nodeSize
			if nodeSize < 0 || startPos < minPos || fork.start < minStart { break }
			var localSkipped = fork.id >= minRepeatType ? 4 : 0
			let nodeStart = fork.start
			fork.next()
			while fork.pos > startPos {
				if fork.size < 0 {
					if fork.size == SpecialRecord.contextChange || fork.size == SpecialRecord.lookAhead {
						localSkipped += 4
					} else { return result.size > 4 ? result : nil }
				} else if fork.id >= minRepeatType {
					localSkipped += 4
				}
				fork.next()
			}
			start = nodeStart
			size += nodeSize
			skip += localSkipped
		}
		if inRepeat < 0 || size == maxSize {
			result = (size, start, skip)
		}
		return result.size > 4 ? result : nil
	}

	func copyToBuffer(bufferStart: Int, buffer: inout [UInt16], index: Int) -> Int {
		let id = cursor.id
		let start = cursor.start
		let end = cursor.end
		let size = cursor.size
		cursor.next()
		if size >= 0 && id < minRepeatType {
			var idx = index
			if size > 4 {
				let endPos = cursor.pos - (size - 4)
				while cursor.pos > endPos {
					idx = copyToBuffer(bufferStart: bufferStart, buffer: &buffer, index: idx)
				}
			}
			idx -= 1; buffer[idx] = UInt16(index)
			idx -= 1; buffer[idx] = UInt16(end - bufferStart)
			idx -= 1; buffer[idx] = UInt16(start - bufferStart)
			idx -= 1; buffer[idx] = UInt16(id)
			return idx
		} else if size == SpecialRecord.contextChange {
			contextHash = id
		} else if size == SpecialRecord.lookAhead {
			lookAhead = id
		}
		return index
	}

	var children: [Any] = []
	var positions: [Int] = []
	while cursor.pos > 0 {
		takeNode(
			parentStart: data.start ?? 0, minPos: data.bufferStart ?? 0,
			children: &children, positions: &positions, inRepeat: -1, depth: 0
		)
	}
	let length = data.length ?? (children.isEmpty ? 0 : positions[0] + (children[0] is Tree ? (children[0] as! Tree).length : (children[0] as! TreeBuffer).length))
	return Tree(type: types[data.topID], children: children.reversed(), positions: positions.reversed(), length: length)
}

func balanceRange(
	balanceType: NodeType,
	children: [Any], positions: [Int],
	from: Int, to: Int,
	start: Int, length: Int,
	mkTop: (([Any], [Int], Int) -> Tree)?,
	mkTree: @escaping ([Any], [Int], Int) -> Tree
) -> Tree {
	var total = 0
	for i in from ..< to {
		total += nodeSize(balanceType: balanceType, node: children[i])
	}

	let maxChild = Int(ceil(Double(total) * 1.5 / Double(Balance.branchFactor)))
	var localChildren: [Any] = []
	var localPositions: [Int] = []

	func divide(_ children: [Any], _ positions: [Int], _ from: Int, _ to: Int, _ offset: Int) {
		var i = from
		while i < to {
			let groupFrom = i
			let groupStart = positions[i]
			var groupSize = nodeSize(balanceType: balanceType, node: children[i])
			i += 1
			while i < to {
				let nextSize = nodeSize(balanceType: balanceType, node: children[i])
				if groupSize + nextSize >= maxChild { break }
				groupSize += nextSize
				i += 1
			}
			if i == groupFrom + 1 {
				if groupSize > maxChild, let only = children[groupFrom] as? Tree {
					divide(only.children, only.positions, 0, only.children.count, positions[groupFrom] + offset)
					continue
				}
				localChildren.append(children[groupFrom])
			} else {
				let len = positions[i - 1] + lengthOfAny(children[i - 1]) - groupStart
				localChildren.append(balanceRange(
					balanceType: balanceType, children: children, positions: positions,
					from: groupFrom, to: i, start: groupStart, length: len,
					mkTop: nil, mkTree: mkTree
				))
			}
			localPositions.append(groupStart + offset - start)
		}
	}

	divide(children, positions, from, to, 0)
	return (mkTop ?? mkTree)(localChildren, localPositions, length)
}

func nodeSize(balanceType: NodeType, node: Any) -> Int {
	if !balanceType.isAnonymous || node is TreeBuffer {
		return 1
	}
	guard let tree = node as? Tree else { return 1 }
	if tree.type !== balanceType { return 1 }
	var size = 1
	for child in tree.children {
		if let t = child as? Tree {
			if t.type !== balanceType { return 1 }
			size += nodeSize(balanceType: balanceType, node: t)
		} else {
			return 1
		}
	}
	return size
}

func lengthOfAny(_ node: Any) -> Int {
	if let tree = node as? Tree { return tree.length }
	if let buf = node as? TreeBuffer { return buf.length }
	return 0
}
