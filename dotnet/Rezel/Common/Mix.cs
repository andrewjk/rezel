namespace Rezel.Common;

public readonly struct NestedParse
{
    public readonly Parser Parser;
    public readonly object? Overlay;
    public readonly bool Bracketed;

    public NestedParse(Parser parser, object? overlay = null, bool bracketed = false)
    {
        Parser = parser;
        Overlay = overlay;
        Bracketed = bracketed;
    }
}

public static class MixedParsing
{
    public static ParseWrapper ParseMixed(Func<ISyntaxNodeRef, IInput, NestedParse?> nest)
    {
        return (parse, input, fragments, ranges) =>
            (IPartialParse)new MixedParse(parse, nest, input, fragments, ranges);
    }
}

internal sealed class InnerParse
{
    public readonly Parser Parser;
    public IPartialParse Parse;
    public readonly CommonRange[]? Overlay;
    public readonly bool Bracketed;
    public readonly Tree Target;
    public readonly int From;

    public InnerParse(Parser parser, IPartialParse parse, CommonRange[]? overlay,
        bool bracketed, Tree target, int from)
    {
        Parser = parser;
        Parse = parse;
        Overlay = overlay;
        Bracketed = bracketed;
        Target = target;
        From = from;
    }
}

internal readonly struct ReusableMount
{
    public readonly TreeFragment Frag;
    public readonly MountedTree Mount;
    public readonly int Pos;

    public ReusableMount(TreeFragment frag, MountedTree mount, int pos)
    {
        Frag = frag;
        Mount = mount;
        Pos = pos;
    }
}

internal sealed class ActiveOverlay
{
    public int Depth;
    public readonly List<CommonRange> Ranges = [];
    public readonly Parser Parser;
    public readonly Func<ISyntaxNodeRef, object?> Predicate;
    public readonly ReusableMount[] Mounts;
    public readonly int Index;
    public readonly int Start;
    public readonly bool Bracketed;
    public readonly Tree Target;
    public readonly ActiveOverlay? Prev;

    public ActiveOverlay(Parser parser, Func<ISyntaxNodeRef, object?> predicate,
        ReusableMount[] mounts, int index, int start,
        bool bracketed, Tree target, ActiveOverlay? prev)
    {
        Parser = parser;
        Predicate = predicate;
        Mounts = mounts;
        Index = index;
        Start = start;
        Bracketed = bracketed;
        Target = target;
        Prev = prev;
    }
}

internal enum Cover
{
    None = 0,
    Partial = 1,
    Full = 2,
}

internal sealed class CoverInfo
{
    public readonly CommonRange[] Ranges;
    public int Depth;
    public readonly CoverInfo? Prev;

    public CoverInfo(CommonRange[] ranges, int depth, CoverInfo? prev)
    {
        Ranges = ranges;
        Depth = depth;
        Prev = prev;
    }
}

internal sealed class MixedParse : IPartialParse
{
    private IPartialParse? _baseParse;
    private readonly List<InnerParse> _inner = [];
    private int _innerDone;
    private Tree? _baseTree;
    private int? _stoppedAt;

    private readonly Func<ISyntaxNodeRef, IInput, NestedParse?> _nest;
    private readonly IInput _input;
    private readonly TreeFragment[] _fragments;
    private readonly CommonRange[] _ranges;

    private static readonly NodeProp<int> StoppedInner = new(perNode: true);

    public MixedParse(IPartialParse @base, Func<ISyntaxNodeRef, IInput, NestedParse?> nest,
        IInput input, TreeFragment[] fragments, CommonRange[] ranges)
    {
        _baseParse = @base;
        _nest = nest;
        _input = input;
        _fragments = fragments;
        _ranges = ranges;
    }

    public int ParsedPos
    {
        get
        {
            if (_baseParse != null) return 0;
            var pos = _input.Length;
            for (var i = _innerDone; i < _inner.Count; i++)
                if (_inner[i].From < pos)
                    pos = Math.Min(pos, _inner[i].Parse.ParsedPos);
            return pos;
        }
    }

    public int? StoppedAt => _stoppedAt;

    public void StopAt(int pos)
    {
        _stoppedAt = pos;
        if (_baseParse != null)
            _baseParse.StopAt(pos);
        else
            for (var i = _innerDone; i < _inner.Count; i++)
                _inner[i].Parse.StopAt(pos);
    }

