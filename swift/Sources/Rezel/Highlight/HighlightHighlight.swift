private nonisolated(unsafe) var _nextTagID: Int = 0

public class Tag: @unchecked Sendable, CustomStringConvertible {
	public let id: Int
	public let name: String
	public let set: [Tag]
	public let base: Tag?
	public let modified: [Modifier]

	public init(id: Int, name: String, set: [Tag], base: Tag?, modified: [Modifier]) {
		self.id = id
		self.name = name
		self.set = set
		self.base = base
		self.modified = modified
	}

	public init(name: String, set: [Tag], base: Tag?, modified: [Modifier]) {
		id = _nextTagID
		_nextTagID += 1
		self.name = name
		self.set = set
		self.base = base
		self.modified = modified
	}

	public var description: String {
		var n = name
		for mod in modified {
			if !mod.name.isEmpty { n = "\(mod.name)(\(n))" }
		}
		return n
	}

	public static func define(_ name: String? = nil, parent: Tag? = nil) -> Tag {
		let n = name ?? "?"
		if let parent = parent, parent.base != nil {
			fatalError("Can not derive from a modified tag")
		}
		let id = _nextTagID
		_nextTagID += 1
		var parentSet: [Tag] = []
		if let parent = parent {
			parentSet = parent.set
		}
		let tag = Tag(id: id, name: n, set: parentSet, base: nil, modified: [])
		var fullSet = [tag]
		fullSet.append(contentsOf: parentSet)
		return Tag(id: id, name: n, set: fullSet, base: nil, modified: [])
	}

	public static func defineModifier(_ name: String = "") -> (Tag) -> Tag {
		let mod = Modifier(name: name)
		return { tag in
			if tag.modified.contains(where: { $0 === mod }) { return tag }
			return Modifier.get(tag.base ?? tag, mods: tag.modified + [mod].sorted { $0.id < $1.id })
		}
	}
}

private nonisolated(unsafe) var _nextModifierID: Int = 0

public class Modifier: @unchecked Sendable {
	var instances: [Tag] = []
	let id: Int
	let name: String

	init(name: String = "") {
		id = _nextModifierID
		_nextModifierID += 1
		self.name = name
	}

	public static func get(_ base: Tag, mods: [Modifier]) -> Tag {
		if mods.isEmpty { return base }
		if let exists = mods[0].instances.first(where: { $0.base === base && hlSameArray(mods, $0.modified) }) {
			return exists
		}
		var set: [Tag] = []
		let tag = Tag(name: base.name, set: set, base: base, modified: mods)
		for m in mods {
			m.instances.append(tag)
		}
		let configs = hlPowerSet(mods)
		for parent in base.set {
			if parent.modified.isEmpty {
				for config in configs {
					set.append(Modifier.get(parent, mods: config))
				}
			}
		}
		return Tag(name: base.name, set: set, base: base, modified: mods)
	}
}

private func hlSameArray(_ a: [Modifier], _ b: [Modifier]) -> Bool {
	guard a.count == b.count else { return false }
	for i in 0 ..< a.count {
		if a[i].id != b[i].id { return false }
	}
	return true
}

private func hlPowerSet(_ array: [Modifier]) -> [[Modifier]] {
	var sets: [[Modifier]] = [[]]
	for i in 0 ..< array.count {
		let e = sets.count
		for j in 0 ..< e {
			sets.append(sets[j] + [array[i]])
		}
	}
	return sets.sorted { $0.count > $1.count }
}

private let hlModeOpaque = 0
private let hlModeInherit = 1
private let hlModeNormal = 2

public class HighlightRule: @unchecked Sendable {
	public let tags: [Tag]
	public let mode: Int
	public let context: [String]?
	public var next: HighlightRule?

	public init(tags: [Tag], mode: Int, context: [String]?, next: HighlightRule? = nil) {
		self.tags = tags
		self.mode = mode
		self.context = context
		self.next = next
	}

	public var opaque: Bool {
		mode == hlModeOpaque
	}

	public var inherit: Bool {
		mode == hlModeInherit
	}

