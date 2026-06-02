//
//  Highlight.swift
//  Rezel
//
//  Created on 2025-06-11.
//

import Foundation

/// Enum to represent either a single highlighter or an array of highlighters
public enum HighlighterOrArray {
    case single(any Highlighter)
    case array([any Highlighter])
}

fileprivate nonisolated(unsafe) var nextTagID = 0

/// Highlighting tags are markers that denote a highlighting category.
/// They are associated with parts of a syntax tree by a language mode,
/// and then mapped to an actual CSS style by a highlighter.
public final class Tag {
    /// @internal
    let id: Int
    
    /// @internal
    let name: String
    
    let set: [Tag]
    let base: Tag?
    fileprivate let modified: [Modifier]
    
    fileprivate init(
        name: String,
        set: [Tag],
        base: Tag?,
        modified: [Modifier]
    ) {
        self.id = nextTagID
        nextTagID += 1
        self.name = name
        self.set = set
        self.base = base
        self.modified = modified
    }
    
    func toString() -> String {
        var name = self.name
        for mod in modified {
            if let modName = mod.name {
                name = "\(modName)(\(name))"
            }
        }
        return name
    }
    
    /// Define a new tag. If `parent` is given, the tag is treated as a
    /// sub-tag of that parent, and highlighters that don't mention this
    /// tag will try to fall back to the parent tag.
    static func define(_ nameOrParent: StringOrTag = .string("?"), _ parent: Tag? = nil) -> Tag {
        let name: String
        var parentTag = parent
        
        switch nameOrParent {
        case .string(let str):
            name = str
        case .tag(let tag):
            name = "?"
            parentTag = tag
        }
        
        if let parentTag = parentTag, parentTag.base != nil {
            fatalError("Can not derive from a modified tag")
        }
        
        let tag = Tag(name: name, set: [], base: nil, modified: [])
        var set = [tag]
        if let parentTag = parentTag {
            set.append(contentsOf: parentTag.set)
        }
        
        return Tag(name: name, set: set, base: parentTag, modified: [])
    }
    
    /// Define a tag modifier, which is a function that, given a tag,
    /// will return a tag that is a subtag of the original.
    static func defineModifier(_ name: String? = nil) -> (Tag) -> Tag {
        let mod = Modifier(name: name)
        return { tag in
            if tag.modified.contains(where: { $0 === mod }) {
                return tag
            }
            let base = tag.base ?? tag
            let newMods = (tag.modified + [mod]).sorted { $0.id < $1.id }
            return Modifier.get(base: base, mods: newMods)
        }
    }
}

public enum StringOrTag {
    case string(String)
    case tag(Tag)
}

fileprivate nonisolated(unsafe) var nextModifierID = 0

fileprivate class Modifier {
    var instances: [Tag] = []
    let id: Int
    let name: String?
    
    init(name: String?) {
        self.id = nextModifierID
        nextModifierID += 1
        self.name = name
    }
    
    static func get(base: Tag, mods: [Modifier]) -> Tag {
        if mods.isEmpty {
            return base
        }
        
        if let exists = mods[0].instances.first(where: { $0.base === base && sameArray(a: mods, b: $0.modified) }) {
            return exists
        }
        
        var set: [Tag] = []
        let tag = Tag(name: base.name, set: set, base: base, modified: mods)
        
        for mod in mods {
            mod.instances.append(tag)
        }
        
        let configs = powerSet(array: mods)
        for parent in base.set {
            if parent.modified.isEmpty {
                for config in configs {
                    set.append(Modifier.get(base: parent, mods: config))
                }
            }
        }
        
        return tag
    }
}

fileprivate func sameArray<T: AnyObject>(a: [T], b: [T]) -> Bool {
    return a.count == b.count && zip(a, b).allSatisfy { $0 === $1 }
}

fileprivate func powerSet<T>(array: [T]) -> [[T]] {
    var sets: [[T]] = [[]]
    for i in 0..<array.count {
        for j in 0..<sets.count {
            var newSet = sets[j]
            newSet.append(array[i])
            sets.append(newSet)
        }
    }
    return sets.sorted { $0.count > $1.count }
}

