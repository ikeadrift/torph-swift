# Torph for SwiftUI

A dependency-free native Swift port of [Lochie Axon’s Torph](https://torph.lochie.me). Matching characters move to their new positions, new characters fade and slide in, and removed characters fade, slide, and optionally shrink. Word grouping, character origins, anchor-based movement, grouped replacement, numeric slides, and fade timing follow the upstream implementation.

Requires **Swift 6**, **iOS 17+**, **macOS 14+**, **tvOS 17+**, **watchOS 10+**, or **visionOS 1+**. macOS and iOS Simulator builds have been verified; the other declared platforms have not been runtime-tested.

## Install

In Xcode, choose **File → Add Package Dependencies**, enter:

```text
https://github.com/ikeadrift/torph-swift.git
```

Choose **Up to Next Major Version** starting at **0.1.1**, then add the **Torph** product to your app target. This repository is private: sign in to an authorized GitHub account in Xcode's settings.

For another Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/ikeadrift/torph-swift.git", from: "0.1.1")
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
        scale: true,
        locale: Locale(identifier: "en_US"),
        alignment: .leading,
        lineSpacing: 4
    ),
    onAnimationStart: { print("Started") },
    onAnimationComplete: { print("Settled") },
    onAnimationCancel: { print("Interrupted") }
)
```

Default timing matches the web library’s cubic Bézier `(0.19, 1, 0.22, 1)` over **0.4 seconds**. Unlike the web API, durations use seconds. Springs use the upstream physics, sampled curve, and settling-duration algorithm. Completion follows the container width animation, including its remaining time when an update retains the same target width. Glyph animations finish independently. A new update cancels the previous callback token; stale completions are ignored. Disappearance tears down animations without firing completion/cancellation callbacks, as upstream does. Immediate updates do not fire animation callbacks.

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
