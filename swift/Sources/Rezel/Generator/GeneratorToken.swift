import Foundation
public let MAX_CHAR = 0xFFFF

public class Edge: CustomStringConvertible {
	public let from: Int
	public let to: Int
	public let target: GeneratorState

	public init(from: Int, to: Int, target: GeneratorState) {
		self.from = from; self.to = to; self.target = target
	}

	public var description: String {
		let label = from < 0 ? "ε" : charFor(from) + (to > from + 1 ? "-\(charFor(to - 1))" : "")
		return "-> \(target.id)[label=\(label)]"
	}
}

func charFor(_ n: Int) -> String {
	if n > MAX_CHAR { return "∞" }
	if n == 10 { return "\\n" }
	if n == 13 { return "\\r" }
	if n < 32 || (n >= 0xD800 && n < 0xDFFF) { return "\\u{\(String(n, radix: 16))}" }
	return String(UnicodeScalar(n)!)
}

private nonisolated(unsafe) var stateIDCounter = 1

public class GeneratorState: CustomStringConvertible {
	public var edges: [Edge] = []
	public let accepting: [Term]
	public let id: Int

	public init(accepting: [Term] = [], id: Int? = nil) {
		self.accepting = accepting
		self.id = id ?? stateIDCounter
		if id == nil { stateIDCounter += 1 }
	}

	public func edge(_ from: Int, _ to: Int, _ target: GeneratorState) {
		edges.append(Edge(from: from, to: to, target: target))
	}

	public func nullEdge(_ target: GeneratorState) {
		edge(-1, -1, target)
	}

	public func compile() -> GeneratorState {
		var localID = 0
		var labeled: [String: GeneratorState] = [:]
		let startState = explore(closure().sorted { $0.id - $1.id < 0 })
		return minimize(Array(labeled.values), start: startState)

		func explore(_ states: [GeneratorState]) -> GeneratorState {
			let key = ids(states)
			let newState = GeneratorState(accepting: states.reduce([] as [Term]) { unionObj($0, $1.accepting) }, id: localID)
			localID += 1
			labeled[key] = newState
			var out: [Edge] = []
			for s in states {
				for e in s.edges {
					if e.from >= 0 { out.append(e) }
				}
			}
			let transitions = mergeEdges(out)
			for merged in transitions {
				let targets = merged.targets.sorted { $0.id < $1.id }
				let targetKey = ids(targets)
				if let existing = labeled[targetKey] {
					newState.edge(merged.from, merged.to, existing)
				} else {
					newState.edge(merged.from, merged.to, explore(targets))
				}
			}
			return newState
		}
	}

	public func closure() -> [GeneratorState] {
		var result: [GeneratorState] = []
		var seen: Set<Int> = []
		func explore(_ state: GeneratorState) {
			if seen.contains(state.id) { return }
			seen.insert(state.id)
			if state.edges.contains(where: { $0.from >= 0 }) ||
				(!state.accepting.isEmpty && !state.edges.contains(where: { sameSetObjToken(state.accepting, $0.target.accepting) }))
			{
				result.append(state)
			}
			for e in state.edges {
				if e.from < 0 { explore(e.target) }
			}
		}
		explore(self)
		return result
	}

	public func findConflicts(_ occurTogether: @escaping (Term, Term) -> Bool) -> [TokenConflict] {
		var conflicts: [TokenConflict] = []
		let cycleTerms = self.cycleTerms()

		func add(_ a: Term, _ b: Term, _ soft: Int, _ aEdges: [Edge], _ bEdges: [Edge]?) {
			var a = a, b = b, soft = soft
			if a.id < b.id { swap(&a, &b); soft = -soft }
			if let found = conflicts.first(where: { $0.a === a && $0.b === b }) {
				if found.soft != soft { found.soft = 0 }
			} else {
				conflicts.append(TokenConflict(a: a, b: b, soft: soft,
				                               exampleA: exampleFromEdges(aEdges), exampleB: bEdges.map { exampleFromEdges($0) }))
			}
		}

		reachable { state, edges in
			if state.accepting.isEmpty { return }
			for i in 0 ..< state.accepting.count {
				for j in (i + 1) ..< state.accepting.count {
					add(state.accepting[i], state.accepting[j], 0, edges, nil)
				}
			}
			state.reachable { s, es in
				if s !== state {
					for term in s.accepting {
						let hasCycle = cycleTerms.contains(where: { $0 === term })
						for orig in state.accepting {
							if term !== orig {
								add(term, orig,
								    hasCycle || cycleTerms.contains(where: { $0 === orig }) || !occurTogether(term, orig) ? 0 : 1,
								    edges, edges + es)
							}
						}
					}
				}
			}
		}
		return conflicts
	}

