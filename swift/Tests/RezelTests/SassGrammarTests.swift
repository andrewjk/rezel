import Foundation
@testable import Rezel
import Testing

private let sassTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("sass")
	.appendingPathComponent("test")

private func runSassTests(_ file: String) throws {
	let content = try String(contentsOf: sassTestDir.appendingPathComponent(file), encoding: .utf8)
	let tests = try fileTests(content, file)
	for t in tests {
		try t.run(sassParser)
	}
}

@Suite(.serialized)
struct SassGrammarTests {
	@Test func declarations() throws {
		try runSassTests("declarations.txt")
	}

	@Test func sass() throws {
		try runSassTests("sass.txt")
	}

	@Test func selector() throws {
		try runSassTests("selector.txt")
	}

	@Test func statements() throws {
		try runSassTests("statements.txt")
	}
}
