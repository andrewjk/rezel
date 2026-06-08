public class CachedToken {
	public var start: Int = -1
	public var value: Int = -1
	public var end: Int = -1
	public var extended: Int = -1
	public var lookAhead: Int = 0
	public var mask: Int = 0
	public var context: Int = 0

	public init() {}
}

private nonisolated(unsafe) let nullToken = CachedToken()

public class InputStream {
	public var chunk: String = "" {
		didSet { chunkUtf16 = Array(chunk.utf16) }
	}

	public var chunkOff: Int = 0
	public var chunkPos: Int
	private var chunk2: String = "" {
		didSet { chunk2Utf16 = Array(chunk2.utf16) }
	}

	private var chunk2Pos: Int = 0
	private var chunkUtf16: [UInt16] = []
	private var chunk2Utf16: [UInt16] = []

	public var next: Int = -1
	public var token: CachedToken = nullToken
	public var pos: Int
	public var end: Int

	private var rangeIndex: Int = 0
	private var range: CommonRange

	public let input: InputProtocol
	public let ranges: [CommonRange]

	public init(input: InputProtocol, ranges: [CommonRange]) {
		self.input = input
		self.ranges = ranges
		pos = ranges[0].from
		chunkPos = pos
		range = ranges[0]
		end = ranges[ranges.count - 1].to
		_ = readNext()
	}

	public func resolveOffset(_ offset: Int, assoc: Int) -> Int? {
		var range = self.range
		var index = rangeIndex
		var pos = self.pos + offset
		while pos < range.from {
			if index == 0 { return nil }
			index -= 1
			let next = ranges[index]
			pos -= range.from - next.to
			range = next
		}
		while assoc < 0 ? pos > range.to : pos >= range.to {
			if index == ranges.count - 1 { return nil }
			index += 1
			let next = ranges[index]
			pos += next.from - range.to
			range = next
		}
		return pos
	}

	public func clipPos(_ pos: Int) -> Int {
		if pos >= range.from && pos < range.to { return pos }
		for r in ranges {
			if r.to > pos { return max(pos, r.from) }
		}
		return end
	}

	public func peek(_ offset: Int) -> Int {
		let idx = chunkOff + offset
		var pos: Int
		var result: Int

		if idx >= 0 && idx < chunkUtf16.count {
			pos = self.pos + offset
			result = Int(chunkUtf16[idx])
		} else {
			guard let resolved = resolveOffset(offset, assoc: 1) else { return -1 }
			pos = resolved
			if pos >= chunk2Pos && pos < chunk2Pos + chunk2Utf16.count {
				result = Int(chunk2Utf16[pos - chunk2Pos])
			} else {
				var i = rangeIndex
				var r = range
				while r.to <= pos {
					i += 1
					r = ranges[i]
				}
				chunk2 = input.chunk(from: pos)
				chunk2Pos = pos
				if pos + chunk2Utf16.count > r.to {
					let endIdx = chunk2.utf16.index(chunk2.startIndex, offsetBy: r.to - pos)
					chunk2 = String(chunk2[chunk2.startIndex ..< endIdx])
				}
				result = chunk2Utf16.count > 0 ? Int(chunk2Utf16[0]) : -1
			}
		}
		if pos >= token.lookAhead { token.lookAhead = pos + 1 }
		return result
	}

	public func acceptToken(_ token: Int, endOffset: Int = 0) {
		let end: Int
		if endOffset != 0 {
			guard let resolved = resolveOffset(endOffset, assoc: -1) else {
				fatalError("Token end out of bounds")
			}
			end = resolved
		} else {
			end = pos
		}
		if end < self.token.start { fatalError("Token end out of bounds") }
		self.token.value = token
		self.token.end = end
	}

	public func acceptTokenTo(_ token: Int, endPos: Int) {
		self.token.value = token
		self.token.end = endPos
	}

