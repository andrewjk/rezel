import Foundation
@testable import Rezel
import Testing

private let phpTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("php")
	.appendingPathComponent("test")

private func runPhpTests(_ file: String) throws {
	let content = try String(contentsOf: phpTestDir.appendingPathComponent(file), encoding: .utf8)
	let tests = try fileTests(content, file)
	for t in tests {
		try t.run(phpParser)
	}
}

@Suite(.serialized)
struct PhpGrammarTests {
	@Test func phpClass() throws {
		try runPhpTests("class.txt")
	}

	@Test func declarations() throws {
		try runPhpTests("declarations.txt")
	}

	@Test func expressions() throws {
		try runPhpTests("expressions.txt")
	}

	@Test func interpolation() throws {
		try runPhpTests("interpolation.txt")
	}

	@Test func literals() throws {
		try runPhpTests("literals.txt")
	}

	@Test func statements() throws {
		try runPhpTests("statements.txt")
	}

	@Test func string() throws {
		try runPhpTests("string.txt")
	}

	@Test func types() throws {
		try runPhpTests("types.txt")
	}
}
