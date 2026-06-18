using System.Text.RegularExpressions;
using Rezel.Common;
using Rezel.Lr;
using Rezel.Grammars;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using File = System.IO.File;

namespace Rezel.Tests;

public static class GrammarParserRegistry
{
    public static readonly string GrammarTestRoot = Path.Combine(
        Path.GetDirectoryName(typeof(GrammarTests).Assembly.Location)!,
        "..", "..", "..", "..", "..", "web", "grammars");

    public static readonly string[] Languages =
    [
        "cpp", "css", "go", "java", "php", "python", "rust", "sass", "xml", "yaml",
        "zig", "csharp"
    ];

    public static LRParser GetParser(string lang)
    {
        return lang switch
        {
            "cpp" => CppGrammar.Parser,
            "css" => CssGrammar.Parser,
            "go" => GoGrammar.Parser,
            "java" => JavaGrammar.Parser,
            "php" => PhpGrammar.Parser,
            "python" => PythonGrammar.Parser,
            "rust" => RustGrammar.Parser,
            "sass" => SassGrammar.Parser,
            "xml" => XmlGrammar.Parser,
            "yaml" => YamlGrammar.Parser,
            "zig" => ZigGrammar.Parser,
            "csharp" => CSharpGrammar.Parser,
            _ => throw new ArgumentException($"Unknown grammar: {lang}"),
        };
    }

    public static string GetTestDir(string lang)
    {
        var subDir = lang switch
        {
            "zig" => "codemirror-lang-zig",
            "csharp" => "codemirror-lang-csharp",
            _ => lang,
        };
        return Path.Combine(GrammarTestRoot, subDir, "test");
    }
}

[TestClass]
public class GrammarTests
{
    public static IEnumerable<object[]> GetGrammarTestCases()
    {
        foreach (var lang in GrammarParserRegistry.Languages)
        {
            var testDir = GrammarParserRegistry.GetTestDir(lang);
            if (!Directory.Exists(testDir)) continue;
            foreach (var file in Directory.GetFiles(testDir, "*.txt"))
            {
                yield return new object[] { lang, file };
            }
        }
    }

    private static readonly HashSet<string> KnownFailures = new()
    {
        // YAML spec example that also fails in the upstream JS implementation
        "yaml|spec.txt|Example 8.15 Block Sequence Entry Types",
    };

    [TestMethod]
    [DynamicData(nameof(GetGrammarTestCases))]
    public void RunGrammarTest(string lang, string filePath)
    {
        var parser = GrammarParserRegistry.GetParser(lang);
        var fileName = Path.GetFileName(filePath);
        var content = File.ReadAllText(filePath);

        var tests = TestUtils.FileTests(content, fileName);
        foreach (var test in tests)
        {
            var key = $"{lang}|{fileName}|{test.Name}";
            if (KnownFailures.Contains(key))
            {
                Console.WriteLine($"SKIP (known failure): {key}");
                continue;
            }
            test.Run(parser);
        }
    }
}
