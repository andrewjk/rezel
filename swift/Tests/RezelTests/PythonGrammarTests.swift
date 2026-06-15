import Foundation
@testable import Rezel
import Testing

private let pythonTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("python")
	.appendingPathComponent("test")

private func runPythonTests(_ file: String) throws {
	let content = try String(contentsOf: pythonTestDir.appendingPathComponent(file), encoding: .utf8)
	let tests = try fileTests(content, file)
	for t in tests {
		try t.run(pythonParser)
	}
}

@Suite(.serialized)
struct PythonGrammarTests {
	@Test func expression() throws {
		try runPythonTests("expression.txt")
	}

	@Test func statement() throws {
		try runPythonTests("statement.txt")
	}
}
