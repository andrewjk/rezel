import Foundation

private let space: [Int] = [9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200,
                            8201, 8202, 8232, 8233, 8239, 8287, 12288]

private let braceR = 125
private let semicolon = 59
private let slash = 47
private let star = 42
private let plus = 43
private let minus = 45
private let lt = 60
private let comma = 44
private let question = 63
private let dot = 46
private let bracketL = 91

nonisolated(unsafe) let jsTrackNewline = ContextTracker(
	start: false as Any,
	shift: { context, term, stack, _ in
		let name = stack.parser.termNames?[term] ?? ""
		if name == "LineComment" || name == "BlockComment" || name == "spaces" {
			return context
		}
		return (name == "newline") as Any
	},
	strict: false
)

func makeJsExternalTokenizer(name: String, terms: [String: Int]) -> TokenizerProtocol {
	if name == "insertSemicolon" {
		let insertSemi = terms["insertSemi"]!
		return ExternalTokenizer({ input, stack in
			let next = input.next
			if next == braceR || next == -1 || (stack.context as? Bool == true) {
				input.acceptToken(insertSemi)
			}
		}, contextual: true, fallback: true)
	}

	if name == "noSemicolon" {
		let noSemi = terms["noSemi"]!
		return ExternalTokenizer({ input, stack in
			let next = input.next
			if space.contains(next) { return }
			if next == slash {
				let after = input.peek(1)
				if after == slash || after == star { return }
			}
			if next != braceR, next != semicolon, next != -1, !(stack.context as? Bool == true) {
				input.acceptToken(noSemi)
			}
		}, contextual: true)
	}

	if name == "noSemicolonType" {
		let noSemiType = terms["noSemiType"]!
		return ExternalTokenizer({ input, stack in
			if input.next == bracketL, !(stack.context as? Bool == true) {
				input.acceptToken(noSemiType)
			}
		}, contextual: true)
	}

	if name == "operatorToken" {
		let incdec = terms["incdec"]!
		let incdecPrefix = terms["incdecPrefix"]!
		let questionDot = terms["questionDot"]!
		return ExternalTokenizer({ input, stack in
			let next = input.next
			if next == plus || next == minus {
				input.advance()
				if next == input.next {
					input.advance()
					let mayPostfix = !(stack.context as? Bool == true) && stack.canShift(incdec)
					input.acceptToken(mayPostfix ? incdec : incdecPrefix)
				}
			} else if next == question, input.peek(1) == dot {
				input.advance()
				input.advance()
				if input.next < 48 || input.next > 57 {
					input.acceptToken(questionDot)
				}
			}
		}, contextual: true)
	}

	if name == "jsx" {
		let JSXStartTag = terms["JSXStartTag"]!
		return ExternalTokenizer({ input, stack in
			if input.next != lt { return }
			let parser = stack.parser
			let keys = Array(parser.dialects.keys)
			let jsxIdx = keys.firstIndex(of: "jsx")
			if let jsxIdx = jsxIdx {
				if !stack.dialectEnabled(jsxIdx) { return }
			} else {
				return
			}
			input.advance()
			if input.next == slash { return }
			var back = 0
			while space.contains(input.next) {
				input.advance(); back += 1
			}
			if jsIdentifierChar(input.next, true) {
				input.advance()
				back += 1
				while jsIdentifierChar(input.next, false) {
					input.advance(); back += 1
				}
				while space.contains(input.next) {
					input.advance(); back += 1
				}
				if input.next == comma { return }
				let extendsStr = "extends"
				let extendsScalars = Array(extendsStr.unicodeScalars)
				for i in 0 ... extendsStr.count {
					if i == extendsStr.count {
						if !jsIdentifierChar(input.next, true) { return }
						break
					}
					if input.next != Int(extendsScalars[i].value) { break }
					input.advance()
					back += 1
				}
			}
			input.acceptToken(JSXStartTag, endOffset: -back)
		}, contextual: true)
	}

	fatalError("Unknown JS external tokenizer: \(name)")
}

