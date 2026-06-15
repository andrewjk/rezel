import Foundation
@testable import Rezel
import Testing

private let rustTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("rust")
	.appendingPathComponent("test")

private func runRustTests(_ file: String) throws {
	let content = try String(contentsOf: rustTestDir.appendingPathComponent(file), encoding: .utf8)
	let tests = try fileTests(content, file)
	for t in tests {
		try t.run(rustParser)
	}
}

@Suite(.serialized)
struct RustGrammarTests {
	@Test func asyncTests() throws {
		try runRustTests("async.txt")
	}

	@Test func comments() throws {
		try runRustTests("comments.txt")
	}

	@Test func declarations() throws {
		try runRustTests("declarations.txt")
	}

	@Test func expressions() throws {
		try runRustTests("expressions.txt")
	}

	@Test func literals() throws {
		try runRustTests("literals.txt")
	}

	@Test func macros() throws {
		try runRustTests("macros.txt")
	}

	@Test func patterns() throws {
		try runRustTests("patterns.txt")
	}

	@Test func types() throws {
		try runRustTests("types.txt")
	}
}
