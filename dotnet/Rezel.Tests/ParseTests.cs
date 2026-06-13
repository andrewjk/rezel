using System.Diagnostics;
using System.Linq;
using Rezel.Common;
using Rezel.Generator;
using Rezel.Lr;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Rezel.Tests;

[TestClass]
public class ParseTests
{
    static LRParser P(string text, BuildOptions? options = null, ParserConfig? config = null)
    {
        var opts = new BuildOptions { Warn = e => throw new InvalidOperationException(e) };
        if (options != null)
        {
            opts.FileName = options.FileName;
            opts.IncludeNames = options.IncludeNames;
            opts.ModuleStyle = options.ModuleStyle;
            opts.TypeScript = options.TypeScript;
            opts.ExportName = options.ExportName;
            opts.ExternalTokenizerFn = options.ExternalTokenizerFn;
            opts.ExternalPropSource = options.ExternalPropSource;
            opts.ExternalSpecializer = options.ExternalSpecializer;
            opts.ExternalProp = options.ExternalProp;
            opts.ContextTracker = options.ContextTracker;
        }
        var parser = BuildExt.BuildParser(text, opts);
        if (config != null) parser = parser.Configure(config);
        return parser;
    }

    static int Shared(Tree a, Tree b)
    {
        var inA = new HashSet<Tree>();
        var shared = 0;

        void Register(Tree t)
        {
            var mounted = t.Prop(NodeProps.Mounted);
            if (mounted != null && mounted.Overlay == null) t = mounted.Tree;
            foreach (var child in t.Children.OfType<Tree>())
                Register(child);
            inA.Add(t);
        }

        void Scan(Tree t)
        {
            if (inA.Contains(t))
            {
                shared += t.Length;
            }
            else
            {
                var mounted = t.Prop(NodeProps.Mounted);
                var scan = mounted != null && mounted.Overlay == null ? mounted.Tree : t;
                foreach (var child in scan.Children.OfType<Tree>())
                    Scan(child);
            }
        }

        Register(a);
        Scan(b);
        return (int)Math.Round(100.0 * shared / b.Length);
    }

    static TreeFragment[] Fragments(Tree tree, params (int FromA, int ToA, int FromB, int ToB)[] changes)
    {
        return TreeFragment.ApplyChanges(
            TreeFragment.AddTree(tree),
            changes.Select(c => new ChangedRange(c.FromA, c.ToA, c.FromB, c.ToB)).ToArray(),
            2
        );
    }

    static TreeFragment[] Fragments(Tree tree, params (int FromA, int ToA)[] changes)
    {
        return TreeFragment.ApplyChanges(
            TreeFragment.AddTree(tree),
            changes.Select(c => new ChangedRange(c.FromA, c.ToA, c.FromA, c.ToA)).ToArray(),
            2
        );
    }

