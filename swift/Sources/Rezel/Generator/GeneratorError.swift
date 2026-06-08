public final class GenError: Error, CustomStringConvertible, Sendable {
	public let message: String

	public init(_ message: String) {
		self.message = message
	}

	public var description: String {
		message
	}
}
