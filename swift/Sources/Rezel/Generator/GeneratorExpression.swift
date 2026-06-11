import Foundation

public class Expression: Node {
	public var prec: Int {
		get { 10 } set {}
	}

	public func walk(_ f: (Expression) -> Expression) -> Expression {
		f(self)
	}

	public func eq(_: Expression) -> Bool {
		false
	}
}

public class NameExpression: Expression {
	public let id: Identifier
	public let args: [Expression]

	public init(start: Int, id: Identifier, args: [Expression]) {
		self.id = id; self.args = args; super.init(start: start)
	}

	override public var description: String {
		id.name + (args.isEmpty ? "" : "<\(args.map { $0.description }.joined(separator: ","))>")
	}

	override public func eq(_ other: Expression) -> Bool {
		guard let o = other as? NameExpression else { return false }
		return id.name == o.id.name && exprsEq(args, o.args)
	}

	override public func walk(_ f: (Expression) -> Expression) -> Expression {
		let newArgs = walkExprs(args, f)
		return f(sameExprs(newArgs, args) ? self : NameExpression(start: start, id: id, args: newArgs))
	}
}

public class SpecializeExpression: Expression {
	public let type: String
	public let props: [Prop]
	public let token: Expression
	public let content: Expression

	public init(start: Int, type: String, props: [Prop], token: Expression, content: Expression) {
		self.type = type; self.props = props; self.token = token; self.content = content
		super.init(start: start)
	}

	override public var description: String {
		"@\(type)[\(props.map { $0.description }.joined(separator: ","))]<\(token), \(content)>"
	}

	override public func eq(_ other: Expression) -> Bool {
		guard let o = other as? SpecializeExpression else { return false }
		return type == o.type && Prop.eqProps(props, o.props) && exprEq(token, o.token) && exprEq(content, o.content)
	}

	override public func walk(_ f: (Expression) -> Expression) -> Expression {
		let t = token.walk(f), c = content.walk(f)
		return f(t === token && c === content ? self : SpecializeExpression(start: start, type: type, props: props, token: t, content: c))
	}
}

public class InlineRuleExpression: Expression {
	public let rule: RuleDeclaration

	public init(start: Int, rule: RuleDeclaration) {
		self.rule = rule; super.init(start: start)
	}

	override public var description: String {
		"\(rule.id)\(rule.props.isEmpty ? "" : "[\(rule.props.map { $0.description }.joined(separator: ","))]") { \(rule.expr) }"
	}

	override public func eq(_ other: Expression) -> Bool {
		guard let o = other as? InlineRuleExpression else { return false }
		return exprEq(rule.expr, o.rule.expr) && rule.id.name == o.rule.id.name && Prop.eqProps(rule.props, o.rule.props)
	}

	override public func walk(_ f: (Expression) -> Expression) -> Expression {
		let e = rule.expr.walk(f)
		return f(e === rule.expr ? self : InlineRuleExpression(start: start, rule: RuleDeclaration(start: rule.start, id: rule.id, props: rule.props, params: [], expr: e)))
	}
}

public class ChoiceExpression: Expression {
	override public var prec: Int {
		get { 1 } set {}
	}

	public let exprs: [Expression]

	public init(start: Int, exprs: [Expression]) {
		self.exprs = exprs; super.init(start: start)
	}

	override public var description: String {
		exprs.map { maybeParens($0, parent: self) }.joined(separator: " | ")
	}

	override public func eq(_ other: Expression) -> Bool {
		guard let o = other as? ChoiceExpression else { return false }
		return exprsEq(exprs, o.exprs)
	}

	override public func walk(_ f: (Expression) -> Expression) -> Expression {
		let newExprs = walkExprs(exprs, f)
		return f(sameExprs(newExprs, exprs) ? self : ChoiceExpression(start: start, exprs: newExprs))
	}
}

public class SequenceExpression: Expression {
	override public var prec: Int {
		get { 2 } set {}
	}

	public let exprs: [Expression]
	public let markers: [[ConflictMarker]]
	public let empty: Bool

	public init(start: Int, exprs: [Expression], markers: [[ConflictMarker]], empty: Bool = false) {
		self.exprs = exprs; self.markers = markers; self.empty = empty; super.init(start: start)
	}

	override public var description: String {
		empty ? "()" : exprs.map { maybeParens($0, parent: self) }.joined(separator: " ")
	}

	override public func eq(_ other: Expression) -> Bool {
		guard let o = other as? SequenceExpression else { return false }
		return exprsEq(exprs, o.exprs) && markers.enumerated().allSatisfy { i, m in
			let om = o.markers[i]
			return m.count == om.count && m.enumerated().allSatisfy { j, x in x.eq(om[j]) }
		}
	}

	override public func walk(_ f: (Expression) -> Expression) -> Expression {
		let newExprs = walkExprs(exprs, f)
		return f(sameExprs(newExprs, exprs) ? self : SequenceExpression(start: start, exprs: newExprs, markers: markers, empty: empty && newExprs.isEmpty))
	}
}

public class ConflictMarker: Node {
	public let id: Identifier
	public let type: MarkerType

	public init(start: Int, id: Identifier, type: MarkerType) {
		self.id = id; self.type = type; super.init(start: start)
	}

	override public var description: String {
		(type == .ambig ? "~" : "!") + id.name
	}

	public func eq(_ other: ConflictMarker) -> Bool {
		id.name == other.id.name && type == other.type
	}
}

public enum MarkerType {
	case ambig, prec
}

public class RepeatExpression: Expression {
	override public var prec: Int {
		get { 3 } set {}
	}

