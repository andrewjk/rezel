using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Rezel.Generator;

public class Input
{
    public string Type = "sof";
    public object? Value;
    public int Start;
    public int End;
    public readonly string Source;
    public readonly string? FileName;

    static readonly Regex SkipRegex = new(@"^(\s|//.*|/\*[\s\S]*?\*/)*", RegexOptions.Compiled);
    static readonly Regex DQStringRegex = new("^(?:\\\\.|[^\"\\\\])*\"", RegexOptions.Compiled);
    static readonly Regex SQStringRegex = new("^(?:\\\\.|[^'\\\\])*'", RegexOptions.Compiled);
    static readonly Regex SetCloseRegex = new("^(?:\\\\.|[^\\]\\\\])*\\]", RegexOptions.Compiled);
    static readonly Regex WordRegex = new(@"[\p{L}\d_-]+", RegexOptions.Compiled);

    static bool IsIdentChar(string source, int pos, out int charLen)
    {
        char ch = source[pos];
        if (char.IsHighSurrogate(ch) && pos + 1 < source.Length && char.IsLowSurrogate(source[pos + 1]))
        {
            int codePoint = char.ConvertToUtf32(ch, source[pos + 1]);
            var cat = CharUnicodeInfo.GetUnicodeCategory(codePoint);
            charLen = 2;
            return cat == UnicodeCategory.UppercaseLetter || cat == UnicodeCategory.LowercaseLetter ||
                   cat == UnicodeCategory.TitlecaseLetter || cat == UnicodeCategory.ModifierLetter ||
                   cat == UnicodeCategory.OtherLetter;
        }
        charLen = 1;
        return ch == '_' || ch == '-' || char.IsLetterOrDigit(ch);
    }
    static readonly Regex SetDashRegex = new(@"\\.|-|""", RegexOptions.Compiled);

    const string SetMarker = "\ufdda";

    public Input(string source, string? fileName = null)
    {
        Source = source;
        FileName = fileName;
        Next();
    }

    public (int line, int ch) LineInfo(int pos)
    {
        int line = 1, cur = 0;
        while (true)
        {
            int next = Source.IndexOf('\n', cur);
            if (next > -1 && next < pos)
            {
                line++;
                cur = next + 1;
            }
            else
            {
                return (line, pos - cur);
            }
        }
    }

    public string Message(string msg, int pos = -1)
    {
        string posInfo = FileName ?? "";
        if (pos > -1)
        {
            var info = LineInfo(pos);
            posInfo += (posInfo.Length > 0 ? " " : "") + info.line + ":" + info.ch;
        }
        return posInfo.Length > 0 ? $"{msg} ({posInfo})" : msg;
    }

    [DoesNotReturn]
    public void Raise(string msg, int pos = -1)
    {
        throw new GenError(Message(msg, pos));
    }

    int MatchFrom(int pos, Regex re)
    {
        var m = re.Match(Source[pos..]);
        return m.Success ? pos + m.Length : -1;
    }

    public void Next()
    {
        int start = MatchFrom(End, SkipRegex);
        if (start == Source.Length) { Set("eof", null, start, start); return; }

        char next = Source[start];
        if (next == '"')
        {
            int end = MatchFrom(start + 1, DQStringRegex);
            if (end == -1) Raise("Unterminated string literal", start);
            Set("string", ReadString(Source[(start + 1)..(end - 1)]), start, end);
        }
        else if (next == '\'')
        {
            int end = MatchFrom(start + 1, SQStringRegex);
            if (end == -1) Raise("Unterminated string literal", start);
            Set("string", ReadString(Source[(start + 1)..(end - 1)]), start, end);
        }
        else if (next == '@')
        {
            int end = start + 1;
            while (end < Source.Length && IsIdentChar(Source, end, out int cl)) end += cl;
            if (end == start + 1) Raise("@ without a name", start);
            Set("at", Source[(start + 1)..end], start, end);
        }
        else if ((next == '$' || next == '!') && start + 1 < Source.Length && Source[start + 1] == '[')
        {
            int end = MatchFrom(start + 2, SetCloseRegex);
            if (end == -1) Raise("Unterminated character set", start);
            Set("set", Source[(start + 2)..(end - 1)], start, end);
        }
        else if ("[]()!~+*?{}<>.,|:$=".Contains(next))
        {
            Set(next.ToString(), null, start, start + 1);
        }
        else
        {
            int end = start;
            while (end < Source.Length && IsIdentChar(Source, end, out int cl)) end += cl;
            if (end > start)
                Set("id", Source[start..end], start, end);
            else
                Raise($"Unexpected character \"{next}\"", start);
        }
    }

