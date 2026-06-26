import Foundation

private let _b = 98
private let _e = 101
private let _f = 102
private let _r = 114
private let _E = 69
private let Zero = 48
private let Dot = 46
private let Plus = 43
private let Minus = 45
private let Hash = 35
private let Quote = 34
private let Pipe = 124
private let LessThan = 60
private let GreaterThan = 62

private func isNum(_ ch: Int) -> Bool {
	return ch >= 48 && ch <= 57
}

private func isNum_(_ ch: Int) -> Bool {
	return isNum(ch) || ch == 95
}

private func isWordChar(_ ch: Int) -> Bool {
	guard let scalar = UnicodeScalar(ch) else { return false }
	return scalar.properties.isAlphabetic || scalar.properties.numericType != nil || ch == 95
}

private func makeRustExternalTokenizer(name: String, terms: [String: Int]) -> TokenizerProtocol {
	if name == "literalTokens" {
		let Float = terms["Float"]!
		let RawString = terms["RawString"]!
		return ExternalTokenizer { input, _ in
			if isNum(input.next) {
				var isFloat = false
				repeat {
					input.advance()
				} while isNum_(input.next)
				if input.next == Dot {
					isFloat = true
					input.advance()
					if isNum(input.next) {
						repeat {
							input.advance()
						} while isNum_(input.next)
					} else if input.next == Dot || input.next > 0x7F || isWordChar(input.next) {
						return
					}
				}
				if input.next == _e || input.next == _E {
					isFloat = true
					input.advance()
					if input.next == Plus || input.next == Minus { input.advance() }
					if !isNum_(input.next) { return }
					repeat {
						input.advance()
					} while isNum_(input.next)
				}
				if input.next == _f {
					let after = input.peek(1)
					if (after == Zero + 3 && input.peek(2) == Zero + 2) ||
						(after == Zero + 6 && input.peek(2) == Zero + 4)
					{
						input.advance(3)
						isFloat = true
					} else {
						return
					}
				}
				if isFloat { input.acceptToken(Float) }
			} else if input.next == _b || input.next == _r {
				if input.next == _b { input.advance() }
				if input.next != _r { return }
				input.advance()
				var count = 0
				while input.next == Hash {
					count += 1; input.advance()
				}
				if input.next != Quote { return }
				input.advance()
				contentLoop: while true {
					if input.next < 0 { return }
					let isQuote = input.next == Quote
					input.advance()
					if isQuote {
						for _ in 0 ..< count {
							if input.next != Hash { continue contentLoop }
							input.advance()
						}
						input.acceptToken(RawString)
						return
					}
				}
			}
		}
	}

	if name == "closureParam" {
		let closureParamDelim = terms["closureParamDelim"]!
		return ExternalTokenizer { input, _ in
			if input.next == Pipe { input.acceptToken(closureParamDelim, endOffset: 1) }
		}
	}

	if name == "tpDelim" {
		let tpOpen = terms["tpOpen"]!
		let tpClose = terms["tpClose"]!
		return ExternalTokenizer { input, _ in
			if input.next == LessThan {
				input.acceptToken(tpOpen, endOffset: 1)
			} else if input.next == GreaterThan {
				input.acceptToken(tpClose, endOffset: 1)
			}
		}
	}

	fatalError("Unknown Rust external tokenizer: \(name)")
}

private nonisolated(unsafe) let definition = hlTags["definition"] as! (Tag) -> Tag
private nonisolated(unsafe) let functionMod = hlTags["function"] as! (Tag) -> Tag
private nonisolated(unsafe) let specialMod = hlTags["special"] as! (Tag) -> Tag

nonisolated(unsafe) let rustHighlighting = styleTags([
	"const macro_rules struct union enum type fn impl trait let static": hlTags["definitionKeyword"] as Any,
	"mod use crate": hlTags["moduleKeyword"] as Any,
	"pub unsafe async mut extern default move": hlTags["modifier"] as Any,
	"for if else loop while match continue break return await": hlTags["controlKeyword"] as Any,
	"as in ref": hlTags["operatorKeyword"] as Any,
	"where _ crate super dyn": hlKeyword,
	"self": hlTags["self"] as Any,
	"String": hlString,
	"Char": hlTags["character"] as Any,
	"RawString": specialMod(hlString),
	"Boolean": hlTags["bool"] as Any,
	"Identifier": hlTags["variableName"] as Any,
	"CallExpression/Identifier": functionMod(hlTags["variableName"] as! Tag),
	"BoundIdentifier": definition(hlTags["variableName"] as! Tag),
	"FunctionItem/BoundIdentifier": functionMod(definition(hlTags["variableName"] as! Tag)),
	"LoopLabel": hlTags["labelName"] as Any,
	"FieldIdentifier": hlPropertyName,
	"CallExpression/FieldExpression/FieldIdentifier": functionMod(hlPropertyName),
	"Lifetime": specialMod(hlTags["variableName"] as! Tag),
	"ScopeIdentifier": hlTags["namespace"] as Any,
	"TypeIdentifier": hlTypeName,
	"MacroInvocation/Identifier MacroInvocation/ScopedIdentifier/Identifier": hlTags["macroName"] as Any,
	"MacroInvocation/TypeIdentifier MacroInvocation/ScopedIdentifier/TypeIdentifier": hlTags["macroName"] as Any,
	"\"!\"": hlTags["macroName"] as Any,
	"UpdateOp": hlTags["updateOperator"] as Any,
	"LineComment": hlTags["lineComment"] as Any,
	"BlockComment": hlTags["blockComment"] as Any,
	"Integer": hlTags["integer"] as Any,
	"Float": hlTags["float"] as Any,
	"ArithOp": hlTags["arithmeticOperator"] as Any,
	"logicOp": hlTags["logicOperator"] as Any,
	"BitOp": hlTags["bitwiseOperator"] as Any,
	"CompareOp": hlTags["compareOperator"] as Any,
	"=": hlTags["definitionOperator"] as Any,
	".. ... => ->": hlPunctuation,
	"( )": hlTags["paren"] as Any,
	"[ ]": hlTags["squareBracket"] as Any,
	"{ }": hlTags["brace"] as Any,
	". DerefOp": hlTags["derefOperator"] as Any,
	"&": hlTags["operator"] as Any,
	", ; ::": hlTags["separator"] as Any,
	"Attribute/...": hlMeta,
])

public let rustParser: LRParser = {
	let externals: [String: TokenizerProtocol] = [
		"literalTokens": makeRustExternalTokenizer(name: "literalTokens", terms: RustParserData.termTable),
		"closureParam": makeRustExternalTokenizer(name: "closureParam", terms: RustParserData.termTable),
		"tpDelim": makeRustExternalTokenizer(name: "tpDelim", terms: RustParserData.termTable),
	]
	let spec = RustParserData.makeSpec(
		externals: externals,
		propSources: [rustHighlighting]
	)
	return LRParser(spec: spec)
}()
