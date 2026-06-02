//
//  Grammar.swift
//  Rezel
//
//  Created on 2025-06-11.
//

import Foundation

fileprivate struct TermFlag {
    static let terminal = 1
    static let top = 2
    static let eof = 4
    static let preserve = 8
    static let repeated = 16
    static let inline = 32
}

public typealias Props = [String: String]

public func hasProps(_ props: Props) -> Bool {
    return !props.isEmpty
}

fileprivate nonisolated(unsafe) var termHash = 0

/// A term in the grammar (terminal or non-terminal)
public class Term {
    var hash: Int = { termHash += 1; return termHash }()
    var id: Int = -1
    var rules: [Rule] = []
    
    let name: String
    private var flags: Int
    let nodeName: String?
    var props: Props
    
    init(name: String, flags: Int, nodeName: String?, props: Props = [:]) {
        self.name = name
        self.flags = flags
        self.nodeName = nodeName
        self.props = props
    }
    
    public func toString() -> String {
        return name
    }
    
    var nodeType: Bool {
        return top || nodeName != nil || hasProps(props) || repeated
    }
    
    var terminal: Bool {
        return (flags & TermFlag.terminal) > 0
    }
    
    var `eof`: Bool {
        return (flags & TermFlag.eof) > 0
    }
    
    var error: Bool {
        return props["error"] != nil
    }
    
    var top: Bool {
        return (flags & TermFlag.top) > 0
    }
    
    var interesting: Bool {
        return flags > 0 || nodeName != nil
    }
    
    var repeated: Bool {
        return (flags & TermFlag.repeated) > 0
    }
    
    var preserve: Bool {
        get {
            return (flags & TermFlag.preserve) > 0
        }
        set {
            flags = newValue ? (flags | TermFlag.preserve) : (flags & ~TermFlag.preserve)
        }
    }
    
    var `inline`: Bool {
        get {
            return (flags & TermFlag.inline) > 0
        }
        set {
            flags = newValue ? (flags | TermFlag.inline) : (flags & ~TermFlag.inline)
        }
    }
    
    func cmp(_ other: Term) -> Int {
        return hash - other.hash
    }
}

/// Set of terms in the grammar
public class TermSet {
    var terms: [Term] = []
    var names: [String: Term] = [:]
    var eof: Term
    var error: Term
    var tops: [Term] = []
    
    init() {
        eof = Term(name: "␄", flags: TermFlag.terminal | TermFlag.eof, nodeName: nil)
        error = Term(name: "⚠", flags: TermFlag.preserve, nodeName: "⚠")
        terms.append(eof)
        terms.append(error)
        names["␄"] = eof
        names["⚠"] = error
    }
    
    func term(_ name: String, nodeName: String?, flags: Int = 0, props: Props = [:]) -> Term {
        let term = Term(name: name, flags: flags, nodeName: nodeName, props: props)
        terms.append(term)
        names[name] = term
        return term
    }
    
    func makeTop(nodeName: String?, props: Props) -> Term {
        let term = self.term("@top", nodeName: nodeName, flags: TermFlag.top, props: props)
        tops.append(term)
        return term
    }
    
    func makeTerminal(_ name: String, nodeName: String?, props: Props = [:]) -> Term {
        return term(name, nodeName: nodeName, flags: TermFlag.terminal, props: props)
    }
    
    func makeNonTerminal(_ name: String, nodeName: String?, props: Props = [:]) -> Term {
        return term(name, nodeName: nodeName, flags: 0, props: props)
    }
    
    func makeRepeat(_ name: String) -> Term {
        return term(name, nodeName: nil, flags: TermFlag.repeated)
    }
    
    func uniqueName(_ name: String) -> String {
        var i = 0
        while true {
            let cur = i == 0 ? name : "\(name)-\(i)"
            if names[cur] == nil {
                return cur
            }
            i += 1
        }
    }
    
