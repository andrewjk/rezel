import Foundation

public func decodeArray(_ input: Any) -> [UInt16] {
    if let arr = input as? [UInt16] { return arr }
    guard let str = input as? String else { return input as! [UInt16] }

    var array: [UInt16]? = nil
    var pos = 0
    var out = 0

    while pos < str.unicodeScalars.count {
        var value = 0
        let scalars = Array(str.unicodeScalars)
        while true {
            var next = Int(scalars[pos].value)
            pos += 1
            var stop = false
            if next == Int(encodeBigValCode) {
                value = Int(encodeBigVal)
                break
            }
            if next >= Int(encodeGap2) { next -= 1 }
            if next >= Int(encodeGap1) { next -= 1 }
            var digit = next - Int(encodeStart)
            if digit >= encodeBase {
                digit -= encodeBase
                stop = true
            }
            value += digit
            if stop { break }
            value *= encodeBase
        }
        if array != nil {
            array![out] = UInt16(value)
            out += 1
        } else {
            array = [UInt16](repeating: 0, count: value)
        }
    }
    return array!
}

public func decodeArray32(_ input: Any) -> [UInt32] {
    if let arr = input as? [UInt32] { return arr }
    guard let str = input as? String else { return input as! [UInt32] }

    var array: [UInt32]? = nil
    var pos = 0
    var out = 0

    let scalars = Array(str.unicodeScalars)
    while pos < scalars.count {
        var value = 0
        while true {
            var next = Int(scalars[pos].value)
            pos += 1
            var stop = false
            if next == Int(encodeBigValCode) {
                value = Int(encodeBigVal)
                break
            }
            if next >= Int(encodeGap2) { next -= 1 }
            if next >= Int(encodeGap1) { next -= 1 }
            var digit = next - Int(encodeStart)
            if digit >= encodeBase {
                digit -= encodeBase
                stop = true
            }
            value += digit
            if stop { break }
            value *= encodeBase
        }
        if array != nil {
            array![out] = UInt32(value)
            out += 1
        } else {
            array = [UInt32](repeating: 0, count: value)
        }
    }
    return array!
}
