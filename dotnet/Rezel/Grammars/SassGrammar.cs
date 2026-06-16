using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class SassGrammar
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
    private const int BraceL = 123;
    private const int BraceR = 125;
    private const int Slash = 47;
    private const int Asterisk = 42;
    private const int NewlineChar = 10;
    private const int EqualsChar = 61;
    private const int Plus = 43;
    private const int And = 38;

    private static bool IsAlpha(int ch) => (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch >= 161;
    private static bool IsDigit(int ch) => ch >= 48 && ch <= 57;

    private static bool StartOfComment(InputStream input)
    {
        return input.Next == Slash && ((input.Peek(1) == Slash) || (input.Peek(1) == Asterisk));
    }

    private class IndentLevel
    {
        public IndentLevel? Parent;
        public int Depth;
        public int Hash;

        public IndentLevel(IndentLevel? parent, int depth)
        {
            Parent = parent;
            Depth = depth;
            Hash = (parent != null ? parent.Hash + (parent.Hash << 8) : 0) + depth + (depth << 4);
        }
    }

    private static readonly IndentLevel TopIndent = new(null, 0);

    private static ContextTracker MakeSassTrackIndent()
    {
        return new ContextTracker(
            start: TopIndent,
            shift: (context, term, stack, input) =>
            {
                var ctx = (IndentLevel)context!;
                var name = stack.Parser.TermNames?.GetValueOrDefault(term) ?? "";
                if (name == "indent") return new IndentLevel(ctx, stack.Pos - input.Pos);
                if (name == "dedent") return ctx.Parent!;
                return ctx;
            },
            hash: (context) => ((IndentLevel)context!).Hash
        );
    }

    private static int? DialectIndex(LRParser parser, string name)
    {
        var keys = parser.Dialects.Keys.ToArray();
        var idx = Array.IndexOf(keys, name);
        return idx >= 0 ? idx : null;
    }

    private static ITokenizer MakeSassExternalTokenizer(string name, Dictionary<string, int> terms)
    {
        if (name == "spaces")
        {
            var eof = terms["eof"];
            var blankLineStart = terms["blankLineStart"];
            var newlineTerm = terms["newline"];
            var whitespace = terms["whitespace"];

            return new ExternalTokenizer((input, stack) =>
            {
                var indentedIdx = DialectIndex(stack.Parser, "indented");
                if (indentedIdx.HasValue && stack.DialectEnabled(indentedIdx.Value))
                {
                    if (input.Next < 0 && stack.CanShift(eof))
                    {
                        input.AcceptToken(eof);
                    }
                    else
                    {
                        var prev = input.Peek(-1);
                        if ((prev == NewlineChar || prev < 0) && stack.CanShift(blankLineStart))
                        {
                            var spaces = 0;
                            while (input.Next != NewlineChar && Space.Contains(input.Next)) { input.Advance(); spaces++; }
                            if (input.Next == NewlineChar || StartOfComment(input))
                                input.AcceptToken(blankLineStart, endOffset: -spaces);
                            else if (spaces > 0)
                                input.AcceptToken(whitespace);
                        }
                        else if (input.Next == NewlineChar)
                        {
                            input.AcceptToken(newlineTerm, endOffset: 1);
                        }
                        else if (Space.Contains(input.Next))
                        {
                            input.Advance();
                            while (input.Next != NewlineChar && Space.Contains(input.Next)) input.Advance();
                            input.AcceptToken(whitespace);
                        }
                    }
                }
                else
                {
                    var length = 0;
                    while (Space.Contains(input.Next))
                    {
                        input.Advance();
                        length++;
                    }
                    if (length > 0) input.AcceptToken(whitespace);
                }
            }, contextual: true);
        }

        if (name == "comments")
        {
            var LineComment = terms["LineComment"];
            var Comment = terms["Comment"];

            return new ExternalTokenizer((input, stack) =>
            {
                if (!StartOfComment(input)) return;
                input.Advance();
                var indentedIdx = DialectIndex(stack.Parser, "indented");
                if (indentedIdx.HasValue && stack.DialectEnabled(indentedIdx.Value))
                {
                    var indentedComment = -1;
                    for (var off = 1; ; off++)
                    {
                        var prev = input.Peek(-off - 1);
                        if (prev == NewlineChar || prev < 0)
                        {
                            indentedComment = off + 1;
                            break;
                        }
                        else if (!Space.Contains(prev))
                        {
                            break;
                        }
                    }
                    if (indentedComment > -1)
                    {
                        var block = input.Next == Asterisk;
                        var end = 0;
                        input.Advance();
                        while (input.Next >= 0)
                        {
                            if (input.Next == NewlineChar)
                            {
                                input.Advance();
                                var indented = 0;
                                while (input.Next != NewlineChar && Space.Contains(input.Next))
                                {
                                    indented++;
                                    input.Advance();
                                }
                                if (indented < indentedComment)
                                {
                                    end = -indented - 1;
                                    break;
                                }
                            }
                            else if (block && input.Next == Asterisk && input.Peek(1) == Slash)
                            {
                                end = 2;
                                break;
                            }
                            else
                            {
                                input.Advance();
                            }
                        }
                        input.AcceptToken(block ? Comment : LineComment, endOffset: end);
                        return;
                    }
                }
                if (input.Next == Slash)
                {
                    while (input.Next != NewlineChar && input.Next >= 0) input.Advance();
                    input.AcceptToken(LineComment);
                }
                else
                {
                    input.Advance();
                    while (input.Next >= 0)
                    {
                        var next = input.Next;
                        input.Advance();
                        if (next == Asterisk && input.Next == Slash)
                        {
                            input.Advance();
                            break;
                        }
                    }
                    input.AcceptToken(Comment);
                }
            });
        }

        if (name == "indentedMixins")
        {
            var IndentedMixin = terms["IndentedMixin"];
            var IndentedInclude = terms["IndentedInclude"];

            return new ExternalTokenizer((input, stack) =>
            {
                var indentedIdx = DialectIndex(stack.Parser, "indented");
                if (indentedIdx.HasValue && stack.DialectEnabled(indentedIdx.Value))
                {
                    if (input.Next == Plus || input.Next == EqualsChar)
                        input.AcceptToken(input.Next == EqualsChar ? IndentedMixin : IndentedInclude, endOffset: 1);
                }
            });
        }

        if (name == "indentation")
        {
            var dedent = terms["dedent"];
            var indent = terms["indent"];

            return new ExternalTokenizer((input, stack) =>
            {
                var indentedIdx = DialectIndex(stack.Parser, "indented");
                if (!indentedIdx.HasValue || !stack.DialectEnabled(indentedIdx.Value)) return;
                var ctx = (IndentLevel)stack.Context!;
                if (input.Next < 0 && ctx.Depth != 0)
                {
                    input.AcceptToken(dedent);
                    return;
                }
                var prev = input.Peek(-1);
                if (prev == NewlineChar)
                {
                    var depth = 0;
                    while (input.Next != NewlineChar && Space.Contains(input.Next))
                    {
                        input.Advance();
                        depth++;
                    }
                    if (depth != ctx.Depth &&
                        input.Next != NewlineChar && !StartOfComment(input))
                    {
                        if (depth < ctx.Depth) input.AcceptToken(dedent, endOffset: -depth);
                        else input.AcceptToken(indent);
                    }
                }
            });
        }

        if (name == "identifiers")
        {
            var identifier = terms["identifier"];
            var callee = terms["callee"];
            var varName = terms["VariableName"];
            var queryIdentifier = terms["queryIdentifier"];
            var InterpolationStart = terms["InterpolationStart"];

            return new ExternalTokenizer((input, stack) =>
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
                    else if (next == Hash && input.Peek(1) == BraceL)
                    {
                        input.AcceptToken(InterpolationStart, endOffset: 2);
                        break;
                    }
                    else
                    {
                        if (inside)
                            input.AcceptToken(
                                dashes == 2 && stack.CanShift(varName) ? varName
                                : stack.CanShift(queryIdentifier) ? queryIdentifier
                                : next == ParenL ? callee
                                : identifier);
                        break;
                    }
                }
            });
        }

        if (name == "interpolationEnd")
        {
            var InterpolationEnd = terms["InterpolationEnd"];
            var InterpolationContinue = terms["InterpolationContinue"];

            return new ExternalTokenizer((input, _) =>
            {
                if (input.Next == BraceR)
                {
                    input.Advance();
                    while (IsAlpha(input.Next) || input.Next == Dash || input.Next == Underscore || IsDigit(input.Next))
                        input.Advance();
                    if (input.Next == Hash && input.Peek(1) == BraceL)
                        input.AcceptToken(InterpolationContinue, endOffset: 2);
                    else
                        input.AcceptToken(InterpolationEnd);
                }
            });
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
                        next == BracketL || (next == Colon && IsAlpha(input.Peek(1))) || next == Dash || next == And || next == Asterisk)
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

        throw new ArgumentException($"Unknown Sass external tokenizer: {name}");
    }

    private static readonly NodePropSource SassHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["AtKeyword import charset namespace keyframes media supports include mixin use forward extend at-root"] = Tags.DefinitionKeyword,
        ["Keyword selector"] = Tags.Keyword,
        ["ControlKeyword"] = Tags.ControlKeyword,
        ["NamespaceName"] = Tags.Namespace,
        ["KeyframeName"] = Tags.LabelName,
        ["KeyframeRangeName"] = Tags.OperatorKeyword,
        ["TagName"] = Tags.TagName,
        ["ClassName Suffix"] = Tags.ClassName,
        ["PseudoClassName"] = Tags.Constant(Tags.ClassName),
        ["IdName"] = Tags.LabelName,
        ["FeatureName PropertyName"] = Tags.PropertyName,
        ["AttributeName"] = Tags.AttributeName,
        ["NumberLiteral"] = Tags.Number,
        ["KeywordQuery"] = Tags.Keyword,
        ["UnaryQueryOp"] = Tags.OperatorKeyword,
        ["CallTag ValueName"] = Tags.Atom,
        ["VariableName"] = Tags.VariableName,
        ["SassVariableName"] = Tags.Special(Tags.VariableName),
        ["Callee"] = Tags.OperatorKeyword,
        ["Unit"] = Tags.Unit,
        ["UniversalSelector NestingSelector IndentedMixin IndentedInclude"] = Tags.DefinitionOperator,
        ["MatchOp"] = Tags.CompareOperator,
        ["ChildOp SiblingOp, LogicOp"] = Tags.LogicOperator,
        ["BinOp"] = Tags.ArithmeticOperator,
        ["Important Global Default"] = Tags.ModifierTag,
        ["Comment"] = Tags.BlockComment,
        ["LineComment"] = Tags.LineComment,
        ["ColorLiteral"] = Tags.Color,
        ["ParenthesizedContent StringLiteral"] = Tags.String,
        ["InterpolationStart InterpolationContinue InterpolationEnd"] = Tags.Meta,
        [": \"...\""] = Tags.Punctuation,
        ["PseudoOp #"] = Tags.DerefOperator,
        ["; ,"] = Tags.Separator,
        ["( )"] = Tags.Paren,
        ["[ ]"] = Tags.SquareBracket,
        ["{ }"] = Tags.Brace,
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var termTable = SassParserData.TermTable!;
        var externals = new Dictionary<string, ITokenizer>
        {
            ["indentation"] = MakeSassExternalTokenizer("indentation", termTable),
            ["descendant"] = MakeSassExternalTokenizer("descendant", termTable),
            ["interpolationEnd"] = MakeSassExternalTokenizer("interpolationEnd", termTable),
            ["unitToken"] = MakeSassExternalTokenizer("unitToken", termTable),
            ["identifiers"] = MakeSassExternalTokenizer("identifiers", termTable),
            ["spaces"] = MakeSassExternalTokenizer("spaces", termTable),
            ["comments"] = MakeSassExternalTokenizer("comments", termTable),
            ["indentedMixins"] = MakeSassExternalTokenizer("indentedMixins", termTable),
        };
        var spec = SassParserData.MakeSpec(
            externals: externals,
            propSources: [SassHighlighting],
            context: MakeSassTrackIndent()
        );
        return new LRParser(spec);
    }
}
