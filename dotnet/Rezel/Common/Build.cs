namespace Rezel.Common;

public static class BalanceConstants
{
    public const int BranchFactor = 8;
}

public static class CutOffConstants
{
    public const int Depth = 2500;
}

public static class SpecialRecord
{
    public const int Reuse = -1;
    public const int ContextChange = -3;
    public const int LookAhead = -4;
}

public sealed class BuildData
{
    public object Buffer;
    public NodeSet NodeSet;
    public int TopID;
    public int? Start;
    public int? BufferStart;
    public int? Length;
    public int? MaxBufferLength;
    public IList<Tree>? Reused;
    public int? MinRepeatType;

    public BuildData(object buffer, NodeSet nodeSet, int topID,
        int? start = null, int? bufferStart = null, int? length = null,
        int? maxBufferLength = null, IList<Tree>? reused = null, int? minRepeatType = null)
    {
        Buffer = buffer;
        NodeSet = nodeSet;
        TopID = topID;
        Start = start;
        BufferStart = bufferStart;
        Length = length;
        MaxBufferLength = maxBufferLength;
        Reused = reused;
        MinRepeatType = minRepeatType;
    }
}

public interface IBufferCursor
{
    int Pos { get; }
    int Id { get; }
    int Start { get; }
    int End { get; }
    int Size { get; }
    void Next();
    IBufferCursor Fork();
}

public sealed class FlatBufferCursor : IBufferCursor
{
    public readonly int[] Buffer;
    public int Index;

    public FlatBufferCursor(int[] buffer, int index)
    {
        Buffer = buffer;
        Index = index;
    }

    public int Id => Buffer[Index - 4];
    public int Start => Buffer[Index - 3];
    public int End => Buffer[Index - 2];
    public int Size => Buffer[Index - 1];
    public int Pos => Index;

    public void Next() => Index -= 4;

    public IBufferCursor Fork() => new FlatBufferCursor(Buffer, Index);
}

