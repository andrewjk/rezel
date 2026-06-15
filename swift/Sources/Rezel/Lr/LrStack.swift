public let lookaheadMargin = 25

public enum Recover {
	public static let insert = 200
	public static let delete = 190
	public static let reduce = 100
	public static let maxNext = 4
	public static let maxInsertStackDepth = 300
	public static let dampenInsertStackDepth = 120
	public static let minBigReduction = 2000
}

public class StackContext {
	public let hash: Int
	public let tracker: ContextTracker
	public let context: Any

	public init(tracker: ContextTracker, context: Any) {
		self.tracker = tracker
		self.context = context
		hash = tracker.strict ? tracker.hash(context) : 0
	}
}

public class Stack: CustomStringConvertible {
	let p: LrParse
	public var stack: [Int]
	public var state: Int
	public var reducePos: Int
	public var pos: Int
	public var score: Int
	public var buffer: [Int]
	public var bufferBase: Int
	public var curContext: StackContext?
	public var lookAhead: Int
	public var parent: Stack?

	public init(
		p: LrParse,
		stack: [Int],
		state: Int,
		reducePos: Int,
		pos: Int,
		score: Int,
		buffer: [Int],
		bufferBase: Int,
		curContext: StackContext?,
		lookAhead: Int = 0,
		parent: Stack?
	) {
		self.p = p
		self.stack = stack
		self.state = state
		self.reducePos = reducePos
		self.pos = pos
		self.score = score
		self.buffer = buffer
		self.bufferBase = bufferBase
		self.curContext = curContext
		self.lookAhead = lookAhead
		self.parent = parent
	}

	public var description: String {
		let states = stack.enumerated().filter { $0.offset % 3 == 0 }.map { $0.element } + [state]
		let scoreStr = score != 0 ? "!\(score)" : ""
		return "[\(states.map(String.init).joined(separator: ","))]@\(pos)\(scoreStr)"
	}

	public static func start(_ p: LrParse, state: Int, pos: Int = 0) -> Stack {
		let cx = p.parser.context
		return Stack(
			p: p,
			stack: [],
			state: state,
			reducePos: pos,
			pos: pos,
			score: 0,
			buffer: [],
			bufferBase: 0,
			curContext: cx != nil ? StackContext(tracker: cx!, context: cx!.start) : nil,
			lookAhead: 0,
			parent: nil
		)
	}

	public var context: Any? {
		return curContext?.context
	}

	func pushState(_ state: Int, _ start: Int) {
		stack.append(self.state)
		stack.append(start)
		stack.append(bufferBase + buffer.count)
		self.state = state
	}

	public func reduce(_ action: Int) {
		let depth = action >> Action.ReduceDepthShift
		let type = action & Action.ValueMask
		let parser = p.parser

		let lookaheadRecord = reducePos < pos - lookaheadMargin && setLookAhead(pos)

		let dPrec = parser.dynamicPrecedence(type)
		if dPrec != 0 { score += dPrec }

		if depth == 0 {
			if type < parser.minRepeatTerm, reducePos < pos { reducePos = pos }
			pushState(parser.getGoto(state: state, term: type, loose: true), reducePos)
			if type < parser.minRepeatTerm {
				storeNode(term: type, start: reducePos, end: reducePos, size: lookaheadRecord ? 8 : 4, mustSink: true)
			}
			reduceContext(type, start: reducePos)
			return
		}

		let base = stack.count - (depth - 1) * 3 - ((action & Action.StayFlag) != 0 ? 6 : 0)
		let start = base > 0 ? stack[base - 2] : p.ranges[0].from
		if type < parser.minRepeatTerm && start == reducePos && reducePos < pos {
			reducePos = pos
		}
		let size = reducePos - start

		if size >= Recover.minBigReduction {
			let nodeType = type < parser.nodeSet.types.count ? parser.nodeSet.types[type] : nil
			if nodeType == nil || !nodeType!.isAnonymous {
				if start == p.lastBigReductionStart {
					p.bigReductionCount += 1
					p.lastBigReductionSize = size
				} else if p.lastBigReductionSize < size {
					p.bigReductionCount = 1
					p.lastBigReductionStart = start
					p.lastBigReductionSize = size
				}
			}
		}

		let bufferBaseVal = base > 0 ? stack[base - 1] : 0
		let count = bufferBase + buffer.count - bufferBaseVal

		if type < parser.minRepeatTerm || (action & Action.RepeatFlag) != 0 {
			let pos = parser.stateFlag(state, flag: StateFlag.Skipped) ? self.pos : reducePos
			storeNode(term: type, start: start, end: pos, size: count + 4, mustSink: true)
		}
		if (action & Action.StayFlag) != 0 {
			state = stack[base]
		} else {
			let baseStateID = stack[base - 3]
			state = parser.getGoto(state: baseStateID, term: type, loose: true)
		}
		if stack.count > base {
			stack.removeLast(stack.count - base)
		}
		reduceContext(type, start: start)
	}

