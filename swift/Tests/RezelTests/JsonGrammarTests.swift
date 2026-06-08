import Foundation
@testable import Rezel
import Testing

private let jsonTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("json")
	.appendingPathComponent("test")

@Suite(.serialized)
struct JsonGrammarTests {
	@Test func literals() throws {
		let tests = try fileTests(String(contentsOf: jsonTestDir.appendingPathComponent("literals.txt"), encoding: .utf8), "literals.txt")
		for t in tests {
			try t.run(jsonParser)
		}
	}

	@Test func strings() throws {
		let tests = try fileTests(String(contentsOf: jsonTestDir.appendingPathComponent("strings.txt"), encoding: .utf8), "strings.txt")
		for t in tests {
			try t.run(jsonParser)
		}
	}

	@Test func numbers() throws {
		let tests = try fileTests(String(contentsOf: jsonTestDir.appendingPathComponent("numbers.txt"), encoding: .utf8), "numbers.txt")
		for t in tests {
			try t.run(jsonParser)
		}
	}

	@Test func objects() throws {
		let tests = try fileTests(String(contentsOf: jsonTestDir.appendingPathComponent("objects.txt"), encoding: .utf8), "objects.txt")
		for t in tests {
			try t.run(jsonParser)
		}
	}

	@Test func arrays() throws {
		let tests = try fileTests(String(contentsOf: jsonTestDir.appendingPathComponent("arrays.txt"), encoding: .utf8), "arrays.txt")
		for t in tests {
			try t.run(jsonParser)
		}
	}
}
