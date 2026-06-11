using System.Text;
using System.Text.Json;

namespace Rezel.Generator;

public abstract class Expression : Node
{
    protected Expression(int start) : base(start) { }

    public virtual int Prec => 10;

    public virtual Expression Walk(Func<Expression, Expression> f) => f(this);

    public virtual bool Eq(Expression other) => false;

    public static readonly Dictionary<string, int[][]> CharClasses = new()
    {
        ["asciiLetter"] = new int[][] { new int[] { 65, 91 }, new int[] { 97, 123 } },
        ["asciiLowercase"] = new int[][] { new int[] { 97, 123 } },
        ["asciiUppercase"] = new int[][] { new int[] { 65, 91 } },
        ["digit"] = new int[][] { new int[] { 48, 58 } },
        ["whitespace"] = new int[][]
        {
            new int[] { 9, 14 },
            new int[] { 32, 33 },
            new int[] { 133, 134 },
            new int[] { 160, 161 },
            new int[] { 5760, 5761 },
            new int[] { 8192, 8203 },
            new int[] { 8232, 8234 },
            new int[] { 8239, 8240 },
            new int[] { 8287, 8288 },
            new int[] { 12288, 12289 },
        },
        ["eof"] = new int[][] { new int[] { 0xffff, 0xffff } },
    };

    public static bool ExprEq(Expression a, Expression b)
    {
        return a.GetType() == b.GetType() && a.Eq(b);
    }

    public static bool ExprsEq(Expression[] a, Expression[] b)
    {
        if (a.Length != b.Length) return false;
        for (int i = 0; i < a.Length; i++)
            if (!ExprEq(a[i], b[i])) return false;
        return true;
    }

    internal static Expression[] WalkExprs(Expression[] exprs, Func<Expression, Expression> f)
    {
        List<Expression>? result = null;
        for (int i = 0; i < exprs.Length; i++)
        {
            var expr = exprs[i].Walk(f);
            if (expr != exprs[i] && result == null)
                result = new List<Expression>(exprs[..i]);
            if (result != null)
                result.Add(expr);
        }
        return result?.ToArray() ?? exprs;
    }

    internal static string MaybeParens(Expression node, Expression parent)
    {
        return node.Prec < parent.Prec ? $"({node})" : node.ToString()!;
    }
}

public sealed class NameExpression : Expression
{
    public readonly Identifier Id;
    public readonly Expression[] Args;

    public NameExpression(int start, Identifier id, Expression[] args) : base(start)
    {
        Id = id;
        Args = args;
    }

    public override string ToString()
    {
        if (Args.Length == 0) return Id.Name;
        return $"{Id.Name}<{string.Join(",", Args.Select(a => a.ToString()))}>";
    }

    public override bool Eq(Expression other)
    {
        var o = (NameExpression)other;
        return Id.Name == o.Id.Name && ExprsEq(Args, o.Args);
    }

    public override Expression Walk(Func<Expression, Expression> f)
    {
        var args = WalkExprs(Args, f);
        return f(args == Args ? this : new NameExpression(Start, Id, args));
    }
}

public sealed class SpecializeExpression : Expression
{
    public readonly string Type;
    public readonly Prop[] Props;
    public readonly Expression Token;
    public readonly Expression Content;

    public SpecializeExpression(int start, string type, Prop[] props, Expression token, Expression content) : base(start)
    {
        Type = type;
        Props = props;
        Token = token;
        Content = content;
    }

    public override string ToString()
    {
        return $"@{Type}[{string.Join(",", Props.Select(p => p.ToString()))}]<{Token}, {Content}>";
    }

    public override bool Eq(Expression other)
    {
        var o = (SpecializeExpression)other;
        return Type == o.Type && Prop.EqProps(Props, o.Props) && ExprEq(Token, o.Token) && ExprEq(Content, o.Content);
    }

    public override Expression Walk(Func<Expression, Expression> f)
    {
        var token = Token.Walk(f);
        var content = Content.Walk(f);
        return f(
            token == Token && content == Content
                ? this
                : new SpecializeExpression(Start, Type, Props, token, content)
        );
    }
}

