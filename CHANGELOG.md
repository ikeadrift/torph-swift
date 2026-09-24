# Changelog

## 0.3.1

- Preserve in-flight morphs when changing scaling, blur, stagger, or timing. Updated settings take effect on the next text change instead of clearing the renderer and cancelling the current animation.
- Add a hosted SwiftUI regression test for repeated effect changes during animation and the following text transition.

## 0.3.0

- Add independent entrance, exit, and grouped scale factors, an option to scale around each run’s own center, and `scaling: .none`. Defaults preserve the original appearance.
- Fix `scale: false` so grouped exits also stop shrinking.
- Add optional outgoing blur that progresses with the exit fade and continues smoothly from interrupted entrance blur.
- Add regression coverage for grouped exits, custom factors/origins, no-scale fade/blur, interruptions, and invalid values.

## 0.2.1

- Keep staggered fade and blur starts in character order across ordinary text, numbers, and grouped replacements.
- Preserve entering words’ movement anchors when character staggering splits a long word; the split no longer incorrectly triggers grouped replacement.
- Add regression tests for mixed entrance order, independent blur spread, anchor movement, and genuine replacement groups.

## 0.2.0

- New text now enters with a configurable 6-point blur that clears with its fade. Set `entrance: .init(blurRadius: 0)` for the previous appearance.
- Add configurable character stagger as a fraction of animation duration, native SwiftUI `UnitCurve` stagger curves, and an optional independent blur stagger. All entrance effects fit inside the existing animation timeline.
- Preserve pending entrance delays and blur/fade progress through rapid updates. Only newly inserted words split into graphemes when staggering is enabled.
- Fix position jumps when a moving whole word splits into characters; entering characters anchor to the current presentation position.
- Keep interrupted container height animations running after width completion, while retaining the documented width-based completion callback.
- Fix the spring sampling expression that failed to compile with Swift 6.2.1.
- Add regression coverage for interruption, blur, stagger, custom curves, Unicode, and invalid inputs, plus macOS test and iOS Simulator build CI.

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
