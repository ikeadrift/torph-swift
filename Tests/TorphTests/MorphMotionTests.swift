import XCTest
import SwiftUI
@testable import Torph

final class MorphMotionTests: XCTestCase {
    func testNativeSpringsUseSwiftUISolver() {
        let springs: [Spring] = [.smooth, .snappy, .bouncy, Spring(duration: 0.3, bounce: 0.2), Spring(response: 0.4, dampingRatio: 0.75), Spring(mass: 2, stiffness: 240, damping: 40)]
        for spring in springs {
            for velocity in [0.0, 1.5] {
                let curve = MorphCurve(.spring(spring, initialVelocity: velocity))
                XCTAssertEqual(curve.duration, spring.settlingDuration(target: 1.0, initialVelocity: velocity, epsilon: 0.001), accuracy: 0.000001)
                for fraction in [0.1, 0.3, 0.5, 0.8] {
                    XCTAssertEqual(curve.value(fraction), spring.value(target: 1.0, initialVelocity: velocity, time: fraction*curve.duration), accuracy: 0.000001)
                }
                XCTAssertEqual(curve.value(1), 1)
            }
        }
    }

    func testDefaultSpringRespondsAndSettlesFaster() {
        let old = MorphCurve(.spring(mass: 1, stiffness: 100, damping: 10))
        let current = MorphCurve(.spring())
        XCTAssertLessThan(current.duration, old.duration*0.5)
        XCTAssertGreaterThan(current.value(0.2/current.duration), 0.9)
    }

    let curve = MorphCurve(.easeOut(duration: 1))
    func positions(_ segments: [MorphSegment]) -> [String: CGRect] {
        var x = 0.0
        return Dictionary(uniqueKeysWithValues: segments.map { s in
            let rect = CGRect(x: x,y: 0,width: Double(s.text.count)*10,height: 20)
            x += rect.width; return (s.id,rect)
        })
    }
    func testNewCapitalTTravelsWithTransactionNotProcessing() {
        let diff = TextMatcher.diff(from: TextMatcher.segment("Processing transaction"),to: "Transaction complete")
        let before = positions(diff.preparedPrevious), after = positions(diff.segments)
        let motion = MorphMotion.plan(diff: diff,oldRects: before,newRects: after,previous: [],now: 0,curve: curve,lineHeight: 20,scaleExits: true)
        let t = motion.first { $0.segment.text == "T" }!
        let r = motion.first { $0.segment.id == "transaction:1" }!
        XCTAssertEqual(t.start.rect.minX,before["transaction:0"]!.minX)
        XCTAssertNotEqual(t.start.rect.minX,before["Processing"]!.minX)
        for time in [0.0,0.1,0.25,0.5,0.75,1] {
            XCTAssertEqual(r.presentation(at: time).rect.minX-t.presentation(at: time).rect.minX,10,accuracy: 0.0001)
        }
        XCTAssertEqual(t.presentation(at: 0.25).opacity,0)
        XCTAssertEqual(t.presentation(at: 0.5).opacity,0.5)
        XCTAssertEqual(t.presentation(at: 0.75).opacity,1)
        let processing = motion.filter { $0.segment.text == "Processing" }
        XCTAssertEqual(processing.count,1)
        XCTAssertTrue(processing[0].exiting)
        XCTAssertEqual(processing[0].end.scale,0.95)
    }
    func testAnchorSearchUsesDirectionPriorityNotDistance() {
        let ids = ["a","b","c","d","e"]
        XCTAssertEqual(MorphMotion.anchor(at: 3,ids: ids,persistent: ["a","e"]),"a")
        XCTAssertEqual(MorphMotion.anchor(at: 1,ids: ids,persistent: ["a","e"],forwardFirst: true),"e")
    }
    func testReplacementGroupsRequireSixAdjacentSegments() {
        let old = TextMatcher.segment("abcdef",numbers: false)
        XCTAssertEqual(MorphMotion.groups(old,members: Set(old.map(\.id))).count,1)
        XCTAssertTrue(MorphMotion.groups(old,members: Set(old.dropFirst().map(\.id))).isEmpty)
        let diff = TextMatcher.diff(from: old,to: "UVWXYZ",numbers: false)
        let plan = MorphMotion.plan(diff: diff,oldRects: positions(old),newRects: positions(diff.segments),previous: [],now: 0,curve: curve,lineHeight: 20,scaleExits: true)
        XCTAssertTrue(plan.filter { $0.exiting }.allSatisfy { $0.end.scale == 0.8 && $0.fadeShare == 0.45 })
        XCTAssertTrue(plan.filter { !$0.exiting }.allSatisfy { $0.start.scale == 0.8 && $0.fadeShare == 0.35 })
        for item in plan where !item.exiting {
            XCTAssertEqual(item.end.rect.minX+item.end.rect.width*item.end.origin.x,30,accuracy: 0.001)
        }
    }
    func testNumericReplacementSlidesAndNeverChangesSurvivorText() {
        let old = TextMatcher.segment("123")
        let diff = TextMatcher.diff(from: old,to: "124")
        let plan = MorphMotion.plan(diff: diff,oldRects: positions(old),newRects: positions(diff.segments),previous: [],now: 0,curve: curve,lineHeight: 20,scaleExits: true)
        XCTAssertEqual(plan.first { $0.segment.text == "4" }?.start.slide,-20)
        XCTAssertEqual(plan.first { $0.segment.text == "3" }?.end.slide,20)
        XCTAssertEqual(plan.first { $0.segment.text == "4" }?.fadeShare,0.25)
        XCTAssertEqual(plan.first { $0.segment.text == "3" }?.fadeShare,0.45)
        XCTAssertNotEqual(old.last?.id,diff.segments.last?.id)
    }
    func testInterruptedSurvivorContinuesFromPresentationPosition() {
        let old = TextMatcher.segment("hello world")
        let first = TextMatcher.diff(from: old,to: "world hello")
        let a = MorphMotion.plan(diff: first,oldRects: positions(old),newRects: positions(first.segments),previous: [],now: 0,curve: curve,lineHeight: 20,scaleExits: true)
        let second = TextMatcher.diff(from: first.segments,to: "hello world")
        let b = MorphMotion.plan(diff: second,oldRects: positions(first.segments),newRects: positions(second.segments),previous: a,now: 0.2,curve: curve,lineHeight: 20,scaleExits: true)
        XCTAssertEqual(b.first { $0.id == "hello" }!.start.rect,a.first { $0.id == "hello" }!.presentation(at: 0.2).rect)
    }
    func testContainerResumesSameTargetAndHoldsWhenEmpty() {
        let a = MorphSizeMotion(from: .init(width: 100,height: 20),to: .init(width: 200,height: 20),previous: nil,now: 0,curve: curve,hold: false)
        let b = MorphSizeMotion(from: a.size(at: 0.2),to: .init(width: 200,height: 20),previous: a,now: 0.2,curve: curve,hold: false)
        XCTAssertEqual(a.size(at: 0.5),b.size(at: 0.5))
        let hold = MorphSizeMotion(from: .init(width: 100,height: 20),to: .zero,previous: nil,now: 0,curve: curve,hold: true)
        XCTAssertEqual(hold.size(at: 0.7),CGSize(width: 100,height: 20))
    }
    func testRapidNumericUpdatesDoNotRestartAnEnteringDigitsFade() {
        let old = TextMatcher.segment("123")
        let first = TextMatcher.diff(from: old,to: "124")
        let initial = MorphMotion.plan(diff: first,oldRects: positions(old),newRects: positions(first.segments),previous: [],now: 0,curve: curve,lineHeight: 20,scaleExits: true)
        let digit = first.segments.last!.id
        let second = TextMatcher.diff(from: first.segments,to: "1240")
        let interrupted = MorphMotion.plan(diff: second,oldRects: positions(first.segments),newRects: positions(second.segments),previous: initial,now: 0.05,curve: curve,lineHeight: 20,scaleExits: true)
        let a = initial.first { $0.id == digit }!, b = interrupted.first { $0.id == digit && !$0.exiting }!
        for t in [0.05,0.10,0.20,0.25,0.5] {
            XCTAssertEqual(a.presentation(at: t).opacity,b.presentation(at: t).opacity,accuracy: 0.000001)
            XCTAssertEqual(a.presentation(at: t).slide,b.presentation(at: t).slide,accuracy: 0.000001)
        }
    }

