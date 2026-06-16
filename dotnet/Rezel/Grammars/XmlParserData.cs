using Rezel.Common;
using Rezel.Lr;

namespace Rezel.Grammars;

public static class XmlParserData
{
    public const int Version = 14;

    public const string States = "\",lOQOaOOOrOxO'#CfOzOpO'#CiO!tOaO'#CgOOOP'#Cg'#CgO!{OrO'#CrO#TOtO'#CsO#]OpO'#CtOOOP'#DT'#DTOOOP'#Cv'#CvQQOaOOOOOW'#Cw'#CwO#eOxO,59QOOOP,59Q,59QOOOO'#Cx'#CxO#mOpO,59TO#uO!bO,59TOOOP'#C|'#C|O$TOaO,59RO$[OpO'#CoOOOP,59R,59ROOOQ'#C}'#C}O$dOrO,59^OOOP,59^,59^OOOS'#DO'#DOO$lOtO,59_OOOP,59_,59_O$tOpO,59`O$|OpO,59`OOOP-E6t-E6tOOOW-E6u-E6uOOOP1G.l1G.lOOOO-E6v-E6vO%UO!bO1G.oO%UO!bO1G.oO%dOpO'#CkO%lO!bO'#CyO%zO!bO1G.oOOOP1G.o1G.oOOOP1G.w1G.wOOOP-E6z-E6zOOOP1G.m1G.mO&VOpO,59ZO&_OpO,59ZOOOQ-E6{-E6{OOOP1G.x1G.xOOOS-E6|-E6|OOOP1G.y1G.yO&gOpO1G.zO&gOpO1G.zOOOP1G.z1G.zO&oO!bO7+$ZO&}O!bO7+$ZOOOP7+$Z7+$ZOOOP7+$c7+$cO'YOpO,59VO'bOpO,59VO'mO!bO,59eOOOO-E6w-E6wO'{OpO1G.uO'{OpO1G.uOOOP1G.u1G.uO(TOpO7+$fOOOP7+$f7+$fO(]O!bO<<GuOOOP<<Gu<<GuOOOP<<G}<<G}O'bOpO1G.qO'bOpO1G.qO(hO#tO'#CnO(vO&jO'#CnOOOO1G.q1G.qO)UOpO7+$aOOOP7+$a7+$aOOOP<<HQ<<HQOOOPAN=aAN=aOOOPAN=iAN=iO'bOpO7+$]OOOO7+$]7+$]OOOO'#Cz'#CzO)^O#tO,59YOOOO,59Y,59YOOOO'#C{'#C{O)lO&jO,59YOOOP<<G{<<G{OOOO<<Gw<<GwOOOO-E6x-E6xOOOO1G.t1G.tOOOO-E6y-E6y\"";

    public const string StateData = "\")z~OPQOSVOTWOVWOWWOXWOiXOyPO!QTO!SUO~OvZOx]O~O^`Oz^O~OPQOQcOSVOTWOVWOWWOXWOyPO!QTO!SUO~ORdO~P!SOteO!PgO~OuhO!RjO~O^lOz^O~OvZOxoO~O^qOz^O~O[vO`sOdwOz^O~ORyO~P!SO^{Oz^O~OteO!P}O~OuhO!R!PO~O^!QOz^O~O[!SOz^O~O[!VO`sOd!WOz^O~Oa!YOz^O~Oz^O[mX`mXdmX~O[!VO`sOd!WO~O^!]Oz^O~O[!_Oz^O~O[!aOz^O~O[!cO`sOd!dOz^O~O[!cO`sOd!dO~Oa!eOz^O~Oz^O{!gO}!hO~Oz^O[ma`madma~O[!kOz^O~O[!lOz^O~O[!mO`sOd!nO~OW!qOX!qO{!sO|!qO~OW!tOX!tO}!sO!O!tO~O[!vOz^O~OW!qOX!qO{!yO|!qO~OW!tOX!tO}!yO!O!tO~O\"";

