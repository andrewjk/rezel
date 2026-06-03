//
//  Parse.swift
//  Rezel
//
//  Created on 2025-06-11.
//

import Foundation

// Verbose logging flag — matches the TS equivalent: /\bparse\b/.test(process.env.LOG!)
fileprivate let parseLog = verbose.contains("parse")

// Map from stack identity to displayed ID string
nonisolated(unsafe) fileprivate var stackIDs: [ObjectIdentifier: String] = [:]

// Recovery configuration constants
fileprivate struct Rec {
    static let distance = 5
    static let maxRemainingPerStep = 3
    static let minBufferLengthPrune = 500
    static let forceReduceLimit = 10
    static let cutDepth = 2800 * 3
    static let cutTo = 2000 * 3
    static let maxLeftAssociativeReductionCount = 300
    static let maxStackCount = 12
}

// Helper function to find a position in a tree to cut at
fileprivate func cutAt(tree: Tree, pos: Int, side: SideInt) -> Int {
    let cursor = tree.cursor(mode: IterMode.includeAnonymous)
    _ = cursor.moveTo(pos: pos)
    
    while true {
        if !(side < 0 ? cursor.childBefore(pos: pos) : cursor.childAfter(pos: pos)) {
            while true {
                if ((side < 0 ? cursor.to < pos : cursor.from > pos) && !cursor.type.isError) {
                    return side < 0
                        ? max(0, min(cursor.to - 1, pos - Lookahead.margin))
                        : min(tree.length, max(cursor.from + 1, pos + Lookahead.margin))
                }
                if side < 0 ? cursor.prevSibling() : cursor.nextSibling() {
                    break
                }
                if !cursor.parent() {
                    return side < 0 ? 0 : tree.length
                }
            }
        }
    }
}

/// Cursor for navigating through tree fragments
class LrFragmentCursor {
    var i = 0
    var fragment: TreeFragment?
    var safeFrom = -1
    var safeTo = -1
    var trees: [Tree] = []
    var startPositions: [Int] = []
    var index: [Int] = []
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
        
        safeFrom = fr.openStart ? cutAt(tree: fr.tree, pos: fr.from + fr.offset, side: 1) - fr.offset : fr.from
        safeTo = fr.openEnd ? cutAt(tree: fr.tree, pos: fr.to + fr.offset, side: -1) - fr.offset : fr.to
        
        while !trees.isEmpty {
            trees.removeLast()
            startPositions.removeLast()
            index.removeLast()
        }
        
        trees.append(fr.tree)
        startPositions.append(-fr.offset)
        index.append(0)
        nextStart = safeFrom
    }
    
    /// Get a node at the given position
    func nodeAt(pos: Int) -> Tree? {
        if pos < nextStart {
            return nil
        }
        
        while let _ = fragment, safeTo <= pos {
            nextFragment()
        }
        
        guard let fragment = fragment else {
            return nil
        }
        
        while true {
            let last = trees.count - 1
            if last < 0 {
                nextFragment()
                return nil
            }
            
            let top = trees[last]
            let idx = index[last]
            
            if idx == top.children.count {
                trees.removeLast()
                startPositions.removeLast()
                index.removeLast()
                continue
            }
            
            let next = top.children[idx]
            let startPos = startPositions[last] + top.positions[idx]
            
            if startPos > pos {
                nextStart = startPos
                return nil
            }
            
            if case .tree(let nextTree) = next {
                if startPos == pos {
                    if startPos < safeFrom {
                        return nil
                    }
                    let end = startPos + nextTree.length
                    if end <= safeTo {
                        let lookAhead = nextTree.prop(prop: nodePropLookAhead)
                        if lookAhead == nil || end + lookAhead! < fragment.to {
                            return nextTree
                        }
                    }
                }
                index[last] += 1
                if startPos + next.length >= max(safeFrom, pos) {
                    trees.append(nextTree)
                    startPositions.append(startPos)
                    index.append(0)
                }
            } else {
                index[last] += 1
                nextStart = startPos + next.length
            }
        }
    }
}

/// Cache for tokens during parsing
class TokenCache {
    var tokens: [CachedToken] = []
    var mainToken: CachedToken?
    var actions: [Int] = []
    
    let stream: InputStream
    
    init(parser: LRParser, stream: InputStream) {
        self.stream = stream
        self.tokens = parser.tokenizers.map { _ in CachedToken() }
    }
    
