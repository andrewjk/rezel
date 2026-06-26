import Foundation

func makeGoExternalTokenizer(name: String, terms: [String: Int]) -> TokenizerProtocol {
	if name == "semicolon" {
		let insertedSemi = terms["insertedSemi"]!
		let newline = 10, carriageReturn = 13, space = 32, tab = 9, slash = 47, closeParen = 41, closeBrace = 125
		return ExternalTokenizer({ input, stack in
			var scan = 0
			var next = input.next
			while true {
				if (stack.context as? Bool == true && (next < 0 || next == newline || next == carriageReturn ||
						next == slash && input.peek(scan + 1) == slash)) ||
					next == closeParen || next == closeBrace
				{
					input.acceptToken(insertedSemi)
				}
				if next != space, next != tab { break }
				scan += 1
				next = input.peek(scan)
			}
		}, contextual: true, fallback: true)
	}
	fatalError("Unknown Go external tokenizer: \(name)")
}

private nonisolated(unsafe) let definition = hlTags["definition"] as! (Tag) -> Tag
private nonisolated(unsafe) let functionMod = hlTags["function"] as! (Tag) -> Tag

nonisolated(unsafe) let goHighlighting = styleTags([
	"func interface struct chan map const type var": hlTags["definitionKeyword"] as Any,
	"import package": hlTags["moduleKeyword"] as Any,
	"switch for go select return break continue goto fallthrough case if else defer": hlTags["controlKeyword"] as Any,
	"range": hlKeyword,
	"Bool": hlTags["bool"] as Any,
	"String": hlString,
	"Rune": hlTags["character"] as Any,
	"Number": hlNumber,
	"Nil": hlTags["null"] as Any,
	"VariableName": hlTags["variableName"] as Any,
	"DefName": definition(hlTags["variableName"] as! Tag),
	"TypeName": hlTypeName,
	"LabelName": hlTags["labelName"] as Any,
	"FieldName": hlPropertyName,
	"FunctionDecl/DefName": functionMod(definition(hlTags["variableName"] as! Tag)),
	"TypeSpec/DefName": definition(hlTypeName),
	"CallExpr/VariableName": functionMod(hlTags["variableName"] as! Tag),
	"LineComment": hlTags["lineComment"] as Any,
	"BlockComment": hlTags["blockComment"] as Any,
	"LogicOp": hlTags["logicOperator"] as Any,
	"ArithOp": hlTags["arithmeticOperator"] as Any,
	"BitOp": hlTags["bitwiseOperator"] as Any,
	"DerefOp .": hlTags["derefOperator"] as Any,
	"UpdateOp IncDecOp": hlTags["updateOperator"] as Any,
	"CompareOp": hlTags["compareOperator"] as Any,
	"= :=": hlTags["definitionOperator"] as Any,
	"<-": hlTags["operator"] as Any,
	"~ \"*\"": hlTags["modifier"] as Any,
	"; ,": hlTags["separator"] as Any,
	"... :": hlPunctuation,
	"( )": hlTags["paren"] as Any,
	"[ ]": hlTags["squareBracket"] as Any,
	"{ }": hlTags["brace"] as Any,
])

public let goParser: LRParser = {
	let terms = GoParserData.termTable
	var trackedIds = Set<Int>()
	for name in ["IncDecOp", "identifier", "Rune", "String", "Number"] {
		if let id = terms[name] { trackedIds.insert(id) }
	}
	for kw in ["break", "continue", "return", "fallthrough"] {
		if let id = terms["identifier/\"\(kw)\""] { trackedIds.insert(id) }
	}
	for ch in ["\")\"", "\"]\"", "\"}\""] {
		if let id = terms[ch] { trackedIds.insert(id) }
	}
	let spaceId = terms["space"]
	let trackTokens = ContextTracker(
		start: false as Any,
		shift: { context, term, _, _ in
			if let sid = spaceId, term == sid { return context }
			return trackedIds.contains(term) as Any
		}
	)
	let externals: [String: TokenizerProtocol] = [
		"semicolon": makeGoExternalTokenizer(name: "semicolon", terms: terms),
	]
	let spec = GoParserData.makeSpec(
		externals: externals,
		propSources: [goHighlighting],
		context: trackTokens
	)
	return LRParser(spec: spec)
}()
