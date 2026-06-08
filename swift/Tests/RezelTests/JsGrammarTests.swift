import Foundation
@testable import Rezel
import Testing

private let expressionTests = #"""

# Minimal

0

==>

Script(ExpressionStatement(Number))

# Strings

"A string with \"double\" and 'single' quotes";
'A string with "double" and \'single\' quotes';
'\\';
"\\";

'A string with new \
line';

==>

Script(ExpressionStatement(String(Escape,Escape)),
       ExpressionStatement(String(Escape,Escape)),
       ExpressionStatement(String(Escape)),
       ExpressionStatement(String(Escape)),
       ExpressionStatement(String(Escape)))

# Numbers

101;
3.14;
3.14e+1;
0x1ABCDEFabcdef;
0o7632157312;
0b1010101001;
1e+3;

==>

Script(
  ExpressionStatement(Number),
  ExpressionStatement(Number),
  ExpressionStatement(Number),
  ExpressionStatement(Number),
  ExpressionStatement(Number),
  ExpressionStatement(Number),
  ExpressionStatement(Number))

# Identifiers

theVar;
theVar2;
$_;
é象𫝄;
últimaVez;
県;

==>

Script(
  ExpressionStatement(VariableName),
  ExpressionStatement(VariableName),
  ExpressionStatement(VariableName),
  ExpressionStatement(VariableName),
  ExpressionStatement(VariableName),
  ExpressionStatement(VariableName))

# RegExps

/one\\/;
/one/g;
/one/i;
/one/gim;
/on\/e/gim;
/on[^/]afe/gim;
/[\]/]/;

==>

Script(
  ExpressionStatement(RegExp),
  ExpressionStatement(RegExp),
  ExpressionStatement(RegExp),
  ExpressionStatement(RegExp),
  ExpressionStatement(RegExp),
  ExpressionStatement(RegExp),
  ExpressionStatement(RegExp))

# Arrays

[];
[ "item1" ];
[ "item1", ];
[ "item1", item2 ];
[ , item2 ];
[ item2 = 5 ];
[ a, ...b, c ];

==>

Script(
  ExpressionStatement(ArrayExpression),
  ExpressionStatement(ArrayExpression(String)),
  ExpressionStatement(ArrayExpression(String)),
  ExpressionStatement(ArrayExpression(String,VariableName)),
  ExpressionStatement(ArrayExpression(VariableName)),
  ExpressionStatement(ArrayExpression(AssignmentExpression(VariableName,Equals,Number))),
  ExpressionStatement(ArrayExpression(VariableName, Spread, VariableName, VariableName)))

# Functions

[
  function() {},
  function(arg1, ...arg2) {
    arg2;
  },
  function stuff() {},
  function trailing(a,) {},
  function trailing(a,b,) {}
]

==>

Script(ExpressionStatement(ArrayExpression(
  FunctionExpression(function,ParamList,Block),
  FunctionExpression(function,ParamList(VariableDefinition,Spread,VariableDefinition), Block(ExpressionStatement(VariableName))),
  FunctionExpression(function,VariableDefinition,ParamList,Block),
  FunctionExpression(function,VariableDefinition,ParamList(VariableDefinition), Block),
  FunctionExpression(function,VariableDefinition,ParamList(VariableDefinition,VariableDefinition),Block))))

# Arrow functions

a => 1;
() => 2;
(d, e) => 3;
(f, g,) => {
  return h;
};
async () => 4;

==>

Script(
  ExpressionStatement(ArrowFunction(ParamList(VariableDefinition),Arrow,Number)),
  ExpressionStatement(ArrowFunction(ParamList,Arrow,Number)),
  ExpressionStatement(ArrowFunction(ParamList(VariableDefinition,VariableDefinition),Arrow,Number)),
  ExpressionStatement(ArrowFunction(ParamList(VariableDefinition,VariableDefinition),Arrow,Block(ReturnStatement(return,VariableName)))),
  ExpressionStatement(ArrowFunction(async,ParamList,Arrow,Number)))

# Arrow function followed by comma

({
  a: () => 1,
  b: "x"
})

==>

Script(ExpressionStatement(ParenthesizedExpression(ObjectExpression(
  Property(PropertyDefinition,ArrowFunction(ParamList,Arrow,Number)),
  Property(PropertyDefinition,String)))))

# Long potential arrow function

(assign = [to, from], from = assign[0], to = assign[1]);

==>

Script(ExpressionStatement(ParenthesizedExpression(SequenceExpression(
  AssignmentExpression(VariableName,Equals,ArrayExpression(VariableName,VariableName)),
  AssignmentExpression(VariableName,Equals,MemberExpression(VariableName,Number)),
  AssignmentExpression(VariableName,Equals,MemberExpression(VariableName,Number))))))

# Ternary operator

condition ? case1 : case2;

x.y = some.condition ? 2**x : 1 - 2;

==>

Script(
  ExpressionStatement(ConditionalExpression(VariableName,LogicOp,VariableName,LogicOp,VariableName)),
  ExpressionStatement(AssignmentExpression(
    MemberExpression(VariableName,PropertyName),Equals,
    ConditionalExpression(
      MemberExpression(VariableName,PropertyName),LogicOp,
      BinaryExpression(Number,ArithOp,VariableName),LogicOp,
      BinaryExpression(Number,ArithOp,Number)))))

# Type operators

typeof x;
x instanceof String;

==>

Script(ExpressionStatement(UnaryExpression(typeof,VariableName)),
       ExpressionStatement(BinaryExpression(VariableName,instanceof,VariableName)))

# Delete

delete thing['prop'];
true ? delete thing.prop : null;

==>

Script(
  ExpressionStatement(UnaryExpression(delete,MemberExpression(VariableName,String))),
  ExpressionStatement(ConditionalExpression(BooleanLiteral,LogicOp,
    UnaryExpression(delete,MemberExpression(VariableName,PropertyName)),LogicOp,null)))

# Void

a = void b();

==>

Script(ExpressionStatement(AssignmentExpression(VariableName,Equals,UnaryExpression(void,CallExpression(VariableName,ArgList)))))

# Augmented assignment

s |= 1;
t %= 2;
w ^= 3;
x += 4;
y.z *= 5;
z += 1;
a >>= 1;
b >>>= 1;
c <<= 1;

==>

Script(
  ExpressionStatement(AssignmentExpression(VariableName,UpdateOp,Number)),
  ExpressionStatement(AssignmentExpression(VariableName,UpdateOp,Number)),
  ExpressionStatement(AssignmentExpression(VariableName,UpdateOp,Number)),
  ExpressionStatement(AssignmentExpression(VariableName,UpdateOp,Number)),
  ExpressionStatement(AssignmentExpression(MemberExpression(VariableName,PropertyName),UpdateOp,Number)),
  ExpressionStatement(AssignmentExpression(VariableName,UpdateOp,Number)),
  ExpressionStatement(AssignmentExpression(VariableName,UpdateOp,Number)),
  ExpressionStatement(AssignmentExpression(VariableName,UpdateOp,Number)),
  ExpressionStatement(AssignmentExpression(VariableName,UpdateOp,Number)))

# Operator precedence

