import Foundation

// MARK: - BuildOptions

public struct BuildOptions {
    public var fileName: String?
    public var warn: ((String) -> Void)?
    public var externalTokenizer: ((String, [String: Int]) -> TokenizerProtocol)?
    public var externalSpecializer: ((String, [String: Int]) -> (String, Stack) -> Int)?
    public var externalPropSource: ((String) -> NodePropSource)?
    public var externalProp: ((String) -> NodePropBase)?
    public var contextTracker: ContextTracker?

    public init(
        fileName: String? = nil,
        warn: ((String) -> Void)? = nil,
        externalTokenizer: ((String, [String: Int]) -> TokenizerProtocol)? = nil,
        externalSpecializer: ((String, [String: Int]) -> (String, Stack) -> Int)? = nil,
        externalPropSource: ((String) -> NodePropSource)? = nil,
        externalProp: ((String) -> NodePropBase)? = nil,
        contextTracker: ContextTracker? = nil
    ) {
        self.fileName = fileName
        self.warn = warn
        self.externalTokenizer = externalTokenizer
        self.externalSpecializer = externalSpecializer
        self.externalPropSource = externalPropSource
        self.externalProp = externalProp
        self.contextTracker = contextTracker
    }
}

// MARK: - Parts

class Parts {
    let terms: [Term]
    let conflicts: [Conflicts]?

    init(terms: [Term], conflicts: [Conflicts]?) {
        self.terms = terms
        self.conflicts = conflicts
    }

    func concat(_ other: Parts) -> Parts {
        if self === Parts.none { return other }
        if other === Parts.none { return self }
        var mergedConflicts: [Conflicts]? = nil
        if self.conflicts != nil || other.conflicts != nil {
            var c = self.conflicts ?? self.ensureConflicts()
            let oc = other.ensureConflicts()
            c[c.count - 1] = c[c.count - 1].join(oc[0])
            for i in 1..<oc.count { c.append(oc[i]) }
            mergedConflicts = c
        }
        return Parts(terms: self.terms + other.terms, conflicts: mergedConflicts)
    }

    func withConflicts(_ pos: Int, _ conflicts: Conflicts) -> Parts {
        if conflicts === Conflicts.none { return self }
        var array = self.conflicts ?? ensureConflicts()
        array[pos] = array[pos].join(conflicts)
        return Parts(terms: self.terms, conflicts: array)
    }

    func ensureConflicts() -> [Conflicts] {
        if let c = self.conflicts { return c }
        return (0...terms.count).map { _ in Conflicts.none }
    }

    nonisolated(unsafe) static let none = Parts(terms: [], conflicts: nil)
}

func p(_ terms: Term...) -> Parts {
    return Parts(terms: terms, conflicts: nil)
}

// MARK: - BuiltRule

class BuiltRule {
    let id: String
    let args: [Expression]
    let term: Term

    init(id: String, args: [Expression], term: Term) {
        self.id = id
        self.args = args
        self.term = term
    }

    func matches(_ expr: NameExpression) -> Bool {
        return id == expr.id.name && exprsEq(expr.args, args)
    }

    func matchesRepeat(_ expr: RepeatExpression) -> Bool {
        return id == "+" && exprEq(expr.expr, args[0])
    }
}

// MARK: - SkipInfo

struct SkipInfo {
    var skip: [Term]
    var rule: Term?
    var startTokens: [Term]
    var id: Int
}

// MARK: - Constants

private let minSharedActions = 5
private let ASTRAL_CODE = 0x10000
private let GAP_START = 0xd800
private let GAP_END = 0xe000
private let MAX_CODE = 0x10ffff
private let LOW_SURR_B = 0xdc00
private let HIGH_SURR_B = 0xdfff

// MARK: - SharedActions

struct SharedActions {
    let actions: [ActionItem]
    let addr: Int
}

// MARK: - DataBuilder

class DataBuilder {
    var data: [Int] = []

    func storeArray(_ newData: [Int]) -> Int {
        let found = findArray(data, newData)
        if found > -1 { return found }
        let pos = data.count
        data.append(contentsOf: newData)
        return pos
    }

    func finish() -> [UInt16] {
        return data.map { UInt16(truncatingIfNeeded: $0) }
    }
}

// MARK: - TokenOrigin

struct TokenOrigin {
    var spec: Term?
    var external: AnyObject?
    var group: LocalTokenSet?
}

// MARK: - TokenizerSpecProtocol

protocol TokenizerSpecProtocol: AnyObject {
    var groupID: Int? { get }
    func create() -> Any
}

// MARK: - BuildTokenGroup

class BuildTokenGroup: TokenizerSpecProtocol {
    var tokens: [Term]
    let groupID: Int?

    init(tokens: [Term], groupID: Int) {
        self.tokens = tokens
        self.groupID = groupID
    }

    func create() -> Any { return groupID ?? 0 }
}

// MARK: - LocalTokenGroupSpec

class LocalTokenGroupSpec: TokenizerSpecProtocol {
    let groupID: Int?
    private let fullData: [UInt16]
    private let precOffset: Int
    private let elseToken: Int?

    init(groupID: Int, fullData: [UInt16], precOffset: Int, elseToken: Int?) {
        self.groupID = groupID
        self.fullData = fullData
        self.precOffset = precOffset
        self.elseToken = elseToken
    }

    func create() -> Any {
        return LocalTokenGroup(data: fullData, precTable: precOffset, elseToken: elseToken)
    }
}

// MARK: - FinishStateContext

class FinishStateContext {
    var sharedActions: [SharedActions] = []
    let tokenizers: [TokenizerSpecProtocol]
    let data: DataBuilder
    var stateArray: [UInt32]
    let skipData: [Int]
    let skipInfo: [SkipInfo]
    let states: [AutState]
    let builder: Builder

    init(
        tokenizers: [TokenizerSpecProtocol],
        data: DataBuilder,
        stateArray: [UInt32],
        skipData: [Int],
        skipInfo: [SkipInfo],
        states: [AutState],
        builder: Builder
    ) {
        self.tokenizers = tokenizers
        self.data = data
        self.stateArray = stateArray
        self.skipData = skipData
        self.skipInfo = skipInfo
        self.states = states
        self.builder = builder
    }

    func findSharedActions(_ state: AutState) -> SharedActions? {
        if state.actions.count < minSharedActions { return nil }
        var found: SharedActions? = nil
        for shared in sharedActions {
            if (found == nil || shared.actions.count > found!.actions.count) &&
                shared.actions.allSatisfy({ sa in state.actions.contains(where: { b in actionEq(sa, b) }) }) {
                found = shared
            }
        }
        if let found = found { return found }
        var max: [ActionItem]? = nil
        var scratch: [ActionItem] = []
        for i in (state.id + 1)..<states.count {
            let other = states[i]
            var fill = 0
            if other.defaultReduce != nil || other.actions.count < minSharedActions { continue }
            for a in state.actions {
                for b in other.actions {
                    if actionEq(a, b) {
                        if fill < scratch.count {
                            scratch[fill] = a
                        } else {
                            scratch.append(a)
                        }
                        fill += 1
                    }
                }
            }
            if fill >= minSharedActions && (max == nil || max!.count < fill) {
                max = Array(scratch.prefix(fill))
                scratch = []
            }
        }
        guard let maxActions = max else { return nil }
        let result = SharedActions(actions: maxActions, addr: storeActions(maxActions, -1, shared: nil))
        sharedActions.append(result)
        return result
    }

    func storeActions(_ actions: [ActionItem], _ skipReduce: Int, shared: SharedActions?) -> Int {
        if skipReduce < 0 && shared != nil && shared!.actions.count == actions.count { return shared!.addr }
        var d: [Int] = []
        for action in actions {
            if let shared = shared, shared.actions.contains(where: { actionEq($0, action) }) { continue }
            if let shift = action as? Shift {
                d.append(shift.term.id)
                d.append(shift.target.id)
                d.append(0)
            } else if let reduce = action as? Reduce {
                let code = reduceAction(reduce.rule, skipInfo)
                if code != skipReduce {
                    d.append(reduce.term.id)
                    d.append(code & Action.ValueMask)
                    d.append(code >> 16)
                }
            }
        }
        d.append(Seq.End)
        if skipReduce > -1 {
            d.append(Seq.Other)
            d.append(skipReduce & Action.ValueMask)
            d.append(skipReduce >> 16)
        } else if let shared = shared {
            d.append(Seq.Next)
            d.append(shared.addr & 0xffff)
            d.append(shared.addr >> 16)
        } else {
            d.append(Seq.Done)
        }
        return data.storeArray(d)
    }

    func finish(_ state: AutState, _ isSkip: Bool, _ forcedReduce: Int) {
        let b = builder
        let skipID = b.skipRules.firstIndex(where: { $0 === state.skip }) ?? 0
        let skipTable = skipData[skipID]
        let skipTerms = skipInfo[skipID].startTokens

        let defaultReduce = state.defaultReduce != nil ? reduceAction(state.defaultReduce!, skipInfo) : 0
        var flags: UInt32 = isSkip ? UInt32(StateFlag.Skipped) : 0

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
            if skipReduce < 0 { shared = findSharedActions(state) }
        }

        if state.set.contains(where: { $0.rule.name.top && $0.pos == $0.rule.parts.count }) {
            flags |= UInt32(StateFlag.Accepting)
        }

        var externalList: [TokenizerSpecProtocol] = []
        for i in 0..<(state.actions.count + skipTerms.count) {
            let term: Term
            if i < state.actions.count {
                term = actionTerm(state.actions[i])
            } else {
                term = skipTerms[i - state.actions.count]
            }
            var t = term
            while true {
                if let orig = b.tokenOrigins[t.name], let spec = orig.spec {
                    t = spec
                    continue
                }
                if let orig = b.tokenOrigins[t.name], let ext = orig.external as? ExternalTokenSet {
                    if !externalList.contains(where: { $0 === ext }) { externalList.append(ext) }
                }
                break
            }
        }

        var tokenizerMask: UInt32 = 0
        for i in 0..<tokenizers.count {
            let tok = tokenizers[i]
            if externalList.contains(where: { $0 === tok }) || tok.groupID == state.tokenGroup {
                tokenizerMask |= UInt32(1 << i)
            }
        }

        let base = state.id * ParseState.Size
        stateArray[base + ParseState.Flags] = flags
        stateArray[base + ParseState.Actions] = UInt32(storeActions(
            defaultReduce != 0 ? [] : state.actions, skipReduce, shared: shared
        ))
        stateArray[base + ParseState.Skip] = UInt32(skipTable)
        stateArray[base + ParseState.TokenizerMask] = tokenizerMask
        stateArray[base + ParseState.DefaultReduce] = UInt32(defaultReduce)
        stateArray[base + ParseState.ForcedReduce] = UInt32(forcedReduce)
    }
}

