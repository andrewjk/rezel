import Foundation
public class Pos: CustomStringConvertible {
    public var hashValue: Int = 0

    public let rule: Rule
    public let pos: Int
    public var ahead: [Term]
    public var ambigAhead: [String]
    public let skipAhead: Term
    public let via: Pos?

    public init(rule: Rule, pos: Int, ahead: [Term], ambigAhead: [String], skipAhead: Term, via: Pos?) {
        self.rule = rule; self.pos = pos; self.ahead = ahead; self.ambigAhead = ambigAhead
        self.skipAhead = skipAhead; self.via = via
    }

    @discardableResult
    public func finish() -> Pos {
        var h = hashGen(hashGen(rule.id, pos), skipAhead.hash)
        for a in ahead { h = hashGen(h, a.hash) }
        for group in ambigAhead { h = hashString(h, group) }
        hashValue = h
        return self
    }

    public var next: Term? {
        pos < rule.parts.count ? rule.parts[pos] : nil
    }

    public func advance() -> Pos {
        Pos(rule: rule, pos: pos + 1, ahead: ahead, ambigAhead: ambigAhead, skipAhead: skipAhead, via: via).finish()
    }

    public var skip: Term {
        pos == rule.parts.count ? skipAhead : rule.skip
    }

    public func cmp(_ pos: Pos) -> Int {
        return chain(rule.cmp(pos.rule),
            self.pos - pos.pos,
            skipAhead.hash - pos.skipAhead.hash,
            cmpSet(ahead, pos.ahead, { a, b in a.cmp(b) }),
            cmpSet(ambigAhead, pos.ambigAhead, cmpStr))
    }

    public func eqSimple(_ pos: Pos) -> Bool {
        pos.rule === rule && pos.pos == self.pos
    }

    public var description: String {
        var parts = rule.parts.map { $0.name }
        parts.insert("·", at: pos)
        return "\(rule.name) -> \(parts.joined(separator: " "))"
    }

    public func eq(_ other: Pos) -> Bool {
        self === other ||
            (hashValue == other.hashValue &&
                rule === other.rule &&
                pos == other.pos &&
                skipAhead === other.skipAhead &&
                sameSetObj(ahead, other.ahead) &&
                ambigAhead == other.ambigAhead)
    }

    public func trail(_ maxLen: Int = 60) -> String {
        var result: [Term] = []
        var p: Pos? = self
        while let current = p {
            for i in stride(from: current.pos - 1, through: 0, by: -1) { result.append(current.rule.parts[i]) }
            p = current.via
        }
        var value = result.reversed().map { $0.name }.joined(separator: " ")
        if value.count > maxLen {
            let start = value.index(value.endIndex, offsetBy: -(maxLen), limitedBy: value.startIndex) ?? value.startIndex
            value = "…" + value[start...]
            if let spaceRange = value.range(of: " ", options: .literal, range: value.startIndex..<(value.index(after: value.startIndex))) {
            } else if let spaceIdx = value.firstIndex(of: " "), spaceIdx < value.index(value.startIndex, offsetBy: 3) {
                value = String(value[spaceIdx...])
            }
        }
        return value
    }

    public func conflicts(_ atPos: Int? = nil) -> Conflicts {
        let p = atPos ?? pos
        var result = rule.conflicts[p]
        if p == rule.parts.count && !ambigAhead.isEmpty {
            result = result.join(Conflicts(precedence: 0, ambigAhead))
        }
        return result
    }

    public static func addOrigins(_ group: [Pos], context: [Pos]) -> [Pos] {
        var result = group
        var i = 0
        while i < result.count {
            let next = result[i]
            if next.pos == 0 {
                for pos in context {
                    if pos.next === next.rule.name && !result.contains(where: { $0 === pos }) { result.append(pos) }
                }
            }
            i += 1
        }
        return result
    }
}

func cmpStr(_ a: String, _ b: String) -> Int { a < b ? -1 : a > b ? 1 : 0 }

func conflictsAt(_ group: [Pos]) -> Conflicts {
    var result = Conflicts.none
    for pos in group { result = result.join(pos.conflicts()) }
    return result
}

