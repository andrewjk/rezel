import Foundation
@testable import Rezel
import Testing

private let literalsTests = """

# True

true

==>

JsonText(True)

# False

false

==>

JsonText(False)

# Null

null

==>

JsonText(Null)
"""

private let stringsTests = #"""

# Empty String

""

==>

JsonText(String)

# Non-empty String

"This is a boring old string"

==>

JsonText(String)

# All The Valid One-Character Escapes

"\"\\\/\b\f\n\rt\t"

==>

JsonText(String)

# Unicode Escape

"\u005C"

==>

JsonText(String)

"""#

private let numbersTests = """

# Simple Integer

42

==>

JsonText(Number)

# Zero By Itself Is Ok

0

==>

JsonText(Number)

# Leading Zeros Aren't Ok

[0123]

==>

JsonText(Array(Number, ⚠(Number)))

# Optional Minus Sign

-53

==>

JsonText(Number)

# Decimal Digits

123.4

==>

JsonText(Number)

# Must Have Digits After Decimal

123.

==>

JsonText(Number, ⚠)

# Exponent: Lowercase e

1e5

==>

JsonText(Number)

# Exponent: Uppercase E

1E5

==>

JsonText(Number)

# Exponent: Optional Plus Sign

1e+5

==>

JsonText(Number)

# Exponent: Optional Minus Sign

1E-5

==>

JsonText(Number)

# Exponent Without Digit Is Not Ok

42e

==>

JsonText(Number, ⚠)
"""

private let objectsTests = """

# Empty Object

{ }

==>

JsonText(Object)

# One Property

{
  "foo": 123
}

==>

JsonText(Object(Property(PropertyName,Number)))

# Multiple Properties

{
  "foo": 123,
  "bar": "I'm a bar!",
  "obj": {},
  "arr": [1, 2, 3]
}

==>

JsonText(Object(
  Property(PropertyName,Number),
  Property(PropertyName,String),
  Property(PropertyName,Object),
  Property(PropertyName,Array(Number,Number,Number))))
"""

private let arraysTests = """

# Empty Array

[ ]

==>

JsonText(Array)

# Array With One Value

["One is the loneliest number"]

==>

JsonText(Array(String))

# Array With Multiple Values

[
  "The more the merrier",
  1e5,
  true,
  { },
  ["I'm", "nested"]
]

==>

JsonText(Array(
  String,
  Number,
  True,
  Object,
  Array(String,String)))
"""

@Suite(.serialized)
struct JsonGrammarTests {
	@Test func literals() throws {
		let tests = try fileTests(literalsTests, "literals.txt")
		for t in tests {
			try t.run(jsonParser)
		}
	}

	@Test func strings() throws {
		let tests = try fileTests(stringsTests, "strings.txt")
		for t in tests {
			try t.run(jsonParser)
		}
	}

	@Test func numbers() throws {
		let tests = try fileTests(numbersTests, "numbers.txt")
		for t in tests {
			try t.run(jsonParser)
		}
	}

	@Test func objects() throws {
		let tests = try fileTests(objectsTests, "objects.txt")
		for t in tests {
			try t.run(jsonParser)
		}
	}

	@Test func arrays() throws {
		let tests = try fileTests(arraysTests, "arrays.txt")
		for t in tests {
			try t.run(jsonParser)
		}
	}
}
