import Foundation
@testable import Rezel
import Testing

@Suite(.serialized)
struct JsDiagnosticTests {
	@Test func buildJsParser() {
		do {
			let parser = try buildParser(#"""
@top Script { expression ";" }
expression { Number | VariableName }
@tokens {
  Number { @digit+ }
  VariableName { @asciiLetter+ }
  ";" { ";" }
}
@skip { space }
@tokens { space { @whitespace+ } }
"""#)
			let tree = parser.parse(input: "42;")
			print("Simple parser tree: \(tree)")
			#expect(tree.length == 3)
		} catch {
			Issue.record("Failed to build parser: \(error)")
		}
	}
}
