import Foundation

nonisolated(unsafe) let bashHighlighting = styleTags([
	"while do done until for in case esac if then elif else fi": hlTags["controlKeyword"] as Any,
	"IORedirect": hlTags["operator"] as Any,
	"&& || |": hlTags["logicOperator"] as Any,
	"= +=": hlTags["operator"] as Any,
	"( )": hlTags["paren"] as Any,
	"[ ]": hlTags["squareBracket"] as Any,
	"{ }": hlTags["brace"] as Any,
	"${": hlTags["brace"] as Any,
	"$(": hlTags["paren"] as Any,
	"RawString": hlString,
	"String": hlString,
	"AnsiCString": hlString,
	"VariableName": hlTags["variableName"] as Any,
	"EnvironmentVariable": hlTags["variableName"] as Any,
	"Functionname": hlTags["variableName"] as Any,
	"Comment": hlComment,
	"CommandName": hlName,
	"; &": hlTags["separator"] as Any,
])

public let bashParser: LRParser = {
	let spec = BashParserData.makeSpec(
		externals: [:],
		propSources: [bashHighlighting]
	)
	return LRParser(spec: spec)
}()
