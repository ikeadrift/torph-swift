import SwiftUI

/// Torph's word/character matching and FLIP motion, rendered with native SwiftUI text.
public struct TextMorph: View {
    private let text: String
    private let configuration: TextMorphConfiguration
    private let cursorIndex: Int?
    private let onAnimationStart: (() -> Void)?
    private let onAnimationComplete: (() -> Void)?
    private let onAnimationCancel: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var segments: [MorphSegment]
    @State private var request: MorphDiff?
    @State private var measurementID = UUID()
    @State private var trajectories: [MorphTrajectory] = []
    @State private var hasMeasured = false
    @State private var activeAnimation: UUID?
    @State private var renderAnimation: UUID?
    @State private var completionDeadline = 0.0
    @State private var renderDeadline = 0.0
    @State private var sizeMotion: MorphSizeMotion?
    @State private var settledSize = CGSize.zero

    public init(_ text: String, configuration: TextMorphConfiguration = .init(), cursorIndex: Int? = nil,
                onAnimationStart: (() -> Void)? = nil,
                onAnimationComplete: (() -> Void)? = nil,
                onAnimationCancel: (() -> Void)? = nil) {
        self.text = text; self.configuration = configuration; self.cursorIndex = cursorIndex
        self.onAnimationStart = onAnimationStart; self.onAnimationComplete = onAnimationComplete
        self.onAnimationCancel = onAnimationCancel
        _segments = State(initialValue: TextMatcher.segment(text,locale: configuration.locale,numbers: configuration.numbers))
    }

    private var disabled: Bool {
        configuration.disabled || (reduceMotion && configuration.respectReducedMotion) || layoutDirection == .rightToLeft
    }

