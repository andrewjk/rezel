using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class RustGrammar
{
    private const int B = 98;
    private const int E = 101;
    private const int F = 102;
    private const int R = 114;
    private const int BigE = 69;
    private const int Zero = 48;
    private const int Dot = 46;
    private const int Plus = 43;
    private const int Minus = 45;
    private const int Hash = 35;
    private const int Quote = 34;
    private const int Pipe = 124;
    private const int LessThan = 60;
    private const int GreaterThan = 62;

    private static bool IsNum(int ch) => ch >= 48 && ch <= 57;
    private static bool IsNum_(int ch) => IsNum(ch) || ch == 95;
    private static bool IsWord(int ch) => (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch == 95 || ch >= 128;

    private static ITokenizer MakeRustExternalTokenizer(string name, Dictionary<string, int> terms)
    {
        if (name == "literalTokens")
        {
            var Float = terms["Float"];
            var RawString = terms["RawString"];

            return new ExternalTokenizer((input, _) =>
            {
                if (IsNum(input.Next))
                {
                    var isFloat = false;
                    do { input.Advance(); } while (IsNum_(input.Next));
                    if (input.Next == Dot)
                    {
                        isFloat = true;
                        input.Advance();
                        if (IsNum(input.Next))
                        {
                            do { input.Advance(); } while (IsNum_(input.Next));
                        }
                        else if (input.Next == Dot || input.Next > 0x7f || IsWord(input.Next))
                        {
                            return;
                        }
                    }
                    if (input.Next == E || input.Next == BigE)
                    {
                        isFloat = true;
                        input.Advance();
                        if (input.Next == Plus || input.Next == Minus) input.Advance();
                        if (!IsNum_(input.Next)) return;
                        do { input.Advance(); } while (IsNum_(input.Next));
                    }
                    if (input.Next == F)
                    {
                        var after = input.Peek(1);
                        if ((after == Zero + 3 && input.Peek(2) == Zero + 2) ||
                            (after == Zero + 6 && input.Peek(2) == Zero + 4))
                        {
                            input.Advance();
                            input.Advance();
                            input.Advance();
                            isFloat = true;
                        }
                        else
                        {
                            return;
                        }
                    }
                    if (isFloat) input.AcceptToken(Float);
                }
                else if (input.Next == B || input.Next == R)
                {
                    if (input.Next == B) input.Advance();
                    if (input.Next != R) return;
                    input.Advance();
                    var count = 0;
                    while (input.Next == Hash) { count++; input.Advance(); }
                    if (input.Next != Quote) return;
                    input.Advance();
                    while (true)
                    {
                        if (input.Next < 0) return;
                        var isQuote = input.Next == Quote;
                        input.Advance();
                        if (isQuote)
                        {
                            var matched = true;
                            for (var i = 0; i < count; i++)
                            {
                                if (input.Next != Hash) { matched = false; break; }
                                input.Advance();
                            }
                            if (matched)
                            {
                                input.AcceptToken(RawString);
                                return;
                            }
                        }
                    }
                }
            });
        }

        if (name == "closureParam")
        {
            var closureParamDelim = terms["closureParamDelim"];
            return new ExternalTokenizer((input, _) =>
            {
                if (input.Next == Pipe) input.AcceptToken(closureParamDelim, endOffset: 1);
            });
        }

        if (name == "tpDelim")
        {
            var tpOpen = terms["tpOpen"];
            var tpClose = terms["tpClose"];
            return new ExternalTokenizer((input, _) =>
            {
                if (input.Next == LessThan) input.AcceptToken(tpOpen, endOffset: 1);
                else if (input.Next == GreaterThan) input.AcceptToken(tpClose, endOffset: 1);
            });
        }

        throw new ArgumentException($"Unknown Rust external tokenizer: {name}");
    }

    private static readonly NodePropSource RustHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["const macro_rules struct union enum type fn impl trait let static"] = Tags.DefinitionKeyword,
        ["mod use crate"] = Tags.ModuleKeyword,
        ["pub unsafe async mut extern default move"] = Tags.ModifierTag,
        ["for if else loop while match continue break return await"] = Tags.ControlKeyword,
        ["as in ref"] = Tags.OperatorKeyword,
        ["where _ crate super dyn"] = Tags.Keyword,
        ["self"] = Tags.Self,
        ["String"] = Tags.String,
        ["Char"] = Tags.Character,
        ["RawString"] = Tags.Special(Tags.String),
        ["Boolean"] = Tags.Bool,
        ["Identifier"] = Tags.VariableName,
        ["CallExpression/Identifier"] = Tags.Function(Tags.VariableName),
        ["BoundIdentifier"] = Tags.Definition(Tags.VariableName),
        ["FunctionItem/BoundIdentifier"] = Tags.Function(Tags.Definition(Tags.VariableName)),
        ["LoopLabel"] = Tags.LabelName,
        ["FieldIdentifier"] = Tags.PropertyName,
        ["CallExpression/FieldExpression/FieldIdentifier"] = Tags.Function(Tags.PropertyName),
        ["Lifetime"] = Tags.Special(Tags.VariableName),
        ["ScopeIdentifier"] = Tags.Namespace,
        ["TypeIdentifier"] = Tags.TypeName,
        ["MacroInvocation/Identifier MacroInvocation/ScopedIdentifier/Identifier"] = Tags.MacroName,
        ["MacroInvocation/TypeIdentifier MacroInvocation/ScopedIdentifier/TypeIdentifier"] = Tags.MacroName,
        ["\"!\""] = Tags.MacroName,
        ["UpdateOp"] = Tags.UpdateOperator,
        ["LineComment"] = Tags.LineComment,
        ["BlockComment"] = Tags.BlockComment,
        ["Integer"] = Tags.Integer,
        ["Float"] = Tags.Float,
        ["ArithOp"] = Tags.ArithmeticOperator,
        ["LogicOp"] = Tags.LogicOperator,
        ["BitOp"] = Tags.BitwiseOperator,
        ["CompareOp"] = Tags.CompareOperator,
        ["="] = Tags.DefinitionOperator,
        [".. ... => ->"] = Tags.Punctuation,
        ["( )"] = Tags.Paren,
        ["[ ]"] = Tags.SquareBracket,
        ["{ }"] = Tags.Brace,
        [". DerefOp"] = Tags.DerefOperator,
        ["&"] = Tags.Operator,
        [", ; ::"] = Tags.Separator,
        ["Attribute/..."] = Tags.Meta,
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var termTable = RustParserData.TermTable!;
        var externals = new Dictionary<string, ITokenizer>
        {
            ["closureParam"] = MakeRustExternalTokenizer("closureParam", termTable),
            ["tpDelim"] = MakeRustExternalTokenizer("tpDelim", termTable),
            ["literalTokens"] = MakeRustExternalTokenizer("literalTokens", termTable),
        };
        var spec = RustParserData.MakeSpec(
            externals: externals,
            propSources: [RustHighlighting]
        );
        return new LRParser(spec);
    }
}
