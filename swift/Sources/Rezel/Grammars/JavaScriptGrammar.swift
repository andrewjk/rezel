import Foundation

let jsGrammarText = #"""
@dialects { jsx, ts }

@precedence {
  typeargs,
  typeMember,
  typePrefix,
  intersectionPrefixed @left,
  intersection @left,
  unionPrefixed @left,
  union @left,
  typeExtends @right,
  else @right,
  member,
  readonly,
  newArgs,
  call,
  instantiate,
  taggedTemplate,
  prefix,
  postfix,
  typeof,
  exp @left,
  times @left,
  plus @left,
  shift @left,
  loop,
  rel @left,
  satisfies,
  equal @left,
  bitAnd @left,
  bitXor @left,
  bitOr @left,
  and @left,
  or @left,
  ternary @right,
  assign @right,
  comma @left,
  statement @cut,
  predicate
}

@top Script { Hashbang? statement* }

@top SingleExpression { expression }

@top SingleClassItem { classItem }

statement[@isGroup=Statement] {
  ExportDeclaration |
  ImportDeclaration |
  ForStatement { kw<"for"> ckw<"await">? (ForSpec | ForInSpec | ForOfSpec) statement } |
  WhileStatement { kw<"while"> ParenthesizedExpression statement } |
  WithStatement { kw<"with"> ParenthesizedExpression statement } |
  DoStatement { kw<"do"> statement kw<"while"> ParenthesizedExpression semi } |
  IfStatement { kw<"if"> ParenthesizedExpression statement (!else kw<"else"> statement)? } |
  SwitchStatement { kw<"switch"> ParenthesizedExpression SwitchBody { "{" switchItem* "}" } } |
  TryStatement {
    kw<"try"> Block
    CatchClause { kw<"catch"> ("(" pattern ")")? Block }?
    FinallyClause { kw<"finally"> Block }?
  } |
  ReturnStatement { kw<"return"> (noSemi expression)? semi } |
  ThrowStatement { kw<"throw"> expression semi } |
  BreakStatement { kw<"break"> (noSemi Label)? semi } |
  ContinueStatement { kw<"continue"> (noSemi Label)? semi } |
  DebuggerStatement { kw<"debugger"> semi } |
  Block |
  LabeledStatement { Label ":" statement } |
  declaration |
  ExpressionStatement { expression semi } |
  ";"
}

ExportDeclaration {
  kw<"export"> Star (ckw<"as"> (VariableName | String))? ckw<"from"> String semi |
  kw<"export"> kw<"default"> (FunctionDeclaration | ClassDeclaration | expression semi) |
  kw<"export"> tskw<"type">? declaration |
  kw<"export"> tskw<"type">? ExportGroup (ckw<"from"> String)? semi |
  kw<"export"> "=" expression semi
}

ExportGroup {
  "{" commaSep<(VariableName | String | kw<"default">) (ckw<"as"> (VariableName { word } | String))?> "}"
}

ImportDeclaration {
  kw<"import"> ckw<"defer">? tskw<"type">? (Star ckw<"as"> VariableDefinition | commaSep<VariableDefinition | ImportGroup>)
    ckw<"from"> String semi |
  kw<"import"> ckw<"defer">? String semi
}

ImportGroup {
  "{" commaSep<tskw<"type">? (VariableDefinition | (VariableName | String | kw<"default">) ckw<"as"> VariableDefinition)> "}"
}

ForSpec {
  "("
  (VariableDeclaration | expression ";" | ";") expression? ";" expression?
  ")"
}

forXSpec<op> {
  "("
  (variableDeclarationKeyword pattern | VariableName | MemberExpression | ArrayPattern | ObjectPattern)
  !loop op expression
  ")"
}

ForInSpec { forXSpec<kw<"in">> }
ForOfSpec { forXSpec<ckw<"of">> }

declaration {
  FunctionDeclaration |
  ClassDeclaration |
  VariableDeclaration |
  TypeAliasDeclaration |
  InterfaceDeclaration |
  EnumDeclaration |
  NamespaceDeclaration |
  AmbientDeclaration
}

FunctionDeclaration {
  async? !statement kw<"function"> Star? VariableDefinition? functionSignature (Block | semi)
}

