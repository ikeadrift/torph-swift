import SwiftUI

extension TextMorphConfiguration {
    /// Visual effects for inserted and removed text. Matching text still moves,
    /// and numeric text still rolls. Fading is part of the base morph behavior.
    public struct Effects: Equatable, Sendable {
        public var entrance: Entrance
        public var exit: Exit
        /// Scale overrides and shared origins for large replacements only.
        /// Does not change word matching, replacement detection, or fade timing.
        public var replacementScaling: ReplacementScaling

        public init(entrance: Entrance = .init(), exit: Exit = .init(),
                    replacementScaling: ReplacementScaling = .grouped()) {
            self.entrance = entrance
            self.exit = exit
            self.replacementScaling = replacementScaling
        }

        /// Torph motion with 2-point entrance blur and the original scale factors.
        public static var standard: Self { .init() }
        /// Fade in/out with no blur or scaling. Matching movement and numeric rolls remain.
        public static var fade: Self {
            .init(entrance: .init(scale: 1, blurRadius: 0),
                  exit: .init(scale: 1), replacementScaling: .individual)
        }
        /// Fade and blur in both directions with no scaling. Radius is in points.
        public static func fadeAndBlur(blurRadius: CGFloat = 2) -> Self {
            .init(entrance: .init(scale: 1, blurRadius: blurRadius),
                  exit: .init(scale: 1, blurRadius: blurRadius), replacementScaling: .individual)
        }

        func scaleFactor(entering: Bool, grouped: Bool) -> Double {
            var value = entering ? entrance.scale : exit.scale
            if grouped, case let .grouped(entrance, exit) = replacementScaling {
                value = entering ? entrance : exit
            }
            return value.isFinite ? min(2, max(0, value)) : 1
        }
        var usesGroupScaling: Bool {
            if case .grouped = replacementScaling { return true }
            return false
        }
    }

    /// Initial appearance of newly inserted text; it settles to scale 1 and blur 0.
    public struct Entrance: Equatable, Sendable {
        /// Initial size multiplier. 1 disables individual entrance scaling.
        public var scale: Double
        /// Initial blur in points. Zero disables entrance blur.
        public var blurRadius: CGFloat

        public init(scale: Double = 0.95, blurRadius: CGFloat = 2) {
            self.scale = scale
            self.blurRadius = blurRadius
        }

        var radius: Double { effectBlurRadius(blurRadius) }
    }

    /// Final appearance reached as removed text fades out.
    public struct Exit: Equatable, Sendable {
        /// Final size multiplier. 1 disables individual exit scaling.
        public var scale: Double
        /// Final blur in points. Zero disables exit blur.
        public var blurRadius: CGFloat

        public init(scale: Double = 0.95, blurRadius: CGFloat = 0) {
            self.scale = scale
            self.blurRadius = blurRadius
        }
        var radius: Double { effectBlurRadius(blurRadius) }
    }

    public enum ReplacementScaling: Equatable, Sendable {
        /// Use entrance/exit scales around each text run's own center, including
        /// large replacements. An intact word is one run, not separate letters.
        case individual
        /// Override entrance/exit scales for large replacements (six or more
        /// consecutive replaced segments), scaling around their shared center.
        case grouped(entrance: Double = 0.8, exit: Double = 0.8)
    }
}

private func effectBlurRadius(_ value: CGFloat) -> Double {
    value.isFinite ? Double(min(64, max(0, value))) : 0
}
