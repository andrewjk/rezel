using Rezel.Common;

namespace Rezel.Lr;

public sealed class StackContext
{
    public readonly int Hash;
    public readonly ContextTracker Tracker;
    public readonly object? Context;

    public StackContext(ContextTracker tracker, object? context)
    {
        Tracker = tracker;
        Context = context;
        Hash = tracker.Strict ? tracker.Hash(context) : 0;
    }
}

public sealed class Stack
{
    public readonly Parse P;
    public readonly List<int> StackList;
    public int State;
    public int ReducePos;
    public int Pos;
    public int Score;
    public List<int> Buffer;
    public int BufferBase;
    public StackContext? CurContext;
    public int LookAhead;
    public Stack? Parent;

    public Stack(Parse p, List<int> stack, int state, int reducePos, int pos,
        int score, List<int> buffer, int bufferBase, StackContext? curContext,
        int lookAhead, Stack? parent)
    {
        P = p;
        StackList = stack;
        State = state;
        ReducePos = reducePos;
        Pos = pos;
        Score = score;
        Buffer = buffer;
        BufferBase = bufferBase;
        CurContext = curContext;
        LookAhead = lookAhead;
        Parent = parent;
    }

    public override string ToString()
    {
        var states = new List<int>();
        for (var i = 0; i < StackList.Count; i += 3) states.Add(StackList[i]);
        states.Add(State);
        return $"[{string.Join(",", states)}]@{Pos}{(Score != 0 ? "!" + Score : "")}";
    }

    public static Stack Start(Parse p, int state, int pos = 0)
    {
        var cx = p.Parser.Context;
        return new Stack(p, [], state, pos, pos, 0, [], 0,
            cx != null ? new StackContext(cx, cx.Start) : null, 0, null);
    }

    public object? Context => CurContext?.Context;

    public void PushState(int state, int start)
    {
        StackList.Add(State);
        StackList.Add(start);
        StackList.Add(BufferBase + Buffer.Count);
        State = state;
    }

    public void Reduce(int action)
    {
        var depth = action >> Action.ReduceDepthShift;
        var type = action & Action.ValueMask;
        var parser = P.Parser;

        var lookaheadRecord = ReducePos < Pos - Lookahead.Margin && SetLookAhead(Pos);

        var dPrec = parser.DynamicPrecedence(type);
        if (dPrec != 0) Score += dPrec;

        if (depth == 0)
        {
            if (type < parser.MinRepeatTerm && ReducePos < Pos) ReducePos = Pos;
            PushState(parser.GetGoto(State, type, true), ReducePos);
            if (type < parser.MinRepeatTerm)
                StoreNode(type, ReducePos, ReducePos, lookaheadRecord ? 8 : 4, true);
            ReduceContext(type, ReducePos);
            return;
        }

        var @base = StackList.Count - (depth - 1) * 3 - ((action & Action.StayFlag) != 0 ? 6 : 0);
        var start = @base > 0 ? StackList[@base - 2] : P.Ranges[0].From;
        if (type < parser.MinRepeatTerm && start == ReducePos && ReducePos < Pos)
            ReducePos = Pos;
        var size = ReducePos - start;

        if (size >= Recover.MinBigReduction && parser.NodeSet.Types[type] is { IsAnonymous: false })
        {
            if (start == P.LastBigReductionStart)
            {
                P.BigReductionCount++;
                P.LastBigReductionSize = size;
            }
            else if (P.LastBigReductionSize < size)
            {
                P.BigReductionCount = 1;
                P.LastBigReductionStart = start;
                P.LastBigReductionSize = size;
            }
        }

        var bufferBase = @base > 0 ? StackList[@base - 1] : 0;
        var count = BufferBase + Buffer.Count - bufferBase;

        if (type < parser.MinRepeatTerm || (action & Action.RepeatFlag) != 0)
        {
            var pos = parser.StateFlag(State, StateFlag.Skipped) ? Pos : ReducePos;
            StoreNode(type, start, pos, count + 4, true);
        }
        if ((action & Action.StayFlag) != 0)
        {
            State = StackList[@base];
        }
        else
        {
            var baseStateID = StackList[@base - 3];
            State = parser.GetGoto(baseStateID, type, true);
        }
        while (StackList.Count > @base) StackList.RemoveAt(StackList.Count - 1);
        ReduceContext(type, start);
    }

