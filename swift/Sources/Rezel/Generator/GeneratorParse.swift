import Foundation

public class GenInput {
    public var type: String = "sof"
    public var value: Any? = nil
    public var start: Int = 0
    public var end: Int = 0
    public let string: String
    public let fileName: String?
    private var stringIndex: String.Index

    public init(_ string: String, fileName: String? = nil) {
        self.string = string; self.fileName = fileName
        self.stringIndex = string.startIndex
        next()
    }

    private var pos: Int { string.distance(from: string.startIndex, to: stringIndex) }

    public func lineInfo(_ pos: Int) -> (line: Int, ch: Int) {
        var line = 1, cur = string.startIndex
        while true {
            guard let nlRange = string.range(of: "\n", range: cur..<string.endIndex) else {
                return (line, pos - string.distance(from: string.startIndex, to: cur))
            }
            let nlPos = string.distance(from: string.startIndex, to: nlRange.lowerBound)
            if nlPos >= pos { return (line, pos - string.distance(from: string.startIndex, to: cur)) }
            line += 1; cur = nlRange.upperBound
        }
    }

    public func message(_ msg: String, _ pos: Int = -1) -> String {
        var posInfo = fileName ?? ""
        if pos > -1 {
            let info = lineInfo(pos)
            posInfo += posInfo.isEmpty ? "" : " "
            posInfo += "\(info.line):\(info.ch)"
        }
        return posInfo.isEmpty ? msg : "\(msg) (\(posInfo))"
    }

    public func raise(_ msg: String, _ pos: Int = -1) -> Never {
        fatalError(message(msg, pos))
    }

    public func next() {
        let s = string
        while stringIndex < s.endIndex {
            let ch = s[stringIndex]
            if ch == " " || ch == "\n" || ch == "\t" || ch == "\r" { stringIndex = s.index(after: stringIndex); continue }
            if ch == "/" && s.index(after: stringIndex) < s.endIndex {
                let nextCh = s[s.index(after: stringIndex)]
                if nextCh == "/" {
                    stringIndex = s.index(after: stringIndex)
                    if let nl = s[stringIndex...].firstIndex(of: "\n") { stringIndex = s.index(after: nl) } else { stringIndex = s.endIndex }
                    continue
                } else if nextCh == "*" {
                    stringIndex = s.index(after: s.index(after: stringIndex))
                    if let endRange = s[stringIndex...].range(of: "*/") { stringIndex = endRange.upperBound } else { stringIndex = s.endIndex }
                    continue
                }
            }
            break
        }

        let startOffset = string.distance(from: s.startIndex, to: stringIndex)
        if stringIndex >= s.endIndex { start = startOffset; end = startOffset; type = "eof"; return }
        let ch = s[stringIndex]
        let startPos = stringIndex

        if ch == "\"" {
            var i = s.index(after: stringIndex)
            while i < s.endIndex {
                let c = s[i]
                if c == "\\" { i = s.index(after: i); if i < s.endIndex { i = s.index(after: i) } }
                else if c == "\"" { i = s.index(after: i); break }
                else { i = s.index(after: i) }
            }
            let content = String(s[s.index(after: startPos)..<s.index(before: i)])
            start = startOffset; end = string.distance(from: s.startIndex, to: i); stringIndex = i
            type = "string"; value = readString(content); return
        } else if ch == "'" {
            var i = s.index(after: stringIndex)
            while i < s.endIndex {
                let c = s[i]
                if c == "\\" { i = s.index(after: i); if i < s.endIndex { i = s.index(after: i) } }
                else if c == "'" { i = s.index(after: i); break }
                else { i = s.index(after: i) }
            }
            let content = String(s[s.index(after: startPos)..<s.index(before: i)])
            start = startOffset; end = string.distance(from: s.startIndex, to: i); stringIndex = i
            type = "string"; value = readString(content); return
        } else if ch == "@" {
            let afterAt = s.index(after: stringIndex)
            let (word, wordEndIdx) = readWord(from: afterAt)
            guard let w = word else { start = startOffset; raise("@ without a name", startOffset) }
            start = startOffset; end = string.distance(from: s.startIndex, to: wordEndIdx); stringIndex = wordEndIdx
            type = "at"; value = w; return
        } else if (ch == "$" || ch == "!") && s.index(after: stringIndex) < s.endIndex && s[s.index(after: stringIndex)] == "[" {
            var i = s.index(after: s.index(after: stringIndex))
            while i < s.endIndex {
                let c = s[i]
                if c == "\\" { i = s.index(after: i); if i < s.endIndex { i = s.index(after: i) } }
                else if c == "]" { i = s.index(after: i); break }
                else { i = s.index(after: i) }
            }
            let contentStart = s.index(after: s.index(after: startPos))
            let contentEnd = s.index(before: i)
            let content = String(s[contentStart..<contentEnd])
            start = startOffset; end = string.distance(from: s.startIndex, to: i); stringIndex = i
            type = "set"; value = content; return
        } else if "[]()!~+*?{}<>.,|:$=".contains(ch) {
            let nextIdx = s.index(after: stringIndex)
            start = startOffset; end = startOffset + 1; stringIndex = nextIdx
            type = String(ch); value = nil; return
        } else {
            let (word, wordEndIdx) = readWord(from: stringIndex)
            guard let w = word else { start = startOffset; raise("Unexpected character \(ch)", startOffset) }
            start = startOffset; end = string.distance(from: s.startIndex, to: wordEndIdx); stringIndex = wordEndIdx
            type = "id"; value = w; return
        }
    }

