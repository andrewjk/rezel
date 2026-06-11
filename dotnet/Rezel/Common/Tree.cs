namespace Rezel.Common;

public class Tree
{
    public Dictionary<int, object>? Props;

    public readonly NodeType Type;
    public object[] Children;
    public int[] Positions;
    public readonly int Length;

    private SyntaxNode? _cachedNode;
    private SyntaxNode? _cachedInnerNode;

    public Tree(NodeType type, object[] children, int[] positions, int length,
        (object, object)[]? props = null)
    {
        Type = type;
        Children = children;
        Positions = positions;
        Length = length;
        if (props != null && props.Length > 0)
        {
            Props = new Dictionary<int, object>();
            foreach (var (prop, value) in props)
            {
                if (prop is NodePropBase np)
                    Props[np.Id] = value;
                else if (prop is int id)
                    Props[id] = value;
            }
        }
    }

    public override string ToString()
    {
        var mounted = MountedTree.Get(this);
        if (mounted != null && mounted.Overlay == null)
            return mounted.Tree.ToString()!;
        var childStr = "";
        foreach (var ch in Children)
        {
            var s = ch.ToString()!;
            if (!string.IsNullOrEmpty(s))
            {
                if (childStr.Length > 0) childStr += ",";
                childStr += s;
            }
        }
        if (string.IsNullOrEmpty(Type.Name)) return childStr;
        var name = Type.Name;
        if (ContainsNonWord(name) && !Type.IsError)
            return "\"" + name + "\"" + (childStr.Length == 0 ? "" : "(" + childStr + ")");
        return name + (childStr.Length == 0 ? "" : "(" + childStr + ")");
    }

    private static bool ContainsNonWord(string s)
    {
        foreach (var c in s)
            if (!char.IsLetterOrDigit(c) && c != '_')
                return true;
        return false;
    }

    public static readonly Tree Empty = new(NodeType.None, [], [], 0);

    public TreeCursor Cursor(IterMode mode = IterMode.None) =>
        new(TopNode, mode);

    public TreeCursor CursorAt(int pos, int side = 0, IterMode mode = IterMode.None)
    {
        var scope = _cachedNode ?? TopNode;
        var cursor = new TreeCursor(scope);
        cursor.MoveTo(pos, side);
        _cachedNode = cursor._tree;
        return cursor;
    }

    public SyntaxNode TopNode => new TreeNode(this, 0, 0, null);

    public SyntaxNode Resolve(int pos, int side = 0)
    {
        var node = Helpers.ResolveNode(_cachedNode ?? TopNode, pos, side, false);
        _cachedNode = node;
        return node;
    }

    public SyntaxNode ResolveInner(int pos, int side = 0)
    {
        var node = Helpers.ResolveNode(_cachedInnerNode ?? TopNode, pos, side, true);
        _cachedInnerNode = node;
        return node;
    }

    public NodeIterator? ResolveStack(int pos, int side = 0) =>
        Helpers.StackIterator(this, pos, side);

    public void Iterate(int from, int to, IterMode mode,
        Func<ISyntaxNodeRef, bool> enter, Action<ISyntaxNodeRef>? leave = null)
    {
        var toVal = to;
        var anon = mode.HasFlag(IterMode.IncludeAnonymous);
        var c = Cursor(mode | IterMode.IncludeAnonymous);
        while (true)
        {
            var entered = false;
            if (c.From <= toVal && c.To >= from &&
                (!anon && c.Type.IsAnonymous) || enter(c.Ref) != false)
            {
                if (c.FirstChild()) continue;
                entered = true;
            }
            while (true)
            {
                if (entered && leave != null && (anon || !c.Type.IsAnonymous))
                    leave(c.Ref);
                if (c.NextSibling()) break;
                if (!c.Parent()) return;
                entered = true;
            }
        }
    }

    public object? PropObj(NodePropBase prop)
    {
        if (!prop.PerNode)
            return Type.PropObj(prop);
        return Props != null && Props.TryGetValue(prop.Id, out var value) ? value : null;
    }

    public T? Prop<T>(NodeProp<T> prop) => (T?)PropObj(prop);

    public (object, object)[] PropValues
    {
        get
        {
            var result = new List<(object, object)>();
            if (Props != null)
            {
                foreach (var (id, value) in Props)
                    result.Add((id, value));
            }
            return result.ToArray();
        }
    }

    public Tree Balance(Func<object[], int[], int, Tree>? makeTree = null)
    {
        if (Children.Length <= BalanceConstants.BranchFactor)
            return this;
        return Balancing.BalanceRange(
            NodeType.None,
            Children, Positions,
            0, Children.Length,
            0, Length,
            (ch, pos, len) => new Tree(Type, ch, pos, len, PropValues),
            makeTree ?? ((ch, pos, len) => new Tree(NodeType.None, ch, pos, len))
        );
    }

    public static Tree Build(BuildData data) => TreeBuilding.BuildTree(data);
}
