import Foundation
public typealias Props = [String: String]

public func hasProps(_ props: Props) -> Bool {
	!props.isEmpty
}

public func chain(_ values: Int...) -> Int {
	for v in values {
		if v != 0 { return v }
	}
	return 0
}

private nonisolated(unsafe) var termHashCounter = 0

public class Term: CustomStringConvertible {
	public var hash: Int
	public var id: Int = -1
	public var rules: [Rule] = []

	public let name: String
	public private(set) var flags: Int
	public let nodeName: String?
	public var props: Props

	public init(name: String, flags: Int, nodeName: String?, props: Props = [:]) {
		termHashCounter += 1
		hash = termHashCounter
		self.name = name
		self.flags = flags
		self.nodeName = nodeName
		self.props = props
	}

	public var description: String {
		name
	}

	public var nodeType: Bool {
		top || nodeName != nil || hasProps(props) || repeated
	}

	public var terminal: Bool {
		(flags & TermFlag.terminal) > 0
	}

	public var eof: Bool {
		(flags & TermFlag.eof) > 0
	}

	public var error: Bool {
		props["error"] != nil
	}

	public var top: Bool {
		(flags & TermFlag.top) > 0
	}

	public var interesting: Bool {
		flags > 0 || nodeName != nil
	}

	public var repeated: Bool {
		(flags & TermFlag.repeated) > 0
	}

	public var preserve: Bool {
		get { (flags & TermFlag.preserve) > 0 }
		set { flags = newValue ? flags | TermFlag.preserve : flags & ~TermFlag.preserve }
	}

	public var inline: Bool {
		get { (flags & TermFlag.inline) > 0 }
		set { flags = newValue ? flags | TermFlag.inline : flags & ~TermFlag.inline }
	}

	public func cmp(_ other: Term) -> Int {
		hash - other.hash
	}
}

public enum TermFlag {
	public static let terminal = 1
	public static let top = 2
	public static let eof = 4
	public static let preserve = 8
	public static let repeated = 16
	public static let inline = 32
}

public class TermSet {
	public var terms: [Term] = []
	public var names: [String: Term] = [:]
	public let eof: Term
	public let error: Term
	public var tops: [Term] = []

	public init() {
		let eofTerm = Term(name: "␄", flags: TermFlag.terminal | TermFlag.eof, nodeName: nil)
		let errorTerm = Term(name: "⚠", flags: TermFlag.preserve, nodeName: "⚠")
		terms.append(eofTerm); names["␄"] = eofTerm
		terms.append(errorTerm); names["⚠"] = errorTerm
		eof = eofTerm; error = errorTerm
	}

	@discardableResult
	public func term(_ name: String, _ nodeName: String?, _ flags: Int = 0, _ props: Props = [:]) -> Term {
		let t = Term(name: name, flags: flags, nodeName: nodeName, props: props)
		terms.append(t)
		names[name] = t
		return t
	}

	public func makeTop(_ nodeName: String?, _ props: Props) -> Term {
		let t = Term(name: "@top", flags: TermFlag.top, nodeName: nodeName, props: props)
		terms.append(t)
		names["@top"] = t
		tops.append(t)
		return t
	}

	public func makeTerminal(_ name: String, _ nodeName: String?, _ props: Props = [:]) -> Term {
		let t = Term(name: name, flags: TermFlag.terminal, nodeName: nodeName, props: props)
		terms.append(t)
		names[name] = t
		return t
	}

	public func makeNonTerminal(_ name: String, _ nodeName: String?, _ props: Props = [:]) -> Term {
		let t = Term(name: name, flags: 0, nodeName: nodeName, props: props)
		terms.append(t)
		names[name] = t
		return t
	}

	public func makeRepeat(_ name: String) -> Term {
		let t = Term(name: name, flags: TermFlag.repeated, nodeName: nil)
		terms.append(t)
		names[name] = t
		return t
	}

	public func uniqueName(_ name: String) -> String {
		var i = 0
		while true {
			let cur = i == 0 ? name : "\(name)-\(i)"
			if names[cur] == nil { return cur }
			i += 1
		}
	}

