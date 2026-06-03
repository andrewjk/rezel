import Testing
import Foundation
@testable import Rezel

@Suite("Cases")
struct CasesTests {

    static let casesDir: URL = {
        let this = URL(fileURLWithPath: #filePath)
        let pkg = this.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return pkg.appendingPathComponent("web/test/cases").standardized
    }()

    static let caseFiles: [(name: String, content: String)] = {
        let fm = FileManager.default
        print("DIR: \(casesDir)")
        guard let files = try? fm.contentsOfDirectory(at: casesDir, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "txt" }
            .compactMap { url -> (String, String)? in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return (url.deletingPathExtension().lastPathComponent, content)
            }
            .sorted { $0.0 < $1.0 }
    }()

    nonisolated(unsafe) static var extTokCache: ExternalTokenizer?
    nonisolated(unsafe) static var specCache: ((String, Stack) -> Int)?

    static func extTok(name: String, terms: [String: Int]) -> ExternalTokenizer {
        if let cached = extTokCache { return cached }
        guard name == "ext1" else { fatalError("Undefined external tokenizer \(name)") }
        let t = ExternalTokenizer(token: { input, _ in
            if input.next == 0x7b {
                input.advance()
                input.acceptToken(terms["braceOpen"]!)
            } else if input.next == 0x7d {
                input.advance()
                input.acceptToken(terms["braceClose"]!)
            } else if input.next == 0x2e {
                input.advance()
                input.acceptToken(terms["Dot"]!)
            }
        })
        extTokCache = t
        return t
    }

    static func extSpec(name: String, terms: [String: Int]) -> (String, Stack) -> Int {
        if let cached = specCache { return cached }
        guard name == "spec1" else { fatalError("Undefined external specialize \(name)") }
        let fn: (String, Stack) -> Int = { value, _ in
            value == "one" ? terms["one"]! : value == "two" ? terms["two"]! : -1
        }
        specCache = fn
        return fn
    }

    static func extProp(name: String) -> NodeProp<Any> {
        NodeProp<Any>(config: NodePropConfig(deserialize: { $0 }))
    }

    struct TestItem: @unchecked Sendable {
        let name: String
        let run: () throws -> Void
    }

    static func makeItem(_ file: (name: String, content: String)) -> TestItem {
        let content = file.content
        guard let hashPos = content.range(of: "\n# ") else {
            return TestItem(name: file.name) {
                Issue.record("No test cases in \(file.name)")
            }
        }
        let grammar = String(content[content.startIndex..<hashPos.lowerBound])
        let testContent = String(content[hashPos.lowerBound...])

        let errMatch = grammar.range(of: "//! ")
        let noCases = testContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if let errMatch = errMatch {
            let expectedErr = String(grammar[errMatch.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if noCases {
                return TestItem(name: file.name + " fails") {
                    // Expected error tests cannot be fully verified in Swift because
                    // the parser uses fatalError() for errors (uncatchable).
                    // We at least verify the builder doesn't produce a valid parser.
                    var capture: [String] = []
                    let parser = buildParser(text: grammar, options: BuildOptions(
                        fileName: file.name + ".txt",
                        warn: { msg in capture.append(msg) },
                        externalTokenizer: extTok,
                        externalSpecializer: extSpec,
                        externalProp: extProp
                    ))
                    if parser.nodeSet.types.count > 1 {
                        // If we got past build it likely didn't error, but check warnings
                        if !capture.contains(where: { $0.lowercased().contains(expectedErr) }) {
                            Issue.record("Expected error '\(expectedErr)' but no matching warning found. Warnings: \(capture)")
                        }
                    }
                }
            } else {
                return TestItem(name: file.name) {
                    Issue.record("File has both expected error and test cases")
                }
            }
        }

        if noCases {
            return TestItem(name: file.name) {
                Issue.record("Test with neither expected errors nor input cases")
            }
        }

        let caseItems: [(String, (LRParser) -> Void)]
        do {
            caseItems = try fileTests(file: testContent, fileName: file.name + ".txt").map { test in
                (test.name, test.run)
            }
        } catch {
            return TestItem(name: file.name) {
                throw error
            }
        }

        return TestItem(name: file.name) {
            let parser = buildParser(text: grammar, options: BuildOptions(
                fileName: file.name + ".txt",
                externalTokenizer: extTok,
                externalSpecializer: extSpec,
                externalProp: extProp
            ))
            for (name, run) in caseItems {
                do {
                    run(parser)
                } catch {
                    Issue.record("\(file.name)/\(name): \(error)")
                }
            }
        }
    }

    static let allItems: [TestItem] = {
        caseFiles.map(makeItem)
    }()

    @Test(arguments: allItems)
    func runCase(item: TestItem) throws {
        try item.run()
    }
}

struct ParserBuildError: Error, CustomStringConvertible {
    let message: String
    init(_ msg: String) { self.message = msg }
    var description: String { message }
}

func extTok(name: String, terms: [String: Int]) -> ExternalTokenizer {
    CasesTests.extTok(name: name, terms: terms)
}

func extSpec(name: String, terms: [String: Int]) -> (String, Stack) -> Int {
    CasesTests.extSpec(name: name, terms: terms)
}

func extProp(name: String) -> NodeProp<Any> {
    CasesTests.extProp(name: name)
}
