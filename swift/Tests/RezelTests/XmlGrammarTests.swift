import Foundation
@testable import Rezel
import Testing

private let xmlTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("xml")
	.appendingPathComponent("test")

@Suite(.serialized)
struct XmlGrammarTests {
	@Test func tags() throws {
		let content = try String(contentsOf: xmlTestDir.appendingPathComponent("tags.txt"), encoding: .utf8)
		let tests = try fileTests(content, "tags.txt")
		for t in tests {
			try t.run(xmlParser)
		}
	}
}