    func testFortyInterruptedUpdatesPreserveSurvivorPositionsAndRetireExits() {
        var segments = TextMatcher.segment("Processing transaction")
        var motions: [MorphTrajectory] = []
        let values = ["Transaction complete","complete Transaction","$99","$100","","Back again","Processing transaction"]
        for index in 0..<40 {
            let now = Double(index)*0.06
            let diff = TextMatcher.diff(from: segments,to: values[index % values.count])
            let next = MorphMotion.plan(diff: diff,oldRects: positions(diff.preparedPrevious),newRects: positions(diff.segments),previous: motions,now: now,curve: curve,lineHeight: 20,scaleExits: true)
            for item in next where !item.exiting {
                if let before = motions.first(where: { !$0.exiting && $0.id == item.id }), diff.preparedPrevious.contains(where: { $0.id == item.id }) {
                    XCTAssertEqual(item.presentation(at: now).rect.origin,before.presentation(at: now).rect.origin)
                }
                XCTAssertTrue(item.presentation(at: now).rect.minX.isFinite)
            }
            XCTAssertEqual(next.filter { !$0.exiting }.map(\.segment),diff.segments)
            XCTAssertLessThan(next.count,200)
            segments = diff.segments; motions = next
        }
        XCTAssertTrue(motions.filter(\.exiting).allSatisfy { $0.presentation(at: 10).opacity == 0 })
    }

    func testCenteredContainerDoesNotJumpWhenRetargetedOrEmptied() {
        let ease = MorphCurve(.cubicBezier(x1: 0.42,y1: 0,x2: 0.58,y2: 1,duration: 1))
        var motion = MorphSizeMotion(from: .init(width: 90,height: 20),to: .init(width: 240,height: 20),previous: nil,now: 0,curve: ease,hold: false)
        for (i,target) in [160.0,160,300,80,0,180,180,120].enumerated() {
            let now = Double(i+1)*0.07, before = motion.size(at: now)
            let next = MorphSizeMotion(from: before,to: .init(width: target,height: 20),previous: motion,now: now,curve: ease,hold: target == 0)
            // A centered label's left edge is parentCenter - width/2.
            XCTAssertEqual(200-before.width/2,200-next.size(at: now).width/2,accuracy: 0.0001)
            XCTAssertTrue(next.size(at: now+0.01).width.isFinite)
            motion = next
        }
    }

    func testResumedContainerFinishesBeforeNewGlyphTimeline() {
        let first = MorphSizeMotion(from: .init(width: 100,height: 20),to: .init(width: 200,height: 20),previous: nil,now: 0,curve: curve,hold: false)
        let second = MorphSizeMotion(from: first.size(at: 0.8),to: .init(width: 200,height: 20),previous: first,now: 0.8,curve: curve,hold: false)
        XCTAssertEqual(second.width.began+second.width.curve.duration,1)
        // A fresh glyph still needs its complete duration (ends at 1.8).
        XCTAssertLessThan(second.width.began+second.width.curve.duration,0.8+curve.duration)
    }

}
