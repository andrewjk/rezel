using Rezel.Common;
using static Rezel.Lr.SpecializeConsts;

namespace Rezel.Lr;

public sealed class Dialect
{
    public readonly string? Source;
    public readonly bool[] Flags;
    public readonly byte[]? Disabled;

    public Dialect(string? source, bool[] flags, byte[]? disabled)
    {
        Source = source;
        Flags = flags;
        Disabled = disabled;
    }

    public bool Allows(int term) => Disabled == null || Disabled[term] == 0;
}

public sealed class ContextTracker
{
    public readonly object? Start;
    public readonly Func<object?, int, Stack, InputStream, object?> Shift;
    public readonly Func<object?, int, Stack, InputStream, object?> Reduce;
    public readonly Func<object?, Tree, Stack, InputStream, object?> Reuse;
    public readonly Func<object?, int> Hash;
    public readonly bool Strict;

    public ContextTracker(
        object? start,
        Func<object?, int, Stack, InputStream, object?>? shift = null,
        Func<object?, int, Stack, InputStream, object?>? reduce = null,
        Func<object?, Tree, Stack, InputStream, object?>? reuse = null,
        Func<object?, int>? hash = null,
        bool strict = true)
    {
        Start = start;
        Shift = shift ?? Id2;
        Reduce = reduce ?? Id2;
        Reuse = reuse ?? Id3;
        Hash = hash ?? (_ => 0);
        Strict = strict;
    }

    private static object? Id2(object? x, int _, Stack __, InputStream ___) => x;
    private static object? Id3(object? x, Tree _, Stack __, InputStream ___) => x;
}

public sealed class Parse : IPartialParse
{
    private static readonly Comparison<Stack> StackScoreComparer = (a, b) => b.Score - a.Score;

    private List<Stack> _stacksA = [];
    private List<Stack> _stacksB = [];
    public List<Stack> Stacks;
    public int Recovering;
    public FragmentCursor? Fragments;
    public int NextStackID = 0x2654;
    public int MinStackPos;
    public List<Tree> Reused = [];
    public InputStream Stream;
    public TokenCache Tokens;
    public int TopTerm;
    public int? _stoppedAt;

    public int? StoppedAt { get => _stoppedAt; }

    public int LastBigReductionStart = -1;
    public int LastBigReductionSize;
    public int BigReductionCount;

    public readonly LRParser Parser;
    public readonly IInput Input;
    public readonly CommonRange[] Ranges;

    public Parse(LRParser parser, IInput input, TreeFragment[] fragments, CommonRange[] ranges)
    {
        Parser = parser;
        Input = input;
        Ranges = ranges;
        Stream = new InputStream(input, ranges);
        Tokens = new TokenCache(parser, Stream);
        TopTerm = parser.Top[1];
        var from = ranges[0].From;
        Stacks = _stacksA;
        _stacksA.Add(Stack.Start(this, parser.Top[0], from));
        Fragments = fragments.Length > 0 && Stream.End - from > parser.BufferLength * 4
            ? new FragmentCursor(fragments, parser.NodeSet)
            : null;
    }

    public int ParsedPos => MinStackPos;