    func getActions(stack: Stack) -> [Int] {
        var actionIndex = 0
        var main: CachedToken? = nil
        let parser = stack.p.parser
        let tokenizers = parser.tokenizers
        
        let mask = parser.stateSlot(state: stack.state, slot: ParseState.tokenizerMask)
        let context = stack.curContext?.hash ?? 0
        var lookAhead = 0
        
        for i in 0..<tokenizers.count {
            if ((1 << i) & mask) == 0 {
                continue
            }
            
            let tokenizer = tokenizers[i]
            let token = tokens[i]
            
            if let _ = main, !tokenizer.fallback {
                continue
            }
            
            if tokenizer.contextual ||
                token.start != stack.pos ||
                token.mask != mask ||
                token.context != context {
                updateCachedToken(token: token, tokenizer: tokenizer, stack: stack)
                token.mask = mask
                token.context = context
            }
            
            if token.lookAhead > token.end + Lookahead.margin {
                lookAhead = max(token.lookAhead, lookAhead)
            }
            
            if token.value != LrTerm.err {
                let startIndex = actionIndex
                if token.extended > -1 {
                    actionIndex = addActions(stack: stack, token: token.extended, end: token.end, index: actionIndex)
                }
                actionIndex = addActions(stack: stack, token: token.value, end: token.end, index: actionIndex)
                if !tokenizer.extend {
                    main = token
                    if actionIndex > startIndex {
                        break
                    }
                }
            }
        }
        
        while actions.count > actionIndex {
            actions.removeLast()
        }
        
        if lookAhead > 0 {
            _ = stack.setLookAhead(lookAhead)
        }
        
        if main == nil && stack.pos == stream.end {
            main = CachedToken()
            main!.value = stack.p.parser.eofTerm
            main!.start = stack.pos
            main!.end = stack.pos
            actionIndex = addActions(stack: stack, token: main!.value, end: main!.end, index: actionIndex)
        }
        
        self.mainToken = main
        return actions
    }
    
    func getMainToken(stack: Stack) -> CachedToken {
        if let main = mainToken {
            return main
        }
        
        let main = CachedToken()
        main.start = stack.pos
        main.end = min(stack.pos + 1, stack.p.stream.end)
        main.value = stack.pos == stack.p.stream.end ? stack.p.parser.eofTerm : LrTerm.err
        return main
    }
    
    func updateCachedToken(token: CachedToken, tokenizer: any Tokenizer, stack: Stack) {
        let start = stream.clipPos(stack.pos)
        tokenizer.token(stream.reset(start, token: token), stack)
        
        if token.value > -1 {
            let parser = stack.p.parser
            
            for i in 0..<parser.specialized.count {
                if parser.specialized[i] == token.value {
                    let result = parser.specializers[i](stream.read(token.start, token.end), stack)
                    if result >= 0 && stack.p.parser.dialect.allows(term: result >> 1) {
                        if (result & 1) == Specialize.specialize {
                            token.value = result >> 1
                        } else {
                            token.extended = result >> 1
                        }
                        break
                    }
                }
            }
        } else {
            token.value = LrTerm.err
            token.end = stream.clipPos(start + 1)
        }
    }
    
    func putAction(action: Int, token: Int, end: Int, index: Int) -> Int {
        // Don't add duplicate actions
        for i in stride(from: 0, to: index, by: 3) {
            if actions[i] == action {
                return index
            }
        }
        
        var newIndex = index
        if newIndex < actions.count {
            actions[newIndex] = action
        } else {
            actions.append(action)
        }
        newIndex += 1
        if newIndex < actions.count {
            actions[newIndex] = token
        } else {
            actions.append(token)
        }
        newIndex += 1
        if newIndex < actions.count {
            actions[newIndex] = end
        } else {
            actions.append(end)
        }
        newIndex += 1
        return newIndex
    }
    
    func addActions(stack: Stack, token: Int, end: Int, index: Int) -> Int {
        let state = stack.state
        let parser = stack.p.parser
        let data = parser.data
        var idx = index
        
        for set in 0..<2 {
            var i = parser.stateSlot(state: state, slot: set == 1 ? ParseState.skip : ParseState.actions)
            
            while true {
                if data[i] == Seq.end {
                    if data[i + 1] == Seq.next {
                        i = pair(data: data, off: i + 2)
                    } else {
                        if idx == 0 && data[i + 1] == Seq.other {
                            idx = putAction(action: pair(data: data, off: i + 2), token: token, end: end, index: idx)
                        }
                        break
                    }
                }
                
                if data[i] == token {
                    idx = putAction(action: pair(data: data, off: i + 1), token: token, end: end, index: idx)
                }
                
                i += 3
            }
        }
        
        return idx
    }
}

/// Helper function to combine two 16-bit values into a 32-bit value
fileprivate func pair(data: [UInt16], off: Int) -> Int {
    return Int(data[off]) | (Int(data[off + 1]) << 16)
}

/// Push a stack to the array, deduplicating by position and state
fileprivate func pushStackDedup(stack: Stack, newStacks: inout [Stack]) {
    for i in 0..<newStacks.count {
        let other = newStacks[i]
        if other.pos == stack.pos && other.sameState(stack) {
            if newStacks[i].score < stack.score {
                newStacks[i] = stack
            }
            return
        }
    }
    newStacks.append(stack)
}

/// Find a finished parse stack
fileprivate func findFinished(stacks: [Stack]) -> Stack? {
    var best: Stack?
    
    for stack in stacks {
        let stopped = stack.p.stoppedAt
        if (stack.pos == stack.p.stream.end || (stopped != nil && stack.pos > stopped!)) &&
           stack.p.parser.stateFlag(state: stack.state, flag: StateFlag.accepting) &&
           (best == nil || best!.score < stack.score) {
            best = stack
        }
    }
    
    return best
}

