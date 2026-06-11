namespace Rezel.Lr;

public static class Action
{
    public const int ReduceFlag = 1 << 16;
    public const int ValueMask = (1 << 16) - 1;
    public const int ReduceDepthShift = 19;
    public const int RepeatFlag = 1 << 17;
    public const int GotoFlag = 1 << 17;
    public const int StayFlag = 1 << 18;
}

public static class StateFlag
{
    public const int Skipped = 1;
    public const int Accepting = 2;
}

public static class SpecializeConsts
{
    public const int Specialize = 0;
    public const int Extend = 1;
}

public static class Term
{
    public const int Err = 0;
}

public static class Seq
{
    public const int End = 0xffff;
    public const int Done = 0;
    public const int Next = 1;
    public const int Other = 2;
}

public static class ParseState
{
    public const int Flags = 0;
    public const int Actions = 1;
    public const int Skip = 2;
    public const int TokenizerMask = 3;
    public const int DefaultReduce = 4;
    public const int ForcedReduce = 5;
    public const int Size = 6;
}

public static class Encode
{
    public const int BigValCode = 126;
    public const int BigVal = 0xffff;
    public const int Start = 32;
    public const int Gap1 = 34;
    public const int Gap2 = 92;
    public const int Base = 46;
}

public static class File
{
    public const int Version = 14;
}
