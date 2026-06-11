namespace Rezel.Common;

public enum Side
{
    Before = -2,
    AtOrBefore = -1,
    Around = 0,
    AtOrAfter = 1,
    After = 2,
    DontCare = 4,
}

public static class SideChecks
{
    public static bool CheckSide(Side side, int pos, int from, int to)
    {
        return side switch
        {
            Side.Before => from < pos,
            Side.AtOrBefore => to >= pos && from < pos,
            Side.Around => from < pos && to > pos,
            Side.AtOrAfter => from <= pos && to > pos,
            Side.After => to > pos,
            Side.DontCare => true,
            _ => false,
        };
    }
}
