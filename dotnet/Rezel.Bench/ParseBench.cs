using BenchmarkDotNet.Attributes;
using Rezel.Common;
using Rezel.Grammars;
using Rezel.Lr;

namespace Rezel.Bench;

[MemoryDiagnoser]
[SimpleJob(warmupCount: 3, iterationCount: 5)]
public class ParseBench
{
    private LRParser _jsonParser = null!;
    private LRParser _jsParser = null!;

    private string _jsonSmall = null!;
    private string _jsonMedium = null!;
    private string _jsonLarge = null!;
    private string _jsSmall = null!;
    private string _jsMedium = null!;
    private string _jsLarge = null!;

    [GlobalSetup]
    public void Setup()
    {
        _jsonParser = JsonGrammar.Parser;
        _jsParser = JavaScriptGrammar.Parser;

        _jsonSmall = MakeJson(5);
        _jsonMedium = MakeJson(30);
        _jsonLarge = MakeJson(150);

        _jsSmall = MakeJs(3);
        _jsMedium = MakeJs(20);
        _jsLarge = MakeJs(80);
    }

    [Benchmark(Baseline = true)]
    public Tree ParseJsonSmall() => _jsonParser.Parse(_jsonSmall);

    [Benchmark]
    public Tree ParseJsonMedium() => _jsonParser.Parse(_jsonMedium);

    [Benchmark]
    public Tree ParseJsonLarge() => _jsonParser.Parse(_jsonLarge);

    [Benchmark]
    public Tree ParseJsSmall() => _jsParser.Parse(_jsSmall);

    [Benchmark]
    public Tree ParseJsMedium() => _jsParser.Parse(_jsMedium);

    [Benchmark]
    public Tree ParseJsLarge() => _jsParser.Parse(_jsLarge);

    private static string MakeJson(int entries)
    {
        var sb = new System.Text.StringBuilder();
        sb.Append("{\"users\":[");
        for (var i = 0; i < entries; i++)
        {
            if (i > 0) sb.Append(',');
            sb.Append("{\"id\":");
            sb.Append(i);
            sb.Append(",\"name\":\"User");
            sb.Append(i);
            sb.Append("\",\"email\":\"user");
            sb.Append(i);
            sb.Append("@example.com\",\"active\":true,\"scores\":[");
            for (var j = 0; j < 6; j++)
            {
                if (j > 0) sb.Append(',');
                sb.Append((i + 1) * (j + 1) * 7);
            }
            sb.Append("],\"address\":{\"street\":\"");
            sb.Append(i);
            sb.Append(" Main St\",\"city\":\"Springfield\",\"zip\":\"6270");
            sb.Append(i % 10);
            sb.Append("\"},\"tags\":[\"member\",\"active\",\"vip\"]}");
        }
        sb.Append("],\"meta\":{\"count\":");
        sb.Append(entries);
        sb.Append(",\"updated\":1700000000000}");
        sb.Append('}');
        return sb.ToString();
    }

    private static string MakeJs(int funcs)
    {
        var sb = new System.Text.StringBuilder();
        sb.Append("const items = [];\n");
        sb.Append("let total = 0;\n");
        for (var i = 0; i < funcs; i++)
        {
            sb.Append("function process");
            sb.Append(i);
            sb.Append("(value, index) {\n");
            sb.Append("  const result = value * 2 + index;\n");
            sb.Append("  if (result > 100) {\n");
            sb.Append("    return result;\n");
            sb.Append("  } else {\n");
            sb.Append("    for (let j = 0; j < index; j++) {\n");
            sb.Append("      total += items[j] ?? 0;\n");
            sb.Append("    }\n");
            sb.Append("    return total;\n");
            sb.Append("  }\n");
            sb.Append("}\n");
            sb.Append("class Handler");
            sb.Append(i);
            sb.Append(" {\n");
            sb.Append("  constructor(name) { this.name = name; this.count = ");
            sb.Append(i);
            sb.Append("; }\n");
            sb.Append("  run(input) { return process");
            sb.Append(i);
            sb.Append("(input, this.count); }\n");
            sb.Append("}\n");
        }
        sb.Append("export { total, items };\n");
        return sb.ToString();
    }
}
