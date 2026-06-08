import Foundation

public let encodeStart: UInt8 = 32
public let encodeGap1: UInt8 = .init(ascii: "\"")
public let encodeGap2: UInt8 = .init(ascii: "\\")
public let encodeBase = 46
public let encodeBigVal = 0xFFFF
public let encodeBigValCode: UInt8 = 126

public enum Seq {
	public static let End = 0xFFFF
	public static let Done = 0
	public static let Other = 2
	public static let Next = 1
}

public enum Action {
	public static let ReduceFlag = 1 << 16
	public static let ValueMask = (1 << 16) - 1
	public static let ReduceDepthShift = 19
	public static let RepeatFlag = 1 << 17
	public static let GotoFlag = 1 << 17
	public static let StayFlag = 1 << 18
}

public enum StateFlag {
	public static let Skipped = 1
	public static let Accepting = 2
}

public enum Specialize {
	public static let Specialize = 0
	public static let Extend = 1
}

public enum ParseState {
	public static let Size = 6
	public static let Flags = 0
	public static let Actions = 1
	public static let Skip = 2
	public static let TokenizerMask = 3
	public static let DefaultReduce = 4
	public static let ForcedReduce = 5
}

public enum LrTerm {
	public static let Err = 0
}

public enum LrFile {
	public static let Version = 14
}
