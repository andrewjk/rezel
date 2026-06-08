public struct NestedParse {
	public let parser: Parser
	public let overlay: Any?
	public let bracketed: Bool

	public init(parser: Parser, overlay: Any? = nil, bracketed: Bool = false) {
		self.parser = parser
		self.overlay = overlay
		self.bracketed = bracketed
	}
}

public func parseMixed(
	nest: @escaping (SyntaxNodeRef, InputProtocol) -> NestedParse?
) -> (AnyPartialParse, InputProtocol, [TreeFragment], [CommonRange]) -> AnyPartialParse {
	return { parse, input, fragments, ranges in
		let mp = MixedParse(base: parse, nest: nest, input: input, fragments: fragments, ranges: ranges)
		return AnyPartialParse(mp)
	}
}

class InnerParse {
	let parser: Parser
	var parse: any PartialParse
	let overlay: [CommonRange]?
	let bracketed: Bool
	let target: Tree
	let from: Int

	init(parser: Parser, parse: any PartialParse, overlay: [CommonRange]?, bracketed: Bool, target: Tree, from: Int) {
		self.parser = parser
		self.parse = parse
		self.overlay = overlay
		self.bracketed = bracketed
		self.target = target
		self.from = from
	}
}

func checkRanges(_ ranges: [CommonRange]) {
	if ranges.isEmpty || ranges.contains(where: { $0.from >= $0.to }) {
		fatalError("Invalid inner parse ranges given: \(ranges)")
	}
}

class ActiveOverlay {
	var depth = 0
	var ranges: [CommonRange] = []
	let parser: Parser
	let predicate: (SyntaxNodeRef) -> Any?
	let mounts: [ReusableMount]
	let index: Int
	let start: Int
	let bracketed: Bool
	let target: Tree
	let prev: ActiveOverlay?

	init(
		parser: Parser,
		predicate: @escaping (SyntaxNodeRef) -> Any?,
		mounts: [ReusableMount],
		index: Int,
		start: Int,
		bracketed: Bool,
		target: Tree,
		prev: ActiveOverlay?
	) {
		self.parser = parser
		self.predicate = predicate
		self.mounts = mounts
		self.index = index
		self.start = start
		self.bracketed = bracketed
		self.target = target
		self.prev = prev
	}
}

enum Cover: Int {
	case none = 0
	case partial = 1
	case full = 2
}

func checkCover(_ covered: [CommonRange], from: Int, to: Int) -> Cover {
	for range in covered {
		if range.from >= to { break }
		if range.to > from {
			return range.from <= from && range.to >= to ? .full : .partial
		}
	}
	return .none
}

nonisolated(unsafe) let stoppedInner = NodeProp<Int>(perNode: true)

class CoverInfo {
	var ranges: [CommonRange]
	var depth: Int
	let prev: CoverInfo?

	init(ranges: [CommonRange], depth: Int, prev: CoverInfo?) {
		self.ranges = ranges
		self.depth = depth
		self.prev = prev
	}
}

class MixedParse: PartialParse {
	var baseParse: AnyPartialParse?
	var inner: [InnerParse] = []
	var innerDone = 0
	var baseTree: Tree?
	var stoppedAt: Int?

	let nest: (SyntaxNodeRef, InputProtocol) -> NestedParse?
	let input: InputProtocol
	let fragments: [TreeFragment]
	let ranges: [CommonRange]

	init(base: AnyPartialParse, nest: @escaping (SyntaxNodeRef, InputProtocol) -> NestedParse?, input: InputProtocol, fragments: [TreeFragment], ranges: [CommonRange]) {
		baseParse = base
		self.nest = nest
		self.input = input
		self.fragments = fragments
		self.ranges = ranges
	}

	var parsedPos: Int {
		if baseParse != nil { return 0 }
		var pos = input.length
		for i in innerDone ..< inner.count {
			if inner[i].from < pos { pos = min(pos, inner[i].parse.parsedPos) }
		}
		return pos
	}

	func stopAt(_ pos: Int) {
		stoppedAt = pos
		if baseParse != nil {
			baseParse?.stopAt(pos)
		} else {
			for i in innerDone ..< inner.count {
				inner[i].parse.stopAt(pos)
			}
		}
	}