/// Get a specializer function from a spec
fileprivate func getSpecializer(spec: SpecializerSpec) -> (String, Stack) -> Int {
    if let external = spec.external {
        let mask = spec.extend ? Specialize.extend : Specialize.specialize
        return { value, stack in (external(value, stack) << 1) | mask }
    }
    return spec.get!
}

/// Dialect configuration for the parser
public class Dialect {
    let source: String?
    let flags: [Bool]
    let disabled: [UInt8]?
    
    init(source: String?, flags: [Bool], disabled: [UInt8]?) {
        self.source = source
        self.flags = flags
        self.disabled = disabled
    }
    
    func allows(term: Int) -> Bool {
        return disabled == nil || disabled![term] == 0
    }
}

/// Specializer specification
struct SpecializerSpec {
    let term: Int
    let get: ((String, Stack) -> Int)?
    let external: ((String, Stack) -> Int)?
    let extend: Bool
}

/// Parse configuration options
public struct ParserConfig {
    var props: [NodePropSource]?
    var top: String?
    var dialect: String?
    var tokenizers: [(from: ExternalTokenizer, to: ExternalTokenizer)]?
    var specializers: [(from: (String, Stack) -> Int, to: (String, Stack) -> Int)]?
    var contextTracker: ContextTracker<Any>?
    var strict: Bool?
    var wrap: ParseWrapper?
    var bufferLength: Int?
}

/// Parser specification
struct ParserSpec {
    let version: Int
    let states: StringOrArray
    let stateData: StringOrArray  
    let goto: StringOrArray
    let nodeNames: String
    let maxTerm: Int
    let repeatNodeCount: Int
    let nodeProps: [[Any]]?
    let propSources: [NodePropSource]?
    let skippedNodes: [Int]?
    let tokenData: String
    let tokenizers: [Any] // [Tokenizer | Int]
    let topRules: [String: [Int]]
    let context: ContextTracker<Any>?
    let dialects: [String: Int]?
    let dynamicPrecedences: [Int: Int]?
    let specialized: [SpecializerSpec]?
    let tokenPrec: Int
    let termNames: [Int: String]?
}

/// Enum for string or array data
enum StringOrArray {
    case string(String)
    case uint32Array([UInt32])
    case uint16Array([UInt16])
}

/// Identity function for generic types
fileprivate func id<T>(_ x: T) -> T {
    return x
}

/// Context tracker for tracking stateful context during parsing
public class ContextTracker<T> {
    var start: T
    var shift: (T, Int, Stack, InputStream) -> T
    var reduce: (T, Int, Stack, InputStream) -> T
    var reuse: (T, Tree, Stack, InputStream) -> T
    var hash: (T) -> Int
    var strict: Bool
    
    init(start: T,
         shift: ((T, Int, Stack, InputStream) -> T)? = nil,
         reduce: ((T, Int, Stack, InputStream) -> T)? = nil,
         reuse: ((T, Tree, Stack, InputStream) -> T)? = nil,
         hash: ((T) -> Int)? = nil,
         strict: Bool = true) {
        self.start = start
        self.shift = shift ?? { val, _, _, _ in val }
        self.reduce = reduce ?? { val, _, _, _ in val }
        self.reuse = reuse ?? { val, _, _, _ in val }
        self.hash = hash ?? { _ in 0 }
        self.strict = strict
    }
}

/// Main parse implementation
class Parse: PartialParse {
    var stacks: [Stack]
    var recovering = 0
    var fragments: LrFragmentCursor?
    var nextStackID = 0x2654
    var minStackPos = 0
    
    var reused: [Tree] = []
    var stream: InputStream
    var tokens: TokenCache
    var topTerm: Int
    public var stoppedAt: Int?
    
    var lastBigReductionStart = -1
    var lastBigReductionSize = 0
    var bigReductionCount = 0
    
    let parser: LRParser
    let input: any Input
    let ranges: [Range]
    
    init(parser: LRParser, input: any Input, fragments: [TreeFragment], ranges: [Range]) {
        self.parser = parser
        self.input = input
        self.ranges = ranges
        self.stream = InputStream(input: input, ranges: ranges)
        self.tokens = TokenCache(parser: parser, stream: stream)
        self.topTerm = parser.top[1]
        self.stacks = []
        self.fragments = nil
        self.stoppedAt = nil
        let from = ranges[0].from
        self.stacks = [Stack.start(self, parser.top[0], from)]
        
        if fragments.count > 0 && (stream.end - from > parser.bufferLength * 4) {
            self.fragments = LrFragmentCursor(fragments: fragments, nodeSet: parser.nodeSet)
        } else {
            self.fragments = nil
        }
    }
    
    public var parsedPos: Int {
        return minStackPos
    }
    
