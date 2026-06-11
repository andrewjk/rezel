using Rezel.Common;
using Rezel.Lr;

namespace Rezel.Grammars;

public static class JsonParserData
{
    public const int Version = 14;

    public const string States = "\"$bOVQPOOOOQO'#Cb'#CbOnQPO'#CeOvQPO'#ClOOQO'#Cr'#CrQOQPOOOOQO'#Cg'#CgO}QPO'#CfO!SQPO'#CtOOQO,59P,59PO![QPO,59PO!aQPO'#CuOOQO,59W,59WO!iQPO,59WOVQPO,59QOqQPO'#CmO!nQPO,59`OOQO1G.k1G.kOVQPO'#CnO!vQPO,59aOOQO1G.r1G.rOOQO1G.l1G.lOOQO,59X,59XOOQO-E6k-E6kOOQO,59Y,59YOOQO-E6l-E6l\"";

    public const string StateData = "\"#O~OeOS~OQSORSOSSOTSOWQO_ROgPO~OVXOgUO~O^[O~PVO[^O~O]_OVhX~OVaO~O]bO^iX~O^dO~O]_OVha~O]bO^ia~O\"";

    public const string Goto = "\"!kjPPPPPPkPPkqwPPPPk{!RPPP!XP!e!hXSOR^bQWQRf_TVQ_Q`WRg`QcZRicQTOQZRQe^RhbRYQR]R\"";

    public const string NodeNames = "⚠ JsonText True False Null Number String } { Object Property PropertyName : , ] [ Array";

    public const int MaxTerm = 25;
    public const int RepeatNodeCount = 2;

    public static readonly string[] NodePropNames = new[] { "isolate", "openedBy", "closedBy" };

    public static NodePropSpec[]? BuildNodeProps()
    {
        var nodeProps = NodeProps.ByName;
        var result = new List<NodePropSpec>();

        if (nodeProps.TryGetValue("isolate", out var isolateProp) && isolateProp is NodeProp<object> isolateObj)
        {
            result.Add(new NodePropSpec(isolateObj, new object[] { -2, 6, 11, "\"\"" }));
        }
        if (nodeProps.TryGetValue("openedBy", out var openedByProp) && openedByProp is NodeProp<object> openedByObj)
        {
            result.Add(new NodePropSpec(openedByObj, new object[] { 7, "\"{\"", 14, "\"[\"" }));
        }
        if (nodeProps.TryGetValue("closedBy", out var closedByProp) && closedByProp is NodeProp<object> closedByObj)
        {
            result.Add(new NodePropSpec(closedByObj, new object[] { 8, "\"}\"", 15, "\"]\"" }));
        }
        return result.Count > 0 ? result.ToArray() : null;
    }

    public static readonly int[] SkippedNodes = [0];

    public const string TokenData = "\"(|~RaXY!WYZ!W]^!Wpq!Wrs!]|}$u}!O$z!Q!R%T!R![&c![!]&t!}#O&y#P#Q'O#Y#Z'T#b#c'r#h#i(Z#o#p(r#q#r(w~!]Oe~~!`Wpq!]qr!]rs!xs#O!]#O#P!}#P;'S!];'S;=`$o<%lO!]~!}Og~~#QXrs!]!P!Q!]#O#P!]#U#V!]#Y#Z!]#b#c!]#f#g!]#h#i!]#i#j#m~#pR!Q![#y!c!i#y#T#Z#y~#|R!Q![$V!c!i$V#T#Z$V~$YR!Q![$c!c!i$c#T#Z$c~$fR!Q![!]!c!i!]#T#Z!]~$rP;=`<%l!]~$zO]~~$}Q!Q!R%T!R![&c~%YRT~!O!P%c!g!h%w#X#Y%w~%fP!Q![%i~%nRT~!Q![%i!g!h%w#X#Y%w~%zR{|&T}!O&T!Q![&Z~&WP!Q![&Z~&`PT~!Q![&Z~&hST~!O!P%c!Q![&c!g!h%w#X#Y%w~&yO[~~'OO_~~'TO^~~'WP#T#U'Z~'^P#`#a'a~'dP#g#h'g~'jP#X#Y'm~'rOR~~'uP#i#j'x~'{P#`#a(O~(RP#`#a(U~(ZOS~~(^P#f#g(a~(dP#i#j(g~(jP#X#Y(m~(rOQ~~(wOW~~(|OV~\"";

    public const int TokenPrec = 0;

    public static readonly Dictionary<string, int[]> TopRules = new Dictionary<string, int[]> { ["JsonText"] = new[] { 0, 1 } };

    public static readonly Dictionary<int, string> TermNames = new Dictionary<int, string> { [19] = "␄", [0] = "⚠", [20] = "%mainskip", [21] = "whitespace", [1] = "@top", [22] = "value", [2] = "True", [3] = "False", [4] = "Null", [5] = "Number", [6] = "String", [23] = "string", [7] = "\"}\"", [8] = "\"{\"", [9] = "Object", [24] = "list<Property>", [10] = "Property", [11] = "PropertyName", [12] = "\":\"", [17] = "(\",\" Property)+", [13] = "\",\"", [14] = "\"]\"", [15] = "\"[\"", [16] = "Array", [25] = "list<value>", [18] = "(\",\" value)+" };

    public static readonly Dictionary<string, int> TermTable = new Dictionary<string, int> { ["JsonText"] = 1, ["True"] = 2, ["False"] = 3, ["Null"] = 4, ["Number"] = 5, ["String"] = 6, ["Object"] = 9, ["Property"] = 10, ["PropertyName"] = 11, ["Array"] = 16 };

    public static LRParserSpec MakeSpec(
        Dictionary<string, ITokenizer>? externals = null,
        NodePropSource[]? propSources = null,
        ContextTracker? context = null)
    {
        var tokenizers = new List<object>();
        tokenizers.Add(0);

        return new LRParserSpec
        {
            Version = Version,
            States = States,
            StateData = StateData,
            Goto = Goto,
            NodeNames = NodeNames,
            MaxTerm = MaxTerm,
            RepeatNodeCount = RepeatNodeCount,
            NodeProps = BuildNodeProps(),
            PropSources = propSources,
            SkippedNodes = SkippedNodes,
            TokenData = TokenData,
            Tokenizers = tokenizers.ToArray(),
            TopRules = TopRules,
            Context = context,
            TokenPrec = TokenPrec,
            TermNames = TermNames
        };
    }
}