public sealed class InlineRuleExpression : Expression
{
    public readonly RuleDeclaration Rule;

    public InlineRuleExpression(int start, RuleDeclaration rule) : base(start)
    {
        Rule = rule;
    }

    public override string ToString()
    {
        var rule = Rule;
        var propsPart = rule.Props.Length > 0 ? $"[{string.Join(",", rule.Props.Select(p => p.ToString()))}]" : "";
        return $"{rule.Id.Name}{propsPart} {{ {rule.Expr} }}";
    }

    public override bool Eq(Expression other)
    {
        var rule = Rule;
        var oRule = ((InlineRuleExpression)other).Rule;
        return ExprEq(rule.Expr, oRule.Expr) && rule.Id.Name == oRule.Id.Name && Prop.EqProps(rule.Props, oRule.Props);
    }

    public override Expression Walk(Func<Expression, Expression> f)
    {
        var rule = Rule;
        var expr = rule.Expr.Walk(f);
        return f(
            expr == rule.Expr
                ? this
                : new InlineRuleExpression(Start, new RuleDeclaration(rule.Start, rule.Id, rule.Props, rule.Params, expr))
        );
    }
}

public sealed class ChoiceExpression : Expression
{
    public override int Prec => 1;

    public readonly Expression[] Exprs;

    public ChoiceExpression(int start, Expression[] exprs) : base(start)
    {
        Exprs = exprs;
    }

    public override string ToString()
    {
        return string.Join(" | ", Exprs.Select(e => MaybeParens(e, this)));
    }

    public override bool Eq(Expression other)
    {
        return ExprsEq(Exprs, ((ChoiceExpression)other).Exprs);
    }

    public override Expression Walk(Func<Expression, Expression> f)
    {
        var exprs = WalkExprs(Exprs, f);
        return f(exprs == Exprs ? this : new ChoiceExpression(Start, exprs));
    }
}

public sealed class SequenceExpression : Expression
{
    public override int Prec => 2;

    public readonly Expression[] Exprs;
    public readonly ConflictMarker[][] Markers;
    public readonly bool Empty;

    public SequenceExpression(int start, Expression[] exprs, ConflictMarker[][] markers, bool empty = false) : base(start)
    {
        Exprs = exprs;
        Markers = markers;
        Empty = empty;
    }

    public override string ToString()
    {
        if (Empty) return "()";
        return string.Join(" ", Exprs.Select(e => MaybeParens(e, this)));
    }

    public override bool Eq(Expression other)
    {
        var o = (SequenceExpression)other;
        if (!ExprsEq(Exprs, o.Exprs)) return false;
        for (int i = 0; i < Markers.Length; i++)
        {
            var m = Markers[i];
            var om = o.Markers[i];
            if (m.Length != om.Length) return false;
            for (int j = 0; j < m.Length; j++)
                if (!m[j].Eq(om[j])) return false;
        }
        return true;
    }

    public override Expression Walk(Func<Expression, Expression> f)
    {
        var exprs = WalkExprs(Exprs, f);
        return f(
            exprs == Exprs
                ? this
                : new SequenceExpression(Start, exprs, Markers, Empty && exprs.Length == 0)
        );
    }
}

public sealed class ConflictMarker : Node
{
    public readonly Identifier Id;
    public readonly string Type;

    public ConflictMarker(int start, Identifier id, string type) : base(start)
    {
        Id = id;
        Type = type;
    }

    public override string ToString()
    {
        return (Type == "ambig" ? "~" : "!") + Id.Name;
    }

    public bool Eq(ConflictMarker other)
    {
        return Id.Name == other.Id.Name && Type == other.Type;
    }
}

public sealed class RepeatExpression : Expression
{
    public override int Prec => 3;

    public readonly Expression Expr;
    public readonly string Kind;

    public RepeatExpression(int start, Expression expr, string kind) : base(start)
    {
        Expr = expr;
        Kind = kind;
    }

