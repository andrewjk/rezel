using System.Text;
using System.Text.Json;
using LrFile = Rezel.Lr.File;
using LrAction = Rezel.Lr.Action;
using LrParseState = Rezel.Lr.ParseState;
using LrSeq = Rezel.Lr.Seq;
using LrStateFlag = Rezel.Lr.StateFlag;
using LrSpecializeConsts = Rezel.Lr.SpecializeConsts;
using LrStack = Rezel.Lr.Stack;
using Rezel.Common;
using Rezel.Lr;

namespace Rezel.Generator;

public class BuildOptions
{
    public string? FileName { get; set; }
    public Action<string>? Warn { get; set; }
    public bool IncludeNames { get; set; }
    public string ModuleStyle { get; set; } = "es";
    public bool TypeScript { get; set; }
    public string ExportName { get; set; } = "parser";
    public Func<string, Dictionary<string, int>, ExternalTokenizer>? ExternalTokenizerFn { get; set; }
    public Func<string, NodePropSource>? ExternalPropSource { get; set; }
    public Func<string, Dictionary<string, int>, Func<string, LrStack, int>>? ExternalSpecializer { get; set; }
    public Func<string, NodeProp<object>>? ExternalProp { get; set; }
    public object? ContextTracker { get; set; }
}

public class Parts
{
    public readonly Term[] Terms;
    public readonly Conflicts[]? Conflicts;

    public Parts(Term[] terms, Conflicts[]? conflicts)
    {
        Terms = terms;
        Conflicts = conflicts;
    }

    public Parts Concat(Parts other)
    {
        if (this == None) return other;
        if (other == None) return this;
        Conflicts[]? conflicts = null;
        if (Conflicts != null || other.Conflicts != null)
        {
            var self = Conflicts != null ? (Conflicts[])Conflicts.Clone() : EnsureConflicts();
            conflicts = self;
            var otherConflicts = other.EnsureConflicts();
            conflicts[conflicts.Length - 1] = conflicts[conflicts.Length - 1].Join(otherConflicts[0]);
            for (int i = 1; i < otherConflicts.Length; i++)
            {
                var tmp = new Conflicts[conflicts.Length + 1];
                Array.Copy(conflicts, tmp, conflicts.Length);
                tmp[conflicts.Length] = otherConflicts[i];
                conflicts = tmp;
            }
        }
        return new Parts(Terms.Concat(other.Terms).ToArray(), conflicts);
    }

    public Parts WithConflicts(int pos, Conflicts conflicts)
    {
        if (conflicts == Generator.Conflicts.None) return this;
        var array = Conflicts != null ? (Conflicts[])Conflicts.Clone() : EnsureConflicts();
        array[pos] = array[pos].Join(conflicts);
        return new Parts(Terms, array);
    }

    public Conflicts[] EnsureConflicts()
    {
        if (Conflicts != null) return Conflicts;
        var empty = new Conflicts[Terms.Length + 1];
        for (int i = 0; i < empty.Length; i++) empty[i] = Generator.Conflicts.None;
        return empty;
    }

    public static readonly Parts None = new Parts([], null);
}

public sealed class BuiltRule
{
    public readonly string Id;
    public readonly Expression[] Args;
    public readonly Term Term;

    public BuiltRule(string id, Expression[] args, Term term)
    {
        Id = id;
        Args = args;
        Term = term;
    }

    public bool Matches(NameExpression expr)
    {
        return Id == expr.Id.Name && Expression.ExprsEq(expr.Args, Args);
    }

    public bool MatchesRepeat(RepeatExpression expr)
    {
        return Id == "+" && Expression.ExprEq(expr.Expr, Args[0]);
    }
}

public sealed class SkipInfo
{
    public readonly Term[] Skip;
    public readonly Term? Rule;
    public readonly Term[] StartTokens;
    public readonly int Id;

    public SkipInfo(Term[] skip, Term? rule, Term[] startTokens, int id)
    {
        Skip = skip;
        Rule = rule;
        StartTokens = startTokens;
        Id = id;
    }
}

public sealed class NodeInfoResult
{
    public required string? Name;
    public required Dictionary<string, string> Props;
    public required int? Dialect;
    public required int DynamicPrec;
    public required bool Inline;
    public required string? Group;
    public required string? Exported;
}

public sealed class GotoEdgeParents
{
    public List<int> Parents;
    public readonly int Target;

    public GotoEdgeParents(int parent, int target)
    {
        Parents = [parent];
        Target = target;
    }
}

public sealed class PrecRelation
{
    public readonly Term Term;
    public readonly List<Term> After;

    public PrecRelation(Term term, List<Term> after)
    {
        Term = term;
        After = after;
    }
}

public sealed class TokenArg
{
    public readonly string Name;
    public readonly Expression Expr;
    public readonly TokenArg[] Scope;

    public TokenArg(string name, Expression expr, TokenArg[] scope)
    {
        Name = name;
        Expr = expr;
        Scope = scope;
    }
}

public sealed class BuildingRule
{
    public readonly string Name;
    public readonly TokenState Start;
    public readonly TokenState To;
    public readonly Expression[] Args;

    public BuildingRule(string name, TokenState start, TokenState to, Expression[] args)
    {
        Name = name;
        Start = start;
        To = to;
        Args = args;
    }
}

public sealed class SpecializeEntry
{
    public readonly string Value;
    public readonly string? Name;
    public readonly Term Term;
    public readonly string Type;
    public readonly int? Dialect;

    public SpecializeEntry(string value, string? name, Term term, string type, int? dialect)
    {
        Value = value;
        Name = name;
        Term = term;
        Type = type;
        Dialect = dialect;
    }
}

public sealed class TokenOrigin
{
    public Term? Spec;
    public object? External;
    public object? Group;

    public TokenOrigin(Term? spec = null, object? external = null, object? group = null)
    {
        Spec = spec;
        External = external;
        Group = group;
    }
}

public sealed class DataBuilder
{
    private readonly List<int> _data = [];

    public int StoreArray(int[] data)
    {
        var found = FindArray(_data, data);
        if (found > -1) return found;
        var pos = _data.Count;
        foreach (var num in data) _data.Add(num);
        return pos;
    }

    public int StoreArray(List<int> data) => StoreArray(data.ToArray());

    public ushort[] Finish() => _data.Select(d => (ushort)d).ToArray();

    private static int FindArray(List<int> data, int[] value)
    {
        for (int i = 0; ; )
        {
            var next = data.IndexOf(value[0], i);
            if (next == -1 || next + value.Length > data.Count) break;
            var found = true;
            for (int j = 1; j < value.Length; j++)
            {
                if (value[j] != data[next + j])
                {
                    i = next + 1;
                    found = false;
                    break;
                }
            }
            if (found) return next;
        }
        return -1;
    }
}

public sealed class FinishStateContext
{
    public List<SharedActions> SharedActionsList = [];
    public readonly TokenizerSpec[] Tokenizers;
    public readonly DataBuilder Data;
    public readonly uint[] StateArray;
    public readonly int[] SkipData;
    public readonly SkipInfo[] SkipInfo;
    public readonly LrState[] States;
    public readonly Builder Builder;

    const int MinSharedActions = 5;

    public FinishStateContext(
        TokenizerSpec[] tokenizers,
        DataBuilder data,
        uint[] stateArray,
        int[] skipData,
        SkipInfo[] skipInfo,
        LrState[] states,
        Builder builder)
    {
        Tokenizers = tokenizers;
        Data = data;
        StateArray = stateArray;
        SkipData = skipData;
        SkipInfo = skipInfo;
        States = states;
        Builder = builder;
    }

    public SharedActions? FindSharedActions(LrState state)
    {
        if (state.Actions.Count < MinSharedActions) return null;
        SharedActions? found = null;
        foreach (var shared in SharedActionsList)
        {
            if ((found == null || shared.Actions.Length > found.Actions.Length) &&
                shared.Actions.All(a => state.Actions.Any(b => b.Eq(a))))
                found = shared;
        }
        if (found != null) return found;
        ShiftOrReduce[]? max = null;
        var scratch = new List<ShiftOrReduce>();
        for (var i = state.Id + 1; i < States.Length; i++)
        {
            var other = States[i];
            if (other.DefaultReduce != null || other.Actions.Count < MinSharedActions) continue;
            scratch.Clear();
            foreach (var a in state.Actions)
                foreach (var b in other.Actions)
                    if (a.Eq(b)) scratch.Add(a);
            if (scratch.Count >= MinSharedActions && (max == null || max.Length < scratch.Count))
                max = scratch.ToArray();
        }
        if (max == null) return null;
        var result = new SharedActions(max, StoreActions(max, -1, null));
        SharedActionsList.Add(result);
        return result;
    }

    public int StoreActions(ShiftOrReduce[] actions, int skipReduce, SharedActions? shared)
    {
        if (skipReduce < 0 && shared != null && shared.Actions.Length == actions.Length) return shared.Addr;
        var data = new List<int>();
        foreach (var action in actions)
        {
            if (shared != null && shared.Actions.Any(a => a.Eq(action))) continue;
            if (action is Shift shift)
            {
                data.Add(shift.Term.Id);
                data.Add(shift.Target.Id);
                data.Add(0);
            }
            else if (action is Reduce reduce)
            {
                var code = BuildHelpers.ReduceAction(reduce.Rule, SkipInfo);
                if (code != skipReduce)
                {
                    data.Add(reduce.Term.Id);
                    data.Add(code & LrAction.ValueMask);
                    data.Add(code >> 16);
                }
            }
        }
        data.Add(LrSeq.End);
        if (skipReduce > -1)
        {
            data.Add(LrSeq.Other);
            data.Add(skipReduce & LrAction.ValueMask);
            data.Add(skipReduce >> 16);
        }
        else if (shared != null)
        {
            data.Add(LrSeq.Next);
            data.Add(shared.Addr & 0xffff);
            data.Add(shared.Addr >> 16);
        }
        else
        {
            data.Add(LrSeq.Done);
        }
        return Data.StoreArray(data.ToArray());
    }

    public void Finish(LrState state, bool isSkip, int forcedReduce)
    {
        var b = Builder;
        var skipID = Array.IndexOf(b.SkipRules, state.Skip);
        var skipTable = SkipData[skipID];
        var skipTerms = SkipInfo[skipID].StartTokens;

        var defaultReduce = state.DefaultReduce != null ? BuildHelpers.ReduceAction(state.DefaultReduce, SkipInfo) : 0;
        var flags = isSkip ? LrStateFlag.Skipped : 0;

        var skipReduce = -1;
        SharedActions? shared = null;
        if (defaultReduce == 0)
        {
            if (isSkip)
                foreach (var action in state.Actions)
                    if (action is Reduce r && r.Term.Eof)
                        skipReduce = BuildHelpers.ReduceAction(r.Rule, SkipInfo);
            if (skipReduce < 0) shared = FindSharedActions(state);
        }

        if (state.Set.Any(p => p.Rule.Name.Top && p.Index == p.Rule.Parts.Length))
            flags |= LrStateFlag.Accepting;

        var external = new List<TokenizerSpec>();
        for (var i = 0; i < state.Actions.Count + skipTerms.Length; i++)
        {
            var term = i < state.Actions.Count ? state.Actions[i].Term : skipTerms[i - state.Actions.Count];
            while (true)
            {
                if (!b.TokenOrigins.TryGetValue(term.Name, out var orig)) break;
                if (orig.Spec != null)
                {
                    term = orig.Spec;
                    continue;
                }
                if (orig.External is ExternalTokenSet extSet)
                    BuildHelpers.AddToSet(external, new ExternalTokenGroupSpec(b, extSet.Ast));
                break;
            }
        }
        var tokenizerMask = 0;
        for (var i = 0; i < Tokenizers.Length; i++)
        {
            var tok = Tokenizers[i];
            if (external.Any(e => ReferenceEquals(e, tok)) || tok.GroupID == state.TokenGroup) tokenizerMask |= 1 << i;
        }

        var @base = state.Id * LrParseState.Size;
        StateArray[@base + LrParseState.Flags] = (uint)flags;
        StateArray[@base + LrParseState.Actions] = (uint)StoreActions(
            defaultReduce != 0 ? [] : state.Actions.ToArray(),
            skipReduce,
            shared
        );
        StateArray[@base + LrParseState.Skip] = (uint)skipTable;
        StateArray[@base + LrParseState.TokenizerMask] = (uint)tokenizerMask;
        StateArray[@base + LrParseState.DefaultReduce] = (uint)defaultReduce;
        StateArray[@base + LrParseState.ForcedReduce] = (uint)forcedReduce;
    }
}

public sealed class SharedActions
{
    public readonly ShiftOrReduce[] Actions;
    public readonly int Addr;

    public SharedActions(ShiftOrReduce[] actions, int addr)
    {
        Actions = actions;
        Addr = addr;
    }
}

public sealed class NodePropInfo
{
    public string Prop;
    public readonly Dictionary<string, List<int>> Values = [];

    public NodePropInfo(string prop) { Prop = prop; }
}

public sealed class PropSource
{
    public readonly string Name;
    public readonly string? From;