	public let expr: Expression
	public let kind: RepeatKind

	public init(start: Int, expr: Expression, kind: RepeatKind) {
		self.expr = expr; self.kind = kind; super.init(start: start)
	}

	override public var description: String {
		maybeParens(expr, parent: self) + kind.rawValue
	}

	override public func eq(_ other: Expression) -> Bool {
		guard let o = other as? RepeatExpression else { return false }
		return exprEq(expr, o.expr) && kind == o.kind
	}

	override public func walk(_ f: (Expression) -> Expression) -> Expression {
		let e = expr.walk(f)
		return f(e === expr ? self : RepeatExpression(start: start, expr: e, kind: kind))
	}
}

public enum RepeatKind: String {
	case optional = "?", star = "*", plus = "+"
}

public class LiteralExpression: Expression {
	public let value: String
	public init(start: Int, value: String) {
		self.value = value; super.init(start: start)
	}

	override public var description: String {
		"\"\(value)\""
	}

	override public func eq(_ other: Expression) -> Bool {
		guard let o = other as? LiteralExpression else { return false }
		return value == o.value
	}
}

public class SetExpression: Expression {
	public let ranges: [(Int, Int)]
	public let inverted: Bool
	public init(start: Int, ranges: [(Int, Int)], inverted: Bool) {
		self.ranges = ranges; self.inverted = inverted; super.init(start: start)
	}

	override public var description: String {
		let rangeStr = ranges.map { a, b in
			String(UnicodeScalar(a)!) + (b == a + 1 ? "" : "-" + String(UnicodeScalar(b - 1)!))
		}.joined()
		return "[\(inverted ? "^" : "")\(rangeStr)]"
	}

	override public func eq(_ other: Expression) -> Bool {
		guard let o = other as? SetExpression else { return false }
		return inverted == o.inverted && ranges.count == o.ranges.count &&
			ranges.enumerated().allSatisfy { i, ab in ab.0 == o.ranges[i].0 && ab.1 == o.ranges[i].1 }
	}
}

public class AnyExpression: Expression {
	override public var description: String {
		"_"
	}

	override public func eq(_: Expression) -> Bool {
		true
	}
}

public func walkExprs(_ exprs: [Expression], _ f: (Expression) -> Expression) -> [Expression] {
	var result: [Expression]? = nil
	for i in 0 ..< exprs.count {
		let expr = exprs[i].walk(f)
		if !exprRefsEqual(expr, exprs[i]), result == nil {
			result = Array(exprs[0 ..< i])
		}
		if result != nil { result!.append(expr) }
	}
	return result ?? exprs
}

public func sameExprs(_ a: [Expression], _ b: [Expression]) -> Bool {
	guard a.count == b.count else { return false }
	for i in 0 ..< a.count {
		if a[i] !== b[i] { return false }
	}
	return true
}

public let charClasses: [String: [(Int, Int)]] = [
	"asciiLetter": [(65, 91), (97, 123)],
	"asciiLowercase": [(97, 123)],
	"asciiUppercase": [(65, 91)],
	"digit": [(48, 58)],
	"whitespace": [(9, 14), (32, 33), (133, 134), (160, 161), (5760, 5761), (8192, 8203), (8232, 8234), (8239, 8240), (8287, 8288), (12288, 12289)],
	"eof": [(0xFFFF, 0xFFFF)],
]

public class CharClass: Expression {
	public let type: String
	public init(start: Int, type: String) {
		self.type = type; super.init(start: start)
	}

	override public var description: String {
		"@" + type
	}

	override public func eq(_ other: Expression) -> Bool {
		guard let o = other as? CharClass else { return false }
		return type == o.type
	}
}

public func exprEq(_ a: Expression, _ b: Expression) -> Bool {
	return type(of: a) == type(of: b) && a.eq(b)
}

public func exprsEq(_ a: [Expression], _ b: [Expression]) -> Bool {
	return a.count == b.count && a.enumerated().allSatisfy { i, e in exprEq(e, b[i]) }
}

private func exprRefsEqual(_ a: Expression, _ b: Expression) -> Bool {
	return ObjectIdentifier(a) == ObjectIdentifier(b)
}

public class Prop: Node {
	public let at: Bool
	public let name: String
	public let value: [PropPart]

	public init(start: Int, at: Bool, name: String, value: [PropPart]) {
		self.at = at; self.name = name; self.value = value; super.init(start: start)
	}

	public func eq(_ other: Prop) -> Bool {
		name == other.name && value.count == other.value.count &&
			value.enumerated().allSatisfy { i, v in v.value == other.value[i].value && v.name == other.value[i].name }
	}

	override public var description: String {
		var result = (at ? "@" : "") + name
		if !value.isEmpty {
			result += "="
			for p in value {
				if let n = p.name { result += "{\(n)}" }
				else if let v = p.value, v.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "-"))) != nil {
					result += "\"\(v)\""
				} else {
					result += (p.value ?? "")
				}
			}
		}
		return result
	}

	public static func eqProps(_ a: [Prop], _ b: [Prop]) -> Bool {
		a.count == b.count && a.enumerated().allSatisfy { i, p in p.eq(b[i]) }
	}
}

public class PropPart: Node {
	public let value: String?
	public let name: String?
	public init(start: Int, value: String?, name: String?) {
		self.value = value; self.name = name; super.init(start: start)
	}
}

func maybeParens(_ node: Expression, parent: Expression) -> String {
	node.prec < parent.prec ? "(\(node))" : node.description
}