// MARK: - TokenArg

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

// MARK: - BuildingRule

class BuildingRule {
    let name: String
    let start: State
    let to: State
    let args: [Expression]

    init(name: String, start: State, to: State, args: [Expression]) {
        self.name = name
        self.start = start
        self.to = to
        self.args = args
    }
}

// MARK: - TokenSet

class TokenSet {
    var startState: State = State()
    var built: [BuiltRule] = []
    var building: [BuildingRule] = []
    var rules: [RuleDeclaration]
    var byDialect: [Int: [Term]] = [:]
    var precedenceRelations: [(term: Term, after: [Term])] = []

    let b: Builder
    let ast: TokenDeclaration?

    init(b: Builder, ast: TokenDeclaration?) {
        self.b = b
        self.ast = ast
        self.rules = ast?.rules ?? []
        for rule in self.rules { b.unique(rule.id) }
    }

    func getToken(_ expr: NameExpression) -> Term? {
        for builtRule in built where builtRule.matches(expr) { return builtRule.term }
        let name = expr.id.name
        guard let rule = rules.first(where: { $0.id.name == name }) else { return nil }
        let info = b.nodeInfo(
            rule.props,
            "d",
            name,
            expr.args,
            rule.params.count != expr.args.count ? [] : rule.params
        )
        let term = b.makeTerminal(expr.description, info.name, info.props)
        if let dialect = info.dialect {
            if byDialect[dialect] == nil { byDialect[dialect] = [] }
            byDialect[dialect]!.append(term)
        }
        if (term.nodeType || info.exported != nil) && rule.params.count == 0 {
            if !term.nodeType { term.preserve = true }
            b.namedTerms[info.exported ?? name] = term
        }
        buildRule(rule, expr, startState, State(accepting: [term]))
        built.append(BuiltRule(id: name, args: expr.args, term: term))
        return term
    }

    func buildRule(
        _ rule: RuleDeclaration,
        _ expr: NameExpression,
        _ from: State,
        _ to: State,
        _ args: [TokenArg] = []
    ) {
        let name = expr.id.name
        if rule.params.count != expr.args.count {
            b.raise("Incorrect number of arguments for token '\(name)'", expr.start)
        }
        if let buildingRule = building.first(where: { $0.name == name && exprsEq(expr.args, $0.args) }) {
            if buildingRule.to === to {
                from.nullEdge(buildingRule.start)
                return
            }
            var lastIndex = building.count - 1
            while building[lastIndex].name != name { lastIndex -= 1 }
            b.raise(
                "Invalid (non-tail) recursion in token rules: \(building[lastIndex...].map { $0.name }.joined(separator: " -> "))",
                expr.start
            )
        }
        b.used(rule.id.name)
        let start = State()
        from.nullEdge(start)
        building.append(BuildingRule(name: name, start: start, to: to, args: expr.args))
        build(
            b.substituteArgs(rule.expr, expr.args, rule.params),
            start,
            to,
            expr.args.enumerated().map { i, e in TokenArg(name: rule.params[i].name, expr: e, scope: args) }
        )
        building.removeLast()
    }

    func build(_ expr: Expression, _ from: State, _ to: State, _ args: [TokenArg]) {
        if let nameExpr = expr as? NameExpression {
            let name = nameExpr.id.name
            if let arg = args.first(where: { $0.name == name }) {
                return build(arg.expr, from, to, arg.scope)
            }
            var foundRule: RuleDeclaration? = nil
            for i in 0...b.localTokens.count {
                let setRules: [RuleDeclaration]
                if i == b.localTokens.count { setRules = b.tokens.rules }
                else { setRules = b.localTokens[i].rules }
                if let r = setRules.first(where: { $0.id.name == name }) {
                    foundRule = r
                    break
                }
            }
            guard let rule = foundRule else {
                b.raise("Reference to token rule '\(name)', which isn't found", expr.start)
            }
            buildRule(rule, nameExpr, from, to, args)
        } else if let charClassExpr = expr as? CharClass {
            for (a, bVal) in (charClasses[charClassExpr.type] ?? []) {
                from.edge(a, bVal, to)
            }
        } else if let choiceExpr = expr as? ChoiceExpression {
            for choice in choiceExpr.exprs { build(choice, from, to, args) }
        } else if isExprEmpty(expr) {
            from.nullEdge(to)
        } else if let seqExpr = expr as? SequenceExpression {
            if let conflict = seqExpr.markers.first(where: { !$0.isEmpty }) {
                b.raise("Conflict marker in token expression", conflict[0].start)
            }
            var current = from
            for i in 0..<seqExpr.exprs.count {
                let next = i == seqExpr.exprs.count - 1 ? to : State()
                build(seqExpr.exprs[i], current, next, args)
                current = next
            }
        } else if let repeatExpr = expr as? RepeatExpression {
            switch repeatExpr.kind {
            case .star:
                let loop = State()
                from.nullEdge(loop)
                build(repeatExpr.expr, loop, loop, args)
                loop.nullEdge(to)
            case .plus:
                let loop = State()
                build(repeatExpr.expr, from, loop, args)
                build(repeatExpr.expr, loop, loop, args)
                loop.nullEdge(to)
            case .optional:
                from.nullEdge(to)
                build(repeatExpr.expr, from, to, args)
            }
        } else if let setExpr = expr as? SetExpression {
            let ranges = setExpr.inverted ? invertRanges(setExpr.ranges) : setExpr.ranges
            for (a, bVal) in ranges { rangeEdges(from, to, a, bVal) }
        } else if let litExpr = expr as? LiteralExpression {
            var current = from
            let utf16 = Array(litExpr.value.utf16)
            for i in 0..<utf16.count {
                let ch = Int(utf16[i])
                let next = i == utf16.count - 1 ? to : State()
                current.edge(ch, ch + 1, next)
                current = next
            }
        } else if expr is AnyExpression {
            let mid = State()
            from.edge(0, GAP_START, to)
            from.edge(GAP_END, MAX_CHAR + 1, to)
            from.edge(0xd800, GAP_END, mid)
            mid.edge(LOW_SURR_B, 0xe000, to)
        } else {
            b.raise("Unrecognized expression type in token", expr.start)
        }
    }

    func takePrecedences() {
        var rel: [(term: Term, after: [Term])] = []
        precedenceRelations = rel
        guard let ast = ast else { return }
        for group in ast.precedences {
            var prev: [Term] = []
            for item in group.items {
                var level: [Term] = []
                if let nameItem = item as? NameExpression {
                    for builtRule in built {
                        if !nameItem.args.isEmpty ? builtRule.matches(nameItem) : builtRule.id == nameItem.id.name {
                            level.append(builtRule.term)
                        }
                    }
                } else if let litItem = item as? LiteralExpression {
                    let id = stringToJSON(litItem.value)
                    if let found = built.first(where: { $0.id == id }) { level.append(found.term) }
                }
                if level.isEmpty { b.warn("Precedence specified for unknown token \(item)", item.start) }
                for term in level { addRel(&rel, term, prev) }
                prev = prev + level
            }
        }
        precedenceRelations = rel
    }

    func precededBy(_ a: Term, _ b: Term) -> Bool {
        guard let found = precedenceRelations.first(where: { $0.term === a }) else { return false }
        return found.after.contains(where: { $0 === b })
    }

    func buildPrecTable(_ softConflicts: [TokenConflict]) -> [Int] {
        var precTable: [Int] = []
        var rel = precedenceRelations
        for conflict in softConflicts {
            var a = conflict.a, b = conflict.b
            if conflict.soft != 0 {
                if !rel.contains(where: { $0.term === a }) || !rel.contains(where: { $0.term === b }) { continue }
                if conflict.soft < 0 { swap(&a, &b) }
                addRel(&rel, b, [a])
                addRel(&rel, a, [])
            }
        }
        outer: while !rel.isEmpty {
            for i in 0..<rel.count {
                let record = rel[i]
                if record.after.allSatisfy({ t in precTable.contains(t.id) }) {
                    precTable.append(record.term.id)
                    if rel.count == 1 { break outer }
                    rel.remove(at: i)
                    continue outer
                }
            }
            b.raise("Cyclic token precedence relation between \(rel.map { $0.term.description }.joined(separator: ", "))")
        }
        return precTable
    }
}

// MARK: - MainTokenSet

class MainTokenSet: TokenSet {
    var explicitConflicts: [(a: Term, b: Term)] = []

    override init(b: Builder, ast: TokenDeclaration?) {
        super.init(b: b, ast: ast)
    }

    func getLiteral(_ expr: LiteralExpression) -> Term {
        let id = stringToJSON(expr.value)
        for builtRule in built where builtRule.id == id { return builtRule.term }
        var nodeName: String? = nil
        var props: Props = [:]
        var dialect: Int? = nil
        var exported: String? = nil
        if let decl = ast?.literals.first(where: { $0.literal == expr.value }) {
            let info = b.nodeInfo(decl.props, "da", expr.value)
            nodeName = info.name
            props = info.props
            dialect = info.dialect
            exported = info.exported
        }
        let term = b.makeTerminal(id, nodeName, props)
        if let dialect = dialect {
            if byDialect[dialect] == nil { byDialect[dialect] = [] }
            byDialect[dialect]!.append(term)
        }
        if let exported = exported { b.namedTerms[exported] = term }
        build(expr, startState, State(accepting: [term]), [])
        built.append(BuiltRule(id: id, args: [], term: term))
        return term
    }

    func takeConflicts() {
        func resolve(_ expr: Expression) -> Term? {
            if let nameExpr = expr as? NameExpression {
                for builtRule in built where builtRule.matches(nameExpr) { return builtRule.term }
            } else if let litExpr = expr as? LiteralExpression {
                let id = stringToJSON(litExpr.value)
                if let found = built.first(where: { $0.id == id }) { return found.term }
            }
            b.warn("Conflict specified for unknown token \(expr)", expr.start)
            return nil
        }
        for c in ast?.conflicts ?? [] {
            var aTerm = resolve(c.a)
            var bTerm = resolve(c.b)
            if let a = aTerm, let b = bTerm {
                if a.id < b.id { swap(&aTerm, &bTerm) }
                explicitConflicts.append((a: aTerm!, b: bTerm!))
            }
        }
    }