    public PropSource(string name, string? from) { Name = name; From = from; }
}

public sealed class KnownProp
{
    public readonly NodePropBase Prop;
    public readonly PropSource Source;

    public KnownProp(NodePropBase prop, PropSource source) { Prop = prop; Source = source; }
}

public sealed class AstRuleEntry
{
    public readonly Term Skip;
    public readonly RuleDeclaration Rule;

    public AstRuleEntry(Term skip, RuleDeclaration rule) { Skip = skip; Rule = rule; }
}

public sealed class DefinedGroup
{
    public readonly Term Name;
    public readonly string Group;
    public readonly RuleDeclaration Rule;

    public DefinedGroup(Term name, string group, RuleDeclaration rule) { Name = name; Group = group; Rule = rule; }
}

public sealed class DynamicPrec
{
    public readonly Term Rule;
    public readonly int Prec;

    public DynamicPrec(Term rule, int prec) { Rule = rule; Prec = prec; }
}

public sealed class PrepareResult
{
    public required uint[] States;
    public required ushort[] StateData;
    public required ushort[] Goto;
    public required string NodeNames;
    public required List<NodePropInfo> NodeProps;
    public required List<int> SkippedTypes;
    public required int MaxTerm;
    public required int RepeatNodeCount;
    public required TokenizerSpec[] Tokenizers;
    public required ushort[] TokenData;
    public required Dictionary<string, int[]> TopRules;
    public required Dictionary<string, int> Dialects;
    public required Dictionary<int, int>? DynamicPrecedences;
    public required List<object> Specialized;
    public required int TokenPrec;
    public required Dictionary<int, string> TermNames;
    public required Dictionary<string, int> TermTable;
}

public interface TokenizerSpec
{
    int? GroupID { get; }
    object Create();
    string CreateSource(Func<string, string, string, string> importName);
}

public sealed class TokenGroupSpec : TokenizerSpec
{
    public readonly List<Term> Tokens;
    public readonly int GroupIDValue;
    public int? GroupID => GroupIDValue;

    public TokenGroupSpec(Term[] tokens, int groupID) { Tokens = new List<Term>(tokens); GroupIDValue = groupID; }
    public TokenGroupSpec(List<Term> tokens, int groupID) { Tokens = tokens; GroupIDValue = groupID; }
    public object Create() => GroupIDValue;
    public string CreateSource(Func<string, string, string, string> _) => GroupIDValue.ToString();
}

public sealed class LocalTokenGroupSpec : TokenizerSpec
{
    public readonly int GroupIDValue;
    public readonly ushort[] FullData;
    public readonly int PrecOffset;
    public readonly int? FallbackId;
    public int? GroupID => GroupIDValue;

    public LocalTokenGroupSpec(int groupID, ushort[] fullData, int precOffset, int? fallbackId)
    {
        GroupIDValue = groupID;
        FullData = fullData;
        PrecOffset = precOffset;
        FallbackId = fallbackId;
    }

    public object Create() => new LocalTokenGroup(FullData, PrecOffset, FallbackId);
    public string CreateSource(Func<string, string, string, string> importName) =>
        $"new {importName("LocalTokenGroup", "../lr", "")}({EncodeUtil.EncodeArray(FullData)}, {PrecOffset}{(FallbackId != null ? $", {FallbackId}" : "")})";
}

public sealed class ExternalTokenGroupSpec : TokenizerSpec
{
    public int? GroupID => null;
    public readonly Builder BuilderRef;
    public readonly ExternalTokenDeclaration ExtAst;

    public ExternalTokenGroupSpec(Builder b, ExternalTokenDeclaration ast) { BuilderRef = b; ExtAst = ast; }
    public object Create() => BuilderRef.Options.ExternalTokenizerFn!(ExtAst.Id.Name, BuilderRef.TermTable);
    public string CreateSource(Func<string, string, string, string> importName) => importName(ExtAst.Id.Name, ExtAst.Source, ExtAst.Id.Name);
}

public class Builder
{
    public GrammarDeclaration Ast = null!;
    public Input Input = null!;
    public TermSet Terms = new();
    public MainTokenSet Tokens = null!;
    public LocalTokenSet[] LocalTokens = [];
    public ExternalTokenSet[] ExternalTokens = [];
    public ExternalSpecializer[] ExternalSpecializers = [];
    public Dictionary<string, List<SpecializeEntry>> Specialized = new();
    public Dictionary<string, TokenOrigin?> TokenOrigins = new();
    public List<Rule> Rules = [];
    public List<BuiltRule> Built = [];
    public Dictionary<string, Identifier?> RuleNames = new();
    public Dictionary<string, Term> NamedTerms = new();
    public Dictionary<string, int> TermTable = new();
    public Dictionary<string, KnownProp> KnownProps = new();
    public string[] Dialects = [];
    public List<DynamicPrec> DynamicRulePrecedences = [];
    public List<DefinedGroup> DefinedGroups = [];
    public List<AstRuleEntry> AstRules = [];
    public List<Term> CurrentSkip = [];
    public Term[] SkipRules = [];
    public readonly BuildOptions Options;

    static readonly Expression[] NoneExprs = [];

    public Builder(string text, BuildOptions options)
    {
        Options = options;

        Ast = Log.Time("Parse", () =>
        {
            Input = new Input(text, options.FileName);
            return Input.Parse();
        });

        foreach (var kvp in NodeProps.ByName)
        {
            if (kvp.Value is NodePropBase prop && !prop.PerNode)
                KnownProps[kvp.Key] = new KnownProp(prop, new PropSource(kvp.Key, null));
        }
        foreach (var prop in Ast.ExternalProps)
        {
            KnownProps[prop.Id.Name] = new KnownProp(
                options.ExternalProp != null ? options.ExternalProp(prop.Id.Name) : new NodeProp<string>(),
                new PropSource(prop.ExternalID.Name, prop.Source)
            );
        }

        Dialects = Ast.Dialects.Select(d => d.Name).ToArray();
        Tokens = new MainTokenSet(this, Ast.Tokens);
        LocalTokens = Ast.LocalTokens.Select(g => new LocalTokenSet(this, g)).ToArray();
        ExternalTokens = Ast.ExternalTokens.Select(ext => new ExternalTokenSet(this, ext)).ToArray();
        ExternalSpecializers = Ast.ExternalSpecializers.Select(decl => new ExternalSpecializer(this, decl)).ToArray();

        Log.Time<object>("Build rules", () =>
        {
            var noSkip = NewName("%noskip", true);
            CurrentSkip.Add(noSkip);
            DefineRule(noSkip, []);
            var mainSkip = Ast.MainSkip != null ? NewName("%mainskip", true) : noSkip;
            var scopedSkip = new List<Term>();
            var topRules = new List<(RuleDeclaration rule, Term skip)>();
            foreach (var rule in Ast.Rules) AstRules.Add(new AstRuleEntry(mainSkip, rule));
            foreach (var rule in Ast.TopRules) topRules.Add((rule, mainSkip));
            foreach (var scoped in Ast.ScopedSkip)
            {
                var skip = noSkip;
                var found = -1;
                for (var si = 0; si < scopedSkip.Count; si++)
                {
                    if (Expression.ExprEq(Ast.ScopedSkip[si].Expr, scoped.Expr)) { found = si; break; }
                }
                if (found > -1) skip = scopedSkip[found];
                else if (Ast.MainSkip != null && Expression.ExprEq(scoped.Expr, Ast.MainSkip)) skip = mainSkip;
                else if (!BuildHelpers.IsEmpty(scoped.Expr)) skip = NewName("%skip", true);
                scopedSkip.Add(skip);
                foreach (var rule in scoped.Rules) AstRules.Add(new AstRuleEntry(skip, rule));
                foreach (var rule in scoped.TopRules) topRules.Add((rule, skip));
            }
            foreach (var entry in AstRules) Unique(entry.Rule.Id);
            SkipRules = mainSkip == noSkip ? [mainSkip] : [noSkip, mainSkip];
            if (mainSkip != noSkip) DefineRule(mainSkip, NormalizeExpr(Ast.MainSkip!));
            for (var i = 0; i < Ast.ScopedSkip.Length; i++)
            {
                var skip = scopedSkip[i];
                if (!SkipRules.Contains(skip))
                {
                    SkipRules = SkipRules.Append(skip).ToArray();
                    if (skip != noSkip) DefineRule(skip, NormalizeExpr(Ast.ScopedSkip[i].Expr));
                }
            }
            CurrentSkip.RemoveAt(CurrentSkip.Count - 1);
            foreach (var (rule, skip) in topRules.OrderBy(t => t.rule.Start))
            {
                Unique(rule.Id);
                Used(rule.Id.Name);
                CurrentSkip.Add(skip);
                var info = NodeInfo(rule.Props, "a", rule.Id.Name, NoneExprs, [], rule.Expr);
                var term = Terms.MakeTop(info.Name, info.Props);
                NamedTerms[info.Name!] = term;
                DefineRule(term, NormalizeExpr(rule.Expr));
                CurrentSkip.RemoveAt(CurrentSkip.Count - 1);
            }
            foreach (var ext in ExternalSpecializers) ext.Finish();
            foreach (var entry in AstRules)
            {
                var skip = entry.Skip;
                var rule = entry.Rule;
                if (RuleNames[rule.Id.Name] != null && BuildHelpers.IsExported(rule) && rule.Params.Length == 0)
                {
                    BuildRule(rule, NoneExprs, skip, false);
                    if (rule.Expr is SequenceExpression seq && seq.Exprs.Length == 0) Used(rule.Id.Name);
                }
            }
            return null!;
        });

        foreach (var kvp in RuleNames)
        {
            if (kvp.Value != null) Warn($"Unused rule '{kvp.Value.Name}'", kvp.Value.Start);
        }

        Tokens.TakePrecedences();
        Tokens.TakeConflicts();
        foreach (var lt in LocalTokens) lt.TakePrecedences();
        foreach (var entry in DefinedGroups) DefineGroup(entry.Name, entry.Group, entry.Rule);
        CheckGroups();
    }

    internal void Unique(Identifier id)
    {
        if (RuleNames.ContainsKey(id.Name)) Raise($"Duplicate definition of rule '{id.Name}'", id.Start);
        RuleNames[id.Name] = id;
    }

    internal void Used(string name) { RuleNames[name] = null; }

    internal Term NewName(string @base, object? nodeName = null, Dictionary<string, string>? props = null)
    {
        var startI = nodeName != null ? 0 : 1;
        for (var i = startI; ; i++)
        {
            var name = i > 0 ? $"{@base}-{i}" : @base;
            if (!Terms.Names.ContainsKey(name))
            {
                string? nn = nodeName is true or null ? null : nodeName as string;
                return Terms.MakeNonTerminal(name, nn, props);
            }
        }
    }