ClassDeclaration {
  !statement Decorator* tskw<"abstract">? kw<"class"> VariableDefinition TypeParamList?
  (kw<"extends"> ((VariableName | MemberExpression) !typeargs TypeArgList | expression))?
  (tskw<"implements"> commaSep1<type>)?
  ClassBody
}

classItem { MethodDeclaration | PropertyDeclaration | StaticBlock | ";" }

ClassBody { "{" classItem* "}" }

privacy {
  @extend[@name=Privacy,@dialect=ts]<word, "public" | "private" | "protected">
}

privacyArg {
  @extend[@name=Privacy,@dialect=ts]<identifier, "public" | "private" | "protected">
}

propModifier {
  Decorator |
  tsPkwMod<"declare"> |
  privacy |
  pkwMod<"static"> |
  tsPkwMod<"abstract"> |
  tsPkwMod<"override">
}

classPropName { propName | PrivatePropertyDefinition }

MethodDeclaration[group=ClassItem] {
  propModifier*
  pkwMod<"async">?
  (pkwMod<"get"> | pkwMod<"set"> | Star)?
  classPropName
  functionSignature
  (Block | semi)
}

StaticBlock[group=ClassItem] {
  pkwMod<"static"> Block
}

PropertyDeclaration[group=ClassItem] {
  propModifier*
  (tsPkwMod<"readonly"> | pkwMod<"accessor">)?
  classPropName
  (Optional | LogicOp<"!">)?
  TypeAnnotation?
  ("=" expressionNoComma)?
  semi
}

variableDeclarationKeyword {
  kw<"let"> | kw<"var"> | kw<"const"> | ckw<"await">? ckw<"using">
}

VariableDeclaration {
  variableDeclarationKeyword commaSep1<patternAssignTyped> semi
}

TypeAliasDeclaration {
  tskw<"type"> TypeDefinition TypeParamList? "=" type semi
}

InterfaceDeclaration {
  tskw<"interface"> TypeDefinition TypeParamList? (kw<"extends"> commaSep1<type>)? ObjectType
}

EnumDeclaration {
  kw<"const">? tskw<"enum"> TypeDefinition EnumBody { "{" commaSep<PropertyName ("=" expressionNoComma)?> "}" }
}

NamespaceDeclaration {
  (tskw<"namespace"> | tskw<"module">) VariableDefinition ("." PropertyDefinition)* Block
}

AmbientDeclaration {
  tskw<"declare"> (
    VariableDeclaration |
    TypeAliasDeclaration |
    EnumDeclaration |
    InterfaceDeclaration |
    NamespaceDeclaration |
    GlobalDeclaration { tskw<"global"> Block } |
    ClassDeclaration {
      tskw<"abstract">? kw<"class"> VariableDefinition TypeParamList?
      (kw<"extends"> expression)?
      (tskw<"implements"> commaSep1<type>)?
      ClassBody { "{" (
        MethodDeclaration |
        PropertyDeclaration |
        IndexSignature semi
      )* "}" }
    } |
    AmbientFunctionDeclaration {
      async? kw<"function"> Star? VariableDefinition? TypeParamList? ParamList (TypeAnnotation | TypePredicate) semi
    }
  )
}

decoratorExpression {
  VariableName |
  MemberExpression { decoratorExpression !member ("." | questionDot) (PropertyName | PrivatePropertyName) } |
  CallExpression { decoratorExpression !call TypeArgList? questionDot? ArgList } |
  ParenthesizedExpression
}

Decorator { "@" decoratorExpression }

pattern { VariableDefinition | ArrayPattern | ObjectPattern }

ArrayPattern { "[" commaSep<("..."? patternAssign)?> ~destructure "]" }

ObjectPattern { "{" commaSep<PatternProperty> ~destructure "}" }

patternAssign {
  pattern ("=" expressionNoComma)?
}

TypeAnnotation { ":" type }

TypePredicate {
  ":" (
     tskw<"asserts"> (VariableName | kw<"this">) !predicate (tskw<"is"> type)? |
     (VariableName | kw<"this">) !predicate tskw<"is"> type
  )
}

patternAssignTyped {
  pattern Optional? TypeAnnotation? ("=" expressionNoComma)?
}

