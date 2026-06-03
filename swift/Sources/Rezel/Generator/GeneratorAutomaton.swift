//
//  Automaton.swift
//  Rezel
//
//  Created on 2025-06-11.
//

import Foundation

/// Position in a grammar rule (LR(1) item)
public class Pos: CustomStringConvertible {
    var hashValue: Int = 0

    let rule: Rule
    let pos: Int
    var ahead: [Term]
    var ambigAhead: [String]
    let skipAhead: Term
    let via: Pos?

    init(
        rule: Rule,
        pos: Int,
        ahead: [Term],
        ambigAhead: [String],
        skipAhead: Term,
        via: Pos?
    ) {
        self.rule = rule
        self.pos = pos
        self.ahead = ahead
        self.ambigAhead = ambigAhead
        self.skipAhead = skipAhead
        self.via = via
    }

    @discardableResult
    func finish() -> Self {
        var h = hash(hash(rule.id, pos), skipAhead.hash)
        for a in ahead {
            h = hash(h, a.hash)
        }
        for group in ambigAhead {
            h = hashString(h, group)
        }
        hashValue = h
        return self
    }

    var next: Term? {
        return pos < rule.parts.count ? rule.parts[pos] : nil
    }

    func advance() -> Pos {
        return Pos(
            rule: rule,
            pos: pos + 1,
            ahead: ahead,
            ambigAhead: ambigAhead,
            skipAhead: skipAhead,
            via: via
        ).finish()
    }

    var skip: Term {
        return pos == rule.parts.count ? skipAhead : rule.skip
    }

    func cmp(_ pos: Pos) -> Int {
        let ruleCmp = rule.cmp(pos.rule)
        if ruleCmp != 0 { return ruleCmp }
        
        let posCmp = self.pos - pos.pos
        if posCmp != 0 { return posCmp }
        
        let skipCmp = skipAhead.hash - pos.skipAhead.hash
        if skipCmp != 0 { return skipCmp }
        
        let aheadCmp = cmpSet(ahead, pos.ahead) { $0.cmp($1) }
        if aheadCmp != 0 { return aheadCmp }
        
        return cmpSet(ambigAhead, pos.ambigAhead) { a, b in
            if a < b { return -1 }
            if a > b { return 1 }
            return 0
        }
    }

    func eqSimple(_ pos: Pos) -> Bool {
        return pos.rule === rule && pos.pos == self.pos
    }

    public var description: String {
        var parts = rule.parts.map { $0.name }
        parts.insert("·", at: pos)
        return "\(rule.name) -> \(parts.joined(separator: " "))"
    }

    func eq(_ other: Pos) -> Bool {
        return self === other ||
               (hashValue == other.hashValue &&
                rule === other.rule &&
                pos == other.pos &&
                skipAhead === other.skipAhead &&
                sameSet(ahead, other.ahead) &&
                eqSet(ambigAhead, other.ambigAhead))
    }

    func trail(maxLen: Int = 60) -> String {
        var result: [Term] = []
        var currentPos: Pos? = self
        while let pos = currentPos {
            for i in stride(from: pos.pos - 1, through: 0, by: -1) {
                result.append(pos.rule.parts[i])
            }
            currentPos = pos.via
        }
        let value = result.reversed().map { $0.name }.joined(separator: " ")
        if value.count > maxLen {
            let index = value.index(value.endIndex, offsetBy: -maxLen)
            if let spaceRange = value.range(of: " ", range: index..<value.endIndex) {
                return "… " + String(value[spaceRange.upperBound...])
            }
            return "… " + String(value[index...])
        }
        return value
    }

    func conflicts(_ pos: Int? = nil) -> Conflicts {
        let position = pos ?? self.pos
        var result = rule.conflicts[position]
        if position == rule.parts.count && !ambigAhead.isEmpty {
            result = result.join(Conflicts(precedence: 0, ambigGroups: ambigAhead))
        }
        return result
    }

    static func addOrigins(group: [Pos], context: [Pos]) -> [Pos] {
        var result = group
        for i in 0..<result.count {
            let next = result[i]
            if next.pos == 0 {
                for pos in context {
                    if let nextTerm = pos.next, nextTerm === next.rule.name && !result.contains(where: { $0 === pos }) {
                        result.append(pos)
                    }
                }
            }
        }
        return result
    }
}

