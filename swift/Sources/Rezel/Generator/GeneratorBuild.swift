import Foundation

public class Parts {
    public let terms: [Term]
    public let conflicts: [Conflicts]?
    
    public init(terms: [Term], conflicts: [Conflicts]?) {
        self.terms = terms
        self.conflicts = conflicts
    }
    
    public func concat(_ other: Parts) -> Parts {
        if self.terms.isEmpty && (self.conflicts == nil || self.conflicts!.isEmpty) { return other }
        if other.terms.isEmpty && (other.conflicts == nil || other.conflicts!.isEmpty) { return self }
        var newConflicts: [Conflicts]? = nil
        if self.conflicts != nil || other.conflicts != nil {
            let selfC = self.ensureConflicts()
            let otherC = other.ensureConflicts()
            newConflicts = selfC
            if !newConflicts!.isEmpty {
                newConflicts![newConflicts!.count - 1] = newConflicts![newConflicts!.count - 1].join(otherC[0])
            }
            if otherC.count > 1 {
                for i in 1..<otherC.count {
                    newConflicts!.append(otherC[i])
                }
            }
        }
        return Parts(terms: self.terms + other.terms, conflicts: newConflicts)
    }
    
    public func withConflicts(_ pos: Int, _ conflicts: Conflicts) -> Parts {
        if conflicts === Conflicts.none { return self }
        var array = ensureConflicts()
        if pos < array.count {
            array[pos] = array[pos].join(conflicts)
        }
        return Parts(terms: terms, conflicts: array)
    }
    
    public func ensureConflicts() -> [Conflicts] {
        if let c = conflicts { return c }
        return Array(repeating: Conflicts.none, count: terms.count + 1)
    }
    
    public static nonisolated(unsafe) let none = Parts(terms: [], conflicts: nil)
}

public func p(_ terms: Term...) -> Parts {
    return Parts(terms: terms, conflicts: nil)
}

public class BuiltRule {
    public let id: String
    public let args: [Expression]
    public let term: Term
    
    public init(id: String, args: [Expression], term: Term) {
        self.id = id
        self.args = args
        self.term = term
    }
    
    public func matches(_ expr: NameExpression) -> Bool {
        return id == expr.id.name && exprsEq(expr.args, args)
    }
    
    public func matchesRepeat(_ expr: RepeatExpression) -> Bool {
        return id == "+" && exprEq(expr.expr, args[0])
    }
}

public struct BuildOptions {
    let fileName: String?
    let warn: ((String) -> Void)?
    let includeNames: Bool
    let moduleStyle: String
    let typeScript: Bool
    let exportName: String?
    let externalTokenizer: ((String, [String: Int]) -> ExternalTokenizer)?
    let externalPropSource: ((String) -> NodePropSource)?
    let externalSpecializer: ((String, [String: Int]) -> (String, Stack) -> Int)?
    let externalProp: ((String) -> NodeProp<Any>)?
    let contextTracker: Any?
    
    public init(
        fileName: String? = nil,
        warn: ((String) -> Void)? = nil,
        includeNames: Bool = false,
        moduleStyle: String = "es",
        typeScript: Bool = false,
        exportName: String? = nil,
        externalTokenizer: ((String, [String: Int]) -> ExternalTokenizer)? = nil,
        externalPropSource: ((String) -> NodePropSource)? = nil,
        externalSpecializer: ((String, [String: Int]) -> (String, Stack) -> Int)? = nil,
        externalProp: ((String) -> NodeProp<Any>)? = nil,
        contextTracker: Any? = nil
    ) {
        self.fileName = fileName
        self.warn = warn
        self.includeNames = includeNames
        self.moduleStyle = moduleStyle
        self.typeScript = typeScript
        self.exportName = exportName
        self.externalTokenizer = externalTokenizer
        self.externalPropSource = externalPropSource
        self.externalSpecializer = externalSpecializer
        self.externalProp = externalProp
        self.contextTracker = contextTracker
    }
}

public struct SkipInfo {
    let skip: [Term]
    let rule: Term?
    let startTokens: [Term]
    let id: Int
}

public struct SharedActions {
    let actions: [Any]
    let addr: Int
}

let MinSharedActions = 5

class DataBuilder {
    var data: [Int] = []
    
    func storeArray(_ data: [Int]) -> Int {
        if let found = findArray(self.data, data) {
            return found
        }
        let pos = self.data.count
        self.data.append(contentsOf: data)
        return pos
    }
    
    func finish() -> [UInt16] {
        return data.map { UInt16($0) }
    }
}

func findArray(_ data: [Int], _ value: [Int]) -> Int? {
    var i = 0
    search: while true {
        if let next = data[i...].firstIndex(of: value[0]) {
            if next + value.count > data.count { break }
            for j in 1..<value.count {
                if value[j] != data[next + j] {
                    i = next + 1
                    continue search
                }
            }
            return next
        }
        break
    }
    return nil
}

func findSkipStates(_ table: [State], _ startRules: [Term]) -> (Int) -> Bool {
    var nonSkip: [Int: Bool] = [:]
    var work: [State] = []
    func add(_ state: State) {
        if nonSkip[state.id] == nil {
            nonSkip[state.id] = true
            work.append(state)
        }
    }
    for state in table {
        if let sr = state.startRule, startRules.contains(where: { $0.id == sr.id }) {
            add(state)
        }
    }
    var i = 0
    while i < work.count {
        for a in work[i].actions {
            if let shift = a as? Shift {
                add(shift.target)
            }
        }
        for g in work[i].goto {
            add(g.target)
        }
        i += 1
    }
    return { id in nonSkip[id] == nil }
}

func reduceAction(_ rule: Rule, _ skipInfo: [SkipInfo], depth: Int? = nil) -> Int {
    let d = depth ?? rule.parts.count
    return rule.name.id |
        Action.reduceFlag |
        (rule.isRepeatWrap && d == rule.parts.count ? Action.repeatFlag : 0) |
        (skipInfo.contains(where: { $0.rule === rule.name }) ? Action.stayFlag : 0) |
        (d << Action.reduceDepthShift)
}

func buildSpecializeTable(_ spec: [[String: Any]]) -> [String: Int] {
    var table: [String: Int] = [:]
    for entry in spec {
        let value = entry["value"] as! String
        let term = entry["term"] as! Term
        let type = entry["type"] as! String
        let code = type == "specialize" ? Specialize.specialize : Specialize.extend
        table[value] = (term.id << 1) | code
    }
    return table
}

func addToSet<T: AnyObject>(_ set: inout [T], _ value: T) {
    if !set.contains(where: { $0 === value }) {
        set.append(value)
    }
}

func computeGotoTable(_ states: [State]) -> [UInt16] {
    var goto: [Int: [Int: [Int]]] = [:]
    var maxTerm = 0
    for state in states {
        for entry in state.goto {
            maxTerm = max(entry.term.id, maxTerm)
            if goto[entry.term.id] == nil {
                goto[entry.term.id] = [:]
            }
            if goto[entry.term.id]![entry.target.id] == nil {
                goto[entry.term.id]![entry.target.id] = []
            }
            goto[entry.term.id]![entry.target.id]!.append(state.id)
        }
    }
    let dataBuilder = DataBuilder()
    var index: [Int] = []
    let offset = maxTerm + 2
    for term in 0...maxTerm {
        if let entries = goto[term] {
            var termTable: [Int] = []
            let keys = Array(entries.keys).sorted()
            for (idx, target) in keys.enumerated() {
                let list = entries[target]!
                let isLast = idx == keys.count - 1
                termTable.append((isLast ? 1 : 0) + (list.count << 1))
                termTable.append(target)
                termTable.append(contentsOf: list)
            }
            index.append(dataBuilder.storeArray(termTable) + offset)
        } else {
            index.append(1)
        }
    }
    if index.contains(where: { $0 > 0xffff }) {
        fatalError("Goto table too large")
    }
    var result: [UInt16] = [UInt16(maxTerm + 1)]
    result.append(contentsOf: index.map { UInt16($0) })
    result.append(contentsOf: dataBuilder.data.map { UInt16($0) })
    return result
}

func addToSet<T: Equatable>(_ set: inout [T], _ value: T) {
    if !set.contains(value) {
        set.append(value)
    }
}

func addToProp(_ term: Term, _ prop: String, _ value: String) {
    let cur = term.props[prop]
    if cur == nil || !cur!.split(separator: " ").contains(where: { $0 == value }) {
        term.props[prop] = cur != nil ? cur! + " " + value : value
    }
}

func buildTokenMasks(_ groups: [TokenGroupSpec]) -> [Int: Int] {
    var masks: [Int: Int] = [:]
    for group in groups {
        let groupMask = 1 << group.groupID
        for term in group.tokens {
            masks[term.id] = (masks[term.id] ?? 0) | groupMask
        }
    }
    return masks
}

func isEmpty(_ expr: Expression) -> Bool {
    if let seq = expr as? SequenceExpression {
        return seq.exprs.isEmpty
    }
    return false
}

func ignored(_ name: String) -> Bool {
    let first = name.first ?? Character("")
    return first == "_" || first.isUppercase == false
}

func isExported(_ rule: RuleDeclaration) -> Bool {
    return rule.props.contains(where: { $0.at && $0.name == "export" })
}

func gatherExtTokens(_ b: Builder, _ tokens: [(id: Identifier, props: [Prop])]) -> [String: Term] {
    var result: [String: Term] = [:]
    for token in tokens {
        b.unique(token.id)
        let info = b.nodeInfo(token.props, allow: "d", defaultName: token.id.name, args: [], params: [])
        let term = b.makeTerminal(token.id.name, nodeName: info.name, props: info.props)
        if let dialect = info.dialect {
            if b.tokens.byDialect[dialect] == nil {
                b.tokens.byDialect[dialect] = []
            }
            b.tokens.byDialect[dialect]!.append(term)
        }
        b.namedTerms[token.id.name] = term
        result[token.id.name] = term
    }
    return result
}

func findExtToken(_ b: Builder, _ tokens: [String: Term], _ expr: NameExpression) -> Term? {
    guard let found = tokens[expr.id.name] else { return nil }
    if !expr.args.isEmpty {
        b.raise("External tokens cannot take arguments", pos: expr.args[0].start)
    }
    b.used(expr.id.name)
    return found
}

func addRel(_ rel: inout [(term: Term, after: [Term])], _ term: Term, _ after: [Term]) {
    if let idx = rel.firstIndex(where: { $0.term === term }) {
        rel[idx] = (term: term, after: rel[idx].after + after)
    } else {
        rel.append((term: term, after: after))
    }
}

