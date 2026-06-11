namespace Rezel.Common;

public sealed class BufferNode : SyntaxNode
{
    public override NodeType Type { get; }
    public override string Name => Type.Name;

    public override int From => Context.Start + Context.Buffer.Buffer[Index + 1];
    public override int To => Context.Start + Context.Buffer.Buffer[Index + 2];

    public readonly BufferContext Context;
    internal readonly BufferNode? ParentRef;
    public readonly int Index;

    public BufferNode(BufferContext context, BufferNode? parent, int index)
    {
        Context = context;
        ParentRef = parent;
        Index = index;
        Type = context.Buffer.Set.Types[context.Buffer.Buffer[index]];
    }

    private BufferNode? Child(int dir, int pos, Side side)
    {
        var buffer = Context.Buffer;
        var idx = buffer.FindChild(
            Index + 4,
            buffer.Buffer[Index + 3],
            dir,
            pos - Context.Start,
            side
        );
        return idx < 0 ? null : new BufferNode(Context, this, idx);
    }

    public override SyntaxNode? FirstChild => Child(1, 0, Side.DontCare);
    public override SyntaxNode? LastChild => Child(-1, 0, Side.DontCare);
    public override SyntaxNode? ChildAfter(int pos) => Child(1, pos, Side.After);
    public override SyntaxNode? ChildBefore(int pos) => Child(-1, pos, Side.Before);

    public override object? PropObj(NodePropBase prop) => Type.PropObj(prop);

    public override SyntaxNode? Enter(int pos, int side, IterMode? mode = null)
    {
        mode ??= IterMode.None;
        if (mode.Value.HasFlag(IterMode.ExcludeBuffers)) return null;
        var buffer = Context.Buffer;
        var idx = buffer.FindChild(
            Index + 4,
            buffer.Buffer[Index + 3],
            side > 0 ? 1 : -1,
            pos - Context.Start,
            (Side)side
        );
        return idx < 0 ? null : new BufferNode(Context, this, idx);
    }

    public override SyntaxNode? Parent =>
        (SyntaxNode?)ParentRef ?? Context.Parent.NextSignificantParent();

    private SyntaxNode? ExternalSibling(int dir) =>
        ParentRef != null
            ? null
            : Context.Parent.NextChild(Context.Index + dir, dir, 0, Side.DontCare);

    public override SyntaxNode? NextSibling
    {
        get
        {
            var buffer = Context.Buffer;
            var after = buffer.Buffer[Index + 3];
            var parentEnd = ParentRef != null ? buffer.Buffer[ParentRef.Index + 3] : buffer.Buffer.Length;
            if (after < parentEnd)
                return new BufferNode(Context, ParentRef, after);
            return ExternalSibling(1);
        }
    }

    public override SyntaxNode? PrevSibling
    {
        get
        {
            var buffer = Context.Buffer;
            var parentStart = ParentRef != null ? ParentRef.Index + 4 : 0;
            if (Index == parentStart) return ExternalSibling(-1);
            var idx = buffer.FindChild(parentStart, Index, -1, 0, Side.DontCare);
            return new BufferNode(Context, ParentRef, idx);
        }
    }

    public override Tree? Tree => null;

    public override Tree ToTree()
    {
        var children = new List<object>();
        var positions = new List<int>();
        var buffer = Context.Buffer;
        var startI = Index + 4;
        var endI = buffer.Buffer[Index + 3];
        if (endI > startI)
        {
            var from = buffer.Buffer[Index + 1];
            children.Add(buffer.Slice(startI, endI, from));
            positions.Add(0);
        }
        return new Tree(Type, children.ToArray(), positions.ToArray(), To - From);
    }
}