    public const string Goto = "\"%cxPPPPPPPPPPyyP!PP!VPP!`!jP!pyyyP!v!|#S$[$k$q$w$}%TPPPP%ZXWORYbXRORYb_t`qru!T!U!bQ!i!YS!p!e!fR!w!oQdRRybXSORYbQYORmYQ[PRn[Q_QQkVjp_krz!R!T!X!Z!^!`!f!j!oQr`QzcQ!RlQ!TqQ!XsQ!ZtQ!^{Q!`!QQ!f!YQ!j!]R!o!eQu`S!UqrU![u!U!bR!b!TQ!r!gR!x!rQ!u!hR!z!uQbRRxbQfTR|fQiUR!OiSXOYTaRb\"";

    public const string NodeNames = "⚠ StartTag StartCloseTag MissingCloseTag StartCloseTag StartCloseTag Document Text EntityReference CharacterReference Cdata Element EndTag OpenTag TagName Attribute AttributeName Is AttributeValue CloseTag SelfCloseEndTag SelfClosingTag Comment ProcessingInst MismatchedCloseTag DoctypeDecl";

    public const int MaxTerm = 50;
    public const int RepeatNodeCount = 9;

    public static readonly string[] NodePropNames = new[] { "closedBy", "openedBy", "isolate" };

    public static NodePropSpec[]? BuildNodeProps()
    {
        var nodeProps = NodeProps.ByName;
        var result = new List<NodePropSpec>();

        if (nodeProps.TryGetValue("closedBy", out var closedByProp))
        {
            result.Add(new NodePropSpec(closedByProp, new object[] { 1, "SelfCloseEndTag EndTag", 13, "CloseTag MissingCloseTag" }));
        }
        if (nodeProps.TryGetValue("openedBy", out var openedByProp))
        {
            result.Add(new NodePropSpec(openedByProp, new object[] { 12, "StartTag StartCloseTag", 19, "OpenTag", 20, "StartTag" }));
        }
        if (nodeProps.TryGetValue("isolate", out var isolateProp))
        {
            result.Add(new NodePropSpec(isolateProp, new object[] { -6, 13, 18, 19, 21, 22, 24, "" }));
        }
        return result.Count > 0 ? result.ToArray() : null;
    }

    public static readonly int[] SkippedNodes = [0];

