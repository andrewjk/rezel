//
//  Parse.swift
//  Rezel
//
//  Created on 2025-06-11.
//

import Foundation

/// Parser input for grammar files
public class GrammarInput {
    var type: String = "sof"
    var value: Any?
    var start: Int = 0
    var end: Int = 0
    
    let string: String
    let fileName: String?
    
    init(string: String, fileName: String? = nil) {
        self.string = string
        self.fileName = fileName
        next()
    }
    
    func lineInfo(pos: Int) -> (line: Int, ch: Int) {
        var line = 1
        var cur = 0
        
        while true {
            let curIndex = string.index(string.startIndex, offsetBy: cur)
        if let next = string.range(of: "\n", range: curIndex..<string.endIndex)?.lowerBound {
                let nextPos = string.distance(from: string.startIndex, to: next)
                if nextPos > -1 && nextPos < pos {
                    line += 1
                    cur = nextPos + 1
                } else {
                    return (line: line, ch: pos - cur)
                }
            } else {
                return (line: line, ch: pos - cur)
            }
        }
    }
    
    func message(_ msg: String, pos: Int = -1) -> String {
        var posInfo = fileName ?? ""
        if pos > -1 {
            let info = lineInfo(pos: pos)
            posInfo += (posInfo.isEmpty ? "" : " ") + "\(info.line):\(info.ch)"
        }
        return posInfo.isEmpty ? msg : msg + " (\(posInfo))"
    }
    
    func raise(_ msg: String, pos: Int = -1) -> Never {
        fatalError(message(msg, pos: pos))
    }
    
    func match(pos: Int, pattern: String) -> Int {
        let substring = String(string[string.index(string.startIndex, offsetBy: pos)...])
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return -1
        }
        
        let range = NSRange(location: 0, length: (substring as NSString).length)
        guard let match = regex.firstMatch(in: substring, options: [], range: range) else {
            return -1
        }
        