    public Tree? Advance()
    {
        if (_baseParse != null)
        {
            var done = _baseParse.Advance();
            if (done == null) return null;
            _baseParse = null;
            _baseTree = done;
            StartInner();
            if (_stoppedAt != null)
                foreach (var ip in _inner)
                    ip.Parse.StopAt(_stoppedAt.Value);
        }

        if (_innerDone == _inner.Count)
        {
            var result = _baseTree!;
            if (_stoppedAt != null)
            {
                var pv = result.PropValues.ToList();
                pv.Add((StoppedInner, _stoppedAt.Value));
                result = new Tree(result.Type, result.Children, result.Positions, result.Length, pv.ToArray());
            }
            return result;
        }

        var innerParse = _inner[_innerDone];
        var innerDone = innerParse.Parse.Advance();
        if (innerDone != null)
        {
            _innerDone++;
            var props = innerParse.Target.Props != null
                ? new Dictionary<int, object>(innerParse.Target.Props)
                : new Dictionary<int, object>();
            props[NodeProps.Mounted.Id] = new MountedTree(innerDone, innerParse.Overlay,
                innerParse.Parser, innerParse.Bracketed);
            innerParse.Target.Props = props;
        }
        return null;
    }

    private void StartInner()
    {
        var fragmentCursor = new FragmentCursor(_fragments);
        ActiveOverlay? overlay = null;
        CoverInfo? covered = null;

        if (_baseTree == null) return;
        var cursor = new TreeCursor(
            new TreeNode(_baseTree, _ranges[0].From, 0, null),
            IterMode.IncludeAnonymous | IterMode.IgnoreMounts
        );

        while (true)
        {
            var enter = true;
            if (_stoppedAt != null && cursor.From >= _stoppedAt.Value)
            {
                enter = false;
            }
            else if (fragmentCursor.HasNode(cursor))
            {
                if (overlay != null)
                {
                    var match = overlay.Mounts.FirstOrDefault(m =>
                        m.Frag.From <= cursor.From && m.Frag.To >= cursor.To && m.Mount.Overlay != null);
                    if (!match.Equals(default))
                    {
                        foreach (var r in match.Mount.Overlay!)
                        {
                            var from = r.From + match.Pos;
                            var to = r.To + match.Pos;
                            if (from >= cursor.From && to <= cursor.To &&
                                !overlay.Ranges.Any(x => x.From < to && x.To > from))
                                overlay.Ranges.Add(new CommonRange(from, to));
                        }
                    }
                }
                enter = false;
            }
            else if (covered != null)
            {
                var isCovered = CheckCoverValue(covered.Ranges, cursor.From, cursor.To);
                if (isCovered != null)
                    enter = isCovered != Cover.Full;
            }
            else if (!cursor.Type.IsAnonymous &&
                     _nest(cursor.Ref, _input) is { } nestResult &&
                     (cursor.From < cursor.To || nestResult.Overlay == null))
            {
                if (cursor.Tree == null)
                {
                    Materialize(cursor);
                    if (overlay != null) overlay.Depth++;
                    if (covered != null) covered.Depth++;
                }

                var oldMounts = fragmentCursor.FindMounts(cursor.From, nestResult.Parser);

                if (nestResult.Overlay is Func<ISyntaxNodeRef, object?> overlayFn)
                {
                    overlay = new ActiveOverlay(
                        nestResult.Parser, overlayFn, oldMounts, _inner.Count, cursor.From,
                        nestResult.Bracketed, cursor.Tree!, overlay
                    );
                }
                else
                {
                    CommonRange[] nestRanges;
                    if (nestResult.Overlay is CommonRange[] overlayRanges)
                        nestRanges = PunchRanges(_ranges, overlayRanges);
                    else
                    {
                        var r = cursor.From < cursor.To
                            ? [new CommonRange(cursor.From, cursor.To)]
                            : Array.Empty<CommonRange>();
                        nestRanges = PunchRanges(_ranges, r);
                    }

                    if (nestRanges.Length > 0) CheckRanges(nestRanges);

                    if (nestRanges.Length > 0 || nestResult.Overlay == null)
                    {
                        IPartialParse parse;
                        if (nestRanges.Length > 0)
                            parse = nestResult.Parser.StartParse(_input,
                                EnterFragments(oldMounts, nestRanges), nestRanges);
                        else
                            parse = nestResult.Parser.StartParse("");

                        CommonRange[]? innerOverlay;
                        if (nestResult.Overlay is CommonRange[] ovr)
                            innerOverlay = ovr.Select(r => new CommonRange(r.From - cursor.From, r.To - cursor.From)).ToArray();
                        else
                            innerOverlay = null;

                        _inner.Add(new InnerParse(
                            nestResult.Parser, parse, innerOverlay,
                            nestResult.Bracketed, cursor.Tree!,
                            nestRanges.Length > 0 ? nestRanges[0].From : cursor.From
                        ));
                    }

                    if (nestResult.Overlay == null)
                        enter = false;
                    else if (nestRanges.Length > 0)
                        covered = new CoverInfo(nestRanges, 0, covered);
                }
            }
            else if (overlay != null)
            {
                var range = overlay.Predicate(cursor.Ref);
                if (range != null)
                {
                    CommonRange rangeVal;
                    if (range is CommonRange cr)
                        rangeVal = cr;
                    else if (range is bool b && b)
                        rangeVal = new CommonRange(cursor.From, cursor.To);
                    else
                        goto afterOverlay;

                    if (rangeVal.From < rangeVal.To)
                    {
                        if (overlay.Ranges.Count > 0 && overlay.Ranges[^1].To == rangeVal.From)
                            overlay.Ranges[^1] = new CommonRange(overlay.Ranges[^1].From, rangeVal.To);
                        else
                            overlay.Ranges.Add(rangeVal);
                    }
                }
            afterOverlay:;
            }

            if (enter && cursor.FirstChild())
            {
                if (overlay != null) overlay.Depth++;
                if (covered != null) covered.Depth++;
            }
            else
            {
                while (true)
                {
                    if (cursor.NextSibling()) goto nextIter;
                    if (!cursor.Parent()) goto done;
                    if (overlay != null)
                    {
                        overlay.Depth--;
                        if (overlay.Depth == 0)
                        {
                            var ranges = PunchRanges(_ranges, overlay.Ranges.ToArray());
                            if (ranges.Length > 0)
                            {
                                CheckRanges(ranges);
                                var ip = new InnerParse(
                                    overlay.Parser,
                                    overlay.Parser.StartParse(_input,
                                        EnterFragments(overlay.Mounts, ranges), ranges),
                                    overlay.Ranges.Select(r => new CommonRange(r.From - overlay.Start, r.To - overlay.Start)).ToArray(),
                                    overlay.Bracketed,
                                    overlay.Target,
                                    ranges[0].From
                                );
                                _inner.Insert(overlay.Index, ip);
                            }
                            overlay = overlay.Prev;
                        }
                    }
                    if (covered != null)
                    {
                        covered.Depth--;
                        if (covered.Depth <= 0)
                            covered = covered.Prev;
                    }
                }
            }
        nextIter:;
        }
    done:;
    }