    public PrepareResult PrepareParser()
    {
        var rules = Log.Time("Simplify rules", () =>
            BuildHelpers.SimplifyRules(Rules, SkipRules.Concat(Terms.Tops).ToArray()));
        var finish = Terms.Finish(rules.ToArray());
        var nodeTypes = finish.NodeTypes;
        var termNames = finish.Names;
        var minRepeatTerm = finish.MinRepeatTerm;
        var maxTerm = finish.MaxTerm;
        foreach (var kvp in NamedTerms) TermTable[kvp.Key] = kvp.Value.Id;
        if (Log.Verbose.Contains("grammar")) Console.WriteLine(string.Join("\n", rules));
        var startTerms = Terms.Tops.ToList();
        var first = Automaton.ComputeFirstSets(Terms);
        var skipInfo = SkipRules.Select((name, id) =>
        {
            var skip = new List<Term>();
            var startTokens = new List<Term>();
            var rulesList = new List<Rule>();
            foreach (var rule in name.Rules)
            {
                if (rule.Parts.Length == 0) continue;
                var start = rule.Parts[0];
                if (start.Terminal) { if (!startTokens.Contains(start)) startTokens.Add(start); }
                else if (first.TryGetValue(start.Name, out var firstSet))
                    foreach (var t in firstSet)
                        if (t != null && !startTokens.Contains(t)) startTokens.Add(t);
                if (start.Terminal && rule.Parts.Length == 1 && !rulesList.Any(r => r != rule && r.Parts[0] == start))
                    skip.Add(start);
                else rulesList.Add(rule);
            }
            name.Rules = rulesList;
            if (rulesList.Count > 0) startTerms.Add(name);
            return new SkipInfo(skip.ToArray(), rulesList.Count > 0 ? name : null, startTokens.ToArray(), id);
        }).ToArray();
        var fullTable = Log.Time("Build full automaton", () =>
            Automaton.BuildFullAutomaton(Terms, startTerms.ToArray(), first));
        var localTokens = LocalTokens.Select((grp, i) =>
            grp.BuildLocalGroup(fullTable, skipInfo, i + LocalTokens.Length)).ToArray();
        var (tokenGroups, tokenPrec, tokenData) = Log.Time("Build token groups", () =>
            Tokens.BuildTokenGroups(fullTable, skipInfo, localTokens.Length));
        foreach (var ext in ExternalTokens) ext.CheckConflicts(fullTable, skipInfo);
        var table = Log.Time("Finish automaton", () => Automaton.FinishAutomaton(fullTable));
        var skipState = BuildHelpers.FindSkipStates(table, Terms.Tops);
        if (Log.Verbose.Contains("lr")) Console.WriteLine(string.Join("\n", table.Select(s => s.ToString())));
        var specialized = new List<object>();
        foreach (var ext in ExternalSpecializers) specialized.Add(ext);
        foreach (var kvp in Specialized)
            specialized.Add(new { Token = Terms.Names[kvp.Key], Table = BuildHelpers.BuildSpecializeTable(kvp.Value) });
        int TokStart(TokenizerSpec t)
        {
            if (t is ExternalTokenGroupSpec es) return es.ExtAst.Start;
            return Tokens.Ast?.Start ?? -1;
        }
        var tokenizers = tokenGroups.Cast<TokenizerSpec>()
            .Concat(ExternalTokens.Select(e => (TokenizerSpec)new ExternalTokenGroupSpec(this, e.Ast)))
            .OrderBy(t => TokStart(t)).Concat(localTokens).ToArray();
        var data = new DataBuilder();
        var skipData = skipInfo.Select(info =>
        {
            var actions = new List<int>();
            foreach (var term in info.Skip) { actions.Add(term.Id); actions.Add(0); actions.Add(LrAction.StayFlag >> 16); }
            if (info.Rule != null)
            {
                var state = table.First(s => s.StartRule == info.Rule);
                foreach (Shift action in state.Actions) { actions.Add(action.Term.Id); actions.Add(state.Id); actions.Add(LrAction.GotoFlag >> 16); }
            }
            actions.Add(LrSeq.End); actions.Add(LrSeq.Done);
            return data.StoreArray(actions.ToArray());
        }).ToArray();
        var states = Log.Time("Finish states", () =>
        {
            var stateArray = new uint[table.Length * LrParseState.Size];
            var forceReductions = ComputeForceReductions(table, skipInfo);
            var finishCx = new FinishStateContext(tokenizers, data, stateArray, skipData, skipInfo, table, this);
            foreach (var s in table) finishCx.Finish(s, skipState(s.Id), forceReductions[s.Id]);
            return stateArray;
        });
        var dialects = new Dictionary<string, int>();
        for (var i = 0; i < Dialects.Length; i++)
        {
            var dTerms = Tokens.ByDialect.TryGetValue(i, out var terms) ? terms : [];
            dialects[Dialects[i]] = data.StoreArray(dTerms.Select(t => t.Id).Append(LrSeq.End).ToArray());
        }
        Dictionary<int, int>? dynamicPrecedences = null;
        if (DynamicRulePrecedences.Count > 0)
        {
            dynamicPrecedences = new Dictionary<int, int>();
            foreach (var dp in DynamicRulePrecedences) dynamicPrecedences[dp.Rule.Id] = dp.Prec;
        }
        var topRules = new Dictionary<string, int[]>();
        foreach (var term in Terms.Tops)
            topRules[term.NodeName!] = [table.First(s => s.StartRule == term).Id, term.Id];
        var precTable = data.StoreArray(tokenPrec.Append(LrSeq.End).ToArray());
        var (nodeProps, skippedTypes) = GatherNodeProps(nodeTypes);
        return new PrepareResult
        {
            States = states, StateData = data.Finish(), Goto = BuildHelpers.ComputeGotoTable(table),
            NodeNames = string.Join(" ", nodeTypes.Where(t => t.Id < minRepeatTerm).Select(t => t.NodeName)),
            NodeProps = nodeProps, SkippedTypes = skippedTypes, MaxTerm = maxTerm,
            RepeatNodeCount = nodeTypes.Count - minRepeatTerm, Tokenizers = tokenizers,
            TokenData = tokenData, TopRules = topRules, Dialects = dialects,
            DynamicPrecedences = dynamicPrecedences, Specialized = specialized,
            TokenPrec = precTable, TermNames = termNames, TermTable = TermTable
        };
    }

    public LRParser GetParser()
    {
        var prep = PrepareParser();
        var specialized = prep.Specialized.Select(v =>
        {
            if (v is ExternalSpecializer ext)
            {
                var externalFn = Options.ExternalSpecializer!(ext.Ast.Id.Name, TermTable);
                return new SpecializerSpec { Term = ext.Term!.Id,
                    Get = (value, stack) => (externalFn(value, stack) << 1) | (ext.Ast.Type == "extend" ? LrSpecializeConsts.Extend : LrSpecializeConsts.Specialize),
                    External = externalFn, Extend = ext.Ast.Type == "extend" };
            }
            else
            {
                dynamic d = v; Term token = d.Token; var tbl = (Dictionary<string, int>)d.Table;
                return new SpecializerSpec { Term = token.Id, Get = (value, _) => tbl.TryGetValue(value, out var tid) ? tid : -1 };
            }
        }).ToArray();
        var nodePropSpecs = prep.NodeProps.Select(np =>
        {
            var terms = new List<object>();
            foreach (var kvp in np.Values)
            {
                if (kvp.Value.Count == 1) { terms.Add(kvp.Value[0]); terms.Add(kvp.Key); }
                else { terms.Add(-kvp.Value.Count); foreach (var id in kvp.Value) terms.Add(id); terms.Add(kvp.Key); }
            }
            return new NodePropSpec((NodeProp<object>)KnownProps[np.Prop].Prop, terms.ToArray());
        }).ToArray();
        return LRParser.Deserialize(new LRParserSpec
        {
            Version = LrFile.Version, States = prep.States, StateData = prep.StateData,
            Goto = prep.Goto, NodeNames = prep.NodeNames, MaxTerm = prep.MaxTerm,
            RepeatNodeCount = prep.RepeatNodeCount,
            NodeProps = nodePropSpecs.Length > 0 ? nodePropSpecs : null,
            PropSources = Options.ExternalPropSource != null ? Ast.ExternalPropSources.Select(s => Options.ExternalPropSource!(s.Id.Name)).ToArray() : null,
            SkippedNodes = prep.SkippedTypes.Count > 0 ? prep.SkippedTypes.ToArray() : null,
            TokenData = EncodeUtil.EncodeArray(prep.TokenData),
            Tokenizers = prep.Tokenizers.Select(t => t.Create()).ToArray(),
            TopRules = prep.TopRules,
            Context = Ast.Context != null && Options.ContextTracker is ContextTracker ct ? ct : null,
            Dialects = prep.Dialects, DynamicPrecedences = prep.DynamicPrecedences,
            Specialized = specialized.Length > 0 ? specialized : null,
            TokenPrec = prep.TokenPrec, TermNames = Options.IncludeNames ? prep.TermNames : null
        });
    }

    public (string parser, string terms) GetParserFile()
    {
        var prep = PrepareParser();
        var mod = Options.ModuleStyle ?? "es";
        var gen = "// This file was generated by lezer-generator. You probably shouldn't edit it.\n";
        var head = gen;
        var imports = new Dictionary<string, List<string>>();
        var imported = new Dictionary<string, string>();
        var defined = new Dictionary<string, bool>();
        foreach (var w in BuildHelpers.Keywords) defined[w] = true;
        var exportName = Options.ExportName ?? "parser";
        defined[exportName] = true;
        string getName(string prefix) { for (var i = 0; ; i++) { var id = prefix + (i > 0 ? "_" + i : ""); if (!defined.ContainsKey(id)) return id; } }
        string importName(string name, string source, string prefix = "")
        {
            var spec = name + " from " + source;
            if (imported.TryGetValue(spec, out var existing)) return existing;
            var src = JsonSerializer.Serialize(source);
            var varName = name;
            if (defined.ContainsKey(name)) { varName = getName(prefix.Length > 0 ? prefix : name); name += (mod == "cjs" ? ":" : " as") + $" {varName}"; }
            defined[varName] = true;
            if (!imports.TryGetValue(src, out var list)) { list = new List<string>(); imports[src] = list; }
            list.Add(name);
            imported[spec] = varName;
            return varName;
        }
        var lrParser = importName("LRParser", "../lr");
        var tokenizers = prep.Tokenizers.Select(tok => tok.CreateSource(importName)).ToArray();
        var context = Ast.Context != null ? importName(Ast.Context.Id.Name, Ast.Context.Source) : null;
        var nodeProps = prep.NodeProps.Select(np =>
        {
            var known = KnownProps[np.Prop]; var source = known.Source;
            var propID = source.From != null ? importName(source.Name, source.From) : JsonSerializer.Serialize(source.Name);
            var termsStr = string.Join(",", np.Values.SelectMany(kvp =>
                kvp.Value.Count == 1 ? new[] { kvp.Value[0].ToString(), BuildHelpers.SerializePropValue(kvp.Key) }
                : kvp.Value.Select(id => id.ToString()).Append(BuildHelpers.SerializePropValue(kvp.Key)).Prepend((-kvp.Value.Count).ToString())));
            return $"[{propID}, {termsStr}]";
        }).ToArray();
        string specTableStr(Dictionary<string, int> table) =>
            "{__proto__:null," + string.Join(", ", table.Select(kvp =>
                $"{(System.Text.RegularExpressions.Regex.IsMatch(kvp.Key, @"^(\d+|[a-zA-Z_]\w*)$") ? kvp.Key : JsonSerializer.Serialize(kvp.Key))}:{kvp.Value}")) + "}";
        var specHead = "";
        var specialized = prep.Specialized.Select(v =>
        {
            if (v is ExternalSpecializer ext)
            {
                var nm = importName(ext.Ast.Id.Name, ext.Ast.Source);
                var ts = Options.TypeScript ? ": any" : "";
                return $"{{term: {ext.Term!.Id}, get: (value{ts}, stack{ts}) => ({nm}(value, stack) << 1){(ext.Ast.Type == "extend" ? $" | {LrSpecializeConsts.Extend}" : "")}, external: {nm}{(ext.Ast.Type == "extend" ? ", extend: true" : "")}}}";
            }
            else
            {
                dynamic d = v; Term token = d.Token; var tbl = d.Table;
                var tblName = getName("spec_" + System.Text.RegularExpressions.Regex.Replace(token.Name, @"\W", ""));
                defined[tblName] = true;
                specHead += $"const {tblName} = {specTableStr(tbl)}\n";
                var ts = Options.TypeScript ? $": keyof typeof {tblName}" : "";
                return $"{{term: {token.Id}, get: (value{ts}) => {tblName}[value] || -1}}";
            }
        }).ToArray();
        var propSources = Ast.ExternalPropSources.Select(s => importName(s.Id.Name, s.Source)).ToArray();
        foreach (var source in imports)
        {
            if (mod == "cjs") head += $"const {{{string.Join(", ", source.Value)}}} = require({source.Key})\n";
            else head += $"import {{{string.Join(", ", source.Value)}}} from {source.Key}\n";
        }
        head += specHead;
        var dialects = prep.Dialects.Select(kvp => $"{kvp.Key}: {kvp.Value}");
        var statesStr = EncodeUtil.EncodeArray(prep.States.Select(u => (int)u).ToArray(), unchecked((int)0xffffffff));
        var parserStr = $"{lrParser}.deserialize({{\n  version: {LrFile.Version},\n  states: {statesStr},\n  stateData: {EncodeUtil.EncodeArray(prep.StateData)},\n  goto: {EncodeUtil.EncodeArray(prep.Goto)},\n  nodeNames: {JsonSerializer.Serialize(prep.NodeNames)},\n  maxTerm: {prep.MaxTerm}";
        if (context != null) parserStr += $",\n  context: {context}";
        if (nodeProps.Length > 0) parserStr += $",\n  nodeProps: [\n    {string.Join(",\n    ", nodeProps)}\n  ]";
        if (propSources.Length > 0) parserStr += $",\n  propSources: [{string.Join(", ", propSources)}]";
        if (prep.SkippedTypes.Count > 0) parserStr += $",\n  skippedNodes: {JsonSerializer.Serialize(prep.SkippedTypes)}";
        parserStr += $",\n  repeatNodeCount: {prep.RepeatNodeCount},\n  tokenData: {EncodeUtil.EncodeArray(prep.TokenData)},\n  tokenizers: [{string.Join(", ", tokenizers)}],\n  topRules: {JsonSerializer.Serialize(prep.TopRules)}";
        if (dialects.Any()) parserStr += $",\n  dialects: {{{string.Join(", ", dialects)}}}";
        if (prep.DynamicPrecedences != null) parserStr += $",\n  dynamicPrecedences: {JsonSerializer.Serialize(prep.DynamicPrecedences)}";
        if (specialized.Length > 0) parserStr += $",\n  specialized: [{string.Join(", ", specialized)}]";
        parserStr += $",\n  tokenPrec: {prep.TokenPrec}";
        if (Options.IncludeNames) parserStr += $",\n  termNames: {JsonSerializer.Serialize(prep.TermNames)}";
        parserStr += "\n})";
        var termsList = new List<string>();
        foreach (var kvp in TermTable)
        {
            var id = kvp.Key;
            if (BuildHelpers.Keywords.Contains(id)) { for (var i = 1; ; i++) { id = new string('_', i) + kvp.Key; if (!TermTable.ContainsKey(id)) break; } }
            else if (!System.Text.RegularExpressions.Regex.IsMatch(id, @"^[\w$]+$")) continue;
            termsList.Add($"{id}{(mod == "cjs" ? ":" : " =")} {kvp.Value}");
        }
        for (var i = 0; i < Dialects.Length; i++) termsList.Add($"Dialect_{Dialects[i]}{(mod == "cjs" ? ":" : " =")} {i}");
        return (head + (mod == "cjs" ? $"exports.{exportName} = {parserStr}\n" : $"export const {exportName} = {parserStr}\n"),
            mod == "cjs" ? $"{gen}module.exports = {{\n  {string.Join(",\n  ", termsList)}\n}}" : $"{gen}export const\n  {string.Join(",\n  ", termsList)}\n");
    }

