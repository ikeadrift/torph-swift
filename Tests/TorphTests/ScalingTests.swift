import XCTest
@testable import Torph

final class ScalingTests: XCTestCase {
    private func plan(_ before: String = "abcdef", _ after: String = "UVWXYZ",
                      effects: TextMorphConfiguration.Effects = .standard,
                      previous: [MorphTrajectory] = [], now: Double = 0) -> [MorphTrajectory] {
        let old = previous.isEmpty ? TextMatcher.segment(before, numbers: false) : previous.filter { !$0.exiting }.map(\.segment)
        let diff = TextMatcher.diff(from: old, to: after, numbers: false)
        func rects(_ segments: [MorphSegment]) -> [String: CGRect] {
            Dictionary(uniqueKeysWithValues: segments.enumerated().map { ($0.element.id, CGRect(x: $0.offset*10,y: 0,width: 10,height: 20)) })
        }
        return MorphMotion.plan(diff: diff,oldRects: rects(diff.preparedPrevious),newRects: rects(diff.segments),
                                previous: previous,now: now,curve: MorphCurve(.easeOut(duration: 1)),lineHeight: 20,
                                effects: effects)
    }

    func testIndependentExitScalingForOrdinaryAndGroupedReplacements() {
        let effects = TextMorphConfiguration.Effects(
            entrance: .init(scale: 0.9), exit: .init(scale: 1),
            replacementScaling: .grouped(entrance: 0.7, exit: 1))
        for pair in [("abcdef","UVWXYZ"),("a","Z")] {
            let items = plan(pair.0,pair.1,effects: effects)
            let exits = items.filter(\.exiting)
            XCTAssertFalse(exits.isEmpty)
            for item in exits { XCTAssertEqual(item.end.scale,1) }
            XCTAssertTrue(items.filter { !$0.exiting }.allSatisfy { $0.start.scale < 1 })
        }
    }

    func testFadeAndBlurPresetKeepsScaleConstantThroughoutMotion() {
        for item in plan(effects: .fadeAndBlur(blurRadius: 8)) {
            for time in [0.0,0.1,0.3,0.5,1] { XCTAssertEqual(item.presentation(at: time).scale,1) }
        }
        let exit = plan(effects: .fadeAndBlur(blurRadius: 8)).first { $0.exiting }!
        XCTAssertEqual(exit.presentation(at: 0.225).blur,4,accuracy: 0.0001)
        XCTAssertEqual(exit.presentation(at: 0.225).opacity,0.5,accuracy: 0.0001)
        XCTAssertEqual(exit.presentation(at: 1).opacity,0)
    }

    func testIndividualAndGroupScaleFactorsAndOrigins() {
        let settings = TextMorphConfiguration.Effects(
            entrance: .init(scale: 0.9), exit: .init(scale: 0.7),
            replacementScaling: .grouped(entrance: 0.6, exit: 0.5))
        let grouped = plan(effects: settings)
        XCTAssertTrue(grouped.filter { !$0.exiting }.allSatisfy { $0.start.scale == 0.6 })
        XCTAssertTrue(grouped.filter(\.exiting).allSatisfy { $0.end.scale == 0.5 })
        var individual = settings; individual.replacementScaling = .individual
        for item in plan(effects: individual) {
            XCTAssertEqual(item.start.origin, CGPoint(x: 0.5,y: 0.5))
            XCTAssertEqual(item.end.origin, CGPoint(x: 0.5,y: 0.5))
            XCTAssertEqual(item.exiting ? item.end.scale : item.start.scale,item.exiting ? 0.7 : 0.9)
        }
    }

    func testExitBlurContinuesFromInterruptedEntrance() {
        let entering = plan("a","b",effects: .fadeAndBlur())
        let prior = entering.first { !$0.exiting }!.presentation(at: 0.4)
        let exiting = plan("b","c",effects: .fadeAndBlur(blurRadius: 10),previous: entering,now: 0.4)
            .first { $0.exiting && $0.segment.text == "b" }!
        XCTAssertEqual(exiting.presentation(at: 0.4).blur,prior.blur,accuracy: 0.0001)
        XCTAssertEqual(exiting.presentation(at: 0.4).opacity,prior.opacity,accuracy: 0.0001)
        XCTAssertEqual(exiting.presentation(at: 0.65).blur,10,accuracy: 0.0001)
    }

    func testInvalidScalingAndBlurValuesStayFinite() {
        for replacement: TextMorphConfiguration.ReplacementScaling in [.individual, .grouped(entrance: .infinity, exit: .nan)] {
            let effects = TextMorphConfiguration.Effects(
                entrance: .init(scale: .nan, blurRadius: .infinity),
                exit: .init(scale: -.infinity, blurRadius: .nan), replacementScaling: replacement)
            for item in plan(effects: effects) {
                for time in [0.0,0.25,1] {
                    XCTAssertTrue(item.presentation(at: time).scale.isFinite)
                    XCTAssertTrue(item.presentation(at: time).blur.isFinite)
                }
            }
        }
    }

    func testPresetsHaveDistinctRenderedBehaviorAndComposeWithCustomSettings() {
        let standard = plan()
        XCTAssertEqual(standard.first { !$0.exiting }!.start.scale, 0.8)
        XCTAssertEqual(standard.first { !$0.exiting }!.presentation(at: 0).blur, 2)
        XCTAssertEqual(standard.first { $0.exiting }!.end.blur, 0)
        for preset in [TextMorphConfiguration.Effects.fade, .fadeAndBlur()] {
            let items = plan(effects: preset)
            for item in items {
                XCTAssertEqual(item.start.scale, 1)
                XCTAssertEqual(item.end.scale, 1)
                XCTAssertEqual(item.presentation(at: 1).blur, item.exiting ? preset.exit.blurRadius : 0)
            }
            XCTAssertEqual(items.first { !$0.exiting }!.presentation(at: 0).blur, preset.entrance.blurRadius)
        }
        var custom = TextMorphConfiguration.Effects.fadeAndBlur()
        custom.exit.scale = 0.7
        let customized = plan(effects: custom)
        XCTAssertTrue(customized.filter(\.exiting).allSatisfy { $0.end.scale == 0.7 })
        XCTAssertTrue(customized.filter { !$0.exiting }.allSatisfy { $0.start.scale == 1 })
    }
}
