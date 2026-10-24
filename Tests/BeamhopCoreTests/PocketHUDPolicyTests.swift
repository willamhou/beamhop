import XCTest
@testable import BeamhopCore

/// Pocket HUD chip policy (owner UX pass 2026-10-24): visibility is count-driven with an
/// opt-out, idle opacity is setting/hover-driven, and the persisted drag position is
/// clamped into the visible frame. Pure functions — no UI, no UserDefaults side effects.
final class PocketHUDPolicyTests: XCTestCase {
    // MARK: visibility

    func testVisibleWhenCountPositive() {
        XCTAssertTrue(PocketHUDPolicy.isVisible(count: 1, hideWhenEmpty: true))
        XCTAssertTrue(PocketHUDPolicy.isVisible(count: 1, hideWhenEmpty: false))
        XCTAssertTrue(PocketHUDPolicy.isVisible(count: 3, hideWhenEmpty: true))
    }

    func testHiddenWhenEmptyUnlessSettingOff() {
        XCTAssertFalse(PocketHUDPolicy.isVisible(count: 0, hideWhenEmpty: true))
        XCTAssertTrue(PocketHUDPolicy.isVisible(count: 0, hideWhenEmpty: false))
        XCTAssertFalse(PocketHUDPolicy.isVisible(count: -2, hideWhenEmpty: true))
    }

    // MARK: idle opacity

    func testOpacityFadesOnlyWhenIdleFadeOnAndNotHovered() {
        XCTAssertEqual(PocketHUDPolicy.opacity(idleFade: true, hovered: false), 0.55)
        XCTAssertEqual(PocketHUDPolicy.opacity(idleFade: true, hovered: true), 1.0)
        XCTAssertEqual(PocketHUDPolicy.opacity(idleFade: false, hovered: false), 1.0)
        XCTAssertEqual(PocketHUDPolicy.opacity(idleFade: false, hovered: true), 1.0)
    }

    // MARK: persisted origin parsing

    func testParseOriginRoundTrips() {
        let p = CGPoint(x: 120.5, y: 64.25)
        XCTAssertEqual(PocketHUDPolicy.parseOrigin(PocketHUDPolicy.formatOrigin(p)), p)
    }

    func testParseOriginRejectsGarbage() {
        XCTAssertNil(PocketHUDPolicy.parseOrigin(nil))
        XCTAssertNil(PocketHUDPolicy.parseOrigin(""))
        XCTAssertNil(PocketHUDPolicy.parseOrigin("abc"))
        XCTAssertNil(PocketHUDPolicy.parseOrigin("1,2,3"))
        XCTAssertNil(PocketHUDPolicy.parseOrigin("1"))
        XCTAssertNil(PocketHUDPolicy.parseOrigin("1;2"))
    }

    // MARK: clamping (never strand the chip off-screen)

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let chip = CGSize(width: 200, height: 36)

    func testClampedOriginKeepsInside() {
        let p = CGPoint(x: 1000, y: 100)
        XCTAssertEqual(PocketHUDPolicy.clampedOrigin(p, panelSize: chip, visibleFrame: screen), p)
    }

    func testClampedOriginPullsBackFromRightAndTop() {
        // Beyond the right/bottom edge: snaps so the chip stays fully visible.
        let far = CGPoint(x: 5000, y: 5000)
        XCTAssertEqual(PocketHUDPolicy.clampedOrigin(far, panelSize: chip, visibleFrame: screen),
                       CGPoint(x: screen.maxX - chip.width, y: screen.maxY - chip.height))
    }

    func testClampedOriginPullsBackFromNegative() {
        let neg = CGPoint(x: -500, y: -300)
        XCTAssertEqual(PocketHUDPolicy.clampedOrigin(neg, panelSize: chip, visibleFrame: screen),
                       CGPoint(x: screen.minX, y: screen.minY))
    }

    func testClampedOriginHandlesFrameSmallerThanPanel() {
        // Degenerate frame: max() guards keep the result at minX/minY instead of NaN/flip.
        let tiny = CGRect(x: 0, y: 0, width: 50, height: 20)
        let result = PocketHUDPolicy.clampedOrigin(CGPoint(x: 10, y: 10), panelSize: chip, visibleFrame: tiny)
        XCTAssertEqual(result, CGPoint(x: 0, y: 0))
    }
}
