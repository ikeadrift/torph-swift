// Native implementation of Torph's FLIP anchors, grouped replacement, and fade/slide rules.
import Foundation
import SwiftUI
import CoreGraphics

struct MorphCurve: Sendable {
    var duration: Double
    var samples: [Double]?
    var nativeSpring: Spring?
    var initialVelocity = 0.0
    var bezier: [Double]
    init(_ timing: TextMorphConfiguration.Timing) {
        samples = nil; bezier = [0.19, 1, 0.22, 1]
        switch timing {
        case .easeOut(let seconds): duration = seconds.isFinite ? max(0, seconds) : 0.4
        case .cubicBezier(let x1,let y1,let x2,let y2,let seconds):
            duration = seconds.isFinite ? max(0,seconds) : 0.4
            bezier = [x1,y1,x2,y2].allSatisfy(\.isFinite) ? [min(1,max(0,x1)),y1,min(1,max(0,x2)),y2] : [0.19,1,0.22,1]
        case .nativeSpring(let spring, let velocity):
            nativeSpring = spring
            initialVelocity = velocity.isFinite ? velocity : 0
            let end = spring.settlingDuration(target: 1.0, initialVelocity: initialVelocity, epsilon: 0.001)
            duration = end.isFinite ? max(0, min(10, end)) : 10
        case .spring(let mass, let stiffness, let damping, let precision):
            let precision = precision.isFinite ? max(0.000001,precision) : 0.001
            let mass = mass.isFinite ? max(0.001, mass) : 1
            let stiffness = stiffness.isFinite ? max(0.001, stiffness) : 100
            let damping = damping.isFinite ? max(0.001, damping) : 10
            let omega = sqrt(stiffness / mass), zeta = damping / (2 * sqrt(stiffness * mass))
            func position(_ t: Double) -> Double {
                if abs(zeta - 1) < 1e-8 { return 1 - exp(-omega*t) * (1+omega*t) }
                if zeta < 1 {
                    let d = omega * sqrt(1-zeta*zeta)
                    return 1-exp(-zeta*omega*t)*(cos(d*t)+zeta*omega/d*sin(d*t))
                }
                let s = sqrt(zeta*zeta-1), r1 = -omega*(zeta+s), r2 = -omega*(zeta-s)
                let b = -r1/(r2-r1), a = 1-b
                return 1-a*exp(r1*t)-b*exp(r2*t)
            }
            var settled = 0.0, end = 10.0, t = 0.0
            while t < 10 {
                if abs(position(t)-1) > precision { settled = 0 } else {
                    settled += 0.001
                    if settled > 0.1 { end = ceil((t-settled+0.001)*1000)/1000; break }
                }
                t += 0.001
            }
            duration = end
            let count = min(100,max(32,Int((end*1000/15).rounded())))
            var values = (0..<count).map { i in i == count-1 ? 1 : (position(Double(i)/Double(count-1)*end)*10000).rounded()/10000 }
            while values.count > 2 && values[values.count-2] == 1 { values.remove(at: values.count-2) }
            samples = values
        }
    }
    func value(_ progress: Double) -> Double {
        let t = min(1,max(0,progress))
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        if let nativeSpring {
            return nativeSpring.value(target: 1.0, initialVelocity: initialVelocity, time: t*duration)
        }
        if let samples {
            let x = t*Double(samples.count-1), index = Int(x)
            return samples[index]+(samples[min(index+1,samples.count-1)]-samples[index])*(x-Double(index))
        }
        func coordinate(_ s: Double, _ a: Double, _ b: Double) -> Double {
            3*(1-s)*(1-s)*s*a+3*(1-s)*s*s*b+s*s*s
        }
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let middle = (low+high)/2
            if coordinate(middle,bezier[0],bezier[2]) < t { low = middle } else { high = middle }
        }
        return coordinate((low+high)/2,bezier[1],bezier[3])
    }
    func slope(_ t: Double) -> Double {
        let a = min(max(t,0),1-0.0001)
        return (value(a+0.0001)-value(a))/0.0001
    }
}

