import Foundation

public let lrDefaultBufferLength = 1024

enum LrRec {
	static let distance = 5
	static let maxRemainingPerStep = 3
	static let minBufferLengthPrune = 500
	static let forceReduceLimit = 10
	static let cutDepth = 2800 * 3
	static let cutTo = 2000 * 3
	static let maxLeftAssociativeReductionCount = 300
	static let maxStackCount = 12
}

func lrPair(_ data: [UInt16], _ off: Int) -> Int {
	return Int(data[off]) | (Int(data[off + 1]) << 16)
}

class LrFragmentCursor {
	var i: Int = 0
	var fragment: TreeFragment?
	var safeFrom: Int = -1
	var safeTo: Int = -1
	var trees: [Tree] = []
	var startArr: [Int] = []
	var indexArr: [Int] = []
	var nextStart: Int = 0

	let fragments: [TreeFragment]
	let nodeSet: NodeSet

	init(fragments: [TreeFragment], nodeSet: NodeSet) {
		self.fragments = fragments
		self.nodeSet = nodeSet
		nextFragment()
	}

	func nextFragment() {
		if i == fragments.count {
			fragment = nil
			nextStart = 1_000_000_000
			return
		}
		let fr = fragments[i]
		i += 1
		fragment = fr
		safeFrom = fr.openStart ? lrCutAt(fr.tree, pos: fr.from + fr.offset, side: 1) - fr.offset : fr.from
		safeTo = fr.openEnd ? lrCutAt(fr.tree, pos: fr.to + fr.offset, side: -1) - fr.offset : fr.to
		trees.removeAll()
		startArr.removeAll()
		indexArr.removeAll()
		trees.append(fr.tree)
		startArr.append(-fr.offset)
		indexArr.append(0)
		nextStart = safeFrom
	}

	func nodeAt(_ pos: Int) -> Tree? {
		if pos < nextStart { return nil }
		while fragment != nil, safeTo <= pos {
			nextFragment()
		}
		if fragment == nil { return nil }

		while true {
			let last = trees.count - 1
			if last < 0 {
				nextFragment()
				return nil
			}
			let top = trees[last]
			let idx = indexArr[last]
			if idx == top.children.count {
				trees.removeLast()
				startArr.removeLast()
				indexArr.removeLast()
				continue
			}
			let next = top.children[idx]
			let s = startArr[last] + top.positions[idx]
			if s > pos {
				nextStart = s
				return nil
			}
			if let nextTree = next as? Tree {
				if s == pos {
					if s < safeFrom { return nil }
					let end = s + nextTree.length
					if end <= safeTo {
						let lookAhead = nextTree.prop(nodePropLookAhead)
						if lookAhead == nil || end + lookAhead! < fragment!.to { return nextTree }
					}
				}
				indexArr[last] += 1
				if s + nextTree.length >= max(safeFrom, pos) {
					trees.append(nextTree)
					startArr.append(s)
					indexArr.append(0)
				}
			} else {
				indexArr[last] += 1
				let bufferNode = next as! TreeBuffer
				nextStart = s + bufferNode.length
			}
		}
	}
}

func lrCutAt(_ tree: Tree, pos: Int, side: Int) -> Int {
	let cursor = tree.cursor(mode: IterMode.includeAnonymous)
	cursor.moveTo(pos: pos)
	while true {
		let moved = side < 0 ? cursor.childBefore(pos) : cursor.childAfter(pos)
		if !moved {
			while true {
				if (side < 0 ? cursor.to < pos : cursor.from > pos) && !cursor.type.isError {
					if side < 0 {
						return max(0, min(cursor.to - 1, pos - lookaheadMargin))
					} else {
						return min(tree.length, max(cursor.from + 1, pos + lookaheadMargin))
					}
				}
				let siblingMoved = side < 0 ? cursor.prevSibling() : cursor.nextSibling()
				if siblingMoved { break }
				if !cursor.parent() { return side < 0 ? 0 : tree.length }
			}
		}
	}
}

class TokenCache {
	var tokens: [CachedToken] = []
	var mainToken: CachedToken?
	var actions: [Int] = []
	let stream: InputStream

	init(parser: LRParser, stream: InputStream) {
		self.stream = stream
		tokens = parser.tokenizers.map { _ in CachedToken() }
	}