public static class TreeBuilding
{
    public static Tree BuildTree(BuildData data)
    {
        var maxBufferLength = data.MaxBufferLength ?? Constants.DefaultBufferLength;
        var reused = (IList<Tree>)(data.Reused ?? Array.Empty<Tree>());
        var minRepeatType = data.MinRepeatType ?? data.NodeSet.Types.Length;
        var types = data.NodeSet.Types;
        var buildNodeSet = data.NodeSet;

        IBufferCursor cursor;
        if (data.Buffer is int[] arr)
            cursor = new FlatBufferCursor(arr, arr.Length);
        else if (data.Buffer is IBufferCursor bc)
            cursor = bc;
        else
            throw new ArgumentException("BuildData.Buffer must be int[] or IBufferCursor");

        var contextHash = 0;
        var lookAhead = 0;

        void TakeNode(int parentStart, int minPos,
            List<object> children, List<int> positions,
            int inRepeat, int depth)
        {
            var id = cursor.Id;
            var start = cursor.Start;
            var end = cursor.End;
            var size = cursor.Size;
            var lookAheadAtStart = lookAhead;
            var contextAtStart = contextHash;

            if (size < 0)
            {
                cursor.Next();
                if (size == SpecialRecord.Reuse)
                {
                    children.Add(reused[id]);
                    positions.Add(start - parentStart);
                    return;
                }
                if (size == SpecialRecord.ContextChange)
                {
                    contextHash = id;
                    return;
                }
                if (size == SpecialRecord.LookAhead)
                {
                    lookAhead = id;
                    return;
                }
                throw new InvalidOperationException($"Unrecognized record size: {size}");
            }

            var type = types[id];
            object node;
            int startPos;

            if (end - start <= maxBufferLength &&
                FindBufferSize(cursor.Pos - minPos, inRepeat) is { } bufInfo)
            {
                var bufferData = new ushort[bufInfo.Size - bufInfo.Skip];
                var endPos = cursor.Pos - bufInfo.Size;
                var idx = bufferData.Length;
                while (cursor.Pos > endPos)
                    idx = CopyToBuffer(bufInfo.Start, bufferData, idx);
                node = new TreeBuffer(bufferData, end - bufInfo.Start, buildNodeSet);
                startPos = bufInfo.Start - parentStart;
            }
            else
            {
                var endPos = cursor.Pos - size;
                cursor.Next();
                var localChildren = new List<object>();
                var localPositions = new List<int>();
                var localInRepeat = id >= minRepeatType ? id : -1;
                var lastGroup = 0;
                var lastEnd = end;

                while (cursor.Pos > endPos)
                {
                    if (localInRepeat >= 0 && cursor.Id == localInRepeat && cursor.Size >= 0)
                    {
                        if (cursor.End <= lastEnd - maxBufferLength)
                        {
                            MakeRepeatLeaf(localChildren, localPositions,
                                start, lastGroup, cursor.End, lastEnd,
                                localInRepeat, lookAheadAtStart, contextAtStart);
                            lastGroup = localChildren.Count;
                            lastEnd = cursor.End;
                        }
                        cursor.Next();
                    }
                    else if (depth > CutOffConstants.Depth)
                    {
                        TakeFlatNode(start, endPos, localChildren, localPositions);
                    }
                    else
                    {
                        TakeNode(start, endPos, localChildren, localPositions, localInRepeat, depth + 1);
                    }
                }

                if (localInRepeat >= 0 && lastGroup > 0 && lastGroup < localChildren.Count)
                {
                    MakeRepeatLeaf(localChildren, localPositions,
                        start, lastGroup, start, lastEnd,
                        localInRepeat, lookAheadAtStart, contextAtStart);
                }
                localChildren.Reverse();
                localPositions.Reverse();

                if (localInRepeat > -1 && lastGroup > 0)
                {
                    var make = MakeBalanced(type, contextAtStart);
                    node = Balancing.BalanceRange(
                        type, localChildren.ToArray(), localPositions.ToArray(),
                        0, localChildren.Count, 0, end - start,
                        make, make
                    );
                }
                else
                {
                    node = MakeTreeInternal(type, localChildren.ToArray(), localPositions.ToArray(),
                        end - start, lookAheadAtStart - end, contextAtStart);
                }
                startPos = start - parentStart;
            }

            children.Add(node);
            positions.Add(startPos);
        }

        void TakeFlatNode(int parentStart, int minPos,
            List<object> children, List<int> positions)
        {
            var nodes = new List<int>();
            var nodeCount = 0;
            var stopAt = -1;
            while (cursor.Pos > minPos)
            {
                var nid = cursor.Id;
                var nstart = cursor.Start;
                var nend = cursor.End;
                var nsize = cursor.Size;
                if (nsize > 4)
                {
                    cursor.Next();
                }
                else if (stopAt > -1 && nstart < stopAt)
                {
                    break;
                }
                else
                {
                    if (stopAt < 0) stopAt = nend - maxBufferLength;
                    nodes.Add(nid);
                    nodes.Add(nstart);
                    nodes.Add(nend);
                    nodeCount++;
                    cursor.Next();
                }
            }
            if (nodeCount > 0)
            {
                var buffer = new ushort[nodeCount * 4];
                var s = nodes[^2];
                var j = 0;
                for (var i = nodes.Count - 3; i >= 0; i -= 3)
                {
                    buffer[j++] = (ushort)nodes[i];
                    buffer[j++] = (ushort)(nodes[i + 1] - s);
                    buffer[j++] = (ushort)(nodes[i + 2] - s);
                    buffer[j++] = (ushort)j;
                }
                children.Add(new TreeBuffer(buffer, nodes[2] - s, data.NodeSet));
                positions.Add(s - parentStart);
            }
        }

        Func<object[], int[], int, Tree> MakeBalanced(NodeType type, int ctxHash)
        {
            return (children, pos, length) =>
            {
                var lookAheadVal = 0;
                var lastI = children.Length - 1;
                if (lastI >= 0 && children[lastI] is Tree last)
                {
                    if (lastI == 0 && last.Type == type && last.Length == length) return last;
                    if (last.PropObj(NodeProps.LookAhead) is int lookAheadProp)
                        lookAheadVal = pos[lastI] + last.Length + lookAheadProp;
                }
                return MakeTreeInternal(type, children, pos, length, lookAheadVal, ctxHash);
            };
        }

        void MakeRepeatLeaf(List<object> children, List<int> positions,
            int @base, int i, int from, int to,
            int type, int la, int ctxHash)
        {
            var localChildren = new List<object>();
            var localPositions = new List<int>();
            while (children.Count > i)
            {
                localChildren.Add(children[^1]);
                children.RemoveAt(children.Count - 1);
                localPositions.Add(positions[^1] + @base - from);
                positions.RemoveAt(positions.Count - 1);
            }
            children.Add(MakeTreeInternal(types[type], localChildren.ToArray(), localPositions.ToArray(),
                to - from, la - to, ctxHash));
            positions.Add(from - @base);
        }

        Tree MakeTreeInternal(NodeType type, object[] children, int[] positions,
            int length, int la, int ctxHash, (object, object)[]? props = null)
        {
            if (ctxHash != 0)
            {
                var pair = (NodeProps.ContextHash as object, ctxHash as object);
                props = props != null ? [pair, .. props] : [pair];
            }
            if (la > 25)
            {
                var pair = (NodeProps.LookAhead as object, la as object);
                props = props != null ? [pair, .. props] : [pair];
            }
            return new Tree(type, children, positions, length, props);
        }

        (int Size, int Start, int Skip)? FindBufferSize(int maxSize, int inRepeat)
        {
            var fork = cursor.Fork();
            var size = 0;
            var start = 0;
            var skip = 0;
            var minStart = fork.End - maxBufferLength;
            var result = (Size: 0, Start: 0, Skip: 0);
            var minPos = fork.Pos - maxSize;

            while (fork.Pos > minPos)
            {
                var nodeSize = fork.Size;
                if (fork.Id == inRepeat && nodeSize >= 0)
                {
                    result = (size, start, skip);
                    skip += 4; size += 4;
                    fork.Next();
                    continue;
                }
                var startPos = fork.Pos - nodeSize;
                if (nodeSize < 0 || startPos < minPos || fork.Start < minStart) break;
                var localSkipped = fork.Id >= minRepeatType ? 4 : 0;
                var nodeStart = fork.Start;
                fork.Next();
                while (fork.Pos > startPos)
                {
                    if (fork.Size < 0)
                    {
                        if (fork.Size == SpecialRecord.ContextChange || fork.Size == SpecialRecord.LookAhead)
                            localSkipped += 4;
                        else goto doneScan;
                    }
                    else if (fork.Id >= minRepeatType)
                    {
                        localSkipped += 4;
                    }
                    fork.Next();
                }
                start = nodeStart;
                size += nodeSize;
                skip += localSkipped;
            }
        doneScan:
            if (inRepeat < 0 || size == maxSize)
                result = (size, start, skip);
            return result.Size > 4 ? result : null;
        }

        int CopyToBuffer(int bufferStart, ushort[] buffer, int index)
        {
            var id = cursor.Id;
            var start = cursor.Start;
            var end = cursor.End;
            var size = cursor.Size;
            cursor.Next();
            if (size >= 0 && id < minRepeatType)
            {
                var idx = index;
                if (size > 4)
                {
                    var endPos = cursor.Pos - (size - 4);
                    while (cursor.Pos > endPos)
                        idx = CopyToBuffer(bufferStart, buffer, idx);
                }
                buffer[--idx] = (ushort)index;
                buffer[--idx] = (ushort)(end - bufferStart);
                buffer[--idx] = (ushort)(start - bufferStart);
                buffer[--idx] = (ushort)id;
                return idx;
            }
            if (size == SpecialRecord.ContextChange)
                contextHash = id;
            else if (size == SpecialRecord.LookAhead)
                lookAhead = id;
            return index;
        }

        var childrenList = new List<object>();
        var positionsList = new List<int>();
        while (cursor.Pos > 0)
            TakeNode(data.Start ?? 0, data.BufferStart ?? 0, childrenList, positionsList, -1, 0);

        var finalLength = data.Length ??
            (childrenList.Count > 0
                ? positionsList[0] + (childrenList[0] is Tree t ? t.Length : ((TreeBuffer)childrenList[0]).Length)
                : 0);

        childrenList.Reverse();
        positionsList.Reverse();

        return new Tree(types[data.TopID], childrenList.ToArray(), positionsList.ToArray(), finalLength);
    }
}