	public func storeNode(term: Int, start: Int, end: Int, size: Int = 4, mustSink: Bool = false) {
		var size = size
		if term == LrTerm.Err &&
			(stack.isEmpty || stack[stack.count - 1] < buffer.count + bufferBase)
		{
			let top = buffer.count
			if top > 0, buffer[top - 4] == LrTerm.Err, buffer[top - 1] > -1 {
				if start == end { return }
				if buffer[top - 2] >= start {
					buffer[top - 2] = end
					return
				}
			}
		}

		if !mustSink || pos == end {
			buffer.append(term)
			buffer.append(start)
			buffer.append(end)
			buffer.append(size)
		} else {
			var index = buffer.count
			if index > 0, buffer[index - 4] != LrTerm.Err || buffer[index - 1] < 0 {
				var mustMove = false
				var scan = index
				while scan > 0, buffer[scan - 2] > end {
					if buffer[scan - 1] >= 0 {
						mustMove = true
						break
					}
					scan -= 4
				}
				if mustMove {
					while index > 0, buffer[index - 2] > end {
						if index >= buffer.count {
							buffer.append(contentsOf: [0, 0, 0, 0])
						}
						buffer[index] = buffer[index - 4]
						buffer[index + 1] = buffer[index - 3]
						buffer[index + 2] = buffer[index - 2]
						buffer[index + 3] = buffer[index - 1]
						index -= 4
						if size > 4 { size -= 4 }
					}
				}
			}
			while buffer.count < index + 4 {
				buffer.append(0)
			}
			buffer[index] = term
			buffer[index + 1] = start
			buffer[index + 2] = end
			buffer[index + 3] = size
		}
	}

	public func shift(action: Int, type: Int, start: Int, end: Int) {
		if (action & Action.GotoFlag) != 0 {
			pushState(action & Action.ValueMask, pos)
		} else if (action & Action.StayFlag) == 0 {
			let nextState = action
			let parser = p.parser
			pos = end
			let skipped = parser.stateFlag(nextState, flag: StateFlag.Skipped)
			if !skipped, end > start || type <= parser.maxNode { reducePos = end }
			pushState(nextState, skipped ? start : min(start, reducePos))
			shiftContext(type, start: start)
			if type <= parser.maxNode { buffer.append(type); buffer.append(start); buffer.append(end); buffer.append(4) }
		} else {
			pos = end
			shiftContext(type, start: start)
			if type <= p.parser.maxNode { buffer.append(type); buffer.append(start); buffer.append(end); buffer.append(4) }
		}
	}

	public func apply(action: Int, next: Int, nextStart: Int, nextEnd: Int) {
		if (action & Action.ReduceFlag) != 0 { reduce(action) }
		else { shift(action: action, type: next, start: nextStart, end: nextEnd) }
	}

	public func useNode(_ value: Tree, next: Int) {
		var index = p.reused.count - 1
		if index < 0 || p.reused[index] !== value {
			p.reused.append(value)
			index += 1
		}
		let start = pos
		reducePos = start + value.length
		pos = reducePos
		pushState(next, start)
		buffer.append(index)
		buffer.append(start)
		buffer.append(reducePos)
		buffer.append(-1)
		if curContext != nil {
			updateContext(curContext!.tracker.reuse(
				curContext!.context,
				value,
				self,
				p.stream.reset(pos - value.length)
			))
		}
	}

	public func split() -> Stack {
		var parent: Stack? = self
		var off = parent!.buffer.count
		if off > 0 && parent!.buffer[off - 4] == LrTerm.Err { off -= 4 }
		while off > 0 && parent!.buffer[off - 2] > parent!.reducePos {
			off -= 4
		}
		let buf = Array(parent!.buffer[off...])
		let base = parent!.bufferBase + off
		while let p = parent, base == p.bufferBase {
			parent = p.parent
		}
		return Stack(
			p: p,
			stack: Array(stack),
			state: state,
			reducePos: reducePos,
			pos: pos,
			score: score,
			buffer: buf,
			bufferBase: base,
			curContext: curContext,
			lookAhead: lookAhead,
			parent: parent
		)
	}

