import Testing
import Foundation
@testable import Rezel

@Suite("FileTests")
struct FileTestsSuite {
    @Test("handle parser error")
    func handleParserError() {
        let content = """

# Working Spec

b

==> B

# Broken Spec

bbbb bbbb bbbb bbbb
bbbb bbbb bbbb bbbb
bbbb bbbb bbbb bbbb
bbbb bbbb bbbb bbbb aaaa
bbbb

"""
        let file = "test-error.txt"

        let expectedContext = """
  | # Broken Spec
  | 
  | bbbb bbbb bbbb bbbb
  | bbbb bbbb bbbb bbbb
  | bbbb bbbb bbbb bbbb
  | bbbb bbbb bbbb bbbb aaaa
"""
        let expectedError = "Unexpected file format in \(file) around\n\n\(expectedContext)"

        do {
            _ = try fileTests(file: content, fileName: file)
            Issue.record("Expected error to be thrown")
        } catch let error as FileTestError {
            #expect(error.description == expectedError)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