func compareRepeatPrec(_ a: [Pos], _ b: [Pos]) -> Int {
    for pos in a {
        if pos.rule.name.repeated {
            for posB in b {
                if posB.rule.name === pos.rule.name {
                    if pos.rule.isRepeatWrap && pos.pos == 2 { return 1 }
                    if posB.rule.isRepeatWrap && posB.pos == 2 { return -1 }
                }
            }
        }
    }
    return 0
}

func termsAhead(_ rule: Rule, _ pos: Int, _ after: [Term], _ first: [String: [Term?]]) -> [Term] {
    var found: [Term] = []
    for i in (pos + 1)..<rule.parts.count {
        let next = rule.parts[i]
        var cont = false
        if next.terminal {
            addTo(next, &found)
        } else {
            for term in first[next.name] ?? [] {
                if term == nil { cont = true } else { addTo(term!, &found) }
            }
        }
        if !cont { return found }
    }
    for a in after { addTo(a, &found) }
    return found
}

func eqSetPos(_ a: [Pos], _ b: [Pos]) -> Bool {
    if a.count != b.count { return false }
    for i in 0..<a.count { if !a[i].eq(b[i]) { return false } }
    return true
}

func sameSet<T: Equatable>(_ a: [T], _ b: [T]) -> Bool {
    if a.count != b.count { return false }
    for i in 0..<a.count { if a[i] != b[i] { return false } }
    return true
}

func sameSetObj<T: AnyObject>(_ a: [T], _ b: [T]) -> Bool {
    if a.count != b.count { return false }
    for i in 0..<a.count { if a[i] !== b[i] { return false } }
    return true
}

public class Shift: CustomStringConvertible {
    public let term: Term
    public let target: AutState

    public init(term: Term, target: AutState) { self.term = term; self.target = target }

    public func eq(_ other: ActionItem) -> Bool {
        guard let o = other as? Shift else { return false }
        return term === o.term && o.target.id == target.id
    }

    public func cmp(_ other: ActionItem) -> Int {
        if other is Reduce { return -1 }
        guard let o = other as? Shift else { return -1 }
        return chain(term.id - o.term.id, target.id - o.target.id)
    }

    public func matches(_ other: ActionItem, _ mapping: [Int]) -> Bool {
        guard let o = other as? Shift else { return false }
        return mapping[o.target.id] == mapping[target.id]
    }

    public var description: String { "s\(target.id)" }

    public func map(_ mapping: [Int], _ states: [AutState]) -> Shift {
        let mapped = states[mapping[target.id]]
        return mapped === target ? self : Shift(term: term, target: mapped)
    }
}

public class Reduce: CustomStringConvertible {
    public let term: Term
    public let rule: Rule

    public init(term: Term, rule: Rule) { self.term = term; self.rule = rule }

    public func eq(_ other: ActionItem) -> Bool {
        guard let o = other as? Reduce else { return false }
        return term === o.term && rule.sameReduce(o.rule)
    }

    public func cmp(_ other: ActionItem) -> Int {
        if other is Shift { return 1 }
        guard let o = other as? Reduce else { return 1 }
        return chain(term.id - o.term.id, rule.name.id - o.rule.name.id, rule.parts.count - o.rule.parts.count)
    }

    public func matches(_ other: ActionItem, _ mapping: [Int]) -> Bool {
        guard let o = other as? Reduce else { return false }
        return o.rule.sameReduce(rule)
    }

    public var description: String { "\(rule.name.name)(\(rule.parts.count))" }

    public func map(_ mapping: [Int], _ states: [AutState]) -> Reduce { self }
}

public typealias ActionItem = AnyObject

func hashPositions(_ set: [Pos]) -> Int {
    var h = 5381
    for pos in set { h = hashGen(h, pos.hashValue) }
    return h
}

class AutConflictContext {
    var conflicts: [AutConflict] = []
    let first: [String: [Term?]]
    init(first: [String: [Term?]]) { self.first = first }
}

class AutConflict {
    let error: String
    let rules: [Term]
    init(error: String, rules: [Term]) { self.error = error; self.rules = rules }
}

