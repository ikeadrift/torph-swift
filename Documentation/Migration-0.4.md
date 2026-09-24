# Migrating to 0.4

Version 0.4 intentionally removes the old effect API. There are no deprecated aliases. Text matching, default motion timings, callbacks, layout, and native `Spring` support remain unchanged. Default entrance blur remains 2 points.

## Common configurations

Before:

```swift
TextMorph(message, configuration: .init(
    entrance: .init(blurRadius: 2),
    scaling: .none,
    exitBlurRadius: 2
))
```

After:

```swift
TextMorph(message, configuration: .init(effects: .fadeAndBlur()))
```

Custom appearance:

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

## Property mapping

| Removed 0.3 API | 0.4 replacement |
| --- | --- |
| `configuration.entrance.blurRadius` | `configuration.effects.entrance.blurRadius` |
| `configuration.exitBlurRadius` | `configuration.effects.exit.blurRadius` |
| `configuration.scaling.entrance` | `configuration.effects.entrance.scale` |
| `configuration.scaling.exit` | `configuration.effects.exit.scale` |
| `scaling.groupReplacements = false` | `effects.replacementScaling = .individual` |
| Group entrance/exit factors | `effects.replacementScaling = .grouped(entrance:exit:)` |
| `scaling: .none` | Set both directional scales to 1 and replacement scaling to `.individual`; `.fade` and `.fadeAndBlur()` do this for you |
| `scale: false` | Set `effects.exit.scale = 1`; if using `.grouped`, also set its `exit` to 1 |
| Stagger, blur stagger, stagger curve, and spread | Removed; delete these arguments |

`ReplacementScaling` is an enum: `.individual` has no hidden group factors, while `.grouped` explicitly supplies the two override factors. Each text run uses its own center in individual mode; an intact word remains a run. This setting controls scaling only, not how words match or how replacement groups fade.

The demo uses the library's `.standard`, `.fade`, and `.fadeAndBlur()` presets directly. All three return complete `Effects` values that you can customize before passing them to `TextMorphConfiguration`.

For pre-1.0 releases, use an explicit minor-version range if you want to adopt future breaking changes deliberately:

```swift
.package(url: "https://github.com/ikeadrift/torph-swift.git", .upToNextMinor(from: "0.4.0"))
```