    public const string TokenData = "\"!)v~R!YOX$qXY)iYZ)iZ]$q]^)i^p$qpq)iqr$qrs*vsv$qvw+fwx/ix}$q}!O0[!O!P$q!P!Q2z!Q![$q![!]4n!]!^$q!^!_8U!_!`!#t!`!a!$l!a!b!%d!b!c$q!c!}4n!}#P$q#P#Q!'W#Q#R$q#R#S4n#S#T$q#T#o4n#o%W$q%W%o4n%o%p$q%p&a4n&a&b$q&b1p4n1p4U$q4U4d4n4d4e$q4e$IS4n$IS$I`$q$I`$Ib4n$Ib$Kh$q$Kh%#t4n%#t&/x$q&/x&Et4n&Et&FV$q&FV;'S4n;'S;:j8O;:j;=`)c<%l?&r$q?&r?Ah4n?Ah?BY$q?BY?Mn4n?MnO$qi$zXVP|W!O`Or$qrs%gsv$qwx'^x!^$q!^!_(o!_;'S$q;'S;=`)c<%lO$qa%nVVP!O`Ov%gwx&Tx!^%g!^!_&o!_;'S%g;'S;=`'W<%lO%gP&YTVPOv&Tw!^&T!_;'S&T;'S;=`&i<%lO&TP&lP;=`<%l&T`&tS!O`Ov&ox;'S&o;'S;=`'Q<%lO&o`'TP;=`<%l&oa'ZP;=`<%l%gX'eWVP|WOr'^rs&Tsv'^w!^'^!^!_'}!_;'S'^;'S;=`(i<%lO'^W(ST|WOr'}sv'}w;'S'};'S;=`(c<%lO'}W(fP;=`<%l'}X(lP;=`<%l'^h(vV|W!O`Or(ors&osv(owx'}x;'S(o;'S;=`)]<%lO(oh)`P;=`<%l(oi)fP;=`<%l$qo)t`VPzU|W!O`OX$qXY)iYZ)iZ]$q]^)i^p$qpq)iqr$qrs%gsv$qwx'^x!^$q!^!_(o!_;'S$q;'S;=`)c<%lO$qk+PVVP{Y!O`Ov%gwx&Tx!^%g!^!_&o!_;'S%g;'S;=`'W<%lO%g~+iast,n![!]-r!c!}-r#R#S-r#T#o-r%W%o-r%p&a-r&b1p-r4U4d-r4e$IS-r$I`$Ib-r$Kh%#t-r&/x&Et-r&FV;'S-r;'S;:j/c?&r?Ah-r?BY?Mn-r~,qQ!Q![,w#l#m-V~,zQ!Q![,w!]!^-Q~-VOX~~-YR!Q![-c!c!i-c#T#Z-c~-fS!Q![-c!]!^-Q!c!i-c#T#Z-c~-ug}!O-r!O!P-r!Q![-r![!]-r!]!^/^!c!}-r#R#S-r#T#o-r$}%O-r%W%o-r%p&a-r&b1p-r1p4U-r4U4d-r4e$IS-r$I`$Ib-r$Je$Jg-r$Kh%#t-r&/x&Et-r&FV;'S-r;'S;:j/c?&r?Ah-r?BY?Mn-r~/cOW~~/fP;=`<%l-rk/rWVP|W}bOr'^rs&Tsv'^w!^'^!^!_'}!_;'S'^;'S;=`(i<%lO'^k0eZVP|W!O`Or$qrs%gsv$qwx'^x}$q}!O1W!O!^$q!^!_(o!_;'S$q;'S;=`)c<%lO$qk1aZVP|W!O`Or$qrs%gsv$qwx'^x!^$q!^!_(o!_!`$q!`!a2S!a;'S$q;'S;=`)c<%lO$qk2_XVP|W!O`!PQOr$qrs%gsv$qwx'^x!^$q!^!_(o!_;'S$q;'S;=`)c<%lO$qm3TZVP|W!O`Or$qrs%gsv$qwx'^x!^$q!^!_(o!_!`$q!`!a3v!a;'S$q;'S;=`)c<%lO$qm4RXVP|W!O`dSOr$qrs%gsv$qwx'^x!^$q!^!_(o!_;'S$q;'S;=`)c<%lO$qo4{!PVP^Q`S|W!O`Or$qrs%gsv$qwx'^x}$q}!O4n!O!P4n!P!Q$q!Q![4n![!]4n!]!^$q!^!_(o!_!c$q!c!}4n!}#R$q#R#S4n#S#T$q#T#o4n#o$}$q$}%O4n%O%W$q%W%o4n%o%p$q%p&a4n&a&b$q&b1p4n1p4U4n4U4d4n4d4e$q4e$IS4n$IS$I`$q$I`$Ib4n$Ib$Je$q$Je$Jg4n$Jg$Kh$q$Kh%#t4n%#t&/x$q&/x&Et4n&Et&FV$q&FV;'S4n;'S;:j8O;:j;=`)c<%l?&r$q?&r?Ah4n?Ah?BY$q?BY?Mn4n?MnO$qo8RP;=`<%l4ni8]Y|W!O`Oq(oqr8{rs&osv(owx'}x!a(o!a!b!#U!b;'S(o;'S;=`)]<%lO(oi9S_|W!O`Or(ors&osv(owx'}x}(o}!O:R!O!f(o!f!g;e!g!}(o!}#ODh#O#W(o#W#XLp#X;'S(o;'S;=`)]<%lO(oi:YX|W!O`Or(ors&osv(owx'}x}(o}!O:u!O;'S(o;'S;=`)]<%lO(oi;OV|W!O`!QPOr(ors&osv(owx'}x;'S(o;'S;=`)]<%lO(oi;lX|W!O`Or(ors&osv(owx'}x!q(o!q!r<X!r;'S(o;'S;=`)]<%lO(oi<`X|W!O`Or(ors&osv(owx'}x!e(o!e!f<{!f;'S(o;'S;=`)]<%lO(oi=SX|W!O`Or(ors&osv(owx'}x!v(o!v!w=o!w;'S(o;'S;=`)]<%lO(oi=vX|W!O`Or(ors&osv(owx'}x!{(o!{!|>c!|;'S(o;'S;=`)]<%lO(oi>jX|W!O`Or(ors&osv(owx'}x!r(o!r!s?V!s;'S(o;'S;=`)]<%lO(oi?^X|W!O`Or(ors&osv(owx'}x!g(o!g!h?y!h;'S(o;'S;=`)]<%lO(oi@QY|W!O`Or?yrs@psv?yvwA[wxBdx!`?y!`!aCr!a;'S?y;'S;=`Db<%lO?ya@uV!O`Ov@pvxA[x!`@p!`!aAy!a;'S@p;'S;=`B^<%lO@pPA_TO!`A[!`!aAn!a;'SA[;'S;=`As<%lOA[PAsOiPPAvP;=`<%lA[aBQS!O`iPOv&ox;'S&o;'S;=`'Q<%lO&oaBaP;=`<%l@pXBiX|WOrBdrsA[svBdvwA[w!`Bd!`!aCU!a;'SBd;'S;=`Cl<%lOBdXC]T|WiPOr'}sv'}w;'S'};'S;=`(c<%lO'}XCoP;=`<%lBdiC{V|W!O`iPOr(ors&osv(owx'}x;'S(o;'S;=`)]<%lO(oiDeP;=`<%l?yiDoZ|W!O`Or(ors&osv(owx'}x!e(o!e!fEb!f#V(o#V#WIr#W;'S(o;'S;=`)]<%lO(oiEiX|W!O`Or(ors&osv(owx'}x!f(o!f!gFU!g;'S(o;'S;=`)]<%lO(oiF]X|W!O`Or(ors&osv(owx'}x!c(o!c!dFx!d;'S(o;'S;=`)]<%lO(oiGPX|W!O`Or(ors&osv(owx'}x!v(o!v!wGl!w;'S(o;'S;=`)]<%lO(oiGsX|W!O`Or(ors&osv(owx'}x!c(o!c!dH`!d;'S(o;'S;=`)]<%lO(oiHgX|W!O`Or(ors&osv(owx'}x!}(o!}#OIS#O;'S(o;'S;=`)]<%lO(oiI]VyP|W!O`Or(ors&osv(owx'}x;'S(o;'S;=`)]<%lO(oiIyX|W!O`Or(ors&osv(owx'}x#W(o#W#XJf#X;'S(o;'S;=`)]<%lO(oiJmX|W!O`Or(ors&osv(owx'}x#T(o#T#UKY#U;'S(o;'S;=`)]<%lO(oiKaX|W!O`Or(ors&osv(owx'}x#h(o#h#iK|#i;'S(o;'S;=`)]<%lO(oiLTX|W!O`Or(ors&osv(owx'}x#T(o#T#UH`#U;'S(o;'S;=`)]<%lO(oiLwX|W!O`Or(ors&osv(owx'}x#c(o#c#dMd#d;'S(o;'S;=`)]<%lO(oiMkX|W!O`Or(ors&osv(owx'}x#V(o#V#WNW#W;'S(o;'S;=`)]<%lO(oiN_X|W!O`Or(ors&osv(owx'}x#h(o#h#iNz#i;'S(o;'S;=`)]<%lO(oi! RX|W!O`Or(ors&osv(owx'}x#m(o#m#n! n#n;'S(o;'S;=`)]<%lO(oi! uX|W!O`Or(ors&osv(owx'}x#d(o#d#e!!b#e;'S(o;'S;=`)]<%lO(oi!!iX|W!O`Or(ors&osv(owx'}x#X(o#X#Y?y#Y;'S(o;'S;=`)]<%lO(oi!#_V|W!O`!SPOr(ors&osv(owx'}x;'S(o;'S;=`)]<%lO(ok!$PXVPaQ|W!O`Or$qrs%gsv$qwx'^x!^$q!^!_(o!_;'S$q;'S;=`)c<%lO$qo!$wXVP[U|W!O`Or$qrs%gsv$qwx'^x!^$q!^!_(o!_;'S$q;'S;=`)c<%lO$qk!%mZVP|W!O`Or$qrs%gsv$qwx'^x!^$q!^!_(o!_!`$q!`!a!&`!a;'S$q;'S;=`)c<%lO$qk!&kXVP|W!O`!RQOr$qrs%gsv$qwx'^x!^$q!^!_(o!_;'S$q;'S;=`)c<%lO$qk!'aZVP|W!O`Or$qrs%gsv$qwx'^x!^$q!^!_(o!_#P$q#P#Q!(S#Q;'S$q;'S;=`)c<%lO$qk!(]ZVP|W!O`Or$qrs%gsv$qwx'^x!^$q!^!_(o!_!`$q!`!a!)O!a;'S$q;'S;=`)c<%lO$qk!)ZXVPxQ|W!O`Or$qrs%gsv$qwx'^x!^$q!^!_(o!_;'S$q;'S;=`)c<%lO$q\"";

