// Adapted from Torph by Lochie Axon: https://github.com/lochie/torph
// Copyright (c) 2025 Lochie Axon. MIT licensed; see LICENSE and NOTICE.
// Port of lochie/torph's segment.ts and diff.ts (MIT, Lochie Axon).
import Foundation

public struct MorphSegment: Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case digit, symbol }
    public let id: String
    public let text: String
    public let kind: Kind?
    public var isDigit: Bool { kind == .digit }
    public init(id: String = UUID().uuidString, text: String, kind: Kind? = nil) {
        self.id = id; self.text = text; self.kind = kind
    }
}

public struct MorphDiff: Sendable {
    public let segments: [MorphSegment]
    /// Old whole-word nodes must be split BEFORE measuring either side.
    public let splits: [String: [MorphSegment]]
    public let preparedPrevious: [MorphSegment]
    public var inserted: [MorphSegment] {
        let ids = Set(preparedPrevious.map(\.id)); return segments.filter { !ids.contains($0.id) }
    }
    public var removed: [MorphSegment] {
        let ids = Set(segments.map(\.id)); return preparedPrevious.filter { !ids.contains($0.id) }
    }
}

struct IDAllocator {
    var used = Set<String>()
    mutating func take(_ base: String) -> String {
        if used.insert(base).inserted { return base }
        var i = 1
        while used.contains("\(base)~\(i)") { i += 1 }
        let id = "\(base)~\(i)"; used.insert(id); return id
    }
}

public enum TextMatcher {
    public static func segment(_ text: String, locale: Locale = .current, numbers: Bool = true) -> [MorphSegment] {
        var alloc = IDAllocator(), result: [MorphSegment] = []
        let byWord = text.contains(" ") || text.contains("\n")
        var offset = 0
        for (lineIndex, line) in text.components(separatedBy: "\n").enumerated() {
            if lineIndex > 0 {
                result.append(.init(id: alloc.take("newline-\(offset)"), text: "\n")); offset += 1
            }
            for (part, index) in pieces(line, byWord: byWord) {
                let position = offset + index
                let base = part == " " ? "space-\(position)" : alloc.used.contains(part) ? "\(part)-\(position)" : part
                result.append(.init(id: alloc.take(base), text: part == " " ? "\u{a0}" : part))
            }
            offset += line.utf16.count
        }
        guard numbers else { return result }
        var expanded: [MorphSegment] = [], run: [MorphSegment] = []
        func flush() {
            let word = run.map(\.text).joined()
            expanded += NumberMatcher.isNumeric(word) ? NumberMatcher.segment(word) : run
            run = []
        }
        for item in result {
            if item.text == "\u{a0}" || item.text == "\n" { flush(); expanded.append(item) }
            else { run.append(item) }
        }
        flush(); return expanded
    }

