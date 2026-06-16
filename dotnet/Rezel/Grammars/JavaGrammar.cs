using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class JavaGrammar
{
    private static readonly NodePropSource JavaHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["null"] = Tags.Null,
        ["instanceof"] = Tags.OperatorKeyword,
        ["this"] = Tags.Self,
        ["new super assert open to with void"] = Tags.Keyword,
        ["class interface extends implements enum var"] = Tags.DefinitionKeyword,
        ["module package import"] = Tags.ModuleKeyword,
        ["switch while for if else case default do break continue return try catch finally throw"] = Tags.ControlKeyword,
        ["requires exports opens uses provides public private protected static transitive abstract final strictfp synchronized native transient volatile throws"] = Tags.ModifierTag,
        ["IntegerLiteral"] = Tags.Integer,
        ["FloatingPointLiteral"] = Tags.Float,
        ["StringLiteral TextBlock"] = Tags.String,
        ["CharacterLiteral"] = Tags.Character,
        ["LineComment"] = Tags.LineComment,
        ["BlockComment"] = Tags.BlockComment,
        ["BooleanLiteral"] = Tags.Bool,
        ["PrimitiveType"] = Tags.Standard(Tags.TypeName),
        ["TypeName"] = Tags.TypeName,
        ["Identifier"] = Tags.VariableName,
        ["MethodName/Identifier"] = Tags.Function(Tags.VariableName),
        ["Definition"] = Tags.Definition(Tags.VariableName),
        ["ArithOp"] = Tags.ArithmeticOperator,
        ["LogicOp"] = Tags.LogicOperator,
        ["BitOp"] = Tags.BitwiseOperator,
        ["CompareOp"] = Tags.CompareOperator,
        ["AssignOp"] = Tags.DefinitionOperator,
        ["UpdateOp"] = Tags.UpdateOperator,
        ["Asterisk"] = Tags.Punctuation,
        ["Label"] = Tags.LabelName,
        ["( )"] = Tags.Paren,
        ["[ ]"] = Tags.SquareBracket,
        ["{ }"] = Tags.Brace,
        ["."] = Tags.DerefOperator,
        [", ;"] = Tags.Separator,
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var spec = JavaParserData.MakeSpec(
            propSources: [JavaHighlighting]
        );
        return new LRParser(spec);
    }
}
