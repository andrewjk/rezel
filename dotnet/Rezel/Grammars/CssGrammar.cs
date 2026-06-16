using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class CssGrammar
{
    private static readonly HashSet<int> Space =
    [
        9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197,
        8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288
    ];

    private const int Colon = 58;
    private const int ParenL = 40;
    private const int Underscore = 95;
    private const int BracketL = 91;
    private const int Dash = 45;
    private const int Period = 46;
    private const int Hash = 35;
    private const int Percent = 37;
    private const int Backslash = 92;
    private const int Newline = 10;

    private static bool IsAlpha(int ch) => (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch >= 161;
    private static bool IsDigit(int ch) => ch >= 48 && ch <= 57;
    private static bool IsHex(int ch) => IsDigit(ch) || (ch >= 97 && ch <= 102) || (ch >= 65 && ch <= 70);

    private static void IdentifierTokens(InputStream input, Stack stack, int id, int varName, int callee)
    {
        var inside = false;
        var dashes = 0;
        for (var i = 0; ; i++)
        {
            var next = input.Next;
            if (IsAlpha(next) || next == Dash || next == Underscore || (inside && IsDigit(next)))
            {
                if (!inside && (next != Dash || i > 0)) inside = true;
                if (dashes == i && next == Dash) dashes++;
                input.Advance();
            }
            else if (next == Backslash && input.Peek(1) != Newline)
            {
                input.Advance();
                if (IsHex(input.Next))
                {
                    do { input.Advance(); } while (IsHex(input.Next));
                    if (input.Next == 32) input.Advance();
                }
                else if (input.Next > -1)
                {
                    input.Advance();
                }
                inside = true;
            }
            else
            {
                if (inside)
                    input.AcceptToken(dashes == 2 && stack.CanShift(varName) ? varName : next == ParenL ? callee : id);
                break;
            }
        }
    }

    private static ITokenizer MakeCssExternalTokenizer(string name, Dictionary<string, int> terms)
    {
        if (name == "identifiers")
        {
            var identifier = terms["identifier"];
            var callee = terms["callee"];
            var varName = terms["VariableName"];
            return new ExternalTokenizer((input, stack) =>
                IdentifierTokens(input, stack, identifier, varName, callee),
                contextual: true);
        }

        if (name == "queryIdentifiers")
        {
            var queryIdentifier = terms["queryIdentifier"];
            var queryVariableName = terms["queryVariableName"];
            var queryCallee = terms["QueryCallee"];
            return new ExternalTokenizer((input, stack) =>
                IdentifierTokens(input, stack, queryIdentifier, queryVariableName, queryCallee),
                contextual: true);
        }

        if (name == "descendant")
        {
            var descendantOp = terms["descendantOp"];
            return new ExternalTokenizer((input, _) =>
            {
                if (Space.Contains(input.Peek(-1)))
                {
                    var next = input.Next;
                    if (IsAlpha(next) || next == Underscore || next == Hash || next == Period ||
                        next == 42 || next == BracketL || (next == Colon && IsAlpha(input.Peek(1))) ||
                        next == Dash || next == 38)
                        input.AcceptToken(descendantOp);
                }
            });
        }

        if (name == "unitToken")
        {
            var unit = terms["Unit"];
            return new ExternalTokenizer((input, _) =>
            {
                if (!Space.Contains(input.Peek(-1)))
                {
                    var next = input.Next;
                    if (next == Percent) { input.Advance(); input.AcceptToken(unit); }
                    if (IsAlpha(next))
                    {
                        do { input.Advance(); } while (IsAlpha(input.Next) || IsDigit(input.Next));
                        input.AcceptToken(unit);
                    }
                }
            });
        }

        throw new ArgumentException($"Unknown CSS external tokenizer: {name}");
    }

    private static readonly NodePropSource CssHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["AtKeyword import charset namespace keyframes media supports font-feature-values"] = Tags.DefinitionKeyword,
        ["from to selector scope MatchFlag"] = Tags.Keyword,
        ["NamespaceName"] = Tags.Namespace,
        ["KeyframeName"] = Tags.LabelName,
        ["KeyframeRangeName"] = Tags.OperatorKeyword,
        ["TagName"] = Tags.TagName,
        ["ClassName"] = Tags.ClassName,
        ["PseudoClassName"] = Tags.Constant(Tags.ClassName),
        ["IdName"] = Tags.LabelName,
        ["FeatureName PropertyName"] = Tags.PropertyName,
        ["AttributeName"] = Tags.AttributeName,
        ["NumberLiteral"] = Tags.Number,
        ["KeywordQuery"] = Tags.Keyword,
        ["UnaryQueryOp"] = Tags.OperatorKeyword,
        ["CallTag ValueName FontName"] = Tags.Atom,
        ["VariableName"] = Tags.VariableName,
        ["Callee"] = Tags.OperatorKeyword,
        ["Unit"] = Tags.Unit,
        ["UniversalSelector NestingSelector"] = Tags.DefinitionOperator,
        ["MatchOp CompareOp"] = Tags.CompareOperator,
        ["ChildOp SiblingOp, LogicOp"] = Tags.LogicOperator,
        ["BinOp"] = Tags.ArithmeticOperator,
        ["Important"] = Tags.ModifierTag,
        ["Comment"] = Tags.BlockComment,
        ["ColorLiteral"] = Tags.Color,
        ["ParenthesizedContent StringLiteral"] = Tags.String,
        [":"] = Tags.Punctuation,
        ["PseudoOp #"] = Tags.DerefOperator,
        ["; , |"] = Tags.Separator,
        ["( )"] = Tags.Paren,
        ["[ ]"] = Tags.SquareBracket,
        ["{ }"] = Tags.Brace,
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var termTable = CssParserData.TermTable!;
        var externals = new Dictionary<string, ITokenizer>
        {
            ["descendant"] = MakeCssExternalTokenizer("descendant", termTable),
            ["unitToken"] = MakeCssExternalTokenizer("unitToken", termTable),
            ["identifiers"] = MakeCssExternalTokenizer("identifiers", termTable),
            ["queryIdentifiers"] = MakeCssExternalTokenizer("queryIdentifiers", termTable),
        };
        var spec = CssParserData.MakeSpec(
            externals: externals,
            propSources: [CssHighlighting]
        );
        return new LRParser(spec);
    }
}
