namespace Rezel.Generator;

public class Node
{
    public readonly int Start;

    public Node(int start)
    {
        Start = start;
    }
}

public sealed class ScopedSkipEntry
{
    public readonly Expression Expr;
    public readonly RuleDeclaration[] TopRules;
    public readonly RuleDeclaration[] Rules;

    public ScopedSkipEntry(Expression expr, RuleDeclaration[] topRules, RuleDeclaration[] rules)
    {
        Expr = expr;
        TopRules = topRules;
        Rules = rules;
    }
}

public sealed class PrecItem
{
    public readonly Identifier Id;
    public readonly string? Type;

    public PrecItem(Identifier id, string? type)
    {
        Id = id;
        Type = type;
    }
}

public sealed class TokenEntry
{
    public readonly Identifier Id;
    public readonly Prop[] Props;

    public TokenEntry(Identifier id, Prop[] props)
    {
        Id = id;
        Props = props;
    }
}

public sealed class GrammarDeclaration : Node
{
    public readonly RuleDeclaration[] Rules;
    public readonly RuleDeclaration[] TopRules;
    public readonly TokenDeclaration? Tokens;
    public readonly LocalTokenDeclaration[] LocalTokens;
    public readonly ContextDeclaration? Context;
    public readonly ExternalTokenDeclaration[] ExternalTokens;
    public readonly ExternalSpecializeDeclaration[] ExternalSpecializers;
    public readonly ExternalPropSourceDeclaration[] ExternalPropSources;
    public readonly PrecDeclaration? Precedences;
    public readonly Expression? MainSkip;
    public readonly ScopedSkipEntry[] ScopedSkip;
    public readonly Identifier[] Dialects;
    public readonly ExternalPropDeclaration[] ExternalProps;
    public readonly bool AutoDelim;

    public GrammarDeclaration(
        int start,
        RuleDeclaration[] rules,
        RuleDeclaration[] topRules,
        TokenDeclaration? tokens,
        LocalTokenDeclaration[] localTokens,
        ContextDeclaration? context,
        ExternalTokenDeclaration[] externalTokens,
        ExternalSpecializeDeclaration[] externalSpecializers,
        ExternalPropSourceDeclaration[] externalPropSources,
        PrecDeclaration? precedences,
        Expression? mainSkip,
        ScopedSkipEntry[] scopedSkip,
        Identifier[] dialects,
        ExternalPropDeclaration[] externalProps,
        bool autoDelim
    ) : base(start)
    {
        Rules = rules;
        TopRules = topRules;
        Tokens = tokens;
        LocalTokens = localTokens;
        Context = context;
        ExternalTokens = externalTokens;
        ExternalSpecializers = externalSpecializers;
        ExternalPropSources = externalPropSources;
        Precedences = precedences;
        MainSkip = mainSkip;
        ScopedSkip = scopedSkip;
        Dialects = dialects;
        ExternalProps = externalProps;
        AutoDelim = autoDelim;
    }
}

public sealed class RuleDeclaration : Node
{
    public readonly Identifier Id;
    public readonly Prop[] Props;
    public readonly Identifier[] Params;
    public readonly Expression Expr;

    public RuleDeclaration(
        int start,
        Identifier id,
        Prop[] props,
        Identifier[] parameters,
        Expression expr
    ) : base(start)
    {
        Id = id;
        Props = props;
        Params = parameters;
        Expr = expr;
    }
}

public sealed class PrecDeclaration : Node
{
    public readonly PrecItem[] Items;

    public PrecDeclaration(int start, PrecItem[] items) : base(start)
    {
        Items = items;
    }
}

public sealed class TokenPrecDeclaration : Node
{
    public readonly Expression[] Items;

    public TokenPrecDeclaration(int start, Expression[] items) : base(start)
    {
        Items = items;
    }
}

public sealed class TokenConflictDeclaration : Node
{
    public readonly Expression A;
    public readonly Expression B;

    public TokenConflictDeclaration(int start, Expression a, Expression b) : base(start)
    {
        A = a;
        B = b;
    }
}

public sealed class TokenDeclaration : Node
{
    public readonly TokenPrecDeclaration[] Precedences;
    public readonly TokenConflictDeclaration[] Conflicts;
    public readonly RuleDeclaration[] Rules;
    public readonly LiteralDeclaration[] Literals;

    public TokenDeclaration(
        int start,
        TokenPrecDeclaration[] precedences,
        TokenConflictDeclaration[] conflicts,
        RuleDeclaration[] rules,
        LiteralDeclaration[] literals
    ) : base(start)
    {
        Precedences = precedences;
        Conflicts = conflicts;
        Rules = rules;
        Literals = literals;
    }
}

public sealed class LocalTokenDeclaration : Node
{
    public readonly TokenPrecDeclaration[] Precedences;
    public readonly RuleDeclaration[] Rules;
    public readonly TokenEntry? Fallback;

    public LocalTokenDeclaration(
        int start,
        TokenPrecDeclaration[] precedences,
        RuleDeclaration[] rules,
        TokenEntry? fallback
    ) : base(start)
    {
        Precedences = precedences;
        Rules = rules;
        Fallback = fallback;
    }
}

public sealed class LiteralDeclaration : Node
{
    public readonly string Literal;
    public readonly Prop[] Props;

    public LiteralDeclaration(int start, string literal, Prop[] props) : base(start)
    {
        Literal = literal;
        Props = props;
    }
}

public sealed class ContextDeclaration : Node
{
    public readonly Identifier Id;
    public readonly string Source;

    public ContextDeclaration(int start, Identifier id, string source) : base(start)
    {
        Id = id;
        Source = source;
    }
}

public sealed class ExternalTokenDeclaration : Node
{
    public readonly Identifier Id;
    public readonly string Source;
    public readonly TokenEntry[] Tokens;
    public readonly Identifier[] Conflicts;

    public ExternalTokenDeclaration(
        int start,
        Identifier id,
        string source,
        TokenEntry[] tokens,
        Identifier[] conflicts
    ) : base(start)
    {
        Id = id;
        Source = source;
        Tokens = tokens;
        Conflicts = conflicts;
    }
}

public sealed class ExternalSpecializeDeclaration : Node
{
    public readonly string Type;
    public readonly Expression Token;
    public readonly Identifier Id;
    public readonly string Source;
    public readonly TokenEntry[] Tokens;

    public ExternalSpecializeDeclaration(
        int start,
        string type,
        Expression token,
        Identifier id,
        string source,
        TokenEntry[] tokens
    ) : base(start)
    {
        Type = type;
        Token = token;
        Id = id;
        Source = source;
        Tokens = tokens;
    }
}

public sealed class ExternalPropSourceDeclaration : Node
{
    public readonly Identifier Id;
    public readonly string Source;

    public ExternalPropSourceDeclaration(int start, Identifier id, string source) : base(start)
    {
        Id = id;
        Source = source;
    }
}

public sealed class ExternalPropDeclaration : Node
{
    public readonly Identifier Id;
    public readonly Identifier ExternalID;
    public readonly string Source;

    public ExternalPropDeclaration(int start, Identifier id, Identifier externalID, string source) : base(start)
    {
        Id = id;
        ExternalID = externalID;
        Source = source;
    }
}

public sealed class Identifier : Node
{
    public readonly string Name;

    public Identifier(int start, string name) : base(start)
    {
        Name = name;
    }
}