	private func getChunk() {
		if pos >= chunk2Pos, pos < chunk2Pos + chunk2Utf16.count {
			let oldChunk = chunk
			let oldChunkPos = chunkPos
			chunk = chunk2
			chunkPos = chunk2Pos
			chunk2 = oldChunk
			chunk2Pos = oldChunkPos
			chunkOff = pos - chunkPos
		} else {
			chunk2 = chunk
			chunk2Pos = chunkPos
			var nextChunk = input.chunk(from: pos)
			let endPos = pos + nextChunk.utf16.count
			if endPos > range.to {
				let endIdx = nextChunk.utf16.index(nextChunk.startIndex, offsetBy: range.to - pos)
				nextChunk = String(nextChunk[nextChunk.startIndex ..< endIdx])
			}
			chunk = nextChunk
			chunkPos = pos
			chunkOff = 0
		}
	}

	private func readNext() -> Int {
		if chunkOff >= chunkUtf16.count {
			getChunk()
			if chunkOff >= chunkUtf16.count { next = -1; return next }
		}
		next = Int(chunkUtf16[chunkOff])
		return next
	}

	@discardableResult
	public func advance(_ n: Int = 1) -> Int {
		chunkOff += n
		var n = n
		while pos + n >= range.to {
			if rangeIndex == ranges.count - 1 { return setDone() }
			n -= range.to - pos
			rangeIndex += 1
			range = ranges[rangeIndex]
			pos = range.from
		}
		pos += n
		if pos >= token.lookAhead { token.lookAhead = pos + 1 }
		return readNext()
	}

	private func setDone() -> Int {
		pos = end
		chunkPos = end
		range = ranges[ranges.count - 1]
		rangeIndex = ranges.count - 1
		chunk = ""
		next = -1
		return next
	}

	@discardableResult
	public func reset(_ pos: Int, token: CachedToken? = nil) -> InputStream {
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
				_ = setDone()
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
			let chunkChars = chunkUtf16
			if pos >= chunkPos && pos < chunkPos + chunkChars.count {
				chunkOff = pos - chunkPos
			} else {
				chunk = ""
				chunkOff = 0
			}
			_ = readNext()
		}
		return self
	}

	public func read(from: Int, to: Int) -> String {
		if from >= chunkPos && to <= chunkPos + chunkUtf16.count {
			let startIdx = chunk.utf16.index(chunk.startIndex, offsetBy: from - chunkPos)
			let endIdx = chunk.utf16.index(chunk.startIndex, offsetBy: to - chunkPos)
			return String(chunk[startIdx ..< endIdx])
		}
		if from >= chunk2Pos && to <= chunk2Pos + chunk2Utf16.count {
			let startIdx = chunk2.utf16.index(chunk2.startIndex, offsetBy: from - chunk2Pos)
			let endIdx = chunk2.utf16.index(chunk2.startIndex, offsetBy: to - chunk2Pos)
			return String(chunk2[startIdx ..< endIdx])
		}
		if from >= range.from && to <= range.to {
			return input.read(from: from, to: to)
		}
		var result = ""
		for r in ranges {
			if r.from >= to { break }
			if r.to > from {
				result += input.read(from: max(r.from, from), to: min(r.to, to))
			}
		}
		return result
	}
}

public protocol TokenizerProtocol {
	func token(_ input: InputStream, stack: Stack)
	var contextual: Bool { get }
	var fallback: Bool { get }
	var extend: Bool { get }
}

public class TokenGroup: TokenizerProtocol {
	public var contextual: Bool = false
	public var fallback: Bool = false
	public var extend: Bool = false

	public let data: [UInt16]
	public let id: Int

	public init(data: [UInt16], id: Int) {
		self.data = data
		self.id = id
	}

	public func token(_ input: InputStream, stack: Stack) {
		let parser = stack.p.parser
		readToken(data, input: input, stack: stack, group: id, precTable: parser.data, precOffset: parser.tokenPrecTable)
	}
}