/// This function is used to add a set of tags to a language syntax
/// via NodeSet.extend or LRParser.configure.
public func styleTags(spec: [String: [Tag]]) -> NodePropSource {
    var byName: [String: StyleRule] = [:]
    
    for (prop, tags) in spec {
        for part in prop.split(separator: " ") where !part.isEmpty {
            var pieces: [String] = []
            var mode: Mode = .normal
            var rest = part
            var pos = 0
            
            while true {
                if rest == "..." && pos > 0 && pos + 3 == part.count {
                    mode = .inherit
                    break
                }
                
                guard let match = rest.range(of: #"(?:[^"\\]|\\.)*?"|[^/!]+"#, options: .regularExpression) else {
                    fatalError("Invalid path: \(part)")
                }
                
                let matched = String(part[part.index(part.startIndex, offsetBy: pos)..<match.upperBound])
                let value: String
                if matched == "*" {
                    value = ""
                } else if matched.first == "\"" {
                    guard let jsonData = matched.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: jsonData),
                          let str = json as? String else {
                        fatalError("Invalid JSON string: \(matched)")
                    }
                    value = str
                } else {
                    value = matched
                }
                
                pieces.append(value)
                pos += matched.count
                
                if pos == part.count {
                    break
                }
                
                let next = part[part.index(part.startIndex, offsetBy: pos)]
                pos += 1
                
                if pos == part.count && next == "!" {
                    mode = .opaque
                    break
                }
                
                if next != "/" {
                    fatalError("Invalid path: \(part)")
                }
                
                rest = part[part.index(part.startIndex, offsetBy: pos)...]
            }
            
            let last = pieces.count - 1
            let inner = pieces[last]
            
            if inner.isEmpty {
                fatalError("Invalid path: \(part)")
            }
            
            let context = last > 0 ? Array(pieces[0..<last]) : nil
            let rule = StyleRule(tags: tags, mode: mode, context: context)
            byName[inner] = rule.sort(other: byName[inner])
        }
    }
    
    return { type in
        if let rule = byName[type.name] {
            return (styleRuleNodeProp, rule)
        }
        return nil
    }
}

fileprivate enum Mode: Int {
    case opaque = 0
    case inherit = 1
    case normal = 2
}

fileprivate class StyleRule {
    let tags: [Tag]
    let mode: Mode
    let context: [String]?
    var next: StyleRule?
    
    init(tags: [Tag], mode: Mode, context: [String]?, next: StyleRule? = nil) {
        self.tags = tags
        self.mode = mode
        self.context = context
        self.next = next
    }
    
    var opaque: Bool {
        return mode == .opaque
    }
    
    var inherit: Bool {
        return mode == .inherit
    }
    
    func sort(other: StyleRule?) -> StyleRule {
        let other = other
        if other == nil || other!.depth < self.depth {
            self.next = other
            return self
        }
        other!.next = sort(other: other!.next)
        return other!
    }
    
    var depth: Int {
        return context?.count ?? 0
    }
    
    static nonisolated(unsafe) let empty = StyleRule(tags: [], mode: .normal, context: nil)
}

fileprivate nonisolated(unsafe) let styleRuleNodeProp = NodeProp<StyleRule>(
    config: NodePropConfig(combine: { a, b in
        var cur: StyleRule?
        var root: StyleRule = StyleRule.empty
        var take: StyleRule
        var ruleA: StyleRule? = a
        var ruleB: StyleRule? = b
        
        while ruleA != nil || ruleB != nil {
            if ruleA == nil || (ruleB != nil && ruleA!.depth >= ruleB!.depth) {
                take = ruleB!
                ruleB = ruleB!.next
            } else {
                take = ruleA!
                ruleA = ruleA!.next
            }
            
            if let cur = cur, cur.mode == take.mode && take.context == nil && cur.context == nil {
                continue
            }
            
            let copy = StyleRule(tags: take.tags, mode: take.mode, context: take.context)
            if let cur = cur {
                cur.next = copy
            } else {
                root = copy
            }
            cur = copy
        }
        
        return root
    })
)

