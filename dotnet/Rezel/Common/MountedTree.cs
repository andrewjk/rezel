namespace Rezel.Common;

public sealed class MountedTree
{
    public readonly Tree Tree;
    public readonly CommonRange[]? Overlay;
    public readonly Parser Parser;
    public readonly bool Bracketed;

    public MountedTree(Tree tree, CommonRange[]? overlay, Parser parser, bool bracketed = false)
    {
        Tree = tree;
        Overlay = overlay;
        Parser = parser;
        Bracketed = bracketed;
    }

    public static MountedTree? Get(Tree? tree)
    {
        if (tree == null || tree.Props == null) return null;
        return tree.Props.GetValueOrDefault(NodeProps.Mounted.Id) as MountedTree;
    }
}