	func getActions(_ stack: Stack) -> [Int] {
		var actionIndex = 0
		var main: CachedToken? = nil
		let parser = stack.p.parser
		let tokenizers = parser.tokenizers

		let mask = parser.stateSlot(stack.state, slot: ParseState.TokenizerMask)
		let context = stack.curContext?.hash ?? 0
		var lookAhead = 0

		for i in 0 ..< tokenizers.count {
			if ((1 << i) & mask) == 0 { continue }
			let tokenizer = tokenizers[i]
			let token = tokens[i]
			if main != nil && !tokenizer.fallback { continue }
			if tokenizer.contextual ||
				token.start != stack.pos ||
				token.mask != mask ||
				token.context != context
			{
				updateCachedToken(token, tokenizer: tokenizer, stack: stack)
				token.mask = mask
				token.context = context
			}
			if token.lookAhead > token.end + lookaheadMargin {
				lookAhead = max(token.lookAhead, lookAhead)
			}

			if token.value != LrTerm.Err {
				let startIndex = actionIndex
				if token.extended > -1 {
					actionIndex = addActions(stack, token: token.extended, end: token.end, index: actionIndex)
				}
				actionIndex = addActions(stack, token: token.value, end: token.end, index: actionIndex)
				if !tokenizer.extend {
					main = token
					if actionIndex > startIndex { break }
				}
			}
		}

		while actions.count > actionIndex {
			actions.removeLast()
		}
		if lookAhead > 0 { stack.setLookAhead(lookAhead) }
		if main == nil, stack.pos == stream.end {
			main = CachedToken()
			main!.value = stack.p.parser.eofTerm
			main!.start = stack.pos
			main!.end = stack.pos
			actionIndex = addActions(stack, token: main!.value, end: main!.end, index: actionIndex)
		}
		mainToken = main
		return actions
	}

	func getMainToken(_ stack: Stack) -> CachedToken {
		if let mt = mainToken { return mt }
		let main = CachedToken()
		main.start = stack.pos
		main.end = min(stack.pos + 1, stack.p.stream.end)
		main.value = stack.pos == stack.p.stream.end ? stack.p.parser.eofTerm : LrTerm.Err
		return main
	}

	func updateCachedToken(_ token: CachedToken, tokenizer: TokenizerProtocol, stack: Stack) {
		let start = stream.clipPos(stack.pos)
		tokenizer.token(stream.reset(start, token: token), stack: stack)
		if token.value > -1 {
			let parser = stack.p.parser
			for i in 0 ..< parser.specialized.count {
				if parser.specialized[i] == token.value {
					let result = parser.specializers[i](stream.read(from: token.start, to: token.end), stack)
					if result >= 0, stack.p.parser.dialect.allows(term: result >> 1) {
						if (result & 1) == Specialize.Specialize {
							token.value = result >> 1
						} else {
							token.extended = result >> 1
						}
						break
					}
				}
			}
		} else {
			token.value = LrTerm.Err
			token.end = stream.clipPos(start + 1)
		}
	}

	func putAction(_ action: Int, token: Int, end: Int, index: Int) -> Int {
		var i = 0
		while i < index {
			if actions[i] == action { return index }
			i += 3
		}
		var idx = index
		if actions.count <= idx { actions.append(action) } else { actions[idx] = action }
		idx += 1
		if actions.count <= idx { actions.append(token) } else { actions[idx] = token }
		idx += 1
		if actions.count <= idx { actions.append(end) } else { actions[idx] = end }
		idx += 1
		return idx
	}

	func addActions(_ stack: Stack, token: Int, end: Int, index: Int) -> Int {
		let state = stack.state
		let parser = stack.p.parser
		let data = parser.data
		var index = index
		for set in 0 ..< 2 {
			var i = parser.stateSlot(state, slot: set == 0 ? ParseState.Actions : ParseState.Skip)
			while true {
				if Int(data[i]) == Seq.End {
					if Int(data[i + 1]) == Seq.Next {
						i = lrPair(data, i + 2)
					} else {
						if index == 0 && Int(data[i + 1]) == Seq.Other {
							index = putAction(lrPair(data, i + 2), token: token, end: end, index: index)
						}
						break
					}
				}
				if Int(data[i]) == token {
					index = putAction(lrPair(data, i + 1), token: token, end: end, index: index)
				}
				i += 3
			}
		}
		return index
	}
}

