import Foundation
@testable import Rezel
import Testing

private let zigTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("codemirror-lang-zig")
	.appendingPathComponent("test")

private func runZigTests(_ file: String) throws {
	let content = try String(contentsOf: zigTestDir.appendingPathComponent(file), encoding: .utf8)
	let tests = try fileTests(content, file)
	for t in tests {
		try t.run(zigParser)
	}
}

@Suite(.serialized)
struct ZigGrammarTests {
	@Test func comments() throws {
		try runZigTests("comments.txt")
	}

	@Test func declarations() throws {
		try runZigTests("declarations.txt")
	}

	@Test func expressions() throws {
		try runZigTests("expressions.txt")
	}

	@Test func literals() throws {
		try runZigTests("literals.txt")
	}

	@Test func types() throws {
		try runZigTests("types.txt")
	}
}