    private func readWord(from idx: String.Index) -> (String?, String.Index) {
        var i = idx
        while i < string.endIndex {
            let ch = string[i]
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "-" { i = string.index(after: i) }
            else { break }
        }
        if i == idx { return (nil, idx) }
        return (String(string[idx..<i]), i)
    }

    @discardableResult
    public func eat(_ type: String, _ value: Any? = nil) -> Bool {
        if self.type == type && (value == nil || self.value as? String == value as? String) {
            next(); return true
        }
        return false
    }

    public func unexpected() -> Never { raise("Unexpected token '\(string[string.index(string.startIndex, offsetBy: start)..<string.index(string.startIndex, offsetBy: end)])'", start) }

    @discardableResult
    public func expect(_ type: String, _ value: Any? = nil) -> Any? {
        let val = self.value
        if self.type != type || !(value == nil || val as? String == value as? String) { unexpected() }
        next()
        return val
    }

    public func parse() throws -> GrammarDeclaration { try parseGrammar(self) }
}

private func parseGrammar(_ input: GenInput) throws -> GrammarDeclaration {
    let start = input.start
    var rules: [RuleDeclaration] = []
    var prec: PrecDeclaration? = nil
    var tokens: TokenDeclaration? = nil
    var localTokens: [LocalTokenDeclaration] = []
    var mainSkip: Expression? = nil
    var scopedSkip: [(expr: Expression, topRules: [RuleDeclaration], rules: [RuleDeclaration])] = []
    var dialects: [Identifier] = []
    var context: ContextDeclaration? = nil
    var external: [ExternalTokenDeclaration] = []
    var specialized: [ExternalSpecializeDeclaration] = []
    var genProps: [ExternalPropDeclaration] = []
    var propSources: [ExternalPropSourceDeclaration] = []
    var tops: [RuleDeclaration] = []
    var sawTop = false
    var autoDelim = false

    while input.type != "eof" {
        let declStart = input.start
        if input.eat("at", "top") {
            if input.type != "id" { input.raise("Top rules must have a name", input.start) }
            tops.append(try parseRule(input, named: parseIdent(input)))
            sawTop = true
        } else if input.type == "at" && input.value as? String == "tokens" {
            if tokens != nil { input.raise("Multiple @tokens declarations", input.start) }
            else { tokens = parseTokens(input) }
        } else if input.eat("at", "local") {
            input.expect("id", "tokens")
            localTokens.append(parseLocalTokens(input, declStart))
        } else if input.eat("at", "context") {
            if context != nil { input.raise("Multiple @context declarations", declStart) }
            let id = parseIdent(input)
            input.expect("id", "from")
            let source = input.expect("string") as! String
            context = ContextDeclaration(start: declStart, id: id, source: source)
        } else if input.eat("at", "external") {
            if input.eat("id", "tokens") { external.append(parseExternalTokens(input, declStart)) }
            else if input.eat("id", "prop") { genProps.append(parseExternalProp(input, declStart)) }
            else if input.eat("id", "extend") { specialized.append(parseExternalSpecialize(input, "extend", declStart)) }
            else if input.eat("id", "specialize") { specialized.append(parseExternalSpecialize(input, "specialize", declStart)) }
            else if input.eat("id", "propSource") { propSources.append(parseExternalPropSource(input, declStart)) }
            else { input.unexpected() }
        } else if input.eat("at", "dialects") {
            input.expect("{")
            var first = true
            while !input.eat("}") {
                if !first { input.eat(",") }
                dialects.append(parseIdent(input))
                first = false
            }
        } else if input.type == "at" && input.value as? String == "precedence" {
            if prec != nil { input.raise("Multiple precedence declarations", input.start) }
            prec = parsePrecedence(input)
        } else if input.eat("at", "detectDelim") {
            autoDelim = true
        } else if input.eat("at", "skip") {
            let skip = parseBracedExpr(input)
            if input.type == "{" {
                input.next()
                var skipRules: [RuleDeclaration] = [], skipTopRules: [RuleDeclaration] = []
                while !input.eat("}") {
                    if input.eat("at", "top") {
                        skipTopRules.append(try parseRule(input, named: parseIdent(input)))
                        sawTop = true
                    } else {
                        skipRules.append(try parseRule(input))
                    }
                }
                scopedSkip.append((expr: skip, topRules: skipTopRules, rules: skipRules))
            } else {
                if mainSkip != nil { input.raise("Multiple top-level skip declarations", input.start) }
                mainSkip = skip
            }
        } else {
            rules.append(try parseRule(input))
        }
    }
    if !sawTop { input.raise("Missing @top declaration") }
    return GrammarDeclaration(start: start, rules: rules, topRules: tops, tokens: tokens,
        localTokens: localTokens, context: context, externalTokens: external,
        externalSpecializers: specialized, externalPropSources: propSources,
        precedences: prec, mainSkip: mainSkip, scopedSkip: scopedSkip,
        dialects: dialects, externalProps: genProps, autoDelim: autoDelim)
}

