import Foundation
@testable import Rezel
import Testing

private let bashTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("lezer-bash")
	.appendingPathComponent("test")

private func runBashTests(_ file: String) throws {
	let content = try String(contentsOf: bashTestDir.appendingPathComponent(file), encoding: .utf8)
	let tests = try fileTests(content, file)
	for t in tests {
		try t.run(bashParser)
	}
}

@Suite(.serialized)
struct BashGrammarTests {
	@Test func comments() throws {
		try runBashTests("comments.txt")
	}

	@Test func basics() throws {
		try runBashTests("basics.txt")
	}

	@Test func pipeline() throws {
		try runBashTests("pipeline.txt")
	}

	@Test func lists() throws {
		try runBashTests("lists.txt")
	}

	@Test func subshell() throws {
		try runBashTests("subshell.txt")
	}

	@Test func braceGroup() throws {
		try runBashTests("brace_group.txt")
	}

	@Test func controlFlow() throws {
		try runBashTests("control_flow.txt")
	}

	@Test func function() throws {
		try runBashTests("function.txt")
	}

	@Test func assignment() throws {
		try runBashTests("assignment.txt")
	}

	@Test func variable() throws {
		try runBashTests("variable.txt")
	}

	@Test func expansion() throws {
		try runBashTests("expansion.txt")
	}

	@Test func substitution() throws {
		try runBashTests("substitution.txt")
	}

	@Test func figVariable() throws {
		try runBashTests("fig_variable.txt")
	}

	@Test func string() throws {
		try runBashTests("string.txt")
	}

	@Test func redirection() throws {
		try runBashTests("redirection.txt")
	}
}