	public func sort(_ other: HighlightRule?) -> HighlightRule {
		guard let other = other else {
			next = nil
			return self
		}
		if other.depth < depth {
			next = other
			return self
		}
		other.next = sort(other.next)
		return other
	}

	public var depth: Int {
		context?.count ?? 0
	}

	public static let empty = HighlightRule(tags: [], mode: hlModeNormal, context: nil)
}

private nonisolated(unsafe) let _ruleNodeProp = NodeProp<HighlightRule>(
	deserialize: { _ in HighlightRule.empty },
	combine: { a, b in
		var cur: HighlightRule?
		var root: HighlightRule!
		var aOpt: HighlightRule? = a
		var bOpt: HighlightRule? = b

		while aOpt != nil || bOpt != nil {
			let take: HighlightRule
			if aOpt == nil || (bOpt != nil && aOpt!.depth >= bOpt!.depth) {
				take = bOpt!
				bOpt = bOpt!.next
			} else {
				take = aOpt!
				aOpt = aOpt!.next
			}
			if let cur = cur, cur.mode == take.mode, take.context == nil, cur.context == nil {
				continue
			}
			let copy = HighlightRule(tags: take.tags, mode: take.mode, context: take.context)
			if cur != nil { cur!.next = copy } else { root = copy }
			cur = copy
		}
		return root
	}
)

public func styleTags(_ spec: [String: Any]) -> NodePropSource {
	var byName: [String: HighlightRule] = [:]

	for (prop, value) in spec {
		var tags: [Tag]
		if let t = value as? Tag { tags = [t] }
		else if let t = value as? [Tag] { tags = t }
		else { continue }

		for part in prop.split(separator: " ") {
			guard !part.isEmpty else { continue }
			var pieces: [String] = []
			var mode = hlModeNormal
			var rest = Substring(part)
			var pos = 0

			while true {
				if rest == "..." && pos > 0 && pos + 3 == part.count {
					mode = hlModeInherit
					break
				}
				guard let m = rest.range(of: #"^"(?:[^"\\]|\\.)*?"|[^/!]+"#, options: .regularExpression) else {
					fatalError("Invalid path: \(part)")
				}
				let matched = String(rest[m])
				var piece = matched
				if piece == "*" { piece = "" }
				else if piece.first == "\"" {
					piece = String(piece.dropFirst().dropLast())
				}
				pieces.append(piece)
				pos += matched.count
				if pos >= part.count { break }
				let nextChar = part[part.index(part.startIndex, offsetBy: pos)]
				pos += 1
				if pos >= part.count && nextChar == "!" {
					mode = hlModeOpaque
					break
				}
				if nextChar != "/" { fatalError("Invalid path: \(part)") }
				rest = part[part.index(part.startIndex, offsetBy: pos)...]
			}

			let last = pieces.count - 1
			let inner = pieces[last]
			if inner.isEmpty { fatalError("Invalid path: \(part)") }
			let rule = HighlightRule(tags: tags, mode: mode, context: last > 0 ? Array(pieces[0 ..< last]) : nil)
			if let existing = byName[inner] {
				byName[inner] = rule.sort(existing)
			} else {
				byName[inner] = rule
			}
		}
	}
	return _ruleNodeProp.add(match: byName)
}

public protocol Highlighter {
	func style(_ tags: [Tag]) -> String?
	func scope(_ node: NodeType) -> Bool
}

public extension Highlighter {
	func scope(_: NodeType) -> Bool {
		false
	}
}

public struct TagStyle {
	public let tag: Any
	public let className: String

	public init(tag: Tag, className: String) {
		self.tag = tag
		self.className = className
	}

	public init(tags: [Tag], className: String) {
		tag = tags
		self.className = className
	}
}

public func tagHighlighter(
	_ tags: [TagStyle],
	scope: ((NodeType) -> Bool)? = nil,
	all: String? = nil
) -> Highlighter {
	var map: [Int: String] = [:]
	for style in tags {
		if let tag = style.tag as? Tag {
			map[tag.id] = style.className
		} else if let tags = style.tag as? [Tag] {
			for tag in tags {
				map[tag.id] = style.className
			}
		}
	}
	return TagHighlighterImpl(map: map, scopeFn: scope, allClass: all ?? "")
}

