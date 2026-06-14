using Rezel.Common;

namespace Rezel.Highlight;

public class Tag
{
    private static int _nextTagID;
    public int Id = _nextTagID++;
    public string? Name;
    public readonly List<Tag> Set;
    public readonly Tag? Base;
    public readonly Modifier[] Modified;

    public Tag(string? name, List<Tag> set, Tag? bas, Modifier[] modified)
    {
        Name = name;
        Set = set;
        Base = bas;
        Modified = modified;
    }

    public override string ToString()
    {
        var name = Name ?? "";
        foreach (var mod in Modified)
            if (mod.Name != null)
                name = mod.Name + "(" + name + ")";
        return name;
    }

    public static Tag Define(string? name = null, Tag? parent = null)
    {
        if (parent?.Base != null) throw new InvalidOperationException("Can not derive from a modified tag");
        var tag = new Tag(name, [], null, []);
        tag.Set.Add(tag);
        if (parent != null)
            foreach (var t in parent.Set)
                tag.Set.Add(t);
        return tag;
    }

    public static Tag Define(Tag parent)
    {
        return Define(null, parent);
    }

    public static Func<Tag, Tag> DefineModifier(string? name = null)
    {
        var mod = new Modifier(name);
        return tag =>
        {
            if (Array.IndexOf(tag.Modified, mod) > -1) return tag;
            return Modifier.Get(
                tag.Base ?? tag,
                tag.Modified.Append(mod).OrderBy(m => m.Id).ToArray());
        };
    }
}

public class Modifier
{
    public readonly List<Tag> Instances = [];
    private static int _nextModifierID;
    public int Id = _nextModifierID++;
    public readonly string? Name;

    public Modifier(string? name)
    {
        Name = name;
    }

    public static Tag Get(Tag bas, Modifier[] mods)
    {
        if (mods.Length == 0) return bas;
        var exists = mods[0].Instances.Find(t => t.Base == bas && SameArray(mods, t.Modified));
        if (exists != null) return exists;
        var set = new List<Tag>();
        var tag = new Tag(bas.Name, set, bas, mods);
        foreach (var m in mods)
            m.Instances.Add(tag);
        var configs = PowerSet(mods);
        foreach (var parent in bas.Set)
            if (parent.Modified.Length == 0)
                foreach (var config in configs)
                    set.Add(Modifier.Get(parent, config));
        return tag;
    }

    private static bool SameArray<T>(T[] a, T[] b)
    {
        return a.Length == b.Length && a.SequenceEqual(b);
    }

    private static T[][] PowerSet<T>(T[] array)
    {
        var sets = new List<T[]> { Array.Empty<T>() };
        for (var i = 0; i < array.Length; i++)
        {
            var e = sets.Count;
            for (var j = 0; j < e; j++)
                sets.Add([.. sets[j], array[i]]);
        }
        return sets.OrderByDescending(s => s.Length).ToArray();
    }
}

public class Rule
{
    public readonly Tag[] Tags;
    public readonly int Mode;
    public readonly string[]? Context;
    public Rule? Next;

    public Rule(Tag[] tags, int mode, string[]? context, Rule? next = null)
    {
        Tags = tags;
        Mode = mode;
        Context = context;
        Next = next;
    }

    public bool Opaque => Mode == 0;
    public bool Inherit => Mode == 1;
    public int Depth => Context?.Length ?? 0;

    public Rule Sort(Rule? other)
    {
        if (other == null || other.Depth < Depth)
        {
            Next = other;
            return this;
        }
        other.Next = Sort(other.Next);
        return other;
    }

    public static readonly Rule Empty = new([], 2, null);
}

public static class ModeConst
{
    public const int Opaque = 0;
    public const int Inherit = 1;
    public const int Normal = 2;
}

public interface Highlighter
{
    string? Style(Tag[] tags);
    Func<NodeType, bool>? Scope { get; }
}

public static class HighlightUtil
{
    private static readonly NodeProp<Rule> RuleNodeProp;

    static HighlightUtil()
    {
        RuleNodeProp = new NodeProp<Rule>(s => null!, (a, b) =>
        {
            Rule? cur = null;
            Rule? root = null;
            Rule? take;
            var aCur = a;
            var bCur = b;
            while (aCur != null || bCur != null)
            {
                if (aCur == null || (bCur != null && aCur.Depth >= bCur.Depth))
                {
                    take = bCur!;
                    bCur = bCur!.Next;
                }
                else
                {
                    take = aCur;
                    aCur = aCur.Next;
                }
                if (cur != null && cur.Mode == take!.Mode && take.Context == null && cur.Context == null)
                    continue;
                var copy = new Rule(take.Tags, take.Mode, take.Context);
                if (cur != null) cur.Next = copy;
                else root = copy;
                cur = copy;
            }
            return root!;
        });
    }

