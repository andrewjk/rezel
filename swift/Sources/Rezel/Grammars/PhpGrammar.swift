import Foundation

// MARK: - Character constants

private let tab = 9
private let lf = 10
private let cr = 13
private let space = 32
private let singleQuote = 39
private let parenOpen = 40
private let parenClose = 41
private let dash = 45
private let digit0 = 48
private let digit7 = 55
private let lt = 60
private let gt = 62
private let question = 63
private let uppercaseA = 65
private let uppercaseZ = 90
private let bracketOpen = 91
private let backslash = 92
private let underscore = 95
private let lowercaseA = 97
private let lowercaseZ = 122
private let letter_e = 101
private let letter_f = 102
private let letter_n = 110
private let letter_r = 114
private let letter_t = 116
private let letter_u = 117
private let letter_v = 118
private let letter_x = 120
private let braceOpen = 123
private let braceClose = 125
private let doubleQuote = 34
private let dollar = 36

// MARK: - Helpers

private func isPhpSpace(_ ch: Int) -> Bool {
	ch == tab || ch == lf || ch == cr || ch == space
}

private func isPhpASCIILetter(_ ch: Int) -> Bool {
	(ch >= lowercaseA && ch <= lowercaseZ) || (ch >= uppercaseA && ch <= uppercaseZ)
}

private func isPhpIdentifierStart(_ ch: Int) -> Bool {
	ch == underscore || ch >= 0x80 || isPhpASCIILetter(ch)
}

private func isPhpHex(_ ch: Int) -> Bool {
	(ch >= digit0 && ch <= digit7) || (ch >= lowercaseA && ch <= 102) || (ch >= uppercaseA && ch <= 70)
}

private let phpCastTypes: Set<String> = [
	"int", "integer", "bool", "boolean", "float", "double", "real",
	"string", "array", "object", "unset",
]

// MARK: - Escape scanning

private func phpScanEscape(_ input: InputStream) -> Int {
	let after = input.peek(1)
	if after == letter_n || after == letter_r || after == letter_t ||
		after == letter_v || after == letter_e || after == letter_f ||
		after == backslash || after == dollar || after == doubleQuote ||
		after == braceOpen
	{
		return 2
	}

	if after >= digit0 && after <= digit7 {
		var size = 2
		while size < 5 {
			let next = input.peek(size)
			if next >= digit0 && next <= digit7 { size += 1 } else { break }
		}
		return size
	}

	if after == letter_x && isPhpHex(input.peek(2)) {
		return isPhpHex(input.peek(3)) ? 4 : 3
	}

	if after == letter_u && input.peek(2) == braceOpen {
		var size = 3
		while true {
			let next = input.peek(size)
			if next == braceClose { return size == 2 ? 0 : size + 1 }
			if !isPhpHex(next) { break }
			size += 1
		}
	}

	return 0
}

// MARK: - External tokenizers

