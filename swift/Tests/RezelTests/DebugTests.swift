import Foundation
@testable import Rezel
import Testing

@Suite(.serialized)
struct DebugTests {
	@Test func eofCase() throws {
		let grammar = """
		@top A { (X | Y)+ }

		@tokens {
		  X { "x" }
		  Y { "x" @eof }
		  @precedence { Y, X }
		}
		"""
		let parser = try buildParser(grammar, options: BuildOptions(
			fileName: "test.txt",
			externalTokenizer: { _, _ in fatalError() },
			externalSpecializer: { _, _ in fatalError() },
			externalProp: { _ in NodeProp<String>(deserialize: { x in x }) }
		))

		print("Parser tokenData count: \(parser.data.count)")
		print("Parser tokenizers count: \(parser.tokenizers.count)")
		if let firstTok = parser.tokenizers.first {
			print("First tokenizer type: \(type(of: firstTok))")
			if let tg = firstTok as? TokenGroup {
				print("TokenGroup data count: \(tg.data.count)")
				print("TokenGroup first 20 values: \(tg.data.prefix(20).map { Int($0) })")
			}
		}
		print("Parser tokenPrecTable: \(parser.tokenPrecTable)")

		let input = "xxx"
		let tree = parser.parse(input: input)
		print("=== EOF TEST ===")
		print("Input: \(input)")
		print("Tree length: \(tree.length)")
		print("Tree topNode: \(tree.topNode.name)")
		let cursor = tree.cursor()
		cursor.iterate(enter: { n in
			print("  ENTER \(n.name) from=\(n.from) to=\(n.to) type.id=\(n.type.id)")
			return true
		}, leave: { n in
			print("  LEAVE \(n.name) from=\(n.from) to=\(n.to)")
		})

		let tests = try fileTests("""

		# Matches EOF markers

		xxx

		==> A(X, X, Y)
		""", "test.txt")
		for t in tests {
			try t.run(parser)
		}
	}

	@Test func precedenceOrderCase() throws {
		let grammar = """
		@top T { (Tag | "<" | "<<" | "<<<")+ }

		@skip { space }

		@tokens {
		  space { " "+ }
		  Tag { "<" "<"* @asciiLetter+ }
		  @precedence { Tag, "<<" }
		  @precedence { Tag, "<" }
		  @precedence { Tag, "<<<" }
		  "<" "<<" "<<<"
		}
		"""
		let parser = try buildParser(grammar, options: BuildOptions(
			fileName: "test.txt",
			externalTokenizer: { _, _ in fatalError() },
			externalSpecializer: { _, _ in fatalError() },
			externalProp: { _ in NodeProp<String>(deserialize: { x in x }) }
		))

		let input = "<okay <<< << <"
		let tree = parser.parse(input: input)
		print("=== PRECEDENCE ORDER TEST ===")
		print("Input: \(input)")
		print("Tree length: \(tree.length)")
		print("Tree topNode: \(tree.topNode.name)")
		let cursor = tree.cursor()
		cursor.iterate(enter: { n in
			print("  ENTER \(n.name) from=\(n.from) to=\(n.to) type.id=\(n.type.id)")
			return true
		}, leave: { n in
			print("  LEAVE \(n.name) from=\(n.from) to=\(n.to)")
		})
	}