    func buildTokenGroups(
        _ states: [AutState],
        _ skipInfo: [SkipInfo],
        _ startID: Int
    ) throws -> (tokenGroups: [BuildTokenGroup], tokenPrec: [Int], tokenData: [UInt16]) {
        let tokens = startState.compile()
        if !tokens.accepting.isEmpty {
            let name = tokens.accepting[0].name
            if let rule = rules.first(where: { $0.id.name == name }) {
                b.raise("Grammar contains zero-length tokens (in '\(name)')", rule.start)
            }
        }

        let occurTogether = checkTogether(states, b, skipInfo)
        var allConflicts = tokens.findConflicts(occurTogether).filter { conflict in
            !precededBy(conflict.a, conflict.b) && !precededBy(conflict.b, conflict.a)
        }
        for ec in explicitConflicts {
            if !allConflicts.contains(where: { ($0.a === ec.a && $0.b === ec.b) }) {
                allConflicts.append(TokenConflict(a: ec.a, b: ec.b, soft: 0, exampleA: "", exampleB: ""))
            }
        }
        let softConflicts = allConflicts.filter { $0.soft != 0 }
        let conflicts = allConflicts.filter { $0.soft == 0 }
        var errors: [(conflict: TokenConflict, error: String)] = []

        var groups: [BuildTokenGroup] = []
        for state in states {
            if state.defaultReduce != nil || state.tokenGroup > -1 { continue }
            var terms: [Term] = []
            var incompatible: [Term] = []
            let skipIdx = b.skipRules.firstIndex(where: { $0 === state.skip }) ?? 0
            let skip = skipInfo[skipIdx].startTokens
            for term in skip {
                if state.actions.contains(where: { actionTerm($0) === term }) {
                    b.raise("Use of token \(term.name) conflicts with skip rule")
                }
            }
            var stateTerms: [Term] = []
            for i in 0..<(state.actions.count + skip.count) {
                var term: Term
                if i < state.actions.count { term = actionTerm(state.actions[i]) }
                else { term = skip[i - state.actions.count] }
                let orig = b.tokenOrigins[term.name]
                if let orig = orig, let spec = orig.spec {
                    term = spec
                } else if let orig = orig, orig.external != nil {
                    continue
                }
                addTo(term, &stateTerms)
            }
            if stateTerms.isEmpty { continue }

            for term in stateTerms {
                for conflict in conflicts {
                    var conflicting: Term? = nil
                    if conflict.a === term { conflicting = conflict.b }
                    else if conflict.b === term { conflicting = conflict.a }
                    guard let conflicting = conflicting else { continue }
                    if stateTerms.contains(where: { $0 === conflicting }) &&
                        !errors.contains(where: { $0.conflict === conflict }) {
                        var example = ""
                        if !conflict.exampleA.isEmpty {
                            example = " (example: \(stringToJSON(conflict.exampleA))"
                            if let eb = conflict.exampleB, !eb.isEmpty { example += " vs \(stringToJSON(eb))" }
                            example += ")"
                        }
                        errors.append((
                            conflict: conflict,
                            error: "Overlapping tokens \(term.name) and \(conflicting.name) used in same context\(example)\nAfter: \(state.set[0].trail())"
                        ))
                    }
                    addTo(term, &terms)
                    addTo(conflicting, &incompatible)
                }
            }

            var tokenGroup: BuildTokenGroup? = nil
            for group in groups {
                if incompatible.contains(where: { t in group.tokens.contains(where: { $0 === t }) }) { continue }
                for term in terms { addTo(term, &group.tokens) }
                tokenGroup = group
                break
            }
            if tokenGroup == nil {
                tokenGroup = BuildTokenGroup(tokens: terms, groupID: groups.count + startID)
                groups.append(tokenGroup!)
            }
            state.tokenGroup = tokenGroup!.groupID!
        }

        if !errors.isEmpty {
            b.raise(errors.map { $0.error }.joined(separator: "\n\n"))
        }
        if groups.count + startID > 16 {
            b.raise("Too many different token groups (\(groups.count)) to represent them as a 16-bit bitfield")
        }

        let precTable = buildPrecTable(softConflicts)
        let tokenData = try tokens.toArray(buildTokenMasks(groups), precTable)

        return (tokenGroups: groups, tokenPrec: precTable, tokenData: tokenData)
    }
}

// MARK: - LocalTokenSet

class LocalTokenSet: TokenSet {
    var fallbackTerm: Term? = nil

    let localAst: LocalTokenDeclaration

    init(b: Builder, ast: LocalTokenDeclaration) {
        self.localAst = ast
        super.init(b: b, ast: nil)
        self.rules = ast.rules
        for rule in self.rules { b.unique(rule.id) }
        if let fb = ast.fallback { b.unique(fb.id) }
    }

    override func getToken(_ expr: NameExpression) -> Term? {
        var term: Term? = nil
        if let fb = localAst.fallback, fb.id.name == expr.id.name {
            if !expr.args.isEmpty {
                b.raise("Incorrect number of arguments for \(expr.id.name)", expr.start)
            }
            if fallbackTerm == nil {
                let info = b.nodeInfo(fb.props, "", expr.id.name, [], [])
                let t = b.makeTerminal(expr.id.name, info.name, info.props)
                fallbackTerm = t
                if t.nodeType || info.exported != nil {
                    if !t.nodeType { t.preserve = true }
                    b.namedTerms[info.exported ?? expr.id.name] = t
                }
                b.used(expr.id.name)
            }
            term = fallbackTerm
        } else {
            term = super.getToken(expr)
        }
        if let term = term, b.tokenOrigins[term.name] == nil {
            b.tokenOrigins[term.name] = TokenOrigin(spec: nil, external: nil, group: self)
        }
        return term
    }

    func buildLocalGroup(
        _ states: [AutState],
        _ skipInfo: [SkipInfo],
        _ id: Int
    ) throws -> LocalTokenGroupSpec {
        let tokens = startState.compile()
        if !tokens.accepting.isEmpty {
            let name = tokens.accepting[0].name
            if let rule = rules.first(where: { $0.id.name == name }) {
                b.raise("Grammar contains zero-length tokens (in '\(name)')", rule.start)
            }
        }

        for conflict in tokens.findConflicts({ _, _ in true }) {
            if !precededBy(conflict.a, conflict.b) && !precededBy(conflict.b, conflict.a) {
                var example = ""
                if !conflict.exampleA.isEmpty { example = " (example: \(stringToJSON(conflict.exampleA)))" }
                b.raise("Overlapping tokens \(conflict.a.name) and \(conflict.b.name) in local token group\(example)")
            }
        }

        for state in states {
            if state.defaultReduce != nil { continue }
            var usesThis: Term? = nil
            var usesOther: Term? = nil
            let skipIdx = b.skipRules.firstIndex(where: { $0 === state.skip }) ?? 0
            if !skipInfo[skipIdx].startTokens.isEmpty {
                usesOther = skipInfo[skipIdx].startTokens[0]
            }
            for action in state.actions {
                let term = actionTerm(action)
                var orig = b.tokenOrigins[term.name]
                while let o = orig, let spec = o.spec { orig = b.tokenOrigins[spec.name] }
                if let o = orig, o.group === self {
                    usesThis = term
                } else {
                    usesOther = term
                }
            }
            if usesThis != nil {
                if usesOther != nil {
                    b.raise("Tokens from a local token group used together with other tokens (\(usesThis!.name) with \(usesOther!.name))")
                }
                state.tokenGroup = id
            }
        }

        let precTable = buildPrecTable([])
        let tokenData = try tokens.toArray([id: Seq.End], precTable)
        let precOffset = tokenData.count
        var fullData = tokenData
        for val in precTable { fullData.append(UInt16(truncatingIfNeeded: val)) }
        fullData.append(UInt16(Seq.End))

        return LocalTokenGroupSpec(
            groupID: id,
            fullData: fullData,
            precOffset: precOffset,
            elseToken: fallbackTerm?.id
        )
    }
}

// MARK: - ExternalTokenSet

class ExternalTokenSet: TokenizerSpecProtocol {
    let tokens: [String: Term]
    let b: Builder
    let ast: ExternalTokenDeclaration
    let groupID: Int? = nil

    init(b: Builder, ast: ExternalTokenDeclaration) {
        self.b = b
        self.ast = ast
        self.tokens = gatherExtTokens(b, ast.tokens)
        for (_, term) in tokens {
            b.tokenOrigins[term.name] = TokenOrigin(spec: nil, external: self, group: nil)
        }
    }

    func getToken(_ expr: NameExpression) -> Term? {
        return findExtToken(b, tokens, expr)
    }

    func checkConflicts(_ states: [AutState], _ skipInfo: [SkipInfo]) {
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
                let skipIdx = b.skipRules.firstIndex(where: { $0 === state.skip }) ?? 0
                let skip = skipInfo[skipIdx].startTokens
                var relevant = false
                var conflict: Term? = nil
                for i in 0..<(state.actions.count + skip.count) {
                    let term: Term
                    if i < state.actions.count { term = actionTerm(state.actions[i]) }
                    else { term = skip[i - state.actions.count] }
                    if tokens[term.name] != nil { relevant = true }
                    else if conflicting.contains(where: { $0 === term }) { conflict = term }
                }
                if relevant, let conflict = conflict {
                    b.raise(
                        "Tokens from external group used together with conflicting token '\(conflict.name)'\nAfter: \(state.set[0].trail())",
                        ast.start
                    )
                }
            }
        }
    }

    func create() -> Any {
        guard let factory = b.options.externalTokenizer else {
            fatalError("External tokenizer '\(ast.id.name)' requested but no externalTokenizer option provided")
        }
        return factory(ast.id.name, b.termTable)
    }
}

// MARK: - ExternalSpecializer

class ExternalSpecializer {
    var term: Term? = nil
    let tokens: [String: Term]
    let b: Builder
    let ast: ExternalSpecializeDeclaration

    init(b: Builder, ast: ExternalSpecializeDeclaration) {
        self.b = b
        self.ast = ast
        self.tokens = gatherExtTokens(b, ast.tokens)
    }

    func finish() {
        let terms = b.normalizeExpr(ast.token)
        if terms.count != 1 || terms[0].terms.count != 1 || !terms[0].terms[0].terminal {
            b.raise("The token expression to '@external \(ast.type)' must resolve to a token", ast.token.start)
        }
        term = terms[0].terms[0]
        for (_, token) in tokens {
            b.tokenOrigins[token.name] = TokenOrigin(spec: term, external: self, group: nil)
        }
    }

    func getToken(_ expr: NameExpression) -> Term? {
        return findExtToken(b, tokens, expr)
    }
}

// MARK: - KnownProp

struct KnownProp {
    var prop: NodePropBase
    var source: (name: String, from: String?)
}

// MARK: - SpecializedEntry

struct SpecializedEntry {
    var value: String
    var name: String?
    var term: Term
    var type: String
    var dialect: Int?
}

// MARK: - SpecializeTableEntry (for prepareParser output)

struct SpecializeTableEntry {
    let token: Term
    let table: [String: Int]
}

// MARK: - Builder

