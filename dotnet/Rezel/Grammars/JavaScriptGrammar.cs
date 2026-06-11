using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class JavaScriptGrammar
{
    private static readonly HashSet<int> Space = [
        9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200,
        8201, 8202, 8232, 8233, 8239, 8287, 12288
    ];

    private const int BraceR = 125;
    private const int Semicolon = 59;
    private const int Slash = 47;
    private const int Star = 42;
    private const int Plus = 43;
    private const int Minus = 45;
    private const int Lt = 60;
    private const int Comma = 44;
    private const int Question = 63;
    private const int Dot = 46;
    private const int BracketL = 91;

    private static bool JsIdentifierChar(int ch, bool start)
    {
        return (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch == 95 || ch >= 192 ||
            (!start && ch >= 48 && ch <= 57);
    }

    public static readonly ContextTracker JsTrackNewline = new(
        start: (object?)false,
        shift: (context, term, stack, _) =>
        {
            var name = stack.Parser.TermNames?.GetValueOrDefault(term) ?? "";
            if (name is "LineComment" or "BlockComment" or "spaces")
                return context;
            return name == "newline";
        },
        @strict: false
    );

    private static ITokenizer MakeJsExternalTokenizer(string name, Dictionary<string, int> terms)
    {
        if (name == "insertSemicolon")
        {
            var insertSemi = terms["insertSemi"];
            return new ExternalTokenizer((input, stack) =>
            {
                var next = input.Next;
                if (next == BraceR || next == -1 || ((bool?)stack.Context == true))
                    input.AcceptToken(insertSemi);
            }, contextual: true, fallback: true);
        }

        if (name == "noSemicolon")
        {
            var noSemi = terms["noSemi"];
            return new ExternalTokenizer((input, stack) =>
            {
                var next = input.Next;
                if (Space.Contains(next)) return;
                if (next == Slash)
                {
                    var after = input.Peek(1);
                    if (after == Slash || after == Star) return;
                }
                if (next != BraceR && next != Semicolon && next != -1 && !((bool?)stack.Context == true))
                    input.AcceptToken(noSemi);
            }, contextual: true);
        }

        if (name == "noSemicolonType")
        {
            var noSemiType = terms["noSemiType"];
            return new ExternalTokenizer((input, stack) =>
            {
                if (input.Next == BracketL && !((bool?)stack.Context == true))
                    input.AcceptToken(noSemiType);
            }, contextual: true);
        }

        if (name == "operatorToken")
        {
            var incdec = terms["incdec"];
            var incdecPrefix = terms["incdecPrefix"];
            var questionDot = terms["questionDot"];
            return new ExternalTokenizer((input, stack) =>
            {
                var next = input.Next;
                if (next == Plus || next == Minus)
                {
                    input.Advance();
                    if (next == input.Next)
                    {
                        input.Advance();
                        var mayPostfix = !((bool?)stack.Context == true) && stack.CanShift(incdec);
                        input.AcceptToken(mayPostfix ? incdec : incdecPrefix);
                    }
                }
                else if (next == Question && input.Peek(1) == Dot)
                {
                    input.Advance();
                    input.Advance();
                    if (input.Next < 48 || input.Next > 57)
                        input.AcceptToken(questionDot);
                }
            }, contextual: true);
        }

        if (name == "jsx")
        {
            var JSXStartTag = terms["JSXStartTag"];
            return new ExternalTokenizer((input, stack) =>
            {
                if (input.Next != Lt) return;
                var parser = stack.Parser;
                var keys = parser.Dialects.Keys.ToArray();
                var jsxIdx = Array.IndexOf(keys, "jsx");
                if (jsxIdx >= 0)
                {
                    if (!stack.DialectEnabled(jsxIdx)) return;
                }
                else return;

                input.Advance();
                if (input.Next == Slash) return;
                var back = 0;
                while (Space.Contains(input.Next))
                {
                    input.Advance(); back++;
                }
                if (JsIdentifierChar(input.Next, true))
                {
                    input.Advance();
                    back++;
                    while (JsIdentifierChar(input.Next, false))
                    {
                        input.Advance(); back++;
                    }
                    while (Space.Contains(input.Next))
                    {
                        input.Advance(); back++;
                    }
                    if (input.Next == Comma) return;
                    var extendsStr = "extends";
                    for (var i = 0; i <= extendsStr.Length; i++)
                    {
                        if (i == extendsStr.Length)
                        {
                            if (!JsIdentifierChar(input.Next, true)) return;
                            break;
                        }
                        if (input.Next != extendsStr[i]) break;
                        input.Advance();
                        back++;
                    }
                }
                input.AcceptToken(JSXStartTag, endOffset: -back);
            }, contextual: true);
        }

        throw new ArgumentException($"Unknown JS external tokenizer: {name}");
    }

    private static readonly NodePropSource JsHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["get set async static"] = Tags.ModifierTag,
        ["for while do if else switch try catch finally return throw break continue default case defer"] = Tags.ControlKeyword,
        ["in of await yield void typeof delete instanceof as satisfies"] = Tags.OperatorKeyword,
        ["let var const using function class extends"] = Tags.DefinitionKeyword,
        ["import export from"] = Tags.ModuleKeyword,
        ["with debugger new"] = Tags.Keyword,
        ["TemplateString"] = Tags.Special(Tags.String),
        ["super"] = Tags.Atom,
        ["BooleanLiteral"] = Tags.Bool,
        ["this"] = Tags.Self,
        ["null"] = Tags.Null,
        ["VariableName"] = Tags.VariableName,
        ["CallExpression/VariableName TaggedTemplateExpression/VariableName"] = Tags.Function(Tags.VariableName),
        ["VariableDefinition"] = Tags.Definition(Tags.VariableName),
        ["Label"] = Tags.LabelName,
        ["PropertyName"] = Tags.PropertyName,
        ["PrivatePropertyName"] = Tags.Special(Tags.PropertyName),
        ["CallExpression/MemberExpression/PropertyName"] = Tags.Function(Tags.PropertyName),
        ["FunctionDeclaration/VariableDefinition"] = Tags.Function(Tags.Definition(Tags.VariableName)),
        ["ClassDeclaration/VariableDefinition"] = Tags.Definition(Tags.ClassName),
        ["NewExpression/VariableName"] = Tags.ClassName,
        ["PropertyDefinition"] = Tags.Definition(Tags.PropertyName),
        ["PrivatePropertyDefinition"] = Tags.Definition(Tags.Special(Tags.PropertyName)),
        ["UpdateOp"] = Tags.UpdateOperator,
        ["LineComment Hashbang"] = Tags.LineComment,
        ["BlockComment"] = Tags.BlockComment,
        ["Number"] = Tags.Number,
        ["String"] = Tags.String,
        ["Escape"] = Tags.Escape,
        ["ArithOp"] = Tags.ArithmeticOperator,
        ["LogicOp"] = Tags.LogicOperator,
        ["BitOp"] = Tags.BitwiseOperator,
        ["CompareOp"] = Tags.CompareOperator,
        ["RegExp"] = Tags.Regexp,
        ["Equals"] = Tags.DefinitionOperator,
        ["Arrow"] = Tags.Function(Tags.Punctuation),
        [": Spread"] = Tags.Punctuation,
        ["( )"] = Tags.Paren,
        ["[ ]"] = Tags.SquareBracket,
        ["{ }"] = Tags.Brace,
        ["InterpolationStart InterpolationEnd"] = Tags.Special(Tags.Brace),
        ["."] = Tags.DerefOperator,
        [", ;"] = Tags.Separator,
        ["@"] = Tags.Meta,
        ["TypeName"] = Tags.TypeName,
        ["TypeDefinition"] = Tags.Definition(Tags.TypeName),
        ["type enum interface implements namespace module declare"] = Tags.DefinitionKeyword,
        ["abstract global Privacy readonly override"] = Tags.ModifierTag,
        ["is keyof unique infer asserts"] = Tags.OperatorKeyword,
        ["JSXAttributeValue"] = Tags.AttributeValue,
        ["JSXText"] = Tags.Content,
        ["JSXStartTag JSXStartCloseTag JSXSelfCloseEndTag JSXEndTag"] = Tags.AngleBracket,
        ["JSXIdentifier JSXNamespacedName"] = Tags.TagName,
        ["JSXAttribute/JSXIdentifier JSXAttribute/JSXNamespacedName"] = Tags.AttributeName,
        ["JSXBuiltin/JSXIdentifier"] = Tags.Standard(Tags.TagName),
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var termTable = JavaScriptParserData.TermTable!;
        var externals = new Dictionary<string, ITokenizer>
        {
            ["insertSemicolon"] = MakeJsExternalTokenizer("insertSemicolon", termTable),
            ["noSemicolon"] = MakeJsExternalTokenizer("noSemicolon", termTable),
            ["noSemicolonType"] = MakeJsExternalTokenizer("noSemicolonType", termTable),
            ["operatorToken"] = MakeJsExternalTokenizer("operatorToken", termTable),
            ["jsx"] = MakeJsExternalTokenizer("jsx", termTable),
        };
        var spec = JavaScriptParserData.MakeSpec(
            externals: externals,
            propSources: [JsHighlighting],
            context: JsTrackNewline
        );
        return new LRParser(spec);
    }
}
