//
//  Node.swift
//  Rezel
//
//  Created on 2025-06-11.
//

import Foundation

/// Base class for AST nodes
public class Node {
    let start: Int
    
    init(start: Int) {
        self.start = start
    }
}

/// Grammar declaration node
public class GrammarDeclaration: Node {
    let rules: [RuleDeclaration]
    let topRules: [RuleDeclaration]
    let tokens: TokenDeclaration?
    let localTokens: [LocalTokenDeclaration]
    let context: ContextDeclaration?
    let externalTokens: [ExternalTokenDeclaration]
    let externalSpecializers: [ExternalSpecializeDeclaration]
    let externalPropSources: [ExternalPropSourceDeclaration]
    let precedences: PrecDeclaration?
    let mainSkip: Expression?
    let scopedSkip: [(expr: Expression, topRules: [RuleDeclaration], rules: [RuleDeclaration])]
    let dialects: [Identifier]
    let externalProps: [ExternalPropDeclaration]
    let autoDelim: Bool
    
    init(
        start: Int,
        rules: [RuleDeclaration],
        topRules: [RuleDeclaration],
        tokens: TokenDeclaration?,
        localTokens: [LocalTokenDeclaration],
        context: ContextDeclaration?,
        externalTokens: [ExternalTokenDeclaration],
        externalSpecializers: [ExternalSpecializeDeclaration],
        externalPropSources: [ExternalPropSourceDeclaration],
        precedences: PrecDeclaration?,
        mainSkip: Expression?,
        scopedSkip: [(expr: Expression, topRules: [RuleDeclaration], rules: [RuleDeclaration])],
        dialects: [Identifier],
        externalProps: [ExternalPropDeclaration],
        autoDelim: Bool
    ) {
        self.rules = rules
        self.topRules = topRules
        self.tokens = tokens
        self.localTokens = localTokens
        self.context = context
        self.externalTokens = externalTokens
        self.externalSpecializers = externalSpecializers
        self.externalPropSources = externalPropSources
        self.precedences = precedences
        self.mainSkip = mainSkip
        self.scopedSkip = scopedSkip
        self.dialects = dialects
        self.externalProps = externalProps
        self.autoDelim = autoDelim
        super.init(start: start)
    }
    
    public func toString() -> String {
        return rules.map { $0.toString() }.joined(separator: "\n")
    }
}

/// Rule declaration node
public class RuleDeclaration: Node {
    let id: Identifier
    let props: [Prop]
    let params: [Identifier]
    let expr: Expression
    
    init(start: Int, id: Identifier, props: [Prop], params: [Identifier], expr: Expression) {
        self.id = id
        self.props = props
        self.params = params
        self.expr = expr
        super.init(start: start)
    }
    
    public func toString() -> String {
        let paramsStr = params.isEmpty ? "" : "<\(params.map { $0.name }.joined(separator: ","))>"
        return "\(id.name)\(paramsStr) -> \(expr)"
    }
}

/// Precedence declaration node
public class PrecDeclaration: Node {
    let items: [(id: Identifier, type: String?)]
    
    init(start: Int, items: [(id: Identifier, type: String?)]) {
        self.items = items
        super.init(start: start)
    }
}

/// Token precedence declaration node
public class TokenPrecDeclaration: Node {
    let items: [Expression]
    
    init(start: Int, items: [Expression]) {
        self.items = items
        super.init(start: start)
    }
}

/// Token conflict declaration node
public class TokenConflictDeclaration: Node {
    let a: Expression
    let b: Expression
    
    init(start: Int, a: Expression, b: Expression) {
        self.a = a
        self.b = b
        super.init(start: start)
    }
}

/// Token declaration node
public class TokenDeclaration: Node {
    let precedences: [TokenPrecDeclaration]
    let conflicts: [TokenConflictDeclaration]
    let rules: [RuleDeclaration]
    let literals: [LiteralDeclaration]
    
    init(
        start: Int,
        precedences: [TokenPrecDeclaration],
        conflicts: [TokenConflictDeclaration],
        rules: [RuleDeclaration],
        literals: [LiteralDeclaration]
    ) {
        self.precedences = precedences
        self.conflicts = conflicts
        self.rules = rules
        self.literals = literals
        super.init(start: start)
    }
}

/// Local token declaration node
public class LocalTokenDeclaration: Node {
    let precedences: [TokenPrecDeclaration]
    let rules: [RuleDeclaration]
    let fallback: (id: Identifier, props: [Prop])?
    
    init(
        start: Int,
        precedences: [TokenPrecDeclaration],
        rules: [RuleDeclaration],
        fallback: (id: Identifier, props: [Prop])?
    ) {
        self.precedences = precedences
        self.rules = rules
        self.fallback = fallback
        super.init(start: start)
    }
}