public class AutState: CustomStringConvertible {
    public var actions: [ActionItem] = []
    public var actionPositions: [[Pos]] = []
    public var gotoActions: [Shift] = []
    public var tokenGroup: Int = -1
    public var defaultReduce: Rule? = nil
    public var id: Int
    public var set: [Pos]
    public var flags: Int = 0
    public let skip: Term
    public let hashValue: Int
    public let startRule: Term?

    public init(id: Int, set: [Pos], flags: Int = 0, skip: Term, hash: Int? = nil, startRule: Term? = nil) {
        self.id = id; self.set = set; self.flags = flags; self.skip = skip
        self.hashValue = hash ?? hashPositions(set); self.startRule = startRule
    }

    public var description: String {
        let actions = self.actions.map { t in
            if let s = t as? Shift { return "\(s.term)=\(s)" }
            if let r = t as? Reduce { return "\(r.term)=\(r)" }
            return ""
        }.joined(separator: ",")
        let gotoPart = gotoActions.isEmpty ? "" : " | " + gotoActions.map { "\($0.term)=\($0)" }.joined(separator: ",")
        if let dr = defaultReduce {
            return "\(id): \(set.filter { $0.pos > 0 }.map { "\($0)" }.joined(separator: ", "))\n  always \(dr.name)(\(dr.parts.count))"
        }
        return "\(id): \(set.filter { $0.pos > 0 }.map { "\($0)" }.joined(separator: ", "))\n  \(actions)\(gotoPart)"
    }

    func addActionInner(_ value: ActionItem, _ positions: [Pos]) -> ActionItem? {
        var i = 0
        check: while i < actions.count {
            let action = actions[i]
            let actionTerm: Term
            if let s = action as? Shift { actionTerm = s.term } else if let r = action as? Reduce { actionTerm = r.term } else { i += 1; continue }
            let valueTerm: Term
            if let s = value as? Shift { valueTerm = s.term } else if let r = value as? Reduce { valueTerm = r.term } else { i += 1; continue }

            if actionTerm === valueTerm {
                if actionEq(action, value) { return nil }
                let fullPos = Pos.addOrigins(positions, context: set)
                let actionFullPos = Pos.addOrigins(actionPositions[i], context: set)
                let conflicts = conflictsAt(fullPos)
                let actionConflicts = conflictsAt(actionFullPos)
                let diff = chain(compareRepeatPrec(fullPos, actionFullPos), conflicts.precedence - actionConflicts.precedence)
                if diff > 0 {
                    actions.remove(at: i)
                    actionPositions.remove(at: i)
                    continue check
                } else if diff < 0 {
                    return nil
                } else if conflicts.ambigGroups.contains(where: { actionConflicts.ambigGroups.contains($0) }) {
                    i += 1
                    continue check
                } else {
                    return action
                }
            }
            i += 1
        }
        actions.append(value)
        actionPositions.append(positions)
        return nil
    }

    func addAction(_ value: ActionItem, _ positions: [Pos], _ context: AutConflictContext) {
        let conflict = addActionInner(value, positions)
        if let conflict = conflict {
            let conflictIdx = actions.firstIndex(where: { $0 === conflict })!
            let conflictPos = actionPositions[conflictIdx][0]
            let rules = [positions[0].rule.name, conflictPos.rule.name]
            if context.conflicts.contains(where: { c in c.rules.contains(where: { r in rules.contains(where: { $0 === r }) }) }) { return }
            var error: String
            if conflict is Shift {
                error = "shift/reduce conflict between\n  \(conflictPos)\nand\n  \(positions[0].rule)"
            } else {
                error = "reduce/reduce conflict between\n  \(conflictPos.rule)\nand\n  \(positions[0].rule)"
            }
            error += "\nWith input:\n  \(positions[0].trail(70)) · \(actionTerm(value)) …"
            if conflict is Shift {
                error += findConflictShiftSource(positions[0], actionTerm(value), context.first)
            }
            error += findConflictOrigin(conflictPos, positions[0])
            context.conflicts.append(AutConflict(error: error, rules: rules))
        }
    }

    public func getGoto(_ term: Term) -> Shift? {
        gotoActions.first { $0.term === term }
    }

    public func hasSet(_ set: [Pos]) -> Bool { eqSetPos(self.set, set) }

