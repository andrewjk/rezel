import Foundation

// MARK: - Context types

private let yamlType_Top = 0
private let yamlType_Seq = 1
private let yamlType_Map = 2
private let yamlType_Flow = 3
private let yamlType_Lit = 4

// MARK: - Character helpers

private func yamlIsNonBreakSpace(_ ch: Int) -> Bool {
	ch == 32 || ch == 9
}

private func yamlIsBreakSpace(_ ch: Int) -> Bool {
	ch == 10 || ch == 13
}

private func yamlIsSpace(_ ch: Int) -> Bool {
	yamlIsNonBreakSpace(ch) || yamlIsBreakSpace(ch)
}

private func yamlIsSep(_ ch: Int) -> Bool {
	ch < 0 || yamlIsSpace(ch)
}

private func yamlUriChar(_ ch: Int) -> Bool {
	return ch > 32 && ch < 127 && ch != 34 && ch != 37 && ch != 44 && ch != 60 &&
		ch != 62 && ch != 92 && ch != 94 && ch != 96 && ch != 123 && ch != 124 && ch != 125
}

private func yamlHexChar(_ ch: Int) -> Bool {
	return (ch >= 48 && ch <= 57) || (ch >= 97 && ch <= 102) || (ch >= 65 && ch <= 70)
}

// MARK: - Char table

// "Safe char" info for char codes 33 to 125. s: safe, i: indicator, f: flow indicator
private let yamlCharTable = Array("iiisiiissisfissssssssssssisssiiissssssssssssssssssssssssssfsfssissssssssssssssssssssssssssfif")

private func yamlCharTag(_ ch: Int) -> Character {
	if ch < 33 { return "u" }
	if ch > 125 { return "s" }
	return yamlCharTable[ch - 33]
}

private func yamlIsSafe(_ ch: Int, inFlow: Bool) -> Bool {
	let tag = yamlCharTag(ch)
	return tag != "u" && !(inFlow && tag == "f")
}

// MARK: - YamlContext

private class YamlContext {
	let parent: YamlContext?
	let depth: Int
	let type: Int
	let hashValue: Int

	init(parent: YamlContext?, depth: Int, type: Int) {
		self.parent = parent
		self.depth = depth
		self.type = type
		let parentHash = parent?.hashValue ?? 0
		hashValue = parentHash &+ (parentHash << 8) &+ depth &+ (depth << 4) &+ type
	}
}

// MARK: - Scanning helpers

private func yamlFindColumn(_ input: InputStream, _ pos: Int) -> Int {
	var col = 0
	var p = pos - input.pos - 1
	while true {
		let ch = input.peek(p)
		if yamlIsBreakSpace(ch) || ch == -1 { return col }
		p -= 1
		col += 1
	}
}

private func yamlThree(_ input: InputStream, _ ch: Int, _ off: Int = 0) -> Bool {
	return input.peek(off) == ch && input.peek(off + 1) == ch && input.peek(off + 2) == ch && yamlIsSep(input.peek(off + 3))
}

@discardableResult
private func yamlReadUriChar(_ input: InputStream, quoted: Bool) -> Bool {
	if input.next == 37 {
		input.advance()
		if yamlHexChar(input.next) { input.advance() }
		if yamlHexChar(input.next) { input.advance() }
		return true
	} else if yamlUriChar(input.next) || (quoted && input.next == 44) {
		input.advance()
		return true
	}
	return false
}

private func yamlReadTag(_ input: InputStream) {
	input.advance()
	if input.next == 60 {
		input.advance()
		while true {
			if !yamlReadUriChar(input, quoted: true) {
				if input.next == 62 { input.advance() }
				break
			}
		}
	} else {
		while yamlReadUriChar(input, quoted: false) {}
	}
}

private func yamlReadAnchor(_ input: InputStream) {
	input.advance()
	while !yamlIsSep(input.next), yamlCharTag(input.next) != "f" {
		input.advance()
	}
}

@discardableResult
private func yamlReadQuoted(_ input: InputStream, scan: Bool) -> Bool {
	let quote = input.next
	var lineBreak = false
	let start = input.pos
	input.advance()
	while true {
		let ch = input.next
		if ch < 0 { break }
		input.advance()
		if ch == quote {
			if ch == 39 {
				if input.next == 39 { input.advance() }
				else { break }
			} else {
				break
			}
		} else if ch == 92 && quote == 34 {
			if input.next >= 0 { input.advance() }
		} else if yamlIsBreakSpace(ch) {
			if scan { return false }
			lineBreak = true
		} else if scan && input.pos >= start + 1024 {
			return false
		}
	}
	return !lineBreak
}