    public static NodePropSource StyleTags(Dictionary<string, object> spec)
    {
        var byName = new Dictionary<string, Rule>();
        foreach (var (prop, tagsVal) in spec)
        {
            Tag[] tagArray = tagsVal switch
            {
                Tag t => [t],
                Tag[] arr => arr,
                _ => throw new ArgumentException("Invalid tag type")
            };
            foreach (var part in prop.Split(' '))
            {
                if (string.IsNullOrEmpty(part)) continue;
                var pieces = new List<string>();
                var mode = ModeConst.Normal;
                var rest = part;
                var pos = 0;
                while (true)
                {
                    if (rest == "..." && pos > 0 && pos + 3 == part.Length)
                    {
                        mode = ModeConst.Inherit;
                        break;
                    }
                    var m = System.Text.RegularExpressions.Regex.Match(rest, "^\"(?:[^\"\\\\]|\\\\.)*\"|[^/!]+");
                    if (!m.Success) throw new ArgumentException("Invalid path: " + part);
                    pieces.Add(m.Value == "*" ? "" : m.Value[0] == '"' ? System.Text.Json.JsonSerializer.Deserialize<string>(m.Value) ?? "" : m.Value);
                    pos += m.Value.Length;
                    if (pos == part.Length) break;
                    var next = part[pos++];
                    if (pos == part.Length && next == '!')
                    {
                        mode = ModeConst.Opaque;
                        break;
                    }
                    if (next != '/') throw new ArgumentException("Invalid path: " + part);
                    rest = part[pos..];
                }
                var last = pieces.Count - 1;
                var inner = pieces[last];
                if (string.IsNullOrEmpty(inner)) throw new ArgumentException("Invalid path: " + part);
                var rule = new Rule(tagArray, mode, last > 0 ? pieces[..last].ToArray() : null);
                if (byName.TryGetValue(inner, out var existing))
                    byName[inner] = rule.Sort(existing);
                else
                    byName[inner] = rule;
            }
        }
        return RuleNodeProp.Add(byName);
    }

    public static Highlighter TagHighlighter(
        (object Tag, string Class)[] tagClasses,
        Func<NodeType, bool>? scope = null,
        string? all = null)
    {
        var map = new Dictionary<int, string?>();
        foreach (var (tag, cssClass) in tagClasses)
        {
            switch (tag)
            {
                case Tag t:
                    map[t.Id] = cssClass;
                    break;
                case Tag[] arr:
                    foreach (var t in arr)
                        map[t.Id] = cssClass;
                    break;
            }
        }
        return new TagHighlighterImpl(map, scope, all);
    }

    public static void HighlightTree(
        Tree tree,
        Highlighter highlighter,
        Action<int, int, string> putStyle,
        int from = 0,
        int to = -1)
    {
        to = to < 0 ? tree.Length : to;
        var builder = new HighlightBuilder(from, [highlighter], putStyle);
        builder.HighlightRange(tree.Cursor(), from, to, "", builder.Highlighters);
        builder.Flush(to);
    }

    public static void HighlightCode(
        string code,
        Tree tree,
        Highlighter highlighter,
        Action<string, string> putText,
        Action putBreak,
        int from = 0,
        int to = -1)
    {
        to = to < 0 ? code.Length : to;
        var pos = from;
        void WriteTo(int p, string classes)
        {
            if (p <= pos) return;
            var text = code[pos..p];
            var i = 0;
            while (true)
            {
                var nextBreak = text.IndexOf('\n', i);
                var upto = nextBreak < 0 ? text.Length : nextBreak;
                if (upto > i) putText(text[i..upto], classes);
                if (nextBreak < 0) break;
                putBreak();
                i = nextBreak + 1;
            }
            pos = p;
        }
        HighlightTree(
            tree,
            highlighter,
            (f, t2, classes) =>
            {
                WriteTo(f, "");
                WriteTo(t2, classes);
            },
            from,
            to);
        WriteTo(to, "");
    }

