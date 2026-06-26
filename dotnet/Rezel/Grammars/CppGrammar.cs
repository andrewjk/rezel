using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class CppGrammar
{
    private const int R = 82;
    private const int L = 76;
    private const int U = 85;
    private const int u = 117;
    private const int A = 65;
    private const int Z = 90;
    private const int a = 97;
    private const int z = 122;
    private const int Underscore = 95;
    private const int Zero = 48;
    private const int Quote = 34;
    private const int ParenL = 40;
    private const int ParenR = 41;
    private const int Space = 32;
    private const int GreaterThan = 62;

    private static ITokenizer MakeCppExternalTokenizer(string name, Dictionary<string, int> terms)
    {
        if (name == "rawString")
        {
            var RawString = terms["RawString"];
            return new ExternalTokenizer((input, _) =>
            {
                if (input.Next == L || input.Next == U)
                {
                    input.Advance();
                }
                else if (input.Next == u)
                {
                    input.Advance();
                    if (input.Next == Zero + 8) input.Advance();
                }
                if (input.Next != R) return;
                input.Advance();
                if (input.Next != Quote) return;
                input.Advance();

                var marker = "";
                while (input.Next != ParenL)
                {
                    if (input.Next == Space || input.Next <= 13 || input.Next == ParenR) return;
                    marker += (char)input.Next;
                    input.Advance();
                }
                input.Advance();

                while (true)
                {
                    if (input.Next < 0)
                    {
                        input.AcceptToken(RawString);
                        return;
                    }
                    if (input.Next == ParenR)
                    {
                        var match = true;
                        for (var i = 0; match && i < marker.Length; i++)
                            if (input.Peek(i + 1) != marker[i]) match = false;
                        if (match && input.Peek(marker.Length + 1) == Quote)
                        {
                            input.AcceptToken(RawString, endOffset: 2 + marker.Length);
                            return;
                        }
                    }
                    input.Advance();
                }
            });
        }

        if (name == "fallback")
        {
            var templateArgsEndFallback = terms["templateArgsEndFallback"];
            var MacroName = terms["MacroName"];
            return new ExternalTokenizer((input, _) =>
            {
                if (input.Next == GreaterThan)
                {
                    if (input.Peek(1) == GreaterThan)
                        input.AcceptToken(templateArgsEndFallback, endOffset: 1);
                }
                else
                {
                    var sawLetter = false;
                    var i = 0;
                    for (; ; i++)
                    {
                        if (input.Next >= A && input.Next <= Z) sawLetter = true;
                        else if (input.Next >= a && input.Next <= z) return;
                        else if (input.Next != Underscore && !(input.Next >= Zero && input.Next <= Zero + 9)) break;
                        input.Advance();
                    }
                    if (sawLetter && i > 1) input.AcceptToken(MacroName);
                }
            }, extend: true);
        }

        throw new ArgumentException($"Unknown C++ external tokenizer: {name}");
    }

    private static readonly NodePropSource CppHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["typedef struct union enum class typename decltype auto template operator friend noexcept namespace using requires concept import export module __attribute__ __declspec __based"] = Tags.DefinitionKeyword,
        ["extern MsCallModifier MsPointerModifier extern static register thread_local inline const volatile restrict _Atomic mutable constexpr constinit consteval virtual explicit VirtualSpecifier Access"] = Tags.ModifierTag,
        ["if else switch for while do case default return break continue goto throw try catch"] = Tags.ControlKeyword,
        ["co_return co_yield co_await"] = Tags.ControlKeyword,
        ["new sizeof delete static_assert"] = Tags.OperatorKeyword,
        ["NULL nullptr"] = Tags.Null,
        ["this"] = Tags.Self,
        ["True False"] = Tags.Bool,
        ["TypeSize PrimitiveType"] = Tags.Standard(Tags.TypeName),
        ["TypeIdentifier"] = Tags.TypeName,
        ["FieldIdentifier"] = Tags.PropertyName,
        ["CallExpression/FieldExpression/FieldIdentifier"] = Tags.Function(Tags.PropertyName),
        ["ModuleName/Identifier"] = Tags.Namespace,
        ["PartitionName"] = Tags.LabelName,
        ["StatementIdentifier"] = Tags.LabelName,
        ["Identifier DestructorName"] = Tags.VariableName,
        ["CallExpression/Identifier"] = Tags.Function(Tags.VariableName),
        ["CallExpression/ScopedIdentifier/Identifier"] = Tags.Function(Tags.VariableName),
        ["FunctionDeclarator/Identifier FunctionDeclarator/DestructorName"] = Tags.Function(Tags.Definition(Tags.VariableName)),
        ["NamespaceIdentifier"] = Tags.Namespace,
        ["OperatorName"] = Tags.Operator,
        ["ArithOp"] = Tags.ArithmeticOperator,
        ["LogicOp"] = Tags.LogicOperator,
        ["BitOp"] = Tags.BitwiseOperator,
        ["CompareOp"] = Tags.CompareOperator,
        ["AssignOp"] = Tags.DefinitionOperator,
        ["UpdateOp"] = Tags.UpdateOperator,
        ["LineComment"] = Tags.LineComment,
        ["BlockComment"] = Tags.BlockComment,
        ["Number"] = Tags.Number,
        ["String"] = Tags.String,
        ["RawString SystemLibString"] = Tags.Special(Tags.String),
        ["CharLiteral"] = Tags.Character,
        ["EscapeSequence"] = Tags.Escape,
        ["UserDefinedLiteral/Identifier"] = Tags.Literal,
        ["PreprocArg"] = Tags.Meta,
        ["PreprocDirectiveName #include #ifdef #ifndef #if #define #else #endif #elif"] = Tags.ProcessingInstruction,
        ["MacroName"] = Tags.Special(Tags.Name),
        ["( )"] = Tags.Paren,
        ["[ ]"] = Tags.SquareBracket,
        ["{ }"] = Tags.Brace,
        ["< >"] = Tags.AngleBracket,
        [". ->"] = Tags.DerefOperator,
        [", ;"] = Tags.Separator,
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var termTable = CppParserData.TermTable!;
        var externals = new Dictionary<string, ITokenizer>
        {
            ["rawString"] = MakeCppExternalTokenizer("rawString", termTable),
            ["fallback"] = MakeCppExternalTokenizer("fallback", termTable),
        };
        var spec = CppParserData.MakeSpec(
            externals: externals,
            propSources: [CppHighlighting]
        );
        return new LRParser(spec);
    }
}
