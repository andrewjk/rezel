import Foundation
@testable import Rezel
import Testing

private let tagsTests = #"""

# Regular tag

<foo>bar</foo>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),Text,CloseTag(StartCloseTag,TagName,EndTag)))

# Nested tag

<a><b>c</b><br></a>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),
  Element(OpenTag(StartTag,TagName,EndTag),Text,CloseTag(StartCloseTag,TagName,EndTag)),
  Element(SelfClosingTag(StartTag,TagName,EndTag)),
  CloseTag(StartCloseTag,TagName,EndTag)))

# Attribute

<br foo="bar">

==>

Document(Element(SelfClosingTag(StartTag,TagName,Attribute(AttributeName,Is,AttributeValue),EndTag)))

# Multiple attributes

<a x="one" y="two" z="three"></a>

==>

Document(Element(OpenTag(StartTag,TagName,
  Attribute(AttributeName,Is,AttributeValue),
  Attribute(AttributeName,Is,AttributeValue),
  Attribute(AttributeName,Is,AttributeValue),EndTag),
  CloseTag(StartCloseTag,TagName,EndTag)))

# Value-less attributes

<a x y="one" z></a>

==>

Document(Element(OpenTag(StartTag,TagName,
  Attribute(AttributeName),
  Attribute(AttributeName,Is,AttributeValue),
  Attribute(AttributeName),EndTag),
  CloseTag(StartCloseTag,TagName,EndTag)))

# Unquoted attributes

<a x=one y z=two></a>

==>

Document(Element(OpenTag(StartTag,TagName,
  Attribute(AttributeName,Is,UnquotedAttributeValue),
  Attribute(AttributeName),
  Attribute(AttributeName,Is,UnquotedAttributeValue),EndTag),
  CloseTag(StartCloseTag,TagName,EndTag)))

# Unquoted attributes with slashes

<link as=font crossorigin=anonymous href=/fonts/google-sans/regular/latin.woff2 rel=preload>

==>

Document(Element(SelfClosingTag(StartTag,TagName,
  Attribute(AttributeName,Is,UnquotedAttributeValue),
  Attribute(AttributeName,Is,UnquotedAttributeValue),
  Attribute(AttributeName,Is,UnquotedAttributeValue),
  Attribute(AttributeName,Is,UnquotedAttributeValue),
EndTag)))

# Single-quoted attributes

<link x='one' z='two&amp;'>

==>

Document(Element(SelfClosingTag(StartTag, TagName,
  Attribute(AttributeName, Is, AttributeValue),
  Attribute(AttributeName, Is, AttributeValue(EntityReference)),
EndTag)))

# Entities

<a attr="one&amp;two">&amp;&#67;</a>

==>

Document(Element(OpenTag(StartTag,TagName,
  Attribute(AttributeName,Is,AttributeValue(EntityReference)),EndTag),
  EntityReference,CharacterReference,
  CloseTag(StartCloseTag,TagName,EndTag)))

# Doctype

<!doctype html>
<doc></doc>

==>

Document(DoctypeDecl,Text,Element(OpenTag(StartTag,TagName,EndTag),CloseTag(StartCloseTag,TagName,EndTag)))

# Processing instructions

<?foo?><bar><?baz?></bar>

==>

Document(ProcessingInst,Element(OpenTag(StartTag,TagName,EndTag),ProcessingInst,CloseTag(StartCloseTag,TagName,EndTag)))

# Comments

<!-- top comment -->
<element><!-- inner comment --> text</element>
<!---->
<!--
-->

==>

Document(Comment,Text,Element(OpenTag(StartTag,TagName,EndTag),Comment,Text,CloseTag(StartCloseTag,TagName,EndTag)),Text,Comment,Text,Comment)

# Mismatched tag

<a></b>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),MismatchedCloseTag(StartCloseTag,TagName,EndTag)))

# Unclosed tag

<a>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag)))

# Ignore pseudo-xml self-closers

<br/>

==>

Document(Element(SelfClosingTag(StartTag,TagName,EndTag)))

# Unclosed implicitly closed tag

<p>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag)))

# Nested mismatched tag

<a><b><c></c></x></a>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),
  Element(OpenTag(StartTag,TagName,EndTag),
    Element(OpenTag(StartTag,TagName,EndTag),CloseTag(StartCloseTag,TagName,EndTag)),
    MismatchedCloseTag(StartCloseTag,TagName,EndTag),
    ⚠),
  CloseTag(StartCloseTag,TagName,EndTag)))

