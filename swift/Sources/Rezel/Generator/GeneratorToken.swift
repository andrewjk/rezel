//
//  Token.swift
//  Rezel
//
//  Created on 2025-06-11.
//

import Foundation

public let MAX_CHAR: Int = 0xffff

public class TokenBuildState: TokenState {
    func edge(_ from: Int, _ to: Int, _ target: TokenBuildState) {
        edges.append(Edge(from: from, to: to, target: target))
    }
    
    func nullEdge(_ target: TokenBuildState) {
        edges.append(Edge(from: -1, to: -1, target: target))
    }
}

/// Edge between states in the tokenizer automaton
public class Edge {
    let from: Int
    let to: Int
    var target: TokenState
    
    init(from: Int, to: Int, target: TokenState) {
        self.from = from
        self.to = to
        self.target = target
    }
    
    func toString() -> String {
        let label = from < 0 ? "ε" : charFor(from) + (to > from + 1 ? "-\(charFor(to - 1))" : "")
        return "-> \(target.id)[label=\"\(label)\"]"
    }
}

fileprivate func charFor(_ n: Int) -> String {
    if n > MAX_CHAR {
        return "∞"
    } else if n == 10 {
        return "\\n"
    } else if n == 13 {
        return "\\r"
    } else if n < 32 || (n >= 0xd800 && n < 0xdfff) {
        return "\\u{\(String(n, radix: 16))}"
    } else {
        return String(UnicodeScalar(n)!)
    }
}

fileprivate typealias Partition = [Int: [TokenState]]

fileprivate func unionTerms(_ a: [Term], _ b: [Term]) -> [Term] {
    var result = a
    for term in b {
        if !result.contains(where: { $0 === term }) {
            result.append(term)
        }
    }
    return result.sorted { $0.id < $1.id }
}

/// Minimize the automaton states
fileprivate func minimize(_ states: [TokenState], start: TokenState) -> TokenState {
    var partition: Partition = [:]
    var byAccepting: [String: [TokenState]] = [:]
    
    for state in states {
        let id = ids(elts: state.accepting)
        var group = byAccepting[id] ?? []
        group.append(state)
        byAccepting[id] = group
        partition[state.id] = group
    }
    
    while true {
        var split = false
        var newPartition: Partition = [:]
        
        for state in states {
            if newPartition[state.id] != nil { continue }
            
            let group = partition[state.id]!
            if group.count == 1 {
                newPartition[group[0].id] = group
                continue
            }
            
            var parts: [[TokenState]] = []
            groupsLoop: for state in group {
                for var p in parts {
                    if isEquivalent(a: state, b: p[0], partition: partition) {
                        p.append(state)
                        continue groupsLoop
                    }
                }
                parts.append([state])
            }
            
            if parts.count > 1 {
                split = true
            }
            
            for p in parts {
                for s in p {
                    newPartition[s.id] = p
                }
            }
        }
        
        if !split {
            return applyMinimization(states: states, start: start, partition: partition)
        }
        
        partition = newPartition
    }
}

fileprivate func samePartition(_ a: [TokenState]?, _ b: [TokenState]?) -> Bool {
    guard let a = a, let b = b else { return false }
    if a.count != b.count { return false }
    for i in 0..<a.count {
        if a[i] !== b[i] { return false }
    }
    return true
}

fileprivate func isEquivalent(a: TokenState, b: TokenState, partition: Partition) -> Bool {
    if a.edges.count != b.edges.count {
        return false
    }
    
    for i in 0..<a.edges.count {
        let eA = a.edges[i]
        let eB = b.edges[i]
        
        if eA.from != eB.from || eA.to != eB.to || !samePartition(partition[eA.target.id], partition[eB.target.id]) {
            return false
        }
    }
    
    return true
}

fileprivate func applyMinimization(states: [TokenState], start: TokenState, partition: Partition) -> TokenState {
    for state in states {
        for i in 0..<state.edges.count {
            let edge = state.edges[i]
            let target = partition[edge.target.id]![0]
            if target !== edge.target {
                state.edges[i] = Edge(from: edge.from, to: edge.to, target: target)
            }
        }
    }
    
    return partition[start.id]![0]
}

fileprivate nonisolated(unsafe) var stateID = 1

/// TokenState in the tokenizer automaton
public class TokenState {
    var edges: [Edge] = []
    let accepting: [Term]
    let id: Int
    
    init(accepting: [Term] = [], id: Int = stateID) {
        self.accepting = accepting
        self.id = id
        if id == stateID {
            stateID += 1
        }
    }
    
    func edge(from: Int, to: Int, target: TokenState) {
        edges.append(Edge(from: from, to: to, target: target))
    }
    
    func nullEdge(target: TokenState) {
        edge(from: -1, to: -1, target: target)
    }
    
