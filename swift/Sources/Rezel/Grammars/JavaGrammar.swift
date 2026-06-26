import Foundation

private nonisolated(unsafe) let definition = hlTags["definition"] as! (Tag) -> Tag
private nonisolated(unsafe) let functionMod = hlTags["function"] as! (Tag) -> Tag
private nonisolated(unsafe) let standardMod = hlTags["standard"] as! (Tag) -> Tag

nonisolated(unsafe) let javaHighlighting = styleTags([
	"null": hlTags["null"] as Any,
	"instanceof": hlTags["operatorKeyword"] as Any,
	"this": hlTags["self"] as Any,
	"new super assert open to with void": hlTags["keyword"] as Any,
	"class interface extends implements enum var": hlTags["definitionKeyword"] as Any,
	"module package import": hlTags["moduleKeyword"] as Any,
	"switch while for if else case default do break continue return try catch finally throw": hlTags["controlKeyword"] as Any,
	"requires exports opens uses provides public private protected static transitive abstract final strictfp synchronized native transient volatile throws": hlTags["modifier"] as Any,
	"IntegerLiteral": hlTags["integer"] as Any,
	"FloatingPointLiteral": hlTags["float"] as Any,
	"StringLiteral TextBlock": hlTags["string"] as Any,
	"CharacterLiteral": hlTags["character"] as Any,
	"LineComment": hlTags["lineComment"] as Any,
	"BlockComment": hlTags["blockComment"] as Any,
	"BooleanLiteral": hlTags["bool"] as Any,
	"PrimitiveType": standardMod(hlTypeName),
	"TypeName": hlTypeName,
	"Identifier": hlTags["variableName"] as Any,
	"MethodName/Identifier": functionMod(hlTags["variableName"] as! Tag),
	"Definition": definition(hlTags["variableName"] as! Tag),
	"ArithOp": hlTags["arithmeticOperator"] as Any,
	"LogicOp": hlTags["logicOperator"] as Any,
	"BitOp": hlTags["bitwiseOperator"] as Any,
	"CompareOp": hlTags["compareOperator"] as Any,
	"AssignOp": hlTags["definitionOperator"] as Any,
	"UpdateOp": hlTags["updateOperator"] as Any,
	"Asterisk": hlPunctuation,
	"Label": hlTags["labelName"] as Any,
	"( )": hlTags["paren"] as Any,
	"[ ]": hlTags["squareBracket"] as Any,
	"{ }": hlTags["brace"] as Any,
	".": hlTags["derefOperator"] as Any,
	", ;": hlTags["separator"] as Any,
])

public let javaParser: LRParser = {
	let spec = JavaParserData.makeSpec(
		externals: [:],
		propSources: [javaHighlighting]
	)
	return LRParser(spec: spec)
}()