    private static void CheckRanges(CommonRange[] ranges)
    {
        if (ranges.Length == 0 || ranges.Any(r => r.From >= r.To))
            throw new InvalidOperationException($"Invalid inner parse ranges given");
    }

    private static Cover? CheckCoverValue(CommonRange[] covered, int from, int to)
    {
        foreach (var range in covered)
        {
            if (range.From >= to) break;
            if (range.To > from)
                return range.From <= from && range.To >= to ? Cover.Full : Cover.Partial;
        }
        return null;
    }

    private static void SliceBuf(TreeBuffer buf, int startI, int endI,
        List<object> nodes, List<int> positions, int off)
    {
        if (startI < endI)
        {
            var from = buf.Buffer[startI + 1];
            nodes.Add(buf.Slice(startI, endI, from));
            positions.Add(from - off);
        }
    }

    private static void Materialize(TreeCursor cursor)
    {
        var node = cursor.Node;
        if (node is not BufferNode bufNode) return;
        var stack = new List<int>();
        var buffer = bufNode.Context.Buffer;

        do
        {
            stack.Add(cursor.Index);
            cursor.Parent();
        } while (cursor.Tree == null);

        var parentTreeNode = cursor._tree;
        var @base = cursor.Tree!;

        var i = 0;
        while (i < @base.Children.Length)
        {
            if (@base.Children[i] is TreeBuffer tb && ReferenceEquals(tb, buffer)) break;
            i++;
        }

        var buf = (TreeBuffer)@base.Children[i];
        var b = buf.Buffer;
        var newStack = new List<int> { i };

        Tree Split(int startI, int endI, NodeType type, int innerOffset, int length, int stackPos)
        {
            var targetI = stack[stackPos];
            var children = new List<object>();
            var positions = new List<int>();
            SliceBuf(buf, startI, targetI, children, positions, innerOffset);
            var from = b[targetI + 1];
            var to = b[targetI + 2];
            newStack.Add(children.Count);
            object child;
            if (stackPos > 0)
                child = Split(targetI + 4, b[targetI + 3], buf.Set.Types[b[targetI]], from, to - from, stackPos - 1);
            else
                child = bufNode.ToTree();
            children.Add(child);
            positions.Add(from - innerOffset);
            SliceBuf(buf, b[targetI + 3], endI, children, positions, innerOffset);
            return new Tree(type, children.ToArray(), positions.ToArray(), length);
        }

        var result = Split(0, b.Length, NodeType.None, 0, buf.Length, stack.Count - 1);
        @base.Children[i] = result;

        var currentTreeNode = parentTreeNode;
        for (var si = 0; si < newStack.Count; si++)
        {
            var idx = newStack[si];
            var tree = (Tree)currentTreeNode._tree.Children[idx];
            var pos = currentTreeNode._tree.Positions[idx];
            if (si == newStack.Count - 1)
            {
                var treeNode = new TreeNode(tree, pos + currentTreeNode.From, idx, currentTreeNode);
                cursor.Yield(treeNode);
            }
            else
            {
                currentTreeNode = new TreeNode(tree, pos + currentTreeNode.From, idx, currentTreeNode);
            }
        }
    }

