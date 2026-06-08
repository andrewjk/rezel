public func hashGen(_ a: Int, _ b: Int) -> Int {
	return (a << 5) &+ a &+ b
}

public func hashString(_ h: Int, _ s: String) -> Int {
	var h = h
	for ch in s.unicodeScalars {
		h = hashGen(h, Int(ch.value))
	}
	return h
}