private func yamlScanBrackets(_ input: InputStream) -> Bool {
	var stack: [Int] = []
	let end = input.pos + 1024
	while true {
		if input.next == 91 || input.next == 123 {
			stack.append(input.next)
			input.advance()
		} else if input.next == 39 || input.next == 34 {
			if !yamlReadQuoted(input, scan: true) { return false }
		} else if input.next == 93 || input.next == 125 {
			if stack.last != input.next - 2 { return false }
			stack.removeLast()
			input.advance()
			if stack.isEmpty { return true }
		} else if input.next < 0 || input.pos > end || yamlIsBreakSpace(input.next) {
			return false
		} else {
			input.advance()
		}
	}
}

@discardableResult
private func yamlReadPlain(_ input: InputStream, scan: Bool, inFlow: Bool, indent: Int) -> Bool {
	if yamlCharTag(input.next) == "s" ||
		(input.next == 63 || input.next == 58 || input.next == 45) &&
		yamlIsSafe(input.peek(1), inFlow: inFlow)
	{
		input.advance()
	} else {
		return false
	}
	let start = input.pos
	while true {
		var next = input.next
		var off = 0
		var lineIndent = indent + 1
		while yamlIsSpace(next) {
			if yamlIsBreakSpace(next) {
				if scan { return false }
				lineIndent = 0
			} else {
				lineIndent += 1
			}
			off += 1
			next = input.peek(off)
		}
		let safe = next >= 0 &&
			(next == 58 ? yamlIsSafe(input.peek(off + 1), inFlow: inFlow) :
				next == 35 ? input.peek(off - 1) != 32 :
				yamlIsSafe(next, inFlow: inFlow))
		if !safe || (!inFlow && lineIndent <= indent) ||
			(lineIndent == 0 && !inFlow && (yamlThree(input, 45, off) || yamlThree(input, 46, off)))
		{
			break
		}
		if scan && yamlCharTag(next) == "f" { return false }
		for _ in 0 ... off {
			input.advance()
		}
		if scan && input.pos > start + 1024 { return false }
	}
	return true
}

// MARK: - Context Tracker

private nonisolated(unsafe) let yamlIndentation: ContextTracker = {
	let t = YamlParserData.termTable
	let sequenceStartMark = t["sequenceStartMark"]!
	let mapStartMark = t["mapStartMark"]!
	let explicitMapStartMark = t["explicitMapStartMark"]!
	let blockEnd = t["blockEnd"]!
	let bracketL = t["\"[" + "\""]!
	let braceL = t["\"{" + "\""]!
	let blockLiteralContent = t["BlockLiteralContent"]!
	let blockLiteralHeader = t["BlockLiteralHeader"]!
	let flowSequence = t["FlowSequence"]!
	let flowMapping = t["FlowMapping-1"]!

	return ContextTracker(
		start: YamlContext(parent: nil, depth: -1, type: yamlType_Top) as Any,
		shift: { context, term, stack, input in
			guard let cx = context as? YamlContext else { return context }
			if term == sequenceStartMark {
				return YamlContext(parent: cx, depth: yamlFindColumn(input, input.pos), type: yamlType_Seq) as Any
			}
			if term == mapStartMark || term == explicitMapStartMark {
				return YamlContext(parent: cx, depth: yamlFindColumn(input, input.pos), type: yamlType_Map) as Any
			}
			if term == blockEnd {
				return (cx.parent ?? YamlContext(parent: nil, depth: -1, type: yamlType_Top)) as Any
			}
			if term == bracketL || term == braceL {
				return YamlContext(parent: cx, depth: 0, type: yamlType_Flow) as Any
			}
			if term == blockLiteralContent, cx.type == yamlType_Lit {
				return (cx.parent ?? YamlContext(parent: nil, depth: -1, type: yamlType_Top)) as Any
			}
			if term == blockLiteralHeader {
				let text = input.read(from: input.pos, to: stack.pos)
				if let match = text.first(where: { $0 >= "1" && $0 <= "9" }), let digit = match.wholeNumberValue {
					return YamlContext(parent: cx, depth: cx.depth + digit, type: yamlType_Lit) as Any
				}
			}
			return context
		},
		reduce: { context, term, _, _ in
			guard let cx = context as? YamlContext else { return context }
			if cx.type == yamlType_Flow, term == flowSequence || term == flowMapping {
				return (cx.parent ?? YamlContext(parent: nil, depth: -1, type: yamlType_Top)) as Any
			}
			return context
		},
		hash: { context in (context as? YamlContext)?.hashValue ?? 0 }
	)
}()

