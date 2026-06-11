namespace Rezel.Common;

public interface ISyntaxNodeRef
{
    int From { get; }
    int To { get; }
    NodeType Type { get; }
    string Name { get; }
    Tree? Tree { get; }
    SyntaxNode Node { get; }
    bool MatchContext(string[] context);
}

public abstract class SyntaxNode : ISyntaxNodeRef
{
    public abstract int From { get; }
    public abstract int To { get; }
    public abstract NodeType Type { get; }
    public virtual string Name => Type.Name;
    public abstract Tree? Tree { get; }
    public abstract SyntaxNode? Parent { get; }
    public abstract SyntaxNode? FirstChild { get; }
    public abstract SyntaxNode? LastChild { get; }
    public abstract SyntaxNode? ChildAfter(int pos);
    public abstract SyntaxNode? ChildBefore(int pos);
    public abstract SyntaxNode? Enter(int pos, int side, IterMode? mode = null);
    public abstract SyntaxNode? NextSibling { get; }
    public abstract SyntaxNode? PrevSibling { get; }
    public abstract Tree ToTree();
    public abstract object? PropObj(NodePropBase prop);

    public T? Prop<T>(NodeProp<T> prop) => (T?)PropObj(prop);

    public SyntaxNode Node => this;
    public TreeCursor Cursor(IterMode mode = IterMode.None) => new(this, mode);

    public SyntaxNode Resolve(int pos, int side = 0) =>
        Helpers.ResolveNode(this, pos, side, false);

    public SyntaxNode ResolveInner(int pos, int side = 0) =>
        Helpers.ResolveNode(this, pos, side, true);

    public SyntaxNode EnterUnfinishedNodesBefore(int pos)
    {
        var scan = ChildBefore(pos);
        var node = (SyntaxNode)this;
        while (scan != null)
        {
            var last = scan.LastChild;
            if (last == null || last.To != scan.To) break;
            if (last.Type.IsError && last.From == last.To)
            {
                node = scan;
                scan = last.PrevSibling;
            }
            else
            {
                scan = last;
            }
        }
        return node;
    }

    public SyntaxNode? GetChild(object type, object? before = null, object? after = null) =>
        Helpers.GetChildren(this, type, before, after).FirstOrDefault();

    public SyntaxNode[] GetChildren(object type, object? before = null, object? after = null) =>
        Helpers.GetChildren(this, type, before, after);

    public bool MatchContext(string[] context) =>
        Helpers.MatchNodeContext(Parent, context);
}

public sealed class NodeIterator
{
    public readonly SyntaxNode Node;
    public readonly NodeIterator? Next;

    public NodeIterator(SyntaxNode node, NodeIterator? next = null)
    {
        Node = node;
        Next = next;
    }
}