/// Literal declaration node
public class LiteralDeclaration: Node {
    let literal: String
    let props: [Prop]
    
    init(start: Int, literal: String, props: [Prop]) {
        self.literal = literal
        self.props = props
        super.init(start: start)
    }
}

/// Context declaration node
public class ContextDeclaration: Node {
    let id: Identifier
    let source: String
    
    init(start: Int, id: Identifier, source: String) {
        self.id = id
        self.source = source
        super.init(start: start)
    }
}

/// External token declaration node
public class ExternalTokenDeclaration: Node {
    let id: Identifier
    let source: String
    let tokens: [(id: Identifier, props: [Prop])]
    let conflicts: [Identifier]
    
    init(
        start: Int,
        id: Identifier,
        source: String,
        tokens: [(id: Identifier, props: [Prop])],
        conflicts: [Identifier]
    ) {
        self.id = id
        self.source = source
        self.tokens = tokens
        self.conflicts = conflicts
        super.init(start: start)
    }
}

/// External specialize declaration node
public class ExternalSpecializeDeclaration: Node {
    let type: String
    let token: Expression
    let id: Identifier
    let source: String
    let tokens: [(id: Identifier, props: [Prop])]
    
    init(
        start: Int,
        type: String,
        token: Expression,
        id: Identifier,
        source: String,
        tokens: [(id: Identifier, props: [Prop])]
    ) {
        self.type = type
        self.token = token
        self.id = id
        self.source = source
        self.tokens = tokens
        super.init(start: start)
    }
}

/// External property source declaration node
public class ExternalPropSourceDeclaration: Node {
    let id: Identifier
    let source: String
    
    init(start: Int, id: Identifier, source: String) {
        self.id = id
        self.source = source
        super.init(start: start)
    }
}

/// External property declaration node
public class ExternalPropDeclaration: Node {
    let id: Identifier
    let externalID: Identifier
    let source: String
    
    init(start: Int, id: Identifier, externalID: Identifier, source: String) {
        self.id = id
        self.externalID = externalID
        self.source = source
        super.init(start: start)
    }
}

/// Identifier node
public class Identifier: Node {
    let name: String
    
    init(start: Int, name: String) {
        self.name = name
        super.init(start: start)
    }
    
    public func toString() -> String {
        return name
    }
}

/// Expression base class
public class Expression: Node, Equatable {
    public static func == (lhs: Expression, rhs: Expression) -> Bool {
        return type(of: lhs) == type(of: rhs) && lhs.eq(rhs)
    }
    
    public func walk(_ f: (Expression) -> Expression) -> Expression {
        return f(self)
    }
    
    public func eq(_ other: Expression) -> Bool {
        return false
    }
    
    public func toString() -> String {
        return ""
    }
    
    var prec: Int = 10
}

/// Name expression node
public class NameExpression: Expression {
    let id: Identifier
    let args: [Expression]
    
    init(start: Int, id: Identifier, args: [Expression]) {
        self.id = id
        self.args = args
        super.init(start: start)
        self.prec = 10
    }
    
    public override func toString() -> String {
        let argsStr = args.isEmpty ? "" : "<\(args.map { $0.toString() }.joined(separator: ","))>"
        return "\(id.name)\(argsStr)"
    }
    
    public override func eq(_ other: Expression) -> Bool {
        guard let other = other as? NameExpression else { return false }
        return id.name == other.id.name && exprsEq(args, other.args)
    }
    
    public override func walk(_ f: (Expression) -> Expression) -> Expression {
        let newArgs = walkExprs(args, f)
        return f(newArgs == args ? self : NameExpression(start: start, id: id, args: newArgs))
    }
}

/// Specialize expression node
public class SpecializeExpression: Expression {
    let type: String
    let props: [Prop]
    let token: Expression
    let content: Expression
    
    init(start: Int, type: String, props: [Prop], token: Expression, content: Expression) {
        self.type = type
        self.props = props
        self.token = token
        self.content = content
        super.init(start: start)
    }
    
    public override func toString() -> String {
        let propsStr = props.map { $0.toString() }.joined(separator: ",")
        return "@\(type)[\(propsStr)]<\(token), \(content)>"
    }
    
    public override func eq(_ other: Expression) -> Bool {
        guard let other = other as? SpecializeExpression else { return false }
        return type == other.type &&
               Prop.eqProps(props, other.props) &&
               exprEq(token, other.token) &&
               exprEq(content, other.content)
    }
    
    public override func walk(_ f: (Expression) -> Expression) -> Expression {
        let newToken = token.walk(f)
        let newContent = content.walk(f)
        return f(
            (newToken === token && newContent === content) ? self :
            SpecializeExpression(start: start, type: type, props: props, token: newToken, content: newContent)
        )
    }
}

