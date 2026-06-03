import Foundation

private class StringInputAdapter: Input {
    let string: String
    init(_ string: String) { self.string = string }
    var length: Int { string.count }
    func chunk(from: Int) -> String {
        let clamped = min(max(from, 0), string.utf16.count)
        let idx = String.Index(utf16Offset: clamped, in: string)
        return String(string[idx...])
    }
    var lineChunks: Bool { false }
    func read(from: Int, to: Int) -> String {
        let clampedFrom = min(max(from, 0), string.utf16.count)
        let clampedTo = min(max(to, clampedFrom), string.utf16.count)
        let start = String.Index(utf16Offset: clampedFrom, in: string)
        let end = String.Index(utf16Offset: clampedTo, in: string)
        return String(string[start..<end])
    }
}

private class TestSpec {
    let name: String
    let props: [(propId: Int, value: Any)]
    let children: [TestSpec]
    let wildcard: Bool

    init(
        name: String,
        props: [(propId: Int, value: Any)],
        children: [TestSpec],
        wildcard: Bool
    ) {
        self.name = name
        self.props = props
        self.children = children
        self.wildcard = wildcard
    }

    static func parse(_ spec: String) -> [TestSpec] {
        var pos = spec.startIndex
        var tok = "sof"
        var value = ""

        func err() -> Never {
            fatalError("Invalid test spec: \(spec)")
        }

        func advance() {
            pos = spec.index(after: pos)
        }

        func peekChar() -> Character {
            guard pos < spec.endIndex else { return "\0" }
            return spec[pos]
        }

        @discardableResult
        func next() -> String {
            while pos < spec.endIndex && spec[pos].isWhitespace {
                pos = spec.index(after: pos)
            }
            if pos == spec.endIndex {
                tok = "eof"
                return tok
            }
            let ch = peekChar()
            advance()

            if ch == "(" && spec[pos...].hasPrefix("...)") {
                pos = spec.index(pos, offsetBy: 3)
                tok = "..."
                return tok
            }

            if ch == "[" || ch == "]" || ch == "(" || ch == ")" || ch == "," || ch == "=" {
                tok = String(ch)
                return tok
            }

            if ch != "[" && ch != "]" && ch != "(" && ch != ")" && ch != "," && ch != "=" && ch != "\"" && !ch.isWhitespace {
                var name = ""
                var cur = spec.index(before: pos)
                while cur < spec.endIndex {
                    let c = spec[cur]
                    if c == "[" || c == "]" || c == "(" || c == ")" || c == "," || c == "=" || c == "\"" || c.isWhitespace {
                        break
                    }
                    name.append(c)
                    cur = spec.index(after: cur)
                }
                pos = cur
                value = name
                tok = "name"
                return tok
            }

            if ch == "\"" {
                var content = "\""
                var cur = pos
                while cur < spec.endIndex && spec[cur] != "\"" {
                    if spec[cur] == "\\" {
                        cur = spec.index(after: cur)
                        if cur < spec.endIndex {
                            content.append(spec[cur])
                        }
                    } else {
                        content.append(spec[cur])
                    }
                    cur = spec.index(after: cur)
                }
                if cur < spec.endIndex {
                    content.append(spec[cur])
                    cur = spec.index(after: cur)
                }
                pos = cur

                // Remove surrounding quotes and unescape
                let inner = content.dropFirst().dropLast()
                value = inner.replacingOccurrences(of: "\\\"", with: "\"")
                tok = "name"
                return tok
            }

            err()
        }

        func parseSeq() -> [TestSpec] {
            var seq: [TestSpec] = []
            while tok != "eof" && tok != ")" {
                seq.append(parse())
                if tok == "," {
                    next()
                }
            }
            return seq
        }

        func parse() -> TestSpec {
            guard tok == "name" else { err() }
            let name = value
            var children: [TestSpec] = []
            var props: [(propId: Int, value: Any)] = []
            var wildcard = false
            next()

            if tok == "[" {
                next()
                while tok != "]" {
                    guard tok == "name" else { err() }
                    let propName = value
                    next()
                    var propVal = ""
                    if tok == "=" {
                        next()
                        guard tok == "name" else { err() }
                        propVal = value
                        next()
                    }
                    // Look up the NodeProp by name from well-known props
                    if let (propId, deserializer) = lookupNodeProp(name: propName) {
                        let deserialized = deserializer(propVal)
                        props.append((propId: propId, value: deserialized))
                    }
                }
                guard tok == "]" else { err() }
                next()
            }

            if tok == "(" {
                next()
                children = parseSeq()
                guard tok == ")" else { err() }
                next()
            } else if tok == "..." {
                wildcard = true
                next()
            }

            return TestSpec(name: name, props: props, children: children, wildcard: wildcard)
        }

        next()
        let result = parseSeq()
        guard tok == "eof" else { err() }
        return result
    }

