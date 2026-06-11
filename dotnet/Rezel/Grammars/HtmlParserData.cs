using Rezel.Common;
using Rezel.Lr;

namespace Rezel.Grammars;

public static class HtmlParserData
{
    public const int Version = 14;

    public const string States = "\",xOVO!bOOO!ZQ#tO'#CrO!`Q#tO'#C{O!eQ#tO'#DOO!jQ#tO'#DRO!oQ#tO'#DTO!tOOO'#CqO#POOO'#CqO#[OOO'#CqO$kO!bO'#CqOOOO'#Cq'#CqO$rO#tO'#DUO$zQ#tO'#DWO%PQ#tO'#DXOOOO'#Dl'#DlOOOO'#DZ'#DZQVO!bOOO%UQ&jO,59^O%aQ&jO,59gO%lQ&jO,59jO%wQ&jO,59mO&SQ&jO,59oOOOO'#D_'#D_O&_OOO'#CyO&jOOO,59]OOOO'#D`'#D`O&rOOO'#C|O&}OOO,59]OOOO'#Da'#DaO'VOOO'#DPO'bOOO,59]OOOO'#Db'#DbO'jO!bO,59]O'qQ#tO'#DSOOOO,59],59]OOOO'#Dc'#DcO'vO#tO,59pOOOO,59p,59pO(OQ#tO,59rO(TQ#tO,59sOOOO-E7X-E7XO(YQ&jO'#CtOOQO'#D['#D[O(hQ&jO1G.xOOOO1G.x1G.xOOOO1G/Z1G/ZO(sQ&jO1G/ROOOO1G/R1G/RO)OQ&jO1G/UOOOO1G/U1G/UO)ZQ&jO1G/XOOOO1G/X1G/XO)fQ&jO1G/ZOOOO-E7]-E7]O)qQ#tO'#CzOOOO1G.w1G.wOOOO-E7^-E7^O)vQ#tO'#C}OOOO-E7_-E7_O){Q#tO'#DQOOOO-E7`-E7`O*QQ#tO,59nOOOO-E7a-E7aOOOO1G/[1G/[OOOO1G/^1G/^OOOO1G/_1G/_O*VQ,UO,59`OOQO-E7Y-E7YOOOO7+$d7+$dOOOO7+$u7+$uOOOO7+$m7+$mOOOO7+$p7+$pOOOO7+$s7+$sO*bQ#tO,59fO*gQ#tO,59iO*lQ#tO,59lOOOO1G/Y1G/YO*qO7[O'#CwO+SOMhO'#CwOOQO1G.z1G.zOOOO1G/Q1G/QOOOO1G/T1G/TOOOO1G/W1G/WOOOO'#D]'#D]O+eO7[O,59cOOQO,59c,59cOOOO'#D^'#D^O+vOMhO,59cOOOO-E7Z-E7ZOOQO1G.}1G.}OOOO-E7[-E7[\"";

    public const string StateData = "\",b~O!_OS~OUSOVPOWQOXROYTO[]O][O^^O_^Oa^Ob^Oc^Od^Oy^O|_O!eZO~OgaO~OgbO~OgcO~OgdO~OgeO~O!XfOPmP![mP~O!YiOQpP![pP~O!ZlORsP![sP~OUSOVPOWQOXROYTOZqO[]O][O^^O_^Oa^Ob^Oc^Od^Oy^O!eZO~O![rO~P#gO!]sO!fuO~OgvO~OgwO~OS|OT}OiyO~OS!POT}OiyO~OS!ROT}OiyO~OS!TOT}OiyO~OS}OT}OiyO~O!XfOPmX![mX~OP!WO![!XO~O!YiOQpX![pX~OQ!ZO![!XO~O!ZlORsX![sX~OR!]O![!XO~O![!XO~P#gOg!_O~O!]sO!f!aO~OS!bO~OS!cO~Oj!dOShXThXihX~OS!fOT!gOiyO~OS!hOT!gOiyO~OS!iOT!gOiyO~OS!jOT!gOiyO~OS!gOT!gOiyO~Og!kO~Og!lO~Og!mO~OS!nO~Ol!qO!a!oO!c!pO~OS!rO~OS!sO~OS!tO~Ob!uOc!uOd!uO!a!wO!b!uO~Ob!xOc!xOd!xO!c!wO!d!xO~Ob!uOc!uOd!uO!a!{O!b!uO~Ob!xOc!xOd!xO!c!{O!d!xO~OT~cbd!ey|~\"";