ParamList {
  "(" commaSep<"..." patternAssignTyped | Decorator* privacyArg? tskw<"readonly">? patternAssignTyped | kw<"this"> TypeAnnotation> ")"
}

Block {
  !statement "{" statement* "}"
}

switchItem {
  CaseLabel { kw<"case"> expression ":" } |
  DefaultLabel { kw<"default"> ":" } |
  statement
}

expression[@isGroup=Expression] {
  expressionNoComma | SequenceExpression
}

SequenceExpression {
  expressionNoComma !comma ("," expressionNoComma)+
}

expressionNoComma {
  Number |
  String |
  TemplateString |
  VariableName |
  boolean |
  kw<"this"> |
  kw<"null"> |
  kw<"super"> |
  RegExp |
  ArrayExpression |
  ObjectExpression { "{" commaSep<Property> ~destructure "}" } |
  NewTarget { kw<"new"> "." PropertyName } |
  NewExpression { kw<"new"> expressionNoComma (!newArgs ArgList)? } |
  UnaryExpression |
  YieldExpression |
  AwaitExpression |
  ParenthesizedExpression |
  ClassExpression |
  FunctionExpression |
  ArrowFunction |
  MemberExpression |
  BinaryExpression |
  ConditionalExpression { expressionNoComma !ternary questionOp expressionNoComma LogicOp<":"> expressionNoComma } |
  AssignmentExpression |
  PostfixExpression { expressionNoComma !postfix (incdec | LogicOp<"!">) } |
  CallExpression { expressionNoComma !call questionDot? ArgList } |
  InstantiationExpression { (VariableName | MemberExpression) !instantiate TypeArgList } |
  TaggedTemplateExpression { expressionNoComma !taggedTemplate TemplateString } |
  DynamicImport { kw<"import"> "(" expressionNoComma ")" } |
  ImportMeta { kw<"import"> "." PropertyName } |
  JSXElement |
  PrefixCast { tsAngleOpen (type | kw<"const">) ~tsAngle ">" expressionNoComma } |
  ArrowFunction[@dynamicPrecedence=1] {
    TypeParamList { tsAngleOpen commaSep<typeParam> ">" } ParamList TypeAnnotation? "=>" (Block | expressionNoComma)
  }
}

ParenthesizedExpression { "(" expression ")" }

ArrayExpression {
  "[" commaSep1<"..."? expressionNoComma | ""> ~destructure "]"
}

propName { PropertyDefinition | "[" expression "]" ~destructure | Number ~destructure | String ~destructure }

Property {
  pkwMod<"async">? (pkwMod<"get"> | pkwMod<"set"> | Star)? propName functionSignature Block |
  propName ~destructure (":" expressionNoComma)? |
  "..." expressionNoComma
}

PatternProperty {
  "..." patternAssign |
  ((PropertyName | Number | String) ~destructure (":" pattern)? |
   ("[" expression "]" ~destructure ":" pattern)) ("=" expressionNoComma)?
}

ClassExpression {
  kw<"class"> VariableDefinition? (kw<"extends"> expression)? ClassBody
}

functionSignature { TypeParamList? ParamList (TypeAnnotation | TypePredicate)? }

FunctionExpression {
  async? kw<"function"> Star? VariableDefinition? functionSignature Block
}

YieldExpression[@dynamicPrecedence=1] {
  !prefix ckw<"yield"> Star? expressionNoComma
}

AwaitExpression[@dynamicPrecedence=1] {
  !prefix ckw<"await"> expressionNoComma
}

UnaryExpression {
  !prefix (kw<"void"> | kw<"typeof"> | kw<"delete"> |
           LogicOp<"!"> | BitOp<"~"> | incdec | incdecPrefix | plusMin)
  expressionNoComma
}