private class TagHighlighterImpl: Highlighter {
	let map: [Int: String]
	let scopeFn: ((NodeType) -> Bool)?
	let allClass: String

	init(map: [Int: String], scopeFn: ((NodeType) -> Bool)?, allClass: String) {
		self.map = map
		self.scopeFn = scopeFn
		self.allClass = allClass
	}

	func style(_ tags: [Tag]) -> String? {
		var cls = allClass
		for tag in tags {
			for sub in tag.set {
				if let tagClass = map[sub.id] {
					cls = cls.isEmpty ? tagClass : cls + " " + tagClass
					break
				}
			}
		}
		return cls.isEmpty ? nil : cls
	}

	func scope(_ node: NodeType) -> Bool {
		scopeFn?(node) ?? false
	}
}

private func hlHighlightTags(_ highlighters: [Highlighter], tags: [Tag]) -> String? {
	var result: String? = nil
	for highlighter in highlighters {
		if let value = highlighter.style(tags) {
			result = result != nil ? result! + " " + value : value
		}
	}
	return result
}

public func highlightTree(
	_ tree: Tree,
	highlighter: Any,
	putStyle: @escaping (Int, Int, String) -> Void,
	from: Int = 0,
	to: Int? = nil
) {
	let to = to ?? tree.length
	let highlighters: [Highlighter]
	if let h = highlighter as? Highlighter {
		highlighters = [h]
	} else if let h = highlighter as? [Highlighter] {
		highlighters = h
	} else {
		highlighters = []
	}
	let builder = HighlightBuilder(at: from, highlighters: highlighters, span: putStyle)
	builder.highlightRange(tree.cursor(), from: from, to: to, inheritedClass: "", highlighters: highlighters)
	builder.flush(to)
}

public func highlightCode(
	_ code: String,
	tree: Tree,
	highlighter: Any,
	putText: @escaping (String, String) -> Void,
	putBreak: @escaping () -> Void,
	from: Int = 0,
	to: Int? = nil
) {
	let to = to ?? code.count
	var pos = from

	func writeTo(_ p: Int, _ classes: String) {
		if p <= pos { return }
		let startIndex = code.index(code.startIndex, offsetBy: pos)
		let endIndex = code.index(code.startIndex, offsetBy: p)
		let text = String(code[startIndex ..< endIndex])
		var i = 0
		let textChars = Array(text)
		while true {
			let nextBreak = textChars[i...].firstIndex(of: Character("\n"))
			let upto = nextBreak ?? textChars.count
			if upto > i {
				let s = String(textChars[i ..< upto])
				putText(s, classes)
			}
			if nextBreak == nil { break }
			putBreak()
			i = nextBreak! + 1
		}
		pos = p
	}

	highlightTree(tree, highlighter: highlighter, putStyle: { from, to, classes in
		writeTo(from, "")
		writeTo(to, classes)
	}, from: from, to: to)
	writeTo(to, "")
}

class HighlightBuilder {
	var cls: String = ""
	var at: Int
	let highlighters: [Highlighter]
	let span: (Int, Int, String) -> Void

	init(at: Int, highlighters: [Highlighter], span: @escaping (Int, Int, String) -> Void) {
		self.at = at
		self.highlighters = highlighters
		self.span = span
	}

	func startSpan(_ at: Int, _ cls: String) {
		if cls != self.cls {
			flush(at)
			if at > self.at { self.at = at }
			self.cls = cls
		}
	}

	func flush(_ to: Int) {
		if to > at, !cls.isEmpty { span(at, to, cls) }
	}