func checkTogether(_ states: [State], _ b: Builder, _ skipInfo: [SkipInfo]) -> (Term, Term) -> Bool {
    var cache: [Int: Bool] = [:]
    func hasTerm(_ state: State, _ term: Term) -> Bool {
        if state.actions.contains(where: { a in
            if let s = a as? Shift { return s.term === term }
            if let r = a as? Reduce { return r.term === term }
            return false
        }) { return true }
        let si = b.skipRules.firstIndex(where: { $0 === state.skip }) ?? 0
        return skipInfo[si].startTokens.contains(where: { $0 === term })
    }
    return { a, b in
        let aID = a.id, bID = b.id
        let first: Term, second: Term
        if aID < bID { first = b; second = a } else { first = a; second = b }
        let key = first.id | (second.id << 16)
        if let cached = cache[key] { return cached }
        let result = states.contains { state in hasTerm(state, first) && hasTerm(state, second) }
        cache[key] = result
        return result
    }
}

func inlineRules(_ rules: [Rule], _ preserve: [Term]) -> [Rule] {
    var currentRules = rules
    for pass in 0... {
        var inlinable: [String: [Rule]] = [:]
        var found = false
        if pass == 0 {
            for rule in currentRules {
                if rule.name.inline && inlinable[rule.name.name] == nil {
                    let group = currentRules.filter { $0.name === rule.name }
                    if group.contains(where: { $0.parts.contains(where: { $0 === rule.name }) }) { continue }
                    inlinable[rule.name.name] = group
                    found = true
                }
            }
        }
        for i in 0..<currentRules.count {
            let rule = currentRules[i]
            if !rule.name.interesting &&
                !rule.parts.contains(where: { $0 === rule.name }) &&
                rule.parts.count < 3 &&
                !preserve.contains(where: { $0 === rule.name }) &&
                (rule.parts.count == 1 || currentRules.allSatisfy({ $0.skip === rule.skip || !$0.parts.contains(where: { $0 === rule.name }) })) &&
                !rule.parts.contains(where: { inlinable[$0.name] != nil }) &&
                !currentRules.enumerated().contains(where: { $0.offset != i && $0.element.name === rule.name }) {
                inlinable[rule.name.name] = [rule]
                found = true
            }
        }
        if !found { return currentRules }
        var newRules: [Rule] = []
        for rule in currentRules {
            if inlinable[rule.name.name] != nil { continue }
            if !rule.parts.contains(where: { inlinable[$0.name] != nil }) {
                newRules.append(rule)
                continue
            }
            func expand(at: Int, conflicts: [Conflicts], parts: [Term]) {
                if at == rule.parts.count {
                    newRules.append(Rule(name: rule.name, parts: parts, conflicts: conflicts, skip: rule.skip))
                    return
                }
                let next = rule.parts[at]
                if let replace = inlinable[next.name] {
                    for r in replace {
                        var newConflicts = conflicts
                        if !newConflicts.isEmpty { newConflicts.removeLast() }
                        newConflicts.append(conflicts[at].join(r.conflicts[0]))
                        if r.conflicts.count > 1 {
                            for j in 1..<(r.conflicts.count - 1) {
                                newConflicts.append(r.conflicts[j])
                            }
                        }
                        newConflicts.append(rule.conflicts[at + 1].join(r.conflicts.last ?? Conflicts.none))
                        expand(at: at + 1, conflicts: newConflicts, parts: parts + r.parts)
                    }
                } else {
                    expand(at: at + 1, conflicts: conflicts + [rule.conflicts[at + 1]], parts: parts + [next])
                }
            }
            expand(at: 0, conflicts: [rule.conflicts[0]], parts: [])
        }
        currentRules = newRules
    }
    return currentRules
}

func mergeRules(_ rules: [Rule]) -> [Rule] {
    var merged: [String: Term] = [:]
    var found = false
    var i = 0
    while i < rules.count {
        let groupStart = i
        let name = rules[i].name
        i += 1
        while i < rules.count && rules[i].name === name { i += 1 }
        let size = i - groupStart
        if name.interesting { continue }
        var j = i
        while j < rules.count {
            let otherStart = j
            let otherName = rules[j].name
            j += 1
            while j < rules.count && rules[j].name === otherName { j += 1 }
            if j - otherStart != size || otherName.interesting { continue }
            var match = true
            for k in 0..<size where match {
                let a = rules[groupStart + k]
                let b = rules[otherStart + k]
                if a.cmpNoName(b) != 0 { match = false }
            }
            if match {
                merged[name.name] = otherName
                found = true
            }
        }
    }
    if !found { return rules }
    var newRules: [Rule] = []
    for rule in rules {
        if merged[rule.name.name] == nil {
            let newParts = rule.parts.map { merged[$0.name] ?? $0 }
            newRules.append(Rule(name: rule.name, parts: newParts, conflicts: rule.conflicts, skip: rule.skip))
        }
    }
    return newRules
}

func simplifyRules(_ rules: [Rule], _ preserve: [Term]) -> [Rule] {
    return mergeRules(inlineRules(rules, preserve))
}

func invertRanges(_ ranges: [(Int, Int)]) -> [(Int, Int)] {
    var pos = 0
    var result: [(Int, Int)] = []
    let maxChar = 0x10ffff
    for (a, b) in ranges {
        if a > pos { result.append((pos, a)) }
        pos = b
    }
    if pos <= maxChar { result.append((pos, maxChar + 1)) }
    return result
}

func isValidDynamicPrecedence(_ s: String) -> Bool {
    if s == "10" || s == "-10" { return true }
    if let v = Int(s), v >= -9 && v <= 9 { return true }
    return false
}

func rangeEdges(from: TokenBuildState, to: TokenBuildState, low: Int, hi: Int) {
    var low = low
    let astral = 0x10000, gapStart = 0xd800, gapEnd = 0xe000, maxChar = 0x10ffff
    let lowSurrB = 0xdc00, highSurrB = 0xdfff
    if low < astral {
        if low < gapStart { from.edge(low, min(hi, gapStart), to) }
        if hi > gapEnd { from.edge(max(low, gapEnd), min(hi, maxChar + 1), to) }
        low = astral
    }
    if hi <= astral { return }
    let lowStr = String(UnicodeScalar(low)!)
    let hiStr = String(UnicodeScalar(hi - 1)!)
    let lowA = Int(lowStr.utf16[lowStr.utf16.startIndex])
    let lowB: Int
    if lowStr.utf16.count > 1 { lowB = Int(lowStr.utf16[lowStr.utf16.index(after: lowStr.utf16.startIndex)]) } else { lowB = 0 }
    let hiA = Int(hiStr.utf16[hiStr.utf16.startIndex])
    let hiB: Int
    if hiStr.utf16.count > 1 { hiB = Int(hiStr.utf16[hiStr.utf16.index(after: hiStr.utf16.startIndex)]) } else { hiB = 0 }
    if lowA == hiA {
        let hop = TokenBuildState()
        from.edge(lowA, lowA + 1, hop)
        hop.edge(lowB, hiB + 1, to)
    } else {
        var midStart = lowA, midEnd = hiA
        if lowB > lowSurrB {
            midStart += 1
            let hop = TokenBuildState()
            from.edge(lowA, lowA + 1, hop)
            hop.edge(lowB, highSurrB + 1, to)
        }
        if hiB < highSurrB {
            midEnd -= 1
            let hop = TokenBuildState()
            from.edge(hiA, hiA + 1, hop)
            hop.edge(lowSurrB, hiB + 1, to)
        }
        if midStart <= midEnd {
            let hop = TokenBuildState()
            from.edge(midStart, midEnd + 1, hop)
            hop.edge(lowSurrB, highSurrB + 1, to)
        }
    }
}

class FinishStateContext {
    var sharedActions: [SharedActions] = []
    let tokenizers: [Any]
    let data: DataBuilder
    var stateArray: [UInt32]
    let skipData: [Int]
    let skipInfo: [SkipInfo]
    let states: [State]
    let builder: Builder
    
    init(tokenizers: [Any], data: DataBuilder, stateArray: [UInt32], skipData: [Int], skipInfo: [SkipInfo], states: [State], builder: Builder) {
        self.tokenizers = tokenizers
        self.data = data
        self.stateArray = stateArray
        self.skipData = skipData
        self.skipInfo = skipInfo
        self.states = states
        self.builder = builder
    }
    
    func findSharedActions(_ state: State) -> SharedActions? {
        if state.actions.count < MinSharedActions { return nil }
        var found: SharedActions?
        for shared in sharedActions {
            if (found == nil || shared.actions.count > found!.actions.count) &&
                shared.actions.allSatisfy({ a in state.actions.contains(where: { b in actionEq(a, b) }) }) {
                found = shared
            }
        }
        if let f = found { return f }
        var maxActions: [Any]?
        for i in (state.id + 1)..<states.count {
            let other = states[i]
            if other.defaultReduce != nil || other.actions.count < MinSharedActions { continue }
            var fill = 0
            var scratch: [Any] = []
            for a in state.actions {
                for b in other.actions {
                    if actionEq(a, b) {
                        scratch.append(a)
                        fill += 1
                    }
                }
            }
            if fill >= MinSharedActions && (maxActions == nil || maxActions!.count < fill) {
                maxActions = scratch
            }
        }
        guard let max = maxActions else { return nil }
        let result = SharedActions(actions: max, addr: storeActions(max, skipReduce: -1, shared: nil))
        sharedActions.append(result)
        return result
    }
    
    func storeActions(_ actions: [Any], skipReduce: Int, shared: SharedActions?) -> Int {
        if skipReduce < 0 && shared != nil && shared!.actions.count == actions.count {
            return shared!.addr
        }
        var data: [Int] = []
        for action in actions {
            if let s = shared, s.actions.contains(where: { actionEq($0, action) }) { continue }
            if let shift = action as? Shift {
                data.append(shift.term.id)
                data.append(shift.target.id)
                data.append(0)
            } else if let reduce = action as? Reduce {
                let code = reduceAction(reduce.rule, skipInfo)
                if code != skipReduce {
                    data.append(reduce.term.id)
                    data.append(code & Action.valueMask)
                    data.append(code >> 16)
                }
            }
        }
        data.append(Seq.end)
        if skipReduce > -1 {
            data.append(Seq.other)
            data.append(skipReduce & Action.valueMask)
            data.append(skipReduce >> 16)
        } else if let s = shared {
            data.append(Seq.next)
            data.append(s.addr & 0xffff)
            data.append(s.addr >> 16)
        } else {
            data.append(Seq.done)
        }
        return self.data.storeArray(data)
    }
    