public class LrParse: PartialParse {
	public var stacks: [Stack]
	public var recovering: Int = 0
	var fragments: LrFragmentCursor?
	var nextStackID: Int = 0x2654
	public var minStackPos: Int = 0
	public var reused: [Tree] = []
	public var stream: InputStream
	var tokens: TokenCache
	var topTerm: Int
	public var stoppedAt: Int?

	public var lastBigReductionStart: Int = -1
	public var lastBigReductionSize: Int = 0
	public var bigReductionCount: Int = 0

	public let parser: LRParser
	public let input: InputProtocol
	public let ranges: [CommonRange]

	public init(
		parser: LRParser,
		input: InputProtocol,
		fragments: [TreeFragment],
		ranges: [CommonRange]
	) {
		self.parser = parser
		self.input = input
		self.ranges = ranges
		stream = InputStream(input: input, ranges: ranges)
		tokens = TokenCache(parser: parser, stream: stream)
		topTerm = parser.top.1
		let from = ranges[0].from
		self.fragments = !fragments.isEmpty && stream.end - from > parser.bufferLength * 4
			? LrFragmentCursor(fragments: fragments, nodeSet: parser.nodeSet)
			: nil
		stacks = []
		stacks = [Stack.start(self, state: parser.top.0, pos: from)]
	}

	public var parsedPos: Int {
		minStackPos
	}

	public func advance() -> Tree? {
		var stacks = self.stacks
		let pos = minStackPos
		var newStacks: [Stack] = []
		self.stacks = newStacks
		var stopped: [Stack]? = nil
		var stoppedTokens: [Int]? = nil

		if bigReductionCount > LrRec.maxLeftAssociativeReductionCount, stacks.count == 1 {
			let s = stacks[0]
			while s.forceReduce(), s.stack.count > 0, s.stack[s.stack.count - 2] >= lastBigReductionStart {}
			bigReductionCount = 0
			lastBigReductionSize = 0
		}

		var i = 0
		while i < stacks.count {
			var stack = stacks[i]
			while true {
				tokens.mainToken = nil
				if stack.pos > pos {
					newStacks.append(stack)
				} else if advanceStack(&stack, stacks: &newStacks, split: &stacks) {
					continue
				} else {
					if stopped == nil {
						stopped = []
						stoppedTokens = []
					}
					stopped!.append(stack)
					let tok = tokens.getMainToken(stack)
					stoppedTokens!.append(tok.value)
					stoppedTokens!.append(tok.end)
				}
				break
			}
			i += 1
		}

		if newStacks.isEmpty {
			if let stopped = stopped, let finished = lrFindFinished(stopped) {
				return stackToTree(finished)
			}
			if parser.strict {
				fatalError("No parse at \(pos)")
			}
			if recovering == 0 { recovering = LrRec.distance }
		}

		if recovering > 0, let stopped = stopped, let stoppedTokens = stoppedTokens {
			let finished: Stack?
			if let stoppedAt = stoppedAt, stopped[0].pos > stoppedAt {
				finished = stopped[0]
			} else {
				finished = runRecovery(stopped, tokens: stoppedTokens, newStacks: &newStacks)
			}
			if let finished = finished {
				return stackToTree(finished.forceAll())
			}
		}

		if recovering > 0 {
			let maxRemaining = recovering == 1 ? 1 : recovering * LrRec.maxRemainingPerStep
			if newStacks.count > maxRemaining {
				newStacks.sort { $0.score > $1.score }
				while newStacks.count > maxRemaining {
					newStacks.removeLast()
				}
			}
			if newStacks.contains(where: { $0.reducePos > pos }) { recovering -= 1 }
		} else if newStacks.count > 1 {
			var i = 0
			outer: while i < newStacks.count - 1 {
				let stack = newStacks[i]
				var j = i + 1
				while j < newStacks.count {
					let other = newStacks[j]
					if stack.sameState(other) ||
						(stack.buffer.count > LrRec.minBufferLengthPrune &&
							other.buffer.count > LrRec.minBufferLengthPrune)
					{
						if (stack.score - other.score) > 0 || (stack.score == other.score && stack.buffer.count - other.buffer.count > 0) {
							newStacks.remove(at: j)
							j -= 1
						} else {
							newStacks.remove(at: i)
							continue outer
						}
					}
					j += 1
				}
				i += 1
			}
			if newStacks.count > LrRec.maxStackCount {
				newStacks.sort { $0.score > $1.score }
				newStacks.removeLast(newStacks.count - LrRec.maxStackCount)
			}
		}

		self.stacks = newStacks
		minStackPos = newStacks[0].pos
		for i in 1 ..< newStacks.count {
			if newStacks[i].pos < minStackPos { minStackPos = newStacks[i].pos }
		}
		return nil
	}

