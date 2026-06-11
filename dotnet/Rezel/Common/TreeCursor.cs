namespace Rezel.Common;

public sealed class TreeCursor : ISyntaxNodeRef
{
    public NodeType Type { get; set; }
    public int From { get; set; }
    public int To { get; set; }
    public string Name => Type.Name;

    public TreeNode _tree;
    public BufferContext? Buffer;
    private readonly Stack<int> _stack = new();
    public int Index;
    private BufferNode? _bufferNode;
    public readonly IterMode Mode;

    public TreeCursor(SyntaxNode node, IterMode mode = IterMode.None)
    {
        Mode = mode & ~IterMode.EnterBracketed;
        if (node is TreeNode treeNode)
        {
            _tree = treeNode;
            Type = treeNode.Type;
            From = treeNode.From;
            To = treeNode.To;
            Buffer = null;
        }
        else if (node is BufferNode bufNode)
        {
            _tree = bufNode.Context.Parent;
            Buffer = bufNode.Context;
            Type = bufNode.Type;
            From = bufNode.From;
            To = bufNode.To;
            Index = bufNode.Index;
            for (var n = bufNode.ParentRef; n != null; n = n.ParentRef)
                _stack.Push(n.Index);
            _bufferNode = bufNode;
        }
        else
        {
            throw new InvalidOperationException("Unknown node type");
        }
    }

    private bool YieldNode(TreeNode? node)
    {
        if (node == null) return false;
        _tree = node;
        Type = node.Type;
        From = node.From;
        To = node.To;
        return true;
    }

    private bool YieldBuf(int index, NodeType? typeOverride = null)
    {
        Index = index;
        if (Buffer == null) return false;
        var buf = Buffer;
        Type = typeOverride ?? buf.Buffer.Set.Types[buf.Data[index]];
        From = buf.Start + buf.Data[index + 1];
        To = buf.Start + buf.Data[index + 2];
        return true;
    }

    public bool Yield(SyntaxNode? node)
    {
        if (node == null) return false;
        if (node is TreeNode treeNode)
        {
            Buffer = null;
            return YieldNode(treeNode);
        }
        if (node is BufferNode bufNode)
        {
            Buffer = bufNode.Context;
            return YieldBuf(bufNode.Index, bufNode.Type);
        }
        return false;
    }

    public ISyntaxNodeRef Ref => this;

    public Tree? Tree => Buffer != null ? null : _tree._tree;

    public SyntaxNode Node
    {
        get
        {
            if (Buffer == null) return _tree;

            var cache = _bufferNode;
            BufferNode? result = null;
            var depth = 0;
            if (cache != null && cache.Context == Buffer)
            {
                var idx = Index;
                var d = _stack.Count;
                while (d >= 0)
                {
                    var c = (BufferNode?)cache;
                    while (c != null)
                    {
                        if (c.Index == idx)
                        {
                            if (idx == Index) return c;
                            result = c;
                            depth = d + 1;
                            goto endScan;
                        }
                        c = c.ParentRef;
                    }
                    d--;
                    if (d >= 0) idx = _stack.ToArray()[d];
                }
            endScan:;
            }

            var stackArr = _stack.ToArray();
            for (var i = depth; i < stackArr.Length; i++)
                result = new BufferNode(Buffer!, result, stackArr[i]);
            var bn = new BufferNode(Buffer!, result, Index);
            _bufferNode = bn;
            return bn;
        }
    }

    public bool MatchContext(string[] context)
    {
        if (Buffer == null)
            return Helpers.MatchNodeContext(Node.Parent, context);
        var buf = Buffer!;
        var types = buf.Buffer.Set.Types;
        var i = context.Length - 1;
        var d = _stack.Count - 1;
        while (i >= 0)
        {
            if (d < 0) return Helpers.MatchNodeContext(_tree, context, i);
            var t = types[buf.Data[_stack.ToArray()[d]]];
            if (!t.IsAnonymous)
            {
                if (!string.IsNullOrEmpty(context[i]) && context[i] != t.Name) return false;
                i--;
            }
            d--;
        }
        return true;
    }

    private bool EnterChild(int dir, int pos, Side side)
    {
        if (Buffer == null)
        {
            var children = _tree._tree.Children;
            return Yield(_tree.NextChild(
                dir < 0 ? children.Length - 1 : 0, dir, pos, side, Mode
            ));
        }

        var buf = Buffer!;
        var idx = buf.Buffer.FindChild(
            Index + 4,
            buf.Data[Index + 3],
            dir,
            pos - buf.Start,
            side
        );
        if (idx < 0) return false;
        _stack.Push(Index);
        return YieldBuf(idx);
    }