private func parseRule(_ input: GenInput, named: Identifier? = nil) throws -> RuleDeclaration {
    let start = named?.start ?? input.start
    let id = named ?? parseIdent(input)
    let props = parseProps(input)
    var params: [Identifier] = []
    if input.eat("<") {
        while !input.eat(">") {
            if !params.isEmpty { input.expect(",") }
            params.append(parseIdent(input))
        }
    }
    let expr = parseBracedExpr(input)
    return RuleDeclaration(start: start, id: id, props: props, params: params, expr: expr)
}

private func parseProps(_ input: GenInput) -> [Prop] {
    if input.type != "[" { return [] }
    var props: [Prop] = []
    input.expect("[")
    while !input.eat("]") {
        if !props.isEmpty { input.expect(",") }
        props.append(parseProp(input))
    }
    return props
}

private func parseProp(_ input: GenInput) -> Prop {
    let propStart = input.start
    var value: [PropPart] = []
    let name = input.value as! String
    let at = input.type == "at"
    if !input.eat("at") && !input.eat("id") { input.unexpected() }
    if input.eat("=") {
        while true {
            if input.type == "string" || input.type == "id" {
                value.append(PropPart(start: input.start, value: input.value as? String, name: nil))
                input.next()
            } else if input.eat(".") {
                value.append(PropPart(start: input.start, value: ".", name: nil))
            } else if input.eat("{") {
                value.append(PropPart(start: input.start, value: nil, name: input.expect("id") as? String))
                input.expect("}")
            } else {
                break
            }
        }
    }
    return Prop(start: propStart, at: at, name: name, value: value)
}

private func parseBracedExpr(_ input: GenInput) -> Expression {
    input.expect("{")
    let expr = parseExprChoice(input)
    input.expect("}")
    return expr
}

