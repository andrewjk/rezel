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

// MARK: - HTML Data Tables

private let selfClosers: Set<String> = [
	"area", "base", "br", "col", "command", "embed", "frame", "hr",
	"img", "input", "keygen", "link", "meta", "param", "source",
	"track", "wbr", "menuitem",
]

private let implicitlyClosed: Set<String> = [
	"dd", "li", "optgroup", "option", "p", "rp", "rt",
	"tbody", "td", "tfoot", "th", "tr",
]

private let closeOnOpen: [String: Set<String>] = [
	"dd": ["dd", "dt"],
	"dt": ["dd", "dt"],
	"li": ["li"],
	"option": ["option", "optgroup"],
	"optgroup": ["optgroup"],
	"p": [
		"address", "article", "aside", "blockquote", "dir", "div", "dl",
		"fieldset", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
		"header", "hgroup", "hr", "menu", "nav", "ol", "p", "pre",
		"section", "table", "ul",
	],
	"rp": ["rp", "rt"],
	"rt": ["rp", "rt"],
	"tbody": ["tbody", "tfoot"],
	"td": ["td", "th"],
	"tfoot": ["tbody"],
	"th": ["td", "th"],
	"thead": ["tbody", "tfoot"],
	"tr": ["tr"],
]

private let lessThan = 60
private let greaterThan = 62
private let slash = 47
private let question = 63
private let bang = 33
private let dash = 45

// MARK: - Helpers

private func htmlNameChar(_ ch: Int) -> Bool {
	return ch == 45 || ch == 46 || ch == 58 || (ch >= 65 && ch <= 90) || ch == 95 || (ch >= 97 && ch <= 122) || ch >= 161
}

private func tagNameAfter(_ input: InputStream, _ offset: Int) -> String? {
	var offset = offset
	var next = input.peek(offset)
	var name = ""
	while true {
		if !htmlNameChar(next) { break }
		name += String(UnicodeScalar(next)!)
		offset += 1
		next = input.peek(offset)
	}
	if !name.isEmpty {
		return name.lowercased()
	}
	return next == question || next == bang ? nil : ""
}

private func inForeignElement(_ context: ElementContext?) -> Bool {
	var cx = context
	while let c = cx {
		if c.name == "svg" || c.name == "math" { return true }
		cx = c.parent
	}
	return false
}

private func termName(_ stack: Stack, _ term: Int) -> String {
	return stack.parser.termNames?[term] ?? ""
}

private func dialectIndex(_ parser: LRParser, _ name: String) -> Int? {
	let keys = Array(parser.dialects.keys)
	return keys.firstIndex(of: name)
}

// MARK: - External Tokenizer Factory