    func matches(_ type: NodeType) -> Bool {
        guard type.name == name else { return false }
        for (propId, expectedValue) in props {
            let actual = type.props[propId]
            if !areEqual(actual, expectedValue) {
                return false
            }
        }
        return true
    }

    private func areEqual(_ a: Any?, _ b: Any?) -> Bool {
        guard let a = a, let b = b else { return a == nil && b == nil }
        return "\(a)" == "\(b)"
    }
}

private func lookupNodeProp(name: String) -> (propId: Int, (String) -> Any)? {
    switch name {
    case "closedBy":
        return (nodePropClosedBy.id, { nodePropClosedBy.deserialize($0) })
    case "openedBy":
        return (nodePropOpenedBy.id, { nodePropOpenedBy.deserialize($0) })
    case "group":
        return (nodePropGroup.id, { nodePropGroup.deserialize($0) })
    case "isolate":
        return (nodePropIsolate.id, { nodePropIsolate.deserialize($0) })
    case "contextHash":
        return (nodePropContextHash.id, { nodePropContextHash.deserialize($0) })
    case "lookAhead":
        return (nodePropLookAhead.id, { nodePropLookAhead.deserialize($0) })
    case "mounted":
        return (nodePropMounted.id, { nodePropMounted.deserialize($0) })
    default:
        return nil
    }
}

