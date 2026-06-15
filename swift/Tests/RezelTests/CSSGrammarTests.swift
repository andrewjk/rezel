import Foundation
@testable import Rezel
import Testing

private let cssTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("css")
	.appendingPathComponent("test")

private func runCSSTests(_ file: String) throws {
	let content = try String(contentsOf: cssTestDir.appendingPathComponent(file), encoding: .utf8)
	let tests = try fileTests(content, file)
	for t in tests {
		try t.run(cssParser)
	}
}

@Suite(.serialized)
struct CSSGrammarTests {
	@Test func declarations() throws {
		try runCSSTests("declarations.txt")
	}

	@Test func selector() throws {
		try runCSSTests("selector.txt")
	}

	@Test func statements() throws {
		try runCSSTests("statements.txt")
	}
}