class Builder {
    var ast: GrammarDeclaration!
    var input: GenInput!
    let terms = TermSet()
    var tokens: MainTokenSet!
    var localTokens: [LocalTokenSet] = []
    var externalTokens: [ExternalTokenSet] = []
    var externalSpecializers: [ExternalSpecializer] = []
    var specialized: [String: [SpecializedEntry]] = [:]
    var tokenOrigins: [String: TokenOrigin] = [:]
    var rules: [Rule] = []
    var built: [BuiltRule] = []
    var ruleNames: [String: Identifier] = [:]
    var namedTerms: [String: Term] = [:]
    var termTable: [String: Int] = [:]
    var knownProps: [String: KnownProp] = [:]
    var dialects: [String] = []
    var dynamicRulePrecedences: [(rule: Term, prec: Int)] = []
    var definedGroups: [(name: Term, group: String, rule: RuleDeclaration)] = []
    var astRules: [(skip: Term, rule: RuleDeclaration)] = []
    var currentSkip: [Term] = []
    var skipRules: [Term] = []
    let options: BuildOptions

    init(text: String, options: BuildOptions) throws {
        self.options = options

        let parsedInput = GenInput(text, fileName: options.fileName)
        self.input = parsedInput
        self.ast = try logTime("Parse") { try parsedInput.parse() }

        let builtinProps: [(String, NodePropBase)] = [
            ("openedBy", nodePropOpenedBy),
            ("closedBy", nodePropClosedBy),
            ("group", nodePropGroup),
            ("isolate", nodePropIsolate),
        ]
        for (name, prop) in builtinProps {
            knownProps[name] = KnownProp(prop: prop, source: (name: name, from: nil))
        }
        for prop in ast.externalProps {
            let propBase: NodePropBase
            if let factory = options.externalProp {
                propBase = factory(prop.id.name)
            } else {
                propBase = NodeProp<String>()
            }
            knownProps[prop.id.name] = KnownProp(
                prop: propBase,
                source: (name: prop.externalID.name, from: prop.source)
            )
        }

        dialects = ast.dialects.map { $0.name }

        tokens = MainTokenSet(b: self, ast: ast.tokens)
        localTokens = ast.localTokens.map { LocalTokenSet(b: self, ast: $0) }
        externalTokens = ast.externalTokens.map { ExternalTokenSet(b: self, ast: $0) }
        externalSpecializers = ast.externalSpecializers.map { ExternalSpecializer(b: self, ast: $0) }

        try logTime("Build rules") {
            let noSkip = newName("%noskip", true)
            currentSkip.append(noSkip)
            defineRule(noSkip, [])

            let mainSkip = ast.mainSkip != nil ? newName("%mainskip", true) : noSkip
            var scopedSkip: [Term] = []
            var topRules: [(rule: RuleDeclaration, skip: Term)] = []
            for rule in ast.rules { astRules.append((skip: mainSkip, rule: rule)) }
            for rule in ast.topRules { topRules.append((rule: rule, skip: mainSkip)) }
            for scoped in ast.scopedSkip {
                var skip = noSkip
                let found = ast.scopedSkip.enumerated().first { i, sc in
                    i < scopedSkip.count && exprEq(sc.expr, scoped.expr)
                }
                if let found = found {
                    skip = scopedSkip[found.offset]
                } else if ast.mainSkip != nil && exprEq(scoped.expr, ast.mainSkip!) {
                    skip = mainSkip
                } else if !isExprEmpty(scoped.expr) {
                    skip = newName("%skip", true)
                }
                scopedSkip.append(skip)
                for rule in scoped.rules { astRules.append((skip: skip, rule: rule)) }
                for rule in scoped.topRules { topRules.append((rule: rule, skip: skip)) }
            }

            for astRule in astRules { unique(astRule.rule.id) }

            skipRules = mainSkip === noSkip ? [mainSkip] : [noSkip, mainSkip]
            if mainSkip !== noSkip { defineRule(mainSkip, normalizeExpr(ast.mainSkip!)) }
            for i in 0..<ast.scopedSkip.count {
                let skip = scopedSkip[i]
                if !skipRules.contains(where: { $0 === skip }) {
                    skipRules.append(skip)
                    if skip !== noSkip { defineRule(skip, normalizeExpr(ast.scopedSkip[i].expr)) }
                }
            }

            for topRule in topRules.sorted(by: { $0.rule.start < $1.rule.start }) {
                unique(topRule.rule.id)
                used(topRule.rule.id.name)
                currentSkip.append(topRule.skip)
                let info = nodeInfo(topRule.rule.props, "a", topRule.rule.id.name, [], [], topRule.rule.expr)
                let term = terms.makeTop(info.name, info.props)
                namedTerms[info.name!] = term
                defineRule(term, normalizeExpr(topRule.rule.expr))
                currentSkip.removeLast()
            }

            for ext in externalSpecializers { ext.finish() }

            for astRule in astRules {
                let rule = astRule.rule
                if ruleNames[rule.id.name] != nil && isExported(rule) && rule.params.isEmpty {
                    _ = buildRule(rule, [], astRule.skip, false)
                    if let seq = rule.expr as? SequenceExpression, seq.exprs.isEmpty {
                        used(rule.id.name)
                    }
                }
            }
        }

        for (_, id) in ruleNames {
            warn("Unused rule '\(id.name)'", id.start)
        }

        tokens.takePrecedences()
        tokens.takeConflicts()
        for lt in localTokens { lt.takePrecedences() }

        for entry in definedGroups { defineGroup(entry.name, entry.group, entry.rule) }
        checkGroups()
    }

    func unique(_ id: Identifier) {
        if ruleNames[id.name] != nil {
            raise("Duplicate definition of rule '\(id.name)'", id.start)
        }
        ruleNames[id.name] = id
    }

    func used(_ name: String) {
        ruleNames.removeValue(forKey: name)
    }

    func newName(_ base: String, _ nodeName: Any? = nil, _ props: Props = [:]) -> Term {
        let nodeNameStr: String? = nodeName as? String
        let startIdx = nodeName != nil ? 0 : 1
        for i in startIdx... {
            let name = i == 0 ? base : "\(base)-\(i)"
            if terms.names[name] == nil {
                return terms.makeNonTerminal(name, nodeNameStr, props)
            }
        }
        fatalError("unreachable")
    }

    func prepareParser() throws -> (
        states: [UInt32],
        stateData: [UInt16],
        goto: [UInt16],
        nodeNames: String,
        nodeProps: [(prop: String, terms: [Any])],
        skippedTypes: [Int],
        maxTerm: Int,
        repeatNodeCount: Int,
        tokenizers: [TokenizerSpecProtocol],
        tokenData: [UInt16],
        topRules: [String: [Int]],
        dialects: [String: Int],
        dynamicPrecedences: [Int: Int]?,
        specialized: [Any],
        tokenPrec: Int,
        termNames: [Int: String]
    ) {
        let simplifiedRules = try logTime("Simplify rules") {
            simplifyRules(rules, skipRules + terms.tops)
        }
        let (nodeTypes, names, minRepeatTerm, maxTerm) = try terms.finish(simplifiedRules)
        for (_, term) in namedTerms { termTable[namedTerms.first(where: { $0.value === term })?.key ?? ""] = term.id }
        for (name, term) in namedTerms { termTable[name] = term.id }

        if verbose.contains("grammar") {
            print(simplifiedRules.map { $0.description }.joined(separator: "\n"))
        }

        var startTerms = terms.tops
        let first = computeFirstSets(terms)
        let skipInfoArr: [SkipInfo] = skipRules.enumerated().map { id, name in
            var skip: [Term] = []
            var startTokens: [Term] = []
            var rules: [Rule] = []
            for rule in name.rules {
                if rule.parts.isEmpty { continue }
                let start = rule.parts[0]
                if start.terminal {
                    if !startTokens.contains(where: { $0 === start }) { startTokens.append(start) }
                } else {
                    for t in first[start.name] ?? [] {
                        if let t = t, !startTokens.contains(where: { $0 === t }) { startTokens.append(t) }
                    }
                }
                if start.terminal && rule.parts.count == 1 && !rules.contains(where: { $0 !== rule && $0.parts[0] === start }) {
                    skip.append(start)
                } else {
                    rules.append(rule)
                }
            }
            name.rules = rules
            if !rules.isEmpty { startTerms.append(name) }
            return SkipInfo(skip: skip, rule: rules.isEmpty ? nil : name, startTokens: startTokens, id: id)
        }
        let fullTable = try logTime("Build full automaton") {
            try buildFullAutomaton(terms, startTerms, first)
        }
        let localTokenSpecs = try localTokens.enumerated().map { (offset, grp) in
            try grp.buildLocalGroup(fullTable, skipInfoArr, offset)
        }
        let (tokenGroups, tokenPrec, tokenData) = try logTime("Build token groups") {
            try tokens.buildTokenGroups(fullTable, skipInfoArr, localTokens.count)
        }
        for ext in externalTokens { ext.checkConflicts(fullTable, skipInfoArr) }
        let table = try logTime("Finish automaton") { finishAutomaton(fullTable) }
        let skipState = findSkipStates(table, terms.tops)

        if verbose.contains("lr") {
            print(table.map { $0.description }.joined(separator: "\n"))
        }

        var specializedList: [Any] = []
        for ext in externalSpecializers { specializedList.append(ext) }
        for (name, entries) in specialized {
            let term = terms.names[name]
            if let term = term {
                specializedList.append(SpecializeTableEntry(token: term, table: buildSpecializeTable(entries)))
            }
        }

        func tokStart(_ tokenizer: TokenizerSpecProtocol) -> Int {
            if let ext = tokenizer as? ExternalTokenSet { return ext.ast.start }
            return tokens.ast?.start ?? -1
        }
        var allTokenizers: [TokenizerSpecProtocol] = []
        allTokenizers.append(contentsOf: tokenGroups)
        allTokenizers.append(contentsOf: externalTokens)
        allTokenizers.sort { tokStart($0) < tokStart($1) }
        allTokenizers.append(contentsOf: localTokenSpecs)

        let data = DataBuilder()
        let skipData = skipInfoArr.map { info in
            var actions: [Int] = []
            for term in info.skip {
                actions.append(term.id)
                actions.append(0)
                actions.append(Action.StayFlag >> 16)
            }
            if let rule = info.rule {
                if let state = table.first(where: { $0.startRule === rule }) {
                    for action in state.actions {
                        if let shift = action as? Shift {
                            actions.append(shift.term.id)
                            actions.append(state.id)
                            actions.append(Action.GotoFlag >> 16)
                        }
                    }
                }
            }
            actions.append(Seq.End)
            actions.append(Seq.Done)
            return data.storeArray(actions)
        }

        let stateArray = try logTime("Finish states") { () -> [UInt32] in
            var states = [UInt32](repeating: 0, count: table.count * ParseState.Size)
            let forceReductions = computeForceReductions(table, skipInfoArr)
            let finishCx = FinishStateContext(
                tokenizers: allTokenizers,
                data: data,
                stateArray: states,
                skipData: skipData,
                skipInfo: skipInfoArr,
                states: table,
                builder: self
            )
            for s in table {
                finishCx.finish(s, skipState(s.id), forceReductions[s.id])
            }
            return finishCx.stateArray
        }

        var dialectsDict: [String: Int] = [:]
        for i in 0..<dialects.count {
            let terms = (tokens.byDialect[i] ?? []).map { $0.id } + [Seq.End]
            dialectsDict[dialects[i]] = data.storeArray(terms)
        }

        var dynamicPrecedences: [Int: Int]? = nil
        if !dynamicRulePrecedences.isEmpty {
            dynamicPrecedences = [:]
            for entry in dynamicRulePrecedences { dynamicPrecedences![entry.rule.id] = entry.prec }
        }

        var topRulesDict: [String: [Int]] = [:]
        for term in terms.tops {
            if let nodeName = term.nodeName {
                if let state = table.first(where: { $0.startRule === term }) {
                    topRulesDict[nodeName] = [state.id, term.id]
                }
            }
        }

        let precTable = data.storeArray(tokenPrec + [Seq.End])
        let (nodeProps, skippedTypes) = try gatherNodeProps(nodeTypes)

        return (
            states: stateArray,
            stateData: data.finish(),
            goto: computeGotoTable(table),
            nodeNames: nodeTypes.filter { $0.id < minRepeatTerm }.map { $0.nodeName ?? "" }.joined(separator: " "),
            nodeProps: nodeProps,
            skippedTypes: skippedTypes,
            maxTerm: maxTerm,
            repeatNodeCount: nodeTypes.count - minRepeatTerm,
            tokenizers: allTokenizers,
            tokenData: tokenData,
            topRules: topRulesDict,
            dialects: dialectsDict,
            dynamicPrecedences: dynamicPrecedences,
            specialized: specializedList,
            tokenPrec: precTable,
            termNames: names
        )
    }

