namespace Rezel.Common;

public sealed class TreeNode : SyntaxNode
{
    internal readonly Tree _tree;
    public override int From { get; }
    public readonly int Index;
    internal readonly TreeNode? ParentRef;

    public TreeNode(Tree tree, int from, int index, TreeNode? parent)
    {
        _tree = tree;
        From = from;
        Index = index;
        ParentRef = parent;
    }

    public override NodeType Type => _tree.Type;
    public override string Name => _tree.Type.Name;
    public override int To => From + _tree.Length;
    public override Tree? Tree => _tree;

    internal SyntaxNode? NextChild(int i, int dir, int pos, Side side, IterMode mode = IterMode.None)
    {
        var parent = this;
        while (true)
        {
            var children = parent._tree.Children;
            var positions = parent._tree.Positions;
            var e = dir > 0 ? children.Length : -1;
            while (i != e)
            {
                var next = children[i];
                var start = positions[i] + parent.From;
                var nextLen = next is Tree t ? t.Length : ((TreeBuffer)next).Length;

                if (mode.HasFlag(IterMode.EnterBracketed) &&
                    next is Tree treeNext &&
                    MountedTree.Get(treeNext) is { } mounted &&
                    mounted.Overlay == null &&
                    mounted.Bracketed &&
                    pos >= start &&
                    pos <= start + treeNext.Length)
                {
                    // Enter bracketed
                }
                else if (!SideChecks.CheckSide(side, pos, start, start + nextLen))
                {
                    i += dir;
                    continue;
                }

                if (next is TreeBuffer buf)
                {
                    if (mode.HasFlag(IterMode.ExcludeBuffers)) { i += dir; continue; }
                    var idx = buf.FindChild(0, buf.Buffer.Length, dir, pos - start, side);
                    if (idx > -1)
                    {
                        var ctx = new BufferContext(parent, buf, i, start);
                        return new BufferNode(ctx, null, idx);
                    }
                }
                else if (next is Tree treeNext2)
                {
                    if (!mode.HasFlag(IterMode.IncludeAnonymous) &&
                        treeNext2.Type.IsAnonymous && !Helpers.HasChild(treeNext2))
                    {
                        i += dir;
                        continue;
                    }
                    if (!mode.HasFlag(IterMode.IgnoreMounts) &&
                        MountedTree.Get(treeNext2) is { } m && m.Overlay == null)
                        return new TreeNode(m.Tree, start, i, parent);
                    var inner = new TreeNode(treeNext2, start, i, parent);
                    if (mode.HasFlag(IterMode.IncludeAnonymous) || !inner.Type.IsAnonymous)
                        return inner;
                    return inner.NextChild(dir < 0 ? treeNext2.Children.Length - 1 : 0, dir, pos, side, mode);
                }

                i += dir;
            }

            if (mode.HasFlag(IterMode.IncludeAnonymous) || !parent.Type.IsAnonymous) return null;
            if (parent.Index >= 0)
                i = parent.Index + dir;
            else
                i = dir < 0 ? -1 : parent.ParentRef!._tree.Children.Length;
            if (parent.ParentRef == null) return null;
            parent = parent.ParentRef;
        }
    }

    public override SyntaxNode? FirstChild => NextChild(0, 1, 0, Side.DontCare);
    public override SyntaxNode? LastChild => NextChild(_tree.Children.Length - 1, -1, 0, Side.DontCare);
    public override SyntaxNode? ChildAfter(int pos) => NextChild(0, 1, pos, Side.After);
    public override SyntaxNode? ChildBefore(int pos) => NextChild(_tree.Children.Length - 1, -1, pos, Side.Before);

    public override object? PropObj(NodePropBase prop) => _tree.PropObj(prop);

    public override SyntaxNode? Enter(int pos, int side, IterMode? mode = null)
    {
        mode ??= IterMode.None;
        if (!mode.Value.HasFlag(IterMode.IgnoreOverlays) &&
            MountedTree.Get(_tree) is { } mounted && mounted.Overlay != null)
        {
            var rPos = pos - From;
            var enterBracketed = mode.Value.HasFlag(IterMode.EnterBracketed) && mounted.Bracketed;
            foreach (var range in mounted.Overlay)
            {
                var ok1 = side > 0 || enterBracketed ? range.From <= rPos : range.From < rPos;
                var ok2 = side < 0 || enterBracketed ? range.To >= rPos : range.To > rPos;
                if (ok1 && ok2)
                    return new TreeNode(mounted.Tree, mounted.Overlay[0].From + From, -1, this);
            }
        }
        return NextChild(0, 1, pos, (Side)side, mode.Value);
    }

    internal TreeNode NextSignificantParent()
    {
        var val = this;
        while (val.Type.IsAnonymous && val.ParentRef != null)
            val = val.ParentRef;
        return val;
    }

    public override SyntaxNode? Parent =>
        ParentRef?.ParentRef != null ? ParentRef.NextSignificantParent() : ParentRef;

    public override SyntaxNode? NextSibling =>
        ParentRef != null && Index >= 0
            ? ParentRef.NextChild(Index + 1, 1, 0, Side.DontCare)
            : null;

    public override SyntaxNode? PrevSibling =>
        ParentRef != null && Index >= 0
            ? ParentRef.NextChild(Index - 1, -1, 0, Side.DontCare)
            : null;

    public override Tree ToTree() => _tree;
}