private func makeHtmlExternalTokenizer(name: String, terms: [String: Int]) -> TokenizerProtocol {
	if name == "tagStart" {
		let StartTag = terms["StartTag"]!
		let StartSelfClosingTag = terms["StartSelfClosingTag"]!
		let StartScriptTag = terms["StartScriptTag"]!
		let StartStyleTag = terms["StartStyleTag"]!
		let StartTextareaTag = terms["StartTextareaTag"]!
		let StartCloseTag = terms["StartCloseTag"]!
		let NoMatchStartCloseTag = terms["NoMatchStartCloseTag"]!
		let MismatchedStartCloseTag = terms["MismatchedStartCloseTag"]!
		let missingCloseTag = terms["missingCloseTag"]!
		let IncompleteTag = terms["IncompleteTag"]!
		let IncompleteCloseTag = terms["IncompleteCloseTag"]!

		return ExternalTokenizer({ input, stack in
			if input.next != lessThan {
				if input.next < 0, stack.context != nil {
					input.acceptToken(missingCloseTag)
				}
				return
			}
			input.advance()
			let close = input.next == slash
			if close { input.advance() }
			guard let name = tagNameAfter(input, 0) else { return }
			if name.isEmpty {
				input.acceptToken(close ? IncompleteCloseTag : IncompleteTag)
				return
			}

			let parent = (stack.context as? ElementContext)?.name
			if close {
				if name == parent {
					input.acceptToken(StartCloseTag)
				} else if let parent = parent, implicitlyClosed.contains(parent) {
					input.acceptToken(missingCloseTag, endOffset: -2)
				} else if let noMatchIdx = dialectIndex(stack.parser, "noMatch"),
				          stack.dialectEnabled(noMatchIdx)
				{
					input.acceptToken(NoMatchStartCloseTag)
				} else {
					var cx = stack.context as? ElementContext
					while let c = cx {
						if c.name == name { return }
						cx = c.parent
					}
					input.acceptToken(MismatchedStartCloseTag)
				}
			} else {
				if name == "script" {
					input.acceptToken(StartScriptTag)
				} else if name == "style" {
					input.acceptToken(StartStyleTag)
				} else if name == "textarea" {
					input.acceptToken(StartTextareaTag)
				} else if selfClosers.contains(name) {
					input.acceptToken(StartSelfClosingTag)
				} else if let parent = parent,
				          let closeSet = closeOnOpen[parent],
				          closeSet.contains(name)
				{
					input.acceptToken(missingCloseTag, endOffset: -1)
				} else {
					input.acceptToken(StartTag)
				}
			}
		}, contextual: true)
	}

	if name == "endTag" {
		let EndTag = terms["EndTag"]!
		let SelfClosingEndTag = terms["SelfClosingEndTag"]!

		return ExternalTokenizer { input, stack in
			if input.next == slash, input.peek(1) == greaterThan {
				let selfClosing: Bool
				if let idx = dialectIndex(stack.parser, "selfClosing"), stack.dialectEnabled(idx) {
					selfClosing = true
				} else {
					selfClosing = inForeignElement(stack.context as? ElementContext)
				}
				input.acceptToken(selfClosing ? SelfClosingEndTag : EndTag, endOffset: 2)
			} else if input.next == greaterThan {
				input.acceptToken(EndTag, endOffset: 1)
			}
		}
	}

	if name == "commentContent" {
		let commentContent = terms["commentContent"]!

		return ExternalTokenizer { input, _ in
			var dashes = 0
			for i in 0 ..< Int.max {
				if input.next < 0 {
					if i > 0 { input.acceptToken(commentContent) }
					break
				}
				if input.next == dash {
					dashes += 1
				} else if input.next == greaterThan, dashes >= 2 {
					if i >= 3 {
						input.acceptToken(commentContent, endOffset: -2)
					}
					break
				} else {
					dashes = 0
				}
				input.advance()
			}
		}
	}

	if name == "scriptTokens" {
		let scriptText = terms["scriptText"]!
		let StartCloseScriptTag = terms["StartCloseScriptTag"]!
		return makeContentTokenizer("script", textToken: scriptText, endToken: StartCloseScriptTag)
	}

	if name == "styleTokens" {
		let styleText = terms["styleText"]!
		let StartCloseStyleTag = terms["StartCloseStyleTag"]!
		return makeContentTokenizer("style", textToken: styleText, endToken: StartCloseStyleTag)
	}

	if name == "textareaTokens" {
		let textareaText = terms["textareaText"]!
		let StartCloseTextareaTag = terms["StartCloseTextareaTag"]!
		return makeContentTokenizer("textarea", textToken: textareaText, endToken: StartCloseTextareaTag)
	}

	fatalError("Unknown HTML external tokenizer: \(name)")
}