	public func cycleTerms() -> [Term] {
		var work: [GeneratorState] = []
		reachable { state, _ in
			for e in state.edges {
				work.append(state); work.append(e.target)
			}
		}

		var table: [ObjectIdentifier: [GeneratorState]] = [:]
		var haveCycle: [GeneratorState] = []
		var i = 0
		while i < work.count {
			let from = work[i]; i += 1
			let to = work[i]; i += 1
			let key = ObjectIdentifier(from)
			var entry = table[key] ?? []
			if entry.contains(where: { $0 === to }) { continue }
			if from === to {
				if !haveCycle.contains(where: { $0 === from }) { haveCycle.append(from) }
			} else {
				for next in entry {
					work.append(from); work.append(next)
				}
				entry.append(to)
			}
			table[key] = entry
		}

		var result: [Term] = []
		for state in haveCycle {
			for term in state.accepting {
				if !result.contains(where: { $0 === term }) { result.append(term) }
			}
		}
		return result
	}

	public func reachable(_ f: (GeneratorState, [Edge]) -> Void) {
		var seen: [GeneratorState] = []
		var edges: [Edge] = []
		func explore(_ s: GeneratorState) {
			f(s, edges)
			seen.append(s)
			for e in s.edges {
				if !seen.contains(where: { $0 === e.target }) {
					edges.append(e)
					explore(e.target)
					edges.removeLast()
				}
			}
		}
		explore(self)
	}

	public var description: String {
		var out = "digraph {\n"
		reachable { state, _ in
			if !state.accepting.isEmpty {
				out += "  \(state.id) [label=\"\(state.accepting.map { $0.name }.joined(separator: ","))\"];\n"
			}
			for e in state.edges {
				out += "  \(state.id) \(e);\n"
			}
		}
		return out + "}"
	}

	public func toArray(_ groupMasks: [Int: Int], _ precedence: [Int]) throws -> [UInt16] {
		var offsets: [Int] = Array(repeating: 0, count: 1000)
		var data: [Int] = []
		reachable { state, _ in
			let start = data.count
			let acceptEnd = start + 3 + state.accepting.count * 2
			while offsets.count <= state.id {
				offsets.append(0)
			}
			offsets[state.id] = start
			data.append(state.stateMask(groupMasks))
			data.append(acceptEnd)
			data.append(state.edges.count)
			let sorted = state.accepting.sorted { precedence.firstIndex(of: $0.id) ?? 0 < precedence.firstIndex(of: $1.id) ?? 0 }
			for term in sorted {
				data.append(term.id); data.append(groupMasks[term.id] ?? 0xFFFF)
			}
			for e in state.edges {
				data.append(e.from); data.append(e.to); data.append(-e.target.id - 1)
			}
		}
		for i in 0 ..< data.count {
			if data[i] < 0 { data[i] = offsets[-data[i] - 1] }
		}
		if data.count > (1 << 16) { throw GenError("Tokenizer tables too big to represent with 16-bit offsets.") }
		return data.map { UInt16(truncatingIfNeeded: $0) }
	}

	public func stateMask(_ groupMasks: [Int: Int]) -> Int {
		var mask = 0
		reachable { state, _ in
			for term in state.accepting {
				mask |= groupMasks[term.id] ?? 0xFFFF
			}
		}
		return mask
	}
}

public class TokenConflict {
	public let a: Term
	public let b: Term
	public var soft: Int
	public let exampleA: String
	public let exampleB: String?

	public init(a: Term, b: Term, soft: Int, exampleA: String, exampleB: String? = nil) {
		self.a = a; self.b = b; self.soft = soft; self.exampleA = exampleA; self.exampleB = exampleB
	}
}

func exampleFromEdges(_ edges: [Edge]) -> String {
	var str = ""
	for e in edges {
		if e.from >= 0 { str += String(UnicodeScalar(e.from)!) }
	}
	return str
}

func ids(_ elts: [GeneratorState]) -> String {
	elts.map { "\($0.id)" }.joined(separator: "-")
}

