namespace Rezel.Generator;

public static class Hash
{
    public static int Compute(int a, int b) => unchecked((a << 5) + a + b);

    public static int HashString(int h, string s)
    {
        for (var i = 0; i < s.Length; i++) h = Compute(h, s[i]);
        return h;
    }
}
