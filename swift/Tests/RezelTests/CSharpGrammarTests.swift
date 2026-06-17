import Foundation
@testable import Rezel
import Testing

private let csharpTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("codemirror-lang-csharp")
	.appendingPathComponent("test")

private func runCSharpTests(_ file: String) throws {
	let content = try String(contentsOf: csharpTestDir.appendingPathComponent(file), encoding: .utf8)
	let tests = try fileTests(content, file)
	for t in tests {
		try t.run(csharpParser)
	}
}

@Suite(.serialized)
struct CSharpGrammarTests {
	@Test func comments() throws {
		try runCSharpTests("comments.txt")
	}

	@Test func declarations() throws {
		try runCSharpTests("declarations.txt")
	}

	@Test func expressions() throws {
		try runCSharpTests("expressions.txt")
	}

	@Test func literals() throws {
		try runCSharpTests("literals.txt")
	}

	@Test func types() throws {
		try runCSharpTests("types.txt")
	}
}
