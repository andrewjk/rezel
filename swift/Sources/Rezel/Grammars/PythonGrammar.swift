import Foundation

// MARK: - Character constants

private let newline = 10
private let carriageReturn = 13
private let space = 32
private let tab = 9
private let hash = 35
private let parenOpen = 40
private let dot = 46
private let braceOpen = 123
private let braceClose = 125
private let singleQuote = 39
private let doubleQuote = 34
private let backslash = 92
private let letter_o = 111
private let letter_x = 120
private let letter_N = 78
private let letter_u = 117
private let letter_U = 85

// MARK: - Flags

private let cx_Bracketed = 1
private let cx_String = 2
private let cx_DoubleQuote = 4
private let cx_Long = 8
private let cx_Raw = 16
private let cx_Format = 32

// MARK: - Helpers

private func isLineBreak(_ ch: Int) -> Bool {
	ch == newline || ch == carriageReturn
}

private func isHex(_ ch: Int) -> Bool {
	(ch >= 48 && ch <= 57) || (ch >= 65 && ch <= 70) || (ch >= 97 && ch <= 102)
}

private func isWordChar(_ ch: Int) -> Bool {
	guard let scalar = UnicodeScalar(ch) else { return false }
	return scalar.properties.isAlphabetic || (ch >= 48 && ch <= 57) || ch == 95
}

private func countIndent(_ s: String) -> Int {
	var depth = 0
	for ch in s.unicodeScalars {
		if ch == "\t" {
			depth += 8 - (depth % 8)
		} else {
			depth += 1
		}
	}
	return depth
}

private func skipEscape(_ input: InputStream, _ ch: Int) {
	if ch == letter_o {
		var i = 0
		while i < 2, input.next >= 48, input.next <= 55 {
			input.advance(); i += 1
		}
	} else if ch == letter_x {
		var i = 0
		while i < 2, isHex(input.next) {
			input.advance(); i += 1
		}
	} else if ch == letter_u {
		var i = 0
		while i < 4, isHex(input.next) {
			input.advance(); i += 1
		}
	} else if ch == letter_U {
		var i = 0
		while i < 8, isHex(input.next) {
			input.advance(); i += 1
		}
	} else if ch == letter_N {
		if input.next == braceOpen {
			input.advance()
			while input.next >= 0, input.next != braceClose, input.next != singleQuote,
			      input.next != doubleQuote, input.next != newline
			{
				input.advance()
			}
			if input.next == braceClose { input.advance() }
		}
	}
}

// MARK: - Context

private class PythonContext {
	let parent: PythonContext?
	let indent: Int
	let flags: Int
	let hashValue: Int

	init(parent: PythonContext?, indent: Int, flags: Int) {
		self.parent = parent
		self.indent = indent
		self.flags = flags
		let parentHash = parent?.hashValue ?? 0
		hashValue = parentHash &+ (parentHash << 8) &+ indent &+ (indent << 4) &+ flags &+ (flags << 6)
	}
}

private nonisolated(unsafe) let pythonTopContext = PythonContext(parent: nil, indent: 0, flags: 0)

// MARK: - Term name sets / maps

private let pythonBracketedNames: Set<String> = [
	"ParenthesizedExpression", "TupleExpression", "ComprehensionExpression",
	"importList", "ArgList", "ParamList",
	"ArrayExpression", "ArrayComprehensionExpression", "subscript",
	"SetExpression", "SetComprehensionExpression",
	"FormatString", "FormatReplacement", "nestedFormatReplacement",
	"DictionaryExpression", "DictionaryComprehensionExpression",
	"SequencePattern", "MappingPattern", "PatternArgList", "TypeParamList",
]

// The opening bracket tokens `(`, `[`, `{` are anonymous terms named by their literal value.
private let pythonBracketOpenNames: Set<String> = ["\"(\"", "\"[\"", "\"{\""]

private let pythonStringFlags: [String: Int] = [
	"stringStart": cx_String,
	"stringStartD": cx_String | cx_DoubleQuote,
	"stringStartL": cx_String | cx_Long,
	"stringStartLD": cx_String | cx_Long | cx_DoubleQuote,
	"stringStartR": cx_String | cx_Raw,
	"stringStartRD": cx_String | cx_Raw | cx_DoubleQuote,
	"stringStartRL": cx_String | cx_Raw | cx_Long,
	"stringStartRLD": cx_String | cx_Raw | cx_Long | cx_DoubleQuote,
	"stringStartF": cx_String | cx_Format,
	"stringStartFD": cx_String | cx_Format | cx_DoubleQuote,
	"stringStartFL": cx_String | cx_Format | cx_Long,
	"stringStartFLD": cx_String | cx_Format | cx_Long | cx_DoubleQuote,
	"stringStartFR": cx_String | cx_Format | cx_Raw,
	"stringStartFRD": cx_String | cx_Format | cx_Raw | cx_DoubleQuote,
	"stringStartFRL": cx_String | cx_Format | cx_Raw | cx_Long,
	"stringStartFRLD": cx_String | cx_Format | cx_Raw | cx_Long | cx_DoubleQuote,
]

