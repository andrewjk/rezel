using LrTerm = Rezel.Lr.Term;

namespace Rezel.Generator;

public static class TermFlag
{
    public const int Terminal = 1;
    public const int Top = 2;
    public const int Eof = 4;
    public const int Preserve = 8;
    public const int Repeated = 16;
    public const int Inline = 32;
}

public delegate int CmpFunc<in T>(T a, T b);

public static class GrammarUtils
{
    public static bool HasProps(Dictionary<string, string> props)
    {
        return props.Count > 0;
    }

    public static int CmpSet<T>(IReadOnlyList<T> a, IReadOnlyList<T> b, CmpFunc<T> cmp)
    {
        if (a.Count != b.Count) return a.Count - b.Count;
        for (var i = 0; i < a.Count; i++)
        {
            var diff = cmp(a[i], b[i]);
            if (diff != 0) return diff;
        }
        return 0;
    }

    public static List<T> Union<T>(List<T> a, List<T> b) where T : IComparable<T>
    {
        if (a.Count == 0 || ReferenceEquals(a, b)) return b;
        if (b.Count == 0) return a;
        var result = new List<T>(a);
        foreach (var value in b)
            if (!a.Contains(value))
                result.Add(value);
        result.Sort();
        return result;
    }
}

public sealed class Term
{
    private static int _termHash;

    public readonly int Hash = ++_termHash;
    public int Id = -1;
    public List<Rule> Rules = [];

    public readonly string Name;
    private int _flags;
    public readonly string? NodeName;
    public readonly Dictionary<string, string> Props;

    public Term(string name, int flags, string? nodeName, Dictionary<string, string>? props = null)
    {
        Name = name;
        _flags = flags;
        NodeName = nodeName;
        Props = props ?? new Dictionary<string, string>();
    }

    public override string ToString() => Name;

    public bool NodeType => Top || NodeName != null || GrammarUtils.HasProps(Props) || Repeated;

    public bool Terminal => (_flags & TermFlag.Terminal) > 0;
    public bool Eof => (_flags & TermFlag.Eof) > 0;
    public bool Error => Props.ContainsKey("error");
    public bool Top => (_flags & TermFlag.Top) > 0;
    public bool Interesting => _flags > 0 || NodeName != null;
    public bool Repeated => (_flags & TermFlag.Repeated) > 0;

    public bool Preserve
    {
        get => (_flags & TermFlag.Preserve) > 0;
        set => _flags = value ? _flags | TermFlag.Preserve : _flags & ~TermFlag.Preserve;
    }

    public bool Inline
    {
        get => (_flags & TermFlag.Inline) > 0;
        set => _flags = value ? _flags | TermFlag.Inline : _flags & ~TermFlag.Inline;
    }

    public int Cmp(Term other) => Hash - other.Hash;
}

public sealed class TermSet
{
    public List<Term> Terms = [];
    public Dictionary<string, Term> Names = [];
    public readonly Term Eof;
    public readonly Term Error;
    public List<Term> Tops = [];

    public TermSet()
    {
        Eof = Term("\u2404", null, TermFlag.Terminal | TermFlag.Eof);
        Error = Term("\u26A0", "\u26A0", TermFlag.Preserve);
    }

    public Term Term(string name, string? nodeName, int flags = 0, Dictionary<string, string>? props = null)
    {
        var term = new Term(name, flags, nodeName, props);
        Terms.Add(term);
        Names[name] = term;
        return term;
    }

    public Term MakeTop(string? nodeName, Dictionary<string, string> props)
    {
        var term = Term("@top", nodeName, TermFlag.Top, props);
        Tops.Add(term);
        return term;
    }

    public Term MakeTerminal(string name, string? nodeName, Dictionary<string, string>? props = null)
    {
        return Term(name, nodeName, TermFlag.Terminal, props);
    }

    public Term MakeNonTerminal(string name, string? nodeName, Dictionary<string, string>? props = null)
    {
        return Term(name, nodeName, 0, props);
    }

    public Term MakeRepeat(string name)
    {
        return Term(name, null, TermFlag.Repeated);
    }

    public string UniqueName(string name)
    {
        for (var i = 0; ; i++)
        {
            var cur = i > 0 ? $"{name}-{i}" : name;
            if (!Names.ContainsKey(cur)) return cur;
        }
    }