BinaryExpression {
  expressionNoComma !exp ArithOp<"**"> expressionNoComma |
  expressionNoComma !times (divide | ArithOp<"%"> | ArithOp<"*">) expressionNoComma |
  expressionNoComma !plus plusMin expressionNoComma |
  expressionNoComma !shift BitOp<">>" ">"? | "<<"> expressionNoComma |
  expressionNoComma !rel (LessThan | CompareOp<"<=" | ">" "="?> | kw<"instanceof">) expressionNoComma |
  expressionNoComma !satisfies tskw<"satisfies"> type |
  (expressionNoComma | PrivatePropertyName) !rel ~tsIn kw<"in"> expressionNoComma |
  expressionNoComma !rel ckw<"as"> (kw<"const"> | type) |
  expressionNoComma !rel tskw<"satisfies"> type |
  expressionNoComma !equal CompareOp<"==" "="? | "!=" "="?> expressionNoComma |
  expressionNoComma !bitOr BitOp { "|" } expressionNoComma |
  expressionNoComma !bitXor BitOp<"^"> expressionNoComma |
  expressionNoComma !bitAnd BitOp { "&" } expressionNoComma |
  expressionNoComma !and LogicOp<"&&"> expressionNoComma |
  expressionNoComma !or LogicOp<"||" | "??"> expressionNoComma
}

AssignmentExpression {
  (VariableName | MemberExpression) !assign UpdateOp<($[+\-/%^] | "*" "*"? | "|" "|"? | "&" "&"? | "<<" | ">>" ">"? | "??") "=">
    expressionNoComma |
  (VariableName | MemberExpression | ArrayPattern | ObjectPattern) !assign "=" expressionNoComma
}

MemberExpression {
  expressionNoComma !member (("." | questionDot) (PropertyName | PrivatePropertyName) | questionDot? "[" expression "]")
}

ArgList {
  "(" commaSep<"..."? expressionNoComma> ")"
}

ArrowFunction {
  async? (ParamList { VariableDefinition } | ParamList TypeAnnotation?) "=>" (Block | expressionNoComma)
}

TypeArgList[@dynamicPrecedence=1] {
  @extend[@dialect=ts,@name="<"]<LessThan, "<"> commaSep<type> ">"
}

TypeParamList {
  "<" commaSep<typeParam> ">"
}

typeParam { (kw<"in"> | tskw<"out"> | kw<"const">)? TypeDefinition ~tsAngle (kw<"extends"> type)? ("=" type)? }

typeofExpression {
  MemberExpression { typeofExpression !member (("." | questionDot) PropertyName | "[" expression "]") } |
  InstantiationExpression { typeofExpression !instantiate TypeArgList } |
  VariableName
}

type[@isGroup=Type] {
  ThisType { kw<"this"> } |
  LiteralType {
   plusMin? Number |
   boolean |
   String
  } |
  TemplateType |
  NullType { kw<"null"> } |
  VoidType { kw<"void"> } |
  TypeofType { kw<"typeof"> typeofExpression } |
  KeyofType { !typePrefix tskw<"keyof"> type } |
  UniqueType { !typePrefix tskw<"unique"> type } |
  ImportType { kw<"import"> "(" String ")" } |
  InferredType { tskw<"infer"> TypeName } |
  ParenthesizedType { "(" type ")" } |
  FunctionSignature { TypeParamList? ParamTypeList "=>" type } |
  NewSignature { kw<"new"> ParamTypeList "=>" type } |
  IndexedType |
  TupleType { "[" commaSep<(Label ":")? type | "..." type> ~destructure "]" } |
  ArrayType { type noSemiType "[" "]" } |
  ReadonlyType { tskw<"readonly"> !readonly type } |
  ObjectType |
  UnionType {
    type (!union unionOp type)+ |
    unionOp type (!unionPrefixed unionOp type)*
  } |
  IntersectionType {
    type (!intersection intersectionOp type)+ |
    intersectionOp type (!intersectionPrefixed intersectionOp type)*
  } |
  ConditionalType { type !typeExtends kw<"extends"> type questionOp ~arrow type LogicOp<":"> type } |
  ParameterizedType { (TypeName | IndexedType) !typeargs TypeArgList } |
  TypeName
}

IndexedType {
  type !typeMember ("." TypeName | noSemiType "[" type "]")+
}

ObjectType {
  "{" (
    (MethodType |
     PropertyType |
     IndexSignature |
     CallSignature { ParamTypeList (TypeAnnotation | TypePredicate) } |
     NewSignature[@dynamicPrecedence=1] { @extend[@name=new]<word, "new"> ParamTypeList TypeAnnotation })
    ("," | semi)
  )* ~destructure "}"
}

