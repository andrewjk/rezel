extension NodeType {
    public func `is`(_ name: Any) -> Bool {
        if let s = name as? String { return `is`(s) }
        if let i = name as? Int { return id == i }
        return false
    }
}
