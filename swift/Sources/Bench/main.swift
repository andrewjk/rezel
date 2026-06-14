import Foundation
import Rezel

var jsSB = ""
for i in 0..<20 {
    jsSB += "function f\(i)(x) {\n  const r = x * 2;\n  if (r > 100) return r;\n  return r + i;\n}\n"
    jsSB += "class C\(i) { constructor(n) { this.n = n; } run(x) { return f\(i)(x); } }\n"
}
let jsText = jsSB
let smallJs = String(jsText.prefix(300))

let singleJson = "{\"a\":1,\"b\":[1,2,3],\"c\":{\"d\":[{\"e\":1},{\"e\":2},{\"e\":3}]}}"
let jsonText = String(repeating: singleJson, count: 50)
let smallJson = singleJson

let jsP = javaScriptParser
let jsonP = jsonParser

// Warmup
for _ in 0..<5 {
    jsP.parse(input: jsText)
    jsonP.parse(input: jsonText)
    jsP.parse(input: smallJs)
    jsonP.parse(input: smallJson)
}

let iters = 200

func bench(_ name: String, _ block: () -> Void) {
    let start = DispatchTime.now()
    for _ in 0..<iters { block() }
    let end = DispatchTime.now()
    let ns = end.uptimeNanoseconds - start.uptimeNanoseconds
    let us = Double(ns) / Double(iters) / 1000.0
    print("\(name): \(String(format: "%.1f", us)) us")
}

bench("ParseJsonSmall") { jsonP.parse(input: smallJson) }
bench("ParseJsonMedium") { jsonP.parse(input: jsonText) }
bench("ParseJsSmall") { jsP.parse(input: smallJs) }
bench("ParseJsMedium") { jsP.parse(input: jsText) }