    public const string Goto = "\"%q!aPPPPPPPPPPPPPPPPPPPPP!b!hP!nPP!zP!}#Q#T#Z#^#a#g#j#m#s#y!bP!b!bP$P$V$m$s$y%P%V%]%cPPPPPPPP%iX^OX`pXUOX`pezabcde{!O!Q!S!UR!q!dRhUR!XhXVOX`pRkVR!XkXWOX`pRnWR!XnXXOX`pQrXR!XpXYOX`pQ`ORx`Q{aQ!ObQ!QcQ!SdQ!UeZ!e{!O!Q!S!UQ!v!oR!z!vQ!y!pR!|!yQgUR!VgQjVR!YjQmWR![mQpXR!^pQtZR!`tS_O`ToXp\"";

    public const string NodeNames = "⚠ StartCloseTag StartCloseTag StartCloseTag EndTag SelfClosingEndTag StartTag StartTag StartTag StartTag StartTag StartCloseTag StartCloseTag StartCloseTag IncompleteTag IncompleteCloseTag Document Text EntityReference CharacterReference InvalidEntity Element OpenTag TagName Attribute AttributeName Is AttributeValue UnquotedAttributeValue ScriptText CloseTag OpenTag StyleText CloseTag OpenTag TextareaText CloseTag OpenTag CloseTag SelfClosingTag Comment ProcessingInst MismatchedCloseTag CloseTag DoctypeDecl";

    public const int MaxTerm = 68;
    public const int RepeatNodeCount = 9;

    public static readonly string[] NodePropNames = new[] { "closedBy", "openedBy", "group", "isolate" };

    public static NodePropSpec[]? BuildNodeProps()
    {
        var nodeProps = NodeProps.ByName;
        var result = new List<NodePropSpec>();

        if (nodeProps.TryGetValue("closedBy", out var closedByProp) && closedByProp is NodeProp<object> closedByObj)
        {
            result.Add(new NodePropSpec(closedByObj, new object[] { -10, 1, 2, 3, 7, 8, 9, 10, 11, 12, 13, "\"EndTag\"", 6, "\"EndTag SelfClosingEndTag\"", -4, 22, 31, 34, 37, "\"CloseTag\"" }));
        }
        if (nodeProps.TryGetValue("openedBy", out var openedByProp) && openedByProp is NodeProp<object> openedByObj)
        {
            result.Add(new NodePropSpec(openedByObj, new object[] { 4, "\"StartTag StartCloseTag\"", 5, "\"StartTag\"", -4, 30, 33, 36, 38, "\"OpenTag\"" }));
        }
        if (nodeProps.TryGetValue("group", out var groupProp) && groupProp is NodeProp<object> groupObj)
        {
            result.Add(new NodePropSpec(groupObj, new object[] { -10, 14, 15, 18, 19, 20, 21, 40, 41, 42, 43, "\"Entity\"", 17, "\"Entity TextContent\"", -3, 29, 32, 35, "\"TextContent Entity\"" }));
        }
        if (nodeProps.TryGetValue("isolate", out var isolateProp) && isolateProp is NodeProp<object> isolateObj)
        {
            result.Add(new NodePropSpec(isolateObj, new object[] { -11, 22, 30, 31, 33, 34, 36, 37, 38, 39, 42, 43, "\"ltr\"", -3, 27, 28, 40, "\"\"" }));
        }
        return result.Count > 0 ? result.ToArray() : null;
    }

    public static readonly int[] SkippedNodes = [0];

