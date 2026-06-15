import Foundation

private let R = 82
private let L = 76
private let u = 117
private let U = 85
private let a = 97
private let z = 122
private let A = 65
private let Z = 90
private let Underscore = 95
private let Zero = 48
private let Quote = 34
private let ParenL = 40
private let ParenR = 41
private let Space = 32
private let Newline = 10
private let GreaterThan = 62

private func makeCppExternalTokenizer(name: String, terms: [String: Int]) -> TokenizerProtocol {
	if name == "rawString" {
		let RawString = terms["RawString"]!
		return ExternalTokenizer { input, _ in
			// Raw string literals can start with: R, LR, uR, UR, u8R
			if input.next == L || input.next == U {
				input.advance()
			} else if input.next == u {
				input.advance()
				if input.next == Zero + 8 { input.advance() }
			}
			if input.next != R { return }
			input.advance()
			if input.next != Quote { return }
			input.advance()

			var marker = ""
			while input.next != ParenL {
				if input.next == Space || input.next <= 13 || input.next == ParenR { return }
				marker += String(UnicodeScalar(input.next)!)
				input.advance()
			}
			input.advance()

			let markerCodes = marker.unicodeScalars.map { Int($0.value) }
			while true {
				if input.next < 0 {
					input.acceptToken(RawString)
					return
				}
				if input.next == ParenR {
					var match = true
					var i = 0
					while match && i < markerCodes.count {
						if input.peek(i + 1) != markerCodes[i] { match = false }
						i += 1
					}
					if match && input.peek(markerCodes.count + 1) == Quote {
						input.acceptToken(RawString, endOffset: 2 + markerCodes.count)
						return
					}
				}
				input.advance()
			}
		}
	}

	if name == "fallback" {
		let templateArgsEndFallback = terms["templateArgsEndFallback"]!
		let MacroName = terms["MacroName"]!
		return ExternalTokenizer({ input, _ in
			if input.next == GreaterThan {
				// Provide a template-args-closing token when the next characters
				// are ">>", in which case the regular tokenizer will only see a
				// bit shift op.
				if input.peek(1) == GreaterThan {
					input.acceptToken(templateArgsEndFallback, endOffset: 1)
				}
			} else {
				// Notice all-uppercase identifiers
				var sawLetter = false
				var i = 0
				while true {
					if input.next >= A, input.next <= Z {
						sawLetter = true
					} else if input.next >= a, input.next <= z {
						return
					} else if input.next != Underscore, !(input.next >= Zero && input.next <= Zero + 9) {
						break
					}
					input.advance()
					i += 1
				}
				if sawLetter, i > 1 {
					input.acceptToken(MacroName)
				}
			}
		}, extend: true)
	}

	fatalError("Unknown CPP external tokenizer: \(name)")
}

private nonisolated(unsafe) let definition = hlTags["definition"] as! (Tag) -> Tag
private nonisolated(unsafe) let functionMod = hlTags["function"] as! (Tag) -> Tag
private nonisolated(unsafe) let specialMod = hlTags["special"] as! (Tag) -> Tag
private nonisolated(unsafe) let standardMod = hlTags["standard"] as! (Tag) -> Tag

nonisolated(unsafe) let cppHighlighting = styleTags([
	"typedef struct union enum class typename decltype auto template operator friend noexcept namespace using requires concept import export module __attribute__ __declspec __based": hlTags["definitionKeyword"] as Any,
	"extern MsCallModifier MsPointerModifier extern static register thread_local inline const volatile restrict _Atomic mutable constexpr constinit consteval virtual explicit VirtualSpecifier Access": hlTags["modifier"] as Any,
	"if else switch for while do case default return break continue goto throw try catch": hlTags["controlKeyword"] as Any,
	"co_return co_yield co_await": hlTags["controlKeyword"] as Any,
	"new sizeof delete static_assert": hlTags["operatorKeyword"] as Any,
	"NULL nullptr": hlTags["null"] as Any,
	"this": hlTags["self"] as Any,
	"True False": hlTags["bool"] as Any,
	"TypeSize PrimitiveType": standardMod(hlTypeName),
	"TypeIdentifier": hlTypeName,
	"FieldIdentifier": hlPropertyName,
	"CallExpression/FieldExpression/FieldIdentifier": functionMod(hlPropertyName),
	"ModuleName/Identifier": hlTags["namespace"] as Any,
	"PartitionName": hlTags["labelName"] as Any,
	"StatementIdentifier": hlTags["labelName"] as Any,
	"Identifier DestructorName": hlTags["variableName"] as Any,
	"CallExpression/Identifier": functionMod(hlTags["variableName"] as! Tag),
	"CallExpression/ScopedIdentifier/Identifier": functionMod(hlTags["variableName"] as! Tag),
	"FunctionDeclarator/Identifier FunctionDeclarator/DestructorName": functionMod(definition(hlTags["variableName"] as! Tag)),
	"NamespaceIdentifier": hlTags["namespace"] as Any,
	"OperatorName": hlTags["operator"] as Any,
	"ArithOp": hlTags["arithmeticOperator"] as Any,
	"LogicOp": hlTags["logicOperator"] as Any,
	"BitOp": hlTags["bitwiseOperator"] as Any,
	"CompareOp": hlTags["compareOperator"] as Any,
	"AssignOp": hlTags["definitionOperator"] as Any,
	"UpdateOp": hlTags["updateOperator"] as Any,
	"LineComment": hlTags["lineComment"] as Any,
	"BlockComment": hlTags["blockComment"] as Any,
	"Number": hlNumber,
	"String": hlString,
	"RawString SystemLibString": specialMod(hlString),
	"CharLiteral": hlTags["character"] as Any,
	"EscapeSequence": hlTags["escape"] as Any,
	"UserDefinedLiteral/Identifier": hlTags["literal"] as Any,
	"PreprocArg": hlTags["meta"] as Any,
	"PreprocDirectiveName #include #ifdef #ifndef #if #define #else #endif #elif": hlTags["processingInstruction"] as Any,
	"MacroName": specialMod(hlName),
	"( )": hlTags["paren"] as Any,
	"[ ]": hlTags["squareBracket"] as Any,
	"{ }": hlTags["brace"] as Any,
	"< >": hlTags["angleBracket"] as Any,
	". ->": hlTags["derefOperator"] as Any,
	", ;": hlTags["separator"] as Any,
])

public nonisolated(unsafe) let cppParser: LRParser = {
	let externals: [String: TokenizerProtocol] = [
		"rawString": makeCppExternalTokenizer(name: "rawString", terms: CppParserData.termTable),
		"fallback": makeCppExternalTokenizer(name: "fallback", terms: CppParserData.termTable),
	]
	let spec = CppParserData.makeSpec(
		externals: externals,
		propSources: [cppHighlighting]
	)
	return LRParser(spec: spec)
}()
