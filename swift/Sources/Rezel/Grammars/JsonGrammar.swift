import Foundation

private nonisolated(unsafe) let jsonHighlighting = styleTags([
	"String": hlString,
	"Number": hlNumber,
	"True False": (hlTags["bool"] as! Tag),
	"PropertyName": hlPropertyName,
	"Null": (hlTags["null"] as! Tag),
	", :": (hlTags["separator"] as! Tag),
	"[ ]": (hlTags["squareBracket"] as! Tag),
	"{ }": (hlTags["brace"] as! Tag),
])

public let jsonParser: LRParser = {
	let spec = JsonParserData.makeSpec(
		externals: [:],
		propSources: [jsonHighlighting]
	)
	return LRParser(spec: spec)
}()