/// A highlighter defines a mapping from highlighting tags and language
/// scopes to CSS class names.
public protocol Highlighter {
    /// Get the set of classes that should be applied to the given set of
    /// highlighting tags, or null if this highlighter doesn't assign a style.
    func style(tags: [Tag]) -> String?
    
    /// When given, the highlighter will only be applied to trees on whose
    /// top node this predicate returns true.
    var scope: ((NodeType) -> Bool)? { get }
}

public struct TagStyle {
    public let tag: TagOrTags
    public let styleClass: String
    
    public init(tag: TagOrTags, class styleClass: String) {
        self.tag = tag
        self.styleClass = styleClass
    }
}

public enum TagOrTags {
    case tag(Tag)
    case tags([Tag])
}

public struct HighlighterOptions {
    public let scope: ((NodeType) -> Bool)?
    public let all: String?
    
    public init(scope: ((NodeType) -> Bool)? = nil, all: String? = nil) {
        self.scope = scope
        self.all = all
    }
}

/// Define a highlighter from an array of tag/class pairs.
public func tagHighlighter(
    tags: [TagStyle],
    options: HighlighterOptions = HighlighterOptions()
) -> any Highlighter {
    var map: [Int: String] = [:]
    
    for style in tags {
        switch style.tag {
        case .tag(let tag):
            map[tag.id] = style.styleClass
        case .tags(let tagArray):
            for tag in tagArray {
                map[tag.id] = style.styleClass
            }
        }
    }
    
    return SimpleHighlighter(
        map: map,
        scope: options.scope,
        all: options.all
    )
}

fileprivate class SimpleHighlighter: Highlighter {
    let map: [Int: String]
    let scope: ((NodeType) -> Bool)?
    let all: String?
    
    init(map: [Int: String], scope: ((NodeType) -> Bool)?, all: String?) {
        self.map = map
        self.scope = scope
        self.all = all
    }
    
    func style(tags: [Tag]) -> String? {
        var cls = all
        for tag in tags {
            for sub in tag.set {
                if let tagClass = map[sub.id] {
                    cls = cls != nil ? cls! + " " + tagClass : tagClass
                    break
                }
            }
        }
        return cls
    }
}

fileprivate func highlightTags(highlighters: [any Highlighter], tags: [Tag]) -> String? {
    var result: String? = nil
    for highlighter in highlighters {
        if let value = highlighter.style(tags: tags) {
            result = result != nil ? result! + " " + value : value
        }
    }
    return result
}

/// Highlight the given tree with the given highlighter.
public func highlightTree(
    tree: Tree,
    highlighter: HighlighterOrArray,
    putStyle: @escaping (Int, Int, String) -> Void,
    from: Int = 0,
    to: Int? = nil
) {
    let to = to ?? tree.length
    let highlightersArray: [any Highlighter]
    
    switch highlighter {
    case .single(let single):
        highlightersArray = [single]
    case .array(let array):
        highlightersArray = array
    }
    
    let builder = HighlightBuilder(
        at: from,
        highlighters: highlightersArray,
        span: putStyle
    )
    
    builder.highlightRange(
        cursor: tree.cursor(mode: []),
        from: from,
        to: to,
        inheritedClass: "",
        highlighters: highlightersArray
    )
    
    builder.flush(to: to)
}