    Dictionary<int, bool> GatherNonSkippedNodes()
    {
        var seen = new Dictionary<int, bool>(); var work = new List<Term>();
        void Add(Term t) { if (!seen.ContainsKey(t.Id)) { seen[t.Id] = true; work.Add(t); } }
        foreach (var t in Terms.Tops) Add(t);
        for (var i = 0; i < work.Count; i++) foreach (var r in work[i].Rules) foreach (var p in r.Parts) Add(p);
        return seen;
    }

    (List<NodePropInfo>, List<int>) GatherNodeProps(List<Term> nodeTypes)
    {
        var notSkipped = GatherNonSkippedNodes(); var skipped = new List<int>(); var props = new List<NodePropInfo>();
        foreach (var type in nodeTypes)
        {
            if (!notSkipped.ContainsKey(type.Id) && !type.Error) skipped.Add(type.Id);
            foreach (var kvp in type.Props)
            {
                if (!KnownProps.TryGetValue(kvp.Key, out var known)) throw new GenError("No known prop type for " + kvp.Key);
                if (known.Source.From == null && (known.Source.Name == "repeated" || known.Source.Name == "error")) continue;
                var rec = props.Find(r => r.Prop == kvp.Key);
                if (rec == null) { rec = new NodePropInfo(kvp.Key); props.Add(rec); }
                if (!rec.Values.TryGetValue(kvp.Value, out var list)) { list = []; rec.Values[kvp.Value] = list; }
                list.Add(type.Id);
            }
        }
        return (props, skipped);
    }

    internal Term MakeTerminal(string name, string? tag, Dictionary<string, string> props) =>
        Terms.MakeTerminal(Terms.UniqueName(name), tag, props);

    int[] ComputeForceReductions(LrState[] states, SkipInfo[] skipInfo)
    {
        var reductions = new int[states.Length];
        var candidates = new Pos[states.Length][];
        var gotoEdges = new Dictionary<int, List<GotoEdgeParents>>();
        for (var si = 0; si < states.Length; si++)
        {
            var state = states[si]; reductions[si] = 0;
            foreach (var edge in state.Goto)
            {
                if (!gotoEdges.TryGetValue(edge.Term.Id, out var list)) { list = []; gotoEdges[edge.Term.Id] = list; }
                var found = list.Find(o => o.Target == edge.Target.Id);
                if (found != null) found.Parents.Add(state.Id); else list.Add(new GotoEdgeParents(state.Id, edge.Target.Id));
            }
            candidates[si] = state.Set.Where(p => p.Index > 0 && !p.Rule.Name.Top)
                .OrderByDescending(p => p.Index).ThenBy(p => p.Rule.Parts.Length).ToArray();
        }
        var length1Reductions = new Dictionary<int, int>();
        bool CreatesCycle(int term, int startState, int[]? parents = null)
        {
            if (!gotoEdges.TryGetValue(term, out var edges)) return false;
            return edges.Any(val =>
            {
                var pi = parents != null ? parents.Where(id => val.Parents.Contains(id)).ToArray() : val.Parents.ToArray();
                if (pi.Length == 0) return false;
                if (val.Target == startState) return true;
                return length1Reductions.TryGetValue(val.Target, out var f) && CreatesCycle(f, startState, pi);
            });
        }
        foreach (var state in states)
            if (state.DefaultReduce != null && state.DefaultReduce.Parts.Length > 0)
            {
                reductions[state.Id] = BuildHelpers.ReduceAction(state.DefaultReduce, skipInfo);
                if (state.DefaultReduce.Parts.Length == 1) length1Reductions[state.Id] = state.DefaultReduce.Name.Id;
            }
        for (var setSize = 1; ; setSize++)
        {
            var done = true;
            foreach (var state in states)
            {
                if (state.DefaultReduce != null) continue;
                var set = candidates[state.Id];
                if (set.Length != setSize) { if (set.Length > setSize) done = false; continue; }
                foreach (var pos in set)
                {
                    if (pos.Index != 1 || !CreatesCycle(pos.Rule.Name.Id, state.Id))
                    {
                        reductions[state.Id] = BuildHelpers.ReduceAction(pos.Rule, skipInfo, pos.Index);
                        if (pos.Index == 1) length1Reductions[state.Id] = pos.Rule.Name.Id;
                        break;
                    }
                }
            }
            if (done) break;
        }
        return reductions;
    }

    internal Expression SubstituteArgs(Expression expr, Expression[] args, Identifier[] parameters)
    {
        if (args.Length == 0) return expr;
        return expr.Walk(e =>
        {
            if (e is NameExpression ne)
            {
                var fi = -1;
                for (var i = 0; i < parameters.Length; i++) if (parameters[i].Name == ne.Id.Name) { fi = i; break; }
                if (fi > -1)
                {
                    var arg = args[fi];
                    if (ne.Args.Length > 0)
                    {
                        if (arg is NameExpression na && na.Args.Length == 0) return new NameExpression(ne.Start, na.Id, ne.Args);
                        Raise("Passing arguments to a parameter that already has arguments", ne.Start);
                    }
                    return arg;
                }
            }
            else if (e is InlineRuleExpression ie)
            {
                var r = ie.Rule; var p = SubstituteArgsInProps(r.Props, args, parameters);
                return p == r.Props ? e : new InlineRuleExpression(ie.Start, new RuleDeclaration(r.Start, r.Id, p, r.Params, r.Expr));
            }
            else if (e is SpecializeExpression se)
            {
                var p = SubstituteArgsInProps(se.Props, args, parameters);
                return p == se.Props ? e : new SpecializeExpression(se.Start, se.Type, p, se.Token, se.Content);
            }
            return e;
        });
    }

    internal Prop[] SubstituteArgsInProps(Prop[] props, Expression[] args, Identifier[] parameters)
    {
        PropPart[] Sub(PropPart[] value)
        {
            var result = value;
            for (var i = 0; i < value.Length; i++)
            {
                var part = value[i]; if (part.Name == null) continue;
                var fi = -1;
                for (var j = 0; j < parameters.Length; j++) if (parameters[j].Name == part.Name) { fi = j; break; }
                if (fi < 0) continue;
                if (result == value) result = (PropPart[])value.Clone();
                var expr = args[fi];
                if (expr is NameExpression na && na.Args.Length == 0) result[i] = new PropPart(part.Start, na.Id.Name, null);
                else if (expr is LiteralExpression la) result[i] = new PropPart(part.Start, la.Value, null);
                else Raise($"Trying to interpolate expression '{expr}' into a prop", part.Start);
            }
            return result;
        }
        var r = props;
        for (var i = 0; i < props.Length; i++)
        {
            var prop = props[i]; var v = Sub(prop.Value);
            if (v != prop.Value) { if (r == props) r = (Prop[])props.Clone(); r[i] = new Prop(prop.Start, prop.At, prop.Name, v); }
        }
        return r;
    }

    (Conflicts here, Conflicts atEnd) ConflictsFor(ConflictMarker[] markers)
    {
        var here = Generator.Conflicts.None; var atEnd = Generator.Conflicts.None;
        foreach (var m in markers)
        {
            if (m.Type == "ambig") here = here.Join(new Generator.Conflicts(0, [m.Id.Name]));
            else
            {
                var precs = Ast.Precedences!;
                var idx = -1;
                for (var i = 0; i < precs.Items.Length; i++) if (precs.Items[i].Id.Name == m.Id.Name) { idx = i; break; }
                if (idx < 0) Raise($"Reference to unknown precedence: '{m.Id.Name}'", m.Id.Start);
                var prec = precs.Items[idx]; var val = precs.Items.Length - idx;
                if (prec.Type == "cut") here = here.Join(new Generator.Conflicts(0, null, val));
                else
                {
                    here = here.Join(new Generator.Conflicts(val << 2));
                    atEnd = atEnd.Join(new Generator.Conflicts((val << 2) + (prec.Type == "left" ? 1 : prec.Type == "right" ? -1 : 0)));
                }
            }
        }
        return (here, atEnd);
    }

    [System.Diagnostics.CodeAnalysis.DoesNotReturn]
    internal void Raise(string message, int pos = 1) => Input.Raise(message, pos);
    internal void Warn(string message, int pos = -1) { var msg = Input.Message(message, pos); if (Options.Warn != null) Options.Warn(msg); else Console.WriteLine(msg); }

    void DefineRule(Term name, Parts[] choices)
    {
        var skip = CurrentSkip[CurrentSkip.Count - 1];
        foreach (var c in choices) Rules.Add(new Rule(name, c.Terms, c.EnsureConflicts(), skip));
    }

    Parts[] Resolve(NameExpression expr)
    {
        foreach (var b in Built) if (b.Matches(expr)) return [MP(b.Term)];
        var found = Tokens.GetToken(expr); if (found != null) return [MP(found)];
        foreach (var g in LocalTokens) { found = g.GetToken(expr); if (found != null) return [MP(found)]; }
        foreach (var e in ExternalTokens) { found = e.GetToken(expr); if (found != null) return [MP(found)]; }
        foreach (var e in ExternalSpecializers) { found = e.GetToken(expr); if (found != null) return [MP(found)]; }
        var known = AstRules.Find(r => r.Rule.Id.Name == expr.Id.Name);
        if (known == null) { Raise($"Reference to undefined rule '{expr.Id.Name}'", expr.Start); return []; }
        if (known.Rule.Params.Length != expr.Args.Length) Raise($"Wrong number or arguments for '{expr.Id.Name}'", expr.Start);
        Used(known.Rule.Id.Name);
        return [MP(BuildRule(known.Rule, expr.Args, known.Skip))];
    }

    Parts NormalizeRepeat(RepeatExpression expr)
    {
        var known = Built.Find(b => b.MatchesRepeat(expr));
        if (known != null) return MP(known.Term);
        var name = expr.Expr.Prec < expr.Prec ? $"({expr.Expr})+" : $"{expr.Expr}+";
        var term = Terms.MakeRepeat(Terms.UniqueName(name));
        Built.Add(new BuiltRule("+", [expr.Expr], term));
        DefineRule(term, NormalizeExpr(expr.Expr).Concat([MP(term, term)]).ToArray());
        return MP(term);
    }

    Parts[] NormalizeSequence(SequenceExpression expr)
    {
        var result = expr.Exprs.Select(NormalizeExpr).ToArray();
        Parts[] Complete(Parts start, int from, Conflicts endConflicts)
        {
            var (here, atEnd) = ConflictsFor(expr.Markers[from]);
            if (from == result.Length) return [start.WithConflicts(start.Terms.Length, here.Join(endConflicts))];
            var choices = new List<Parts>();
            foreach (var choice in result[from])
                foreach (var full in Complete(start.Concat(choice).WithConflicts(start.Terms.Length, here), from + 1, endConflicts.Join(atEnd)))
                    choices.Add(full);
            return choices.ToArray();
        }
        return Complete(Parts.None, 0, Generator.Conflicts.None);
    }

    internal Parts[] NormalizeExpr(Expression expr)
    {
        if (expr is RepeatExpression rep1 && rep1.Kind == "?") return [Parts.None, .. NormalizeExpr(rep1.Expr)];
        if (expr is RepeatExpression rep2) { var r = NormalizeRepeat(rep2); return rep2.Kind == "+" ? [r] : [Parts.None, r]; }
        if (expr is ChoiceExpression ch) return ch.Exprs.Aggregate(Array.Empty<Parts>(), (o, e) => o.Concat(NormalizeExpr(e)).ToArray());
        if (expr is SequenceExpression sq) return NormalizeSequence(sq);
        if (expr is LiteralExpression li) return [MP(Tokens.GetLiteral(li))];
        if (expr is NameExpression nm) return Resolve(nm);
        if (expr is SpecializeExpression sp) return [MP(ResolveSpecialization(sp))];
        if (expr is InlineRuleExpression il) return [MP(BuildRule(il.Rule, NoneExprs, CurrentSkip[CurrentSkip.Count - 1], true))];
        Raise($"This type of expression ('{expr}') may not occur in non-token rules", expr.Start); return [];
    }

