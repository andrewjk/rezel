import Foundation

private nonisolated(unsafe) let definition = hlTags["definition"] as! (Tag) -> Tag
private nonisolated(unsafe) let functionMod = hlTags["function"] as! (Tag) -> Tag

nonisolated(unsafe) let zigHighlighting = styleTags([
	"asm enum fn struct test union var": hlTags["definitionKeyword"] as Any,
	"comptime const continue defer errdefer export extern inline noalias noinline nosuspend pub resume": hlTags["modifier"] as Any,
	"addrspace align allowzero anyframe anytype callconv error linksection packed threadlocal unreachable volatile": hlTags["modifier"] as Any,
	"opaque": hlTags["modifier"] as Any,
	"if else switch for while case return break continue try": hlTags["controlKeyword"] as Any,
	"BlockLabel BreakLabel": hlTags["labelName"] as Any,
	"Identifier": hlTags["variableName"] as Any,
	"BuiltinIdentifier": hlKeyword,
	"Name": definition(hlTags["variableName"] as! Tag),
	"FnProto/Identifier": functionMod(definition(hlTags["variableName"] as! Tag)),
	"VarDeclProto/TypeExpr/Identifier FnProto/TypeExpr/Identifier ContainerField/TypeExpr/Identifier ParamType/TypeExpr/Identifier": hlTypeName,
	"AdditionOp": hlTags["arithmeticOperator"] as Any,
	"MultiplyOp": hlTags["arithmeticOperator"] as Any,
	"and or": hlTags["logicOperator"] as Any,
	"BitwiseOp": hlTags["bitwiseOperator"] as Any,
	"BitShiftOp": hlTags["bitwiseOperator"] as Any,
	"CompareOp": hlTags["compareOperator"] as Any,
	"AssignOp": hlTags["definitionOperator"] as Any,
	"UpdateOp": hlTags["updateOperator"] as Any,
	"ContainerDocComment": hlTags["lineComment"] as Any,
	"DocComment": hlTags["lineComment"] as Any,
	"LineComment": hlTags["lineComment"] as Any,
	"Integer": hlNumber,
	"StringLiteral": hlString,
	"StringLiteralSingle": hlString,
	"( )": hlTags["paren"] as Any,
	"[ ]": hlTags["squareBracket"] as Any,
	"{ }": hlTags["brace"] as Any,
	".*": hlTags["derefOperator"] as Any,
	", ;": hlTags["separator"] as Any,
])

public let zigParser: LRParser = {
	let spec = ZigParserData.makeSpec(
		externals: [:],
		propSources: [zigHighlighting]
	)
	return LRParser(spec: spec)
}()