    public const string TokenData = "\"!<p!aR!YOX$qXY,QYZ,QZ[$q[]&X]^,Q^p$qpq,Qqr-_rs3_sv-_vw3}wxHYx}-_}!OH{!O!P-_!P!Q$q!Q![-_![!]Mz!]!^-_!^!_!$S!_!`!;x!`!a&X!a!c-_!c!}Mz!}#R-_#R#SMz#S#T1k#T#oMz#o#s-_#s$f$q$f%W-_%W%oMz%o%p-_%p&aMz&a&b-_&b1pMz1p4U-_4U4dMz4d4e-_4e$ISMz$IS$I`-_$I`$IbMz$Ib$Kh-_$Kh%#tMz%#t&/x-_&/x&EtMz&Et&FV-_&FV;'SMz;'S;:j!#|;:j;=`3X<%l?&r-_?&r?AhMz?Ah?BY$q?BY?MnMz?MnO$q!a$|caP!b`!dplWOX$qXZ&XZ[$q[^&X^p$qpq&Xqr$qrs&}sv$qvw+Pwx(tx!^$q!^!_*V!_!a&X!a#S$q#S#T&X#T;'S$q;'S;=`+z<%lO$q!a&bXaP!b`!dpOr&Xrs&}sv&Xwx(tx!^&X!^!_*V!_;'S&X;'S;=`*y<%lO&X!a'UVaP!dpOv&}wx'kx!^&}!^!_(V!_;'S&};'S;=`(n<%lO&}!a'pTaPOv'kw!^'k!_;'S'k;'S;=`(P<%lO'k!a(SP;=`<%l'k!a([S!dpOv(Vx;'S(V;'S;=`(h<%lO(V!a(kP;=`<%l(V!a(qP;=`<%l&}!a({WaP!b`Or(trs'ksv(tw!^(t!^!_)e!_;'S(t;'S;=`*P<%lO(t!a)jT!b`Or)esv)ew;'S)e;'S;=`)y<%lO)e!a)|P;=`<%l)e!a*SP;=`<%l(t!a*^V!b`!dpOr*Vrs(Vsv*Vwx)ex;'S*V;'S;=`*s<%lO*V!a*vP;=`<%l*V!a*|P;=`<%l&X!a+UYlWOX+PZ[+P^p+Pqr+Psw+Px!^+P!a#S+P#T;'S+P;'S;=`+t<%lO+P!a+wP;=`<%l+P!a+}P;=`<%l$q!a,]`!_^aP!b`!dpOX&XXY,QYZ,QZ]&X]^,Q^p&Xpq,Qqr&Xrs&}sv&Xwx(tx!^&X!^!_*V!_;'S&X;'S;=`*y<%lO&X!a-ljaPiS!b`!dplWOX$qXZ&XZ[$q[^&X^p$qpq&Xqr-_rs&}sv-_vw/^wx(tx!P-_!P!Q$q!Q!^-_!^!_*V!_!a&X!a#S-_#S#T1k#T#s-_#s$f$q$f;'S-_;'S;=`3X<%l?Ah-_?Ah?BY$q?BY?Mn-_?MnO$q!a/ebiSlWOX+PZ[+P^p+Pqr/^sw/^x!P/^!P!Q+P!Q!^/^!a#S/^#S#T0m#T#s/^#s$f+P$f;'S/^;'S;=`1e<%l?Ah/^?Ah?BY+P?BY?Mn/^?MnO+P!a0rXiSqr0msw0mx!P0m!Q!^0m!a#s0m$f;'S0m;'S;=`1_<%l?Ah0m?BY?Mn0m!a1bP;=`<%l0m!a1hP;=`<%l/^!a1vcaPiS!b`!dpOq&Xqr1krs&}sv1kvw0mwx(tx!P1k!P!Q&X!Q!^1k!^!_*V!_!a&X!a#s1k#s$f&X$f;'S1k;'S;=`3R<%l?Ah1k?Ah?BY&X?BY?Mn1k?MnO&X!a3UP;=`<%l1k!a3[P;=`<%l-_!a3hVaP!ah!dpOv&}wx'kx!^&}!^!_(V!_;'S&};'S;=`(n<%lO&}!a4WiiSlWd!ROX5uXZ7SZ[5u[^7S^p5uqr8trs7Sst>]tw8twx7Sx!P8t!P!Q5u!Q!]8t!]!^/^!^!a7S!a#S8t#S#T;{#T#s8t#s$f5u$f;'S8t;'S;=`>V<%l?Ah8t?Ah?BY5u?BY?Mn8t?MnO5u!a5zblWOX5uXZ7SZ[5u[^7S^p5uqr5urs7Sst+Ptw5uwx7Sx!]5u!]!^7w!^!a7S!a#S5u#S#T7S#T;'S5u;'S;=`8n<%lO5u!a7VVOp7Sqs7St!]7S!]!^7l!^;'S7S;'S;=`7q<%lO7S!a7qOb!R!a7tP;=`<%l7S!a8OYlWb!ROX+PZ[+P^p+Pqr+Psw+Px!^+P!a#S+P#T;'S+P;'S;=`+t<%lO+P!a8qP;=`<%l5u!a8{iiSlWOX5uXZ7SZ[5u[^7S^p5uqr8trs7Sst/^tw8twx7Sx!P8t!P!Q5u!Q!]8t!]!^:j!^!a7S!a#S8t#S#T;{#T#s8t#s$f5u$f;'S8t;'S;=`>V<%l?Ah8t?Ah?BY5u?BY?Mn8t?MnO5u!a:sbiSlWb!ROX+PZ[+P^p+Pqr/^sw/^x!P/^!P!Q+P!Q!^/^!a#S/^#S#T0m#T#s/^#s$f+P$f;'S/^;'S;=`1e<%l?Ah/^?Ah?BY+P?BY?Mn/^?MnO+P!a<QciSOp7Sqr;{rs7Sst0mtw;{wx7Sx!P;{!P!Q7S!Q!];{!]!^=]!^!a7S!a#s;{#s$f7S$f;'S;{;'S;=`>P<%l?Ah;{?Ah?BY7S?BY?Mn;{?MnO7S!a=dXiSb!Rqr0msw0mx!P0m!Q!^0m!a#s0m$f;'S0m;'S;=`1_<%l?Ah0m?BY?Mn0m!a>SP;=`<%l;{!a>YP;=`<%l8t!a>dhiSlWOX@OXZAYZ[@O[^AY^p@OqrBwrsAYswBwwxAYx!PBw!P!Q@O!Q!]Bw!]!^/^!^!aAY!a#SBw#S#TE{#T#sBw#s$f@O$f;'SBw;'S;=`HS<%l?AhBw?Ah?BY@O?BY?MnBw?MnO@O!a@TalWOX@OXZAYZ[@O[^AY^p@Oqr@OrsAYsw@OwxAYx!]@O!]!^Az!^!aAY!a#S@O#S#TAY#T;'S@O;'S;=`Bq<%lO@O!aA]UOpAYq!]AY!]!^Ao!^;'SAY;'S;=`At<%lOAY!aAtOc!R!aAwP;=`<%lAY!aBRYlWc!ROX+PZ[+P^p+Pqr+Psw+Px!^+P!a#S+P#T;'S+P;'S;=`+t<%lO+P!aBtP;=`<%l@O!aCOhiSlWOX@OXZAYZ[@O[^AY^p@OqrBwrsAYswBwwxAYx!PBw!P!Q@O!Q!]Bw!]!^Dj!^!aAY!a#SBw#S#TE{#T#sBw#s$f@O$f;'SBw;'S;=`HS<%l?AhBw?Ah?BY@O?BY?MnBw?MnO@O!aDsbiSlWc!ROX+PZ[+P^p+Pqr/^sw/^x!P/^!P!Q+P!Q!^/^!a#S/^#S#T0m#T#s/^#s$f+P$f;'S/^;'S;=`1e<%l?Ah/^?Ah?BY+P?BY?Mn/^?MnO+P!aFQbiSOpAYqrE{rsAYswE{wxAYx!PE{!P!QAY!Q!]E{!]!^GY!^!aAY!a#sE{#s$fAY$f;'SE{;'S;=`G|<%l?AhE{?Ah?BYAY?BY?MnE{?MnOAY!aGaXiSc!Rqr0msw0mx!P0m!Q!^0m!a#s0m$f;'S0m;'S;=`1_<%l?Ah0m?BY?Mn0m!aHPP;=`<%lE{!aHVP;=`<%lBw!aHcWaP!b`!cxOr(trs'ksv(tw!^(t!^!_)e!_;'S(t;'S;=`*P<%lO(t!aIYlaPiS!b`!dplWOX$qXZ&XZ[$q[^&X^p$qpq&Xqr-_rs&}sv-_vw/^wx(tx}-_}!OKQ!O!P-_!P!Q$q!Q!^-_!^!_*V!_!a&X!a#S-_#S#T1k#T#s-_#s$f$q$f;'S-_;'S;=`3X<%l?Ah-_?Ah?BY$q?BY?Mn-_?MnO$q!aK_kaPiS!b`!dplWOX$qXZ&XZ[$q[^&X^p$qpq&Xqr-_rs&}sv-_vw/^wx(tx!P-_!P!Q$q!Q!^-_!^!_*V!_!`&X!`!aMS!a#S-_#S#T1k#T#s-_#s$f$q$f;'S-_;'S;=`3X<%l?Ah-_?Ah?BY$q?BY?Mn-_?MnO$q!aM_XaP!b`!dp!fQOr&Xrs&}sv&Xwx(tx!^&X!^!_*V!_;'S&X;'S;=`*y<%lO&X!aNZ!ZaPgQiS!b`!dplWOX$qXZ&XZ[$q[^&X^p$qpq&Xqr-_rs&}sv-_vw/^wx(tx}-_}!OMz!O!PMz!P!Q$q!Q![Mz![!]Mz!]!^-_!^!_*V!_!a&X!a!c-_!c!}Mz!}#R-_#R#SMz#S#T1k#T#oMz#o#s-_#s$f$q$f$}-_$}%OMz%O%W-_%W%oMz%o%p-_%p&aMz&a&b-_&b1pMz1p4UMz4U4dMz4d4e-_4e$ISMz$IS$I`-_$I`$IbMz$Ib$Je-_$Je$JgMz$Jg$Kh-_$Kh%#tMz%#t&/x-_&/x&EtMz&Et&FV-_&FV;'SMz;'S;:j!#|;:j;=`3X<%l?&r-_?&r?AhMz?Ah?BY$q?BY?MnMz?MnO$q!a!$PP;=`<%lMz!a!$ZY!b`!dpOq*Vqr!$yrs(Vsv*Vwx)ex!a*V!a!b!4t!b;'S*V;'S;=`*s<%lO*V!a!%Q]!b`!dpOr*Vrs(Vsv*Vwx)ex}*V}!O!%y!O!f*V!f!g!']!g#W*V#W#X!0`#X;'S*V;'S;=`*s<%lO*V!a!&QX!b`!dpOr*Vrs(Vsv*Vwx)ex}*V}!O!&m!O;'S*V;'S;=`*s<%lO*V!a!&vV!b`!dp!ePOr*Vrs(Vsv*Vwx)ex;'S*V;'S;=`*s<%lO*V!a!'dX!b`!dpOr*Vrs(Vsv*Vwx)ex!q*V!q!r!(P!r;'S*V;'S;=`*s<%lO*V!a!(WX!b`!dpOr*Vrs(Vsv*Vwx)ex!e*V!e!f!(s!f;'S*V;'S;=`*s<%lO*V!a!(zX!b`!dpOr*Vrs(Vsv*Vwx)ex!v*V!v!w!)g!w;'S*V;'S;=`*s<%lO*V!a!)nX!b`!dpOr*Vrs(Vsv*Vwx)ex!{*V!{!|!*Z!|;'S*V;'S;=`*s<%lO*V!a!*bX!b`!dpOr*Vrs(Vsv*Vwx)ex!r*V!r!s!*}!s;'S*V;'S;=`*s<%lO*V!a!+UX!b`!dpOr*Vrs(Vsv*Vwx)ex!g*V!g!h!+q!h;'S*V;'S;=`*s<%lO*V!a!+xY!b`!dpOr!+qrs!,hsv!+qvw!-Swx!.[x!`!+q!`!a!/j!a;'S!+q;'S;=`!0Y<%lO!+q!a!,mV!dpOv!,hvx!-Sx!`!,h!`!a!-q!a;'S!,h;'S;=`!.U<%lO!,h!a!-VTO!`!-S!`!a!-f!a;'S!-S;'S;=`!-k<%lO!-S!a!-kO|P!a!-nP;=`<%l!-S!a!-xS!dp|POv(Vx;'S(V;'S;=`(h<%lO(V!a!.XP;=`<%l!,h!a!.aX!b`Or!.[rs!-Ssv!.[vw!-Sw!`!.[!`!a!.|!a;'S!.[;'S;=`!/d<%lO!.[!a!/TT!b`|POr)esv)ew;'S)e;'S;=`)y<%lO)e!a!/gP;=`<%l!.[!a!/sV!b`!dp|POr*Vrs(Vsv*Vwx)ex;'S*V;'S;=`*s<%lO*V!a!0]P;=`<%l!+q!a!0gX!b`!dpOr*Vrs(Vsv*Vwx)ex#c*V#c#d!1S#d;'S*V;'S;=`*s<%lO*V!a!1ZX!b`!dpOr*Vrs(Vsv*Vwx)ex#V*V#V#W!1v#W;'S*V;'S;=`*s<%lO*V!a!1}X!b`!dpOr*Vrs(Vsv*Vwx)ex#h*V#h#i!2j#i;'S*V;'S;=`*s<%lO*V!a!2qX!b`!dpOr*Vrs(Vsv*Vwx)ex#m*V#m#n!3^#n;'S*V;'S;=`*s<%lO*V!a!3eX!b`!dpOr*Vrs(Vsv*Vwx)ex#d*V#d#e!4Q#e;'S*V;'S;=`*s<%lO*V!a!4XX!b`!dpOr*Vrs(Vsv*Vwx)ex#X*V#X#Y!+q#Y;'S*V;'S;=`*s<%lO*V!a!4{Y!b`!dpOr!4trs!5ksv!4tvw!6Vwx!8]x!a!4t!a!b!:]!b;'S!4t;'S;=`!;r<%lO!4t!a!5pV!dpOv!5kvx!6Vx!a!5k!a!b!7W!b;'S!5k;'S;=`!8V<%lO!5k!a!6YTO!a!6V!a!b!6i!b;'S!6V;'S;=`!7Q<%lO!6V!a!6lTO!`!6V!`!a!6{!a;'S!6V;'S;=`!7Q<%lO!6V!a!7QOyP!a!7TP;=`<%l!6V!a!7]V!dpOv!5kvx!6Vx!`!5k!`!a!7r!a;'S!5k;'S;=`!8V<%lO!5k!a!7yS!dpyPOv(Vx;'S(V;'S;=`(h<%lO(V!a!8YP;=`<%l!5k!a!8bX!b`Or!8]rs!6Vsv!8]vw!6Vw!a!8]!a!b!8}!b;'S!8];'S;=`!:V<%lO!8]!a!9SX!b`Or!8]rs!6Vsv!8]vw!6Vw!`!8]!`!a!9o!a;'S!8];'S;=`!:V<%lO!8]!a!9vT!b`yPOr)esv)ew;'S)e;'S;=`)y<%lO)e!a!:YP;=`<%l!8]!a!:dY!b`!dpOr!4trs!5ksv!4tvw!6Vwx!8]x!`!4t!`!a!;S!a;'S!4t;'S;=`!;r<%lO!4t!a!;]V!b`!dpyPOr*Vrs(Vsv*Vwx)ex;'S*V;'S;=`*s<%lO*V!a!;uP;=`<%l!4t!a!<TXaPjS!b`!dpOr&Xrs&}sv&Xwx(tx!^&X!^!_*V!_;'S&X;'S;=`*y<%lO&X\"";