// MARK: - External Tokenizers

func makeYamlExternalTokenizer(name: String, terms: [String: Int]) -> TokenizerProtocol {
	if name == "newlines" {
		let eof = terms["eof"]!
		let blockEnd = terms["blockEnd"]!
		let directiveEnd = terms["DirectiveEnd"]!
		let docEnd = terms["DocEnd"]!
		return ExternalTokenizer({ input, stack in
			if input.next == -1, stack.canShift(eof) {
				input.acceptToken(eof)
				return
			}
			let prev = input.peek(-1)
			if yamlIsBreakSpace(prev) || prev < 0, (stack.context as? YamlContext)?.type != yamlType_Flow {
				if yamlThree(input, 45) {
					if stack.canShift(blockEnd) { input.acceptToken(blockEnd) }
					else { input.acceptToken(directiveEnd, endOffset: 3); return }
				}
				if yamlThree(input, 46) {
					if stack.canShift(blockEnd) { input.acceptToken(blockEnd) }
					else { input.acceptToken(docEnd, endOffset: 3); return }
				}
				var depth = 0
				while input.next == 32 {
					depth += 1; input.advance()
				}
				let cxType = (stack.context as? YamlContext)?.type ?? yamlType_Top
				let cxDepth = (stack.context as? YamlContext)?.depth ?? -1
				if depth < cxDepth ||
					depth == cxDepth && cxType == yamlType_Seq &&
					(input.next != 45 || !yamlIsSep(input.peek(1))),
					input.next != -1, !yamlIsBreakSpace(input.next), input.next != 35
				{
					input.acceptToken(blockEnd, endOffset: -depth)
				}
			}
		}, contextual: true)
	}

	if name == "blockMark" {
		let flowMapMark = terms["flowMapMark"]!
		let sequenceContinueMark = terms["sequenceContinueMark"]!
		let sequenceStartMark = terms["sequenceStartMark"]!
		let explicitMapContinueMark = terms["explicitMapContinueMark"]!
		let explicitMapStartMark = terms["explicitMapStartMark"]!
		let mapContinueMark = terms["mapContinueMark"]!
		let mapStartMark = terms["mapStartMark"]!
		let colon = terms["\"" + ":" + "\""]!
		return ExternalTokenizer({ input, stack in
			let cxType = (stack.context as? YamlContext)?.type ?? yamlType_Top
			let cxDepth = (stack.context as? YamlContext)?.depth ?? -1

			if cxType == yamlType_Flow {
				if input.next == 63 {
					input.advance()
					if yamlIsSep(input.next) { input.acceptToken(flowMapMark) }
				}
				return
			}

			if input.next == 45 {
				input.advance()
				if yamlIsSep(input.next) {
					input.acceptToken(cxType == yamlType_Seq && cxDepth == yamlFindColumn(input, input.pos - 1)
						? sequenceContinueMark : sequenceStartMark)
				}
			} else if input.next == 63 {
				input.advance()
				if yamlIsSep(input.next) {
					input.acceptToken(cxType == yamlType_Map && cxDepth == yamlFindColumn(input, input.pos - 1)
						? explicitMapContinueMark : explicitMapStartMark)
				}
			} else {
				let start = input.pos
				while true {
					if yamlIsNonBreakSpace(input.next) {
						if input.pos == start { return }
						input.advance()
					} else if input.next == 33 {
						yamlReadTag(input)
					} else if input.next == 38 {
						yamlReadAnchor(input)
					} else if input.next == 42 {
						yamlReadAnchor(input)
						break
					} else if input.next == 39 || input.next == 34 {
						if yamlReadQuoted(input, scan: true) { break }
						return
					} else if input.next == 91 || input.next == 123 {
						if !yamlScanBrackets(input) { return }
						break
					} else {
						yamlReadPlain(input, scan: true, inFlow: false, indent: 0)
						break
					}
				}
				while yamlIsNonBreakSpace(input.next) {
					input.advance()
				}
				if input.next == 58 {
					if input.pos == start, stack.canShift(colon) { return }
					let after = input.peek(1)
					if yamlIsSep(after) {
						input.acceptTokenTo(cxType == yamlType_Map && cxDepth == yamlFindColumn(input, start)
							? mapContinueMark : mapStartMark, endPos: start)
					}
				}
			}
		}, contextual: true)
	}

	if name == "literals" {
		let tag = terms["Tag"]!
		let anchor = terms["Anchor"]!
		let alias = terms["Alias"]!
		let quotedLiteral = terms["QuotedLiteral"]!
		let literal = terms["Literal"]!
		return ExternalTokenizer { input, stack in
			let cxType = (stack.context as? YamlContext)?.type ?? yamlType_Top
			let cxDepth = (stack.context as? YamlContext)?.depth ?? -1

			if input.next == 33 {
				yamlReadTag(input)
				input.acceptToken(tag)
			} else if input.next == 38 || input.next == 42 {
				let token = input.next == 38 ? anchor : alias
				yamlReadAnchor(input)
				input.acceptToken(token)
			} else if input.next == 39 || input.next == 34 {
				yamlReadQuoted(input, scan: false)
				input.acceptToken(quotedLiteral)
			} else if yamlReadPlain(input, scan: false, inFlow: cxType == yamlType_Flow, indent: cxDepth) {
				input.acceptToken(literal)
			}
		}
	}

	if name == "blockLiteral" {
		let blockLiteralContent = terms["BlockLiteralContent"]!
		return ExternalTokenizer { input, stack in
			let cxType = (stack.context as? YamlContext)?.type ?? yamlType_Top
			let cxDepth = (stack.context as? YamlContext)?.depth ?? -1
			var indent = cxType == yamlType_Lit ? cxDepth : -1
			var upto = input.pos
			scanLoop: while true {
				var depth = 0
				var next = input.next
				while next == 32 {
					depth += 1; next = input.peek(depth)
				}
				if depth == 0, yamlThree(input, 45, depth) || yamlThree(input, 46, depth) { break }
				if !yamlIsBreakSpace(next) {
					if indent < 0 { indent = max(cxDepth + 1, depth) }
					if depth < indent { break }
				}
				while true {
					if input.next < 0 { break scanLoop }
					let isBreak = yamlIsBreakSpace(input.next)
					input.advance()
					if isBreak { continue scanLoop }
					upto = input.pos
				}
			}
			input.acceptTokenTo(blockLiteralContent, endPos: upto)
		}
	}

	fatalError("Unknown YAML external tokenizer: \(name)")
}

