#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import Torph

@MainActor
private final class ConfigurationHarness: ObservableObject {
    @Published var text = "Set to ready"
    @Published var configuration = TextMorphConfiguration(timing: .easeOut(duration: 0.8))
    var starts = 0
    var cancellations = 0
    var completions = 0
}

private struct ConfigurationHarnessView: View {
    @ObservedObject var model: ConfigurationHarness
    var body: some View {
        TextMorph(model.text, configuration: model.configuration,
                  onAnimationStart: { model.starts += 1 },
                  onAnimationComplete: { model.completions += 1 },
                  onAnimationCancel: { model.cancellations += 1 })
            .font(.title)
            .frame(width: 500, height: 100)
    }
}

final class ConfigurationChangeTests: XCTestCase {
    /// Exercise the real SwiftUI onChange/measurement lifecycle: a settings edit
    /// used to clear trajectories and cancel the current animation immediately.
    @MainActor
    func testChangingEffectsMidMorphPreservesAnimationLifecycle() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let model = ConfigurationHarness()
        let host = NSHostingView(rootView: ConfigurationHarnessView(model: model))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        // Command-line XCTest has no NSApplication event loop. Explicitly drive
        // layout/display so older SwiftUI runtimes deliver measurement preferences.
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        model.text = "Setting as ready"
        for _ in 0..<150 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if model.starts == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.starts, 1, "The test must start a real measured morph")
        XCTAssertEqual(model.completions, 0)

        // Swap complete settings repeatedly while text is in flight.
        for blur in [4.0, 0.0, 4.0] {
            model.configuration.scaling = .none
            model.configuration.entrance = .init(blurRadius: blur)
            model.configuration.exitBlurRadius = blur
            model.configuration.timing = .spring()
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertEqual(model.cancellations, 0)
        XCTAssertEqual(model.starts, 1)
        for _ in 0..<150 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if model.completions == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.completions, 1)
        XCTAssertEqual(model.cancellations, 0)

        // Settings edits must not leave the next transition unable to start.
        model.text = "Set to ready"
        for _ in 0..<150 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if model.completions == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.starts, 2)
        XCTAssertEqual(model.completions, 2)
        XCTAssertEqual(model.cancellations, 0)
    }
}
#endif