    func getParser() throws -> LRParser {
        let result = try prepareParser()

        var specializedSpecs: [LRParser.SpecializerSpec] = []
        for v in result.specialized {
            if let ext = v as? ExternalSpecializer {
                guard let factory = options.externalSpecializer else {
                    fatalError("External specializer '\(ext.ast.id.name)' requested but no externalSpecializer option provided")
                }
                let extFn = factory(ext.ast.id.name, termTable)
                let isExtend = ext.ast.type == "extend"
                specializedSpecs.append(LRParser.SpecializerSpec(
                    term: ext.term!.id,
                    get: { value, stack in (extFn(value, stack) << 1) | (isExtend ? Specialize.Extend : Specialize.Specialize) },
                    external: extFn,
                    extend: isExtend
                ))
            } else if let entry = v as? SpecializeTableEntry {
                specializedSpecs.append(LRParser.SpecializerSpec(
                    term: entry.token.id,
                    get: { value, _ in entry.table[value] ?? -1 },
                    external: nil,
                    extend: false
                ))
            }
        }

        let nodePropArrays: [[Any]] = result.nodeProps.map { prop, terms in
            [knownProps[prop]!.prop] + terms
        }

        var propSources: [NodePropSource]? = nil
        if let factory = options.externalPropSource {
            propSources = ast.externalPropSources.map { factory($0.id.name) }
        }

        let spec = LRParser.ParserSpec(
            version: LrFile.Version,
            states: result.states,
            stateData: result.stateData,
            goto: result.goto,
            nodeNames: result.nodeNames,
            maxTerm: result.maxTerm,
            repeatNodeCount: result.repeatNodeCount,
            nodeProps: nodePropArrays.isEmpty ? nil : nodePropArrays,
            propSources: propSources,
            skippedNodes: result.skippedTypes.isEmpty ? nil : result.skippedTypes,
            tokenData: result.tokenData,
            tokenizers: result.tokenizers.map { $0.create() },
            topRules: result.topRules,
            context: options.contextTracker,
            dialects: result.dialects.isEmpty ? nil : result.dialects,
            dynamicPrecedences: result.dynamicPrecedences,
            specialized: specializedSpecs.isEmpty ? nil : specializedSpecs,
            tokenPrec: result.tokenPrec,
            termNames: result.termNames
        )
        return LRParser(spec: spec)
    }

    func gatherNonSkippedNodes() -> [Int: Bool] {
        var seen: [Int: Bool] = [:]
        var work: [Term] = []
        func add(_ term: Term) {
            if seen[term.id] == nil {
                seen[term.id] = true
                work.append(term)
            }
        }
        for term in terms.tops { add(term) }
        var i = 0
        while i < work.count {
            for rule in work[i].rules {
                for part in rule.parts { add(part) }
            }
            i += 1
        }
        return seen
    }

    func gatherNodeProps(_ nodeTypes: [Term]) throws -> (nodeProps: [(prop: String, terms: [Any])], skippedTypes: [Int]) {
        let notSkipped = gatherNonSkippedNodes()
        var skippedTypes: [Int] = []
        var nodeProps: [(prop: String, values: [String: [Int]])] = []
        for type in nodeTypes {
            if notSkipped[type.id] == nil && !type.error { skippedTypes.append(type.id) }
            for (prop, value) in type.props {
                guard let known = knownProps[prop] else {
                    throw GenError("No known prop type for \(prop)")
                }
                if known.source.from == nil && (known.source.name == "repeated" || known.source.name == "error") {
                    continue
                }
                var rec = nodeProps.first(where: { $0.prop == prop })
                if rec == nil {
                    nodeProps.append((prop: prop, values: [:]))
                    rec = nodeProps[nodeProps.count - 1]
                }
                if rec!.values[value] == nil { rec!.values[value] = [] }
                rec!.values[value]!.append(type.id)
            }
        }
        let result = nodeProps.map { prop, values -> (prop: String, terms: [Any]) in
            var terms: [Any] = []
            for (val, ids) in values {
                if ids.count == 1 {
                    terms.append(ids[0])
                    terms.append(val)
                } else {
                    terms.append(-ids.count)
                    for id in ids { terms.append(id) }
                    terms.append(val)
                }
            }
            return (prop: prop, terms: terms)
        }
        return (nodeProps: result, skippedTypes: skippedTypes)
    }

    func makeTerminal(_ name: String, _ nodeName: String?, _ props: Props) -> Term {
        return terms.makeTerminal(terms.uniqueName(name), nodeName, props)
    }

