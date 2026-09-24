import XCTest
@testable import Torph
final class StaggerRegressionTests: XCTestCase {
    func rects(_ segments: [MorphSegment]) -> [String: CGRect] {
        var x = 0.0
        return Dictionary(uniqueKeysWithValues: segments.map { s in
            defer { x += Double(s.text.count)*10 }
            return (s.id, CGRect(x: x,y: 0,width: Double(s.text.count)*10,height: 20))
        })
    }
    func testStaggerFollowsTextOrderAcrossGroupBoundary() {
        let entrance = TextMorphConfiguration.Entrance(stagger: 0.25)
        let old = TextMatcher.segment("Keep this")
        let diff = TextMatcher.diff(from: old,to: "a Keep this elephant").preparingEntrance(entrance)
        let plan = MorphMotion.plan(diff: diff,oldRects: rects(diff.preparedPrevious),newRects: rects(diff.segments),previous: [],now: 0,curve: MorphCurve(.easeOut(duration: 1)),lineHeight: 20,scaleExits: true,entrance: entrance)
        let visible = plan.filter { !$0.exiting && $0.entrance != nil }
        for (a,b) in zip(visible,visible.dropFirst()) {
            XCTAssertLessThanOrEqual(a.entrance!.fade.delay,b.entrance!.fade.delay,"Later characters should not enter before earlier characters with linear stagger")
        }
    }
    func testStaggerDoesNotDiscardEnteringWordsAnchorMovement() {
        let old = TextMatcher.segment("greetings world")
        let raw = TextMatcher.diff(from: old,to: "world elephant")
        func make(_ effect: TextMorphConfiguration.Entrance) -> [MorphTrajectory] {
            let diff = raw.preparingEntrance(effect)
            return MorphMotion.plan(diff: diff,oldRects: rects(diff.preparedPrevious),newRects: rects(diff.segments),previous: [],now: 0,curve: MorphCurve(.easeOut(duration: 1)),lineHeight: 20,scaleExits: true,entrance: effect)
        }
        let plain = make(.init()).first { !$0.exiting && $0.segment.text == "elephant" }!
        let staggered = make(.init(stagger: 0.25)).first { !$0.exiting && $0.segment.text == "e" }!
        XCTAssertEqual(plain.start.rect.minX-plain.end.rect.minX,staggered.start.rect.minX-staggered.end.rect.minX,accuracy: 0.001,"Enabling fade stagger should not remove the entering word's positional anchor")
    }

    func testFadeAndBlurOrderAcrossTextAndNumbers() {
        for effect in [TextMorphConfiguration.Entrance(stagger: 0.25), .init(stagger: 0, blurStagger: 0.25), .init(stagger: 0.4, blurStagger: 0.2)] {
            let old = TextMatcher.segment("Keep this")
            let diff = TextMatcher.diff(from: old,to: "a Keep this 123").preparingEntrance(effect)
            let plan = MorphMotion.plan(diff: diff,oldRects: rects(diff.preparedPrevious),newRects: rects(diff.segments),previous: [],now: 0,curve: MorphCurve(.easeOut(duration: 1)),lineHeight: 20,scaleExits: true,entrance: effect)
            let tracks = plan.filter { !$0.exiting }.compactMap(\.entrance)
            for (a,b) in zip(tracks,tracks.dropFirst()) {
                if effect.fadeSpread > 0 { XCTAssertLessThanOrEqual(a.fade.delay,b.fade.delay) }
                if effect.blurSpread > 0 { XCTAssertLessThanOrEqual(a.blur.delay,b.blur.delay) }
            }
            if effect.fadeSpread > 0 { XCTAssertEqual(tracks.last!.fade.delay-tracks.first!.fade.delay,effect.fadeSpread,accuracy: 0.000001) }
            if effect.blurSpread > 0 { XCTAssertEqual(tracks.last!.blur.delay-tracks.first!.blur.delay,effect.blurSpread,accuracy: 0.000001) }
        }
    }

    func testGenuineReplacementGroupsSurviveStaggerPreparation() {
        let old = TextMatcher.segment("Keep this")
        let raw = TextMatcher.diff(from: old,to: "Keep this one two three four five six")
        let prepared = raw.preparingEntrance(.init(stagger: 0.3))
        let groups = MorphMotion.groups(prepared.segments, members: Set(prepared.inserted.map(\.id)), logicalOrigins: prepared.entranceParents)
        XCTAssertEqual(groups.count,1)
        XCTAssertTrue(groups[0].contains(prepared.segments.last!.id))
    }

}
