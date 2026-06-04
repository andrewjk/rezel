import Testing
@testable import Rezel

@Suite("fileTests")
struct FileTestsTests {
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
        let expectedError = "Unexpected file format in test-error.txt around\n\n  | # Broken Spec\n  | \n  | bbbb bbbb bbbb bbbb\n  | bbbb bbbb bbbb bbbb\n  | bbbb bbbb bbbb bbbb\n  | bbbb bbbb bbbb bbbb aaaa"

        let file = "test-error.txt"

        do {
            let _ = try fileTests(content, file)
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error.localizedDescription == expectedError || "\(error)" == expectedError)
        }
    }
}