    // ICU's Unicode word boundaries provide the same UAX #29 basis as Intl.Segmenter.
    // Native ICU/locale dictionary revisions can differ from the browser's ICU version.
    private static func pieces(_ line: String, byWord: Bool) -> [(String, Int)] {
        if !byWord {
            var offset = 0
            return line.map { c in defer { offset += String(c).utf16.count }; return (String(c), offset) }
        }
        guard !line.isEmpty else { return [] }
        let regex = try! NSRegularExpression(pattern: "\\b", options: .useUnicodeWordBoundaries)
        let ns = line as NSString
        var cuts = Set(regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).map(\.range.location))
        cuts.insert(0); cuts.insert(ns.length)
        let ordered = cuts.sorted()
        var result: [(String, Int)] = []
        for (start, end) in zip(ordered, ordered.dropFirst()) where start < end {
            let part = ns.substring(with: NSRange(location: start, length: end - start))
            // Intl emits each punctuation/emoji token separately, but combines a run of spaces.
            if part.allSatisfy(\.isWhitespace) || part.contains(where: { $0.isLetter || $0.isNumber }) {
                result.append((part, start))
            } else {
                var offset = start
                for c in part { result.append((String(c), offset)); offset += String(c).utf16.count }
            }
        }
        return result
    }

    struct Word { var text: String; var segments: [MorphSegment] }
    static func words(_ segments: [MorphSegment]) -> [Word] {
        var result: [Word] = [], run: [MorphSegment] = []
        func flush() { if !run.isEmpty { result.append(Word(text: run.map(\.text).joined(), segments: run)); run = [] } }
        for s in segments {
            if s.text == "\u{a0}" || s.text == "\n" { flush() } else { run.append(s) }
        }
        flush(); return result
    }

    public static func diff(from old: [MorphSegment], to text: String, numbers: Bool = true,
                            locale: Locale = .current, cursorIndex: Int? = nil) -> MorphDiff {
        let oldWords = words(old)
        func finish(_ segments: [MorphSegment], _ splits: [String: [MorphSegment]] = [:]) -> MorphDiff {
            .init(segments: segments, splits: splits, preparedPrevious: old.flatMap { splits[$0.id] ?? [$0] })
        }
        let digitsInvolved = numbers && (NumberMatcher.hasDigit(text) || oldWords.contains { NumberMatcher.hasDigit($0.text) })
        if oldWords.count <= 1 && !text.contains(" ") && !text.contains("\n") && !digitsInvolved {
            return finish(segment(text, locale: locale, numbers: numbers))
        }
        var newWords: [String] = [], separators: [[String]] = [], pending: [String] = [], word = ""
        for c in text {
            if c == " " || c == "\n" {
                if !word.isEmpty { newWords.append(word); separators.append(pending); pending = []; word = "" }
                pending.append(String(c))
            } else { word.append(c) }
        }
        if !word.isEmpty { newWords.append(word); separators.append(pending); pending = [] }
        let trailing = pending
        if oldWords.count > 1_000_000 / max(1, newWords.count) { return finish(segment(text, locale: locale, numbers: numbers)) }
        func isNum(_ s: String) -> Bool { numbers && NumberMatcher.isNumeric(s) }
        func token(_ s: String) -> String { isNum(s) ? "\0#" : s }
        let anchors = lcs(oldWords.map { token($0.text) }, newWords.map(token))
        let oldMatched = Set(anchors.map { $0.0 }), newMatched = Set(anchors.map { $0.1 })
        var pairs = Dictionary(uniqueKeysWithValues: anchors.map { ($0.1, $0.0) })
        var oldUnmatched = oldWords.indices.filter { !oldMatched.contains($0) }
        var newUnmatched = newWords.indices.filter { !newMatched.contains($0) }
        var exactUsed = Set<Int>()
        for ni in newUnmatched {
            for oi in oldUnmatched where !exactUsed.contains(oi) {
                if token(newWords[ni]) == token(oldWords[oi].text) { pairs[ni] = oi; exactUsed.insert(oi); break }
            }
        }
        oldUnmatched.removeAll { exactUsed.contains($0) }
        newUnmatched.removeAll { pairs[$0] != nil }
        func gaps(_ count: Int, _ matched: Set<Int>) -> [Int] {
            var n = 0; return (0..<count).map { i in defer { if matched.contains(i) { n += 1 } }; return n }
        }
        let oldGaps = gaps(oldWords.count, oldMatched), newGaps = gaps(newWords.count, newMatched)
        var morphs: [Int: Int] = [:], used = Set<Int>()
        if oldUnmatched.count <= 2_500 / max(1, newUnmatched.count) {
            for ni in newUnmatched {
                var best: Int?, score = 0.4
                for oi in oldUnmatched where !used.contains(oi) && oldGaps[oi] == newGaps[ni] {
                    let a = oldWords[oi].text, b = newWords[ni]
                    let affinity: Double
                    if (NumberMatcher.hasDigit(a) || NumberMatcher.hasDigit(b)) && NumberMatcher.skeleton(a) == NumberMatcher.skeleton(b) {
                        affinity = 1
                    } else { affinity = Double(lcs(Array(a), Array(b)).count) / Double(max(a.count, b.count, 1)) }
                    if affinity > score { best = oi; score = affinity }
                }
                if let best { morphs[ni] = best; used.insert(best) }
            }
        }
        enum Mode { case fresh, reuse, morph, number }
        let plans: [(Mode, Int?)] = newWords.indices.map { ni in
            guard let oi = pairs[ni] ?? morphs[ni] else { return (.fresh, nil) }
            return (isNum(newWords[ni]) ? .number : pairs[ni] != nil ? .reuse : .morph, oi)
        }
        let cursor = plans.filter { $0.0 == .number }.count == 1 ? cursorIndex : nil
        var alloc = IDAllocator()
        for (mode, oi) in plans {
            guard let oi else { continue }
            let group = oldWords[oi]
            if mode != .reuse && group.segments.count == 1 {
                for i in 0..<group.text.count { alloc.used.insert("\(group.segments[0].id):\(i)") }
            } else { for s in group.segments { alloc.used.insert(s.id) } }
        }
        var result: [MorphSegment] = [], splits: [String: [MorphSegment]] = [:], offset = 0
        func split(_ group: Word) -> [MorphSegment] {
            guard group.segments.count == 1 && group.text.count > 1 else { return group.segments }
            let chars = group.text.enumerated().map { MorphSegment(id: "\(group.segments[0].id):\($0.offset)", text: String($0.element)) }
            splits[group.segments[0].id] = chars; return chars
        }
        func push(_ seps: [String]) {
            for s in seps {
                result.append(.init(id: alloc.take("\(s == "\n" ? "newline" : "space")-\(offset)"), text: s == "\n" ? s : "\u{a0}")); offset += 1
            }
        }
        for ni in newWords.indices {
            push(separators[ni])
            let (mode, oi) = plans[ni], value = newWords[ni]
            switch mode {
            case .reuse: result += oldWords[oi!].segments
            case .number:
                let previous = split(oldWords[oi!]).map { MorphSegment(id: $0.id, text: $0.text, kind: $0.kind ?? NumberMatcher.kind($0.text)) }
                result += NumberMatcher.segment(value, previous: previous, cursorIndex: cursor.map { $0 - offset }, decimal: locale.decimalSeparator ?? ".")
            case .morph:
                let group = oldWords[oi!], previous = split(group), chars = Array(value)
                let matches = lcs(Array(group.text), chars)
                let origins = Dictionary(uniqueKeysWithValues: matches.compactMap { o, n in o < previous.count ? (n, previous[o]) : nil })
                for ci in chars.indices { result.append(.init(id: origins[ci]?.id ?? alloc.take("\(value)~\(ci)"), text: String(chars[ci]))) }
            case .fresh:
                result += isNum(value) ? NumberMatcher.segment(value) : [.init(id: alloc.take(value), text: value)]
            }
            offset += value.utf16.count
        }
        push(trailing); return finish(result, splits)
    }
}

/// Upstream's forward LCS traversal: ties advance the old side.
func lcs<T: Equatable>(_ a: [T], _ b: [T]) -> [(Int, Int)] {
    guard !a.isEmpty && !b.isEmpty else { return [] }
    // Upstream bounds word-pair work. Also protect native callers from huge character runs.
    if a.count > 1_000_000 / b.count { return [] }
    let width = b.count + 1
    var dp = Array(repeating: 0, count: (a.count + 1) * width)
    for i in a.indices.reversed() { for j in b.indices.reversed() {
        dp[i * width + j] = a[i] == b[j] ? dp[(i+1)*width+j+1]+1 : max(dp[(i+1)*width+j],dp[i*width+j+1])
    } }
    var i = 0, j = 0, result: [(Int, Int)] = []
    while i < a.count && j < b.count {
        if a[i] == b[j] { result.append((i,j)); i += 1; j += 1 }
        else if dp[(i+1)*width+j] >= dp[i*width+j+1] { i += 1 } else { j += 1 }
    }
    return result
}