    func finish(_ state: State, isSkip: Bool, forcedReduce: Int) {
        let b = builder
        let skipID = b.skipRules.firstIndex(where: { $0 === state.skip }) ?? 0
        let skipTable = skipData[skipID]
        let skipTerms = skipInfo[skipID].startTokens
        
        let defaultReduce = state.defaultReduce != nil ? reduceAction(state.defaultReduce!, skipInfo) : 0
        var flags: UInt32 = isSkip ? UInt32(StateFlag.skipped) : 0
        
        var skipReduce = -1
        var shared: SharedActions? = nil
        if defaultReduce == 0 {
            if isSkip {
                for action in state.actions {
                    if let reduce = action as? Reduce, reduce.term.eof {
                        skipReduce = reduceAction(reduce.rule, skipInfo)
                    }
                }
            }
            if skipReduce < 0 {
                shared = findSharedActions(state)
            }
        }
        
        if state.set.contains(where: { $0.rule.name.top && $0.pos == $0.rule.parts.count }) {
            flags |= UInt32(StateFlag.accepting)
        }
        
        var external: [Any] = []
        for i in 0..<(state.actions.count + skipTerms.count) {
            let term: Term
            if i < state.actions.count {
                if let s = state.actions[i] as? Shift { term = s.term }
                else if let r = state.actions[i] as? Reduce { term = r.term }
                else { continue }
            } else {
                term = skipTerms[i - state.actions.count]
            }
            var currentTerm: Term = term
            while true {
                if let orig = b.tokenOrigins[currentTerm.name] {
                    if let spec = orig.spec {
                        currentTerm = spec
                        continue
                    }
                    if let ext = orig.external as? ExternalTokenSetClass {
                        if !external.contains(where: { ($0 as AnyObject) === (ext as AnyObject) }) {
                            external.append(ext)
                        }
                    }
                }
                break
            }
        }
        
        var tokenizerMask: UInt32 = 0
        for i in 0..<tokenizers.count {
            let tok = tokenizers[i]
            if external.contains(where: { ($0 as AnyObject) === (tok as AnyObject) }) ||
                (tok as? TokenGroupSpec)?.groupID == state.tokenGroup {
                tokenizerMask |= 1 << i
            }
        }
        
        let base = state.id * ParseState.size
        stateArray[base + ParseState.flags] = flags
        stateArray[base + ParseState.actions] = UInt32(storeActions(defaultReduce != 0 ? [] : state.actions, skipReduce: skipReduce, shared: shared))
        stateArray[base + ParseState.skip] = UInt32(skipTable)
        stateArray[base + ParseState.tokenizerMask] = tokenizerMask
        stateArray[base + ParseState.defaultReduce] = UInt32(defaultReduce)
        stateArray[base + ParseState.forcedReduce] = UInt32(forcedReduce)
    }
}

class TokenGroupSpec {
    var tokens: [Term]
    let groupID: Int
    init(tokens: [Term], groupID: Int) {
        self.tokens = tokens
        self.groupID = groupID
    }
}

protocol Namespace {
    func resolve(_ expr: NameExpression, builder: Builder) -> [Parts]
}

class TokenArg {
    let name: String
    let expr: Expression
    let scope: [TokenArg]
    init(name: String, expr: Expression, scope: [TokenArg]) {
        self.name = name
        self.expr = expr
        self.scope = scope
    }
}

class BuildingRule {
    let name: String
    let start: TokenBuildState
    let to: TokenBuildState
    let args: [Expression]
    init(name: String, start: TokenBuildState, to: TokenBuildState, args: [Expression]) {
        self.name = name
        self.start = start
        self.to = to
        self.args = args
    }
}

class TokenSet {
    let startState = TokenBuildState()
    var built: [BuiltRule] = []
    var building: [BuildingRule] = []
    var rules: [RuleDeclaration]
    var byDialect: [Int: [Term]] = [:]
    var precedenceRelations: [(term: Term, after: [Term])] = []
    
    weak var b: Builder?
    let ast: Any?
    
    init(b: Builder, ast: Any?) {
        self.b = b
        self.ast = ast
        self.rules = (ast as? TokenDeclaration)?.rules ?? (ast as? LocalTokenDeclaration)?.rules ?? []
        for rule in self.rules {
            b.unique(rule.id)
        }
    }
    
    func getToken(_ expr: NameExpression) -> Term? {
        for built in built {
            if built.matches(expr) { return built.term }
        }
        guard let b = b else { return nil }
        let name = expr.id.name
        guard let rule = rules.first(where: { $0.id.name == name }) else { return nil }
        let info = b.nodeInfo(rule.props, allow: "d", defaultName: name, args: expr.args, params: rule.params.count != expr.args.count ? [] : rule.params)
        let term = b.makeTerminal(expr.toString(), nodeName: info.name, props: info.props)
        if let dialect = info.dialect {
            if byDialect[dialect] == nil { byDialect[dialect] = [] }
            byDialect[dialect]!.append(term)
        }
        if (term.nodeType || info.exported != nil) && rule.params.isEmpty {
            if !term.nodeType { term.preserve = true }
            b.namedTerms[info.exported ?? name] = term
        }
        buildRule(rule, expr: expr, from: startState, to: TokenBuildState(accepting: [term]))
        built.append(BuiltRule(id: name, args: expr.args, term: term))
        return term
    }
    
    func buildRule(_ rule: RuleDeclaration, expr: NameExpression, from: TokenBuildState, to: TokenBuildState, args: [TokenArg] = []) {
        guard let b = b else { return }
        let name = expr.id.name
        if rule.params.count != expr.args.count {
            b.raise("Incorrect number of arguments for token '\(name)'", pos: expr.start)
        }
        if let found = building.first(where: { $0.name == name && exprsEq($0.args, expr.args) }) {
            if found.to === to {
                from.nullEdge(found.start)
                return
            }
            let lastIdx = self.building.lastIndex(where: { $0.name == name })!
            let slice = self.building[lastIdx...].map { $0.name }
            b.raise("Invalid (non-tail) recursion in token rules: \(slice.joined(separator: " -> "))", pos: expr.start)
        }
        b.used(rule.id.name)
        let start = TokenBuildState()
        from.nullEdge(start)
        building.append(BuildingRule(name: name, start: start, to: to, args: expr.args))
        build(b.substituteArgs(rule.expr, args: expr.args, params: rule.params), from: start, to: to, args: expr.args.enumerated().map { TokenArg(name: rule.params[$0].name, expr: $1, scope: args) })
        building.removeLast()
    }
    
    func build(_ expr: Expression, from: TokenBuildState, to: TokenBuildState, args: [TokenArg]) {
        guard let b = b else { return }
        if let nameExpr = expr as? NameExpression {
            let name = nameExpr.id.name
            if let arg = args.first(where: { $0.name == name }) {
                return build(arg.expr, from: from, to: to, args: arg.scope)
            }
            var rule: RuleDeclaration?
            for lt in b.localTokens {
                if let r = lt.rules.first(where: { $0.id.name == name }) { rule = r; break }
            }
            if rule == nil {
                rule = b.tokens.rules.first(where: { $0.id.name == name })
            }
            guard let foundRule = rule else {
                b.raise("Reference to token rule '\(name)', which isn't found", pos: expr.start)
            }
            buildRule(foundRule, expr: nameExpr, from: from, to: to, args: args)
        } else if let charClass = expr as? CharClass {
            if let ranges = CharClasses[charClass.type] {
                for (a, bb) in ranges {
                    from.edge(a, bb, to)
                }
            }
        } else if expr is ChoiceExpression {
            for choice in (expr as! ChoiceExpression).exprs {
                build(choice, from: from, to: to, args: args)
            }
        } else if isEmpty(expr) {
            from.nullEdge(to)
        } else if let seq = expr as? SequenceExpression {
            if seq.markers.contains(where: { !$0.isEmpty }) {
                b.raise("Conflict marker in token expression", pos: seq.markers.first(where: { !$0.isEmpty })![0].start)
            }
            var currentFrom = from
            for (i, e) in seq.exprs.enumerated() {
                let next = i == seq.exprs.count - 1 ? to : TokenBuildState()
                build(e, from: currentFrom, to: next, args: args)
                currentFrom = next
            }
        } else if let repeatExpr = expr as? RepeatExpression {
            if repeatExpr.kind == "*" {
                let loop = TokenBuildState()
                from.nullEdge(loop)
                build(repeatExpr.expr, from: loop, to: loop, args: args)
                loop.nullEdge(to)
            } else if repeatExpr.kind == "+" {
                let loop = TokenBuildState()
                build(repeatExpr.expr, from: from, to: loop, args: args)
                build(repeatExpr.expr, from: loop, to: loop, args: args)
                loop.nullEdge(to)
            } else {
                from.nullEdge(to)
                build(repeatExpr.expr, from: from, to: to, args: args)
            }
        } else if let setExpr = expr as? SetExpression {
            let ranges = setExpr.inverted ? invertRanges(setExpr.ranges) : setExpr.ranges
            for (a, bb) in ranges {
                rangeEdges(from: from, to: to, low: a, hi: bb)
            }
        } else if let lit = expr as? LiteralExpression {
            var currentFrom = from
            let value = lit.value
            for (i, ch) in value.utf16.enumerated() {
                let next = i == value.utf16.count - 1 ? to : TokenBuildState()
                currentFrom.edge(Int(ch), Int(ch) + 1, next)
                currentFrom = next
            }
        } else if expr is AnyExpression {
            let mid = TokenBuildState()
            from.edge(0, 0xdc00, to)
            from.edge(0xdc00, 0x10001, to)
            from.edge(0xd800, 0xdc00, mid)
            mid.edge(0xdc00, 0xe000, to)
        } else {
            b.raise("Unrecognized expression type in token")
        }
    }
    
    func takePrecedences() {
        var rel: [(term: Term, after: [Term])] = []
        if let ast = self.ast as? TokenDeclaration {
            for group in ast.precedences {
                var prev: [Term] = []
                for item in group.items {
                    var level: [Term] = []
                    if let nameExpr = item as? NameExpression {
                        for built in self.built {
                            if nameExpr.args.isEmpty ? built.id == nameExpr.id.name : built.matches(nameExpr) {
                                level.append(built.term)
                            }
                        }
                    } else if let lit = item as? LiteralExpression {
                        let id = "\"\(lit.value)\""
                        if let found = built.first(where: { $0.id == id }) {
                            level.append(found.term)
                        }
                    }
                    if level.isEmpty {
                        b?.warn("Precedence specified for unknown token \(item)", pos: item.start)
                    }
                    for term in level {
                        addRel(&rel, term, prev)
                    }
                    prev = prev + level
                }
            }
        }
        self.precedenceRelations = rel
    }
    
    func precededBy(_ a: Term, _ b: Term) -> Bool {
        return precedenceRelations.contains(where: { $0.term === a && $0.after.contains(where: { $0 === b }) })
    }
    
