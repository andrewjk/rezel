namespace Rezel.Common;

public sealed class NodeWeakMap<T>
{
    private readonly Dictionary<object, object> _map = new();

    private void SetBuffer(TreeBuffer buffer, int index, T value)
    {
        if (!_map.TryGetValue(buffer, out var inner))
        {
            inner = new Dictionary<int, T>();
            _map[buffer] = inner;
        }
        ((Dictionary<int, T>)inner)[index] = value;
    }

    private T? GetBuffer(TreeBuffer buffer, int index)
    {
        if (_map.TryGetValue(buffer, out var inner) && inner is Dictionary<int, T> dict)
            return dict.TryGetValue(index, out var val) ? val : default;
        return default;
    }

    public void Set(SyntaxNode node, T value)
    {
        if (node is BufferNode buf)
            SetBuffer(buf.Context.Buffer, buf.Index, value);
        else if (node is TreeNode tn)
            _map[tn._tree] = value!;
    }

    public T? Get(SyntaxNode node)
    {
        if (node is BufferNode buf)
            return GetBuffer(buf.Context.Buffer, buf.Index);
        if (node is TreeNode tn)
            return _map.TryGetValue(tn._tree, out var val) ? (T?)val : default;
        return default;
    }

    public void CursorSet(TreeCursor cursor, T value)
    {
        if (cursor.Buffer != null)
            SetBuffer(cursor.Buffer.Buffer, cursor.Index, value);
        else if (cursor.Tree != null)
            _map[cursor.Tree] = value!;
    }

    public T? CursorGet(TreeCursor cursor)
    {
        if (cursor.Buffer != null)
            return GetBuffer(cursor.Buffer.Buffer, cursor.Index);
        if (cursor.Tree != null)
            return _map.TryGetValue(cursor.Tree, out var val) ? (T?)val : default;
        return default;
    }
}
