import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenshotError: LocalizedError {
    case permissionDenied
    case noDisplay
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "未开启屏幕录制权限。Capture 已保留，但不会附加截图。"
        case .noDisplay:
            "找不到可截图的窗口或显示器。"
        case .encodingFailed:
            "截图已生成，但无法安全写入本地文件。"
        }
    }
}

protocol ScreenshotCapturing: Sendable {
    func capture(for capture: CaptureRecord) async throws -> URL
}

struct SystemScreenshotService: ScreenshotCapturing {
    func capture(for capture: CaptureRecord) async throws -> URL {
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenshotError.permissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let filter: SCContentFilter
        let size: CGSize

        if let window = content.windows.first(where: {
            $0.owningApplication?.processID == capture.provenance.processID && $0.isOnScreen
        }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
            size = window.frame.size
        } else if let display = content.displays.first {
            filter = SCContentFilter(display: display, excludingWindows: [])
            size = CGSize(width: display.width, height: display.height)
        } else {
            throw ScreenshotError.noDisplay
        }

        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(size.width))
        configuration.height = max(1, Int(size.height))
        configuration.showsCursor = true
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let destinationURL = try makeDestinationURL(captureID: capture.id)
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotError.encodingFailed
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destinationURL.path
        )
        return destinationURL
    }

    private func makeDestinationURL(captureID: String) throws -> URL {
        let manager = FileManager.default
        let support = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        let directory = support
            .appendingPathComponent("beamhop", isDirectory: true)
            .appendingPathComponent("screenshots", isDirectory: true)
            .appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        return directory.appendingPathComponent("\(captureID).png")
    }
}