private func defaultIgnore(_ type: NodeType) -> Bool {
    return type.name.range(of: #"\W"#, options: .regularExpression) != nil
}

public func testTree(
    tree: Tree,
    expect: String,
    mayIgnore: ((NodeType) -> Bool)? = nil
) {
    let ignore = mayIgnore ?? defaultIgnore
    let specs = TestSpec.parse(expect)
    var stack: [[TestSpec]] = [specs]
    var pos: [Int] = [0]

    tree.iterate(
        enter: { n in
            guard !n.name.isEmpty else { return true }
            let last = stack.count - 1
            let index = pos[last]
            let seq = stack[last]
            let nextSpec = index < seq.count ? seq[index] : nil

            if let nextSpec = nextSpec, nextSpec.matches(n.type) {
                if nextSpec.wildcard {
                    pos[last] += 1
                    return false
                }
                pos.append(0)
                stack.append(nextSpec.children)
                return true
            } else if ignore(n.type) {
                return false
            } else {
                let parent = last > 0 ? stack[last - 1][pos[last - 1]].name : "tree"
                let after: String
                if let nextSpec = nextSpec {
                    after = nextSpec.name + (parent == "tree" ? "" : " in \(parent)")
                } else {
                    after = "end of \(parent)"
                }
                fatalError("Expected \(after), got \(n.name) at \(n.to) \n\(tree.toString())")
            }
        },
        leave: { n in
            guard !n.name.isEmpty else { return }
            let last = stack.count - 1
            let index = pos[last]
            let seq = stack[last]
            if index < seq.count {
                let expected = seq[index...].map { $0.name }.joined(separator: ", ")
                fatalError("Unexpected end of \(n.name). Expected \(expected) at \(n.from)\n\(tree.toString())")
            }
            pos.removeLast()
            stack.removeLast()
            pos[last - 1] += 1
        }
    )

    if pos[0] != specs.count {
        let expected = stack[0][pos[0]...].map { $0.name }.joined(separator: ", ")
        fatalError("Unexpected end of tree. Expected \(expected) at \(tree.length)\n\(tree.toString())")
    }
}

private func idx(_ location: Int, in string: String, offsetBy offset: Int = 0, limitedBy limit: String.Index? = nil) -> String.Index {
    let total = min(max(location + offset, 0), string.utf16.count)
    return String.Index(utf16Offset: total, in: string)
}

private func toLineContext(_ file: String, _ index: String.Index) -> String {
    var endIndex = file.endIndex
    if let searchRange = file.index(index, offsetBy: 80, limitedBy: file.endIndex) {
        if let eol = file.range(of: "\n", range: searchRange..<file.endIndex) {
            endIndex = eol.lowerBound
        }
    }
    return String(file[index..<endIndex])
        .components(separatedBy: "\n")
        .map { "  | \($0)" }
        .joined(separator: "\n")
}

public struct FileTest {
    public let name: String
    public let text: String
    public let expected: String
    public let configStr: String
    public let config: [String: Any]?
    public let strict: Bool
    public let run: (any Parser) -> Void
}

public enum FileTestError: Error, CustomStringConvertible {
    case unexpectedFormat(file: String, context: String)
    case invalidHeader(String)

    public var description: String {
        switch self {
        case .unexpectedFormat(let file, let context):
            return "Unexpected file format in \(file) around\n\n\(context)"
        case .invalidHeader(let header):
            return "Invalid test header: \(header)"
        }
    }
}

public func fileTests(
    file: String,
    fileName: String,
    mayIgnore: ((NodeType) -> Bool)? = nil
) throws -> [FileTest] {
    let ignore = mayIgnore ?? defaultIgnore
    var tests: [FileTest] = []
    var lastIndex = file.startIndex

    let pattern = #"\s*#[ \t]*(.*)(?:\r\n|\r|\n)([\s\S]*?)==+>([\s\S]*?)(?:$|(?:\r\n|\r|\n)+(?=#))"#
    let regex = try! NSRegularExpression(pattern: pattern)

    var searchStart = file.startIndex
    while searchStart < file.endIndex {
        let nsRange = NSRange(searchStart..<file.endIndex, in: file)
        guard let match = regex.firstMatch(in: file, options: [], range: nsRange) else {
            throw FileTestError.unexpectedFormat(file: fileName, context: toLineContext(file, lastIndex))
        }

        let fullNSRange = match.range
        let fullLower = idx(fullNSRange.location, in: file)
        let fullUpper = idx(fullNSRange.location, in: file, offsetBy: fullNSRange.length, limitedBy: file.endIndex)
        let fullRange = fullLower..<fullUpper

        let headerNS = match.range(at: 1)
        let headerLower = idx(headerNS.location, in: file)
        let headerUpper = idx(headerNS.location, in: file, offsetBy: headerNS.length, limitedBy: file.endIndex)
        let headerRange = headerLower..<headerUpper

        let inputNS = match.range(at: 2)
        let inputLower = idx(inputNS.location, in: file)
        let inputUpper = idx(inputNS.location, in: file, offsetBy: inputNS.length, limitedBy: file.endIndex)
        let inputRange = inputLower..<inputUpper

        let expectedNS = match.range(at: 3)
        let expectedLower = idx(expectedNS.location, in: file)
        let expectedUpper = idx(expectedNS.location, in: file, offsetBy: expectedNS.length, limitedBy: file.endIndex)
        let expectedRange = expectedLower..<expectedUpper

        let header = String(file[headerRange])
        let text = String(file[inputRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = String(file[expectedRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        let headerRegex = try! NSRegularExpression(pattern: #"^(.*?)(\{.*?\})?$"#)
        let headerNSRange = NSRange(header.startIndex..., in: header)
        guard let headerMatch = headerRegex.firstMatch(in: header, options: [], range: headerNSRange) else {
            throw FileTestError.invalidHeader(header)
        }

        let nameNS = headerMatch.range(at: 1)
        let nameLower = idx(nameNS.location, in: header)
        let nameUpper = idx(nameNS.location, in: header, offsetBy: nameNS.length, limitedBy: header.endIndex)
        let name = String(header[nameLower..<nameUpper])

        var configStr = ""
        var config: [String: Any]? = nil
        if headerMatch.range(at: 2).location != NSNotFound {
            let configNS = headerMatch.range(at: 2)
            let configLower = idx(configNS.location, in: header)
            let configUpper = idx(configNS.location, in: header, offsetBy: configNS.length, limitedBy: header.endIndex)
            configStr = String(header[configLower..<configUpper])
            if let data = configStr.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                config = obj
            }
        }

        let strict = !expected.contains("⚠") && !expected.contains("...")

        let capturedConfig = config
        let capturedStrict = strict
        let capturedConfigStr = configStr

        tests.append(FileTest(
            name: name,
            text: text,
            expected: expected,
            configStr: capturedConfigStr,
            config: capturedConfig,
            strict: capturedStrict,
            run: { parser in
                var configuredParser = parser
                if let lrParser = configuredParser as? LRParser, (capturedStrict || capturedConfig != nil) {
                    var options = ParserConfig()
                    options.strict = capturedStrict
                    configuredParser = lrParser.configure(config: options)
                }
                let inputObj = StringInputAdapter(text)
                let tree = configuredParser.parse(input: inputObj)
                testTree(tree: tree, expect: expected, mayIgnore: ignore)
            }
        ))

        lastIndex = fullRange.upperBound
        searchStart = fullRange.upperBound
        if searchStart >= file.endIndex || file[searchStart...].allSatisfy({ $0.isWhitespace }) {
            break
        }
    }

    return tests
}