public static class Balancing
{
    public static Tree BalanceRange(
        NodeType balanceType,
        object[] children, int[] positions,
        int from, int to,
        int start, int length,
        Func<object[], int[], int, Tree>? mkTop,
        Func<object[], int[], int, Tree> mkTree)
    {
        var total = 0;
        for (var i = from; i < to; i++)
            total += NodeSize(balanceType, children[i]);

        var maxChild = (int)Math.Ceiling(total * 1.5 / BalanceConstants.BranchFactor);
        var localChildren = new List<object>();
        var localPositions = new List<int>();

        void Divide(object[] ch, int[] pos, int fromIdx, int toIdx, int offset)
        {
            var i = fromIdx;
            while (i < toIdx)
            {
                var groupFrom = i;
                var groupStart = pos[i];
                var groupSize = NodeSize(balanceType, ch[i]);
                i++;
                while (i < toIdx)
                {
                    var nextSize = NodeSize(balanceType, ch[i]);
                    if (groupSize + nextSize >= maxChild) break;
                    groupSize += nextSize;
                    i++;
                }
                if (i == groupFrom + 1)
                {
                    if (groupSize > maxChild && ch[groupFrom] is Tree only)
                    {
                        Divide(only.Children, only.Positions, 0, only.Children.Length, pos[groupFrom] + offset);
                        continue;
                    }
                    localChildren.Add(ch[groupFrom]);
                }
                else
                {
                    var len = pos[i - 1] + LengthOf(ch[i - 1]) - groupStart;
                    localChildren.Add(BalanceRange(
                        balanceType, ch, pos,
                        groupFrom, i, groupStart, len,
                        null, mkTree
                    ));
                }
                localPositions.Add(groupStart + offset - start);
            }
        }

        Divide(children, positions, from, to, 0);
        return (mkTop ?? mkTree)(localChildren.ToArray(), localPositions.ToArray(), length);
    }

    public static int NodeSize(NodeType balanceType, object node)
    {
        if (!balanceType.IsAnonymous || node is TreeBuffer) return 1;
        if (node is not Tree tree) return 1;
        if (tree.Type != balanceType) return 1;
        var size = 1;
        foreach (var child in tree.Children)
        {
            if (child is Tree t)
            {
                if (t.Type != balanceType) return 1;
                size += NodeSize(balanceType, t);
            }
            else
            {
                return 1;
            }
        }
        return size;
    }

    public static int LengthOf(object node) =>
        node switch
        {
            Tree t => t.Length,
            TreeBuffer b => b.Length,
            _ => 0
        };
}