private func makeContentTokenizer(_ tag: String, textToken: Int, endToken: Int) -> TokenizerProtocol {
	let tagChars = Array(tag.unicodeScalars.map { Int($0.value) })
	let lastState = 2 + tagChars.count

	return ExternalTokenizer { input, _ in
		var state = 0
		var matchedLen = 0
		var i = 0
		while true {
			if input.next < 0 {
				if i > 0 { input.acceptToken(textToken) }
				break
			}
			if (state == 0 && input.next == lessThan) ||
				(state == 1 && input.next == slash) ||
				(state >= 2 && state < lastState && input.next == tagChars[state - 2])
			{
				state += 1
				matchedLen += 1
			} else if state == lastState, input.next == greaterThan {
				if i > matchedLen {
					input.acceptToken(textToken, endOffset: -matchedLen)
				} else {
					input.acceptToken(endToken, endOffset: -(matchedLen - 2))
				}
				break
			} else if input.next == 10 || input.next == 13, i > 0 {
				input.acceptToken(textToken, endOffset: 1)
				break
			} else {
				state = 0
				matchedLen = 0
			}
			input.advance()
			i += 1
		}
	}
}

// MARK: - Context Tracker

private nonisolated(unsafe) let htmlElementContext = ContextTracker(
	start: Any?.none as Any,
	shift: { context, term, stack, input in
		let name = termName(stack, term)
		if name == "StartTag" || name == "StartSelfClosingTag" || name == "StartScriptTag" || name == "StartStyleTag" || name == "StartTextareaTag" {
			let tagName = tagNameAfter(input, 1) ?? ""
			return ElementContext(name: tagName, parent: context as? ElementContext) as Any
		}
		return context
	},
	reduce: { context, term, stack, _ in
		if termName(stack, term) == "Element", let ctx = context as? ElementContext {
			return ctx.parent as Any
		}
		return context
	},
	reuse: { context, node, stack, input in
		let type = node.type.id
		let name = stack.parser.termNames?[type] ?? ""
		if name == "StartTag" || name == "OpenTag" {
			let tagName = tagNameAfter(input, 1) ?? ""
			return ElementContext(name: tagName, parent: context as? ElementContext) as Any
		}
		return context
	},
	hash: { context in
		guard let ctx = context as? ElementContext else { return 0 }
		var h = 0
		var c: ElementContext? = ctx
		while let cur = c {
			h = h &* 11 &+ cur.name.hashValue
			c = cur.parent
		}
		return h
	},
	strict: false
)

// MARK: - Highlighting

private nonisolated(unsafe) let htmlHighlighting = styleTags([
	"Text RawText IncompleteTag IncompleteCloseTag": hlContent,
	"StartTag StartCloseTag SelfClosingEndTag EndTag": hlBracket,
	"TagName": hlTypeName,
	"MismatchedCloseTag/TagName": [hlTypeName, (hlTags["invalid"] as! Tag)],
	"AttributeName": hlPropertyName,
	"AttributeValue UnquotedAttributeValue": (hlTags["attributeValue"] as! Tag),
	"Is": (hlTags["definitionKeyword"] as! Tag),
	"EntityReference CharacterReference": (hlTags["character"] as! Tag),
	"Comment": hlComment,
	"ProcessingInst": (hlTags["processingInstruction"] as! Tag),
	"DoctypeDecl": (hlTags["documentMeta"] as! Tag),
])

// MARK: - Build Parser

public let htmlParser: LRParser = {
	let externals: [String: TokenizerProtocol] = [
		"scriptTokens": makeHtmlExternalTokenizer(name: "scriptTokens", terms: HtmlParserData.termTable),
		"styleTokens": makeHtmlExternalTokenizer(name: "styleTokens", terms: HtmlParserData.termTable),
		"textareaTokens": makeHtmlExternalTokenizer(name: "textareaTokens", terms: HtmlParserData.termTable),
		"endTag": makeHtmlExternalTokenizer(name: "endTag", terms: HtmlParserData.termTable),
		"tagStart": makeHtmlExternalTokenizer(name: "tagStart", terms: HtmlParserData.termTable),
		"commentContent": makeHtmlExternalTokenizer(name: "commentContent", terms: HtmlParserData.termTable),
	]
	let spec = HtmlParserData.makeSpec(
		externals: externals,
		propSources: [htmlHighlighting],
		context: htmlElementContext
	)
	return LRParser(spec: spec)
}()