    internal Term BuildRule(RuleDeclaration rule, Expression[] args, Term skip, bool inline = false)
    {
        var expr = SubstituteArgs(rule.Expr, args, rule.Params);
        var info = NodeInfo(rule.Props, inline ? "pg" : "pgi", rule.Id.Name, args, rule.Params, rule.Expr);
        if (info.Exported != null && rule.Params.Length > 0) Warn("Can't export parameterized rules", rule.Start);
        if (info.Exported != null && inline) Warn("Can't export inline rule", rule.Start);
        var name = NewName(rule.Id.Name + (args.Length > 0 ? "<" + string.Join(",", args) + ">" : ""), info.Name != null ? (object?)info.Name : true, info.Props);
        if (info.Inline) name.Inline = true;
        if (info.DynamicPrec != 0) RegisterDynamicPrec(name, info.DynamicPrec);
        if ((name.NodeType || info.Exported != null) && rule.Params.Length == 0)
        {
            if (info.Name == null) name.Preserve = true;
            if (!inline) NamedTerms[info.Exported ?? rule.Id.Name] = name;
        }
        if (!inline) Built.Add(new BuiltRule(rule.Id.Name, args, name));
        CurrentSkip.Add(skip);
        var parts = NormalizeExpr(expr);
        if (parts.Length > 100 * (expr is ChoiceExpression ce ? ce.Exprs.Length : 1))
            Warn($"Rule {rule.Id.Name} is generating a lot ({parts.Length}) of choices.\n  Consider splitting it up or reducing the amount of ? or | operator uses.", rule.Start);
        DefineRule(name, parts);
        CurrentSkip.RemoveAt(CurrentSkip.Count - 1);
        if (info.Group != null) DefinedGroups.Add(new DefinedGroup(name, info.Group, rule));
        return name;
    }

    internal NodeInfoResult NodeInfo(Prop[] props, string allow, string? defaultName = null,
        Expression[]? args = null, Identifier[]? parameters = null, Expression? expr = null,
        Dictionary<string, string>? defaultProps = null)
    {
        args ??= NoneExprs; parameters ??= [];
        var result = new Dictionary<string, string>();
        var name = defaultName != null && (allow.Contains('a') || !BuildHelpers.Ignored(defaultName)) && !defaultName.Contains(' ')
            ? defaultName : null;
        int? dialect = null; var dynamicPrec = 0; var inlineVal = false; string? group = null; string? exported = null;
        foreach (var prop in props)
        {
            if (!prop.At)
            {
                if (!KnownProps.ContainsKey(prop.Name))
                {
                    var builtin = new[] { "name", "dialect", "dynamicPrecedence", "export", "isGroup" }.Contains(prop.Name) ? $" (did you mean '@{prop.Name}'?)" : "";
                    Raise($"Unknown prop name '{prop.Name}'{builtin}", prop.Start);
                }
                result[prop.Name] = FinishProp(prop, args, parameters);
            }
            else if (prop.Name == "name") { name = FinishProp(prop, args, parameters); if (name.Contains(' ')) Raise($"Node names cannot have spaces ('{name}')", prop.Start); }
            else if (prop.Name == "dialect")
            {
                if (!allow.Contains('d')) Raise("Can't specify a dialect on non-token rules", props[0].Start);
                if (prop.Value.Length != 1 && prop.Value[0].Value == null) Raise("The '@dialect' rule prop must hold a plain string value");
                var dialectID = Array.IndexOf(Dialects, prop.Value[0].Value);
                if (dialectID < 0) Raise($"Unknown dialect '{prop.Value[0].Value}'", prop.Value[0].Start);
                dialect = dialectID;
            }
            else if (prop.Name == "dynamicPrecedence")
            {
                if (!allow.Contains('p')) Raise("Dynamic precedence can only be specified on nonterminals");
                if (prop.Value.Length != 1 || !System.Text.RegularExpressions.Regex.IsMatch(prop.Value[0].Value ?? "", @"^-?(?:10|\d)$"))
                    Raise("The '@dynamicPrecedence' rule prop must hold an integer between -10 and 10");
                dynamicPrec = int.Parse(prop.Value[0].Value!);
            }
            else if (prop.Name == "inline") { if (prop.Value.Length > 0) Raise("'@inline' doesn't take a value", prop.Value[0].Start); if (!allow.Contains('i')) Raise("Inline can only be specified on nonterminals"); inlineVal = true; }
            else if (prop.Name == "isGroup") { if (!allow.Contains('g')) Raise("'@isGroup' can only be specified on nonterminals"); group = prop.Value.Length > 0 ? FinishProp(prop, args, parameters) : defaultName; }
            else if (prop.Name == "export") { exported = prop.Value.Length > 0 ? FinishProp(prop, args, parameters) : defaultName; }
            else Raise($"Unknown built-in prop name '@{prop.Name}'", prop.Start);
        }
        if (expr != null && Ast.AutoDelim && (name != null || result.Count > 0)) { var delim = FindDelimiters(expr); if (delim != null) { BuildHelpers.AddToProp(delim[0], "closedBy", delim[1].NodeName!); BuildHelpers.AddToProp(delim[1], "openedBy", delim[0].NodeName!); } }
        if (defaultProps != null && defaultProps.Count > 0) foreach (var kvp in defaultProps) if (!result.ContainsKey(kvp.Key)) result[kvp.Key] = kvp.Value;
        if (result.Count > 0 && name == null) Raise("Node has properties but no name", props.Length > 0 ? props[0].Start : expr!.Start);
        if (inlineVal && (result.Count > 0 || dialect != null || dynamicPrec != 0)) Raise("Inline nodes can't have props, dynamic precedence, or a dialect", props[0].Start);
        if (inlineVal && name != null) name = null;
        return new NodeInfoResult { Name = name, Props = result, Dialect = dialect, DynamicPrec = dynamicPrec, Inline = inlineVal, Group = group, Exported = exported };
    }

    string FinishProp(Prop prop, Expression[] args, Identifier[] parameters) =>
        string.Join("", prop.Value.Select(part =>
        {
            if (part.Value != null) return part.Value;
            var pos = -1;
            for (var i = 0; i < parameters.Length; i++) if (parameters[i].Name == part.Name) { pos = i; break; }
            if (pos < 0) Raise($"Property refers to '{part.Name}', but no parameter by that name is in scope", part.Start);
            var e = args[pos];
            if (e is NameExpression ne && ne.Args.Length == 0) return ne.Id.Name;
            if (e is LiteralExpression le) return le.Value;
            Raise($"Expression '{e}' can not be used as part of a property value", part.Start); return "";
        }));

    Term ResolveSpecialization(SpecializeExpression expr)
    {
        var type = expr.Type;
        var info = NodeInfo(expr.Props, "d");
        var terminal = NormalizeExpr(expr.Token);
        if (terminal.Length != 1 || terminal[0].Terms.Length != 1 || !terminal[0].Terms[0].Terminal)
            Raise($"The first argument to '{type}' must resolve to a token", expr.Token.Start);
        string[]? values = null;
        var singleLit = BuildHelpers.IsLiteralToken(expr.Content);
        if (singleLit != null) values = singleLit;
        else if (expr.Content is ChoiceExpression ch && ch.Exprs.All(e => BuildHelpers.IsLiteralToken(e) != null))
            values = ch.Exprs.SelectMany(e => BuildHelpers.IsLiteralToken(e)!).ToArray();
        else Raise($"The second argument to '{expr.Type}' must be a literal or choice of literals", expr.Content.Start);
        var term = terminal[0].Terms[0]; Term? token = null;
        if (!Specialized.TryGetValue(term.Name, out var table)) { table = []; Specialized[term.Name] = table; }
        foreach (var value in values)
        {
            var known = table.Find(sp => sp.Value == value);
            if (known == null)
            {
                if (token == null)
                {
                    token = MakeTerminal(term.Name + "/" + JsonSerializer.Serialize(value), info.Name, info.Props);
                    if (info.Dialect != null) { if (!Tokens.ByDialect.ContainsKey(info.Dialect.Value)) Tokens.ByDialect[info.Dialect.Value] = []; Tokens.ByDialect[info.Dialect.Value].Add(token); }
                }
                table.Add(new SpecializeEntry(value, info.Name, token, type, info.Dialect));
                TokenOrigins[token.Name] = new TokenOrigin(spec: term);
                if (info.Name != null || info.Exported != null) { if (info.Name == null) token.Preserve = true; NamedTerms[info.Exported ?? info.Name!] = token; }
            }
            else
            {
                if (known.Type != type) Raise($"Conflicting specialization types for {JsonSerializer.Serialize(value)} of {term.Name} ({type} vs {known.Type})", expr.Start);
                if (known.Dialect != info.Dialect) Raise($"Conflicting dialects for specialization {JsonSerializer.Serialize(value)} of {term.Name}", expr.Start);
                if (known.Name != info.Name) Raise($"Conflicting names for specialization {JsonSerializer.Serialize(value)} of {term.Name}", expr.Start);
                if (token != null && known.Term != token) Raise($"Conflicting specialization tokens for {JsonSerializer.Serialize(value)} of {term.Name}", expr.Start);
                token = known.Term;
            }
        }
        return token!;
    }

    Term[]? FindDelimiters(Expression expr)
    {
        if (expr is not SequenceExpression seq || seq.Exprs.Length < 2) return null;
        (Term term, string str)? FT(Expression e)
        {
            if (e is LiteralExpression lit) return (Tokens.GetLiteral(lit), lit.Value);
            if (e is NameExpression ne && ne.Args.Length == 0)
            {
                var rule = Ast.Rules.FirstOrDefault(r => r.Id.Name == ne.Id.Name);
                if (rule != null) return FT(rule.Expr);
                var tok = Tokens.Rules.FirstOrDefault(r => r.Id.Name == ne.Id.Name);
                if (tok != null && tok.Expr is LiteralExpression tl) return (Tokens.GetToken(ne)!, tl.Value);
            }
            return null;
        }
        var last = FT(seq.Exprs[^1]); if (last == null || last.Value.term.NodeName == null) return null;
        var brackets = new[] { "()", "[]", "{}", "<>" };
        var bracket = brackets.FirstOrDefault(b => last.Value.str.Contains(b[1]) && !last.Value.str.Contains(b[0]));
        if (bracket == null) return null;
        var first = FT(seq.Exprs[0]);
        if (first == null || first.Value.term.NodeName == null || !first.Value.str.Contains(bracket[0]) || first.Value.str.Contains(bracket[1])) return null;
        return [first.Value.term, last.Value.term];
    }

    void RegisterDynamicPrec(Term term, int prec) { DynamicRulePrecedences.Add(new DynamicPrec(term, prec)); term.Preserve = true; }

    void DefineGroup(Term rule, string group, RuleDeclaration ast)
    {
        var recur = new List<Term>();
        List<Term> GetNamed(Term r)
        {
            if (r.NodeName != null) return [r];
            if (recur.Contains(r)) Raise($"Rule '{ast.Id.Name}' cannot define a group because it contains a non-named recursive rule ('{r.Name}')", ast.Start);
            var res = new List<Term>(); recur.Add(r);
            foreach (var rule in Rules) if (rule.Name == r)
            {
                var names = rule.Parts.Select(GetNamed).Where(x => x.Count > 0).ToList();
                if (names.Count > 1) Raise($"Rule '{ast.Id.Name}' cannot define a group because some choices produce multiple named nodes", ast.Start);
                if (names.Count == 1) res.AddRange(names[0]);
            }
            recur.RemoveAt(recur.Count - 1); return res;
        }
        foreach (var n in GetNamed(rule))
        {
            var existing = n.Props.ContainsKey("group") ? n.Props["group"].Split(' ') : [];
            n.Props["group"] = existing.Concat([group]).OrderBy(x => x).Aggregate((a, b) => a + " " + b);
        }
    }

    void CheckGroups()
    {
        var groups = new Dictionary<string, List<Term>>(); var nodeNames = new Dictionary<string, bool>();
        foreach (var term in Terms.Terms) if (term.NodeName != null)
        {
            nodeNames[term.NodeName] = true;
            if (term.Props.ContainsKey("group")) foreach (var g in term.Props["group"].Split(' '))
            { if (!groups.TryGetValue(g, out var l)) { l = []; groups[g] = l; } l.Add(term); }
        }
        var names = groups.Keys.ToList();
        for (var i = 0; i < names.Count; i++)
        {
            var terms = groups[names[i]];
            if (nodeNames.ContainsKey(names[i])) Warn($"Group name '{names[i]}' conflicts with a node of the same name");
            for (var j = i + 1; j < names.Count; j++)
            {
                var other = groups[names[j]];
                if (terms.Any(t => other.Contains(t)) && (terms.Count > other.Count ? other.Any(t => !terms.Contains(t)) : terms.Any(t => !other.Contains(t))))
                    Warn($"Groups '{names[i]}' and '{names[j]}' overlap without one being a superset of the other");
            }
        }
    }

    static Parts MP(params Term[] terms) => new(terms, null);
}

public class TokenSet
{
    public TokenState StartState = new();
    public List<BuiltRule> BuiltRules = [];
    public List<BuildingRule> Building = [];
    public RuleDeclaration[] Rules;
    public Dictionary<int, List<Term>> ByDialect = [];
    public PrecRelation[] PrecedenceRelations = [];
    public readonly Builder B;
    public readonly TokenDeclaration? Ast;