	public func finish(_ rules: [Rule]) throws -> (nodeTypes: [Term], names: [Int: String], minRepeatTerm: Int, maxTerm: Int) {
		for rule in rules {
			rule.name.rules.append(rule)
		}

		terms = terms.filter { t in
			t.terminal || t.preserve || rules.contains { $0.name === t || $0.parts.contains { $0 === t } }
		}

		var names: [Int: String] = [:]
		var nodeTypes = [error]

		error.id = LrTerm.Err
		var nextID = LrTerm.Err + 1

		for t in terms {
			if t.id < 0, t.nodeType, !t.repeated {
				t.id = nextID; nextID += 1; nodeTypes.append(t)
			}
		}
		let minRepeatTerm = nextID
		for t in terms {
			if t.repeated { t.id = nextID; nextID += 1; nodeTypes.append(t) }
		}
		eof.id = nextID; nextID += 1
		for t in terms {
			if t.id < 0 { t.id = nextID; nextID += 1 }
			if !t.name.isEmpty { names[t.id] = t.name }
		}
		if nextID >= 0xFFFE { throw GenError("Too many terms") }
		return (nodeTypes, names, minRepeatTerm, nextID - 1)
	}
}

private enum TermID {
	static let err = 0
}

public func cmpSet<T>(_ a: [T], _ b: [T], _ cmp: (T, T) -> Int) -> Int {
	if a.count != b.count { return a.count - b.count }
	for i in 0 ..< a.count {
		let diff = cmp(a[i], b[i])
		if diff != 0 { return diff }
	}
	return 0
}

private nonisolated(unsafe) let conflictsNone = Conflicts(precedence: 0)

public class Conflicts {
	public let precedence: Int
	public let ambigGroups: [String]
	public let cut: Int

	public init(precedence: Int, _ ambigGroups: [String] = [], cut: Int = 0) {
		self.precedence = precedence
		self.ambigGroups = ambigGroups
		self.cut = cut
	}

	public func join(_ other: Conflicts) -> Conflicts {
		if self === Conflicts.none || self === other { return other }
		if other === Conflicts.none { return self }
		return Conflicts(precedence: max(precedence, other.precedence),
		                 union(ambigGroups, other.ambigGroups),
		                 cut: max(cut, other.cut))
	}

	public func cmp(_ other: Conflicts) -> Int {
		return chain(precedence - other.precedence,
		             cmpSet(ambigGroups, other.ambigGroups) { a, b in a < b ? -1 : a > b ? 1 : 0 },
		             cut - other.cut)
	}

	public nonisolated(unsafe) static let none = Conflicts(precedence: 0)
}

public func union<T: Comparable>(_ a: [T], _ b: [T]) -> [T] {
	if a.isEmpty || a.elementsEqual(b) { return b }
	if b.isEmpty { return a }
	var result = a
	for v in b {
		if !a.contains(v) { result.append(v) }
	}
	return result.sorted()
}

private nonisolated(unsafe) var ruleIDCounter = 0

public class Rule: CustomStringConvertible {
	public let id: Int
	public let name: Term
	public let parts: [Term]
	public let conflicts: [Conflicts]
	public let skip: Term

	public init(name: Term, parts: [Term], conflicts: [Conflicts], skip: Term) {
		ruleIDCounter += 1
		id = ruleIDCounter
		self.name = name; self.parts = parts; self.conflicts = conflicts; self.skip = skip
	}

	public func cmp(_ rule: Rule) -> Int {
		id - rule.id
	}

	public func cmpNoName(_ rule: Rule) -> Int {
		return chain(parts.count - rule.parts.count,
		             skip.hash - rule.skip.hash,
		             parts.enumerated().reduce(0) { r, p in r != 0 ? r : p.element.cmp(rule.parts[p.offset]) },
		             cmpSet(conflicts, rule.conflicts) { a, b in a.cmp(b) })
	}

	public var description: String {
		"\(name) -> \(parts.map { "\($0)" }.joined(separator: " "))"
	}

	public var isRepeatWrap: Bool {
		name.repeated && parts.count == 2 && parts[0] === name
	}

	public func sameReduce(_ other: Rule) -> Bool {
		name === other.name && parts.count == other.parts.count && isRepeatWrap == other.isRepeatWrap
	}
}