    void Set(string type, object? value, int start, int end)
    {
        Type = type;
        Value = value;
        Start = start;
        End = end;
    }

    public bool Eat(string type, object? value = null)
    {
        if (Type == type && (value == null || object.Equals(Value, value)))
        {
            Next();
            return true;
        }
        return false;
    }

    [DoesNotReturn]
    public void Unexpected()
    {
        Raise($"Unexpected token '{Source[Start..End]}'", Start);
    }

    public object? Expect(string type, object? value = null)
    {
        var val = Value;
        if (Type != type || !(value == null || object.Equals(val, value))) Unexpected();
        Next();
        return val;
    }

    public GrammarDeclaration Parse() => ParseGrammar(this);

    static GrammarDeclaration ParseGrammar(Input input)
    {
        int start = input.Start;
        var rules = new List<RuleDeclaration>();
        PrecDeclaration? prec = null;
        TokenDeclaration? tokens = null;
        var localTokens = new List<LocalTokenDeclaration>();
        Expression? mainSkip = null;
        var scopedSkip = new List<ScopedSkipEntry>();
        var dialects = new List<Identifier>();
        ContextDeclaration? context = null;
        var external = new List<ExternalTokenDeclaration>();
        var specialized = new List<ExternalSpecializeDeclaration>();
        var props = new List<ExternalPropDeclaration>();
        var propSources = new List<ExternalPropSourceDeclaration>();
        var tops = new List<RuleDeclaration>();
        bool sawTop = false;
        bool autoDelim = false;

        while (input.Type != "eof")
        {
            int declStart = input.Start;
            if (input.Eat("at", "top"))
            {
                if (input.Type != "id") input.Raise("Top rules must have a name", input.Start);
                tops.Add(ParseRule(input, ParseIdent(input)));
                sawTop = true;
            }
            else if (input.Type == "at" && input.Value is "tokens")
            {
                if (tokens != null) input.Raise("Multiple @tokens declarations", input.Start);
                else tokens = ParseTokens(input);
            }
            else if (input.Eat("at", "local"))
            {
                input.Expect("id", "tokens");
                localTokens.Add(ParseLocalTokens(input, declStart));
            }
            else if (input.Eat("at", "context"))
            {
                if (context != null) input.Raise("Multiple @context declarations", declStart);
                var id = ParseIdent(input);
                input.Expect("id", "from");
                var source = (string)input.Expect("string")!;
                context = new ContextDeclaration(declStart, id, source);
            }
            else if (input.Eat("at", "external"))
            {
                if (input.Eat("id", "tokens")) external.Add(ParseExternalTokens(input, declStart));
                else if (input.Eat("id", "prop")) props.Add(ParseExternalProp(input, declStart));
                else if (input.Eat("id", "extend")) specialized.Add(ParseExternalSpecialize(input, "extend", declStart));
                else if (input.Eat("id", "specialize")) specialized.Add(ParseExternalSpecialize(input, "specialize", declStart));
                else if (input.Eat("id", "propSource")) propSources.Add(ParseExternalPropSource(input, declStart));
                else input.Unexpected();
            }
            else if (input.Eat("at", "dialects"))
            {
                input.Expect("{");
                for (bool first = true; !input.Eat("}"); first = false)
                {
                    if (!first) input.Eat(",");
                    dialects.Add(ParseIdent(input));
                }
            }
            else if (input.Type == "at" && input.Value is "precedence")
            {
                if (prec != null) input.Raise("Multiple precedence declarations", input.Start);
                prec = ParsePrecedence(input);
            }
            else if (input.Eat("at", "detectDelim"))
            {
                autoDelim = true;
            }
            else if (input.Eat("at", "skip"))
            {
                var skip = ParseBracedExpr(input);
                if (input.Type == "{")
                {
                    input.Next();
                    var skipRules = new List<RuleDeclaration>();
                    var topRules = new List<RuleDeclaration>();
                    while (!input.Eat("}"))
                    {
                        if (input.Eat("at", "top"))
                        {
                            topRules.Add(ParseRule(input, ParseIdent(input)));
                            sawTop = true;
                        }
                        else
                        {
                            skipRules.Add(ParseRule(input));
                        }
                    }
                    scopedSkip.Add(new ScopedSkipEntry(skip, topRules.ToArray(), skipRules.ToArray()));
                }
                else
                {
                    if (mainSkip != null) input.Raise("Multiple top-level skip declarations", input.Start);
                    mainSkip = skip;
                }
            }
            else
            {
                rules.Add(ParseRule(input));
            }
        }

        if (!sawTop) input.Raise("Missing @top declaration");

        return new GrammarDeclaration(
            start,
            rules.ToArray(),
            tops.ToArray(),
            tokens,
            localTokens.ToArray(),
            context,
            external.ToArray(),
            specialized.ToArray(),
            propSources.ToArray(),
            prec,
            mainSkip,
            scopedSkip.ToArray(),
            dialects.ToArray(),
            props.ToArray(),
            autoDelim
        );
    }