func tokenSameSet<T: Equatable>(_ a: [T], _ b: [T]) -> Bool {
	a.count == b.count && zip(a, b).allSatisfy { $0.0 == $0.1 }
}

class MergedEdge {
	let from: Int, to: Int
	let targets: [GeneratorState]
	init(from: Int, to: Int, targets: [GeneratorState]) {
		self.from = from; self.to = to; self.targets = targets
	}
}

func mergeEdges(_ edges: [Edge]) -> [MergedEdge] {
	var separate: [Int] = []
	var result: [MergedEdge] = []
	for e in edges {
		if !separate.contains(e.from) { separate.append(e.from) }
		if !separate.contains(e.to) { separate.append(e.to) }
	}
	separate.sort()
	if separate.count > 1 {
		for i in 1 ..< separate.count {
			let from = separate[i - 1], to = separate[i]
			var found: [GeneratorState] = []
			for e in edges {
				if e.to > from, e.from < to {
					for target in e.target.closure() {
						if !found.contains(where: { $0 === target }) { found.append(target) }
					}
				}
			}
			if !found.isEmpty { result.append(MergedEdge(from: from, to: to, targets: found)) }
		}
	}
	let eof = edges.filter { $0.from == Seq.End && $0.to == Seq.End }
	if !eof.isEmpty {
		var found: [GeneratorState] = []
		for e in eof {
			for target in e.target.closure() {
				if !found.contains(where: { $0 === target }) { found.append(target) }
			}
		}
		if !found.isEmpty { result.append(MergedEdge(from: Seq.End, to: Seq.End, targets: found)) }
	}
	return result
}

func minimize(_ states: [GeneratorState], start: GeneratorState) -> GeneratorState {
	var partition: [Int: [GeneratorState]] = [:]
	var byAccepting: [String: [GeneratorState]] = [:]
	for state in states {
		let id = state.accepting.map { $0.id }.sorted().map { "\($0)" }.joined(separator: ",")
		let key = id
		if byAccepting[key] == nil { byAccepting[key] = [] }
		byAccepting[key]!.append(state)
		partition[state.id] = byAccepting[key]
	}

	while true {
		var split = false
		var newPartition: [Int: [GeneratorState]] = [:]
		for state in states {
			if newPartition[state.id] != nil { continue }
			guard let group = partition[state.id] else { continue }
			if group.count == 1 {
				newPartition[group[0].id] = group
				continue
			}
			var parts: [[GeneratorState]] = []
			for s in group {
				if let idx = parts.firstIndex(where: { isEquivalent(s, $0[0], partition) }) {
					parts[idx].append(s)
				} else {
					parts.append([s])
				}
			}
			if parts.count > 1 { split = true }
			for p in parts {
				for s in p {
					newPartition[s.id] = p
				}
			}
		}
		if !split { return applyMinimization(states, start: start, partition: partition) }
		partition = newPartition
	}
}

func isEquivalent(_ a: GeneratorState, _ b: GeneratorState, _ partition: [Int: [GeneratorState]]) -> Bool {
	if a.edges.count != b.edges.count { return false }
	for i in 0 ..< a.edges.count {
		let eA = a.edges[i], eB = b.edges[i]
		if eA.from != eB.from || eA.to != eB.to { return false }
		let gA = partition[eA.target.id]
		let gB = partition[eB.target.id]
		if let gA = gA, let gB = gB, gA[0].id == gB[0].id { continue }
		if gA == nil && gB == nil { continue }
		return false
	}
	return true
}

func applyMinimization(_ states: [GeneratorState], start: GeneratorState, partition: [Int: [GeneratorState]]) -> GeneratorState {
	for state in states {
		for i in 0 ..< state.edges.count {
			let e = state.edges[i]
			guard let target = partition[e.target.id]?[0] else { continue }
			if target !== e.target { state.edges[i] = Edge(from: e.from, to: e.to, target: target) }
		}
	}
	return partition[start.id]![0]
}

func unionObj(_ a: [Term], _ b: [Term]) -> [Term] {
	if a.isEmpty { return b }
	var result = a
	for v in b {
		if !result.contains(where: { $0 === v }) { result.append(v) }
	}
	return result
}

func sameSetObjToken(_ a: [Term], _ b: [Term]) -> Bool {
	if a.count != b.count { return false }
	for i in 0 ..< a.count {
		if a[i] !== b[i] { return false }
	}
	return true
}
