namespace Rezel.Generator;

public abstract class ShiftOrReduce
{
    public readonly Term Term;

    protected ShiftOrReduce(Term term) { Term = term; }

    public abstract bool Eq(ShiftOrReduce other);
    public abstract int Cmp(ShiftOrReduce other);
    public abstract bool Matches(ShiftOrReduce other, int[] mapping);
    public abstract ShiftOrReduce Map(int[] mapping, LrState[] states);
}

public sealed class Shift : ShiftOrReduce
{
    public readonly LrState Target;

    public Shift(Term term, LrState target) : base(term) { Target = target; }

    public override bool Eq(ShiftOrReduce other) =>
        other is Shift s && Term == s.Term && s.Target.Id == Target.Id;

    public override int Cmp(ShiftOrReduce other)
    {
        if (other is Reduce) return -1;
        var s = (Shift)other;
        return Term.Id != s.Term.Id ? Term.Id - s.Term.Id : Target.Id - s.Target.Id;
    }

    public override bool Matches(ShiftOrReduce other, int[] mapping) =>
        other is Shift s && mapping[s.Target.Id] == mapping[Target.Id];

    public override string ToString() => "s" + Target.Id;

    public override ShiftOrReduce Map(int[] mapping, LrState[] states)
    {
        var mapped = states[mapping[Target.Id]];
        return ReferenceEquals(mapped, Target) ? this : new Shift(Term, mapped);
    }
}

public sealed class Reduce : ShiftOrReduce
{
    public readonly Rule Rule;

    public Reduce(Term term, Rule rule) : base(term) { Rule = rule; }

    public override bool Eq(ShiftOrReduce other) =>
        other is Reduce r && Term == r.Term && Rule.SameReduce(r.Rule);

    public override int Cmp(ShiftOrReduce other)
    {
        if (other is Shift) return 1;
        var r = (Reduce)other;
        return Term.Id != r.Term.Id ? Term.Id - r.Term.Id
            : Rule.Name.Id != r.Rule.Name.Id ? Rule.Name.Id - r.Rule.Name.Id
            : Rule.Parts.Length - r.Rule.Parts.Length;
    }

    public override bool Matches(ShiftOrReduce other, int[] _) =>
        other is Reduce r && r.Rule.SameReduce(Rule);

    public override string ToString() => $"{Rule.Name}({Rule.Parts.Length})";

    public override ShiftOrReduce Map(int[] mapping, LrState[] states) => this;
}

public sealed class Pos
{
    public int HashValue;
    public readonly Rule Rule;
    public readonly int Index;
    public List<Term> Ahead;
    public List<string> AmbigAhead;
    public readonly Term SkipAhead;
    public readonly Pos? Via;

    public Pos(Rule rule, int index, List<Term> ahead, List<string> ambigAhead, Term skipAhead, Pos? via)
    {
        Rule = rule;
        Index = index;
        Ahead = ahead;
        AmbigAhead = ambigAhead;
        SkipAhead = skipAhead;
        Via = via;
    }

    public Pos Finish()
    {
        var h = Hash.Compute(Hash.Compute(Rule.Id, Index), SkipAhead.Hash);
        foreach (var a in Ahead) h = Hash.Compute(h, a.Hash);
        foreach (var group in AmbigAhead) h = Hash.HashString(h, group);
        HashValue = h;
        return this;
    }

    public Term? Next => Index < Rule.Parts.Length ? Rule.Parts[Index] : null;

    public Pos Advance() =>
        new Pos(Rule, Index + 1, Ahead, AmbigAhead, SkipAhead, Via).Finish();

    public Term Skip => Index == Rule.Parts.Length ? SkipAhead : Rule.Skip;

    public int Cmp(Pos pos)
    {
        return Rule.Cmp(pos.Rule) != 0 ? Rule.Cmp(pos.Rule)
            : Index - pos.Index != 0 ? Index - pos.Index
            : SkipAhead.Hash - pos.SkipAhead.Hash != 0 ? SkipAhead.Hash - pos.SkipAhead.Hash
            : GrammarUtils.CmpSet(Ahead, pos.Ahead, (a, b) => a.Cmp(b)) != 0
                ? GrammarUtils.CmpSet(Ahead, pos.Ahead, (a, b) => a.Cmp(b))
            : GrammarUtils.CmpSet(AmbigAhead, pos.AmbigAhead, (a, b) => string.CompareOrdinal(a, b));
    }