/// Inline rule expression node
public class InlineRuleExpression: Expression {
    let rule: RuleDeclaration
    
    init(start: Int, rule: RuleDeclaration) {
        self.rule = rule
        super.init(start: start)
    }
    
    public override func toString() -> String {
        let propsStr = rule.props.isEmpty ? "" : "[\(rule.props.map { $0.toString() }.joined(separator: ","))]"
        return "\(rule.id)\(propsStr) { \(rule.expr) }"
    }
    
    public override func eq(_ other: Expression) -> Bool {
        guard let other = other as? InlineRuleExpression else { return false }
        return exprEq(rule.expr, other.rule.expr) &&
               rule.id.name == other.rule.id.name &&
               Prop.eqProps(rule.props, other.rule.props)
    }
    
    public override func walk(_ f: (Expression) -> Expression) -> Expression {
        let newExpr = rule.expr.walk(f)
        return f(
            (newExpr === rule.expr) ? self :
            InlineRuleExpression(
                start: start,
                rule: RuleDeclaration(
                    start: rule.start,
                    id: rule.id,
                    props: rule.props,
                    params: rule.params,
                    expr: newExpr
                )
            )
        )
    }
}

/// Choice expression node
public class ChoiceExpression: Expression {
    let exprs: [Expression]
    
    init(start: Int, exprs: [Expression]) {
        self.exprs = exprs
        super.init(start: start)
        self.prec = 1
    }
    
    public override func toString() -> String {
        return exprs.map { maybeParens($0, self) }.joined(separator: " | ")
    }
    
    public override func eq(_ other: Expression) -> Bool {
        guard let other = other as? ChoiceExpression else { return false }
        return exprsEq(exprs, other.exprs)
    }
    
    public override func walk(_ f: (Expression) -> Expression) -> Expression {
        let newExprs = walkExprs(exprs, f)
        return f(newExprs == exprs ? self : ChoiceExpression(start: start, exprs: newExprs))
    }
}

/// Sequence expression node
public class SequenceExpression: Expression {
    let exprs: [Expression]
    let markers: [[ConflictMarker]]
    let empty: Bool
    
    init(start: Int, exprs: [Expression], markers: [[ConflictMarker]], empty: Bool = false) {
        self.exprs = exprs
        self.markers = markers
        self.empty = empty
        super.init(start: start)
        self.prec = 2
    }
    
    public override func toString() -> String {
        if empty {
            return "()"
        }
        return exprs.map { maybeParens($0, self) }.joined(separator: " ")
    }
    
    public override func eq(_ other: Expression) -> Bool {
        guard let other = other as? SequenceExpression else { return false }
        guard exprsEq(exprs, other.exprs) else { return false }
        
        guard markers.count == other.markers.count else { return false }
        for i in 0..<markers.count {
            let m = markers[i]
            let om = other.markers[i]
            guard m.count == om.count else { return false }
            for j in 0..<m.count {
                guard m[j].eq(om[j]) else { return false }
            }
        }
        
        return true
    }
    
    public override func walk(_ f: (Expression) -> Expression) -> Expression {
        let newExprs = walkExprs(exprs, f)
        return f(
            (newExprs == exprs) ? self :
            SequenceExpression(start: start, exprs: newExprs, markers: markers, empty: empty && newExprs.isEmpty)
        )
    }
}

/// Conflict marker node
public class ConflictMarker: Node {
    let id: Identifier
    let type: String
    
    init(start: Int, id: Identifier, type: String) {
        self.id = id
        self.type = type
        super.init(start: start)
    }
    
    public func toString() -> String {
        return (type == "ambig" ? "~" : "!") + id.name
    }
    
    func eq(_ other: ConflictMarker) -> Bool {
        return id.name == other.id.name && type == other.type
    }
}

/// Repeat expression node
public class RepeatExpression: Expression {
    let expr: Expression
    let kind: String
    
    init(start: Int, expr: Expression, kind: String) {
        self.expr = expr
        self.kind = kind
        super.init(start: start)
        self.prec = 3
    }
    
    public override func toString() -> String {
        return maybeParens(expr, self) + kind
    }
    
    public override func eq(_ other: Expression) -> Bool {
        guard let other = other as? RepeatExpression else { return false }
        return exprEq(expr, other.expr) && kind == other.kind
    }
    
    public override func walk(_ f: (Expression) -> Expression) -> Expression {
        let newExpr = expr.walk(f)
        return f((newExpr === expr) ? self : RepeatExpression(start: start, expr: newExpr, kind: kind))
    }
}

/// Literal expression node
public class LiteralExpression: Expression {
    let value: String
    
    init(start: Int, value: String) {
        self.value = value
        super.init(start: start)
    }
    