IndexSignature {
  (plusMin? tsPkwMod<"readonly">)?
  "[" PropertyDefinition { identifier } (TypeAnnotation | ~tsIn kw<"in"> type (ckw<"as"> type)?) "]"
  (plusMin? Optional)?
  TypeAnnotation
}

MethodType {
  pkwMod<"async">?
  (pkwMod<"get"> | pkwMod<"set"> | Star)?
  propName
  (plusMin? Optional)?
  functionSignature
}

PropertyType {
  (plusMin? tsPkwMod<"readonly">)?
  propName
  (plusMin? Optional)?
  TypeAnnotation
}

ParamTypeList[@name=ParamList] {
  "(" commaSep<"..."? pattern ~arrow Optional? ~arrow TypeAnnotation? | kw<"this"> TypeAnnotation> ")"
}

@skip {} {
  TemplateString[isolate] {
    templateStart (templateEscape | templateContent | templateExpr)* templateEnd
  }

  TemplateType[isolate] {
    templateStart (templateContent | templateType)* templateEnd
  }

  String[isolate] {
    '"' (stringContentDouble | Escape)* ('"' | "\n") |
    "'" (stringContentSingle | Escape)* ("'" | "\n")
  }

  BlockComment[isolate] { "/*" (blockCommentContent | blockCommentNewline)* blockCommentEnd }
}

templateExpr[@name=Interpolation,isolate] { InterpolationStart expression? InterpolationEnd }

templateType[@name=Interpolation,isolate] { InterpolationStart type? InterpolationEnd }

@skip {} {
  JSXElement {
    JSXSelfClosingTag |
    (JSXOpenTag | JSXFragmentTag) (JSXText | JSXElement | JSXEscape)* JSXCloseTag
  }
}

JSXSelfClosingTag { JSXStartTag jsxElementName jsxAttribute* JSXSelfCloseEndTag }

JSXOpenTag { JSXStartTag jsxElementName jsxAttribute* JSXEndTag }

JSXFragmentTag { JSXStartTag JSXEndTag }

JSXCloseTag { JSXStartCloseTag jsxElementName? JSXEndTag }

jsxElementName {
  JSXIdentifier |
  JSXBuiltin { JSXLowerIdentifier } |
  JSXNamespacedName |
  JSXMemberExpression
}

JSXMemberExpression { (JSXMemberExpression | JSXIdentifier | JSXLowerIdentifier) "." (JSXIdentifier | JSXLowerIdentifier) }

JSXNamespacedName { (JSXIdentifier | JSXNamespacedName | JSXLowerIdentifier) ":" (JSXIdentifier | JSXLowerIdentifier) }

jsxAttribute {
  JSXSpreadAttribute { "{" "..." expression "}" } |
  JSXAttribute { (JSXIdentifier | JSXNamespacedName | JSXLowerIdentifier) ("=" jsxAttributeValue)? }
}

jsxAttributeValue {
  JSXAttributeValue |
  JSXEscape { "{" expression "}" } |
  JSXElement
}

JSXEscape { "{" "..."? expression "}" }

commaSep<content> {
  "" | content ("," content?)*
}

commaSep1<content> {
  content ("," content)*
}

kw<term> { @specialize[@name={term}]<identifier, term> }

ckw<term> { @extend[@name={term}]<identifier, term> }

tskw<term> { @extend[@name={term},@dialect=ts]<identifier, term> }

async { @extend[@name=async]<identifier, "async"> }

pkwMod<term> { @extend[@name={term}]<word, term> }

tsPkwMod<term> { @extend[@name={term},@dialect=ts]<word, term> }

semi { ";" | insertSemi }

boolean { @specialize[@name=BooleanLiteral]<identifier, "true" | "false"> }

Star { "*" }

VariableName { identifier ~arrow }

VariableDefinition { identifier ~arrow }

TypeDefinition { identifier }

TypeName { identifier ~arrow }

Label { identifier }

PropertyName { word ~propName }

PropertyDefinition { word ~propName }

PrivatePropertyName { privateIdentifier }

PrivatePropertyDefinition { privateIdentifier }

Optional { "?" }

questionOp[@name=LogicOp] { "?" }

