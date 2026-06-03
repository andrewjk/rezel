//
//  Log.swift
//  Rezel
//
//  Created on 2025-06-11.
//

import Foundation

/// Verbose logging flag
public let verbose: String = ProcessInfo.processInfo.environment["LOG"] ?? "parse"

/// Timing flag for performance measurement
public let timing: Bool = verbose.contains("time")

/// Time a function execution if timing is enabled
public func time<T>(_ label: String, _ f: () -> T) -> T {
    if timing {
        let t0 = Date().timeIntervalSince1970
        let result = f()
        let elapsed = Date().timeIntervalSince1970 - t0
        print("\(label) (\(String(format: "%.2f", elapsed))s)")
        return result
    } else {
        return f()
    }
}
