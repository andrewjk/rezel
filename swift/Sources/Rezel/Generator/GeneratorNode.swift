import Foundation

public class Node: CustomStringConvertible {
    public let start: Int
    public init(start: Int) { self.start = start }
    public var description: String { "" }
}

public class GrammarDeclaration: Node {
    public let rules: [RuleDeclaration]
    public let topRules: [RuleDeclaration]
    public let tokens: TokenDeclaration?
    public let localTokens: [LocalTokenDeclaration]
    public let context: ContextDeclaration?
    public let externalTokens: [ExternalTokenDeclaration]
    public let externalSpecializers: [ExternalSpecializeDeclaration]
    public let externalPropSources: [ExternalPropSourceDeclaration]
    public let precedences: PrecDeclaration?
    public let mainSkip: Expression?
    public let scopedSkip: [(expr: Expression, topRules: [RuleDeclaration], rules: [RuleDeclaration])]
    public let dialects: [Identifier]
    public let externalProps: [ExternalPropDeclaration]
    public let autoDelim: Bool

    public init(start: Int, rules: [RuleDeclaration], topRules: [RuleDeclaration],
                tokens: TokenDeclaration?, localTokens: [LocalTokenDeclaration],
                context: ContextDeclaration?, externalTokens: [ExternalTokenDeclaration],
                externalSpecializers: [ExternalSpecializeDeclaration],
                externalPropSources: [ExternalPropSourceDeclaration],
                precedences: PrecDeclaration?, mainSkip: Expression?,
                scopedSkip: [(expr: Expression, topRules: [RuleDeclaration], rules: [RuleDeclaration])],
                dialects: [Identifier], externalProps: [ExternalPropDeclaration], autoDelim: Bool) {
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

    public override var description: String { rules.map { "\($0)" }.joined(separator: "\n") }
}

public class RuleDeclaration: Node {
    public let id: Identifier
    public let props: [Prop]
    public let params: [Identifier]
    public let expr: Expression

    public init(start: Int, id: Identifier, props: [Prop], params: [Identifier], expr: Expression) {
        self.id = id; self.props = props; self.params = params; self.expr = expr
        super.init(start: start)
    }

    public override var description: String {
        id.name + (params.isEmpty ? "" : "<\(params.map { "\($0)" }.joined(separator: ","))>") + " -> " + expr.description
    }
}

public class PrecDeclaration: Node {
    public let items: [(id: Identifier, type: PrecType?)]
    public init(start: Int, items: [(id: Identifier, type: PrecType?)]) {
        self.items = items; super.init(start: start)
    }
}

public enum PrecType: String {
    case left, right, cut
}

public class TokenPrecDeclaration: Node {
    public let items: [Expression]
    public init(start: Int, items: [Expression]) { self.items = items; super.init(start: start) }
}

public class TokenConflictDeclaration: Node {
    public let a: Expression
    public let b: Expression
    public init(start: Int, a: Expression, b: Expression) { self.a = a; self.b = b; super.init(start: start) }
}

public class TokenDeclaration: Node {
    public let precedences: [TokenPrecDeclaration]
    public let conflicts: [TokenConflictDeclaration]
    public let rules: [RuleDeclaration]
    public let literals: [LiteralDeclaration]

    public init(start: Int, precedences: [TokenPrecDeclaration], conflicts: [TokenConflictDeclaration],
                rules: [RuleDeclaration], literals: [LiteralDeclaration]) {
        self.precedences = precedences; self.conflicts = conflicts
        self.rules = rules; self.literals = literals
        super.init(start: start)
    }
}

public class LocalTokenDeclaration: Node {
    public let precedences: [TokenPrecDeclaration]
    public let rules: [RuleDeclaration]
    public let fallback: (id: Identifier, props: [Prop])?

    public init(start: Int, precedences: [TokenPrecDeclaration], rules: [RuleDeclaration],
                fallback: (id: Identifier, props: [Prop])?) {
        self.precedences = precedences; self.rules = rules; self.fallback = fallback
        super.init(start: start)
    }
}

public class LiteralDeclaration: Node {
    public let literal: String
    public let props: [Prop]
    public init(start: Int, literal: String, props: [Prop]) {
        self.literal = literal; self.props = props; super.init(start: start)
    }
}

public class ContextDeclaration: Node {
    public let id: Identifier
    public let source: String
    public init(start: Int, id: Identifier, source: String) {
        self.id = id; self.source = source; super.init(start: start)
    }
}

public class ExternalTokenDeclaration: Node {
    public let id: Identifier
    public let source: String
    public let tokens: [(id: Identifier, props: [Prop])]
    public let conflicts: [Identifier]

    public init(start: Int, id: Identifier, source: String, tokens: [(id: Identifier, props: [Prop])], conflicts: [Identifier]) {
        self.id = id; self.source = source; self.tokens = tokens; self.conflicts = conflicts
        super.init(start: start)
    }
}

public class ExternalSpecializeDeclaration: Node {
    public let type: String
    public let token: Expression
    public let id: Identifier
    public let source: String
    public let tokens: [(id: Identifier, props: [Prop])]

    public init(start: Int, type: String, token: Expression, id: Identifier, source: String, tokens: [(id: Identifier, props: [Prop])]) {
        self.type = type; self.token = token; self.id = id; self.source = source; self.tokens = tokens
        super.init(start: start)
    }
}

public class ExternalPropSourceDeclaration: Node {
    public let id: Identifier
    public let source: String
    public init(start: Int, id: Identifier, source: String) {
        self.id = id; self.source = source; super.init(start: start)
    }
}

public class ExternalPropDeclaration: Node {
    public let id: Identifier
    public let externalID: Identifier
    public let source: String
    public init(start: Int, id: Identifier, externalID: Identifier, source: String) {
        self.id = id; self.externalID = externalID; self.source = source; super.init(start: start)
    }
}

public class Identifier: Node {
    public let name: String
    public init(start: Int, name: String) { self.name = name; super.init(start: start) }
    public override var description: String { name }
}

public class Expression: Node {
    public var prec: Int { get { 10 } set { } }

    public func walk(_ f: (Expression) -> Expression) -> Expression { f(self) }
    public func eq(_ other: Expression) -> Bool { false }
}
