import Foundation
import CoreGraphics
import SwiftUI

extension TextMorphConfiguration {
    /// Optional blur and character staggering for newly inserted text.
    public struct Entrance: Equatable, Sendable {
        /// Initial Gaussian blur radius in points. Zero preserves the original appearance.
        public var blurRadius: CGFloat
        /// Total first-to-last fade delay, as a fraction of the animation duration (0...0.9).
        public var stagger: Double
        /// Independent blur stagger. Nil uses `stagger`.
        public var blurStagger: Double?
        /// Maps character order to delay: linear, easeIn, easeOut, or a custom Bézier.
        public var staggerCurve: UnitCurve

        public init(blurRadius: CGFloat = 6, stagger: Double = 0, blurStagger: Double? = nil,
                    staggerCurve: UnitCurve = .linear) {
            self.blurRadius = blurRadius
            self.stagger = stagger
            self.blurStagger = blurStagger
            self.staggerCurve = staggerCurve
        }

        func delayFraction(at progress: Double) -> Double {
            let value = staggerCurve.value(at: progress)
            return value.isFinite ? min(1, max(0, value)) : progress
        }

        var radius: Double { blurRadius.isFinite ? Double(min(64, max(0, blurRadius))) : 0 }
        private func fraction(_ value: Double) -> Double { value.isFinite ? min(0.9, max(0, value)) : 0 }
        var fadeSpread: Double { fraction(stagger) }
        var blurSpread: Double { fraction(blurStagger ?? stagger) }
        var needsCharacters: Bool { fadeSpread > 0 || (radius > 0 && blurSpread > 0) }
        var isEnabled: Bool { radius > 0 || fadeSpread > 0 }
    }
}

extension MorphDiff {
    /// Only split fresh words when character staggering is requested. Existing runs
    /// retain their identity and shaping; the public matching engine stays unchanged.
    func preparingEntrance(_ entrance: TextMorphConfiguration.Entrance) -> MorphDiff {
        guard entrance.needsCharacters else { return self }
        let oldIDs = Set(preparedPrevious.map(\.id))
        var allocator = IDAllocator()
        allocator.used = oldIDs.union(segments.map(\.id))
        var parents = entranceParents
        let next = segments.flatMap { segment -> [MorphSegment] in
            guard !oldIDs.contains(segment.id), segment.text.count > 1,
                  !segment.text.allSatisfy(\.isWhitespace) else { return [segment] }
            return segment.text.enumerated().map { index, character in
                let id = allocator.take("\(segment.id):entrance:\(index)")
                parents[id] = segment.id
                return MorphSegment(id: id, text: String(character), kind: segment.kind)
            }
        }
        return MorphDiff(segments: next, splits: splits, preparedPrevious: preparedPrevious, entranceParents: parents)
    }
}
