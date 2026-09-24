import XCTest
@testable import Torph

final class InterruptionRegressionTests: XCTestCase {
    private let curve = MorphCurve(.easeOut(duration: 1))
    private func rects(_ segments: [MorphSegment]) -> [String: CGRect] {
        var x = 0.0
        return Dictionary(uniqueKeysWithValues: segments.map { segment in
            let rect = CGRect(x: x, y: 0, width: Double(segment.text.count) * 10, height: 20)
            x += rect.width
            return (segment.id, rect)
        })
    }
    func testSplittingAMovingWordPreservesItsPresentedPosition() {
        let initial = TextMatcher.segment("hello world")
        let first = TextMatcher.diff(from: initial, to: "world hello")
        let firstPlan = MorphMotion.plan(diff: first, oldRects: rects(first.preparedPrevious), newRects: rects(first.segments), previous: [], now: 0, curve: curve, lineHeight: 20)
        let now = 0.05
        let world = firstPlan.first { $0.id == "world" }!
        let second = TextMatcher.diff(from: first.segments, to: "worlds hello")
        XCTAssertNotNil(second.splits["world"])
        let secondPlan = MorphMotion.plan(diff: second, oldRects: rects(second.preparedPrevious), newRects: rects(second.segments), previous: firstPlan, now: now, curve: curve, lineHeight: 20)
        let w = secondPlan.first { $0.id == "world:0" }!
        XCTAssertEqual(w.presentation(at: now).rect.minX, world.presentation(at: now).rect.minX, accuracy: 0.0001, "Splitting a moving word should not jump its first character")
        let d = secondPlan.first { $0.id == "world:4" }!
        let s = secondPlan.first { $0.segment.text == "s" && !$0.exiting }!
        XCTAssertEqual(s.start.rect.minX - d.start.rect.minX, 10, accuracy: 0.0001,
                       "A new character must anchor to the moving character, not its layout endpoint")
    }

    func testSplittingAnEnteringWordPreservesBlurAndFade() {
        let old = TextMatcher.segment("hello there")
        let first = TextMatcher.diff(from: old, to: "hello world")
        let firstPlan = MorphMotion.plan(diff: first, oldRects: rects(first.preparedPrevious), newRects: rects(first.segments),
                                         previous: [], now: 0, curve: curve, lineHeight: 20)
        let word = firstPlan.first { $0.segment.text == "world" }!
        let second = TextMatcher.diff(from: first.segments, to: "hello worlds")
        let secondPlan = MorphMotion.plan(diff: second, oldRects: rects(second.preparedPrevious), newRects: rects(second.segments),
                                          previous: firstPlan, now: 0.1, curve: curve, lineHeight: 20)
        let child = secondPlan.first { $0.id == "world:0" }!
        for time in [0.1, 0.3, 0.5, 0.8, 1] {
            XCTAssertEqual(child.presentation(at: time).opacity, word.presentation(at: time).opacity, accuracy: 0.0001)
            XCTAssertEqual(child.presentation(at: time).blur, word.presentation(at: time).blur, accuracy: 0.0001)
        }
    }
    func testWidthCompletionDoesNotMeanHeightHasFinished() {
        let first = MorphSizeMotion(from: .init(width: 100, height: 20), to: .init(width: 200, height: 20), previous: nil, now: 0, curve: curve, hold: false)
        let second = MorphSizeMotion(from: first.size(at: 0.8), to: .init(width: 200, height: 80), previous: first, now: 0.8, curve: curve, hold: false)
        let completion = second.width.began + second.width.curve.duration
        XCTAssertEqual(completion, 1)
        XCTAssertEqual(second.height.began + second.height.curve.duration, 1.8)
        let beforeClearing = second.size(at: completion).height
        let retained = second.retained(after: completion)
        XCTAssertNotNil(retained)
        XCTAssertEqual(beforeClearing, retained!.size(at: completion).height, accuracy: 0.0001)
        XCTAssertEqual(retained!.size(at: second.endTime).height, 80, accuracy: 0.0001)
        XCTAssertNil(second.retained(after: second.endTime))
    }
}
