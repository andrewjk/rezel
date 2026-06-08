public enum Side: Int {
	case before = -2
	case atOrBefore = -1
	case around = 0
	case atOrAfter = 1
	case after = 2
	case dontCare = 4
}

func checkSide(_ side: Side, pos: Int, from: Int, to: Int) -> Bool {
	switch side {
	case .before: return from < pos
	case .atOrBefore: return to >= pos && from < pos
	case .around: return from < pos && to > pos
	case .atOrAfter: return from <= pos && to > pos
	case .after: return to > pos
	case .dontCare: return true
	}
}