    func compile() -> TokenState {
        var labeled: [String: TokenState] = [:]
        var localID = 0
        
        let startTokenState = explore(states: closure().sorted { $0.id < $1.id })
        return minimize(Array(labeled.values), start: startTokenState)
        
        func explore(states: [TokenState]) -> TokenState {
            let allAccepting = states.reduce([Term]()) { (result: [Term], state: TokenState) in
                return unionTerms(result, state.accepting)
            }
            
            let newTokenState = TokenState(accepting: allAccepting, id: localID)
            labeled[ids(elts: states)] = newTokenState
            localID += 1
            
            var out: [Edge] = []
            for state in states {
                for edge in state.edges {
                    if edge.from >= 0 {
                        out.append(edge)
                    }
                }
            }
            
            let transitions = mergeEdges(edges: out)
            for merged in transitions {
                let targets = merged.targets.sorted { $0.id < $1.id }
                let targetTokenState = labeled[ids(elts: targets)] ?? explore(states: targets)
                newTokenState.edge(from: merged.from, to: merged.to, target: targetTokenState)
            }
            
            return newTokenState
        }
    }
    
    func closure() -> [TokenState] {
        var result: [TokenState] = []
        var seen: Set<Int> = []
        
        func explore(_ state: TokenState) {
            if seen.contains(state.id) { return }
            seen.insert(state.id)
            
            let hasNonEpsilon = state.edges.contains { $0.from >= 0 }
            let hasUniqueAccepting = !state.accepting.isEmpty && !state.edges.contains { edge in
                sameSet(a: state.accepting, b: edge.target.accepting)
            }
            
            if hasNonEpsilon || hasUniqueAccepting {
                result.append(state)
            }
            
            for edge in state.edges {
                if edge.from < 0 {
                    explore(edge.target)
                }
            }
        }
        
        explore(self)
        return result
    }
    
    func findConflicts(occurTogether: (Term, Term) -> Bool) -> [Conflict] {
        var conflicts: [Conflict] = []
        let cycleTerms = cycleTerms()
        
        func add(_ a: Term, _ b: Term, _ soft: Int, _ aEdges: [Edge], _ bEdges: [Edge]?) {
            var a = a
            var b = b
            var soft = soft
            
            if a.id < b.id {
                let temp = a
                a = b
                b = temp
                soft = -soft
            }
            
            if let found = conflicts.first(where: { $0.a.id == a.id && $0.b.id == b.id }) {
                if found.soft != soft {
                    found.soft = 0
                }
            } else {
                conflicts.append(Conflict(a: a, b: b, soft: soft, exampleA: exampleFromEdges(aEdges), exampleB: bEdges != nil ? exampleFromEdges(bEdges!) : nil))
            }
        }
        
        reachable { (state, edges) in
            if state.accepting.isEmpty { return }
            
            for i in 0..<state.accepting.count {
                for j in (i + 1)..<state.accepting.count {
                    add(state.accepting[i], state.accepting[j], 0, edges, nil)
                }
            }
            
            state.reachable { (s, es) in
                if s !== state {
                    for term in s.accepting {
                        let hasCycle = cycleTerms.contains { $0.id == term.id }
                        for orig in state.accepting {
                            if term.id != orig.id {
                                let softConflict = hasCycle || cycleTerms.contains { $0.id == orig.id } || !occurTogether(term, orig) ? 0 : 1
                                add(term, orig, softConflict, edges, edges + es)
                            }
                        }
                    }
                }
            }
        }
        
        return conflicts
    }
    
    func cycleTerms() -> [Term] {
        var work: [TokenState] = []
        reachable { (state, edges) in
            for edge in state.edges {
                work.append(state)
                work.append(edge.target)
            }
        }
        
        var table: [Int: [TokenState]] = [:]
        var haveCycle: [TokenState] = []
        
        var i = 0
        while i < work.count {
            let from = work[i]
            i += 1
            let to = work[i]
            i += 1
            
            var entry = table[from.id] ?? []
            if entry.contains(where: { $0 === to }) { continue }
            
            if from === to {
                if !haveCycle.contains(where: { $0 === from }) {
                    haveCycle.append(from)
                }
            } else {
                for next in entry {
                    work.append(from)
                    work.append(next)
                }
                entry.append(to)
            }
            table[from.id] = entry
        }
        
        var result: [Term] = []
        for state in haveCycle {
            for term in state.accepting {
                if !result.contains(where: { $0.id == term.id }) {
                    result.append(term)
                }
            }
        }
        
        return result
    }
    
    func reachable(_ f: (TokenState, [Edge]) -> Void) {
        var seen: [TokenState] = []
        var edges: [Edge] = []
        
        func explore(_ s: TokenState) {
            f(s, edges)
            seen.append(s)
            
            for edge in s.edges {
                if !seen.contains(where: { $0 === edge.target }) {
                    edges.append(edge)
                    explore(edge.target)
                    edges.removeLast()
                }
            }
        }
        
        explore(self)
    }
    
