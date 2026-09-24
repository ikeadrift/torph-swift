# Torph for SwiftUI

**Original library by [Lochie Axon](https://github.com/lochie).** The text-matching algorithms and original motion behavior come from [Torph](https://github.com/lochie/torph) ([web demo](https://torph.lochie.me)). This is an unofficial SwiftUI port maintained by [ikeadrift](https://github.com/ikeadrift), not an official Lochie release or an indication of his endorsement. See [NOTICE](NOTICE) for source attribution and [LICENSE](LICENSE) for the retained MIT terms.

A dependency-free native Swift port of [Lochie Axon’s Torph](https://torph.lochie.me). Matching characters move to their new positions, new characters fade and slide in, and removed characters fade, slide, and optionally shrink. Word grouping, character origins, anchor-based movement, grouped replacement, and numeric slides follow the upstream implementation. Native effects add configurable entrance and exit blur with a 2-point default entrance blur.

Requires **Swift 6**, **iOS 17+**, **macOS 14+**, **tvOS 17+**, **watchOS 10+**, or **visionOS 1+**. macOS and iOS Simulator builds have been verified; the other declared platforms have not been runtime-tested.

## Install

In Xcode, choose **File → Add Package Dependencies**, enter:

```text
https://github.com/ikeadrift/torph-swift.git
```

Choose **Up to Next Minor Version** starting at **0.4.1**, then add the **Torph** product to your app target.

For another Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/ikeadrift/torph-swift.git", .upToNextMinor(from: "0.4.1"))
],
targets: [
    .target(name: "MyFeature", dependencies: [
        .product(name: "Torph", package: "torph-swift")
    ])
]
```

Use Swift tools 6.0 or newer and declare the appropriate minimum platform in your consuming package. Xcode builds the source for your target. The package has no external dependencies.

For local use, clone this repository and choose **Add Local…** in Xcode. Keep the cloned folder at a stable path, or include its source inside your app repository.

## Usage

```swift
import SwiftUI
import Torph

struct StatusLabel: View {
    @State private var complete = false

    var body: some View {
        VStack(spacing: 24) {
            TextMorph(complete ? "Transaction complete" : "Processing transaction")
                .font(.title2.weight(.medium))
                .foregroundStyle(.primary)

            Button("Change status") { complete.toggle() }
        }
    }
}
```

Change the input string normally; `TextMorph` measures and animates the transition. The initial value appears immediately.

```swift
TextMorph(
    message,
    configuration: .init(
        timing: .spring(mass: 1, stiffness: 200, damping: 20),
        numbers: true,
        locale: Locale(identifier: "en_US"),
        alignment: .leading,
        lineSpacing: 4
    ),
    onAnimationStart: { print("Started") },
    onAnimationComplete: { print("Settled") },
    onAnimationCancel: { print("Interrupted") }
)
```

Default timing matches the web library’s cubic Bézier `(0.19, 1, 0.22, 1)` over **0.4 seconds**. Unlike the web API, durations use seconds. Springs use the upstream physics, sampled curve, and settling-duration algorithm. Completion follows the container width animation, including its remaining time when an update retains the same target width. Glyph animations and the container height finish independently. Glyphs can finish after a resumed width animation. A new update cancels the previous callback token; stale completions are ignored. Disappearance tears down animations without firing completion/cancellation callbacks, as upstream does. Immediate updates do not fire animation callbacks.

## Effects

All appearance options live in `configuration.effects`. Timing is separate. Presets are ordinary editable values, and choosing one replaces the complete effects configuration:

```swift
TextMorph(message, configuration: .init(effects: .standard))
TextMorph(message, configuration: .init(effects: .fade))
TextMorph(message, configuration: .init(effects: .fadeAndBlur()))
TextMorph(message, configuration: .init(effects: .fadeAndBlur(blurRadius: 5)))
```

| Preset | Entrance scale / blur | Exit scale / blur | Large replacement scaling |
| --- | --- | --- | --- |
| `.standard` (default) | 0.95 / 2 pt | 0.95 / 0 pt | Shared center, 0.8 in and out |
| `.fade` | 1 / 0 pt | 1 / 0 pt | Individual, no scaling |
| `.fadeAndBlur()` | 1 / 2 pt | 1 / 2 pt | Individual, no scaling |

Fade, matching movement, and numeric rolls are part of the base animation. These presets change scale and blur; `.fade` does not disable matching movement or numeric rolls. Use `configuration.disabled` for immediate native text without animation.

Customize each direction together:

```swift
TextMorph(message, configuration: .init(
    timing: .spring(.snappy),
    effects: .init(
        entrance: .init(scale: 0.95, blurRadius: 2),
        exit: .init(scale: 1, blurRadius: 2),
        replacementScaling: .individual
    )
))
```

`entrance` describes the starting scale and blur of inserted text; it settles to scale 1 and blur 0. `exit` describes the final scale and blur of removed text. Scale `1` means unchanged size; blur `0` disables blur. Fade timing follows the original Torph motion rules. Ordinary numeric runs use their original slide/fade rules instead of individual text scaling.

### Blur curves

Entrance and exit each accept a native SwiftUI `UnitCurve`, including custom Béziers:

```swift
var effects = TextMorphConfiguration.Effects.fadeAndBlur()
effects.entrance.blurCurve = .easeOut
effects.exit.blurCurve = .easeIn
// Or use one curve for both directions:
let soft = TextMorphConfiguration.Effects.fadeAndBlur(blurCurve: .easeInOut)
// Custom blur progress:
effects.entrance.blurCurve = .bezier(
    startControlPoint: .init(x: 0.2, y: 0),
    endControlPoint: .init(x: 0.8, y: 1)
)
```

The default is `.linear`. The curve eases blur progress **within the existing fade window**; it does not change opacity, movement, scaling, duration, or when characters start. Entrance interpolates its initial blur to zero; exit interpolates the current blur to its target radius. Overshooting curves are bounded to those endpoints. Interrupted text retains its original blur curve/timeline; an exit begins at the currently visible blur. No stagger or spread is involved.

### Grouped scaling

For six or more consecutive replaced segments, `.grouped(entrance:exit:)` overrides the individual scale factors and uses a shared center. It does **not** change matching identities, replacement detection, blur, or fade timing. An intact word counts as one segment.

```swift
var effects = TextMorphConfiguration.Effects.standard
// Whole replacement blocks scale around their shared center.
effects.replacementScaling = .grouped(entrance: 0.9, exit: 0.85)
// Or use the entrance/exit scales around each text run's own center.
effects.replacementScaling = .individual
```

Grouped scaling defaults to 0.8 in both directions. To disable **all** scaling, start from `.fade` or `.fadeAndBlur()`, which set both individual scales to 1 and select `.individual`. Setting only `entrance.scale` or `exit.scale` does not override an explicit grouped scale.

### Customizing a preset

```swift
var effects = TextMorphConfiguration.Effects.fadeAndBlur()
effects.exit.blurRadius = 4
effects.entrance.scale = 0.98
let configuration = TextMorphConfiguration(timing: .spring(), effects: effects)
```

Initial text and Reduce Motion/disabled/RTL fallbacks appear immediately. Whole words retain native shaping until the matcher needs to split them. Retained characters do not restart their entrance effects; interrupted exits begin at their current blur/opacity. Scale factors are clamped to `0...2` (nonfinite values use `1`) and blur to `0...64` points (nonfinite values use `0`).

Effects and timing changes apply to the next text morph. An animation already in progress finishes with its existing settings. Changes to segmentation, layout, or disabled/reduced-motion behavior reset the layout.

**Upgrading from 0.3:** see the [0.4 migration guide](Documentation/Migration-0.4.md). The old scaling flag and scattered effect properties have been removed. Stagger and spread are no longer supported.

## Native springs

Pass any SwiftUI `Spring` value directly:

```swift
TextMorph(message, configuration: .init(timing: .spring(.snappy)))
TextMorph(message, configuration: .init(
    timing: .spring(Spring(duration: 0.35, bounce: 0.15))
))
```

Native springs use SwiftUI's solver, with optional `initialVelocity:`. This accepts `Spring`, not an opaque SwiftUI `Animation` value or its repeat/delay modifiers. Native settling duration is bounded to 10 seconds. Physical parameters remain available with `.spring(mass:stiffness:damping:precision:)`.

The default `.spring()` uses mass **1**, stiffness **360**, damping **30**, and precision **0.001** for a quicker response. The original web spring is available explicitly as `.spring(mass: 1, stiffness: 100, damping: 10)`. The overall default timing remains the upstream 0.4-second ease-out; choose `.spring()` to use the spring preset.

## Numbers

Use Foundation format styles to produce the string, and pass the same locale to the matcher:

```swift
let locale = Locale(identifier: "en_US")
TextMorph(
    total.formatted(.currency(code: "USD").locale(locale)),
    configuration: .init(locale: locale)
)
.font(.largeTitle.monospacedDigit())
```

Unchanged digits retain identity according to upstream’s place and reshape rules. Changed digits exit and enter as distinct segments. Currency, signs, decimal points, and grouping symbols are matched separately. Ordinary numeric tokens are recognized automatically; dates and identifiers such as `COVID-19` stay text. Set `numbers: false` for ordinary character matching. For numeric editing, pass `cursorIndex:` to `TextMorph` or the matching engine; it applies to a single matched numeric word.

## Layout and accessibility

- Inherits `.font` (including Dynamic Type) and `.foregroundStyle`.
- Uses upstream’s nowrap layout; explicit newlines and blank lines are supported.
- Swift `Character` keeps emoji sequences and combining marks intact.
- Exposes one complete accessibility label instead of separate characters.
- Respects Reduce Motion by default, rendering native `Text` immediately.
- Right-to-left layout uses native `Text` to preserve shaping and bidirectional layout.
- Set `disabled: true` to use native `Text` without morphing.

This is intended for labels and short UI messages. Unchanged words remain whole native text runs. Only words being character-morphed are split, which can affect cross-character kerning, ligatures, and joined-script shaping. For scripts requiring joined shaping in a left-to-right environment, use `disabled: true`. Rich attributed text, text selection, truncation/line-limit parity, are not implemented. Native fonts and Unicode segmentation can differ from a browser.

## Matching engine

```swift
let old = TextMatcher.segment("Sending message")
let diff = TextMatcher.diff(from: old, to: "Sending messages")
// diff.segments: new ordering with surviving identities
// diff.inserted: newly allocated segments
// diff.removed: segments absent from the new value
// diff.splits: whole-word nodes to split before measuring
// diff.preparedPrevious: old nodes after applying those splits
```

Reuse `diff.segments` as the next update’s input. Exact and reordered words preserve identity; changed words use a longest common subsequence. Standalone labels reuse deterministic grapheme identities. Fuzzy matching is bounded to avoid quadratic memory growth on large inputs. The engine is independent of SwiftUI and its value types are `Sendable`.

## Test

Run `swift test` from this directory. Reference fixtures are included.

## Relationship to upstream

Reference: [lochie/torph](https://github.com/lochie/torph), commit `d79a5aa63226acf97d49c3e34fafb2e85c07b026`. The core algorithms are ported from the upstream source. This is not an official release. The regression suite compares the Swift matcher against **316 upstream-generated cases / 1,718 transitions** and separately checks motion planning.

See [the behavior parity audit](Documentation/BehaviorParity.md) for the exact source mapping, test methodology, capitalization regression, and remaining platform differences. Native typography, locale segmentation, frame scheduling, and bidi rendering prevent an honest claim of universal pixel-for-pixel equivalence.

MIT licensed; upstream copyright and license are retained in [LICENSE](LICENSE).
