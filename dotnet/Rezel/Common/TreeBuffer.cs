namespace Rezel.Common;

public static class Constants
{
    public const int DefaultBufferLength = 1024;
}

public sealed class TreeBuffer
{
    public readonly ushort[] Buffer;
    public readonly int Length;
    public readonly NodeSet Set;

    public TreeBuffer(ushort[] buffer, int length, NodeSet set)
    {
        Buffer = buffer;
        Length = length;
        Set = set;
    }

    public NodeType Type => NodeType.None;

    public override string ToString()
    {
        var result = new List<string>();
        var index = 0;
        while (index < Buffer.Length)
        {
            result.Add(ChildString(index));
            index = Buffer[index + 3];
        }
        return string.Join(",", result);
    }

    public string ChildString(int index)
    {
        var id = Buffer[index];
        var endIndex = Buffer[index + 3];
        var type = Set.Types[id];
        var result = type.Name;
        if (ContainsNonWord(result) && !type.IsError)
            result = "\"" + result + "\"";
        var idx = index + 4;
        if (endIndex == idx) return result;
        var children = new List<string>();
        while (idx < endIndex)
        {
            children.Add(ChildString(idx));
            idx = Buffer[idx + 3];
        }
        return result + "(" + string.Join(",", children) + ")";
    }

    private static bool ContainsNonWord(string s)
    {
        foreach (var c in s)
            if (!char.IsLetterOrDigit(c) && c != '_')
                return true;
        return false;
    }

    public int FindChild(int startIndex, int endIndex, int dir, int pos, Side side)
    {
        var pick = -1;
        var i = startIndex;
        while (i != endIndex)
        {
            if (SideChecks.CheckSide(side, pos, Buffer[i + 1], Buffer[i + 2]))
            {
                pick = i;
                if (dir > 0) break;
            }
            i = Buffer[i + 3];
        }
        return pick;
    }

    public TreeBuffer Slice(int startI, int endI, int from)
    {
        var b = Buffer;
        var copy = new ushort[endI - startI];
        var len = 0;
        var i = startI;
        var j = 0;
        while (i < endI)
        {
            copy[j++] = b[i++];
            copy[j++] = (ushort)(b[i++] - from);
            var to = b[i++] - from;
            copy[j++] = (ushort)to;
            copy[j++] = (ushort)(b[i++] - startI);
            len = Math.Max(len, to);
        }
        return new TreeBuffer(copy, len, Set);
    }
}