    public const int TokenPrec = 0;

    public static readonly Dictionary<string, int[]> TopRules = new Dictionary<string, int[]> { ["Document"] = new[] { 0, 6 } };

    public static readonly Dictionary<int, string> TermNames = new Dictionary<int, string> { [35] = "␄", [0] = "⚠", [1] = "StartTag", [2] = "StartCloseTag", [3] = "MissingCloseTag", [4] = "mismatchedStartCloseTag", [5] = "incompleteStartCloseTag", [36] = "commentContent", [37] = "piContent", [38] = "cdataContent", [6] = "@top", [26] = "(entity | DoctypeDecl)+", [39] = "entity", [7] = "Text", [8] = "EntityReference", [9] = "CharacterReference", [40] = "\"]]\\u003E\"", [10] = "Cdata", [41] = "cdataStart", [27] = "cdataContent+", [11] = "Element", [12] = "EndTag", [13] = "OpenTag", [28] = "space+", [42] = "space", [14] = "TagName", [29] = "(Attribute space*)+", [15] = "Attribute", [16] = "AttributeName", [17] = "Is", [18] = "AttributeValue", [43] = "\"\\u0022\"", [30] = "(attributeContentDouble | EntityReference | CharacterReference)+", [44] = "attributeContentDouble", [45] = "\"\\u0027\"", [31] = "(attributeContentSingle | EntityReference | CharacterReference)+", [46] = "attributeContentSingle", [32] = "entity+", [19] = "CloseTag", [20] = "SelfCloseEndTag", [21] = "SelfClosingTag", [47] = "\"--\\u003E\"", [22] = "Comment", [48] = "\"\\u003C!--\"", [33] = "commentContent+", [49] = "\"?\\u003E\"", [23] = "ProcessingInst", [50] = "\"\\u003C?\"", [34] = "piContent+", [24] = "MismatchedCloseTag", [25] = "DoctypeDecl" };

