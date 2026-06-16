using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class XmlGrammar
{
    private class ElementContext
    {
        public string? Name;
        public ElementContext? Parent;

        public ElementContext(string? name, ElementContext? parent)
        {
            Name = name;
            Parent = parent;
        }
    }

    private const int LessThan = 60;
    private const int Slash = 47;
    private const int Bang = 33;
    private const int Question = 63;

    private static bool XmlNameChar(int ch)
    {
        return ch == 45 || ch == 46 || ch == 58 || (ch >= 65 && ch <= 90) || ch == 95 || (ch >= 97 && ch <= 122) || ch >= 161;
    }

    private static bool IsSpaceChar(int ch)
    {
        return ch == 9 || ch == 10 || ch == 13 || ch == 32;
    }

    private static string? TagNameAfter(InputStream input, int offset)
    {
        while (IsSpaceChar(input.Peek(offset))) offset++;
        var name = "";
        while (true)
        {
            var next = input.Peek(offset);
            if (!XmlNameChar(next)) break;
            name += (char)next;
            offset++;
        }
        return name.Length > 0 ? name : null;
    }

    private static string TermName(Stack stack, int term)
    {
        return stack.Parser.TermNames?.GetValueOrDefault(term) ?? "";
    }

    private static readonly ContextTracker XmlElementContext = new(
        start: null,
        shift: (context, term, stack, input) =>
        {
            return TermName(stack, term) == "StartTag"
                ? new ElementContext(TagNameAfter(input, 1) ?? "", context as ElementContext)
                : context;
        },
        reduce: (context, term, stack, _) =>
        {
            return TermName(stack, term) == "Element" && context is ElementContext ctx
                ? ctx.Parent
                : context;
        },
        reuse: (context, node, stack, input) =>
        {
            var typeName = stack.Parser.TermNames?.GetValueOrDefault(node.Type.Id) ?? "";
            return typeName is "StartTag" or "OpenTag"
                ? new ElementContext(TagNameAfter(input, 1) ?? "", context as ElementContext)
                : context;
        },
        @strict: false
    );

    private static ITokenizer MakeXmlExternalTokenizer(string name, Dictionary<string, int> terms)
    {
        if (name == "startTag")
        {
            var StartTag = terms["StartTag"];
            var StartCloseTag = terms["StartCloseTag"];
            var mismatchedStartCloseTag = terms["mismatchedStartCloseTag"];
            var incompleteStartCloseTag = terms["incompleteStartCloseTag"];
            var MissingCloseTag = terms["MissingCloseTag"];

            return new ExternalTokenizer((input, stack) =>
            {
                if (input.Next != LessThan) return;
                input.Advance();
                if (input.Next == Slash)
                {
                    input.Advance();
                    var tagName = TagNameAfter(input, 0);
                    if (tagName == null) { input.AcceptToken(incompleteStartCloseTag); return; }
                    var elementCtx = stack.Context as ElementContext;
                    if (elementCtx != null && tagName == elementCtx.Name) { input.AcceptToken(StartCloseTag); return; }
                    for (var c = elementCtx; c != null; c = c.Parent)
                        if (c.Name == tagName) { input.AcceptToken(MissingCloseTag, endOffset: -2); return; }
                    input.AcceptToken(mismatchedStartCloseTag);
                }
                else if (input.Next != Bang && input.Next != Question)
                {
                    input.AcceptToken(StartTag);
                }
            }, contextual: true);
        }

        if (name == "commentContent")
        {
            var commentContent = terms["commentContent"];
            return ScanTo(commentContent, "-->");
        }

        if (name == "piContent")
        {
            var piContent = terms["piContent"];
            return ScanTo(piContent, "?>");
        }

        if (name == "cdataContent")
        {
            var cdataContent = terms["cdataContent"];
            return ScanTo(cdataContent, "]]>");
        }

        throw new ArgumentException($"Unknown XML external tokenizer: {name}");
    }

    private static ITokenizer ScanTo(int type, string end)
    {
        return new ExternalTokenizer((input, _) =>
        {
            var len = 0;
            var first = (int)end[0];
            while (true)
            {
                if (input.Next < 0) break;
                if (input.Next == first)
                {
                    var match = true;
                    for (var i = 1; i < end.Length; i++)
                    {
                        if (input.Peek(i) != end[i]) { match = false; break; }
                    }
                    if (match) break;
                }
                input.Advance();
                len++;
            }
            if (len > 0) input.AcceptToken(type);
        });
    }

    private static readonly NodePropSource XmlHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["Text"] = Tags.Content,
        ["StartTag StartCloseTag EndTag SelfCloseEndTag"] = Tags.AngleBracket,
        ["TagName"] = Tags.TagName,
        ["MismatchedCloseTag/TagName"] = new[] { Tags.TagName, Tags.Invalid },
        ["AttributeName"] = Tags.AttributeName,
        ["AttributeValue"] = Tags.AttributeValue,
        ["Is"] = Tags.DefinitionOperator,
        ["EntityReference CharacterReference"] = Tags.Character,
        ["Comment"] = Tags.BlockComment,
        ["ProcessingInst"] = Tags.ProcessingInstruction,
        ["DoctypeDecl"] = Tags.DocumentMeta,
        ["Cdata"] = Tags.Special(Tags.String),
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var termTable = XmlParserData.TermTable!;
        var externals = new Dictionary<string, ITokenizer>
        {
            ["startTag"] = MakeXmlExternalTokenizer("startTag", termTable),
            ["commentContent"] = MakeXmlExternalTokenizer("commentContent", termTable),
            ["piContent"] = MakeXmlExternalTokenizer("piContent", termTable),
            ["cdataContent"] = MakeXmlExternalTokenizer("cdataContent", termTable),
        };
        var spec = XmlParserData.MakeSpec(
            externals: externals,
            propSources: [XmlHighlighting],
            context: XmlElementContext
        );
        return new LRParser(spec);
    }
}