/// Highlight the given tree with the given highlighter, calling putText
/// for every piece of text and putBreak for every line break.
public func highlightCode(
    code: String,
    tree: Tree,
    highlighter: HighlighterOrArray,
    putText: @escaping (String, String) -> Void,
    putBreak: @escaping () -> Void,
    from: Int = 0,
    to: Int? = nil
) {
    let to = to ?? code.count
    var pos = from
    
    func writeTo(_ p: Int, _ classes: String) {
        if p <= pos {
            return
        }
        
        let text = String(code[code.index(code.startIndex, offsetBy: pos)..<code.index(code.startIndex, offsetBy: p)])
        var i = text.startIndex
        
        while true {
            let nextBreak = text.range(of: "\n", range: i..<text.endIndex)
            let upto = nextBreak?.lowerBound ?? text.endIndex
            
            if i < upto {
                putText(String(text[i..<upto]), classes)
            }
            
            guard let nextBreak = nextBreak else {
                break
            }
            
            putBreak()
            i = text.index(after: nextBreak.lowerBound)
        }
        
        pos = p
    }
    
    highlightTree(
        tree: tree,
        highlighter: highlighter,
        putStyle: { from, to, classes in
            writeTo(from, "")
            writeTo(to, classes)
        },
        from: from,
        to: to
    )
    
    writeTo(to, "")
}

fileprivate class HighlightBuilder {
    var currentClass = ""
    var at: Int
    let highlighters: [any Highlighter]
    let span: (Int, Int, String) -> Void
    
    init(at: Int, highlighters: [any Highlighter], span: @escaping (Int, Int, String) -> Void) {
        self.at = at
        self.highlighters = highlighters
        self.span = span
    }
    
    func startSpan(at position: Int, cls: String) {
        if cls != currentClass {
            flush(to: position)
            if position > at {
                at = position
            }
            currentClass = cls
        }
    }
    
    func flush(to: Int) {
        if to > at && !currentClass.isEmpty {
            span(at, to, currentClass)
        }
    }
    
    func highlightRange(
        cursor: TreeCursor,
        from: Int,
        to: Int,
        inheritedClass: String,
        highlighters: [any Highlighter]
    ) {
        let type = cursor.type
        let start = cursor.from
        let end = cursor.to
        
        if start >= to || end <= from {
            return
        }
        
        var highlighters = highlighters
        if type.isTop {
            highlighters = highlighters.filter { h in
                guard let scope = h.scope else {
                    return true
                }
                return scope(type)
            }
        }
        
        var cls = inheritedClass
        let rule = cursor.type.prop(prop: styleRuleNodeProp) ?? StyleRule.empty
        let tagCls = highlightTags(highlighters: highlighters, tags: rule.tags)
        
        if let tagCls = tagCls {
            if !cls.isEmpty {
                cls += " "
            }
            cls += tagCls
            if rule.inherit {
                if !inheritedClass.isEmpty {
                    cls += " "
                }
                cls += tagCls
            }
        }
        
        startSpan(at: max(from, start), cls: cls)
        
        if rule.opaque {
            return
        }
        
        if let tree = cursor.tree,
           let mounted = tree.prop(prop: nodePropMounted),
           let overlay = mounted.overlay {
            let innerNode = cursor._tree!.enter(pos: overlay[0].from + start, side: 1, mode: nil)!
            let innerHighlighters = highlighters.filter { h in
                guard let scope = h.scope else {
                    return true
                }
                return scope(mounted.tree.type)
            }
            
            let hasChild = cursor.firstChild()
            
            for i in 0...overlay.count {
                let next = i < overlay.count ? overlay[i] : nil
                let nextPos = next?.from ?? 0 + start
                let rangeFrom = max(from, i == 0 ? start : overlay[i - 1].to + start)
                let rangeTo = min(to, nextPos)
                
                if rangeFrom < rangeTo && hasChild {
                    while cursor.from < rangeTo {
                        highlightRange(
                            cursor: cursor,
                            from: rangeFrom,
                            to: rangeTo,
                            inheritedClass: inheritedClass,
                            highlighters: highlighters
                        )
                        startSpan(at: min(rangeTo, cursor.to), cls: cls)
                        if cursor.to >= nextPos || !cursor.nextSibling() {
                            break
                        }
                    }
                }
                
                if next == nil || nextPos > to {
                    break
                }
                
                let currentPos = next!.to + start
                if currentPos > from {
                    highlightRange(
                        cursor: innerNode.cursor(mode: []),
                        from: max(from, next!.from + start),
                        to: min(to, currentPos),
                        inheritedClass: "",
                        highlighters: innerHighlighters
                    )
                    startSpan(at: min(to, currentPos), cls: cls)
                }
            }
            
            if hasChild {
                _ = cursor.parent()
            }
        } else if cursor.firstChild() {
            repeat {
                if cursor.to <= from {
                    continue
                }
                if cursor.from >= to {
                    break
                }
                highlightRange(
                    cursor: cursor,
                    from: from,
                    to: to,
                    inheritedClass: inheritedClass,
                    highlighters: highlighters
                )
                startSpan(at: min(to, cursor.to), cls: cls)
            } while cursor.nextSibling()
            
            _ = cursor.parent()
        }
    }
}

