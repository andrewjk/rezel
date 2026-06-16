using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class GoGrammar
{
    private const int Newline = 10;
    private const int CarriageReturn = 13;
    private const int Space = 32;
    private const int Tab = 9;
    private const int Slash = 47;
    private const int CloseParen = 41;
    private const int CloseBrace = 125;

    private static readonly HashSet<string> TrackedTokenNames =
    [
        "IncDecOp", "identifier", "Rune", "String", "Number",
        "break", "continue", "return", "fallthrough",
        "closeParen", "closeBracket", "closeBrace"
    ];

    private static HashSet<int> _trackedTerms = new();
    private static int _termSpace;

    private static void InitTermIds(Dictionary<string, int> terms)
    {
        _termSpace = terms["space"];
        _trackedTerms = new HashSet<int>
        {
            terms["IncDecOp"], terms["identifier"], terms["Rune"], terms["String"], terms["Number"],
            terms["break"], terms["continue"], terms["return"], terms["fallthrough"],
            terms["closeParen"], terms["closeBracket"], terms["closeBrace"]
        };
    }

    private static ContextTracker MakeGoTrackTokens()
    {
        return new ContextTracker(
            start: (object?)false,
            shift: (context, term, stack, _) =>
            {
                if (term == _termSpace) return context;
                return _trackedTerms.Contains(term);
            },
            hash: (context) => (bool?)context == true ? 1 : 0,
            strict: false
        );
    }

    private static ITokenizer MakeGoExternalTokenizer(string name, Dictionary<string, int> terms)
    {
        if (name == "semicolon")
        {
            var insertedSemi = terms["insertedSemi"];
            return new ExternalTokenizer((input, stack) =>
            {
                var scan = 0;
                var next = input.Next;
                while (true)
                {
                    var ctx = (bool?)stack.Context;
                    if ((ctx == true && (next < 0 || next == Newline || next == CarriageReturn ||
                          (next == Slash && input.Peek(scan + 1) == Slash))) ||
                        next == CloseParen || next == CloseBrace)
                        input.AcceptToken(insertedSemi);
                    if (next != Space && next != Tab) break;
                    scan++;
                    next = input.Peek(scan);
                }
            }, contextual: true);
        }

        throw new ArgumentException($"Unknown Go external tokenizer: {name}");
    }

    private static readonly NodePropSource GoHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["func interface struct chan map const type var"] = Tags.DefinitionKeyword,
        ["import package"] = Tags.ModuleKeyword,
        ["switch for go select return break continue goto fallthrough case if else defer"] = Tags.ControlKeyword,
        ["range"] = Tags.Keyword,
        ["Bool"] = Tags.Bool,
        ["String"] = Tags.String,
        ["Rune"] = Tags.Character,
        ["Number"] = Tags.Number,
        ["Nil"] = Tags.Null,
        ["VariableName"] = Tags.VariableName,
        ["DefName"] = Tags.Definition(Tags.VariableName),
        ["TypeName"] = Tags.TypeName,
        ["LabelName"] = Tags.LabelName,
        ["FieldName"] = Tags.PropertyName,
        ["FunctionDecl/DefName"] = Tags.Function(Tags.Definition(Tags.VariableName)),
        ["TypeSpec/DefName"] = Tags.Definition(Tags.TypeName),
        ["CallExpr/VariableName"] = Tags.Function(Tags.VariableName),
        ["LineComment"] = Tags.LineComment,
        ["BlockComment"] = Tags.BlockComment,
        ["LogicOp"] = Tags.LogicOperator,
        ["ArithOp"] = Tags.ArithmeticOperator,
        ["BitOp"] = Tags.BitwiseOperator,
        ["DerefOp ."] = Tags.DerefOperator,
        ["UpdateOp IncDecOp"] = Tags.UpdateOperator,
        ["CompareOp"] = Tags.CompareOperator,
        ["= :="] = Tags.DefinitionOperator,
        ["<-"] = Tags.Operator,
        ["~ \"*\""] = Tags.ModifierTag,
        ["; ,"] = Tags.Separator,
        ["... :"] = Tags.Punctuation,
        ["( )"] = Tags.Paren,
        ["[ ]"] = Tags.SquareBracket,
        ["{ }"] = Tags.Brace,
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var termTable = GoParserData.TermTable!;
        InitTermIds(termTable);
        var externals = new Dictionary<string, ITokenizer>
        {
            ["semicolon"] = MakeGoExternalTokenizer("semicolon", termTable),
        };
        var spec = GoParserData.MakeSpec(
            externals: externals,
            propSources: [GoHighlighting],
            context: MakeGoTrackTokens()
        );
        return new LRParser(spec);
    }
}