    static RuleDeclaration ParseRule(Input input, Identifier? named = null)
    {
        int start = named?.Start ?? input.Start;
        var id = named ?? ParseIdent(input);
        var ruleProps = ParseProps(input);
        var parms = new List<Identifier>();
        if (input.Eat("<"))
            while (!input.Eat(">"))
            {
                if (parms.Count > 0) input.Expect(",");
                parms.Add(ParseIdent(input));
            }
        var expr = ParseBracedExpr(input);
        return new RuleDeclaration(start, id, ruleProps, parms.ToArray(), expr);
    }

    static Prop[] ParseProps(Input input)
    {
        if (input.Type != "[") return [];
        var props = new List<Prop>();
        input.Expect("[");
        while (!input.Eat("]"))
        {
            if (props.Count > 0) input.Expect(",");
            props.Add(ParseProp(input));
        }
        return props.ToArray();
    }

    static Prop ParseProp(Input input)
    {
        int start = input.Start;
        var value = new List<PropPart>();
        string name = (string)input.Value!;
        bool at = input.Type == "at";
        if (!input.Eat("at") && !input.Eat("id")) input.Unexpected();
        if (input.Eat("="))
        {
            while (true)
            {
                if (input.Type == "string" || input.Type == "id")
                {
                    value.Add(new PropPart(input.Start, (string?)input.Value, null));
                    input.Next();
                }
                else if (input.Eat("."))
                {
                    value.Add(new PropPart(input.Start, ".", null));
                }
                else if (input.Eat("{"))
                {
                    value.Add(new PropPart(input.Start, null, (string?)input.Expect("id")));
                    input.Expect("}");
                }
                else break;
            }
        }
        return new Prop(start, at, name, value.ToArray());
    }

    static Expression ParseBracedExpr(Input input)
    {
        input.Expect("{");
        var expr = ParseExprChoice(input);
        input.Expect("}");
        return expr;
    }

