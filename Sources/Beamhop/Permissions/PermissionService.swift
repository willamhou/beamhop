import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// AX/CGPreflight only expose granted-vs-not (no notDetermined). Codex review.
enum PermState { case granted, denied }

/// Reads permission state + jumps to the right System Settings pane (URLs verified in Week 0 S6).
struct PermissionService {
    func accessibility() -> PermState { AXIsProcessTrusted() ? .granted : .denied }

    /// Reads screen-recording status. ⚠️ preflight does NOT prompt (codex review).
    func preflightScreenRecording() -> PermState {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// Actually triggers the screen-recording authorization dialog (Week 2 screenshots use this).
    func requestScreenRecording() { _ = CGRequestScreenCaptureAccess() }

    /// Triggers the system Accessibility prompt (the only AX call that shows UI).
    func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
    func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