struct MorphPresentation {
    var rect: CGRect
    var opacity: Double = 1
    var scale: Double = 1
    var slide: Double = 0
    var origin: CGPoint = CGPoint(x: 0.5,y: 0.5)
}

struct MorphTrajectory: Identifiable {
    var segment: MorphSegment
    var id: String { segment.id }
    var start: MorphPresentation
    var end: MorphPresentation
    var began: TimeInterval
    var curve: MorphCurve
    var fadeDelay: Double = 0
    var fadeShare: Double = 0.25
    var exiting = false
    // Numeric mover animation is independent of its slot's FLIP animation.
    var inheritedSlide: SlideTrack?
    var inheritedFade: FadeTrack?
    struct FadeTrack {
        var from: Double; var to: Double; var began: Double; var duration: Double
        var delay: Double; var share: Double
        func value(at time: Double) -> Double {
            let progress = duration <= 0 ? 1 : max(0,(time-began)/duration)
            let t = min(1,max(0,(progress-delay)/max(0.00001,share)))
            return from+(to-from)*t
        }
    }
    struct SlideTrack { var from: Double; var to: Double; var began: Double; var curve: MorphCurve }
    func presentation(at time: TimeInterval) -> MorphPresentation {
        let progress = curve.duration <= 0 ? 1 : max(0,(time-began)/curve.duration)
        let p = curve.value(progress)
        let fade = min(1,max(0,(progress-fadeDelay)/max(0.00001,fadeShare)))
        var result = end
        result.rect.origin.x = start.rect.minX+(end.rect.minX-start.rect.minX)*p
        result.rect.origin.y = start.rect.minY+(end.rect.minY-start.rect.minY)*p
        result.opacity = start.opacity+(end.opacity-start.opacity)*fade
        result.scale = start.scale+(end.scale-start.scale)*p
        result.slide = start.slide+(end.slide-start.slide)*p
        if let track = inheritedSlide {
            let q = track.curve.value(track.curve.duration <= 0 ? 1 : (time-track.began)/track.curve.duration)
            result.slide = track.from+(track.to-track.from)*q
        }
        if let inheritedFade { result.opacity = inheritedFade.value(at: time) }
        return result
    }
}

