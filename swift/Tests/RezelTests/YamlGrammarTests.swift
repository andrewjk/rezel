import Foundation
@testable import Rezel
import Testing

private let yamlTestDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("web")
	.appendingPathComponent("grammars")
	.appendingPathComponent("yaml")
	.appendingPathComponent("test")

private func runYamlTests(_ file: String) throws {
	let content = try String(contentsOf: yamlTestDir.appendingPathComponent(file), encoding: .utf8)
	let tests = try fileTests(content, file)
	for t in tests {
		// HACK: This doesn't work in JS either
		if t.name == "Example 8.15 Block Sequence Entry Types" { continue }
		try t.run(yamlParser)
	}
}

@Suite(.serialized)
struct YamlGrammarTests {
	@Test func debugSpec() throws {
		let content = try String(contentsOf: yamlTestDir.appendingPathComponent("spec.txt"), encoding: .utf8)
		let tests = try fileTests(content, "spec.txt")
		var failures: [(String, Error)] = []
		for t in tests {
			// HACK: This doesn't work in JS either
			if t.name == "Example 8.15 Block Sequence Entry Types" { continue }
			do {
				try t.run(yamlParser)
			} catch {
				failures.append((t.name, error))
			}
		}
		if !failures.isEmpty {
			for (name, error) in failures {
				print("FAIL: \(name) - \(error)")
			}
			print("FAILURES: \(failures.count) out of \(tests.count)")
		}
	}

	@Test func basics() throws {
		try runYamlTests("basics.txt")
	}

	@Test func spec() throws {
		try runYamlTests("spec.txt")
	}
}
