//
//  Decode.swift
//  Rezel
//
//  Created on 2025-06-11.
//

import Foundation

// See lezer-generator/src/encode.ts for comments about the encoding used here

public enum ArrayOrString {
    case array([Int])
    case string(String)
}

public func decodeArray(_ input: ArrayOrString) -> [Int] {
    switch input {
    case .array(let array):
        return array
    case .string(let strInput):
        var result: [Int] = []
        let chars = Array(strInput.utf16)
        let count = chars.count
        var pos = 0
        var outputIndex = 0
        var first = true
        
        while pos < count {
            var value = 0
            
            while true {
                guard pos < count else { fatalError("Unexpected end of input") }
                let nextChar = chars[pos]
                var stop = false
                
                pos += 1
                
                if nextChar == Encode.bigValCode {
                    value = Encode.bigVal
                    break
                }
                
                var next = Int(nextChar)
                
                if next >= Encode.gap2 {
                    next -= 1
                }
                if next >= Encode.gap1 {
                    next -= 1
                }
                
                var digit = next - Encode.start
                if digit >= Encode.base {
                    digit -= Encode.base
                    stop = true
                }
                
                value += digit
                if stop {
                    break
                }
                value *= Encode.base
            }
            
            if first {
                result = [Int](repeating: 0, count: value)
                first = false
            } else {
                if outputIndex < result.count {
                    result[outputIndex] = value
                } else {
                    result.append(value)
                }
                outputIndex += 1
            }
        }
        
        return result
    }
}