using Rezel.Common;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Rezel.Tests;

[TestClass]
public class TreeTests
{
    static readonly NodeType[] Types;
    static readonly NodeSet NodeSet;
    static readonly NodeType RepeatType;

    static TreeTests()
    {
        var names = new[] { "T", "a", "b", "c", "Pa", "Br" };
        Types = new NodeType[names.Length + 1];
        for (var i = 0; i < names.Length; i++)
        {
            var isAtom = names[i] is "a" or "b" or "c";
            Types[i] = NodeType.Define(
                id: i,
                name: names[i],
                props: isAtom ? [NodeProps.Group.Add(_ => new[] { "atom" })] : null
            );
        }
        RepeatType = NodeType.Define(id: names.Length);
        Types[names.Length] = RepeatType;
        NodeSet = new NodeSet(Types);
    }

    static int Id(string n) => Types.First(x => x.Name == n).Id;

    static Tree Mk(string spec)
    {
        var starts = new List<int>();
        var buffer = new List<int>();
        var pos = 0;

        while (pos < spec.Length)
        {
            var ch = spec[pos];
            if (ch is 'a' or 'b' or 'c')
            {
                var bufStart = buffer.Count;
                var groupStart = pos;
                var i = 0;
                while (pos < spec.Length && spec[pos] is 'a' or 'b' or 'c')
                {
                    buffer.Add(Id(spec[pos].ToString()));
                    buffer.Add(pos);
                    buffer.Add(pos + 1);
                    buffer.Add(4);
                    if (i > 0)
                    {
                        var curLen = buffer.Count;
                        buffer.Add(RepeatType.Id);
                        buffer.Add(groupStart);
                        buffer.Add(pos + 1);
                        buffer.Add(curLen + 4 - bufStart);
                    }
                    i++;
                    pos++;
                }
            }
            else if (ch is '[' or '(')
            {
                starts.Add(buffer.Count);
                starts.Add(pos);
                pos++;
            }
            else if (ch is ']' or ')')
            {
                var stringStart = starts[^1]; starts.RemoveAt(starts.Count - 1);
                var bufStartOff = starts[^1]; starts.RemoveAt(starts.Count - 1);
                var nodeName = ch == ')' ? "Pa" : "Br";
                var curLen = buffer.Count;
                buffer.Add(Id(nodeName));
                buffer.Add(stringStart);
                buffer.Add(pos + 1);
                buffer.Add(curLen + 4 - bufStartOff);
                pos++;
            }
            else
            {
                pos++;
            }
        }

        return Tree.Build(new BuildData(
            buffer: buffer.ToArray(),
            nodeSet: NodeSet,
            topID: 0,
            maxBufferLength: 10,
            minRepeatType: RepeatType.Id
        ));
    }

    static string BuildRecurSpec(int depth)
    {
        if (depth > 0)
        {
            var inner = BuildRecurSpec(depth - 1);
            return "(" + inner + ")[" + inner + "]";
        }
        else
        {
            var result = "";
            for (var i = 0; i < 20; i++)
                result += new[] { "a", "b", "c" }[i % 3];
            return result;
        }
    }

    static Tree? _recur;
    static Tree Recur() => _recur ??= Mk(BuildRecurSpec(6));

    static Tree? _simple;
    static Tree Simple() => _simple ??= Mk("aaaa(bbb[ccc][aaa][()])");

    static Tree? _anonTree;
    static Tree AnonTree => _anonTree ??= new(
        Types[0],
        [
            new Tree(
                NodeType.None,
                [
                    new Tree(Types[1], [], [], 1),
                    new Tree(Types[2], [], [], 1),
                ],
                [0, 1],
                2
            ),
        ],
        [0],
        2
    );

    // SyntaxNode tests

    [TestMethod]
    public void CanResolveAtTopLevel()
    {
        var c = Simple().Resolve(2, -1);
        Assert.AreEqual(1, c.From);
        Assert.AreEqual(2, c.To);
        Assert.AreEqual("a", c.Name);
        Assert.AreEqual("T", c.Parent!.Name);
        Assert.IsNull(c.Parent!.Parent);

        c = Simple().Resolve(2, 1);
        Assert.AreEqual(2, c.From);
        Assert.AreEqual(3, c.To);

        c = Simple().Resolve(2);
        Assert.AreEqual("T", c.Name);
        Assert.AreEqual(0, c.From);
        Assert.AreEqual(23, c.To);
    }

