//
//  Token.swift
//  Rezel
//
//  Created on 2025-06-11.
//

import Foundation

public class CachedToken {
    var start = -1
    var value = -1
    var end = -1
    var `extended` = -1
    var lookAhead = 0
    var mask = 0
    var context = 0
}

fileprivate nonisolated(unsafe) let nullToken = CachedToken()

/// [Tokenizers](#lr.ExternalTokenizer) interact with the input
/// through this interface. It presents the input as a stream of
/// characters, tracking lookahead and hiding the complexity of
/// [ranges](#common.Parser.parse^ranges) from tokenizer code.
public class InputStream {
    /// @internal
    var chunk = ""
    /// @internal
    var chunkOff = 0
    /// @internal
    var chunkPos = Int(0)
    
    // Backup chunk
    private var chunk2 = ""
    private var chunk2Pos = Int(0)
    
    /// The character code of the next code unit in the input, or -1
    /// when the stream is at the end of the input.
    var next: Int = -1
    
    /// @internal
    var token: CachedToken = nullToken
    
    /// The current position of the stream. Note that, due to parses
    /// being able to cover non-contiguous
    /// [ranges](#common.Parser.startParse), advancing the stream does
    /// not always mean its position moves a single unit.
    var pos: Int = Int(0)
    
    /// @internal
    let end: Int
    
    private var rangeIndex = 0
    private var range: Range
    
    let input: any Input
    let ranges: [Range]
    
    /// @internal
    init(input: any Input, ranges: [Range]) {
        self.input = input
        self.ranges = ranges
        self.pos = ranges[0].from
        self.chunkPos = ranges[0].from
        self.range = ranges[0]
        self.end = ranges[ranges.count - 1].to
        readNext()
    }
    
    /// @internal
    func resolveOffset(_ offset: Int, assoc: Int) -> Int? {
        var range = self.range
        var index = self.rangeIndex
        var pos = self.pos + offset
        
        while pos < range.from {
            if index == 0 {
                return nil
            }
            let next = ranges[index - 1]
            pos -= range.from - next.to
            range = next
            index -= 1
        }
        
        while (assoc < 0 ? pos > range.to : pos >= range.to) {
            if index == ranges.count - 1 {
                return nil
            }
            let next = ranges[index + 1]
            pos += next.from - range.to
            range = next
            index += 1
        }
        
        return pos
    }
    
    /// @internal
    func clipPos(_ pos: Int) -> Int {
        if pos >= range.from && pos < range.to {
            return pos
        }
        for range in ranges {
            if range.to > pos {
                return max(pos, range.from)
            }
        }
        return end
    }
    
    /// Look at a code unit near the stream position. `.peek(0)` equals
    /// `.next`, `.peek(-1)` gives you the previous character, and so
    /// on.
    ///
    /// Note that looking around during tokenizing creates dependencies
    /// on potentially far-away content, which may reduce the
    /// effectiveness incremental parsing—when looking forward—or even
    /// cause invalid reparses when looking backward more than 25 code
    /// units, since the library does not track lookbehind.
    func peek(_ offset: Int) -> Int {
        let idx = chunkOff + offset
        var pos: Int
        var result: Int
        
        if idx >= 0 && idx < chunk.utf16.count {
            pos = self.pos + offset
            guard !chunk.isEmpty else { return -1 }
            let strIdx = chunk.index(chunk.startIndex, offsetBy: idx)
            guard strIdx < chunk.endIndex else { return -1 }
            result = Int(chunk.utf16[strIdx])
        } else {
            guard let resolved = resolveOffset(offset, assoc: 1) else {
                return -1
            }
            pos = resolved
            if pos >= chunk2Pos && pos < chunk2Pos + chunk2.utf16.count {
                guard !chunk2.isEmpty else { return -1 }
                let offset = pos - chunk2Pos
                if offset >= 0 && offset < chunk2.utf16.count {
                    let strIdx = chunk2.index(chunk2.startIndex, offsetBy: offset)
                    guard strIdx < chunk2.endIndex else { return -1 }
                    result = Int(chunk2.utf16[strIdx])
                } else {
                    return -1
                }
            } else {
                var i = rangeIndex
                var currentRange = range
                while currentRange.to <= pos && i + 1 < ranges.count {
                    currentRange = ranges[i + 1]
                    i += 1
                }
                
                chunk2 = input.chunk(from: pos)
                chunk2Pos = pos
                
                if pos + chunk2.utf16.count > currentRange.to {
                    let endOffset = currentRange.to - pos
                    let endIndex = chunk2.index(chunk2.startIndex, offsetBy: endOffset)
                    chunk2 = String(chunk2[..<endIndex])
                }
                guard !chunk2.isEmpty else { return -1 }
                result = Int(chunk2.utf16[chunk2.startIndex])
            }
        }
        
        if pos >= token.lookAhead {
            token.lookAhead = pos + 1
        }
        return result
    }
    
