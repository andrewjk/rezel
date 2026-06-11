namespace Rezel.Common;

public readonly struct CommonRange : IEquatable<CommonRange>
{
    public readonly int From;
    public readonly int To;

    public CommonRange(int from, int to)
    {
        From = from;
        To = to;
    }

    public override string ToString() => $"({From}..{To})";

    public bool Equals(CommonRange other) => From == other.From && To == other.To;

    public override bool Equals(object? obj) => obj is CommonRange other && Equals(other);

    public override int GetHashCode() => HashCode.Combine(From, To);

    public static bool operator ==(CommonRange left, CommonRange right) => left.Equals(right);

    public static bool operator !=(CommonRange left, CommonRange right) => !left.Equals(right);
}
