import Foundation

func digitToChar(_ digit: Int) -> Character {
    var ch = digit + Int(encodeStart)
    if ch >= Int(encodeGap1) { ch += 1 }
    if ch >= Int(encodeGap2) { ch += 1 }
    return Character(UnicodeScalar(ch)!)
}

public func encode(_ value: Int, max: Int = Int(encodeBigVal)) -> String {
    if value > max { fatalError("Trying to encode a number that's too big: \(value)") }
    if value == Int(encodeBigVal) { return String(Character(UnicodeScalar(Int(encodeBigValCode))!)) }
    var result = ""
    var v = value
    var first = true
    while true {
        let low = v % encodeBase
        let rest = v - low
        let digit = low + (first ? encodeBase : 0)
        result = String(digitToChar(digit)) + result
        if rest == 0 { break }
        v = rest / encodeBase
        first = false
    }
    return result
}

public func encodeArray(_ values: [Int], max: Int = Int(encodeBigVal)) -> String {
    var result = "\"" + encode(values.count, max: 0xffffffff)
    for v in values {
        result += encode(v, max: max)
    }
    result += "\""
    return result
}
