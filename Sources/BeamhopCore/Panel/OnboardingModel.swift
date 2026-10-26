import Combine
import Foundation

/// Durable evidence of local preparation only. No source content or agent completion claim.
public struct OnboardingProgress: Codable, Equatable {
    public var hasCaptured = false
    public var hasTransportReceipt: Bool { lastReceipt == .copied || lastReceipt == .prepared }
    public var needsRecovery = false
    public var lastHandoffID: String?
    public var lastReceipt: HopRecord.Status?
    public init() {}
}

/// Main-thread presentation interface; the controller supplies current permission state.
/// Tests inject a private defaults suite, never the user's application domain.
public final class OnboardingModel: ObservableObject {
    public enum Step: Equatable { case permission, capture, receiver, recovery, manualSubmission }
    @Published public private(set) var progress: OnboardingProgress
    @Published public private(set) var accessibilityGranted = false
    private let defaults: UserDefaults
    private let key = "beamhop.firstHandoff.v1"
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        progress =
            defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(OnboardingProgress.self, from: $0) }
            ?? .init()
        if progress.lastReceipt == .preparing {
            progress.lastReceipt = .failed
            progress.needsRecovery = true
            save()
        }
    }
    public var nextStep: Step {
        if !accessibilityGranted { return .permission }
        if progress.needsRecovery { return .recovery }
        if !progress.hasCaptured { return .capture }
        if !progress.hasTransportReceipt { return .receiver }
        return .manualSubmission
    }
    public func refreshAccessibility(granted: Bool) { accessibilityGranted = granted }
    public func captureSaved() {
        progress.hasCaptured = true
        save()
    }
    public func observe(_ activity: HopActivity) {
        if activity.kind == .started {
            progress.lastHandoffID = activity.id
            progress.lastReceipt = .preparing
            progress.needsRecovery = false
        } else {
            guard activity.id == progress.lastHandoffID else { return }
            switch activity.kind {
            case .copied, .prepared:
                progress.lastReceipt = activity.kind == .copied ? .copied : .prepared
                progress.needsRecovery = false
            case .failed, .interrupted:
                progress.lastReceipt = .failed
                progress.needsRecovery = true
            case .recovered: progress.needsRecovery = false
            default: return
            }
        }
        save()
    }
    private func save() {
        if let data = try? JSONEncoder().encode(progress) { defaults.set(data, forKey: key) }
    }
}
