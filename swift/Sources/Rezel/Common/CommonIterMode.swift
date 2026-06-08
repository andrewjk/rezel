public struct IterMode: OptionSet, Sendable {
	public let rawValue: Int
	public init(rawValue: Int) {
		self.rawValue = rawValue
	}

	public static let excludeBuffers = IterMode(rawValue: 1)
	public static let includeAnonymous = IterMode(rawValue: 2)
	public static let ignoreMounts = IterMode(rawValue: 4)
	public static let ignoreOverlays = IterMode(rawValue: 8)
	public static let enterBracketed = IterMode(rawValue: 16)
}
