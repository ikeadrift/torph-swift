// Adapted from Torph by Lochie Axon: https://github.com/lochie/torph
// Copyright (c) 2025 Lochie Axon. MIT licensed; see LICENSE and NOTICE.
// Port of lochie/torph's number.ts (MIT, Lochie Axon).
import Foundation

public enum NumberMatcher {
    static let separators = ".,'\u{a0}\u{202f}\u{2009}\u{2007}"
    static func digit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
    static func hasDigit(_ text: String) -> Bool { text.contains(where: digit) }
    static func kind(_ text: String) -> MorphSegment.Kind { text.count == 1 && text.first.map(digit) == true ? .digit : .symbol }
    static func skeleton(_ text: String) -> String { String(text.filter { !digit($0) && !separators.contains($0) }) }
    static func isNumeric(_ text: String) -> Bool {
        let c = Array(text); var start = 0, end = c.count
        func affix(_ c: Character, _ set: String) -> Bool {
            set.contains(c) || c.unicodeScalars.contains { $0.properties.generalCategory == .currencySymbol }
        }
        while start < end && affix(c[start], "+-−(#") { start += 1 }
        while end > start && affix(c[end-1], "%.,!?:;)\"'”’") { end -= 1 }
        guard start < end, digit(c[start]), digit(c[end-1]) else { return false }
        return c[start..<end].allSatisfy { digit($0) || separators.contains($0) }
    }
    public static func segment(_ value: String, previous: [MorphSegment] = [], cursorIndex: Int? = nil, decimal: String = ".") -> [MorphSegment] {
        let chars = Array(value), old = previous.map { $0.text == "\u{a0}" ? Character(" ") : $0.text.first ?? " " }
        let mapping = previous.isEmpty ? [:] : cursorIndex.map { cursor(old, chars, $0, decimal) } ?? places(old, chars, decimal)
        return chars.enumerated().map { i, c in
            .init(id: mapping[i].map { previous[$0].id } ?? "\0n\(UUID().uuidString)", text: c == " " ? "\u{a0}" : String(c), kind: digit(c) ? .digit : .symbol)
        }
    }
    private static func cursor(_ a: [Character], _ b: [Character], _ cursor: Int, _ decimal: String) -> [Int: Int] {
        func grouping(_ c: Character) -> Bool { String(c) != decimal && separators.contains(c) }
        let old = a.indices.filter { !grouping(a[$0]) }, new = b.indices.filter { !grouping(b[$0]) }
        let keptCursor = new.prefix { $0 < cursor }.count, delta = new.count - old.count
        var matches: [Int: Int] = [:]
        if delta > 0 {
            for i in new.indices {
                if i < keptCursor - delta && i < old.count { matches[new[i]] = old[i] }
                else if i >= keptCursor && i-delta >= 0 && i-delta < old.count { matches[new[i]] = old[i-delta] }
            }
        } else if delta < 0 {
            for i in new.indices {
                if i < keptCursor && i < old.count { matches[new[i]] = old[i] }
                else if i >= keptCursor && i-delta < old.count { matches[new[i]] = old[i-delta] }
            }
        } else {
            for i in new.indices where a[old[i]] == b[new[i]] { matches[new[i]] = old[i] }
        }
        let oldSeps = a.indices.filter { grouping(a[$0]) }, newSeps = b.indices.filter { grouping(b[$0]) }
        for (o,n) in zip(oldSeps.reversed(),newSeps.reversed()) where a[o] == b[n] { matches[n] = o }
        return matches
    }
    private static func places(_ a: [Character], _ b: [Character], _ decimal: String) -> [Int: Int] {
        var result: [Int: Int] = [:], start = 0, oldEnd = a.count, newEnd = b.count
        while start < a.count && start < b.count && a[start] == b[start] && !digit(a[start]) {
            result[start] = start; start += 1
        }
        while oldEnd > start && newEnd > start && a[oldEnd-1] == b[newEnd-1] && !digit(a[oldEnd-1]) {
            result[newEnd-1] = oldEnd-1; oldEnd -= 1; newEnd -= 1
        }
        let oldPivot = (start..<oldEnd).last { String(a[$0]) == decimal } ?? oldEnd
        let newPivot = (start..<newEnd).last { String(b[$0]) == decimal } ?? newEnd
        let oldCount = (start..<oldPivot).filter { digit(a[$0]) }.count
        let newCount = (start..<newPivot).filter { digit(b[$0]) }.count
        if oldCount > 0 && newCount > 0 && abs(oldCount-newCount) >= 3 { return result }
        func matchDigits(_ oldRange: Range<Int>, _ newRange: Range<Int>, _ towardsPivot: Bool) -> Bool {
            let old = oldRange.filter { digit(a[$0]) }, new = newRange.filter { digit(b[$0]) }
            if old.count == new.count || !towardsPivot {
                for (o,n) in zip(old,new) where a[o] == b[n] { result[n] = o }
                return false
            }
            let matches = lcs(old.reversed().map { a[$0] },new.reversed().map { b[$0] })
            for (o,n) in matches { result[new[new.count-1-n]] = old[old.count-1-o] }
            return !matches.isEmpty
        }
        let reshaped = matchDigits(start..<oldPivot, start..<newPivot, true)
        func matchSeparator(_ o: Int, _ n: Int) { if !digit(a[o]) && a[o] == b[n] { result[n] = o } }
        if !reshaped {
            for (o,n) in zip((start..<oldPivot).reversed(), (start..<newPivot).reversed()) { matchSeparator(o,n) }
        }
        if oldPivot < oldEnd && newPivot < newEnd {
            result[newPivot] = oldPivot
            for (o,n) in zip((oldPivot+1)..<oldEnd,(newPivot+1)..<newEnd) { matchSeparator(o,n) }
            _ = matchDigits((oldPivot+1)..<oldEnd,(newPivot+1)..<newEnd,false)
        }
        return result
    }
}