    func buildPrecTable(_ softConflicts: [ConflictSpec]) -> [Int] {
        var precTable: [Int] = []
        var rel = precedenceRelations
        for conflict in softConflicts {
            if conflict.soft != 0 {
                var a = conflict.a, b = conflict.b
                if conflict.soft < 0 { swap(&a, &b) }
                if !rel.contains(where: { $0.term === a }) || !rel.contains(where: { $0.term === b }) { continue }
                addRel(&rel, b, [a])
                addRel(&rel, a, [])
            }
        }
        while !rel.isEmpty {
            var found = false
            for i in 0..<rel.count {
                if rel[i].after.allSatisfy({ precTable.contains($0.id) }) {
                    precTable.append(rel[i].term.id)
                    if rel.count == 1 { found = true; break }
                    rel[i] = rel[rel.count - 1]
                    rel.removeLast()
                    found = true
                    break
                }
            }
            if !found {
                b?.raise("Cyclic token precedence relation between \(rel.map { String(describing: $0.term) }.joined(separator: ", "))")
            }
        }
        return precTable
    }
}

class ExternalTokenSetClass {
    let tokens: [String: Term]
    weak var b: Builder?
    let ast: ExternalTokenDeclaration
    
    init(b: Builder, ast: ExternalTokenDeclaration) {
        self.b = b
        self.ast = ast
        self.tokens = gatherExtTokens(b, ast.tokens)
        for (_, term) in self.tokens {
            b.tokenOrigins[term.name] = TokenOrigin(spec: nil, external: self, group: nil)
        }
    }
    
    func getToken(_ expr: NameExpression) -> Term? {
        return findExtToken(b!, tokens, expr)
    }
    
    func checkConflicts(_ states: [State], _ skipInfo: [SkipInfo]) {
        guard let b = b else { return }
        var conflicting: [Term] = []
        for id in ast.conflicts {
            guard let term = b.namedTerms[id.name] else {
                b.warn("Unknown conflict term '\(id.name)'")
                continue
            }
            if !term.terminal {
                b.warn("Term '\(id.name)' isn't a terminal and cannot be used in a token conflict.")
            } else if tokens[id.name] != nil {
                b.warn("External token set specifying a conflict with one of its own tokens ('\(id.name)')")
            } else {
                conflicting.append(term)
            }
        }
        if !conflicting.isEmpty {
            for state in states {
                let si = b.skipRules.firstIndex(where: { $0 === state.skip }) ?? 0
                let skip = skipInfo[si].startTokens
                var relevant = false
                var conflict: Term?
                for i in 0..<(state.actions.count + skip.count) {
                    let term: Term
                    if i < state.actions.count {
                        if let s = state.actions[i] as? Shift { term = s.term }
                        else if let r = state.actions[i] as? Reduce { term = r.term }
                        else { continue }
                    } else {
                        term = skip[i - state.actions.count]
                    }
                    if tokens[term.name] != nil {
                        relevant = true
                    } else if conflicting.contains(where: { $0 === term }) {
                        conflict = term
                    }
                }
                if relevant, let c = conflict {
                    b.raise("Tokens from external group used together with conflicting token '\(c.name)'\nAfter: \(state.set[0].trail())", pos: ast.start)
                }
            }
        }
    }
    
    func createExternal() -> ExternalTokenizer? {
        guard let b = b, let extTokenizer = b.options.externalTokenizer else { return nil }
        return extTokenizer(ast.id.name, b.termTable)
    }
}

class ExternalSpecializerClass {
    var term: Term?
    let tokens: [String: Term]
    weak var b: Builder?
    let ast: ExternalSpecializeDeclaration
    
    init(b: Builder, ast: ExternalSpecializeDeclaration) {
        self.b = b
        self.ast = ast
        self.tokens = gatherExtTokens(b, ast.tokens)
    }
    
    func finish() {
        guard let b = b else { return }
        let terms = b.normalizeExpr(ast.token)
        if terms.count != 1 || terms[0].terms.count != 1 || !terms[0].terms[0].terminal {
            b.raise("The token expression to '@external \(ast.type)' must resolve to a token", pos: ast.token.start)
        }
        self.term = terms[0].terms[0]
        for (_, t) in tokens {
            b.tokenOrigins[t.name] = TokenOrigin(spec: self.term, external: self, group: nil)
        }
    }
    
    func getToken(_ expr: NameExpression) -> Term? {
        return findExtToken(b!, tokens, expr)
    }
}

struct TokenOrigin {
    let spec: Term?
    let external: AnyObject?
    let group: AnyObject?
}

struct ConflictSpec {
    let a: Term
    let b: Term
    let soft: Int
    let exampleA: String
    let exampleB: String?
}

class MainTokenSet: TokenSet {
    var explicitConflicts: [(a: Term, b: Term)] = []
    
    init(b: Builder, ast: TokenDeclaration?) {
        super.init(b: b, ast: ast)
    }
    
    func getLiteral(_ expr: LiteralExpression) -> Term? {
        let id = "\"\(expr.value)\""
        for built in built {
            if built.id == id { return built.term }
        }
        guard let b = b else { return nil }
        var name: String? = nil
        var props: Props = [:]
        var dialect: Int? = nil
        var exported: String? = nil
        if let decl = (self.ast as? TokenDeclaration)?.literals.first(where: { $0.literal == expr.value }) {
            let info = b.nodeInfo(decl.props, allow: "da", defaultName: expr.value, args: [], params: [])
            name = info.name
            props = info.props
            dialect = info.dialect
            exported = info.exported
        }
        let term = b.makeTerminal(id, nodeName: name, props: props)
        if let d = dialect {
            if byDialect[d] == nil { byDialect[d] = [] }
            byDialect[d]!.append(term)
        }
        if let exp = exported { b.namedTerms[exp] = term }
        build(expr, from: startState, to: TokenBuildState(accepting: [term]), args: [])
        built.append(BuiltRule(id: id, args: [], term: term))
        return term
    }
    
    func takeConflicts() {
        guard let ast = self.ast as? TokenDeclaration else { return }
        let resolve = { (expr: Expression) -> Term? in
            if let nameExpr = expr as? NameExpression {
                for built in self.built {
                    if built.matches(nameExpr) { return built.term }
                }
            } else if let lit = expr as? LiteralExpression {
                let id = "\"\(lit.value)\""
                if let found = self.built.first(where: { $0.id == id }) { return found.term }
            }
            self.b?.warn("Conflict specified for unknown token \(expr)", pos: expr.start)
            return nil
        }
        for c in ast.conflicts {
            guard let a = resolve(c.a), let b = resolve(c.b) else { continue }
            if a.id < b.id {
                explicitConflicts.append((a: b, b: a))
            } else {
                explicitConflicts.append((a: a, b: b))
            }
        }
    }
    
    func buildTokenGroups(_ states: [State], _ skipInfo: [SkipInfo], _ startID: Int) -> (tokenGroups: [TokenGroupSpec], tokenPrec: [Int], tokenData: [UInt16]) {
        guard let b = b else { fatalError("Builder is nil") }
        let tokens = startState.compile()
        if !tokens.accepting.isEmpty {
            let name = tokens.accepting[0].name
            b.raise("Grammar contains zero-length tokens (in '\(name)')", pos: rules.first(where: { $0.id.name == name })?.start ?? 0)
        }
        let checkTogetherFn = checkTogether(states, b, skipInfo)
        var allConflicts = tokens.findConflicts(occurTogether: checkTogetherFn).filter { c in
            !precededBy(c.a, c.b) && !precededBy(c.b, c.a)
        }
        for ec in explicitConflicts {
            if !allConflicts.contains(where: { $0.a === ec.a && $0.b === ec.b }) {
                allConflicts.append(Conflict(a: ec.a, b: ec.b, soft: 0, exampleA: "", exampleB: nil))
            }
        }
        let softConflicts = allConflicts.filter { $0.soft != 0 }
        let hardConflicts = allConflicts.filter { $0.soft == 0 }
        var errors: [(conflict: Conflict, error: String)] = []
        var groups: [TokenGroupSpec] = []
        for state in states {
            if state.defaultReduce != nil || state.tokenGroup > -1 { continue }
            var terms: [Term] = []
            var incompatible: [Term] = []
            let skip = skipInfo[b.skipRules.firstIndex(where: { $0 === state.skip }) ?? 0].startTokens
            for term in skip {
                if state.actions.contains(where: { a in
                    if let s = a as? Shift { return s.term === term }
                    if let r = a as? Reduce { return r.term === term }
                    return false
                }) {
                    b.raise("Use of token \(term.name) conflicts with skip rule")
                }
            }
            var stateTerms: [Term] = []
            for i in 0..<(state.actions.count + skip.count) {
                let baseTerm: Term
                if i < state.actions.count {
                    if let s = state.actions[i] as? Shift { baseTerm = s.term }
                    else if let r = state.actions[i] as? Reduce { baseTerm = r.term }
                    else { continue }
                } else {
                    baseTerm = skip[i - state.actions.count]
                }
                let orig = b.tokenOrigins[baseTerm.name]
                if let spec = orig?.spec {
                    addToSet(&stateTerms, spec)
                } else if orig?.external != nil { continue }
                else { addToSet(&stateTerms, baseTerm) }
            }
            if stateTerms.isEmpty { continue }
            for term in stateTerms {
                for conflict in hardConflicts {
                    let conflicting: Term? = conflict.a === term ? conflict.b : conflict.b === term ? conflict.a : nil
                    guard let c = conflicting else { continue }
                    if stateTerms.contains(where: { $0 === c }) && !errors.contains(where: { $0.conflict.a === conflict.a && $0.conflict.b === conflict.b }) {
                        let example = conflict.exampleA.isEmpty ? "" : " (example: \(conflict.exampleA)\(conflict.exampleB != nil ? " vs \(conflict.exampleB!)" : ""))"
                        errors.append((conflict: conflict, error: "Overlapping tokens \(term.name) and \(c.name) used in same context\(example)\nAfter: \(state.set[0].trail())"))
                    }
                    addToSet(&terms, term)
                    addToSet(&incompatible, c)
                }
            }
            var tokenGroup: TokenGroupSpec? = nil
            for group in groups {
                if incompatible.contains(where: { group.tokens.contains($0) }) { continue }
                for term in terms {
                    if !group.tokens.contains(where: { $0 === term }) { group.tokens.append(term) }
                }
                tokenGroup = group
                break
            }
            if tokenGroup == nil {
                tokenGroup = TokenGroupSpec(tokens: terms, groupID: groups.count + startID)
                groups.append(tokenGroup!)
            }
            state.tokenGroup = tokenGroup!.groupID
        }
        if !errors.isEmpty {
            b.raise(errors.map { $0.error }.joined(separator: "\n\n"))
        }
        if groups.count + startID > 16 {
            b.raise("Too many different token groups (\(groups.count)) to represent them as a 16-bit bitfield")
        }
        let precTable = buildPrecTable(softConflicts.map { ConflictSpec(a: $0.a, b: $0.b, soft: $0.soft, exampleA: $0.exampleA, exampleB: $0.exampleB) })
        let tokenData = tokens.toArray(groupMasks: buildTokenMasks(groups), precedence: precTable)
        return (tokenGroups: groups, tokenPrec: precTable, tokenData: tokenData)
    }
}