	public func stopAt(_ pos: Int) {
		if let stoppedAt = stoppedAt, stoppedAt < pos {
			fatalError("Can't move stoppedAt forward")
		}
		stoppedAt = pos
	}

	private func advanceStack(_ stack: inout Stack, stacks: inout [Stack], split: inout [Stack]) -> Bool {
		let start = stack.pos
		let parser = self.parser

		if let stoppedAt = stoppedAt, start > stoppedAt {
			return stack.forceReduce() ? true : false
		}

		if let fragments = fragments {
			let strictCx = stack.curContext != nil && stack.curContext!.tracker.strict
			let cxHash = strictCx ? stack.curContext!.hash : 0
			var cached = fragments.nodeAt(start)
			while cached != nil {
				let match = parser.nodeSet.types[cached!.type.id] === cached!.type
					? parser.getGoto(state: stack.state, term: cached!.type.id)
					: -1
				if match > -1 && cached!.length > 0 &&
					(!strictCx || (cached!.prop(nodePropContextHash) ?? 0) == cxHash)
				{
					stack.useNode(cached!, next: match)
					return true
				}
				if !(cached! is Tree) || (cached! as! Tree).children.isEmpty || (cached! as! Tree).positions[0] > 0 {
					break
				}
				let inner = (cached! as! Tree).children[0]
				if let innerTree = inner as? Tree, (cached! as! Tree).positions[0] == 0 {
					cached = innerTree
				} else {
					break
				}
			}
		}

		let defaultReduce = parser.stateSlot(stack.state, slot: ParseState.DefaultReduce)
		if defaultReduce > 0 {
			stack.reduce(defaultReduce)
			return true
		}

		if stack.stack.count >= LrRec.cutDepth {
			while stack.stack.count > LrRec.cutTo && stack.forceReduce() {}
		}

		let actions = tokens.getActions(stack)
		var i = 0
		while i < actions.count {
			let action = actions[i]; i += 1
			let term = actions[i]; i += 1
			let end = actions[i]; i += 1
			let isLast = i >= actions.count
			let localStack = isLast ? stack : stack.split()
			let main = tokens.mainToken
			localStack.apply(action: action, next: term, nextStart: main?.start ?? localStack.pos, nextEnd: end)
			if isLast {
				stack = localStack
				return true
			} else if localStack.pos > start {
				stacks.append(localStack)
			} else {
				split.append(localStack)
			}
		}
		return false
	}

	private func advanceFully(_ stack: inout Stack, newStacks: inout [Stack]) -> Bool {
		let pos = stack.pos
		while true {
			var splitStacks: [Stack] = []
			if !advanceStack(&stack, stacks: &newStacks, split: &splitStacks) { return false }
			newStacks.append(contentsOf: splitStacks)
			if stack.pos > pos {
				lrPushStackDedup(stack, newStacks: &newStacks)
				return true
			}
		}
	}