a <= b && c >= d;
a.b = c ? d : e;
a && b(c) && d;
a && new b(c) && d;
typeof a == b && c instanceof d;

==>

Script(
  ExpressionStatement(BinaryExpression(BinaryExpression(VariableName,CompareOp,VariableName),LogicOp,
    BinaryExpression(VariableName,CompareOp,VariableName))),
  ExpressionStatement(AssignmentExpression(MemberExpression(VariableName,PropertyName),Equals,
    ConditionalExpression(VariableName,LogicOp,VariableName,LogicOp,VariableName))),
  ExpressionStatement(BinaryExpression(BinaryExpression(VariableName,LogicOp,CallExpression(VariableName,ArgList(VariableName))),LogicOp,
    VariableName)),
  ExpressionStatement(BinaryExpression(BinaryExpression(VariableName,LogicOp,NewExpression(new,VariableName,ArgList(VariableName))),LogicOp,
    VariableName)),
  ExpressionStatement(BinaryExpression(BinaryExpression(UnaryExpression(typeof,VariableName),CompareOp,VariableName),LogicOp,
    BinaryExpression(VariableName,instanceof,VariableName))))

# Rest args

foo(...rest);

==>

Script(ExpressionStatement(CallExpression(VariableName,ArgList(Spread,VariableName))))

# Forward slashes after parenthesized expressions

(foo - bar) / baz;
if (foo - bar) /baz/;
(this.a() / this.b() - 1) / 2;

==>

Script(
  ExpressionStatement(BinaryExpression(ParenthesizedExpression(BinaryExpression(VariableName,ArithOp,VariableName)),ArithOp,VariableName)),
  IfStatement(if,ParenthesizedExpression(BinaryExpression(VariableName,ArithOp,VariableName)),
    ExpressionStatement(RegExp)),
  ExpressionStatement(BinaryExpression(ParenthesizedExpression(
    BinaryExpression(
      BinaryExpression(
        CallExpression(MemberExpression(this,PropertyName),ArgList),ArithOp,
        CallExpression(MemberExpression(this,PropertyName),ArgList)),ArithOp,Number)),ArithOp,Number)))

# Yield expressions

yield db.users.where('[endpoint+email]');
yield* a;
yield [22];

==>

Script(
  ExpressionStatement(YieldExpression(yield,
    CallExpression(MemberExpression(MemberExpression(VariableName,PropertyName),PropertyName),ArgList(String)))),
  ExpressionStatement(YieldExpression(yield,Star,VariableName)),
  ExpressionStatement(YieldExpression(yield,ArrayExpression(Number))))

# Template strings

`one line`;
`multi
  line`;

`multi
  ${2 + 2}
  hello
  ${1, 2}
  line`;

`$$$$`;
`$`;
`$$$$${ async }`;

`\\\``;

`one${`two${`three`}`}`;

f`hi${there}`;

==>

Script(
  ExpressionStatement(TemplateString),
  ExpressionStatement(TemplateString),
  ExpressionStatement(TemplateString(
    Interpolation(InterpolationStart,BinaryExpression(Number,ArithOp,Number),InterpolationEnd),
    Interpolation(InterpolationStart,SequenceExpression(Number,Number),InterpolationEnd))),
  ExpressionStatement(TemplateString),
  ExpressionStatement(TemplateString),
  ExpressionStatement(TemplateString(Interpolation(InterpolationStart,VariableName,InterpolationEnd))),
  ExpressionStatement(TemplateString(Escape,Escape)),
  ExpressionStatement(TemplateString(Interpolation(InterpolationStart,TemplateString(
    Interpolation(InterpolationStart,TemplateString,InterpolationEnd)),InterpolationEnd))),
  ExpressionStatement(TaggedTemplateExpression(VariableName,TemplateString(
    Interpolation(InterpolationStart,VariableName,InterpolationEnd)))))

# Atoms

this;
null;
undefined;
true;
false;

==>

Script(
  ExpressionStatement(this),
  ExpressionStatement(null),
  ExpressionStatement(VariableName),
  ExpressionStatement(BooleanLiteral),
  ExpressionStatement(BooleanLiteral))

# Objects

foo({},
    { a: "b" },
    { c: "d", "e": f, 1: 2 },
    {
      g,
      [methodName]() {}
    },
    {b, get},
    {a,});

==>

Script(ExpressionStatement(CallExpression(VariableName,ArgList(
  ObjectExpression,
  ObjectExpression(Property(PropertyDefinition,String)),
  ObjectExpression(Property(PropertyDefinition,String),Property(String,VariableName),Property(Number,Number)),
  ObjectExpression(Property(PropertyDefinition),Property(VariableName,ParamList,Block)),
  ObjectExpression(Property(PropertyDefinition),Property(PropertyDefinition)),
  ObjectExpression(Property(PropertyDefinition))))))

# Method definitions

({
  foo: true,

  add(a, b) {
    return a + b;
  },

  get bar() { return c; },

  set bar(a) { c = a; },

  *barGenerator() { yield c; },

  get() { return 1; }
});

==>

Script(ExpressionStatement(ParenthesizedExpression(ObjectExpression(
  Property(PropertyDefinition,BooleanLiteral),
  Property(PropertyDefinition,ParamList(VariableDefinition,VariableDefinition),
    Block(ReturnStatement(return,BinaryExpression(VariableName,ArithOp,VariableName)))),
  Property(get,PropertyDefinition,ParamList,Block(ReturnStatement(return,VariableName))),
  Property(set,PropertyDefinition,ParamList(VariableDefinition),
    Block(ExpressionStatement(AssignmentExpression(VariableName,Equals,VariableName)))),
  Property(Star,PropertyDefinition,ParamList,Block(ExpressionStatement(YieldExpression(yield,VariableName)))),
  Property(PropertyDefinition,ParamList,Block(ReturnStatement(return,Number)))))))

# Keyword property names

({
  finally() {},
  catch() {},
  get: function () {},
  set() {},
  static: true,
  async: true,
});

==>

Script(ExpressionStatement(ParenthesizedExpression(ObjectExpression(
  Property(PropertyDefinition,ParamList,Block),
  Property(PropertyDefinition,ParamList,Block),
  Property(PropertyDefinition,FunctionExpression(function,ParamList,Block)),
  Property(PropertyDefinition,ParamList,Block),
  Property(PropertyDefinition,BooleanLiteral),
  Property(PropertyDefinition,BooleanLiteral)))))

# Generator functions

[
  function *() {},
  function *generateStuff(arg1, arg2) {
    yield;
    yield arg2;
  }
];

==>

Script(ExpressionStatement(ArrayExpression(
  FunctionExpression(function,Star,ParamList,Block),
  FunctionExpression(function,Star,VariableDefinition,ParamList(VariableDefinition,VariableDefinition),Block(
    ExpressionStatement(VariableName),
    ExpressionStatement(YieldExpression(yield,VariableName)))))))

# Member expressions

x.someProperty;
x?.other;
x[someVariable];
f()["some-string"];
return returned.promise().done(a).fail(b);

==>