    func computeForceReductions(_ states: [AutState], _ skipInfo: [SkipInfo]) -> [Int] {
        var reductions: [Int] = []
        var candidates: [[Pos]] = []
        var gotoEdges: [Int: [(parents: [Int], target: Int)]] = [:]

        for state in states {
            reductions.append(0)
            for edge in state.gotoActions {
                if gotoEdges[edge.term.id] == nil { gotoEdges[edge.term.id] = [] }
                var array = gotoEdges[edge.term.id]!
                if let found = array.firstIndex(where: { $0.target == edge.target.id }) {
                    array[found].parents.append(state.id)
                } else {
                    array.append((parents: [state.id], target: edge.target.id))
                }
                gotoEdges[edge.term.id] = array
            }
            candidates.append(
                state.set.filter { $0.pos > 0 && !$0.rule.name.top }
                    .sorted { $0.pos > $1.pos || ($0.pos == $1.pos && $0.rule.parts.count < $1.rule.parts.count) }
            )
        }

        var length1Reductions: [Int: Int] = [:]
        func createsCycle(_ term: Int, _ startState: Int, _ parents: [Int]? = nil) -> Bool {
            guard let edges = gotoEdges[term] else { return false }
            return edges.contains { val in
                let parentIntersection: [Int]
                if let parents = parents {
                    parentIntersection = parents.filter { p in val.parents.contains(p) }
                } else {
                    parentIntersection = val.parents
                }
                if parentIntersection.isEmpty { return false }
                if val.target == startState { return true }
                if let found = length1Reductions[val.target] {
                    return createsCycle(found, startState, parentIntersection)
                }
                return false
            }
        }

        for state in states {
            if let dr = state.defaultReduce, dr.parts.count > 0 {
                reductions[state.id] = reduceAction(dr, skipInfo)
                if dr.parts.count == 1 {
                    length1Reductions[state.id] = dr.name.id
                }
            }
        }

        var setSize = 1
        while true {
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
                        reductions[state.id] = reduceAction(pos.rule, skipInfo, pos.pos)
                        if pos.pos == 1 { length1Reductions[state.id] = pos.rule.name.id }
                        break
                    }
                }
            }
            if done { break }
            setSize += 1
        }
        return reductions
    }

    func substituteArgs(_ expr: Expression, _ args: [Expression], _ params: [Identifier]) -> Expression {
        if args.isEmpty { return expr }
        return expr.walk { e in
            if let nameExpr = e as? NameExpression {
                if let found = params.firstIndex(where: { $0.name == nameExpr.id.name }) {
                    let arg = args[found]
                    if !nameExpr.args.isEmpty {
                        if let argName = arg as? NameExpression, argName.args.isEmpty {
                            return NameExpression(start: nameExpr.start, id: argName.id, args: nameExpr.args)
                        }
                        self.raise("Passing arguments to a parameter that already has arguments", nameExpr.start)
                    }
                    return arg
                }
            } else if let inlineExpr = e as? InlineRuleExpression {
                let r = inlineExpr.rule
                let newProps = self.substituteArgsInProps(r.props, args, params)
                if Prop.eqProps(newProps, r.props) {
                    return e
                }
                return InlineRuleExpression(start: inlineExpr.start, rule: RuleDeclaration(
                    start: r.start, id: r.id, props: newProps, params: r.params, expr: r.expr
                ))
            } else if let specExpr = e as? SpecializeExpression {
                let newProps = self.substituteArgsInProps(specExpr.props, args, params)
                if Prop.eqProps(newProps, specExpr.props) {
                    return e
                }
                return SpecializeExpression(
                    start: specExpr.start, type: specExpr.type, props: newProps,
                    token: specExpr.token, content: specExpr.content
                )
            }
            return e
        }
    }

    func substituteArgsInProps(_ props: [Prop], _ args: [Expression], _ params: [Identifier]) -> [Prop] {
        func substituteInValue(_ value: [PropPart]) -> [PropPart]? {
            var changed = false
            var result = value
            for i in 0..<value.count {
                let part = value[i]
                guard let name = part.name else { continue }
                guard let pos = params.firstIndex(where: { $0.name == name }) else { continue }
                if !changed { result = value; changed = true }
                let expr = args[pos]
                if let argName = expr as? NameExpression, argName.args.isEmpty {
                    result[i] = PropPart(start: part.start, value: argName.id.name, name: nil)
                } else if let litExpr = expr as? LiteralExpression {
                    result[i] = PropPart(start: part.start, value: litExpr.value, name: nil)
                } else {
                    raise("Trying to interpolate expression '\(expr)' into a prop", part.start)
                }
            }
            return changed ? result : nil
        }
        var result = props
        var changed = false
        for i in 0..<props.count {
            let prop = props[i]
            if let newValue = substituteInValue(prop.value) {
                if !changed { result = props; changed = true }
                result[i] = Prop(start: prop.start, at: prop.at, name: prop.name, value: newValue)
            }
        }
        return result
    }

    func conflictsFor(_ markers: [ConflictMarker]) -> (here: Conflicts, atEnd: Conflicts) {
        var here = Conflicts.none
        var atEnd = Conflicts.none
        for marker in markers {
            if marker.type == .ambig {
                here = here.join(Conflicts(precedence: 0, [marker.id.name]))
            } else {
                guard let precs = ast.precedences else {
                    raise("Reference to unknown precedence: '\(marker.id.name)'", marker.id.start)
                }
                let index = precs.items.firstIndex(where: { $0.id.name == marker.id.name })
                guard let index = index else {
                    raise("Reference to unknown precedence: '\(marker.id.name)'", marker.id.start)
                }
                let value = precs.items.count - index
                let prec = precs.items[index]
                if prec.type == .cut {
                    here = here.join(Conflicts(precedence: 0, cut: value))
                } else {
                    here = here.join(Conflicts(precedence: value << 2))
                    let endValue = (value << 2) + (prec.type == .left ? 1 : prec.type == .right ? -1 : 0)
                    atEnd = atEnd.join(Conflicts(precedence: endValue))
                }
            }
        }
        return (here: here, atEnd: atEnd)
    }

    func raise(_ message: String, _ pos: Int = 1) -> Never {
        input.raise(message, pos)
    }

    func warn(_ message: String, _ pos: Int = -1) {
        let msg = input.message(message, pos)
        if let warnFn = options.warn { warnFn(msg) }
        else { print(msg) }
    }

    func defineRule(_ name: Term, _ choices: [Parts]) {
        let skip = currentSkip[currentSkip.count - 1]
        for choice in choices {
            rules.append(Rule(name: name, parts: choice.terms, conflicts: choice.ensureConflicts(), skip: skip))
        }
    }

    func resolve(_ expr: NameExpression) -> [Parts] {
        for builtRule in built where builtRule.matches(expr) { return [p(builtRule.term)] }

        if let found = tokens.getToken(expr) { return [p(found)] }
        for grp in localTokens {
            if let found = grp.getToken(expr) { return [p(found)] }
        }
        for ext in externalTokens {
            if let found = ext.getToken(expr) { return [p(found)] }
        }
        for ext in externalSpecializers {
            if let found = ext.getToken(expr) { return [p(found)] }
        }

        guard let known = astRules.first(where: { $0.rule.id.name == expr.id.name }) else {
            raise("Reference to undefined rule '\(expr.id.name)'", expr.start)
        }
        if known.rule.params.count != expr.args.count {
            raise("Wrong number of arguments for '\(expr.id.name)'", expr.start)
        }
        used(known.rule.id.name)
        return [p(buildRule(known.rule, expr.args, known.skip))]
    }

    func normalizeRepeat(_ expr: RepeatExpression) -> Parts {
        if let known = built.first(where: { $0.matchesRepeat(expr) }) { return p(known.term) }

        let name = expr.expr.prec < expr.prec ? "(\(expr.expr))+" : "\(expr.expr)+"
        let term = terms.makeRepeat(terms.uniqueName(name))
        built.append(BuiltRule(id: "+", args: [expr.expr], term: term))

        defineRule(term, normalizeExpr(expr.expr) + [p(term, term)])
        return p(term)
    }

    func normalizeSequence(_ expr: SequenceExpression) -> [Parts] {
        let result: [[Parts]] = expr.exprs.map { normalizeExpr($0) }
        func complete(_ start: Parts, _ from: Int, _ endConflicts: Conflicts) -> [Parts] {
            let conflicts = conflictsFor(expr.markers[from])
            if from == result.count {
                return [start.withConflicts(start.terms.count, conflicts.here.join(endConflicts))]
            }
            var choices: [Parts] = []
            for choice in result[from] {
                for full in complete(
                    start.concat(choice).withConflicts(start.terms.count, conflicts.here),
                    from + 1,
                    endConflicts.join(conflicts.atEnd)
                ) {
                    choices.append(full)
                }
            }
            return choices
        }
        return complete(Parts.none, 0, Conflicts.none)
    }

    func normalizeExpr(_ expr: Expression) -> [Parts] {
        if let repeatExpr = expr as? RepeatExpression, repeatExpr.kind == .optional {
            return [Parts.none] + normalizeExpr(repeatExpr.expr)
        } else if let repeatExpr = expr as? RepeatExpression {
            let repeated = normalizeRepeat(repeatExpr)
            return repeatExpr.kind == .plus ? [repeated] : [Parts.none, repeated]
        } else if let choiceExpr = expr as? ChoiceExpression {
            return choiceExpr.exprs.reduce([]) { $0 + normalizeExpr($1) }
        } else if let seqExpr = expr as? SequenceExpression {
            return normalizeSequence(seqExpr)
        } else if let litExpr = expr as? LiteralExpression {
            return [p(tokens.getLiteral(litExpr))]
        } else if let nameExpr = expr as? NameExpression {
            return resolve(nameExpr)
        } else if let specExpr = expr as? SpecializeExpression {
            return [p(resolveSpecialization(specExpr))]
        } else if let inlineExpr = expr as? InlineRuleExpression {
            return [p(buildRule(
                inlineExpr.rule, [],
                currentSkip[currentSkip.count - 1], true
            ))]
        } else {
            raise("This type of expression ('\(expr)') may not occur in non-token rules", expr.start)
        }
    }

    func buildRule(_ rule: RuleDeclaration, _ args: [Expression], _ skip: Term, _ inline: Bool = false) -> Term {
        let expr = substituteArgs(rule.expr, args, rule.params)
        let info = nodeInfo(
            rule.params.isEmpty && rule.props.isEmpty ? [] : rule.props,
            inline ? "pg" : "pgi",
            rule.id.name,
            args,
            rule.params,
            rule.expr
        )
        if info.exported != nil && !rule.params.isEmpty { warn("Can't export parameterized rules", rule.start) }
        if info.exported != nil && inline { warn("Can't export inline rule", rule.start) }
        let name = newName(
            rule.id.name + (args.isEmpty ? "" : "<\(args.map { $0.description }.joined(separator: ","))>"),
            info.name ?? true,
            info.props
        )
        if info.isInline { name.inline = true }
        if info.dynamicPrec != 0 { registerDynamicPrec(name, info.dynamicPrec) }
        if (name.nodeType || info.exported != nil) && rule.params.isEmpty {
            if info.name == nil { name.preserve = true }
            if !inline { namedTerms[info.exported ?? rule.id.name] = name }
        }

        if !inline { built.append(BuiltRule(id: rule.id.name, args: args, term: name)) }
        currentSkip.append(skip)
        let parts = normalizeExpr(expr)
        if parts.count > 100 * (expr is ChoiceExpression ? (expr as! ChoiceExpression).exprs.count : 1) {
            warn(
                "Rule \(rule.id.name) is generating a lot (\(parts.count)) of choices.\n  Consider splitting it up or reducing the amount of ? or | operator uses.",
                rule.start
            )
        }
        if verbose.contains("rulesize") && parts.count > 10 {
            print("Rule \(rule.id.name): \(parts.count) variants")
        }
        defineRule(name, parts)
        currentSkip.removeLast()
        if let group = info.group { definedGroups.append((name: name, group: group, rule: rule)) }
        return name
    }

    func nodeInfo(
        _ props: [Prop],
        _ allow: String,
        _ defaultName: String? = nil,
        _ args: [Expression] = [],
        _ params: [Identifier] = [],
        _ expr: Expression? = nil,
        _ defaultProps: Props? = nil
    ) -> (name: String?, props: Props, dialect: Int?, dynamicPrec: Int, isInline: Bool, group: String?, exported: String?) {
        var result: Props = [:]
        var name = defaultName
        if let dn = defaultName, (allow.contains("a") || !isIgnored(dn)) && !dn.contains(" ") {
            name = dn
        } else {
            name = nil
        }
        var dialect: Int? = nil
        var dynamicPrec = 0
        var isInline = false
        var group: String? = nil
        var exported: String? = nil

        for prop in props {
            if !prop.at {
                if knownProps[prop.name] == nil {
                    let builtinNames = ["name", "dialect", "dynamicPrecedence", "export", "isGroup"]
                    let hint = builtinNames.contains(prop.name) ? " (did you mean '@\(prop.name)'?)" : ""
                    raise("Unknown prop name '\(prop.name)'\(hint)", prop.start)
                }
                result[prop.name] = finishProp(prop, args, params)
            } else if prop.name == "name" {
                name = finishProp(prop, args, params)
                if let n = name, n.contains(" ") { raise("Node names cannot have spaces ('\(n)')", prop.start) }
            } else if prop.name == "dialect" {
                if !allow.contains("d") { raise("Can't specify a dialect on non-token rules", props[0].start) }
                if prop.value.count != 1 && prop.value[0].value == nil {
                    raise("The '@dialect' rule prop must hold a plain string value")
                }
                let dialectName = prop.value[0].value ?? ""
                let dialectID = dialects.firstIndex(of: dialectName)
                if let dialectID = dialectID {
                    dialect = dialectID
                } else {
                    raise("Unknown dialect '\(dialectName)'", prop.value[0].start)
                }
            } else if prop.name == "dynamicPrecedence" {
                if !allow.contains("p") { raise("Dynamic precedence can only be specified on nonterminals") }
                let val = prop.value[0].value ?? ""
                if prop.value.count != 1 || !(val.matchesRegex("^-?(?:10|\\d)$")) {
                    raise("The '@dynamicPrecedence' rule prop must hold an integer between -10 and 10")
                }
                dynamicPrec = Int(prop.value[0].value!)!
            } else if prop.name == "inline" {
                if !prop.value.isEmpty { raise("'@inline' doesn't take a value", prop.value[0].start) }
                if !allow.contains("i") { raise("Inline can only be specified on nonterminals") }
                isInline = true
            } else if prop.name == "isGroup" {
                if !allow.contains("g") { raise("'@isGroup' can only be specified on nonterminals") }
                group = !prop.value.isEmpty ? finishProp(prop, args, params) : defaultName
            } else if prop.name == "export" {
                exported = !prop.value.isEmpty ? finishProp(prop, args, params) : defaultName
            } else {
                raise("Unknown built-in prop name '@\(prop.name)'", prop.start)
            }
        }
        if let expr = expr, ast.autoDelim, let name = name, hasProps(result) || name != nil {
            if let delim = findDelimiters(expr) {
                addToProp(delim.0, "closedBy", delim.1.nodeName!)
                addToProp(delim.1, "openedBy", delim.0.nodeName!)
            }
        }
        if let defaultProps = defaultProps, hasProps(defaultProps) {
            for (prop, value) in defaultProps { if result[prop] == nil { result[prop] = value } }
        }
        if hasProps(result) && name == nil {
            raise("Node has properties but no name", props.isEmpty ? expr!.start : props[0].start)
        }
        if isInline && (hasProps(result) || dialect != nil || dynamicPrec != 0) {
            raise("Inline nodes can't have props, dynamic precedence, or a dialect", props[0].start)
        }
        if isInline { name = nil }
        return (name: name, props: result, dialect: dialect, dynamicPrec: dynamicPrec, isInline: isInline, group: group, exported: exported)
    }

    func finishProp(_ prop: Prop, _ args: [Expression], _ params: [Identifier]) -> String {
        return prop.value.map { part in
            if let value = part.value { return value }
            guard let pos = params.firstIndex(where: { $0.name == part.name }) else {
                raise("Property refers to '\(part.name ?? "")', but no parameter by that name is in scope", part.start)
            }
            let expr = args[pos]
            if let nameExpr = expr as? NameExpression, nameExpr.args.isEmpty { return nameExpr.id.name }
            if let litExpr = expr as? LiteralExpression { return litExpr.value }
            raise("Expression '\(expr)' can not be used as part of a property value", part.start)
        }.joined()
    }

    func resolveSpecialization(_ expr: SpecializeExpression) -> Term {
        let type = expr.type
        let info = nodeInfo(expr.props, "d")
        let terminal = normalizeExpr(expr.token)
        if terminal.count != 1 || terminal[0].terms.count != 1 || !terminal[0].terms[0].terminal {
            raise("The first argument to '\(type)' must resolve to a token", expr.token.start)
        }
        let values: [String]
        if let lit = isLiteralToken(expr.content) {
            values = [lit]
        } else if let choiceExpr = expr.content as? ChoiceExpression,
                  choiceExpr.exprs.allSatisfy({ isLiteralToken($0) != nil }) {
            values = choiceExpr.exprs.map { isLiteralToken($0)! }
        } else {
            raise("The second argument to '\(expr.type)' must be a literal or choice of literals", expr.content.start)
        }

        let term = terminal[0].terms[0]
        var token: Term? = nil
        if specialized[term.name] == nil { specialized[term.name] = [] }
        let table = specialized[term.name]!
        for value in values {
            if let known = table.first(where: { $0.value == value }) {
                if known.type != type {
                    raise("Conflicting specialization types for \(stringToJSON(value)) of \(term.name) (\(type) vs \(known.type))", expr.start)
                }
                if known.dialect != info.dialect {
                    raise("Conflicting dialects for specialization \(stringToJSON(value)) of \(term.name)", expr.start)
                }
                if known.name != info.name {
                    raise("Conflicting names for specialization \(stringToJSON(value)) of \(term.name)", expr.start)
                }
                if let token = token, known.term !== token {
                    raise("Conflicting specialization tokens for \(stringToJSON(value)) of \(term.name)", expr.start)
                }
                token = known.term
            } else {
                if token == nil {
                    token = makeTerminal(term.name + "/" + stringToJSON(value), info.name, info.props)
                    if let dialect = info.dialect {
                        if tokens.byDialect[dialect] == nil { tokens.byDialect[dialect] = [] }
                        tokens.byDialect[dialect]!.append(token!)
                    }
                }
                specialized[term.name]!.append(SpecializedEntry(
                    value: value, name: info.name, term: token!, type: type, dialect: info.dialect
                ))
                tokenOrigins[token!.name] = TokenOrigin(spec: term, external: nil, group: nil)
                if info.name != nil || info.exported != nil {
                    if info.name == nil { token!.preserve = true }
                    namedTerms[info.exported ?? info.name!] = token!
                }
            }
        }
        return token!
    }

    func findDelimiters(_ expr: Expression) -> (Term, Term)? {
        guard let seq = expr as? SequenceExpression, seq.exprs.count >= 2 else { return nil }
        func findToken(_ e: Expression) -> (term: Term, str: String)? {
            if let litExpr = e as? LiteralExpression {
                return (term: tokens.getLiteral(litExpr), str: litExpr.value)
            }
            if let nameExpr = e as? NameExpression, nameExpr.args.isEmpty {
                if let rule = ast.rules.first(where: { $0.id.name == nameExpr.id.name }) {
                    return findToken(rule.expr)
                }
                if let tokenRule = tokens.rules.first(where: { $0.id.name == nameExpr.id.name }),
                   let litExpr = tokenRule.expr as? LiteralExpression {
                    guard let term = tokens.getToken(nameExpr) else { return nil }
                    return (term: term, str: litExpr.value)
                }
            }
            return nil
        }
        guard let lastToken = findToken(seq.exprs[seq.exprs.count - 1]),
              lastToken.term.nodeName != nil else { return nil }
        let brackets = ["()", "[]", "{}", "<>"]
        guard let bracket = brackets.first(where: {
            lastToken.str.contains($0[$0.index($0.startIndex, offsetBy: 1)]) &&
            !lastToken.str.contains($0[$0.startIndex])
        }) else { return nil }
        guard let firstToken = findToken(seq.exprs[0]),
              firstToken.term.nodeName != nil,
              firstToken.str.contains(bracket[bracket.startIndex]),
              !firstToken.str.contains(bracket[bracket.index(bracket.startIndex, offsetBy: 1)]) else { return nil }
        return (firstToken.term, lastToken.term)
    }

    func registerDynamicPrec(_ term: Term, _ prec: Int) {
        dynamicRulePrecedences.append((rule: term, prec: prec))
        term.preserve = true
    }

    func defineGroup(_ rule: Term, _ group: String, _ ast: RuleDeclaration) {
        var recur: [Term] = []
        func getNamed(_ rule: Term) -> [Term] {
            if rule.nodeName != nil { return [rule] }
            if recur.contains(where: { $0 === rule }) {
                raise("Rule '\(ast.id.name)' cannot define a group because it contains a non-named recursive rule ('\(rule.name)')", ast.start)
            }
            var result: [Term] = []
            recur.append(rule)
            for r in rules where r.name === rule {
                let names = r.parts.map(getNamed).filter { !$0.isEmpty }
                if names.count > 1 {
                    raise("Rule '\(ast.id.name)' cannot define a group because some choices produce multiple named nodes", ast.start)
                }
                if let first = names.first { result.append(contentsOf: first) }
            }
            recur.removeAll { $0 === rule }
            return result
        }

        for name in getNamed(rule) {
            let existing = name.props["group"]?.split(separator: " ").map(String.init) ?? []
            let newGroups = (existing + [group]).sorted()
            name.props["group"] = newGroups.joined(separator: " ")
        }
    }

    func checkGroups() {
        var groups: [String: [Term]] = [:]
        var nodeNames: Set<String> = []
        for term in terms.terms {
            if let nodeName = term.nodeName {
                nodeNames.insert(nodeName)
                if let groupStr = term.props["group"] {
                    for g in groupStr.split(separator: " ").map(String.init) {
                        if groups[g] == nil { groups[g] = [] }
                        groups[g]!.append(term)
                    }
                }
            }
        }
        let names = Array(groups.keys)
        for i in 0..<names.count {
            let name = names[i]
            let terms = groups[name]!
            if nodeNames.contains(name) { warn("Group name '\(name)' conflicts with a node of the same name") }
            for j in (i + 1)..<names.count {
                let other = groups[names[j]]!
                if terms.contains(where: { t in other.contains(where: { $0 === t }) }) &&
                    (terms.count > other.count
                        ? other.contains(where: { t in !terms.contains(where: { $0 === t }) })
                        : terms.contains(where: { t in !other.contains(where: { $0 === t }) })) {
                    warn("Groups '\(name)' and '\(names[j])' overlap without one being a superset of the other")
                }
            }
        }
    }
}