    public Tree? Advance()
    {
        var stacks = Stacks;
        var pos = MinStackPos;
        var newStacks = Stacks = ReferenceEquals(Stacks, _stacksA) ? _stacksB : _stacksA;
        newStacks.Clear();
        List<Stack>? stopped = null;
        List<int>? stoppedTokens = null;

        if (BigReductionCount > Rec.MaxLeftAssociativeReductionCount && stacks.Count == 1)
        {
            var s = stacks[0];
            while (s.ForceReduce() && s.StackList.Count > 0 &&
                   s.StackList[s.StackList.Count - 2] >= LastBigReductionStart) { }
            BigReductionCount = LastBigReductionSize = 0;
        }

        for (var i = 0; i < stacks.Count; i++)
        {
            var stack = stacks[i];
            while (true)
            {
                Tokens.MainToken = null;
                if (stack.Pos > pos)
                {
                    newStacks.Add(stack);
                }
                else if (AdvanceStack(stack, newStacks, stacks))
                {
                    continue;
                }
                else
                {
                    stopped ??= [];
                    stoppedTokens ??= [];
                    stopped.Add(stack);
                    var tok = Tokens.GetMainToken(stack);
                    stoppedTokens.Add(tok.Value);
                    stoppedTokens.Add(tok.End);
                }
                break;
            }
        }

        if (newStacks.Count == 0)
        {
            var finished = stopped != null ? FindFinished(stopped) : null;
            if (finished != null) return StackToTree(finished);

            if (Parser.Strict)
                throw new Exception("No parse at " + pos);

            if (Recovering == 0) Recovering = Rec.Distance;
        }

        if (Recovering != 0 && stopped != null)
        {
            var finished = StoppedAt != null && stopped[0].Pos > StoppedAt
                ? stopped[0]
                : RunRecovery(stopped, stoppedTokens!, newStacks);
            if (finished != null) return StackToTree(finished.ForceAll());
        }

        if (Recovering != 0)
        {
            var maxRemaining = Recovering == 1 ? 1 : Recovering * Rec.MaxRemainingPerStep;
            if (newStacks.Count > maxRemaining)
            {
                newStacks.Sort(StackScoreComparer);
                newStacks.RemoveRange(maxRemaining, newStacks.Count - maxRemaining);
            }
            var reducePosAbove = false;
            for (var i = 0; i < newStacks.Count; i++)
            {
                if (newStacks[i].ReducePos > pos) { reducePosAbove = true; break; }
            }
            if (reducePosAbove) Recovering--;
        }
        else if (newStacks.Count > 1)
        {
            for (var i = 0; i < newStacks.Count - 1; i++)
            {
                var stack = newStacks[i];
                for (var j = i + 1; j < newStacks.Count; j++)
                {
                    var other = newStacks[j];
                    if (stack.SameState(other) ||
                        (stack.Buffer.Count > Rec.MinBufferLengthPrune &&
                         other.Buffer.Count > Rec.MinBufferLengthPrune))
                    {
                        var diff = stack.Score - other.Score;
                        if ((diff != 0 ? diff : stack.Buffer.Count - other.Buffer.Count) > 0)
                        {
                            newStacks.RemoveAt(j--);
                        }
                        else
                        {
                            newStacks.RemoveAt(i--);
                            goto outerContinue;
                        }
                    }
                }
            }
            if (newStacks.Count > Rec.MaxStackCount)
            {
                newStacks.Sort(StackScoreComparer);
                newStacks.RemoveRange(Rec.MaxStackCount, newStacks.Count - Rec.MaxStackCount);
            }
        }
    outerContinue:

        MinStackPos = newStacks[0].Pos;
        for (var i = 1; i < newStacks.Count; i++)
            if (newStacks[i].Pos < MinStackPos) MinStackPos = newStacks[i].Pos;
        return null;
    }

    public void StopAt(int pos)
    {
        if (StoppedAt != null && StoppedAt < pos)
            throw new ArgumentOutOfRangeException("Can't move stoppedAt forward");
        _stoppedAt = pos;
    }

    private bool AdvanceStack(Stack stack, List<Stack>? stacks, List<Stack>? split)
    {
        var start = stack.Pos;
        var parser = Parser;

        if (StoppedAt != null && start > StoppedAt) return stack.ForceReduce();

        if (Fragments != null)
        {
            var strictCx = stack.CurContext != null && stack.CurContext.Tracker.Strict;
            var cxHash = strictCx ? stack.CurContext!.Hash : 0;
            for (var cached = Fragments.NodeAt(start); cached != null;)
            {
                var typeMatch = Parser.NodeSet.Types[cached.Type.Id] == cached.Type;
                var match = typeMatch
                    ? parser.GetGoto(stack.State, cached.Type.Id)
                    : -1;
                if (match > -1 && cached.Length > 0 &&
                    (!strictCx || (cached.Prop(NodeProps.ContextHash) is int ch ? ch : 0) == cxHash))
                {
                    stack.UseNode(cached, match);
                    return true;
                }
                if (cached is not Tree t || t.Children.Length == 0 || t.Positions[0] > 0)
                    break;
                var inner = t.Children[0];
                if (inner is Tree innerTree && t.Positions[0] == 0) cached = innerTree;
                else break;
            }
        }

        var defaultReduce = parser.StateSlot(stack.State, ParseState.DefaultReduce);
        if (defaultReduce > 0)
        {
            stack.Reduce(defaultReduce);
            return true;
        }

        if (stack.StackList.Count >= Rec.CutDepth)
        {
            while (stack.StackList.Count > Rec.CutTo && stack.ForceReduce()) { }
        }

        var actions = Tokens.GetActions(stack);
        for (var i = 0; i < actions.Count;)
        {
            var action = actions[i++];
            var term = actions[i++];
            var end = actions[i++];
            var last = i == actions.Count || split == null;
            var localStack = last ? stack : stack.Split();
            var main = Tokens.MainToken;
            localStack.Apply(action, term, main?.Start ?? localStack.Pos, end);
            if (last) return true;
            else if (localStack.Pos > start) stacks!.Add(localStack);
            else split!.Add(localStack);
        }

        return false;
    }