    /// Accept a token. By default, the end of the token is set to the
    /// current stream position, but you can pass an offset (relative to
    /// the stream position) to change that.
    func acceptToken(_ tokenValue: Int, endOffset: Int = 0) {
        guard let end = endOffset != 0 ? resolveOffset(endOffset, assoc: -1) : self.pos else {
            fatalError("Token end out of bounds")
        }
        if end < token.start {
            fatalError("Token end out of bounds")
        }
        self.token.value = tokenValue
        self.token.end = end
    }
    
    /// Accept a token ending at a specific given position.
    func acceptTokenTo(_ token: Int, endPos: Int) {
        self.token.value = token
        self.token.end = endPos
    }
    
    private func getChunk() {
        if pos >= chunk2Pos && pos < chunk2Pos + chunk2.utf16.count {
            let tempChunk = chunk
            let tempChunkPos = chunkPos
            chunk = chunk2
            chunkPos = chunk2Pos
            chunk2 = tempChunk
            chunk2Pos = tempChunkPos
            chunkOff = pos - chunkPos
        } else {
            chunk2 = chunk
            chunk2Pos = chunkPos
            let nextChunk = input.chunk(from: pos)
            let end = pos + nextChunk.utf16.count
            
            if end > range.to {
                let endOffset = range.to - pos
                let endIndex = nextChunk.index(nextChunk.startIndex, offsetBy: endOffset)
                chunk = String(nextChunk[..<endIndex])
            } else {
                chunk = nextChunk
            }
            
            chunkPos = pos
            chunkOff = 0
        }
    }
    
    @discardableResult
    private func readNext() -> Int {
        if chunkOff >= chunk.utf16.count {
            getChunk()
            if chunkOff >= chunk.utf16.count {
                next = -1
                return next
            }
        }
        next = Int(chunk.utf16[chunk.index(chunk.startIndex, offsetBy: chunkOff)])
        return next
    }
    
    /// Move the stream forward N (defaults to 1) code units. Returns
    /// the new value of `next`.
    @discardableResult
    func advance(_ n: Int = 1) -> Int {
        chunkOff += n
        var remaining = n
        
        while pos + remaining >= range.to {
            if rangeIndex == ranges.count - 1 {
                return setDone()
            }
            remaining -= range.to - pos
            rangeIndex += 1
            range = ranges[rangeIndex]
            pos = range.from
        }
        
        pos += remaining
        
        if pos >= token.lookAhead {
            token.lookAhead = pos + 1
        }
        
        return readNext()
    }
    
    @discardableResult
    private func setDone() -> Int {
        chunkPos = end
        pos = end
        range = ranges[ranges.count - 1]
        chunk = ""
        next = -1
        return next
    }
    
    /// @internal
    func reset(_ pos: Int, token: CachedToken? = nil) -> InputStream {
        if let token = token {
            self.token = token
            token.start = pos
            token.lookAhead = pos + 1
            token.value = -1
            token.extended = -1
        } else {
            self.token = nullToken
        }
        
        if self.pos != pos {
            self.pos = pos
            if pos == end {
                setDone()
                return self
            }
            
            while pos < range.from {
                rangeIndex -= 1
                range = ranges[rangeIndex]
            }
            while pos >= range.to {
                rangeIndex += 1
                range = ranges[rangeIndex]
            }
            
            if pos >= chunkPos && pos < chunkPos + chunk.count {
                chunkOff = pos - chunkPos
            } else {
                chunk = ""
                chunkOff = 0
            }
            
            readNext()
        }
        
        return self
    }
    
