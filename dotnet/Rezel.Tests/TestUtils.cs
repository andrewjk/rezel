using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Rezel.Common;
using Rezel.Generator;
using Rezel.Lr;

namespace Rezel.Tests;

public class TestSpec
{
    public string Name;
    public (NodePropBase Prop, object Value)[] Props;
    public List<TestSpec> Children;
    public bool Wildcard;

    public TestSpec(string name, (NodePropBase, object)[] props, List<TestSpec>? children = null, bool wildcard = false)
    {
        Name = name;
        Props = props;
        Children = children ?? [];
        Wildcard = wildcard;
    }

        public static List<TestSpec> Parse(string spec)
        {
            var pos = 0;
            var tok = "sof";
            var value = "";

            void Advance()
            {
            while (pos < spec.Length && char.IsWhiteSpace(spec[pos])) pos++;
            if (pos == spec.Length) { tok = "eof"; return; }
            var ch = spec[pos++];
            if (ch == '(' && pos + 4 <= spec.Length && spec.Substring(pos, 4) == "...)")
            {
                pos += 4;
                tok = "...";
                return;
            }
            if ("[],=()".Contains(ch)) { tok = ch.ToString(); return; }
            if (!char.IsWhiteSpace(ch) && !"[],=\"()".Contains(ch))
            {
                var start = pos - 1;
                while (pos < spec.Length && !char.IsWhiteSpace(spec[pos]) && !"[],=\"()".Contains(spec[pos]))
                    pos++;
                value = spec[start..pos];
                tok = "name";
                return;
            }
            if (ch == '"')
            {
                var start = pos - 1;
                var end = pos;
                while (end < spec.Length)
                {
                    if (spec[end] == '\\') { end += 2; }
                    else if (spec[end] == '"') { end++; break; }
                    else end++;
                }
                var raw = spec[start..end];
                try
                {
                    value = JsonSerializer.Deserialize<string>(raw) ?? raw;
                }
                catch
                {
                    value = raw;
                }
                pos = end;
                tok = "name";
                return;
            }
            throw new InvalidOperationException($"Invalid test spec: {spec}");
        }

        Advance();

        List<TestSpec> ParseSeq()
        {
            var seq = new List<TestSpec>();
            while (tok != "eof" && tok != ")")
            {
                seq.Add(ParseOne());
                if (tok == ",") Advance();
            }
            return seq;
        }

        TestSpec ParseOne()
        {
            var name = value;
            var children = new List<TestSpec>();
            var props = new List<(NodePropBase, object)>();
            var wildcard = false;
            if (tok != "name") throw new InvalidOperationException($"Invalid test spec: {spec}");
            Advance();
            if (tok == "[")
            {
                Advance();
                while (tok != "]")
                {
                    if (tok != "name") throw new InvalidOperationException($"Invalid test spec: {spec}");
                    var propName = value;
                    Advance();
                    object propValue = "";
                    if (tok == "=")
                    {
                        Advance();
                        if (tok != "name") throw new InvalidOperationException($"Invalid test spec: {spec}");
                        propValue = value;
                        Advance();
                    }
                    if (NodeProps.ByName.TryGetValue(propName, out var nodeProp))
                    {
                        if (nodeProp is NodeProp<string> strProp)
                        {
                            props.Add((strProp, strProp.Deserialize((string)propValue)));
                        }
                        else
                        {
                            props.Add((nodeProp, propValue));
                        }
                    }
                }
                Advance();
            }
            if (tok == "(")
            {
                Advance();
                children = ParseSeq();
                if (tok != ")") throw new InvalidOperationException($"Invalid test spec: {spec}");
                Advance();
            }
            else if (tok == "...")
            {
                wildcard = true;
                Advance();
            }
            return new TestSpec(name, props.ToArray(), children, wildcard);
        }

        var result = ParseSeq();
        if (tok != "eof") throw new InvalidOperationException($"Invalid test spec: {spec}");
        return result;
    }

    public bool Matches(NodeType type)
    {
        if (type.Name != Name) return false;
        foreach (var (prop, val) in Props)
        {
            var typeProp = prop switch
            {
                NodeProp<string> sp => (object?)type.Prop(sp),
                NodeProp<string[]> sap => (object?)type.Prop(sap),
                _ => type.PropObj(prop)
            };
            var specVal = val;
            if (specVal is string s && string.IsNullOrEmpty(s))
            {
                if (typeProp != null) return false;
                continue;
            }
            if (typeProp == null) return false;
            if (typeProp is string ts && specVal is string sv && ts != sv) return false;
        }
        return true;
    }
}

public static class TestUtils
{
    public static bool DefaultIgnore(NodeType type)
    {
        return type.Name.All(c => !char.IsLetterOrDigit(c));
    }

