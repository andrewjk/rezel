using Rezel.Common;
using Rezel.Lr;
using Rezel.Highlight;

namespace Rezel.Grammars;

public static class BashGrammar
{
    private static readonly NodePropSource BashHighlighting = HighlightUtil.StyleTags(new Dictionary<string, object>
    {
        ["while do done until for in case esac if then elif else fi"] = Tags.ControlKeyword,
        ["IORedirect"] = Tags.Operator,
        ["&& || |"] = Tags.LogicOperator,
        ["= +="] = Tags.Operator,
        ["( )"] = Tags.Paren,
        ["[ ]"] = Tags.SquareBracket,
        ["{ }"] = Tags.Brace,
        ["${"] = Tags.Brace,
        ["$("] = Tags.Paren,
        ["RawString"] = Tags.String,
        ["String"] = Tags.String,
        ["AnsiCString"] = Tags.String,
        ["VariableName"] = Tags.VariableName,
        ["EnvironmentVariable"] = Tags.VariableName,
        ["Functionname"] = Tags.VariableName,
        ["Comment"] = Tags.Comment,
        ["CommandName"] = Tags.Name,
        ["; &"] = Tags.Separator,
    });

    private static LRParser? _parser;
    public static LRParser Parser => _parser ??= CreateParser();

    private static LRParser CreateParser()
    {
        var spec = BashParserData.MakeSpec(
            propSources: [BashHighlighting]
        );
        return new LRParser(spec);
    }
}