private func makePhpExternalTokenizer(name: String, terms: [String: Int]) -> TokenizerProtocol {
	if name == "expression" {
		let castOpenT = terms["castOpen"]!
		let heredocStringT = terms["HeredocString"]!
		return ExternalTokenizer { input, _ in
			if input.next == parenOpen {
				input.advance()
				var peek = 0
				while isPhpSpace(input.peek(peek)) {
					peek += 1
				}
				var name = ""
				var next = input.peek(peek)
				while isPhpASCIILetter(next) {
					name += String(UnicodeScalar(next)!)
					peek += 1
					next = input.peek(peek)
				}
				while isPhpSpace(input.peek(peek)) {
					peek += 1
				}
				if input.peek(peek) == parenClose && phpCastTypes.contains(name.lowercased()) {
					input.acceptToken(castOpenT)
				}
			} else if input.next == lt && input.peek(1) == lt && input.peek(2) == lt {
				for _ in 0 ..< 3 {
					input.advance()
				}
				while input.next == space || input.next == tab {
					input.advance()
				}
				let quoted = input.next == singleQuote
				if quoted { input.advance() }
				if !isPhpIdentifierStart(input.next) { return }
				var tag: [Int] = [input.next]
				while true {
					input.advance()
					if !isPhpIdentifierStart(input.next) && !(input.next >= digit0 && input.next <= digit7) { break }
					tag.append(input.next)
				}
				if quoted {
					if input.next != singleQuote { return }
					input.advance()
				}
				if input.next != lf && input.next != cr { return }
				while true {
					let lineStart = input.next == lf || input.next == cr
					input.advance()
					if input.next < 0 { return }
					if lineStart {
						while input.next == space || input.next == tab {
							input.advance()
						}
						var match = true
						for i in 0 ..< tag.count {
							if input.next != tag[i] { match = false; break }
							input.advance()
						}
						if match {
							input.acceptToken(heredocStringT)
							return
						}
					}
				}
			}
		}
	}

	if name == "interpolated" {
		let escapeSequenceT = terms["EscapeSequence"]!
		let interpolatedStringContentT = terms["interpolatedStringContent"]!
		let afterInterpolationT = terms["afterInterpolation"]!
		return ExternalTokenizer { input, stack in
			var content = false
			while true {
				if input.next == doubleQuote || input.next < 0 ||
					(input.next == dollar && (isPhpIdentifierStart(input.peek(1)) || input.peek(1) == braceOpen)) ||
					(input.next == braceOpen && input.peek(1) == dollar)
				{
					break
				} else if input.next == backslash {
					let escaped = phpScanEscape(input)
					if escaped > 0 {
						if content { break }
						else {
							input.acceptToken(escapeSequenceT, endOffset: escaped)
							return
						}
					}
				} else if !content && (
					input.next == bracketOpen ||
						(input.next == dash && input.peek(1) == gt && isPhpIdentifierStart(input.peek(2))) ||
						(input.next == question && input.peek(1) == dash && input.peek(2) == gt && isPhpIdentifierStart(input.peek(3)))
				) && stack.canShift(afterInterpolationT) {
					break
				}
				input.advance()
				content = true
			}
			if content { input.acceptToken(interpolatedStringContentT) }
		}
	}

	if name == "semicolon" {
		let automaticSemicolonT = terms["automaticSemicolon"]!
		return ExternalTokenizer { input, stack in
			if input.next == question && stack.canShift(automaticSemicolonT) && input.peek(1) == gt {
				input.acceptToken(automaticSemicolonT)
			}
		}
	}

	if name == "eofToken" {
		let eofT = terms["eof"]!
		return ExternalTokenizer { input, _ in
			if input.next < 0 { input.acceptToken(eofT) }
		}
	}

	fatalError("Unknown PHP external tokenizer: \(name)")
}

// MARK: - Keyword specializer

private func buildPhpKeywordMap(_ terms: [String: Int]) -> [String: Int] {
	var m: [String: Int] = [:]
	let directKeywords: [String] = [
		"abstract", "and", "array", "as", "break", "case", "catch", "clone",
		"const", "continue", "default", "declare", "do", "echo", "else", "elseif",
		"enddeclare", "endfor", "endforeach", "endif", "endswitch", "endwhile",
		"enum", "extends", "final", "finally", "fn", "for", "foreach", "from",
		"function", "global", "goto", "if", "implements", "include", "include_once",
		"instanceof", "insteadof", "interface", "list", "match", "namespace",
		"new", "null", "or", "print", "readonly", "require", "require_once",
		"return", "switch", "throw", "trait", "try", "unset", "use", "var",
		"while", "xor", "yield",
	]
	for kw in directKeywords {
		m[kw] = terms[kw]
	}
	let boolean = terms["Boolean"]!
	m["true"] = boolean
	m["false"] = boolean
	let visibility = terms["Visibility"]!
	m["public"] = visibility
	m["private"] = visibility
	m["protected"] = visibility
	return m
}

// MARK: - Highlighting

private nonisolated(unsafe) let definition = hlTags["definition"] as! (Tag) -> Tag
private nonisolated(unsafe) let functionMod = hlTags["function"] as! (Tag) -> Tag
private nonisolated(unsafe) let specialMod = hlTags["special"] as! (Tag) -> Tag