    public var body: some View {
        Group {
            if disabled { Text(verbatim: text) }
            else {
                TimelineView(.animation(paused: renderAnimation == nil)) { tick in
                    let now = tick.date.timeIntervalSinceReferenceDate
                    let size = sizeMotion?.size(at: now) ?? settledSize
                    MeasurementProbe(segments: segments, id: measurementID, side: .next,
                                     configuration: configuration)
                        .opacity(hasMeasured ? 0 : 1)
                        .background(alignment: .topLeading) {
                            if let request {
                                MeasurementProbe(segments: request.preparedPrevious, id: measurementID,
                                                 side: .previous, configuration: configuration).hidden()
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if hasMeasured {
                                ZStack(alignment: .topLeading) {
                                    ForEach(Array(trajectories.enumerated()),id: \.offset) { _, trajectory in
                                        let presentation = trajectory.presentation(at: now)
                                        MotionGlyph(segment: trajectory.segment,presentation: presentation)
                                    }
                                }
                                .frame(width: 0,height: 0,alignment: .topLeading)
                            }
                        }
                        .frame(width: hasMeasured ? max(0,size.width) : nil,
                               height: hasMeasured ? max(0,size.height) : nil,alignment: .topLeading)
                }
                .onPreferenceChange(MeasurementsKey.self, perform: measured)
            }
        }
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
        .onChange(of: text) { _, _ in update() }
        .onChange(of: configuration) { _, _ in update(reset: true) }
        .onChange(of: reduceMotion) { _, _ in update(reset: true) }
        .onChange(of: layoutDirection) { _, _ in update(reset: true) }
        .task(id: activeAnimation) {
            guard let token = activeAnimation else { return }
            try? await Task.sleep(for: .seconds(max(0,completionDeadline-Date.timeIntervalSinceReferenceDate)))
            guard !Task.isCancelled, activeAnimation == token else { return }
            activeAnimation = nil
            sizeMotion = nil
            // Upstream's completion follows the width animation. Resumed width can
            // finish before the latest glyph animations; don't snap those to rest.
            onAnimationComplete?()
        }
        .task(id: renderAnimation) {
            guard let token = renderAnimation else { return }
            try? await Task.sleep(for: .seconds(max(0,renderDeadline-Date.timeIntervalSinceReferenceDate)))
            guard !Task.isCancelled, renderAnimation == token else { return }
            renderAnimation = nil
            settleGlyphs()
        }
        .onDisappear {
            // Upstream teardown clears animations without reporting an animation event.
            activeAnimation = nil
            renderAnimation = nil
            sizeMotion = nil
            settleGlyphs()
        }
    }

    private func settleGlyphs() {
        trajectories = trajectories.filter { !$0.exiting }.map { item in
            var item = item; item.start = item.end; item.began = 0
            item.inheritedSlide = nil; item.inheritedFade = nil; return item
        }
    }

    private func update(reset: Bool = false) {
        if disabled || reset || !hasMeasured {
            if activeAnimation != nil { activeAnimation = nil; onAnimationCancel?() }
            segments = TextMatcher.segment(text,locale: configuration.locale,numbers: configuration.numbers)
            request = nil; trajectories = []; hasMeasured = false; sizeMotion = nil; renderAnimation = nil; measurementID = UUID()
            return
        }
        // No view transition is allowed to invent a position for a newly inserted glyph.
        // Both layouts are measured first; MorphMotion explicitly supplies its anchor.
        let diff = TextMatcher.diff(from: segments,to: text,numbers: configuration.numbers,locale: configuration.locale,cursorIndex: cursorIndex)
        request = diff; segments = diff.segments; measurementID = UUID()
    }

    private func measured(_ values: [MeasurementKey: CGRect]) {
        let root = MeasurementKey(request: measurementID,side: .next,id: nil)
        guard let newBounds = values[root] else { return }
        func rects(_ side: MeasurementSide) -> [String: CGRect] {
            Dictionary(uniqueKeysWithValues: values.compactMap { key, value in
                guard key.request == measurementID && key.side == side, let id = key.id else { return nil }
                return (id,value)
            })
        }
        let next = rects(.next)
        guard next.count == segments.count else { return }
        let now = Date.timeIntervalSinceReferenceDate, curve = MorphCurve(configuration.timing)
        if let request {
            guard values[.init(request: measurementID,side: .previous,id: nil)] != nil else { return }
            let previous = rects(.previous)
            guard previous.count == request.preparedPrevious.count else { return }
            let oldSize = sizeMotion?.size(at: now) ?? settledSize
            onAnimationStart?()
            if activeAnimation != nil { onAnimationCancel?() }
            let lineCount = max(1,segments.filter { $0.text == "\n" }.count+1)
            trajectories = MorphMotion.plan(diff: request,oldRects: previous,newRects: next,previous: trajectories,
                                            now: now,curve: curve,lineHeight: newBounds.height/Double(lineCount),scaleExits: configuration.scale)
            sizeMotion = MorphSizeMotion(from: oldSize,to: newBounds.size,previous: sizeMotion,now: now,curve: curve,hold: segments.isEmpty)
            settledSize = newBounds.size
            completionDeadline = sizeMotion!.width.began+sizeMotion!.width.curve.duration
            renderDeadline = max(completionDeadline, trajectories.map { $0.began+$0.curve.duration }.max() ?? now)
            self.request = nil; activeAnimation = UUID(); renderAnimation = UUID(); hasMeasured = true
        } else if !hasMeasured {
            trajectories = segments.compactMap { segment in
                guard segment.text != "\n",let rect = next[segment.id] else { return nil }
                let p = MorphPresentation(rect: rect)
                return MorphTrajectory(segment: segment,start: p,end: p,began: 0,curve: curve)
            }
            settledSize = newBounds.size; hasMeasured = true
        } else if renderAnimation == nil && settledSize != newBounds.size {
            // Font / Dynamic Type / environment changed; update layout without text morphing.
            trajectories = segments.compactMap { segment in
                guard segment.text != "\n",let rect = next[segment.id] else { return nil }
                let p = MorphPresentation(rect: rect)
                return MorphTrajectory(segment: segment,start: p,end: p,began: 0,curve: curve)
            }
            settledSize = newBounds.size
        }
    }
}

private struct MotionGlyph: View {
    let segment: MorphSegment
    let presentation: MorphPresentation
    private var glyph: some View {
        Text(verbatim: segment.text)
            .fixedSize()
            .frame(width: presentation.rect.width,height: presentation.rect.height,alignment: .topLeading)
            .offset(y: presentation.slide)
    }
    var body: some View {
        Group {
            if segment.kind != nil {
                glyph.mask {
                    LinearGradient(stops: [.init(color: .clear,location: 0),.init(color: .black,location: 0.15),
                                           .init(color: .black,location: 0.85),.init(color: .clear,location: 1)],
                                   startPoint: .top,endPoint: .bottom)
                        .frame(width: presentation.rect.width+2*presentation.rect.height,height: presentation.rect.height)
                }
            } else { glyph }
        }
        .scaleEffect(presentation.scale,anchor: UnitPoint(x: presentation.origin.x,y: presentation.origin.y))
        .opacity(presentation.opacity)
        .offset(x: presentation.rect.minX,y: presentation.rect.minY)
        .allowsHitTesting(false)
    }
}

private enum MeasurementSide: Hashable { case previous, next }
private struct MeasurementKey: Hashable { let request: UUID; let side: MeasurementSide; let id: String? }
private struct MeasurementsKey: PreferenceKey {
    static let defaultValue: [MeasurementKey: CGRect] = [:]
    static func reduce(value: inout [MeasurementKey: CGRect],nextValue: () -> [MeasurementKey: CGRect]) {
        value.merge(nextValue(),uniquingKeysWith: { _,new in new })
    }
}
private struct GlyphAnchorsKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private struct MeasurementProbe: View {
    let segments: [MorphSegment]
    let id: UUID
    let side: MeasurementSide
    let configuration: TextMorphConfiguration
    private var space: MeasurementKey { .init(request: id,side: side,id: nil) }
    var body: some View {
        MorphLayout(alignment: configuration.alignment,lineSpacing: configuration.lineSpacing) {
            ForEach(segments) { segment in
                Text(verbatim: segment.text == "\n" ? " " : segment.text)
                    .fixedSize().opacity(segment.text == "\n" ? 0 : 1)
                    .layoutValue(key: GlyphKey.self,value: segment.text)
                    .anchorPreference(key: GlyphAnchorsKey.self, value: .bounds) { [segment.id: $0] }
            }
            Text(" ").fixedSize().hidden().layoutValue(key: ProbeKey.self,value: true)
        }
        // The upstream root is nowrap. Only explicit newlines create a new line.
        .fixedSize(horizontal: true,vertical: true)
        // Resolve child bounds directly into this probe's coordinates. A changing
        // named space can transiently fall back to global coordinates during layout.
        .backgroundPreferenceValue(GlyphAnchorsKey.self) { anchors in
            GeometryReader { geometry in
                let rects = anchors.reduce(into: [space: CGRect(origin: .zero, size: geometry.size)]) { result, item in
                    result[.init(request: id, side: side, id: item.key)] = geometry[item.value]
                }
                Color.clear.preference(key: MeasurementsKey.self, value: rects)
            }
        }
        .accessibilityHidden(true)
    }
}
public struct TextMorphConfiguration: Equatable, Sendable {
    public enum Timing: Equatable, Sendable {
        /// Torph's default cubic Bézier curve. Duration is in seconds.
        case easeOut(duration: Double = 0.4)
        case spring(mass: Double = 1, stiffness: Double = 360, damping: Double = 30, precision: Double = 0.001)
        /// Uses SwiftUI's spring solver directly, including custom initial velocity.
        case nativeSpring(Spring, initialVelocity: Double = 0)

        public static func spring(_ spring: Spring, initialVelocity: Double = 0) -> Self {
            .nativeSpring(spring, initialVelocity: initialVelocity)
        }
        case cubicBezier(x1: Double, y1: Double, x2: Double, y2: Double, duration: Double = 0.4)

    }

    public enum Alignment: Sendable { case leading, center, trailing }
    public var timing: Timing
    public var numbers: Bool
    public var scale: Bool
    public var disabled: Bool
    public var respectReducedMotion: Bool
    public var locale: Locale
    public var alignment: Alignment
    public var lineSpacing: CGFloat

    public init(
        timing: Timing = .easeOut(), numbers: Bool = true, scale: Bool = true,
        disabled: Bool = false, respectReducedMotion: Bool = true,
        locale: Locale = Locale(identifier: "en"), alignment: Alignment = .leading,
        lineSpacing: CGFloat = 0
    ) {
        self.timing = timing
        self.numbers = numbers
        self.scale = scale
        self.disabled = disabled
        self.respectReducedMotion = respectReducedMotion
        self.locale = locale
        self.alignment = alignment
        self.lineSpacing = lineSpacing
    }
}