class LocalTokenSet: TokenSet {
    var fallback: Term? = nil
    
    init(b: Builder, ast: LocalTokenDeclaration) {
        super.init(b: b, ast: ast)
        if let fb = ast.fallback { b.unique(fb.id) }
    }
    
    override func getToken(_ expr: NameExpression) -> Term? {
        guard let b = b else { return nil }
        if let fb = self.ast as? LocalTokenDeclaration, let fallbackDecl = fb.fallback, fallbackDecl.id.name == expr.id.name {
            if !expr.args.isEmpty { b.raise("Incorrect number of arguments for \(expr.id.name)", pos: expr.start) }
            if self.fallback == nil {
                let info = b.nodeInfo(fallbackDecl.props, allow: "", defaultName: expr.id.name, args: [], params: [])
                let term = b.makeTerminal(expr.id.name, nodeName: info.name, props: info.props)
                if term.nodeType || info.exported != nil {
                    if !term.nodeType { term.preserve = true }
                    b.namedTerms[info.exported ?? expr.id.name] = term
                }
                b.used(expr.id.name)
                self.fallback = term
            }
            if let t = self.fallback, b.tokenOrigins[t.name] == nil {
                b.tokenOrigins[t.name] = TokenOrigin(spec: nil, external: nil, group: self)
            }
            return self.fallback
        }
        let term = super.getToken(expr)
        if let t = term, b.tokenOrigins[t.name] == nil {
            b.tokenOrigins[t.name] = TokenOrigin(spec: nil, external: nil, group: self)
        }
        return term
    }
    
    func buildLocalGroup(_ states: [State], _ skipInfo: [SkipInfo], _ id: Int) -> Any {
        let tokens = startState.compile()
        if !tokens.accepting.isEmpty {
            b?.raise("Grammar contains zero-length tokens (in '\(tokens.accepting[0].name)')", pos: rules.first(where: { $0.id.name == tokens.accepting[0].name })?.start ?? 0)
        }
        for c in tokens.findConflicts(occurTogether: { _, _ in true }) {
            if !precededBy(c.a, c.b) && !precededBy(c.b, c.a) {
                let example = c.exampleA.isEmpty ? "" : " (example: \(c.exampleA))"
                b?.raise("Overlapping tokens \(c.a.name) and \(c.b.name) in local token group\(example)")
            }
        }
        for state in states {
            if state.defaultReduce != nil { continue }
            var usesThis: Term? = nil
            var usesOther: Term? = nil
            for action in state.actions {
                if let s = action as? Shift {
                    var orig = b?.tokenOrigins[s.term.name]
                    while let spec = orig?.spec { orig = b?.tokenOrigins[spec.name] }
                    if orig?.group as? LocalTokenSet === self { usesThis = s.term }
                    else { usesOther = s.term }
                } else if let r = action as? Reduce {
                    var orig = b?.tokenOrigins[r.term.name]
                    while let spec = orig?.spec { orig = b?.tokenOrigins[spec.name] }
                    if orig?.group as? LocalTokenSet === self { usesThis = r.term }
                    else { usesOther = r.term }
                }
            }
            if usesThis != nil {
                if usesOther != nil {
                    b?.raise("Tokens from a local token group used together with other tokens (\(usesThis!.name) with \(usesOther!.name))")
                }
                state.tokenGroup = id
            }
        }
        return id
    }
}

class Builder {
    var ast: GrammarDeclaration!
    var input: GrammarInput!
    var terms = TermSet()
    var tokens: MainTokenSet!
    var localTokens: [LocalTokenSet] = []
    var externalTokens: [ExternalTokenSetClass] = []
    var externalSpecializers: [ExternalSpecializerClass] = []
    var specialized: [String: [[String: Any]]] = [:]
    var tokenOrigins: [String: TokenOrigin] = [:]
    var rules: [Rule] = []
    var built: [BuiltRule] = []
    var ruleNames: [String: Identifier?] = [:]
    var namedTerms: [String: Term] = [:]
    var termTable: [String: Int] = [:]
    var knownProps: [String: (prop: Any, source: (name: String, from: String?))] = [:]
    var dialects: [String] = []
    var dynamicRulePrecedences: [(rule: Term, prec: Int)] = []
    var definedGroups: [(name: Term, group: String, rule: RuleDeclaration)] = []
    var astRules: [(skip: Term, rule: RuleDeclaration)] = []
    var currentSkip: [Term] = []
    var skipRules: [Term] = []
    let options: BuildOptions
    
    init(_ text: String, options: BuildOptions) {
        self.options = options
        self.input = GrammarInput(string: text, fileName: options.fileName)
        self.ast = input!.parse()
        self.dialects = ast.dialects.map { $0.name }
        self.tokens = MainTokenSet(b: self, ast: ast.tokens)
        self.localTokens = ast.localTokens.map { LocalTokenSet(b: self, ast: $0) }
        self.externalTokens = ast.externalTokens.map { ExternalTokenSetClass(b: self, ast: $0) }
        self.externalSpecializers = ast.externalSpecializers.map { ExternalSpecializerClass(b: self, ast: $0) }
        
        let noSkip = newName("%noskip", nodeName: true)
        currentSkip.append(noSkip)
        defineRule(noSkip, choices: [])
        let mainSkip = ast.mainSkip != nil ? newName("%mainskip", nodeName: true) : noSkip
        var scopedSkip: [Term] = []
        var topRules: [(rule: RuleDeclaration, skip: Term)] = []
        for rule in ast.rules { astRules.append((skip: mainSkip, rule: rule)) }
        for rule in ast.topRules { topRules.append((rule: rule, skip: mainSkip)) }
        for scoped in ast.scopedSkip {
            var skip = noSkip
            if let found = ast.scopedSkip.firstIndex(where: { exprEq($0.expr, scoped.expr) }), found < scopedSkip.count {
                skip = scopedSkip[found]
            } else if ast.mainSkip != nil && exprEq(scoped.expr, ast.mainSkip!) {
                skip = mainSkip
            } else if !isEmpty(scoped.expr) {
                skip = newName("%skip", nodeName: true)
            }
            scopedSkip.append(skip)
            for rule in scoped.rules { astRules.append((skip: skip, rule: rule)) }
            for rule in scoped.topRules { topRules.append((rule: rule, skip: skip)) }
        }
        for r in astRules { unique(r.rule.id) }
        skipRules = mainSkip === noSkip ? [mainSkip] : [noSkip, mainSkip]
        if mainSkip !== noSkip { defineRule(mainSkip, choices: normalizeExpr(ast.mainSkip!)) }
        for i in 0..<ast.scopedSkip.count {
            let skip = scopedSkip[i]
            if !skipRules.contains(where: { $0 === skip }) {
                skipRules.append(skip)
                if skip !== noSkip { defineRule(skip, choices: normalizeExpr(ast.scopedSkip[i].expr)) }
            }
        }
        currentSkip.removeLast()
        for tr in topRules.sorted(by: { $0.rule.start < $1.rule.start }) {
            unique(tr.rule.id)
            used(tr.rule.id.name)
            currentSkip.append(tr.skip)
            let info = nodeInfo(tr.rule.props, allow: "a", defaultName: tr.rule.id.name, args: [], params: [], expr: tr.rule.expr)
            let term = terms.makeTop(nodeName: info.name, props: info.props)
            namedTerms[info.name ?? tr.rule.id.name] = term
            defineRule(term, choices: normalizeExpr(tr.rule.expr))
            currentSkip.removeLast()
        }
        for ext in externalSpecializers { ext.finish() }
        for r in astRules {
            if ruleNames[r.rule.id.name] != nil && isExported(r.rule) && r.rule.params.isEmpty {
                _ = buildRule(r.rule, args: [], skip: r.skip, inline: false)
                if let seq = r.rule.expr as? SequenceExpression, seq.exprs.isEmpty { used(r.rule.id.name) }
            }
        }
        for (_, value) in ruleNames {
            if let v = value { warn("Unused rule '\(v.name)'", pos: v.start) }
        }
        tokens.takePrecedences()
        tokens.takeConflicts()
        for lt in localTokens { lt.takePrecedences() }
        for dg in definedGroups { defineGroup(name: dg.name, group: dg.group, rule: dg.rule) }
        checkGroups()
    }
    
    func unique(_ id: Identifier) {
        if ruleNames[id.name] != nil { raise("Duplicate definition of rule '\(id.name)'", pos: id.start) }
        ruleNames[id.name] = id
    }
    
    func used(_ name: String) { ruleNames[name] = nil }
    
    func newName(_ base: String, nodeName: Any? = nil, props: Props = [:]) -> Term {
        for i in (nodeName != nil ? 0 : 1)... {
            let name = i == 0 ? base : "\(base)-\(i)"
            if terms.names[name] == nil {
                return terms.makeNonTerminal(name, nodeName: nodeName as? String ?? nil, props: props)
            }
        }
        fatalError("Could not create unique name for \(base)")
    }
    
