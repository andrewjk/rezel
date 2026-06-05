import Foundation

private let jsonGrammarText = #"""
@top JsonText { value }

value { True | False | Null | Number | String | Object | Array }

String[isolate] { string }
Object { "{" list<Property>? "}" }
Array  { "[" list<value>? "]" }

Property { PropertyName ":" value }
PropertyName[isolate] { string }


@tokens {
  True  { "true" }
  False { "false" }
  Null  { "null" }

  Number { '-'? int frac? exp?  }
  int  { '0' | $[1-9] @digit* }
  frac { '.' @digit+ }
  exp  { $[eE] $[+\-]? @digit+ }

  string { '"' char* '"' }
  char { $[\u{20}\u{21}\u{23}-\u{5b}\u{5d}-\u{10ffff}] | "\\" esc }
  esc  { $["\\\/bfnrt] | "u" hex hex hex hex }
  hex  { $[0-9a-fA-F] }

  whitespace { $[ \n\r\t] }

  "{" "}" "[" "]" "," ":"
}

@skip { whitespace }
list<item> { item ("," item)* }

@external propSource jsonHighlighting from "./highlight"

@detectDelim
"""#

nonisolated(unsafe) private let jsonHighlighting = styleTags([
    "String": hlString,
    "Number": hlNumber,
    "True False": (hlTags["bool"] as! Tag),
    "PropertyName": hlPropertyName,
    "Null": (hlTags["null"] as! Tag),
    ", :": (hlTags["separator"] as! Tag),
    "[ ]": (hlTags["squareBracket"] as! Tag),
    "{ }": (hlTags["brace"] as! Tag),
])

nonisolated(unsafe) public let jsonParser: LRParser = {
    do {
        return try buildParser(jsonGrammarText, options: BuildOptions(
            externalPropSource: { _ in jsonHighlighting }
        ))
    } catch {
        fatalError("Failed to build JSON parser: \(error)")
    }
}()
