// Upstream's independent width/height continuation and bounded momentum carry.
import Foundation
import CoreGraphics

struct MorphSizeMotion {
    struct Axis {
        var from: Double
        var to: Double
        var began: Double
        var curve: MorphCurve
        var carry = 0.0
        var bump = 3.0
        var samples: [Double]?
        func progress(_ now: Double) -> Double { curve.duration <= 0 ? 1 : min(1,max(0,(now-began)/curve.duration)) }
        func easing(_ t: Double) -> Double {
            if t >= 1 { return 1 }
            if let samples {
                let x = max(0,t)*Double(samples.count-1), i = Int(x)
                return samples[i]+(samples[min(i+1,samples.count-1)]-samples[i])*(x-Double(i))
            }
            return curve.value(t)
        }
        func value(_ now: Double) -> Double { from+(to-from)*easing(progress(now)) }
        // Upstream differentiates the analytic carried curve, while playback uses
        // its rounded CSS linear() samples. Preserve both through repeated interrupts.
        func analyticEasing(_ t: Double) -> Double {
            t >= 1 ? 1 : curve.value(t)+carry*t*pow(1-t,bump)
        }
        func velocity(_ now: Double) -> Double {
            let t = progress(now)
            guard t < 1,curve.duration > 0 else { return 0 }
            let lo = min(max(t,0),1-0.0001)
            return (to-from)*(analyticEasing(lo+0.0001)-analyticEasing(lo))/0.0001/curve.duration
        }
    }
    var width: Axis
    var height: Axis
    init(from: CGSize,to: CGSize,previous: MorphSizeMotion?,now: Double,curve: MorphCurve,hold: Bool) {
        func axis(_ from: Double,_ to: Double,_ old: Axis?) -> Axis {
            if hold { return Axis(from: from,to: from,began: now,curve: curve) }
            if let old,old.progress(now) < 1,abs(old.to-to) < 0.5 { return old }
            var result = Axis(from: from,to: to,began: now,curve: curve)
            if abs(to-from) > 0.5 {
                let normalized = (old?.velocity(now) ?? 0)*curve.duration/(to-from)
                result.carry = max(0,min(8,normalized)-curve.slope(0))
                result.bump = max(3,ceil(result.carry/(exp(1)*0.1))-1)
                if result.carry > 0 {
                    let count = min(120,max(32,Int((curve.duration*1000/8).rounded())))
                    result.samples = (0..<count).map { i in
                        let t = Double(i)/Double(count-1)
                        return i == count-1 ? 1 : ((curve.value(t)+result.carry*t*pow(1-t,result.bump))*10000).rounded()/10000
                    }
                }
            }
            return result
        }
        width = axis(from.width,to.width,previous?.width); height = axis(from.height,to.height,previous?.height)
    }
    func size(at now: Double) -> CGSize { CGSize(width: width.value(now),height: height.value(now)) }
}