	private func runRecovery(_ stacks: [Stack], tokens: [Int], newStacks: inout [Stack]) -> Stack? {
		var finished: Stack? = nil
		var restarted = false
		for i in 0 ..< stacks.count {
			var stack = stacks[i]
			let token = tokens[i << 1]
			var tokenEnd = tokens[(i << 1) + 1]

			if stack.deadEnd {
				if restarted { continue }
				restarted = true
				stack.restart()
				var s = stack
				if advanceFully(&s, newStacks: &newStacks) { continue }
				stack = s
			}

			var force = stack.split()
			for _ in 0 ..< LrRec.forceReduceLimit {
				if !force.forceReduce() { break }
				var f = force
				if advanceFully(&f, newStacks: &newStacks) { break }
				force = f
			}

			for insert in stack.recoverByInsert(token) {
				var ins = insert
				_ = advanceFully(&ins, newStacks: &newStacks)
			}

			if stream.end > stack.pos {
				if tokenEnd == stack.pos {
					tokenEnd += 1
				}
				stack.recoverByDelete(token, tokenEnd)
				lrPushStackDedup(stack, newStacks: &newStacks)
			} else if finished == nil || finished!.score < force.score {
				finished = force
			}
		}
		return finished
	}

	public func stackToTree(_ stack: Stack) -> Tree {
		stack.close()
		return Tree.build(data: BuildData(
			buffer: StackBufferCursor.create(stack),
			nodeSet: parser.nodeSet,
			topID: topTerm,
			start: ranges[0].from,
			length: stack.pos - ranges[0].from,
			maxBufferLength: parser.bufferLength,
			reused: reused,
			minRepeatType: parser.minRepeatTerm
		))
	}
}

func lrPushStackDedup(_ stack: Stack, newStacks: inout [Stack]) {
	for i in 0 ..< newStacks.count {
		let other = newStacks[i]
		if other.pos == stack.pos, other.sameState(stack) {
			if newStacks[i].score < stack.score { newStacks[i] = stack }
			return
		}
	}
	newStacks.append(stack)
}

func lrFindFinished(_ stacks: [Stack]) -> Stack? {
	var best: Stack? = nil
	for stack in stacks {
		let stopped = stack.p.stoppedAt
		if stack.pos == stack.p.stream.end || (stopped != nil && stack.pos > stopped!),
		   stack.p.parser.stateFlag(stack.state, flag: StateFlag.Accepting),
		   best == nil || best!.score < stack.score
		{
			best = stack
		}
	}
	return best
}

public class LrDialect {
	public let source: String?
	public let flags: [Bool]
	public let disabled: [UInt8]?

	public init(source: String?, flags: [Bool], disabled: [UInt8]?) {
		self.source = source
		self.flags = flags
		self.disabled = disabled
	}

	public func allows(term: Int) -> Bool {
		guard let disabled = disabled else { return true }
		return term < disabled.count && disabled[term] == 0
	}
}

public class ContextTracker {
	public let start: Any
	public let shift: (Any, Int, Stack, InputStream) -> Any
	public let reduce: (Any, Int, Stack, InputStream) -> Any
	public let reuse: (Any, Tree, Stack, InputStream) -> Any
	public let hash: (Any) -> Int
	public let strict: Bool

	public init(
		start: Any,
		shift: ((Any, Int, Stack, InputStream) -> Any)? = nil,
		reduce: ((Any, Int, Stack, InputStream) -> Any)? = nil,
		reuse: ((Any, Tree, Stack, InputStream) -> Any)? = nil,
		hash: ((Any) -> Int)? = nil,
		strict: Bool = true
	) {
		self.start = start
		self.shift = shift ?? { ctx, _, _, _ in ctx }
		self.reduce = reduce ?? { ctx, _, _, _ in ctx }
		self.reuse = reuse ?? { ctx, _, _, _ in ctx }
		self.hash = hash ?? { _ in 0 }
		self.strict = strict
	}
}

public class LRParser: Parser {
	public let states: [UInt32]
	public let data: [UInt16]
	public let goto: [UInt16]
	public let maxTerm: Int
	public let minRepeatTerm: Int
	public var tokenizers: [TokenizerProtocol]
	public let topRules: [String: [Int]]
	public var context: ContextTracker?
	public let dialects: [String: Int]
	public let dynamicPrecedences: [Int: Int]?
	public var specialized: [UInt16]
	public var specializers: [(String, Stack) -> Int]
	public var specializerSpecs: [SpecializerSpec]
	public let tokenPrecTable: Int
	public let termNames: [Int: String]?
	public let maxNode: Int
	public var dialect: LrDialect
	public var wrappers: [ParseWrapper] = []
	public var top: (Int, Int)
	public var bufferLength: Int
	public var strict: Bool
	public var nodeSet: NodeSet