/// Measurement-independent planning, shared by the renderer and regression tests.
enum MorphMotion {
    static func anchor(at index: Int, ids: [String], persistent: Set<String>, forwardFirst: Bool = false) -> String? {
        func backward() -> String? { ids[..<index].reversed().first { persistent.contains($0) } }
        func forward() -> String? { ids.dropFirst(index+1).first { persistent.contains($0) } }
        return forwardFirst ? forward() ?? backward() : backward() ?? forward()
    }
    static func groups(_ all: [MorphSegment], members: Set<String>) -> [[String]] {
        var result: [[String]] = [], run: [String] = []
        func flush() { if run.count >= 6 { result.append(run) }; run = [] }
        for s in all { if members.contains(s.id) { run.append(s.id) } else { flush() } }
        flush(); return result
    }
    static func plan(diff: MorphDiff, oldRects: [String: CGRect], newRects: [String: CGRect],
                     previous: [MorphTrajectory], now: Double, curve: MorphCurve,
                     lineHeight: Double, scaleExits: Bool) -> [MorphTrajectory] {
        let old = diff.preparedPrevious.filter { $0.text != "\n" }, new = diff.segments.filter { $0.text != "\n" }
        let oldIDs = Set(old.map(\.id)), newIDs = Set(new.map(\.id)), persistent = oldIDs.intersection(newIDs)
        let oldLookup = Dictionary(uniqueKeysWithValues: previous.filter { !$0.exiting }.map { ($0.id,$0) })
        var result = previous.filter { $0.exiting && $0.presentation(at: now).opacity > 0 }
        // A returning ID gets a fresh node, as in DOM reconciliation. Stale exiting
        // nodes use separate render identity (see TextMorph's enumerated scene).
        let entering = newIDs.subtracting(oldIDs), exiting = oldIDs.subtracting(newIDs)
        func centers(_ runs: [[String]], rects: [String: CGRect]) -> [String: CGPoint] {
            var result: [String: CGPoint] = [:]
            for run in runs {
                let bounds = run.compactMap { rects[$0] }.reduce(CGRect.null) { $0.union($1) }
                for id in run { result[id] = CGPoint(x: bounds.midX,y: bounds.midY) }
            }
            return result
        }
        let enterCenters = centers(groups(new,members: entering),rects: newRects)
        let exitCenters = centers(groups(old,members: exiting),rects: oldRects)
        func origin(_ center: CGPoint, _ rect: CGRect) -> CGPoint {
            CGPoint(x: (center.x-rect.minX)/max(rect.width,0.001),y: (center.y-rect.minY)/max(rect.height,0.001))
        }
        for (index,s) in new.enumerated() {
            guard let rect = newRects[s.id] else { continue }
            var end = MorphPresentation(rect: rect), start = end
            var delay = 0.0, share = 0.25
            let oldMotion = oldLookup[s.id]
            if let oldRect = oldRects[s.id] {
                start = oldMotion?.presentation(at: now) ?? MorphPresentation(rect: oldRect)
                start.rect.size = rect.size
                // Upstream drops scale when it cancels a running segment animation.
                start.scale = 1
            } else if let center = enterCenters[s.id] {
                start.scale = 0.8; start.opacity = 0; share = 0.35
                end.origin = origin(center,rect); start.origin = end.origin
            } else {
                let anchorID = anchor(at: index,ids: new.map(\.id),persistent: persistent)
                if let a = anchorID, let before = oldRects[a], let after = newRects[a] {
                    start.rect.origin.x += before.minX-after.minX
                    start.rect.origin.y += before.minY-after.minY
                }
                start.opacity = 0
                if let kind = s.kind { start.slide = kind == .digit ? -lineHeight : lineHeight }
                else { start.scale = 0.95; delay = 0.25; share = 0.5 }
            }
            var trajectory = MorphTrajectory(segment: s,start: start,end: end,began: now,curve: curve,fadeDelay: delay,fadeShare: share)
            if s.kind != nil, oldRects[s.id] != nil, let oldMotion {
                trajectory.inheritedSlide = oldMotion.inheritedSlide ?? .init(from: oldMotion.start.slide,to: oldMotion.end.slide,began: oldMotion.began,curve: oldMotion.curve)
                trajectory.inheritedFade = oldMotion.inheritedFade ?? .init(
                    from: oldMotion.start.opacity,to: oldMotion.end.opacity,began: oldMotion.began,
                    duration: oldMotion.curve.duration,delay: oldMotion.fadeDelay,share: oldMotion.fadeShare)
            }
            result.append(trajectory)
        }
        for (index,s) in old.enumerated() where exiting.contains(s.id) {
            guard let rect = oldRects[s.id] else { continue }
            var start = oldLookup[s.id]?.presentation(at: now) ?? MorphPresentation(rect: rect)
            start.scale = 1
            var end = start; end.opacity = 0
            var share = 0.25
            if let center = exitCenters[s.id] {
                start.origin = origin(center,start.rect); end.origin = start.origin
                end.scale = 0.8; share = 0.45
            } else {
                if let a = anchor(at: index,ids: old.map(\.id),persistent: persistent,forwardFirst: true),
                   let before = oldRects[a], let after = newRects[a] {
                    end.rect.origin.x += after.minX-before.minX; end.rect.origin.y += after.minY-before.minY
                }
                if s.kind != nil { end.slide = lineHeight; share = 0.45 }
                else { end.scale = scaleExits ? 0.95 : 1 }
            }
            result.append(.init(segment: s,start: start,end: end,began: now,curve: curve,fadeShare: share,exiting: true))
        }
        return result
    }
}
