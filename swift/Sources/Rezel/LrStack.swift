//
//  Stack.swift
//  Rezel
//
//  Created on 2025-06-12.
//

import Foundation

/// Every token is assumed to have looked this far ahead, so that
/// small lookahead values don't have to be separately stored.
/// Lookaheads further than this are attached to the tree with props.
public struct Lookahead {
    public static let margin = 25
}

/// A parse stack. These are used internally by the parser to track
/// parsing progress. They also provide some properties and methods
/// that external code such as a tokenizer can use to get information
/// about the parse state.
public final class Stack {
    /// The parse that this stack is part of @internal
    let p: Parse
    
    /// Holds state, input pos, buffer index triplets for all but the
    /// top state @internal
    var stack: [Int] = []
    
    /// The current parse state
    public var state: Int = 0
    
    // The position at which the next reduce should take place. This
    // can be less than `this.pos` when skipped expressions have been
    // added to the stack (which should be moved outside of the next
    // reduction)
    /// @internal
    public var reducePos: Int = 0
    
    /// The input position up to which this stack has parsed.
    public var pos: Int = 0
    
    /// The dynamic score of the stack, including dynamic precedence
    /// and error-recovery penalties
    /// @internal
    public var score: Int = 0
    
    // The output buffer. Holds (type, start, end, size) quads
    // representing nodes created by the parser, where `size` is
    // amount of buffer array entries covered by this node.
    /// @internal
    public var buffer: [Int] = []
    
    // The base offset of the buffer. When stacks are split, the split
    // instance shared the buffer history with its parent up to
    // `bufferBase`, which is the absolute offset (including the
    // offset of previous splits) into the buffer at which this stack
    // starts writing.
    /// @internal
    public var bufferBase: Int = 0
    
    /// @internal
    var curContext: StackContext?
    
    /// @internal
    public var lookAhead: Int = 0
    
    // A parent stack from which this was split off, if any. This is
    // set up so that it always points to a stack that has some
    // additional buffer content, never to a stack with an equal
    // `bufferBase`.
    /// @internal
    weak var parent: Stack?
    
    /// @internal
    init(
        p: Parse,
        stack: [Int],
        state: Int,
        reducePos: Int,
        pos: Int,
        score: Int,
        buffer: [Int],
        bufferBase: Int,
        curContext: StackContext?,
        lookAhead: Int = 0,
        parent: Stack? = nil
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
    
    /// @internal
    func toString() -> String {
        let states = stack.enumerated().compactMap { (index, i) in i % 3 == 0 ? String(i) : nil }
        return "[\(states.joined(separator: ""))]\(pos)\(score != 0 ? "!\(score)" : "")"
    }
    
    // Start an empty stack
    /// @internal
    static func start(_ p: Parse, _ state: Int, _ pos: Int = 0) -> Stack {
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
            curContext: cx != nil ? StackContext(tracker: cx!, context: cx.start) : nil,
            lookAhead: 0,
            parent: nil
        )
    }
    
    /// The stack's current [context](#lr.ContextTracker) value, if
    /// any. Its type will depend on the context tracker's type
    /// parameter, or it will be `null` if there is no context
    /// tracker.
    var context: Any? {
        return curContext?.context
    }
    
    // Push a state onto the stack, tracking its start position as well
    // as the buffer base at that point.
    /// @internal
    func pushState(_ state: Int, _ start: Int) {
        stack.append(self.state)
        stack.append(start)
        stack.append(bufferBase + buffer.count)
        self.state = state
    }
    