    /// @internal
    func read(_ from: Int, _ to: Int) -> String {
        if from >= chunkPos && to <= chunkPos + chunk.utf16.count {
            return String(chunk[chunk.index(chunk.startIndex, offsetBy: from - chunkPos)..<chunk.index(chunk.startIndex, offsetBy: to - chunkPos)])
        }
        
        if from >= chunk2Pos && to <= chunk2Pos + chunk2.utf16.count {
            return String(chunk2[chunk2.index(chunk2.startIndex, offsetBy: from - chunk2Pos)..<chunk2.index(chunk2.startIndex, offsetBy: to - chunk2Pos)])
        }
        
        if from >= range.from && to <= range.to {
            return input.read(from: from, to: to)
        }
        
        var result = ""
        for r in ranges {
            if r.from >= to {
                break
            }
            if r.to > from {
                result += input.read(from: max(from, r.from), to: min(to, r.to))
            }
        }
        
        return result
    }
}

/// Tokenizer interface
public protocol Tokenizer {
    /// @internal
    func token(_ input: InputStream, _ stack: Stack)
    /// @internal
    var contextual: Bool { get }
    /// @internal
    var fallback: Bool { get }
    /// @internal
    var `extend`: Bool { get }
}

/// @internal
public class TokenGroup: Tokenizer {
    public var contextual: Bool = false
    public var fallback: Bool = false
    public var `extend`: Bool = false
    
    let data: [Int]
    let id: Int
    
    init(data: [Int], id: Int) {
        self.data = data
        self.id = id
    }
    
    public func token(_ input: InputStream, _ stack: Stack) {
        readToken(data: data, input: input, stack: stack, group: id, precTable: stack.p.parser.data.map { Int($0) }, precOffset: stack.p.parser.tokenPrecTable)
    }
}

/// @hide
public class LocalTokenGroup: Tokenizer {
    public var contextual: Bool = false
    public var fallback: Bool = false
    public var `extend`: Bool = false
    
    let data: [Int]
    let precTable: Int
    let elseToken: Int?
    let localGroupID: Int
    
    init(data: ArrayOrString, precTable: Int, elseToken: Int? = nil, localGroupID: Int = 0) {
        self.precTable = precTable
        self.elseToken = elseToken
        self.data = decodeArray(data)
        self.localGroupID = localGroupID
    }
    
    public func token(_ input: InputStream, _ stack: Stack) {
        let start = input.pos
        var skipped = 0
        
        while true {
            let atEof = input.next < 0
            let nextPos = input.resolveOffset(1, assoc: 1)
            
            readToken(
                data: data,
                input: input,
                stack: stack,
                group: 0,
                precTable: stack.p.parser.data.map { Int($0) },
                precOffset: precTable
            )
            
            if input.token.value > -1 {
                break
            }
            
            if elseToken == nil {
                return
            }
            
            if !atEof {
                skipped += 1
            }
            
            guard let nextPos = nextPos else {
                break
            }
            _ = input.reset(nextPos, token: input.token)
        }
        
        if skipped > 0 {
            _ = input.reset(start, token: input.token)
            input.acceptToken(elseToken!, endOffset: skipped)
        }
    }
}

public struct ExternalOptions {
    /// When set to true, mark this tokenizer as depending on the
    /// current parse stack, which prevents its result from being cached
    /// between parser actions at the same positions.
    var contextual: Bool = false
    /// By defaults, when a tokenizer returns a token, that prevents
    /// tokenizers with lower precedence from even running. When
    /// `fallback` is true, the tokenizer is allowed to run when a
    /// previous tokenizer returned a token that didn't match any of the
    /// current state's actions.
    var fallback: Bool = false
    /// When set to true, tokenizing will not stop after this tokenizer
    /// has produced a token. (But it will still fail to reach this one
    /// if a higher-precedence tokenizer produced a token.)
    var `extend`: Bool = false
}

