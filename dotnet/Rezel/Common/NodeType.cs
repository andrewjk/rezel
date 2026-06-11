namespace Rezel.Common;

[Flags]
public enum NodeFlag
{
    None = 0,
    Top = 1,
    Skipped = 2,
    Error = 4,
    Anonymous = 8,
}

public sealed class NodeType
{
    public readonly string Name;
    public readonly Dictionary<int, object> Props;
    public readonly int Id;
    public readonly int Flags;

    public NodeType(string name, Dictionary<int, object> props, int id, int flags = 0)
    {
        Name = name;
        Props = props;
        Id = id;
        Flags = flags;
    }

    public static NodeType Define(int id, string? name = null, object[]? props = null,
        bool top = false, bool error = false, bool skipped = false)
    {
        var propDict = new Dictionary<int, object>();
        var flags = NodeFlag.None;
        if (top) flags |= NodeFlag.Top;
        if (skipped) flags |= NodeFlag.Skipped;
        if (error) flags |= NodeFlag.Error;
        if (name == null) flags |= NodeFlag.Anonymous;

        var type = new NodeType(name ?? "", propDict, id, (int)flags);

        if (props != null)
        {
            foreach (var src in props)
            {
                if (src is NodePropSource source)
                {
                    var add = source(type);
                    if (add is { } addVal)
                    {
                        if (addVal.Item1.PerNode)
                            throw new InvalidOperationException("Can't store a per-node prop on a node type");
                        propDict[addVal.Item1.Id] = addVal.Item2;
                    }
                }
            }
        }

        return type;
    }

    public object? PropObj(NodePropBase prop) => Props.TryGetValue(prop.Id, out var value) ? value : null;

    public T? Prop<T>(NodeProp<T> prop) => (T?)PropObj(prop);

    public bool IsTop => (Flags & (int)NodeFlag.Top) > 0;
    public bool IsSkipped => (Flags & (int)NodeFlag.Skipped) > 0;
    public bool IsError => (Flags & (int)NodeFlag.Error) > 0;
    public bool IsAnonymous => (Flags & (int)NodeFlag.Anonymous) > 0;

    public bool Is(string name)
    {
        if (Name == name) return true;
        var group = Prop(NodeProps.Group);
        return group != null && Array.IndexOf(group, name) > -1;
    }

    public bool Is(int id) => Id == id;

    public bool Is(object nameOrId)
    {
        if (nameOrId is string s) return Is(s);
        if (nameOrId is int i) return Is(i);
        return false;
    }

    public static readonly NodeType None = new("", new Dictionary<int, object>(), 0, (int)NodeFlag.Anonymous);

    public static Func<NodeType, T?> Match<T>(Dictionary<string, T> map)
    {
        var direct = new Dictionary<string, T>();
        foreach (var (prop, value) in map)
        {
            foreach (var name in prop.Split(' '))
            {
                direct[name] = value;
            }
        }

        return node =>
        {
            if (direct.TryGetValue(node.Name, out var found)) return found;
            var groups = node.Prop(NodeProps.Group);
            if (groups != null)
            {
                foreach (var group in groups)
                {
                    if (direct.TryGetValue(group, out var g)) return g;
                }
            }
            return default;
        };
    }
}
