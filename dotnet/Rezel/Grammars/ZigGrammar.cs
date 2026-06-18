using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class ZigGrammar
{
    private static readonly NodePropSource ZigHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["asm enum fn struct test union var"] = Tags.DefinitionKeyword,
        ["comptime const continue defer errdefer export extern inline noalias noinline nosuspend pub resume"] = Tags.ModifierTag,
        ["addrspace align allowzero anyframe anytype callconv error linksection packed threadlocal unreachable volatile"] = Tags.ModifierTag,
        ["opaque"] = Tags.ModifierTag,
        ["if else switch for while case return break continue try"] = Tags.ControlKeyword,
        ["BlockLabel BreakLabel"] = Tags.LabelName,
        ["Identifier"] = Tags.VariableName,
        ["BuiltinIdentifier"] = Tags.Keyword,
        ["Name"] = Tags.Definition(Tags.VariableName),
        ["FnProto/Identifier"] = Tags.Function(Tags.Definition(Tags.VariableName)),
        ["VarDeclProto/TypeExpr/Identifier FnProto/TypeExpr/Identifier ContainerField/TypeExpr/Identifier ParamType/TypeExpr/Identifier"] = Tags.TypeName,
        ["AdditionOp"] = Tags.ArithmeticOperator,
        ["MultiplyOp"] = Tags.ArithmeticOperator,
        ["and or"] = Tags.LogicOperator,
        ["BitwiseOp"] = Tags.BitwiseOperator,
        ["BitShiftOp"] = Tags.BitwiseOperator,
        ["CompareOp"] = Tags.CompareOperator,
        ["AssignOp"] = Tags.DefinitionOperator,
        ["UpdateOp"] = Tags.UpdateOperator,
        ["ContainerDocComment"] = Tags.LineComment,
        ["DocComment"] = Tags.LineComment,
        ["LineComment"] = Tags.LineComment,
        ["Integer"] = Tags.Number,
        ["StringLiteral"] = Tags.String,
        ["StringLiteralSingle"] = Tags.String,
        ["( )"] = Tags.Paren,
        ["[ ]"] = Tags.SquareBracket,
        ["{ }"] = Tags.Brace,
        [".*"] = Tags.DerefOperator,
        [", ;"] = Tags.Separator,
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var spec = ZigParserData.MakeSpec(
            propSources: [ZigHighlighting]
        );
        return new LRParser(spec);
    }
}
