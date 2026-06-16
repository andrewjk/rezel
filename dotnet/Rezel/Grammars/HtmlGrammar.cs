using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class HtmlGrammar
{
    private class ElementContext
    {
        public string Name;
        public ElementContext? Parent;

        public ElementContext(string name, ElementContext? parent)
        {
            Name = name;
            Parent = parent;
        }
    }

    private static readonly HashSet<string> SelfClosers = [
        "area", "base", "br", "col", "command", "embed", "frame", "hr",
        "img", "input", "keygen", "link", "meta", "param", "source",
        "track", "wbr", "menuitem",
    ];

    private static readonly HashSet<string> ImplicitlyClosed = [
        "dd", "li", "optgroup", "option", "p", "rp", "rt",
        "tbody", "td", "tfoot", "th", "tr",
    ];

    private static readonly Dictionary<string, HashSet<string>> CloseOnOpen = new()
    {
        ["dd"] = ["dd", "dt"],
        ["dt"] = ["dd", "dt"],
        ["li"] = ["li"],
        ["option"] = ["option", "optgroup"],
        ["optgroup"] = ["optgroup"],
        ["p"] = [
            "address", "article", "aside", "blockquote", "dir", "div", "dl",
            "fieldset", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
            "header", "hgroup", "hr", "menu", "nav", "ol", "p", "pre",
            "section", "table", "ul",
        ],
        ["rp"] = ["rp", "rt"],
        ["rt"] = ["rp", "rt"],
        ["tbody"] = ["tbody", "tfoot"],
        ["td"] = ["td", "th"],
        ["tfoot"] = ["tbody"],
        ["th"] = ["td", "th"],
        ["thead"] = ["tbody", "tfoot"],
        ["tr"] = ["tr"],
    };

    private const int LessThan = 60;
    private const int GreaterThan = 62;
    private const int Slash = 47;
    private const int Question = 63;
    private const int Bang = 33;
    private const int Dash = 45;

    private static bool HtmlNameChar(int ch)
    {
        return ch == 45 || ch == 46 || ch == 58 || (ch >= 65 && ch <= 90) || ch == 95 || (ch >= 97 && ch <= 122) || ch >= 161;
    }

    private static string? TagNameAfter(InputStream input, int offset)
    {
        var next = input.Peek(offset);
        var name = "";
        while (true)
        {
            if (!HtmlNameChar(next)) break;
            name += (char)next;
            offset++;
            next = input.Peek(offset);
        }
        if (name.Length > 0) return name.ToLowerInvariant();
        return next == Question || next == Bang ? null : "";
    }

    private static bool InForeignElement(object? context)
    {
        var cx = context as ElementContext;
        while (cx != null)
        {
            if (cx.Name == "svg" || cx.Name == "math") return true;
            cx = cx.Parent;
        }
        return false;
    }

    private static string TermName(Stack stack, int term)
    {
        return stack.Parser.TermNames?.GetValueOrDefault(term) ?? "";
    }

    private static int? DialectIndex(LRParser parser, string name)
    {
        var keys = parser.Dialects.Keys.ToArray();
        var idx = Array.IndexOf(keys, name);
        return idx >= 0 ? idx : null;
    }

    private static ITokenizer MakeContentTokenizer(string tag, int textToken, int endToken)
    {
        var tagChars = tag.Select(c => (int)c).ToArray();
        var lastState = 2 + tagChars.Length;

        return new ExternalTokenizer((input, stack) =>
        {
            var state = 0;
            var matchedLen = 0;
            var i = 0;
            while (true)
            {
                if (input.Next < 0)
                {
                    if (i > 0) input.AcceptToken(textToken);
                    break;
                }
                if ((state == 0 && input.Next == LessThan) ||
                    (state == 1 && input.Next == Slash) ||
                    (state >= 2 && state < lastState && input.Next == tagChars[state - 2]))
                {
                    state++;
                    matchedLen++;
                }
                else if (state == lastState && input.Next == GreaterThan)
                {
                    if (i > matchedLen)
                        input.AcceptToken(textToken, endOffset: -matchedLen);
                    else
                        input.AcceptToken(endToken, endOffset: -(matchedLen - 2));
                    break;
                }
                else if ((input.Next == 10 || input.Next == 13) && i > 0)
                {
                    input.AcceptToken(textToken, endOffset: 1);
                    break;
                }
                else
                {
                    state = 0;
                    matchedLen = 0;
                }
                input.Advance();
                i++;
            }
        });
    }

    private static ITokenizer MakeHtmlExternalTokenizer(string name, Dictionary<string, int> terms)
    {
        if (name == "tagStart")
        {
            var StartTag = terms["StartTag"];
            var StartSelfClosingTag = terms["StartSelfClosingTag"];
            var StartScriptTag = terms["StartScriptTag"];
            var StartStyleTag = terms["StartStyleTag"];
            var StartTextareaTag = terms["StartTextareaTag"];
            var StartCloseTag = terms["StartCloseTag"];
            var NoMatchStartCloseTag = terms["NoMatchStartCloseTag"];
            var MismatchedStartCloseTag = terms["MismatchedStartCloseTag"];
            var missingCloseTag = terms["missingCloseTag"];
            var IncompleteTag = terms["IncompleteTag"];
            var IncompleteCloseTag = terms["IncompleteCloseTag"];

            return new ExternalTokenizer((input, stack) =>
            {
                if (input.Next != LessThan)
                {
                    if (input.Next < 0 && stack.Context != null)
                        input.AcceptToken(missingCloseTag);
                    return;
                }
                input.Advance();
                var close = input.Next == Slash;
                if (close) input.Advance();
                var tagName = TagNameAfter(input, 0);
                if (tagName == null) return;
                if (tagName.Length == 0)
                {
                    input.AcceptToken(close ? IncompleteCloseTag : IncompleteTag);
                    return;
                }

                var parentCtx = stack.Context as ElementContext;
                var parent = parentCtx?.Name;
                if (close)
                {
                    if (tagName == parent)
                    {
                        input.AcceptToken(StartCloseTag);
                    }
                    else if (parent != null && ImplicitlyClosed.Contains(parent))
                    {
                        input.AcceptToken(missingCloseTag, endOffset: -2);
                    }
                    else
                    {
                        var noMatchIdx = DialectIndex(stack.Parser, "noMatch");
                        if (noMatchIdx.HasValue && stack.DialectEnabled(noMatchIdx.Value))
                        {
                            input.AcceptToken(NoMatchStartCloseTag);
                        }
                        else
                        {
                            var cx = stack.Context as ElementContext;
                            while (cx != null)
                            {
                                if (cx.Name == tagName) return;
                                cx = cx.Parent;
                            }
                            input.AcceptToken(MismatchedStartCloseTag);
                        }
                    }
                }
                else
                {
                    if (tagName == "script")
                        input.AcceptToken(StartScriptTag);
                    else if (tagName == "style")
                        input.AcceptToken(StartStyleTag);
                    else if (tagName == "textarea")
                        input.AcceptToken(StartTextareaTag);
                    else if (SelfClosers.Contains(tagName))
                        input.AcceptToken(StartSelfClosingTag);
                    else if (parent != null && CloseOnOpen.TryGetValue(parent, out var closeSet) && closeSet.Contains(tagName))
                        input.AcceptToken(missingCloseTag, endOffset: -1);
                    else
                        input.AcceptToken(StartTag);
                }
            }, contextual: true);
        }

        if (name == "endTag")
        {
            var EndTag = terms["EndTag"];
            var SelfClosingEndTag = terms["SelfClosingEndTag"];

            return new ExternalTokenizer((input, stack) =>
            {
                if (input.Next == Slash && input.Peek(1) == GreaterThan)
                {
                    bool selfClosing;
                    var idx = DialectIndex(stack.Parser, "selfClosing");
                    if (idx.HasValue && stack.DialectEnabled(idx.Value))
                        selfClosing = true;
                    else
                        selfClosing = InForeignElement(stack.Context);
                    input.AcceptToken(selfClosing ? SelfClosingEndTag : EndTag, endOffset: 2);
                }
                else if (input.Next == GreaterThan)
                {
                    input.AcceptToken(EndTag, endOffset: 1);
                }
            });
        }

        if (name == "commentContent")
        {
            var commentContent = terms["commentContent"];

            return new ExternalTokenizer((input, _) =>
            {
                var dashes = 0;
                for (var i = 0; i < int.MaxValue; i++)
                {
                    if (input.Next < 0)
                    {
                        if (i > 0) input.AcceptToken(commentContent);
                        break;
                    }
                    if (input.Next == Dash)
                    {
                        dashes++;
                    }
                    else if (input.Next == GreaterThan && dashes >= 2)
                    {
                        if (i >= 3) input.AcceptToken(commentContent, endOffset: -2);
                        break;
                    }
                    else
                    {
                        dashes = 0;
                    }
                    input.Advance();
                }
            });
        }

        if (name == "scriptTokens")
        {
            var scriptText = terms["scriptText"];
            var StartCloseScriptTag = terms["StartCloseScriptTag"];
            return MakeContentTokenizer("script", scriptText, StartCloseScriptTag);
        }

        if (name == "styleTokens")
        {
            var styleText = terms["styleText"];
            var StartCloseStyleTag = terms["StartCloseStyleTag"];
            return MakeContentTokenizer("style", styleText, StartCloseStyleTag);
        }

        if (name == "textareaTokens")
        {
            var textareaText = terms["textareaText"];
            var StartCloseTextareaTag = terms["StartCloseTextareaTag"];
            return MakeContentTokenizer("textarea", textareaText, StartCloseTextareaTag);
        }

        throw new ArgumentException($"Unknown HTML external tokenizer: {name}");
    }

    private static readonly ContextTracker HtmlElementContext = new(
        start: null,
        shift: (context, term, stack, input) =>
        {
            var name = TermName(stack, term);
            if (name is "StartTag" or "StartSelfClosingTag" or "StartScriptTag" or "StartStyleTag" or "StartTextareaTag")
            {
                var tagName = TagNameAfter(input, 1) ?? "";
                return new ElementContext(tagName, context as ElementContext);
            }
            return context;
        },
        reduce: (context, term, stack, _) =>
        {
            if (TermName(stack, term) == "Element" && context is ElementContext ctx)
                return ctx.Parent;
            return context;
        },
        reuse: (context, node, stack, input) =>
        {
            var typeName = stack.Parser.TermNames?.GetValueOrDefault(node.Type.Id) ?? "";
            if (typeName is "StartTag" or "OpenTag")
            {
                var tagName = TagNameAfter(input, 1) ?? "";
                return new ElementContext(tagName, context as ElementContext);
            }
            return context;
        },
        hash: (context) =>
        {
            if (context is not ElementContext ctx) return 0;
            var h = 0;
            var c = ctx;
            while (c != null)
            {
                h = HashCode.Combine(h, c.Name);
                c = c.Parent;
            }
            return h;
        },
        @strict: false
    );

    private static readonly NodePropSource HtmlHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["Text RawText IncompleteTag IncompleteCloseTag"] = Tags.Content,
        ["StartTag StartCloseTag SelfClosingEndTag EndTag"] = Tags.Bracket,
        ["TagName"] = Tags.TypeName,
        ["MismatchedCloseTag/TagName"] = new[] { Tags.TypeName, Tags.Invalid },
        ["AttributeName"] = Tags.PropertyName,
        ["AttributeValue UnquotedAttributeValue"] = Tags.AttributeValue,
        ["Is"] = Tags.DefinitionKeyword,
        ["EntityReference CharacterReference"] = Tags.Character,
        ["Comment"] = Tags.Comment,
        ["ProcessingInst"] = Tags.ProcessingInstruction,
        ["DoctypeDecl"] = Tags.DocumentMeta,
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var termTable = HtmlParserData.TermTable!;
        var externals = new Dictionary<string, ITokenizer>
        {
            ["scriptTokens"] = MakeHtmlExternalTokenizer("scriptTokens", termTable),
            ["styleTokens"] = MakeHtmlExternalTokenizer("styleTokens", termTable),
            ["textareaTokens"] = MakeHtmlExternalTokenizer("textareaTokens", termTable),
            ["endTag"] = MakeHtmlExternalTokenizer("endTag", termTable),
            ["tagStart"] = MakeHtmlExternalTokenizer("tagStart", termTable),
            ["commentContent"] = MakeHtmlExternalTokenizer("commentContent", termTable),
        };
        var spec = HtmlParserData.MakeSpec(
            externals: externals,
            propSources: [HtmlHighlighting],
            context: HtmlElementContext
        );
        return new LRParser(spec);
    }
}