    private static CommonRange[] PunchRanges(CommonRange[] outer, CommonRange[] ranges)
    {
        CommonRange[]? current = null;
        var j = 0;
        for (var i = 1; i < outer.Length; i++)
        {
            var gapFrom = outer[i - 1].To;
            var gapTo = outer[i].From;
            var active = current ?? ranges;
            while (j < active.Length)
            {
                var r = active[j];
                if (r.From >= gapTo) break;
                if (r.To <= gapFrom) { j++; continue; }
                if (current == null) current = (CommonRange[])ranges.Clone();
                if (r.From < gapFrom)
                {
                    current![j] = new CommonRange(r.From, gapFrom);
                    if (r.To > gapTo)
                        current = current[..j].Append(new CommonRange(gapTo, r.To)).Concat(current[j..]).ToArray();
                }
                else if (r.To > gapTo)
                {
                    current![j] = new CommonRange(gapTo, r.To);
                    j--;
                }
                else
                {
                    var tmp = current!.ToList();
                    tmp.RemoveAt(j);
                    current = tmp.ToArray();
                    j--;
                }
                j++;
            }
        }
        return current ?? ranges;
    }

    private static CommonRange[] FindCoverChanges(CommonRange[] a, CommonRange[] b, int from, int to)
    {
        var iA = 0;
        var iB = 0;
        var inA = false;
        var inB = false;
        var pos = int.MinValue / 2;
        var result = new List<CommonRange>();

        while (true)
        {
            var nextA = iA == a.Length ? int.MaxValue / 2 : (inA ? a[iA].To : a[iA].From);
            var nextB = iB == b.Length ? int.MaxValue / 2 : (inB ? b[iB].To : b[iB].From);
            if (inA != inB)
            {
                var start = Math.Max(pos, from);
                var end = Math.Min(Math.Min(nextA, nextB), to);
                if (start < end) result.Add(new CommonRange(start, end));
            }
            pos = Math.Min(nextA, nextB);
            if (pos == int.MaxValue / 2) break;
            if (nextA == pos)
            {
                if (!inA) inA = true;
                else { inA = false; iA++; }
            }
            if (nextB == pos)
            {
                if (!inB) inB = true;
                else { inB = false; iB++; }
            }
        }
        return result.ToArray();
    }

