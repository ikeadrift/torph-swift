# Behavior parity audit

Reference: [`lochie/torph` at d79a5aa63226acf97d49c3e34fafb2e85c07b026](https://github.com/lochie/torph/tree/d79a5aa63226acf97d49c3e34fafb2e85c07b026), MIT, copyright Lochie Axon.

## The reported capitalization artifact

For `Processing transaction` → `Transaction complete`, the upstream oracle produces:

- `Processing`: one whole-word segment, exits whole.
- `transaction`: split into characters before layout measurement.
- Initial lowercase `t`: exits.
- `ransaction`: preserves the split characters’ identities.
- Uppercase `T`: fresh identity, entering anchor is the following surviving `r`.
- `complete`: enters as a whole word.

Neither matcher prefers capital letters. The first native implementation introduced a visual association: it inserted `T` at its final leftmost position while `ransaction` traveled there. Upstream initializes an entering segment with its anchor’s old-to-new displacement. Consequently, `T` starts beside the old word and moves with `r`. The rewritten renderer does this explicitly. A regression test samples their relative position throughout the animation; the separation remains constant. The recorded iOS Simulator demonstration is in `Artifacts/capitalization.mp4`.

## Source-to-Swift mapping

| Upstream source | Native implementation | Contract |
| --- | --- | --- |
| `segment.ts` | `TextMatcher.swift` | Word segmentation for phrases; grapheme segmentation for standalone labels; deterministic collision-safe text identities; numeric expansion. |
| `diff.ts`, `lcs.ts` | `TextMatcher.swift` | Forward LCS tie-breaking, exact reorder pass, fuzzy matching only inside original LCS gaps, strict >0.4 affinity, numeric skeleton affinity, split-before-measure, upfront identity reservation. |
| `number.ts` | `NumberMatcher.swift` | Affixes, decimal pivot, digit equality, integer reshape LCS, grouping separators, large magnitude replacement, fractional matching, caret matching. |
| `flip.ts` | `MorphMotion.swift` | Enter anchors search backward first, exits forward first; priority is directional, not geometric distance. |
| text `animate.ts` | `MorphMotion.swift` | Enter scale 0.95, fade starts at 25% and lasts 50%; ordinary exit scale 0.95 with a 25% fade. No arbitrary vertical slide for ordinary text. |
| `replace-animate.ts` | `MorphMotion.swift` | Six consecutive replaced segments trigger group scale 0.8 about a shared center; exit fade 45%, enter fade 35%. |
| `number-animate.ts`, `styles.ts` | `MorphMotion.swift`, `TextMorph.swift` | Separate slot translation and inner slide; digits enter from above, symbols below, exits below; line-height slide, per-slot vertical masking, 25% / 45% fades. No SwiftUI numericText in the library renderer. |
| `spring.ts`, `easing.ts` | `MorphMotion.swift` | Default cubic Bézier, explicit custom Bézier, sampled physical spring, precision and settling-duration calculation. |
| container `animate.ts` | `MorphSizeMotion.swift` | Width and height animate independently, retain same-target progress, carry bounded forward momentum when retargeted, hold the old box while empty text exits. |

## Evidence

`scripts/generate-upstream-fixtures.mjs` runs the actual upstream TypeScript after Node’s type stripping. It does not emulate the reference algorithm. It emits checked-in JSON containing the initial segments, prepared old segments after splits, destination segments, kinds, and origin indices for each update.

The checked-in corpus covers **316 cases / 1,718 transitions**:

- All values/cycles from upstream’s shared text cases.
- All values from upstream’s shared number cases, including caret positions and locales.
- Those numeric cases run again through the complete text pipeline.
- The reported capitalization regression and upstream’s title-case transaction example.
- 200 deterministically seeded mixed-word, repeated-word, punctuation, identifier, and number cases.

`testUpstreamCorpus` asserts exact segment text, kinds, split topology, and origin mapping at every step, plus unique identities. Separate motion tests check anchors, relative character movement, grouped replacement, fade fractions, numeric slides, interrupted positions, and container continuation. These are behavioral tests, not merely string-output checks.

Regenerate with:

```sh
node scripts/generate-upstream-fixtures.mjs /path/to/lochie/torph
swift test
```

The generator caches stripped modules in `.build/upstream-oracle`; use a fresh cache if changing the reference checkout. JavaScript is used only to generate test fixtures. The shipped package is Swift, with no JavaScript runtime or third-party dependencies.

## Rapid interruption behavior

Surviving numeric segments keep the original inner slide **and fade** timelines while their outer slots retarget. Repeated container retargets derive momentum from the analytic carried curve, matching the upstream implementation before rounded playback sampling. An unchanged width target resumes its prior timeline; its remaining duration controls completion callbacks, while newer glyph motion is allowed to finish independently.

Regression tests exercise 40 successive updates at 60 ms intervals, numeric fade continuity through repeated edits, centered container edge continuity through empty values, and a resumed width that completes before the latest glyph animation. The demo offers a centered **Run burst** sequence every 120 ms, plus Clear and Restart.

## Native boundaries and remaining differences

Passing the corpus establishes parity for those cases, not universal or pixel-identical equivalence. The following boundaries are explicit:

- Native SwiftUI font metrics, line boxes, rasterization, and layout scheduling replace DOM/CSS/WAAPI. Numeric edge masks approximate the CSS `0.15em` band using a proportion of the native line box. These affect pixels and exact frame timing.
- Foundation ICU Unicode word boundaries replace `Intl.Segmenter`. Dictionary-based language segmentation and ICU versions may differ. The supplied locale is used for numeric decimal matching/formatting; native word boundary tailoring is not a complete locale-specific Intl implementation.
- Native character splitting preserves extended grapheme clusters. Upstream changed-word splitting uses UTF-16 code units, which can split emoji/combining sequences. We do not reproduce malformed surrogate fragments.
- Right-to-left environments use unanimated native `Text` to preserve correct shaping. Full animated bidi parity remains unverified.
- Springs and interrupted container carry use upstream’s rounded sample tables. Native floating-point evaluation and frame scheduling can still differ from CSS animation playback.
- Native measurement occurs during SwiftUI layout. A burst of values coalesced before a layout pass need not produce all intermediate browser update callbacks.
- Critically damped springs use the analytic finite limit; invalid physics parameters are sanitized. The reference formula has a singularity at exact critical damping; that defect is not reproduced.
- A one-million-cell limit also protects character-level LCS allocations in native code. Beyond it, native character matching declines a pairing; upstream only bounds the outer word work.
- CSS easing strings, CSS debug overlays, arbitrary HTML wrappers, rich text, and browser text selection are outside the Swift API. The default line behavior is upstream’s **nowrap**, with explicit newline support.

The library’s earlier simplified matcher, always-grapheme segmentation, generic SwiftUI enter/exit transitions, 50% exit shrink, automatic word wrapping, and numericText-based digit rolling have been replaced.

## Native measurement correction (0.1.1)

A changing named coordinate space could transiently return global child frames during SwiftUI layout. In the counter reproduction, a digit's local Y became approximately 670 points after changing the motion preset. Measurement probes now resolve bounds anchors directly, avoiding that fallback. Verified in the scrolled counter with preset changes and repeated increments.

The no-argument spring preset intentionally uses faster physical parameters (1 / 360 / 30). Explicit 1 / 100 / 10 retains the upstream spring. Opt-in native `Spring` values use SwiftUI's solver, with a 10-second settling cap; they are an additional native API, not an upstream sampled-curve claim.