    public TokenSet(Builder b, TokenDeclaration? ast) { B = b; Ast = ast; Rules = ast?.Rules ?? []; foreach (var r in Rules) b.Unique(r.Id); }

    public virtual Term? GetToken(NameExpression expr)
    {
        foreach (var built in BuiltRules) if (built.Matches(expr)) return built.Term;
        var name = expr.Id.Name;
        var rule = Rules.FirstOrDefault(r => r.Id.Name == name);
        if (rule == null) return null;
        var info = B.NodeInfo(rule.Props, "d", name, expr.Args,
            rule.Params.Length != expr.Args.Length ? [] : rule.Params);
        var term = B.MakeTerminal(expr.ToString()!, info.Name, info.Props);
        if (info.Dialect != null) { if (!ByDialect.ContainsKey(info.Dialect.Value)) ByDialect[info.Dialect.Value] = []; ByDialect[info.Dialect.Value].Add(term); }
        if ((term.NodeType || info.Exported != null) && rule.Params.Length == 0)
        { if (!term.NodeType) term.Preserve = true; B.NamedTerms[info.Exported ?? name] = term; }
        BuildTokenRule(rule, expr, StartState, new TokenState([term]));
        BuiltRules.Add(new BuiltRule(name, expr.Args, term));
        return term;
    }

    internal void BuildTokenRule(RuleDeclaration rule, NameExpression expr, TokenState from, TokenState to, TokenArg[]? args = null)
    {
        args ??= [];
        if (rule.Params.Length != expr.Args.Length) B.Raise($"Incorrect number of arguments for token '{expr.Id.Name}'", expr.Start);
        var building = Building.Find(b => b.Name == expr.Id.Name && Expression.ExprsEq(expr.Args, b.Args));
        if (building != null)
        {
            if (building.To == to) { from.NullEdge(building.Start); return; }
            var li = Building.Count - 1; while (Building[li].Name != expr.Id.Name) li--;
            B.Raise($"Invalid (non-tail) recursion in token rules: {string.Join(" -> ", Building.Skip(li).Select(b => b.Name))}", expr.Start);
        }
        B.Used(rule.Id.Name); var start = new TokenState(); from.NullEdge(start);
        Building.Add(new BuildingRule(expr.Id.Name, start, to, expr.Args));
        BuildExpr(B.SubstituteArgs(rule.Expr, expr.Args, rule.Params), start, to,
            expr.Args.Select((e, i) => new TokenArg(rule.Params[i].Name, e, args)).ToArray());
        Building.RemoveAt(Building.Count - 1);
    }

    internal void BuildExpr(Expression expr, TokenState from, TokenState to, TokenArg[] args)
    {
        if (expr is NameExpression ne)
        {
            var arg = args.FirstOrDefault(a => a.Name == ne.Id.Name);
            if (arg != null) { BuildExpr(arg.Expr, from, to, arg.Scope); return; }
            RuleDeclaration? rule = null;
            for (var i = 0; i <= B.LocalTokens.Length; i++) { var set = i == B.LocalTokens.Length ? B.Tokens : (TokenSet)B.LocalTokens[i]; rule = set.Rules.FirstOrDefault(r => r.Id.Name == ne.Id.Name); if (rule != null) break; }
            if (rule == null) { B.Raise($"Reference to token rule '{ne.Id.Name}', which isn't found", expr.Start); return; }
            BuildTokenRule(rule, ne, from, to, args);
        }
        else if (expr is CharClass cc) { foreach (var r in Expression.CharClasses[cc.Type]) from.Edge(r[0], r[1], to); }
        else if (expr is ChoiceExpression ch) { foreach (var c in ch.Exprs) BuildExpr(c, from, to, args); }
        else if (BuildHelpers.IsEmpty(expr)) from.NullEdge(to);
        else if (expr is SequenceExpression sq)
        {
            var conflict = sq.Markers.FirstOrDefault(c => c.Length > 0);
            if (conflict != null) B.Raise("Conflict marker in token expression", conflict[0].Start);
            for (var i = 0; i < sq.Exprs.Length; i++) { var next = i == sq.Exprs.Length - 1 ? to : new TokenState(); BuildExpr(sq.Exprs[i], from, next, args); from = next; }
        }
        else if (expr is RepeatExpression rep)
        {
            if (rep.Kind == "*") { var loop = new TokenState(); from.NullEdge(loop); BuildExpr(rep.Expr, loop, loop, args); loop.NullEdge(to); }
            else if (rep.Kind == "+") { var loop = new TokenState(); BuildExpr(rep.Expr, from, loop, args); BuildExpr(rep.Expr, loop, loop, args); loop.NullEdge(to); }
            else { from.NullEdge(to); BuildExpr(rep.Expr, from, to, args); }
        }
        else if (expr is SetExpression se)
        {
            var ranges = se.Inverted ? BuildHelpers.InvertRanges(se.Ranges) : se.Ranges;
            foreach (var r in ranges) BuildHelpers.RangeEdges(from, to, r[0], r[1]);
        }
        else if (expr is LiteralExpression li)
        {
            for (var i = 0; i < li.Value.Length; i++) { var code = (int)li.Value[i]; var next = i == li.Value.Length - 1 ? to : new TokenState(); from.Edge(code, code + 1, next); from = next; }
        }
        else if (expr is AnyExpression)
        {
            var mid = new TokenState(); from.Edge(0, 0xdc00, to); from.Edge(0xdc00, TokenState.MaxChar + 1, to);
            from.Edge(0xd800, 0xdc00, mid); mid.Edge(0xdc00, 0xe000, to);
        }
        else B.Raise("Unrecognized expression type in token", expr.Start);
    }

    public void TakePrecedences()
    {
        var rel = new List<PrecRelation>();
        if (Ast != null) foreach (var group in Ast.Precedences)
        {
            var prev = new List<Term>();
            foreach (var item in group.Items)
            {
                var level = new List<Term>();
                if (item is NameExpression ne) { foreach (var b in BuiltRules) if (ne.Args.Length > 0 ? b.Matches(ne) : b.Id == ne.Id.Name) level.Add(b.Term); }
                else { var id = JsonSerializer.Serialize(((LiteralExpression)item).Value); var f = BuiltRules.Find(b => b.Id == id); if (f != null) level.Add(f.Term); }
                if (level.Count == 0) B.Warn($"Precedence specified for unknown token {item}", item.Start);
                foreach (var t in level) BuildHelpers.AddRel(rel, t, prev); prev = prev.Concat(level).ToList();
            }
        }
        PrecedenceRelations = rel.ToArray();
    }

    public bool PrecededBy(Term a, Term b) => PrecedenceRelations.FirstOrDefault(r => r.Term == a) is { } f && f.After.Contains(b);

    public int[] BuildPrecTable(TokenConflict[] softConflicts)
    {
        var precTable = new List<int>(); var rel = PrecedenceRelations.ToList();
        foreach (var c in softConflicts) if (c.Soft != 0)
        {
            var a = c.A; var b = c.B;
            if (!rel.Any(r => r.Term == a) || !rel.Any(r => r.Term == b)) continue;
            if (c.Soft < 0) (a, b) = (b, a);
            BuildHelpers.AddRel(rel, b, [a]); BuildHelpers.AddRel(rel, a, []);
        }
        while (rel.Count > 0) { var found = false;
            for (var i = 0; i < rel.Count; i++) { var rec = rel[i];
                if (rec.After.All(t => precTable.Contains(t.Id))) { precTable.Add(rec.Term.Id);
                    if (rel.Count == 1) goto done; rel[i] = rel[^1]; rel.RemoveAt(rel.Count - 1); found = true; break; } }
            if (!found) B.Raise($"Cyclic token precedence relation between {string.Join(", ", rel.Select(r => r.Term))}"); }
        done: return precTable.ToArray();
    }
}

public sealed class MainTokenSet : TokenSet
{
    public List<(Term A, Term B)> ExplicitConflicts = [];
    public MainTokenSet(Builder b, TokenDeclaration? ast) : base(b, ast) { }

    public Term GetLiteral(LiteralExpression expr)
    {
        var id = JsonSerializer.Serialize(expr.Value);
        foreach (var b in BuiltRules) if (b.Id == id) return b.Term;
        string? name = null; var props = new Dictionary<string, string>(); int? dialect = null; string? exported = null;
        var decl = Ast?.Literals.FirstOrDefault(l => l.Literal == expr.Value);
        if (decl != null) { var info = B.NodeInfo(decl.Props, "da", expr.Value); name = info.Name; props = info.Props; dialect = info.Dialect; exported = info.Exported; }
        var term = B.MakeTerminal(id, name, props);
        if (dialect != null) { if (!ByDialect.ContainsKey(dialect.Value)) ByDialect[dialect.Value] = []; ByDialect[dialect.Value].Add(term); }
        if (exported != null) B.NamedTerms[exported] = term;
        BuildExpr(expr, StartState, new TokenState([term]), []);
        BuiltRules.Add(new BuiltRule(id, [], term)); return term;
    }

    public void TakeConflicts()
    {
        Term? Resolve(Expression e)
        {
            if (e is NameExpression ne) { foreach (var b in BuiltRules) if (b.Matches(ne)) return b.Term; }
            else { var id = JsonSerializer.Serialize(((LiteralExpression)e).Value); var f = BuiltRules.Find(b => b.Id == id); if (f != null) return f.Term; }
            B.Warn($"Conflict specified for unknown token {e}", e.Start); return null;
        }
        if (Ast?.Conflicts != null) foreach (var c in Ast.Conflicts)
        {
            var a = Resolve(c.A); var b = Resolve(c.B);
            if (a != null && b != null) { if (a.Id < b.Id) (a, b) = (b, a); ExplicitConflicts.Add((a, b)); }
        }
    }

    public (TokenGroupSpec[] tokenGroups, int[] tokenPrec, ushort[] tokenData) BuildTokenGroups(
        LrState[] states, SkipInfo[] skipInfo, int startID)
    {
        var tokens = StartState.Compile();
        if (tokens.Accepting.Count > 0) B.Raise($"Grammar contains zero-length tokens (in '{tokens.Accepting[0].Name}')",
            Rules.FirstOrDefault(r => r.Id.Name == tokens.Accepting[0].Name)?.Start ?? 0);
        var allConflicts = tokens.FindConflicts(BuildHelpers.CheckTogether(states, B, skipInfo))
            .Where(c => !PrecededBy(c.A, c.B) && !PrecededBy(c.B, c.A)).ToList();
        foreach (var (a, b) in ExplicitConflicts) if (!allConflicts.Any(c => c.A == a && c.B == b)) allConflicts.Add(new TokenConflict(a, b, 0, "", ""));
        var softConflicts = allConflicts.Where(c => c.Soft != 0).ToArray();
        var conflicts = allConflicts.Where(c => c.Soft == 0).ToArray();
        var errors = new List<(TokenConflict c, string e)>();
        var groups = new List<TokenGroupSpec>();
        foreach (var state in states)
        {
            if (state.DefaultReduce != null || state.TokenGroup > -1) continue;
            var terms = new List<Term>(); var incompatible = new List<Term>();
            var skip = skipInfo[Array.IndexOf(B.SkipRules, state.Skip)].StartTokens;
            foreach (var t in skip) if (state.Actions.Any(a => a.Term == t)) B.Raise($"Use of token {t.Name} conflicts with skip rule");
            var stateTerms = new List<Term>();
            for (var i = 0; i < state.Actions.Count + skip.Length; i++)
            {
                var t = i < state.Actions.Count ? state.Actions[i].Term : skip[i - state.Actions.Count];
                if (B.TokenOrigins.TryGetValue(t.Name, out var orig) && orig.Spec != null) t = orig.Spec;
                else if (orig?.External != null) continue;
                BuildHelpers.AddToSet(stateTerms, t);
            }
            if (stateTerms.Count == 0) continue;
            foreach (var t in stateTerms) foreach (var conflict in conflicts)
            {
                var conflicting = conflict.A == t ? conflict.B : conflict.B == t ? conflict.A : null;
                if (conflicting == null) continue;
                if (stateTerms.Contains(conflicting) && !errors.Any(e => e.c == conflict))
                {
                    var example = !string.IsNullOrEmpty(conflict.ExampleA) ? $" (example: {JsonSerializer.Serialize(conflict.ExampleA)}{(!string.IsNullOrEmpty(conflict.ExampleB) ? $" vs {JsonSerializer.Serialize(conflict.ExampleB)}" : "")})" : "";
                    errors.Add((conflict, $"Overlapping tokens {t.Name} and {conflicting.Name} used in same context{example}\nAfter: {state.Set[0].Trail()}"));
                }
                BuildHelpers.AddToSet(terms, t); BuildHelpers.AddToSet(incompatible, conflicting);
            }
            TokenGroupSpec? tokenGroup = null;
            foreach (var g in groups) { if (incompatible.Any(t => g.Tokens.Contains(t))) continue; foreach (var t in terms) BuildHelpers.AddToSet(g.Tokens, t); tokenGroup = g; break; }
            if (tokenGroup == null) { tokenGroup = new TokenGroupSpec(terms.ToArray(), groups.Count + startID); groups.Add(tokenGroup); }
            state.TokenGroup = tokenGroup.GroupIDValue;
        }
        if (errors.Count > 0) B.Raise(string.Join("\n\n", errors.Select(e => e.e)));
        if (groups.Count + startID > 16) B.Raise($"Too many different token groups ({groups.Count}) to represent them as a 16-bit bitfield");
        var precTable = BuildPrecTable(softConflicts);
        return (groups.ToArray(), precTable, tokens.ToArray(BuildHelpers.BuildTokenMasks(groups), precTable));
    }
}

