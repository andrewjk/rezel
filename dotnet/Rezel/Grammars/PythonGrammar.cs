using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class PythonGrammar
{
    private const int Newline = 10;
    private const int CarriageReturn = 13;
    private const int Space = 32;
    private const int Tab = 9;
    private const int Hash = 35;
    private const int ParenOpen = 40;
    private const int Dot = 46;
    private const int BraceOpen = 123;
    private const int BraceClose = 125;
    private const int SingleQuote = 39;
    private const int DoubleQuote = 34;
    private const int Backslash = 92;
    private const int LetterO = 111;
    private const int LetterX = 120;
    private const int LetterN = 78;
    private const int LetterU = 117;
    private const int LetterBigU = 85;

    private const int CxBracketed = 1;
    private const int CxString = 2;
    private const int CxDoubleQuote = 4;
    private const int CxLong = 8;
    private const int CxRaw = 16;
    private const int CxFormat = 32;

    private class PyContext
    {
        public PyContext? Parent;
        public int Indent;
        public int Flags;
        public int Hash;

        public PyContext(PyContext? parent, int indent, int flags)
        {
            Parent = parent;
            Indent = indent;
            Flags = flags;
            Hash = (parent != null ? parent.Hash + (parent.Hash << 8) : 0) + indent + (indent << 4) + flags + (flags << 6);
        }
    }

    private static readonly PyContext TopIndent = new(null, 0, 0);

    private static bool IsLineBreak(int ch) => ch == Newline || ch == CarriageReturn;
    private static bool IsHex(int ch) => (ch >= 48 && ch <= 57) || (ch >= 65 && ch <= 70) || (ch >= 97 && ch <= 102);

    private static int CountIndent(string spaceStr)
    {
        var depth = 0;
        for (var i = 0; i < spaceStr.Length; i++)
            depth += spaceStr[i] == Tab ? 8 - (depth % 8) : 1;
        return depth;
    }

    private static Dictionary<string, int> _stringFlags = new();

    private static void BuildStringFlags(Dictionary<string, int> terms)
    {
        if (_stringFlags.Count > 0) return;
        _stringFlags["stringStart"] = 0 | CxString;
        _stringFlags["stringStartD"] = CxDoubleQuote | CxString;
        _stringFlags["stringStartL"] = CxLong | CxString;
        _stringFlags["stringStartLD"] = CxLong | CxDoubleQuote | CxString;
        _stringFlags["stringStartR"] = CxRaw | CxString;
        _stringFlags["stringStartRD"] = CxRaw | CxDoubleQuote | CxString;
        _stringFlags["stringStartRL"] = CxRaw | CxLong | CxString;
        _stringFlags["stringStartRLD"] = CxRaw | CxLong | CxDoubleQuote | CxString;
        _stringFlags["stringStartF"] = CxFormat | CxString;
        _stringFlags["stringStartFD"] = CxFormat | CxDoubleQuote | CxString;
        _stringFlags["stringStartFL"] = CxFormat | CxLong | CxString;
        _stringFlags["stringStartFLD"] = CxFormat | CxLong | CxDoubleQuote | CxString;
        _stringFlags["stringStartFR"] = CxFormat | CxRaw | CxString;
        _stringFlags["stringStartFRD"] = CxFormat | CxRaw | CxDoubleQuote | CxString;
        _stringFlags["stringStartFRL"] = CxFormat | CxRaw | CxLong | CxString;
        _stringFlags["stringStartFRLD"] = CxFormat | CxRaw | CxLong | CxDoubleQuote | CxString;
    }

    private static readonly HashSet<string> BracketedNames =
    [
        "ParenthesizedExpression", "TupleExpression", "ComprehensionExpression", "importList", "ArgList", "ParamList",
        "ArrayExpression", "ArrayComprehensionExpression", "subscript",
        "SetExpression", "SetComprehensionExpression", "FormatString", "FormatReplacement", "nestedFormatReplacement",
        "DictionaryExpression", "DictionaryComprehensionExpression",
        "SequencePattern", "MappingPattern", "PatternArgList", "TypeParamList"
    ];

    private static int _termIndent, _termDedent, _termReplacementStart, _termString, _termFormatString;
    private static HashSet<int> _bracketOpens = new();
    private static Dictionary<int, int> _stringFlagById = new();

    private static void InitTermIds(Dictionary<string, int> terms)
    {
        _termIndent = terms["indent"];
        _termDedent = terms["dedent"];
        _termReplacementStart = terms["replacementStart"];
        _termString = terms["String"];
        _termFormatString = terms["FormatString"];
        _bracketOpens = new HashSet<int> { terms["ParenL"], terms["BracketL"], terms["BraceL"] };
        _stringFlagById = new Dictionary<int, int>();
        foreach (var (name, flag) in _stringFlags)
            _stringFlagById[terms[name]] = flag;
    }

    private static ContextTracker MakePythonTrackIndent()
    {
        return new ContextTracker(
            start: TopIndent,
            reduce: (context, term, stack, input) =>
            {
                var ctx = (PyContext)context!;
                var name = stack.Parser.TermNames?.GetValueOrDefault(term) ?? "";
                if ((ctx.Flags & CxBracketed) > 0 && BracketedNames.Contains(name) ||
                    (term == _termString || term == _termFormatString) && (ctx.Flags & CxString) > 0)
                    return ctx.Parent;
                return ctx;
            },
            shift: (context, term, stack, input) =>
            {
                var ctx = (PyContext)context!;
                if (term == _termIndent)
                    return new PyContext(ctx, CountIndent(input.Read(input.Pos, stack.Pos)), 0);
                if (term == _termDedent)
                    return ctx.Parent!;
                if (_bracketOpens.Contains(term) || term == _termReplacementStart)
                    return new PyContext(ctx, 0, CxBracketed);
                if (_stringFlagById.TryGetValue(term, out var sf))
                    return new PyContext(ctx, 0, sf | (ctx.Flags & CxBracketed));
                return ctx;
            },
            hash: (context) => ((PyContext)context!).Hash,
            @strict: false
        );
    }

    private static ITokenizer MakePythonExternalTokenizer(string name, Dictionary<string, int> terms)
    {
        if (name == "newlines")
        {
            var eof = terms["eof"];
            var newlineBracketed = terms["newlineBracketed"];
            var blankLineStart = terms["blankLineStart"];
            var newlineToken = terms["newline"];

            return new ExternalTokenizer((input, stack) =>
            {
                var ctx = (PyContext)stack.Context!;
                if (input.Next < 0)
                {
                    input.AcceptToken(eof);
                }
                else if ((ctx.Flags & CxBracketed) > 0)
                {
                    if (IsLineBreak(input.Next)) input.AcceptToken(newlineBracketed, endOffset: 1);
                }
                else if (((input.Peek(-1) < 0 || IsLineBreak(input.Peek(-1))) && stack.CanShift(blankLineStart)))
                {
                    var spaces = 0;
                    while (input.Next == Space || input.Next == Tab) { input.Advance(); spaces++; }
                    if (input.Next == Newline || input.Next == CarriageReturn || input.Next == Hash)
                        input.AcceptToken(blankLineStart, endOffset: -spaces);
                }
                else if (IsLineBreak(input.Next))
                {
                    input.AcceptToken(newlineToken, endOffset: 1);
                }
            }, contextual: true);
        }

        if (name == "indentation")
        {
            var indent = terms["indent"];
            var dedent = terms["dedent"];

            return new ExternalTokenizer((input, stack) =>
            {
                var ctx = (PyContext)stack.Context!;
                if (ctx.Flags != 0) return;
                var prev = input.Peek(-1);
                if (prev == Newline || prev == CarriageReturn)
                {
                    var depth = 0;
                    var chars = 0;
                    while (true)
                    {
                        if (input.Next == Space) depth++;
                        else if (input.Next == Tab) depth += 8 - (depth % 8);
                        else break;
                        input.Advance();
                        chars++;
                    }
                    if (depth != ctx.Indent &&
                        input.Next != Newline && input.Next != CarriageReturn && input.Next != Hash)
                    {
                        if (depth < ctx.Indent) input.AcceptToken(dedent, endOffset: -chars);
                        else input.AcceptToken(indent);
                    }
                }
            });
        }

        if (name == "legacyPrint")
        {
            var printKeyword = terms["printKeyword"];
            var printStr = "print";

            return new ExternalTokenizer((input, _) =>
            {
                for (var i = 0; i < 5; i++)
                {
                    if (input.Next != printStr[i]) return;
                    input.Advance();
                }
                if (char.IsLetterOrDigit((char)input.Next)) return;
                for (var off = 0; ; off++)
                {
                    var next = input.Peek(off);
                    if (next == Space || next == Tab) continue;
                    if (next != ParenOpen && next != Dot && next != Newline && next != CarriageReturn && next != Hash)
                        input.AcceptToken(printKeyword);
                    return;
                }
            });
        }

        if (name == "strings")
        {
            var stringContent = terms["stringContent"];
            var Escape = terms["Escape"];
            var replacementStart = terms["replacementStart"];
            var stringEnd = terms["stringEnd"];

            return new ExternalTokenizer((input, stack) =>
            {
                var ctx = (PyContext)stack.Context!;
                var flags = ctx.Flags;
                var quote = (flags & CxDoubleQuote) > 0 ? DoubleQuote : SingleQuote;
                var longStr = (flags & CxLong) > 0;
                var escapes = (flags & CxRaw) == 0;
                var format = (flags & CxFormat) > 0;

                var start = input.Pos;
                while (true)
                {
                    if (input.Next < 0)
                    {
                        break;
                    }
                    else if (format && input.Next == BraceOpen)
                    {
                        if (input.Peek(1) == BraceOpen)
                        {
                            input.Advance();
                            input.Advance();
                        }
                        else
                        {
                            if (input.Pos == start)
                            {
                                input.AcceptToken(replacementStart, endOffset: 1);
                                return;
                            }
                            break;
                        }
                    }
                    else if (escapes && input.Next == Backslash)
                    {
                        if (input.Pos == start)
                        {
                            input.Advance();
                            var escaped = input.Next;
                            if (escaped >= 0)
                            {
                                input.Advance();
                                SkipEscape(input, escaped);
                            }
                            input.AcceptToken(Escape);
                            return;
                        }
                        break;
                    }
                    else if (input.Next == Backslash && !escapes && input.Peek(1) > -1)
                    {
                        input.Advance();
                        input.Advance();
                    }
                    else if (input.Next == quote && (!longStr || (input.Peek(1) == quote && input.Peek(2) == quote)))
                    {
                        if (input.Pos == start)
                        {
                            input.AcceptToken(stringEnd, endOffset: longStr ? 3 : 1);
                            return;
                        }
                        break;
                    }
                    else if (input.Next == Newline)
                    {
                        if (longStr)
                        {
                            input.Advance();
                        }
                        else if (input.Pos == start)
                        {
                            input.AcceptToken(stringEnd);
                            return;
                        }
                        break;
                    }
                    else
                    {
                        input.Advance();
                    }
                }
                if (input.Pos > start) input.AcceptToken(stringContent);
            });
        }

        throw new ArgumentException($"Unknown Python external tokenizer: {name}");
    }

    private static void SkipEscape(InputStream input, int ch)
    {
        if (ch == LetterO)
        {
            for (var i = 0; i < 2 && input.Next >= 48 && input.Next <= 55; i++) input.Advance();
        }
        else if (ch == LetterX)
        {
            for (var i = 0; i < 2 && IsHex(input.Next); i++) input.Advance();
        }
        else if (ch == LetterU)
        {
            for (var i = 0; i < 4 && IsHex(input.Next); i++) input.Advance();
        }
        else if (ch == LetterBigU)
        {
            for (var i = 0; i < 8 && IsHex(input.Next); i++) input.Advance();
        }
        else if (ch == LetterN)
        {
            if (input.Next == BraceOpen)
            {
                input.Advance();
                while (input.Next >= 0 && input.Next != BraceClose && input.Next != SingleQuote &&
                       input.Next != DoubleQuote && input.Next != Newline)
                    input.Advance();
                if (input.Next == BraceClose) input.Advance();
            }
        }
    }

    private static readonly NodePropSource PythonHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["async \"*\" \"**\" FormatConversion FormatSpec"] = Tags.ModifierTag,
        ["for while if elif else try except finally return raise break continue with pass assert await yield match case"] = Tags.ControlKeyword,
        ["in not and or is del"] = Tags.OperatorKeyword,
        ["from def class global nonlocal lambda"] = Tags.DefinitionKeyword,
        ["import"] = Tags.ModuleKeyword,
        ["with as print"] = Tags.Keyword,
        ["Boolean"] = Tags.Bool,
        ["None"] = Tags.Null,
        ["VariableName"] = Tags.VariableName,
        ["CallExpression/VariableName"] = Tags.Function(Tags.VariableName),
        ["FunctionDefinition/VariableName"] = Tags.Function(Tags.Definition(Tags.VariableName)),
        ["ClassDefinition/VariableName"] = Tags.Definition(Tags.ClassName),
        ["PropertyName"] = Tags.PropertyName,
        ["CallExpression/MemberExpression/PropertyName"] = Tags.Function(Tags.PropertyName),
        ["Comment"] = Tags.LineComment,
        ["Number"] = Tags.Number,
        ["String"] = Tags.String,
        ["FormatString"] = Tags.Special(Tags.String),
        ["Escape"] = Tags.Escape,
        ["UpdateOp"] = Tags.UpdateOperator,
        ["ArithOp!"] = Tags.ArithmeticOperator,
        ["BitOp"] = Tags.BitwiseOperator,
        ["CompareOp"] = Tags.CompareOperator,
        ["AssignOp"] = Tags.DefinitionOperator,
        ["Ellipsis"] = Tags.Punctuation,
        ["At"] = Tags.Meta,
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
        var termTable = PythonParserData.TermTable!;
        BuildStringFlags(termTable);
        InitTermIds(termTable);
        var externals = new Dictionary<string, ITokenizer>
        {
            ["legacyPrint"] = MakePythonExternalTokenizer("legacyPrint", termTable),
            ["indentation"] = MakePythonExternalTokenizer("indentation", termTable),
            ["newlines"] = MakePythonExternalTokenizer("newlines", termTable),
            ["strings"] = MakePythonExternalTokenizer("strings", termTable),
        };
        var spec = PythonParserData.MakeSpec(
            externals: externals,
            propSources: [PythonHighlighting],
            context: MakePythonTrackIndent()
        );
        return new LRParser(spec);
    }
}