# Incomplete close tag

<html><body></</html>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),
  Element(OpenTag(StartTag,TagName,EndTag), IncompleteCloseTag, ⚠),
  CloseTag(StartCloseTag,TagName,EndTag)))

# Re-synchronize close tags

<a><b><c></x></c></a>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),
  Element(OpenTag(StartTag,TagName,EndTag),
    Element(OpenTag(StartTag,TagName,EndTag),
      MismatchedCloseTag(StartCloseTag,TagName,EndTag),
      CloseTag(StartCloseTag,TagName,EndTag)),
    ⚠),
  CloseTag(StartCloseTag,TagName,EndTag)))

# Top-level mismatched close tag

<a></a></a>

==>

Document(
  Element(OpenTag(StartTag,TagName,EndTag),CloseTag(StartCloseTag,TagName,EndTag)),
  MismatchedCloseTag(StartCloseTag,TagName,EndTag))

# Self-closing tags

<a><img src=blah></a>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),
  Element(SelfClosingTag(StartTag,TagName,Attribute(AttributeName,Is,UnquotedAttributeValue),EndTag)),
  CloseTag(StartCloseTag,TagName,EndTag)))

# Implicitly closed

<dl><dd>Hello</dl>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),
  Element(OpenTag(StartTag,TagName,EndTag),Text),
  CloseTag(StartCloseTag,TagName,EndTag)))

# Closed by sibling

<div>
  <p>Foo
  <p>Bar
</div>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),
  Text,
  Element(OpenTag(StartTag,TagName,EndTag),Text),
  Element(OpenTag(StartTag,TagName,EndTag),Text),
  CloseTag(StartCloseTag,TagName,EndTag)))

# Closed by sibling at top

<p>Foo
<p>Bar

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),Text),Element(OpenTag(StartTag,TagName,EndTag),Text))

# Textarea

<p>Enter something: <textarea code-lang=javascript>function foo() {
  return "</bar>"
}</textarea>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),
  Text,
  Element(OpenTag(StartTag,TagName,Attribute(AttributeName,Is,UnquotedAttributeValue),EndTag),
    TextareaText,
  CloseTag(StartCloseTag,TagName,EndTag))))

# Script

<script>This is not an entity: &lt;</script>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),ScriptText,CloseTag(StartCloseTag,TagName,EndTag)))

# Doesn't get confused by a stray ampersand

<html>a&b</html>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),Text,InvalidEntity,Text,CloseTag(StartCloseTag,TagName,EndTag)))

# Can ignore mismatches {"dialect": "noMatch"}

<div>foo</p>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),Text,CloseTag(StartCloseTag,TagName,EndTag)))

# Can handle lone close tags {"dialect": "noMatch"}

</strong>

==>

Document(CloseTag(StartCloseTag,TagName,EndTag))

# Parses ampersands in attributes

<img src="foo&bar">

==>

Document(Element(SelfClosingTag(StartTag, TagName, Attribute(AttributeName, Is, AttributeValue(InvalidEntity)), EndTag)))

# Supports self-closing dialect {"dialect": "selfClosing"}

<section><image id=i2 /></section>

==>

Document(Element(
  OpenTag(StartTag,TagName,EndTag),
  Element(SelfClosingTag(StartTag,TagName,Attribute(AttributeName,Is,UnquotedAttributeValue),SelfClosingEndTag)),
  CloseTag(StartCloseTag,TagName,EndTag)))

# Allows self-closing in foreign elements

<div><svg><circle/></svg></div>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),
  Element(OpenTag(StartTag,TagName,EndTag),
    Element(SelfClosingTag(StartTag,TagName,SelfClosingEndTag)),
    CloseTag(StartCloseTag,TagName,EndTag)),
  CloseTag(StartCloseTag,TagName,EndTag)))

# Parses multiple unfinished tags in a row

<div
<div
<div

==>

Document(Element(OpenTag(StartTag,TagName,⚠),
  Element(OpenTag(StartTag,TagName,⚠),
    Element(OpenTag(StartTag,TagName,⚠)))))

# Allows self-closing on special tags {"dialect": "selfClosing"}

<body>
  <br/>
  <textarea/>
  <script/>
  <style/>
</body>

==>