    public func advance() -> Tree? {
        let stacks = self.stacks
        let pos = minStackPos
        var newStacks: [Stack] = []
        var stopped: [Stack]?
        var stoppedTokens: [Int]?
        var dummySplit: [Stack] = []
        
        if stacks.isEmpty { return nil }
        
        // Handle big reductions to avoid deep recursion
        if bigReductionCount > Rec.maxLeftAssociativeReductionCount && stacks.count == 1 {
            let s = stacks[0]
            while s.forceReduce() && s.stack.count > 0 && s.stack[s.stack.count - 2] >= lastBigReductionStart {
                // Keep reducing
            }
            bigReductionCount = 0
            lastBigReductionSize = 0
        }
        
        // Process all stacks at current position
        for i in 0..<stacks.count {
            var stack = stacks[i]
            while true {
                tokens.mainToken = nil
                if stack.pos > pos {
                    newStacks.append(stack)
                } else if advanceStack(stack: &stack, stacks: &newStacks, split: &dummySplit) {
                    continue
                } else {
                    if stopped == nil {
                        stopped = []
                        stoppedTokens = []
                    }
                    stopped!.append(stack)
                    let tok = tokens.getMainToken(stack: stack)
                    stoppedTokens!.append(tok.value)
                    stoppedTokens!.append(tok.end)
                }
                break
            }
        }
        
        if newStacks.isEmpty {
            if let finished = stopped.flatMap({ findFinished(stacks: $0) }) {
                if parseLog { print("Finish with \(stackID(stack: finished))") }
                return stackToTree(stack: finished.forceAll())
            }
            
            if parser.strict {
                if parseLog, let _ = stopped {
                    let tokenName = tokens.mainToken.map { parser.getName(term: $0.value) } ?? "none"
                    print("Stuck with token \(tokenName)")
                }
                return nil
            }
            
            if recovering == 0 {
                recovering = Rec.distance
            }
        }
        
        if recovering > 0, let stopped = stopped, let stoppedTokens = stoppedTokens {
            let finished: Stack?
            if let stoppedAt = stoppedAt, stopped[0].pos > stoppedAt {
                finished = stopped[0]
            } else {
                finished = runRecovery(stacks: stopped, tokens: stoppedTokens, newStacks: &newStacks)
            }
            
            if let finished = finished {
                if parseLog { print("Force-finish \(stackID(stack: finished))") }
                return stackToTree(stack: finished.forceAll())
            }
        }
        
        // Prune stacks during recovery
        if recovering > 0 {
            let maxRemaining = recovering == 1 ? 1 : recovering * Rec.maxRemainingPerStep
            if newStacks.count > maxRemaining {
                newStacks.sort { $0.score > $1.score }
                while newStacks.count > maxRemaining {
                    newStacks.removeLast()
                }
            }
            if newStacks.contains(where: { $0.reducePos > pos }) {
                recovering -= 1
            }
        } else if newStacks.count > 1 {
            // Prune duplicate or long-running stacks
            var i = 0
            while i < (newStacks.count - 1) {
                var j = i + 1
                while j < newStacks.count {
                    let stack = newStacks[i]
                    let other = newStacks[j]
                    if stack.sameState(other) ||
                       (stack.buffer.count > Rec.minBufferLengthPrune && other.buffer.count > Rec.minBufferLengthPrune) {
                        if (stack.score - other.score != 0 || stack.buffer.count - other.buffer.count != 0) {
                            if stack.score > other.score || (stack.score == other.score && stack.buffer.count > other.buffer.count) {
                                newStacks.remove(at: j)
                                continue
                            } else {
                                newStacks.remove(at: i)
                                i -= 1
                                break
                            }
                        }
                    }
                    j += 1
                }
                i += 1
            }
            
            if newStacks.count > Rec.maxStackCount {
                newStacks.sort { $0.score > $1.score }
                while newStacks.count > Rec.maxStackCount {
                    newStacks.removeLast()
                }
            }
        }
        
        minStackPos = newStacks[0].pos
        for i in 1..<newStacks.count {
            if newStacks[i].pos < minStackPos {
                minStackPos = newStacks[i].pos
            }
        }
        
        self.stacks = newStacks
        return nil
    }
    
    public func stopAt(pos: Int) {
        if let stoppedAt = stoppedAt, stoppedAt < pos {
            fatalError("Can't move stoppedAt forward")
        }
        self.stoppedAt = pos
    }
    