	func highlightRange(
		_ cursor: TreeCursor,
		from: Int,
		to: Int,
		inheritedClass paramInherited: String,
		highlighters: [Highlighter]
	) {
		var inheritedClass = paramInherited
		let start = cursor.from
		let end = cursor.to
		if start >= to || end <= from { return }

		var highlighters = highlighters
		if cursor.type.isTop {
			highlighters = self.highlighters.filter { h in !h.scope(cursor.type) || h.scope(cursor.type) }
		}

		var cls = inheritedClass
		let rule = getStyleTags(cursor) ?? HighlightRule.empty
		let tagCls = hlHighlightTags(highlighters, tags: rule.tags)
		if let tagCls = tagCls {
			if !cls.isEmpty { cls += " " }
			cls += tagCls
			if rule.mode == hlModeInherit {
				inheritedClass = inheritedClass + (inheritedClass.isEmpty ? "" : " ") + tagCls
			}
		}

		startSpan(max(from, start), cls)
		if rule.opaque { return }

		let mounted = cursor.tree?.prop(nodePropMounted)
		if let mounted = mounted, mounted.overlay != nil {
			let inner = cursor.node.enter(mounted.overlay![0].from + start, side: 1, mode: nil)!
			let innerHighlighters = self.highlighters.filter { h in !h.scope(mounted.tree.type) || h.scope(mounted.tree.type) }
			let hasChild = cursor.firstChild()
			var i = 0
			var pos = start
			while true {
				let next = i < mounted.overlay!.count ? mounted.overlay![i] : nil
				let nextPos = next != nil ? next!.from + start : end
				let rangeFrom = max(from, pos)
				let rangeTo = min(to, nextPos)
				if rangeFrom < rangeTo && hasChild {
					while cursor.from < rangeTo {
						highlightRange(cursor, from: rangeFrom, to: rangeTo, inheritedClass: inheritedClass, highlighters: highlighters)
						startSpan(min(rangeTo, cursor.to), cls)
						if cursor.to >= nextPos || !cursor.nextSibling() { break }
					}
				}
				if next == nil || nextPos > to { break }
				pos = next!.to + start
				if pos > from {
					highlightRange(
						inner.cursor(mode: nil),
						from: max(from, next!.from + start),
						to: min(to, pos),
						inheritedClass: "",
						highlighters: innerHighlighters
					)
					startSpan(min(to, pos), cls)
				}
				i += 1
			}
			if hasChild { cursor.parent() }
		} else if cursor.firstChild() {
			if mounted != nil { inheritedClass = "" }
			repeat {
				if cursor.to <= from { continue }
				if cursor.from >= to { break }
				highlightRange(cursor, from: from, to: to, inheritedClass: inheritedClass, highlighters: highlighters)
				startSpan(min(to, cursor.to), cls)
			} while cursor.nextSibling()
			cursor.parent()
		}
	}
}

public func getStyleTags(_ node: SyntaxNodeRef) -> HighlightRule? {
	var rule: HighlightRule? = node.type.prop(_ruleNodeProp)
	while rule != nil, rule!.context != nil, !node.matchContext(rule!.context!) {
		rule = rule!.next
	}
	return rule
}

public let hlComment = Tag.define("comment")
public let hlName = Tag.define("name")
public let hlTypeName = Tag.define("typeName", parent: hlName)
public let hlPropertyName = Tag.define("propertyName", parent: hlName)
public let hlLiteral = Tag.define("literal")
public let hlString = Tag.define("string", parent: hlLiteral)
public let hlNumber = Tag.define("number", parent: hlLiteral)
public let hlContent = Tag.define("content")
public let hlHeading = Tag.define("heading", parent: hlContent)
public let hlKeyword = Tag.define("keyword")
public let hlOperator = Tag.define("operator")
public let hlPunctuation = Tag.define("punctuation")
public let hlBracket = Tag.define("bracket", parent: hlPunctuation)
public let hlMeta = Tag.define("meta")

