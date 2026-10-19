import Foundation

/// Shared by the capture guard and panel focus recovery. PID matching also works for the
/// SwiftPM executable, whose bundle identifier is not necessarily com.beamhop.app.
public enum CaptureFocusPolicy {
    public static func isSelf(sourcePID: Int32, sourceBundleID: String, ownPID: Int32) -> Bool {
        sourcePID == ownPID || sourceBundleID == "com.beamhop.app"
    }

    /// Restore only while Beamhop still owns focus. A click into another app, an open Inbox
    /// window, a newly opened panel, or an exited source must always win over restoration.
    public static func shouldRestore(sourcePID: Int32, ownPID: Int32, frontmostPID: Int32?,
                                     sourceTerminated: Bool, hasVisibleBeamhopWindow: Bool) -> Bool {
        sourcePID != ownPID && frontmostPID == ownPID
            && !sourceTerminated && !hasVisibleBeamhopWindow
    }
}