    public bool EqSimple(Pos pos) => pos.Rule == Rule && pos.Index == Index;

    public override string ToString()
    {
        var parts = Rule.Parts.Select(t => t.Name).ToList();
        parts.Insert(Index, "\u00b7");
        return $"{Rule.Name} -> {string.Join(" ", parts)}";
    }

    public bool Eq(Pos other) =>
        ReferenceEquals(this, other)
        || (HashValue == other.HashValue
            && Rule == other.Rule
            && Index == other.Index
            && SkipAhead == other.SkipAhead
            && Helpers.SameSet(Ahead, other.Ahead)
            && Helpers.SameSet(AmbigAhead, other.AmbigAhead));

    public string Trail(int maxLen = 60)
    {
        var result = new List<Term>();
        for (var p = this; p != null; p = p.Via)
            for (var i = p.Index - 1; i >= 0; i--)
                result.Add(p.Rule.Parts[i]);
        result.Reverse();
        var value = string.Join(" ", result.Select(t => t.Name));
        if (value.Length > maxLen)
        {
            value = value[^maxLen..];
            var spaceIdx = value.IndexOf(' ');
            if (spaceIdx >= 0)
                value = "\u2026 " + value[(spaceIdx + 1)..];
        }
        return value;
    }

    public Conflicts GetConflicts(int? position = null)
    {
        var pos = position ?? Index;
        var result = Rule.Conflicts[pos];
        if (pos == Rule.Parts.Length && AmbigAhead.Count > 0)
            result = result.Join(new Conflicts(0, AmbigAhead));
        return result;
    }

    public static Pos[] AddOrigins(Pos[] group, Pos[] context)
    {
        var result = new List<Pos>(group);
        for (var i = 0; i < result.Count; i++)
        {
            var next = result[i];
            if (next.Index == 0)
                foreach (var pos in context)
                    if (pos.Next == next.Rule.Name && !result.Contains(pos))
                        result.Add(pos);
        }
        return result.ToArray();
    }
}

public sealed class AutomatonConflict
{
    public readonly string Error;
    public readonly Term[] Rules;

    public AutomatonConflict(string error, Term[] rules)
    {
        Error = error;
        Rules = rules;
    }
}

public sealed class LrState
{
    public List<ShiftOrReduce> Actions = [];
    public List<Pos[]> ActionPositions = [];
    public List<Shift> Goto = [];
    public int TokenGroup = -1;
    public Rule? DefaultReduce;
    public int Id;
    public Pos[] Set;
    public int Flags;
    public readonly Term Skip;
    public readonly int HashValue;
    public readonly Term? StartRule;

    private Dictionary<int, List<ShiftOrReduce>>? _actionsByTerm;

    public LrState(int id, Pos[] set, int flags, Term skip, int hashValue, Term? startRule = null)
    {
        Id = id;
        Set = set;
        Flags = flags;
        Skip = skip;
        HashValue = hashValue;
        StartRule = startRule;
    }

    public override string ToString()
    {
        var actionsStr = string.Join(",", Actions.Select(t => t.Term + "=" + t))
            + (Goto.Count > 0 ? " | " + string.Join(",", Goto.Select(g => g.Term + "=" + g)) : "");
        return Id + ": " + string.Join(",", Set.Where(p => p.Index > 0).Select(p => p.ToString()))
            + (DefaultReduce != null
                ? $"\n  always {DefaultReduce.Name}({DefaultReduce.Parts.Length})"
                : actionsStr.Length > 0 ? "\n  " + actionsStr : "");
    }