    public const int TokenPrec = 517;

    public static readonly Dictionary<string, int> Dialects = new Dictionary<string, int> { ["noMatch"] = 0, ["selfClosing"] = 515 };

    public static readonly Dictionary<string, int[]> TopRules = new Dictionary<string, int[]> { ["Document"] = new[] { 0, 16 } };

    public static readonly Dictionary<int, string> TermNames = new Dictionary<int, string> { [54] = "␄", [0] = "⚠", [55] = "scriptText", [1] = "StartCloseScriptTag", [56] = "styleText", [2] = "StartCloseStyleTag", [57] = "textareaText", [3] = "StartCloseTextareaTag", [4] = "EndTag", [5] = "SelfClosingEndTag", [6] = "StartTag", [7] = "StartScriptTag", [8] = "StartStyleTag", [9] = "StartTextareaTag", [10] = "StartSelfClosingTag", [11] = "StartCloseTag", [12] = "NoMatchStartCloseTag", [13] = "MismatchedStartCloseTag", [58] = "missingCloseTag", [14] = "IncompleteTag", [15] = "IncompleteCloseTag", [59] = "commentContent", [60] = "%skip", [61] = "space", [16] = "@top", [45] = "(entity | DoctypeDecl)+", [62] = "entity", [17] = "Text", [18] = "EntityReference", [19] = "CharacterReference", [20] = "InvalidEntity", [21] = "Element", [22] = "OpenScriptTag", [23] = "TagName", [46] = "Attribute+", [24] = "Attribute", [25] = "AttributeName", [26] = "Is", [27] = "AttributeValue", [63] = "\"\\u0022\"", [47] = "(attributeContentDouble | EntityReference | CharacterReference | InvalidEntity)+", [64] = "attributeContentDouble", [65] = "\"\\u0027\"", [48] = "(attributeContentSingle | EntityReference | CharacterReference | InvalidEntity)+", [66] = "attributeContentSingle", [28] = "UnquotedAttributeValue", [29] = "ScriptText", [49] = "scriptText+", [30] = "CloseScriptTag", [31] = "OpenStyleTag", [32] = "StyleText", [50] = "styleText+", [33] = "CloseStyleTag", [34] = "OpenTextareaTag", [35] = "TextareaText", [51] = "textareaText+", [36] = "CloseTextareaTag", [37] = "OpenTag", [52] = "entity+", [38] = "CloseTag", [39] = "SelfClosingTag", [40] = "Comment", [67] = "commentStart", [53] = "commentContent+", [68] = "commentEnd", [41] = "ProcessingInst", [42] = "MismatchedCloseTag", [43] = "NoMatchCloseTag", [44] = "DoctypeDecl" };