public sealed class LocalTokenSet : TokenSet
{
    public Term? Fallback;
    public readonly LocalTokenDeclaration LocalAst;

    public LocalTokenSet(Builder b, LocalTokenDeclaration ast) : base(b, (TokenDeclaration?)null)
    {
        LocalAst = ast; Rules = ast.Rules; foreach (var r in Rules) b.Unique(r.Id);
        if (ast.Fallback != null) b.Unique(ast.Fallback.Id);
    }

    public override Term? GetToken(NameExpression expr)
    {
        Term? term = null;
        if (LocalAst.Fallback != null && LocalAst.Fallback.Id.Name == expr.Id.Name)
        {
            if (expr.Args.Length > 0) B.Raise($"Incorrect number of arguments for {expr.Id.Name}", expr.Start);
            if (Fallback == null)
            {
                var info = B.NodeInfo(LocalAst.Fallback.Props, "", expr.Id.Name);
                term = Fallback = B.MakeTerminal(expr.Id.Name, info.Name, info.Props);
                if (term.NodeType || info.Exported != null) { if (!term.NodeType) term.Preserve = true; B.NamedTerms[info.Exported ?? expr.Id.Name] = term; }
                B.Used(expr.Id.Name);
            }
            term = Fallback;
        }
        else term = base.GetToken(expr);
        if (term != null && !B.TokenOrigins.ContainsKey(term.Name)) B.TokenOrigins[term.Name] = new TokenOrigin(group: this);
        return term;
    }

    public LocalTokenGroupSpec BuildLocalGroup(LrState[] states, SkipInfo[] skipInfo, int id)
    {
        var tokens = StartState.Compile();
        if (tokens.Accepting.Count > 0) B.Raise($"Grammar contains zero-length tokens (in '{tokens.Accepting[0].Name}')",
            Rules.FirstOrDefault(r => r.Id.Name == tokens.Accepting[0].Name)?.Start ?? 0);
        foreach (var c in tokens.FindConflicts((_, _) => true))
            if (!PrecededBy(c.A, c.B) && !PrecededBy(c.B, c.A))
                B.Raise($"Overlapping tokens {c.A.Name} and {c.B.Name} in local token group{(!string.IsNullOrEmpty(c.ExampleA) ? $" (example: {JsonSerializer.Serialize(c.ExampleA)})" : "")}");
        foreach (var state in states)
        {
            if (state.DefaultReduce != null) continue;
            Term? usesThis = null;
            Term? usesOther = skipInfo[Array.IndexOf(B.SkipRules, state.Skip)].StartTokens.ElementAtOrDefault(0);
            foreach (var action in state.Actions)
            {
                var t = action.Term;
                if (B.TokenOrigins.TryGetValue(t.Name, out var orig))
                {
                    while (orig?.Spec != null) { orig = B.TokenOrigins.TryGetValue(orig.Spec.Name, out var o2) ? o2 : null; }
                    if (orig?.Group == this) usesThis = t; else usesOther = t;
                }
                else usesOther = t;
            }
            if (usesThis != null)
            {
                if (usesOther != null) B.Raise($"Tokens from a local token group used together with other tokens ({usesThis.Name} with {usesOther.Name})");
                state.TokenGroup = id;
            }
        }
        var precTable = BuildPrecTable([]);
        var groupMasks = new Dictionary<int, int> { [id] = LrSeq.End };
        var tokenData = tokens.ToArray(groupMasks, precTable);
        var precOffset = tokenData.Length;
        var fullData = new ushort[tokenData.Length + precTable.Length + 1];
        Array.Copy(tokenData, fullData, tokenData.Length);
        for (var i = 0; i < precTable.Length; i++) fullData[precOffset + i] = (ushort)precTable[i];
        fullData[^1] = LrSeq.End;
        return new LocalTokenGroupSpec(id, fullData, precOffset, Fallback?.Id);
    }
}

public sealed class ExternalTokenSet
{
    public readonly Dictionary<string, Term> Tokens;
    public readonly Builder B;
    public readonly ExternalTokenDeclaration Ast;

    public ExternalTokenSet(Builder b, ExternalTokenDeclaration ast)
    {
        B = b; Ast = ast; Tokens = BuildHelpers.GatherExtTokens(b, ast.Tokens);
        foreach (var kvp in Tokens) b.TokenOrigins[kvp.Value.Name] = new TokenOrigin(external: this);
    }

    public Term? GetToken(NameExpression expr) => BuildHelpers.FindExtToken(B, Tokens, expr);

    public void CheckConflicts(LrState[] states, SkipInfo[] skipInfo)
    {
        var conflicting = new List<Term>();
        foreach (var id in Ast.Conflicts)
        {
            if (!B.NamedTerms.TryGetValue(id.Name, out var term)) B.Warn($"Unknown conflict term '{id.Name}'");
            else if (!term.Terminal) B.Warn($"Term '{id.Name}' isn't a terminal and cannot be used in a token conflict.");
            else if (Tokens.ContainsKey(id.Name)) B.Warn($"External token set specifying a conflict with one of its own tokens ('{id.Name}')");
            else conflicting.Add(term);
        }
        if (conflicting.Count > 0) foreach (var state in states)
        {
            var skip = skipInfo[Array.IndexOf(B.SkipRules, state.Skip)].StartTokens;
            var relevant = false; Term? conflict = null;
            for (var i = 0; i < state.Actions.Count + skip.Length; i++)
            {
                var t = i < state.Actions.Count ? state.Actions[i].Term : skip[i - state.Actions.Count];
                if (Tokens.ContainsKey(t.Name)) relevant = true;
                else if (conflicting.Contains(t)) conflict = t;
            }
            if (relevant && conflict != null) B.Raise($"Tokens from external group used together with conflicting token '{conflict.Name}'\nAfter: {state.Set[0].Trail()}", Ast.Start);
        }
    }
}

public sealed class ExternalSpecializer
{
    public Term? Term; public readonly Dictionary<string, Term> Tokens;
    public readonly Builder B; public readonly ExternalSpecializeDeclaration Ast;

    public ExternalSpecializer(Builder b, ExternalSpecializeDeclaration ast) { B = b; Ast = ast; Tokens = BuildHelpers.GatherExtTokens(b, ast.Tokens); }

    public void Finish()
    {
        var terms = B.NormalizeExpr(Ast.Token);
        if (terms.Length != 1 || terms[0].Terms.Length != 1 || !terms[0].Terms[0].Terminal)
            B.Raise($"The token expression to '@external {Ast.Type}' must resolve to a token", Ast.Token.Start);
        Term = terms[0].Terms[0];
        foreach (var kvp in Tokens) B.TokenOrigins[kvp.Value.Name] = new TokenOrigin(spec: Term, external: this);
    }

    public Term? GetToken(NameExpression expr) => BuildHelpers.FindExtToken(B, Tokens, expr);
}

public static class BuildHelpers
{
    public static readonly string[] Keywords =
        ["arguments","await","break","case","catch","continue","debugger","default","do","else","eval",
         "finally","for","function","if","return","switch","throw","try","var","while","with","null",
         "true","false","instanceof","typeof","void","delete","new","in","this","const","class",
         "extends","export","import","super","enum","implements","interface","let","package","private",
         "protected","public","static","yield","require"];

    public static void AddToSet<T>(List<T> set, T value) { if (!set.Contains(value)) set.Add(value); }
    public static void AddToProp(Term term, string prop, string value)
    {
        var cur = term.Props.GetValueOrDefault(prop, "");
        if (string.IsNullOrEmpty(cur) || !cur.Split(' ').Contains(value)) term.Props[prop] = string.IsNullOrEmpty(cur) ? value : cur + " " + value;
    }
    public static bool IsEmpty(Expression expr) => expr is SequenceExpression s && s.Exprs.Length == 0;
    public static bool IsExported(RuleDeclaration rule) => rule.Props.Any(p => p.At && p.Name == "export");
    public static bool Ignored(string name) { var f = name[0]; return f == '_' || char.ToUpperInvariant(f) != f; }
    public static string SerializePropValue(string v) => !System.Text.RegularExpressions.Regex.IsMatch(v, @"^(true|false|\d+(\.\d+)?|\.\d+)$") ? JsonSerializer.Serialize(v) : v;

    public static string[]? IsLiteralToken(Expression expr)
    {
        if (expr is LiteralExpression l) return [l.Value];
        if (expr is SequenceExpression s) { var r = ""; foreach (var sub in s.Exprs) { var li = IsLiteralToken(sub); if (li == null) return null; r += string.Join("", li); } return [r]; }
        return null;
    }

    public static int ReduceAction(Rule rule, SkipInfo[] skipInfo, int? depth = null)
    {
        var d = depth ?? rule.Parts.Length;
        return rule.Name.Id | LrAction.ReduceFlag |
            (rule.IsRepeatWrap && d == rule.Parts.Length ? LrAction.RepeatFlag : 0) |
            (skipInfo.Any(i => i.Rule == rule.Name) ? LrAction.StayFlag : 0) |
            (d << LrAction.ReduceDepthShift);
    }

    public static Dictionary<string, int> BuildSpecializeTable(List<SpecializeEntry> spec)
    {
        var table = new Dictionary<string, int>();
        foreach (var e in spec) { var code = e.Type == "specialize" ? LrSpecializeConsts.Specialize : LrSpecializeConsts.Extend; table[e.Value] = (e.Term.Id << 1) | code; }
        return table;
    }

    public static Func<int, bool> FindSkipStates(LrState[] table, List<Term> startRules)
    {
        var nonSkip = new Dictionary<int, bool>(); var work = new List<LrState>();
        void Add(LrState s) { if (!nonSkip.ContainsKey(s.Id)) { nonSkip[s.Id] = true; work.Add(s); } }
        foreach (var s in table) if (s.StartRule != null && startRules.Contains(s.StartRule)) Add(s);
        for (var i = 0; i < work.Count; i++) { foreach (var a in work[i].Actions) if (a is Shift sh) Add(sh.Target); foreach (var g in work[i].Goto) Add(g.Target); }
        return id => !nonSkip.ContainsKey(id);
    }

    public static ushort[] ComputeGotoTable(LrState[] states)
    {
        var gotoMap = new Dictionary<int, Dictionary<int, List<int>>>(); var maxTerm = 0;
        foreach (var state in states) foreach (var entry in state.Goto)
        {
            maxTerm = Math.Max(entry.Term.Id, maxTerm);
            if (!gotoMap.TryGetValue(entry.Term.Id, out var set)) { set = []; gotoMap[entry.Term.Id] = set; }
            if (!set.TryGetValue(entry.Target.Id, out var list)) { list = []; set[entry.Target.Id] = list; }
            list.Add(state.Id);
        }
        var data = new DataBuilder(); var index = new List<int>(); var offset = maxTerm + 2;
        for (var term = 0; term <= maxTerm; term++)
        {
            if (!gotoMap.TryGetValue(term, out var entries)) { index.Add(1); continue; }
            var tt = new List<int>(); var keys = entries.Keys.ToList();
            for (var ki = 0; ki < keys.Count; ki++) { var target = keys[ki]; var list = entries[target]; tt.Add((ki == keys.Count - 1 ? 1 : 0) + (list.Count << 1)); tt.Add(target); tt.AddRange(list); }
            index.Add(data.StoreArray(tt.ToArray()) + offset);
        }
        if (index.Any(n => n > 0xffff)) throw new GenError("Goto table too large");
        var result = new ushort[1 + index.Count + data.Finish().Length];
        result[0] = (ushort)(maxTerm + 1);
        for (var i = 0; i < index.Count; i++) result[1 + i] = (ushort)index[i];
        var finished = data.Finish(); Array.Copy(finished, 0, result, 1 + index.Count, finished.Length);
        return result;
    }

    public static Dictionary<int, int> BuildTokenMasks(List<TokenGroupSpec> groups)
    {
        var masks = new Dictionary<int, int>();
        foreach (var g in groups) { var gm = 1 << g.GroupIDValue; foreach (var t in g.Tokens) { masks.TryGetValue(t.Id, out var ex); masks[t.Id] = ex | gm; } }
        return masks;
    }

    public static Func<Term, Term, bool> CheckTogether(LrState[] states, Builder b, SkipInfo[] skipInfo)
    {
        var cache = new Dictionary<int, bool>();
        bool HasTerm(LrState state, Term term) =>
            state.Actions.Any(a => a.Term == term) || skipInfo[Array.IndexOf(b.SkipRules, state.Skip)].StartTokens.Contains(term);
        return (a, bT) =>
        {
            if (a.Id < bT.Id) (a, bT) = (bT, a);
            var key = a.Id | (bT.Id << 16);
            if (cache.TryGetValue(key, out var c)) return c;
            return cache[key] = states.Any(s => HasTerm(s, a) && HasTerm(s, bT));
        };
    }

