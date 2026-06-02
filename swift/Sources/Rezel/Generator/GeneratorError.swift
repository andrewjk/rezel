//
//  Error.swift
//  Rezel
//
//  Created on 2025-06-11.
//

import Foundation

/// The type of error raised when the parser generator finds an issue.
public final class GenError: Error {
    let message: String
    
    init(_ message: String = "") {
        self.message = message
    }
    
    public var localizedDescription: String {
        return message
    }
}