    static LRParser? _p1;
    static LRParser P1() => _p1 ??= P(@"
    @precedence { call }

    @top T { statement* }
    statement { Cond | Loop | Block | expression "";"" }
    Cond { kw<""if""> expression statement }
    Block { ""{"" statement* ""}"" }
    Loop { kw<""while""> expression statement }
    expression { Call | Num | Var | ""!"" expression }
    Call { expression !call ""("" expression* "")"" }

    kw<value> { @specialize<Var, value> }
    @tokens {
      Num { @digit+ }
      Var { @asciiLetter+ }
      whitespace { @whitespace+ }
    }
    @skip { whitespace }");

    [TestMethod]
    public void CanParseIncrementally()
    {
        var doc = string.Concat(Enumerable.Repeat("if true { print(1); hello; } while false { if 1 do(something 1 2 3); }", 10));
        var ast = P1().Configure(new ParserConfig { BufferLength = 2 }).Parse(doc);
        var content = "Cond(Var,Block(Call(Var,Num),Var)),Loop(Var,Block(Cond(Num,Call(Var,Var,Num,Num,Num))))";
        var expected = "T(" + string.Concat(Enumerable.Repeat(content + ",", 9)) + content + ")";
        TestUtils.TestTree(ast, expected);
        Assert.AreEqual(700, ast.Length);

        var pos = doc.IndexOf("false")!;
        var doc2 = doc[..pos] + "x" + doc[(pos + 5)..];
        var frags = Fragments(ast, (pos, pos + 5, pos, pos + 1));
        var ast2 = P1()
            .Configure(new ParserConfig { BufferLength = 2 })
            .Parse(doc2, frags);
        TestUtils.TestTree(ast2, expected);
        var shared = Shared(ast, ast2);
        Assert.IsTrue(shared > 40, $"Shared was {shared}, expected > 40");
        Assert.AreEqual(696, ast2.Length);
    }

    static (int From, int To) Qq(Tree ast, string query, int offset = 1)
    {
        var cursor = ast.Cursor();
        do
        {
            if (cursor.Name == query && --offset == 0)
                return (cursor.From, cursor.To);
        } while (cursor.Next());
        throw new Exception($"Couldn't find {query}");
    }

    [TestMethod]
    public void AssignsCorrectNodePositions()
    {
        var doc = "if 1 { while 2 { foo(bar(baz bug)); } }";
        var ast = P1().Configure(new ParserConfig { BufferLength = 10, Strict = true }).Parse(doc);
        Assert.AreEqual(39, ast.Length);

        var cond = Qq(ast, "Cond");
        var one = Qq(ast, "Num");
        Assert.AreEqual(0, cond.From);
        Assert.AreEqual(39, cond.To);
        Assert.AreEqual(3, one.From);
        Assert.AreEqual(4, one.To);

        var loop = Qq(ast, "Loop");
        var two = Qq(ast, "Num", 2);
        Assert.AreEqual(7, loop.From);
        Assert.AreEqual(37, loop.To);
        Assert.AreEqual(13, two.From);
        Assert.AreEqual(14, two.To);

        var call = Qq(ast, "Call");
        var inner = Qq(ast, "Call", 2);
        Assert.AreEqual(17, call.From);
        Assert.AreEqual(34, call.To);
        Assert.AreEqual(21, inner.From);
        Assert.AreEqual(33, inner.To);

        var bar = Qq(ast, "Var", 2);
        var bug = Qq(ast, "Var", 4);
        Assert.AreEqual(21, bar.From);
        Assert.AreEqual(24, bar.To);
        Assert.AreEqual(29, bug.From);
        Assert.AreEqual(32, bug.To);
    }

    static string ResolveDoc = "while 111 { one; two(three 20); }";

    void TestResolve(int bufferLength)
    {
        var ast = P1().Configure(new ParserConfig { Strict = true, BufferLength = bufferLength }).Parse(ResolveDoc);

        var cx111 = ast.CursorAt(7);
        Assert.AreEqual("Num", cx111.Name);
        Assert.AreEqual(6, cx111.From);
        Assert.AreEqual(9, cx111.To);
        cx111.Parent();
        Assert.AreEqual("Loop", cx111.Name);
        Assert.AreEqual(0, cx111.From);
        Assert.AreEqual(33, cx111.To);

        var cxThree = ast.CursorAt(22);
        Assert.AreEqual("Var", cxThree.Name);
        Assert.AreEqual(21, cxThree.From);
        Assert.AreEqual(26, cxThree.To);
        cxThree.Parent();
        Assert.AreEqual("Call", cxThree.Name);
        Assert.AreEqual(17, cxThree.From);
        Assert.AreEqual(30, cxThree.To);

        var branch = cxThree.MoveTo(18);
        Assert.AreEqual("Var", branch.Name);
        Assert.AreEqual(17, branch.From);
        Assert.AreEqual(20, branch.To);

        // Always resolve to the uppermost context for a position
        Assert.AreEqual("Loop", ast.CursorAt(6).Name);
        Assert.AreEqual("Loop", ast.CursorAt(9).Name);

        var c = ast.CursorAt(20);
        Assert.IsTrue(c.FirstChild());
        Assert.AreEqual("Var", c.Name);
        Assert.IsTrue(c.NextSibling());
        Assert.AreEqual("Var", c.Name);
        Assert.IsTrue(c.NextSibling());
        Assert.AreEqual("Num", c.Name);
        Assert.IsFalse(c.NextSibling());
    }

    [TestMethod]
    public void CanResolvePositionsInBuffers() => TestResolve(1024);

    [TestMethod]
    public void CanResolvePositionsInTrees() => TestResolve(2);

    static string IterDoc = "while 1 { a; b; c(d e); } while 2 { f; }";
    static object[] IterSeq = [
        "T", 0, "Loop", 0, "Num", 6, "/Num", 7, "Block", 8, "Var", 10, "/Var", 11,
        "Var", 13, "/Var", 14, "Call", 16, "Var", 16, "/Var", 17, "Var", 18, "/Var", 19,
        "Var", 20, "/Var", 21, "/Call", 22, "/Block", 25, "/Loop", 25, "Loop", 26,
        "Num", 32, "/Num", 33, "Block", 34, "Var", 36, "/Var", 37, "/Block", 40,
        "/Loop", 40, "/T", 40
    ];
    static object[] PartialIterSeq = [
        "T", 0, "Loop", 0, "Block", 8, "Var", 13, "/Var", 14, "Call", 16,
        "Var", 16, "/Var", 17, "Var", 18, "/Var", 19, "/Call", 22, "/Block", 25,
        "/Loop", 25, "/T", 40
    ];

    void TestIter(int bufferLength, bool partial)
    {
        var output = new List<object>();
        var ast = P1().Configure(new ParserConfig { Strict = true, BufferLength = bufferLength }).Parse(IterDoc);
        ast.Iterate(
            partial ? 13 : 0,
            partial ? 19 : ast.Length,
            IterMode.None,
            enter: n => { output.Add(n.Name); output.Add(n.From); return true; },
            leave: n => { output.Add("/" + n.Name); output.Add(n.To); }
        );
        var expected = partial ? PartialIterSeq : IterSeq;
        Assert.AreEqual(string.Join(",", expected), string.Join(",", output));
    }

    [TestMethod]
    public void SupportsForwardIterationInBuffers() => TestIter(1024, false);

    [TestMethod]
    public void SupportsForwardIterationInTrees() => TestIter(2, false);

    [TestMethod]
    public void SupportsPartialForwardIterationInBuffers() => TestIter(1024, true);

    [TestMethod]
    public void SupportsPartialForwardIterationInTrees() => TestIter(2, true);

    [TestMethod]
    public void CanSkipIndividualNodesDuringIteration()
    {
        var ast = P1().Parse("foo(baz(baz), bug(quux)");
        var ids = 0;
        ast.Iterate(0, ast.Length, IterMode.None,
            enter: n =>
            {
                if (n.Name == "Var") ids++;
                return !(n.From == 4 && n.Name == "Call");
            });
        Assert.AreEqual(3, ids);
    }

    [TestMethod]
    public void DoesNotIncorrectlyReuseNodes()
    {
        var opts = new BuildOptions { Warn = e => throw new InvalidOperationException(e) };
        var parser = BuildExt.BuildParser(@"
@precedence { times @left, plus @left }
@top T { expr+ }
expr { Bin | Var }
Bin { expr !plus ""+"" expr | expr !times ""*"" expr }
@skip { space }
@tokens { space { "" ""+ } Var { ""x"" } ""*""[@name=Times] ""+""[@name=Plus] }
", opts);
        var p = parser.Configure(new ParserConfig { Strict = true, BufferLength = 2 });
        var ast = p.Parse("x + x + x");
        TestUtils.TestTree(ast, "T(Bin(Bin(Var,Plus,Var),Plus,Var))");
        var ast2 = p.Parse("x * x + x + x", Fragments(ast, (0, 0, 0, 4)));
        TestUtils.TestTree(ast2, "T(Bin(Bin(Bin(Var,Times,Var),Plus,Var),Plus,Var))");
    }

    [TestMethod]
    public void CanCacheSkippedContent()
    {
        var comments = BuildExt.BuildParser(@"
@top T { ""x""+ }
@skip { space | Comment }
@skip {} {
  Comment { commentStart (Comment | commentContent)* commentEnd }
}
@tokens {
  space { "" ""+ }
  commentStart { ""("" }
  commentEnd { "")"" }
  commentContent { ![()]+ }
}
", new BuildOptions { Warn = e => throw new InvalidOperationException(e) });
        var doc = "x  (one (two) (three " + string.Concat(Enumerable.Repeat("(y)", 500)) + ")) x";
        var ast = comments.Configure(new ParserConfig { BufferLength = 10, Strict = true }).Parse(doc);
        var ast2 = comments
            .Configure(new ParserConfig { BufferLength = 10 })
            .Parse(doc[1..], Fragments(ast, (0, 1, 0, 0)));
        var sharedVal = Shared(ast, ast2);
        Assert.IsTrue(sharedVal > 80, $"Shared was {sharedVal}, expected > 80");
    }

    [TestMethod]
    public void DoesNotGetSlowOnLongInvalidInput()
    {
        var sw = Stopwatch.StartNew();
        var ast = P1().Parse(new string('#', 2000));
        sw.Stop();
        Assert.IsTrue(sw.ElapsedMilliseconds < 500, $"Took {sw.ElapsedMilliseconds}ms");
        Assert.AreEqual("T(⚠)", ast.ToString());
    }

    [TestMethod]
    public void SupportsInputRanges()
    {
        var tree = P1().Parse(
            "if 1{{x}}0{{y}}0 foo {{z}};",
            null,
            [
                new CommonRange(0, 4),
                new CommonRange(9, 10),
                new CommonRange(15, 21),
                new CommonRange(26, 27),
            ]);
        Assert.AreEqual("T(Cond(Num,Var))", tree.ToString());
    }

    [TestMethod]
    public void DoesNotReuseNodesBeyondFragments()
    {
        var comments = BuildExt.BuildParser(@"
@top Top { (Group | Char)* }
@tokens {
  Group { ""(""![)]* "")"" }
  Char { _ }
}", new BuildOptions { Warn = e => throw new InvalidOperationException(e) });
        var p = comments.Configure(new ParserConfig { BufferLength = 10 });
        var doc = "xxx(" + string.Concat(Enumerable.Repeat("x", 996));
        var tree1 = p.Parse(doc);
        var tree2 = p.Parse(
            doc + ")",
            TreeFragment.ApplyChanges(TreeFragment.AddTree(tree1),
                [new ChangedRange(1000, 1000, 1000, 1001)])
        );
        Assert.AreEqual("Top(Char,Char,Char,Group)", tree2.ToString());
    }

    // Sequences tests

    static LRParser? _p1Seq;
    static LRParser P1Seq() => _p1Seq ??= P(@"
    @top T { (X | Y)+ }
    @skip { C }
    C { ""c"" }
    X { ""x"" }
    Y { ""y"" "";""* }");

    static LRParser? _blob;
    static LRParser Blob() => _blob ??= P(@"@top Blob { ch* } @tokens { ch { _ } }", null, new ParserConfig { BufferLength = 10 });

    static LRParser? _templateParser;
    static LRParser TemplateParser() => _templateParser ??= P(@"
    @top Doc { (Dir | Content | Block)* }
    Dir { ""{{"" Word ""}}"" }
    Block { ""{%"" BlockContent { (Dir | Content)* } ""%}"" }
    @tokens {
      Content { ![{%]+ }
      Word { $[a-z]+ }
    }");

    static int Depth(Tree tree) =>
        tree.Children.Length == 0 ? 1 :
        tree.Children.Select(c => c is Tree t ? Depth(t) + 1 : 1).Max();

    static int Breadth(Tree tree) =>
        tree.Children.Length == 0 ? 0 :
        tree.Children.Select(c => c is Tree t ? Breadth(t) : 0).Append(tree.Children.Length).Max();

    [TestMethod]
    public void BalancesParsedSequences()
    {
        var ast = P1Seq().Configure(new ParserConfig { BufferLength = 10 }).Parse(string.Concat(Enumerable.Repeat("x", 1000)));
        var d = Depth(ast);
        var b = Breadth(ast);
        Assert.IsTrue(d <= 6);
        Assert.IsTrue(d >= 4);
        Assert.IsTrue(b >= 5);
        Assert.IsTrue(b <= 10);
    }

    [TestMethod]
    public void CreatesATreeForLongContentlessRepeats()
    {
        var p = BuildExt.BuildParser(@"
@top T { (A | B { ""["" b+ ""]"" })+ }
@tokens {
  A { ""a"" }
  b { ""b"" }
}
", new BuildOptions { Warn = e => throw new InvalidOperationException(e) });
        var tree = p.Configure(new ParserConfig { BufferLength = 10 }).Parse("a[" + string.Concat(Enumerable.Repeat("b", 500)) + "]");
        Assert.AreEqual("T(A,B)", tree.ToString());
        Assert.IsTrue(Depth(tree) >= 5);
    }

    [TestMethod]
    public void BalancingNotConfusedBySkippedNodes()
    {
        var ast = P1Seq().Configure(new ParserConfig { BufferLength = 10 }).Parse(string.Concat(Enumerable.Repeat("xc", 1000)));
        var d = Depth(ast);
        var b = Breadth(ast);
        Assert.IsTrue(d <= 6);
        Assert.IsTrue(d >= 4);
        Assert.IsTrue(b >= 5);
        Assert.IsTrue(b <= 10);
    }

    [TestMethod]
    public void CachesPartsOfSequences()
    {
        var doc = string.Concat(Enumerable.Repeat("x", 1000));
        var p = P1Seq().Configure(new ParserConfig { BufferLength = 10 });
        var ast = p.Parse(doc);
        var full = p.Parse(doc, TreeFragment.AddTree(ast));
        var sharedFull = Shared(ast, full);
        Assert.IsTrue(sharedFull >= 99, $"Shared was {sharedFull}, expected >= 99");

        var front = p.Parse(doc, Fragments(ast, (900, 1000, 900, 1000)));
        Assert.IsTrue(Shared(ast, front) > 50);

        var back = p.Parse(doc, Fragments(ast, (0, 100, 0, 100)));
        Assert.IsTrue(Shared(ast, back) > 50);

        var middle = p.Parse(doc, Fragments(ast, (0, 100, 0, 100), (900, 1000, 900, 1000)));
        Assert.IsTrue(Shared(ast, middle) > 50);

        var sides = p.Parse(doc, Fragments(ast, (450, 550, 450, 550)));
        Assert.IsTrue(Shared(ast, sides) > 50);
    }

    [TestMethod]
    public void AssignsRightPositionsToSequences()
    {
        var doc = string.Concat(Enumerable.Repeat("x", 100)) + "y;;;;;;;;;" + string.Concat(Enumerable.Repeat("x", 90));
        var ast = P1Seq().Configure(new ParserConfig { BufferLength = 10 }).Parse(doc);
        var i = 0;
        ast.Iterate(0, ast.Length, IterMode.None, enter: n =>
        {
            if (i == 0)
            {
                Assert.AreEqual("T", n.Name);
            }
            else if (i == 101)
            {
                Assert.AreEqual("Y", n.Name);
                Assert.AreEqual(100, n.From);
                Assert.AreEqual(110, n.To);
            }
            else
            {
                Assert.AreEqual("X", n.Name);
                Assert.AreEqual(n.To, n.From + 1);
                Assert.AreEqual(n.From, i <= 100 ? i - 1 : i + 8);
            }
            i++;
            return true;
        });
    }

    // Multiple tops

    [TestMethod]
    public void ParsesNamedTops()
    {
        var parser = BuildExt.BuildParser(@"
@top X { FOO C }
@top Y { B C }
FOO { B }
B { ""b"" }
C { ""c"" }
", new BuildOptions { Warn = e => throw new InvalidOperationException(e) });

        TestUtils.TestTree(parser.Parse("bc"), "X(FOO(B), C)");
        TestUtils.TestTree(parser.Configure(new ParserConfig { Top = "X" }).Parse("bc"), "X(FOO(B), C)");
        TestUtils.TestTree(parser.Configure(new ParserConfig { Top = "Y" }).Parse("bc"), "Y(B, C)");
    }

    [TestMethod]
    public void ParsesFirstTopAsDefault()
    {
        var parser = BuildExt.BuildParser(@"
@top X { FOO C }
@top Y { B C }
FOO { B }
B { ""b"" }
C { ""c"" }
", new BuildOptions { Warn = e => throw new InvalidOperationException(e) });

        TestUtils.TestTree(parser.Parse("bc"), "X(FOO(B), C)");
        TestUtils.TestTree(parser.Configure(new ParserConfig { Top = "Y" }).Parse("bc"), "Y(B, C)");
    }

    // Mixed languages

    [TestMethod]
    public void CanMixGrammars()
    {
        var opts = new BuildOptions { Warn = e => throw new InvalidOperationException(e) };
        var inner = BuildExt.BuildParser(@"
      @top I { expr+ }
      expr { B { Open{""("" } expr+ Close{"")""} } | Dot{"".""} }", opts);
        var outer = BuildExt.BuildParser(@"
      @top O { expr+ }
      expr { ""[["" NestContent ""]]"" | Bang{""!""} }
      @tokens {
        NestContent[@export] { ![\]]+ }
        ""[[""[@name=Start] ""]]""[@name=End]
      }
    ", opts).Configure(new ParserConfig
        {
            Wrap = MixedParsing.ParseMixed((node, input) =>
            {
                if (node.Name == "NestContent") return new NestedParse(inner, bracketed: true);
                return null;
            }),
        });

        TestUtils.TestTree(
            outer.Parse("![[((.).)]][[.]]"),
            "O(Bang,Start,I(B(Open,B(Open,Dot,Close),Dot,Close)),End,Start,I(Dot),End)");
        TestUtils.TestTree(outer.Parse("[[/]]"), "O(Start,I(⚠),End)");

        var tree = outer.Parse("[[(.)]]");
        var innerNode = tree.TopNode.ChildAfter(2)!;
        Assert.AreEqual("I", innerNode.Name);
        Assert.AreEqual(2, innerNode.From);
        Assert.AreEqual(5, innerNode.To);
        Assert.AreEqual(2, innerNode.FirstChild!.From);
        Assert.AreEqual(5, innerNode.FirstChild!.To);
        Assert.IsNull(tree.TopNode.Enter(2, 0));
        Assert.AreEqual("I", tree.TopNode.Enter(2, 0, IterMode.EnterBracketed)!.Name);
    }

    [TestMethod]
    public void SupportsConditionalNesting()
    {
        var opts = new BuildOptions { Warn = e => throw new InvalidOperationException(e) };
        var inner = BuildExt.BuildParser(@"@top Script { any } @tokens { any { ![]+ } }", opts);
        var outer = BuildExt.BuildParser(@"
      @top T { Tag }
      Tag { Open Content? Close }
      Open { ""<"" name "">"" }
      Close { ""</"" name "">"" }
      @tokens {
        name { @asciiLetter+ }
        Content { ![<]+ }
      }
    ", opts).Configure(new ParserConfig
        {
            Wrap = MixedParsing.ParseMixed((node, input) =>
            {
                if (node.Name == "Content")
                {
                    var open = node.Node.Parent!.FirstChild!;
                    if (input.Read(open.From, open.To) == "<script>") return new NestedParse(inner);
                }
                return null;
            }),
        });
        TestUtils.TestTree(outer.Parse("<foo>bar</foo>"), "T(Tag(Open,Content,Close))");
        TestUtils.TestTree(outer.Parse("<script>hello</script>"), "T(Tag(Open,Script,Close))");
    }

    [TestMethod]
    public void CanParseIncrementallyAcrossNesting()
    {
        var opts = new BuildOptions { Warn = e => throw new InvalidOperationException(e) };
        var outer = BuildExt.BuildParser(@"
      @top Program { (Nest | Name)* }
      @skip { space }
      @skip {} {
        Nest { ""{"" Nested ""}"" }
        Nested { nestedChar* }
      }
      @tokens {
        space { @whitespace+ }
        nestedChar { ![}] }
        Name { $[a-z]+ }
      }
    ", opts).Configure(new ParserConfig
        {
            BufferLength = 10,
            Wrap = MixedParsing.ParseMixed((node, input) => node.Name == "Nested" ? new NestedParse(Blob()) : null),
        });
        var baseStr = "hello {bbbb} ";
        var doc = string.Concat(Enumerable.Repeat(baseStr, 500)) + "{" + string.Concat(Enumerable.Repeat("b", 1000)) + "} " + string.Concat(Enumerable.Repeat(baseStr, 500));
        var off = baseStr.Length * 500 + 500;
        var ast1 = outer.Parse(doc);
        var ast2 = outer.Parse(
            doc[..off] + "bbb" + doc[(off)..],
            TreeFragment.ApplyChanges(TreeFragment.AddTree(ast1),
                [new ChangedRange(off, off, off, off + 3)])
        );
        Assert.AreEqual(ast1.ToString(), ast2.ToString());

        var sharedVal = Shared(ast1, ast2);
        Assert.IsTrue(sharedVal > 90, $"Shared was {sharedVal}, expected > 90");
    }

    [TestMethod]
    public void CanCreateOverlays()
    {
        var mix = TemplateParser().Configure(new ParserConfig
        {
            Wrap = MixedParsing.ParseMixed((node, input) =>
            {
                return node.Name == "Doc"
                    ? new NestedParse(Blob(),
                        overlay: (Func<ISyntaxNodeRef, object?>)(n => n.Name == "Content"),
                        bracketed: true)
                    : null;
            }),
        });
        var tree = mix.Parse("foo{{bar}}baz{{bug}}");
        Assert.AreEqual("Doc(Content,Dir(Word),Content,Dir(Word))", tree.ToString());
        var c1 = tree.ResolveInner(1);
        Assert.AreEqual("Blob", c1.Name);
        Assert.AreEqual(0, c1.From);
        Assert.AreEqual(13, c1.To);
        Assert.AreEqual("Doc", c1.Parent!.Name);
        Assert.AreEqual("Blob", tree.ResolveInner(10, 1).Name);
        Assert.AreEqual("Dir", tree.TopNode.Enter(3, 1)!.Name);
        Assert.AreEqual("Blob", tree.TopNode.Enter(3, 1, IterMode.EnterBracketed)!.ToString());

        var mix2 = TemplateParser().Configure(new ParserConfig
        {
            Wrap = MixedParsing.ParseMixed((node, input) =>
            {
                return node.Name == "Doc"
                    ? new NestedParse(Blob(),
                        overlay: new CommonRange[] { new CommonRange(5, 7) })
                    : null;
            }),
        });
        var tree2 = mix2.Parse("{{a}}bc{{d}}");
        var c2 = tree2.ResolveInner(6);
        Assert.AreEqual("Blob", c2.Name);
        Assert.AreEqual(5, c2.From);
        Assert.AreEqual(7, c2.To);
        Assert.AreEqual("Dir", tree.TopNode.Enter(5, -1, IterMode.EnterBracketed)!.Name);
    }

    [TestMethod]
    public void AddsMountEvenForEmptyNodes()
    {
        var inner = P(@"@top E { tok? } @tokens { tok { "" ""+ } }");
        var mix = TemplateParser().Configure(new ParserConfig
        {
            Wrap = MixedParsing.ParseMixed((node, input) =>
                node.Name == "BlockContent" ? new NestedParse(inner) : null)
        });
        var ast = mix.Parse("a{%%}b{% %}");
        TestUtils.TestTree(ast, "Doc(Content,Block(E),Content,Block(E))");
    }

    [TestMethod]
    public void CanResolveStack()
    {
        var opts = new BuildOptions { Warn = e => throw new InvalidOperationException(e) };
        var parens = BuildExt.BuildParser(@"
      @top T { (Text | Group)* }
      Group { ""("" (Text | Group)* "")"" }
      @tokens { Text { ![()]+ } }", opts);
        var mix = TemplateParser().Configure(new ParserConfig
        {
            Wrap = MixedParsing.ParseMixed((node, input) =>
                node.Type.IsTop ? new NestedParse(parens, overlay: (Func<ISyntaxNodeRef, object?>)(n => n.Name == "Content")) : null)
        });

        string Trail(NodeIterator? stack)
        {
            var result = new List<string>();
            for (; stack != null; stack = stack.Next) result.Add(stack.Node.Name);
            return string.Join(" ", result);
        }

        for (var i = 0; i < 2; i++)
        {
            var parser = i == 1 ? mix.Configure(new ParserConfig { BufferLength = 2 }) : mix;
            var ast = parser.Parse("(hey{%okay(one)two%}three)!");
            Assert.AreEqual("Text Group Content BlockContent Block Group T Doc", Trail(ast.ResolveStack(12)));
            Assert.AreEqual("Content Text Group T Doc", Trail(ast.ResolveStack(2)));
            Assert.AreEqual("Text Block Group Doc T", Trail(ast.ResolveStack(5)));
        }
    }

    [TestMethod]
    public void ReusesRangesFromPreviousParses()
    {
        var opts = new BuildOptions { Warn = e => throw new InvalidOperationException(e) };
        var queried = new List<int>();
        var outer = BuildExt.BuildParser(@"
      @top Doc { expr* }
      expr {
        Paren { ""("" expr* """" "")"" } |
        Array { ""["" expr* ""]"" } |
        Number |
        String
      }
      @skip { space }
      @tokens {
        Number { $[0-9]+ }
        String { ""'"" ![']* ""'"" }
        space { $[ \n]+ }
      }
    ", opts).Configure(new ParserConfig
        {
            BufferLength = 2,
            Wrap = MixedParsing.ParseMixed((node, input) =>
            {
                return node.Name == "Array"
                    ? new NestedParse(Blob(),
                        overlay: (Func<ISyntaxNodeRef, object?>)(n =>
                        {
                            if (n.Name == "String")
                            {
                                queried.Add(n.From);
                                return true;
                            }
                            return false;
                        }))
                    : null;
            }),
        });

        var doc = " (100) (() [50] 123456789012345678901234 ((['one' 123456789012345678901234 (('two'))]) ['three'])) ";
        var tree = outer.Parse(doc);
        Assert.AreEqual(
            "Doc(Paren(Number),Paren(Paren,Array(Number),Number,Paren(Paren(Array(String,Number,Paren(Paren(String)))),Array(String))))",
            tree.ToString());
        var inOne = tree.ResolveInner(45);
        Assert.AreEqual("Blob", inOne.Name);
        Assert.AreEqual(44, inOne.From);
        Assert.AreEqual(82, inOne.To);
        Assert.IsNull(inOne.NextSibling);
        Assert.IsNull(inOne.PrevSibling);
        Assert.AreEqual("Array", inOne.Parent!.Name);
        Assert.AreEqual("Blob", tree.ResolveInner(89).Name);
        Assert.AreEqual("44,77,88", string.Join(",", queried));
        queried.Clear();

        var frags = Fragments(tree, (45, 46));
        var tree2 = outer.Parse(doc[..45] + "x" + doc[46..], frags);
        Assert.AreEqual("44", string.Join(",", queried));
        var sharedVal = Shared(tree, tree2);
        Assert.IsTrue(sharedVal > 20, $"Shared was {sharedVal}, expected > 20");
    }

    [TestMethod]
    public void ProperlyHandlesFragmentOffsets()
    {
        var opts = new BuildOptions { Warn = e => throw new InvalidOperationException(e) };
        var inner = BuildExt.BuildParser(@"@top Text { (Word | "" "")* } @tokens { Word { ![ ]+ } }", opts)
            .Configure(new ParserConfig { BufferLength = 2 });
        var outer = BuildExt.BuildParser(@"
      @top Doc { expr* }
      expr { Wrap { ""("" expr* """" "")"" } | Templ { ""["" expr* ""]"" } | Number | String }
      @skip { space }
      @tokens {
        Number { $[0-9]+ }
        String { ""'"" ![']* ""'"" }
        space { $[ \n]+ }
      }
    ", opts).Configure(new ParserConfig
        {
            BufferLength = 2,
            Wrap = MixedParsing.ParseMixed((node, input) =>
            {
                return node.Name == "Templ"
                    ? new NestedParse(inner,
                        overlay: (Func<ISyntaxNodeRef, object?>)(n =>
                            n.Name == "String" ? new CommonRange(n.From + 1, n.To - 1) : false))
                    : null;
            }),
        });

        var doc = " 0123456789012345678901234 (['123456789 123456789 12345 stuff' 123456789 (('123456789 123456789 12345 other' 4))] 200)";
        var tree = outer.Parse(doc);

        // Verify that mounts inside reused nodes don't get re-parsed
        var tree1 = outer.Parse("88" + doc, Fragments(tree, (0, 0, 0, 2)));
        Assert.AreSame(tree.ResolveInner(50).Tree, tree1.ResolveInner(52).Tree);

        // Verify that content inside the nested parse gets accurately reused
        var tree2 = outer.Parse(
            "88" + doc[..30] + doc[31..],
            Fragments(tree, (0, 0, 0, 2), (30, 31, 32, 32)));
        var sharedVal = Shared(tree, tree2);
        Assert.IsTrue(sharedVal > 20, $"Shared was {sharedVal}, expected > 20");
        var sharedInner = Shared(tree.ResolveInner(49).Tree!, tree2.ResolveInner(50).Tree!);
        Assert.IsTrue(sharedInner > 20, $"Shared inner was {sharedInner}, expected > 20");
        var other = tree2.ResolveInner(103, 1);
        Assert.AreEqual(103, other.From);
        Assert.AreEqual(108, other.To);
    }

    [TestMethod]
    public void SupportsNestedOverlays()
    {
        var opts = new BuildOptions { Warn = e => throw new InvalidOperationException(e) };
        var outer = BuildExt.BuildParser(@"
      @top Doc { expr* }
      expr {
        Paren { ""("" expr* """" "")"" } |
        Array { ""["" expr* ""]"" } |
        Number |
        String
      }
      @skip { space }
      @tokens {
        Number { $[0-9]+ }
        String { ""'"" ![']* ""'"" }
        space { $[ \n]+ }
      }
    ", opts).Configure(new ParserConfig { BufferLength = 2 });

        void TestMixed(LRParser parser)
        {
            var tree = parser.Parse("['x' 100 (['xxx' 20 ('xx')] 'xxx')]");
            var blob1 = tree.ResolveInner(2, 1);
            Assert.AreEqual("Blob", blob1.Name);
            Assert.AreEqual(2, blob1.From);
            Assert.AreEqual(32, blob1.To);
            var blob2 = tree.ResolveInner(12, 1);
            Assert.AreEqual("Blob", blob2.Name);
            Assert.AreEqual(12, blob2.From);
            Assert.AreEqual(24, blob2.To);
        }

        TestMixed(
            outer.Configure(new ParserConfig
            {
                Wrap = MixedParsing.ParseMixed((node, input) =>
                {
                    return node.Name == "Array"
                        ? new NestedParse(Blob(),
                            overlay: (Func<ISyntaxNodeRef, object?>)(n =>
                                n.Name == "String" ? new CommonRange(n.From + 1, n.To - 1) : false))
                        : null;
                }),
            }));

        TestMixed(
            outer.Configure(new ParserConfig
            {
                Wrap = MixedParsing.ParseMixed((node, input) =>
                {
                    if (node.Name != "Array") return null;
                    var ranges = new List<CommonRange>();
                    void Scan(SyntaxNode n)
                    {
                        if (n.Name == "String") ranges.Add(new CommonRange(n.From + 1, n.To - 1));
                        else
                            for (var ch = n.FirstChild; ch != null; ch = ch.NextSibling)
                                if (ch.Name != "Array") Scan(ch);
                    }
                    Scan(node.Node);
                    return new NestedParse(Blob(), overlay: ranges.ToArray());
                }),
            }));
    }

    [TestMethod]
    public void ReparsesCutOffInnerParsesEvenIfOuterTreeFinished()
    {
        var opts = new BuildOptions { Warn = e => throw new InvalidOperationException(e) };
        var inner = BuildExt.BuildParser(@"@top Phrase { ""<"" ch* "">"" } @tokens { ch { ![>] } }", opts)
            .Configure(new ParserConfig { BufferLength = 2 });
        var parser = BuildExt.BuildParser(@"
      @top Doc { Section* }
      Section { ""{"" SectionContent? ""}"" }
      @tokens { SectionContent { ![}]+ } }
    ", opts).Configure(new ParserConfig
        {
            BufferLength = 2,
            Wrap = MixedParsing.ParseMixed((node, input) =>
                node.Name == "SectionContent" ? new NestedParse(inner) : null),
        });
        var input = "{<" + string.Concat(Enumerable.Repeat("x", 100)) + ">}{<xxxx>}";
        var parse = parser.StartParse(input);
        while (parse.ParsedPos < 50) parse.Advance();
        parse.StopAt(parse.ParsedPos);
        Tree? tree1 = null;
        while ((tree1 = parse.Advance()) == null) { }
        Assert.AreEqual("Doc(Section(Phrase(⚠)),Section(Phrase(⚠)))", tree1.ToString());
        var tree2 = parser.Parse(input, TreeFragment.AddTree(tree1));
        Assert.AreEqual("Doc(Section(Phrase),Section(Phrase))", tree2.ToString());
    }
}
