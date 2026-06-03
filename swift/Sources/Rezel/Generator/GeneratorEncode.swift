//
//  Encode.swift
//  Rezel
//
//  Created on 2025-06-11.
//

import Foundation

// Encode numbers as groups of printable ascii characters
//
// - 0xffff, which is often used as placeholder, is encoded as "~"
//
// - The characters from " " (32) to "}" (125), excluding '"' and
//   "\\", indicate values from 0 to 92
//
// - The first bit in a 'digit' is used to indicate whether this is
//   the end of a number.
//
// - That leaves 46 other values, which are actually significant.
//
// - The digits in a number are ordered from high to low significance.

fileprivate func digitToChar(_ digit: Int) -> Character {
    var ch = digit + Encode.start
    if ch >= Encode.gap1 { ch += 1 }
    if ch >= Encode.gap2 { ch += 1 }
    return Character(UnicodeScalar(ch)!)
}

/// Encode a single number as a string
public func encode(_ value: Int, max: Int = 0xffff) -> String {
    if value > max {
        fatalError("Trying to encode a number that's too big: \(value)")
    }
    if value == Encode.bigVal {
        return String(UnicodeScalar(Encode.bigValCode)!)
    }
    
    var result = ""
    var first = Encode.base
    var value = value
    
    while true {
        let low = value % Encode.base
        let rest = value - low
        result = String(digitToChar(low + first)) + result
        if rest == 0 {
            break
        }
        value = rest / Encode.base
        first = 0
    }
    
    return result
}

/// Encode an array of numbers as a string
public func encodeArray(_ values: [Int], max: Int = 0xffff) -> String {
    var result = encode(values.count, max: 0xffffffff)
    for i in 0..<values.count {
        result += encode(values[i], max: max)
    }
    return result
}