    private bool AdvanceFully(Stack stack, List<Stack> newStacks)
    {
        var pos = stack.Pos;
        while (true)
        {
            if (!AdvanceStack(stack, null, null)) return false;
            if (stack.Pos > pos)
            {
                PushStackDedup(stack, newStacks);
                return true;
            }
        }
    }

    private Stack? RunRecovery(List<Stack> stacks, List<int> tokens, List<Stack> newStacks)
    {
        Stack? finished = null;
        var restarted = false;
        for (var i = 0; i < stacks.Count; i++)
        {
            var stack = stacks[i];
            var token = tokens[i << 1];
            var tokenEnd = tokens[(i << 1) + 1];

            if (stack.DeadEnd)
            {
                if (restarted) continue;
                restarted = true;
                stack.Restart();
                AdvanceFully(stack, newStacks);
                continue;
            }

            var force = stack.Split();
            for (var j = 0; j < Rec.ForceReduceLimit && force.ForceReduce(); j++)
            {
                if (AdvanceFully(force, newStacks)) break;
            }

            foreach (var insert in stack.RecoverByInsert(token))
            {
                AdvanceFully(insert, newStacks);
            }

            if (Stream.End > stack.Pos)
            {
                if (tokenEnd == stack.Pos)
                {
                    tokenEnd++;
                    token = Term.Err;
                }
                stack.RecoverByDelete(token, tokenEnd);
                PushStackDedup(stack, newStacks);
            }
            else if (finished == null || finished.Score < force.Score)
            {
                finished = force;
            }
        }

        return finished;
    }

    public Tree StackToTree(Stack stack)
    {
        stack.Close();
        return Tree.Build(new BuildData(
            buffer: StackBufferCursor.Create(stack),
            nodeSet: Parser.NodeSet,
            topID: TopTerm,
            maxBufferLength: Parser.BufferLength,
            reused: Reused,
            start: Ranges[0].From,
            length: stack.Pos - Ranges[0].From,
            minRepeatType: Parser.MinRepeatTerm
        ));
    }

    private static void PushStackDedup(Stack stack, List<Stack> newStacks)
    {
        for (var i = 0; i < newStacks.Count; i++)
        {
            var other = newStacks[i];
            if (other.Pos == stack.Pos && other.SameState(stack))
            {
                if (newStacks[i].Score < stack.Score) newStacks[i] = stack;
                return;
            }
        }
        newStacks.Add(stack);
    }

    private static Stack? FindFinished(List<Stack> stacks)
    {
        Stack? best = null;
        foreach (var stack in stacks)
        {
            var stopped = stack.P.StoppedAt;
            if ((stack.Pos == stack.P.Stream.End || (stopped != null && stack.Pos > stopped)) &&
                stack.P.Parser.StateFlag(stack.State, StateFlag.Accepting) &&
                (best == null || best.Score < stack.Score))
                best = stack;
        }
        return best;
    }
}

public sealed class FragmentCursor
{
    private int _i;
    private TreeFragment? _fragment;
    private int _safeFrom = -1;
    private int _safeTo = -1;
    private readonly List<Tree> _trees = [];
    private readonly List<int> _start = [];
    private readonly List<int> _index = [];
    private int _nextStart;

    private readonly TreeFragment[] _fragments;
    private readonly NodeSet _nodeSet;