	public func recoverByDelete(_ next: Int, _ nextEnd: Int) {
		let isNode = next <= p.parser.maxNode
		if isNode { storeNode(term: next, start: pos, end: nextEnd, size: 4) }
		storeNode(term: LrTerm.Err, start: pos, end: nextEnd, size: isNode ? 8 : 4)
		pos = nextEnd
		reducePos = nextEnd
		score -= Recover.delete
	}

	public func canShift(_ term: Int) -> Bool {
		let sim = SimulatedStack(start: self)
		while true {
			let dr = p.parser.stateSlot(sim.state, slot: ParseState.DefaultReduce)
			let action = dr != 0 ? dr : p.parser.hasAction(state: sim.state, terminal: term)
			if action == 0 { return false }
			if (action & Action.ReduceFlag) == 0 { return true }
			sim.reduce(action)
		}
	}

	public func recoverByInsert(_ next: Int) -> [Stack] {
		if stack.count >= Recover.maxInsertStackDepth { return [] }

		var nextStates = p.parser.nextStates(state)
		if nextStates.count > Recover.maxNext << 1 || stack.count >= Recover.dampenInsertStackDepth {
			var best: [Int] = []
			var i = 0
			while i < nextStates.count {
				let s = nextStates[i + 1]
				if s != state, p.parser.hasAction(state: s, terminal: next) != 0 {
					best.append(nextStates[i])
					best.append(s)
				}
				i += 2
			}
			if stack.count < Recover.dampenInsertStackDepth {
				i = 0
				while best.count < Recover.maxNext << 1, i < nextStates.count {
					let s = nextStates[i + 1]
					var found = false
					for j in stride(from: 1, to: best.count, by: 2) {
						if best[j] == s { found = true; break }
					}
					if !found { best.append(nextStates[i]); best.append(s) }
					i += 2
				}
			}
			nextStates = best
		}
		var result: [Stack] = []
		var i = 0
		while i < nextStates.count, result.count < Recover.maxNext {
			let s = nextStates[i + 1]
			if s == state { i += 2; continue }
			let stk = split()
			stk.pushState(s, pos)
			stk.storeNode(term: LrTerm.Err, start: stk.pos, end: stk.pos, size: 4, mustSink: true)
			stk.shiftContext(nextStates[i], start: pos)
			stk.reducePos = pos
			stk.score -= Recover.insert
			result.append(stk)
			i += 2
		}
		return result
	}

	@discardableResult
	public func forceReduce() -> Bool {
		let parser = p.parser
		var reduce = parser.stateSlot(state, slot: ParseState.ForcedReduce)
		if (reduce & Action.ReduceFlag) == 0 { return false }
		if !parser.validAction(state, action: reduce) {
			let depth = reduce >> Action.ReduceDepthShift
			let term = reduce & Action.ValueMask
			let target = stack.count - depth * 3
			if target < 0 || parser.getGoto(state: stack[target], term: term, loose: false) < 0 {
				guard let backup = findForcedReduction() else { return false }
				reduce = backup
			}
			storeNode(term: LrTerm.Err, start: pos, end: pos, size: 4, mustSink: true)
			score -= Recover.reduce
		}
		reducePos = pos
		self.reduce(reduce)
		return true
	}

	public func findForcedReduction() -> Int? {
		let parser = p.parser
		var seen: [Int] = []

		func explore(_ state: Int, depth: Int) -> Int? {
			if seen.contains(state) { return nil }
			seen.append(state)
			return parser.allActions(state) { action in
				if (action & (Action.StayFlag | Action.GotoFlag)) != 0 {
					return nil
				} else if (action & Action.ReduceFlag) != 0 {
					let rDepth = (action >> Action.ReduceDepthShift) - depth
					if rDepth > 1 {
						let term = action & Action.ValueMask
						let target = self.stack.count - rDepth * 3
						if target >= 0, parser.getGoto(state: self.stack[target], term: term, loose: false) >= 0 {
							return (rDepth << Action.ReduceDepthShift) | Action.ReduceFlag | term
						}
					}
					return nil
				} else {
					return explore(action, depth: depth + 1)
				}
			}
		}
		return explore(state, depth: 0)
	}