    public override func toString() -> String {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
    
    public override func eq(_ other: Expression) -> Bool {
        guard let other = other as? LiteralExpression else { return false }
        return value == other.value
    }
}

/// Set expression node
public class SetExpression: Expression {
    let ranges: [(Int, Int)]
    let inverted: Bool
    
    init(start: Int, ranges: [(Int, Int)], inverted: Bool) {
        self.ranges = ranges
        self.inverted = inverted
        super.init(start: start)
    }
    
    public override func toString() -> String {
        let rangesStr = ranges.map { (a, b) in
            let startChar = String(UnicodeScalar(a)!)
            if b == a + 1 {
                return startChar
            } else {
                return "\(startChar)-\(String(UnicodeScalar(b)!))"
            }
        }.joined()
        return "[\(inverted ? "^" : "")\(rangesStr)]"
    }
    
    public override func eq(_ other: Expression) -> Bool {
        guard let other = other as? SetExpression else { return false }
        guard inverted == other.inverted else { return false }
        guard ranges.count == other.ranges.count else { return false }
        
        for i in 0..<ranges.count {
            let (a, b) = ranges[i]
            let (x, y) = other.ranges[i]
            if a != x || b != y {
                return false
            }
        }
        
        return true
    }
}

/// Any expression node
public class AnyExpression: Expression {
    public override init(start: Int) {
        super.init(start: start)
    }
    
    public override func toString() -> String {
        return "_"
    }
    
    public override func eq(_ other: Expression) -> Bool {
        return other is AnyExpression
    }
}

/// Character class expression node
public class CharClass: Expression {
    let type: String
    
    init(start: Int, type: String) {
        self.type = type
        super.init(start: start)
    }
    
    public override func toString() -> String {
        return "@" + type
    }
    
    public override func eq(_ other: Expression) -> Bool {
        guard let other = other as? CharClass else { return false }
        return type == other.type
    }
}

/// Property node
public class Prop: Node {
    let at: Bool
    let name: String
    let value: [PropPart]
    
    init(start: Int, at: Bool, name: String, value: [PropPart]) {
        self.at = at
        self.name = name
        self.value = value
        super.init(start: start)
    }
    
    func eq(_ other: Prop) -> Bool {
        guard name == other.name else { return false }
        guard value.count == other.value.count else { return false }
        
        for i in 0..<value.count {
            let v = value[i]
            let ov = other.value[i]
            guard v.value == ov.value && v.name == ov.name else { return false }
        }
        
        return true
    }
    
    public func toString() -> String {
        var result = (at ? "@" : "") + name
        if !value.isEmpty {
            result += "="
            for part in value {
                if let name = part.name {
                    result += "{\(name)}"
                } else if let value = part.value {
                    if !value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
                        result += "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
                    } else {
                        result += value
                    }
                }
            }
        }
        return result
    }
    
    static func eqProps(_ a: [Prop], _ b: [Prop]) -> Bool {
        guard a.count == b.count else { return false }
        for i in 0..<a.count {
            guard a[i].eq(b[i]) else { return false }
        }
        return true
    }
}

/// Property part node
public class PropPart: Node {
    let value: String?
    let name: String?
    
    init(start: Int, value: String?, name: String?) {
        self.value = value
        self.name = name
        super.init(start: start)
    }
}

// Character classes
public let CharClasses: [String: [(Int, Int)]] = [
    "asciiLetter": [(65, 91), (97, 123)],
    "asciiLowercase": [(97, 123)],
    "asciiUppercase": [(65, 91)],
    "digit": [(48, 58)],
    "whitespace": [
        (9, 14), (32, 33), (133, 134), (160, 161),
        (5760, 5761), (8192, 8203), (8232, 8234),
        (8239, 8240), (8287, 8288), (12288, 12289)
    ],
    "eof": [(0xffff, 0xffff)]
]

/// Compare two expressions for equality
public func exprEq(_ a: Expression, _ b: Expression) -> Bool {
    return type(of: a) == type(of: b) && a.eq(b)
}

/// Compare two arrays of expressions for equality
public func exprsEq(_ a: [Expression], _ b: [Expression]) -> Bool {
    guard a.count == b.count else { return false }
    for i in 0..<a.count {
        guard exprEq(a[i], b[i]) else { return false }
    }
    return true
}

// Helper functions

fileprivate func walkExprs(_ exprs: [Expression], _ f: (Expression) -> Expression) -> [Expression] {
    var result: [Expression]?
    for i in 0..<exprs.count {
        let expr = exprs[i].walk(f)
        if expr !== exprs[i] && result == nil {
            result = Array(exprs[0..<i])
        }
        result?.append(expr)
    }
    return result ?? exprs
}

fileprivate func maybeParens(_ node: Expression, _ parent: Expression) -> String {
    return node.prec < parent.prec ? "(\(node.toString()))" : node.toString()
}