public nonisolated(unsafe) let hlTags: [String: Any] = {
	var t: [String: Any] = [:]

	t["comment"] = hlComment
	t["lineComment"] = Tag.define("lineComment", parent: hlComment)
	t["blockComment"] = Tag.define("blockComment", parent: hlComment)
	t["docComment"] = Tag.define("docComment", parent: hlComment)

	t["name"] = hlName
	t["variableName"] = Tag.define("variableName", parent: hlName)
	t["typeName"] = hlTypeName
	t["tagName"] = Tag.define("tagName", parent: hlTypeName)
	t["propertyName"] = hlPropertyName
	t["attributeName"] = Tag.define("attributeName", parent: hlPropertyName)
	t["className"] = Tag.define("className", parent: hlName)
	t["labelName"] = Tag.define("labelName", parent: hlName)
	t["namespace"] = Tag.define("namespace", parent: hlName)
	t["macroName"] = Tag.define("macroName", parent: hlName)

	t["literal"] = hlLiteral
	t["string"] = hlString
	t["docString"] = Tag.define("docString", parent: hlString)
	t["character"] = Tag.define("character", parent: hlString)
	t["attributeValue"] = Tag.define("attributeValue", parent: hlString)
	t["number"] = hlNumber
	t["integer"] = Tag.define("integer", parent: hlNumber)
	t["float"] = Tag.define("float", parent: hlNumber)
	t["bool"] = Tag.define("bool", parent: hlLiteral)
	t["regexp"] = Tag.define("regexp", parent: hlLiteral)
	t["escape"] = Tag.define("escape", parent: hlLiteral)
	t["color"] = Tag.define("color", parent: hlLiteral)
	t["url"] = Tag.define("url", parent: hlLiteral)

	t["keyword"] = hlKeyword
	t["self"] = Tag.define("self", parent: hlKeyword)
	t["null"] = Tag.define("null", parent: hlKeyword)
	t["atom"] = Tag.define("atom", parent: hlKeyword)
	t["unit"] = Tag.define("unit", parent: hlKeyword)
	t["modifier"] = Tag.define("modifier", parent: hlKeyword)
	t["operatorKeyword"] = Tag.define("operatorKeyword", parent: hlKeyword)
	t["controlKeyword"] = Tag.define("controlKeyword", parent: hlKeyword)
	t["definitionKeyword"] = Tag.define("definitionKeyword", parent: hlKeyword)
	t["moduleKeyword"] = Tag.define("moduleKeyword", parent: hlKeyword)

	t["operator"] = hlOperator
	t["derefOperator"] = Tag.define("derefOperator", parent: hlOperator)
	t["arithmeticOperator"] = Tag.define("arithmeticOperator", parent: hlOperator)
	t["logicOperator"] = Tag.define("logicOperator", parent: hlOperator)
	t["bitwiseOperator"] = Tag.define("bitwiseOperator", parent: hlOperator)
	t["compareOperator"] = Tag.define("compareOperator", parent: hlOperator)
	t["updateOperator"] = Tag.define("updateOperator", parent: hlOperator)
	t["definitionOperator"] = Tag.define("definitionOperator", parent: hlOperator)
	t["typeOperator"] = Tag.define("typeOperator", parent: hlOperator)
	t["controlOperator"] = Tag.define("controlOperator", parent: hlOperator)

	t["punctuation"] = hlPunctuation
	t["separator"] = Tag.define("separator", parent: hlPunctuation)
	t["bracket"] = hlBracket
	t["angleBracket"] = Tag.define("angleBracket", parent: hlBracket)
	t["squareBracket"] = Tag.define("squareBracket", parent: hlBracket)
	t["paren"] = Tag.define("paren", parent: hlBracket)
	t["brace"] = Tag.define("brace", parent: hlBracket)

	t["content"] = hlContent
	t["heading"] = hlHeading
	t["heading1"] = Tag.define("heading1", parent: hlHeading)
	t["heading2"] = Tag.define("heading2", parent: hlHeading)
	t["heading3"] = Tag.define("heading3", parent: hlHeading)
	t["heading4"] = Tag.define("heading4", parent: hlHeading)
	t["heading5"] = Tag.define("heading5", parent: hlHeading)
	t["heading6"] = Tag.define("heading6", parent: hlHeading)
	t["contentSeparator"] = Tag.define("contentSeparator", parent: hlContent)
	t["list"] = Tag.define("list", parent: hlContent)
	t["quote"] = Tag.define("quote", parent: hlContent)
	t["emphasis"] = Tag.define("emphasis", parent: hlContent)
	t["strong"] = Tag.define("strong", parent: hlContent)
	t["link"] = Tag.define("link", parent: hlContent)
	t["monospace"] = Tag.define("monospace", parent: hlContent)
	t["strikethrough"] = Tag.define("strikethrough", parent: hlContent)

	t["inserted"] = Tag.define("inserted")
	t["deleted"] = Tag.define("deleted")
	t["changed"] = Tag.define("changed")
	t["invalid"] = Tag.define("invalid")

	t["meta"] = hlMeta
	t["documentMeta"] = Tag.define("documentMeta", parent: hlMeta)
	t["annotation"] = Tag.define("annotation", parent: hlMeta)
	t["processingInstruction"] = Tag.define("processingInstruction", parent: hlMeta)

	t["definition"] = Tag.defineModifier("definition")
	t["constant"] = Tag.defineModifier("constant")
	t["function"] = Tag.defineModifier("function")
	t["standard"] = Tag.defineModifier("standard")
	t["local"] = Tag.defineModifier("local")
	t["special"] = Tag.defineModifier("special")

	return t
}()

