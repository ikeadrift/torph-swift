import SwiftUI
import XCTest
@testable import Torph

final class BlurCurveTests: XCTestCase {
    private func plan(_ before: String, _ after: String, effects: TextMorphConfiguration.Effects,
                      previous: [MorphTrajectory] = [], now: Double = 0) -> [MorphTrajectory] {
        let old = previous.isEmpty ? TextMatcher.segment(before) : previous.filter { !$0.exiting }.map(\.segment)
        let diff = TextMatcher.diff(from: old, to: after)
        func rects(_ segments: [MorphSegment]) -> [String: CGRect] {
            var x = 0.0
            return Dictionary(uniqueKeysWithValues: segments.map { segment in
                let rect = CGRect(x: x, y: 0, width: Double(segment.text.count) * 10, height: 20)
                x += rect.width
                return (segment.id, rect)
            })
        }
        return MorphMotion.plan(diff: diff, oldRects: rects(diff.preparedPrevious), newRects: rects(diff.segments),
                                previous: previous, now: now, curve: MorphCurve(.easeOut(duration: 1)),
                                lineHeight: 20, effects: effects)
    }

    func testEntranceAndExitCurvesAreIndependentOfOpacityAndMovement() {
        let effects = TextMorphConfiguration.Effects(
            entrance: .init(blurRadius: 8, blurCurve: .easeIn),
            exit: .init(blurRadius: 10, blurCurve: .easeOut))
        let custom = plan("a", "b", effects: effects)
        var linear = effects
        linear.entrance.blurCurve = .linear
        linear.exit.blurCurve = .linear
        let baseline = plan("a", "b", effects: linear)
        for (actual, expected) in zip(custom, baseline) {
            for time in [0.0, 0.05, 0.125, 0.375, 0.5, 0.75, 1] {
                let a = actual.presentation(at: time), b = expected.presentation(at: time)
                XCTAssertEqual(a.opacity, b.opacity)
                XCTAssertEqual(a.rect, b.rect)
                XCTAssertEqual(a.scale, b.scale)
                XCTAssertEqual(a.slide, b.slide)
            }
        }
        let entering = custom.first { !$0.exiting }!
        XCTAssertEqual(entering.presentation(at: 0.375).blur, 8 * (1 - UnitCurve.easeIn.value(at: 0.25)), accuracy: 0.000001)
        let exiting = custom.first { $0.exiting }!
        XCTAssertEqual(exiting.presentation(at: 0.0625).blur, 10 * UnitCurve.easeOut.value(at: 0.25), accuracy: 0.000001)
    }

    func testCustomBezierUsesEachKindsExistingFadeWindow() {
        let bezier = UnitCurve.bezier(startControlPoint: .init(x: 0.25, y: 0.1), endControlPoint: .init(x: 0.75, y: 0.9))
        for pair in [("a", "b"), ("abcdef", "UVWXYZ"), ("1", "2")] {
            let items = plan(pair.0, pair.1, effects: .fadeAndBlur(blurRadius: 8, blurCurve: bezier))
            for item in items {
                let time = item.fadeDelay + item.fadeShare * 0.3
                let progress = bezier.value(at: 0.3)
                XCTAssertEqual(item.presentation(at: time).blur, item.exiting ? 8 * progress : 8 * (1 - progress), accuracy: 0.000001)
                XCTAssertEqual(item.presentation(at: 0).blur, item.exiting ? 0 : 8)
                XCTAssertEqual(item.presentation(at: 1).blur, item.exiting ? 8 : 0)
            }
        }
    }

    func testSplittingAnInterruptedEntrancePreservesItsOriginalBlurCurve() {
        let first = plan("hello there", "hello world", effects: .fadeAndBlur(blurRadius: 8, blurCurve: .easeIn))
        let parent = first.first { $0.segment.text == "world" }!
        let second = plan("hello world", "hello worlds", effects: .fadeAndBlur(blurRadius: 8, blurCurve: .easeOut), previous: first, now: 0.4)
        let child = second.first { $0.segment.text == "w" && !$0.exiting }!
        for time in [0.4, 0.5, 0.6, 0.75, 1] {
            XCTAssertEqual(child.presentation(at: time).blur, parent.presentation(at: time).blur, accuracy: 0.000001)
            XCTAssertEqual(child.presentation(at: time).opacity, parent.presentation(at: time).opacity, accuracy: 0.000001)
        }
    }

    func testCurvedExitStartsAtCurrentBlurAndSurvivesAnotherUpdate() {
        let first = plan("a", "b", effects: .fadeAndBlur(blurRadius: 8, blurCurve: .easeIn))
        let entered = first.first { !$0.exiting }!
        let second = plan("b", "c", effects: .fadeAndBlur(blurRadius: 10, blurCurve: .easeOut), previous: first, now: 0.4)
        let exit = second.first { $0.segment.text == "b" && $0.exiting }!
        let initial = entered.presentation(at: 0.4).blur
        XCTAssertEqual(exit.presentation(at: 0.4).blur, initial, accuracy: 0.000001)
        XCTAssertEqual(exit.presentation(at: 0.4625).blur, initial + (10 - initial) * UnitCurve.easeOut.value(at: 0.25), accuracy: 0.000001)
        let third = plan("c", "d", effects: .fade, previous: second, now: 0.45)
        let retained = third.first { $0.segment.text == "b" && $0.exiting }!
        for time in [0.45, 0.5, 0.6, 0.65] {
            XCTAssertEqual(retained.presentation(at: time).blur, exit.presentation(at: time).blur)
        }
    }

    func testOvershootingBezierKeepsBlurWithinItsEndpoints() {
        let bezier = UnitCurve.bezier(startControlPoint: .init(x: 0.2, y: -0.5), endControlPoint: .init(x: 0.8, y: 1.5))
        for item in plan("a", "b", effects: .fadeAndBlur(blurRadius: 8, blurCurve: bezier)) {
            for step in 0...100 {
                let blur = item.presentation(at: Double(step) / 100).blur
                XCTAssertTrue(blur.isFinite)
                XCTAssertGreaterThanOrEqual(blur, 0)
                XCTAssertLessThanOrEqual(blur, 8)
            }
        }
    }
}