    func advanceStack(stack: inout Stack, stacks: inout [Stack], split: inout [Stack]) -> Bool {
        let start = stack.pos
        let parser = self.parser
        let base = parseLog ? stackID(stack: stack) + " -> " : ""
        
        if let stoppedAt = stoppedAt, start > stoppedAt {
            return stack.forceReduce()
        }
        
        // Try to reuse fragments
        if let fragments = fragments {
            let strictCx = stack.curContext?.tracker.strict ?? false
            let cxHash = strictCx ? (stack.curContext?.hash ?? 0) : 0
            
            var cached = fragments.nodeAt(pos: start)
            while let c = cached {
                let match: Int
                if parser.nodeSet.types[c.type.id] === c.type {
                    match = parser.getGoto(state: stack.state, term: c.type.id)
                } else {
                    match = -1
                }
                
                if match > -1 && c.length > 0 &&
                   (!strictCx || (c.prop(prop: nodePropContextHash) ?? 0) == cxHash) {
                    stack.useNode(c, next: match)
                    if parseLog { print("\(base)\(stackID(stack: stack)) (via reuse of \(parser.getName(term: c.type.id)))") }
                    return true
                }
                
                if c.children.isEmpty || c.positions[0] > 0 {
                    break
                }
                
                if case .tree(let inner) = c.children[0], c.positions[0] == 0 {
                    cached = inner
                } else {
                    break
                }
            }
        }
        
        // Try default reduce
        let defaultReduce = parser.stateSlot(state: stack.state, slot: ParseState.defaultReduce)
        if defaultReduce > 0 {
            stack.reduce(defaultReduce)
            if parseLog { print("\(base)\(stackID(stack: stack)) (via always-reduce \(parser.getName(term: defaultReduce & Action.valueMask)))") }
            return true
        }
        
        // Force reduce if stack is too deep
        if stack.stack.count >= Rec.cutDepth {
            while stack.stack.count > Rec.cutTo && stack.forceReduce() {
                // Keep reducing
            }
        }
        
        // Get and apply token actions
        let actions = tokens.getActions(stack: stack)
        for i in stride(from: 0, to: actions.count, by: 3) {
            let action = actions[i]
            let term = actions[i + 1]
            let end = actions[i + 2]
            let last = (i + 3) >= actions.count || split.isEmpty
            let localStack: Stack
            if last {
                localStack = stack
            } else {
                localStack = stack.split()
            }
            
            let main = tokens.mainToken
            localStack.apply(action, term, nextStart: main?.start ?? localStack.pos, nextEnd: end)
            if parseLog {
                let kind = (action & Action.reduceFlag) == 0
                    ? "shift"
                    : "reduce of \(parser.getName(term: action & Action.valueMask))"
                print("\(base)\(stackID(stack: localStack)) (via \(kind) for \(parser.getName(term: term)) @ \(start)\(localStack === stack ? "" : ", split"))")
            }
            
            if last {
                return true
            } else if localStack.pos > start {
                stacks.append(localStack)
            } else {
                split.append(localStack)
            }
        }
        
        return false
    }
    
    func advanceFully(stack: inout Stack, newStacks: inout [Stack]) -> Bool {
        let pos = stack.pos
        var emptySplit: [Stack] = []
        while true {
            if !advanceStack(stack: &stack, stacks: &newStacks, split: &emptySplit) {
                return false
            }
            if stack.pos > pos {
                pushStackDedup(stack: stack, newStacks: &newStacks)
                return true
            }
        }
    }
    
    func runRecovery(stacks: [Stack], tokens: [Int], newStacks: inout [Stack]) -> Stack? {
        var finished: Stack?
        var restarted = false
        
        for i in 0..<stacks.count {
            var stack = stacks[i]
            let token = tokens[i * 2]
            let tokenEnd = tokens[i * 2 + 1]
            let base = parseLog ? stackID(stack: stack) + " -> " : ""
            
            if stack.deadEnd {
                if restarted {
                    continue
                }
                restarted = true
                stack.restart()
                if parseLog { print("\(base)\(stackID(stack: stack)) (restarted)") }
                let done = advanceFully(stack: &stack, newStacks: &newStacks)
                if done {
                    continue
                }
            }
            
            var force = stack.split()
            var forceBase = base
            for _ in 0..<Rec.forceReduceLimit {
                if !force.forceReduce() {
                    break
                }
                if parseLog { print("\(forceBase)\(stackID(stack: force)) (via force-reduce)") }
                let done = advanceFully(stack: &force, newStacks: &newStacks)
                if done {
                    break
                }
                if parseLog { forceBase = stackID(stack: force) + " -> " }
            }
            
            for var insert in stack.recoverByInsert(token) {
                if parseLog { print("\(base)\(stackID(stack: insert)) (via recover-insert)") }
                _ = advanceFully(stack: &insert, newStacks: &newStacks)
            }
            
            if stream.end > stack.pos {
                var tokenEnd = tokenEnd
                var token = token
                if tokenEnd == stack.pos {
                    tokenEnd += 1
                    token = LrTerm.err
                }
                stack.recoverByDelete(token, nextEnd: tokenEnd)
                if parseLog { print("\(base)\(stackID(stack: stack)) (via recover-delete \(parser.getName(term: token)))") }
                pushStackDedup(stack: stack, newStacks: &newStacks)
            } else if finished == nil || finished!.score < force.score {
                finished = force
            }
        }
        
        return finished
    }
    
    func stackToTree(stack: Stack) -> Tree {
        stack.close()
        return Tree.build(
            data: BuildData(
                buffer: .cursor(StackBufferCursor.create(stack)),
                nodeSet: parser.nodeSet,
                topID: topTerm,
                start: ranges[0].from,
                length: stack.pos - ranges[0].from,
                maxBufferLength: parser.bufferLength,
                reused: reused,
                minRepeatType: parser.minRepeatTerm
            )
        )
    }

    func stackID(stack: Stack) -> String {
        let oid = ObjectIdentifier(stack)
        if let id = stackIDs[oid] {
            return id + stack.toString()
        }
        let id = String(UnicodeScalar(nextStackID)!)
        nextStackID += 1
        stackIDs[oid] = id
        return id + stack.toString()
    }
}