public class LocalTokenGroup: TokenizerProtocol {
	public var contextual: Bool = false
	public var fallback: Bool = false
	public var extend: Bool = false
	public let data: [UInt16]
	public let precTable: Int
	public let elseToken: Int?

	public init(data: Any, precTable: Int, elseToken: Int? = nil) {
		self.precTable = precTable
		self.elseToken = elseToken
		if let arr = data as? [UInt16] {
			self.data = arr
		} else if let str = data as? String {
			self.data = decodeArray(str)
		} else {
			fatalError("LocalTokenGroup data must be [UInt16] or String")
		}
	}

	public func token(_ input: InputStream, stack: Stack) {
		let start = input.pos
		var skipped = 0
		while true {
			let atEof = input.next < 0
			let nextPos = input.resolveOffset(1, assoc: 1)
			readToken(data, input: input, stack: stack, group: 0, precTable: data, precOffset: precTable)
			if input.token.value > -1 { break }
			if elseToken == nil { return }
			if !atEof { skipped += 1 }
			if nextPos == nil { break }
			input.reset(nextPos!, token: input.token)
		}
		if skipped > 0 {
			input.reset(start, token: input.token)
			input.acceptToken(elseToken!, endOffset: skipped)
		}
	}
}

public class ExternalTokenizer: TokenizerProtocol {
	public var contextual: Bool
	public var fallback: Bool
	public var extend: Bool
	public let tokenFn: (InputStream, Stack) -> Void

	public init(
		_ token: @escaping (InputStream, Stack) -> Void,
		contextual: Bool = false,
		fallback: Bool = false,
		extend: Bool = false
	) {
		tokenFn = token
		self.contextual = contextual
		self.fallback = fallback
		self.extend = extend
	}

	public func token(_ input: InputStream, stack: Stack) {
		tokenFn(input, stack)
	}
}

func readToken(
	_ data: [UInt16],
	input: InputStream,
	stack: Stack,
	group: Int,
	precTable: [UInt16],
	precOffset: Int
) {
	var state = 0
	let groupMask = 1 << group
	let dialect = stack.p.parser.dialect

	scan: while true {
		if (groupMask & Int(data[state])) == 0 { break }
		let accEnd = Int(data[state + 1])

		var i = state + 3
		while i < accEnd {
			if (Int(data[i + 1]) & groupMask) > 0 {
				let term = Int(data[i])
				if dialect.allows(term: term),
				   input.token.value == -1 ||
				   input.token.value == term ||
				   overrides(term, prev: input.token.value, tableData: precTable, tableOffset: precOffset)
				{
					input.acceptToken(term)
					break
				}
			}
			i += 2
		}

		let next = input.next
		var low = 0
		var high = Int(data[state + 2])

		if input.next < 0, high > low {
			let eofIdx = accEnd + high * 3 - 3
			if Int(data[eofIdx]) == Seq.End {
				state = Int(data[eofIdx + 2])
				continue scan
			}
		}

		while low < high {
			let mid = (low + high) >> 1
			let index = accEnd + mid + (mid << 1)
			let from = Int(data[index])
			let to = Int(data[index + 1]) == 0 ? 0x10000 : Int(data[index + 1])
			if next < from { high = mid }
			else if next >= to { low = mid + 1 }
			else {
				state = Int(data[index + 2])
				input.advance()
				continue scan
			}
		}
		break
	}
}

func findOffset(_ data: [UInt16], start: Int, term: Int) -> Int {
	var i = start
	while i < data.count {
		let next = Int(data[i])
		if next == Seq.End { return -1 }
		if next == term { return i - start }
		i += 1
	}
	return -1
}

func overrides(_ token: Int, prev: Int, tableData: [UInt16], tableOffset: Int) -> Bool {
	let iPrev = findOffset(tableData, start: tableOffset, term: prev)
	if iPrev < 0 { return true }
	return findOffset(tableData, start: tableOffset, term: token) < iPrev
}