    func finish(rules: [Rule]) -> (nodeTypes: [Term], names: [Int: String], minRepeatTerm: Int, maxTerm: Int) {
        for rule in rules {
            rule.name.rules.append(rule)
        }
        
        terms = terms.filter { term in
            term.terminal || term.preserve || rules.contains { rule in
                rule.name === term || rule.parts.contains(where: { $0 === term })
            }
        }
        
        var names: [Int: String] = [:]
        var nodeTypes = [error]
        
        error.id = 0
        var nextID = 1
        
        // Assign ids to terms that represent node types
        for term in terms {
            if term.id < 0 && term.nodeType && !term.repeated {
                term.id = nextID
                nextID += 1
                nodeTypes.append(term)
            }
        }
        
        // Put all repeated terms after the regular node types
        let minRepeatTerm = nextID
        for term in terms {
            if term.repeated {
                term.id = nextID
                nextID += 1
                nodeTypes.append(term)
            }
        }
        
        // Then comes the EOF term
        eof.id = nextID
        nextID += 1
        
        // And then the remaining (non-node, non-repeat) terms
        for term in terms {
            if term.id < 0 {
                term.id = nextID
                nextID += 1
            }
            if term.name.isEmpty == false {
                names[term.id] = term.name
            }
        }
        
        if nextID >= 0xfffe {
            fatalError("Too many terms")
        }
        
        return (nodeTypes: nodeTypes, names: names, minRepeatTerm: minRepeatTerm, maxTerm: nextID - 1)
    }
}

/// Compare two arrays element by element
public func cmpSet<T>(_ a: [T], _ b: [T], cmp: (T, T) -> Int) -> Int {
    if a.count != b.count {
        return a.count - b.count
    }
    for i in 0..<a.count {
        let diff = cmp(a[i], b[i])
        if diff != 0 {
            return diff
        }
    }
    return 0
}

/// Conflict resolution information
public class Conflicts {
    let precedence: Int
    let ambigGroups: [String]
    let cut: Int
    
    init(precedence: Int, ambigGroups: [String] = [], cut: Int = 0) {
        self.precedence = precedence
        self.ambigGroups = ambigGroups
        self.cut = cut
    }
    
    func join(_ other: Conflicts) -> Conflicts {
        if self === Conflicts.none || self === other {
            return other
        }
        if other === Conflicts.none {
            return self
        }
        return Conflicts(
            precedence: max(self.precedence, other.precedence),
            ambigGroups: union(self.ambigGroups, other.ambigGroups),
            cut: max(self.cut, other.cut)
        )
    }
    
    func cmp(_ other: Conflicts) -> Int {
        let precedenceDiff = self.precedence - other.precedence
        if precedenceDiff != 0 {
            return precedenceDiff
        }
        
        let ambigGroupsDiff = cmpSet(self.ambigGroups, other.ambigGroups) { a, b in
            if a < b { return -1 }
            if a > b { return 1 }
            return 0
        }
        if ambigGroupsDiff != 0 {
            return ambigGroupsDiff
        }
        
        return self.cut - other.cut
    }
    
    static nonisolated(unsafe) let none = Conflicts(precedence: 0)
}

/// Union of two sorted arrays
public func union<T>(_ a: [T], _ b: [T]) -> [T] where T: Comparable {
    if a.isEmpty || a == b {
        return b
    }
    if b.isEmpty {
        return a
    }
    
    var result = a
    for value in b {
        if !a.contains(value) {
            result.append(value)
        }
    }
    return result.sorted()
}

fileprivate nonisolated(unsafe) var ruleID = 0

/// A grammar rule
public class Rule {
    let id: Int = { ruleID += 1; return ruleID }()
    
    let name: Term
    let parts: [Term]
    let conflicts: [Conflicts]
    let skip: Term
    
    init(name: Term, parts: [Term], conflicts: [Conflicts], skip: Term) {
        self.name = name
        self.parts = parts
        self.conflicts = conflicts
        self.skip = skip
    }
    
    func cmp(_ rule: Rule) -> Int {
        return id - rule.id
    }
    
    func cmpNoName(_ rule: Rule) -> Int {
        let lengthDiff = parts.count - rule.parts.count
        if lengthDiff != 0 {
            return lengthDiff
        }
        
        let skipDiff = skip.hash - rule.skip.hash
        if skipDiff != 0 {
            return skipDiff
        }
        
        for i in 0..<parts.count {
            let partDiff = parts[i].cmp(rule.parts[i])
            if partDiff != 0 {
                return partDiff
            }
        }
        
        return cmpSet(conflicts, rule.conflicts) { a, b in
            a.cmp(b)
        }
    }
    
    func toString() -> String {
        return "\(name) -> \(parts.map { $0.toString() }.joined(separator: " "))"
    }
    
    var isRepeatWrap: Bool {
        return name.repeated && parts.count == 2 && parts[0] === name
    }
    
    func sameReduce(_ other: Rule) -> Bool {
        return name === other.name &&
               parts.count == other.parts.count &&
               isRepeatWrap == other.isRepeatWrap
    }
}