    public sealed class FinishResult
    {
        public required List<Term> NodeTypes;
        public required Dictionary<int, string> Names;
        public required int MinRepeatTerm;
        public required int MaxTerm;
    }

    public FinishResult Finish(Rule[] rules)
    {
        foreach (var rule in rules)
            rule.Name.Rules.Add(rule);

        Terms = Terms.Where(t =>
            t.Terminal || t.Preserve || rules.Any(r => r.Name == t || r.Parts.Contains(t))
        ).ToList();

        var names = new Dictionary<int, string>();
        var nodeTypes = new List<Term> { Error };

        Error.Id = LrTerm.Err;
        var nextID = LrTerm.Err + 1;

        foreach (var term in Terms)
            if (term.Id < 0 && term.NodeType && !term.Repeated)
            {
                term.Id = nextID++;
                nodeTypes.Add(term);
            }

        var minRepeatTerm = nextID;
        foreach (var term in Terms)
            if (term.Repeated)
            {
                term.Id = nextID++;
                nodeTypes.Add(term);
            }

        Eof.Id = nextID++;
        foreach (var term in Terms)
        {
            if (term.Id < 0) term.Id = nextID++;
            if (term.Name != null) names[term.Id] = term.Name;
        }

        if (nextID >= 0xfffe) throw new GenError("Too many terms");

        return new FinishResult
        {
            NodeTypes = nodeTypes,
            Names = names,
            MinRepeatTerm = minRepeatTerm,
            MaxTerm = nextID - 1
        };
    }
}

public sealed class Conflicts
{
    public readonly int Precedence;
    public readonly List<string> AmbigGroups;
    public readonly int Cut;

    public Conflicts(int precedence, List<string>? ambigGroups = null, int cut = 0)
    {
        Precedence = precedence;
        AmbigGroups = ambigGroups ?? [];
        Cut = cut;
    }

    public Conflicts Join(Conflicts other)
    {
        if (ReferenceEquals(this, None) || ReferenceEquals(this, other)) return other;
        if (ReferenceEquals(other, None)) return this;
        return new Conflicts(
            Math.Max(Precedence, other.Precedence),
            GrammarUtils.Union(AmbigGroups, other.AmbigGroups),
            Math.Max(Cut, other.Cut)
        );
    }

    public int Cmp(Conflicts other)
    {
        return (Precedence - other.Precedence) != 0
            ? Precedence - other.Precedence
            : GrammarUtils.CmpSet(AmbigGroups, other.AmbigGroups, (a, b) => string.CompareOrdinal(a, b)) != 0
                ? GrammarUtils.CmpSet(AmbigGroups, other.AmbigGroups, (a, b) => string.CompareOrdinal(a, b))
                : Cut - other.Cut;
    }

    public static readonly Conflicts None = new Conflicts(0);
}

public sealed class Rule
{
    private static int _ruleID;

    public readonly int Id = _ruleID++;
    public readonly Term Name;
    public readonly Term[] Parts;
    public readonly Conflicts[] Conflicts;
    public readonly Term Skip;

    public Rule(Term name, Term[] parts, Conflicts[] conflicts, Term skip)
    {
        Name = name;
        Parts = parts;
        Conflicts = conflicts;
        Skip = skip;
    }

    public int Cmp(Rule rule) => Id - rule.Id;

    public int CmpNoName(Rule rule)
    {
        var lenDiff = Parts.Length - rule.Parts.Length;
        if (lenDiff != 0) return lenDiff;
        var skipDiff = Skip.Hash - rule.Skip.Hash;
        if (skipDiff != 0) return skipDiff;
        for (var i = 0; i < Parts.Length; i++)
        {
            var partDiff = Parts[i].Cmp(rule.Parts[i]);
            if (partDiff != 0) return partDiff;
        }
        return GrammarUtils.CmpSet(Conflicts, rule.Conflicts, (a, b) => a.Cmp(b));
    }

    public override string ToString() => Name + " -> " + string.Join(" ", (object[])Parts);

    public bool IsRepeatWrap => Name.Repeated && Parts.Length == 2 && Parts[0] == Name;

    public bool SameReduce(Rule other)
    {
        return Name == other.Name &&
               Parts.Length == other.Parts.Length &&
               IsRepeatWrap == other.IsRepeatWrap;
    }
}