func conflictsAt(group: [Pos]) -> Conflicts {
    var result = Conflicts.none
    for pos in group {
        result = result.join(pos.conflicts())
    }
    return result
}

func compareRepeatPrec(a: [Pos], b: [Pos]) -> Int {
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

func termsAhead(
    rule: Rule,
    pos: Int,
    after: [Term],
    first: [String: [Term?]]
) -> [Term] {
    var found: [Term] = []
    for i in (pos + 1)..<rule.parts.count {
        let next = rule.parts[i]
        var cont = false
        if next.terminal {
            addTo(next, &found)
        } else {
            for term in first[next.name] ?? [] {
                if let t = term {
                    addTo(t, &found)
                } else {
                    cont = true
                }
            }
        }
        if !cont { return found }
    }
    for a in after {
        addTo(a, &found)
    }
    return found
}

func eqSet<T: Equatable>(_ a: [T], _ b: [T]) -> Bool {
    if a.count != b.count { return false }
    for i in 0..<a.count {
        if a[i] != b[i] { return false }
    }
    return true
}

func sameSet<T: AnyObject>(_ a: [T], _ b: [T]) -> Bool {
    if a.count != b.count { return false }
    for i in 0..<a.count {
        if a[i] !== b[i] { return false }
    }
    return true
}

/// Shift action in parser
public class Shift: CustomStringConvertible {
    let term: Term
    var target: State

    init(term: Term, target: State) {
        self.term = term
        self.target = target
    }

    func eq(_ other: Any) -> Bool {
        guard let other = other as? Shift else { return false }
        return term === other.term && other.target.id == target.id
    }

    func cmp(_ other: Any) -> Int {
        guard let other = other as? Shift else {
            if other is Reduce { return -1 }
            return 0
        }
        let termCmp = term.id - other.term.id
        if termCmp != 0 { return termCmp }
        return target.id - other.target.id
    }

    func matches(_ other: Any, mapping: [Int]) -> Bool {
        guard let other = other as? Shift else { return false }
        return mapping[other.target.id] == mapping[target.id]
    }

    public var description: String {
        return "s\(target.id)"
    }

    func map(mapping: [Int], states: [State?]) -> Shift {
        let idx = mapping[target.id]
        guard idx < states.count, let mapped = states[idx] else {
            fatalError("Shift.map: target.id=\(target.id) mapping[\(target.id)]=\(idx) states.count=\(states.count)")
        }
        return mapped === target ? self : Shift(term: term, target: mapped)
    }

    func map(mapping: [Int], states: [State]) -> Shift {
        let idx = mapping[target.id]
        guard idx < states.count else {
            fatalError("Shift.map: target.id=\(target.id) mapping[\(target.id)]=\(idx) states.count=\(states.count)")
        }
        let mapped = states[idx]
        return mapped === target ? self : Shift(term: term, target: mapped)
    }
}

/// Reduce action in parser
public class Reduce: CustomStringConvertible {
    let term: Term
    let rule: Rule

    init(term: Term, rule: Rule) {
        self.term = term
        self.rule = rule
    }

    func eq(_ other: Any) -> Bool {
        guard let other = other as? Reduce else { return false }
        return term === other.term && other.rule.sameReduce(rule)
    }

    func cmp(_ other: Any) -> Int {
        guard let other = other as? Reduce else {
            if other is Shift { return 1 }
            return 0
        }
        let termCmp = term.id - other.term.id
        if termCmp != 0 { return termCmp }
        
        let nameCmp = rule.name.id - other.rule.name.id
        if nameCmp != 0 { return nameCmp }
        
        return rule.parts.count - other.rule.parts.count
    }

    func matches(_ other: Any, mapping: [Int]) -> Bool {
        guard let other = other as? Reduce else { return false }
        return other.rule.sameReduce(rule)
    }

    public var description: String {
        return "\(rule.name.name)(\(rule.parts.count))"
    }

    func map() -> Self {
        return self
    }
}

func actionTerm(_ action: Any) -> Term? {
    if let shift = action as? Shift { return shift.term }
    if let reduce = action as? Reduce { return reduce.term }
    return nil
}

func actionEq(_ a: Any, _ b: Any) -> Bool {
    if let sa = a as? Shift { return sa.eq(b) }
    if let ra = a as? Reduce { return ra.eq(b) }
    return false
}

func hashPositions(set: [Pos]) -> Int {
    var h = 5381
    for pos in set {
        h = hash(h, pos.hashValue)
    }
    return h
}

class TokenConflictContext {
    var conflicts: [TokenConflict] = []
    let first: [String: [Term?]]
    
    init(first: [String: [Term?]]) {
        self.first = first
    }
}

/// Parser state
public class State: CustomStringConvertible {
    var actions: [Any] = [] // Shift | Reduce
    var actionPositions: [[Pos]] = []
    var goto: [Shift] = []
    var tokenGroup: Int = -1
    var defaultReduce: Rule?
    var id: Int
    var set: [Pos]
    var flags = 0
    let skip: Term
    let hashValue: Int
    let startRule: Term?

    init(
        id: Int,
        set: [Pos],
        flags: Int = 0,
        skip: Term,
        hash: Int = hashPositions(set: []),
        startRule: Term? = nil
    ) {
        self.id = id
        self.set = set
        self.flags = flags
        self.skip = skip
        self.hashValue = hash
        self.startRule = startRule
    }

    public var description: String {
        let actionsStr = actions.map { "\($0)" }.joined(separator: ",")
        let gotoStr = goto.isEmpty ? "" : " | \(goto.map { "\($0)" }.joined(separator: ","))"
        let defaultStr = defaultReduce != nil ?
            "\n  always \(defaultReduce!.name)(\(defaultReduce!.parts.count))" :
            (actionsStr.isEmpty ? "" : "\n  \(actionsStr)")
        return "\(id): \(set.filter { $0.pos > 0 }.map { "\($0)" }.joined())\(defaultStr)\(gotoStr)"
    }

    func addActionInner(_ value: Any, positions: [Pos]) -> Any? {
        var i = 0
        check: while i < actions.count {
            let action = actions[i]
            let aTerm = actionTerm(action)
            let vTerm = actionTerm(value)
            if let aTerm = aTerm, let vTerm = vTerm, aTerm === vTerm {
                if actionEq(action, value) { return nil }
                
                let fullPos = Pos.addOrigins(group: positions, context: set)
                let actionFullPos = Pos.addOrigins(group: actionPositions[i], context: set)
                let conflicts = conflictsAt(group: fullPos)
                let actionConflicts = conflictsAt(group: actionFullPos)

                let repeatPrec = compareRepeatPrec(a: fullPos, b: actionFullPos)
                let diff = repeatPrec != 0 ? repeatPrec : conflicts.precedence - actionConflicts.precedence

                if diff > 0 {
                    actions.remove(at: i)
                    actionPositions.remove(at: i)
                    continue check
                } else if diff < 0 {
                    return nil
                } else if !conflicts.ambigGroups.filter({ actionConflicts.ambigGroups.contains($0) }).isEmpty {
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

    func addAction(_ value: Any, positions: [Pos], context: TokenConflictContext) {
        if let conflict = addActionInner(value, positions: positions) {
            let conflictIndex = actions.firstIndex(where: { action in
                return actionEq(action, conflict)
            })!
            let conflictPos = actionPositions[conflictIndex][0]
            let rules = [positions[0].rule.name, conflictPos.rule.name]

            if context.conflicts.contains(where: { c in
                c.rules.contains(where: { rules.contains($0) })
            }) { return }

            var error: String
            if conflict is Shift {
                error = "shift/reduce conflict between\n  \(conflictPos)\nand\n  \(positions[0].rule)"
            } else {
                error = "reduce/reduce conflict between\n  \(conflictPos.rule)\nand\n  \(positions[0].rule)"
            }

            if let shiftValue = value as? Shift {
                error += "\nWith input:\n  \(positions[0].trail(maxLen: 70)) · \(shiftValue.term) …"
                error += findTokenConflictShiftSource(conflictPos: positions[0], termAfter: shiftValue.term, first: context.first)
            } else if let reduceValue = value as? Reduce {
                error += "\nWith input:\n  \(positions[0].trail(maxLen: 70)) · \(reduceValue.term) …"
            }

            error += findTokenConflictOrigin(conflictPos, positions[0])
            context.conflicts.append(TokenConflict(error: error, rules: rules))
        }
    }

    func getGoto(_ term: Term) -> Shift? {
        return goto.first { $0.term === term }
    }

    func hasSet(_ set: [Pos]) -> Bool {
        return eqSet(self.set, set)
    }

    private var _actionsByTerm: [Int: [Any]]? = nil

    func actionsByTerm() -> [Int: [Any]] {
        if let result = _actionsByTerm { return result }
        
        var result: [Int: [Any]] = [:]
        for action in actions {
            let termId: Int
            if let shift = action as? Shift {
                termId = shift.term.id
            } else if let reduce = action as? Reduce {
                termId = reduce.term.id
            } else {
                continue
            }
            result[termId, default: []].append(action)
        }
        _actionsByTerm = result
        return result
    }

    func finish() {
        if !actions.isEmpty {
            if let first = actions.first as? Reduce {
                let rule = first.rule
                if actions.allSatisfy({ ($0 as? Reduce)?.rule.sameReduce(rule) ?? false }) {
                    defaultReduce = rule
                }
            }
        }
        actions.sort { a, b in
            if let shiftA = a as? Shift, let shiftB = b as? Shift {
                return shiftA.cmp(shiftB) < 0
            } else if let reduceA = a as? Reduce, let reduceB = b as? Reduce {
                return reduceA.cmp(reduceB) < 0
            } else if let _ = a as? Shift {
                return true
            } else {
                return false
            }
        }
        goto.sort { $0.cmp($1) < 0 }
    }

    func eq(_ other: State) -> Bool {
        let dThis = defaultReduce
        let dOther = other.defaultReduce

        if dThis != nil || dOther != nil {
            return dThis != nil && dOther != nil && dThis!.sameReduce(dOther!)
        }

        return skip === other.skip &&
               tokenGroup == other.tokenGroup &&
               eqActionSet(actions, other.actions) &&
               eqSet(goto, other.goto)
    }
}

class TokenConflict {
    let error: String
    let rules: [Term]
    
    init(error: String, rules: [Term]) {
        self.error = error
        self.rules = rules
    }
}

func closure(_ set: [Pos], first: [String: [Term?]]) -> [Pos] {
    var added: [Pos] = []
    var redo: [Pos] = []
    let none: [String] = []
    
    func addFor(
        _ name: Term,
        _ ahead: [Term],
        _ ambigAhead: [String],
        _ skipAhead: Term,
        _ via: Pos
    ) {
        for rule in name.rules {
            var add = added.first { $0.rule === rule }
            if add == nil {
                let existing = set.first { $0.pos == 0 && $0.rule === rule }
                add = existing != nil ?
                    Pos(rule: rule, pos: 0, ahead: existing!.ahead, ambigAhead: existing!.ambigAhead,
                        skipAhead: existing!.skipAhead, via: existing!.via) :
                    Pos(rule: rule, pos: 0, ahead: [], ambigAhead: none, skipAhead: skipAhead, via: via)
                added.append(add!)
            }
            
            if add!.skipAhead !== skipAhead {
                fatalError("Inconsistent skip sets after \(via.trail())")
            }
            
            add!.ambigAhead = union(add!.ambigAhead, ambigAhead)
            for term in ahead {
                if !add!.ahead.contains(where: { $0 === term }) {
                    add!.ahead.append(term)
                    if !add!.rule.parts.isEmpty && !add!.rule.parts[0].terminal {
                        addTo(add!, &redo)
                    }
                }
            }
        }
    }

    for pos in set {
        if let next = pos.next, !next.terminal {
            addFor(
                next,
                termsAhead(rule: pos.rule, pos: pos.pos, after: pos.ahead, first: first),
                pos.conflicts(pos.pos + 1).ambigGroups,
                pos.pos == pos.rule.parts.count - 1 ? pos.skipAhead : pos.rule.skip,
                pos
            )
        }
    }
    
    while !redo.isEmpty {
        let add = redo.removeLast()
        addFor(
            add.rule.parts[0],
            termsAhead(rule: add.rule, pos: 0, after: add.ahead, first: first),
            union(add.rule.conflicts[1].ambigGroups,
                  add.rule.parts.count == 1 ? add.ambigAhead : none),
            add.rule.parts.count == 1 ? add.skipAhead : add.rule.skip,
            add
        )
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
    if !array.contains(value) {
        array.append(value)
    }
}

func addTo<T: AnyObject>(_ value: T, _ array: inout [T]) {
    if !array.contains(where: { $0 === value }) {
        array.append(value)
    }
}

/// Compute FIRST sets for all non-terminals
public func computeFirstSets(terms: TermSet) -> [String: [Term?]] {
    var table: [String: [Term?]] = [:]
    for t in terms.terms where !t.terminal {
        table[t.name] = []
    }
    
    while true {
        var change = false
        for nt in terms.terms where !nt.terminal {
            for rule in nt.rules {
                var set = table[nt.name]!
                var found = false
                let startLen = set.count
                
                for part in rule.parts {
                    found = true
                    if part.terminal {
                        addTo(part as Term?, &set)
                    } else {
                        for t in table[part.name] ?? [] {
                            if t == nil {
                                found = false
                            } else {
                                addTo(t! as Term?, &set)
                            }
                        }
                    }
                    if found { break }
                }

                if !found { addTo(nil as Term?, &set) }
                if set.count > startLen { change = true }
                table[nt.name] = set
            }
        }
        if !change { return table }
    }
}

class Core {
    let set: [Pos]
    let state: State
    
    init(set: [Pos], state: State) {
        self.set = set
        self.state = state
    }
}

func findTokenConflictOrigin(_ a: Pos, _ b: Pos) -> String {
    if a.eqSimple(b) { return "" }
    
    func via(root: Pos, start: Pos) -> String {
        var hist: [Pos] = []
        var p = start.via!
        while !p.eqSimple(root) {
            hist.append(p)
            p = p.via!
        }
        if hist.isEmpty { return "" }
        hist.insert(start, at: 0)
        return hist.reversed().enumerated().map { i, p in
            "\n" + String(repeating: " ", count: i + 1) + (p === start ? "" : "via ") + "\(p)"
        }.joined()
    }

    var p: Pos? = a
    while let currentP = p {
        var p2: Pos? = b
        while let currentP2 = p2 {
            if currentP.eqSimple(currentP2) {
                return "\nShared origin: \(currentP)" + via(root: currentP, start: a) + via(root: currentP, start: b)
            }
            p2 = currentP2.via
        }
        p = currentP.via
    }
    
    return ""
}

func findTokenConflictShiftSource(
    conflictPos: Pos,
    termAfter: Term,
    first: [String: [Term?]]
) -> String {
    var pos = conflictPos
    var path: [Term] = []
    while true {
        for i in stride(from: pos.pos - 1, through: 0, by: -1) {
            path.append(pos.rule.parts[i])
        }
        if pos.via == nil { break }
        pos = pos.via!
    }
    path.reverse()
    
    var seen = Set<Int>()
    
    func explore(_ pos: Pos, _ i: Int, _ hasMatch: Pos?) -> String {
        var pos = pos
        if i == path.count && hasMatch != nil && pos.next == nil {
            return "\nThe reduction of \(conflictPos.rule.name) is allowed before \(termAfter) because of this rule:\n  \(hasMatch!)"
        }

        while let next = pos.next {
            if i < path.count && next === path[i] {
                let inner = explore(pos.advance(), i + 1, hasMatch)
                if !inner.isEmpty { return inner }
            }
            
            let after = pos.rule.parts.count > pos.pos + 1 ? pos.rule.parts[pos.pos + 1] : nil
            let match: Pos? = (pos.pos + 1 == pos.rule.parts.count) ? hasMatch : nil
            
            if let after = after {
                let matches: Bool
                if after.terminal {
                    matches = after === termAfter
                } else {
                    matches = (first[after.name] ?? []).contains(where: { $0 === termAfter })
                }
                if matches {
                    return explore(pos.advance(), i, pos.advance())
                }
            }
            
            for rule in next.rules {
                let hashValue = (rule.id << 5) + i + (hasMatch != nil ? 555 : 0)
                if !seen.contains(hashValue) {
                    seen.insert(hashValue)
                    let newPos = Pos(rule: rule, pos: 0, ahead: [], ambigAhead: [], skipAhead: next, via: pos)
                    newPos.finish()
                    let inner = explore(newPos, i, match)
                    if !inner.isEmpty { return inner }
                }
            }
            
            if !next.terminal && (first[next.name] ?? []).contains(where: { $0 == nil }) {
                pos = pos.advance()
            } else {
                break
            }
        }
        return ""
    }
    
    return explore(pos, 0, nil)
}

/// Build a full LR(1) automaton
public func buildFullAutomaton(
    terms: TermSet,
    startTerms: [Term],
    first: [String: [Term?]]
) -> [State] {
    var states: [State] = []
    var statesBySetHash: [Int: [State]] = [:]
    var cores: [Int: [Core]] = [:]
    let none: [String] = []
    let t0 = Date().timeIntervalSince1970
    
    func getState(core: [Pos], top: Term?) -> State? {
        if core.isEmpty { return nil }
        
        let coreHash = hashPositions(set: core)
        let byHash = cores[coreHash]
        var skip: Term?
        
        for pos in core {
            if skip == nil {
                skip = pos.skip
            } else if skip! !== pos.skip {
                fatalError("Inconsistent skip sets after \(pos.trail())")
            }
        }
        
        if let byHash = byHash {
            for known in byHash {
                if eqSet(core, known.set) {
                    if known.state.skip !== skip {
                        fatalError("Inconsistent skip sets after \(known.set[0].trail())")
                    }
                    return known.state
                }
            }
        }

        let set = closure(core, first: first)
        let hash = hashPositions(set: set)
        var forHash = statesBySetHash[hash] ?? []
        var found: State?
        
        if top == nil {
            found = forHash.first { $0.hasSet(set) }
        }
        
        if found == nil {
            found = State(id: states.count, set: set, flags: 0, skip: skip!, hash: hash, startRule: top)
            forHash.append(found!)
            statesBySetHash[hash] = forHash
            states.append(found!)
            
            if timing && states.count % 500 == 0 {
                let elapsed = Date().timeIntervalSince1970 - t0
                print("\(states.count) states after \(String(format: "%.2f", elapsed))s")
            }
        }
        
        if cores[coreHash] == nil {
            cores[coreHash] = []
        }
        cores[coreHash]!.append(Core(set: core, state: found!))
        
        return found
    }

    for startTerm in startTerms {
        let startSkip = !startTerm.rules.isEmpty ? startTerm.rules[0].skip : terms.names["%noskip"]!
        _ = getState(core: startTerm.rules.map { rule in
            Pos(rule: rule, pos: 0, ahead: [terms.eof], ambigAhead: none, skipAhead: startSkip, via: nil).finish()
        }, top: startTerm)
    }

    let conflicts = TokenConflictContext(first: first)

    var filled = 0
    while filled < states.count {
        let state = states[filled]
        var byTerm: [Term] = []
        var byTermPos: [[Pos]] = []
        var atEnd: [Pos] = []
        
        for pos in state.set {
            if pos.pos == pos.rule.parts.count {
                if !pos.rule.name.top {
                    atEnd.append(pos)
                }
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
                if let next = getState(core: set, top: nil) {
                    state.addAction(Shift(term: term, target: next), positions: byTermPos[i], context: conflicts)
                }
            } else {
                if let goto = getState(core: positions, top: nil) {
                    state.goto.append(Shift(term: term, target: goto))
                }
            }
        }

        var replaced = false
        for pos in atEnd {
            for ahead in pos.ahead {
                let count = state.actions.count
                    state.addAction(Reduce(term: ahead, rule: pos.rule), positions: [pos], context: conflicts)
                if state.actions.count == count {
                    replaced = true
                }
            }
        }

        if replaced {
            for i in (0..<state.goto.count).reversed() {
                let start = first[state.goto[i].term.name] ?? []
                if start.allSatisfy({ term in
                    if let t = term {
                        return !state.actions.contains(where: { action in
                            if let shift = action as? Shift {
                                return shift.term === t
                            }
                            return false
                        })
                    }
                    return true
                }) {
                    state.goto.remove(at: i)
                }
            }
        }
        filled += 1
    }

    if !conflicts.conflicts.isEmpty {
        for c in conflicts.conflicts {
            print(c.error)
        }
    }

    for state in states {
        state.finish()
    }
    
    if timing {
        print("\(states.count) states total.")
    }
    
    return states
}

func applyCut(_ set: [Pos]) -> [Pos] {
    var found: [Pos]? = nil
    var cut = 1
    
    for pos in set {
        let value = pos.rule.conflicts[pos.pos - 1].cut
        if value < cut { continue }
        
        if found == nil || value > cut {
            cut = value
            found = []
        }
        found!.append(pos)
    }
    
    return found ?? set
}

func canMerge(_ a: State, _ b: State, mapping: [Int]) -> Bool {
    for goto in a.goto {
        for other in b.goto {
            if goto.term === other.term && mapping[goto.target.id] != mapping[other.target.id] {
                return false
            }
        }
    }
    
    let byTerm = b.actionsByTerm()
    for action in a.actions {
        let termId: Int
        if let shift = action as? Shift {
            termId = shift.term.id
        } else if let reduce = action as? Reduce {
            termId = reduce.term.id
        } else {
            continue
        }
        
        if let setB = byTerm[termId] {
            if setB.contains(where: { item in
                if let shift = item as? Shift {
                    return !shift.matches(action, mapping: mapping)
                } else if let reduce = item as? Reduce {
                    return !reduce.matches(action, mapping: mapping)
                }
                return false
            }) {
                if setB.count == 1 { return false }

                let setA = a.actionsByTerm()[termId] ?? []
                if setA.count != setB.count ||
                   setA.contains(where: { a1 in
                       if let shiftA = a1 as? Shift {
                           return !setB.contains(where: { !shiftA.matches($0, mapping: mapping) })
                       } else if let reduceA = a1 as? Reduce {
                           return !setB.contains(where: { !reduceA.matches($0, mapping: mapping) })
                       }
                       return false
                   }) {
                    return false
                }
            }
        }
    }
    
    return true
}

func mergeStates(_ states: [State], mapping: [Int]) -> [State] {
    var newStates: [State?] = Array(repeating: nil, count: states.count)
    
    for state in states {
        let newID = mapping[state.id]
        if newStates[newID] == nil {
            newStates[newID] = State(
                id: newID,
                set: state.set,
                flags: 0,
                skip: state.skip,
                hash: state.hashValue,
                startRule: state.startRule
            )
            newStates[newID]!.tokenGroup = state.tokenGroup
            newStates[newID]!.defaultReduce = state.defaultReduce
        }
    }
    
    for state in states {
        let newID = mapping[state.id]
        let target = newStates[newID]!
        target.flags |= state.flags
        
        for i in 0..<state.actions.count {
            let action = state.actions[i]
            let mappedAction: Any
            if let shift = action as? Shift {
                mappedAction = shift.map(mapping: mapping, states: newStates)
            } else if let reduce = action as? Reduce {
                mappedAction = reduce.map()
            } else {
                continue
            }
            
            if !target.actions.contains(where: { ($0 as? Shift)?.eq(mappedAction) ?? ($0 as? Reduce)?.eq(mappedAction) ?? false }) {
                target.actions.append(mappedAction)
                target.actionPositions.append(state.actionPositions[i])
            }
        }
        
        for goto in state.goto {
            let mapped = goto.map(mapping: mapping, states: newStates)
            if !target.goto.contains(where: { $0.eq(mapped) }) {
                target.goto.append(mapped)
            }
        }
    }
    
    let result = newStates.compactMap { $0 }
    for i in 0..<result.count {
        result[i].id = i
    }
    return result
}

class Group {
    var members: [Int]
    let origin: Int
    
    init(origin: Int, member: Int) {
        self.origin = origin
        self.members = [member]
    }
}

func samePosSet(_ a: [Pos], _ b: [Pos]) -> Bool {
    if a.count != b.count { return false }
    for i in 0..<a.count {
        if !a[i].eqSimple(b[i]) { return false }
    }
    return true
}

/// Collapse an LR(1) automaton to an LALR-like automaton
func collapseAutomaton(_ states: [State]) -> [State] {
    var mapping: [Int] = []
    var groups: [Group] = []
    
    assignGroups: for i in 0..<states.count {
        let state = states[i]
        
        if state.startRule == nil {
            for j in 0..<groups.count {
                let group = groups[j]
                let other = states[group.members[0]]
                
                if state.tokenGroup == other.tokenGroup &&
                   state.skip === other.skip &&
                   other.startRule == nil &&
                   samePosSet(state.set, other.set) {
                    group.members.append(i)
                    mapping.append(j)
                    continue assignGroups
                }
            }
        }
        
        mapping.append(groups.count)
        groups.append(Group(origin: groups.count, member: i))
    }

    func spill(groupIndex: Int, index: Int) {
        let group = groups[groupIndex]
        let state = states[group.members[index]]
        let pop = group.members.removeLast()
        
        if index != group.members.count {
            group.members[index] = pop
        }
        
        for i in (groupIndex + 1)..<groups.count {
            mapping[state.id] = i
            
            if groups[i].origin == group.origin &&
               groups[i].members.allSatisfy({ canMerge(state, states[$0], mapping: mapping) }) {
                groups[i].members.append(state.id)
                return
            }
        }
        
        mapping[state.id] = groups.count
        groups.append(Group(origin: group.origin, member: state.id))
    }

    var pass = 1
    while true {
        var hasConflicts = false
        let t0 = Date().timeIntervalSince1970
        
        for g in 0..<groups.count {
            let group = groups[g]
            for i in 0..<(group.members.count - 1) {
                for j in (i + 1)..<group.members.count {
                    let idA = group.members[i]
                    let idB = group.members[j]
                    
                    if !canMerge(states[idA], states[idB], mapping: mapping) {
                        hasConflicts = true
                        spill(groupIndex: g, index: j)
                    }
                }
            }
        }
        
        if timing {
            let elapsed = Date().timeIntervalSince1970 - t0
            print("Collapse pass \(pass)\(hasConflicts ? "" : ", done") (\(String(format: "%.2f", elapsed))s)")
        }
        
        if !hasConflicts {
            return mergeStates(states, mapping: mapping)
        }
        
        pass += 1
    }
}

func mergeIdentical(_ states: [State]) -> [State] {
    var pass = 1
    var currentStates = states
    
    while true {
        var mapping = Array(repeating: 0, count: currentStates.count)
        var didMerge = false
        let t0 = Date().timeIntervalSince1970
        var newStates: [State] = []
        
        for i in 0..<currentStates.count {
            let state = currentStates[i]
            if let matchIndex = newStates.firstIndex(where: { state.eq($0) }) {
                mapping[i] = matchIndex
                didMerge = true
                let other = newStates[matchIndex]
                var add: [Pos]? = nil
                
                for pos in state.set {
                    if !other.set.contains(where: { $0.eqSimple(pos) }) {
                        if add == nil { add = [] }
                        add!.append(pos)
                    }
                }
                
                if let add = add {
                    other.set = (add + other.set).sorted { $0.cmp($1) < 0 }
                }
            } else {
                mapping[i] = newStates.count
                newStates.append(state)
            }
        }
        
        if timing {
            let elapsed = Date().timeIntervalSince1970 - t0
            print("Merge identical pass \(pass)\(didMerge ? "" : ", done") (\(String(format: "%.2f", elapsed))s)")
        }
        
        if !didMerge { return currentStates }
        
        for state in newStates where state.defaultReduce == nil {
            state.actions = state.actions.map { action in
                if let shift = action as? Shift {
                    return shift.map(mapping: mapping, states: newStates)
                } else if let reduce = action as? Reduce {
                    return reduce.map()
                }
                return action
            } as [Any]
            
            state.goto = state.goto.map { $0.map(mapping: mapping, states: newStates) }
        }
        
        for i in 0..<newStates.count {
            newStates[i].id = i
        }
        
        currentStates = newStates
        pass += 1
    }
}

func eqActionSet(_ a: [Any], _ b: [Any]) -> Bool {
    if a.count != b.count { return false }
    for i in 0..<a.count {
        if let shiftA = a[i] as? Shift, let shiftB = b[i] as? Shift {
            if !shiftA.eq(shiftB) { return false }
        } else if let reduceA = a[i] as? Reduce, let reduceB = b[i] as? Reduce {
            if !reduceA.eq(reduceB) { return false }
        } else {
            return false
        }
    }
    return true
}

extension Term: Equatable {
    public static func ==(lhs: Term, rhs: Term) -> Bool {
        return lhs === rhs
    }
}

extension Pos: Equatable {
    public static func ==(lhs: Pos, rhs: Pos) -> Bool {
        return lhs.eq(rhs)
    }
}

extension Shift: Equatable {
    public static func ==(lhs: Shift, rhs: Shift) -> Bool {
        return lhs.eq(rhs)
    }
}

extension Reduce: Equatable {
    public static func ==(lhs: Reduce, rhs: Reduce) -> Bool {
        return lhs.eq(rhs)
    }
}

/// Finish the automaton by merging identical states and collapsing
public func finishAutomaton(_ full: [State]) -> [State] {
    let collapsed = collapseAutomaton(full)
    let result = mergeIdentical(collapsed)
    return result
}
