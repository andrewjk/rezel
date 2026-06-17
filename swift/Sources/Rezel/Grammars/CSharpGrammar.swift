import Foundation

private let csQuote: Int = 34
private let csBackslash: Int = 92
private let csBraceL: Int = 123
private let csBraceR: Int = 125

func makeCSharpExternalTokenizer(name: String, terms: [String: Int]) -> TokenizerProtocol {
	if name == "interpString" {
		let content = terms["interpStringContent"]!
		let brace = terms["interpStringBrace"]!
		let end = terms["interpStringEnd"]!
		return ExternalTokenizer { input, _ in
			var i = 0
			while true {
				switch input.next {
				case -1:
					if i > 0 { input.acceptToken(content) }
					return
				case csQuote:
					if i > 0 { input.acceptToken(content) }
					else { input.acceptToken(end, endOffset: 1) }
					return
				case csBraceL:
					if input.peek(1) == csBraceL { input.acceptToken(content, endOffset: 2) }
					else { input.acceptToken(brace) }
					return
				case csBraceR:
					if input.peek(1) == csBraceR { input.acceptToken(content, endOffset: 2) }
					return
				case csBackslash:
					let next = input.peek(1)
					if next == csBraceL || next == csBraceR { return }
					input.advance()
					fallthrough
				default:
					input.advance()
				}
				i += 1
			}
		}
	}

	if name == "interpVString" {
		let content = terms["interpVStringContent"]!
		let brace = terms["interpVStringBrace"]!
		let end = terms["interpVStringEnd"]!
		return ExternalTokenizer { input, _ in
			var i = 0
			while true {
				switch input.next {
				case -1:
					if i > 0 { input.acceptToken(content) }
					return
				case csQuote:
					if input.peek(1) == csQuote { input.acceptToken(content, endOffset: 2) }
					else if i > 0 { input.acceptToken(content) }
					else { input.acceptToken(end, endOffset: 1) }
					return
				case csBraceL:
					if input.peek(1) == csBraceL { input.acceptToken(content, endOffset: 2) }
					else { input.acceptToken(brace) }
					return
				case csBraceR:
					if input.peek(1) == csBraceR { input.acceptToken(content, endOffset: 2) }
					return
				default:
					input.advance()
				}
				i += 1
			}
		}
	}

	fatalError("Unknown C# external tokenizer: \(name)")
}

private nonisolated(unsafe) let constantMod = hlTags["constant"] as! (Tag) -> Tag
private nonisolated(unsafe) let functionMod = hlTags["function"] as! (Tag) -> Tag

nonisolated(unsafe) let csharpHighlighting = styleTags([
	"Keyword ContextualKeyword SimpleType": hlKeyword,
	"NullLiteral BooleanLiteral": hlTags["bool"] as Any,
	"IntegerLiteral": hlTags["integer"] as Any,
	"RealLiteral": hlTags["float"] as Any,
	"StringLiteral CharacterLiteral InterpolatedRegularString InterpolatedVerbatimString $\" @$\" $@\"": hlString,
	"LineComment BlockComment": hlTags["comment"] as Any,
	". .. : Astrisk Slash % + - ++ -- Not ~ << & | ^ && || < > <= >= == NotEq = += -= *= SlashEq %= &= |= ^= ? ?? ??= =>": hlTags["operator"] as Any,
	"PP_Directive": hlKeyword,
	"TypeIdentifier": hlTypeName,
	"ArgumentName AttrsNamedArg": hlTags["variableName"] as Any,
	"ConstName": constantMod(hlTags["variableName"] as! Tag),
	"MethodName": functionMod(hlTags["variableName"] as! Tag),
	"ParamName": [hlTags["emphasis"] as! Tag, hlTags["variableName"] as! Tag],
	"VarName": hlTags["variableName"] as Any,
	"FieldName PropertyName": hlPropertyName,
	"( )": hlTags["paren"] as Any,
	"{ }": hlTags["brace"] as Any,
	"[ ]": hlTags["squareBracket"] as Any,
])

public nonisolated(unsafe) let csharpParser: LRParser = {
	let externals: [String: TokenizerProtocol] = [
		"interpString": makeCSharpExternalTokenizer(name: "interpString", terms: CSharpParserData.termTable),
		"interpVString": makeCSharpExternalTokenizer(name: "interpVString", terms: CSharpParserData.termTable),
	]
	let spec = CSharpParserData.makeSpec(
		externals: externals,
		propSources: [csharpHighlighting]
	)
	return LRParser(spec: spec)
}()
