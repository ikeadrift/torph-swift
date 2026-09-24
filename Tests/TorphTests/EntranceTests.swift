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
        let diff = TextMatcher.diff(from: [], to: text)
        return MorphMotion.plan(diff: diff, oldRects: [:], newRects: rects(diff.segments),
                                previous: [], now: 0, curve: MorphCurve(.easeOut(duration: duration)),
                                lineHeight: 20, effects: .init(entrance: entrance))
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

    func testInterruptedEntranceKeepsBlurAndFade() {
        let effect = TextMorphConfiguration.Entrance(blurRadius: 8)
        let first = plan(entrance: effect)
        let segments = first.map(\.segment)
        let diff = TextMatcher.diff(from: segments, to: "abcd")
        let next = MorphMotion.plan(diff: diff, oldRects: rects(diff.preparedPrevious), newRects: rects(diff.segments),
                                    previous: first, now: 0.1, curve: MorphCurve(.easeOut(duration: 1)),
                                    lineHeight: 20, effects: .init(entrance: effect))
        for before in first {
            let after = next.first { $0.id == before.id && !$0.exiting }!
            for time in [0.1, 0.2, 0.4, 0.7, 1] {
                XCTAssertEqual(before.presentation(at: time).blur, after.presentation(at: time).blur, accuracy: 0.0001)
                XCTAssertEqual(before.presentation(at: time).opacity, after.presentation(at: time).opacity, accuracy: 0.0001)
            }
        }
    }

    func testInvalidValuesSingleCharacterAndZeroDurationRemainFinite() {
        for effect in [TextMorphConfiguration.Entrance(blurRadius: -.infinity),
                       .init(blurRadius: .nan), .init(blurRadius: 1000)] {
            for item in plan(entrance: effect) {
                for time in [0.0, 0.5, 1] {
                    XCTAssertTrue(item.presentation(at: time).blur.isFinite)
                    XCTAssertTrue(item.presentation(at: time).opacity.isFinite)
                }
                XCTAssertEqual(item.presentation(at: 1).blur, 0)
            }
        }
        XCTAssertEqual(plan("a")[0].entrance!.fade.delay, 0.25)
        let immediate = plan(duration: 0)
        XCTAssertTrue(immediate.allSatisfy { $0.presentation(at: 0).opacity == 1 && $0.presentation(at: 0).blur == 0 })
    }
}
