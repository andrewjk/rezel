import Foundation

public class TestSpec {
	public let name: String
	public let props: [(prop: NodePropBase, value: Any)]
	public let children: [TestSpec]
	public let wildcard: Bool

	public init(name: String, props: [(prop: NodePropBase, value: Any)], children: [TestSpec] = [], wildcard: Bool = false) {
		self.name = name; self.props = props; self.children = children; self.wildcard = wildcard
	}

	public static func parse(_ spec: String) throws -> [TestSpec] {
		var pos = spec.startIndex
		var tok = "sof"
		var value = ""

		func err() -> Never {
			fatalError("Invalid test spec: \(spec)")
		}

		func advance() {
			while pos < spec.endIndex, spec[pos].isWhitespace {
				pos = spec.index(after: pos)
			}
			if pos == spec.endIndex { tok = "eof"; return }
			let ch = spec[pos]; pos = spec.index(after: pos)
			if ch == "(", spec.distance(from: pos, to: spec.endIndex) >= 4, spec[pos...].prefix(4) == "...)" {
				pos = spec.index(pos, offsetBy: 4)
				tok = "..."; return
			}
			if "[](),=".contains(ch) { tok = String(ch); return }
			if !ch.isWhitespace, !"[](),=\"".contains(ch) {
				let start = spec.index(before: pos)
				var end = start
				while end < spec.endIndex, !spec[end].isWhitespace, !"[](),=\"".contains(spec[end]) {
					end = spec.index(after: end)
				}
				value = String(spec[start ..< end])
				pos = end
				tok = "name"; return
			}
			if ch == "\"" {
				let start = spec.index(before: pos)
				var end = spec.index(after: start)
				while end < spec.endIndex {
					if spec[end] == "\\" { end = spec.index(after: end); if end < spec.endIndex { end = spec.index(after: end) } }
					else if spec[end] == "\"" { end = spec.index(after: end); break }
					else { end = spec.index(after: end) }
				}
				let raw = String(spec[start ..< end])
				let jsonData = raw.data(using: .utf8) ?? Data()
				if let parsed = try? JSONSerialization.jsonObject(with: jsonData, options: .fragmentsAllowed) as? String {
					value = parsed
				} else {
					value = raw
				}
				pos = end
				tok = "name"; return
			}
			err()
		}

		advance()

		func parseSeq() -> [TestSpec] {
			var seq: [TestSpec] = []
			while tok != "eof", tok != ")" {
				seq.append(parseSpec())
				if tok == "," { advance() }
			}
			return seq
		}

		func parseSpec() -> TestSpec {
			let name = value
			var children: [TestSpec] = []
			var props: [(prop: NodePropBase, value: Any)] = []
			var wildcard = false
			if tok != "name" { err() }
			advance()
			if tok == "[" {
				advance()
				while tok != "]" {
					if tok != "name" { err() }
					let propName = value
					advance()
					var propValue: Any = ""
					if tok == "=" {
						advance()
						if tok != "name" { err() }
						propValue = value
						advance()
					}
					if let prop = nodePropByName[propName] as? NodeProp<String> {
						props.append((prop: prop, value: prop.deserialize(propValue as? String ?? "")))
					} else if let prop = nodePropByName[propName] {
						props.append((prop: prop, value: propValue))
					}
				}
				advance()
			}
			if tok == "(" {
				advance()
				children = parseSeq()
				if tok != ")" { err() }
				advance()
			} else if tok == "..." {
				wildcard = true
				advance()
			}
			return TestSpec(name: name, props: props, children: children, wildcard: wildcard)
		}

		let result = parseSeq()
		if tok != "eof" { err() }
		return result
	}

	public func matches(_ type: NodeType) -> Bool {
		guard type.name == name else { return false }
		for (prop, value) in props {
			if let stringProp = prop as? NodeProp<String> {
				let typeProp = type.prop(stringProp)
				let specVal = value as? String ?? ""
				if specVal.isEmpty {
					if typeProp != nil { return false }
					continue
				}
				guard let typeProp = typeProp else { return false }
				if typeProp != specVal { return false }
			} else if let stringArrayProp = prop as? NodeProp<[String]> {
				let typeProp = type.prop(stringArrayProp)
				let specVal = value as? [String] ?? []
				if specVal.isEmpty {
					if typeProp != nil { return false }
					continue
				}
				guard let typeProp = typeProp else { return false }
				if typeProp != specVal { return false }
			}
		}
		return true
	}
}

public func defaultIgnore(_ type: NodeType) -> Bool {
	let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
	return type.name.unicodeScalars.contains { !wordChars.contains($0) }
}

private func toLineContext(_ file: String, _ index: Int) -> String {
	let startIdx = file.index(file.startIndex, offsetBy: index)
	let searchFrom = file.index(startIdx, offsetBy: 80, limitedBy: file.endIndex) ?? file.endIndex
	var endIdx: String.Index
	if let nlRange = file[searchFrom...].rangeOfCharacter(from: .newlines) {
		endIdx = nlRange.lowerBound
	} else {
		endIdx = file.endIndex
	}
	return file[startIdx ..< endIdx]
		.split(separator: "\n", omittingEmptySubsequences: false)
		.map { "  | " + $0 }
		.joined(separator: "\n")
}