    private var _actionsByTerm: [Int: [ActionItem]]? = nil

    public func actionsByTerm() -> [Int: [ActionItem]] {
        if let result = _actionsByTerm { return result }
        var result: [Int: [ActionItem]] = [:]
        for action in actions {
            let t = actionTerm(action)
            if result[t.id] == nil { result[t.id] = [] }
            result[t.id]!.append(action)
        }
        _actionsByTerm = result
        return result
    }

    public func finish() {
        if !actions.isEmpty {
            if let first = actions[0] as? Reduce {
                let rule = first.rule
                if actions.allSatisfy({ a in (a as? Reduce)?.rule.sameReduce(rule) ?? false }) {
                    defaultReduce = rule
                }
            }
        }
        actions.sort { a, b in
            let ta = actionTerm(a), tb = actionTerm(b)
            if let sa = a as? Shift, let sb = b as? Shift { return sa.cmp(sb) < 0 }
            if a is Reduce, b is Shift { return false }
            if a is Shift, b is Reduce { return true }
            return ta.id < tb.id
        }
        gotoActions.sort { $0.cmp($1) < 0 }
    }

    public func eq(_ other: AutState) -> Bool {
        let dThis = defaultReduce, dOther = other.defaultReduce
        if dThis != nil || dOther != nil { return dThis != nil && dOther != nil ? dThis!.sameReduce(dOther!) : false }
        return skip === other.skip &&
            tokenGroup == other.tokenGroup &&
            eqSetActions(actions, other.actions) &&
            eqSetGoto(gotoActions, other.gotoActions)
    }
}

func actionTerm(_ a: ActionItem) -> Term {
    if let s = a as? Shift { return s.term }
    if let r = a as? Reduce { return r.term }
    fatalError("Unknown action type")
}

func actionEq(_ a: ActionItem, _ b: ActionItem) -> Bool {
    if let sa = a as? Shift { return sa.eq(b) }
    if let ra = a as? Reduce { return ra.eq(b) }
    return false
}

func eqSetActions(_ a: [ActionItem], _ b: [ActionItem]) -> Bool {
    if a.count != b.count { return false }
    for i in 0..<a.count { if !actionEq(a[i], b[i]) { return false } }
    return true
}

func eqSetGoto(_ a: [Shift], _ b: [Shift]) -> Bool {
    if a.count != b.count { return false }
    for i in 0..<a.count { if !a[i].eq(b[i]) { return false } }
    return true
}

func automatonClosure(_ set: [Pos], _ first: [String: [Term?]]) throws -> [Pos] {
    var added: [Pos] = []
    var redo: [Pos] = []
    let none: [Term] = []

    func addFor(_ name: Term, _ ahead: [Term], _ ambigAhead: [String], _ skipAhead: Term, _ via: Pos) throws {
        for rule in name.rules {
            var add = added.first { $0.rule === rule }
            if add == nil {
                let existing = set.first { $0.pos == 0 && $0.rule === rule }
                if let existing = existing {
                    add = Pos(rule: existing.rule, pos: 0, ahead: existing.ahead, ambigAhead: existing.ambigAhead, skipAhead: existing.skipAhead, via: existing.via)
                } else {
                    add = Pos(rule: rule, pos: 0, ahead: [], ambigAhead: [], skipAhead: skipAhead, via: via)
                }
                added.append(add!)
            }
            if add!.skipAhead !== skipAhead {
                throw GenError("Inconsistent skip sets after " + via.trail())
            }
            add!.ambigAhead = union(add!.ambigAhead, ambigAhead)
            for term in ahead {
                if !add!.ahead.contains(where: { $0 === term }) {
                    add!.ahead.append(term)
                    if !add!.rule.parts.isEmpty && !add!.rule.parts[0].terminal { addTo(add!, &redo) }
                }
            }
        }
    }

    for pos in set {
        if let next = pos.next, !next.terminal {
            try addFor(next,
                termsAhead(pos.rule, pos.pos, pos.ahead, first),
                pos.conflicts(pos.pos + 1).ambigGroups,
                pos.pos == pos.rule.parts.count - 1 ? pos.skipAhead : pos.rule.skip,
                pos)
        }
    }
    while !redo.isEmpty {
        let add = redo.removeLast()
        try addFor(add.rule.parts[0],
            termsAhead(add.rule, 0, add.ahead, first),
            union(add.rule.conflicts[1].ambigGroups, add.rule.parts.count == 1 ? add.ambigAhead : []),
            add.rule.parts.count == 1 ? add.skipAhead : add.rule.skip,
            add)
    }

    var result = set
    for add in added {
        add.ahead.sort { $0.hash < $1.hash }
        add.finish()
        if let origIndex = result.firstIndex(where: { $0.pos == 0 && $0.rule === add.rule }) {
            result[origIndex] = add
        } else {
            result.append(add)
        }
    }
    return result.sorted { $0.cmp($1) < 0 }
}

