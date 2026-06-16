using System.Text;
using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class YamlGrammar
{
    private const int TypeTop = 0;
    private const int TypeSeq = 1;
    private const int TypeMap = 2;
    private const int TypeFlow = 3;
    private const int TypeLit = 4;

    private class YamlContext
    {
        public YamlContext? Parent;
        public int Depth;
        public int Type;
        public int Hash;

        public YamlContext(YamlContext? parent, int depth, int type)
        {
            Parent = parent;
            Depth = depth;
            Type = type;
            Hash = (parent != null ? parent.Hash + (parent.Hash << 8) : 0) + depth + (depth << 4) + type;
        }
    }

    private static readonly YamlContext TopContext = new(null, -1, TypeTop);

    private static int FindColumn(InputStream input, int pos)
    {
        var col = 0;
        var p = pos - input.Pos - 1;
        while (true)
        {
            var ch = input.Peek(p);
            if (IsBreakSpace(ch) || ch == -1) return col;
            p--;
            col++;
        }
    }

    private static bool IsNonBreakSpace(int ch) => ch == 32 || ch == 9;
    private static bool IsBreakSpace(int ch) => ch == 10 || ch == 13;
    private static bool IsSpace(int ch) => IsNonBreakSpace(ch) || IsBreakSpace(ch);
    private static bool IsSep(int ch) => ch < 0 || IsSpace(ch);

    private static bool Three(InputStream input, int ch, int off = 0)
    {
        return input.Peek(off) == ch && input.Peek(off + 1) == ch && input.Peek(off + 2) == ch && IsSep(input.Peek(off + 3));
    }

    private static bool UriChar(int ch)
    {
        return ch > 32 && ch < 127 && ch != 34 && ch != 37 && ch != 44 && ch != 60 &&
               ch != 62 && ch != 92 && ch != 94 && ch != 96 && ch != 123 && ch != 124 && ch != 125;
    }

    private static bool HexChar(int ch) => (ch >= 48 && ch <= 57) || (ch >= 97 && ch <= 102) || (ch >= 65 && ch <= 70);

    private static bool ReadUriChar(InputStream input, bool quoted)
    {
        if (input.Next == 37)
        {
            input.Advance();
            if (HexChar(input.Next)) input.Advance();
            if (HexChar(input.Next)) input.Advance();
            return true;
        }
        else if (UriChar(input.Next) || (quoted && input.Next == 44))
        {
            input.Advance();
            return true;
        }
        return false;
    }

    private static void ReadTag(InputStream input)
    {
        input.Advance();
        if (input.Next == 60)
        {
            input.Advance();
            while (true)
            {
                if (!ReadUriChar(input, true))
                {
                    if (input.Next == 62) input.Advance();
                    break;
                }
            }
        }
        else
        {
            while (ReadUriChar(input, false)) { }
        }
    }

    private static readonly string CharTable = "iiisiiissisfissssssssssssisssiiissssssssssssssssssssssssssfsfssissssssssssssssssssssssssssfif";

    private static char CharTag(int ch)
    {
        if (ch < 33) return 'u';
        if (ch > 125) return 's';
        return CharTable[ch - 33];
    }

    private static bool IsSafe(int ch, bool inFlow)
    {
        var tag = CharTag(ch);
        return tag != 'u' && !(inFlow && tag == 'f');
    }

    private static void ReadAnchor(InputStream input)
    {
        input.Advance();
        while (!IsSep(input.Next) && CharTag(input.Next) != 'f') input.Advance();
    }

    private static bool ReadQuoted(InputStream input, bool scan)
    {
        var quote = input.Next;
        var lineBreak = false;
        var start = input.Pos;
        input.Advance();
        while (true)
        {
            var ch = input.Next;
            if (ch < 0) break;
            input.Advance();
            if (ch == quote)
            {
                if (ch == 39)
                {
                    if (input.Next == 39) input.Advance();
                    else break;
                }
                else
                {
                    break;
                }
            }
            else if (ch == 92 && quote == 34)
            {
                if (input.Next >= 0) input.Advance();
            }
            else if (IsBreakSpace(ch))
            {
                if (scan) return false;
                lineBreak = true;
            }
            else if (scan && input.Pos >= start + 1024)
            {
                return false;
            }
        }
        return !lineBreak;
    }

    private static bool ScanBrackets(InputStream input)
    {
        var stackB = new List<int>();
        var end = input.Pos + 1024;
        while (true)
        {
            if (input.Next == 91 || input.Next == 123)
            {
                stackB.Add(input.Next);
                input.Advance();
            }
            else if (input.Next == 39 || input.Next == 34)
            {
                if (!ReadQuoted(input, true)) return false;
            }
            else if (input.Next == 93 || input.Next == 125)
            {
                if (stackB.Count == 0 || stackB[stackB.Count - 1] != input.Next - 2) return false;
                stackB.RemoveAt(stackB.Count - 1);
                input.Advance();
                if (stackB.Count == 0) return true;
            }
            else if (input.Next < 0 || input.Pos > end || IsBreakSpace(input.Next))
            {
                return false;
            }
            else
            {
                input.Advance();
            }
        }
    }

    private static bool ReadPlain(InputStream input, bool scan, bool inFlow, int indent)
    {
        if (CharTag(input.Next) == 's' ||
            ((input.Next == 63 || input.Next == 58 || input.Next == 45) &&
             IsSafe(input.Peek(1), inFlow)))
        {
            input.Advance();
        }
        else
        {
            return false;
        }
        var start = input.Pos;
        while (true)
        {
            var next = input.Next;
            var off = 0;
            var lineIndent = indent + 1;
            while (IsSpace(next))
            {
                if (IsBreakSpace(next))
                {
                    if (scan) return false;
                    lineIndent = 0;
                }
                else
                {
                    lineIndent++;
                }
                off++;
                next = input.Peek(off);
            }
            var safe = next >= 0 &&
                (next == 58 ? IsSafe(input.Peek(off + 1), inFlow) :
                 next == 35 ? input.Peek(off - 1) != 32 :
                 IsSafe(next, inFlow));
            if (!safe || (!inFlow && lineIndent <= indent) ||
                (lineIndent == 0 && !inFlow && (Three(input, 45, off) || Three(input, 46, off))))
                break;
            if (scan && CharTag(next) == 'f') return false;
            for (var i = off; i >= 0; i--) input.Advance();
            if (scan && input.Pos > start + 1024) return false;
        }
        return true;
    }

    private static int _termSequenceStartMark, _termMapStartMark, _termExplicitMapStartMark;
    private static int _termBlockEnd, _termBracketL, _termBraceL;
    private static int _termBlockLiteralContent, _termBlockLiteralHeader;
    private static HashSet<int> _flowReduceTerms = new();

    private static void InitTermIds(Dictionary<string, int> terms)
    {
        _termSequenceStartMark = terms["sequenceStartMark"];
        _termMapStartMark = terms["mapStartMark"];
        _termExplicitMapStartMark = terms["explicitMapStartMark"];
        _termBlockEnd = terms["blockEnd"];
        _termBracketL = terms["BracketL"];
        _termBraceL = terms["BraceL"];
        _termBlockLiteralContent = terms["BlockLiteralContent"];
        _termBlockLiteralHeader = terms["BlockLiteralHeader"];
        _flowReduceTerms = new HashSet<int> { terms["FlowSequence"], terms["FlowMapping"] };
    }

    private static ContextTracker MakeYamlIndentation()
    {
        return new ContextTracker(
            start: TopContext,
            reduce: (context, term, stack, input) =>
            {
                var ctx = (YamlContext)context!;
                return (ctx.Type == TypeFlow && _flowReduceTerms.Contains(term)) ? ctx.Parent! : ctx;
            },
            shift: (context, term, stack, input) =>
            {
                var ctx = (YamlContext)context!;
                if (term == _termSequenceStartMark)
                    return new YamlContext(ctx, FindColumn(input, input.Pos), TypeSeq);
                if (term == _termMapStartMark || term == _termExplicitMapStartMark)
                    return new YamlContext(ctx, FindColumn(input, input.Pos), TypeMap);
                if (term == _termBlockEnd)
                    return ctx.Parent!;
                if (term == _termBracketL || term == _termBraceL)
                    return new YamlContext(ctx, 0, TypeFlow);
                if (term == _termBlockLiteralContent && ctx.Type == TypeLit)
                    return ctx.Parent!;
                if (term == _termBlockLiteralHeader)
                {
                    var indentMatch = System.Text.RegularExpressions.Regex.Match(input.Read(input.Pos, stack.Pos), "[1-9]");
                    if (indentMatch.Success)
                        return new YamlContext(ctx, ctx.Depth + int.Parse(indentMatch.Value), TypeLit);
                }
                return ctx;
            },
            hash: (context) => ((YamlContext)context!).Hash
        );
    }

    private static ITokenizer MakeYamlExternalTokenizer(string name, Dictionary<string, int> terms)
    {
        if (name == "newlines")
        {
            var eof = terms["eof"];
            var blockEnd = terms["blockEnd"];
            var DirectiveEnd = terms["DirectiveEnd"];
            var DocEnd = terms["DocEnd"];

            return new ExternalTokenizer((input, stack) =>
            {
                var ctx = (YamlContext)stack.Context!;
                if (input.Next == -1 && stack.CanShift(eof))
                {
                    input.AcceptToken(eof);
                    return;
                }
                var prev = input.Peek(-1);
                if ((IsBreakSpace(prev) || prev < 0) && ctx.Type != TypeFlow)
                {
                    if (Three(input, 45))
                    {
                        if (stack.CanShift(blockEnd)) input.AcceptToken(blockEnd);
                        else { input.AcceptToken(DirectiveEnd, endOffset: 3); return; }
                    }
                    if (Three(input, 46))
                    {
                        if (stack.CanShift(blockEnd)) input.AcceptToken(blockEnd);
                        else { input.AcceptToken(DocEnd, endOffset: 3); return; }
                    }
                    var depth = 0;
                    while (input.Next == 32) { depth++; input.Advance(); }
                    if ((depth < ctx.Depth ||
                         (depth == ctx.Depth && ctx.Type == TypeSeq &&
                          (input.Next != 45 || !IsSep(input.Peek(1))))) &&
                        input.Next != -1 && !IsBreakSpace(input.Next) && input.Next != 35)
                        input.AcceptToken(blockEnd, endOffset: -depth);
                }
            }, contextual: true);
        }

        if (name == "blockMark")
        {
            var sequenceStartMark = terms["sequenceStartMark"];
            var sequenceContinueMark = terms["sequenceContinueMark"];
            var explicitMapStartMark = terms["explicitMapStartMark"];
            var explicitMapContinueMark = terms["explicitMapContinueMark"];
            var mapStartMark = terms["mapStartMark"];
            var mapContinueMark = terms["mapContinueMark"];
            var flowMapMark = terms["flowMapMark"];
            var Colon = terms["Colon"];

            return new ExternalTokenizer((input, stack) =>
            {
                var ctx = (YamlContext)stack.Context!;
                if (ctx.Type == TypeFlow)
                {
                    if (input.Next == 63)
                    {
                        input.Advance();
                        if (IsSep(input.Next)) input.AcceptToken(flowMapMark);
                    }
                    return;
                }
                if (input.Next == 45)
                {
                    input.Advance();
                    if (IsSep(input.Next))
                        input.AcceptToken(ctx.Type == TypeSeq && ctx.Depth == FindColumn(input, input.Pos - 1)
                                          ? sequenceContinueMark : sequenceStartMark);
                }
                else if (input.Next == 63)
                {
                    input.Advance();
                    if (IsSep(input.Next))
                        input.AcceptToken(ctx.Type == TypeMap && ctx.Depth == FindColumn(input, input.Pos - 1)
                                          ? explicitMapContinueMark : explicitMapStartMark);
                }
                else
                {
                    var start = input.Pos;
                    while (true)
                    {
                        if (IsNonBreakSpace(input.Next))
                        {
                            if (input.Pos == start) return;
                            input.Advance();
                        }
                        else if (input.Next == 33)
                        {
                            ReadTag(input);
                        }
                        else if (input.Next == 38)
                        {
                            ReadAnchor(input);
                        }
                        else if (input.Next == 42)
                        {
                            ReadAnchor(input);
                            break;
                        }
                        else if (input.Next == 39 || input.Next == 34)
                        {
                            if (ReadQuoted(input, true)) break;
                            return;
                        }
                        else if (input.Next == 91 || input.Next == 123)
                        {
                            if (!ScanBrackets(input)) return;
                            break;
                        }
                        else
                        {
                            ReadPlain(input, true, false, 0);
                            break;
                        }
                    }
                    while (IsNonBreakSpace(input.Next)) input.Advance();
                    if (input.Next == 58)
                    {
                        if (input.Pos == start && stack.CanShift(Colon)) return;
                        var after = input.Peek(1);
                        if (IsSep(after))
                            input.AcceptTokenTo(ctx.Type == TypeMap && ctx.Depth == FindColumn(input, start)
                                                ? mapContinueMark : mapStartMark, start);
                    }
                }
            }, contextual: true);
        }

        if (name == "literals")
        {
            var Tag = terms["Tag"];
            var Anchor = terms["Anchor"];
            var Alias = terms["Alias"];
            var QuotedLiteral = terms["QuotedLiteral"];
            var Literal = terms["Literal"];

            return new ExternalTokenizer((input, stack) =>
            {
                var ctx = (YamlContext)stack.Context!;
                if (input.Next == 33)
                {
                    ReadTag(input);
                    input.AcceptToken(Tag);
                }
                else if (input.Next == 38 || input.Next == 42)
                {
                    var token = input.Next == 38 ? Anchor : Alias;
                    ReadAnchor(input);
                    input.AcceptToken(token);
                }
                else if (input.Next == 39 || input.Next == 34)
                {
                    ReadQuoted(input, false);
                    input.AcceptToken(QuotedLiteral);
                }
                else if (ReadPlain(input, false, ctx.Type == TypeFlow, ctx.Depth))
                {
                    input.AcceptToken(Literal);
                }
            });
        }

        if (name == "blockLiteral")
        {
            var BlockLiteralContent = terms["BlockLiteralContent"];

            return new ExternalTokenizer((input, stack) =>
            {
                if (!stack.CanShift(BlockLiteralContent)) return;
                var ctx = (YamlContext)stack.Context!;
                var indent = ctx.Type == TypeLit ? ctx.Depth : -1;
                var upto = input.Pos;
                while (true)
                {
                    var depth = 0;
                    var next = input.Next;
                    while (next == 32) { next = input.Peek(++depth); }
                    if (depth == 0 && (Three(input, 45, depth) || Three(input, 46, depth))) break;
                    if (!IsBreakSpace(next))
                    {
                        if (indent < 0) indent = Math.Max(ctx.Depth + 1, depth);
                        if (depth < indent) break;
                    }
                    while (true)
                    {
                        if (input.Next < 0)
                        {
                            input.AcceptTokenTo(BlockLiteralContent, upto);
                            return;
                        }
                        var isBreak = IsBreakSpace(input.Next);
                        input.Advance();
                        if (isBreak) break;
                        upto = input.Pos;
                    }
                }
                input.AcceptTokenTo(BlockLiteralContent, upto);
            });
        }

        throw new ArgumentException($"Unknown YAML external tokenizer: {name}");
    }

    private static readonly NodePropSource YamlHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["DirectiveName"] = Tags.Keyword,
        ["DirectiveContent"] = Tags.AttributeValue,
        ["DirectiveEnd DocEnd"] = Tags.Meta,
        ["QuotedLiteral"] = Tags.String,
        ["BlockLiteralHeader"] = Tags.Special(Tags.String),
        ["BlockLiteralContent"] = Tags.Content,
        ["Literal"] = Tags.Content,
        ["Key/Literal Key/QuotedLiteral"] = Tags.Definition(Tags.PropertyName),
        ["Anchor Alias"] = Tags.LabelName,
        ["Tag"] = Tags.TypeName,
        ["Comment"] = Tags.LineComment,
        [": , -"] = Tags.Separator,
        ["?"] = Tags.Punctuation,
        ["[ ]"] = Tags.SquareBracket,
        ["{ }"] = Tags.Brace,
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var termTable = YamlParserData.TermTable!;
        InitTermIds(termTable);
        var externals = new Dictionary<string, ITokenizer>
        {
            ["newlines"] = MakeYamlExternalTokenizer("newlines", termTable),
            ["blockMark"] = MakeYamlExternalTokenizer("blockMark", termTable),
            ["literals"] = MakeYamlExternalTokenizer("literals", termTable),
            ["blockLiteral"] = MakeYamlExternalTokenizer("blockLiteral", termTable),
        };
        var spec = YamlParserData.MakeSpec(
            externals: externals,
            propSources: [YamlHighlighting],
            context: MakeYamlIndentation()
        );
        return new LRParser(spec);
    }
}