	@discardableResult
	public func forceAll() -> Stack {
		while !p.parser.stateFlag(state, flag: StateFlag.Accepting) {
			if !forceReduce() {
				storeNode(term: LrTerm.Err, start: pos, end: pos, size: 4, mustSink: true)
				break
			}
		}
		return self
	}

	public var deadEnd: Bool {
		if stack.count != 3 { return false }
		let parser = p.parser
		return parser.data[parser.stateSlot(state, slot: ParseState.Actions)] == Seq.End &&
			parser.stateSlot(state, slot: ParseState.DefaultReduce) == 0
	}

	public func restart() {
		storeNode(term: LrTerm.Err, start: pos, end: pos, size: 4, mustSink: true)
		state = stack[0]
		stack.removeAll()
	}

	public func sameState(_ other: Stack) -> Bool {
		if state != other.state || stack.count != other.stack.count { return false }
		var i = 0
		while i < stack.count {
			if stack[i] != other.stack[i] { return false }
			i += 3
		}
		return true
	}

	public var parser: LRParser {
		p.parser
	}

	public func dialectEnabled(_ dialectID: Int) -> Bool {
		return p.parser.dialect.flags[dialectID]
	}

	private func shiftContext(_ term: Int, start: Int) {
		if curContext != nil {
			updateContext(curContext!.tracker.shift(
				curContext!.context,
				term,
				self,
				p.stream.reset(start)
			))
		}
	}

	private func reduceContext(_ term: Int, start: Int) {
		if curContext != nil {
			updateContext(curContext!.tracker.reduce(
				curContext!.context,
				term,
				self,
				p.stream.reset(start)
			))
		}
	}

	private func emitContext() {
		let last = buffer.count - 1
		if last < 0 || buffer[last] != -3 {
			buffer.append(curContext!.hash)
			buffer.append(pos)
			buffer.append(pos)
			buffer.append(-3)
		}
	}

	public func emitLookAhead() {
		let last = buffer.count - 1
		if last < 0 || buffer[last] != -4 {
			buffer.append(lookAhead)
			buffer.append(pos)
			buffer.append(pos)
			buffer.append(-4)
		}
	}

	private func updateContext(_ context: Any) {
		if !(context as AnyObject === curContext!.context as AnyObject) {
			let newCx = StackContext(tracker: curContext!.tracker, context: context)
			if newCx.hash != curContext!.hash { emitContext() }
			curContext = newCx
		}
	}

	@discardableResult
	public func setLookAhead(_ lookAhead: Int) -> Bool {
		if lookAhead <= self.lookAhead { return false }
		emitLookAhead()
		self.lookAhead = lookAhead
		return true
	}

	public func close() {
		if let cx = curContext, cx.tracker.strict { emitContext() }
		if lookAhead > 0 { emitLookAhead() }
	}
}

class SimulatedStack {
	var state: Int
	var stack: [Int]
	var base: Int
	let start: Stack

	init(start: Stack) {
		self.start = start
		state = start.state
		stack = start.stack
		base = stack.count
	}

	func reduce(_ action: Int) {
		let term = action & Action.ValueMask
		let depth = action >> Action.ReduceDepthShift
		if depth == 0 {
			if stack == start.stack { stack = Array(stack) }
			stack.append(state)
			stack.append(0)
			stack.append(0)
			base += 3
		} else {
			base -= (depth - 1) * 3
		}
		let goto = start.p.parser.getGoto(state: stack[base - 3], term: term, loose: true)
		state = goto
	}
}

public class StackBufferCursor: BufferCursorProtocol {
	public var buffer: [Int]
	public var stack: Stack
	public var pos: Int
	public var index: Int

	public init(stack: Stack, pos: Int, index: Int) {
		self.stack = stack
		self.pos = pos
		self.index = index
		buffer = stack.buffer
		if self.index == 0 { maybeNext() }
	}

	public static func create(_ stack: Stack, pos: Int? = nil) -> StackBufferCursor {
		let p = pos ?? stack.bufferBase + stack.buffer.count
		return StackBufferCursor(stack: stack, pos: p, index: p - stack.bufferBase)
	}

	func maybeNext() {
		if let next = stack.parent {
			index = stack.bufferBase - next.bufferBase
			stack = next
			buffer = next.buffer
		}
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

	public func next() {
		index -= 4
		pos -= 4
		if index == 0 { maybeNext() }
	}

	public func fork() -> BufferCursorProtocol {
		return StackBufferCursor(stack: stack, pos: pos, index: index)
	}
}