    public static (Tag[] Tags, bool Opaque, bool Inherit)? GetStyleTags(ISyntaxNodeRef node)
    {
        var rule = node.Type.Prop(RuleNodeProp);
        while (rule != null && rule.Context != null && !node.MatchContext(rule.Context))
            rule = rule.Next;
        return rule != null ? (rule.Tags, rule.Opaque, rule.Inherit) : null;
    }

    internal static string HighlightTags(Highlighter[] highlighters, Tag[] tags)
    {
        string? result = null;
        foreach (var h in highlighters)
        {
            var value = h.Style(tags);
            if (value != null)
                result = result != null ? result + " " + value : value;
        }
        return result ?? "";
    }
}

internal class TagHighlighterImpl : Highlighter
{
    private readonly Dictionary<int, string?> _map;
    private readonly string? _all;

    public Func<NodeType, bool>? Scope { get; }

    public TagHighlighterImpl(Dictionary<int, string?> map, Func<NodeType, bool>? scope, string? all)
    {
        _map = map;
        Scope = scope;
        _all = all;
    }

    public string? Style(Tag[] tags)
    {
        var cls = _all;
        foreach (var tag in tags)
        {
            foreach (var sub in tag.Set)
            {
                if (_map.TryGetValue(sub.Id, out var tagClass) && tagClass != null)
                {
                    cls = cls != null ? cls + " " + tagClass : tagClass;
                    break;
                }
            }
        }
        return cls;
    }
}

internal class HighlightBuilder
{
    public string Class = "";
    public int At;
    public readonly Highlighter[] Highlighters;
    private readonly Action<int, int, string> _span;

    public HighlightBuilder(int at, Highlighter[] highlighters, Action<int, int, string> span)
    {
        At = at;
        Highlighters = highlighters;
        _span = span;
    }

    public void StartSpan(int at, string cls)
    {
        if (cls != Class)
        {
            Flush(at);
            if (at > At) At = at;
            Class = cls;
        }
    }

    public void Flush(int to)
    {
        if (to > At && !string.IsNullOrEmpty(Class))
            _span(At, to, Class);
    }

    public void HighlightRange(
        TreeCursor cursor,
        int from,
        int to,
        string inheritedClass,
        Highlighter[] highlighters)
    {
        var start = cursor.From;
        var end = cursor.To;
        if (start >= to || end <= from) return;

        var type = cursor.Type;
        if (type.IsTop)
            highlighters = Highlighters.Where(h => h.Scope == null || h.Scope!(type)).ToArray();

        var cls = inheritedClass;
        var styleResult = HighlightUtil.GetStyleTags(cursor);
        var ruleTags = styleResult?.Tags ?? [];
        var ruleOpaque = styleResult?.Opaque ?? false;
        var ruleInherit = styleResult?.Inherit ?? false;

        var tagCls = HighlightUtil.HighlightTags(highlighters, ruleTags);
        if (!string.IsNullOrEmpty(tagCls))
        {
            if (!string.IsNullOrEmpty(cls)) cls += " ";
            cls += tagCls;
            if (ruleInherit)
                inheritedClass += (string.IsNullOrEmpty(inheritedClass) ? "" : " ") + tagCls;
        }

        StartSpan(Math.Max(from, start), cls);
        if (ruleOpaque) return;

        var mounted = cursor.Tree?.Prop(NodeProps.Mounted);
        if (mounted != null && mounted.Overlay != null)
        {
            var inner = cursor.Node.Enter(mounted.Overlay[0].From + start, 1);
            if (inner == null) return;
            var innerHighlighters = Highlighters.Where(h => h.Scope == null || h.Scope!(mounted.Tree.Type)).ToArray();
            var hasChild = cursor.FirstChild();
            for (var i = 0; i <= mounted.Overlay.Length; i++)
            {
                CommonRange? next = i < mounted.Overlay.Length ? mounted.Overlay[i] : null;
                var nextPos = next != null ? next.Value.From + start : end;
                var rangeFrom = Math.Max(from, i == 0 ? start : mounted.Overlay[i - 1].To + start);
                var rangeTo = Math.Min(to, nextPos);
                if (rangeFrom < rangeTo && hasChild)
                {
                    while (cursor.From < rangeTo)
                    {
                        HighlightRange(cursor, rangeFrom, rangeTo, inheritedClass, highlighters);
                        StartSpan(Math.Min(rangeTo, cursor.To), cls);
                        if (cursor.To >= nextPos || !cursor.NextSibling()) break;
                    }
                }
                if (next == null || nextPos > to) break;
                var pos = next.Value.To + start;
                if (pos > from)
                {
                    var innerCursor = inner.Cursor();
                    HighlightRange(
                        innerCursor,
                        Math.Max(from, next.Value.From + start),
                        Math.Min(to, pos),
                        "",
                        innerHighlighters);
                    StartSpan(Math.Min(to, pos), cls);
                }
            }
            if (hasChild) cursor.Parent();
        }
        else if (cursor.FirstChild())
        {
            if (mounted != null) inheritedClass = "";
            do
            {
                if (cursor.To <= from) continue;
                if (cursor.From >= to) break;
                HighlightRange(cursor, from, to, inheritedClass, highlighters);
                StartSpan(Math.Min(to, cursor.To), cls);
            } while (cursor.NextSibling());
            cursor.Parent();
        }
    }
}

