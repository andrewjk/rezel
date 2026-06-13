using Rezel.Lr;

namespace Rezel.Generator;

public sealed class TokenEdge
{
    public readonly int From;
    public readonly int To;
    public readonly TokenState Target;

    public TokenEdge(int from, int to, TokenState target)
    {
        From = from;
        To = to;
        Target = target;
    }

    public override string ToString()
    {
        var label = From < 0
            ? "ε"
            : CharFor(From) + (To > From + 1 ? "-" + CharFor(To - 1) : "");
        return $"-> {Target.Id}[label=\"{label}\"]";
    }

    private static string CharFor(int n)
    {
        return n > TokenState.MaxChar
            ? "∞"
            : n == 10
                ? "\\n"
                : n == 13
                    ? "\\r"
                    : n < 32 || (n >= 0xd800 && n < 0xdfff)
                        ? $"\\u{{{n:X}}}"
                        : ((char)n).ToString();
    }
}

public sealed class MergedTokenEdge
{
    public readonly int From;
    public readonly int To;
    public readonly List<TokenState> Targets;

    public MergedTokenEdge(int from, int to, List<TokenState> targets)
    {
        From = from;
        To = to;
        Targets = targets;
    }
}

public sealed class TokenConflict
{
    public readonly Term A;
    public readonly Term B;
    public int Soft;
    public readonly string ExampleA;
    public readonly string? ExampleB;

    public TokenConflict(Term a, Term b, int soft, string exampleA, string? exampleB = null)
    {
        A = a;
        B = b;
        Soft = soft;
        ExampleA = exampleA;
        ExampleB = exampleB;
    }
}

public sealed class TokenState
{
    public const int MaxChar = 0xffff;

    private static int _stateID = 1;

    public readonly int Id;
    public readonly List<Term> Accepting;
    public readonly List<TokenEdge> Edges = [];

    public TokenState(List<Term>? accepting = null, int? id = null)
    {
        Accepting = accepting ?? [];
        Id = id ?? _stateID++;
    }

    public void Edge(int from, int to, TokenState target)
    {
        Edges.Add(new TokenEdge(from, to, target));
    }

    public void NullEdge(TokenState target)
    {
        Edge(-1, -1, target);
    }

    public TokenState Compile()
    {
        var labeled = new Dictionary<string, TokenState>();
        var localID = 0;

        var initial = Closure();
        initial.Sort((a, b) => a.Id - b.Id);
        var startState = Explore(initial);
        return Minimize(new List<TokenState>(labeled.Values), startState);

        TokenState Explore(List<TokenState> states)
        {
            var accepting = new List<Term>();
            foreach (var s in states)
                foreach (var t in s.Accepting)
                    if (!accepting.Contains(t))
                        accepting.Add(t);
            accepting.Sort((a, b) => a.Cmp(b));

            var newState = new TokenState(accepting, localID++);
            labeled[Ids(states, s => s.Id)] = newState;

            var outEdges = new List<TokenEdge>();
            foreach (var state in states)
                foreach (var edge in state.Edges)
                    if (edge.From >= 0)
                        outEdges.Add(edge);

            var transitions = MergeEdges(outEdges);
            foreach (var merged in transitions)
            {
                var targets = new List<TokenState>(merged.Targets);
                targets.Sort((a, b) => a.Id - b.Id);
                var key = Ids(targets, s => s.Id);
                newState.Edge(merged.From, merged.To,
                    labeled.TryGetValue(key, out var existing) ? existing : Explore(targets));
            }
            return newState;
        }
    }

    public List<TokenState> Closure()
    {
        var result = new List<TokenState>();
        var seen = new HashSet<int>();

        void Explore(TokenState state)
        {
            if (seen.Contains(state.Id)) return;
            seen.Add(state.Id);
            if (state.Edges.Any(e => e.From >= 0) ||
                (state.Accepting.Count > 0 &&
                 !state.Edges.Any(e => SameSet(state.Accepting, e.Target.Accepting))))
                result.Add(state);
            foreach (var edge in state.Edges)
                if (edge.From < 0) Explore(edge.Target);
        }

        Explore(this);
        return result;
    }