    public FragmentCursor(TreeFragment[] fragments, NodeSet nodeSet)
    {
        _fragments = fragments;
        _nodeSet = nodeSet;
        NextFragment();
    }

    private void NextFragment()
    {
        var fr = _fragment = _i == _fragments.Length ? null : _fragments[_i++];
        if (fr != null)
        {
            _safeFrom = fr.OpenStart ? CutAt(fr.Tree, fr.From + fr.Offset, 1) - fr.Offset : fr.From;
            _safeTo = fr.OpenEnd ? CutAt(fr.Tree, fr.To + fr.Offset, -1) - fr.Offset : fr.To;
            _trees.Clear();
            _start.Clear();
            _index.Clear();
            _trees.Add(fr.Tree);
            _start.Add(-fr.Offset);
            _index.Add(0);
            _nextStart = _safeFrom;
        }
        else
        {
            _nextStart = int.MaxValue / 2;
        }
    }

    public Tree? NodeAt(int pos)
    {
        if (pos < _nextStart) return null;
        while (_fragment != null && _safeTo <= pos) NextFragment();
        if (_fragment == null) return null;

        while (true)
        {
            var last = _trees.Count - 1;
            if (last < 0)
            {
                NextFragment();
                return null;
            }
            var top = _trees[last];
            var index = _index[last];
            if (index == top.Children.Length)
            {
                _trees.RemoveAt(last);
                _start.RemoveAt(last);
                _index.RemoveAt(last);
                continue;
            }
            var next = top.Children[index];
            var start = _start[last] + top.Positions[index];
            if (start > pos)
            {
                _nextStart = start;
                return null;
            }
            if (next is Tree nextTree)
            {
                if (start == pos)
                {
                    if (start < _safeFrom) { return null; }
                    var end = start + nextTree.Length;
                    if (end <= _safeTo)
                    {
                        var lookAhead = nextTree.Prop(NodeProps.LookAhead);
                        if (lookAhead == 0 || end + lookAhead < _fragment!.To)
                        {
                            return nextTree;
                        }
                    }
                }
                _index[last]++;
                if (start + nextTree.Length >= Math.Max(_safeFrom, pos))
                {
                    _trees.Add(nextTree);
                    _start.Add(start);
                    _index.Add(0);
                }
            }
            else
            {
                _index[last]++;
                _nextStart = start + ((TreeBuffer)next).Length;
            }
        }
    }

    private static int CutAt(Tree tree, int pos, int side)
    {
        var cursor = tree.Cursor(IterMode.IncludeAnonymous);
        cursor.MoveTo(pos);
        while (true)
        {
            if (!(side < 0 ? cursor.ChildBefore(pos) : cursor.ChildAfter(pos)))
                while (true)
                {
                    if ((side < 0 ? cursor.To < pos : cursor.From > pos) && !cursor.Type.IsError)
                        return side < 0
                            ? Math.Max(0, Math.Min(cursor.To - 1, pos - Lookahead.Margin))
                            : Math.Min(tree.Length, Math.Max(cursor.From + 1, pos + Lookahead.Margin));
                    if (side < 0 ? cursor.PrevSibling() : cursor.NextSibling()) break;
                    if (!cursor.Parent()) return side < 0 ? 0 : tree.Length;
                }
        }
    }
}

public sealed class TokenCache
{
    public readonly CachedToken[] Tokens;
    public CachedToken? MainToken;
    public readonly List<int> Actions = [];
    public readonly InputStream Stream;
    private readonly CachedToken _eofToken = new();
    private readonly CachedToken _dummyToken = new();

    public TokenCache(LRParser parser, InputStream stream)
    {
        Stream = stream;
        Tokens = new CachedToken[parser.Tokenizers.Length];
        for (var i = 0; i < Tokens.Length; i++) Tokens[i] = new CachedToken();
    }