public static class Tags
{
    private static readonly Tag _comment = Tag.Define();
    private static readonly Tag _name = Tag.Define();
    private static readonly Tag _typeName = Tag.Define(_name);
    private static readonly Tag _propertyName = Tag.Define(_name);
    private static readonly Tag _literal = Tag.Define();
    private static readonly Tag _string = Tag.Define(_literal);
    private static readonly Tag _number = Tag.Define(_literal);
    private static readonly Tag _content = Tag.Define();
    private static readonly Tag _heading = Tag.Define(_content);
    private static readonly Tag _keyword = Tag.Define();
    private static readonly Tag _operator = Tag.Define();
    private static readonly Tag _punctuation = Tag.Define();
    private static readonly Tag _bracket = Tag.Define(_punctuation);
    private static readonly Tag _meta = Tag.Define();

    public static readonly Tag Comment = _comment;
    public static readonly Tag LineComment = Tag.Define(_comment);
    public static readonly Tag BlockComment = Tag.Define(_comment);
    public static readonly Tag DocComment = Tag.Define(_comment);
    public static readonly Tag Name = _name;
    public static readonly Tag VariableName = Tag.Define(_name);
    public static readonly Tag TypeName = _typeName;
    public static readonly Tag TagName = Tag.Define(_typeName);
    public static readonly Tag PropertyName = _propertyName;
    public static readonly Tag AttributeName = Tag.Define(_propertyName);
    public static readonly Tag ClassName = Tag.Define(_name);
    public static readonly Tag LabelName = Tag.Define(_name);
    public static readonly Tag Namespace = Tag.Define(_name);
    public static readonly Tag MacroName = Tag.Define(_name);
    public static readonly Tag Literal = _literal;
    public static readonly Tag String = _string;
    public static readonly Tag DocString = Tag.Define(_string);
    public static readonly Tag Character = Tag.Define(_string);
    public static readonly Tag AttributeValue = Tag.Define(_string);
    public static readonly Tag Number = _number;
    public static readonly Tag Integer = Tag.Define(_number);
    public static readonly Tag Float = Tag.Define(_number);
    public static readonly Tag Bool = Tag.Define(_literal);
    public static readonly Tag Regexp = Tag.Define(_literal);
    public static readonly Tag Escape = Tag.Define(_literal);
    public static readonly Tag Color = Tag.Define(_literal);
    public static readonly Tag Url = Tag.Define(_literal);
    public static readonly Tag Keyword = _keyword;
    public static readonly Tag Self = Tag.Define(_keyword);
    public static readonly Tag Null = Tag.Define(_keyword);
    public static readonly Tag Atom = Tag.Define(_keyword);
    public static readonly Tag Unit = Tag.Define(_keyword);
    public static readonly Tag ModifierTag = Tag.Define(_keyword);
    public static readonly Tag OperatorKeyword = Tag.Define(_keyword);
    public static readonly Tag ControlKeyword = Tag.Define(_keyword);
    public static readonly Tag DefinitionKeyword = Tag.Define(_keyword);
    public static readonly Tag ModuleKeyword = Tag.Define(_keyword);
    public static readonly Tag Operator = _operator;
    public static readonly Tag DerefOperator = Tag.Define(_operator);
    public static readonly Tag ArithmeticOperator = Tag.Define(_operator);
    public static readonly Tag LogicOperator = Tag.Define(_operator);
    public static readonly Tag BitwiseOperator = Tag.Define(_operator);
    public static readonly Tag CompareOperator = Tag.Define(_operator);
    public static readonly Tag UpdateOperator = Tag.Define(_operator);
    public static readonly Tag DefinitionOperator = Tag.Define(_operator);
    public static readonly Tag TypeOperator = Tag.Define(_operator);
    public static readonly Tag ControlOperator = Tag.Define(_operator);
    public static readonly Tag Punctuation = _punctuation;
    public static readonly Tag Separator = Tag.Define(_punctuation);
    public static readonly Tag Bracket = _bracket;
    public static readonly Tag AngleBracket = Tag.Define(_bracket);
    public static readonly Tag SquareBracket = Tag.Define(_bracket);
    public static readonly Tag Paren = Tag.Define(_bracket);
    public static readonly Tag Brace = Tag.Define(_bracket);
    public static readonly Tag Content = _content;
    public static readonly Tag Heading = _heading;
    public static readonly Tag Heading1 = Tag.Define(_heading);
    public static readonly Tag Heading2 = Tag.Define(_heading);
    public static readonly Tag Heading3 = Tag.Define(_heading);
    public static readonly Tag Heading4 = Tag.Define(_heading);
    public static readonly Tag Heading5 = Tag.Define(_heading);
    public static readonly Tag Heading6 = Tag.Define(_heading);
    public static readonly Tag ContentSeparator = Tag.Define(_content);
    public static readonly Tag List = Tag.Define(_content);
    public static readonly Tag Quote = Tag.Define(_content);
    public static readonly Tag Emphasis = Tag.Define(_content);
    public static readonly Tag Strong = Tag.Define(_content);
    public static readonly Tag Link = Tag.Define(_content);
    public static readonly Tag Monospace = Tag.Define(_content);
    public static readonly Tag Strikethrough = Tag.Define(_content);
    public static readonly Tag Inserted = Tag.Define();
    public static readonly Tag Deleted = Tag.Define();
    public static readonly Tag Changed = Tag.Define();
    public static readonly Tag Invalid = Tag.Define();
    public static readonly Tag Meta = _meta;
    public static readonly Tag DocumentMeta = Tag.Define(_meta);
    public static readonly Tag Annotation = Tag.Define(_meta);
    public static readonly Tag ProcessingInstruction = Tag.Define(_meta);