// MARK: - Free Functions

func isLiteralToken(_ expr: Expression) -> String? {
    if let litExpr = expr as? LiteralExpression { return litExpr.value }
    if let seqExpr = expr as? SequenceExpression {
        var result = ""
        for sub in seqExpr.exprs {
            guard let lit = isLiteralToken(sub) else { return nil }
            result += lit
        }
        return result
    }
    return nil
}

func isExprEmpty(_ expr: Expression) -> Bool {
    guard let seq = expr as? SequenceExpression else { return false }
    return seq.exprs.isEmpty
}

func stringToJSON(_ s: String) -> String {
    var result = "\""
    for ch in s {
        switch ch {
        case "\"": result += "\\\""
        case "\\": result += "\\\\"
        case "\n": result += "\\n"
        case "\r": result += "\\r"
        case "\t": result += "\\t"
        default: result += String(ch)
        }
    }
    return result + "\""
}

func addToProp(_ term: Term, _ prop: String, _ value: String) {
    let cur = term.props[prop]
    if cur == nil || !cur!.components(separatedBy: " ").contains(value) {
        term.props[prop] = cur != nil ? cur! + " " + value : value
    }
}

func buildSpecializeTable(_ spec: [SpecializedEntry]) -> [String: Int] {
    var table: [String: Int] = [:]
    for entry in spec {
        let code = entry.type == "specialize" ? Specialize.Specialize : Specialize.Extend
        table[entry.value] = (entry.term.id << 1) | code
    }
    return table
}

func reduceAction(_ rule: Rule, _ skipInfo: [SkipInfo], _ depth: Int? = nil) -> Int {
    let d = depth ?? rule.parts.count
    return rule.name.id
        | Action.ReduceFlag
        | (rule.isRepeatWrap && d == rule.parts.count ? Action.RepeatFlag : 0)
        | (skipInfo.contains { $0.rule != nil && $0.rule! === rule.name } ? Action.StayFlag : 0)
        | (d << Action.ReduceDepthShift)
}

func findArray(_ data: [Int], _ value: [Int]) -> Int {
    guard !value.isEmpty else { return 0 }
    var i = 0
    while i + value.count <= data.count {
        let slice = data[i..<(i + value.count)]
        if slice.elementsEqual(value) { return i }
        i += 1
    }
    return -1
}

