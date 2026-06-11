namespace Rezel.Common;

public static class Helpers
{
    public static SyntaxNode ResolveNode(SyntaxNode node, int pos, int side, bool overlays)
    {
        while (node.From == node.To ||
               (side < 1 ? node.From >= pos : node.From > pos) ||
               (side > -1 ? node.To <= pos : node.To < pos))
        {
            SyntaxNode? parent;
            if (!overlays && node is TreeNode tn && tn.Index < 0)
                parent = null;
            else
                parent = node.Parent;
            if (parent == null) return node;
            node = parent;
        }

        var mode = overlays ? IterMode.None : IterMode.IgnoreOverlays;

        if (overlays)
        {
            var scan = (SyntaxNode?)node;
            while (scan != null)
            {
                var parent = scan.Parent;
                if (parent == null) break;
                if (scan is TreeNode sTn && sTn.Index < 0)
                {
                    var entered = parent.Enter(pos, side, mode);
                    if (entered != null && entered.From != scan.From)
                        node = parent;
                }
                scan = parent;
            }
        }

        while (true)
        {
            var inner = node.Enter(pos, side, mode);
            if (inner == null) return node;
            node = inner;
        }
    }

    public static SyntaxNode[] GetChildren(SyntaxNode node, object type, object? before, object? after)
    {
        var cur = node.Cursor();
        var result = new List<SyntaxNode>();
        if (!cur.FirstChild()) return result.ToArray();

        if (before != null)
        {
            var found = false;
            while (!found)
            {
                found = cur.Type.Is(before);
                if (!cur.NextSibling()) return result.ToArray();
            }
        }

        while (true)
        {
            if (after != null && cur.Type.Is(after)) return result.ToArray();
            if (cur.Type.Is(type)) result.Add(cur.Node);
            if (!cur.NextSibling()) return after == null ? result.ToArray() : [];
        }
    }

    public static bool MatchNodeContext(SyntaxNode? node, string[] context, int? startAt = null)
    {
        var i = startAt ?? context.Length - 1;
        var p = node;
        while (i >= 0)
        {
            if (p == null) return false;
            if (!p.Type.IsAnonymous)
            {
                if (!string.IsNullOrEmpty(context[i]) && context[i] != p.Name) return false;
                i--;
            }
            p = p.Parent;
        }
        return true;
    }

    public static bool HasChild(Tree tree)
    {
        foreach (var ch in tree.Children)
        {
            if (ch is TreeBuffer) return true;
            if (ch is Tree t && (!t.Type.IsAnonymous || HasChild(t))) return true;
        }
        return false;
    }

    public static NodeIterator? IterStack(SyntaxNode[] heads)
    {
        if (heads.Length == 0) return null;
        var pick = 0;
        var picked = heads[0];
        for (var i = 1; i < heads.Length; i++)
        {
            var node = heads[i];
            if (node.From > picked.From || node.To < picked.To)
            {
                picked = node;
                pick = i;
            }
        }

        SyntaxNode? next;
        if (picked is TreeNode tn && tn.Index < 0)
            next = null;
        else
            next = picked.Parent;

        var newHeads = (SyntaxNode[])heads.Clone();
        if (next != null)
            newHeads[pick] = next;
        else
        {
            var tmp = new SyntaxNode[newHeads.Length - 1];
            Array.Copy(newHeads, 0, tmp, 0, pick);
            Array.Copy(newHeads, pick + 1, tmp, pick, newHeads.Length - pick - 1);
            newHeads = tmp;
        }
        return new NodeIterator(picked, IterStack(newHeads));
    }

    public static NodeIterator? StackIterator(Tree tree, int pos, int side)
    {
        var inner = tree.ResolveInner(pos, side);
        List<SyntaxNode>? layers = null;
        TreeNode? scan;
        if (inner is TreeNode innerTn)
            scan = innerTn;
        else if (inner is BufferNode innerBn)
            scan = innerBn.Context.Parent;
        else
            scan = null;

        var skipMountCheck = false;

        while (scan != null)
        {
            if (scan.Index < 0)
            {
                var parent = scan.ParentRef!;
                layers ??= [inner];
                layers.Add(parent.Resolve(pos, side));
                scan = parent;
                skipMountCheck = true;
            }
            else
            {
                if (!skipMountCheck)
                {
                    var mount = MountedTree.Get(scan._tree);
                    if (mount != null && mount.Overlay != null &&
                        mount.Overlay[0].From <= pos &&
                        mount.Overlay[mount.Overlay.Length - 1].To >= pos)
                    {
                        var root = new TreeNode(mount.Tree, mount.Overlay[0].From + scan.From, -1, scan);
                        layers ??= [inner];
                        layers.Add(ResolveNode(root, pos, side, false));
                    }
                }
                skipMountCheck = false;
                scan = scan.ParentRef;
            }
        }

        return layers != null ? IterStack(layers.ToArray()) : null;
    }
}