    public List<int> GetActions(Stack stack)
    {
        var actionIndex = 0;
        CachedToken? main = null;
        var parser = stack.P.Parser;
        var tokenizers = parser.Tokenizers;

        var mask = parser.StateSlot(stack.State, ParseState.TokenizerMask);
        var context = stack.CurContext?.Hash ?? 0;
        var lookAhead = 0;

        for (var i = 0; i < tokenizers.Length; i++)
        {
            if (((1 << i) & mask) == 0) continue;
            var tokenizer = tokenizers[i];
            var token = Tokens[i];
            if (main != null && !tokenizer.Fallback) continue;
            if (tokenizer.Contextual ||
                token.Start != stack.Pos ||
                token.Mask != mask ||
                token.Context != context)
            {
                UpdateCachedToken(token, tokenizer, stack);
                token.Mask = mask;
                token.Context = context;
            }
            if (token.LookAhead > token.End + Lookahead.Margin)
            {
                lookAhead = Math.Max(token.LookAhead, lookAhead);
            }

            if (token.Value != Term.Err)
            {
                var startIndex = actionIndex;
                if (token.Extended > -1)
                    actionIndex = AddActions(stack, token.Extended, token.End, actionIndex);
                actionIndex = AddActions(stack, token.Value, token.End, actionIndex);
                if (!tokenizer.Extend)
                {
                    main = token;
                    if (actionIndex > startIndex) break;
                }
            }
        }

        if (Actions.Count > actionIndex) Actions.RemoveRange(actionIndex, Actions.Count - actionIndex);
        if (lookAhead != 0) stack.SetLookAhead(lookAhead);
        if (main == null && stack.Pos == Stream.End)
        {
            main = _eofToken;
            main.Value = stack.P.Parser.EofTerm;
            main.Start = main.End = stack.Pos;
            actionIndex = AddActions(stack, main.Value, main.End, actionIndex);
        }
        MainToken = main;
        return Actions;
    }

    public CachedToken GetMainToken(Stack stack)
    {
        if (MainToken != null) return MainToken;
        var main = _dummyToken;
        var pos = stack.Pos;
        var p = stack.P;
        main.Start = pos;
        main.End = Math.Min(pos + 1, p.Stream.End);
        main.Value = pos == p.Stream.End ? p.Parser.EofTerm : Term.Err;
        return main;
    }

    private void UpdateCachedToken(CachedToken token, ITokenizer tokenizer, Stack stack)
    {
        var start = Stream.ClipPos(stack.Pos);
        tokenizer.Token(Stream.Reset(start, token), stack);
        if (token.Value > -1)
        {
            var parser = stack.P.Parser;
            for (var i = 0; i < parser.Specialized.Length; i++)
            {
                if (parser.Specialized[i] == token.Value)
                {
                    var result = parser.Specializers[i](Stream.ReadSpan(token.Start, token.End), stack);
                    if (result >= 0 && stack.P.Parser.Dialect.Allows(result >> 1))
                    {
                        if ((result & 1) == SpecializeConsts.Specialize) token.Value = result >> 1;
                        else token.Extended = result >> 1;
                        break;
                    }
                }
            }
        }
        else
        {
            token.Value = Term.Err;
            token.End = Stream.ClipPos(start + 1);
        }
    }

    private int PutAction(int action, int token, int end, int index)
    {
        for (var i = 0; i < index; i += 3)
            if (Actions[i] == action) return index;
        if (Actions.Count > index) Actions[index] = action;
        else Actions.Add(action);
        index++;
        if (Actions.Count > index) Actions[index] = token;
        else Actions.Add(token);
        index++;
        if (Actions.Count > index) Actions[index] = end;
        else Actions.Add(end);
        index++;
        return index;
    }

    private int AddActions(Stack stack, int token, int end, int index)
    {
        var state = stack.State;
        var parser = stack.P.Parser;
        var data = parser.Data;
        for (var set = 0; set < 2; set++)
        {
            for (var i = parser.StateSlot(state, set != 0 ? ParseState.Skip : ParseState.Actions); ; i += 3)
            {
                if (data[i] == Seq.End)
                {
                    if (data[i + 1] == Seq.Next)
                    {
                        i = LRParser.Pair(data, i + 2);
                    }
                    else
                    {
                        if (index == 0 && data[i + 1] == Seq.Other)
                            index = PutAction(LRParser.Pair(data, i + 2), token, end, index);
                        break;
                    }
                }
                if (data[i] == token) index = PutAction(LRParser.Pair(data, i + 1), token, end, index);
            }
        }
        return index;
    }
}