	func advance() -> Tree? {
		if baseParse != nil {
			guard let done = baseParse?.advance() else { return nil }
			baseParse = nil
			baseTree = done
			startInner()
			if stoppedAt != nil {
				for ip in inner {
					ip.parse.stopAt(stoppedAt!)
				}
			}
		}
		if innerDone == inner.count {
			var result = baseTree!
			if stoppedAt != nil {
				var pv = result.propValues
				pv.append((stoppedInner, stoppedAt!))
				result = Tree(
					type: result.type, children: result.children,
					positions: result.positions, length: result.length, props: pv
				)
			}
			return result
		}
		let ip = inner[innerDone]
		if let done = ip.parse.advance() {
			innerDone += 1
			var props = ip.target.props ?? [:]
			if ip.target.props != nil {
				props = Dictionary(uniqueKeysWithValues: ip.target.props!.map { ($0.key, $0.value) })
			}
			props[nodePropMounted.id] = MountedTree(tree: done, overlay: ip.overlay, parser: ip.parser, bracketed: ip.bracketed)
			ip.target.props = props
		}
		return nil
	}

	func startInner() {
		let fragmentCursor = FragmentCursor(fragments: fragments)
		var overlay: ActiveOverlay? = nil
		var covered: CoverInfo? = nil

		guard let baseTree = baseTree else { return }
		let cursor = TreeCursor(
			node: TreeNode(tree: baseTree, from: ranges[0].from, index: 0, parent: nil),
			mode: .includeAnonymous.union(.ignoreMounts)
		)

		scan: while true {
			var enter = true
			if stoppedAt != nil && cursor.from >= stoppedAt! {
				enter = false
			} else if fragmentCursor.hasNode(cursor) {
				if let ov = overlay {
					let match = ov.mounts.first(where: { m in
						m.frag.from <= cursor.from && m.frag.to >= cursor.to && m.mount.overlay != nil
					})
					if let match = match {
						for r in match.mount.overlay! {
							let from = r.from + match.pos
							let to = r.to + match.pos
							if from >= cursor.from, to <= cursor.to,
							   !ov.ranges.contains(where: { $0.from < to && $0.to > from })
							{
								ov.ranges.append(CommonRange(from: from, to: to))
							}
						}
					}
				}
				enter = false
			} else if let cov = covered, let isCovered = checkCoverValue(cov.ranges, from: cursor.from, to: cursor.to) {
				enter = isCovered != .full
			} else if !cursor.type.isAnonymous, let nestResult = nest(cursor.ref, input),
			          cursor.from < cursor.to || nestResult.overlay == nil
			{
				if cursor.tree == nil {
					materialize(cursor)
					overlay?.depth += 1
					covered?.depth += 1
				}

				let oldMounts = fragmentCursor.findMounts(cursor.from, parser: nestResult.parser)

				if let overlayFn = nestResult.overlay as? (SyntaxNodeRef) -> Any {
					let predicate: (SyntaxNodeRef) -> Any? = { n in overlayFn(n) as Any? }
					overlay = ActiveOverlay(
						parser: nestResult.parser,
						predicate: predicate,
						mounts: oldMounts,
						index: inner.count,
						start: cursor.from,
						bracketed: nestResult.bracketed,
						target: cursor.tree!,
						prev: overlay
					)
				} else if let overlayFn = nestResult.overlay as? (SyntaxNodeRef) -> Any? {
					overlay = ActiveOverlay(
						parser: nestResult.parser,
						predicate: overlayFn,
						mounts: oldMounts,
						index: inner.count,
						start: cursor.from,
						bracketed: nestResult.bracketed,
						target: cursor.tree!,
						prev: overlay
					)
				} else {
					var nestRanges: [CommonRange]
					if let overlayRanges = nestResult.overlay as? [CommonRange] {
						nestRanges = punchRanges(outer: ranges, ranges: overlayRanges)
					} else {
						let r = cursor.from < cursor.to ? [CommonRange(from: cursor.from, to: cursor.to)] : [CommonRange]()
						nestRanges = punchRanges(outer: ranges, ranges: r)
					}
					if !nestRanges.isEmpty { checkRanges(nestRanges) }

					if !nestRanges.isEmpty || nestResult.overlay == nil {
						let parse: any PartialParse
						if !nestRanges.isEmpty {
							parse = nestResult.parser.startParse(
								input: input,
								fragments: enterFragments(oldMounts, ranges: nestRanges),
								ranges: nestRanges
							)
						} else {
							parse = nestResult.parser.startParse(input: "")
						}
						let innerOverlay: [CommonRange]?
						if let overlayRanges = nestResult.overlay as? [CommonRange] {
							innerOverlay = overlayRanges.map { CommonRange(from: $0.from - cursor.from, to: $0.to - cursor.from) }
						} else {
							innerOverlay = nil
						}
						inner.append(InnerParse(
							parser: nestResult.parser,
							parse: parse,
							overlay: innerOverlay,
							bracketed: nestResult.bracketed,
							target: cursor.tree!,
							from: nestRanges.isEmpty ? cursor.from : nestRanges[0].from
						))
					}
					if nestResult.overlay == nil {
						enter = false
					} else if !nestRanges.isEmpty {
						covered = CoverInfo(ranges: nestRanges, depth: 0, prev: covered)
					}
				}
			} else if let ov = overlay, let range = ov.predicate(cursor) {
				if let rangeVal = range as? CommonRange {
					if rangeVal.from < rangeVal.to {
						if !ov.ranges.isEmpty, ov.ranges[ov.ranges.count - 1].to == rangeVal.from {
							ov.ranges[ov.ranges.count - 1] = CommonRange(from: ov.ranges[ov.ranges.count - 1].from, to: rangeVal.to)
						} else {
							ov.ranges.append(rangeVal)
						}
					}
				} else if let boolVal = range as? Bool, boolVal {
					let rangeVal = CommonRange(from: cursor.from, to: cursor.to)
					if rangeVal.from < rangeVal.to {
						if !ov.ranges.isEmpty, ov.ranges[ov.ranges.count - 1].to == rangeVal.from {
							ov.ranges[ov.ranges.count - 1] = CommonRange(from: ov.ranges[ov.ranges.count - 1].from, to: rangeVal.to)
						} else {
							ov.ranges.append(rangeVal)
						}
					}
				}
			}

			if enter, cursor.firstChild() {
				overlay?.depth += 1
				covered?.depth += 1
			} else {
				while true {
					if cursor.nextSibling() { continue scan }
					if !cursor.parent() { break scan }
					if let ov = overlay {
						ov.depth -= 1
						if ov.depth == 0 {
							let ranges = punchRanges(outer: self.ranges, ranges: ov.ranges)
							if !ranges.isEmpty {
								checkRanges(ranges)
								let ip = InnerParse(
									parser: ov.parser,
									parse: ov.parser.startParse(
										input: input,
										fragments: enterFragments(ov.mounts, ranges: ranges),
										ranges: ranges
									),
									overlay: ov.ranges.map { CommonRange(from: $0.from - ov.start, to: $0.to - ov.start) },
									bracketed: ov.bracketed,
									target: ov.target,
									from: ranges[0].from
								)
								inner.insert(ip, at: ov.index)
							}
							overlay = ov.prev
						}
					}
					if let cov = covered {
						cov.depth -= 1
						if cov.depth <= 0 {
							covered = cov.prev
						}
					}
				}
			}
		}
	}
}

