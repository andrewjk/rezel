import Foundation
@testable import Rezel
import Testing

private let javaTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("java")
	.appendingPathComponent("test")

private func runJavaTests(_ file: String) throws {
	let content = try String(contentsOf: javaTestDir.appendingPathComponent(file), encoding: .utf8)
	let tests = try fileTests(content, file)
	for t in tests {
		try t.run(javaParser)
	}
}

@Suite(.serialized)
struct JavaGrammarTests {
	@Test func comments() throws {
		try runJavaTests("comments.txt")
	}

	@Test func declarations() throws {
		try runJavaTests("declarations.txt")
	}

	@Test func expressions() throws {
		try runJavaTests("expressions.txt")
	}

	@Test func literals() throws {
		try runJavaTests("literals.txt")
	}

	@Test func types() throws {
		try runJavaTests("types.txt")
	}
}