private func parseExprInner(_ input: GenInput) -> Expression {
    let exprStart = input.start
    if input.eat("(") {
        if input.eat(")") { return SequenceExpression(start: exprStart, exprs: [], markers: [[], []], empty: true) }
        let expr = parseExprChoice(input)
        input.expect(")")
        return expr
    } else if input.type == "string" {
        let val = input.value as! String
        input.next()
        if val.isEmpty { return SequenceExpression(start: exprStart, exprs: [], markers: [[], []], empty: true) }
        return LiteralExpression(start: exprStart, value: val)
    } else if input.eat("id", "_") {
        return AnyExpression(start: exprStart)
    } else if input.type == "set" {
        let content = input.value as! String
        let str = input.string
        let invert = str[str.index(str.startIndex, offsetBy: input.start)] == "!"
        let unescaped = readString(content)
        var ranges: [(Int, Int)] = []
        var i = unescaped.startIndex
        while i < unescaped.endIndex {
            let code = Int(unescaped[i].unicodeScalars.first!.value)
            i = unescaped.index(after: i)
            if i < unescaped.endIndex && unescaped[i] == "-" {
                let nextIdx = unescaped.index(after: i)
                if nextIdx < unescaped.endIndex {
                    let endCode = Int(unescaped[nextIdx].unicodeScalars.first!.value)
                    i = unescaped.index(after: nextIdx)
                    if endCode < code { input.raise("Invalid character range", input.start) }
                    addRange(input, &ranges, code, endCode + 1)
                    continue
                }
            }
            addRange(input, &ranges, code, code + 1)
        }
        input.next()
        return SetExpression(start: exprStart, ranges: ranges.sorted { $0.0 < $1.0 }, inverted: invert)
    } else if input.type == "at" && (input.value as? String == "specialize" || input.value as? String == "extend") {
        let type = input.value as! String
        input.next()
        let props = parseProps(input)
        input.expect("<")
        let token = parseExprChoice(input)
        let content: Expression
        if input.eat(",") {
            content = parseExprChoice(input)
        } else if token is LiteralExpression {
            content = token
        } else {
            input.raise("@\(type) requires two arguments when its first argument isn't a literal string")
        }
        input.expect(">")
        return SpecializeExpression(start: exprStart, type: type, props: props, token: token, content: content)
    } else if input.type == "at" && charClasses[input.value as? String ?? ""] != nil {
        let cls = CharClass(start: exprStart, type: input.value as! String)
        input.next()
        return cls
    } else if input.type == "[" {
        let rule = try! parseRule(input, named: Identifier(start: exprStart, name: "_anon"))
        if !rule.params.isEmpty { input.raise("Inline rules can't have parameters", rule.start) }
        return InlineRuleExpression(start: exprStart, rule: rule)
    } else {
        let id = parseIdent(input)
        if input.type == "[" || input.type == "{" {
            let rule = try! parseRule(input, named: id)
            if !rule.params.isEmpty { input.raise("Inline rules can't have parameters", rule.start) }
            return InlineRuleExpression(start: exprStart, rule: rule)
        } else {
            if input.eat(".") && id.name == "std" && charClasses[input.value as? String ?? ""] != nil {
                let cls = CharClass(start: exprStart, type: input.value as! String)
                input.next()
                return cls
            }
            return NameExpression(start: exprStart, id: id, args: parseArgs(input))
        }
    }
}

private func parseArgs(_ input: GenInput) -> [Expression] {
    var args: [Expression] = []
    if input.eat("<") {
        while !input.eat(">"), input.type != "eof" {
            if !args.isEmpty { input.expect(",") }
            args.append(parseExprChoice(input))
        }
    }
    return args
}

private func addRange(_ input: GenInput, _ ranges: inout [(Int, Int)], _ from: Int, _ to: Int) {
    if !ranges.allSatisfy({ $0.1 <= from || $0.0 >= to }) {
        input.raise("Overlapping character range", input.start)
    }
    ranges.append((from, to))
}

private func parseExprSuffix(_ input: GenInput) -> Expression {
    let exprStart = input.start
    var expr = parseExprInner(input)
    while true {
        if input.eat("*") { expr = RepeatExpression(start: exprStart, expr: expr, kind: .star) }
        else if input.eat("?") { expr = RepeatExpression(start: exprStart, expr: expr, kind: .optional) }
        else if input.eat("+") { expr = RepeatExpression(start: exprStart, expr: expr, kind: .plus) }
        else { return expr }
    }
}

private func endOfSequence(_ input: GenInput) -> Bool {
    input.type == "}" || input.type == ")" || input.type == "|" ||
        input.type == "{" || input.type == "," || input.type == ">"
}