func checkCoverValue(_ covered: [CommonRange], from: Int, to: Int) -> Cover? {
	let result = checkCover(covered, from: from, to: to)
	return result == .none ? nil : result
}

func sliceBuf(_ buf: TreeBuffer, startI: Int, endI: Int, nodes: inout [Any], positions: inout [Int], off: Int) {
	if startI < endI {
		let from = Int(buf.buffer[startI + 1])
		nodes.append(buf.slice(startI: startI, endI: endI, from: from))
		positions.append(from - off)
	}
}

func materialize(_ cursor: TreeCursor) {
	let node = cursor.node
	guard let bufNode = node as? BufferNode else { return }
	var stack: [Int] = []
	let buffer = bufNode.context.buffer

	// Scan up to the nearest tree
	repeat {
		stack.append(cursor.index)
		cursor.parent()
	} while cursor.tree == nil

	// cursor._tree is now the parent TreeNode
	let parentTreeNode = cursor._tree

	// Find the index of the buffer in that tree
	let base = cursor.tree!
	var i = 0
	while i < base.children.count {
		if let buf = base.children[i] as? TreeBuffer, buf === buffer { break }
		i += 1
	}
	let buf = base.children[i] as! TreeBuffer
	let b = buf.buffer
	var newStack: [Int] = [i]

	func split(
		startI: Int,
		endI: Int,
		type: NodeType,
		innerOffset: Int,
		length: Int,
		stackPos: Int
	) -> Tree {
		let targetI = stack[stackPos]
		var children: [Any] = []
		var positions: [Int] = []
		sliceBuf(buf, startI: startI, endI: targetI, nodes: &children, positions: &positions, off: innerOffset)
		let from = Int(b[targetI + 1])
		let to = Int(b[targetI + 2])
		newStack.append(children.count)
		let child: Any
		if stackPos > 0 {
			child = split(
				startI: targetI + 4,
				endI: Int(b[targetI + 3]),
				type: buf.set.types[Int(b[targetI])],
				innerOffset: from,
				length: to - from,
				stackPos: stackPos - 1
			)
		} else {
			child = bufNode.toTree()
		}
		children.append(child)
		positions.append(from - innerOffset)
		sliceBuf(buf, startI: Int(b[targetI + 3]), endI: endI, nodes: &children, positions: &positions, off: innerOffset)
		return Tree(type: type, children: children, positions: positions, length: length)
	}

	let result = split(
		startI: 0,
		endI: b.count,
		type: NodeType.none,
		innerOffset: 0,
		length: buf.length,
		stackPos: stack.count - 1
	)
	base.children[i] = result

	// Move the cursor back to the target node
	var currentTreeNode = parentTreeNode
	for (si, index) in newStack.enumerated() {
		let tree = currentTreeNode._tree.children[index] as! Tree
		let pos = currentTreeNode._tree.positions[index]
		if si == newStack.count - 1 {
			let treeNode = TreeNode(tree: tree, from: pos + currentTreeNode.from, index: index, parent: currentTreeNode)
			_ = cursor.yield(treeNode)
		} else {
			currentTreeNode = TreeNode(tree: tree, from: pos + currentTreeNode.from, index: index, parent: currentTreeNode)
		}
	}
}

