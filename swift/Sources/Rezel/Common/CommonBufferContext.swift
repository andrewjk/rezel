public final class BufferContext {
	public let parent: TreeNode
	public let buffer: TreeBuffer
	public let index: Int
	public let start: Int

	public init(parent: TreeNode, buffer: TreeBuffer, index: Int, start: Int) {
		self.parent = parent
		self.buffer = buffer
		self.index = index
		self.start = start
	}
}