    static Expression ParseExprInner(Input input)
    {
        int start = input.Start;
        if (input.Eat("("))
        {
            if (input.Eat(")")) return new SequenceExpression(start, [], [[], []]);
            var expr = ParseExprChoice(input);
            input.Expect(")");
            return expr;
        }
        else if (input.Type == "string")
        {
            string value = (string)input.Value!;
            input.Next();
            if (value.Length == 0) return new SequenceExpression(start, [], [[], []]);
            return new LiteralExpression(start, value);
        }
        else if (input.Eat("id", "_"))
        {
            return new AnyExpression(start);
        }
        else if (input.Type == "set")
        {
            string content = (string)input.Value!;
            bool invert = input.Source[input.Start] == '!';
            var unescaped = ReadString(
                SetDashRegex.Replace(content, m =>
                    m.Value == "-" ? SetMarker : m.Value == "\"" ? "\\\"" : m.Value
                )
            );
            var ranges = new List<int[]>();
            for (int pos = 0; pos < unescaped.Length;)
            {
                int code = char.ConvertToUtf32(unescaped, pos);
                int charCount = code > 0xFFFF ? 2 : 1;
                pos += charCount;
                if (pos < unescaped.Length - 1 && unescaped[pos] == SetMarker[0])
                {
                    int endCode = char.ConvertToUtf32(unescaped, pos + 1);
                    int endCharCount = endCode > 0xFFFF ? 2 : 1;
                    pos += 1 + endCharCount;
                    if (endCode < code) input.Raise("Invalid character range", input.Start);
                    AddRange(input, ranges, code, endCode + 1);
                }
                else
                {
                    if (code == SetMarker[0]) code = 45;
                    AddRange(input, ranges, code, code + 1);
                }
            }
            input.Next();
            ranges.Sort((a, b) => a[0] - b[0]);
            return new SetExpression(start, ranges.ToArray(), invert);
        }
        else if (input.Type == "at" && input.Value is "specialize" or "extend")
        {
            int specStart = input.Start;
            string specValue = (string)input.Value!;
            input.Next();
            var specProps = ParseProps(input);
            input.Expect("<");
            var token = ParseExprChoice(input);
            Expression content = token;
            if (input.Eat(","))
                content = ParseExprChoice(input);
            else if (token is not LiteralExpression)
                input.Raise($"@{specValue} requires two arguments when its first argument isn't a literal string");
            input.Expect(">");
            return new SpecializeExpression(specStart, specValue, specProps, token, content);
        }
        else if (input.Type == "at" && Expression.CharClasses.ContainsKey((string)input.Value!))
        {
            var cls = new CharClass(input.Start, (string)input.Value!);
            input.Next();
            return cls;
        }
        else if (input.Type == "[")
        {
            var rule = ParseRule(input, new Identifier(start, "_anon"));
            if (rule.Params.Length > 0) input.Raise("Inline rules can't have parameters", rule.Start);
            return new InlineRuleExpression(start, rule);
        }
        else
        {
            var id = ParseIdent(input);
            if (input.Type == "[" || input.Type == "{")
            {
                var rule = ParseRule(input, id);
                if (rule.Params.Length > 0) input.Raise("Inline rules can't have parameters", rule.Start);
                return new InlineRuleExpression(start, rule);
            }
            else
            {
                if (input.Eat(".") && id.Name == "std" && Expression.CharClasses.ContainsKey((string)input.Value!))
                {
                    var cls = new CharClass(start, (string)input.Value!);
                    input.Next();
                    return cls;
                }
                return new NameExpression(start, id, ParseArgs(input));
            }
        }
    }

    static Expression[] ParseArgs(Input input)
    {
        var args = new List<Expression>();
        if (input.Eat("<"))
            while (!input.Eat(">"))
            {
                if (args.Count > 0) input.Expect(",");
                args.Add(ParseExprChoice(input));
            }
        return args.ToArray();
    }

    static void AddRange(Input input, List<int[]> ranges, int from, int to)
    {
        if (!ranges.All(r => r[1] <= from || r[0] >= to))
            input.Raise("Overlapping character range", input.Start);
        ranges.Add([from, to]);
    }

    static Expression ParseExprSuffix(Input input)
    {
        int start = input.Start;
        var expr = ParseExprInner(input);
        while (true)
        {
            string kind;
            if (input.Eat("*")) kind = "*";
            else if (input.Eat("+")) kind = "+";
            else if (input.Eat("?")) kind = "?";
            else break;
            expr = new RepeatExpression(start, expr, kind);
        }
        return expr;
    }

    static bool EndOfSequence(Input input)
    {
        return input.Type is "}" or ")" or "|" or "/" or "/\\" or "{" or "," or ">";
    }

    static Expression ParseExprSequence(Input input)
    {
        int start = input.Start;
        var exprs = new List<Expression>();
        var markers = new List<ConflictMarker[]> { Array.Empty<ConflictMarker>() };
        do
        {
            while (true)
            {
                int localStart = input.Start;
                string markerType;
                if (input.Eat("~")) markerType = "ambig";
                else if (input.Eat("!")) markerType = "prec";
                else break;
                var last = markers[markers.Count - 1];
                markers[markers.Count - 1] = [.. last, new ConflictMarker(localStart, ParseIdent(input), markerType)];
            }
            if (EndOfSequence(input)) break;
            exprs.Add(ParseExprSuffix(input));
            markers.Add([]);
        } while (!EndOfSequence(input));

        if (exprs.Count == 1 && markers.All(ms => ms.Length == 0)) return exprs[0];
        return new SequenceExpression(start, exprs.ToArray(), markers.ToArray(), exprs.Count == 0);
    }

