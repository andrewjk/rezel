using System.Text.Json;
using System.Text.RegularExpressions;
using Rezel.Common;
using Rezel.Generator;
using Rezel.Lr;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using File = System.IO.File;

namespace Rezel.Tests;

[TestClass]
public class CasesTests
{
    static readonly string CaseDir = Path.Combine(
        Path.GetDirectoryName(typeof(CasesTests).Assembly.Location)!,
        "..", "..", "..", "..", "..", "web", "test", "cases");

    static ExternalTokenizer? ExternalTokenizerFn(string name, Dictionary<string, int> terms)
    {
        if (name == "ext1")
            return new ExternalTokenizer((input, stack) =>
            {
                var next = input.Next;
                if (next == '{')
                {
                    input.Advance();
                    input.AcceptToken(terms["braceOpen"]);
                }
                else if (next == '}')
                {
                    input.Advance();
                    input.AcceptToken(terms["braceClose"]);
                }
                else if (next == '.')
                {
                    input.Advance();
                    input.AcceptToken(terms["Dot"]);
                }
            });
        return null;
    }

    static Func<string, Stack, int>? ExternalSpecializerFn(string name, Dictionary<string, int> terms)
    {
        if (name == "spec1")
            return (value, stack) =>
            {
                if (value == "one") return terms["one"];
                if (value == "two") return terms["two"];
                return -1;
            };
        return null;
    }

    static NodePropBase? ExternalPropFn(string name)
    {
        if (name == "tag")
            return new NodeProp<string>(x => x);
        return null;
    }

    static string ExtractGrammar(string content, out string rest)
    {
        var idx = content.IndexOf("\n# ", StringComparison.Ordinal);
        if (idx >= 0)
        {
            rest = content[(idx + 1)..];
            return content[..(idx + 1)];
        }
        rest = "";
        return content;
    }

    public static IEnumerable<object[]> GetCaseFiles()
    {
        if (!Directory.Exists(CaseDir)) yield break;
        foreach (var file in Directory.GetFiles(CaseDir, "*.txt"))
        {
            yield return new object[] { file };
        }
    }

    [TestMethod]
    [DynamicData(nameof(GetCaseFiles))]
    public void RunGrammarTestCase(string filePath)
    {
        var fileName = Path.GetFileName(filePath);
        var content = File.ReadAllText(filePath);
        var grammar = ExtractGrammar(content, out var rest);

        var expectedErrMatch = Regex.Match(grammar, @"//! (.*)");
        var hasCases = Regex.IsMatch(rest, @"\S");

        if (expectedErrMatch.Success)
        {
            var expectedErr = expectedErrMatch.Groups[1].Value.Trim().ToLower();
            Exception? caught = null;
            try
            {
                BuildExt.BuildParser(grammar, new BuildOptions
                {
                    FileName = filePath,
                    ExternalTokenizerFn = ExternalTokenizerFn,
                    ExternalSpecializer = ExternalSpecializerFn,
                    ExternalProp = ExternalPropFn,
                    Warn = e => throw new InvalidOperationException(e),
                });
            }
            catch (Exception e)
            {
                caught = e;
            }
            Assert.IsNotNull(caught, $"Expected exception containing '{expectedErr}'");
            StringAssert.Contains(caught.Message.ToLower().Replace("\\u0022", "\\\""), expectedErr);
            if (!hasCases) return;
        }

        Assert.IsTrue(hasCases, $"Test with neither expected errors nor input cases ({fileName})");

        var tests = TestUtils.FileTests(rest, fileName);
        var parser = BuildExt.BuildParser(grammar, new BuildOptions
        {
            FileName = filePath,
            ExternalTokenizerFn = ExternalTokenizerFn,
            ExternalSpecializer = ExternalSpecializerFn,
            ExternalProp = ExternalPropFn,
            Warn = e => throw new InvalidOperationException(e),
        });

        foreach (var test in tests)
        {
            test.Run(parser);
        }
    }
}