/// LR parser with grammar tables
public class LRParser: Parser {
    let states: [UInt32]
    let data: [UInt16]
    let goto: [UInt16]
    let maxTerm: Int
    let minRepeatTerm: Int
    var tokenizers: [any Tokenizer]
    let topRules: [String: [Int]]
    var context: ContextTracker<Any>?
    let dialects: [String: Int]
    let dynamicPrecedences: [Int: Int]?
    let specialized: [UInt16]
    var specializers: [(String, Stack) -> Int]
    var specializerSpecs: [SpecializerSpec]
    let tokenPrecTable: Int
    let termNames: [Int: String]?
    let maxNode: Int
    var dialect: Dialect
    var wrappers: [ParseWrapper] = []
    var top: [Int]
    var bufferLength: Int
    var strict: Bool
    var nodeSet: NodeSet
    let eofTerm: Int
    
    init(spec: ParserSpec) {
        if spec.version != File.version {
            fatalError("Parser version (\(spec.version)) doesn't match runtime version (\(File.version))")
        }
        
        let parsedNodeNames = spec.nodeNames.split(separator: " ").map { String($0) }
        self.minRepeatTerm = parsedNodeNames.count
        var allNodeNames = parsedNodeNames
        for _ in 0..<spec.repeatNodeCount {
            allNodeNames.append("")
        }
        
        let topTerms = spec.topRules.values.map { $0[1] }
        var nodeProps: [[(NodeProp<Any>?, Any?)]] = (0..<allNodeNames.count).map { _ in [] }
        
        func setProp(nodeID: Int, prop: NodeProp<Any>?, value: Any) {
            guard let prop = prop else { return }
            nodeProps[nodeID].append((prop, prop.deserialize(String(describing: value)) as Any?))
        }
        
        if let nodePropsSpec = spec.nodeProps {
            for propSpec in nodePropsSpec {
                var prop: NodeProp<Any>? = nil
                if let propName = propSpec[0] as? String {
                    // Get NodeProp by name - this would need proper implementation
                    // prop = NodeProp.getByName(propName)
                    _ = propName
                } else {
                    prop = propSpec[0] as? NodeProp<Any>
                }
                
                var i = 1
                while i < propSpec.count {
                    let next = propSpec[i] as! Int
                    i += 1
                    if next >= 0 {
                        setProp(nodeID: next, prop: prop, value: propSpec[i])
                        i += 1
                    } else {
                        let value = propSpec[i - next]
                        for _ in 0..<(-next) {
                            setProp(nodeID: propSpec[i] as! Int, prop: prop, value: value)
                            i += 1
                        }
                    }
                }
            }
        }
        
        let localMinRepeatTerm = self.minRepeatTerm
        let types: [NodeType] = allNodeNames.enumerated().map { (index, name) -> NodeType in
            var props: [Int: Any] = [:]
            for (prop, value) in nodeProps[index] {
                if let prop = prop, let value = value {
                    props[prop.id] = value
                }
            }
            var flags = 0
            if index < localMinRepeatTerm && !name.isEmpty {
                // non-anonymous
            } else {
                flags |= NodeFlag.anonymous.rawValue
            }
            if topTerms.contains(index) {
                flags |= NodeFlag.top.rawValue
            }
            if index == 0 {
                flags |= NodeFlag.error.rawValue
            }
            if spec.skippedNodes?.contains(index) == true {
                flags |= NodeFlag.skipped.rawValue
            }
            return NodeType(
                name: index >= localMinRepeatTerm ? "" : name,
                props: props,
                id: index,
                flags: flags
            )
        }
        
        self.nodeSet = NodeSet(types: types)
        
        if let propSources = spec.propSources {
            // self.nodeSet = self.nodeSet.extend(...propSources)
            _ = propSources
        }
        
        self.strict = false
        self.bufferLength = defaultBufferLength
        
        let tokenArray = decodeArray(ArrayOrString.string(spec.tokenData))
        self.context = spec.context
        self.specializerSpecs = spec.specialized ?? []
        self.specialized = self.specializerSpecs.map { UInt16($0.term) }
        self.specializers = self.specializerSpecs.map { getSpecializer(spec: $0) }
        
        self.states = decodeArrayToUInt32(spec.states)
        self.data = decodeArrayToUInt16(spec.stateData)
        self.goto = decodeArrayToUInt16(spec.goto)
        self.maxTerm = spec.maxTerm
        self.tokenizers = spec.tokenizers.map { value in
            if let intValue = value as? Int {
                return TokenGroup(data: tokenArray, id: intValue)
            } else {
                return value as! any Tokenizer
            }
        }
        self.topRules = spec.topRules
        self.dialects = spec.dialects ?? [:]
        self.dynamicPrecedences = spec.dynamicPrecedences
        self.tokenPrecTable = spec.tokenPrec
        self.termNames = spec.termNames
        self.maxNode = self.nodeSet.types.count - 1
        self.top = Array(topRules.values.first ?? [0, 0])
        self.eofTerm = maxNode + 1
        
        // Compute dialect inline to avoid calling self before full initialization
        let dialectValues = Array(dialects.keys)
        let dialectFlags = Array(repeating: false, count: dialectValues.count)
        var dialectDisabled: [UInt8]?
        for i in 0..<dialectValues.count {
            if let dialectIndex = dialects[dialectValues[i]] {
                if dialectDisabled == nil {
                    dialectDisabled = Array(repeating: 0, count: maxTerm + 1)
                }
                var j = dialectIndex
                while data[j] != Seq.end {
                    dialectDisabled![Int(data[j])] = 1
                    j += 1
                }
            }
        }
        self.dialect = Dialect(source: nil, flags: dialectFlags, disabled: dialectDisabled)
    }
    