    private static TreeFragment[] EnterFragments(ReusableMount[] mounts, CommonRange[] ranges)
    {
        var result = new List<TreeFragment>();
        foreach (var mount in mounts)
        {
            var startPos = mount.Pos + (mount.Mount.Overlay != null ? mount.Mount.Overlay[0].From : 0);
            var endPos = startPos + mount.Mount.Tree.Length;
            var from = Math.Max(mount.Frag.From, startPos);
            var to = Math.Min(mount.Frag.To, endPos);

            if (mount.Mount.Overlay != null)
            {
                var overlayRanges = mount.Mount.Overlay
                    .Select(r => new CommonRange(r.From + mount.Pos, r.To + mount.Pos)).ToArray();
                var changes = FindCoverChanges(ranges, overlayRanges, from, to);
                var pos = from;
                for (var i = 0; i <= changes.Length; i++)
                {
                    var last = i == changes.Length;
                    var end = last ? to : changes[i].From;
                    if (end > pos)
                    {
                        result.Add(new TreeFragment(pos, end, mount.Mount.Tree, -startPos,
                            mount.Frag.From >= pos || mount.Frag.OpenStart,
                            mount.Frag.To <= end || mount.Frag.OpenEnd));
                    }
                    if (last) break;
                    pos = changes[i].To;
                }
            }
            else
            {
                result.Add(new TreeFragment(from, to, mount.Mount.Tree, -startPos,
                    mount.Frag.From >= startPos || mount.Frag.OpenStart,
                    mount.Frag.To <= endPos || mount.Frag.OpenEnd));
            }
        }
        return result.ToArray();
    }

    private sealed class StructureCursor
    {
        public readonly TreeCursor Cursor;
        public bool Done;
        private readonly int _offset;

        public StructureCursor(Tree root, int offset)
        {
            _offset = offset;
            Cursor = root.Cursor(IterMode.IncludeAnonymous | IterMode.IgnoreMounts);
        }

        public void MoveTo(int pos)
        {
            var p = pos - _offset;
            while (!Done && Cursor.From < p)
            {
                if (Cursor.To >= p &&
                    Cursor.Enter(p, 1, IterMode.IgnoreOverlays | IterMode.ExcludeBuffers))
                {
                    // Entered
                }
                else if (Cursor.To <= p)
                {
                    if (!Cursor.Next(false)) Done = true;
                }
                else
                {
                    break;
                }
            }
        }

        public bool HasNode(TreeCursor nodeCursor)
        {
            MoveTo(nodeCursor.From);
            if (!Done && Cursor.From + _offset == nodeCursor.From && Cursor.Tree is { } tree)
            {
                var t = tree;
                while (true)
                {
                    if (ReferenceEquals(t, nodeCursor.Tree)) return true;
                    if (t.Children.Length > 0 && t.Positions[0] == 0 && t.Children[0] is Tree child)
                        t = child;
                    else
                        break;
                }
            }
            return false;
        }
    }

    private sealed class FragmentCursor
    {
        private TreeFragment? _curFrag;
        private int _curTo;
        private int _fragI;
        private StructureCursor? _inner;
        private readonly TreeFragment[] _fragments;

        public FragmentCursor(TreeFragment[] fragments)
        {
            _fragments = fragments;
            if (fragments.Length > 0)
            {
                var first = fragments[0];
                _curFrag = first;
                _curTo = first.Tree.Prop(StoppedInner) is int stopped ? stopped : first.To;
                _inner = new StructureCursor(first.Tree, -first.Offset);
            }
        }

        public bool HasNode(TreeCursor node)
        {
            while (_curFrag != null && node.From >= _curTo)
                NextFrag();
            if (_curFrag == null || _inner == null) return false;
            return _curFrag.From <= node.From && _curTo >= node.To && _inner.HasNode(node);
        }

        private void NextFrag()
        {
            _fragI++;
            if (_fragI == _fragments.Length)
            {
                _curFrag = null;
                _inner = null;
            }
            else
            {
                var frag = _fragments[_fragI];
                _curFrag = frag;
                _curTo = frag.Tree.Prop(StoppedInner) is int stopped2 ? stopped2 : frag.To;
                _inner = new StructureCursor(frag.Tree, -frag.Offset);
            }
        }

        public ReusableMount[] FindMounts(int pos, Parser parser)
        {
            var result = new List<ReusableMount>();
            if (_inner != null)
            {
                _inner.Cursor.MoveTo(pos, 1);
                var posNode = _inner.Cursor.Node;
                while (posNode != null)
                {
                    var mount = posNode.Tree != null ? MountedTree.Get(posNode.Tree) : null;
                    if (mount != null && mount.Parser == parser)
                    {
                        for (var i = _fragI; i < _fragments.Length; i++)
                        {
                            var frag = _fragments[i];
                            if (frag.From >= posNode.To) break;
                            if (ReferenceEquals(frag.Tree, _curFrag!.Tree))
                                result.Add(new ReusableMount(frag, mount, posNode.From - frag.Offset));
                        }
                    }
                    posNode = posNode.Parent;
                }
            }
            return result.ToArray();
        }
    }
}
