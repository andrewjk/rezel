using Rezel.Common;

namespace Rezel.Lr;

public static class Decode
{
    public static ushort[] DecodeArray(object input)
    {
        if (input is ushort[] arr) return arr;
        if (input is not string s) throw new ArgumentException("Input must be string or ushort[]");

        ushort[]? array = null;
        var pos = 0;
        var @out = 0;

        while (pos < s.Length)
        {
            var value = 0;
            while (true)
            {
                if (pos >= s.Length) break;
                var next = s[pos++];
                if (next == Encode.BigValCode)
                {
                    value = Encode.BigVal;
                    break;
                }
                if (next >= Encode.Gap2) next--;
                if (next >= Encode.Gap1) next--;
                var digit = next - Encode.Start;
                if (digit >= Encode.Base)
                {
                    digit -= Encode.Base;
                    value += digit;
                    break;
                }
                value += digit;
                value *= Encode.Base;
            }
            if (array != null)
                array[@out++] = (ushort)value;
            else
                array = new ushort[value];
        }

        return array!;
    }

    public static uint[] DecodeArray32(object input)
    {
        if (input is uint[] arr) return arr;
        if (input is not string s) throw new ArgumentException("Input must be string or uint[]");

        uint[]? array = null;
        var pos = 0;
        var @out = 0;

        while (pos < s.Length)
        {
            var value = 0;
            while (true)
            {
                if (pos >= s.Length) break;
                var next = s[pos++];
                if (next == Encode.BigValCode)
                {
                    value = Encode.BigVal;
                    break;
                }
                if (next >= Encode.Gap2) next--;
                if (next >= Encode.Gap1) next--;
                var digit = next - Encode.Start;
                if (digit >= Encode.Base)
                {
                    digit -= Encode.Base;
                    value += digit;
                    break;
                }
                value += digit;
                value *= Encode.Base;
            }
            if (array != null)
                array[@out++] = (uint)value;
            else
                array = new uint[value];
        }

        return array!;
    }
}