    internal ShiftOrReduce? AddActionInner(ShiftOrReduce value, Pos[] positions)
    {
        for (var i = 0; i < Actions.Count; i++)
        {
            var action = Actions[i];
            if (action.Term == value.Term)
            {
                if (action.Eq(value)) return null;
                var fullPos = Pos.AddOrigins(positions, Set);
                var actionFullPos = Pos.AddOrigins(ActionPositions[i], Set);
                var conflicts = Helpers.ConflictsAt(fullPos);
                var actionConflicts = Helpers.ConflictsAt(actionFullPos);
                var repeatPrec = Helpers.CompareRepeatPrec(fullPos, actionFullPos);
                var diff = repeatPrec != 0 ? repeatPrec : conflicts.Precedence - actionConflicts.Precedence;
                if (diff > 0)
                {
                    Actions.RemoveAt(i);
                    ActionPositions.RemoveAt(i);
                    i--;
                    continue;
                }
                else if (diff < 0)
                {
                    return null;
                }
                else if (conflicts.AmbigGroups.Any(g => actionConflicts.AmbigGroups.Contains(g)))
                {
                    continue;
                }
                else
                {
                    return action;
                }
            }
        }
        Actions.Add(value);
        ActionPositions.Add(positions);
        return null;
    }

    internal void AddAction(ShiftOrReduce value, Pos[] positions, ConflictContext context)
    {
        var conflict = AddActionInner(value, positions);
        if (conflict != null)
        {
            var conflictPos = ActionPositions[Actions.IndexOf(conflict)][0];
            var rules = new[] { positions[0].Rule.Name, conflictPos.Rule.Name };
            if (context.ConflictsList.Any(c => c.Rules.Any(r => rules.Contains(r)))) return;
            string error;
            if (conflict is Shift)
                error = $"shift/reduce conflict between\n  {conflictPos}\nand\n  {positions[0].Rule}";
            else
                error = $"reduce/reduce conflict between\n  {conflictPos.Rule}\nand\n  {positions[0].Rule}";
            error += $"\nWith input:\n  {positions[0].Trail(70)} \u00b7 {value.Term} \u2026";
            if (conflict is Shift s)
                error += Helpers.FindConflictShiftSource(positions[0], s.Term, context.First);
            error += Helpers.FindConflictOrigin(conflictPos, positions[0]);
            context.ConflictsList.Add(new AutomatonConflict(error, rules));
        }
    }

    public Shift? GetGoto(Term term) => Goto.Find(a => a.Term == term);

    public bool HasSet(Pos[] set) => Helpers.EqSet(Set, set, (a, b) => a.Eq(b));

    public Dictionary<int, List<ShiftOrReduce>> ActionsByTerm()
    {
        if (_actionsByTerm == null)
        {
            _actionsByTerm = new Dictionary<int, List<ShiftOrReduce>>();
            foreach (var action in Actions)
            {
                if (!_actionsByTerm.TryGetValue(action.Term.Id, out var list))
                {
                    list = new List<ShiftOrReduce>();
                    _actionsByTerm[action.Term.Id] = list;
                }
                list.Add(action);
            }
        }
        return _actionsByTerm;
    }

    public void Finish()
    {
        if (Actions.Count > 0 && Actions[0] is Reduce r)
        {
            var rule = r.Rule;
            if (Actions.All(a => a is Reduce ra && ra.Rule.SameReduce(rule)))
                DefaultReduce = rule;
        }
        Actions.Sort((a, b) => a.Cmp(b));
        Goto.Sort((a, b) => a.Cmp(b));
    }

    public bool Eq(LrState other)
    {
        var dThis = DefaultReduce;
        var dOther = other.DefaultReduce;
        if (dThis != null || dOther != null)
            return dThis != null && dOther != null && dThis.SameReduce(dOther);
        return Skip == other.Skip
            && TokenGroup == other.TokenGroup
            && Helpers.EqSet(Actions, other.Actions, (a, b) => a.Eq(b))
            && Helpers.EqSet(Goto, other.Goto, (a, b) => a.Eq(b));
    }
}

internal sealed class ConflictContext
{
    public List<AutomatonConflict> ConflictsList = [];
    public readonly Dictionary<string, List<Term?>> First;

    public ConflictContext(Dictionary<string, List<Term?>> first)
    {
        First = first;
    }
}

file sealed class Core
{
    public readonly Pos[] Set;
    public readonly LrState State;

    public Core(Pos[] set, LrState state)
    {
        Set = set;
        State = state;
    }
}

file sealed class Group
{
    public List<int> Members;
    public readonly int Origin;

    public Group(int origin, int member)
    {
        Origin = origin;
        Members = [member];
    }
}