    func prepareParser() -> (states: [UInt32], stateData: [UInt16], goto: [UInt16], nodeNames: String, nodeProps: [[String: Any]]?, skippedTypes: [Int], maxTerm: Int, repeatNodeCount: Int, tokenizers: [Any], tokenData: String, topRules: [String: [Int]], dialects: [String: Int], dynamicPrecedences: [Int: Int]?, specialized: [Any], tokenPrec: Int, termNames: [Int: String]) {
         let simplifiedRules = simplifyRules(rules, Array(skipRules) + terms.tops)
         let (nodeTypes, termNames, minRepeatTerm, maxTerm) = terms.finish(rules: simplifiedRules)
        for (prop, t) in namedTerms { termTable[prop] = t.id }
        var startTerms = Array(terms.tops)
        let first = computeFirstSets(terms: terms)
        var skipInfo: [SkipInfo] = []
        for (id, name) in skipRules.enumerated() {
            var skip: [Term] = []
            var startTokens: [Term] = []
            var rules: [Rule] = []
            for rule in name.rules {
                if rule.parts.isEmpty { continue }
                let start = rule.parts[0]
                for t in (start.terminal ? [start] : (first[start.name] ?? []).compactMap({ $0 })) {
                    if !startTokens.contains(where: { $0 === t }) { startTokens.append(t) }
                }
                if start.terminal && rule.parts.count == 1 && !rules.contains(where: { $0 !== rule && $0.parts[0] === start }) {
                    skip.append(start)
                } else { rules.append(rule) }
            }
            name.rules = rules
            if !rules.isEmpty { startTerms.append(name) }
            skipInfo.append(SkipInfo(skip: skip, rule: rules.isEmpty ? nil : name, startTokens: startTokens, id: id))
        }
        let fullTable = buildFullAutomaton(terms: terms, startTerms: startTerms, first: first)
        let localTokenResults = localTokens.enumerated().map { (i, grp) in grp.buildLocalGroup(fullTable, skipInfo, i) }
        let (tokenGroups, tokenPrec, tokenData) = tokens.buildTokenGroups(fullTable, skipInfo, localTokens.count)
        for ext in externalTokens { ext.checkConflicts(fullTable, skipInfo) }
        let table = finishAutomaton(fullTable)
        let skipStateFn = findSkipStates(table, terms.tops)
        var specializedList: [Any] = []
        for ext in externalSpecializers { specializedList.append(ext) }
        for (name, entries) in specialized {
            specializedList.append(["token": terms.names[name] as Any, "table": buildSpecializeTable(entries)])
        }
        let tokStart = { (tokenizer: Any) -> Int in
            if let ext = tokenizer as? ExternalTokenSetClass { return ext.ast.start }
            if tokenizer is TokenGroupSpec { return (self.ast.tokens?.start ?? -1) }
            return -1
        }
        var tokenizers: [Any] = (tokenGroups as [Any]) + externalTokens
        tokenizers.sort { a, b in tokStart(a) < tokStart(b) }
        tokenizers += localTokenResults
        let data = DataBuilder()
        let skipData = skipInfo.map { info -> Int in
            var actions: [Int] = []
            for term in info.skip { actions.append(term.id); actions.append(0); actions.append(Action.stayFlag >> 16) }
            if let rule = info.rule {
                if let state = table.first(where: { $0.startRule?.id == rule.id }) {
                    for action in state.actions {
                        if let s = action as? Shift { actions.append(s.term.id); actions.append(state.id); actions.append(Action.gotoFlag >> 16) }
                    }
                }
            }
            actions.append(Seq.end); actions.append(Seq.done)
            return data.storeArray(actions)
        }
        var states = Array(repeating: UInt32(0), count: table.count * ParseState.size)
        let forceReductions = computeForceReductions(table, skipInfo)
        let finishCx = FinishStateContext(tokenizers: tokenizers, data: data, stateArray: states, skipData: skipData, skipInfo: skipInfo, states: table, builder: self)
        for s in table {
            finishCx.finish(s, isSkip: skipStateFn(s.id), forcedReduce: forceReductions[s.id])
        }
        states = finishCx.stateArray
        var dialectData: [String: Int] = [:]
        for i in 0..<dialects.count {
            dialectData[dialects[i]] = data.storeArray((tokens.byDialect[i] ?? []).map(\.id) + [Seq.end])
        }
        var dynamicPrecs: [Int: Int]? = nil
        if !dynamicRulePrecedences.isEmpty {
            dynamicPrecs = [:]
            for dp in dynamicRulePrecedences { dynamicPrecs![dp.rule.id] = dp.prec }
        }
        var topRuleData: [String: [Int]] = [:]
        for term in terms.tops {
            if let name = term.nodeName, let state = table.first(where: { $0.startRule?.id == term.id }) {
                topRuleData[name] = [state.id, term.id]
            }
        }
        let precTable = data.storeArray(tokenPrec + [Seq.end])
        let (nodeProps, skippedTypes) = gatherNodeProps(nodeTypes: nodeTypes)
        
        let gotoTable = computeGotoTable(table)
        
        return (
            states: states,
            stateData: data.finish(),
            goto: gotoTable,
            nodeNames: nodeTypes.filter { $0.id < minRepeatTerm }.compactMap(\.nodeName).joined(separator: " "),
            nodeProps: nodeProps,
            skippedTypes: skippedTypes,
            maxTerm: maxTerm,
            repeatNodeCount: nodeTypes.count - minRepeatTerm,
            tokenizers: tokenizers,
            tokenData: encodeArray(tokenData.map { Int($0) }),
            topRules: topRuleData,
            dialects: dialectData,
            dynamicPrecedences: dynamicPrecs,
            specialized: specializedList,
            tokenPrec: precTable,
            termNames: termNames
        )
    }
    
    func getParser() -> LRParser {
        let result = prepareParser()
        var specialized: [SpecializerSpec] = []
        for item in result.specialized {
            if let ext = item as? ExternalSpecializerClass {
                guard let extTokenizer = options.externalSpecializer else {
                    fatalError("External specializer required for \(ext.ast.id.name)")
                }
                let fn = extTokenizer(ext.ast.id.name, termTable)
                let mask = ext.ast.type == "extend" ? Specialize.extend : Specialize.specialize
                specialized.append(SpecializerSpec(
                    term: ext.term?.id ?? -1,
                    get: { value, stack in (fn(value, stack) << 1) | mask },
                    external: fn,
                    extend: ext.ast.type == "extend"
                ))
            } else if let dict = item as? [String: Any], let token = dict["token"] as? Term, let table = dict["table"] as? [String: Int] {
                specialized.append(SpecializerSpec(
                    term: token.id,
                    get: { value, _ in table[value] ?? -1 },
                    external: nil,
                    extend: false
                ))
            }
        }
        
        var processedTokenizers: [Any] = []
        for tok in result.tokenizers {
            if let ext = tok as? ExternalTokenSetClass {
                if let t = ext.createExternal() {
                    processedTokenizers.append(t)
                } else {
                    processedTokenizers.append(-1)
                }
            } else if let grp = tok as? TokenGroupSpec {
                processedTokenizers.append(grp.groupID)
            } else {
                processedTokenizers.append(tok)
            }
        }
        
        var nodePropsFinal: [[Any]]? = nil
        if let rawProps = result.nodeProps {
            nodePropsFinal = rawProps.map { entry in
                let ep = entry
                let propName = ep["prop"] as! String
                let terms = ep["terms"] as! [Any]
                let known = knownProps[propName]!
                return [known.prop] + terms
            }
        }
        
        var context: ContextTracker<Any>? = nil
        if ast.context != nil {
            if let fn = options.contextTracker as? ((_: [String: Int]) -> ContextTracker<Any>) {
                context = fn(termTable)
            } else if let ct = options.contextTracker as? ContextTracker<Any> {
                context = ct
            }
        }
        
        let spec = ParserSpec(
            version: File.version,
            states: StringOrArray.uint32Array(result.states),
            stateData: StringOrArray.uint16Array(result.stateData),
            goto: StringOrArray.uint16Array(result.goto),
            nodeNames: result.nodeNames,
            maxTerm: result.maxTerm,
            repeatNodeCount: result.repeatNodeCount,
            nodeProps: nodePropsFinal,
            propSources: options.externalPropSource.map { fn in
                ast.externalPropSources.map { fn($0.id.name) }
            },
            skippedNodes: result.skippedTypes,
            tokenData: result.tokenData,
            tokenizers: processedTokenizers,
            topRules: result.topRules,
            context: context,
            dialects: result.dialects,
            dynamicPrecedences: result.dynamicPrecedences,
            specialized: specialized,
            tokenPrec: result.tokenPrec,
            termNames: result.termNames
        )
        return LRParser(spec: spec)
    }
    
    func gatherNonSkippedNodes() -> Set<Int> {
        var seen: Set<Int> = []
        var work: [Term] = []
        for t in terms.tops { seen.insert(t.id); work.append(t) }
        var i = 0
        while i < work.count {
            for rule in work[i].rules {
                for part in rule.parts {
                    if !seen.contains(part.id) { seen.insert(part.id); work.append(part) }
                }
            }
            i += 1
        }
        return seen
    }
    
    func gatherNodeProps(nodeTypes: [Term]) -> (nodeProps: [[String: Any]]?, skippedTypes: [Int]) {
        let notSkipped = gatherNonSkippedNodes()
        var skippedTypes: [Int] = []
        var nodeProps: [[String: Any]] = []
        for type in nodeTypes {
            if !notSkipped.contains(type.id) && !type.error { skippedTypes.append(type.id) }
            for (propName, propValue) in type.props {
                let known = knownProps[propName]
                if known == nil { raise("No known prop type for \(propName)") }
                if known!.source.from == nil && (known!.source.name == "repeated" || known!.source.name == "error") { continue }
                var rec = nodeProps.firstIndex(where: { $0["prop"] as! String == propName })
                if rec == nil {
                    rec = nodeProps.count
                    nodeProps.append(["prop": propName, "values": [String: [Int]]()])
                }
                var values = nodeProps[rec!]["values"] as! [String: [Int]]
                if values[propValue] == nil { values[propValue] = [] }
                values[propValue]!.append(type.id)
                nodeProps[rec!]["values"] = values
            }
        }
        let formattedProps = nodeProps.map { entry -> [String: Any] in
            let propName = entry["prop"] as! String
            let values = entry["values"] as! [String: [Int]]
            var terms: [Any] = []
            for (val, ids) in values {
                if ids.count == 1 {
                    terms.append(ids[0]); terms.append(val)
                } else {
                    terms.append(-ids.count)
                    for id in ids { terms.append(id) }
                    terms.append(val)
                }
            }
            return ["prop": propName, "terms": terms]
        }
        return (formattedProps.isEmpty ? nil : formattedProps, skippedTypes)
    }
    
    func makeTerminal(_ name: String, nodeName: String?, props: Props = [:]) -> Term {
        return terms.makeTerminal(terms.uniqueName(name), nodeName: nodeName, props: props)
    }
    
    func computeForceReductions(_ states: [State], _ skipInfo: [SkipInfo]) -> [Int] {
        var reductions: [Int] = []
        var candidates: [[Pos]] = []
        var gotoEdges: [Int: [(parents: [Int], target: Int)]] = [:]
        for state in states {
            reductions.append(0)
            for edge in state.goto {
                var array = gotoEdges[edge.term.id] ?? []
                if let found = array.firstIndex(where: { $0.target == edge.target.id }) {
                    array[found].parents.append(state.id)
                } else {
                    array.append((parents: [state.id], target: edge.target.id))
                }
                gotoEdges[edge.term.id] = array
            }
            candidates.append(state.set.filter { $0.pos > 0 && !$0.rule.name.top }.sorted { a, b in
                if b.pos != a.pos { return b.pos < a.pos }
                return a.rule.parts.count < b.rule.parts.count
            })
        }
        var length1Reductions: [Int: Int] = [:]
        func createsCycle(_ term: Int, _ startState: Int, _ parents: [Int]? = nil) -> Bool {
            guard let edges = gotoEdges[term] else { return false }
            for val in edges {
                let parentIntersection = parents != nil ? parents!.filter { val.parents.contains($0) } : val.parents
                if parentIntersection.isEmpty { continue }
                if val.target == startState { return true }
                if let found = length1Reductions[val.target], createsCycle(found, startState, parentIntersection) { return true }
            }
            return false
        }
        for state in states {
            if let dr = state.defaultReduce, !dr.parts.isEmpty {
                reductions[state.id] = reduceAction(dr, skipInfo)
                if dr.parts.count == 1 { length1Reductions[state.id] = dr.name.id }
            }
        }
        for setSize in 1... {
            var done = true
            for state in states {
                if state.defaultReduce != nil { continue }
                let set = candidates[state.id]
                if set.count != setSize {
                    if set.count > setSize { done = false }
                    continue
                }
                for pos in set {
                    if pos.pos != 1 || !createsCycle(pos.rule.name.id, state.id) {
                        reductions[state.id] = reduceAction(pos.rule, skipInfo, depth: pos.pos)
                        if pos.pos == 1 { length1Reductions[state.id] = pos.rule.name.id }
                        break
                    }
                }
            }
            if done { break }
        }
        return reductions
    }
    
