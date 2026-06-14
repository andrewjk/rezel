using System.Text.Json;
using Rezel.Generator;
using LrFile = Rezel.Lr.File;

var cmdArgs = Environment.GetCommandLineArgs();
if (cmdArgs.Length < 4)
{
    Console.Error.WriteLine("Usage: RezelCodeGen <grammar-file> <config-file> <output-file>");
    return 1;
}

var grammarPath = cmdArgs[1];
var configPath = cmdArgs[2];
var outputPath = cmdArgs[3];

var grammarText = File.ReadAllText(grammarPath);
var configJson = File.ReadAllText(configPath);
var config = JsonSerializer.Deserialize<JsonElement>(configJson);

var outputVarName = config.GetProperty("outputVarName").GetString()!;

var serialized = BuildExt.BuildSerializedParser(grammarText);

var code = GenerateCSharp(outputVarName, serialized);
File.WriteAllText(outputPath, code);
Console.WriteLine($"Generated {outputPath}");
return 0;

static string EscapeString(string s)
{
    return s.Replace("\\", "\\\\")
            .Replace("\"", "\\\"")
            .Replace("\n", "\\n")
            .Replace("\r", "\\r")
            .Replace("\t", "\\t");
}

static string LiteralStringArray(string[] arr)
{
    var items = arr.Select(s => $"\"{EscapeString(s)}\"").ToArray();
    return $"new[] {{ {string.Join(", ", items)} }}";
}

static string LiteralIntIntDict(Dictionary<int, int> dict)
{
    var items = dict.Select(kvp => $"[{kvp.Key}] = {kvp.Value}").ToArray();
    return $"new Dictionary<int, int> {{ {string.Join(", ", items)} }}";
}

static string LiteralStringIntDict(Dictionary<string, int> dict)
{
    var items = dict.Select(kvp => $"[\"{EscapeString(kvp.Key)}\"] = {kvp.Value}").ToArray();
    return $"new Dictionary<string, int> {{ {string.Join(", ", items)} }}";
}

static string LiteralStringIntArrayDict(Dictionary<string, int[]> dict)
{
    var items = dict.Select(kvp =>
    {
        var val = $"new[] {{ {string.Join(", ", kvp.Value)} }}";
        return $"[\"{EscapeString(kvp.Key)}\"] = {val}";
    }).ToArray();
    return $"new Dictionary<string, int[]> {{ {string.Join(", ", items)} }}";
}

static string LiteralIntStringDict(Dictionary<int, string> dict)
{
    var items = dict.Select(kvp => $"[{kvp.Key}] = \"{EscapeString(kvp.Value)}\"").ToArray();
    return $"new Dictionary<int, string> {{ {string.Join(", ", items)} }}";
}

static string LiteralAnyArray(object[] arr)
{
    var items = arr.Select(item => item switch
    {
        int i => i.ToString(),
        string s => $"\"{EscapeString(s)}\"",
        null => "null",
        _ => item?.ToString() ?? "null"
    }).ToArray();
    return $"new object[] {{ {string.Join(", ", items)} }}";
}