    public List<TokenConflict> FindConflicts(Func<Term, Term, bool> occurTogether)
    {
        var conflicts = new List<TokenConflict>();
        var cycleTerms = CycleTerms();

        void Add(Term a, Term b, int soft, List<TokenEdge> aEdges, List<TokenEdge>? bEdges = null)
        {
            if (a.Id < b.Id)
            {
                (a, b) = (b, a);
                soft = -soft;
            }
            var found = conflicts.Find(c => c.A == a && c.B == b);
            if (found == null)
                conflicts.Add(new TokenConflict(a, b, soft, ExampleFromEdges(aEdges),
                    bEdges != null ? ExampleFromEdges(bEdges) : null));
            else if (found.Soft != soft) found.Soft = 0;
        }

        Reachable((state, edges) =>
        {
            if (state.Accepting.Count == 0) return;
            for (var i = 0; i < state.Accepting.Count; i++)
                for (var j = i + 1; j < state.Accepting.Count; j++)
                    Add(state.Accepting[i], state.Accepting[j], 0, edges);
            state.Reachable((s, es) =>
            {
                if (!ReferenceEquals(s, state))
                    foreach (var term in s.Accepting)
                    {
                        var hasCycle = cycleTerms.Contains(term);
                        foreach (var orig in state.Accepting)
                            if (term != orig)
                                Add(term, orig,
                                    hasCycle || cycleTerms.Contains(orig) || !occurTogether(term, orig) ? 0 : 1,
                                    edges, edges.Concat(es).ToList());
                    }
            });
        });
        return conflicts;
    }

    public List<Term> CycleTerms()
    {
        var work = new List<TokenState>();
        Reachable((state, _) =>
        {
            foreach (var edge in state.Edges)
            {
                work.Add(state);
                work.Add(edge.Target);
            }
        });

        var table = new Dictionary<TokenState, List<TokenState>>();
        var haveCycle = new List<TokenState>();
        for (var i = 0; i < work.Count;)
        {
            var from = work[i++];
            var to = work[i++];
            if (!table.TryGetValue(from, out var entry))
            {
                entry = [];
                table[from] = entry;
            }
            if (entry.Contains(to)) continue;
            if (ReferenceEquals(from, to))
            {
                if (!haveCycle.Contains(from)) haveCycle.Add(from);
            }
            else
            {
                foreach (var next in entry)
                {
                    work.Add(from);
                    work.Add(next);
                }
                entry.Add(to);
            }
        }

        var result = new List<Term>();
        foreach (var state in haveCycle)
            foreach (var term in state.Accepting)
                if (!result.Contains(term)) result.Add(term);
        return result;
    }

    public void Reachable(Action<TokenState, List<TokenEdge>> f)
    {
        var seen = new List<TokenState>();
        var edges = new List<TokenEdge>();

        void Explore(TokenState s)
        {
            f(s, edges);
            seen.Add(s);
            foreach (var edge in s.Edges)
                if (!seen.Contains(edge.Target))
                {
                    edges.Add(edge);
                    Explore(edge.Target);
                    edges.RemoveAt(edges.Count - 1);
                }
        }

        Explore(this);
    }

    public override string ToString()
    {
        var output = "digraph {\n";
        Reachable((state, _) =>
        {
            if (state.Accepting.Count > 0)
                output += $"  {state.Id} [label=\"{string.Join(",", state.Accepting.Select(t => t.Name))}\"];\n";
            foreach (var edge in state.Edges)
                output += $"  {state.Id} {edge};\n";
        });
        return output + "}";
    }

    public ushort[] ToArray(Dictionary<int, int> groupMasks, int[] precedence)
    {
        var offsets = new Dictionary<int, int>();
        var data = new List<int>();
        Reachable((state, _) =>
        {
            var start = data.Count;
            var acceptEnd = start + 3 + state.Accepting.Count * 2;
            offsets[state.Id] = start;
            data.Add(state.StateMask(groupMasks));
            data.Add(acceptEnd);
            data.Add(state.Edges.Count);
            state.Accepting.Sort((a, b) => Array.IndexOf(precedence, a.Id) - Array.IndexOf(precedence, b.Id));
            foreach (var term in state.Accepting)
            {
                data.Add(term.Id);
                data.Add(groupMasks.TryGetValue(term.Id, out var mask) ? mask : 0xffff);
            }
            foreach (var edge in state.Edges)
            {
                data.Add(edge.From);
                data.Add(edge.To);
                data.Add(-edge.Target.Id - 1);
            }
        });
        for (var i = 0; i < data.Count; i++)
            if (data[i] < 0) data[i] = offsets[-data[i] - 1];
        if (data.Count > 1 << 16)
            throw new GenError("Tokenizer tables too big to represent with 16-bit offsets.");
        var result = new ushort[data.Count];
        for (var i = 0; i < data.Count; i++) result[i] = (ushort)data[i];
        return result;
    }