public func fileTests(_ file: String, _ fileName: String) throws -> [(name: String, text: String, expected: String, run: (Parser) throws -> Void)] {
	var tests: [(name: String, text: String, expected: String, run: (Parser) throws -> Void)] = []
	let pattern = "\\s*#[ \\t]*(.*?)(?:\\r\\n|\\r|\\n)([\\s\\S]*?)==+>([\\s\\S]*?)(?:$|(?:\\r\\n|\\r|\\n)+(?=#))"
	guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return tests }
	let fullRange = NSRange(file.startIndex..., in: file)
	let matches = regex.matches(in: file, range: fullRange)

	var lastIndex = 0
	for m in matches {
		guard m.range.location == lastIndex else {
			throw NSError(domain: "fileTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected file format in \(fileName) around\n\n\(toLineContext(file, lastIndex))"])
		}
		guard let nameRange = Range(m.range(at: 1), in: file),
		      let textRange = Range(m.range(at: 2), in: file),
		      let expectedRange = Range(m.range(at: 3), in: file) else { continue }

		let trimWS = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
		let rawName = String(file[nameRange]).trimmingCharacters(in: trimWS)
		let text = String(file[textRange]).trimmingCharacters(in: trimWS)
		let expected = String(file[expectedRange]).trimmingCharacters(in: trimWS)

		var name = rawName
		var config: [String: Any]? = nil

		if let configRegex = try? NSRegularExpression(pattern: "\\{.*?\\}$", options: []),
		   let range = configRegex.firstMatch(in: rawName, range: NSRange(rawName.startIndex..., in: rawName))?.range
		{
			let configStr = (rawName as NSString).substring(with: range)
			name = (rawName as NSString).substring(to: range.location).trimmingCharacters(in: trimWS)
			if let data = configStr.data(using: .utf8),
			   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
			{
				config = json
			}
		}

		let strict = expected.range(of: "⚠|\\.\\.\\.", options: .regularExpression) == nil

		tests.append((name: name, text: text, expected: expected, run: { parser in
			let p: Parser
			if let lrp = parser as? LRParser {
				p = lrp.configure(
					top: config?["top"] as? String,
					dialect: config?["dialect"] as? String,
					strict: strict
				)
			} else {
				p = parser
			}
			let tree = p.parse(input: text)
			try testTree(tree, expected)
		}))
		lastIndex = m.range.location + m.range.length
	}
	if lastIndex != file.count {
		let endOfContent = file.index(file.startIndex, offsetBy: min(lastIndex, file.count))
		let trimWS = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
		let trailing = file[endOfContent...].trimmingCharacters(in: trimWS)
		if !trailing.isEmpty {
			throw NSError(domain: "fileTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected file format in \(fileName) around\n\n\(toLineContext(file, min(lastIndex, file.count - 1)))"])
		}
	}
	return tests
}

public func testTree(_ tree: Tree, _ expect: String, _ mayIgnore: @escaping (NodeType) -> Bool = defaultIgnore) throws {
	let specs = try TestSpec.parse(expect)
	var stack = [specs]
	var posArr = [0]
	var caughtError: Error?

	tree.cursor().iterate(enter: { n in
		guard !n.name.isEmpty else { return true }
		let name = n.name
		let last = stack.count - 1
		let index = posArr[last]
		let seq = stack[last]
		let next = index < seq.count ? seq[index] : nil

		if let next = next, next.matches(n.type) {
			if next.wildcard {
				posArr[last] += 1
				return false
			}
			posArr.append(0)
			stack.append(next.children)
			return true
		} else if mayIgnore(n.type) {
			return false
		} else {
			let parent = last > 0 ? stack[last - 1][posArr[last - 1]].name : "tree"
			let after = next != nil ? "\(next!.name)\(parent == "tree" ? "" : " in \(parent)")" : "end of \(parent)"
			caughtError = GenError("Expected \(after), got \(name) at \(n.to)")
			return false
		}
	}, leave: { n in
		guard !n.name.isEmpty else { return }
		let name = n.name
		let last = stack.count - 1
		let index = posArr[last]
		let seq = stack[last]
		if index < seq.count {
			let remaining = seq[index...].map { $0.name }.joined(separator: ", ")
			caughtError = GenError("Unexpected end of \(name). Expected \(remaining) at \(n.from)")
			return
		}
		posArr.removeLast()
		stack.removeLast()
		posArr[last - 1] += 1
	})

	if let error = caughtError { throw error }

	if posArr[0] != specs.count {
		let remaining = stack[0][posArr[0]...].map { $0.name }.joined(separator: ", ")
		throw GenError("Unexpected end of tree. Expected \(remaining) at \(tree.length)")
	}
}