    public func createParse(input: any Input, fragments: [TreeFragment], ranges: [Range]) -> any PartialParse {
        var parse: any PartialParse = Parse(parser: self, input: input, fragments: fragments, ranges: ranges)
        for wrapper in wrappers {
            parse = wrapper(parse, input, fragments, ranges)
        }
        return parse
    }
    
    func getGoto(state: Int, term: Int, loose: Bool = false) -> Int {
        let table = goto
        if term >= table[0] {
            return -1
        }
        
        var pos = Int(table[term + 1])
        while true {
            let groupTag = table[pos]
            pos += 1
            let last = groupTag & 1
            let target = table[pos]
            pos += 1
            
            if last != 0 && loose {
                return Int(target)
            }
            
            let end = pos + Int(groupTag >> 1)
            while pos < end {
                if table[pos] == UInt16(state) {
                    return Int(target)
                }
                pos += 1
            }
            
            if last != 0 {
                return -1
            }
        }
    }
    
    func hasAction(state: Int, terminal: Int) -> Int {
        let data = self.data
        
        for set in 0..<2 {
            var i = stateSlot(state: state, slot: set == 1 ? ParseState.skip : ParseState.actions)
            
            while true {
                let next = Int(data[i])
                if next == Seq.end {
                    if data[i + 1] == Seq.next {
                        i = pair(data: data, off: i + 2)
                    } else if data[i + 1] == Seq.other {
                        return pair(data: data, off: i + 2)
                    } else {
                        break
                    }
                }
                
                if next == terminal || next == LrTerm.err {
                    return pair(data: data, off: i + 1)
                }
                
                i += 3
            }
        }
        
        return 0
    }
    
    func stateSlot(state: Int, slot: Int) -> Int {
        let idx = state * ParseState.size + slot
        guard idx >= 0 && idx < states.count else {
            return 0
        }
        return Int(states[idx])
    }
    
    func stateFlag(state: Int, flag: Int) -> Bool {
        return (stateSlot(state: state, slot: ParseState.flags) & flag) > 0
    }
    
    func validAction(state: Int, action: Int) -> Bool {
        return allActions(state: state) { a in
            a == action ? a : nil
        } != nil
    }
    
    func allActions(state: Int, action: (Int) -> Int?) -> Int? {
        let deflt = stateSlot(state: state, slot: ParseState.defaultReduce)
        var result: Int? = deflt != 0 ? action(deflt) : nil
        
        var i = stateSlot(state: state, slot: ParseState.actions)
        while result == nil {
            if data[i] == Seq.end {
                if data[i + 1] == Seq.next {
                    i = pair(data: data, off: i + 2)
                } else {
                    break
                }
            }
            result = action(pair(data: data, off: i + 1))
            i += 3
        }
        
        return result
    }
    
    func nextStates(state: Int) -> [Int] {
        var result: [Int] = []
        var i = stateSlot(state: state, slot: ParseState.actions)
        
        while true {
            if data[i] == Seq.end {
                if data[i + 1] == Seq.next {
                    i = pair(data: data, off: i + 2)
                } else {
                    break
                }
            }
            
            if (Int(data[i + 2]) & (Action.reduceFlag >> 16)) == 0 {
                let value = Int(data[i + 1])
                if !result.contains(where: { $0 == value }) {
                    result.append(Int(data[i]))
                    result.append(value)
                }
            }
            
            i += 3
        }
        
        return result
    }
    
    private init(
        states: [UInt32],
        data: [UInt16],
        goto: [UInt16],
        maxTerm: Int,
        minRepeatTerm: Int,
        tokenizers: [any Tokenizer],
        topRules: [String: [Int]],
        context: ContextTracker<Any>?,
        dialects: [String: Int],
        dynamicPrecedences: [Int: Int]?,
        specialized: [UInt16],
        specializers: [(String, Stack) -> Int],
        specializerSpecs: [SpecializerSpec],
        tokenPrecTable: Int,
        termNames: [Int: String]?,
        maxNode: Int,
        dialect: Dialect,
        wrappers: [ParseWrapper],
        top: [Int],
        bufferLength: Int,
        strict: Bool,
        nodeSet: NodeSet,
        eofTerm: Int
    ) {
        self.states = states
        self.data = data
        self.goto = goto
        self.maxTerm = maxTerm
        self.minRepeatTerm = minRepeatTerm
        self.tokenizers = tokenizers
        self.topRules = topRules
        self.context = context
        self.dialects = dialects
        self.dynamicPrecedences = dynamicPrecedences
        self.specialized = specialized
        self.specializers = specializers
        self.specializerSpecs = specializerSpecs
        self.tokenPrecTable = tokenPrecTable
        self.termNames = termNames
        self.maxNode = maxNode
        self.dialect = dialect
        self.wrappers = wrappers
        self.top = top
        self.bufferLength = bufferLength
        self.strict = strict
        self.nodeSet = nodeSet
        self.eofTerm = eofTerm
    }