    public void StoreNode(int term, int start, int end, int size = 4, bool mustSink = false)
    {
        if (term == Term.Err &&
            (StackList.Count == 0 ||
             StackList[StackList.Count - 1] < Buffer.Count + BufferBase))
        {
            var top = Buffer.Count;
            if (top > 0 && Buffer[top - 4] == Term.Err && Buffer[top - 1] > -1)
            {
                if (start == end) return;
                if (Buffer[top - 2] >= start)
                {
                    Buffer[top - 2] = end;
                    return;
                }
            }
        }

        if (!mustSink || Pos == end)
        {
            Buffer.Add(term);
            Buffer.Add(start);
            Buffer.Add(end);
            Buffer.Add(size);
        }
        else
        {
            var index = Buffer.Count;
            if (index > 0 && (Buffer[index - 4] != Term.Err || Buffer[index - 1] < 0))
            {
                var mustMove = false;
                for (var scan = index; scan > 0 && Buffer[scan - 2] > end; scan -= 4)
                {
                    if (Buffer[scan - 1] >= 0)
                    {
                        mustMove = true;
                        break;
                    }
                }
                if (mustMove)
                    while (index > 0 && Buffer[index - 2] > end)
                    {
                        Buffer[index] = Buffer[index - 4];
                        Buffer[index + 1] = Buffer[index - 3];
                        Buffer[index + 2] = Buffer[index - 2];
                        Buffer[index + 3] = Buffer[index - 1];
                        index -= 4;
                        if (size > 4) size -= 4;
                    }
            }
            Buffer[index] = term;
            Buffer[index + 1] = start;
            Buffer[index + 2] = end;
            Buffer[index + 3] = size;
        }
    }

    public void Shift(int action, int type, int start, int end)
    {
        if ((action & Action.GotoFlag) != 0)
        {
            PushState(action & Action.ValueMask, Pos);
        }
        else if ((action & Action.StayFlag) == 0)
        {
            var nextState = action;
            var parser = P.Parser;
            Pos = end;
            var skipped = parser.StateFlag(nextState, StateFlag.Skipped);
            if (!skipped && (end > start || type <= parser.MaxNode)) ReducePos = end;
            PushState(nextState, skipped ? start : Math.Min(start, ReducePos));
            ShiftContext(type, start);
            if (type <= parser.MaxNode)
            {
                Buffer.Add(type);
                Buffer.Add(start);
                Buffer.Add(end);
                Buffer.Add(4);
            }
        }
        else
        {
            Pos = end;
            ShiftContext(type, start);
            if (type <= P.Parser.MaxNode)
            {
                Buffer.Add(type);
                Buffer.Add(start);
                Buffer.Add(end);
                Buffer.Add(4);
            }
        }
    }

    public void Apply(int action, int next, int nextStart, int nextEnd)
    {
        if ((action & Action.ReduceFlag) != 0) Reduce(action);
        else Shift(action, next, nextStart, nextEnd);
    }

    public void UseNode(Tree value, int next)
    {
        var index = P.Reused.Count - 1;
        if (index < 0 || P.Reused[index] != value)
        {
            P.Reused.Add(value);
            index++;
        }
        var start = Pos;
        ReducePos = Pos = start + value.Length;
        PushState(next, start);
        Buffer.Add(index);
        Buffer.Add(start);
        Buffer.Add(ReducePos);
        Buffer.Add(-1);
        if (CurContext != null)
            UpdateContext(CurContext.Tracker.Reuse(CurContext.Context, value, this, P.Stream.Reset(Pos - value.Length)));
    }

    public Stack Split()
    {
        var parent = this;
        var off = parent.Buffer.Count;
        if (off > 0 && parent.Buffer[off - 4] == Term.Err) off -= 4;
        while (off > 0 && parent.Buffer[off - 2] > parent.ReducePos) off -= 4;
        var buffer = parent.Buffer.GetRange(off, parent.Buffer.Count - off);
        var @base = parent.BufferBase + off;
        while (parent != null && @base == parent.BufferBase) parent = parent.Parent;
        return new Stack(P, new List<int>(StackList), State, ReducePos, Pos,
            Score, buffer, @base, CurContext, LookAhead, parent);
    }

    public void RecoverByDelete(int next, int nextEnd)
    {
        var isNode = next <= P.Parser.MaxNode;
        if (isNode) StoreNode(next, Pos, nextEnd, 4);
        StoreNode(Term.Err, Pos, nextEnd, isNode ? 8 : 4);
        Pos = ReducePos = nextEnd;
        Score -= Recover.Delete;
    }