file static class Helpers
{
    public static bool SameSet<T>(IReadOnlyList<T> a, IReadOnlyList<T> b)
    {
        if (a.Count != b.Count) return false;
        for (var i = 0; i < a.Count; i++)
            if (!Equals(a[i], b[i])) return false;
        return true;
    }

    public static bool EqSet<T>(IReadOnlyList<T> a, IReadOnlyList<T> b, Func<T, T, bool> eq)
    {
        if (a.Count != b.Count) return false;
        for (var i = 0; i < a.Count; i++)
            if (!eq(a[i], b[i])) return false;
        return true;
    }

    public static int HashPositions(Pos[] set)
    {
        var h = 5381;
        foreach (var pos in set) h = Hash.Compute(h, pos.HashValue);
        return h;
    }

    public static List<Term> TermsAhead(Rule rule, int pos, IReadOnlyList<Term> after,
        Dictionary<string, List<Term?>> first)
    {
        var found = new List<Term>();
        for (var i = pos + 1; i < rule.Parts.Length; i++)
        {
            var next = rule.Parts[i];
            var cont = false;
            if (next.Terminal)
            {
                if (!found.Contains(next)) found.Add(next);
            }
            else
            {
                foreach (var term in first[next.Name])
                {
                    if (term == null) cont = true;
                    else if (!found.Contains(term)) found.Add(term);
                }
            }
            if (!cont) return found;
        }
        foreach (var a in after)
            if (!found.Contains(a)) found.Add(a);
        return found;
    }

    public static Conflicts ConflictsAt(Pos[] group)
    {
        var result = Conflicts.None;
        foreach (var pos in group) result = result.Join(pos.GetConflicts());
        return result;
    }

    public static int CompareRepeatPrec(Pos[] a, Pos[] b)
    {
        foreach (var pos in a)
            if (pos.Rule.Name.Repeated)
                foreach (var posB in b)
                    if (posB.Rule.Name == pos.Rule.Name)
                    {
                        if (pos.Rule.IsRepeatWrap && pos.Index == 2) return 1;
                        if (posB.Rule.IsRepeatWrap && posB.Index == 2) return -1;
                    }
        return 0;
    }

    public static Pos[] Closure(Pos[] set, Dictionary<string, List<Term?>> first)
    {
        var added = new List<Pos>();
        var redo = new List<Pos>();

        void AddFor(Term name, List<Term> ahead, List<string> ambigAhead, Term skipAhead, Pos via)
        {
            foreach (var rule in name.Rules)
            {
                var add = added.Find(a => a.Rule == rule);
                if (add == null)
                {
                    var existing = Array.Find(set, p => p.Index == 0 && p.Rule == rule);
                    add = existing != null
                        ? new Pos(rule, 0, new List<Term>(existing.Ahead), existing.AmbigAhead,
                            existing.SkipAhead, existing.Via)
                        : new Pos(rule, 0, new List<Term>(), new List<string>(), skipAhead, via);
                    added.Add(add);
                }
                if (add.SkipAhead != skipAhead)
                    throw new GenError("Inconsistent skip sets after " + via.Trail());
                add.AmbigAhead = GrammarUtils.Union(add.AmbigAhead, ambigAhead);
                foreach (var term in ahead)
                    if (!add.Ahead.Contains(term))
                    {
                        add.Ahead.Add(term);
                        if (add.Rule.Parts.Length > 0 && !add.Rule.Parts[0].Terminal)
                        {
                            if (!redo.Contains(add)) redo.Add(add);
                        }
                    }
            }
        }

        foreach (var pos in set)
        {
            var next = pos.Next;
            if (next != null && !next.Terminal)
                AddFor(
                    next,
                    TermsAhead(pos.Rule, pos.Index, pos.Ahead, first),
                    pos.GetConflicts(pos.Index + 1).AmbigGroups,
                    pos.Index == pos.Rule.Parts.Length - 1 ? pos.SkipAhead : pos.Rule.Skip,
                    pos
                );
        }

        while (redo.Count > 0)
        {
            var add = redo[^1];
            redo.RemoveAt(redo.Count - 1);
            AddFor(
                add.Rule.Parts[0],
                TermsAhead(add.Rule, 0, add.Ahead, first),
                GrammarUtils.Union(
                    add.Rule.Conflicts[1].AmbigGroups,
                    add.Rule.Parts.Length == 1 ? add.AmbigAhead : new List<string>()
                ),
                add.Rule.Parts.Length == 1 ? add.SkipAhead : add.Rule.Skip,
                add
            );
        }

        var result = new List<Pos>(set);
        foreach (var add in added)
        {
            add.Ahead.Sort((a, b) => a.Hash - b.Hash);
            add.Finish();
            var origIndex = Array.FindIndex(set, p => p.Index == 0 && p.Rule == add.Rule);
            if (origIndex > -1) result[origIndex] = add;
            else result.Add(add);
        }
        result.Sort((a, b) => a.Cmp(b));
        return result.ToArray();
    }

    public static Pos[] ApplyCut(Pos[] set)
    {
        List<Pos>? found = null;
        var cut = 1;
        foreach (var pos in set)
        {
            var value = pos.Rule.Conflicts[pos.Index - 1].Cut;
            if (value < cut) continue;
            if (found == null || value > cut)
            {
                cut = value;
                found = new List<Pos>();
            }
            found.Add(pos);
        }
        return found?.ToArray() ?? set;
    }

    public static bool CanMerge(LrState a, LrState b, int[] mapping)
    {
        foreach (var ga in a.Goto)
            foreach (var gb in b.Goto)
                if (ga.Term == gb.Term && mapping[ga.Target.Id] != mapping[gb.Target.Id])
                    return false;
        var byTerm = b.ActionsByTerm();
        foreach (var action in a.Actions)
        {
            if (byTerm.TryGetValue(action.Term.Id, out var setB))
            {
                if (setB.Any(other => !other.Matches(action, mapping)))
                {
                    if (setB.Count == 1) return false;
                    var setA = a.ActionsByTerm()[action.Term.Id];
                    if (setA.Count != setB.Count ||
                        setA.Any(a1 => !setB.Any(a2 => a1.Matches(a2, mapping))))
                        return false;
                }
            }
        }
        return true;
    }

    public static LrState[] MergeStates(LrState[] states, int[] mapping)
    {
        var maxId = mapping.Max();
        var newStates = new LrState?[maxId + 1];
        foreach (var state in states)
        {
            var newID = mapping[state.Id];
            if (newStates[newID] == null)
            {
                newStates[newID] = new LrState(newID, state.Set, 0, state.Skip, state.HashValue,
                    state.StartRule);
                newStates[newID]!.TokenGroup = state.TokenGroup;
                newStates[newID]!.DefaultReduce = state.DefaultReduce;
            }
        }
        foreach (var state in states)
        {
            var newID = mapping[state.Id];
            var target = newStates[newID]!;
            target.Flags |= state.Flags;
            for (var i = 0; i < state.Actions.Count; i++)
            {
                var action = state.Actions[i].Map(mapping, newStates!);
                if (!target.Actions.Any(a => a.Eq(action)))
                {
                    target.Actions.Add(action);
                    target.ActionPositions.Add(state.ActionPositions[i]);
                }
            }
            foreach (var ga in state.Goto)
            {
                var mapped = (Shift)ga.Map(mapping, newStates!);
                if (!target.Goto.Any(g => g.Eq(mapped)))
                    target.Goto.Add(mapped);
            }
        }
        return newStates!;
    }

    public static bool SamePosSet(Pos[] a, Pos[] b)
    {
        if (a.Length != b.Length) return false;
        for (var i = 0; i < a.Length; i++)
            if (!a[i].EqSimple(b[i])) return false;
        return true;
    }

    public static LrState[] CollapseAutomaton(LrState[] states)
    {
        var mapping = new int[states.Length];
        var groups = new List<Group>();
        for (var i = 0; i < states.Length; i++)
        {
            var state = states[i];
            if (state.StartRule == null)
            {
                var found = false;
                for (var j = 0; j < groups.Count; j++)
                {
                    var group = groups[j];
                    var other = states[group.Members[0]];
                    if (state.TokenGroup == other.TokenGroup
                        && state.Skip == other.Skip
                        && other.StartRule == null
                        && SamePosSet(state.Set, other.Set))
                    {
                        group.Members.Add(i);
                        mapping[i] = j;
                        found = true;
                        break;
                    }
                }
                if (found) continue;
            }
            mapping[i] = groups.Count;
            groups.Add(new Group(groups.Count, i));
        }

        void Spill(int groupIndex, int index)
        {
            var group = groups[groupIndex];
            var state = states[group.Members[index]];
            var pop = group.Members[^1];
            group.Members.RemoveAt(group.Members.Count - 1);
            if (index != group.Members.Count) group.Members[index] = pop;
            for (var i = groupIndex + 1; i < groups.Count; i++)
            {
                mapping[state.Id] = i;
                if (groups[i].Origin == group.Origin
                    && groups[i].Members.All(id => CanMerge(state, states[id], mapping)))
                {
                    groups[i].Members.Add(state.Id);
                    return;
                }
            }
            mapping[state.Id] = groups.Count;
            groups.Add(new Group(group.Origin, state.Id));
        }

        for (var pass = 1; ; pass++)
        {
            var hasConflicts = false;
            var t0 = DateTime.Now;
            var startLen = groups.Count;
            for (var g = 0; g < startLen; g++)
            {
                var group = groups[g];
                for (var i = 0; i < group.Members.Count - 1; i++)
                    for (var j = i + 1; j < group.Members.Count; j++)
                    {
                        if (!CanMerge(states[group.Members[i]], states[group.Members[j]], mapping))
                        {
                            hasConflicts = true;
                            Spill(g, j);
                            j--;
                        }
                    }
            }
            if (Log.Timing)
                Console.WriteLine(
                    $"Collapse pass {pass}{(hasConflicts ? "" : ", done")} ({(DateTime.Now - t0).TotalSeconds:F2}s)");
            if (!hasConflicts) return MergeStates(states, mapping);
        }
    }

    public static LrState[] MergeIdentical(LrState[] states)
    {
        for (var pass = 1; ; pass++)
        {
            var mapping = new int[states.Length];
            var didMerge = false;
            var t0 = DateTime.Now;
            var newStates = new List<LrState>();
            for (var i = 0; i < states.Length; i++)
            {
                var state = states[i];
                var match = newStates.FindIndex(s => state.Eq(s));
                if (match < 0)
                {
                    mapping[i] = newStates.Count;
                    newStates.Add(state);
                }
                else
                {
                    mapping[i] = match;
                    didMerge = true;
                    var other = newStates[match];
                    List<Pos>? add = null;
                    foreach (var pos in state.Set)
                        if (!other.Set.Any(p => p.EqSimple(pos)))
                        {
                            add ??= new List<Pos>();
                            add.Add(pos);
                        }
                    if (add != null)
                    {
                        var merged = add.Concat(other.Set).ToList();
                        merged.Sort((a, b) => a.Cmp(b));
                        other.Set = merged.ToArray();
                    }
                }
            }
            if (Log.Timing)
                Console.WriteLine(
                    $"Merge identical pass {pass}{(didMerge ? "" : ", done")} ({(DateTime.Now - t0).TotalSeconds:F2}s)");
            if (!didMerge) return states;
            var newStatesArray = newStates.ToArray();
            foreach (var state in newStatesArray)
                if (state.DefaultReduce == null)
                {
                    for (var i = 0; i < state.Actions.Count; i++)
                        state.Actions[i] = state.Actions[i].Map(mapping, newStatesArray);
                    for (var i = 0; i < state.Goto.Count; i++)
                        state.Goto[i] = (Shift)state.Goto[i].Map(mapping, newStatesArray);
                }
            for (var i = 0; i < newStatesArray.Length; i++)
                newStatesArray[i].Id = i;
            states = newStatesArray;
        }
    }

    public static string FindConflictOrigin(Pos a, Pos b)
    {
        if (a.EqSimple(b)) return "";

        string Via(Pos root, Pos start)
        {
            var hist = new List<Pos>();
            for (var p = start.Via!; !p.EqSimple(root); p = p.Via!)
                hist.Add(p);
            if (hist.Count == 0) return "";
            hist.Insert(0, start);
            hist.Reverse();
            var parts = new string[hist.Count];
            for (var i = 0; i < hist.Count; i++)
                parts[i] = "\n" + new string(' ', (i + 1) * 2)
                    + (ReferenceEquals(hist[i], start) ? "" : "via ") + hist[i];
            return string.Join("", parts);
        }

        for (var p = a; p != null; p = p.Via)
            for (var p2 = b; p2 != null; p2 = p2.Via)
                if (p.EqSimple(p2))
                    return "\nShared origin: " + p + Via(p, a) + Via(p, b);
        return "";
    }

    public static string FindConflictShiftSource(Pos conflictPos, Term termAfter,
        Dictionary<string, List<Term?>> first)
    {
        var pos = conflictPos;
        var path = new List<Term>();
        for (; ; )
        {
            for (var i = pos.Index - 1; i >= 0; i--)
                path.Add(pos.Rule.Parts[i]);
            if (pos.Via == null) break;
            pos = pos.Via;
        }
        path.Reverse();
        var seen = new HashSet<int>();

        string Explore(Pos p, int idx, Pos? hasMatch)
        {
            if (idx == path.Count && hasMatch != null && p.Next == null)
                return $"\nThe reduction of {conflictPos.Rule.Name} is allowed before {termAfter} because of this rule:\n  {hasMatch}";
            while (true)
            {
                var next = p.Next;
                if (next == null) break;
                if (idx < path.Count && next == path[idx])
                {
                    var inner = Explore(p.Advance(), idx + 1, hasMatch);
                    if (inner.Length > 0) return inner;
                }
                Term? after = p.Index + 1 < p.Rule.Parts.Length ? p.Rule.Parts[p.Index + 1] : null;
                Pos? match = p.Index + 1 == p.Rule.Parts.Length ? hasMatch : null;
                if (after != null &&
                    (after.Terminal
                        ? after == termAfter
                        : first[after.Name].Any(t => t == termAfter)))
                    match = p.Advance();
                foreach (var rule in next.Rules)
                {
                    var h = (rule.Id << 5) + idx + (match != null ? 555 : 0);
                    if (!seen.Contains(h))
                    {
                        seen.Add(h);
                        var inner = Explore(
                            new Pos(rule, 0, new List<Term>(), new List<string>(), next, p), idx,
                            match);
                        if (inner.Length > 0) return inner;
                    }
                }
                if (!next.Terminal && first[next.Name].Any(t => t == null))
                    p = p.Advance();
                else break;
            }
            return "";
        }

        return Explore(pos, 0, null);
    }
}

