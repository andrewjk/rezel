import Testing
import Foundation
@testable import Rezel

private let caseDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("web")
    .appendingPathComponent("test")
    .appendingPathComponent("cases")

private func externalTokenizer(name: String, terms: [String: Int]) -> TokenizerProtocol {
    if name == "ext1" {
        return ExternalTokenizer({ input, _ in
            if input.next == Int(Character("{").asciiValue!) {
                input.advance()
                input.acceptToken(terms["braceOpen"]!)
            } else if input.next == Int(Character("}").asciiValue!) {
                input.advance()
                input.acceptToken(terms["braceClose"]!)
            } else if input.next == Int(Character(".").asciiValue!) {
                input.advance()
                input.acceptToken(terms["Dot"]!)
            }
        })
    }
    fatalError("Undefined external tokenizer \(name)")
}

private func externalSpecializer(name: String, terms: [String: Int]) -> (String, Stack) -> Int {
    if name == "spec1" {
        return { value, _ in
            if value == "one" { return terms["one"]! }
            if value == "two" { return terms["two"]! }
            return -1
        }
    }
    fatalError("Undefined external specialize \(name)")
}

private func externalPropFn(_ name: String) -> NodePropBase {
    return NodeProp<String>(deserialize: { x in x })
}

private struct CaseFile {
    let name: String
    let grammar: String
    let testContent: String
    let expectedError: String?

    init?(fileName: String, content: String) {
        let name = (fileName as NSString).deletingPathExtension
        self.name = name

        if let range = content.range(of: "\n# ") {
            grammar = String(content[content.startIndex..<range.lowerBound])
            testContent = String(content[range.lowerBound...])
        } else {
            grammar = content
            testContent = ""
        }

        if let errRange = grammar.range(of: "//! ", options: .backwards) {
            expectedError = String(grammar[errRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            expectedError = nil
        }
    }
}

@Suite("Cases", .serialized)
struct CasesTests {
    private static let skipSet: Set<String> = []

    @Test func cases() throws {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: caseDir, includingPropertiesForKeys: nil)
        var caseFiles: [CaseFile] = []
        for fileURL in files {
            guard fileURL.pathExtension == "txt" else { continue }
            let content = try String(contentsOf: fileURL, encoding: .utf8)

            guard let cf = CaseFile(fileName: fileURL.lastPathComponent, content: content) else { continue }
            caseFiles.append(cf)
        }

        caseFiles.sort { $0.name < $1.name }

        for cf in caseFiles {
            let noCases = cf.testContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if noCases { continue }
            if cf.expectedError != nil { continue }
            if Self.skipSet.contains(cf.name) { continue }

            let fileURL = caseDir.appendingPathComponent(cf.name + ".txt")
            let parser = try buildParser(cf.grammar, options: BuildOptions(
                fileName: fileURL.path,
                externalTokenizer: externalTokenizer,
                externalSpecializer: externalSpecializer,
                externalProp: externalPropFn
            ))
            let tests = try fileTests(cf.testContent, cf.name + ".txt")
            for t in tests {
                do {
                    try t.run(parser)
                } catch {
                    Issue.record("\(cf.name)/\(t.name): \(error)")
                }
            }
        }
    }
}
