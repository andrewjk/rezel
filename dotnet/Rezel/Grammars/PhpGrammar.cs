using System.Text;
using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class PhpGrammar
{
    private static Dictionary<string, int> _keywordMap = new();

    private static int Keywords(string name, Dictionary<string, int> terms)
    {
        if (_keywordMap.Count == 0) BuildKeywordMap(terms);
        return _keywordMap.TryGetValue(name.ToLowerInvariant(), out var found) ? found : -1;
    }

    private static void BuildKeywordMap(Dictionary<string, int> terms)
    {
        _keywordMap["abstract"] = terms["abstract"];
        _keywordMap["and"] = terms["and"];
        _keywordMap["array"] = terms["array"];
        _keywordMap["as"] = terms["as"];
        _keywordMap["true"] = terms["Boolean"];
        _keywordMap["false"] = terms["Boolean"];
        _keywordMap["break"] = terms["break"];
        _keywordMap["case"] = terms["case"];
        _keywordMap["catch"] = terms["catch"];
        _keywordMap["clone"] = terms["clone"];
        _keywordMap["const"] = terms["const"];
        _keywordMap["continue"] = terms["continue"];
        _keywordMap["declare"] = terms["declare"];
        _keywordMap["default"] = terms["default"];
        _keywordMap["do"] = terms["do"];
        _keywordMap["echo"] = terms["echo"];
        _keywordMap["else"] = terms["else"];
        _keywordMap["elseif"] = terms["elseif"];
        _keywordMap["enddeclare"] = terms["enddeclare"];
        _keywordMap["endfor"] = terms["endfor"];
        _keywordMap["endforeach"] = terms["endforeach"];
        _keywordMap["endif"] = terms["endif"];
        _keywordMap["endswitch"] = terms["endswitch"];
        _keywordMap["endwhile"] = terms["endwhile"];
        _keywordMap["enum"] = terms["enum"];
        _keywordMap["extends"] = terms["extends"];
        _keywordMap["final"] = terms["final"];
        _keywordMap["finally"] = terms["finally"];
        _keywordMap["fn"] = terms["fn"];
        _keywordMap["for"] = terms["for"];
        _keywordMap["foreach"] = terms["foreach"];
        _keywordMap["from"] = terms["from"];
        _keywordMap["function"] = terms["function"];
        _keywordMap["global"] = terms["global"];
        _keywordMap["goto"] = terms["goto"];
        _keywordMap["if"] = terms["if"];
        _keywordMap["implements"] = terms["implements"];
        _keywordMap["include"] = terms["include"];
        _keywordMap["include_once"] = terms["include_once"];
        _keywordMap["instanceof"] = terms["instanceof"];
        _keywordMap["insteadof"] = terms["insteadof"];
        _keywordMap["interface"] = terms["interface"];
        _keywordMap["list"] = terms["list"];
        _keywordMap["match"] = terms["match"];
        _keywordMap["namespace"] = terms["namespace"];
        _keywordMap["new"] = terms["new"];
        _keywordMap["null"] = terms["null"];
        _keywordMap["or"] = terms["or"];
        _keywordMap["print"] = terms["print"];
        _keywordMap["readonly"] = terms["readonly"];
        _keywordMap["require"] = terms["require"];
        _keywordMap["require_once"] = terms["require_once"];
        _keywordMap["return"] = terms["return"];
        _keywordMap["switch"] = terms["switch"];
        _keywordMap["throw"] = terms["throw"];
        _keywordMap["trait"] = terms["trait"];
        _keywordMap["try"] = terms["try"];
        _keywordMap["unset"] = terms["unset"];
        _keywordMap["use"] = terms["use"];
        _keywordMap["var"] = terms["var"];
        _keywordMap["public"] = terms["Visibility"];
        _keywordMap["private"] = terms["Visibility"];
        _keywordMap["protected"] = terms["Visibility"];
        _keywordMap["while"] = terms["while"];
        _keywordMap["xor"] = terms["xor"];
        _keywordMap["yield"] = terms["yield"];
    }

    private static bool IsSpace(int ch) => ch == 9 || ch == 10 || ch == 13 || ch == 32;

    private static bool IsASCIILetter(int ch) => (ch >= 97 && ch <= 122) || (ch >= 65 && ch <= 90);

    private static bool IsIdentifierStart(int ch) => ch == 95 || ch >= 0x80 || IsASCIILetter(ch);

    private static bool IsHexChar(int ch) => (ch >= 48 && ch <= 55) || (ch >= 97 && ch <= 102) || (ch >= 65 && ch <= 70);

    private static readonly HashSet<string> CastTypes =
    [
        "int", "integer", "bool", "boolean", "float", "double", "real", "string", "array", "object", "unset"
    ];

    private static ITokenizer MakePhpExternalTokenizer(string name, Dictionary<string, int> terms)
    {
        if (name == "expression")
        {
            var castOpen = terms["castOpen"];
            var HeredocString = terms["HeredocString"];

            return new ExternalTokenizer((input, _) =>
            {
                if (input.Next == 40)
                {
                    input.Advance();
                    var peek = 0;
                    while (IsSpace(input.Peek(peek))) peek++;
                    var nm = "";
                    int next;
                    while (IsASCIILetter(next = input.Peek(peek))) { nm += (char)next; peek++; }
                    while (IsSpace(input.Peek(peek))) peek++;
                    if (input.Peek(peek) == 41 && CastTypes.Contains(nm.ToLowerInvariant()))
                        input.AcceptToken(castOpen);
                }
                else if (input.Next == 60 && input.Peek(1) == 60 && input.Peek(2) == 60)
                {
                    input.Advance();
                    input.Advance();
                    input.Advance();
                    while (input.Next == 32 || input.Next == 9) input.Advance();
                    var quoted = input.Next == 39;
                    if (quoted) input.Advance();
                    if (!IsIdentifierStart(input.Next)) return;
                    var tag = new StringBuilder();
                    tag.Append((char)input.Next);
                    while (true)
                    {
                        input.Advance();
                        if (!IsIdentifierStart(input.Next) && !(input.Next >= 48 && input.Next <= 55)) break;
                        tag.Append((char)input.Next);
                    }
                    if (quoted)
                    {
                        if (input.Next != 39) return;
                        input.Advance();
                    }
                    if (input.Next != 10 && input.Next != 13) return;
                    while (true)
                    {
                        var lineStart = input.Next == 10 || input.Next == 13;
                        input.Advance();
                        if (input.Next < 0) return;
                        if (lineStart)
                        {
                            while (input.Next == 32 || input.Next == 9) input.Advance();
                            var match = true;
                            for (var i = 0; i < tag.Length; i++)
                            {
                                if (input.Next != tag[i]) { match = false; break; }
                                input.Advance();
                            }
                            if (match)
                            {
                                input.AcceptToken(HeredocString);
                                return;
                            }
                        }
                    }
                }
            });
        }

        if (name == "eofToken")
        {
            var eof = terms["eof"];
            return new ExternalTokenizer((input, _) =>
            {
                if (input.Next < 0) input.AcceptToken(eof);
            });
        }

        if (name == "semicolon")
        {
            var automaticSemicolon = terms["automaticSemicolon"];
            return new ExternalTokenizer((input, stack) =>
            {
                if (input.Next == 63 && stack.CanShift(automaticSemicolon) && input.Peek(1) == 62)
                    input.AcceptToken(automaticSemicolon);
            });
        }

        if (name == "interpolated")
        {
            var interpolatedStringContent = terms["interpolatedStringContent"];
            var EscapeSequence = terms["EscapeSequence"];
            var afterInterpolation = terms["afterInterpolation"];

            return new ExternalTokenizer((input, stack) =>
            {
                var content = false;
                while (true)
                {
                    if (input.Next == 34 || input.Next < 0 ||
                        (input.Next == 36 && (IsIdentifierStart(input.Peek(1)) || input.Peek(1) == 123)) ||
                        (input.Next == 123 && input.Peek(1) == 36))
                    {
                        break;
                    }
                    else if (input.Next == 92)
                    {
                        var escaped = ScanEscape(input);
                        if (escaped > 0)
                        {
                            if (content) break;
                            else { input.AcceptToken(EscapeSequence, endOffset: escaped); return; }
                        }
                    }
                    else if (!content && (
                        input.Next == 91 ||
                        (input.Next == 45 && input.Peek(1) == 62 && IsIdentifierStart(input.Peek(2))) ||
                        (input.Next == 63 && input.Peek(1) == 45 && input.Peek(2) == 62 && IsIdentifierStart(input.Peek(3)))
                    ) && stack.CanShift(afterInterpolation))
                    {
                        break;
                    }
                    input.Advance();
                    content = true;
                }
                if (content) input.AcceptToken(interpolatedStringContent);
            });
        }

        throw new ArgumentException($"Unknown PHP external tokenizer: {name}");
    }

    private static int ScanEscape(InputStream input)
    {
        var after = input.Peek(1);
        if (after == 110 || after == 114 || after == 116 || after == 118 || after == 101 ||
            after == 102 || after == 92 || after == 36 || after == 34 || after == 123)
            return 2;

        if (after >= 48 && after <= 55)
        {
            var size = 2;
            int next;
            while (size < 5 && (next = input.Peek(size)) >= 48 && next <= 55) size++;
            return size;
        }

        if (after == 120 && IsHexChar(input.Peek(2)))
            return IsHexChar(input.Peek(3)) ? 4 : 3;

        if (after == 117 && input.Peek(2) == 123)
        {
            for (var size = 3; ; size++)
            {
                var next = input.Peek(size);
                if (next == 125) return size == 2 ? 0 : size + 1;
                if (!IsHexChar(next)) break;
            }
        }

        return 0;
    }

    private static readonly NodePropSource PhpHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["Visibility abstract final static"] = Tags.ModifierTag,
        ["for foreach while do if else elseif switch try catch finally return throw break continue default case"] = Tags.ControlKeyword,
        ["endif endfor endforeach endswitch endwhile declare enddeclare goto match"] = Tags.ControlKeyword,
        ["and or xor yield unset clone instanceof insteadof"] = Tags.OperatorKeyword,
        ["function fn class trait implements extends const enum global interface use var"] = Tags.DefinitionKeyword,
        ["include include_once require require_once namespace"] = Tags.ModuleKeyword,
        ["new from echo print array list as"] = Tags.Keyword,
        ["null"] = Tags.Null,
        ["Boolean"] = Tags.Bool,
        ["VariableName"] = Tags.VariableName,
        ["NamespaceName/..."] = Tags.Namespace,
        ["NamedType/..."] = Tags.TypeName,
        ["Name"] = Tags.Name,
        ["CallExpression/Name"] = Tags.Function(Tags.VariableName),
        ["LabelStatement/Name"] = Tags.LabelName,
        ["MemberExpression/Name"] = Tags.PropertyName,
        ["MemberExpression/VariableName"] = Tags.Special(Tags.PropertyName),
        ["ScopedExpression/ClassMemberName/Name"] = Tags.PropertyName,
        ["ScopedExpression/ClassMemberName/VariableName"] = Tags.Special(Tags.PropertyName),
        ["CallExpression/MemberExpression/Name"] = Tags.Function(Tags.PropertyName),
        ["CallExpression/ScopedExpression/ClassMemberName/Name"] = Tags.Function(Tags.PropertyName),
        ["MethodDeclaration/Name"] = Tags.Function(Tags.Definition(Tags.VariableName)),
        ["FunctionDefinition/Name"] = Tags.Function(Tags.Definition(Tags.VariableName)),
        ["ClassDeclaration/Name"] = Tags.Definition(Tags.ClassName),
        ["UpdateOp"] = Tags.UpdateOperator,
        ["ArithOp"] = Tags.ArithmeticOperator,
        ["LogicOp IntersectionType/&"] = Tags.LogicOperator,
        ["BitOp"] = Tags.BitwiseOperator,
        ["CompareOp"] = Tags.CompareOperator,
        ["ControlOp"] = Tags.ControlOperator,
        ["AssignOp"] = Tags.DefinitionOperator,
        ["$ ConcatOp"] = Tags.Operator,
        ["LineComment"] = Tags.LineComment,
        ["BlockComment"] = Tags.BlockComment,
        ["Integer"] = Tags.Integer,
        ["Float"] = Tags.Float,
        ["String"] = Tags.String,
        ["ShellExpression"] = Tags.Special(Tags.String),
        ["=> ->"] = Tags.Punctuation,
        ["( )"] = Tags.Paren,
        ["#[ [ ]"] = Tags.SquareBracket,
        ["${ { }"] = Tags.Brace,
        ["-> ?->"] = Tags.DerefOperator,
        [", ; :: : \\"] = Tags.Separator,
        ["PhpOpen PhpClose"] = Tags.ProcessingInstruction,
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var termTable = PhpParserData.TermTable!;
        var externals = new Dictionary<string, ITokenizer>
        {
            ["expression"] = MakePhpExternalTokenizer("expression", termTable),
            ["interpolated"] = MakePhpExternalTokenizer("interpolated", termTable),
            ["semicolon"] = MakePhpExternalTokenizer("semicolon", termTable),
            ["eofToken"] = MakePhpExternalTokenizer("eofToken", termTable),
        };
        var keywordFn = (Func<string, Stack, int>)((value, stack) => Keywords(value, termTable));
        var externalSpecializers = new Dictionary<string, Func<string, Stack, int>>
        {
            ["keywords"] = keywordFn,
        };
        var spec = PhpParserData.MakeSpec(
            externals: externals,
            propSources: [PhpHighlighting],
            specializers: externalSpecializers
        );
        return new LRParser(spec);
    }
}
