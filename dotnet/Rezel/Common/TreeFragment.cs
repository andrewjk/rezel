namespace Rezel.Common;

public readonly struct ChangedRange
{
    public readonly int FromA;
    public readonly int ToA;
    public readonly int FromB;
    public readonly int ToB;

    public ChangedRange(int fromA, int toA, int fromB, int toB)
    {
        FromA = fromA;
        ToA = toA;
        FromB = fromB;
        ToB = toB;
    }
}

public sealed class TreeFragment
{
    private readonly int _open;

    public readonly int From;
    public readonly int To;
    public readonly Tree Tree;
    public readonly int Offset;

    public TreeFragment(int from, int to, Tree tree, int offset,
        bool openStart = false, bool openEnd = false)
    {
        From = from;
        To = to;
        Tree = tree;
        Offset = offset;
        _open = (openStart ? 1 : 0) | (openEnd ? 2 : 0);
    }

    public bool OpenStart => (_open & 1) > 0;
    public bool OpenEnd => (_open & 2) > 0;

    public static TreeFragment[] AddTree(Tree tree, TreeFragment[]? fragments = null, bool partial = false)
    {
        fragments ??= [];
        var result = new List<TreeFragment>
        {
            new(0, tree.Length, tree, 0, false, partial)
        };
        foreach (var f in fragments)
            if (f.To > tree.Length)
                result.Add(f);
        return result.ToArray();
    }

    public static TreeFragment[] ApplyChanges(TreeFragment[] fragments, ChangedRange[] changes, int minGap = 128)
    {
        if (changes.Length == 0) return fragments;
        var result = new List<TreeFragment>();
        var fI = 1;
        var nextF = fragments.Length > 0 ? fragments[0] : null;
        var pos = 0;
        var off = 0;

        for (var cI = 0; ; cI++)
        {
            var nextC = cI < changes.Length ? changes[cI] : (ChangedRange?)null;
            var nextPos = nextC != null ? nextC.Value.FromA : int.MaxValue;
            if (nextPos - pos >= minGap)
            {
                while (nextF != null && nextF.From < nextPos)
                {
                    TreeFragment? cut = nextF;
                    if (pos >= cut.From || nextPos <= cut.To || off != 0)
                    {
                        var fFrom = Math.Max(cut.From, pos) - off;
                        var fTo = Math.Min(cut.To, nextPos) - off;
                        cut = fFrom >= fTo
                            ? null
                            : new TreeFragment(fFrom, fTo, cut.Tree, cut.Offset + off,
                                cI > 0, nextC != null);
                    }
                    if (cut != null) result.Add(cut);
                    if (nextF.To > nextPos) break;
                    nextF = fI < fragments.Length ? fragments[fI++] : null;
                }
            }
            if (nextC == null) break;
            pos = nextC.Value.ToA;
            off = nextC.Value.ToA - nextC.Value.ToB;
        }
        return result.ToArray();
    }
}
