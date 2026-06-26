import Foundation

private let cssSpace: [Int] = [9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197,
                               8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288]

private let colon = 58
private let parenL = 40
private let underscore = 95
private let bracketL = 91
private let dash = 45
private let period = 46
private let hash = 35
private let percent = 37
private let ampersand = 38
private let backslash = 92
private let newline = 10
private let asterisk = 42

private func isAlpha(_ ch: Int) -> Bool {
	return (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch >= 161
}

private func isDigit(_ ch: Int) -> Bool {
	return ch >= 48 && ch <= 57
}

private func isHex(_ ch: Int) -> Bool {
	return isDigit(ch) || (ch >= 97 && ch <= 102) || (ch >= 65 && ch <= 70)
}

private func makeIdentifierTokenizer(_ id: Int, _ varName: Int, _ callee: Int) -> TokenizerProtocol {
	return ExternalTokenizer({ input, stack in
		var inside = false
		var dashes = 0
		var i = 0
		while true {
			let next = input.next
			if isAlpha(next) || next == dash || next == underscore || (inside && isDigit(next)) {
				if !inside, next != dash || i > 0 { inside = true }
				if dashes == i, next == dash { dashes += 1 }
				input.advance()
			} else if next == backslash, input.peek(1) != newline {
				input.advance()
				if isHex(input.next) {
					repeat {
						input.advance()
					} while isHex(input.next)
					if input.next == 32 {
						input.advance()
					}
				} else if input.next > -1 {
					input.advance()
				}
				inside = true
			} else {
				if inside {
					let token = dashes == 2 && stack.canShift(varName) ? varName : (next == parenL ? callee : id)
					input.acceptToken(token)
				}
				break
			}
			i += 1
		}
	}, contextual: true)
}

private func makeCssExternalTokenizer(name: String, terms: [String: Int]) -> TokenizerProtocol {
	if name == "identifiers" {
		return makeIdentifierTokenizer(terms["identifier"]!, terms["VariableName"]!, terms["callee"]!)
	}
	if name == "queryIdentifiers" {
		return makeIdentifierTokenizer(terms["queryIdentifier"]!, terms["queryVariableName"]!, terms["QueryCallee"]!)
	}
	if name == "descendant" {
		let descendantOp = terms["descendantOp"]!
		return ExternalTokenizer { input, _ in
			if cssSpace.contains(input.peek(-1)) {
				let next = input.next
				if isAlpha(next) || next == underscore || next == hash || next == period ||
					next == asterisk || next == bracketL || (next == colon && isAlpha(input.peek(1))) ||
					next == dash || next == ampersand
				{
					input.acceptToken(descendantOp)
				}
			}
		}
	}
	if name == "unitToken" {
		let Unit = terms["Unit"]!
		return ExternalTokenizer { input, _ in
			if !cssSpace.contains(input.peek(-1)) {
				let next = input.next
				if next == percent {
					input.advance()
					input.acceptToken(Unit)
				}
				if isAlpha(next) {
					repeat {
						input.advance()
					} while isAlpha(input.next) || isDigit(input.next)
					input.acceptToken(Unit)
				}
			}
		}
	}
	fatalError("Unknown CSS external tokenizer: \(name)")
}

private nonisolated(unsafe) let constantMod = hlTags["constant"] as! (Tag) -> Tag

nonisolated(unsafe) let cssHighlighting = styleTags([
	"AtKeyword import charset namespace keyframes media supports font-feature-values": hlTags["definitionKeyword"] as Any,
	"from to selector scope MatchFlag": hlKeyword,
	"NamespaceName": hlTags["namespace"] as Any,
	"KeyframeName": hlTags["labelName"] as Any,
	"KeyframeRangeName": hlTags["operatorKeyword"] as Any,
	"TagName": hlTags["tagName"] as Any,
	"ClassName": hlTags["className"] as Any,
	"PseudoClassName": constantMod(hlTags["className"] as! Tag),
	"IdName": hlTags["labelName"] as Any,
	"FeatureName PropertyName": hlPropertyName,
	"AttributeName": hlTags["attributeName"] as Any,
	"NumberLiteral": hlNumber,
	"KeywordQuery": hlKeyword,
	"UnaryQueryOp": hlTags["operatorKeyword"] as Any,
	"CallTag ValueName FontName": hlTags["atom"] as Any,
	"VariableName": hlTags["variableName"] as Any,
	"Callee": hlTags["operatorKeyword"] as Any,
	"Unit": hlTags["unit"] as Any,
	"UniversalSelector NestingSelector": hlTags["definitionOperator"] as Any,
	"MatchOp CompareOp": hlTags["compareOperator"] as Any,
	"ChildOp SiblingOp, LogicOp": hlTags["logicOperator"] as Any,
	"BinOp": hlTags["arithmeticOperator"] as Any,
	"Important": hlTags["modifier"] as Any,
	"Comment": hlTags["blockComment"] as Any,
	"ColorLiteral": hlTags["color"] as Any,
	"ParenthesizedContent StringLiteral": hlString,
	":": hlPunctuation,
	"PseudoOp #": hlTags["derefOperator"] as Any,
	"; , |": hlTags["separator"] as Any,
	"( )": hlTags["paren"] as Any,
	"[ ]": hlTags["squareBracket"] as Any,
	"{ }": hlTags["brace"] as Any,
])

public let cssParser: LRParser = {
	let externals: [String: TokenizerProtocol] = [
		"identifiers": makeCssExternalTokenizer(name: "identifiers", terms: CSSParserData.termTable),
		"queryIdentifiers": makeCssExternalTokenizer(name: "queryIdentifiers", terms: CSSParserData.termTable),
		"descendant": makeCssExternalTokenizer(name: "descendant", terms: CSSParserData.termTable),
		"unitToken": makeCssExternalTokenizer(name: "unitToken", terms: CSSParserData.termTable),
	]
	let spec = CSSParserData.makeSpec(
		externals: externals,
		propSources: [cssHighlighting]
	)
	return LRParser(spec: spec)
}()
