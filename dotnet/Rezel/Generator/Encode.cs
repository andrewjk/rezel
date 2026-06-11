using Enc = Rezel.Lr.Encode;

namespace Rezel.Generator;

public static class EncodeUtil
{
    private static char DigitToChar(int digit)
    {
        var ch = digit + Enc.Start;
        if (ch >= Enc.Gap1) ch++;
        if (ch >= Enc.Gap2) ch++;
        return (char)ch;
    }

    public static string EncodeValue(int value, int max = 0xffff)
    {
        if (value > max) throw new ArgumentException("Trying to encode a number that's too big: " + value);
        if (value == Enc.BigVal) return ((char)Enc.BigValCode).ToString();
        var result = "";
        var first = Enc.Base;
        for (;;)
        {
            var low = value % Enc.Base;
            var rest = value - low;
            result = DigitToChar(low + first) + result;
            if (rest == 0) break;
            value = rest / Enc.Base;
            first = 0;
        }
        return result;
    }

    public static string EncodeArray(int[] values, int max = 0xffff)
    {
        var result = "\"" + EncodeValue(values.Length, 0x7fffffff);
        for (var i = 0; i < values.Length; i++) result += EncodeValue(values[i], max);
        result += '"';
        return result;
    }

    public static string EncodeArray(ushort[] values, int max = 0xffff)
    {
        var result = "\"" + EncodeValue(values.Length, 0x7fffffff);
        for (var i = 0; i < values.Length; i++) result += EncodeValue(values[i], max);
        result += '"';
        return result;
    }

    public static string EncodeArray(uint[] values, int max = 0x7fffffff)
    {
        var result = "\"" + EncodeValue((int)values.Length, 0x7fffffff);
        for (var i = 0; i < values.Length; i++) result += EncodeValue((int)values[i], max);
        result += '"';
        return result;
    }
}