func addTo<T: Equatable>(_ value: T, _ array: inout [T]) {
    if !array.contains(value) { array.append(value) }
}

func addTo<T: AnyObject>(_ value: T, _ array: inout [T]) {
    if !array.contains(where: { $0 === value }) { array.append(value) }
}

public func computeFirstSets(_ terms: TermSet) -> [String: [Term?]] {
    var table: [String: [Term?]] = [:]
    for t in terms.terms { if !t.terminal { table[t.name] = [] } }
    while true {
        var change = false
        for nt in terms.terms {
            if !nt.terminal {
                for rule in nt.rules {
                    let set = table[nt.name]!
                    var found = false
                    let startLen = set.count
                    for part in rule.parts {
                        found = true
                        if part.terminal {
                            addTo(part, set: &table[nt.name]!)
                        } else {
                            for t in table[part.name] ?? [] {
                                if t == nil { found = false } else { addTo(t!, set: &table[nt.name]!) }
                            }
                        }
                        if found { break }
                    }
                    if !found {
                        if !(table[nt.name]?.contains(where: { $0 == nil }) ?? false) {
                            table[nt.name]?.append(nil)
                            change = true
                        }
                    }
                    if table[nt.name]!.count > startLen { change = true }
                }
            }
        }
        if !change { return table }
    }
}

func addTo(_ value: Term, set: inout [Term?]) {
    if !set.contains(where: { $0 === value }) { set.append(value) }
}

class AutCore {
    let set: [Pos]
    let state: AutState
    init(set: [Pos], state: AutState) { self.set = set; self.state = state }
}

func findConflictOrigin(_ a: Pos, _ b: Pos) -> String {
    if a.eqSimple(b) { return "" }
    func via(_ root: Pos, _ start: Pos) -> String {
        var hist: [Pos] = []
        var p: Pos? = start.via
        while let current = p {
            if current.eqSimple(root) { break }
            hist.append(current)
            p = current.via
        }
        if hist.isEmpty { return "" }
        hist.insert(start, at: 0)
        return hist.reversed().enumerated().map { i, p in
            "\n" + String(repeating: "  ", count: i + 1) + (p === start ? "" : "via ") + "\(p)"
        }.joined()
    }

    var p: Pos? = a
    while let pa = p {
        var p2: Pos? = b
        while let pb = p2 {
            if pa.eqSimple(pb) { return "\nShared origin: \(pa)" + via(pa, a) + via(pa, b) }
            p2 = pb.via
        }
        p = pa.via
    }
    return ""
}