    public func configure(config: ParserConfig) -> LRParser {
        let copy = LRParser(
            states: states,
            data: data,
            goto: goto,
            maxTerm: maxTerm,
            minRepeatTerm: minRepeatTerm,
            tokenizers: tokenizers,
            topRules: topRules,
            context: context,
            dialects: dialects,
            dynamicPrecedences: dynamicPrecedences,
            specialized: specialized,
            specializers: specializers,
            specializerSpecs: specializerSpecs,
            tokenPrecTable: tokenPrecTable,
            termNames: termNames,
            maxNode: maxNode,
            dialect: dialect,
            wrappers: wrappers,
            top: top,
            bufferLength: bufferLength,
            strict: strict,
            nodeSet: nodeSet,
            eofTerm: eofTerm
        )
        if let props = config.props {
            copy.nodeSet = nodeSet.extend(props)
        }
        if let topName = config.top {
            if let info = topRules[topName] {
                copy.top = info
            } else {
                fatalError("Invalid top rule name \(topName)")
            }
        }
        if let tokenizers = config.tokenizers {
            copy.tokenizers = self.tokenizers.map { t in
                if let found = tokenizers.first(where: { ObjectIdentifier($0.from as AnyObject) == ObjectIdentifier(t as AnyObject) }) {
                    return found.to
                }
                return t
            }
        }
        if let specializers = config.specializers {
            copy.specializers = self.specializers
            copy.specializerSpecs = self.specializerSpecs.enumerated().map { i, s in
                if i < specializers.count {
                    let replacement = specializers[i]
                    let spec = SpecializerSpec(term: s.term, get: nil, external: replacement.to, extend: s.extend)
                    copy.specializers[i] = getSpecializer(spec: spec)
                    return spec
                }
                copy.specializers[i] = getSpecializer(spec: s)
                return s
            }
        }
        if let contextTracker = config.contextTracker {
            copy.context = contextTracker
        }
        if let dialect = config.dialect {
            copy.dialect = parseDialect(dialect: dialect)
        }
        if let strict = config.strict {
            copy.strict = strict
        }
        if let wrap = config.wrap {
            copy.wrappers = copy.wrappers + [wrap]
        }
        if let bufferLength = config.bufferLength {
            copy.bufferLength = bufferLength
        }
        return copy
    }
    
    public func hasWrappers() -> Bool {
        return !wrappers.isEmpty
    }
    
    public func getName(term: Int) -> String {
        if let termNames = termNames, let name = termNames[term], !name.isEmpty {
            return name
        }
        let nodeName = term <= maxNode && !nodeSet.types[term].name.isEmpty ? nodeSet.types[term].name : nil
        return nodeName ?? String(term)
    }
    
    func dynamicPrecedence(term: Int) -> Int {
        guard let dynamicPrecedences = dynamicPrecedences else {
            return 0
        }
        return dynamicPrecedences[term] ?? 0
    }
    
    func parseDialect(dialect: String? = nil) -> Dialect {
        let values = Array(dialects.keys)
        var flags = Array(repeating: false, count: values.count)
        
        if let dialect = dialect {
            for part in dialect.split(separator: " ") {
                if let id = values.firstIndex(of: String(part)) {
                    flags[id] = true
                }
            }
        }
        
        var disabled: [UInt8]?
        for i in 0..<values.count {
            if !flags[i] {
                if disabled == nil {
                    disabled = Array(repeating: 0, count: maxTerm + 1)
                }
                
                if let dialectIndex = dialects[values[i]] {
                    var j = dialectIndex
                    while data[j] != Seq.end {
                        disabled![Int(data[j])] = 1
                        j += 1
                    }
                }
            }
        }
        
        return Dialect(source: dialect, flags: flags, disabled: disabled)
    }
    
    static func deserialize(spec: Any) -> LRParser {
        return LRParser(spec: spec as! ParserSpec)
    }
}

// Helper functions for decoding arrays
fileprivate func decodeArrayToUInt32(_ input: StringOrArray) -> [UInt32] {
    let decoded: [Int]
    switch input {
    case .string(let str):
        decoded = decodeArray(ArrayOrString.string(str))
    case .uint32Array(let arr):
        decoded = arr.map { Int($0) }
    case .uint16Array(let arr):
        decoded = arr.map { Int($0) }
    }
    return decoded.map { UInt32($0) }
}

fileprivate func decodeArrayToUInt16(_ input: StringOrArray) -> [UInt16] {
    let decoded: [Int]
    switch input {
    case .string(let str):
        decoded = decodeArray(ArrayOrString.string(str))
    case .uint32Array(let arr):
        decoded = arr.map { Int($0) }
    case .uint16Array(let arr):
        decoded = arr.map { Int($0) }
    }
    return decoded.map { UInt16($0) }
}