public static class Rec
{
    public const int Distance = 5;
    public const int MaxRemainingPerStep = 3;
    public const int MinBufferLengthPrune = 500;
    public const int ForceReduceLimit = 10;
    public const int CutDepth = 2800 * 3;
    public const int CutTo = 2000 * 3;
    public const int MaxLeftAssociativeReductionCount = 300;
    public const int MaxStackCount = 12;
}

public class LRParser : Parser
{
    public readonly uint[] States;
    public readonly ushort[] Data;
    public readonly ushort[] Goto;
    public readonly int MaxTerm;
    public readonly int MinRepeatTerm;
    public ITokenizer[] Tokenizers;
    public readonly Dictionary<string, int[]> TopRules;
    public ContextTracker? Context;
    public readonly Dictionary<string, int> Dialects;
    public readonly Dictionary<int, int>? DynamicPrecedences;
    public readonly ushort[] Specialized;
    public Func<ReadOnlySpan<char>, Stack, int>[] Specializers;
    public readonly int TokenPrecTable;
    public readonly Dictionary<int, string>? TermNames;
    public readonly int MaxNode;
    public Dialect Dialect;
    public List<ParseWrapper> Wrappers = [];
    public int[] Top;
    public int BufferLength;
    public bool Strict;
    public NodeSet NodeSet;

    public LRParser(LRParserSpec spec)
    {
        if (spec.Version != File.Version)
            throw new ArgumentOutOfRangeException(
                $"Parser version ({spec.Version}) doesn't match runtime version ({File.Version})");

        var nodeNamesList = new List<string>(spec.NodeNames.Split(' '));
        MinRepeatTerm = nodeNamesList.Count;
        for (var i = 0; i < spec.RepeatNodeCount; i++)
            nodeNamesList.Add("");
        var nodeNames = nodeNamesList.ToArray();

        var topTerms = spec.TopRules.Values.Select(r => r[1]).ToHashSet();
        var nodeProps = new List<(NodePropBase, object)>[nodeNames.Length];
        for (var i = 0; i < nodeProps.Length; i++) nodeProps[i] = [];

        void SetProp(int nodeID, NodePropBase prop, string value)
        {
            nodeProps[nodeID].Add((prop, prop.DeserializeObject(value)));
        }

        if (spec.NodeProps != null)
        {
            foreach (var propSpec in spec.NodeProps)
            {
                var prop = propSpec.Prop;
                for (var i = 0; i < propSpec.Entries.Length;)
                {
                    var next = (int)propSpec.Entries[i++];
                    if (next >= 0)
                    {
                        SetProp(next, prop, (string)propSpec.Entries[i++]);
                    }
                    else
                    {
                        var value = (string)propSpec.Entries[i + (-next)];
                        for (var j = -next; j > 0; j--) SetProp((int)propSpec.Entries[i++], prop, value);
                        i++;
                    }
                }
            }
        }

        var types = new NodeType[nodeNames.Length];
        for (var i = 0; i < nodeNames.Length; i++)
        {
            var props = nodeProps[i].Select(p => (NodePropSource)(t => p)).ToArray();
            types[i] = NodeType.Define(
                id: i,
                name: i >= MinRepeatTerm ? null : nodeNames[i],
                props: props.Length > 0 ? props : null,
                top: topTerms.Contains(i),
                error: i == 0,
                skipped: spec.SkippedNodes?.Contains(i) == true
            );
        }
        NodeSet = new NodeSet(types);

        if (spec.PropSources != null) NodeSet = NodeSet.Extend(spec.PropSources);
        Strict = false;
        BufferLength = Constants.DefaultBufferLength;

        var tokenArray = Decode.DecodeArray(spec.TokenData);
        Context = spec.Context;
        var specSpecialized = spec.Specialized ?? [];
        Specialized = new ushort[specSpecialized.Length];
        for (var i = 0; i < specSpecialized.Length; i++)
            Specialized[i] = (ushort)specSpecialized[i].Term;
        Specializers = specSpecialized.Select(SpecializerHelper.GetSpecializer).ToArray();

        States = Decode.DecodeArray32(spec.States);
        Data = Decode.DecodeArray(spec.StateData);
        Goto = Decode.DecodeArray(spec.Goto);
        MaxTerm = spec.MaxTerm;
        Tokenizers = spec.Tokenizers.Select(v => v is int n ? (ITokenizer)new TokenGroup(tokenArray, n) : (ITokenizer)v).ToArray();
        TopRules = spec.TopRules.ToDictionary(kvp => kvp.Key, kvp => kvp.Value);
        Dialects = spec.Dialects ?? [];
        DynamicPrecedences = spec.DynamicPrecedences;
        TokenPrecTable = spec.TokenPrec;
        TermNames = spec.TermNames;
        MaxNode = NodeSet.Types.Length - 1;

        Dialect = ParseDialect();
        Top = TopRules.Values.First();
    }