	private init(copying other: LRParser) {
		states = other.states
		data = other.data
		goto = other.goto
		maxTerm = other.maxTerm
		minRepeatTerm = other.minRepeatTerm
		tokenizers = other.tokenizers
		topRules = other.topRules
		context = other.context
		dialects = other.dialects
		dynamicPrecedences = other.dynamicPrecedences
		specialized = other.specialized
		specializers = other.specializers
		specializerSpecs = other.specializerSpecs
		tokenPrecTable = other.tokenPrecTable
		termNames = other.termNames
		maxNode = other.maxNode
		dialect = other.dialect
		wrappers = other.wrappers
		top = other.top
		bufferLength = other.bufferLength
		strict = other.strict
		nodeSet = other.nodeSet
		super.init()
	}

	public struct SpecializerSpec {
		public let term: Int
		public let get: ((String, Stack) -> Int)?
		public let external: ((String, Stack) -> Int)?
		public let extend: Bool
	}

	public struct ParserSpec {
		public let version: Int
		public let states: Any
		public let stateData: Any
		public let goto: Any
		public let nodeNames: String
		public let maxTerm: Int
		public let repeatNodeCount: Int
		public let nodeProps: [[Any]]?
		public let propSources: [NodePropSource]?
		public let skippedNodes: [Int]?
		public let tokenData: Any
		public let tokenizers: [Any]
		public let topRules: [String: [Int]]
		public var context: ContextTracker?
		public let dialects: [String: Int]?
		public let dynamicPrecedences: [Int: Int]?
		public let specialized: [SpecializerSpec]?
		public let tokenPrec: Int
		public let termNames: [Int: String]?
	}

	public init(spec: ParserSpec) {
		if spec.version != LrFile.Version {
			fatalError("Parser version (\(spec.version)) doesn't match runtime version (\(LrFile.Version))")
		}
		var nodeNames = spec.nodeNames.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
		minRepeatTerm = nodeNames.count
		for _ in 0 ..< spec.repeatNodeCount {
			nodeNames.append("")
		}

		let topTerms = spec.topRules.values.map { $0[1] }
		var nodeProps: [[(NodePropBase, Any)]] = Array(repeating: [], count: nodeNames.count)

		func setProp(_ nodeID: Int, _ prop: NodePropBase, _ value: Any) {
			nodeProps[nodeID].append((prop, value))
		}

		if let specNodeProps = spec.nodeProps {
			for propSpec in specNodeProps {
				guard propSpec.count > 1 else { continue }
				var propBase: NodePropBase? = nil
				if let prop = propSpec[0] as? NodePropBase {
					propBase = prop
				} else if let name = propSpec[0] as? String {
					fatalError("String-based node prop lookup not supported: \(name)")
				}
				guard let prop = propBase else { continue }
				var i = 1
				while i < propSpec.count {
					let next = propSpec[i] as! Int
					i += 1
					if next >= 0 {
						let value = propSpec[i] as! String
						i += 1
						setProp(next, prop, value)
					} else {
						let value = propSpec[i + (-next - 1)] as! String
						for _ in 0 ..< -next {
							let nodeID = propSpec[i] as! Int
							i += 1
							setProp(nodeID, prop, value)
						}
						i += 1
					}
				}
			}
		}

		let propArr = nodeProps.map { np -> [Any] in
			np.map { pair in pair }
		}

		let minRepeat = minRepeatTerm
		nodeSet = NodeSet(types: nodeNames.enumerated().map { index, name in
			NodeType.define(spec: NodeType.DefineSpec(
				id: index,
				name: index >= minRepeat ? nil : name,
				props: propArr[index].isEmpty ? nil : propArr[index] as? [Any],
				top: topTerms.contains(index),
				error: index == 0,
				skipped: spec.skippedNodes?.contains(index) ?? false
			))
		})

		if let propSources = spec.propSources {
			nodeSet = propSources.reduce(nodeSet) { $0.extend($1) }
		}

		strict = false
		bufferLength = lrDefaultBufferLength

		let tokenArray = decodeArray(spec.tokenData)
		context = spec.context
		specializerSpecs = spec.specialized ?? []
		specialized = [UInt16](repeating: 0, count: specializerSpecs.count)
		for i in 0 ..< specializerSpecs.count {
			specialized[i] = UInt16(specializerSpecs[i].term)
		}
		specializers = specializerSpecs.map { lrGetSpecializer($0) }

		states = decodeArray32(spec.states)
		data = decodeArray(spec.stateData)
		goto = decodeArray(spec.goto)
		maxTerm = spec.maxTerm
		tokenizers = spec.tokenizers.map { value in
			if let intVal = value as? Int {
				return TokenGroup(data: tokenArray, id: intVal)
			}
			return value as! TokenizerProtocol
		}
		topRules = spec.topRules
		dialects = spec.dialects ?? [:]
		dynamicPrecedences = spec.dynamicPrecedences ?? nil
		tokenPrecTable = spec.tokenPrec
		termNames = spec.termNames ?? nil
		maxNode = nodeSet.types.count - 1

		dialect = LrDialect(source: nil, flags: [], disabled: nil)
		top = (0, 0)
		super.init()
		dialect = parseDialect()
		let first = topRules.min(by: { $0.value[1] < $1.value[1] })!
		top = (first.value[0], first.value[1])
	}