    public bool FirstChild() => EnterChild(1, 0, Side.DontCare);
    public bool LastChild() => EnterChild(-1, 0, Side.DontCare);
    public bool ChildAfter(int pos) => EnterChild(1, pos, Side.After);
    public bool ChildBefore(int pos) => EnterChild(-1, pos, Side.Before);

    public bool Enter(int pos, int side, IterMode? mode = null)
    {
        mode ??= Mode;
        if (Buffer == null) return Yield(_tree.Enter(pos, side, mode));
        if (mode.Value.HasFlag(IterMode.ExcludeBuffers)) return false;
        return EnterChild(1, pos, (Side)side);
    }

    public bool Parent()
    {
        if (Buffer == null)
        {
            var p = Mode.HasFlag(IterMode.IncludeAnonymous) ? _tree.ParentRef : _tree.Parent as TreeNode;
            return YieldNode(p);
        }
        if (_stack.Count > 0) return YieldBuf(_stack.Pop());
        var pp = Mode.HasFlag(IterMode.IncludeAnonymous)
            ? Buffer!.Parent
            : Buffer!.Parent.NextSignificantParent();
        Buffer = null;
        return YieldNode(pp);
    }

    private bool Sibling(int dir)
    {
        if (Buffer == null)
        {
            if (_tree.ParentRef == null) return false;
            if (_tree.Index < 0) return false;
            return Yield(_tree.ParentRef.NextChild(
                _tree.Index + dir, dir, 0, Side.DontCare, Mode
            ));
        }

        var buf = Buffer!;
        var d = _stack.Count - 1;
        if (dir < 0)
        {
            var parentStart = d < 0 ? 0 : _stack.ToArray()[d] + 4;
            if (Index != parentStart)
                return YieldBuf(buf.Buffer.FindChild(parentStart, Index, -1, 0, Side.DontCare));
        }
        else
        {
            var after = buf.Data[Index + 3];
            var parentEnd = d < 0 ? buf.Buffer.Buffer.Length : buf.Data[_stack.ToArray()[d] + 3];
            if (after < parentEnd) return YieldBuf(after);
        }

        if (d < 0)
            return Yield(buf.Parent.NextChild(buf.Index + dir, dir, 0, Side.DontCare, Mode));
        return false;
    }

    public bool NextSibling() => Sibling(1);
    public bool PrevSibling() => Sibling(-1);

    private bool AtLastNode(int dir)
    {
        int idx;
        TreeNode? parent;
        if (Buffer != null)
        {
            if (dir > 0)
            {
                if (Index < Buffer.Buffer.Buffer.Length) return false;
            }
            else
            {
                for (var i = 0; i < Index; i++)
                    if (Buffer.Buffer.Buffer[i + 3] < Index) return false;
            }
            idx = Buffer.Index;
            parent = Buffer.Parent;
        }
        else
        {
            idx = _tree.Index;
            parent = _tree.ParentRef;
        }

        while (parent != null)
        {
            if (idx > -1)
            {
                var e = dir < 0 ? -1 : parent._tree.Children.Length;
                for (var i = idx + dir; i != e; i += dir)
                {
                    var child = parent._tree.Children[i];
                    if (Mode.HasFlag(IterMode.IncludeAnonymous) ||
                        child is TreeBuffer ||
                        (child is Tree tc && (!tc.Type.IsAnonymous || Helpers.HasChild(tc))))
                        return false;
                }
            }
            idx = parent.Index;
            parent = parent.ParentRef;
        }
        return true;
    }

    private bool Move(int dir, bool enter)
    {
        if (enter && EnterChild(dir, 0, Side.DontCare)) return true;
        while (true)
        {
            if (Sibling(dir)) return true;
            if (AtLastNode(dir) || !Parent()) return false;
        }
    }

    public bool Next(bool enter = true) => Move(1, enter);
    public bool Prev(bool enter = true) => Move(-1, enter);

    public TreeCursor MoveTo(int pos, int side = 0)
    {
        while (From == To ||
               (side < 1 ? From >= pos : From > pos) ||
               (side > -1 ? To <= pos : To < pos))
        {
            if (!Parent()) break;
        }
        while (EnterChild(1, pos, (Side)side)) { }
        return this;
    }

    public void Iterate(Func<ISyntaxNodeRef, bool> enter, Action<ISyntaxNodeRef>? leave = null)
    {
        var depth = 0;
        while (true)
        {
            var mustLeave = false;
            if (Type.IsAnonymous || enter(this) != false)
            {
                if (FirstChild()) { depth++; continue; }
                if (!Type.IsAnonymous) mustLeave = true;
            }
            while (true)
            {
                if (mustLeave && leave != null) leave(this);
                mustLeave = Type.IsAnonymous;
                if (depth == 0) return;
                if (NextSibling()) break;
                Parent();
                depth--;
                mustLeave = true;
            }
        }
    }
}