Script(
  ExpressionStatement(MemberExpression(VariableName,PropertyName)),
  ExpressionStatement(MemberExpression(VariableName,PropertyName)),
  ExpressionStatement(MemberExpression(VariableName,VariableName)),
  ExpressionStatement(MemberExpression(CallExpression(VariableName,ArgList),String)),
  ReturnStatement(return,CallExpression(MemberExpression(CallExpression(MemberExpression(CallExpression(
    MemberExpression(VariableName,PropertyName),ArgList),PropertyName),ArgList(VariableName)),PropertyName),ArgList(VariableName)))))

# Callback chain

return this.map(function (a) {
  return a.b;
})

// a comment

.filter(function (c) {
  return 2;
});

==>

Script(ReturnStatement(return,CallExpression(MemberExpression(CallExpression(MemberExpression(this,PropertyName),
  ArgList(FunctionExpression(function,ParamList(VariableDefinition),Block(ReturnStatement(return,MemberExpression(VariableName,PropertyName)))))),
  LineComment,PropertyName),ArgList(FunctionExpression(function,ParamList(VariableDefinition),Block(ReturnStatement(return,Number)))))))

# Function calls

x.someMethod(arg1, "arg2");
(function(x, y) {

}(a, b));
f(new foo.bar(1), 2);

==>

Script(
  ExpressionStatement(CallExpression(MemberExpression(VariableName,PropertyName),ArgList(VariableName,String))),
  ExpressionStatement(ParenthesizedExpression(CallExpression(FunctionExpression(function,ParamList(VariableDefinition,VariableDefinition),Block),
    ArgList(VariableName,VariableName)))),
  ExpressionStatement(CallExpression(VariableName,ArgList(NewExpression(new,MemberExpression(VariableName,PropertyName),ArgList(Number)),Number))))

# Constructor calls

new foo(1);
new module.Klass(1, "two");
new Thing;

==>

Script(
  ExpressionStatement(NewExpression(new,VariableName,ArgList(Number))),
  ExpressionStatement(NewExpression(new,MemberExpression(VariableName,PropertyName),ArgList(Number,String))),
  ExpressionStatement(NewExpression(new,VariableName)))

# Await Expressions

await asyncFunction();
await asyncPromise;

==>

Script(
  ExpressionStatement(AwaitExpression(await,CallExpression(VariableName,ArgList))),
  ExpressionStatement(AwaitExpression(await,VariableName)))

# Numeric operators

i++;
i--;
i + j * 3 - j % 5;
2 ** i * 3;
2 * i ** 3;
+x;
-x;

==>

Script(
  ExpressionStatement(PostfixExpression(VariableName,ArithOp)),
  ExpressionStatement(PostfixExpression(VariableName,ArithOp)),
  ExpressionStatement(BinaryExpression(BinaryExpression(VariableName,ArithOp,BinaryExpression(VariableName,ArithOp,Number)),ArithOp,BinaryExpression(VariableName,ArithOp,Number))),
  ExpressionStatement(BinaryExpression(BinaryExpression(Number,ArithOp,VariableName),ArithOp,Number)),
  ExpressionStatement(BinaryExpression(Number,ArithOp,BinaryExpression(VariableName,ArithOp,Number))),
  ExpressionStatement(UnaryExpression(ArithOp,VariableName)),
  ExpressionStatement(UnaryExpression(ArithOp,VariableName)))

# Boolean operators

i || j;
i && j;
i ?? j;
!a && !b || !c && !d;

==>

Script(
  ExpressionStatement(BinaryExpression(VariableName,LogicOp,VariableName)),
  ExpressionStatement(BinaryExpression(VariableName,LogicOp,VariableName)),
  ExpressionStatement(BinaryExpression(VariableName,LogicOp,VariableName)),
  ExpressionStatement(BinaryExpression(BinaryExpression(UnaryExpression(LogicOp,VariableName),LogicOp,
    UnaryExpression(LogicOp,VariableName)),LogicOp,BinaryExpression(UnaryExpression(LogicOp,VariableName),LogicOp,
      UnaryExpression(LogicOp,VariableName)))))

# Bitwise operators

i >> j;
i >>> j;
i << j;
i & j;
i | j;
~i ^ ~j;

==>

Script(
  ExpressionStatement(BinaryExpression(VariableName,BitOp,VariableName)),
  ExpressionStatement(BinaryExpression(VariableName,BitOp,VariableName)),
  ExpressionStatement(BinaryExpression(VariableName,BitOp,VariableName)),
  ExpressionStatement(BinaryExpression(VariableName,BitOp,VariableName)),
  ExpressionStatement(BinaryExpression(VariableName,BitOp,VariableName)),
  ExpressionStatement(BinaryExpression(UnaryExpression(BitOp,VariableName),BitOp,UnaryExpression(BitOp,VariableName))))

# Relational operators

x < y;
x <= y;
x == y;
x === y;
x != y;
x !== y;
x > y;
x >= y;

==>

Script(
  ExpressionStatement(BinaryExpression(VariableName,CompareOp,VariableName)),
  ExpressionStatement(BinaryExpression(VariableName,CompareOp,VariableName)),
  ExpressionStatement(BinaryExpression(VariableName,CompareOp,VariableName)),
  ExpressionStatement(BinaryExpression(VariableName,CompareOp,VariableName)),
  ExpressionStatement(BinaryExpression(VariableName,CompareOp,VariableName)),
  ExpressionStatement(BinaryExpression(VariableName,CompareOp,VariableName)),
  ExpressionStatement(BinaryExpression(VariableName,CompareOp,VariableName)),
  ExpressionStatement(BinaryExpression(VariableName,CompareOp,VariableName)))

# Word operators

x in y;
x instanceof y;
!x instanceof y;

==>

Script(
  ExpressionStatement(BinaryExpression(VariableName,in,VariableName)),
  ExpressionStatement(BinaryExpression(VariableName,instanceof,VariableName)),
  ExpressionStatement(BinaryExpression(UnaryExpression(LogicOp,VariableName),instanceof,VariableName)))

# Assignments

x = 0;
x.y = 0;
x["y"] = 0;
async = 0;
[a, b = 2] = foo;
({a, b, ...d} = c);

==>

Script(
  ExpressionStatement(AssignmentExpression(VariableName,Equals,Number)),
  ExpressionStatement(AssignmentExpression(MemberExpression(VariableName,PropertyName),Equals,Number)),
  ExpressionStatement(AssignmentExpression(MemberExpression(VariableName,String),Equals,Number)),
  ExpressionStatement(AssignmentExpression(VariableName,Equals,Number)),
  ExpressionStatement(AssignmentExpression(ArrayPattern(VariableDefinition,VariableDefinition,Equals,Number),Equals,VariableName)),
  ExpressionStatement(ParenthesizedExpression(AssignmentExpression(ObjectPattern(
    PatternProperty(PropertyName),PatternProperty(PropertyName),PatternProperty(Spread,VariableDefinition)),Equals,VariableName))))

# Comma operator

a = 1, b = 2;
c = {d: (3, 4 + 5)};

==>

Script(
  ExpressionStatement(SequenceExpression(AssignmentExpression(VariableName,Equals,Number),AssignmentExpression(VariableName,Equals,Number))),
  ExpressionStatement(AssignmentExpression(VariableName,Equals,ObjectExpression(
    Property(PropertyDefinition,ParenthesizedExpression(SequenceExpression(Number,BinaryExpression(Number,ArithOp,Number))))))))