    public static readonly Func<Tag, Tag> Definition = Tag.DefineModifier("definition");
    public static readonly Func<Tag, Tag> Constant = Tag.DefineModifier("constant");
    public static readonly Func<Tag, Tag> Function = Tag.DefineModifier("function");
    public static readonly Func<Tag, Tag> Standard = Tag.DefineModifier("standard");
    public static readonly Func<Tag, Tag> Local = Tag.DefineModifier("local");
    public static readonly Func<Tag, Tag> Special = Tag.DefineModifier("special");
}

public static class HighlightDefs
{
    public static readonly Highlighter ClassHighlighter = HighlightUtil.TagHighlighter(
    [
        (Tags.Link, "tok-link"),
        (Tags.Heading, "tok-heading"),
        (Tags.Emphasis, "tok-emphasis"),
        (Tags.Strong, "tok-strong"),
        (Tags.Keyword, "tok-keyword"),
        (Tags.Atom, "tok-atom"),
        (Tags.Bool, "tok-bool"),
        (Tags.Url, "tok-url"),
        (Tags.LabelName, "tok-labelName"),
        (Tags.Inserted, "tok-inserted"),
        (Tags.Deleted, "tok-deleted"),
        (Tags.Literal, "tok-literal"),
        (Tags.String, "tok-string"),
        (Tags.Number, "tok-number"),
        (new Tag[] { Tags.Regexp, Tags.Escape, Tags.Special(Tags.String) }, "tok-string2"),
        (Tags.VariableName, "tok-variableName"),
        (Tags.Local(Tags.VariableName), "tok-variableName tok-local"),
        (Tags.Definition(Tags.VariableName), "tok-variableName tok-definition"),
        (Tags.Special(Tags.VariableName), "tok-variableName2"),
        (Tags.Definition(Tags.PropertyName), "tok-propertyName tok-definition"),
        (Tags.TypeName, "tok-typeName"),
        (Tags.Namespace, "tok-namespace"),
        (Tags.ClassName, "tok-className"),
        (Tags.MacroName, "tok-macroName"),
        (Tags.PropertyName, "tok-propertyName"),
        (Tags.Operator, "tok-operator"),
        (Tags.Comment, "tok-comment"),
        (Tags.Meta, "tok-meta"),
        (Tags.Invalid, "tok-invalid"),
        (Tags.Punctuation, "tok-punctuation"),
    ]);
}
