//
//  Parse.swift
//  Rezel
//
//  Created on 2025-06-02.
//

import Foundation

/// The TreeFragment.applyChanges method expects changed ranges in this format.
public struct ChangedRange {
    /// The start of the change in the start document
    public let fromA: Int
    /// The end of the change in the start document
    public let toA: Int
    /// The start of the replacement in the new document
    public let fromB: Int
    /// The end of the replacement in the new document
    public let toB: Int
    
    public init(fromA: Int, toA: Int, fromB: Int, toB: Int) {
        self.fromA = fromA
        self.toA = toA
        self.fromB = fromB
        self.toB = toB
    }
}

internal enum Open: Int {
    case start = 1
    case end = 2
}

/// Tree fragments are used during incremental parsing to track parts of old trees
/// that can be reused in a new parse. An array of fragments is used
/// to track regions of an old tree whose nodes might be reused in new
/// parses. Use the static addTree and applyChanges method to
/// update fragments for document changes.
public final class TreeFragment {
    /// @internal
    internal var openValue: Int
    
    /// The start of the unchanged range pointed to by this fragment.
    /// This refers to an offset in the updated document (as opposed
    /// to the original tree).
    public let from: Int
    
    /// The end of the unchanged range.
    public let to: Int
    
    /// The tree that this fragment is based on.
    public let tree: Tree
    
    /// The offset between the fragment's tree and the document that
    /// this fragment can be used against. Add this when going from
    /// document to tree positions, subtract it to go from tree to
    /// document positions.
    public let offset: Int
    
    /// Construct a tree fragment. You'll usually want to use
    /// addTree and applyChanges instead of calling this directly.
    public init(
        from: Int,
        to: Int,
        tree: Tree,
        offset: Int,
        openStart: Bool = false,
        openEnd: Bool = false
    ) {
        self.from = from
        self.to = to
        self.tree = tree
        self.offset = offset
        self.openValue = (openStart ? Open.start.rawValue : 0) | (openEnd ? Open.end.rawValue : 0)
    }
    
    /// Whether the start of the fragment represents the start of a
    /// parse, or the end of a change. (In the second case, it may not
    /// be safe to reuse some nodes at the start, depending on the
    /// parsing algorithm.)
    public var openStart: Bool {
        return (openValue & Open.start.rawValue) > 0
    }
    
    /// Whether the end of the fragment represents the end of a
    /// full-document parse, or the start of a change.
    public var openEnd: Bool {
        return (openValue & Open.end.rawValue) > 0
    }
    
    /// Create a set of fragments from a freshly parsed tree, or update
    /// an existing set of fragments by replacing the ones that overlap
    /// with a tree with content from the new tree. When `partial` is
    /// true, the parse is treated as incomplete, and the resulting
    /// fragment has openEnd set to true.
    public static func addTree(
        tree: Tree,
        fragments: [TreeFragment] = [],
        partial: Bool = false
    ) -> [TreeFragment] {
        var result = [TreeFragment(from: 0, to: tree.length, tree: tree, offset: 0, openStart: false, openEnd: partial)]
        for f in fragments {
            if f.to > tree.length {
                result.append(f)
            }
        }
        return result
    }
    
    /// Apply a set of edits to an array of fragments, removing or
    /// splitting fragments as necessary to remove edited ranges, and
    /// adjusting offsets for fragments that moved.
    public static func applyChanges(
        fragments: [TreeFragment],
        changes: [ChangedRange],
        minGap: Int = 128
    ) -> [TreeFragment] {
        if changes.isEmpty {
            return fragments
        }
        var result: [TreeFragment] = []
        var fI = 1
        var nextF: TreeFragment? = fragments.first
        var cI = 0
        var pos = 0
        var off = 0
        
        while true {
            let nextC = cI < changes.count ? changes[cI] : nil
            let nextPos = nextC != nil ? nextC!.fromA : Int(1_000_000_000)
            
            if nextPos - pos >= minGap {
                while let currentNextF = nextF, currentNextF.from < nextPos {
                    var cut: TreeFragment? = currentNextF
                    if pos >= cut!.from || nextPos <= cut!.to || off != 0 {
                        let fFrom = max(cut!.from, pos) - off
                        let fTo = min(cut!.to, nextPos) - off
                        if fFrom >= fTo {
                            cut = nil
                        } else {
                            cut = TreeFragment(
                                from: fFrom,
                                to: fTo,
                                tree: cut!.tree,
                                offset: cut!.offset + off,
                                openStart: cI > 0,
                                openEnd: nextC != nil
                            )
                        }
                    }
                    if let cut = cut {
                        result.append(cut)
                    }
                    if cut!.to > nextPos {
                        break
                    }
                    nextF = fI < fragments.count ? fragments[fI] : nil
                    fI += 1
                }
            }
            
            if nextC == nil {
                break
            }
            
            pos = nextC!.toA
            off = nextC!.toA - nextC!.toB
            cI += 1
        }
        
        return result
    }
}