# Punctuation

(foo(1, 2), bar);

==>

Script(ExpressionStatement(ParenthesizedExpression(
  "(",SequenceExpression(CallExpression(VariableName,ArgList("(",Number,Number,")")),",",VariableName),")")))

# Doesn't choke on unfinished ternary operator

1?1

==>

Script(ExpressionStatement(ConditionalExpression(Number,LogicOp,Number,⚠)))

# Can handle unterminated template literals

`f

==>

Script(ExpressionStatement(TemplateString(⚠)))

# Ternary with leading-dot number

a?.2:.3

==>

Script(ExpressionStatement(ConditionalExpression(VariableName,LogicOp,Number,LogicOp,Number)))

"""#

private let statementTests = #"""

# Variable declaration

var a = b
  , c = d;
const [x] = y = 3;

==>

Script(
  VariableDeclaration(var,VariableDefinition,Equals,VariableName,VariableDefinition,Equals,VariableName),
  VariableDeclaration(const,ArrayPattern(VariableDefinition),Equals,AssignmentExpression(VariableName,Equals,Number)))

# Function declaration

function a(a, b) { return 3; }
function b({b}, c = d, e = f) {}

==>

Script(
  FunctionDeclaration(function,VariableDefinition,ParamList(VariableDefinition,VariableDefinition),Block(ReturnStatement(return,Number))),
  FunctionDeclaration(function,VariableDefinition,ParamList(
    ObjectPattern(PatternProperty(PropertyName)),VariableDefinition,Equals,VariableName,VariableDefinition,Equals,VariableName),Block))

# Async functions

async function foo() {}

class Foo { async bar() {} }

async (a) => { return foo; };

==>

Script(
  FunctionDeclaration(async,function,VariableDefinition,ParamList,Block),
  ClassDeclaration(class,VariableDefinition,ClassBody(MethodDeclaration(async,PropertyDefinition,ParamList,Block))),
  ExpressionStatement(ArrowFunction(async,ParamList(VariableDefinition),Arrow,Block(ReturnStatement(return,VariableName)))))

# If statements

if (x) log(y);

if (a.b) {
  d;
}

if (a) {
  c;
  d;
} else {
  e;
}

if (1) if (2) b; else c;

==>

Script(
  IfStatement(if,ParenthesizedExpression(VariableName),ExpressionStatement(CallExpression(VariableName,ArgList(VariableName)))),
  IfStatement(if,ParenthesizedExpression(MemberExpression(VariableName,PropertyName)),Block(ExpressionStatement(VariableName))),
  IfStatement(if,ParenthesizedExpression(VariableName),Block(ExpressionStatement(VariableName),ExpressionStatement(VariableName)),
    else,Block(ExpressionStatement(VariableName))),
  IfStatement(if,ParenthesizedExpression(Number),IfStatement(if,ParenthesizedExpression(Number),ExpressionStatement(VariableName),
    else,ExpressionStatement(VariableName))))

# While loop

while (1) debugger;
while (2) {
  a;
  b;
}

==>

Script(
  WhileStatement(while,ParenthesizedExpression(Number),DebuggerStatement(debugger)),
  WhileStatement(while,ParenthesizedExpression(Number),Block(ExpressionStatement(VariableName),ExpressionStatement(VariableName))))

# Labels

foo: 1;
foo: while(2) break foo;

==>

Script(
  LabeledStatement(Label,ExpressionStatement(Number)),
  LabeledStatement(Label,WhileStatement(while,ParenthesizedExpression(Number),BreakStatement(break,Label))))

# Try

try { throw new Error; } catch {}
try { 1; } catch (x) { 2; } finally { 3; }

==>

Script(
  TryStatement(try,Block(ThrowStatement(throw,NewExpression(new,VariableName))),CatchClause(catch,Block)),
  TryStatement(try,Block(ExpressionStatement(Number)),
    CatchClause(catch,VariableDefinition,Block(ExpressionStatement(Number))),
    FinallyClause(finally,Block(ExpressionStatement(Number)))))

# Switch

switch (x) {
  case 1:
    return true;
  case 2:
  case 50 * 3:
    console.log("ok");
  default:
    return false;
}

==>

Script(SwitchStatement(switch,ParenthesizedExpression(VariableName),SwitchBody(
  CaseLabel(case,Number),
  ReturnStatement(return,BooleanLiteral),
  CaseLabel(case,Number),
  CaseLabel(case,BinaryExpression(Number,ArithOp,Number)),
  ExpressionStatement(CallExpression(MemberExpression(VariableName,PropertyName),ArgList(String))),
  DefaultLabel(default),
  ReturnStatement(return,BooleanLiteral))))

# For

for (let x = 1; x < 10; x++) {}
for (const y of z) {}
for (var m in n) {}
for (q in r) {}
for (var a, b; c; d) continue;
for (i = 0, init(); i < 10; i++) {}
for (;;) {}
for (const {thing} in things) thing;
for await (let x of stream) {}

==>

Script(
  ForStatement(for,ForSpec(VariableDeclaration(let,VariableDefinition,Equals,Number),
    BinaryExpression(VariableName,CompareOp,Number),PostfixExpression(VariableName,ArithOp)),Block),
  ForStatement(for,ForOfSpec(const,VariableDefinition,of,VariableName),Block),
  ForStatement(for,ForInSpec(var,VariableDefinition,in,VariableName),Block),
  ForStatement(for,ForInSpec(VariableName,in,VariableName),Block),
  ForStatement(for,ForSpec(VariableDeclaration(var,VariableDefinition,VariableDefinition),VariableName,VariableName),ContinueStatement(continue)),
  ForStatement(for,ForSpec(SequenceExpression(AssignmentExpression(VariableName,Equals,Number),
    CallExpression(VariableName,ArgList)),BinaryExpression(VariableName,CompareOp,Number),PostfixExpression(VariableName,ArithOp)),Block),
  ForStatement(for,ForSpec,Block),
  ForStatement(for,ForInSpec(const,ObjectPattern(PatternProperty(PropertyName)),in,VariableName),ExpressionStatement(VariableName)),
  ForStatement(for,await,ForOfSpec(let,VariableDefinition,of,VariableName),Block))

# Labeled statements

theLoop: for (;;) {
  if (a) {
    break theLoop;
  }
}

==>

Script(LabeledStatement(Label,ForStatement(for,ForSpec,Block(
  IfStatement(if,ParenthesizedExpression(VariableName),Block(BreakStatement(break,Label)))))))

# Classes

class Foo {
  static one(a) { return a; };
  two(b) { return b; }
  finally() {}
}

class Foo extends require('another-class') {
  constructor() { super(); }
  bar() { super.a(); }
  prop;
  etc = 20;
  static { f() }
}

==>

Script(
  ClassDeclaration(class,VariableDefinition,ClassBody(
    MethodDeclaration(static,PropertyDefinition,ParamList(VariableDefinition),Block(ReturnStatement(return,VariableName))),
    MethodDeclaration(PropertyDefinition,ParamList(VariableDefinition),Block(ReturnStatement(return,VariableName))),
    MethodDeclaration(PropertyDefinition,ParamList,Block))),
  ClassDeclaration(class,VariableDefinition,extends,CallExpression(VariableName,ArgList(String)),ClassBody(
    MethodDeclaration(PropertyDefinition,ParamList,Block(ExpressionStatement(CallExpression(super,ArgList)))),
    MethodDeclaration(PropertyDefinition,ParamList,Block(ExpressionStatement(CallExpression(MemberExpression(super,PropertyName),ArgList)))),
    PropertyDeclaration(PropertyDefinition),
    PropertyDeclaration(PropertyDefinition,Equals,Number),
    StaticBlock(static, Block(ExpressionStatement(CallExpression(VariableName,ArgList)))))))

# Private properties

class Foo {
  #bar() { this.#a() + this?.#prop == #prop in this; }
  #prop;
  #etc = 20;
}

==>

Script(ClassDeclaration(class,VariableDefinition,ClassBody(
  MethodDeclaration(PrivatePropertyDefinition,ParamList,Block(
    ExpressionStatement(BinaryExpression(
       BinaryExpression(
         CallExpression(MemberExpression(this,PrivatePropertyName),ArgList),
         ArithOp,
         MemberExpression(this,PrivatePropertyName)),
       CompareOp,
       BinaryExpression(PrivatePropertyName, in, this))))),
  PropertyDeclaration(PrivatePropertyDefinition),
  PropertyDeclaration(PrivatePropertyDefinition,Equals,Number))))

# Computed properties

class Foo {
  [x] = 44;
  [Symbol.iterator]() {}
}

==>

Script(ClassDeclaration(class,VariableDefinition,ClassBody(
  PropertyDeclaration(VariableName,Equals,Number),
  MethodDeclaration(MemberExpression(VariableName,PropertyName),ParamList,Block))))

# Imports

import defaultMember from "module-name";
import * as name from "module-name";
import { member } from "module-name";
import { member1, member2 as alias2 } from "module-name";
import defaultMember, { member1, member2 as alias2, } from "module-name";
import "module-name";
import defer x from "y";
import defer from "y";

==>

Script(
  ImportDeclaration(import,VariableDefinition,from,String),
  ImportDeclaration(import,Star,as,VariableDefinition,from,String),
  ImportDeclaration(import,ImportGroup(VariableDefinition),from,String),
  ImportDeclaration(import,ImportGroup(VariableDefinition,VariableName,as,VariableDefinition),from,String),
  ImportDeclaration(import,VariableDefinition,ImportGroup(VariableDefinition,VariableName,as,VariableDefinition),from,String),
  ImportDeclaration(import,String),
  ImportDeclaration(import,defer,VariableDefinition,from,String),
  ImportDeclaration(import,VariableDefinition,from,String))

# Exports

export { name1, name2, name3 as x, nameN };
export let a, b = 2;
export default 2 + 2;
export default function() { }
export default async function name1() { }
export { name1 as default, } from "foo";
export * from 'foo';

==>

Script(
  ExportDeclaration(export,ExportGroup(VariableName,VariableName,VariableName,as,VariableName,VariableName)),
  ExportDeclaration(export,VariableDeclaration(let,VariableDefinition,VariableDefinition,Equals,Number)),
  ExportDeclaration(export,default,BinaryExpression(Number,ArithOp,Number)),
  ExportDeclaration(export,default,FunctionDeclaration(function,ParamList,Block)),
  ExportDeclaration(export,default,FunctionDeclaration(async,function,VariableDefinition,ParamList,Block)),
  ExportDeclaration(export,ExportGroup(VariableName,as,VariableName),from,String),
  ExportDeclaration(export,Star,from,String))

# Empty statements

if (true) { ; };;;

==>

Script(IfStatement(if,ParenthesizedExpression(BooleanLiteral),Block))

# Comments

/* a */
one;

/* b **/
two;

/* c ***/
three;

/* d

***/
four;

y // comment
  * z;

==>

Script(
  BlockComment,
  ExpressionStatement(VariableName),
  BlockComment,
  ExpressionStatement(VariableName),
  BlockComment,
  ExpressionStatement(VariableName),
  BlockComment,
  ExpressionStatement(VariableName),
  ExpressionStatement(BinaryExpression(VariableName,LineComment,ArithOp,VariableName)))

# Sync back to statement

function f() {
  log(a b --c)
}
function g() {}

==>

Script(
  FunctionDeclaration(function,VariableDefinition,ParamList,Block(ExpressionStatement(CallExpression(VariableName,ArgList(...))))),
  FunctionDeclaration(function,VariableDefinition,ParamList,Block))

# Destructuring

({x} = y);
[u, v] = w;
let [a,, b = 0] = c;
let {x, y: z = 1} = d;
let {[f]: m} = e;

==>

Script(
  ExpressionStatement(ParenthesizedExpression(AssignmentExpression(
    ObjectPattern(PatternProperty(PropertyName)),Equals,VariableName))),
  ExpressionStatement(AssignmentExpression(ArrayPattern(VariableDefinition,VariableDefinition),Equals,VariableName)),
  VariableDeclaration(let,ArrayPattern(VariableDefinition,VariableDefinition,Equals,Number),Equals,VariableName),
  VariableDeclaration(let,ObjectPattern(
    PatternProperty(PropertyName),
    PatternProperty(PropertyName,VariableDefinition,Equals,Number)
  ),Equals,VariableName),
  VariableDeclaration(let,ObjectPattern(PatternProperty(VariableName,VariableDefinition)),Equals,VariableName))

# Generators

function* foo() { yield 1 }

class B {
  *method() {}
}

({*x() {}})

==>

Script(
  FunctionDeclaration(function,Star,VariableDefinition,ParamList,Block(
    ExpressionStatement(YieldExpression(yield,Number)))),
  ClassDeclaration(class,VariableDefinition,ClassBody(
    MethodDeclaration(Star,PropertyDefinition,ParamList,Block))),
  ExpressionStatement(ParenthesizedExpression(ObjectExpression(Property(Star,PropertyDefinition,ParamList,Block)))))

# Hashbang

#!/bin/env node
foo()

==>

Script(Hashbang,ExpressionStatement(CallExpression(VariableName,ArgList)))

# new.target

function MyObj() {
  if (!new.target) {
    throw new Error('Must construct MyObj with new');
  }
}

==>

Script(
  FunctionDeclaration(function,VariableDefinition,ParamList,Block(
    IfStatement(if,ParenthesizedExpression(UnaryExpression(LogicOp,NewTarget(new,PropertyName))), Block(
      ThrowStatement(throw,NewExpression(new,VariableName,ArgList(String))))))))

"""#

private let semicolonTests = #"""

# No semicolons

x
if (a) {
  var b = c
  d
} else
  e

==>

Script(
  ExpressionStatement(VariableName),
  IfStatement(if,ParenthesizedExpression(VariableName),Block(
     VariableDeclaration(var,VariableDefinition,Equals,VariableName),
     ExpressionStatement(VariableName)),
   else,ExpressionStatement(VariableName)))

# Continued expressions on new line

x
+ 2
foo
(bar)

==>

Script(
  ExpressionStatement(BinaryExpression(VariableName,ArithOp,Number)),
  ExpressionStatement(CallExpression(VariableName,ArgList(VariableName))))

# Doesn't parse postfix ops on a new line

x
++y

==>

Script(
  ExpressionStatement(VariableName),
  ExpressionStatement(UnaryExpression(ArithOp,VariableName)))

# Eagerly cut return/break/continue

return 2
return
2
continue foo
continue
foo
break bar
break
bar

==>

Script(
  ReturnStatement(return,Number),
  ReturnStatement(return),
  ExpressionStatement(Number),
  ContinueStatement(continue,Label),
  ContinueStatement(continue),
  ExpressionStatement(VariableName),
  BreakStatement(break,Label),
  BreakStatement(break),
  ExpressionStatement(VariableName))

# Cut return regardless of whitespace

{ return }

return // foo
;

==>

Script(Block(ReturnStatement(return)),ReturnStatement(return,LineComment))

"""#

private let decoratorTests = #"""

# Decorators on classes and class fields

@d1 class Foo {
  @d2 bar() {}
  @d3 get baz() { return 1 }
  @d4 quux = 1
}

==>

Script(ClassDeclaration(
  Decorator(VariableName),
  class,VariableDefinition,ClassBody(
    MethodDeclaration(Decorator(VariableName),PropertyDefinition,ParamList,Block),
    MethodDeclaration(Decorator(VariableName),get,PropertyDefinition,ParamList,Block(
      ReturnStatement(return,Number))),
    PropertyDeclaration(Decorator(VariableName),PropertyDefinition,Equals,Number))))

# Multiple decorators

@d1 @d2 class Y {}

==>

Script(ClassDeclaration(Decorator(VariableName),Decorator(VariableName),class,VariableDefinition,ClassBody))

# Member decorators

@one.two class X {}

==>

Script(ClassDeclaration(Decorator(MemberExpression(VariableName,PropertyName)),class,VariableDefinition,ClassBody))

# Call decorators

@d(2) @a.b() class Z {}

==>

Script(ClassDeclaration(
  Decorator(CallExpression(VariableName,ArgList(Number))),
  Decorator(CallExpression(MemberExpression(VariableName,PropertyName),ArgList)),
  class,VariableDefinition,ClassBody))

# Parenthesized decorators

@(a instanceof Array ? x : y)(2) class P {}

==>

Script(ClassDeclaration(
  Decorator(CallExpression(ParenthesizedExpression(
    ConditionalExpression(BinaryExpression(VariableName,instanceof,VariableName),LogicOp,VariableName,LogicOp,VariableName)),
    ArgList(Number))),
  class,VariableDefinition,ClassBody))

# Parameter decorators

function foo(@d bar) {}

==>

Script(FunctionDeclaration(function,VariableDefinition,ParamList(Decorator(VariableName),VariableDefinition),Block))

"""#

private let jsxTests = #"""

# Self-closing element {"dialect": "jsx"}

<img/>

==>

Script(ExpressionStatement(JSXElement(JSXSelfClosingTag(JSXStartTag,JSXBuiltin(JSXIdentifier),JSXSelfCloseEndTag))))

# Regular element {"dialect": "jsx"}

<Foo>bar</Foo>

==>

Script(ExpressionStatement(JSXElement(
  JSXOpenTag(JSXStartTag, JSXIdentifier, JSXEndTag),
  JSXText,
  JSXCloseTag(JSXStartCloseTag, JSXIdentifier, JSXEndTag))))

# Fragment {"dialect": "jsx"}

<>bar</>

==>

Script(ExpressionStatement(JSXElement(
  JSXFragmentTag(JSXStartTag, JSXEndTag),
  JSXText,
  JSXCloseTag(JSXStartCloseTag, JSXEndTag))))

# Namespaced name {"dialect": "jsx"}

<blah-namespace:img/>

==>

Script(ExpressionStatement(JSXElement(
  JSXSelfClosingTag(JSXStartTag,JSXNamespacedName(JSXIdentifier, JSXIdentifier),JSXSelfCloseEndTag))))

# Member name {"dialect": "jsx"}

<pkg.Component/>

==>

Script(ExpressionStatement(JSXElement(
  JSXSelfClosingTag(JSXStartTag,JSXMemberExpression(JSXIdentifier, JSXIdentifier),JSXSelfCloseEndTag))))

# Nested tags {"dialect": "jsx"}

<a><b.C>text</b.C>{x} {...y}</a>

==>

Script(ExpressionStatement(JSXElement(
  JSXOpenTag(JSXStartTag, JSXBuiltin(JSXIdentifier), JSXEndTag),
  JSXElement(
    JSXOpenTag(JSXStartTag, JSXMemberExpression(JSXIdentifier, JSXIdentifier), JSXEndTag),
    JSXText,
    JSXCloseTag(JSXStartCloseTag, JSXMemberExpression(JSXIdentifier, JSXIdentifier), JSXEndTag)),
  JSXEscape(VariableName),
  JSXText,
  JSXEscape(Spread, VariableName),
  JSXCloseTag(JSXStartCloseTag, JSXBuiltin(JSXIdentifier), JSXEndTag))))

# Attributes {"dialect": "jsx"}

<Foo a="1" b {...attrs} c={c}></Foo>

==>

Script(ExpressionStatement(JSXElement(
  JSXOpenTag(JSXStartTag, JSXIdentifier,
    JSXAttribute(JSXIdentifier, Equals, JSXAttributeValue),
    JSXAttribute(JSXIdentifier),
    JSXSpreadAttribute(Spread, VariableName),
    JSXAttribute(JSXIdentifier, Equals, JSXEscape(VariableName)),
  JSXEndTag),
  JSXCloseTag(JSXStartCloseTag, JSXIdentifier, JSXEndTag))))

"""#

private let typescriptTests = #"""

# Undefined and Null Type {"dialect": "ts"}

let x: undefined
let y: null

==>

Script(
  VariableDeclaration(let,VariableDefinition,TypeAnnotation(
    TypeName)),
  VariableDeclaration(let,VariableDefinition,TypeAnnotation(
    NullType(null))))

# Type declaration {"dialect": "ts"}

function foo(a: number, b: "literal" | Map<number, boolean>): RegExp[] {}

==>

Script(FunctionDeclaration(function, VariableDefinition, ParamList(
  VariableDefinition, TypeAnnotation(TypeName),
  VariableDefinition, TypeAnnotation(UnionType(LiteralType(String), LogicOp, ParameterizedType(TypeName, TypeArgList(TypeName, TypeName))))
), TypeAnnotation(ArrayType(TypeName)), Block))

# Type predicate {"dialect": "ts"}

function isFoo(foo: any): foo is Foo { return true }

function assertFoo(foo: any): asserts foo is "string" { return true }

==>

Script(
  FunctionDeclaration(function, VariableDefinition, ParamList(
    VariableDefinition, TypeAnnotation(TypeName)
  ), TypePredicate(VariableName, is, TypeName), Block(ReturnStatement(return, BooleanLiteral))),
  FunctionDeclaration(function,VariableDefinition,ParamList(
    VariableDefinition,TypeAnnotation(TypeName)
  ),TypePredicate(asserts,VariableName,is,LiteralType(String)),Block(ReturnStatement(return,BooleanLiteral))))

# Type alias {"dialect": "ts"}

type Foo<T extends string> = T[]

==>

Script(TypeAliasDeclaration(type, TypeDefinition, TypeParamList(TypeDefinition, extends, TypeName), Equals, ArrayType(TypeName)))

# Enum declaration {"dialect": "ts"}

const enum Type { Red = 1, Blue, Green }

==>

Script(EnumDeclaration(const, enum, TypeDefinition, EnumBody(PropertyName, Equals, Number, PropertyName, PropertyName)))

# Interface declaration {"dialect": "ts"}

interface Foo {
  readonly a: number
  b(arg: string): void
  (call: number): boolean
  new (): Foo
  readonly [x: string]: number
}

==>

Script(InterfaceDeclaration(interface, TypeDefinition, ObjectType(
  PropertyType(readonly, PropertyDefinition, TypeAnnotation(TypeName)),
  MethodType(PropertyDefinition, ParamList(VariableDefinition, TypeAnnotation(TypeName)), TypeAnnotation(VoidType(void))),
  CallSignature(ParamList(VariableDefinition, TypeAnnotation(TypeName)), TypeAnnotation(TypeName)),
  NewSignature(new,ParamList, TypeAnnotation(TypeName)),
  IndexSignature(readonly, PropertyDefinition, TypeAnnotation(TypeName), TypeAnnotation(TypeName)))))

# Call type args {"dialect": "ts"}

foo<number, string>() + new Bar<11>()
x < 10 > 5

==>

Script(
  ExpressionStatement(BinaryExpression(
    CallExpression(InstantiationExpression(VariableName, TypeArgList(TypeName, TypeName)), ArgList),
    ArithOp,
    NewExpression(new, InstantiationExpression(VariableName, TypeArgList(LiteralType(Number))), ArgList))),
  ExpressionStatement(BinaryExpression(BinaryExpression(VariableName, CompareOp, Number), CompareOp, Number)))

# Advanced types {"dialect": "ts"}

let x: typeof X.x | keyof Y & Z["Foo"] | A<string>
let tuple: [a, b]
let f: (x: number) => boolean

==>

Script(
  VariableDeclaration(let, VariableDefinition, TypeAnnotation(
    UnionType(TypeofType(typeof, MemberExpression(VariableName, PropertyName)), LogicOp,
              IntersectionType(KeyofType(keyof, TypeName), LogicOp, IndexedType(TypeName, LiteralType(String))),
              LogicOp, ParameterizedType(TypeName, TypeArgList(TypeName))))),
  VariableDeclaration(let, VariableDefinition, TypeAnnotation(TupleType(TypeName, TypeName))),
  VariableDeclaration(let, VariableDefinition, TypeAnnotation(FunctionSignature(
    ParamList(VariableDefinition, TypeAnnotation(TypeName)), Arrow, TypeName))))

# Prefix union/intersection

let x:
  | A
  | B
  | C
let y: & RegExp & (& Date)

==>

Script(
  VariableDeclaration(let,VariableDefinition,TypeAnnotation(
    UnionType(LogicOp,TypeName,LogicOp,TypeName,LogicOp,TypeName))),
  VariableDeclaration(let,VariableDefinition,TypeAnnotation(
    IntersectionType(LogicOp,TypeName,LogicOp,ParenthesizedType(IntersectionType(LogicOp,TypeName))))))

# Prefix cast {"dialect": "ts"}

<string>foo

==>

Script(ExpressionStatement(PrefixCast(TypeName, VariableName)))

# No prefix cast in JSX {"dialect": "ts jsx"}

<string>foo</string>

==>

Script(ExpressionStatement(JSXElement(
  JSXOpenTag(JSXStartTag, JSXBuiltin(JSXIdentifier), JSXEndTag),
  JSXText,
  JSXCloseTag(JSXStartCloseTag, JSXBuiltin(JSXIdentifier), JSXEndTag))))

# Class definition {"dialect": "ts"}

class Foo<T> extends Bar<T> implements Stuff {
  a: number
  public readonly b: string = "two"
  constructor(readonly x: boolean, public y: number, z: string) {}
  private static blah(): void {}
}

==>

Script(ClassDeclaration(
  class, VariableDefinition, TypeParamList(TypeDefinition),
  extends, VariableName, TypeArgList(TypeName),
  implements TypeName,
  ClassBody(
    PropertyDeclaration(PropertyDefinition, TypeAnnotation(TypeName)),
    PropertyDeclaration(Privacy, readonly, PropertyDefinition, TypeAnnotation(TypeName), Equals, String),
    MethodDeclaration(PropertyDefinition, ParamList(
      readonly, VariableDefinition, TypeAnnotation(TypeName),
      Privacy, VariableDefinition, TypeAnnotation(TypeName),
      VariableDefinition, TypeAnnotation(TypeName)), Block),
    MethodDeclaration(Privacy, static, PropertyDefinition, ParamList, TypeAnnotation(VoidType(void)), Block))))

# Arrow with type params {"dialect": "ts"}

let x = <T>(arg: T): T => arg

==>

Script(VariableDeclaration(let, VariableDefinition, Equals, ArrowFunction(
  TypeParamList(TypeDefinition),
  ParamList(VariableDefinition, TypeAnnotation(TypeName)),
  TypeAnnotation(TypeName),
  Arrow,
  VariableName)))

# Template types {"dialect": "ts"}

type Tmpl<T> = `${string} ${5}` | `one ${Two}`

==>

Script(TypeAliasDeclaration(type, TypeDefinition, TypeParamList(TypeDefinition), Equals,
  UnionType(TemplateType(Interpolation(InterpolationStart,TypeName,InterpolationEnd), Interpolation(InterpolationStart,LiteralType(Number),InterpolationEnd)), LogicOp, TemplateType(Interpolation(InterpolationStart,TypeName,InterpolationEnd)))))

# Extending complex types {"dialect": "ts"}

class Foo extends A.B<Param> {}

==>

Script(ClassDeclaration(class, VariableDefinition,
  extends, MemberExpression(VariableName, PropertyName), TypeArgList(TypeName),
  ClassBody))

# Object type {"dialect": "ts"}

type A = {a: number, b: number}
type B = {a: number; b: number;}

==>

Script(
  TypeAliasDeclaration(type,TypeDefinition,Equals,ObjectType(
    PropertyType(PropertyDefinition,TypeAnnotation(TypeName)),
    PropertyType(PropertyDefinition,TypeAnnotation(TypeName)))),
  TypeAliasDeclaration(type,TypeDefinition,Equals,ObjectType(
    PropertyType(PropertyDefinition,TypeAnnotation(TypeName)),
    PropertyType(PropertyDefinition,TypeAnnotation(TypeName)))))

# Conditional Type {"dialect": "ts"}

type X<T> = T extends E ? number : A

==>

Script(
  TypeAliasDeclaration(type,TypeDefinition,TypeParamList(TypeDefinition),Equals,
    ConditionalType(TypeName,extends,TypeName,LogicOp,TypeName,LogicOp,TypeName)))

# Generic Function Type {"dialect": "ts"}

let f: <T>() => T

==>

Script(
  VariableDeclaration(let,VariableDefinition,TypeAnnotation(
    FunctionSignature(TypeParamList(TypeDefinition),ParamList,Arrow,TypeName))))

# Satisfies operator {"dialect": "ts"}

let x = 1 satisfies number

==>

Script(VariableDeclaration(let,VariableDefinition,Equals,BinaryExpression(Number,satisfies,TypeName)))

# Override modifier on properties {"dialect": "ts"}

class A {
  override accessor a;
  static override b = 1;
  override c = 2;
}

==>

Script(ClassDeclaration(class,VariableDefinition,ClassBody(
  PropertyDeclaration(override,accessor,PropertyDefinition),
  PropertyDeclaration(static,override,PropertyDefinition,Equals,Number),
  PropertyDeclaration(override,PropertyDefinition,Equals,Number))))

# Class extending expression {"dialect": "ts"}

class X extends class {} {}

==>

Script(ClassDeclaration(class,VariableDefinition,extends,ClassExpression(class,ClassBody),ClassBody))

# Declare syntax {"dialect": "ts"}

declare namespace myLib {
  function makeGreeting(s: string): string;
  let numberOfGreetings: number;
}

declare function greet(setting: GreetingSettings): void;

declare class Greeter {
  constructor(greeting: string);
  greeting: string;
  showGreeting(): void;
}

class X {
  declare foo();
  declare bar: number;
}

==>

Script(
  AmbientDeclaration(declare,NamespaceDeclaration(namespace,VariableDefinition,Block(
    FunctionDeclaration(function,VariableDefinition,ParamList(VariableDefinition,TypeAnnotation(TypeName)),
      TypeAnnotation(TypeName)),
    VariableDeclaration(let,VariableDefinition,TypeAnnotation(TypeName))))),
  AmbientDeclaration(declare,AmbientFunctionDeclaration(function,VariableDefinition,
    ParamList(VariableDefinition,TypeAnnotation(TypeName)),TypeAnnotation(VoidType(void)))),
  AmbientDeclaration(declare,ClassDeclaration(class,VariableDefinition,ClassBody(
    MethodDeclaration(PropertyDefinition,ParamList(VariableDefinition,TypeAnnotation(TypeName))),
    PropertyDeclaration(PropertyDefinition,TypeAnnotation(TypeName)),
    MethodDeclaration(PropertyDefinition,ParamList,TypeAnnotation(VoidType(void)))))),
  ClassDeclaration(class,VariableDefinition,ClassBody(
    MethodDeclaration(declare,PropertyDefinition,ParamList),
    PropertyDeclaration(declare,PropertyDefinition,TypeAnnotation(TypeName)))))

# Declare this in a Function {"dialect": "ts"}

function foo(this: User) {}

==>

Script(FunctionDeclaration(function,VariableDefinition,ParamList(this,TypeAnnotation(TypeName)),Block))

# Prefers type parameters to comparison operators {"dialect": "ts jsx"}

let a = useState<string>(1)
return 2

==>

Script(
  VariableDeclaration(let,VariableDefinition,Equals,
    CallExpression(InstantiationExpression(VariableName,TypeArgList(TypeName)),ArgList(Number))),
  ReturnStatement(return,Number))

# Type parameters vs JSX {"dialect": "jsx ts"}

let a = <T extends any>(f) => null
let b = <T,>() => 1

==>

Script(
  VariableDeclaration(let,VariableDefinition,Equals,ArrowFunction(
    TypeParamList(TypeDefinition,extends,TypeName),ParamList(VariableDefinition),Arrow,null)),
  VariableDeclaration(let,VariableDefinition,Equals,ArrowFunction(
    TypeParamList(TypeDefinition),ParamList,Arrow,Number)))

# Destructured parameters in function signature {"dialect": "ts"}

type F = ([a, b]: [number, number]) => void

==>

Script(TypeAliasDeclaration(type,TypeDefinition,Equals,FunctionSignature(
  ParamList(ArrayPattern(VariableDefinition,VariableDefinition),TypeAnnotation(TupleType(TypeName,TypeName))),
  Arrow,
  VoidType(void))))

# Instantiated expression {"dialect": "ts"}

let x = a<b>;

type Foo = Bar<typeof baz<Bug<Quux>>>;

==>

Script(
  VariableDeclaration(let,VariableDefinition,Equals,InstantiationExpression(VariableName,TypeArgList(TypeName))),
  TypeAliasDeclaration(type,TypeDefinition,Equals,ParameterizedType(TypeName,TypeArgList(
    TypeofType(typeof,InstantiationExpression(VariableName,TypeArgList(
      ParameterizedType(TypeName,TypeArgList(TypeName)))))))))

# Not instantiated {"dialect": "ts"}

let x = a<b>c

==>

Script(VariableDeclaration(let,VariableDefinition,Equals,BinaryExpression(
  BinaryExpression(VariableName,CompareOp,VariableName),CompareOp,VariableName)))

# Allows computed properties in types {"dialect": "ts"}

interface X {
  [Symbol.iterator](): Iterator<number>
  [1]: string
}

==>

Script(InterfaceDeclaration(interface,TypeDefinition,ObjectType(
  MethodType(MemberExpression(VariableName,PropertyName),ParamList,
    TypeAnnotation(ParameterizedType(TypeName,TypeArgList(TypeName)))),
  PropertyType(Number,TypeAnnotation(TypeName)))))

# Binary type operators {"dialect": "ts"}

log(foo as number, {} satisfies AbstractObjectFactory<ParticleEmitter>)

==>

Script(ExpressionStatement(CallExpression(VariableName,ArgList(
  BinaryExpression(VariableName,as,TypeName),
  BinaryExpression(ObjectExpression,satisfies,ParameterizedType(TypeName,TypeArgList(TypeName)))))))

# Allows this parameters in function types {"dialect": "ts"}

let x: (this: X, expression: string) => Promise<T[]>

==>

Script(VariableDeclaration(let,VariableDefinition,TypeAnnotation(FunctionSignature(
  ParamList(this,TypeAnnotation(TypeName),VariableDefinition,TypeAnnotation(TypeName)),
  Arrow,
  ParameterizedType(TypeName,TypeArgList(ArrayType(TypeName)))))))

"""#

@Suite(.serialized)
struct JsGrammarTests {
	@Test func expression() throws {
		let tests = try fileTests(expressionTests, "expression.txt")
		for t in tests {
			try t.run(jsParser)
		}
	}

	@Test func statement() throws {
		let tests = try fileTests(statementTests, "statement.txt")
		for t in tests {
			try t.run(jsParser)
		}
	}

	@Test func semicolon() throws {
		let tests = try fileTests(semicolonTests, "semicolon.txt")
		for t in tests {
			try t.run(jsParser)
		}
	}

	@Test func decorator() throws {
		let tests = try fileTests(decoratorTests, "decorator.txt")
		for t in tests {
			try t.run(jsParser)
		}
	}

	@Test func jsx() throws {
		let tests = try fileTests(jsxTests, "jsx.txt")
		for t in tests {
			try t.run(jsParser)
		}
	}

	@Test func typescript() throws {
		let tests = try fileTests(typescriptTests, "typescript.txt")
		for t in tests {
			try t.run(jsParser)
		}
	}
}
