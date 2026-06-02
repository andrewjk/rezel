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
        var pos = 0
        var outputIndex = 0
        
        while pos < strInput.count {
            var value = 0
            
            while true {
                guard pos < strInput.count else { fatalError("Unexpected end of input") }
                
                guard pos < strInput.utf16.count else { fatalError("Unexpected end of input") }
                let nextChar = strInput.utf16[strInput.index(strInput.startIndex, offsetBy: pos)]
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
            
            if outputIndex < result.count {
                result[outputIndex] = value
            } else {
                result.append(value)
            }
            
            outputIndex += 1
        }
        
        return result
    }
}