    static Expression ParseExprChoice(Input input)
    {
        int start = input.Start;
        var left = ParseExprSequence(input);
        if (!input.Eat("|")) return left;
        var exprs = new List<Expression> { left };
        do
        {
            exprs.Add(ParseExprSequence(input));
        } while (input.Eat("|"));

        var empty = exprs.Find(s => s is SequenceExpression seq && seq.Empty);
        if (empty != null)
            input.Raise("Empty expression in choice operator. If this is intentional, use () to make it explicit.", empty.Start);
        return new ChoiceExpression(start, exprs.ToArray());
    }

    static Identifier ParseIdent(Input input)
    {
        if (input.Type != "id" && input.Type != "string") input.Unexpected();
        int start = input.Start;
        string name = input.Type == "string" ? (string)input.Value! : (string)input.Value!;
        input.Next();
        return new Identifier(start, name);
    }

    static PrecDeclaration ParsePrecedence(Input input)
    {
        int start = input.Start;
        input.Next();
        input.Expect("{");
        var items = new List<PrecItem>();
        while (!input.Eat("}"))
        {
            if (items.Count > 0) input.Eat(",");
            var id = ParseIdent(input);
            string? type = input.Eat("at", "left") ? "left"
                : input.Eat("at", "right") ? "right"
                : input.Eat("at", "cut") ? "cut"
                : null;
            items.Add(new PrecItem(id, type));
        }
        return new PrecDeclaration(start, items.ToArray());
    }

    static TokenDeclaration ParseTokens(Input input)
    {
        int start = input.Start;
        input.Next();
        input.Expect("{");
        var tokenRules = new List<RuleDeclaration>();
        var literals = new List<LiteralDeclaration>();
        var precedences = new List<TokenPrecDeclaration>();
        var conflicts = new List<TokenConflictDeclaration>();
        while (!input.Eat("}"))
        {
            if (input.Type == "at" && input.Value is "precedence")
                precedences.Add(ParseTokenPrecedence(input));
            else if (input.Type == "at" && input.Value is "conflict")
                conflicts.Add(ParseTokenConflict(input));
            else if (input.Type == "string")
                literals.Add(new LiteralDeclaration(input.Start, (string)input.Expect("string")!, ParseProps(input)));
            else
                tokenRules.Add(ParseRule(input));
        }
        return new TokenDeclaration(start, precedences.ToArray(), conflicts.ToArray(), tokenRules.ToArray(), literals.ToArray());
    }

    static LocalTokenDeclaration ParseLocalTokens(Input input, int start)
    {
        input.Expect("{");
        var tokenRules = new List<RuleDeclaration>();
        var precedences = new List<TokenPrecDeclaration>();
        TokenEntry? fallback = null;
        while (!input.Eat("}"))
        {
            if (input.Type == "at" && input.Value is "precedence")
                precedences.Add(ParseTokenPrecedence(input));
            else if (input.Eat("at", "else") && fallback == null)
                fallback = new TokenEntry(ParseIdent(input), ParseProps(input));
            else
                tokenRules.Add(ParseRule(input));
        }
        return new LocalTokenDeclaration(start, precedences.ToArray(), tokenRules.ToArray(), fallback);
    }

    static TokenPrecDeclaration ParseTokenPrecedence(Input input)
    {
        int start = input.Start;
        input.Next();
        input.Expect("{");
        var tokens = new List<Expression>();
        while (!input.Eat("}"))
        {
            if (tokens.Count > 0) input.Eat(",");
            var expr = ParseExprInner(input);
            if (expr is LiteralExpression or NameExpression) tokens.Add(expr);
            else input.Raise("Invalid expression in token precedences", expr.Start);
        }
        return new TokenPrecDeclaration(start, tokens.ToArray());
    }

