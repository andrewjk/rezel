using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class CSharpGrammar
{
    private const int Quote = 34;
    private const int Backslash = 92;
    private const int BraceL = 123;
    private const int BraceR = 125;

    private static void InterpStringTokens(InputStream input, int content, int brace, int end)
    {
        for (var i = 0; ; i++)
        {
            switch (input.Next)
            {
                case -1:
                    if (i > 0) input.AcceptToken(content);
                    return;

                case Quote:
                    if (i > 0) input.AcceptToken(content);
                    else input.AcceptToken(end, 1);
                    return;

                case BraceL:
                    if (input.Peek(1) == BraceL) input.AcceptToken(content, 2);
                    else input.AcceptToken(brace);
                    return;

                case BraceR:
                    if (input.Peek(1) == BraceR) input.AcceptToken(content, 2);
                    return;

                case Backslash:
                    var next = input.Peek(1);
                    if (next == BraceL || next == BraceR) return;
                    input.Advance();
                    goto default;

                default:
                    input.Advance();
                    break;
            }
        }
    }

    private static void InterpVStringTokens(InputStream input, int content, int brace, int end)
    {
        for (var i = 0; ; i++)
        {
            switch (input.Next)
            {
                case -1:
                    if (i > 0) input.AcceptToken(content);
                    return;

                case Quote:
                    if (input.Peek(1) == Quote) input.AcceptToken(content, 2);
                    else if (i > 0) input.AcceptToken(content);
                    else input.AcceptToken(end, 1);
                    return;

                case BraceL:
                    if (input.Peek(1) == BraceL) input.AcceptToken(content, 2);
                    else input.AcceptToken(brace);
                    return;

                case BraceR:
                    if (input.Peek(1) == BraceR) input.AcceptToken(content, 2);
                    return;

                default:
                    input.Advance();
                    break;
            }
        }
    }

    private static ITokenizer MakeCSharpExternalTokenizer(string name, Dictionary<string, int> terms)
    {
        if (name == "interpString")
        {
            var content = terms["interpStringContent"];
            var brace = terms["interpStringBrace"];
            var end = terms["interpStringEnd"];
            return new ExternalTokenizer((input, _) =>
                InterpStringTokens(input, content, brace, end));
        }

        if (name == "interpVString")
        {
            var content = terms["interpVStringContent"];
            var brace = terms["interpVStringBrace"];
            var end = terms["interpVStringEnd"];
            return new ExternalTokenizer((input, _) =>
                InterpVStringTokens(input, content, brace, end));
        }

        throw new ArgumentException($"Unknown C# external tokenizer: {name}");
    }

    private static readonly NodePropSource CSharpHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["Keyword ContextualKeyword SimpleType"] = Tags.Keyword,
        ["NullLiteral BooleanLiteral"] = Tags.Bool,
        ["IntegerLiteral"] = Tags.Integer,
        ["RealLiteral"] = Tags.Float,
        ["StringLiteral CharacterLiteral InterpolatedRegularString InterpolatedVerbatimString $\" @$\" $@\""] = Tags.String,
        ["LineComment BlockComment"] = Tags.Comment,
        [". .. : Astrisk Slash % + - ++ -- Not ~ << & | ^ && || < > <= >= == NotEq = += -= *= SlashEq %= &= |= ^= ? ?? ??= =>"] = Tags.Operator,
        ["PP_Directive"] = Tags.Keyword,
        ["TypeIdentifier"] = Tags.TypeName,
        ["ArgumentName AttrsNamedArg"] = Tags.VariableName,
        ["ConstName"] = Tags.Constant(Tags.VariableName),
        ["MethodName"] = Tags.Function(Tags.VariableName),
        ["ParamName"] = new[] { Tags.Emphasis, Tags.VariableName },
        ["VarName"] = Tags.VariableName,
        ["FieldName PropertyName"] = Tags.PropertyName,
        ["( )"] = Tags.Paren,
        ["{ }"] = Tags.Brace,
        ["[ ]"] = Tags.SquareBracket,
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var termTable = CSharpParserData.TermTable!;
        var externals = new Dictionary<string, ITokenizer>
        {
            ["interpString"] = MakeCSharpExternalTokenizer("interpString", termTable),
            ["interpVString"] = MakeCSharpExternalTokenizer("interpVString", termTable),
        };
        var spec = CSharpParserData.MakeSpec(
            externals: externals,
            propSources: [CSharpHighlighting]
        );
        return new LRParser(spec);
    }
}