/// Match a syntax node's highlight rules.
public func getStyleTags(node: SyntaxNodeRef) -> StyleTagsResult? {
    var rule = node.type.prop(prop: styleRuleNodeProp)
    
    while let currentRule = rule, let context = currentRule.context, !node.matchContext(context: context) {
        rule = rule?.next
    }
    
    guard let rule = rule else {
        return nil
    }
    
    return StyleTagsResult(tags: rule.tags, opaque: rule.opaque, inherit: rule.inherit)
}

public struct StyleTagsResult {
    public let tags: [Tag]
    public let opaque: Bool
    public let inherit: Bool
}

/// The default set of highlighting tags.
public struct Tags {
    public let comment: Tag
    public let lineComment: Tag
    public let blockComment: Tag
    public let docComment: Tag
    public let name: Tag
    public let variableName: Tag
    public let typeName: Tag
    public let tagName: Tag
    public let propertyName: Tag
    public let attributeName: Tag
    public let className: Tag
    public let labelName: Tag
    public let namespace: Tag
    public let macroName: Tag
    public let literal: Tag
    public let string: Tag
    public let docString: Tag
    public let character: Tag
    public let attributeValue: Tag
    public let number: Tag
    public let integer: Tag
    public let float: Tag
    public let bool: Tag
    public let regexp: Tag
    public let escape: Tag
    public let color: Tag
    public let url: Tag
    public let keyword: Tag
    public let selfKeyword: Tag
    public let nullKeyword: Tag
    public let atom: Tag
    public let unit: Tag
    public let modifierKeyword: Tag
    public let operatorKeyword: Tag
    public let controlKeyword: Tag
    public let definitionKeyword: Tag
    public let moduleKeyword: Tag
    public let operatorSymbol: Tag
    public let derefOperator: Tag
    public let arithmeticOperator: Tag
    public let logicOperator: Tag
    public let bitwiseOperator: Tag
    public let compareOperator: Tag
    public let updateOperator: Tag
    public let definitionOperator: Tag
    public let typeOperator: Tag
    public let controlOperator: Tag
    public let punctuation: Tag
    public let separator: Tag
    public let bracket: Tag
    public let angleBracket: Tag
    public let squareBracket: Tag
    public let paren: Tag
    public let brace: Tag
    public let content: Tag
    public let heading: Tag
    public let heading1: Tag
    public let heading2: Tag
    public let heading3: Tag
    public let heading4: Tag
    public let heading5: Tag
    public let heading6: Tag
    public let contentSeparator: Tag
    public let list: Tag
    public let quote: Tag
    public let emphasis: Tag
    public let strong: Tag
    public let link: Tag
    public let monospace: Tag
    public let strikethrough: Tag
    public let inserted: Tag
    public let deleted: Tag
    public let changed: Tag
    public let invalid: Tag
    public let meta: Tag
    public let documentMeta: Tag
    public let annotation: Tag
    public let processingInstruction: Tag
    public let definition: (Tag) -> Tag
    public let constant: (Tag) -> Tag
    public let function: (Tag) -> Tag
    public let standard: (Tag) -> Tag
    public let local: (Tag) -> Tag
    public let special: (Tag) -> Tag
    
    public nonisolated(unsafe) static let shared = Tags()
    
