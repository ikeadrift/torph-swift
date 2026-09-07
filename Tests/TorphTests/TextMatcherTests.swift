import XCTest
@testable import Torph

final class TextMatcherTests: XCTestCase {
    struct Shape: Decodable, Equatable { let text: String; let kind: String? }
    struct Step: Decodable { let value: String; let cursor: Int?; let prepared: [Shape]; let segments: [Shape]; let origins: [Int?] }
    struct Fixture: Decodable { let label: String; let mode: String; let locale: String; let initial: String; let initialSegments: [Shape]; let steps: [Step] }
    func shape(_ segments: [MorphSegment]) -> [Shape] { segments.map { Shape(text: $0.text, kind: $0.kind?.rawValue) } }

    func testUpstreamCorpus() throws {
        let url = Bundle.module.url(forResource: "upstream", withExtension: "json")!
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(fixtures.count, 84)
        for fixture in fixtures {
            let locale = Locale(identifier: fixture.locale)
            var old = fixture.mode == "text" ? TextMatcher.segment(fixture.initial, locale: locale) : NumberMatcher.segment(fixture.initial)
            XCTAssertEqual(shape(old), fixture.initialSegments, "\(fixture.label): initial segmentation")
            for (i, step) in fixture.steps.enumerated() {
                let prepared: [MorphSegment], next: [MorphSegment]
                if fixture.mode == "text" {
                    let diff = TextMatcher.diff(from: old, to: step.value, locale: locale, cursorIndex: step.cursor)
                    prepared = diff.preparedPrevious; next = diff.segments
                } else {
                    prepared = old; next = NumberMatcher.segment(step.value, previous: old, cursorIndex: step.cursor, decimal: locale.decimalSeparator ?? ".")
                }
                let context = "\(fixture.label) step \(i): \(step.value)"
                XCTAssertEqual(shape(prepared), step.prepared, context + " split plan")
                XCTAssertEqual(shape(next), step.segments, context + " segmentation")
                XCTAssertEqual(Set(next.map(\.id)).count, next.count, context + " unique IDs")
                let positions = Dictionary(uniqueKeysWithValues: prepared.enumerated().map { ($0.element.id,$0.offset) })
                XCTAssertEqual(next.map { positions[$0.id] }, step.origins, context + " origins")
                old = next
            }
        }
    }

    func testCapitalTIsInsertedAndProcessingRemainsWhole() {
        let old = TextMatcher.segment("Processing transaction")
        let diff = TextMatcher.diff(from: old, to: "Transaction complete")
        XCTAssertEqual(old.map(\.text), ["Processing", "\u{a0}", "transaction"])
        XCTAssertEqual(diff.splits.keys.sorted(), ["transaction"])
        XCTAssertEqual(diff.segments.first?.text, "T")
        XCTAssertTrue(diff.inserted.contains { $0.id == diff.segments.first?.id })
        XCTAssertTrue(diff.removed.contains { $0.text == "Processing" })
        XCTAssertTrue(diff.removed.contains { $0.text == "t" })
        XCTAssertEqual(diff.segments[1].id, "transaction:1")
        XCTAssertEqual(diff.segments.last?.text, "complete")
    }

    func testWholeWordsKeepShapingUntilTheyNeedSplitting() {
        let old = TextMatcher.segment("hello world")
        let reordered = TextMatcher.diff(from: old, to: "world hello")
        XCTAssertTrue(reordered.splits.isEmpty)
        XCTAssertEqual(reordered.segments.first?.id, "world")
        XCTAssertEqual(reordered.segments.last?.id, "hello")
    }

    func testGraphemeLabelsRemainIntact() {
        let text = "👨‍👩‍👧‍👦👍🏽🇯🇵e\u{301}"
        XCTAssertEqual(TextMatcher.segment(text).map(\.text), text.map(String.init))
    }
}