static string GenerateCSharp(string varName, SerializedParser serialized)
{
    var lines = new List<string>();
    lines.Add("using Rezel.Common;");
    lines.Add("using Rezel.Lr;");
    lines.Add("");
    lines.Add("namespace Rezel.Grammars;");
    lines.Add("");
    lines.Add($"public static class {varName}Data");
    lines.Add("{");

    lines.Add($"    public const int Version = {LrFile.Version};");
    lines.Add("");
    lines.Add($"    public const string States = \"{EscapeString(serialized.States)}\";");
    lines.Add("");
    lines.Add($"    public const string StateData = \"{EscapeString(serialized.StateData)}\";");
    lines.Add("");
    lines.Add($"    public const string Goto = \"{EscapeString(serialized.Goto)}\";");
    lines.Add("");
    lines.Add($"    public const string NodeNames = \"{EscapeString(serialized.NodeNames)}\";");
    lines.Add("");
    lines.Add($"    public const int MaxTerm = {serialized.MaxTerm};");
    lines.Add($"    public const int RepeatNodeCount = {serialized.RepeatNodeCount};");

    if (serialized.NodePropNames != null && serialized.NodePropData != null)
    {
        lines.Add("");
        lines.Add($"    public static readonly string[] NodePropNames = {LiteralStringArray(serialized.NodePropNames)};");
        lines.Add("");
        lines.Add("    public static NodePropSpec[]? BuildNodeProps()");
        lines.Add("    {");
        lines.Add("        var nodeProps = NodeProps.ByName;");
        lines.Add("        var result = new List<NodePropSpec>();");
        lines.Add("");
        for (var i = 0; i < serialized.NodePropNames.Length; i++)
        {
            var propName = serialized.NodePropNames[i];
            var propData = serialized.NodePropData[i];
            lines.Add($"        if (nodeProps.TryGetValue(\"{EscapeString(propName)}\", out var {propName}Prop))");
            lines.Add("        {");
            lines.Add($"            result.Add(new NodePropSpec({propName}Prop, {LiteralAnyArray(propData)}));");
            lines.Add("        }");
        }
        lines.Add("        return result.Count > 0 ? result.ToArray() : null;");
        lines.Add("    }");
    }

    if (serialized.SkippedNodes != null)
    {
        lines.Add("");
        lines.Add($"    public static readonly int[] SkippedNodes = [{string.Join(", ", serialized.SkippedNodes)}];");
    }

    lines.Add("");
    lines.Add($"    public const string TokenData = \"{EscapeString(serialized.TokenData)}\";");
    lines.Add("");
    lines.Add($"    public const int TokenPrec = {serialized.TokenPrec};");

    if (serialized.Dialects != null)
    {
        lines.Add("");
        lines.Add($"    public static readonly Dictionary<string, int> Dialects = {LiteralStringIntDict(serialized.Dialects)};");
    }

    if (serialized.DynamicPrecedences != null)
    {
        lines.Add("");
        lines.Add($"    public static readonly Dictionary<int, int> DynamicPrecedences = {LiteralIntIntDict(serialized.DynamicPrecedences)};");
    }

    lines.Add("");
    lines.Add($"    public static readonly Dictionary<string, int[]> TopRules = {LiteralStringIntArrayDict(serialized.TopRules)};");

    if (serialized.TermNames != null)
    {
        lines.Add("");
        lines.Add($"    public static readonly Dictionary<int, string> TermNames = {LiteralIntStringDict(serialized.TermNames)};");
    }

    if (serialized.TermTable != null)
    {
        lines.Add("");
        lines.Add($"    public static readonly Dictionary<string, int> TermTable = {LiteralStringIntDict(serialized.TermTable)};");
    }

    lines.Add("");

    if (serialized.SpecializedEntries.Count > 0)
    {
        foreach (var entry in serialized.SpecializedEntries)
        {
            if (entry is SpecializedEntry.Table tbl)
            {
                var tableStr = LiteralStringIntDict(tbl.Lookup);
                lines.Add($"    private static readonly Dictionary<string, int> _specializer_{tbl.Term} = {tableStr};");
                lines.Add($"    private static readonly Dictionary<string, int>.AlternateLookup<ReadOnlySpan<char>> _specializer_{tbl.Term}_lookup = _specializer_{tbl.Term}.GetAlternateLookup<ReadOnlySpan<char>>();");
            }
        }
        lines.Add("");
    }

    lines.Add("    public static LRParserSpec MakeSpec(");
    lines.Add("        Dictionary<string, ITokenizer>? externals = null,");
    lines.Add("        NodePropSource[]? propSources = null,");
    lines.Add("        ContextTracker? context = null)");
    lines.Add("    {");

    lines.Add("        var tokenizers = new List<object>();");
    foreach (var entry in serialized.TokenizerEntries)
    {
        switch (entry)
        {
            case TokenizerEntry.TokenGroup tg:
                lines.Add($"        tokenizers.Add({tg.ID});");
                break;
            case TokenizerEntry.LocalTokenGroup ltg:
                if (ltg.ElseToken.HasValue)
                    lines.Add($"        tokenizers.Add(new LocalTokenGroup(\"{EscapeString(ltg.Data)}\", {ltg.PrecTable}, {ltg.ElseToken.Value}));");
                else
                    lines.Add($"        tokenizers.Add(new LocalTokenGroup(\"{EscapeString(ltg.Data)}\", {ltg.PrecTable}));");
                break;
            case TokenizerEntry.External ext:
                lines.Add($"        tokenizers.Add(externals?[\"{EscapeString(ext.Name)}\"]!);");
                break;
        }
    }

    lines.Add("");
    lines.Add("        return new LRParserSpec");
    lines.Add("        {");
    lines.Add("            Version = Version,");
    lines.Add("            States = States,");
    lines.Add("            StateData = StateData,");
    lines.Add("            Goto = Goto,");
    lines.Add("            NodeNames = NodeNames,");
    lines.Add("            MaxTerm = MaxTerm,");
    lines.Add("            RepeatNodeCount = RepeatNodeCount,");

    if (serialized.NodePropNames != null)
        lines.Add("            NodeProps = BuildNodeProps(),");

    lines.Add("            PropSources = propSources,");

    if (serialized.SkippedNodes != null)
        lines.Add("            SkippedNodes = SkippedNodes,");

    lines.Add("            TokenData = TokenData,");
    lines.Add("            Tokenizers = tokenizers.ToArray(),");
    lines.Add("            TopRules = TopRules,");
    lines.Add("            Context = context,");

    if (serialized.Dialects != null)
        lines.Add("            Dialects = Dialects,");

    if (serialized.DynamicPrecedences != null)
        lines.Add("            DynamicPrecedences = DynamicPrecedences,");

    if (serialized.SpecializedEntries.Count > 0)
    {
        lines.Add("            Specialized = new SpecializerSpec[]");
        lines.Add("            {");
        foreach (var entry in serialized.SpecializedEntries)
        {
            switch (entry)
            {
                case SpecializedEntry.Table tbl:
                    lines.Add($"                new SpecializerSpec {{ Term = {tbl.Term}, Get = (value, _) => _specializer_{tbl.Term}_lookup.TryGetValue(value, out var v) ? v : -1 }},");
                    break;
                case SpecializedEntry.ExternalEntry ext:
                    lines.Add($"                new SpecializerSpec {{ Term = {ext.Term}, External = (value, stack) => ((Func<string, Stack, int>)(externals?[\"{EscapeString(ext.Name)}\"]!)).Invoke(value, stack) }},");
                    break;
            }
        }
        lines.Add("            },");
    }

    lines.Add("            TokenPrec = TokenPrec,");

    if (serialized.TermNames != null)
        lines.Add("            TermNames = TermNames");

    lines.Add("        };");
    lines.Add("    }");
    lines.Add("}");

    return string.Join("\n", lines) + "\n";
}