	@Test func autoDelimCase() throws {
		let grammar = """
		@top T { expr+ }

		expr {
		  ParenExpr { "(" Number ")" } |
		  DoubleExpr { "[[" Number "]]" } |
		  BracketExpr |
		  WeirdExpr |
		  DualExpr
		}

		BracketExpr {
		  BracketLeft Number BracketRight
		}

		WeirdExpr {
		  "((" Number "()"
		}

		DualExpr {
		  ("{" | "{{") Number ("}" | "}}")
		}

		@tokens {
		  Number { @digit+ }
		  BracketLeft { "[|" }
		  BracketRight { "|]" }
		  "[["[@name=DoubleLeft]
		  "]]"[@name=DoubleRight]
		  "(" ")" "{{" "}}" "{" "}" "((" "()"
		}

		@detectDelim
		"""
		let parser = try buildParser(grammar, options: BuildOptions(
			fileName: "test.txt",
			externalTokenizer: { _, _ in fatalError() },
			externalSpecializer: { _, _ in fatalError() },
			externalProp: { _ in NodeProp<String>(deserialize: { x in x }) }
		))

		let input = "(11)"
		let tree = parser.parse(input: input)
		print("=== AUTO DELIM TEST ===")
		print("Input: \(input)")
		print("Tree length: \(tree.length)")
		print("Tree topNode: \(tree.topNode.name)")
		let cursor = tree.cursor()
		cursor.iterate(enter: { n in
			print("  ENTER \(n.name) from=\(n.from) to=\(n.to) type.id=\(n.type.id)")
			return true
		}, leave: { n in
			print("  LEAVE \(n.name) from=\(n.from) to=\(n.to)")
		})

		let nodeTypes = parser.nodeSet.types
		for nt in nodeTypes {
			print("  TYPE id=\(nt.id) name=\(nt.name)")
		}
	}

	@Test func defineGroupCase() throws {
		let grammar = """
		@top T { expr* }

		expr[@isGroup=Expression] {
		  atom |
		  ParenExpr { "(" expr ")" }
		}

		atom { Id | Number }

		@tokens {
		  Id { "a"+ }
		  Number { "1"+ }
		  "(" ")"
		}
		"""
		let parser = try buildParser(grammar, options: BuildOptions(
			fileName: "test.txt",
			externalTokenizer: { _, _ in fatalError() },
			externalSpecializer: { _, _ in fatalError() },
			externalProp: { _ in NodeProp<String>(deserialize: { x in x }) }
		))

		let input = "a(1)"
		let tree = parser.parse(input: input)
		print("=== DEFINE GROUP TEST ===")
		print("Input: \(input)")
		print("Tree length: \(tree.length)")
		print("Tree topNode: \(tree.topNode.name)")
		let cursor = tree.cursor()
		cursor.iterate(enter: { n in
			print("  ENTER \(n.name) from=\(n.from) to=\(n.to) type.id=\(n.type.id)")
			return true
		}, leave: { n in
			print("  LEAVE \(n.name) from=\(n.from) to=\(n.to)")
		})
	}

	@Test func localTokensCase() throws {
		let grammar = """
		@top T { expr* }

		expr {
		 X { "x" } |
		 String { '"' (stringContent | Interpolation | Letter )* stringEnd }
		}

		Interpolation {
		  InterpolationStart expr InterpolationEnd
		}

		@local tokens {
		  stringEnd { '"' }
		  InterpolationStart { "{{" }
		  Y { "y" }
		  Z { "z" }
		  Letter { Y | Z }
		  @else stringContent
		}

		@tokens {
		  InterpolationEnd { "}}" }
		}
		"""
		let parser = try buildParser(grammar, options: BuildOptions(
			fileName: "test.txt",
			externalTokenizer: { _, _ in fatalError() },
			externalSpecializer: { _, _ in fatalError() },
			externalProp: { _ in NodeProp<String>(deserialize: { x in x }) }
		))

		let input = "\"foo{{x}}bar{{x}}yz\""
		let tree = parser.parse(input: input)
		print("=== LOCAL TOKENS TEST ===")
		print("Input: \(input)")
		print("Tree length: \(tree.length)")
		print("Tree topNode: \(tree.topNode.name)")
		let cursor = tree.cursor()
		cursor.iterate(enter: { n in
			print("  ENTER \(n.name) from=\(n.from) to=\(n.to) type.id=\(n.type.id)")
			return true
		}, leave: { n in
			print("  LEAVE \(n.name) from=\(n.from) to=\(n.to)")
		})
	}
}