// MARK: - Context tracker

nonisolated(unsafe) let pythonTrackIndent = ContextTracker(
	start: pythonTopContext as Any,
	shift: { context, term, stack, input in
		guard let cx = context as? PythonContext else { return context }
		let name = stack.parser.termNames?[term] ?? ""
		if name == "indent" {
			let indentStr = input.read(from: input.pos, to: stack.pos)
			return PythonContext(parent: cx, indent: countIndent(indentStr), flags: 0) as Any
		}
		if name == "dedent" {
			return (cx.parent ?? pythonTopContext) as Any
		}
		if pythonBracketOpenNames.contains(name) || name == "replacementStart" {
			return PythonContext(parent: cx, indent: 0, flags: cx_Bracketed) as Any
		}
		if let flags = pythonStringFlags[name] {
			return PythonContext(parent: cx, indent: 0, flags: flags | (cx.flags & cx_Bracketed)) as Any
		}
		return context
	},
	reduce: { context, term, stack, _ in
		guard let cx = context as? PythonContext else { return context }
		let name = stack.parser.termNames?[term] ?? ""
		if (cx.flags & cx_Bracketed) != 0, pythonBracketedNames.contains(name) {
			return (cx.parent ?? pythonTopContext) as Any
		}
		if name == "String" || name == "FormatString", (cx.flags & cx_String) != 0 {
			return (cx.parent ?? pythonTopContext) as Any
		}
		return context
	},
	hash: { context in
		(context as? PythonContext)?.hashValue ?? 0
	}
)

// MARK: - External tokenizers

private func makePythonExternalTokenizer(name: String, terms: [String: Int]) -> TokenizerProtocol {
	if name == "newlines" {
		let eofT = terms["eof"]!
		let newlineBracketedT = terms["newlineBracketed"]!
		let blankLineStartT = terms["blankLineStart"]!
		let newlineT = terms["newline"]!
		return ExternalTokenizer({ input, stack in
			let flags = (stack.context as? PythonContext)?.flags ?? 0
			if input.next < 0 {
				input.acceptToken(eofT)
			} else if (flags & cx_Bracketed) != 0 {
				if isLineBreak(input.next) {
					input.acceptToken(newlineBracketedT, endOffset: 1)
				}
			} else {
				let prev = input.peek(-1)
				if prev < 0 || isLineBreak(prev), stack.canShift(blankLineStartT) {
					var spaces = 0
					while input.next == space || input.next == tab {
						input.advance()
						spaces += 1
					}
					if input.next == newline || input.next == carriageReturn || input.next == hash {
						input.acceptToken(blankLineStartT, endOffset: -spaces)
					}
				} else if isLineBreak(input.next) {
					input.acceptToken(newlineT, endOffset: 1)
				}
			}
		}, contextual: true)
	}

	if name == "indentation" {
		let dedentT = terms["dedent"]!
		let indentT = terms["indent"]!
		return ExternalTokenizer { input, stack in
			guard let cx = stack.context as? PythonContext else { return }
			if cx.flags != 0 { return }
			let prev = input.peek(-1)
			if prev == newline || prev == carriageReturn {
				var depth = 0
				var chars = 0
				while true {
					if input.next == space {
						depth += 1
					} else if input.next == tab {
						depth += 8 - (depth % 8)
					} else {
						break
					}
					input.advance()
					chars += 1
				}
				if depth != cx.indent,
				   input.next != newline, input.next != carriageReturn, input.next != hash
				{
					if depth < cx.indent {
						input.acceptToken(dedentT, endOffset: -chars)
					} else {
						input.acceptToken(indentT)
					}
				}
			}
		}
	}

	if name == "legacyPrint" {
		let printKeywordT = terms["printKeyword"]!
		let printChars: [Int] = [112, 114, 105, 110, 116] // "print"
		return ExternalTokenizer { input, _ in
			for i in 0 ..< 5 {
				if input.next != printChars[i] { return }
				input.advance()
			}
			if isWordChar(input.next) { return }
			var off = 0
			while true {
				let next = input.peek(off)
				if next == space || next == tab { off += 1; continue }
				if next != parenOpen, next != dot, next != newline,
				   next != carriageReturn, next != hash
				{
					input.acceptToken(printKeywordT)
				}
				return
			}
		}
	}

	if name == "strings" {
		let stringEndT = terms["stringEnd"]!
		let stringContentT = terms["stringContent"]!
		let escapeT = terms["Escape"]!
		let replacementStartT = terms["replacementStart"]!
		return ExternalTokenizer { input, stack in
			guard let cx = stack.context as? PythonContext else { return }
			let flags = cx.flags
			let quote = (flags & cx_DoubleQuote) != 0 ? doubleQuote : singleQuote
			let isLong = (flags & cx_Long) != 0
			let escapes = (flags & cx_Raw) == 0
			let format = (flags & cx_Format) != 0

			let start = input.pos
			scan: while true {
				if input.next < 0 {
					break scan
				} else if format, input.next == braceOpen {
					if input.peek(1) == braceOpen {
						input.advance(2)
					} else {
						if input.pos == start {
							input.acceptToken(replacementStartT, endOffset: 1)
							return
						}
						break scan
					}
				} else if escapes, input.next == backslash {
					if input.pos == start {
						input.advance()
						let escaped = input.next
						if escaped >= 0 {
							input.advance()
							skipEscape(input, escaped)
						}
						input.acceptToken(escapeT)
						return
					}
					break scan
				} else if input.next == backslash, !escapes, input.peek(1) > -1 {
					input.advance(2)
				} else if input.next == quote, !isLong || (input.peek(1) == quote && input.peek(2) == quote) {
					if input.pos == start {
						input.acceptToken(stringEndT, endOffset: isLong ? 3 : 1)
						return
					}
					break scan
				} else if input.next == newline {
					if isLong {
						input.advance()
					} else if input.pos == start {
						input.acceptToken(stringEndT)
						return
					}
					break scan
				} else {
					input.advance()
				}
			}
			if input.pos > start { input.acceptToken(stringContentT) }
		}
	}

	fatalError("Unknown Python external tokenizer: \(name)")
}

