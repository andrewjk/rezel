//
//  Constants.swift
//  Rezel
//
//  Created on 2025-06-11.
//

import Foundation

// This file defines some constants that are needed both in this
// package and in lezer-generator, so that the generator code can
// access them without them being part of lezer's public interface.

// Parse actions are represented as numbers, in order to cheaply and
// simply pass them around. The numbers are treated as bitfields
// holding different pieces of information.
//
// When storing actions in 16-bit number arrays, they are split in the
// middle, with the first element holding the first 16 bits, and the
// second the rest.
//
// The value 0 (which is not a valid action because no shift goes to
// state 0, the start state), is often used to denote the absence of a
// valid action.
public struct Action {
    // Distinguishes between shift (off) and reduce (on) actions.
    public static let reduceFlag: Int = 1 << 16
    // The first 16 bits hold the target state's id for shift actions,
    // and the reduced term id for reduce actions.
    public static let valueMask: Int = (1 << 16) - 1
    // In reduce actions, all bits beyond 18 hold the reduction's depth
    // (the amount of stack frames it reduces).
    public static let reduceDepthShift: Int = 19
    // This is set for reduce actions that reduce two instances of a
    // repeat term to the term (but _not_ for the reductions that match
    // the repeated content).
    public static let repeatFlag: Int = 1 << 17
    // Goto actions are a special kind of shift that don't actually
    // shift the current token, just add a stack frame. This is used for
    // non-simple skipped expressions, to enter the skip rule when the
    // appropriate token is seen (because the arbitrary state from which
    // such a rule may start doesn't have the correct goto entries).
    public static let gotoFlag: Int = 1 << 17
    // Both shifts and reduces can have a stay flag set. For shift, it
    // means that the current token must be shifted but the state should
    // stay the same (used for single-token skip expression). For
    // reduce, it means that, instead of consulting the goto table to
    // determine which state to go to, the state already on the stack
    // must be returned to (used at the end of non-simple skip
    // expressions).
    public static let stayFlag: Int = 1 << 18
}

// Each parser state has a `flags` field.
public struct StateFlag {
    // Set if this state is part of a skip expression (which means nodes
    // produced by it should be moved out of any node reduced directly
    // after them).
    public static let skipped: Int = 1
    // Indicates whether this is an accepting state.
    public static let accepting: Int = 2
}

// The lowest bit of the values stored in `parser.specializations`
// indicate whether this specialization replaced the original token
// (`Specialize`) or adds a second interpretation while also leaving
// the first (`Extend`).
public struct Specialize {
    public static let specialize: Int = 0
    public static let extend: Int = 1
}

// Terms are 16-bit numbers
public struct Term {
    // The value of the error term is hard coded, the others are
    // allocated per grammar.
    public static let err: Int = 0
}

public struct Seq {
    // Used as end marker for most of the sequences stored in uint16 arrays
    public static let end: Int = 0xffff
    public static let done: Int = 0
    public static let next: Int = 1
    public static let other: Int = 2
}

// Memory layout of parse states
public struct ParseState {
    // Offsets into the record of the individual fields
    public static let flags: Int = 0
    public static let actions: Int = 1
    public static let skip: Int = 2
    public static let tokenizerMask: Int = 3
    public static let defaultReduce: Int = 4
    public static let forcedReduce: Int = 5
    // Total size of a state record
    public static let size: Int = 6
}

public struct Encode {
    public static let bigValCode: Int = 126
    public static let bigVal: Int = 0xffff
    public static let start: Int = 32
    public static let gap1: Int = 34 // '"'
    public static let gap2: Int = 92 // '\\'
    public static let `base`: Int = 46 // (126 - 32 - 2) / 2
}

public struct File {
    public static let version: Int = 14
}