    public override IPartialParse CreateParse(IInput input, TreeFragment[] fragments, CommonRange[] ranges)
    {
        IPartialParse parse = new Parse(this, input, fragments, ranges);
        foreach (var w in Wrappers) parse = w(parse, input, fragments, ranges);
        return parse;
    }

    public int GetGoto(int state, int term, bool loose = false)
    {
        var table = Goto;
        if (term >= table[0]) return -1;
        var pos = table[term + 1];
        while (true)
        {
            var groupTag = table[pos++];
            var last = groupTag & 1;
            var target = table[pos++];
            if (last != 0 && loose) return target;
            for (var end = pos + (groupTag >> 1); pos < end; pos++)
                if (table[pos] == state) return target;
            if (last != 0) return -1;
        }
    }

    public int HasAction(int state, int terminal)
    {
        var data = Data;
        for (var set = 0; set < 2; set++)
        {
            for (var i = StateSlot(state, set != 0 ? ParseState.Skip : ParseState.Actions); ; i += 3)
            {
                var next = data[i];
                if (next == Seq.End)
                {
                    if (data[i + 1] == Seq.Next) next = data[i = Pair(data, i + 2)];
                    else if (data[i + 1] == Seq.Other) return Pair(data, i + 2);
                    else break;
                }
                if (next == terminal || next == Term.Err) return Pair(data, i + 1);
            }
        }
        return 0;
    }

    public int StateSlot(int state, int slot) => (int)States[state * ParseState.Size + slot];

    public bool StateFlag(int state, int flag) => (StateSlot(state, ParseState.Flags) & flag) > 0;

    public bool ValidAction(int state, int action)
    {
        var result = AllActions(state, a => a == action ? true : (bool?)null);
        return result == true;
    }

    public T? AllActions<T>(int state, Func<int, T?> action) where T : struct
    {
        var deflt = StateSlot(state, ParseState.DefaultReduce);
        T? result = deflt != 0 ? action(deflt) : null;
        for (var i = StateSlot(state, ParseState.Actions); result == null; i += 3)
        {
            if (Data[i] == Seq.End)
            {
                if (Data[i + 1] == Seq.Next) i = Pair(Data, i + 2);
                else break;
            }
            result = action(Pair(Data, i + 1));
        }
        return result;
    }

    public int[] NextStates(int state)
    {
        var terms = new List<int>();
        var result = new List<int>();
        for (var i = StateSlot(state, ParseState.Actions); ; i += 3)
        {
            if (Data[i] == Seq.End)
            {
                if (Data[i + 1] == Seq.Next) i = Pair(Data, i + 2);
                else break;
            }
            if ((Data[i + 2] & (Action.ReduceFlag >> 16)) == 0)
            {
                var value = Data[i + 1];
                if (!terms.Contains(value))
                {
                    terms.Add(value);
                    result.Add(Data[i]);
                    result.Add(value);
                }
            }
        }
        return result.ToArray();
    }

    public LRParser Configure(ParserConfig config)
    {
        var copy = (LRParser)MemberwiseClone();
        if (config.Props != null) copy.NodeSet = NodeSet.Extend(config.Props);
        if (config.Top != null)
        {
            if (!TopRules.TryGetValue(config.Top, out var info))
                throw new ArgumentOutOfRangeException($"Invalid top rule name {config.Top}");
            copy.Top = info;
        }
        if (config.Tokenizers != null)
            copy.Tokenizers = Tokenizers.Select(t =>
            {
                var found = config.Tokenizers!.FirstOrDefault(r => r.From == t);
                return found != null ? found.To : t;
            }).ToArray();
        if (config.Specializers != null)
        {
            copy.Specializers = Specializers.ToArray();
        }
        if (config.ContextTracker != null) copy.Context = config.ContextTracker;
        if (config.Dialect != null) copy.Dialect = ParseDialect(config.Dialect);
        if (config.Strict != null) copy.Strict = config.Strict.Value;
        if (config.Wrap != null) copy.Wrappers = [.. Wrappers, config.Wrap];
        if (config.BufferLength != null) copy.BufferLength = config.BufferLength.Value;
        return copy;
    }