    private init() {
        let t = { Tag.define() }
        
        let _comment = t()
        let _name = t()
        let _typeName = Tag.define(.tag(_name))
        let _propertyName = Tag.define(.tag(_name))
        let _literal = t()
        let _string = Tag.define(.tag(_literal))
        let _number = Tag.define(.tag(_literal))
        let _content = t()
        let _heading = Tag.define(.tag(_content))
        let _keyword = t()
        let _operator = t()
        let _punctuation = t()
        let _bracket = Tag.define(.tag(_punctuation))
        let _meta = t()
        
        self.comment = _comment
        self.lineComment = Tag.define(.tag(_comment))
        self.blockComment = Tag.define(.tag(_comment))
        self.docComment = Tag.define(.tag(_comment))
        self.name = _name
        self.variableName = Tag.define(.tag(_name))
        self.typeName = _typeName
        self.tagName = Tag.define(.tag(_typeName))
        self.propertyName = _propertyName
        self.attributeName = Tag.define(.tag(_propertyName))
        self.className = Tag.define(.tag(_name))
        self.labelName = Tag.define(.tag(_name))
        self.namespace = Tag.define(.tag(_name))
        self.macroName = Tag.define(.tag(_name))
        self.literal = _literal
        self.string = _string
        self.docString = Tag.define(.tag(_string))
        self.character = Tag.define(.tag(_string))
        self.attributeValue = Tag.define(.tag(_string))
        self.number = _number
        self.integer = Tag.define(.tag(_number))
        self.float = Tag.define(.tag(_number))
        self.bool = Tag.define(.tag(_literal))
        self.regexp = Tag.define(.tag(_literal))
        self.escape = Tag.define(.tag(_literal))
        self.color = Tag.define(.tag(_literal))
        self.url = Tag.define(.tag(_literal))
        self.keyword = _keyword
        self.selfKeyword = Tag.define(.tag(_keyword))
        self.nullKeyword = Tag.define(.tag(_keyword))
        self.atom = Tag.define(.tag(_keyword))
        self.unit = Tag.define(.tag(_keyword))
        self.modifierKeyword = Tag.define(.tag(_keyword))
        self.operatorKeyword = Tag.define(.tag(_keyword))
        self.controlKeyword = Tag.define(.tag(_keyword))
        self.definitionKeyword = Tag.define(.tag(_keyword))
        self.moduleKeyword = Tag.define(.tag(_keyword))
        self.operatorSymbol = _operator
        self.derefOperator = Tag.define(.tag(_operator))
        self.arithmeticOperator = Tag.define(.tag(_operator))
        self.logicOperator = Tag.define(.tag(_operator))
        self.bitwiseOperator = Tag.define(.tag(_operator))
        self.compareOperator = Tag.define(.tag(_operator))
        self.updateOperator = Tag.define(.tag(_operator))
        self.definitionOperator = Tag.define(.tag(_operator))
        self.typeOperator = Tag.define(.tag(_operator))
        self.controlOperator = Tag.define(.tag(_operator))
        self.punctuation = _punctuation
        self.separator = Tag.define(.tag(_punctuation))
        self.bracket = _bracket
        self.angleBracket = Tag.define(.tag(_bracket))
        self.squareBracket = Tag.define(.tag(_bracket))
        self.paren = Tag.define(.tag(_bracket))
        self.brace = Tag.define(.tag(_bracket))
        self.content = _content
        self.heading = _heading
        self.heading1 = Tag.define(.tag(_heading))
        self.heading2 = Tag.define(.tag(_heading))
        self.heading3 = Tag.define(.tag(_heading))
        self.heading4 = Tag.define(.tag(_heading))
        self.heading5 = Tag.define(.tag(_heading))
        self.heading6 = Tag.define(.tag(_heading))
        self.contentSeparator = Tag.define(.tag(_content))
        self.list = Tag.define(.tag(_content))
        self.quote = Tag.define(.tag(_content))
        self.emphasis = Tag.define(.tag(_content))
        self.strong = Tag.define(.tag(_content))
        self.link = Tag.define(.tag(_content))
        self.monospace = Tag.define(.tag(_content))
        self.strikethrough = Tag.define(.tag(_content))
        self.inserted = t()
        self.deleted = t()
        self.changed = t()
        self.invalid = t()
        self.meta = _meta
        self.documentMeta = Tag.define(.tag(_meta))
        self.annotation = Tag.define(.tag(_meta))
        self.processingInstruction = Tag.define(.tag(_meta))
        self.definition = Tag.defineModifier("definition")
        self.constant = Tag.defineModifier("constant")
        self.function = Tag.defineModifier("function")
        self.standard = Tag.defineModifier("standard")
        self.local = Tag.defineModifier("local")
        self.special = Tag.defineModifier("special")
    }
}