Document(Element(
  OpenTag(StartTag,TagName,EndTag),
  Text,
  Element(SelfClosingTag(StartTag,TagName,SelfClosingEndTag)),
  Text,
  Element(SelfClosingTag(StartTag,TagName,SelfClosingEndTag)),
  Text,
  Element(SelfClosingTag(StartTag,TagName,SelfClosingEndTag)),
  Text,
  Element(SelfClosingTag(StartTag,TagName,SelfClosingEndTag)),
  Text,
  CloseTag(StartCloseTag,TagName,EndTag)))

# Only treats less-than as opening a tag when followed by a name

< div>x

==>

Document(IncompleteTag,Text)

"""#

private let vueTests = #"""

# Parses Vue builtin directives

<span v-text="msg"></span>

==>

Document(
  Element(
    OpenTag(StartTag, TagName, Attribute(AttributeName, Is, AttributeValue), EndTag),
    CloseTag(StartCloseTag, TagName, EndTag)))

# Parses Vue :is shorthand syntax

<Component :is="view"></Component>

==>

Document(
  Element(
    OpenTag(StartTag, TagName, Attribute(AttributeName, Is, AttributeValue),EndTag),
    CloseTag(StartCloseTag, TagName, EndTag)))

# Parses Vue @click shorthand syntax

<button @click="handler()">Click me</button>

==>

Document(
  Element(
    OpenTag(StartTag, TagName, Attribute(AttributeName, Is, AttributeValue), EndTag),
    Text,
    CloseTag(StartCloseTag, TagName, EndTag)))

# Parses Vue @submit.prevent shorthand syntax

<form @submit.prevent="onSubmit"></form>

==>

Document(
  Element(
    OpenTag(StartTag, TagName, Attribute(AttributeName, Is, AttributeValue), EndTag),
    CloseTag(StartCloseTag, TagName, EndTag)))

# Parses Vue Dynamic Arguments

<a v-bind:[attributeName]="url">Link</a>

==>

Document(
  Element(
    OpenTag(StartTag, TagName, Attribute(AttributeName, Is, AttributeValue), EndTag),
    Text,
    CloseTag(StartCloseTag, TagName, EndTag)))

"""#

private func isJsType(_ type: String?) -> Bool {
	guard let type = type else { return true }
	let lower = type.lowercased()
	if lower == "module" { return true }
	if lower.hasPrefix("text/") || lower.hasPrefix("application/") {
		let rest = String(lower[lower.index(lower.startIndex, offsetBy: lower.hasPrefix("text/") ? 5 : 12)...])
		if rest.hasPrefix("x-") {
			let after = String(rest[rest.index(rest.startIndex, offsetBy: 2)...])
			if after == "javascript" || after == "ecmascript" { return true }
		} else if rest == "javascript" || rest == "ecmascript" {
			return true
		}
	}
	return false
}

private func extractTypeAttr(_ openTag: SyntaxNode, _ input: InputProtocol) -> String? {
	var child = openTag.firstChild
	while let c = child {
		if c.name == "Attribute" {
			let nameNode = c.firstChild
			if let nameNode = nameNode, input.read(from: nameNode.from, to: nameNode.to) == "type" {
				let valNode = nameNode.nextSibling?.nextSibling
				if let valNode = valNode {
					return input.read(from: valNode.from, to: valNode.to)
				}
				return nil
			}
		}
		child = c.nextSibling
	}
	return nil
}

private func wrapMixed(_ mixed: @escaping (AnyPartialParse, InputProtocol, [TreeFragment], [CommonRange]) -> AnyPartialParse) -> ParseWrapper {
	return { parse, input, fragments, ranges in
		mixed(parse, input, fragments, ranges)
	}
}

private nonisolated(unsafe) let mixedHtmlParser: Parser = htmlParser.configure(
	wrap: wrapMixed(parseMixed { node, input in
		if node.name == "ScriptText" {
			let openTag = node.node.parent?.firstChild
			if let openTag = openTag {
				if isJsType(extractTypeAttr(openTag, input)) {
					return NestedParse(parser: jsParser, bracketed: false)
				}
			}
			return nil
		}
		return nil
	})
)

private let mixedTests = #"""

# Doesn't parse VB as JS

<script type="text/visualbasic">let something = 20</script>

==>

Document(Element(OpenTag(StartTag,TagName,Attribute(AttributeName,Is,AttributeValue),EndTag),
  ScriptText,
  CloseTag(StartCloseTag,TagName,EndTag)))

# Does parse type-less script tags as JS

<script>/foo/</script>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),
  Script(ExpressionStatement(RegExp)),
  CloseTag(StartCloseTag,TagName,EndTag)))