    public static void TestTree(Tree tree, string expect, Func<NodeType, bool>? mayIgnore = null)
    {
        mayIgnore ??= DefaultIgnore;
        var specs = TestSpec.Parse(expect);
        var stack = new List<List<TestSpec>> { specs };
        var pos = new List<int> { 0 };
        string? caughtError = null;

        tree.Iterate(0, tree.Length, IterMode.None,
            enter: n =>
            {
                if (string.IsNullOrEmpty(n.Name)) return true;
                var last = stack.Count - 1;
                var index = pos[last];
                var seq = stack[last];
                var next = index < seq.Count ? seq[index] : null;

                if (next != null && next.Matches(n.Type))
                {
                    if (next.Wildcard)
                    {
                        pos[last]++;
                        return false;
                    }
                    pos.Add(0);
                    stack.Add(next.Children);
                    return true;
                }
                else if (mayIgnore(n.Type))
                {
                    return false;
                }
                else
                {
                    var parent = last > 0 ? stack[last - 1][pos[last - 1]].Name : "tree";
                    var after = next != null
                        ? next.Name + (parent == "tree" ? "" : " in " + parent)
                        : $"end of {parent}";
                    caughtError = $"Expected {after}, got {n.Name} at {n.To} \n{tree}";
                    return false;
                }
            },
            leave: n =>
            {
                if (string.IsNullOrEmpty(n.Name)) return;
                var last = stack.Count - 1;
                var index = pos[last];
                var seq = stack[last];
                if (index < seq.Count)
                {
                    var remaining = string.Join(", ", seq.Skip(index).Select(s => s.Name));
                    caughtError = $"Unexpected end of {n.Name}. Expected {remaining} at {n.From}\n{tree}";
                    return;
                }
                pos.RemoveAt(pos.Count - 1);
                stack.RemoveAt(stack.Count - 1);
                pos[last - 1]++;
            }
        );

        if (caughtError != null) throw new InvalidOperationException(caughtError);

        if (pos[0] != specs.Count)
        {
            var remaining = string.Join(", ", stack[0].Skip(pos[0]).Select(s => s.Name));
            throw new InvalidOperationException($"Unexpected end of tree. Expected {remaining} at {tree.Length}\n{tree}");
        }
    }

    private static string ToLineContext(string file, int index)
    {
        var endEol = file.IndexOf('\n', Math.Min(index + 80, file.Length));
        var endIndex = endEol == -1 ? file.Length : endEol;
        return string.Join("\n", file[index..endIndex]
            .Split('\n')
            .Select(str => "  | " + str));
    }

    public static List<TestCase> FileTests(string file, string fileName, Func<NodeType, bool>? mayIgnore = null)
    {
        mayIgnore ??= DefaultIgnore;
        var caseExpr = new Regex(@"\s*#[ \t]*(.*)(?:\r\n|\r|\n)([\s\S]*?)==+>([\s\S]*?)(?:$|(?:\r\n|\r|\n)+(?=#))");
        var tests = new List<TestCase>();
        var lastIndex = 0;

        foreach (Match m in caseExpr.Matches(file))
        {
            if (m.Index != lastIndex)
            {
                throw new InvalidOperationException(
                    $"Unexpected file format in {fileName} around\n\n{ToLineContext(file, lastIndex)}");
            }

            var text = m.Groups[2].Value.Trim();
            var expected = m.Groups[3].Value.Trim();
            var nameRaw = m.Groups[1].Value.Trim();
            var nameConfig = Regex.Match(nameRaw, @"(.*?)(\{.*?\})?$");
            var name = nameConfig.Groups[1].Value.Trim();
            var configStr = nameConfig.Groups[2].Value;
            JsonElement? config = null;
            if (!string.IsNullOrEmpty(configStr))
            {
                config = JsonSerializer.Deserialize<JsonElement>(configStr);
            }
            var strict = !expected.Contains('⚠') && !expected.Contains("...");

            tests.Add(new TestCase
            {
                Name = name,
                Text = text,
                Expected = expected,
                Config = config,
                Strict = strict,
                Run = (Parser parser) =>
                {
                    if (parser is LRParser lrp && (strict || config.HasValue))
                    {
                        var cfg = new ParserConfig
                        {
                            Strict = strict,
                        };
                        if (config.HasValue)
                        {
                            if (config.Value.TryGetProperty("top", out var top))
                                cfg.Top = top.GetString();
                            if (config.Value.TryGetProperty("dialect", out var dialect))
                                cfg.Dialect = dialect.GetString();
                        }
                        parser = lrp.Configure(cfg);
                    }
                    var tree = parser.Parse(text);
                    TestTree(tree, expected, mayIgnore);
                }
            });

            lastIndex = m.Index + m.Length;
        }

        if (lastIndex != file.Length)
        {
            var trailing = file[lastIndex..].Trim();
            if (!string.IsNullOrEmpty(trailing))
            {
                throw new InvalidOperationException(
                    $"Unexpected file format in {fileName} around\n\n{ToLineContext(file, Math.Min(lastIndex, file.Length - 1))}");
            }
        }

        return tests;
    }
}

public class TestCase
{
    public string Name { get; set; } = "";
    public string Text { get; set; } = "";
    public string Expected { get; set; } = "";
    public JsonElement? Config { get; set; }
    public bool Strict { get; set; }
    public Action<Parser> Run { get; set; } = _ => { };
}