    public override string ToString()
    {
        return MaybeParens(Expr, this) + Kind;
    }

    public override bool Eq(Expression other)
    {
        var o = (RepeatExpression)other;
        return ExprEq(Expr, o.Expr) && Kind == o.Kind;
    }

    public override Expression Walk(Func<Expression, Expression> f)
    {
        var expr = Expr.Walk(f);
        return f(expr == Expr ? this : new RepeatExpression(Start, expr, Kind));
    }
}

public sealed class LiteralExpression : Expression
{
    public readonly string Value;

    public LiteralExpression(int start, string value) : base(start)
    {
        Value = value;
    }

    public override string ToString()
    {
        return JsonSerializer.Serialize(Value);
    }

    public override bool Eq(Expression other)
    {
        return Value == ((LiteralExpression)other).Value;
    }
}

public sealed class SetExpression : Expression
{
    public readonly int[][] Ranges;
    public readonly bool Inverted;

    public SetExpression(int start, int[][] ranges, bool inverted) : base(start)
    {
        Ranges = ranges;
        Inverted = inverted;
    }

    public override string ToString()
    {
        var sb = new StringBuilder("[");
        if (Inverted) sb.Append('^');
        foreach (var range in Ranges)
        {
            sb.Append(char.ConvertFromUtf32(range[0]));
            if (range[1] != range[0] + 1)
            {
                sb.Append('-');
                sb.Append(char.ConvertFromUtf32(range[1]));
            }
        }
        sb.Append(']');
        return sb.ToString();
    }

    public override bool Eq(Expression other)
    {
        var o = (SetExpression)other;
        if (Inverted != o.Inverted || Ranges.Length != o.Ranges.Length) return false;
        for (int i = 0; i < Ranges.Length; i++)
        {
            if (Ranges[i][0] != o.Ranges[i][0] || Ranges[i][1] != o.Ranges[i][1]) return false;
        }
        return true;
    }
}

public sealed class AnyExpression : Expression
{
    public AnyExpression(int start) : base(start) { }

    public override string ToString() => "_";

    public override bool Eq(Expression other) => true;
}

public sealed class CharClass : Expression
{
    public readonly string Type;

    public CharClass(int start, string type) : base(start)
    {
        Type = type;
    }

    public override string ToString() => "@" + Type;

    public override bool Eq(Expression other)
    {
        return Type == ((CharClass)other).Type;
    }
}

public sealed class Prop : Node
{
    public readonly bool At;
    public readonly string Name;
    public readonly PropPart[] Value;

    public Prop(int start, bool at, string name, PropPart[] value) : base(start)
    {
        At = at;
        Name = name;
        Value = value;
    }

    public override string ToString()
    {
        var result = new StringBuilder();
        if (At) result.Append('@');
        result.Append(Name);
        if (Value.Length > 0)
        {
            result.Append('=');
            foreach (var part in Value)
                result.Append(part.Name != null ? $"{{{part.Name}}}" : NeedsQuoting(part.Value) ? JsonSerializer.Serialize(part.Value!) : part.Value);
        }
        return result.ToString();
    }

    public bool Eq(Prop other)
    {
        if (Name != other.Name || Value.Length != other.Value.Length) return false;
        for (int i = 0; i < Value.Length; i++)
            if (Value[i].Value != other.Value[i].Value || Value[i].Name != other.Value[i].Name) return false;
        return true;
    }

    public static bool EqProps(Prop[] a, Prop[] b)
    {
        if (a.Length != b.Length) return false;
        for (int i = 0; i < a.Length; i++)
            if (!a[i].Eq(b[i])) return false;
        return true;
    }

    private static bool NeedsQuoting(string? value)
    {
        if (value == null) return false;
        foreach (char c in value)
            if (!char.IsLetterOrDigit(c) && c != '_' && c != '-') return true;
        return false;
    }
}

public sealed class PropPart : Node
{
    public readonly string? Value;
    public readonly string? Name;

    public PropPart(int start, string? value, string? name) : base(start)
    {
        Value = value;
        Name = name;
    }
}
