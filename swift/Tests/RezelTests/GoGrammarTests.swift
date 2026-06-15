import Foundation
@testable import Rezel
import Testing

private let goTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("go")
	.appendingPathComponent("test")

private func runGoTests(_ file: String) throws {
	let content = try String(contentsOf: goTestDir.appendingPathComponent(file), encoding: .utf8)
	let tests = try fileTests(content, file)
	for t in tests {
		try t.run(goParser)
	}
}

@Suite(.serialized)
struct GoGrammarTests {
	@Test func declarations() throws {
		try runGoTests("declarations.txt")
	}

	@Test func expressions() throws {
		try runGoTests("expressions.txt")
	}

	@Test func literals() throws {
		try runGoTests("literals.txt")
	}

	@Test func sourceFiles() throws {
		try runGoTests("source_files.txt")
	}

	@Test func statements() throws {
		try runGoTests("statements.txt")
	}

	@Test func types() throws {
		try runGoTests("types.txt")
	}
}
