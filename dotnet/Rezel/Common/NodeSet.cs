namespace Rezel.Common;

public sealed class NodeSet
{
    public readonly NodeType[] Types;

    public NodeSet(NodeType[] types)
    {
        Types = types;
        for (var i = 0; i < types.Length; i++)
        {
            if (types[i].Id != i)
                throw new InvalidOperationException(
                    "Node type ids should correspond to array positions when creating a node set");
        }
    }

    public NodeSet Extend(params NodePropSource[] props)
    {
        var newTypes = new NodeType[Types.Length];
        for (var ti = 0; ti < Types.Length; ti++)
        {
            var type = Types[ti];
            Dictionary<int, object>? newProps = null;
            foreach (var source in props)
            {
                var add = source(type);
                if (add is { } addVal)
                {
                    newProps ??= new Dictionary<int, object>(type.Props);
                    var value = addVal.Item2;
                    var prop = addVal.Item1;
                    if (prop.Combine != null && newProps.TryGetValue(prop.Id, out var existing))
                        value = prop.Combine(existing, value);
                    newProps[prop.Id] = value;
                }
            }

            newTypes[ti] = newProps != null
                ? new NodeType(type.Name, newProps, type.Id, type.Flags)
                : type;
        }

        return new NodeSet(newTypes);
    }
}