public static class Automaton
{
    public static Dictionary<string, List<Term?>> ComputeFirstSets(TermSet terms)
    {
        var table = new Dictionary<string, List<Term?>>();
        foreach (var t in terms.Terms)
            if (!t.Terminal)
                table[t.Name] = new List<Term?>();
        for (; ; )
        {
            var change = false;
            foreach (var nt in terms.Terms)
                if (!nt.Terminal)
                    foreach (var rule in nt.Rules)
                    {
                        var set = table[nt.Name];
                        var found = false;
                        var startLen = set.Count;
                        foreach (var part in rule.Parts)
                        {
                            found = true;
                            if (part.Terminal)
                            {
                                if (!set.Contains(part)) set.Add(part);
                            }
                            else
                            {
                                foreach (var t in table[part.Name])
                                {
                                    if (t == null) found = false;
                                    else if (!set.Contains(t)) set.Add(t);
                                }
                            }
                            if (found) break;
                        }
                        if (!found && !set.Contains(null)) set.Add(null);
                        if (set.Count > startLen) change = true;
                    }
            if (!change) return table;
        }
    }

    public static LrState[] BuildFullAutomaton(TermSet terms, Term[] startTerms,
        Dictionary<string, List<Term?>> first)
    {
        var states = new List<LrState>();
        var statesBySetHash = new Dictionary<int, List<LrState>>();
        var cores = new Dictionary<int, List<Core>>();
        var t0 = DateTime.Now;

        LrState? GetState(Pos[] core, Term? top = null)
        {
            if (core.Length == 0) return null;
            var coreHash = Helpers.HashPositions(core);
            cores.TryGetValue(coreHash, out var byHash);

            Term? skip = null;
            foreach (var pos in core)
            {
                if (skip == null) skip = pos.Skip;
                else if (skip != pos.Skip)
                    throw new GenError("Inconsistent skip sets after " + pos.Trail());
            }

            if (byHash != null)
                foreach (var known in byHash)
                    if (Helpers.EqSet(known.Set, core, (a, b) => a.Eq(b)))
                    {
                        if (known.State.Skip != skip)
                            throw new GenError("Inconsistent skip sets after " + known.Set[0].Trail());
                        return known.State;
                    }

            var set = Helpers.Closure(core, first);
            var hash = Helpers.HashPositions(set);
            if (!statesBySetHash.TryGetValue(hash, out var forHash))
            {
                forHash = new List<LrState>();
                statesBySetHash[hash] = forHash;
            }
            LrState? found = null;
            if (top == null)
                foreach (var state in forHash)
                    if (state.HasSet(set))
                        found = state;
            if (found == null)
            {
                found = new LrState(states.Count, set, 0, skip!, hash, top);
                forHash.Add(found);
                states.Add(found);
                if (Log.Timing && states.Count % 500 == 0)
                    Console.WriteLine($"{states.Count} states after {(DateTime.Now - t0).TotalSeconds:F2}s");
            }
            if (!cores.TryGetValue(coreHash, out var coreList))
            {
                coreList = new List<Core>();
                cores[coreHash] = coreList;
            }
            coreList.Add(new Core(core, found));
            return found;
        }

        foreach (var startTerm in startTerms)
        {
            var startSkip = startTerm.Rules.Count > 0
                ? startTerm.Rules[0].Skip
                : terms.Names["%noskip"];
            GetState(
                startTerm.Rules.Select(rule =>
                    new Pos(rule, 0, [terms.Eof], new List<string>(), startSkip, null).Finish()
                ).ToArray(),
                startTerm
            );
        }

        var conflictContext = new ConflictContext(first);

        for (var filled = 0; filled < states.Count; filled++)
        {
            var state = states[filled];
            var byTerm = new List<Term>();
            var byTermPos = new List<List<Pos>>();
            var atEnd = new List<Pos>();
            foreach (var pos in state.Set)
            {
                if (pos.Index == pos.Rule.Parts.Length)
                {
                    if (!pos.Rule.Name.Top) atEnd.Add(pos);
                }
                else
                {
                    var next = pos.Rule.Parts[pos.Index];
                    var index = byTerm.IndexOf(next);
                    if (index < 0)
                    {
                        byTerm.Add(next);
                        byTermPos.Add([pos]);
                    }
                    else
                    {
                        byTermPos[index].Add(pos);
                    }
                }
            }
            for (var i = 0; i < byTerm.Count; i++)
            {
                var term = byTerm[i];
                var positions = byTermPos[i].Select(p => p.Advance()).ToArray();
                if (term.Terminal)
                {
                    var cutSet = Helpers.ApplyCut(positions);
                    var next = GetState(cutSet);
                    if (next != null)
                        state.AddAction(new Shift(term, next), byTermPos[i].ToArray(), conflictContext);
                }
                else
                {
                    var gotoState = GetState(positions);
                    if (gotoState != null)
                        state.Goto.Add(new Shift(term, gotoState));
                }
            }

            var replaced = false;
            foreach (var pos in atEnd)
                foreach (var ahead in pos.Ahead)
                {
                    var count = state.Actions.Count;
                    state.AddAction(new Reduce(ahead, pos.Rule), [pos], conflictContext);
                    if (state.Actions.Count == count) replaced = true;
                }

            if (replaced)
                for (var i = 0; i < state.Goto.Count; i++)
                {
                    var start = first[state.Goto[i].Term.Name];
                    if (!start.Any(term => state.Actions.Any(a => a.Term == term && a is Shift)))
                    {
                        state.Goto.RemoveAt(i);
                        i--;
                    }
                }
        }

        if (conflictContext.ConflictsList.Count > 0)
            throw new GenError(string.Join("\n\n", conflictContext.ConflictsList.Select(c => c.Error)));

        foreach (var state in states) state.Finish();
        if (Log.Timing) Console.WriteLine($"{states.Count} states total.");
        return states.ToArray();
    }

    public static LrState[] FinishAutomaton(LrState[] full)
    {
        return Helpers.MergeIdentical(Helpers.CollapseAutomaton(full));
    }
}
