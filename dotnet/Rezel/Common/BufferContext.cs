namespace Rezel.Common;

public sealed class BufferContext
{
    public readonly TreeNode Parent;
    public readonly TreeBuffer Buffer;
    public readonly int Index;
    public readonly int Start;

    public BufferContext(TreeNode parent, TreeBuffer buffer, int index, int start)
    {
        Parent = parent;
        Buffer = buffer;
        Index = index;
        Start = start;
    }

    public ushort[] Data => Buffer.Buffer;
}