        return pos + match.range.length
    }
    
    func next() {
        let start = match(pos: end, pattern: #"(\s|\/\/.*|\/\*[\s\S]*?\*\/)*"#)
        if start == string.count {
            return set(type: "eof", value: nil, start: start, end: start)
        }
        
        let nextCharIndex = string.index(string.startIndex, offsetBy: start)
        let nextChar = string[nextCharIndex]
        
        if nextChar == "\"" {
            let end = match(pos: start + 1, pattern: #"(\\.|[^"\\])*""#)
            if end == -1 {
                raise("Unterminated string literal", pos: start)
            }
            let content = String(string[string.index(string.startIndex, offsetBy: start + 1)..<string.index(string.startIndex, offsetBy: end - 1)])
            return set(type: "string", value: readString(content), start: start, end: end)
        } else if nextChar == "'" {
            let end = match(pos: start + 1, pattern: #"(\\.|[^'\\])*'"#)
            if end == -1 {
                raise("Unterminated string literal", pos: start)
            }
            let content = String(string[string.index(string.startIndex, offsetBy: start + 1)..<string.index(string.startIndex, offsetBy: end - 1)])
            return set(type: "string", value: readString(content), start: start, end: end)
        } else if nextChar == "@" {
            let wordPattern = #"[\w_-]+"#
            guard let regex = try? NSRegularExpression(pattern: wordPattern, options: []) else {
                raise("@ without a name", pos: start)
            }
            
            let searchRange = NSRange(location: start + 1, length: string.count - (start + 1))
            guard let match = regex.firstMatch(in: string, options: [], range: searchRange) else {
                raise("@ without a name", pos: start)
            }
            
            let matchedStr = (string as NSString).substring(with: match.range)
            return set(type: "at", value: matchedStr, start: start, end: start + 1 + matchedStr.count)
        } else if (nextChar == "$" || nextChar == "!") {
            let nextCharIndex2 = string.index(string.startIndex, offsetBy: start + 1)
            if string.count > start + 1 && string[nextCharIndex2] == "[" {
                let end = match(pos: start + 2, pattern: #"(?:\\.|[^\]\\])*\]"#)
                if end == -1 {
                    raise("Unterminated character set", pos: start)
                }
                let content = String(string[string.index(string.startIndex, offsetBy: start + 2)..<string.index(string.startIndex, offsetBy: end - 1)])
                return set(type: "set", value: content, start: start, end: end)
            }
        }
        
        if "[[\\]()!~+*?{}<>.,|:$=]".contains(nextChar) {
            return set(type: String(nextChar), value: nil, start: start, end: start + 1)
        } else {
            let wordPattern = #"[\w_-]+"#
            guard let regex = try? NSRegularExpression(pattern: wordPattern, options: []) else {
                raise("Unexpected character \(nextChar)", pos: start)
            }
            
            let searchRange = NSRange(location: start, length: string.count - start)
            guard let match = regex.firstMatch(in: string, options: [], range: searchRange) else {
                raise("Unexpected character \(nextChar)", pos: start)
            }
            
            let matchedStr = (string as NSString).substring(with: match.range)
            return set(type: "id", value: matchedStr, start: start, end: start + matchedStr.count)
        }
    }
    
    func set(type: String, value: Any?, start: Int, end: Int) {
        self.type = type
        self.value = value
        self.start = start
        self.end = end
    }
    
    func eat(_ type: String, value: Any? = nil) -> Bool {
        if self.type == type && (value == nil || self.value as? String == value as? String) {
            next()
            return true
        } else {
            return false
        }
    }
    
    func unexpected() -> Never {
        let substr = String(string[string.index(string.startIndex, offsetBy: start)..<string.index(string.startIndex, offsetBy: end)])
        raise("Unexpected token '\(substr)'", pos: start)
    }
    
    func expect(_ type: String, value: Any? = nil) -> Any? {
        let val = self.value
        if self.type != type || !(value == nil || val as? String == value as? String) {
            unexpected()
        }
        next()
        return val
    }
    
    func parse() -> GrammarDeclaration {
        return parseGrammar(input: self)
    }
}

/// Parse a grammar file
fileprivate func parseGrammar(input: GrammarInput) -> GrammarDeclaration {
    let start = input.start
    var rules: [RuleDeclaration] = []
    var prec: PrecDeclaration?
    var tokens: TokenDeclaration?
    var localTokens: [LocalTokenDeclaration] = []
    var mainSkip: Expression?
    var scopedSkip: [(expr: Expression, topRules: [RuleDeclaration], rules: [RuleDeclaration])] = []
    var dialects: [Identifier] = []
    var context: ContextDeclaration?
    var external: [ExternalTokenDeclaration] = []
    var specialized: [ExternalSpecializeDeclaration] = []
    var props: [ExternalPropDeclaration] = []
    var propSources: [ExternalPropSourceDeclaration] = []
    var tops: [RuleDeclaration] = []
    var sawTop = false
    var autoDelim = false
    
    while input.type != "eof" {
        let start = input.start
        
        if input.eat("at", value: "top") {
            if input.type != "id" {
                input.raise("Top rules must have a name", pos: input.start)
            }
            tops.append(parseRule(input: input, named: parseIdent(input: input)))
            sawTop = true
        } else if input.type == "at" && input.value as? String == "tokens" {
            if tokens != nil {
                input.raise("Multiple @tokens declarations", pos: input.start)
            } else {
                tokens = parseTokens(input: input)
            }
        } else if input.eat("at", value: "local") {
            _ = input.expect("id", value: "tokens")
            localTokens.append(parseLocalTokens(input: input, start: start))
        } else if input.eat("at", value: "context") {
            if context != nil {
                input.raise("Multiple @context declarations", pos: start)
            }
            let id = parseIdent(input: input)
            _ = input.expect("id", value: "from")
            let source = input.expect("string") as! String
            context = ContextDeclaration(start: start, id: id, source: source)
        } else if input.eat("at", value: "external") {
            if input.eat("id", value: "tokens") {
                external.append(parseExternalTokens(input: input, start: start))
            } else if input.eat("id", value: "prop") {
                props.append(parseExternalProp(input: input, start: start))
            } else if input.eat("id", value: "extend") {
                specialized.append(parseExternalSpecialize(input: input, type: "extend", start: start))
            } else if input.eat("id", value: "specialize") {
                specialized.append(parseExternalSpecialize(input: input, type: "specialize", start: start))
            } else if input.eat("id", value: "propSource") {
                propSources.append(parseExternalPropSource(input: input, start: start))
        } else {
            input.unexpected()
        }
    } else if input.eat("at", value: "dialects") {
            _ = input.expect("{")
            var first = true
            while !input.eat("}") {
                if !first {
                    _ = input.eat(",")
                }
                dialects.append(parseIdent(input: input))
                first = false
            }
        } else if input.type == "at" && input.value as? String == "precedence" {
            if prec != nil {
                input.raise("Multiple precedence declarations", pos: input.start)
            }
            prec = parsePrecedence(input: input)
        } else if input.eat("at", value: "detectDelim") {
            autoDelim = true
        } else if input.eat("at", value: "skip") {
            let skip = parseBracedExpr(input: input)
            if input.type == "{" {
                input.next()
                var rules: [RuleDeclaration] = []
                var topRules: [RuleDeclaration] = []
                while !input.eat("}") {
                    if input.eat("at", value: "top") {
                        topRules.append(parseRule(input: input, named: parseIdent(input: input)))
                        sawTop = true
                    } else {
                        rules.append(parseRule(input: input))
                    }
                }
                scopedSkip.append((expr: skip, topRules: topRules, rules: rules))
            } else {
                if mainSkip != nil {
                    input.raise("Multiple top-level skip declarations", pos: input.start)
                }
                mainSkip = skip
            }
        } else {
            rules.append(parseRule(input: input))
        }
    }
    
    if !sawTop {
        input.raise("Missing @top declaration")
    }
    
    return GrammarDeclaration(
        start: start,
        rules: rules,
        topRules: tops,
        tokens: tokens,
        localTokens: localTokens,
        context: context,
        externalTokens: external,
        externalSpecializers: specialized,
        externalPropSources: propSources,
        precedences: prec,
        mainSkip: mainSkip,
        scopedSkip: scopedSkip,
        dialects: dialects,
        externalProps: props,
        autoDelim: autoDelim
    )
}

fileprivate func parseRule(input: GrammarInput, named: Identifier? = nil) -> RuleDeclaration {
    let start = named?.start ?? input.start
    let id = named ?? parseIdent(input: input)
    let props = parseProps(input: input)
    var params: [Identifier] = []
    
    if input.eat("<") {
        while !input.eat(">") {
            if params.count > 0 {
                _ = input.expect(",")
            }
            params.append(parseIdent(input: input))
        }
    }
    
    let expr = parseBracedExpr(input: input)
    return RuleDeclaration(start: start, id: id, props: props, params: params, expr: expr)
}

fileprivate func parseProps(input: GrammarInput) -> [Prop] {
    if input.type != "[" {
        return []
    }
    
    var props: [Prop] = []
    _ = input.expect("[")
    while !input.eat("]") {
        if props.count > 0 {
            _ = input.expect(",")
        }
        props.append(parseProp(input: input))
    }
    return props
}

fileprivate func parseProp(input: GrammarInput) -> Prop {
    let start = input.start
    var value: [PropPart] = []
    let name = input.value as! String
    let at = input.type == "at"
    
    if !input.eat("at") && !input.eat("id") {
        input.unexpected()
    }
    
    if input.eat("=") {
        while true {
            if input.type == "string" || input.type == "id" {
                value.append(PropPart(start: input.start, value: input.value as? String, name: nil))
                input.next()
            } else if input.eat(".") {
                value.append(PropPart(start: input.start, value: ".", name: nil))
            } else if input.eat("{") {
                value.append(PropPart(start: input.start, value: nil, name: input.expect("id") as? String))
                _ = input.expect("}")
            } else {
                break
            }
        }
    }
    
    return Prop(start: start, at: at, name: name, value: value)
}

fileprivate func parseBracedExpr(input: GrammarInput) -> Expression {
    _ = input.expect("{")
    let expr = parseExprChoice(input: input)
    _ = input.expect("}")
    return expr
}

let SET_MARKER = "\u{FFFF}" // Use a valid high unicode character as marker

fileprivate func parseExprInner(input: GrammarInput) -> Expression {
    let start = input.start
    
    if input.eat("(") {
        if input.eat(")") {
            return SequenceExpression(start: start, exprs: [], markers: [[]], empty: true)
        }
        let expr = parseExprChoice(input: input)
        _ = input.expect(")")
        return expr
    } else if input.type == "string" {
        let value = input.value as! String
        input.next()
        if value.isEmpty {
            return SequenceExpression(start: start, exprs: [], markers: [[]], empty: true)
        }
        return LiteralExpression(start: start, value: value)
    } else if input.eat("id", value: "_") {
        return AnyExpression(start: start)
    } else if input.type == "set" {
        let content = input.value as! String
        let invert = input.string[input.string.index(input.string.startIndex, offsetBy: input.start)] == "!"
        let unescaped = readString(content.replacingOccurrences(of: "\\\\", with: "\\"))
        
        var ranges: [(Int, Int)] = []
        var pos = 0
        
        while pos < unescaped.count {
            let startIdx = unescaped.index(unescaped.startIndex, offsetBy: pos)
            let code = Int(unescaped[startIdx].unicodeScalars.first!.value)
            pos += code > 0xffff ? 2 : 1
            
            if pos < unescaped.count - 1 {
                let nextIdx = unescaped.index(unescaped.startIndex, offsetBy: pos)
                if unescaped[nextIdx] == Character(SET_MARKER) {
                    let endIdx = unescaped.index(unescaped.startIndex, offsetBy: pos + 1)
                    let end = Int(unescaped[endIdx].unicodeScalars.first!.value)
                    pos += end > 0xffff ? 3 : 2
                    
                    if end < code {
                        input.raise("Invalid character range", pos: input.start)
                    }
                    addRange(input: input, ranges: &ranges, from: code, to: end + 1)
                    continue
                }
            }
            
            var finalCode = code
            if code == Int(SET_MARKER.unicodeScalars.first!.value) {
                finalCode = 45
            }
            addRange(input: input, ranges: &ranges, from: finalCode, to: finalCode + 1)
        }
        
        input.next()
        return SetExpression(start: start, ranges: ranges.sorted { $0.0 < $1.0 }, inverted: invert)
    } else if input.type == "at" && (input.value as? String == "specialize" || input.value as? String == "extend") {
        let typeVal = input.value as! String
        let start = input.start
        input.next()
        let props = parseProps(input: input)
        _ = input.expect("<")
        
        let token = parseExprChoice(input: input)
        var content: Expression
        
        if input.eat(",") {
            content = parseExprChoice(input: input)
        } else if let litExpr = token as? LiteralExpression {
            content = litExpr
        } else {
            input.raise("@\(typeVal) requires two arguments when its first argument isn't a literal string")
        }
        
        _ = input.expect(">")
        return SpecializeExpression(start: start, type: typeVal, props: props, token: token, content: content)
    } else if input.type == "at" && CharClasses[input.value as? String ?? ""] != nil {
        let cls = CharClass(start: input.start, type: input.value as! String)
        input.next()
        return cls
    } else if input.type == "[" {
        let rule = parseRule(input: input, named: Identifier(start: start, name: "_anon"))
        if rule.params.count > 0 {
            input.raise("Inline rules can't have parameters", pos: rule.start)
        }
        return InlineRuleExpression(start: start, rule: rule)
    } else {
        let id = parseIdent(input: input)
        if input.type == "[" || input.type == "{" {
            let rule = parseRule(input: input, named: id)
            if rule.params.count > 0 {
                input.raise("Inline rules can't have parameters", pos: rule.start)
            }
            return InlineRuleExpression(start: start, rule: rule)
        } else {
            if input.eat(".") && id.name == "std" && CharClasses[input.value as? String ?? ""] != nil {
                let cls = CharClass(start: start, type: input.value as! String)
                input.next()
                return cls
            }
            return NameExpression(start: start, id: id, args: parseArgs(input: input))
        }
    }
}

fileprivate func parseArgs(input: GrammarInput) -> [Expression] {
    var args: [Expression] = []
    if input.eat("<") {
        while !input.eat(">") {
            if args.count > 0 {
                _ = input.expect(",")
            }
            args.append(parseExprChoice(input: input))
        }
    }
    return args
}

fileprivate func addRange(input: GrammarInput, ranges: inout [(Int, Int)], from: Int, to: Int) {
    for (a, b) in ranges {
        if !(b <= from || a >= to) {
            input.raise("Overlapping character range", pos: input.start)
        }
    }
    ranges.append((from, to))
}

fileprivate func parseExprSuffix(input: GrammarInput) -> Expression {
    let start = input.start
    var expr = parseExprInner(input: input)
    
    while true {
        let kind = input.type
        if input.eat("*") || input.eat("?") || input.eat("+") {
            expr = RepeatExpression(start: start, expr: expr, kind: kind)
        } else {
            return expr
        }
    }
}

fileprivate func endOfSequence(input: GrammarInput) -> Bool {
    return input.type == "}" ||
           input.type == ")" ||
           input.type == "|" ||
           input.type == "/" ||
           input.type == "/\\" ||
           input.type == "{" ||
           input.type == "," ||
           input.type == ">"
}

fileprivate func parseExprSequence(input: GrammarInput) -> Expression {
    let start = input.start
    var exprs: [Expression] = []
    var markers: [[ConflictMarker]] = [[]]
    
    repeat {
        // Add markers at this position
        while true {
            let localStart = input.start
            var markerType: String?
            
            if input.eat("~") {
                markerType = "ambig"
            } else if input.eat("!") {
                markerType = "prec"
            } else {
                break
            }
            
            markers[markers.count - 1].append(ConflictMarker(start: localStart, id: parseIdent(input: input), type: markerType!))
        }
        
        if endOfSequence(input: input) {
            break
        }
        
        exprs.append(parseExprSuffix(input: input))
        markers.append([])
    } while !endOfSequence(input: input)
    
    if exprs.count == 1 && markers.allSatisfy({ $0.isEmpty }) {
        return exprs[0]
    }
    
    return SequenceExpression(start: start, exprs: exprs, markers: markers, empty: exprs.isEmpty)
}

fileprivate func parseExprChoice(input: GrammarInput) -> Expression {
    let start = input.start
    let left = parseExprSequence(input: input)
    
    if !input.eat("|") {
        return left
    }
    
    var exprs: [Expression] = [left]
    repeat {
        exprs.append(parseExprSequence(input: input))
    } while input.eat("|")
    
    if let empty = exprs.first(where: { expr in
        if let seqExpr = expr as? SequenceExpression {
            return seqExpr.empty
        }
        return false
    }) {
        input.raise("Empty expression in choice operator. If this is intentional, use () to make it explicit.", pos: empty.start)
    }
    
    return ChoiceExpression(start: start, exprs: exprs)
}

fileprivate func parseIdent(input: GrammarInput) -> Identifier {
    if input.type != "id" {
        input.unexpected()
    }
    
    let start = input.start
    let name = input.value as! String
    input.next()
    return Identifier(start: start, name: name)
}

fileprivate func parsePrecedence(input: GrammarInput) -> PrecDeclaration {
    let start = input.start
    input.next()
    _ = input.expect("{")
    
    var items: [(id: Identifier, type: String?)] = []
    
    while !input.eat("}") {
        if items.count > 0 {
            _ = input.eat(",")
        }
        
        let id = parseIdent(input: input)
        let type: String?
        
        if input.eat("at", value: "left") {
            type = "left"
        } else if input.eat("at", value: "right") {
            type = "right"
        } else if input.eat("at", value: "cut") {
            type = "cut"
        } else {
            type = nil
        }
        
        items.append((id: id, type: type))
    }
    
    return PrecDeclaration(start: start, items: items)
}

fileprivate func parseTokens(input: GrammarInput) -> TokenDeclaration {
    let start = input.start
    input.next()
    _ = input.expect("{")
    
    var tokenRules: [RuleDeclaration] = []
    var literals: [LiteralDeclaration] = []
    var precedences: [TokenPrecDeclaration] = []
    var conflicts: [TokenConflictDeclaration] = []
    
    while !input.eat("}") {
        if input.type == "at" && input.value as? String == "precedence" {
            precedences.append(parseTokenPrecedence(input: input))
        } else if input.type == "at" && input.value as? String == "conflict" {
            conflicts.append(parseTokenConflict(input: input))
        } else if input.type == "string" {
            let value = input.expect("string") as! String
            literals.append(LiteralDeclaration(start: input.start, literal: value, props: parseProps(input: input)))
        } else {
            tokenRules.append(parseRule(input: input))
        }
    }
    
    return TokenDeclaration(start: start, precedences: precedences, conflicts: conflicts, rules: tokenRules, literals: literals)
}

fileprivate func parseLocalTokens(input: GrammarInput, start: Int) -> LocalTokenDeclaration {
    _ = input.expect("{")
    
    var tokenRules: [RuleDeclaration] = []
    var precedences: [TokenPrecDeclaration] = []
    var fallback: (id: Identifier, props: [Prop])?
    
    while !input.eat("}") {
        if input.type == "at" && input.value as? String == "precedence" {
            precedences.append(parseTokenPrecedence(input: input))
        } else if input.eat("at", value: "else") && fallback == nil {
            let id = parseIdent(input: input)
            fallback = (id: id, props: parseProps(input: input))
        } else {
            tokenRules.append(parseRule(input: input))
        }
    }
    
    return LocalTokenDeclaration(start: start, precedences: precedences, rules: tokenRules, fallback: fallback)
}

fileprivate func parseTokenPrecedence(input: GrammarInput) -> TokenPrecDeclaration {
    let start = input.start
    input.next()
    _ = input.expect("{")
    
    var tokens: [Expression] = []
    
    while !input.eat("}") {
        if tokens.count > 0 {
            _ = input.eat(",")
        }
        
        let expr = parseExprInner(input: input)
        if expr is LiteralExpression || expr is NameExpression {
            tokens.append(expr)
        } else {
            input.raise("Invalid expression in token precedences", pos: expr.start)
        }
    }
    
    return TokenPrecDeclaration(start: start, items: tokens)
}

fileprivate func parseTokenConflict(input: GrammarInput) -> TokenConflictDeclaration {
    let start = input.start
    input.next()
    _ = input.expect("{")
    
    let a = parseExprInner(input: input)
    if !(a is LiteralExpression || a is NameExpression) {
        input.raise("Invalid expression in token conflict", pos: a.start)
    }
    
    _ = input.eat(",")
    let b = parseExprInner(input: input)
    if !(b is LiteralExpression || b is NameExpression) {
        input.raise("Invalid expression in token conflict", pos: b.start)
    }
    
    _ = input.expect("}")
    return TokenConflictDeclaration(start: start, a: a, b: b)
}

fileprivate func parseExternalTokenSet(input: GrammarInput, allowConflicts: Bool) -> (tokens: [(id: Identifier, props: [Prop])], conflicts: [Identifier]) {
    var tokens: [(id: Identifier, props: [Prop])] = []
    var conflicts: [Identifier] = []
    
    _ = input.expect("{")
    var first = true
    
    while !input.eat("}") {
        if !first {
            _ = input.eat(",")
        }
        first = false
        
        if allowConflicts && input.eat("at", value: "conflict") {
            _ = input.expect("{")
            var f = true
            while !input.eat("}") {
                if !f {
                    _ = input.eat(",")
                }
                conflicts.append(parseIdent(input: input))
                f = false
            }
        } else {
            let id = parseIdent(input: input)
            let props = parseProps(input: input)
            tokens.append((id: id, props: props))
        }
    }
    
    return (tokens: tokens, conflicts: conflicts)
}

fileprivate func parseExternalTokens(input: GrammarInput, start: Int) -> ExternalTokenDeclaration {
    let id = parseIdent(input: input)
    _ = input.expect("id", value: "from")
    let from = input.expect("string") as! String
    let (tokens, conflicts) = parseExternalTokenSet(input: input, allowConflicts: true)
    return ExternalTokenDeclaration(start: start, id: id, source: from, tokens: tokens, conflicts: conflicts)
}

fileprivate func parseExternalSpecialize(input: GrammarInput, type: String, start: Int) -> ExternalSpecializeDeclaration {
    let token = parseBracedExpr(input: input)
    let id = parseIdent(input: input)
    _ = input.expect("id", value: "from")
    let from = input.expect("string") as! String
    let (tokens, _) = parseExternalTokenSet(input: input, allowConflicts: false)
    return ExternalSpecializeDeclaration(start: start, type: type, token: token, id: id, source: from, tokens: tokens)
}

fileprivate func parseExternalPropSource(input: GrammarInput, start: Int) -> ExternalPropSourceDeclaration {
    let id = parseIdent(input: input)
    _ = input.expect("id", value: "from")
    let from = input.expect("string") as! String
    return ExternalPropSourceDeclaration(start: start, id: id, source: from)
}

fileprivate func parseExternalProp(input: GrammarInput, start: Int) -> ExternalPropDeclaration {
    let externalID = parseIdent(input: input)
    let id = input.eat("id", value: "as") ? parseIdent(input: input) : externalID
    _ = input.expect("id", value: "from")
    let from = input.expect("string") as! String
    return ExternalPropDeclaration(start: start, id: id, externalID: externalID, source: from)
}

fileprivate func readString(_ string: String) -> String {
    var result = ""
    var pos = 0
    
    while pos < string.count {
        let startIdx = string.index(string.startIndex, offsetBy: pos)
        let char = string[startIdx]
        
        if char == "\\" {
            pos += 1
            if pos >= string.count { break }
            
            let nextIdx = string.index(string.startIndex, offsetBy: pos)
            let next = string[nextIdx]
            
            switch next {
            case "u":
                if pos + 1 < string.count {
                    let nextNextIdx = string.index(string.startIndex, offsetBy: pos + 1)
                    let nextNext = string[nextNextIdx]
                    
                    if nextNext == "{" {
                        // Unicode escape like \u{1234}
                        pos += 2
                        var hex = ""
                        while pos < string.count {
                            let hexIdx = string.index(string.startIndex, offsetBy: pos)
                            let hexChar = string[hexIdx]
                            if hexChar == "}" { break }
                            hex.append(hexChar)
                            pos += 1
                        }
                        if let code = Int(hex, radix: 16) {
                            result.append(String(UnicodeScalar(code)!))
                        }
                    } else {
                        // Unicode escape like \u1234
                        let hexStart = string.index(string.startIndex, offsetBy: pos + 1)
                        let hexEnd = min(string.index(hexStart, offsetBy: 4), string.endIndex)
                        let hex = String(string[hexStart..<hexEnd])
                        if let code = Int(hex, radix: 16) {
                            result.append(String(UnicodeScalar(code)!))
                        }
                        pos += 4
                    }
                }
            case "x":
                // Hex escape like \x12
                if pos + 2 <= string.count {
                    let hexStart = string.index(string.startIndex, offsetBy: pos + 1)
                    let hexEnd = string.index(hexStart, offsetBy: 2)
                    let hex = String(string[hexStart..<hexEnd])
                    if let code = Int(hex, radix: 16) {
                        result.append(Character(UnicodeScalar(code)!))
                    }
                    pos += 2
                }
            case "n":
                result.append("\n")
            case "t":
                result.append("\t")
            case "r":
                result.append("\r")
            case "f":
                result.append("\u{c}") // form feed
            case "b":
                result.append("\u{8}") // backspace
            case "0":
                result.append("\0")
            default:
                result.append(next)
            }
        } else {
            result.append(char)
        }
        pos += 1
    }
    
    return result
}
