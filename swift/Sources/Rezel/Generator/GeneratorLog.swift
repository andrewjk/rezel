import Foundation

public let verbose = ProcessInfo.processInfo.environment["LOG"] ?? ""
public let timing = verbose.contains("time")

public func logTime<T>(_ label: String, _ f: () -> T) -> T {
	if timing {
		let t0 = Date()
		let result = f()
		let elapsed = Date().timeIntervalSince(t0)
		print("\(label) (\(String(format: "%.2f", elapsed))s)")
		return result
	}
	return f()
}

public func logTime<T>(_ label: String, _ f: () throws -> T) rethrows -> T {
	if timing {
		let t0 = Date()
		let result = try f()
		let elapsed = Date().timeIntervalSince(t0)
		print("\(label) (\(String(format: "%.2f", elapsed))s)")
		return result
	}
	return try f()
}
