import XCTest
import SwiftUI
@testable import Torph

final class EntranceTests: XCTestCase {
    private func rects(_ segments: [MorphSegment]) -> [String: CGRect] {
        var x = 0.0
        return Dictionary(uniqueKeysWithValues: segments.map { segment in
            let rect = CGRect(x: x, y: 0, width: Double(segment.text.count) * 10, height: 20)
            x += rect.width
            return (segment.id, rect)
        })
    }

    private func plan(_ text: String = "abc", duration: Double = 1,
                      entrance: TextMorphConfiguration.Entrance = .init()) -> [MorphTrajectory] {
        let diff = TextMatcher.diff(from: [], to: text).preparingEntrance(entrance)
        return MorphMotion.plan(diff: diff, oldRects: [:], newRects: rects(diff.segments),
                                previous: [], now: 0, curve: MorphCurve(.easeOut(duration: duration)),
                                lineHeight: 20, scaleExits: true, entrance: entrance)
    }

    func testDefaultBlurClearsAlongsideFadeAndCanBeDisabled() {
        let item = plan().first!
        XCTAssertEqual(item.presentation(at: 0).blur, 2)
        XCTAssertEqual(item.presentation(at: 0.5).opacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(item.presentation(at: 0.5).blur, 1, accuracy: 0.0001)
        XCTAssertEqual(item.presentation(at: 1).blur, 0)
        XCTAssertEqual(item.presentation(at: 1).opacity, 1)
        let legacy = plan(entrance: .init(blurRadius: 0))
        XCTAssertTrue(legacy.allSatisfy { $0.entrance == nil && $0.presentation(at: 0.5).blur == 0 })
    }

    func testStaggerSpreadsCharacterEntrancesWithinTheAnimation() {
        let items = plan(entrance: .init(blurRadius: 8, stagger: 0.5))
        XCTAssertGreaterThan(items[0].presentation(at: 0.3).opacity, items[1].presentation(at: 0.3).opacity)
        XCTAssertEqual(items[2].presentation(at: 0.3).opacity, 0)
        XCTAssertLessThan(items[0].presentation(at: 0.3).blur, items[2].presentation(at: 0.3).blur)
        for item in items {
            XCTAssertLessThanOrEqual(item.entrance!.fade.delay + item.entrance!.fade.share, 1)
            XCTAssertEqual(item.presentation(at: 1).opacity, 1)
            XCTAssertEqual(item.presentation(at: 1).blur, 0)
            XCTAssertEqual(item.endTime, 1)
        }
    }

    func testStaggerScalesWithDurationAndSupportsNativeCurves() {
        let effect = TextMorphConfiguration.Entrance(stagger: 0.6, staggerCurve: .easeIn)
        let short = plan(duration: 0.4, entrance: effect)
        let long = plan(duration: 2, entrance: effect)
        let linear = plan(entrance: .init(stagger: 0.6))
        XCTAssertLessThan(short[1].entrance!.fade.delay, linear[1].entrance!.fade.delay)
        for (a, b) in zip(short, long) {
            XCTAssertEqual(a.presentation(at: 0.2).opacity, b.presentation(at: 1).opacity, accuracy: 0.0001)
            XCTAssertEqual(a.presentation(at: 0.2).blur, b.presentation(at: 1).blur, accuracy: 0.0001)
        }
        let custom = TextMorphConfiguration.Entrance(stagger: 0.5, staggerCurve: .bezier(
            startControlPoint: .init(x: 0.2, y: 0), endControlPoint: .init(x: 0.8, y: 1)))
        XCTAssertTrue(plan(entrance: custom).allSatisfy { $0.presentation(at: 0.5).blur.isFinite })
    }

    func testBlurStaggerCanBeTunedIndependently() {
        let items = plan(entrance: .init(blurRadius: 6, stagger: 0.5, blurStagger: 0))
        XCTAssertNotEqual(items[0].presentation(at: 0.5).opacity, items[2].presentation(at: 0.5).opacity)
        XCTAssertEqual(items[0].presentation(at: 0.5).blur, items[2].presentation(at: 0.5).blur)
    }

    func testOnlyInsertedWordsSplitAndGraphemesRemainWhole() {
        let old = TextMatcher.segment("hello world")
        let raw = TextMatcher.diff(from: old, to: "hello world 👨‍👩‍👧‍👦👍🏽")
        let split = raw.preparingEntrance(.init(stagger: 0.3))
        XCTAssertEqual(split.segments.first { $0.id == "hello" }?.text, "hello")
        XCTAssertEqual(split.segments.first { $0.id == "world" }?.text, "world")
        XCTAssertTrue(split.segments.contains { $0.text == "👨‍👩‍👧‍👦" })
        XCTAssertTrue(split.segments.contains { $0.text == "👍🏽" })
        XCTAssertEqual(Set(split.segments.map(\.id)).count, split.segments.count)
        XCTAssertEqual(raw.preparingEntrance(.init(stagger: 0)).segments, raw.segments)
    }

    func testWhitespaceDoesNotConsumeStaggerSlots() {
        let items = plan("a b", entrance: .init(stagger: 0.5))
        let visible = items.filter { !$0.segment.text.allSatisfy(\.isWhitespace) }
        XCTAssertEqual(visible.count, 2)
        XCTAssertEqual(visible.first!.entrance!.fade.delay, 0.125)
        XCTAssertEqual(visible.last!.entrance!.fade.delay, 0.625)
        XCTAssertNil(items.first { $0.segment.text.allSatisfy(\.isWhitespace) }?.entrance)
    }

    func testInterruptedEntranceKeepsBlurFadeAndPendingDelays() {
        let effect = TextMorphConfiguration.Entrance(blurRadius: 8, stagger: 0.6)
        let first = plan(entrance: effect)
        let segments = first.map(\.segment)
        let diff = TextMatcher.diff(from: segments, to: "abcd").preparingEntrance(effect)
        let next = MorphMotion.plan(diff: diff, oldRects: rects(diff.preparedPrevious), newRects: rects(diff.segments),
                                    previous: first, now: 0.1, curve: MorphCurve(.easeOut(duration: 1)),
                                    lineHeight: 20, scaleExits: true, entrance: effect)
        for before in first {
            let after = next.first { $0.id == before.id && !$0.exiting }!
            for time in [0.1, 0.2, 0.4, 0.7, 1] {
                XCTAssertEqual(before.presentation(at: time).blur, after.presentation(at: time).blur, accuracy: 0.0001)
                XCTAssertEqual(before.presentation(at: time).opacity, after.presentation(at: time).opacity, accuracy: 0.0001)
            }
        }
    }

    func testInvalidValuesSingleCharacterAndZeroDurationRemainFinite() {
        for effect in [TextMorphConfiguration.Entrance(blurRadius: -.infinity, stagger: .nan),
                       .init(blurRadius: .nan, stagger: -.infinity), .init(blurRadius: 1000, stagger: 10)] {
            for item in plan(entrance: effect) {
                for time in [0.0, 0.5, 1] {
                    XCTAssertTrue(item.presentation(at: time).blur.isFinite)
                    XCTAssertTrue(item.presentation(at: time).opacity.isFinite)
                }
                XCTAssertEqual(item.presentation(at: 1).blur, 0)
            }
        }
        XCTAssertEqual(plan("a", entrance: .init(stagger: 0.9))[0].entrance!.fade.delay, 0.25)
        let immediate = plan(duration: 0, entrance: .init(stagger: 0.9))
        XCTAssertTrue(immediate.allSatisfy { $0.presentation(at: 0).opacity == 1 && $0.presentation(at: 0).blur == 0 })
    }
}