    public bool HasWrappers() => Wrappers.Count > 0;

    public string GetName(int term)
    {
        if (TermNames != null && TermNames.TryGetValue(term, out var name)) return name;
        return term <= MaxNode ? (NodeSet.Types[term].Name ?? term.ToString()) : term.ToString();
    }

    public int EofTerm => MaxNode + 1;

    public NodeType TopNode => NodeSet.Types[Top[1]];

    public int DynamicPrecedence(int term)
    {
        return DynamicPrecedences != null && DynamicPrecedences.TryGetValue(term, out var prec) ? prec : 0;
    }

    public Dialect ParseDialect(string? dialect = null)
    {
        var values = Dialects.Keys.ToArray();
        var flags = new bool[values.Length];
        if (dialect != null)
        {
            foreach (var part in dialect.Split(' '))
            {
                var id = Array.IndexOf(values, part);
                if (id >= 0) flags[id] = true;
            }
        }
        byte[]? disabled = null;
        for (var i = 0; i < values.Length; i++)
        {
            if (!flags[i])
            {
                for (var j = Dialects[values[i]]; ;)
                {
                    var id = Data[j++];
                    if (id == Seq.End) break;
                    disabled ??= new byte[MaxTerm + 1];
                    disabled[id] = 1;
                }
            }
        }
        return new Dialect(dialect, flags, disabled);
    }

    public static LRParser Deserialize(LRParserSpec spec) => new(spec);

    internal static int Pair(ushort[] data, int off) => data[off] | (data[off + 1] << 16);
}

public sealed class LRParserSpec
{
    public int Version;
    public object States = null!;
    public object StateData = null!;
    public object Goto = null!;
    public string NodeNames = null!;
    public int MaxTerm;
    public int RepeatNodeCount;
    public NodePropSpec[]? NodeProps;
    public NodePropSource[]? PropSources;
    public int[]? SkippedNodes;
    public string TokenData = null!;
    public object[] Tokenizers = null!;
    public Dictionary<string, int[]> TopRules = null!;
    public ContextTracker? Context;
    public Dictionary<string, int>? Dialects;
    public Dictionary<int, int>? DynamicPrecedences;
    public SpecializerSpec[]? Specialized;
    public int TokenPrec;
    public Dictionary<int, string>? TermNames;
}

public sealed class NodePropSpec
{
    public NodePropBase Prop;
    public object[] Entries;

    public NodePropSpec(NodePropBase prop, params object[] entries)
    {
        Prop = prop;
        Entries = entries;
    }
}

public sealed class SpecializerSpec
{
    public int Term;
    public Func<ReadOnlySpan<char>, Stack, int>? Get;
    public Func<string, Stack, int>? External;
    public bool Extend;
}

public sealed class ParserConfig
{
    public NodePropSource[]? Props;
    public string? Top;
    public string? Dialect;
    public ExternalTokenizerReplace[]? Tokenizers;
    public SpecializerReplace[]? Specializers;
    public ContextTracker? ContextTracker;
    public bool? Strict;
    public ParseWrapper? Wrap;
    public int? BufferLength;
}

public sealed class ExternalTokenizerReplace
{
    public ExternalTokenizer From = null!;
    public ExternalTokenizer To = null!;
}

public sealed class SpecializerReplace
{
    public Func<string, Stack, int> From = null!;
    public Func<string, Stack, int> To = null!;
}

internal static class SpecializerHelper
{
    internal static Func<ReadOnlySpan<char>, Stack, int> GetSpecializer(SpecializerSpec spec)
    {
        if (spec.External != null)
        {
            var mask = spec.Extend ? SpecializeConsts.Extend : SpecializeConsts.Specialize;
            var ext = spec.External;
            return (value, stack) => (ext(value.ToString(), stack) << 1) | mask;
        }
        return spec.Get!;
    }
}
