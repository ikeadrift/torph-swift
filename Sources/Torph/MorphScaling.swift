import Foundation

extension TextMorphConfiguration {
    /// Scale factors for inserted and removed text. One means no scaling.
    public struct Scaling: Equatable, Sendable {
        public var entrance: Double
        public var exit: Double
        public var groupedEntrance: Double
        public var groupedExit: Double
        /// Use a shared center for large replacements; false scales each run around its own center.
        public var groupReplacements: Bool

        public init(entrance: Double = 0.95, exit: Double = 0.95,
                    groupedEntrance: Double = 0.8, groupedExit: Double = 0.8,
                    groupReplacements: Bool = true) {
            self.entrance = entrance
            self.exit = exit
            self.groupedEntrance = groupedEntrance
            self.groupedExit = groupedExit
            self.groupReplacements = groupReplacements
        }

        public static var none: Self {
            .init(entrance: 1, exit: 1, groupedEntrance: 1, groupedExit: 1, groupReplacements: false)
        }

        func factor(entering: Bool, grouped: Bool) -> Double {
            let value = grouped && groupReplacements
                ? (entering ? groupedEntrance : groupedExit)
                : (entering ? entrance : exit)
            return value.isFinite ? min(2, max(0, value)) : 1
        }
    }
}