func findConflictShiftSource(_ conflictPos: Pos, _ termAfter: Term, _ first: [String: [Term?]]) -> String {
    var pos = conflictPos
    var path: [Term] = []
    while true {
        for i in stride(from: pos.pos - 1, through: 0, by: -1) { path.append(pos.rule.parts[i]) }
        if pos.via == nil { break }
        pos = pos.via!
    }
    path.reverse()
    var seen = Set<Int>()

    func explore(_ pos: Pos, _ i: Int, _ hasMatch: Pos?) -> String {
        if i == path.count && hasMatch != nil && pos.next == nil {
            return "\nThe reduction of \(conflictPos.rule.name) is allowed before \(termAfter) because of this rule:\n  \(hasMatch!)"
        }
        var current = pos
        while true {
            guard let next = current.next else { break }
            if i < path.count && next === path[i] {
                let inner = explore(current.advance(), i + 1, hasMatch)
                if !inner.isEmpty { return inner }
            }
            let after = current.pos + 1 < current.rule.parts.count ? current.rule.parts[current.pos + 1] : nil
            var match: Pos? = (current.pos + 1 == current.rule.parts.count) ? hasMatch : nil
            if let after = after {
                if after.terminal ? after === termAfter : (first[after.name]?.contains(where: { $0 === termAfter }) ?? false) {
                    match = current.advance()
                }
            }
            for rule in next.rules {
                let h = (rule.id << 5) + i + (match != nil ? 555 : 0)
                if !seen.contains(h) {
                    seen.insert(h)
                    let inner = explore(Pos(rule: rule, pos: 0, ahead: [], ambigAhead: [], skipAhead: next, via: current), i, match)
                    if !inner.isEmpty { return inner }
                }
            }
            if !next.terminal && (first[next.name]?.contains(where: { $0 == nil }) ?? false) {
                current = current.advance()
            } else {
                break
            }
        }
        return ""
    }
    return explore(pos, 0, nil)
}