// MARK: - Highlighting

private nonisolated(unsafe) let definition = hlTags["definition"] as! (Tag) -> Tag
private nonisolated(unsafe) let specialMod = hlTags["special"] as! (Tag) -> Tag

nonisolated(unsafe) let yamlHighlighting = styleTags([
	"DirectiveName": hlKeyword,
	"DirectiveContent": hlTags["attributeValue"] as Any,
	"DirectiveEnd DocEnd": hlMeta,
	"QuotedLiteral": hlString,
	"BlockLiteralHeader": specialMod(hlString),
	"BlockLiteralContent": hlContent,
	"Literal": hlContent,
	"Key/Literal Key/QuotedLiteral": definition(hlPropertyName),
	"Anchor Alias": hlTags["labelName"] as Any,
	"Tag": hlTypeName,
	"Comment": hlTags["lineComment"] as Any,
	": , -": hlTags["separator"] as Any,
	"?": hlPunctuation,
	"[ ]": hlTags["squareBracket"] as Any,
	"{ }": hlTags["brace"] as Any,
])

// MARK: - Parser

public nonisolated(unsafe) let yamlParser: LRParser = {
	let externals: [String: TokenizerProtocol] = [
		"newlines": makeYamlExternalTokenizer(name: "newlines", terms: YamlParserData.termTable),
		"blockMark": makeYamlExternalTokenizer(name: "blockMark", terms: YamlParserData.termTable),
		"literals": makeYamlExternalTokenizer(name: "literals", terms: YamlParserData.termTable),
		"blockLiteral": makeYamlExternalTokenizer(name: "blockLiteral", terms: YamlParserData.termTable),
	]
	let spec = YamlParserData.makeSpec(
		externals: externals,
		propSources: [yamlHighlighting],
		context: yamlIndentation
	)
	return LRParser(spec: spec)
}()