    public static void AddRel(List<PrecRelation> rel, Term term, List<Term> after)
    {
        var fi = rel.FindIndex(r => r.Term == term);
        if (fi < 0) rel.Add(new PrecRelation(term, after.ToList()));
        else rel[fi] = new PrecRelation(term, rel[fi].After.Concat(after).ToList());
    }

    public static void RangeEdges(TokenState from, TokenState to, int low, int hi)
    {
        const int Astral = 0x10000, GapStart = 0xd800, GapEnd = 0xe000, LowSurrB = 0xdc00, HighSurrB = 0xdfff;
        if (low < Astral)
        {
            if (low < GapStart) from.Edge(low, Math.Min(hi, GapStart), to);
            if (hi > GapEnd) from.Edge(Math.Max(low, GapEnd), Math.Min(hi, TokenState.MaxChar + 1), to);
            low = Astral;
        }
        if (hi <= Astral) return;
        var lowStr = char.ConvertFromUtf32(low); var hiStr = char.ConvertFromUtf32(hi - 1);
        var lowA = (int)lowStr[0]; var lowB = lowStr.Length > 1 ? (int)lowStr[1] : 0;
        var hiA = (int)hiStr[0]; var hiB = hiStr.Length > 1 ? (int)hiStr[1] : 0;
        if (lowA == hiA) { var hop = new TokenState(); from.Edge(lowA, lowA + 1, hop); hop.Edge(lowB, hiB + 1, to); }
        else
        {
            var ms = lowA; var me = hiA;
            if (lowB > LowSurrB) { ms++; var hop = new TokenState(); from.Edge(lowA, lowA + 1, hop); hop.Edge(lowB, HighSurrB + 1, to); }
            if (hiB < HighSurrB) { me--; var hop = new TokenState(); from.Edge(hiA, hiA + 1, hop); hop.Edge(LowSurrB, hiB + 1, to); }
            if (ms <= me) { var hop = new TokenState(); from.Edge(ms, me + 1, hop); hop.Edge(LowSurrB, HighSurrB + 1, to); }
        }
    }

    public static int[][] InvertRanges(int[][] ranges)
    {
        const int MaxCode = 0x10ffff; var pos = 0; var result = new List<int[]>();
        foreach (var r in ranges) { if (r[0] > pos) result.Add([pos, r[0]]); pos = r[1]; }
        if (pos <= MaxCode) result.Add([pos, MaxCode + 1]);
        return result.ToArray();
    }

    public static Dictionary<string, Term> GatherExtTokens(Builder b, TokenEntry[] tokens)
    {
        var result = new Dictionary<string, Term>();
        foreach (var tok in tokens)
        {
            b.Unique(tok.Id);
            var info = b.NodeInfo(tok.Props, "d", tok.Id.Name);
            var term = b.MakeTerminal(tok.Id.Name, info.Name, info.Props);
            if (info.Dialect != null) { if (!b.Tokens.ByDialect.ContainsKey(info.Dialect.Value)) b.Tokens.ByDialect[info.Dialect.Value] = []; b.Tokens.ByDialect[info.Dialect.Value].Add(term); }
            b.NamedTerms[tok.Id.Name] = term; result[tok.Id.Name] = term;
        }
        return result;
    }

    public static Term? FindExtToken(Builder b, Dictionary<string, Term> tokens, NameExpression expr)
    {
        if (!tokens.TryGetValue(expr.Id.Name, out var f)) return null;
        if (expr.Args.Length > 0) b.Raise("External tokens cannot take arguments", expr.Args[0].Start);
        b.Used(expr.Id.Name); return f;
    }

    public static Rule[] InlineRules(Rule[] rules, Term[] preserve)
    {
        for (var pass = 0; ; pass++)
        {
            var inlinable = new Dictionary<string, Rule[]>(); var found = false;
            if (pass == 0) foreach (var rule in rules) if (rule.Name.Inline && !inlinable.ContainsKey(rule.Name.Name))
            {
                var group = rules.Where(r => r.Name == rule.Name).ToArray();
                if (group.Any(r => r.Parts.Contains(rule.Name))) continue;
                inlinable[rule.Name.Name] = group; found = true;
            }
            for (var i = 0; i < rules.Length; i++)
            {
                var rule = rules[i];
                if (!rule.Name.Interesting && !rule.Parts.Contains(rule.Name) && rule.Parts.Length < 3 &&
                    !preserve.Contains(rule.Name) &&
                    (rule.Parts.Length == 1 || rules.All(o => o.Skip == rule.Skip || !o.Parts.Contains(rule.Name))) &&
                    !rule.Parts.Any(p => inlinable.ContainsKey(p.Name)) &&
                    !rules.Select((r, j) => (r, j)).Any(x => x.j != i && x.r.Name == rule.Name))
                { inlinable[rule.Name.Name] = [rule]; found = true; }
            }
            if (!found) return rules;
            var newRules = new List<Rule>();
            foreach (var rule in rules)
            {
                if (inlinable.ContainsKey(rule.Name.Name)) continue;
                if (!rule.Parts.Any(p => inlinable.ContainsKey(p.Name))) { newRules.Add(rule); continue; }
                void Expand(int at, Conflicts[] conflicts, Term[] parts)
                {
                    if (at == rule.Parts.Length) { newRules.Add(new Rule(rule.Name, parts, conflicts, rule.Skip)); return; }
                    var next = rule.Parts[at];
                    if (!inlinable.TryGetValue(next.Name, out var replace)) { Expand(at + 1, [..conflicts, rule.Conflicts[at + 1]], [..parts, next]); return; }
                    foreach (var r in replace)
                    {
                        var nc = new List<Conflicts>();
                        for (var ci = 0; ci < conflicts.Length - 1; ci++) nc.Add(conflicts[ci]);
                        nc.Add(conflicts[at].Join(r.Conflicts[0]));
                        for (var ci = 1; ci < r.Conflicts.Length - 1; ci++) nc.Add(r.Conflicts[ci]);
                        nc.Add(rule.Conflicts[at + 1].Join(r.Conflicts[^1]));
                        Expand(at + 1, nc.ToArray(), parts.Concat(r.Parts).ToArray());
                    }
                }
                Expand(0, [rule.Conflicts[0]], []);
            }
            rules = newRules.ToArray();
        }
    }

    public static Rule[] MergeRules(Rule[] rules)
    {
        var merged = new Dictionary<string, Term>(); var foundAny = false;
        for (var i = 0; i < rules.Length;)
        {
            var gs = i; var name = rules[i++].Name; while (i < rules.Length && rules[i].Name == name) i++;
            var size = i - gs; if (name.Interesting) continue;
            for (var j = i; j < rules.Length;)
            {
                var os = j; var on = rules[j++].Name; while (j < rules.Length && rules[j].Name == on) j++;
                if (j - os != size || on.Interesting) continue;
                var match = true;
                for (var k = 0; k < size && match; k++) if (rules[gs + k].CmpNoName(rules[os + k]) != 0) match = false;
                if (match) { merged[name.Name] = on; foundAny = true; }
            }
        }
        if (!foundAny) return rules;
        return rules.Where(r => !merged.ContainsKey(r.Name.Name)).Select(r =>
            r.Parts.All(p => !merged.ContainsKey(p.Name)) ? r
            : new Rule(r.Name, r.Parts.Select(p => merged.GetValueOrDefault(p.Name, p)).ToArray(), r.Conflicts, r.Skip)).ToArray();
    }

    public static Rule[] SimplifyRules(List<Rule> rules, Term[] preserve) => MergeRules(InlineRules(rules.ToArray(), preserve));
}

public static class BuildStatic
{
    public static LRParser BuildParser(string text, BuildOptions? options = null) => BuildExt.BuildParser(text, options);
    public static (string parser, string terms) BuildParserFile(string text, BuildOptions? options = null) => BuildExt.BuildParserFile(text, options);
}

public abstract record TokenizerEntry
{
    public record TokenGroup(int ID) : TokenizerEntry;
    public record LocalTokenGroup(string Data, int PrecTable, int? ElseToken) : TokenizerEntry;
    public record External(string Name) : TokenizerEntry;
}

public abstract record SpecializedEntry
{
    public record Table(int Term, Dictionary<string, int> Lookup) : SpecializedEntry;
    public record ExternalEntry(int Term, string Name) : SpecializedEntry;
}

public sealed class SerializedParser
{
    public required string States;
    public required string StateData;
    public required string Goto;
    public required string NodeNames;
    public required int MaxTerm;
    public required int RepeatNodeCount;
    public required string[]? NodePropNames;
    public required List<object[]>? NodePropData;
    public required int[]? SkippedNodes;
    public required string TokenData;
    public required List<TokenizerEntry> TokenizerEntries;
    public required Dictionary<string, int[]> TopRules;
    public required Dictionary<string, int>? Dialects;
    public required Dictionary<int, int>? DynamicPrecedences;
    public required List<SpecializedEntry> SpecializedEntries;
    public required int TokenPrec;
    public required Dictionary<int, string>? TermNames;
    public required Dictionary<string, int>? TermTable;
}

public static class BuildExt
{
    public static LRParser BuildParser(string text, BuildOptions? options = null)
    {
        var builder = new Builder(text, options ?? new BuildOptions());
        return builder.GetParser();
    }
    public static (string parser, string terms) BuildParserFile(string text, BuildOptions? options = null) =>
        new Builder(text, options ?? new BuildOptions()).GetParserFile();

    public static SerializedParser BuildSerializedParser(string text, BuildOptions? options = null)
    {
        var builder = new Builder(text, options ?? new BuildOptions());
        var result = builder.PrepareParser();

        string[]? nodePropNames = null;
        List<object[]>? nodePropData = null;
        if (result.NodeProps.Count > 0)
        {
            nodePropNames = new string[result.NodeProps.Count];
            nodePropData = new List<object[]>();
            for (var i = 0; i < result.NodeProps.Count; i++)
            {
                var np = result.NodeProps[i];
                nodePropNames[i] = np.Prop;
                var entries = new List<object>();
                foreach (var kvp in np.Values)
                {
                    var ids = kvp.Value;
                    var value = builder.KnownProps.ContainsKey(np.Prop)
                        ? BuildHelpers.SerializePropValue(kvp.Key)
                        : kvp.Key;
                    if (ids.Count == 1)
                    {
                        entries.Add(ids[0]);
                        entries.Add(value);
                    }
                    else
                    {
                        entries.Add(-ids.Count);
                        foreach (var id in ids) entries.Add(id);
                        entries.Add(value);
                    }
                }
                nodePropData.Add(entries.ToArray());
            }
        }

        var tokenizerEntries = new List<TokenizerEntry>();
        foreach (var tok in result.Tokenizers)
        {
            if (tok is TokenGroupSpec btg)
                tokenizerEntries.Add(new TokenizerEntry.TokenGroup(btg.GroupIDValue));
            else if (tok is LocalTokenGroupSpec ltg)
                tokenizerEntries.Add(new TokenizerEntry.LocalTokenGroup(
                    EncodeUtil.EncodeArray(ltg.FullData),
                    ltg.PrecOffset,
                    ltg.FallbackId));
            else if (tok is ExternalTokenGroupSpec ext)
                tokenizerEntries.Add(new TokenizerEntry.External(ext.ExtAst.Id.Name));
        }

        var specializedEntries = new List<SpecializedEntry>();
        foreach (var v in result.Specialized)
        {
            if (v is ExternalSpecializer ext)
                specializedEntries.Add(new SpecializedEntry.ExternalEntry(ext.Term!.Id, ext.Ast.Id.Name));
            else
            {
                dynamic d = v;
                Term token = d.Token;
                var tbl = d.Table;
                specializedEntries.Add(new SpecializedEntry.Table(token.Id, tbl));
            }
        }

        return new SerializedParser
        {
            States = EncodeUtil.EncodeArray(result.States),
            StateData = EncodeUtil.EncodeArray(result.StateData),
            Goto = EncodeUtil.EncodeArray(result.Goto),
            NodeNames = result.NodeNames,
            MaxTerm = result.MaxTerm,
            RepeatNodeCount = result.RepeatNodeCount,
            NodePropNames = nodePropNames,
            NodePropData = nodePropData,
            SkippedNodes = result.SkippedTypes.Count > 0 ? result.SkippedTypes.ToArray() : null,
            TokenData = EncodeUtil.EncodeArray(result.TokenData),
            TokenizerEntries = tokenizerEntries,
            TopRules = result.TopRules,
            Dialects = result.Dialects.Count > 0 ? result.Dialects : null,
            DynamicPrecedences = result.DynamicPrecedences,
            SpecializedEntries = specializedEntries,
            TokenPrec = result.TokenPrec,
            TermNames = result.TermNames,
            TermTable = result.TermTable
        };
    }
}
