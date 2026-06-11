namespace Rezel.Common;

[Flags]
public enum IterMode
{
    None = 0,
    ExcludeBuffers = 1,
    IncludeAnonymous = 2,
    IgnoreMounts = 4,
    IgnoreOverlays = 8,
    EnterBracketed = 16,
}
