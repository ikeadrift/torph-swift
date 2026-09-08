# Changelog

## 0.1.2

- Add prominent original-author credit, source attribution, and an explicit unofficial-port notice. Preserve the original MIT license.
- Prepare public GitHub installation instructions.

## 0.1.1

- Fix disappearing or vertically displaced text after updates, scrolling, and configuration changes: resolve layout anchors inside each measurement probe instead of relying on a changing named coordinate space.
- Accept native SwiftUI `Spring` values and initial velocity, evaluated with SwiftUI's solver.
- Make the default spring more responsive (mass 1, stiffness 360, damping 30); preserve explicit upstream parameters.
- Verify native spring curves and response timing, plus all previous reference regressions.

## 0.1.0

- Initial dependency-free SwiftUI library release, with a portable Swift Package Manager archive.
- Upstream word/character matching, numeric identities, anchor motion, grouped replacements, and sampled timing curves.
- Rapid updates preserve surviving numeric fades and slides. Retargeted container momentum uses the upstream analytic derivative; completion follows the remaining width animation while glyphs finish independently.
- Regression coverage includes 1,718 upstream matcher transitions and motion tests for bursts, centered width changes, and empty values.
- See Documentation/BehaviorParity.md for native platform differences.