    [TestMethod]
    public void CanResolveDeeper()
    {
        var c = Simple().Resolve(10, 1);
        Assert.AreEqual("c", c.Name);
        Assert.AreEqual(10, c.From);
        Assert.AreEqual("Br", c.Parent!.Name);
        Assert.AreEqual("Pa", c.Parent!.Parent!.Name);
        Assert.AreEqual("T", c.Parent!.Parent!.Parent!.Name);
    }

    [TestMethod]
    public void CanResolveInLargeTree()
    {
        SyntaxNode? c = Recur().Resolve(10, 1);
        var depth = 1;
        while (c != null)
        {
            c = c.Parent;
            depth++;
        }
        Assert.AreEqual(9, depth);
    }

    [TestMethod]
    public void CachesResolvedParents()
    {
        var a = Recur().Resolve(3, 1);
        var b = Recur().Resolve(3, 1);
        Assert.AreSame(a, b);
    }

    [TestMethod]
    public void SkipsAnonymousNodes()
    {
        Assert.AreEqual("T(a,b)", AnonTree.ToString());
        Assert.AreEqual("T", AnonTree.Resolve(1).Name);
        Assert.AreEqual("b", AnonTree.TopNode.LastChild!.Name);
        Assert.AreEqual("a", AnonTree.TopNode.FirstChild!.Name);
        Assert.AreEqual("b", AnonTree.TopNode.ChildAfter(1)!.Name);
    }

    [TestMethod]
    public void AllowsAccessToUnderlyingTree()
    {
        var tree = Mk("aaa[bbbbb(bb)bbbbbbb]aaa");
        var node = tree.TopNode.FirstChild!;
        while (node.Name != "Br") node = node.NextSibling!;
        Assert.IsNotNull(node.Tree);
        Assert.AreEqual("Br", node.Tree!.Type.Name);

        node = node.FirstChild!;
        while (node.Name != "Pa") node = node.NextSibling!;
        Assert.IsNull(node.Tree);
        Assert.AreEqual("Pa(b,b)", node.ToTree().ToString());

        node = node.FirstChild!;
        Assert.AreEqual("b", node.Name);
        Assert.AreEqual("b", node.ToTree().ToString());
        Assert.AreEqual(0, node.ToTree().Children.Length);
    }

    // TreeCursor tests

    static readonly Dictionary<string, int> SimpleCount = new()
    {
        ["a"] = 7,
        ["b"] = 3,
        ["c"] = 3,
        ["Br"] = 3,
        ["Pa"] = 2,
        ["T"] = 1
    };

    [TestMethod]
    public void CursorIteratesOverAllNodes()
    {
        var count = new Dictionary<string, int>();
        var pos = 0;
        var cur = Simple().Cursor();
        do
        {
            Assert.IsTrue(cur.From >= pos);
            pos = cur.From;
            count.TryGetValue(cur.Name, out var c);
            count[cur.Name] = c + 1;
        } while (cur.Next());
        foreach (var kv in SimpleCount)
            Assert.AreEqual(kv.Value, count.GetValueOrDefault(kv.Key, 0));
    }

    [TestMethod]
    public void CursorIteratesReverse()
    {
        var count = new Dictionary<string, int>();
        var pos = 100;
        var cur = Simple().Cursor();
        do
        {
            Assert.IsTrue(cur.To <= pos);
            pos = cur.To;
            count.TryGetValue(cur.Name, out var c);
            count[cur.Name] = c + 1;
        } while (cur.Prev());
        foreach (var kv in SimpleCount)
            Assert.AreEqual(kv.Value, count.GetValueOrDefault(kv.Key, 0));
    }

    [TestMethod]
    public void CursorWorksWithInternalIteration()
    {
        var openCount = new Dictionary<string, int>();
        var closeCount = new Dictionary<string, int>();
        Simple().Iterate(0, Simple().Length, IterMode.None,
            enter: t =>
            {
                openCount.TryGetValue(t.Name, out var c);
                openCount[t.Name] = c + 1;
                return true;
            },
            leave: t =>
            {
                closeCount.TryGetValue(t.Name, out var c);
                closeCount[t.Name] = c + 1;
            });
        foreach (var kv in SimpleCount)
        {
            Assert.AreEqual(kv.Value, openCount.GetValueOrDefault(kv.Key, 0));
            Assert.AreEqual(kv.Value, closeCount.GetValueOrDefault(kv.Key, 0));
        }
    }

