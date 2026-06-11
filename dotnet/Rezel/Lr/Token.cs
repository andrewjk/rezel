using Rezel.Common;
using static Rezel.Lr.SpecializeConsts;

namespace Rezel.Lr;

public class CachedToken
{
    public int Start = -1;
    public int Value = -1;
    public int End = -1;
    public int Extended = -1;
    public int LookAhead = 0;
    public int Mask = 0;
    public int Context = 0;
}

public interface ITokenizer
{
    void Token(InputStream input, Stack stack);
    bool Contextual { get; }
    bool Fallback { get; }
    bool Extend { get; }
}

public sealed class InputStream
{
    public string Chunk = "";
    public int ChunkOff;
    public int ChunkPos;
    private string _chunk2 = "";
    private int _chunk2Pos;

    public int Next = -1;
    public CachedToken Token;
    public int Pos;
    public int End;

    private int _rangeIndex;
    private CommonRange _range;

    public readonly IInput Input;
    public readonly CommonRange[] Ranges;

    private static readonly CachedToken NullToken = new();

    public InputStream(IInput input, CommonRange[] ranges)
    {
        Input = input;
        Ranges = ranges;
        Pos = ChunkPos = ranges[0].From;
        _range = ranges[0];
        End = ranges[ranges.Length - 1].To;
        Token = NullToken;
        ReadNext();
    }

    public int? ResolveOffset(int offset, int assoc)
    {
        var range = _range;
        var index = _rangeIndex;
        var pos = Pos + offset;
        while (pos < range.From)
        {
            if (index == 0) return null;
            var next = Ranges[--index];
            pos -= range.From - next.To;
            range = next;
        }
        while (assoc < 0 ? pos > range.To : pos >= range.To)
        {
            if (index == Ranges.Length - 1) return null;
            var next = Ranges[++index];
            pos += next.From - range.To;
            range = next;
        }
        return pos;
    }

    public int ClipPos(int pos)
    {
        if (pos >= _range.From && pos < _range.To) return pos;
        foreach (var range in Ranges)
            if (range.To > pos) return Math.Max(pos, range.From);
        return End;
    }

    public int Peek(int offset)
    {
        var idx = ChunkOff + offset;
        int pos;
        int result;
        if (idx >= 0 && idx < Chunk.Length)
        {
            pos = Pos + offset;
            result = Chunk[idx];
        }
        else
        {
            var resolved = ResolveOffset(offset, 1);
            if (resolved == null) return -1;
            pos = resolved.Value;
            if (pos >= _chunk2Pos && pos < _chunk2Pos + _chunk2.Length)
            {
                result = _chunk2[pos - _chunk2Pos];
            }
            else
            {
                var i = _rangeIndex;
                var range = _range;
                while (range.To <= pos) range = Ranges[++i];
                _chunk2 = Input.Chunk(_chunk2Pos = pos);
                if (pos + _chunk2.Length > range.To)
                    _chunk2 = _chunk2[..(range.To - pos)];
                result = _chunk2.Length > 0 ? _chunk2[0] : -1;
            }
        }
        if (pos >= Token.LookAhead) Token.LookAhead = pos + 1;
        return result;
    }

    public void AcceptToken(int token, int endOffset = 0)
    {
        var end = endOffset != 0 ? ResolveOffset(endOffset, -1) : Pos;
        if (end == null || end < Token.Start)
            throw new ArgumentOutOfRangeException("Token end out of bounds");
        Token.Value = token;
        Token.End = end.Value;
    }

    public void AcceptTokenTo(int token, int endPos)
    {
        Token.Value = token;
        Token.End = endPos;
    }

    private void GetChunk()
    {
        if (Pos >= _chunk2Pos && Pos < _chunk2Pos + _chunk2.Length)
        {
            (Chunk, _chunk2) = (_chunk2, Chunk);
            (ChunkPos, _chunk2Pos) = (_chunk2Pos, ChunkPos);
            ChunkOff = Pos - ChunkPos;
        }
        else
        {
            _chunk2 = Chunk;
            _chunk2Pos = ChunkPos;
            var nextChunk = Input.Chunk(Pos);
            var end = Pos + nextChunk.Length;
            Chunk = end > _range.To ? nextChunk[..(_range.To - Pos)] : nextChunk;
            ChunkPos = Pos;
            ChunkOff = 0;
        }
    }

    private void ReadNext()
    {
        if (ChunkOff >= Chunk.Length)
        {
            GetChunk();
            if (ChunkOff == Chunk.Length) { Next = -1; return; }
        }
        Next = Chunk[ChunkOff];
    }

    public int Advance(int n = 1)
    {
        ChunkOff += n;
        while (Pos + n >= _range.To)
        {
            if (_rangeIndex == Ranges.Length - 1) return SetDone();
            n -= _range.To - Pos;
            _range = Ranges[++_rangeIndex];
            Pos = _range.From;
        }
        Pos += n;
        if (Pos >= Token.LookAhead) Token.LookAhead = Pos + 1;
        ReadNext();
        return Next;
    }

    private int SetDone()
    {
        Pos = ChunkPos = End;
        _range = Ranges[_rangeIndex = Ranges.Length - 1];
        Chunk = "";
        return Next = -1;
    }

