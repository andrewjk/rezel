namespace Rezel.Common;

public delegate (NodePropBase, object)? NodePropSource(NodeType type);

public abstract class NodePropBase
{
    private static int _nextPropID;

    public readonly int Id;
    public readonly bool PerNode;
    public readonly Func<object, object, object>? Combine;

    protected NodePropBase(bool perNode = false, Func<object, object, object>? combine = null)
    {
        Id = _nextPropID++;
        PerNode = perNode;
        Combine = combine;
    }

    public abstract object DeserializeObject(string value);
}

public sealed class NodeProp<T> : NodePropBase
{
    public readonly Func<string, T> Deserialize;

    public NodeProp(Func<string, T> deserialize, Func<T, T, T>? combine = null, bool perNode = false)
        : base(perNode, combine != null ? (a, b) => combine((T)a, (T)b) : null)
    {
        Deserialize = deserialize;
    }

    public NodeProp(bool perNode = false)
        : base(perNode)
    {
        Deserialize = _ => throw new InvalidOperationException("This node type doesn't define a deserialize function");
    }

    public override object DeserializeObject(string value) => Deserialize(value)!;

    public NodePropSource Add(Func<NodeType, T?> match)
    {
        if (PerNode) throw new InvalidOperationException("Can't add per-node props to node types");
        return type =>
        {
            var result = match(type);
            if (result == null) return null;
            return (this, result);
        };
    }

    public NodePropSource Add(Dictionary<string, T> match)
    {
        if (PerNode) throw new InvalidOperationException("Can't add per-node props to node types");
        var fn = NodeType.Match(match);
        return type =>
        {
            var result = fn(type);
            if (result == null) return null;
            return (this, result);
        };
    }
}

public static class NodeProps
{
    public static readonly NodeProp<string[]> ClosedBy = new(s => s.Split(' '));
    public static readonly NodeProp<string[]> OpenedBy = new(s => s.Split(' '));
    public static readonly NodeProp<string[]> Group = new(s => s.Split(' '));
    public static readonly NodeProp<string> Isolate = new(value =>
    {
        if (!string.IsNullOrEmpty(value) && value != "rtl" && value != "ltr" && value != "auto")
            throw new ArgumentException($"Invalid value for isolate: {value}");
        return string.IsNullOrEmpty(value) ? "auto" : value;
    });
    public static readonly NodeProp<int> ContextHash = new(perNode: true);
    public static readonly NodeProp<int> LookAhead = new(perNode: true);
    public static readonly NodeProp<MountedTree> Mounted = new(perNode: true);

    public static readonly Dictionary<string, NodePropBase> ByName = new()
    {
        ["closedBy"] = ClosedBy,
        ["openedBy"] = OpenedBy,
        ["group"] = Group,
        ["isolate"] = Isolate,
    };
}