public func buildFullAutomaton(_ terms: TermSet, _ startTerms: [Term], _ first: [String: [Term?]]) throws -> [AutState] {
    var states: [AutState] = []
    var statesBySetHash: [Int: [AutState]] = [:]
    var cores: [Int: [AutCore]] = [:]
    let t0 = Date()

    func getState(_ core: [Pos], _ top: Term? = nil) throws -> AutState? {
        if core.isEmpty { return nil }
        let coreHash = hashPositions(core)
        var skip: Term?
        for pos in core {
            if skip == nil { skip = pos.skip }
            else if skip !== pos.skip { throw GenError("Inconsistent skip sets after " + pos.trail()) }
        }
        if let byHash = cores[coreHash] {
            for known in byHash {
                if eqSetPos(core, known.set) {
                    if known.state.skip !== skip {
                        throw GenError("Inconsistent skip sets after " + known.set[0].trail())
                    }
                    return known.state
                }
            }
        }

        let set = try automatonClosure(core, first)
        let h = hashPositions(set)
        if statesBySetHash[h] == nil { statesBySetHash[h] = [] }
        var found: AutState?
        if top == nil {
            for state in statesBySetHash[h]! {
                if state.hasSet(set) { found = state; break }
            }
        }
        if found == nil {
            found = AutState(id: states.count, set: set, skip: skip!, hash: h, startRule: top)
            statesBySetHash[h]!.append(found!)
            states.append(found!)
            if timing && states.count % 500 == 0 {
                print("\(states.count) states after \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
            }
        }
        if cores[coreHash] == nil { cores[coreHash] = [] }
        cores[coreHash]!.append(AutCore(set: core, state: found!))
        return found!
    }

    for startTerm in startTerms {
        let startSkip = !startTerm.rules.isEmpty ? startTerm.rules[0].skip : terms.names["%noskip"]!
        _ = try getState(startTerm.rules.map { rule in
            Pos(rule: rule, pos: 0, ahead: [terms.eof], ambigAhead: [], skipAhead: startSkip, via: nil).finish()
        }, startTerm)
    }

    let conflictCtx = AutConflictContext(first: first)

    var filled = 0
    while filled < states.count {
        let state = states[filled]; filled += 1
        var byTerm: [Term] = []
        var byTermPos: [[Pos]] = []
        var atEnd: [Pos] = []
        for pos in state.set {
            if pos.pos == pos.rule.parts.count {
                if !pos.rule.name.top { atEnd.append(pos) }
            } else {
                let next = pos.rule.parts[pos.pos]
                if let index = byTerm.firstIndex(where: { $0 === next }) {
                    byTermPos[index].append(pos)
                } else {
                    byTerm.append(next)
                    byTermPos.append([pos])
                }
            }
        }
        for i in 0..<byTerm.count {
            let term = byTerm[i]
            let positions = byTermPos[i].map { $0.advance() }
            if term.terminal {
                let set = applyCut(positions)
                if let next = try getState(set) {
                    state.addAction(Shift(term: term, target: next), byTermPos[i], conflictCtx)
                }
            } else {
                if let goto = try getState(positions) {
                    state.gotoActions.append(Shift(term: term, target: goto))
                }
            }
        }

        var replaced = false
        for pos in atEnd {
            for ahead in pos.ahead {
                let count = state.actions.count
                state.addAction(Reduce(term: ahead, rule: pos.rule), [pos], conflictCtx)
                if state.actions.count == count { replaced = true }
            }
        }

        if replaced {
            var i = 0
            while i < state.gotoActions.count {
                let start = first[state.gotoActions[i].term.name] ?? []
                let hasShift = start.contains(where: { term in
                    term != nil && state.actions.contains(where: { a in
                        guard let s = a as? Shift else { return false }
                        return s.term === term
                    })
                })
                if !hasShift {
                    let hasNilShift = start.contains(where: { $0 == nil }) && state.actions.contains(where: { a in
                        guard let s = a as? Shift else { return false }
                        return true
                    })
                    if !hasNilShift {
                        state.gotoActions.remove(at: i); continue
                    }
                }
                i += 1
            }
        }
    }

    if !conflictCtx.conflicts.isEmpty {
        throw GenError(conflictCtx.conflicts.map { $0.error }.joined(separator: "\n\n"))
    }

    for state in states { state.finish() }
    if timing { print("\(states.count) states total.") }
    return states
}

func applyCut(_ set: [Pos]) -> [Pos] {
    var found: [Pos]? = nil
    var cut = 1
    for pos in set {
        let value = pos.rule.conflicts[pos.pos - 1].cut
        if value < cut { continue }
        if found == nil || value > cut {
            cut = value; found = []
        }
        found!.append(pos)
    }
    return found ?? set
}

func canMerge(_ a: AutState, _ b: AutState, _ mapping: [Int]) -> Bool {
    for goto in a.gotoActions {
        for other in b.gotoActions {
            if goto.term === other.term && mapping[goto.target.id] != mapping[other.target.id] { return false }
        }
    }
    let byTerm = b.actionsByTerm()
    for action in a.actions {
        let t = actionTerm(action)
        if let setB = byTerm[t.id] {
            if setB.contains(where: { other in !actionMatches(action, other, mapping) }) {
                if setB.count == 1 { return false }
                let setA = a.actionsByTerm()[t.id]!
                if setA.count != setB.count { return false }
                if setA.contains(where: { a1 in !setB.contains(where: { a2 in actionMatches(a1, a2, mapping) }) }) { return false }
            }
        }
    }
    return true
}

func actionMatches(_ a: ActionItem, _ b: ActionItem, _ mapping: [Int]) -> Bool {
    if let sa = a as? Shift { return sa.matches(b, mapping) }
    if let ra = a as? Reduce { return ra.matches(b, mapping) }
    return false
}

func mergeStates(_ states: [AutState], _ mapping: [Int]) -> [AutState] {
    var newStates: [AutState?] = Array(repeating: nil, count: states.count)
    for state in states {
        let newID = mapping[state.id]
        if newStates[newID] == nil {
            let ns = AutState(id: newID, set: state.set, skip: state.skip, hash: state.hashValue, startRule: state.startRule)
            ns.tokenGroup = state.tokenGroup
            ns.defaultReduce = state.defaultReduce
            newStates[newID] = ns
        }
    }
    for state in states {
        let newID = mapping[state.id]
        let target = newStates[newID]!
        target.flags |= state.flags
        for i in 0..<state.actions.count {
            let mapped = actionMap(state.actions[i], mapping, newStates.compactMap { $0 })
            if !target.actions.contains(where: { actionEq($0, mapped) }) {
                target.actions.append(mapped)
                target.actionPositions.append(state.actionPositions[i])
            }
        }
        for goto in state.gotoActions {
            let mapped = goto.map(mapping, newStates.compactMap { $0 })
            if !target.gotoActions.contains(where: { $0.eq(mapped) }) { target.gotoActions.append(mapped) }
        }
    }
    return newStates.compactMap { $0 }
}

func actionMap(_ a: ActionItem, _ mapping: [Int], _ states: [AutState]) -> ActionItem {
    if let s = a as? Shift { return s.map(mapping, states) }
    if let r = a as? Reduce { return r.map(mapping, states) }
    return a
}

class AutGroup {
    var members: [Int]
    let origin: Int
    init(origin: Int, member: Int) { self.origin = origin; self.members = [member] }
}

func samePosSet(_ a: [Pos], _ b: [Pos]) -> Bool {
    if a.count != b.count { return false }
    for i in 0..<a.count { if !a[i].eqSimple(b[i]) { return false } }
    return true
}

func collapseAutomaton(_ states: [AutState]) -> [AutState] {
    var mapping: [Int] = []
    var groups: [AutGroup] = []

    for i in 0..<states.count {
        let state = states[i]
        if state.startRule == nil {
            var found = false
            for j in 0..<groups.count {
                let other = states[groups[j].members[0]]
                if state.tokenGroup == other.tokenGroup && state.skip === other.skip && other.startRule == nil && samePosSet(state.set, other.set) {
                    groups[j].members.append(i)
                    mapping.append(j)
                    found = true; break
                }
            }
            if found { continue }
        }
        mapping.append(groups.count)
        groups.append(AutGroup(origin: groups.count, member: i))
    }

    func spill(_ groupIndex: Int, _ index: Int) {
        let group = groups[groupIndex]
        let state = states[group.members[index]]
        let pop = group.members.removeLast()
        if index != group.members.count { group.members[index] = pop }
        for i in (groupIndex + 1)..<groups.count {
            mapping[state.id] = i
            if groups[i].origin == group.origin && groups[i].members.allSatisfy({ id in canMerge(state, states[id], mapping) }) {
                groups[i].members.append(state.id)
                return
            }
        }
        mapping[state.id] = groups.count
        groups.append(AutGroup(origin: group.origin, member: state.id))
    }

    var pass = 1
    while true {
        var conflicts = false
        let t0 = Date()
        let startLen = groups.count
        for g in 0..<startLen {
            let group = groups[g]
            var i = 0
            while i < group.members.count - 1 {
                var j = i + 1
                while j < group.members.count {
                    let idA = group.members[i], idB = group.members[j]
                    if !canMerge(states[idA], states[idB], mapping) {
                        conflicts = true
                        spill(g, j)
                    } else {
                        j += 1
                    }
                }
                i += 1
            }
        }
        if timing {
            print("Collapse pass \(pass)\(conflicts ? "" : ", done") (\(String(format: "%.2f", Date().timeIntervalSince(t0)))s)")
        }
        if !conflicts { return mergeStates(states, mapping) }
        pass += 1
    }
}

func mergeIdentical(_ states: [AutState]) -> [AutState] {
    var states = states
    var pass = 1
    while true {
        var mapping: [Int] = []
        var didMerge = false
        let t0 = Date()
        var newStates: [AutState] = []
        for i in 0..<states.count {
            let state = states[i]
            let match = newStates.firstIndex(where: { state.eq($0) })
            if let match = match {
                mapping.append(match)
                didMerge = true
                let other = newStates[match]
                var add: [Pos]? = nil
                for pos in state.set {
                    if !other.set.contains(where: { $0.eqSimple(pos) }) { (add ?? []).map { _ in }.count; if add == nil { add = [] }; add!.append(pos) }
                }
                if let add = add { other.set = add + other.set; other.set.sort { $0.cmp($1) < 0 } }
            } else {
                mapping.append(newStates.count)
                newStates.append(state)
            }
        }
        if timing {
            print("Merge identical pass \(pass)\(didMerge ? "" : ", done") (\(String(format: "%.2f", Date().timeIntervalSince(t0)))s)")
        }
        if !didMerge { return states }
        for state in newStates {
            if state.defaultReduce == nil {
                state.actions = state.actions.map { actionMap($0, mapping, newStates) }
                state.gotoActions = state.gotoActions.map { $0.map(mapping, newStates) }
            }
        }
        for i in 0..<newStates.count { newStates[i].id = i }
        states = newStates
        pass += 1
    }
}

public func finishAutomaton(_ full: [AutState]) -> [AutState] {
    mergeIdentical(collapseAutomaton(full))
}