nonisolated(unsafe) let phpHighlighting = styleTags([
	"Visibility abstract final static": hlTags["modifier"] as Any,
	"for foreach while do if else elseif switch try catch finally return throw break continue default case": hlTags["controlKeyword"] as Any,
	"endif endfor endforeach endswitch endwhile declare enddeclare goto match": hlTags["controlKeyword"] as Any,
	"and or xor yield unset clone instanceof insteadof": hlTags["operatorKeyword"] as Any,
	"function fn class trait implements extends const enum global interface use var": hlTags["definitionKeyword"] as Any,
	"include include_once require require_once namespace": hlTags["moduleKeyword"] as Any,
	"new from echo print array list as": hlKeyword,
	"null": hlTags["null"] as Any,
	"Boolean": hlTags["bool"] as Any,
	"VariableName": hlTags["variableName"] as Any,
	"NamespaceName/...": hlTags["namespace"] as Any,
	"NamedType/...": hlTypeName,
	"Name": hlName,
	"CallExpression/Name": functionMod(hlTags["variableName"] as! Tag),
	"LabelStatement/Name": hlTags["labelName"] as Any,
	"MemberExpression/Name": hlPropertyName,
	"MemberExpression/VariableName": specialMod(hlPropertyName),
	"ScopedExpression/ClassMemberName/Name": hlPropertyName,
	"ScopedExpression/ClassMemberName/VariableName": specialMod(hlPropertyName),
	"CallExpression/MemberExpression/Name": functionMod(hlPropertyName),
	"CallExpression/ScopedExpression/ClassMemberName/Name": functionMod(hlPropertyName),
	"MethodDeclaration/Name": functionMod(definition(hlTags["variableName"] as! Tag)),
	"FunctionDefinition/Name": functionMod(definition(hlTags["variableName"] as! Tag)),
	"ClassDeclaration/Name": definition(hlTags["className"] as! Tag),
	"UpdateOp": hlTags["updateOperator"] as Any,
	"ArithOp": hlTags["arithmeticOperator"] as Any,
	"LogicOp IntersectionType/&": hlTags["logicOperator"] as Any,
	"BitOp": hlTags["bitwiseOperator"] as Any,
	"CompareOp": hlTags["compareOperator"] as Any,
	"ControlOp": hlTags["controlOperator"] as Any,
	"AssignOp": hlTags["definitionOperator"] as Any,
	"$ ConcatOp": hlOperator,
	"LineComment": hlTags["lineComment"] as Any,
	"BlockComment": hlTags["blockComment"] as Any,
	"Integer": hlTags["integer"] as Any,
	"Float": hlTags["float"] as Any,
	"String": hlString,
	"ShellExpression": specialMod(hlString),
	"=> ->": hlPunctuation,
	"( )": hlTags["paren"] as Any,
	"#[ [ ]": hlTags["squareBracket"] as Any,
	"${ { }": hlTags["brace"] as Any,
	"-> ?->": hlTags["derefOperator"] as Any,
	", ; :: : \\": hlTags["separator"] as Any,
	"PhpOpen PhpClose": hlTags["processingInstruction"] as Any,
])

// MARK: - Parser

public let phpParser: LRParser = {
	let keywordMap = buildPhpKeywordMap(PhpParserData.termTable)
	let externals: [String: TokenizerProtocol] = [
		"expression": makePhpExternalTokenizer(name: "expression", terms: PhpParserData.termTable),
		"interpolated": makePhpExternalTokenizer(name: "interpolated", terms: PhpParserData.termTable),
		"semicolon": makePhpExternalTokenizer(name: "semicolon", terms: PhpParserData.termTable),
		"eofToken": makePhpExternalTokenizer(name: "eofToken", terms: PhpParserData.termTable),
	]
	let specializedExternals: [String: (String, Stack) -> Int] = [
		"keywords": { name, _ in keywordMap[name.lowercased()] ?? -1 },
	]
	let spec = PhpParserData.makeSpec(
		externals: externals,
		specializedExternals: specializedExternals,
		propSources: [phpHighlighting]
	)
	return LRParser(spec: spec)
}()