# Still doesn't end script tags on closing tags

<script type=something></foo></script>

==>

Document(Element(OpenTag(StartTag,TagName,Attribute(AttributeName,Is,UnquotedAttributeValue),EndTag),
  ScriptText,
  CloseTag(StartCloseTag,TagName,EndTag)))

# Missing end tag

<html><script>null

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),
  Element(OpenTag(StartTag,TagName,EndTag),
    Script(ExpressionStatement(null)))))

# JS with script type

<script type="text/javascript">console.log(2)</script>

==>

Document(Element(OpenTag(StartTag,TagName,Attribute(AttributeName,Is,AttributeValue),EndTag),
  Script(...),
  CloseTag(StartCloseTag,TagName,EndTag)))

# JS with unquoted script type

<script type=module>console.log(2)</script>

==>

Document(Element(OpenTag(StartTag,TagName,Attribute(AttributeName,Is,UnquotedAttributeValue),EndTag),
  Script(...),
  CloseTag(StartCloseTag,TagName,EndTag)))

# Error in JS

<script>a b</script>

==>

Document(Element(OpenTag(StartTag,TagName,EndTag),
  Script(...),
  CloseTag(StartCloseTag,TagName,EndTag)))

"""#

private func checkIncremental(_ doc: String, action: (String, Int, String?), prev: Tree? = nil) throws {
	let parser = htmlParser.configure(bufferLength: 2)
	let prevAST = prev ?? parser.parse(input: doc)

	var newDoc: String
	let change: ChangedRange

	let (tp, pos, txt) = action
	if tp == "insert" {
		let idx = doc.index(doc.startIndex, offsetBy: pos)
		newDoc = String(doc[..<idx]) + txt! + String(doc[idx...])
		change = ChangedRange(fromA: pos, toA: pos, fromB: pos, toB: pos + txt!.count)
	} else if tp == "del" {
		let idx = doc.index(doc.startIndex, offsetBy: pos)
		newDoc = String(doc[..<idx]) + String(doc[doc.index(after: idx)...])
		change = ChangedRange(fromA: pos, toA: pos + 1, fromB: pos, toB: pos)
	} else {
		let idx = doc.index(doc.startIndex, offsetBy: pos)
		newDoc = String(doc[..<idx]) + txt! + String(doc[doc.index(after: idx)...])
		change = ChangedRange(fromA: pos, toA: pos + 1, fromB: pos, toB: pos + txt!.count)
	}

	let fragments = TreeFragment.applyChanges(TreeFragment.addTree(prevAST), changes: [change], minGap: 2)
	let ast = parser.parse(input: newDoc, fragments: fragments)
	let orig = parser.parse(input: newDoc)
	if ast.description != orig.description {
		throw NSError(domain: "incremental", code: 1, userInfo: [
			NSLocalizedDescriptionKey: "Mismatch:\n  \(ast)\nvs\n  \(orig)\ndocument: \(doc)",
		])
	}
}

@Suite(.serialized)
struct HtmlGrammarTests {
	@Test func tags() throws {
		let tests = try fileTests(tagsTests, "tags.txt")
		for t in tests {
			try t.run(htmlParser)
		}
	}

	@Test func vue() throws {
		let tests = try fileTests(vueTests, "vue.txt")
		for t in tests {
			try t.run(htmlParser)
		}
	}

	@Test func mixed() throws {
		let tests = try fileTests(mixedTests, "mixed.txt")
		for t in tests {
			try t.run(mixedHtmlParser)
		}
	}

	@Test("doesn't get confused by reused opening tags")
	func incrementalReusedTags() throws {
		try checkIncremental("<code><code>mgnbni</code></code>", action: ("del", 29, nil))
	}

	@Test("can handle a renamed opening tag after a self-closing")
	func incrementalRenamedTag() throws {
		try checkIncremental("<p>one two three four five six seven<p>eight", action: ("replace", 37, "a"))
	}

	@Test("is okay with nameless elements")
	func incrementalNameless() throws {
		try checkIncremental("<body><code><img></code><>body>", action: ("replace", 14, ">"))
		try checkIncremental("abcde<>fghij<", action: ("replace", 12, ">"))
	}

	@Test("doesn't get confused by an invalid close tag receiving a matching open tag")
	func incrementalInvalidCloseTag() throws {
		try checkIncremental("<div><p>foo</body>", action: ("insert", 0, "<body>"))
	}
}