	override public func createParse(input: InputProtocol, fragments: [TreeFragment], ranges: [CommonRange]) -> any PartialParse {
		var parse: any PartialParse = LrParse(parser: self, input: input, fragments: fragments, ranges: ranges)
		for w in wrappers {
			var ap = AnyPartialParse(parse)
			parse = w(&ap, input, fragments, ranges)
		}
		return parse
	}

	public func getGoto(state: Int, term: Int, loose: Bool = false) -> Int {
		let table = goto
		if term >= Int(table[0]) { return -1 }
		var pos = Int(table[term + 1])
		while true {
			let groupTag = Int(table[pos])
			pos += 1
			let last = groupTag & 1
			let target = Int(table[pos])
			pos += 1
			if last != 0 && loose { return target }
			let end = pos + (groupTag >> 1)
			while pos < end {
				if Int(table[pos]) == state { return target }
				pos += 1
			}
			if last != 0 { return -1 }
		}
	}

	public func hasAction(state: Int, terminal: Int) -> Int {
		for set in 0 ..< 2 {
			var i = stateSlot(state, slot: set == 0 ? ParseState.Actions : ParseState.Skip)
			while true {
				let next = Int(data[i])
				if next == Seq.End {
					if Int(data[i + 1]) == Seq.Next {
						i = lrPair(data, i + 2)
						continue
					} else if Int(data[i + 1]) == Seq.Other {
						return lrPair(data, i + 2)
					} else {
						break
					}
				}
				if next == terminal || next == LrTerm.Err {
					return lrPair(data, i + 1)
				}
				i += 3
			}
		}
		return 0
	}

	public func stateSlot(_ state: Int, slot: Int) -> Int {
		return Int(states[state * ParseState.Size + slot])
	}

	public func stateFlag(_ state: Int, flag: Int) -> Bool {
		return (stateSlot(state, slot: ParseState.Flags) & flag) > 0
	}

	public func validAction(_ state: Int, action: Int) -> Bool {
		return allActions(state) { a in a == action ? true : nil } ?? false
	}

	public func allActions<T>(_ state: Int, action: (Int) -> T?) -> T? {
		let deflt = stateSlot(state, slot: ParseState.DefaultReduce)
		if deflt > 0 {
			if let result = action(deflt) { return result }
		}
		var i = stateSlot(state, slot: ParseState.Actions)
		while true {
			if Int(data[i]) == Seq.End {
				if Int(data[i + 1]) == Seq.Next {
					i = lrPair(data, i + 2)
				} else {
					break
				}
			} else {
				if let result = action(lrPair(data, i + 1)) { return result }
				i += 3
			}
		}
		return nil
	}

	public func nextStates(_ state: Int) -> [Int] {
		var result: [Int] = []
		var i = stateSlot(state, slot: ParseState.Actions)
		while true {
			if Int(data[i]) == Seq.End {
				if Int(data[i + 1]) == Seq.Next {
					i = lrPair(data, i + 2)
				} else {
					break
				}
			} else {
				let actionVal = Int(data[i + 2])
				if (actionVal & (Action.ReduceFlag >> 16)) == 0 {
					let value = Int(data[i + 1])
					var found = false
					for j in stride(from: 1, to: result.count, by: 2) {
						if result[j] == value { found = true; break }
					}
					if !found {
						result.append(Int(data[i]))
						result.append(value)
					}
				}
				i += 3
			}
		}
		return result
	}

