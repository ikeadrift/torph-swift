import XCTest
@testable import Torph

final class ScalingTests: XCTestCase {
    private func plan(_ before: String = "abcdef", _ after: String = "UVWXYZ",
                      scaling: TextMorphConfiguration.Scaling = .init(), enabled: Bool = true,
                      blur: CGFloat = 0, previous: [MorphTrajectory] = [], now: Double = 0) -> [MorphTrajectory] {
        let old = previous.isEmpty ? TextMatcher.segment(before, numbers: false) : previous.filter { !$0.exiting }.map(\.segment)
        let diff = TextMatcher.diff(from: old, to: after, numbers: false)
        func rects(_ segments: [MorphSegment]) -> [String: CGRect] {
            Dictionary(uniqueKeysWithValues: segments.enumerated().map { ($0.element.id, CGRect(x: $0.offset*10,y: 0,width: 10,height: 20)) })
        }
        return MorphMotion.plan(diff: diff,oldRects: rects(diff.preparedPrevious),newRects: rects(diff.segments),
                                previous: previous,now: now,curve: MorphCurve(.easeOut(duration: 1)),lineHeight: 20,
                                scaleExits: enabled,scaling: scaling,exitBlurRadius: blur)
    }

    func testLegacyScaleFalseDisablesGroupedAndIndividualExits() {
        for pair in [("abcdef","UVWXYZ"),("a","Z")] {
            let exits = plan(pair.0,pair.1,enabled: false).filter(\.exiting)
            XCTAssertFalse(exits.isEmpty)
            for item in exits { XCTAssertEqual(item.end.scale,1) }
        }
    }

    func testNoScalingKeepsSizeConstantThroughoutFadeAndBlur() {
        for item in plan(scaling: .none,blur: 8) {
            for time in [0.0,0.1,0.3,0.5,1] { XCTAssertEqual(item.presentation(at: time).scale,1) }
        }
        let exit = plan(scaling: .none,blur: 8).first { $0.exiting }!
        XCTAssertEqual(exit.presentation(at: 0.225).blur,4,accuracy: 0.0001)
        XCTAssertEqual(exit.presentation(at: 0.225).opacity,0.5,accuracy: 0.0001)
        XCTAssertEqual(exit.presentation(at: 1).opacity,0)
    }

    func testIndividualAndGroupScaleFactorsAndOrigins() {
        let settings = TextMorphConfiguration.Scaling(entrance: 0.9,exit: 0.7,groupedEntrance: 0.6,groupedExit: 0.5)
        let grouped = plan(scaling: settings)
        XCTAssertTrue(grouped.filter { !$0.exiting }.allSatisfy { $0.start.scale == 0.6 })
        XCTAssertTrue(grouped.filter(\.exiting).allSatisfy { $0.end.scale == 0.5 })
        var individual = settings; individual.groupReplacements = false
        for item in plan(scaling: individual) {
            XCTAssertEqual(item.start.origin, CGPoint(x: 0.5,y: 0.5))
            XCTAssertEqual(item.end.origin, CGPoint(x: 0.5,y: 0.5))
            XCTAssertEqual(item.exiting ? item.end.scale : item.start.scale,item.exiting ? 0.7 : 0.9)
        }
    }

    func testExitBlurContinuesFromInterruptedEntrance() {
        let entering = plan("a","b",scaling: .none)
        let prior = entering.first { !$0.exiting }!.presentation(at: 0.4)
        let exiting = plan("b","c",scaling: .none,blur: 10,previous: entering,now: 0.4).first { $0.exiting && $0.segment.text == "b" }!
        XCTAssertEqual(exiting.presentation(at: 0.4).blur,prior.blur,accuracy: 0.0001)
        XCTAssertEqual(exiting.presentation(at: 0.4).opacity,prior.opacity,accuracy: 0.0001)
        XCTAssertEqual(exiting.presentation(at: 0.65).blur,10,accuracy: 0.0001)
    }

    func testInvalidScalingAndBlurValuesStayFinite() {
        for item in plan(scaling: .init(entrance: .nan,exit: -.infinity,groupedEntrance: .infinity,groupedExit: .nan),blur: .nan) {
            for time in [0.0,0.25,1] {
                XCTAssertTrue(item.presentation(at: time).scale.isFinite)
                XCTAssertTrue(item.presentation(at: time).blur.isFinite)
            }
        }
    }
}