    static TokenConflictDeclaration ParseTokenConflict(Input input)
    {
        int start = input.Start;
        input.Next();
        input.Expect("{");
        var a = ParseExprInner(input);
        if (a is not (LiteralExpression or NameExpression))
            input.Raise("Invalid expression in token conflict", a.Start);
        input.Eat(",");
        var b = ParseExprInner(input);
        if (b is not (LiteralExpression or NameExpression))
            input.Raise("Invalid expression in token conflict", b.Start);
        input.Expect("}");
        return new TokenConflictDeclaration(start, a, b);
    }

    static (TokenEntry[] tokens, Identifier[] conflicts) ParseExternalTokenSet(Input input, bool allowConflicts)
    {
        var tokens = new List<TokenEntry>();
        var conflicts = new List<Identifier>();
        input.Expect("{");
        for (bool first = true; !input.Eat("}"); first = false)
        {
            if (!first) input.Eat(",");
            if (allowConflicts && input.Eat("at", "conflict"))
            {
                input.Expect("{");
                for (bool f = true; !input.Eat("}"); f = false)
                {
                    if (!f) input.Eat(",");
                    conflicts.Add(ParseIdent(input));
                }
            }
            else
            {
                var id = ParseIdent(input);
                var tokenProps = ParseProps(input);
                tokens.Add(new TokenEntry(id, tokenProps));
            }
        }
        return (tokens.ToArray(), conflicts.ToArray());
    }

    static ExternalTokenDeclaration ParseExternalTokens(Input input, int start)
    {
        var id = ParseIdent(input);
        input.Expect("id", "from");
        var from = (string)input.Expect("string")!;
        var (tokens, conflicts) = ParseExternalTokenSet(input, true);
        return new ExternalTokenDeclaration(start, id, from, tokens, conflicts);
    }

    static ExternalSpecializeDeclaration ParseExternalSpecialize(Input input, string type, int start)
    {
        var token = ParseBracedExpr(input);
        var id = ParseIdent(input);
        input.Expect("id", "from");
        var from = (string)input.Expect("string")!;
        var (tokens, _) = ParseExternalTokenSet(input, false);
        return new ExternalSpecializeDeclaration(start, type, token, id, from, tokens);
    }

    static ExternalPropSourceDeclaration ParseExternalPropSource(Input input, int start)
    {
        var id = ParseIdent(input);
        input.Expect("id", "from");
        return new ExternalPropSourceDeclaration(start, id, (string)input.Expect("string")!);
    }

    static ExternalPropDeclaration ParseExternalProp(Input input, int start)
    {
        var externalID = ParseIdent(input);
        var id = input.Eat("id", "as") ? ParseIdent(input) : externalID;
        input.Expect("id", "from");
        var from = (string)input.Expect("string")!;
        return new ExternalPropDeclaration(start, id, externalID, from);
    }

    static string ReadString(string s)
    {
        var result = new StringBuilder();
        int i = 0;
        while (i < s.Length)
        {
            if (s[i] == '\\' && i + 1 < s.Length)
            {
                char c = s[i + 1];
                if (c == 'u' && i + 2 < s.Length && s[i + 2] == '{')
                {
                    int close = s.IndexOf('}', i + 3);
                    result.Append(char.ConvertFromUtf32(int.Parse(s.AsSpan(i + 3, close - i - 3), NumberStyles.HexNumber)));
                    i = close + 1;
                }
                else if (c == 'u' && i + 5 < s.Length)
                {
                    result.Append(char.ConvertFromUtf32(int.Parse(s.AsSpan(i + 2, 4), NumberStyles.HexNumber)));
                    i += 6;
                }
                else if (c == 'x' && i + 3 < s.Length)
                {
                    result.Append((char)int.Parse(s.AsSpan(i + 2, 2), NumberStyles.HexNumber));
                    i += 4;
                }
                else if (c == 'n') { result.Append('\n'); i += 2; }
                else if (c == 't') { result.Append('\t'); i += 2; }
                else if (c == 'b') { result.Append('\b'); i += 2; }
                else if (c == 'r') { result.Append('\r'); i += 2; }
                else if (c == 'f') { result.Append('\f'); i += 2; }
                else if (c == '0') { result.Append('\0'); i += 2; }
                else { result.Append(c); i += 2; }
            }
            else
            {
                result.Append(s[i]);
                i++;
            }
        }
        return result.ToString();
    }
}