    // Apply a reduce action
    /// @internal
    func reduce(_ action: Int) {
        let depth = action >> Action.reduceDepthShift
        let type = action & Action.valueMask
        let parser = p.parser
        
        let lookaheadRecord = reducePos < pos - Lookahead.margin && setLookAhead(pos)
        
        let dPrec = parser.dynamicPrecedence(term: type)
        if dPrec != 0 {
            score += dPrec
        }
        
        if depth == 0 {
            if type < parser.minRepeatTerm && reducePos < pos {
                reducePos = pos
            }
            pushState(parser.getGoto(state: state, term: type, loose: true), reducePos)
            // Zero-depth reductions are a special case—they add stuff to
            // the stack without popping anything off.
            if type < parser.minRepeatTerm {
                storeNode(term: type, start: reducePos, end: reducePos, size: lookaheadRecord ? 8 : 4, mustSink: true)
            }
            reduceContext(term: reducePos)
            return
        }
        
        // Find the base index into `this.stack`, content after which will
        // be dropped. Note that with `StayFlag` reductions we need to
        // consume two extra frames (the dummy parent node for the skipped
        // expression and the state that we'll be staying in, which should
        // be moved to `this.state`).
        let base = stack.count - (depth - 1) * 3 - (action & Action.stayFlag != 0 ? 6 : 0)
        let start = base > 0 ? stack[base - 2] : p.ranges[0].from
        if type < parser.minRepeatTerm && start == reducePos && reducePos < pos {
            reducePos = pos
        }
        let size = reducePos - start
        
        // This is a kludge to try and detect overly deep left-associative
        // trees, which will not increase the parse stack depth and thus
        // won't be caught by the regular stack-depth limit check.
        if size >= Recover.minBigReduction && !parser.nodeSet.types[type]?.isAnonymous ?? false {
            if start == p.lastBigReductionStart {
                p.bigReductionCount += 1
                p.lastBigReductionSize = size
            } else if p.lastBigReductionSize < size {
                p.bigReductionCount = 1
                p.lastBigReductionStart = start
                p.lastBigReductionSize = size
            }
        }
        
        let bufferBaseValue = base > 0 ? stack[base - 1] : 0
        let count = bufferBaseValue + buffer.count - bufferBaseValue
        
        // Store normal terms or `R -> R R` repeat reductions
        if type < parser.minRepeatTerm || (action & Action.repeatFlag) != 0 {
            let pos = parser.stateFlag(state: StateFlag.skipped) ? pos : reducePos
            storeNode(term: type, start: start, end: pos, count + 4, mustSink: true)
        }
        
        if (action & Action.stayFlag) != 0 {
            state = stack[base]
        } else {
            let baseStateID = stack[base - 3]
            state = parser.getGoto(state: baseStateID, term: type, loose: true)
        }
        
        while stack.count > base {
            stack.removeLast()
        }
        
        reduceContext(term: type, start: start)
    }
    
    // Shift a value into the buffer
    /// @internal
    func storeNode(term: Int, _ start: Int, _ end: Int, size: Int = 4, mustSink: Bool = false) {
        if term == Term.err &&
           (stack.isEmpty || stack[stack.count - 1] < bufferBase + buffer.count) {
            // Try to omit/merge adjacent error nodes
            let top = buffer.count
            if top > 0 && buffer[top - 4] == Term.err && buffer[top - 1] > -1 {
                if start == end {
                    return
                }
                if buffer[top - 2] >= start {
                    buffer[top - 2] = end
                    return
                }
            }
        }
        
        if !mustSink || pos == end {
            // Simple case, just append
            buffer.append(term)
            buffer.append(start)
            buffer.append(end)
            buffer.append(size)
        } else {
            // There may be skipped nodes that have to be moved forward
            var index = buffer.count
            if index > 0 && (buffer[index - 4] != Term.err || buffer[index - 1] < 0) {
                var mustMove = false
                for scan in stride(from: index, to: 0, by: -4) {
                    if buffer[scan - 2] > end {
                        if buffer[scan - 1] >= 0 {
                            mustMove = true
                            break
                        }
                    }
                }
                if mustMove {
                    while index > 0 && buffer[index - 2] > end {
                        // Move this record forward
                        buffer[index] = buffer[index - 4]
                        buffer[index + 1] = buffer[index - 3]
                        buffer[index + 2] = buffer[index - 2]
                        buffer[index + 3] = buffer[index - 1]
                        index -= 4
                        if size > 4 {
                            size -= 4
                        }
                    }
                }
            }
            
            buffer[index] = term
            buffer[index + 1] = start
            buffer[index + 2] = end
            buffer[index + 3] = size
        }
    }
    
    // Apply a shift action
    /// @internal
    func shift(_ action: Int, type: Int, start: Int, end: Int) {
        if (action & Action.gotoFlag) != 0 {
            pushState(action & Action.valueMask, pos)
        } else if (action & Action.stayFlag) == 0 {
            // Regular shift
            let nextState = action
            let parser = p.parser
            
            pos = end
            let skipped = parser.stateFlag(nextState: nextState, flag: StateFlag.skipped)
            // Skipped or zero-length non-tree tokens don't move reducePos
            if !skipped && (end > start || type <= parser.maxNode) {
                reducePos = end
            }
            pushState(nextState, skipped ? start : min(start, reducePos))
            shiftContext(term: type, start: start)
            if type <= parser.maxNode {
                buffer.append(type)
                buffer.append(start)
                buffer.append(end)
                buffer.append(4)
            }
        } else {
            // Shift-and-stay, which means this is a skipped token
            pos = end
            shiftContext(term: type, start)
            if type <= parser.maxNode {
                buffer.append(type)
                buffer.append(start)
                buffer.append(end)
                buffer.append(4)
            }
        }
    }
    