private func parseExprSequence(_ input: GenInput) -> Expression {
    let seqStart = input.start
    var exprs: [Expression] = []
    var markers: [[ConflictMarker]] = [[]]

    while true {
        while true {
            let mStart = input.start
            var markerType: MarkerType?
            if input.eat("~") { markerType = .ambig }
            else if input.eat("!") { markerType = .prec }
            else { break }
            markers[markers.count - 1].append(ConflictMarker(start: mStart, id: parseIdent(input), type: markerType!))
        }
        if endOfSequence(input) { break }
        exprs.append(parseExprSuffix(input))
        markers.append([])
    }
    if exprs.count == 1 && markers.allSatisfy({ $0.isEmpty }) { return exprs[0] }
    return SequenceExpression(start: seqStart, exprs: exprs, markers: markers, empty: exprs.isEmpty)
}

private func parseExprChoice(_ input: GenInput) -> Expression {
    let choiceStart = input.start
    let left = parseExprSequence(input)
    if !input.eat("|") { return left }
    var exprs: [Expression] = [left]
    repeat { exprs.append(parseExprSequence(input)) } while input.eat("|")
    if let empty = exprs.first(where: { ($0 as? SequenceExpression)?.empty == true }) {
        input.raise("Empty expression in choice operator. If this is intentional, use () to make it explicit.", empty.start)
    }
    return ChoiceExpression(start: choiceStart, exprs: exprs)
}

private func parseIdent(_ input: GenInput) -> Identifier {
    if input.type != "id" { input.unexpected() }
    let idStart = input.start
    let name = input.value as! String
    input.next()
    return Identifier(start: idStart, name: name)
}

private func parsePrecedence(_ input: GenInput) -> PrecDeclaration {
    let precStart = input.start
    input.next()
    input.expect("{")
    var items: [(id: Identifier, type: PrecType?)] = []
    while !input.eat("}") {
        if !items.isEmpty { input.eat(",") }
        let id = parseIdent(input)
        let type: PrecType? = input.eat("at", "left") ? .left : input.eat("at", "right") ? .right : input.eat("at", "cut") ? .cut : nil
        items.append((id: id, type: type))
    }
    return PrecDeclaration(start: precStart, items: items)
}

private func parseTokens(_ input: GenInput) -> TokenDeclaration {
    let tokStart = input.start
    input.next()
    input.expect("{")
    var tokenRules: [RuleDeclaration] = []
    var literals: [LiteralDeclaration] = []
    var precedences: [TokenPrecDeclaration] = []
    var conflicts: [TokenConflictDeclaration] = []
    while !input.eat("}") {
        if input.type == "at" && input.value as? String == "precedence" {
            precedences.append(parseTokenPrecedence(input))
        } else if input.type == "at" && input.value as? String == "conflict" {
            conflicts.append(parseTokenConflict(input))
        } else if input.type == "string" {
            literals.append(LiteralDeclaration(start: input.start, literal: input.expect("string") as! String, props: parseProps(input)))
        } else {
            tokenRules.append(try! parseRule(input))
        }
    }
    return TokenDeclaration(start: tokStart, precedences: precedences, conflicts: conflicts, rules: tokenRules, literals: literals)
}

private func parseLocalTokens(_ input: GenInput, _ start: Int) -> LocalTokenDeclaration {
    input.expect("{")
    var tokenRules: [RuleDeclaration] = []
    var precedences: [TokenPrecDeclaration] = []
    var fallback: (id: Identifier, props: [Prop])? = nil
    while !input.eat("}") {
        if input.type == "at" && input.value as? String == "precedence" {
            precedences.append(parseTokenPrecedence(input))
        } else if input.eat("at", "else") && fallback == nil {
            fallback = (id: parseIdent(input), props: parseProps(input))
        } else {
            tokenRules.append(try! parseRule(input))
        }
    }
    return LocalTokenDeclaration(start: start, precedences: precedences, rules: tokenRules, fallback: fallback)
}

private func parseTokenPrecedence(_ input: GenInput) -> TokenPrecDeclaration {
    let tpStart = input.start
    input.next()
    input.expect("{")
    var tokens: [Expression] = []
    while !input.eat("}") {
        if !tokens.isEmpty { input.eat(",") }
        let expr = parseExprInner(input)
        if expr is LiteralExpression || expr is NameExpression { tokens.append(expr) }
        else { input.raise("Invalid expression in token precedences", expr.start) }
    }
    return TokenPrecDeclaration(start: tpStart, items: tokens)
}

