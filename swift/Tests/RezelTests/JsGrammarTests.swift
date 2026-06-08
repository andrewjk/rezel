import Foundation
@testable import Rezel
import Testing

private let jsTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("javascript")
	.appendingPathComponent("test")

private func runJsTests(_ file: String) throws {
	let content = try String(contentsOf: jsTestDir.appendingPathComponent(file), encoding: .utf8)
	let tests = try fileTests(content, file)
	for t in tests {
		try t.run(jsParser)
	}
}

@Suite(.serialized)
struct JsGrammarTests {
	@Test func expression() throws {
		try runJsTests("expression.txt")
	}

	@Test func statement() throws {
		try runJsTests("statement.txt")
	}

	@Test func semicolon() throws {
		try runJsTests("semicolon.txt")
	}

	@Test func decorator() throws {
		try runJsTests("decorator.txt")
	}

	@Test func jsx() throws {
		try runJsTests("jsx.txt")
	}

	@Test func typescript() throws {
		try runJsTests("typescript.txt")
	}

	@Test func debugSkip() {
		for input in ["1;2;", "1;\n2;", "1\n2"] {
			let tree = jsParser.parse(input: input)
			let display = input.replacingOccurrences(of: "\n", with: "\\n")
			print("'\(display)' -> \(tree)")
		}
	}
}