public nonisolated(unsafe) let classHighlighter: Highlighter = buildClassHighlighter()

private func buildClassHighlighter() -> Highlighter {
	var styles: [TagStyle] = []
	let tags = hlTags
	let mapping: [(String, String)] = [
		("link", "tok-link"),
		("heading", "tok-heading"),
		("emphasis", "tok-emphasis"),
		("strong", "tok-strong"),
		("keyword", "tok-keyword"),
		("atom", "tok-atom"),
		("bool", "tok-bool"),
		("url", "tok-url"),
		("labelName", "tok-labelName"),
		("inserted", "tok-inserted"),
		("deleted", "tok-deleted"),
		("literal", "tok-literal"),
		("string", "tok-string"),
		("number", "tok-number"),
		("variableName", "tok-variableName"),
		("typeName", "tok-typeName"),
		("namespace", "tok-namespace"),
		("className", "tok-className"),
		("macroName", "tok-macroName"),
		("propertyName", "tok-propertyName"),
		("operator", "tok-operator"),
		("comment", "tok-comment"),
		("meta", "tok-meta"),
		("invalid", "tok-invalid"),
		("punctuation", "tok-punctuation"),
	]
	for (key, cls) in mapping {
		if let tag = tags[key] as? Tag {
			styles.append(TagStyle(tag: tag, className: cls))
		}
	}
	if let regexp = tags["regexp"] as? Tag,
	   let escape = tags["escape"] as? Tag,
	   let specialFn = tags["special"] as? ((Tag) -> Tag),
	   let strTag = tags["string"] as? Tag
	{
		styles.append(TagStyle(tags: [regexp, escape, specialFn(strTag)], className: "tok-string2"))
	}
	if let localFn = tags["local"] as? ((Tag) -> Tag),
	   let varName = tags["variableName"] as? Tag
	{
		styles.append(TagStyle(tag: localFn(varName), className: "tok-variableName tok-local"))
	}
	if let definitionFn = tags["definition"] as? ((Tag) -> Tag),
	   let varName = tags["variableName"] as? Tag
	{
		styles.append(TagStyle(tag: definitionFn(varName), className: "tok-variableName tok-definition"))
	}
	if let specialFn = tags["special"] as? ((Tag) -> Tag),
	   let varName = tags["variableName"] as? Tag
	{
		styles.append(TagStyle(tag: specialFn(varName), className: "tok-variableName2"))
	}
	if let definitionFn = tags["definition"] as? ((Tag) -> Tag),
	   let propName = tags["propertyName"] as? Tag
	{
		styles.append(TagStyle(tag: definitionFn(propName), className: "tok-propertyName tok-definition"))
	}
	return tagHighlighter(styles)
}