/// `@external tokens` declarations in the grammar should resolve to
/// an instance of this class.
public class ExternalTokenizer: Tokenizer {
    /// @internal
    public var contextual: Bool = false
    /// @internal
    public var fallback: Bool = false
    /// @internal
    public var `extend`: Bool = false
    
    let _tokenFunc: (InputStream, Stack) -> Void
    
    /// Create a tokenizer. The first argument is the function that,
    /// given an input stream, scans for the types of tokens it
    /// recognizes at the stream's position, and calls
    /// [`acceptToken`](#lr.InputStream.acceptToken) when it finds
    /// one.
    init(token: @escaping (InputStream, Stack) -> Void, options: ExternalOptions = ExternalOptions()) {
        self._tokenFunc = token
        self.contextual = options.contextual
        self.fallback = options.fallback
        self.`extend` = options.`extend`
    }
    
    public func token(_ input: InputStream, _ stack: Stack) {
        _tokenFunc(input, stack)
    }
}

// Tokenizer data is stored a big uint16 array containing, for each
// state:
//
//  - A group bitmask, indicating what token groups are reachable from
//    this state, so that paths that can only lead to tokens not in
//    any of the current groups can be cut off early.
//
//  - The position of the end of the state's sequence of accepting
//    tokens
//
//  - The number of outgoing edges for the state
//
//  - The accepting tokens, as (token id, group mask) pairs
//
//  - The outgoing edges, as (start character, end character, state
//    index) triples, with end character being exclusive
//
// This function interprets that data, running through a stream as
// long as new states with the a matching group mask can be reached,
// and updating `input.token` when it matches a token.
internal func readToken(
    data: [Int],
    input: InputStream,
    stack: Stack,
    group: Int,
    precTable: [Int],
    precOffset: Int
) {
    var state = 0
    let groupMask = 1 << group
    let dialect = stack.p.parser.dialect
    
    scan: while true {
        if (groupMask & data[state]) == 0 {
            break scan
        }
        
        let accEnd = data[state + 1]
        
        // Check whether this state can lead to a token in the current group
        // Accept tokens in this state, possibly overwriting
        // lower-precedence / shorter tokens
        for i in stride(from: state + 3, to: accEnd, by: 2) {
            if (data[i + 1] & groupMask) != 0 {
                let term = data[i]
                if dialect.allows(term: term) &&
                   (input.token.value == -1 ||
                    input.token.value == term ||
                    overrides(
                        token: term,
                        prev: input.token.value,
                        tableData: precTable,
                        tableOffset: precOffset
                    )) {
                    input.acceptToken(term)
                    break
                }
            }
        }
        
        let next = input.next
        var low = 0
        var high = data[state + 2]
        
        // Special case for EOF
        if input.next < 0 && high > low && data[accEnd + high * 3 - 3] == Seq.end {
            state = data[accEnd + high * 3 - 1]
            continue scan
        }
        
        // Do a binary search on the state's edges
        while low < high {
            let mid = (low + high) >> 1
            let index = accEnd + mid + (mid << 1)
            let from = data[index]
            let to = data[index + 1] != 0 ? data[index + 1] : 0x10000
            
            if next < from {
                high = mid
            } else if next >= to {
                low = mid + 1
            } else {
                state = data[index + 2]
                input.advance()
                continue scan
            }
        }
        
        break scan
    }
}

internal func findOffset(_ data: [Int], start: Int, term: Int) -> Int {
    for i in start..<data.count {
        if data[i] == Seq.end {
            return -1
        }
        if data[i] == term {
            return i - start
        }
    }
    return -1
}

internal func overrides(
    token: Int,
    prev: Int,
    tableData: [Int],
    tableOffset: Int
) -> Bool {
    let iPrev = findOffset(tableData, start: tableOffset, term: prev)
    if iPrev < 0 {
        return true
    }
    let iToken = findOffset(tableData, start: tableOffset, term: token)
    return iToken < iPrev
}