    // Apply an action
    /// @internal
    func apply(_ action: Int, _ next: Int, nextStart: Int, nextEnd: Int) {
        if (action & Action.reduceFlag) != 0 {
            reduce(action)
        } else {
            shift(action: action, next: nextStart, nextStart: nextEnd)
        }
    }
    
    // Add a prebuilt (reused) node into the buffer.
    /// @internal
    func useNode(_ value: Tree, next: Int) {
        let index = p.reused.count - 1
        if index < 0 || p.reused[index] !== value {
            p.reused.append(value)
        }
        let start = pos
        reducePos = pos
        pos = start + value.length
        pushState(next: next, start: start)
        buffer.append(index)
        buffer.append(start)
        buffer.append(reducePos)
        buffer.append(-1) /* size == -1 means this is a reused value */
        
        if let curContext = curContext {
            updateContext(curContext.tracker.reuse(
                curContext.context,
                value: value,
                self,
                p.stream.reset(pos - value.length)
            ))
        }
    }
    
    // Split the stack. Due to the buffer sharing and the fact
    // that `this.stack` tends to stay quite shallow, this isn't very
    // expensive.
    /// @internal
    func split() -> Stack {
        var parent: Stack? = self
        var off = parent!.buffer.count
        // Leave off top error node, if there, because that might be
        // merged with other nodes.
        if off > 0 && parent!.buffer[off - 4] == Term.err {
            off -= 4
        }

        // Because the top of the buffer (after this.pos) may be mutated
        // to reorder reductions and skipped tokens, and shared buffers
        // should be immutable, this copies any outstanding skipped tokens
        // to the new buffer, and puts the base pointer before them.
        while off > 0 && parent!.buffer[off - 2] > parent!.reducePos {
            off -= 4
        }

        let buffer = Array(parent!.buffer[off...])
        let base = parent!.bufferBase + off

        // Make sure parent points to an actual parent with content, if there is such a parent.
        while let p = parent, base == p.bufferBase {
            parent = p.parent
        }

        return Stack(
            p: p,
            stack: stack,
            state: state,
            reducePos: reducePos,
            pos: pos,
            score: score,
            buffer: buffer,
            bufferBase: base,
            curContext: curContext,
            lookAhead: lookAhead,
            parent: parent
        )
    }
    
    // Try to recover from an error by 'deleting' (ignoring) one token.
    /// @internal
    func recoverByDelete(_ next: Int, nextEnd: Int) {
        let isNode = next <= p.parser.maxNode
        if isNode {
            storeNode(term: next, pos, pos, size: 4)
        }
        storeNode(term: Term.err, pos, pos, size: isNode ? 8 : 4)
        pos = nextEnd
        reducePos = nextEnd
        score -= Recover.delete
    }
    
    /// Check if the given term would be able to be shifted (optionally
    /// after some reductions) on this stack. This can be useful for
    /// external tokenizers that want to make sure they only provide a
    /// given token when it applies.
    func canShift(_ term: Int) -> Bool {
        var sim = SimulatedStack(start: self)
        while true {
            let action = p.parser.stateSlot(state: sim.state, slot: ParseState.defaultReduce) ??
                        p.parser.hasAction(state: sim.state, term: term)
            
            if action == 0 {
                return false
            }
            
            if (action & Action.reduceFlag) == 0 {
                return true
            }

            sim.reduce(_ action)
        }
    }
    
    // Apply up to Recover.MaxNext recovery actions that conceptually
    // inserts some missing token or rule.
    /// @internal
    func recoverByInsert(_ next: Int) -> [Stack] {
        if stack.count >= Recover.maxInsertStackDepth {
            return []
        }
        
        let nextStates = p.parser.nextStates(state: state)
        
        var best: [(Int, Int)] = []
        
        if nextStates.count > Recover.maxNext << 1 ||
           stack.count >= Recover.dampenInsertStackDepth {
            
            for i in stride(from: 0, to: nextStates.count - 1, by: 2) {
                let s = nextStates[i + 1]
                if s != state && p.parser.hasAction(state: state, term: next) {
                    best.append((nextStates[i], s))
                }
            }
            
            if stack.count < Recover.dampenInsertStackDepth {
                for i in stride(from: 0, to: nextStates.count - 1, by: 2) {
                    let s = nextStates[i + 1]
                    if !best.contains(where: { $0.1 == s }) {
                        best.append((nextStates[i], s))
                    }
                }
            }
            
            nextStates = best.map { ($0, $1) }
        }
        
        var result: [Stack] = []
        
        for i in stride(from: 0, to: nextStates.count - 1, by: 2) {
            let s = nextStates[i + 1]
            if s == state {
                continue
            }

            let stack = split()
            stack.pushState(s, pos)
            stack.storeNode(term: Term.err, pos, pos, 4, mustSink: true)
            stack.shiftContext(term: nextStates[i], pos: pos)
            stack.reducePos = pos
            stack.score -= Recover.insert
            result.append(stack)

            if result.count >= Recover.maxNext {
                break
            }
        }
        
        return result
    }
    