    public static readonly Dictionary<string, int> TermTable = new Dictionary<string, int> { ["StartTag"] = 1, ["StartCloseTag"] = 2, ["MissingCloseTag"] = 3, ["mismatchedStartCloseTag"] = 4, ["incompleteStartCloseTag"] = 5, ["commentContent"] = 36, ["piContent"] = 37, ["cdataContent"] = 38, ["Document"] = 6, ["Text"] = 7, ["EntityReference"] = 8, ["CharacterReference"] = 9, ["Cdata"] = 10, ["Element"] = 11, ["EndTag"] = 12, ["OpenTag"] = 13, ["TagName"] = 14, ["Attribute"] = 15, ["AttributeName"] = 16, ["Is"] = 17, ["AttributeValue"] = 18, ["CloseTag"] = 19, ["SelfCloseEndTag"] = 20, ["SelfClosingTag"] = 21, ["Comment"] = 22, ["ProcessingInst"] = 23, ["MismatchedCloseTag"] = 24, ["DoctypeDecl"] = 25 };

    public static LRParserSpec MakeSpec(
        Dictionary<string, ITokenizer>? externals = null,
        NodePropSource[]? propSources = null,
        ContextTracker? context = null)
    {
        var tokenizers = new List<object>();
        tokenizers.Add(externals?["startTag"]!);
        tokenizers.Add(externals?["commentContent"]!);
        tokenizers.Add(externals?["piContent"]!);
        tokenizers.Add(externals?["cdataContent"]!);
        tokenizers.Add(0);
        tokenizers.Add(1);
        tokenizers.Add(2);
        tokenizers.Add(3);
        tokenizers.Add(4);

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
