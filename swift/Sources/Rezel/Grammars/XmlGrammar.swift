import Foundation

// MARK: - Element Context

private class ElementContext {
	let name: String
	let parent: ElementContext?

	init(name: String, parent: ElementContext?) {
		self.name = name
		self.parent = parent
	}
}

// MARK: - Helpers

private func xmlNameChar(_ ch: Int) -> Bool {
	return ch == 45 || ch == 46 || ch == 58 || (ch >= 65 && ch <= 90) || ch == 95 || (ch >= 97 && ch <= 122) || ch >= 161
}

private func isSpaceChar(_ ch: Int) -> Bool {
	return ch == 9 || ch == 10 || ch == 13 || ch == 32
}

private func xmlTagNameAfter(_ input: InputStream, _ offset: Int) -> String? {
	var offset = offset
	while isSpaceChar(input.peek(offset)) {
		offset += 1
	}
	var name = ""
	while true {
		let next = input.peek(offset)
		if !xmlNameChar(next) { break }
		name += String(UnicodeScalar(next)!)
		offset += 1
	}
	return name.isEmpty ? nil : name
}

private func xmlTermName(_ stack: Stack, _ term: Int) -> String {
	return stack.parser.termNames?[term] ?? ""
}

// MARK: - External Tokenizer Factory

private func makeXmlExternalTokenizer(name: String, terms: [String: Int]) -> TokenizerProtocol {
	if name == "startTag" {
		let StartTag = terms["StartTag"]!
		let StartCloseTag = terms["StartCloseTag"]!
		let mismatchedStartCloseTag = terms["mismatchedStartCloseTag"]!
		let incompleteStartCloseTag = terms["incompleteStartCloseTag"]!
		let MissingCloseTag = terms["MissingCloseTag"]!

		return ExternalTokenizer({ input, stack in
			if input.next != 60 /* '<' */ { return }
			input.advance()
			if input.next == 47 /* '/' */ {
				input.advance()
				guard let tagName = xmlTagNameAfter(input, 0) else {
					input.acceptToken(incompleteStartCloseTag)
					return
				}
				let cx = stack.context as? ElementContext
				if let cx = cx, tagName == cx.name {
					input.acceptToken(StartCloseTag)
					return
				}
				var c = cx
				while let cur = c {
					if cur.name == tagName {
						input.acceptToken(MissingCloseTag, endOffset: -2)
						return
					}
					c = cur.parent
				}
				input.acceptToken(mismatchedStartCloseTag)
			} else if input.next != 33 /* '!' */, input.next != 63 /* '?' */ {
				input.acceptToken(StartTag)
			}
		}, contextual: true)
	}

	if name == "commentContent" {
		let commentContent = terms["commentContent"]!
		return makeScanToTokenizer(commentContent, end: "-->")
	}

	if name == "piContent" {
		let piContent = terms["piContent"]!
		return makeScanToTokenizer(piContent, end: "?>")
	}

	if name == "cdataContent" {
		let cdataContent = terms["cdataContent"]!
		return makeScanToTokenizer(cdataContent, end: "]]>")
	}

	fatalError("Unknown XML external tokenizer: \(name)")
}

private func makeScanToTokenizer(_ token: Int, end: String) -> TokenizerProtocol {
	let endScalars = Array(end.unicodeScalars.map { Int($0.value) })
	let first = endScalars[0]

	return ExternalTokenizer { input, _ in
		var len = 0
		while true {
			if input.next < 0 { break }
			if input.next == first {
				var matched = true
				for i in 1 ..< endScalars.count {
					if input.peek(i) != endScalars[i] { matched = false; break }
				}
				if matched { break }
			}
			input.advance()
			len += 1
		}
		if len > 0 { input.acceptToken(token) }
	}
}

// MARK: - Context Tracker

private nonisolated(unsafe) let xmlElementContext = ContextTracker(
	start: Any?.none as Any,
	shift: { context, term, stack, input in
		if xmlTermName(stack, term) == "StartTag" {
			let tagName = xmlTagNameAfter(input, 1) ?? ""
			return ElementContext(name: tagName, parent: context as? ElementContext) as Any
		}
		return context
	},
	reduce: { context, term, stack, _ in
		if xmlTermName(stack, term) == "Element", let ctx = context as? ElementContext {
			return ctx.parent as Any
		}
		return context
	},
	reuse: { context, node, stack, input in
		let type = node.type.id
		let name = stack.parser.termNames?[type] ?? ""
		if name == "StartTag" || name == "OpenTag" {
			let tagName = xmlTagNameAfter(input, 1) ?? ""
			return ElementContext(name: tagName, parent: context as? ElementContext) as Any
		}
		return context
	},
	strict: false
)

// MARK: - Highlighting

private nonisolated(unsafe) let specialMod = hlTags["special"] as! (Tag) -> Tag

private nonisolated(unsafe) let xmlHighlighting = styleTags([
	"Text": hlContent,
	"StartTag StartCloseTag EndTag SelfCloseEndTag": hlTags["angleBracket"] as Any,
	"TagName": hlTags["tagName"] as Any,
	"MismatchedCloseTag/TagName": [hlTags["tagName"] as! Tag, hlTags["invalid"] as! Tag],
	"AttributeName": hlTags["attributeName"] as Any,
	"AttributeValue": hlTags["attributeValue"] as Any,
	"Is": hlTags["definitionOperator"] as Any,
	"EntityReference CharacterReference": hlTags["character"] as Any,
	"Comment": hlTags["blockComment"] as Any,
	"ProcessingInst": hlTags["processingInstruction"] as Any,
	"DoctypeDecl": hlTags["documentMeta"] as Any,
	"Cdata": specialMod(hlString),
])

// MARK: - Build Parser

public let xmlParser: LRParser = {
	let externals: [String: TokenizerProtocol] = [
		"startTag": makeXmlExternalTokenizer(name: "startTag", terms: XmlParserData.termTable),
		"commentContent": makeXmlExternalTokenizer(name: "commentContent", terms: XmlParserData.termTable),
		"piContent": makeXmlExternalTokenizer(name: "piContent", terms: XmlParserData.termTable),
		"cdataContent": makeXmlExternalTokenizer(name: "cdataContent", terms: XmlParserData.termTable),
	]
	let spec = XmlParserData.makeSpec(
		externals: externals,
		propSources: [xmlHighlighting],
		context: xmlElementContext
	)
	return LRParser(spec: spec)
}()