func punchRanges(outer: [CommonRange], ranges: [CommonRange]) -> [CommonRange] {
	var current: [CommonRange]? = nil
	var j = 0
	for i in 1 ..< outer.count {
		let gapFrom = outer[i - 1].to
		let gapTo = outer[i].from
		while j < (current ?? ranges).count {
			let r = (current ?? ranges)[j]
			if r.from >= gapTo { break }
			if r.to <= gapFrom { j += 1; continue }
			if current == nil { current = ranges }
			if r.from < gapFrom {
				current![j] = CommonRange(from: r.from, to: gapFrom)
				if r.to > gapTo {
					current!.insert(CommonRange(from: gapTo, to: r.to), at: j + 1)
				}
			} else if r.to > gapTo {
				current![j] = CommonRange(from: gapTo, to: r.to)
				j -= 1
			} else {
				current!.remove(at: j)
				j -= 1
			}
			j += 1
		}
	}
	return current ?? ranges
}

struct ReusableMount {
	let frag: TreeFragment
	let mount: MountedTree
	let pos: Int
}

func findCoverChanges(
	a: [CommonRange], b: [CommonRange], from: Int, to: Int
) -> [CommonRange] {
	var iA = 0, iB = 0
	var inA = false, inB = false
	var pos = -1_000_000_000
	var result: [CommonRange] = []
	while true {
		let nextA = iA == a.count ? Int(1e9) : (inA ? a[iA].to : a[iA].from)
		let nextB = iB == b.count ? Int(1e9) : (inB ? b[iB].to : b[iB].from)
		if inA != inB {
			let start = max(pos, from)
			let end = min(nextA, nextB, to)
			if start < end { result.append(CommonRange(from: start, to: end)) }
		}
		pos = min(nextA, nextB)
		if pos == Int(1e9) { break }
		if nextA == pos {
			if !inA { inA = true }
			else { inA = false; iA += 1 }
		}
		if nextB == pos {
			if !inB { inB = true }
			else { inB = false; iB += 1 }
		}
	}
	return result
}

