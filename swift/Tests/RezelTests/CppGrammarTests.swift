import Foundation
@testable import Rezel
import Testing

private let cppTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("cpp")
	.appendingPathComponent("test")

private func runCppTests(_ file: String) throws {
	let content = try String(contentsOf: cppTestDir.appendingPathComponent(file), encoding: .utf8)
	let tests = try fileTests(content, file)
	for t in tests {
		try t.run(cppParser)
	}
}

@Suite(.serialized)
struct CppGrammarTests {
	@Test func ambiguities() throws {
		try runCppTests("ambiguities.txt")
	}

	@Test func cpp20() throws {
		try runCppTests("cpp20.txt")
	}

	@Test func declarations() throws {
		try runCppTests("declarations.txt")
	}

	@Test func definitions() throws {
		try runCppTests("definitions.txt")
	}

	@Test func expressions() throws {
		try runCppTests("expressions.txt")
	}

	@Test func microsoft() throws {
		try runCppTests("microsoft.txt")
	}

	@Test func preprocessor() throws {
		try runCppTests("preprocessor.txt")
	}

	@Test func statements() throws {
		try runCppTests("statements.txt")
	}

	@Test func types() throws {
		try runCppTests("types.txt")
	}
}