private func jsIdentifierChar(_ ch: Int, _ start: Bool) -> Bool {
	return (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch == 95 || ch >= 192 ||
		(!start && ch >= 48 && ch <= 57)
}

private nonisolated(unsafe) let definition = hlTags["definition"] as! (Tag) -> Tag
private nonisolated(unsafe) let functionMod = hlTags["function"] as! (Tag) -> Tag
private nonisolated(unsafe) let specialMod = hlTags["special"] as! (Tag) -> Tag
private nonisolated(unsafe) let standardMod = hlTags["standard"] as! (Tag) -> Tag

nonisolated(unsafe) let jsHighlighting = styleTags([
	"get set async static": hlTags["modifier"] as Any,
	"for while do if else switch try catch finally return throw break continue default case defer": hlTags["controlKeyword"] as Any,
	"in of await yield void typeof delete instanceof as satisfies": hlTags["operatorKeyword"] as Any,
	"let var const using function class extends": hlTags["definitionKeyword"] as Any,
	"import export from": hlTags["moduleKeyword"] as Any,
	"with debugger new": hlKeyword,
	"TemplateString": specialMod(hlString),
	"super": hlTags["atom"] as Any,
	"BooleanLiteral": hlTags["bool"] as Any,
	"this": hlTags["self"] as Any,
	"null": hlTags["null"] as Any,
	"Star": hlTags["modifier"] as Any,
	"VariableName": hlTags["variableName"] as Any,
	"CallExpression/VariableName TaggedTemplateExpression/VariableName": functionMod(hlTags["variableName"] as! Tag),
	"VariableDefinition": definition(hlTags["variableName"] as! Tag),
	"Label": hlTags["labelName"] as Any,
	"PropertyName": hlPropertyName,
	"PrivatePropertyName": specialMod(hlPropertyName),
	"CallExpression/MemberExpression/PropertyName": functionMod(hlPropertyName),
	"FunctionDeclaration/VariableDefinition": functionMod(definition(hlTags["variableName"] as! Tag)),
	"ClassDeclaration/VariableDefinition": definition(hlTags["className"] as! Tag),
	"NewExpression/VariableName": hlTags["className"] as Any,
	"PropertyDefinition": definition(hlPropertyName),
	"PrivatePropertyDefinition": definition(specialMod(hlPropertyName)),
	"UpdateOp": hlTags["updateOperator"] as Any,
	"LineComment Hashbang": hlTags["lineComment"] as Any,
	"BlockComment": hlTags["blockComment"] as Any,
	"Number": hlNumber,
	"String": hlString,
	"Escape": hlTags["escape"] as Any,
	"ArithOp": hlTags["arithmeticOperator"] as Any,
	"LogicOp": hlTags["logicOperator"] as Any,
	"BitOp": hlTags["bitwiseOperator"] as Any,
	"CompareOp": hlTags["compareOperator"] as Any,
	"RegExp": hlTags["regexp"] as Any,
	"Equals": hlTags["definitionOperator"] as Any,
	"Arrow": functionMod(hlPunctuation),
	": Spread": hlPunctuation,
	"( )": hlTags["paren"] as Any,
	"[ ]": hlTags["squareBracket"] as Any,
	"{ }": hlTags["brace"] as Any,
	"InterpolationStart InterpolationEnd": specialMod(hlTags["brace"] as! Tag),
	".": hlTags["derefOperator"] as Any,
	", ;": hlTags["separator"] as Any,
	"@": hlMeta,
	"TypeName": hlTypeName,
	"TypeDefinition": definition(hlTypeName),
	"type enum interface implements namespace module declare": hlTags["definitionKeyword"] as Any,
	"abstract global Privacy readonly override": hlTags["modifier"] as Any,
	"is keyof unique infer asserts": hlTags["operatorKeyword"] as Any,
	"JSXAttributeValue": hlTags["attributeValue"] as Any,
	"JSXText": hlContent,
	"JSXStartTag JSXStartCloseTag JSXSelfCloseEndTag JSXEndTag": hlTags["angleBracket"] as Any,
	"JSXIdentifier JSXNamespacedName": hlTags["tagName"] as Any,
	"JSXAttribute/JSXIdentifier JSXAttribute/JSXNamespacedName": hlTags["attributeName"] as Any,
	"JSXBuiltin/JSXIdentifier": standardMod(hlTags["tagName"] as! Tag),
])

public nonisolated(unsafe) let javaScriptParser: LRParser = {
	let spec = JavaScriptParserData.makeSpec(
		externals: [
			"insertSemicolon": makeJsExternalTokenizer(name: "insertSemicolon", terms: JavaScriptParserData.termTable),
			"noSemicolon": makeJsExternalTokenizer(name: "noSemicolon", terms: JavaScriptParserData.termTable),
			"noSemicolonType": makeJsExternalTokenizer(name: "noSemicolonType", terms: JavaScriptParserData.termTable),
			"operatorToken": makeJsExternalTokenizer(name: "operatorToken", terms: JavaScriptParserData.termTable),
			"jsx": makeJsExternalTokenizer(name: "jsx", terms: JavaScriptParserData.termTable),
		],
		propSources: [jsHighlighting],
		context: jsTrackNewline
	)
	return LRParser(spec: spec)
}()
