public struct CommonRange: Equatable, CustomStringConvertible {
	public let from: Int
	public let to: Int

	public init(from: Int, to: Int) {
		self.from = from
		self.to = to
	}

	public var description: String {
		"(\(from)..\(to))"
	}
}
