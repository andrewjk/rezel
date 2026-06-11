using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class JsonGrammar
{
    private static readonly NodePropSource JsonHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["String"] = Tags.String,
        ["Number"] = Tags.Number,
        ["True False"] = Tags.Bool,
        ["PropertyName"] = Tags.PropertyName,
        ["Null"] = Tags.Null,
        [", :"] = Tags.Separator,
        ["[ ]"] = Tags.SquareBracket,
        ["{ }"] = Tags.Brace,
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var spec = JsonParserData.MakeSpec(
            externals: new Dictionary<string, ITokenizer>(),
            propSources: [JsonHighlighting]
        );
        return new LRParser(spec);
    }
}