    public int StateMask(Dictionary<int, int> groupMasks)
    {
        var mask = 0;
        Reachable((state, _) =>
        {
            foreach (var term in state.Accepting)
                mask |= groupMasks.TryGetValue(term.Id, out var gm) ? gm : 0xffff;
        });
        return mask;
    }

    private static TokenState Minimize(List<TokenState> states, TokenState start)
    {
        var partition = new Dictionary<int, List<TokenState>>();
        var byAccepting = new Dictionary<string, List<TokenState>>();
        foreach (var state in states)
        {
            var id = Ids(state.Accepting, t => t.Id);
            if (!byAccepting.TryGetValue(id, out var group))
            {
                group = [];
                byAccepting[id] = group;
            }
            group.Add(state);
            partition[state.Id] = group;
        }

        while (true)
        {
            var split = false;
            var newPartition = new Dictionary<int, List<TokenState>>();
            foreach (var state in states)
            {
                if (newPartition.ContainsKey(state.Id)) continue;
                var group = partition[state.Id];
                if (group.Count == 1)
                {
                    newPartition[group[0].Id] = group;
                    continue;
                }
                var parts = new List<List<TokenState>>();
                foreach (var s in group)
                {
                    var matched = false;
                    foreach (var p in parts)
                    {
                        if (IsEquivalent(s, p[0], partition))
                        {
                            p.Add(s);
                            matched = true;
                            break;
                        }
                    }
                    if (!matched) parts.Add([s]);
                }
                if (parts.Count > 1) split = true;
                foreach (var p in parts)
                    foreach (var s in p)
                        newPartition[s.Id] = p;
            }
            if (!split) return ApplyMinimization(states, start, partition);
            partition = newPartition;
        }
    }

    private static bool IsEquivalent(TokenState a, TokenState b, Dictionary<int, List<TokenState>> partition)
    {
        if (a.Edges.Count != b.Edges.Count) return false;
        for (var i = 0; i < a.Edges.Count; i++)
        {
            var eA = a.Edges[i];
            var eB = b.Edges[i];
            if (eA.From != eB.From || eA.To != eB.To || partition[eA.Target.Id] != partition[eB.Target.Id])
                return false;
        }
        return true;
    }

    private static TokenState ApplyMinimization(List<TokenState> states, TokenState start, Dictionary<int, List<TokenState>> partition)
    {
        foreach (var state in states)
            for (var i = 0; i < state.Edges.Count; i++)
            {
                var edge = state.Edges[i];
                var target = partition[edge.Target.Id][0];
                if (!ReferenceEquals(target, edge.Target))
                    state.Edges[i] = new TokenEdge(edge.From, edge.To, target);
            }
        return partition[start.Id][0];
    }

    private static List<MergedTokenEdge> MergeEdges(List<TokenEdge> edges)
    {
        var separate = new List<int>();
        foreach (var edge in edges)
        {
            if (!separate.Contains(edge.From)) separate.Add(edge.From);
            if (!separate.Contains(edge.To)) separate.Add(edge.To);
        }
        separate.Sort();

        var result = new List<MergedTokenEdge>();
        for (var i = 1; i < separate.Count; i++)
        {
            var from = separate[i - 1];
            var to = separate[i];
            var found = new List<TokenState>();
            foreach (var edge in edges)
                if (edge.To > from && edge.From < to)
                    foreach (var target in edge.Target.Closure())
                        if (!found.Contains(target)) found.Add(target);
            if (found.Count > 0) result.Add(new MergedTokenEdge(from, to, found));
        }

        var eof = edges.Where(e => e.From == Seq.End && e.To == Seq.End).ToList();
        if (eof.Count > 0)
        {
            var found = new List<TokenState>();
            foreach (var edge in eof)
                foreach (var target in edge.Target.Closure())
                    if (!found.Contains(target)) found.Add(target);
            if (found.Count > 0) result.Add(new MergedTokenEdge(Seq.End, Seq.End, found));
        }
        return result;
    }

    private static string Ids<T>(IReadOnlyList<T> elts, Func<T, int> getId)
    {
        var result = "";
        for (var i = 0; i < elts.Count; i++)
        {
            if (result.Length > 0) result += "-";
            result += getId(elts[i]);
        }
        return result;
    }

    private static bool SameSet(IReadOnlyList<Term> a, IReadOnlyList<Term> b)
    {
        if (a.Count != b.Count) return false;
        for (var i = 0; i < a.Count; i++)
            if (a[i] != b[i]) return false;
        return true;
    }

    private static string ExampleFromEdges(IReadOnlyList<TokenEdge> edges)
    {
        var result = "";
        for (var i = 0; i < edges.Count; i++)
            result += (char)edges[i].From;
        return result;
    }
}