    public InputStream Reset(int pos, CachedToken? token = null)
    {
        if (token != null)
        {
            Token = token;
            token.Start = pos;
            token.LookAhead = pos + 1;
            token.Value = token.Extended = -1;
        }
        else
        {
            Token = NullToken;
        }
        if (Pos != pos)
        {
            Pos = pos;
            if (pos == End)
            {
                SetDone();
                return this;
            }
            while (pos < _range.From) _range = Ranges[--_rangeIndex];
            while (pos >= _range.To) _range = Ranges[++_rangeIndex];
            if (pos >= ChunkPos && pos < ChunkPos + Chunk.Length)
            {
                ChunkOff = pos - ChunkPos;
            }
            else
            {
                Chunk = "";
                ChunkOff = 0;
            }
            ReadNext();
        }
        return this;
    }

    public string Read(int from, int to)
    {
        if (from >= ChunkPos && to <= ChunkPos + Chunk.Length)
            return Chunk[(from - ChunkPos)..(to - ChunkPos)];
        if (from >= _chunk2Pos && to <= _chunk2Pos + _chunk2.Length)
            return _chunk2[(from - _chunk2Pos)..(to - _chunk2Pos)];
        if (from >= _range.From && to <= _range.To) return Input.Read(from, to);
        var result = "";
        foreach (var r in Ranges)
        {
            if (r.From >= to) break;
            if (r.To > from) result += Input.Read(Math.Max(r.From, from), Math.Min(r.To, to));
        }
        return result;
    }
}

public sealed class TokenGroup : ITokenizer
{
    public bool Contextual => false;
    public bool Fallback => false;
    public bool Extend => false;

    public readonly ushort[] Data;
    public readonly int Id;

    public TokenGroup(ushort[] data, int id)
    {
        Data = data;
        Id = id;
    }

    public void Token(InputStream input, Stack stack)
    {
        TokenReader.ReadToken(Data, input, stack, Id, stack.P.Parser.Data, stack.P.Parser.TokenPrecTable);
    }
}

public sealed class LocalTokenGroup : ITokenizer
{
    public bool Contextual => false;
    public bool Fallback => false;
    public bool Extend => false;

    public readonly ushort[] Data;
    public readonly int PrecTable;
    public readonly int? ElseToken;

    public LocalTokenGroup(object data, int precTable, int? elseToken = null)
    {
        PrecTable = precTable;
        ElseToken = elseToken;
        Data = data is string s ? Decode.DecodeArray(s) : (ushort[])data;
    }

    public void Token(InputStream input, Stack stack)
    {
        var start = input.Pos;
        var skipped = 0;
        for (; ; )
        {
            var atEof = input.Next < 0;
            var nextPos = input.ResolveOffset(1, 1);
            TokenReader.ReadToken(Data, input, stack, 0, Data, PrecTable);
            if (input.Token.Value > -1) break;
            if (ElseToken == null) return;
            if (!atEof) skipped++;
            if (nextPos == null) break;
            input.Reset(nextPos.Value, input.Token);
        }
        if (skipped > 0)
        {
            input.Reset(start, input.Token);
            input.AcceptToken(ElseToken!.Value, skipped);
        }
    }
}

public sealed class ExternalTokenizer : ITokenizer
{
    public bool Contextual { get; }
    public bool Fallback { get; }
    public bool Extend { get; }

    public readonly Action<InputStream, Stack> TokenFn;

    public ExternalTokenizer(Action<InputStream, Stack> token, bool contextual = false,
        bool fallback = false, bool extend = false)
    {
        TokenFn = token;
        Contextual = contextual;
        Fallback = fallback;
        Extend = extend;
    }

    public void Token(InputStream input, Stack stack) => TokenFn(input, stack);
}

public static class TokenReader
{
    public static void ReadToken(ushort[] data, InputStream input, Stack stack,
        int group, ushort[] precTable, int precOffset)
    {
        var state = 0;
        var groupMask = 1 << group;
        var dialect = stack.P.Parser.Dialect;

        while (true)
        {
            if ((groupMask & data[state]) == 0) break;
            var accEnd = data[state + 1];

            for (var i = state + 3; i < accEnd; i += 2)
            {
                if ((data[i + 1] & groupMask) > 0)
                {
                    var term = data[i];
                    if (dialect.Allows(term) &&
                        (input.Token.Value == -1 ||
                         input.Token.Value == term ||
                         Overrides(term, input.Token.Value, precTable, precOffset)))
                    {
                        input.AcceptToken(term);
                        break;
                    }
                }
            }

            var next = input.Next;
            int low = 0;
            int high = data[state + 2];

            if (input.Next < 0 && high > low && data[accEnd + high * 3 - 3] == Seq.End)
            {
                state = data[accEnd + high * 3 - 1];
                continue;
            }

            while (low < high)
            {
                var mid = (low + high) >> 1;
                var index = accEnd + mid + (mid << 1);
                var from = data[index];
                var to = data[index + 1] != 0 ? data[index + 1] : 0x10000;
                if (next < from) high = mid;
                else if (next >= to) low = mid + 1;
                else
                {
                    state = data[index + 2];
                    input.Advance();
                    goto continueScan;
                }
            }
            break;
        continueScan:;
        }
    }

    private static int FindOffset(ushort[] data, int start, int term)
    {
        for (var i = start; ; i++)
        {
            var next = data[i];
            if (next == Seq.End) return -1;
            if (next == term) return i - start;
        }
    }

    private static bool Overrides(int token, int prev, ushort[] tableData, int tableOffset)
    {
        var iPrev = FindOffset(tableData, tableOffset, prev);
        return iPrev < 0 || FindOffset(tableData, tableOffset, token) < iPrev;
    }
}