    public bool CanShift(int term)
    {
        var sim = new SimulatedStack(this);
        while (true)
        {
            var action = P.Parser.StateSlot(sim.State, ParseState.DefaultReduce);
            if (action == 0) action = P.Parser.HasAction(sim.State, term);
            if (action == 0) return false;
            if ((action & Action.ReduceFlag) == 0) return true;
            sim.Reduce(action);
        }
    }

    public Stack[] RecoverByInsert(int next)
    {
        if (StackList.Count >= Recover.MaxInsertStackDepth) return [];

        var nextStates = P.Parser.NextStates(State);
        if (nextStates.Length > Recover.MaxNext << 1 ||
            StackList.Count >= Recover.DampenInsertStackDepth)
        {
            var best = new List<int>();
            for (var i = 0; i < nextStates.Length; i += 2)
            {
                var s = nextStates[i + 1];
                if (s != State && P.Parser.HasAction(s, next) != 0)
                {
                    best.Add(nextStates[i]);
                    best.Add(s);
                }
            }
            if (StackList.Count < Recover.DampenInsertStackDepth)
                for (var i = 0; best.Count < Recover.MaxNext << 1 && i < nextStates.Length; i += 2)
                {
                    var s = nextStates[i + 1];
                    if (!best.Where((v, idx) => (idx & 1) == 1 && v == s).Any())
                    {
                        best.Add(nextStates[i]);
                        best.Add(s);
                    }
                }
            nextStates = best.ToArray();
        }
        var result = new List<Stack>();
        for (var i = 0; i < nextStates.Length && result.Count < Recover.MaxNext; i += 2)
        {
            var s = nextStates[i + 1];
            if (s == State) continue;
            var stack = Split();
            stack.PushState(s, Pos);
            stack.StoreNode(Term.Err, stack.Pos, stack.Pos, 4, true);
            stack.ShiftContext(nextStates[i], Pos);
            stack.ReducePos = Pos;
            stack.Score -= Recover.Insert;
            result.Add(stack);
        }
        return result.ToArray();
    }

    public bool ForceReduce()
    {
        var parser = P.Parser;
        var reduce = parser.StateSlot(State, ParseState.ForcedReduce);
        if ((reduce & Action.ReduceFlag) == 0) return false;
        if (!parser.ValidAction(State, reduce))
        {
            var depth = reduce >> Action.ReduceDepthShift;
            var term = reduce & Action.ValueMask;
            var target = StackList.Count - depth * 3;
            if (target < 0 || parser.GetGoto(StackList[target], term, false) < 0)
            {
                var backup = FindForcedReduction();
                if (backup == null) return false;
                reduce = backup.Value;
            }
            StoreNode(Term.Err, Pos, Pos, 4, true);
            Score -= Recover.Reduce;
        }
        ReducePos = Pos;
        Reduce(reduce);
        return true;
    }

    public int? FindForcedReduction()
    {
        var parser = P.Parser;
        var seen = new List<int>();

        int? Explore(int state, int depth)
        {
            if (seen.Contains(state)) return null;
            seen.Add(state);
            return parser.AllActions(state, action =>
            {
                if ((action & (Action.StayFlag | Action.GotoFlag)) != 0) return null;
                if ((action & Action.ReduceFlag) != 0)
                {
                    var rDepth = (action >> Action.ReduceDepthShift) - depth;
                    if (rDepth > 1)
                    {
                        var term = action & Action.ValueMask;
                        var target = StackList.Count - rDepth * 3;
                        if (target >= 0 && parser.GetGoto(StackList[target], term, false) >= 0)
                            return (rDepth << Action.ReduceDepthShift) | Action.ReduceFlag | term;
                    }
                    return null;
                }
                return Explore(action, depth + 1);
            });
        }
        return Explore(State, 0);
    }

    public Stack ForceAll()
    {
        while (!P.Parser.StateFlag(State, StateFlag.Accepting))
        {
            if (!ForceReduce())
            {
                StoreNode(Term.Err, Pos, Pos, 4, true);
                break;
            }
        }
        return this;
    }

    public bool DeadEnd
    {
        get
        {
            if (StackList.Count != 3) return false;
            var parser = P.Parser;
            return parser.Data[parser.StateSlot(State, ParseState.Actions)] == Seq.End &&
                   parser.StateSlot(State, ParseState.DefaultReduce) == 0;
        }
    }

    public void Restart()
    {
        StoreNode(Term.Err, Pos, Pos, 4, true);
        State = StackList[0];
        StackList.Clear();
    }