    // Force a reduce, if possible. Return false if that can't
    // be done.
    /// @internal
    func forceReduce() -> Bool {
        let parser = p.parser
        let reduce = parser.stateSlot(state: state, slot: ParseState.forcedReduce)
        
        if (reduce & Action.reduceFlag) == 0 {
            return false
        }
        
        if !parser.validAction(state: state, action: reduce) {
            let depth = reduce >> Action.reduceDepthShift
            let term = reduce & Action.valueMask
            let target = stack.count - depth * 3

            if target < 0 || parser.getGoto(state: stack[target], term: term, loose: false) < 0 {
                guard let backup = findForcedReduction() else {
                    return false
                }
                reduce = backup
            }

            storeNode(term: Term.err, pos, pos, 4, mustSink: true)
            score -= Recover.reduce
        }

        reducePos = pos
        reduce(_ reduce)
        return true
    }
    
    /// Try to scan through the automaton to find some kind of reduction
    /// that can be applied. Used when the regular ForcedReduce field
    /// isn't a valid action. @internal
    func findForcedReduction() -> Int? {
        let parser = p.parser
        var seen: [Int] = []
        
        func explore(state: Int, depth: Int) -> Int? {
            if seen.contains(state) {
                return nil
            }
            seen.append(state)
            
            return parser.allActions(state: state) { action in
                if (action & (Action.stayFlag | Action.gotoFlag)) != 0 {
                    return nil
                } else if (action & Action.reduceFlag) != 0 {
                    let rDepth = (action >> Action.reduceDepthShift) - depth
                    if rDepth > 1 {
                        let term = action & Action.valueMask
                        let target = stack.count - rDepth * 3
                        if target >= 0 && parser.getGoto(state: stack[target], term: term, loose: false) >= 0 {
                            return (rDepth << Action.reduceDepthShift) | Action.reduceFlag | term
                        }
                    }
                } else {
                    if let found = explore(state: action, depth: depth + 1) {
                        return found
                    }
                }
                return nil
            }
        }
        
        return explore(state: state, depth: 0)
    }
    
    /// @internal
    func forceAll() -> Stack {
        while !p.parser.stateFlag(state: state, flag: StateFlag.accepting) {
            if !forceReduce() {
                storeNode(term: Term.err, pos, pos, 4, mustSink: true)
                break
            }
        }
        return self
    }
    
    /// Check whether this state has no further actions (assumed to be a direct descendant of the
    /// top state, since any other states must be able to continue
    /// somehow). @internal
    var deadEnd: Bool {
        if stack.count != 3 {
            return false
        }
        let parser = p.parser
        return parser.data[parser.stateSlot(state: state, slot: ParseState.actions)] == Seq.end &&
               parser.stateSlot(state: state, slot: ParseState.defaultReduce) == 0
    }
    
    /// Restart the stack (put it back in its start state). Only safe
    /// when this.stack.length == 3 (state is directly below the top
    /// state). @internal
    func restart() {
        storeNode(term: Term.err, pos, pos, 4, mustSink: true)
        state = stack[0]
        stack.removeAll()
    }
    
    /// @internal
    func sameState(_ other: Stack) -> Bool {
        if state != other.state || stack.count != other.stack.count {
            return false
        }
        for i in 0..<stack.count {
            if stack[i] != other.stack[i] {
                return false
            }
        }
        return true
    }
    
    /// Get the parser used by this stack.
    var parser: LRParser {
        return p.parser
    }
    
    /// Test whether a given dialect (by numeric ID, as exported from
    /// the terms file) is enabled.
    func dialectEnabled(_ dialectID: Int) -> Bool {
        return p.parser.dialect.flags[dialectID]
    }
    
    private func shiftContext(_ term: Int, _ start: Int) {
        if let curContext = curContext {
            updateContext(curContext.tracker.shift(
                curContext.context,
                term,
                self,
                p.stream.reset(start)
            ))
        }
    }
    