	public func configure(
		props: [NodePropSource]? = nil,
		top: String? = nil,
		dialect: String? = nil,
		tokenizers: [(from: TokenizerProtocol, to: TokenizerProtocol)]? = nil,
		specializers: [(from: (String, Stack) -> Int, to: (String, Stack) -> Int)]? = nil,
		contextTracker: ContextTracker? = nil,
		strict: Bool? = nil,
		wrap: ParseWrapper? = nil,
		bufferLength: Int? = nil
	) -> LRParser {
		let copy = LRParser(copying: self)

		if let props = props {
			copy.nodeSet = props.reduce(nodeSet) { $0.extend($1) }
		}
		if let top = top {
			guard let info = topRules[top] else {
				fatalError("Invalid top rule name \(top)")
			}
			copy.top = (info[0], info[1])
		}
		if let tokenizers = tokenizers {
			copy.tokenizers = self.tokenizers.map { t in
				if let found = tokenizers.first(where: { ($0.from as AnyObject) === (t as AnyObject) }) {
					return found.to
				}
				return t
			}
		}
		if let specializers = specializers {
			copy.specializers = self.specializers
			copy.specializerSpecs = specializerSpecs.enumerated().map { i, s in
				if let found = specializers.first(where: { $0.from as AnyObject === s.external as AnyObject }) {
					let spec = SpecializerSpec(term: s.term, get: s.get, external: found.to, extend: s.extend)
					copy.specializers[i] = lrGetSpecializer(spec)
					return spec
				}
				return s
			}
		}
		if let contextTracker = contextTracker {
			copy.context = contextTracker
		}
		if let dialect = dialect {
			copy.dialect = parseDialect(dialect)
		}
		if let strict = strict {
			copy.strict = strict
		}
		if let wrap = wrap {
			copy.wrappers = copy.wrappers + [wrap]
		}
		if let bufferLength = bufferLength {
			copy.bufferLength = bufferLength
		}
		return copy
	}

	public func hasWrappers() -> Bool {
		return !wrappers.isEmpty
	}

	public func getName(_ term: Int) -> String {
		if let termNames = termNames, term < termNames.count {
			return termNames[term] ?? String(term)
		}
		if term <= maxNode {
			return nodeSet.types[term].name.isEmpty ? String(term) : nodeSet.types[term].name
		}
		return String(term)
	}

	public var eofTerm: Int {
		maxNode + 1
	}

	public var topNode: NodeType {
		nodeSet.types[top.1]
	}

	public func dynamicPrecedence(_ term: Int) -> Int {
		guard let prec = dynamicPrecedences else { return 0 }
		return prec[term] ?? 0
	}

	public func parseDialect(_ dialect: String? = nil) -> LrDialect {
		let values = Array(dialects.keys)
		var flags = Array(repeating: false, count: values.count)
		if let dialect = dialect {
			for part in dialect.split(separator: " ") {
				if let id = values.firstIndex(of: String(part)) {
					flags[id] = true
				}
			}
		}
		var disabled: [UInt8]? = nil
		for i in 0 ..< values.count {
			if !flags[i] {
				var j = dialects[values[i]]!
				while j < data.count && Int(data[j]) != Seq.End {
					if disabled == nil {
						disabled = [UInt8](repeating: 0, count: maxTerm + 1)
					}
					if Int(data[j]) < disabled!.count {
						disabled![Int(data[j])] = 1
					}
					j += 1
				}
			}
		}
		return LrDialect(source: dialect, flags: flags, disabled: disabled)
	}

	public static func deserialize(spec: ParserSpec) -> LRParser {
		return LRParser(spec: spec)
	}
}

func lrGetSpecializer(_ spec: LRParser.SpecializerSpec) -> (String, Stack) -> Int {
	if let external = spec.external {
		let mask = spec.extend ? Specialize.Extend : Specialize.Specialize
		return { value, stack in
			(external(value, stack) << 1) | mask
		}
	}
	return spec.get!
}