// MARK: - Highlighting

private nonisolated(unsafe) let definition = hlTags["definition"] as! (Tag) -> Tag
private nonisolated(unsafe) let functionMod = hlTags["function"] as! (Tag) -> Tag
private nonisolated(unsafe) let specialMod = hlTags["special"] as! (Tag) -> Tag

nonisolated(unsafe) let pythonHighlighting = styleTags([
	"async \"*\" \"**\" FormatConversion FormatSpec": hlTags["modifier"] as Any,
	"for while if elif else try except finally return raise break continue with pass assert await yield match case": hlTags["controlKeyword"] as Any,
	"in not and or is del": hlTags["operatorKeyword"] as Any,
	"from def class global nonlocal lambda": hlTags["definitionKeyword"] as Any,
	"import": hlTags["moduleKeyword"] as Any,
	"with as print": hlKeyword,
	"Boolean": hlTags["bool"] as Any,
	"None": hlTags["null"] as Any,
	"VariableName": hlTags["variableName"] as Any,
	"CallExpression/VariableName": functionMod(hlTags["variableName"] as! Tag),
	"FunctionDefinition/VariableName": functionMod(definition(hlTags["variableName"] as! Tag)),
	"ClassDefinition/VariableName": definition(hlTags["className"] as! Tag),
	"PropertyName": hlPropertyName,
	"CallExpression/MemberExpression/PropertyName": functionMod(hlPropertyName),
	"Comment": hlTags["lineComment"] as Any,
	"Number": hlNumber,
	"String": hlString,
	"FormatString": specialMod(hlString),
	"Escape": hlTags["escape"] as Any,
	"UpdateOp": hlTags["updateOperator"] as Any,
	"ArithOp!": hlTags["arithmeticOperator"] as Any,
	"BitOp": hlTags["bitwiseOperator"] as Any,
	"CompareOp": hlTags["compareOperator"] as Any,
	"AssignOp": hlTags["definitionOperator"] as Any,
	"Ellipsis": hlPunctuation,
	"At": hlMeta,
	"( )": hlTags["paren"] as Any,
	"[ ]": hlTags["squareBracket"] as Any,
	"{ }": hlTags["brace"] as Any,
	".": hlTags["derefOperator"] as Any,
	", ;": hlTags["separator"] as Any,
])

// MARK: - Parser

public nonisolated(unsafe) let pythonParser: LRParser = {
	let externals: [String: TokenizerProtocol] = [
		"newlines": makePythonExternalTokenizer(name: "newlines", terms: PythonParserData.termTable),
		"indentation": makePythonExternalTokenizer(name: "indentation", terms: PythonParserData.termTable),
		"legacyPrint": makePythonExternalTokenizer(name: "legacyPrint", terms: PythonParserData.termTable),
		"strings": makePythonExternalTokenizer(name: "strings", terms: PythonParserData.termTable),
	]
	let spec = PythonParserData.makeSpec(
		externals: externals,
		propSources: [pythonHighlighting],
		context: pythonTrackIndent
	)
	return LRParser(spec: spec)
}()