func findSkipStates(_ table: [AutState], _ startRules: [Term]) -> (Int) -> Bool {
    var nonSkip = Set<Int>()
    for state in table {
        if let sr = state.startRule, startRules.contains(where: { $0 === sr }) {
            nonSkip.insert(state.id)
        }
    }
    var work = Array(nonSkip.map { table[$0] })
    var idx = 0
    while idx < work.count {
        let state = work[idx]; idx += 1
        for a in state.actions {
            if let shift = a as? Shift {
                if !nonSkip.contains(shift.target.id) {
                    nonSkip.insert(shift.target.id)
                    work.append(shift.target)
                }
            }
        }
        for a in state.gotoActions {
            if !nonSkip.contains(a.target.id) {
                nonSkip.insert(a.target.id)
                work.append(a.target)
            }
        }
    }
    return { id in !nonSkip.contains(id) }
}

func computeGotoTable(_ states: [AutState]) -> [UInt16] {
    var goto: [Int: [Int: [Int]]] = [:]
    var maxTerm = 0
    for state in states {
        for entry in state.gotoActions {
            maxTerm = max(entry.term.id, maxTerm)
            if goto[entry.term.id] == nil { goto[entry.term.id] = [:] }
            if goto[entry.term.id]![entry.target.id] == nil { goto[entry.term.id]![entry.target.id] = [] }
            goto[entry.term.id]![entry.target.id]!.append(state.id)
        }
    }
    let data = DataBuilder()
    var index: [Int] = []
    let offset = maxTerm + 2

    for term in 0...maxTerm {
        guard let entries = goto[term] else {
            index.append(1)
            continue
        }
        var termTable: [Int] = []
        let keys = Array(entries.keys)
        for (ki, target) in keys.enumerated() {
            let list = entries[target]!
            termTable.append((ki == keys.count - 1 ? 1 : 0) + (list.count << 1))
            termTable.append(target)
            for source in list { termTable.append(source) }
        }
        index.append(data.storeArray(termTable) + offset)
    }
    if index.contains(where: { $0 > 0xffff }) { fatalError("Goto table too large") }

    var result: [UInt16] = [UInt16(maxTerm + 1)]
    result.append(contentsOf: index.map { UInt16(truncatingIfNeeded: $0) })
    result.append(contentsOf: data.data.map { UInt16(truncatingIfNeeded: $0) })
    return result
}

func buildTokenMasks(_ groups: [BuildTokenGroup]) -> [Int: Int] {
    var masks: [Int: Int] = [:]
    for group in groups {
        let groupMask = 1 << (group.groupID ?? 0)
        for term in group.tokens {
            masks[term.id] = (masks[term.id] ?? 0) | groupMask
        }
    }
    return masks
}

func checkTogether(_ states: [AutState], _ b: Builder, _ skipInfo: [SkipInfo]) -> (Term, Term) -> Bool {
    var cache: [Int: Bool] = [:]
    func hasTerm(_ state: AutState, _ term: Term) -> Bool {
        return state.actions.contains(where: { actionTerm($0) === term }) ||
            skipInfo[b.skipRules.firstIndex(where: { $0 === state.skip }) ?? 0].startTokens.contains(where: { $0 === term })
    }
    return { (a: Term, b: Term) -> Bool in
        var (a, b) = (a, b)
        if a.id < b.id { swap(&a, &b) }
        let key = a.id | (b.id << 16)
        if let cached = cache[key] { return cached }
        let result = states.contains { state in hasTerm(state, a) && hasTerm(state, b) }
        cache[key] = result
        return result
    }
}

func invertRanges(_ ranges: [(Int, Int)]) -> [(Int, Int)] {
    var pos = 0
    var result: [(Int, Int)] = []
    for (a, b) in ranges {
        if a > pos { result.append((pos, a)) }
        pos = b
    }
    if pos <= MAX_CODE { result.append((pos, MAX_CODE + 1)) }
    return result
}

func rangeEdges(_ from: State, _ to: State, _ low: Int, _ hi: Int) {
    var low = low, hi = hi
    if low < ASTRAL_CODE {
        if low < GAP_START { from.edge(low, min(hi, GAP_START), to) }
        if hi > GAP_END { from.edge(max(low, GAP_END), min(hi, MAX_CHAR + 1), to) }
        low = ASTRAL_CODE
    }
    if hi <= ASTRAL_CODE { return }

    let lowScalar = Unicode.Scalar(low)!
    let hiScalar = Unicode.Scalar(hi - 1)!
    let lowStr = String(lowScalar)
    let hiStr = String(hiScalar)
    let lowA = lowStr.utf16.first!
    let lowB = lowStr.utf16.last!
    let hiA = hiStr.utf16.first!
    let hiB = hiStr.utf16.last!
    if lowA == hiA {
        let hop = State()
        from.edge(Int(lowA), Int(lowA) + 1, hop)
        hop.edge(Int(lowB), Int(hiB) + 1, to)
    } else {
        var midStart = Int(lowA)
        var midEnd = Int(hiA)
        if Int(lowB) > LOW_SURR_B {
            midStart += 1
            let hop = State()
            from.edge(Int(lowA), Int(lowA) + 1, hop)
            hop.edge(Int(lowB), HIGH_SURR_B + 1, to)
        }
        if Int(hiB) < HIGH_SURR_B {
            midEnd -= 1
            let hop = State()
            from.edge(Int(hiA), Int(hiA) + 1, hop)
            hop.edge(LOW_SURR_B, Int(hiB) + 1, to)
        }
        if midStart <= midEnd {
            let hop = State()
            from.edge(midStart, midEnd + 1, hop)
            hop.edge(LOW_SURR_B, HIGH_SURR_B + 1, to)
        }
    }
}

func gatherExtTokens(_ b: Builder, _ tokens: [(id: Identifier, props: [Prop])]) -> [String: Term] {
    var result: [String: Term] = [:]
    for token in tokens {
        b.unique(token.id)
        let info = b.nodeInfo(token.props, "d", token.id.name)
        let term = b.makeTerminal(token.id.name, info.name, info.props)
        if let dialect = info.dialect {
            if b.tokens.byDialect[dialect] == nil { b.tokens.byDialect[dialect] = [] }
            b.tokens.byDialect[dialect]!.append(term)
        }
        b.namedTerms[token.id.name] = term
        result[token.id.name] = term
    }
    return result
}

func findExtToken(_ b: Builder, _ tokens: [String: Term], _ expr: NameExpression) -> Term? {
    guard let found = tokens[expr.id.name] else { return nil }
    if !expr.args.isEmpty { b.raise("External tokens cannot take arguments", expr.args[0].start) }
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

func inlineRules(_ rules: [Rule], _ preserve: [Term]) -> [Rule] {
    var rules = rules
    var pass = 0
    while true {
        var inlinable: [String: [Rule]] = [:]
        var found = false
        if pass == 0 {
            for rule in rules {
                if rule.name.inline && inlinable[rule.name.name] == nil {
                    let group = rules.filter { $0.name === rule.name }
                    if group.contains(where: { $0.parts.contains(where: { $0 === rule.name }) }) { continue }
                    inlinable[rule.name.name] = group
                    found = true
                }
            }
        }
        for i in 0..<rules.count {
            let rule = rules[i]
            if !rule.name.interesting &&
                !rule.parts.contains(where: { $0 === rule.name }) &&
                rule.parts.count < 3 &&
                !preserve.contains(where: { $0 === rule.name }) &&
                (rule.parts.count == 1 ||
                    rules.allSatisfy({ other in other.skip === rule.skip || !other.parts.contains(where: { $0 === rule.name }) })) &&
                !rule.parts.contains(where: { p in inlinable[p.name] != nil }) &&
                !rules.enumerated().contains(where: { j, r in j != i && r.name === rule.name }) {
                inlinable[rule.name.name] = [rule]
                found = true
            }
        }
        if !found { return rules }
        var newRules: [Rule] = []
        for rule in rules {
            if inlinable[rule.name.name] != nil { continue }
            if !rule.parts.contains(where: { inlinable[$0.name] != nil }) {
                newRules.append(rule)
                continue
            }
            func expand(_ at: Int, _ conflicts: [Conflicts], _ parts: [Term]) {
                if at == rule.parts.count {
                    newRules.append(Rule(name: rule.name, parts: parts, conflicts: conflicts, skip: rule.skip))
                    return
                }
                let next = rule.parts[at]
                if let replace = inlinable[next.name] {
                    for r in replace {
                        let tail = Array(conflicts.dropLast())
                        let joined = conflicts[conflicts.count - 1].join(r.conflicts[0])
                        let middle = Array(r.conflicts.dropFirst().dropLast())
                        let last: [Conflicts] = at + 1 < rule.conflicts.count
                            ? [rule.conflicts[at + 1].join(r.conflicts[r.conflicts.count - 1])]
                            : []
                        let newConflicts = tail + [joined] + middle + last
                        expand(at + 1, newConflicts, parts + r.parts)
                    }
                } else {
                    expand(at + 1, conflicts + [rule.conflicts[at + 1]], parts + [next])
                }
            }
            expand(0, [rule.conflicts[0]], [])
        }
        rules = newRules
        pass += 1
    }
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
                if rules[groupStart + k].cmpNoName(rules[otherStart + k]) != 0 { match = false }
            }
            if match {
                merged[name.name] = otherName
                found = true
            }
        }
    }
    if !found { return rules }
    return rules.compactMap { rule in
        guard merged[rule.name.name] == nil else { return nil }
        if rule.parts.contains(where: { merged[$0.name] != nil }) {
            return Rule(
                name: rule.name,
                parts: rule.parts.map { merged[$0.name] ?? $0 },
                conflicts: rule.conflicts,
                skip: rule.skip
            )
        }
        return rule
    }
}

func simplifyRules(_ rules: [Rule], _ preserve: [Term]) -> [Rule] {
    return mergeRules(inlineRules(rules, preserve))
}

func isIgnored(_ name: String) -> Bool {
    guard let first = name.first else { return true }
    return first == "_" || first.isLowercase
}

func isExported(_ rule: RuleDeclaration) -> Bool {
    return rule.props.contains(where: { $0.at && $0.name == "export" })
}

// MARK: - Entry Point

public func buildParser(_ text: String, options: BuildOptions = BuildOptions()) throws -> LRParser {
    let builder = try Builder(text: text, options: options)
    return try builder.getParser()
}

// MARK: - Regex helper for dynamicPrecedence validation

private struct BuildRegex {
    static let dynamicPrecPattern = try! NSRegularExpression(pattern: "^-?(?:10|\\d)$")
}

extension String {
    func matchesRegex(_ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(startIndex..., in: self)
        return regex.firstMatch(in: self, range: range) != nil
    }
}
