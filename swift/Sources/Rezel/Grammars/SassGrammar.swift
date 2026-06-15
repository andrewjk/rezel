import Foundation

// MARK: - Character constants

private let sassSpace: [Int] = [9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197,
                                8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288]

private let colon = 58
private let parenL = 40
private let underscore = 95
private let bracketL = 91
private let dash = 45
private let period = 46
private let hash = 35
private let percent = 37
private let braceL = 123
private let braceR = 125
private let slash = 47
private let asterisk = 42
private let newlineChar = 10
private let equals = 61
private let plus = 43
private let ampersand = 38

// MARK: - Helpers

private func isAlpha(_ ch: Int) -> Bool {
	(ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch >= 161
}

private func isDigit(_ ch: Int) -> Bool {
	ch >= 48 && ch <= 57
}

private func sassStartOfComment(_ input: InputStream) -> Bool {
	if input.next != slash { return false }
	let next = input.peek(1)
	return next == slash || next == asterisk
}

private func sassIndented(_ stack: Stack) -> Bool {
	let keys = Array(stack.parser.dialects.keys)
	if let idx = keys.firstIndex(of: "indented") {
		return stack.dialectEnabled(idx)
	}
	return false
}

// MARK: - Context

private class SassIndentLevel {
	let parent: SassIndentLevel?
	let depth: Int
	let hashValue: Int

	init(parent: SassIndentLevel?, depth: Int) {
		self.parent = parent
		self.depth = depth
		let parentHash = parent?.hashValue ?? 0
		hashValue = parentHash &+ (parentHash << 8) &+ depth &+ (depth << 4)
	}
}

private nonisolated(unsafe) let sassTopIndent = SassIndentLevel(parent: nil, depth: 0)

// MARK: - Context tracker

private nonisolated(unsafe) let sassTrackIndent = ContextTracker(
	start: sassTopIndent as Any,
	shift: { context, term, stack, input in
		guard let cx = context as? SassIndentLevel else { return context }
		let name = stack.parser.termNames?[term] ?? ""
		if name == "indent" {
			return SassIndentLevel(parent: cx, depth: stack.pos - input.pos) as Any
		}
		if name == "dedent" {
			return (cx.parent ?? sassTopIndent) as Any
		}
		return context
	},
	hash: { context in (context as? SassIndentLevel)?.hashValue ?? 0 }
)

// MARK: - External tokenizers

private func makeSassExternalTokenizer(name: String, terms: [String: Int]) -> TokenizerProtocol {
	if name == "spaces" {
		let eofT = terms["eof"]!
		let blankLineStartT = terms["blankLineStart"]!
		let newlineT = terms["newline"]!
		let whitespaceT = terms["whitespace"]!
		return ExternalTokenizer({ input, stack in
			if sassIndented(stack) {
				if input.next < 0, stack.canShift(eofT) {
					input.acceptToken(eofT)
				} else {
					let prev = input.peek(-1)
					if prev == newlineChar || prev < 0, stack.canShift(blankLineStartT) {
						var spaces = 0
						while input.next != newlineChar && sassSpace.contains(input.next) {
							input.advance()
							spaces += 1
						}
						if input.next == newlineChar || sassStartOfComment(input) {
							input.acceptToken(blankLineStartT, endOffset: -spaces)
						} else if spaces > 0 {
							input.acceptToken(whitespaceT)
						}
					} else if input.next == newlineChar {
						input.acceptToken(newlineT, endOffset: 1)
					} else if sassSpace.contains(input.next) {
						input.advance()
						while input.next != newlineChar, sassSpace.contains(input.next) {
							input.advance()
						}
						input.acceptToken(whitespaceT)
					}
				}
			} else {
				var length = 0
				while sassSpace.contains(input.next) {
					input.advance()
					length += 1
				}
				if length > 0 {
					input.acceptToken(whitespaceT)
				}
			}
		}, contextual: true)
	}

	if name == "comments" {
		let lineCommentT = terms["LineComment"]!
		let commentT = terms["Comment"]!
		return ExternalTokenizer { input, stack in
			guard sassStartOfComment(input) else { return }
			input.advance()
			if sassIndented(stack) {
				var indentedComment = -1
				var off = 1
				while true {
					let prev = input.peek(-off - 1)
					if prev == newlineChar || prev < 0 {
						indentedComment = off + 1
						break
					} else if !sassSpace.contains(prev) {
						break
					}
					off += 1
				}
				if indentedComment > -1 {
					let block = input.next == asterisk
					var end = 0
					input.advance()
					while input.next >= 0 {
						if input.next == newlineChar {
							input.advance()
							var indented = 0
							while input.next != newlineChar, sassSpace.contains(input.next) {
								indented += 1
								input.advance()
							}
							if indented < indentedComment {
								end = -indented - 1
								break
							}
						} else if block, input.next == asterisk, input.peek(1) == slash {
							end = 2
							break
						} else {
							input.advance()
						}
					}
					input.acceptToken(block ? commentT : lineCommentT, endOffset: end)
					return
				}
			}
			if input.next == slash {
				while input.next != newlineChar, input.next >= 0 {
					input.advance()
				}
				input.acceptToken(lineCommentT)
			} else {
				input.advance()
				while input.next >= 0 {
					let next = input.next
					input.advance()
					if next == asterisk, input.next == slash {
						input.advance()
						break
					}
				}
				input.acceptToken(commentT)
			}
		}
	}

	if name == "indentedMixins" {
		let indentedMixinT = terms["IndentedMixin"]!
		let indentedIncludeT = terms["IndentedInclude"]!
		return ExternalTokenizer { input, stack in
			if input.next == plus || input.next == equals, sassIndented(stack) {
				input.acceptToken(input.next == equals ? indentedMixinT : indentedIncludeT, endOffset: 1)
			}
		}
	}

	if name == "indentation" {
		let dedentT = terms["dedent"]!
		let indentT = terms["indent"]!
		return ExternalTokenizer { input, stack in
			guard sassIndented(stack) else { return }
			let cDepth = (stack.context as? SassIndentLevel)?.depth ?? 0
			if input.next < 0, cDepth > 0 {
				input.acceptToken(dedentT)
				return
			}
			let prev = input.peek(-1)
			if prev == newlineChar {
				var depth = 0
				while input.next != newlineChar, sassSpace.contains(input.next) {
					input.advance()
					depth += 1
				}
				if depth != cDepth,
				   input.next != newlineChar, !sassStartOfComment(input)
				{
					if depth < cDepth {
						input.acceptToken(dedentT, endOffset: -depth)
					} else {
						input.acceptToken(indentT)
					}
				}
			}
		}
	}

	if name == "identifiers" {
		let interpolationStartT = terms["InterpolationStart"]!
		let variableNameT = terms["VariableName"]!
		let queryIdentifierT = terms["queryIdentifier"]!
		let calleeT = terms["callee"]!
		let identifierT = terms["identifier"]!
		return ExternalTokenizer { input, stack in
			var inside = false
			var dashes = 0
			var i = 0
			while true {
				let next = input.next
				if isAlpha(next) || next == dash || next == underscore || (inside && isDigit(next)) {
					if !inside, next != dash || i > 0 { inside = true }
					if dashes == i, next == dash { dashes += 1 }
					input.advance()
				} else if next == hash, input.peek(1) == braceL {
					input.acceptToken(interpolationStartT, endOffset: 2)
					break
				} else {
					if inside {
						let token: Int
						if dashes == 2, stack.canShift(variableNameT) {
							token = variableNameT
						} else if stack.canShift(queryIdentifierT) {
							token = queryIdentifierT
						} else if next == parenL {
							token = calleeT
						} else {
							token = identifierT
						}
						input.acceptToken(token)
					}
					break
				}
				i += 1
			}
		}
	}

	if name == "interpolationEnd" {
		let interpolationContinueT = terms["InterpolationContinue"]!
		let interpolationEndT = terms["InterpolationEnd"]!
		return ExternalTokenizer { input, _ in
			if input.next == braceR {
				input.advance()
				while isAlpha(input.next) || input.next == dash || input.next == underscore || isDigit(input.next) {
					input.advance()
				}
				if input.next == hash, input.peek(1) == braceL {
					input.acceptToken(interpolationContinueT, endOffset: 2)
				} else {
					input.acceptToken(interpolationEndT)
				}
			}
		}
	}

	if name == "descendant" {
		let descendantOpT = terms["descendantOp"]!
		return ExternalTokenizer { input, _ in
			if sassSpace.contains(input.peek(-1)) {
				let next = input.next
				if isAlpha(next) || next == underscore || next == hash || next == period ||
					next == bracketL || (next == colon && isAlpha(input.peek(1))) ||
					next == dash || next == ampersand || next == asterisk
				{
					input.acceptToken(descendantOpT)
				}
			}
		}
	}

	if name == "unitToken" {
		let unitT = terms["Unit"]!
		return ExternalTokenizer { input, _ in
			if !sassSpace.contains(input.peek(-1)) {
				let next = input.next
				if next == percent {
					input.advance()
					input.acceptToken(unitT)
				}
				if isAlpha(next) {
					repeat {
						input.advance()
					} while isAlpha(input.next) || isDigit(input.next)
					input.acceptToken(unitT)
				}
			}
		}
	}

	fatalError("Unknown Sass external tokenizer: \(name)")
}

// MARK: - Highlighting

private nonisolated(unsafe) let constantMod = hlTags["constant"] as! (Tag) -> Tag
private nonisolated(unsafe) let specialMod = hlTags["special"] as! (Tag) -> Tag

nonisolated(unsafe) let sassHighlighting = styleTags([
	"AtKeyword import charset namespace keyframes media supports include mixin use forward extend at-root": hlTags["definitionKeyword"] as Any,
	"Keyword selector": hlKeyword,
	"ControlKeyword": hlTags["controlKeyword"] as Any,
	"NamespaceName": hlTags["namespace"] as Any,
	"KeyframeName": hlTags["labelName"] as Any,
	"KeyframeRangeName": hlTags["operatorKeyword"] as Any,
	"TagName": hlTags["tagName"] as Any,
	"ClassName Suffix": hlTags["className"] as Any,
	"PseudoClassName": constantMod(hlTags["className"] as! Tag),
	"IdName": hlTags["labelName"] as Any,
	"FeatureName PropertyName": hlPropertyName,
	"AttributeName": hlTags["attributeName"] as Any,
	"NumberLiteral": hlNumber,
	"KeywordQuery": hlKeyword,
	"UnaryQueryOp": hlTags["operatorKeyword"] as Any,
	"CallTag ValueName": hlTags["atom"] as Any,
	"VariableName": hlTags["variableName"] as Any,
	"SassVariableName": specialMod(hlTags["variableName"] as! Tag),
	"Callee": hlTags["operatorKeyword"] as Any,
	"Unit": hlTags["unit"] as Any,
	"UniversalSelector NestingSelector IndentedMixin IndentedInclude": hlTags["definitionOperator"] as Any,
	"MatchOp": hlTags["compareOperator"] as Any,
	"ChildOp SiblingOp, LogicOp": hlTags["logicOperator"] as Any,
	"BinOp": hlTags["arithmeticOperator"] as Any,
	"Important Global Default": hlTags["modifier"] as Any,
	"Comment": hlTags["blockComment"] as Any,
	"LineComment": hlTags["lineComment"] as Any,
	"ColorLiteral": hlTags["color"] as Any,
	"ParenthesizedContent StringLiteral": hlString,
	"InterpolationStart InterpolationContinue InterpolationEnd": hlMeta,
	": \"...\"": hlPunctuation,
	"PseudoOp #": hlTags["derefOperator"] as Any,
	"; ,": hlTags["separator"] as Any,
	"( )": hlTags["paren"] as Any,
	"[ ]": hlTags["squareBracket"] as Any,
	"{ }": hlTags["brace"] as Any,
])

// MARK: - Parser

public nonisolated(unsafe) let sassParser: LRParser = {
	let externals: [String: TokenizerProtocol] = [
		"spaces": makeSassExternalTokenizer(name: "spaces", terms: SassParserData.termTable),
		"comments": makeSassExternalTokenizer(name: "comments", terms: SassParserData.termTable),
		"indentedMixins": makeSassExternalTokenizer(name: "indentedMixins", terms: SassParserData.termTable),
		"indentation": makeSassExternalTokenizer(name: "indentation", terms: SassParserData.termTable),
		"identifiers": makeSassExternalTokenizer(name: "identifiers", terms: SassParserData.termTable),
		"interpolationEnd": makeSassExternalTokenizer(name: "interpolationEnd", terms: SassParserData.termTable),
		"descendant": makeSassExternalTokenizer(name: "descendant", terms: SassParserData.termTable),
		"unitToken": makeSassExternalTokenizer(name: "unitToken", terms: SassParserData.termTable),
	]
	let spec = SassParserData.makeSpec(
		externals: externals,
		propSources: [sassHighlighting],
		context: sassTrackIndent
	)
	return LRParser(spec: spec)
}()