/// Interface used to represent an in-progress parse, which can be
/// moved forward piece-by-piece.
public protocol PartialParse: AnyObject {
    /// Advance the parse state by some amount. Will return the finished
    /// syntax tree when the parse completes.
    func advance() -> Tree?
    
    /// The position up to which the document has been parsed. Note
    /// that, in multi-pass parsers, this will stay back until the last
    /// pass has moved past a given position.
    var parsedPos: Int { get }
    
    /// Tell the parse to not advance beyond the given position.
    /// `advance` will return a tree when the parse has reached the
    /// position. Note that, depending on the parser algorithm and the
    /// state of the parse when `stopAt` was called, that tree may
    /// contain nodes beyond the position. It is an error to call
    /// `stopAt` with a higher position than it's current value.
    func stopAt(pos: Int)
    
    /// Reports whether `stopAt` has been called on this parse.
    var stoppedAt: Int? { get }
}

/// A superclass that parsers should extend.
public protocol Parser: AnyObject {
    /// Start a parse for a single tree. This is the method concrete
    /// parser implementations must implement. Called by `startParse`,
    /// with the optional arguments resolved.
    func createParse(
        input: any Input,
        fragments: [TreeFragment],
        ranges: [Range]
    ) -> any PartialParse
}

public extension Parser {
    /// Start a parse, returning a partial parse object. TreeFragment can be passed in to
    /// make the parse incremental.
    ///
    /// By default, the entire input is parsed. You can pass `ranges`,
    /// which should be a sorted array of non-empty, non-overlapping
    /// ranges, to parse only those ranges. The tree returned in that
    /// case will start at `ranges[0].from`.
    func startParse(
        input: any Input,
        fragments: [TreeFragment]? = nil,
        ranges: [Range]? = nil
    ) -> any PartialParse {
        let inputObj: any Input
        if let strInput = input as? String {
            inputObj = StringInput(string: strInput)
        } else {
            inputObj = input
        }
        
        let finalRanges: [Range]
        if let ranges = ranges, !ranges.isEmpty {
            finalRanges = ranges
        } else {
            finalRanges = [Range(from: 0, to: inputObj.length)]
        }
        
        return createParse(input: inputObj, fragments: fragments ?? [], ranges: finalRanges)
    }
    
    /// Run a full parse, returning the resulting tree.
    func parse(
        input: any Input,
        fragments: [TreeFragment]? = nil,
        ranges: [Range]? = nil
    ) -> Tree {
        let parse = startParse(input: input, fragments: fragments, ranges: ranges)
        while true {
            if let done = parse.advance() {
                return done
            }
        }
    }
}

/// This is the interface parsers use to access the document. To run
/// Lezer directly on your own document data structure, you have to
/// write an implementation of it.
public protocol Input: AnyObject {
    /// The length of the document.
    var length: Int { get }
    
    /// Get the chunk after the given position. The returned string
    /// should start at `from` and, if that isn't the end of the
    /// document, may be of any length greater than zero.
    func chunk(from: Int) -> String
    
    /// Indicates whether the chunks already end at line breaks, so that
    /// client code that wants to work by-line can avoid re-scanning
    /// them for line breaks. When this is true, the result of `chunk()`
    /// should either be a single line break, or the content between
    /// `from` and the next line break.
    var lineChunks: Bool { get }
    
    /// Read the part of the document between the given positions.
    func read(from: Int, to: Int) -> String
}

internal final class StringInput: Input {
    let string: String
    
    init(string: String) {
        self.string = string
    }
    
    var length: Int {
        return string.count
    }
    
    func chunk(from: Int) -> String {
        let index = string.index(string.startIndex, offsetBy: from)
        return String(string[index...])
    }
    
    var lineChunks: Bool {
        return false
    }
    
    func read(from: Int, to: Int) -> String {
        let start = string.index(string.startIndex, offsetBy: from)
        let end = string.index(string.startIndex, offsetBy: to)
        return String(string[start..<end])
    }
}

/// Parse wrapper functions are supported by some parsers to inject
/// additional parsing logic.
public typealias ParseWrapper = (
    _ inner: any PartialParse,
    _ input: any Input,
    _ fragments: [TreeFragment],
    _ ranges: [Range]
) -> any PartialParse