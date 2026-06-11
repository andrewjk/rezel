namespace Rezel.Generator;

public static class Log
{
    public static readonly string Verbose = Environment.GetEnvironmentVariable("LOG") ?? "";
    public static readonly bool Timing = Verbose.Contains("time");

    public static T Time<T>(string label, Func<T> f)
    {
        if (!Timing) return f();
        var t0 = DateTime.Now;
        var result = f();
        Console.WriteLine($"{label} ({(DateTime.Now - t0).TotalSeconds:F2}s)");
        return result;
    }
}