/// This is a highlighter that adds stable, predictable classes to tokens.
public nonisolated(unsafe) let classHighlighter: any Highlighter = tagHighlighter(
    tags: [
        TagStyle(tag: .tag(Tags.shared.link), class: "tok-link"),
        TagStyle(tag: .tag(Tags.shared.heading), class: "tok-heading"),
        TagStyle(tag: .tag(Tags.shared.emphasis), class: "tok-emphasis"),
        TagStyle(tag: .tag(Tags.shared.strong), class: "tok-strong"),
        TagStyle(tag: .tag(Tags.shared.keyword), class: "tok-keyword"),
        TagStyle(tag: .tag(Tags.shared.atom), class: "tok-atom"),
        TagStyle(tag: .tag(Tags.shared.bool), class: "tok-bool"),
        TagStyle(tag: .tag(Tags.shared.url), class: "tok-url"),
        TagStyle(tag: .tag(Tags.shared.labelName), class: "tok-labelName"),
        TagStyle(tag: .tag(Tags.shared.inserted), class: "tok-inserted"),
        TagStyle(tag: .tag(Tags.shared.deleted), class: "tok-deleted"),
        TagStyle(tag: .tag(Tags.shared.literal), class: "tok-literal"),
        TagStyle(tag: .tag(Tags.shared.string), class: "tok-string"),
        TagStyle(tag: .tag(Tags.shared.number), class: "tok-number"),
        TagStyle(tag: .tags([Tags.shared.regexp, Tags.shared.escape, Tags.shared.special(Tags.shared.string)]), class: "tok-string2"),
        TagStyle(tag: .tag(Tags.shared.variableName), class: "tok-variableName"),
        TagStyle(tag: .tag(Tags.shared.local(Tags.shared.variableName)), class: "tok-variableName tok-local"),
        TagStyle(tag: .tag(Tags.shared.definition(Tags.shared.variableName)), class: "tok-variableName tok-definition"),
        TagStyle(tag: .tag(Tags.shared.special(Tags.shared.variableName)), class: "tok-variableName2"),
        TagStyle(tag: .tag(Tags.shared.definition(Tags.shared.propertyName)), class: "tok-propertyName tok-definition"),
        TagStyle(tag: .tag(Tags.shared.typeName), class: "tok-typeName"),
        TagStyle(tag: .tag(Tags.shared.namespace), class: "tok-namespace"),
        TagStyle(tag: .tag(Tags.shared.className), class: "tok-className"),
        TagStyle(tag: .tag(Tags.shared.macroName), class: "tok-macroName"),
        TagStyle(tag: .tag(Tags.shared.propertyName), class: "tok-propertyName"),
        TagStyle(tag: .tag(Tags.shared.operatorSymbol), class: "tok-operator"),
        TagStyle(tag: .tag(Tags.shared.comment), class: "tok-comment"),
        TagStyle(tag: .tag(Tags.shared.meta), class: "tok-meta"),
        TagStyle(tag: .tag(Tags.shared.invalid), class: "tok-invalid"),
        TagStyle(tag: .tag(Tags.shared.punctuation), class: "tok-punctuation"),
    ],
    options: HighlighterOptions()
)