    func substituteArgs(_ expr: Expression, args: [Expression], params: [Identifier]) -> Expression {
        if args.isEmpty { return expr }
        return expr.walk { e in
            if let nameExpr = e as? NameExpression, let found = params.firstIndex(where: { $0.name == nameExpr.id.name }) {
                let arg = args[found]
                if !nameExpr.args.isEmpty {
                    if arg is NameExpression && (arg as! NameExpression).args.isEmpty {
                        return NameExpression(start: nameExpr.start, id: (arg as! NameExpression).id, args: nameExpr.args)
                    }
                    self.raise("Passing arguments to a parameter that already has arguments", pos: nameExpr.start)
                }
                return arg
            }
            if let inlineExpr = e as? InlineRuleExpression {
                let r = inlineExpr.rule
                if let newProps = substituteArgsInProps(r.props, args: args, params: params) {
                    return InlineRuleExpression(start: inlineExpr.start, rule: RuleDeclaration(start: r.start, id: r.id, props: newProps, params: r.params, expr: r.expr))
                }
                return inlineExpr
            }
            if let specExpr = e as? SpecializeExpression {
                if let newProps = substituteArgsInProps(specExpr.props, args: args, params: params) {
                    return SpecializeExpression(start: specExpr.start, type: specExpr.type, props: newProps, token: specExpr.token, content: specExpr.content)
                }
                return specExpr
            }
            return e
        }
    }
    
    func substituteArgsInProps(_ props: [Prop], args: [Expression], params: [Identifier]) -> [Prop]? {
        var result: [Prop]? = nil
        for (i, prop) in props.enumerated() {
            var newValue = prop.value
            var valueChanged = false
            for (j, part) in prop.value.enumerated() {
                guard let pname = part.name, let found = params.firstIndex(where: { $0.name == pname }) else { continue }
                if !valueChanged { newValue = prop.value; valueChanged = true }
                let expr = args[found]
                if let nameExpr = expr as? NameExpression, nameExpr.args.isEmpty {
                    newValue[j] = PropPart(start: part.start, value: nameExpr.id.name, name: nil)
                } else if let litExpr = expr as? LiteralExpression {
                    newValue[j] = PropPart(start: part.start, value: litExpr.value, name: nil)
                } else {
                    raise("Trying to interpolate expression '\(expr)' into a prop", pos: part.start)
                }
            }
            if valueChanged {
                if result == nil { result = props }
                result![i] = Prop(start: prop.start, at: prop.at, name: prop.name, value: newValue)
            }
        }
        return result
    }
    
    func conflictsFor(_ markers: [ConflictMarker]) -> (here: Conflicts, atEnd: Conflicts) {
        var here = Conflicts.none
        var atEnd = Conflicts.none
        for marker in markers {
            if marker.type == "ambig" {
                here = here.join(Conflicts(precedence: 0, ambigGroups: [marker.id.name]))
            } else {
                guard let precs = ast.precedences else {
                    raise("Reference to unknown precedence: '\(marker.id.name)'", pos: marker.id.start)
                }
                guard let index = precs.items.firstIndex(where: { $0.id.name == marker.id.name }) else {
                    raise("Reference to unknown precedence: '\(marker.id.name)'", pos: marker.id.start)
                }
                let prec = precs.items[index]
                let value = precs.items.count - index
                if prec.type == "cut" {
                    here = here.join(Conflicts(precedence: 0, ambigGroups: [], cut: value))
                } else {
                    here = here.join(Conflicts(precedence: value << 2))
                    atEnd = atEnd.join(Conflicts(precedence: (value << 2) + (prec.type == "left" ? 1 : prec.type == "right" ? -1 : 0)))
                }
            }
        }
        return (here, atEnd)
    }
    
    func raise(_ message: String, pos: Int = 1) -> Never {
        input.raise(message, pos: pos)
    }
    
    func warn(_ message: String, pos: Int = -1) {
        let msg = input.message(message, pos: pos)
        if let w = options.warn { w(msg) } else { print("warning: \(msg)") }
    }
    
    func defineRule(_ name: Term, choices: [Parts]) {
        let skip = currentSkip.last!
        for choice in choices {
            rules.append(Rule(name: name, parts: choice.terms, conflicts: choice.ensureConflicts(), skip: skip))
        }
    }
    
    func resolve(_ expr: NameExpression) -> [Parts] {
        for b in built { if b.matches(expr) { return [p(b.term)] } }
        if let found = tokens.getToken(expr) { return [p(found)] }
        for grp in localTokens { if let found = grp.getToken(expr) { return [p(found)] } }
        for ext in externalTokens { if let found = ext.getToken(expr) { return [p(found)] } }
        for ext in externalSpecializers { if let found = ext.getToken(expr) { return [p(found)] } }
        guard let known = astRules.first(where: { $0.rule.id.name == expr.id.name }) else {
            raise("Reference to undefined rule '\(expr.id.name)'", pos: expr.start)
        }
        if known.rule.params.count != expr.args.count { raise("Wrong number or arguments for '\(expr.id.name)'", pos: expr.start) }
        used(known.rule.id.name)
        return [p(buildRule(known.rule, args: expr.args, skip: known.skip))]
    }
    
    func normalizeRepeat(_ expr: RepeatExpression) -> Parts {
        for b in built { if b.matchesRepeat(expr) { return p(b.term) } }
        let nameStr = expr.expr.prec < expr.prec ? "\(expr.expr.toString())+": "\(expr.expr.toString())+"
        let term = terms.makeRepeat(terms.uniqueName(nameStr))
        built.append(BuiltRule(id: "+", args: [expr.expr], term: term))
        defineRule(term, choices: normalizeExpr(expr.expr) + [p(term, term)])
        return p(term)
    }
    
    func normalizeSequence(_ expr: SequenceExpression) -> [Parts] {
        let result: [[Parts]] = expr.exprs.map { normalizeExpr($0) }
        func complete(_ start: Parts, _ from: Int, _ endConflicts: Conflicts) -> [Parts] {
            let (here, atEnd) = conflictsFor(expr.markers[from])
            if from == result.count { return [start.withConflicts(start.terms.count, here.join(endConflicts))] }
            var choices: [Parts] = []
            for choice in result[from] {
                for full in complete(start.concat(choice).withConflicts(start.terms.count, here), from + 1, endConflicts.join(atEnd)) {
                    choices.append(full)
                }
            }
            return choices
        }
        return complete(Parts.none, 0, Conflicts.none)
    }
    
    func normalizeExpr(_ expr: Expression) -> [Parts] {
        if let repeatExpr = expr as? RepeatExpression {
            if repeatExpr.kind == "?" { return [Parts.none] + normalizeExpr(repeatExpr.expr) }
            let repeated = normalizeRepeat(repeatExpr)
            return repeatExpr.kind == "+" ? [repeated] : [Parts.none, repeated]
        }
        if let choiceExpr = expr as? ChoiceExpression {
            return choiceExpr.exprs.reduce([]) { $0 + normalizeExpr($1) }
        }
        if let seqExpr = expr as? SequenceExpression {
            return normalizeSequence(seqExpr)
        }
        if let litExpr = expr as? LiteralExpression {
            return [p(tokens.getLiteral(litExpr)!)]
        }
        if let nameExpr = expr as? NameExpression {
            return resolve(nameExpr)
        }
        if let specExpr = expr as? SpecializeExpression {
            return [p(resolveSpecialization(specExpr))]
        }
        if let inlineExpr = expr as? InlineRuleExpression {
            return [p(buildRule(inlineExpr.rule, args: [], skip: currentSkip.last!, inline: true))]
        }
        raise("This type of expression ('\(expr)') may not occur in non-token rules", pos: expr.start)
    }
    
    func buildRule(_ rule: RuleDeclaration, args: [Expression], skip: Term, inline: Bool = false) -> Term {
        let expr = substituteArgs(rule.expr, args: args, params: rule.params)
        let info = nodeInfo(rule.props, allow: inline ? "pg" : "pgi", defaultName: rule.id.name, args: args, params: rule.params, expr: rule.expr)
        if info.exported != nil && !rule.params.isEmpty { warn("Can't export parameterized rules", pos: rule.start) }
        if info.exported != nil && inline { warn("Can't export inline rule", pos: rule.start) }
        let suffix = args.isEmpty ? "" : "<\(args.map { String(describing: $0) }.joined(separator: ","))>"
        let name = newName(rule.id.name + suffix, nodeName: info.name ?? true, props: info.props)
        if info.inline { name.inline = true }
        if info.dynamicPrec != 0 { registerDynamicPrec(name, prec: info.dynamicPrec) }
        if (name.nodeType || info.exported != nil) && rule.params.isEmpty {
            if info.name == nil { name.preserve = true }
            if !inline { namedTerms[info.exported ?? rule.id.name] = name }
        }
        if !inline { built.append(BuiltRule(id: rule.id.name, args: args, term: name)) }
        currentSkip.append(skip)
        let parts = normalizeExpr(expr)
        defineRule(name, choices: parts)
        currentSkip.removeLast()
        if let g = info.group { definedGroups.append((name: name, group: g, rule: rule)) }
        return name
    }
    