    [TestMethod]
    public void CursorHandlesOutOfBounds()
    {
        var hit = 0;
        Tree.Empty.Iterate(0, 200, IterMode.None,
            enter: _ => { hit++; return true; },
            leave: _ => { hit++; });
        Assert.AreEqual(0, hit);
    }

    [TestMethod]
    public void CursorLimitedRange()
    {
        var seen = new List<string>();
        Simple().Iterate(3, 14, IterMode.None,
            enter: t =>
            {
                seen.Add(t.Name);
                return t.Name != "Br";
            });
        Assert.AreEqual("T,a,a,Pa,b,b,b,Br,Br", string.Join(",", seen));
    }

    [TestMethod]
    public void CursorCanLeaveNodes()
    {
        var c = Simple().Cursor();
        Assert.IsFalse(c.Parent());
        Assert.IsTrue(c.Next());
        Assert.IsTrue(c.Next());
        Assert.AreEqual(1, c.From);
        Assert.IsTrue(c.Parent());
        Assert.AreEqual(0, c.From);
        for (var j = 0; j < 6; j++) c.Next();
        Assert.AreEqual(5, c.From);
        Assert.IsTrue(c.Parent());
        Assert.AreEqual(4, c.From);
        Assert.IsTrue(c.Parent());
        Assert.AreEqual(0, c.From);
        Assert.IsFalse(c.Parent());
    }

    [TestMethod]
    public void CursorCanMoveToPosition()
    {
        var tree = Recur();
        var start = tree.Length >> 1;
        var cursor = tree.CursorAt(start, 1);
        do
        {
            Assert.IsTrue(cursor.From >= start);
        } while (cursor.Next());
    }

    [TestMethod]
    public void CursorCanMoveIntoParent()
    {
        var c = Simple().CursorAt(10);
        c.MoveTo(2);
        Assert.AreEqual("T", c.Name);
    }

    [TestMethod]
    public void CursorIsNotSlow()
    {
        var tree = Recur();
        var t0 = Environment.TickCount;
        var count = 0;
        for (var i = 0; i < 2000; i++)
        {
            var cur = tree.Cursor();
            do
            {
                if (cur.From < 0 || string.IsNullOrEmpty(cur.Name)) throw new Exception("BAD");
                count++;
            } while (cur.Next());
        }
        var elapsed = Math.Max(Environment.TickCount - t0, 1);
        var perMS = (double)count / elapsed;
        Assert.IsTrue(perMS > 10000, $"Performance too low: {perMS} per ms");
    }

    [TestMethod]
    public void CursorCanProduceNodes()
    {
        var node = Simple().CursorAt(8, 1).Node;
        Assert.AreEqual("Br", node.Name);
        Assert.AreEqual(8, node.From);
        Assert.AreEqual("Pa", node.Parent!.Name);
        Assert.AreEqual(4, node.Parent!.From);
        Assert.AreEqual("T", node.Parent!.Parent!.Name);
        Assert.AreEqual(0, node.Parent!.Parent!.From);
        Assert.IsNull(node.Parent!.Parent!.Parent);
    }

    [TestMethod]
    public void CursorSkipsAnonymousNodes()
    {
        var c = AnonTree.Cursor();
        c.MoveTo(1);
        Assert.AreEqual("T", c.Name);
        Assert.IsTrue(c.FirstChild());
        Assert.AreEqual("a", c.Name);
        Assert.IsTrue(c.NextSibling());
        Assert.AreEqual("b", c.Name);
        Assert.IsFalse(c.Next());
    }

    // matchContext tests

    [TestMethod]
    public void MatchContextCanMatchOnNodes()
    {
        Assert.IsTrue(Simple().Resolve(10, 1).MatchContext(["T", "Pa", "Br"]));
    }

    [TestMethod]
    public void MatchContextCanMatchWildcards()
    {
        Assert.IsTrue(Simple().Resolve(10, 1).MatchContext(["T", "", "Br"]));
    }

    [TestMethod]
    public void MatchContextCanMismatchOnNodes()
    {
        Assert.IsFalse(Simple().Resolve(10, 1).MatchContext(["Q", "Br"]));
    }

    [TestMethod]
    public void MatchContextCanMatchOnCursor()
    {
        var c = Simple().Cursor();
        for (var i = 0; i < 3; i++) c.Enter(15, -1);
        Assert.IsTrue(c.MatchContext(["T", "Pa", "Br"]));
    }
}
