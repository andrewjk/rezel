public protocol InputProtocol {
    var length: Int { get }
    func chunk(from: Int) -> String
    var lineChunks: Bool { get }
    func read(from: Int, to: Int) -> String
}

class StringInput: InputProtocol {
    let string: String

    init(_ string: String) {
        self.string = string
    }

    var length: Int { string.utf16.count }

    func chunk(from: Int) -> String {
        let idx = string.utf16.index(string.startIndex, offsetBy: from)
        return String(string[idx...])
    }

    var lineChunks: Bool { false }

    func read(from: Int, to: Int) -> String {
        let startIdx = string.utf16.index(string.startIndex, offsetBy: from)
        let endIdx = string.utf16.index(string.startIndex, offsetBy: to)
        return String(string[startIdx..<endIdx])
    }
}

public protocol PartialParse {
    mutating func advance() -> Tree?
    var parsedPos: Int { get }
    mutating func stopAt(_ pos: Int)
    var stoppedAt: Int? { get }
}

public typealias ParseWrapper = (inout AnyPartialParse, InputProtocol, [TreeFragment], [Range]) -> AnyPartialParse

public class Parser {
    public init() {}

    public func createParse(input: InputProtocol, fragments: [TreeFragment], ranges: [Range]) -> any PartialParse {
        fatalError("Must be overridden")
    }

    public func startParse(input: Any, fragments: [TreeFragment] = [], ranges: [Range]? = nil) -> any PartialParse {
        let inputObj: InputProtocol
        if let str = input as? String {
            inputObj = StringInput(str)
        } else if let inp = input as? InputProtocol {
            inputObj = inp
        } else {
            fatalError("Input must be String or InputProtocol")
        }
        let resolvedRanges: [Range]
        if let r = ranges {
            if r.isEmpty {
                resolvedRanges = [Range(from: 0, to: 0)]
            } else {
                resolvedRanges = r
            }
        } else {
            resolvedRanges = [Range(from: 0, to: inputObj.length)]
        }
        return createParse(input: inputObj, fragments: fragments, ranges: resolvedRanges)
    }

    public func parse(input: Any, fragments: [TreeFragment] = [], ranges: [Range]? = nil) -> Tree {
        var parse = startParse(input: input, fragments: fragments, ranges: ranges)
        while true {
            if let done = parse.advance() { return done }
        }
    }
}

public struct AnyPartialParse: PartialParse {
    private var _base: any PartialParse

    public init(_ base: any PartialParse) {
        self._base = base
    }

    public mutating func advance() -> Tree? { _base.advance() }
    public var parsedPos: Int { _base.parsedPos }
    public mutating func stopAt(_ pos: Int) { _base.stopAt(pos) }
    public var stoppedAt: Int? { _base.stoppedAt }
}