    public static readonly Dictionary<string, int> TermTable = new Dictionary<string, int> { ["scriptText"] = 55, ["StartCloseScriptTag"] = 1, ["styleText"] = 56, ["StartCloseStyleTag"] = 2, ["textareaText"] = 57, ["StartCloseTextareaTag"] = 3, ["EndTag"] = 4, ["SelfClosingEndTag"] = 5, ["StartTag"] = 6, ["StartScriptTag"] = 7, ["StartStyleTag"] = 8, ["StartTextareaTag"] = 9, ["StartSelfClosingTag"] = 10, ["StartCloseTag"] = 11, ["NoMatchStartCloseTag"] = 12, ["MismatchedStartCloseTag"] = 13, ["missingCloseTag"] = 58, ["IncompleteTag"] = 14, ["IncompleteCloseTag"] = 15, ["commentContent"] = 59, ["Document"] = 16, ["Text"] = 17, ["EntityReference"] = 18, ["CharacterReference"] = 19, ["InvalidEntity"] = 20, ["Element"] = 21, ["OpenScriptTag"] = 22, ["TagName"] = 23, ["Attribute"] = 24, ["AttributeName"] = 25, ["Is"] = 26, ["AttributeValue"] = 27, ["UnquotedAttributeValue"] = 28, ["ScriptText"] = 29, ["CloseScriptTag"] = 30, ["OpenStyleTag"] = 31, ["StyleText"] = 32, ["CloseStyleTag"] = 33, ["OpenTextareaTag"] = 34, ["TextareaText"] = 35, ["CloseTextareaTag"] = 36, ["OpenTag"] = 37, ["CloseTag"] = 38, ["SelfClosingTag"] = 39, ["Comment"] = 40, ["ProcessingInst"] = 41, ["MismatchedCloseTag"] = 42, ["NoMatchCloseTag"] = 43, ["DoctypeDecl"] = 44 };

    public static LRParserSpec MakeSpec(
        Dictionary<string, ITokenizer>? externals = null,
        NodePropSource[]? propSources = null,
        ContextTracker? context = null)
    {
        var tokenizers = new List<object>();
        tokenizers.Add(externals?["scriptTokens"]!);
        tokenizers.Add(externals?["styleTokens"]!);
        tokenizers.Add(externals?["textareaTokens"]!);
        tokenizers.Add(externals?["endTag"]!);
        tokenizers.Add(externals?["tagStart"]!);
        tokenizers.Add(externals?["commentContent"]!);
        tokenizers.Add(0);
        tokenizers.Add(1);
        tokenizers.Add(2);
        tokenizers.Add(3);
        tokenizers.Add(4);
        tokenizers.Add(5);

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
            Dialects = Dialects,
            TokenPrec = TokenPrec,
            TermNames = TermNames
        };
    }
}