    private func reduceContext(_ term: Int, _ start: Int) {
        if let curContext = curContext {
            updateContext(curContext.tracker.reduce(
                curContext.context,
                term,
                self,
                p.stream.reset(start)
            ))
        }
    }
    
    /// @internal
    func emitContext() {
        let last = buffer.count - 1
        if last < 0 || buffer[last] != -3 {
            buffer.append(curContext!.hash)
            buffer.append(pos)
            buffer.append(pos)
            buffer.append(-3)
        }
    }
    
    /// @internal
    func emitLookAhead() {
        let last = buffer.count - 1
        if last < 0 || buffer[last] != -4 {
            buffer.append(lookAhead)
            buffer.append(pos)
            buffer.append(pos)
            buffer.append(-4)
        }
    }
    
    private func updateContext(_ context: Any) {
        if !((curContext!.context as AnyObject) === (context as AnyObject)) {
            let newCx = StackContext(tracker: curContext!.tracker, context: context)
            if newCx.hash != curContext!.hash {
                emitContext()
            }
            curContext = newCx
        }
    }
    
    /// @internal
    func setLookAhead(_ lookAhead: Int) -> Bool {
        if lookAhead <= self.lookAhead {
            return false
        }
        emitLookAhead()
        self.lookAhead = lookAhead
        return true
    }
    
    /// @internal
    func close() {
        if let curContext = curContext, curContext.tracker.strict {
            emitContext()
        }
        if lookAhead > 0 {
            emitLookAhead()
        }
    }
}

class StackContext {
    let hash: Int
    let tracker: any ContextTrackerProtocol
    let context: Any
    
    init(tracker: any ContextTrackerProtocol, context: Any) {
        self.tracker = tracker
        self.context = context
        self.hash = tracker.strict ? tracker.hash(context) : 0
    }
}

public struct Recover {
    public static let insert = 200
    public static let `delete` = 190
    public static let reduce = 100
    public static let maxNext = 4
    public static let maxInsertStackDepth = 300
    public static let dampenInsertStackDepth = 120
    public static let minBigReduction = 2000
}

// Used to cheaply run some reductions to scan ahead without mutating
// an entire stack
class SimulatedStack {
    var state: Int
    var stack: [Int]
    var base: Int
    let start: Stack
    
    init(start: Stack) {
        self.start = start
        self.state = start.state
        self.stack = start.stack
        self.base = start.stack.count
    }
    
    func reduce(_ action: Int) {
        let term = action & Action.valueMask
        let depth = action >> Action.reduceDepthShift
        
        if depth == 0 {
            if stack == start.stack {
                stack = stack + []
            }
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

// This is given to `Tree.build` to build a buffer, and encapsulates
// the parent-stack-walking necessary to read the nodes.
public class StackBufferCursor: BufferCursor {
    public var buffer: [Int]
    var stack: Stack
    public var pos: Int
    var index: Int

    init(stack: Stack, pos: Int, index: Int) {
        self.stack = stack
        self.pos = pos
        self.index = index
        self.buffer = stack.buffer
        if index == 0 {
            maybeNext()
        }

    static func create(_ stack: Stack, _ pos: Int? = nil) -> StackBufferCursor {
        let pos = pos ?? stack.bufferBase + stack.buffer.count
        return StackBufferCursor(stack: stack, pos: pos - stack.bufferBase, index: 0)
    }

    private func maybeNext() {
        guard let next = stack.parent else {
            return
        }
        index = stack.bufferBase - next.bufferBase
        self.stack = next
        buffer = next.buffer
    }

    public var id: Int {
        return buffer[index - 4]
    }

    public var start: Int {
        return buffer[index - 3]
    }

    public var end: Int {
        return buffer[index - 2]
    }

    public var size: Int {
        return buffer[index - 1]
    }

    public func next() {
        index -= 4
        pos -= 4
        if index == 0 {
            maybeNext()
        }
    }

    public func fork() -> any BufferCursor {
        return StackBufferCursor(stack: stack, pos: pos, index: index)
    }
}

protocol ContextTrackerProtocol {
    var start: Any { get }
    func shift(_ context: Any, _ term: Int, _ stack: Stack, _ input: InputStream) -> Any
    func reduce(_ context: Any, _ term: Int, _ stack: Stack, _ input: InputStream) -> Any
    func reuse(_ context: Any, _ node: Tree, _ stack: Stack, _ input: InputStream) -> Any
    func hash(_ context: Any) -> Int
    var strict: Bool { get }
}