unionOp[@name=LogicOp] { "|" }

plusMin { ArithOp<"+" | "-"> }

intersectionOp[@name=LogicOp] { "&" }

@skip { spaces | newline | LineComment | BlockComment }

@context trackNewline from "./tokens.js"

@external tokens noSemicolon from "./tokens" { noSemi }

@external tokens noSemicolonType from "./tokens" { noSemiType }

@external tokens operatorToken from "./tokens" {
 incdec[@name=ArithOp],
 incdecPrefix[@name=ArithOp]
 questionDot[@name="?."]
}

@external tokens jsx from "./tokens" { JSXStartTag }

@local tokens {
  InterpolationStart[closedBy=InterpolationEnd] { "${" }
  templateEnd { "`" }
  templateEscape[@name=Escape] { Escape }
  @else templateContent
}

@local tokens {
  blockCommentEnd { "*/" }
  blockCommentNewline { "\n" }
  @else blockCommentContent
}

@tokens {
  spaces[@export] { $[\u0009 \u000b\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000\ufeff]+ }
  newline[@export] { $[\r\n\u2028\u2029] }

  LineComment[isolate] { "//" ![\n]* }

  Hashbang { "#!" ![\n]* }

  divide[@name=ArithOp] { "/" }

  @precedence { "/*", LineComment, divide }

  @precedence { "/*", LineComment, RegExp }

  identifierChar { @asciiLetter | $[_$\u{a1}-\u{10ffff}] }

  word { identifierChar (identifierChar | @digit)* }

  identifier { word }

  privateIdentifier { "#" word }

  @precedence { spaces, newline, identifier }

  @precedence { spaces, newline, JSXIdentifier, JSXLowerIdentifier }

  @precedence { spaces, newline, word }

  hex { @digit | $[a-fA-F] }

  Number {
    (@digit ("_" | @digit)* ("." ("_" | @digit)*)? | "." @digit ("_" | @digit)*)
      (("e" | "E") ("+" | "-")? ("_" | @digit)+)? |
    @digit ("_" | @digit)* "n" |
    "0x" (hex | "_")+ "n"? |
    "0b" $[01_]+ "n"? |
    "0o" $[0-7_]+ "n"?
  }

  @precedence { Number "." }

  Escape {
    "\\" ("x" hex hex | "u" ("{" hex+ "}" | hex hex hex hex) | ![xu])
  }

  stringContentSingle { ![\\\n']+ }

  stringContentDouble { ![\\\n"]+ }

  templateStart { "`" }

  InterpolationEnd[openedBy=InterpolationStart] { "}" }

  ArithOp<expr> { expr }
  LogicOp<expr> { expr }
  BitOp<expr> { expr }
  CompareOp<expr> { expr }
  UpdateOp<expr> { expr }

  @precedence { "*", ArithOp }

  RegExp[isolate] { "/" (![/\\\n[] | "\\" ![\n] | "[" (![\n\\\]] | "\\" ![\n])* "]")+ ("/" $[dgimsuvy]*)? }

  LessThan[@name=CompareOp] { "<" }

  "="[@name=Equals]
  "..."[@name=Spread]
  "=>"[@name=Arrow]

  "(" ")" "[" "]" "{" "}" "<" ">"

  "." "," ";" ":" "@"

  JSXIdentifier { $[A-Z_$\u{a1}-\u{10ffff}] (identifierChar | @digit | "-")* }
  JSXLowerIdentifier[@name=JSXIdentifier] { $[a-z] (identifierChar | @digit | "-")* }

  JSXAttributeValue { '"' !["]* '"' | "'" ![']* "'" }

  JSXStartCloseTag { "</" }

  JSXEndTag { ">" }

  JSXSelfCloseEndTag { "/>" }

  JSXText { ![<{]+ }

  tsAngleOpen[@dialect=ts,@name="<"] { "<" }
}

@external tokens insertSemicolon from "./tokens" { insertSemi }

@external propSource jsHighlight from "./highlight"

@detectDelim
"""#

private let space: [Int] = [9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200,
                            8201, 8202, 8232, 8233, 8239, 8287, 12288]

private let braceR = 125
private let semicolon = 59
private let slash = 47
private let star = 42
private let plus = 43
private let minus = 45
private let lt = 60
private let comma = 44
private let question = 63
private let dot = 46
private let bracketL = 91

nonisolated(unsafe) let jsTrackNewline = ContextTracker(
	start: false as Any,
	shift: { context, term, stack, _ in
		let name = stack.parser.termNames?[term] ?? ""
		if name == "LineComment" || name == "BlockComment" || name == "spaces" {
			return context
		}
		return (name == "newline") as Any
	},
	strict: false
)

func makeJsExternalTokenizer(name: String, terms: [String: Int]) -> TokenizerProtocol {
	if name == "insertSemicolon" {
		let insertSemi = terms["insertSemi"]!
		return ExternalTokenizer({ input, stack in
			let next = input.next
			if next == braceR || next == -1 || (stack.context as? Bool == true) {
				input.acceptToken(insertSemi)
			}
		}, contextual: true, fallback: true)
	}

	if name == "noSemicolon" {
		let noSemi = terms["noSemi"]!
		return ExternalTokenizer({ input, stack in
			let next = input.next
			if space.contains(next) { return }
			if next == slash {
				let after = input.peek(1)
				if after == slash || after == star { return }
			}
			if next != braceR, next != semicolon, next != -1, !(stack.context as? Bool == true) {
				input.acceptToken(noSemi)
			}
		}, contextual: true)
	}

	if name == "noSemicolonType" {
		let noSemiType = terms["noSemiType"]!
		return ExternalTokenizer({ input, stack in
			if input.next == bracketL, !(stack.context as? Bool == true) {
				input.acceptToken(noSemiType)
			}
		}, contextual: true)
	}

	if name == "operatorToken" {
		let incdec = terms["incdec"]!
		let incdecPrefix = terms["incdecPrefix"]!
		let questionDot = terms["questionDot"]!
		return ExternalTokenizer({ input, stack in
			let next = input.next
			if next == plus || next == minus {
				input.advance()
				if next == input.next {
					input.advance()
					let mayPostfix = !(stack.context as? Bool == true) && stack.canShift(incdec)
					input.acceptToken(mayPostfix ? incdec : incdecPrefix)
				}
			} else if next == question, input.peek(1) == dot {
				input.advance()
				input.advance()
				if input.next < 48 || input.next > 57 {
					input.acceptToken(questionDot)
				}
			}
		}, contextual: true)
	}

	if name == "jsx" {
		let JSXStartTag = terms["JSXStartTag"]!
		return ExternalTokenizer({ input, stack in
			if input.next != lt { return }
			let parser = stack.parser
			let keys = Array(parser.dialects.keys)
			let jsxIdx = keys.firstIndex(of: "jsx")
			if let jsxIdx = jsxIdx {
				if !stack.dialectEnabled(jsxIdx) { return }
			} else {
				return
			}
			input.advance()
			if input.next == slash { return }
			var back = 0
			while space.contains(input.next) {
				input.advance(); back += 1
			}
			if jsIdentifierChar(input.next, true) {
				input.advance()
				back += 1
				while jsIdentifierChar(input.next, false) {
					input.advance(); back += 1
				}
				while space.contains(input.next) {
					input.advance(); back += 1
				}
				if input.next == comma { return }
				let extendsStr = "extends"
				let extendsScalars = Array(extendsStr.unicodeScalars)
				for i in 0...extendsStr.count {
					if i == extendsStr.count {
						if !jsIdentifierChar(input.next, true) { return }
						break
					}
					if input.next != Int(extendsScalars[i].value) { break }
					input.advance()
					back += 1
				}
			}
			input.acceptToken(JSXStartTag, endOffset: -back)
		}, contextual: true)
	}

	fatalError("Unknown JS external tokenizer: \(name)")
}

private func jsIdentifierChar(_ ch: Int, _ start: Bool) -> Bool {
	return (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch == 95 || ch >= 192 ||
		(!start && ch >= 48 && ch <= 57)
}

private nonisolated(unsafe) let definition = hlTags["definition"] as! (Tag) -> Tag
private nonisolated(unsafe) let functionMod = hlTags["function"] as! (Tag) -> Tag
private nonisolated(unsafe) let specialMod = hlTags["special"] as! (Tag) -> Tag
private nonisolated(unsafe) let standardMod = hlTags["standard"] as! (Tag) -> Tag

nonisolated(unsafe) let jsHighlighting = styleTags([
	"get set async static": hlTags["modifier"] as Any,
	"for while do if else switch try catch finally return throw break continue default case defer": hlTags["controlKeyword"] as Any,
	"in of await yield void typeof delete instanceof as satisfies": hlTags["operatorKeyword"] as Any,
	"let var const using function class extends": hlTags["definitionKeyword"] as Any,
	"import export from": hlTags["moduleKeyword"] as Any,
	"with debugger new": hlKeyword,
	"TemplateString": specialMod(hlString),
	"super": hlTags["atom"] as Any,
	"BooleanLiteral": hlTags["bool"] as Any,
	"this": hlTags["self"] as Any,
	"null": hlTags["null"] as Any,
	"Star": hlTags["modifier"] as Any,
	"VariableName": hlTags["variableName"] as Any,
	"CallExpression/VariableName TaggedTemplateExpression/VariableName": functionMod(hlTags["variableName"] as! Tag),
	"VariableDefinition": definition(hlTags["variableName"] as! Tag),
	"Label": hlTags["labelName"] as Any,
	"PropertyName": hlPropertyName,
	"PrivatePropertyName": specialMod(hlPropertyName),
	"CallExpression/MemberExpression/PropertyName": functionMod(hlPropertyName),
	"FunctionDeclaration/VariableDefinition": functionMod(definition(hlTags["variableName"] as! Tag)),
	"ClassDeclaration/VariableDefinition": definition(hlTags["className"] as! Tag),
	"NewExpression/VariableName": hlTags["className"] as Any,
	"PropertyDefinition": definition(hlPropertyName),
	"PrivatePropertyDefinition": definition(specialMod(hlPropertyName)),
	"UpdateOp": hlTags["updateOperator"] as Any,
	"LineComment Hashbang": hlTags["lineComment"] as Any,
	"BlockComment": hlTags["blockComment"] as Any,
	"Number": hlNumber,
	"String": hlString,
	"Escape": hlTags["escape"] as Any,
	"ArithOp": hlTags["arithmeticOperator"] as Any,
	"LogicOp": hlTags["logicOperator"] as Any,
	"BitOp": hlTags["bitwiseOperator"] as Any,
	"CompareOp": hlTags["compareOperator"] as Any,
	"RegExp": hlTags["regexp"] as Any,
	"Equals": hlTags["definitionOperator"] as Any,
	"Arrow": functionMod(hlPunctuation),
	": Spread": hlPunctuation,
	"( )": hlTags["paren"] as Any,
	"[ ]": hlTags["squareBracket"] as Any,
	"{ }": hlTags["brace"] as Any,
	"InterpolationStart InterpolationEnd": specialMod(hlTags["brace"] as! Tag),
	".": hlTags["derefOperator"] as Any,
	", ;": hlTags["separator"] as Any,
	"@": hlMeta,
	"TypeName": hlTypeName,
	"TypeDefinition": definition(hlTypeName),
	"type enum interface implements namespace module declare": hlTags["definitionKeyword"] as Any,
	"abstract global Privacy readonly override": hlTags["modifier"] as Any,
	"is keyof unique infer asserts": hlTags["operatorKeyword"] as Any,
	"JSXAttributeValue": hlTags["attributeValue"] as Any,
	"JSXText": hlContent,
	"JSXStartTag JSXStartCloseTag JSXSelfCloseEndTag JSXEndTag": hlTags["angleBracket"] as Any,
	"JSXIdentifier JSXNamespacedName": hlTags["tagName"] as Any,
	"JSXAttribute/JSXIdentifier JSXAttribute/JSXNamespacedName": hlTags["attributeName"] as Any,
	"JSXBuiltin/JSXIdentifier": standardMod(hlTags["tagName"] as! Tag),
])

public nonisolated(unsafe) let javaScriptParser: LRParser = try! buildParser(jsGrammarText, options: BuildOptions(
	externalTokenizer: makeJsExternalTokenizer,
	externalPropSource: { _ in jsHighlighting },
	contextTracker: jsTrackNewline
))
