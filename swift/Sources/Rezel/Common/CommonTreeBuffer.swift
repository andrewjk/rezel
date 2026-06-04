import Foundation

public let defaultBufferLength = 1024

public final class TreeBuffer: CustomStringConvertible {
    public let buffer: [UInt16]
    public let length: Int
    public let set: NodeSet

    public init(buffer: [UInt16], length: Int, set: NodeSet) {
        self.buffer = buffer
        self.length = length
        self.set = set
    }

    public var type: NodeType {
        return NodeType.none
    }

    public var description: String {
        var result: [String] = []
        var index = 0
        while index < buffer.count {
            result.append(childString(index))
            index = Int(buffer[index + 3])
        }
        return result.joined(separator: ",")
    }

    public func childString(_ index: Int) -> String {
        let id = Int(buffer[index])
        let endIndex = Int(buffer[index + 3])
        let type = set.types[id]
        var result = type.name
        let nonWord = result.unicodeScalars.contains { !CharacterSet.alphanumerics.contains($0) }
        if nonWord && !type.isError {
            result = "\"\(result)\""
        }
        var idx = index + 4
        if endIndex == idx { return result }
        var children: [String] = []
        while idx < endIndex {
            children.append(childString(idx))
            idx = Int(buffer[idx + 3])
        }
        return result + "(" + children.joined(separator: ",") + ")"
    }

    public func findChild(startIndex: Int, endIndex: Int, dir: Int, pos: Int, side: Side) -> Int {
        var pick = -1
        var i = startIndex
        while i != endIndex {
            if checkSide(side, pos: pos, from: Int(buffer[i + 1]), to: Int(buffer[i + 2])) {
                pick = i
                if dir > 0 { break }
            }
            i = Int(buffer[i + 3])
        }
        return pick
    }

    public func slice(startI: Int, endI: Int, from: Int) -> TreeBuffer {
        let b = buffer
        var copy = [UInt16](repeating: 0, count: endI - startI)
        var len = 0
        var i = startI
        var j = 0
        while i < endI {
            copy[j] = b[i]; j += 1; i += 1
            copy[j] = UInt16(Int(b[i]) - from); j += 1; i += 1
            let to = Int(b[i]) - from
            copy[j] = UInt16(to); j += 1; i += 1
            copy[j] = UInt16(Int(b[i]) - startI); j += 1; i += 1
            len = max(len, to)
        }
        return TreeBuffer(buffer: copy, length: len, set: set)
    }
}