    func nodeInfo(_ props: [Prop], allow: String, defaultName: String?, args: [Expression], params: [Identifier], expr: Expression? = nil, defaultProps: Props? = nil) -> (name: String?, props: Props, dialect: Int?, dynamicPrec: Int, inline: Bool, group: String?, exported: String?) {
        var result: Props = [:]
        let name: String? = {
            guard let dn = defaultName else { return nil }
            if allow.contains("a") || !ignored(dn), !dn.contains(" ") { return dn }
            return nil
        }()
        var dialect: Int? = nil
        var dynamicPrec = 0
        var inline = false
        var group: String? = nil
        var exported: String? = nil
        var resultName = name
        for prop in props {
            if !prop.at {
                if knownProps[prop.name] == nil {
                    let builtin = ["name", "dialect", "dynamicPrecedence", "export", "isGroup"].contains(prop.name) ? " (did you mean '@\(prop.name)'?)" : ""
                    raise("Unknown prop name '\(prop.name)'\(builtin)", pos: prop.start)
                }
                result[prop.name] = finishProp(prop, args: args, params: params)
            } else if prop.name == "name" {
                resultName = finishProp(prop, args: args, params: params)
                if resultName!.contains(" ") { raise("Node names cannot have spaces ('\(resultName!)')", pos: prop.start) }
            } else if prop.name == "dialect" {
                if !allow.contains("d") { raise("Can't specify a dialect on non-token rules", pos: props[0].start) }
                if prop.value.count != 1 || prop.value[0].value == nil { raise("The '@dialect' rule prop must hold a plain string value") }
                guard let dID = dialects.firstIndex(of: prop.value[0].value!) else { raise("Unknown dialect '\(prop.value[0].value!)'", pos: prop.value[0].start) }
                dialect = dID
            } else if prop.name == "dynamicPrecedence" {
                if !allow.contains("p") { raise("Dynamic precedence can only be specified on nonterminals") }
                if prop.value.count != 1 || !isValidDynamicPrecedence(prop.value[0].value ?? "") { raise("The '@dynamicPrecedence' rule prop must hold an integer between -10 and 10") }
                dynamicPrec = Int(prop.value[0].value!)!
            } else if prop.name == "inline" {
                if !prop.value.isEmpty { raise("'@inline' doesn't take a value", pos: prop.value[0].start) }
                if !allow.contains("i") { raise("Inline can only be specified on nonterminals") }
                inline = true
            } else if prop.name == "isGroup" {
                if !allow.contains("g") { raise("'@isGroup' can only be specified on nonterminals") }
                group = prop.value.isEmpty ? defaultName : finishProp(prop, args: args, params: params)
            } else if prop.name == "export" {
                exported = prop.value.isEmpty ? defaultName : finishProp(prop, args: args, params: params)
            } else {
                raise("Unknown built-in prop name '@\(prop.name)'", pos: prop.start)
            }
        }
        if let e = expr, ast.autoDelim, resultName != nil || hasProps(result) {
            let delim = findDelimiters(e)
            if let d = delim {
                addToProp(d.0, "closedBy", d.1.nodeName!)
                addToProp(d.1, "openedBy", d.0.nodeName!)
            }
        }
        if let dp = defaultProps, hasProps(dp) {
            for (pk, pv) in dp { if result[pk] == nil { result[pk] = pv } }
        }
        if hasProps(result) && resultName == nil { raise("Node has properties but no name", pos: props.first?.start ?? expr?.start ?? 0) }
        if inline && (hasProps(result) || dialect != nil || dynamicPrec != 0) { raise("Inline nodes can't have props, dynamic precedence, or a dialect", pos: props.first?.start ?? 0) }
        if inline { resultName = nil }
        return (name: resultName, props: result, dialect: dialect, dynamicPrec: dynamicPrec, inline: inline, group: group, exported: exported)
    }
    
    func finishProp(_ prop: Prop, args: [Expression], params: [Identifier]) -> String {
        return prop.value.map { part -> String in
            if let v = part.value { return v }
            guard let pname = part.name, let pos = params.firstIndex(where: { $0.name == pname }) else {
                raise("Property refers to '\(part.name ?? "")', but no parameter by that name is in scope", pos: part.start)
            }
            let expr = args[pos]
            if let nameExpr = expr as? NameExpression, nameExpr.args.isEmpty { return nameExpr.id.name }
            if let litExpr = expr as? LiteralExpression { return litExpr.value }
            raise("Expression '\(expr)' can not be used as part of a property value", pos: part.start)
        }.joined()
    }
    
    func resolveSpecialization(_ expr: SpecializeExpression) -> Term {
        let type = expr.type
        let info = nodeInfo(expr.props, allow: "d", defaultName: nil, args: [], params: [])
        let terminal = normalizeExpr(expr.token)
        if terminal.count != 1 || terminal[0].terms.count != 1 || !terminal[0].terms[0].terminal {
            raise("The first argument to '\(type)' must resolve to a token", pos: expr.token.start)
        }
        let values: [String]
        if let lit = isLiteralToken(expr.content) { values = [lit] }
        else if let choice = expr.content as? ChoiceExpression {
            values = choice.exprs.compactMap { isLiteralToken($0) }
            if values.count != choice.exprs.count { raise("The second argument to '\(type)' must be a literal or choice of literals", pos: expr.content.start) }
        } else { raise("The second argument to '\(type)' must be a literal or choice of literals", pos: expr.content.start) }
        let term = terminal[0].terms[0]
        var table = specialized[term.name] ?? []
        var token: Term? = nil
        for value in values {
            if let known = table.first(where: { $0["value"] as! String == value }) {
                if known["type"] as! String != type { raise("Conflicting specialization types for \(value) of \(term.name)", pos: expr.start) }
                if (known["dialect"] as? Int) != info.dialect { raise("Conflicting dialects for specialization \(value) of \(term.name)", pos: expr.start) }
                if (known["name"] as? String) != info.name { raise("Conflicting names for specialization \(value) of \(term.name)", pos: expr.start) }
                if let t = token, (known["term"] as! Term) !== t { raise("Conflicting specialization tokens for \(value) of \(term.name)", pos: expr.start) }
                token = known["term"] as? Term
            } else {
                if token == nil {
                    token = makeTerminal("\(term.name)/\"\(value)\"", nodeName: info.name, props: info.props)
                    if let d = info.dialect {
                        if tokens.byDialect[d] == nil { tokens.byDialect[d] = [] }
                        tokens.byDialect[d]!.append(token!)
                    }
                }
                let typeCode = type == "specialize" ? "specialize" : "extend"
                table.append(["value": value, "term": token!, "type": typeCode, "dialect": info.dialect as Any, "name": info.name as Any])
                tokenOrigins[token!.name] = TokenOrigin(spec: term, external: nil, group: nil)
                if info.name != nil || info.exported != nil {
                    if info.name == nil { token!.preserve = true }
                    namedTerms[info.exported ?? info.name!] = token!
                }
            }
        }
        specialized[term.name] = table
        return token!
    }
    
    func findDelimiters(_ expr: Expression) -> (Term, Term)? {
        guard let seq = expr as? SequenceExpression, seq.exprs.count >= 2 else { return nil }
        func findToken(_ e: Expression) -> (term: Term, str: String)? {
            if let lit = e as? LiteralExpression { return (term: tokens.getLiteral(lit)!, str: lit.value) }
            if let name = e as? NameExpression, name.args.isEmpty {
                if let rule = ast.rules.first(where: { $0.id.name == name.id.name }) { return findToken(rule.expr) }
                if let tokenRule = tokens.rules.first(where: { $0.id.name == name.id.name }), let lit = tokenRule.expr as? LiteralExpression {
                    return (term: tokens.getToken(name)!, str: lit.value)
                }
            }
            return nil
        }
        guard let lastToken = findToken(seq.exprs.last!), lastToken.term.nodeName != nil else { return nil }
        let brackets = ["()", "[]", "{}", "<>"]
        guard let bracket = brackets.first(where: { lastToken.str.contains($0[..<$0.index($0.startIndex, offsetBy: 1)]) && !lastToken.str.contains($0[$0.index($0.startIndex, offsetBy: 1)...]) }) else { return nil }
        guard let firstToken = findToken(seq.exprs.first!), firstToken.term.nodeName != nil,
              firstToken.str.contains(bracket[..<bracket.index(bracket.startIndex, offsetBy: 1)]),
              !firstToken.str.contains(bracket[bracket.index(bracket.startIndex, offsetBy: 1)...]) else { return nil }
        return (firstToken.term, lastToken.term)
    }
    
    func registerDynamicPrec(_ term: Term, prec: Int) {
        dynamicRulePrecedences.append((rule: term, prec: prec))
        term.preserve = true
    }
    
    func defineGroup(name: Term, group: String, rule: RuleDeclaration) {
        let declStart = rule.start
        var recur: [Term] = []
        func getNamed(_ rule: Term) -> [Term] {
            if rule.nodeName != nil { return [rule] }
            if recur.contains(where: { $0 === rule }) { raise("Rule '\(rule.id)' cannot define a group because it contains a non-named recursive rule ('\(rule.name)')", pos: declStart) }
            var result: [Term] = []
            recur.append(rule)
            for r in self.rules where r.name === rule {
                let names = r.parts.map(getNamed).filter { !$0.isEmpty }
                if names.count > 1 { raise("Rule '\(rule.id)' cannot define a group because some choices produce multiple named nodes", pos: declStart) }
                if names.count == 1 { for n in names[0] { result.append(n) } }
            }
            recur.removeLast()
            return result
        }
        for n in getNamed(name) {
            let cur = n.props["group"]?.split(separator: " ").map(String.init) ?? []
            n.props["group"] = (Set(cur).union([group])).sorted().joined(separator: " ")
        }
    }
    
    func checkGroups() {
        var groups: [String: [Term]] = [:]
        var nodeNames: Set<String> = []
        for term in terms.terms {
            if let nn = term.nodeName {
                nodeNames.insert(nn)
                if let grp = term.props["group"] {
                    for g in grp.split(separator: " ") {
                        let s = String(g)
                        if groups[s] == nil { groups[s] = [] }
                        groups[s]!.append(term)
                    }
                }
            }
        }
        let names = Array(groups.keys)
        for i in 0..<names.count {
            let name = names[i], terms = groups[name]!
            if nodeNames.contains(name) { warn("Group name '\(name)' conflicts with a node of the same name") }
            for j in (i+1)..<names.count {
                let other = groups[names[j]]!
                if terms.contains(where: { other.contains($0) }) && (terms.count > other.count ? other.contains(where: { !terms.contains($0) }) : terms.contains(where: { !other.contains($0) })) {
                    warn("Groups '\(name)' and '\(names[j])' overlap without one being a superset of the other")
                }
            }
        }
    }
}

func isLiteralToken(_ expr: Expression) -> String? {
    if let lit = expr as? LiteralExpression { return lit.value }
    if let seq = expr as? SequenceExpression {
        var result = ""
        for sub in seq.exprs {
            guard let s = isLiteralToken(sub) else { return nil }
            result += s
        }
        return result
    }
    return nil
}

public func buildParser(text: String, options: BuildOptions = BuildOptions()) -> LRParser {
    let builder = Builder(text, options: options)
    let parser = builder.getParser()
    return parser
}