func enterFragments(_ mounts: [ReusableMount], ranges: [CommonRange]) -> [TreeFragment] {
	var result: [TreeFragment] = []
	for mount in mounts {
		let startPos = mount.pos + (mount.mount.overlay != nil ? mount.mount.overlay![0].from : 0)
		let endPos = startPos + mount.mount.tree.length
		let from = max(mount.frag.from, startPos)
		let to = min(mount.frag.to, endPos)

		if let overlay = mount.mount.overlay {
			let overlayRanges = overlay.map { CommonRange(from: $0.from + mount.pos, to: $0.to + mount.pos) }
			let changes = findCoverChanges(a: ranges, b: overlayRanges, from: from, to: to)
			var pos = from
			for i in 0 ... changes.count {
				let last = i == changes.count
				let end = last ? to : changes[i].from
				if end > pos {
					result.append(TreeFragment(
						from: pos, to: end, tree: mount.mount.tree, offset: -startPos,
						openStart: mount.frag.from >= pos || mount.frag.openStart,
						openEnd: mount.frag.to <= end || mount.frag.openEnd
					))
				}
				if last { break }
				pos = changes[i].to
			}
		} else {
			result.append(TreeFragment(
				from: from, to: to, tree: mount.mount.tree, offset: -startPos,
				openStart: mount.frag.from >= startPos || mount.frag.openStart,
				openEnd: mount.frag.to <= endPos || mount.frag.openEnd
			))
		}
	}
	return result
}

class StructureCursor {
	let cursor: TreeCursor
	var done = false
	let offset: Int

	init(root: Tree, offset: Int) {
		self.offset = offset
		cursor = root.cursor(mode: [.includeAnonymous, .ignoreMounts])
	}

	func moveTo(pos: Int) {
		let p = pos - offset
		while !done, cursor.from < p {
			if cursor.to >= p,
			   cursor.enter(p, side: 1, mode: [.ignoreOverlays, .excludeBuffers])
			{
				// Entered
			} else if cursor.to <= p {
				if !cursor.next(false) { done = true }
			} else {
				break
			}
		}
	}

	func hasNode(_ nodeCursor: TreeCursor) -> Bool {
		moveTo(pos: nodeCursor.from)
		if !done && cursor.from + offset == nodeCursor.from, let tree = cursor.tree {
			var t: Tree? = tree
			while let current = t {
				if current === nodeCursor.tree { return true }
				if !current.children.isEmpty && current.positions[0] == 0,
				   let child = current.children[0] as? Tree
				{
					t = child
				} else {
					break
				}
			}
		}
		return false
	}
}

class FragmentCursor {
	var curFrag: TreeFragment?
	var curTo = 0
	var fragI = 0
	var inner: StructureCursor?
	let fragments: [TreeFragment]

	init(fragments: [TreeFragment]) {
		self.fragments = fragments
		if !fragments.isEmpty {
			let first = fragments[0]
			curFrag = first
			curTo = first.tree.prop(stoppedInner) ?? first.to
			inner = StructureCursor(root: first.tree, offset: -first.offset)
		}
	}

	func hasNode(_ node: TreeCursor) -> Bool {
		while curFrag != nil && node.from >= curTo {
			nextFrag()
		}
		guard let frag = curFrag, let inner = inner else { return false }
		return frag.from <= node.from && curTo >= node.to && inner.hasNode(node)
	}

	func nextFrag() {
		fragI += 1
		if fragI == fragments.count {
			curFrag = nil
			inner = nil
		} else {
			let frag = fragments[fragI]
			curFrag = frag
			curTo = frag.tree.prop(stoppedInner) ?? frag.to
			inner = StructureCursor(root: frag.tree, offset: -frag.offset)
		}
	}

	func findMounts(_ pos: Int, parser: Parser) -> [ReusableMount] {
		var result: [ReusableMount] = []
		if let inner = inner {
			inner.cursor.moveTo(pos: pos, side: 1)
			var posNode: SyntaxNode? = inner.cursor.node
			while let p = posNode {
				if let mount = p.tree.flatMap({ MountedTree.get($0) }), mount.parser === parser {
					for i in fragI ..< fragments.count {
						let frag = fragments[i]
						if frag.from >= p.to { break }
						if frag.tree === curFrag!.tree {
							result.append(ReusableMount(frag: frag, mount: mount, pos: p.from - frag.offset))
						}
					}
				}
				posNode = p.parent
			}
		}
		return result
	}
}