private func parseTokenConflict(_ input: GenInput) -> TokenConflictDeclaration {
    let tcStart = input.start
    input.next()
    input.expect("{")
    let a = parseExprInner(input)
    if !(a is LiteralExpression || a is NameExpression) { input.raise("Invalid expression in token conflict", a.start) }
    input.eat(",")
    let b = parseExprInner(input)
    if !(b is LiteralExpression || b is NameExpression) { input.raise("Invalid expression in token conflict", b.start) }
    input.expect("}")
    return TokenConflictDeclaration(start: tcStart, a: a, b: b)
}

private func parseExternalTokenSet(_ input: GenInput, _ allowConflicts: Bool) -> (tokens: [(id: Identifier, props: [Prop])], conflicts: [Identifier]) {
    var tokens: [(id: Identifier, props: [Prop])] = []
    var conflicts: [Identifier] = []
    input.expect("{")
    var first = true
    while !input.eat("}") {
        if !first { input.eat(",") }
        first = false
        if allowConflicts && input.eat("at", "conflict") {
            input.expect("{")
            var f2 = true
            while !input.eat("}") {
                if !f2 { input.eat(",") }
                f2 = false
                conflicts.append(parseIdent(input))
            }
        } else {
            let id = parseIdent(input)
            let props = parseProps(input)
            tokens.append((id: id, props: props))
        }
    }
    return (tokens, conflicts)
}

private func parseExternalTokens(_ input: GenInput, _ start: Int) -> ExternalTokenDeclaration {
    let id = parseIdent(input)
    input.expect("id", "from")
    let from = input.expect("string") as! String
    let result = parseExternalTokenSet(input, true)
    return ExternalTokenDeclaration(start: start, id: id, source: from, tokens: result.tokens, conflicts: result.conflicts)
}

private func parseExternalSpecialize(_ input: GenInput, _ type: String, _ start: Int) -> ExternalSpecializeDeclaration {
    let token = parseBracedExpr(input)
    let id = parseIdent(input)
    input.expect("id", "from")
    let from = input.expect("string") as! String
    return ExternalSpecializeDeclaration(start: start, type: type, token: token, id: id, source: from,
        tokens: parseExternalTokenSet(input, false).tokens)
}

private func parseExternalPropSource(_ input: GenInput, _ start: Int) -> ExternalPropSourceDeclaration {
    let id = parseIdent(input)
    input.expect("id", "from")
    return ExternalPropSourceDeclaration(start: start, id: id, source: input.expect("string") as! String)
}

private func parseExternalProp(_ input: GenInput, _ start: Int) -> ExternalPropDeclaration {
    let externalID = parseIdent(input)
    let id = input.eat("id", "as") ? parseIdent(input) : externalID
    input.expect("id", "from")
    return ExternalPropDeclaration(start: start, id: id, externalID: externalID, source: input.expect("string") as! String)
}

private func readString(_ string: String) -> String {
    var out = ""
    var i = string.startIndex
    while i < string.endIndex {
        let ch = string[i]
        if ch == "\\" {
            i = string.index(after: i)
            guard i < string.endIndex else { break }
            let esc = string[i]
            i = string.index(after: i)
            switch esc {
            case "n": out += "\n"
            case "t": out += "\t"
            case "r": out += "\r"
            case "f": out += "\u{c}"
            case "b": out += "\u{8}"
            case "0": out += "\0"
            case "u":
                if i < string.endIndex && string[i] == "{" {
                    let close = string[string.index(after: i)...].firstIndex(of: "}")!
                    let hex = String(string[string.index(after: i)..<close])
                    out.append(String(UnicodeScalar(Int(hex, radix: 16)!)!))
                    i = string.index(after: close)
                } else if string.distance(from: i, to: string.endIndex) >= 4 {
                    let hex = String(string[i..<string.index(i, offsetBy: 4)])
                    out.append(String(UnicodeScalar(Int(hex, radix: 16)!)!))
                    i = string.index(i, offsetBy: 4)
                }
            case "x":
                if string.distance(from: i, to: string.endIndex) >= 2 {
                    let hex = String(string[i..<string.index(i, offsetBy: 2)])
                    out.append(String(UnicodeScalar(Int(hex, radix: 16)!)!))
                    i = string.index(i, offsetBy: 2)
                }
            default: out.append(esc)
            }
        } else {
            out.append(ch)
            i = string.index(after: i)
        }
    }
    return out
}
