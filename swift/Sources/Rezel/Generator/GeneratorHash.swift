//
//  Hash.swift
//  Rezel
//
//  Created on 2025-06-11.
//

import Foundation

/// Simple hash function combining two numbers
public func hash(_ a: Int, _ b: Int) -> Int {
    return (a << 5) + a + b
}

/// Hash a string character by character
public func hashString(_ h: Int, _ s: String) -> Int {
    var result = h
    for scalar in s.unicodeScalars {
        result = hash(result, Int(scalar.value))
    }
    return result
}