    public bool SameState(Stack other)
    {
        if (State != other.State || StackList.Count != other.StackList.Count) return false;
        for (var i = 0; i < StackList.Count; i += 3)
            if (StackList[i] != other.StackList[i]) return false;
        return true;
    }

    public LRParser Parser => P.Parser;

    public bool DialectEnabled(int dialectID) => P.Parser.Dialect.Flags[dialectID];

    private void ShiftContext(int term, int start)
    {
        if (CurContext != null)
            UpdateContext(CurContext.Tracker.Shift(CurContext.Context, term, this, P.Stream.Reset(start)));
    }

    private void ReduceContext(int term, int start)
    {
        if (CurContext != null)
            UpdateContext(CurContext.Tracker.Reduce(CurContext.Context, term, this, P.Stream.Reset(start)));
    }

    private void EmitContext()
    {
        var last = Buffer.Count - 1;
        if (last < 0 || Buffer[last] != -3)
        {
            Buffer.Add(CurContext!.Hash);
            Buffer.Add(Pos);
            Buffer.Add(Pos);
            Buffer.Add(-3);
        }
    }

    public void EmitLookAhead()
    {
        var last = Buffer.Count - 1;
        if (last < 0 || Buffer[last] != -4)
        {
            Buffer.Add(LookAhead);
            Buffer.Add(Pos);
            Buffer.Add(Pos);
            Buffer.Add(-4);
        }
    }

    private void UpdateContext(object? context)
    {
        if (!Equals(context, CurContext!.Context))
        {
            var newCx = new StackContext(CurContext.Tracker, context);
            if (newCx.Hash != CurContext.Hash) EmitContext();
            CurContext = newCx;
        }
    }

    public bool SetLookAhead(int lookAhead)
    {
        if (lookAhead <= LookAhead) return false;
        EmitLookAhead();
        LookAhead = lookAhead;
        return true;
    }

    public void Close()
    {
        if (CurContext != null && CurContext.Tracker.Strict) EmitContext();
        if (LookAhead > 0) EmitLookAhead();
    }
}

public static class Lookahead
{
    public const int Margin = 25;
}

public static class Recover
{
    public const int Insert = 200;
    public const int Delete = 190;
    public const int Reduce = 100;
    public const int MaxNext = 4;
    public const int MaxInsertStackDepth = 300;
    public const int DampenInsertStackDepth = 120;
    public const int MinBigReduction = 2000;
}

internal sealed class SimulatedStack
{
    public int State;
    public List<int> StackList;
    public int Base;
    public readonly Stack Start;

    public SimulatedStack(Stack start)
    {
        Start = start;
        State = start.State;
        StackList = start.StackList;
        Base = StackList.Count;
    }

    public void Reduce(int action)
    {
        var term = action & Action.ValueMask;
        var depth = action >> Action.ReduceDepthShift;
        if (depth == 0)
        {
            if (StackList == Start.StackList) StackList = new List<int>(StackList);
            StackList.Add(State);
            StackList.Add(0);
            StackList.Add(0);
            Base += 3;
        }
        else
        {
            Base -= (depth - 1) * 3;
        }
        var gotoVal = Start.P.Parser.GetGoto(StackList[Base - 3], term, true);
        State = gotoVal;
    }
}

public sealed class StackBufferCursor : IBufferCursor
{
    public List<int> Buffer;
    public Stack Stack;
    public int Pos;
    public int Index;

    public StackBufferCursor(Stack stack, int pos, int index)
    {
        Stack = stack;
        Pos = pos;
        Index = index;
        Buffer = stack.Buffer;
        if (Index == 0) MaybeNext();
    }

    public static StackBufferCursor Create(Stack stack, int? pos = null)
    {
        var p = pos ?? stack.BufferBase + stack.Buffer.Count;
        return new StackBufferCursor(stack, p, p - stack.BufferBase);
    }

    public void MaybeNext()
    {
        var next = Stack.Parent;
        if (next != null)
        {
            Index = Stack.BufferBase - next.BufferBase;
            Stack = next;
            Buffer = next.Buffer;
        }
    }

    public int Id => Buffer[Index - 4];
    public int Start => Buffer[Index - 3];
    public int End => Buffer[Index - 2];
    public int Size => Buffer[Index - 1];
    int IBufferCursor.Pos => Pos;

    public void Next()
    {
        Index -= 4;
        Pos -= 4;
        if (Index == 0) MaybeNext();
    }

    public IBufferCursor Fork() => new StackBufferCursor(Stack, Pos, Index);
}