    func toString() -> String {
        var out = "digraph {\n"
        reachable { (state, _) in
            if !state.accepting.isEmpty {
                out += "  \(state.id) [label=\"\(state.accepting.map { $0.name }.joined())\"];\n"
            }
            for edge in state.edges {
                out += "  \(state.id) \(edge.toString());\n"
            }
        }
        return out + "}"
    }
    
    func toArray(groupMasks: [Int: Int], precedence: [Int]) -> [UInt16] {
        var offsets: [Int: Int] = [:]
        var data: [Int] = []
        
        reachable { (state, _) in
            let start = data.count
            let acceptEnd = start + 3 + state.accepting.count * 2
            offsets[state.id] = start
            
            data.append(state.stateMask(groupMasks: groupMasks))
            data.append(acceptEnd)
            data.append(state.edges.count)
            
            let sortedAccepting = state.accepting.sorted { a, b in
                let aIndex = precedence.firstIndex(of: a.id) ?? precedence.count
                let bIndex = precedence.firstIndex(of: b.id) ?? precedence.count
                return aIndex < bIndex
            }
            
            for term in sortedAccepting {
                data.append(term.id)
                data.append(groupMasks[term.id] ?? 0xffff)
            }
            
            for edge in state.edges {
                data.append(edge.from)
                data.append(edge.to)
                data.append(-edge.target.id - 1)
            }
        }
        
        // Replace negative numbers with resolved state offsets
        for i in 0..<data.count {
            if data[i] < 0 {
                data[i] = offsets[-data[i] - 1]!
            }
        }
        
        if data.count > (1 << 16) {
            fatalError("Tokenizer tables too big to represent with 16-bit offsets.")
        }
        
        return data.map { UInt16($0) }
    }
    
    func stateMask(groupMasks: [Int: Int]) -> Int {
        var mask = 0
        reachable { (state, _) in
            for term in state.accepting {
                mask |= groupMasks[term.id] ?? 0xffff
            }
        }
        return mask
    }
}

/// Conflict between two tokens
public class Conflict {
    let a: Term
    let b: Term
    var soft: Int
    let exampleA: String
    let exampleB: String?
    
    init(a: Term, b: Term, soft: Int, exampleA: String, exampleB: String?) {
        self.a = a
        self.b = b
        self.soft = soft
        self.exampleA = exampleA
        self.exampleB = exampleB
    }
}

fileprivate func exampleFromEdges(_ edges: [Edge]) -> String {
    return edges.map { String(UnicodeScalar($0.from)!) }.joined()
}

fileprivate func ids(elts: [Term]) -> String {
    return elts.map { String($0.id) }.joined(separator: "-")
}

fileprivate func ids(elts: [TokenState]) -> String {
    return elts.map { String($0.id) }.joined(separator: "-")
}

fileprivate func sameSet<T: Equatable>(a: [T], b: [T]) -> Bool {
    if a.count != b.count {
        return false
    }
    for i in 0..<a.count {
        if a[i] != b[i] {
            return false
        }
    }
    return true
}

fileprivate func sameSet(a: [Term], b: [Term]) -> Bool {
    if a.count != b.count {
        return false
    }
    for i in 0..<a.count {
        if a[i] !== b[i] {
            return false
        }
    }
    return true
}

/// Merged edge with multiple target states
fileprivate class MergedEdge {
    let from: Int
    let to: Int
    let targets: [TokenState]
    
    init(from: Int, to: Int, targets: [TokenState]) {
        self.from = from
        self.to = to
        self.targets = targets
    }
}

/// Merge multiple edges into mutually exclusive ranges
fileprivate func mergeEdges(edges: [Edge]) -> [MergedEdge] {
    var separate: [Int] = []
    var result: [MergedEdge] = []
    
    for edge in edges {
        if !separate.contains(edge.from) {
            separate.append(edge.from)
        }
        if !separate.contains(edge.to) {
            separate.append(edge.to)
        }
    }
    
    separate.sort()
    
    for i in 1..<separate.count {
        let from = separate[i - 1]
        let to = separate[i]
        var found: [TokenState] = []
        
        for edge in edges {
            if edge.to > from && edge.from < to {
                for target in edge.target.closure() {
                    if !found.contains(where: { $0 === target }) {
                        found.append(target)
                    }
                }
            }
        }
        
        if !found.isEmpty {
            result.append(MergedEdge(from: from, to: to, targets: found))
        }
    }
    
    let eof = edges.filter { $0.from == Seq.end && $0.to == Seq.end }
    if !eof.isEmpty {
        var found: [TokenState] = []
        for edge in eof {
            for target in edge.target.closure() {
                if !found.contains(where: { $0 === target }) {
                    found.append(target)
                }
            }
        }
        if !found.isEmpty {
            result.append(MergedEdge(from: Seq.end, to: Seq.end, targets: found))
        }
    }
    
    return result
}