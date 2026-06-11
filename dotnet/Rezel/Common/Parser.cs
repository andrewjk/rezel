namespace Rezel.Common;

public interface IInput
{
    int Length { get; }
    string Chunk(int from);
    bool LineChunks { get; }
    string Read(int from, int to);
}

internal sealed class StringInput : IInput
{
    private readonly string _string;

    public StringInput(string s) => _string = s;

    public int Length => _string.Length;
    public string Chunk(int from) => _string[from..];
    public bool LineChunks => false;
    public string Read(int from, int to) => _string[from..to];
}

public interface IPartialParse
{
    Tree? Advance();
    int ParsedPos { get; }
    void StopAt(int pos);
    int? StoppedAt { get; }
}

public delegate IPartialParse ParseWrapper(
    IPartialParse inner, IInput input, TreeFragment[] fragments, CommonRange[] ranges);

public abstract class Parser
{
    public abstract IPartialParse CreateParse(IInput input, TreeFragment[] fragments, CommonRange[] ranges);

    public IPartialParse StartParse(object input, TreeFragment[]? fragments = null, CommonRange[]? ranges = null)
    {
        fragments ??= [];
        IInput inputObj;
        if (input is string s)
            inputObj = new StringInput(s);
        else if (input is IInput inp)
            inputObj = inp;
        else
            throw new ArgumentException("Input must be string or IInput");

        CommonRange[] resolvedRanges;
        if (ranges != null)
        {
            if (ranges.Length == 0)
                resolvedRanges = [new CommonRange(0, 0)];
            else
                resolvedRanges = ranges;
        }
        else
        {
            resolvedRanges = [new CommonRange(0, inputObj.Length)];
        }

        return CreateParse(inputObj, fragments, resolvedRanges);
    }

    public Tree Parse(object input, TreeFragment[]? fragments = null, CommonRange[]? ranges = null)
    {
        var parse = StartParse(input, fragments, ranges);
        while (true)
        {
            var done = parse.Advance();
            if (done != null) return done;
        }
    }
}
