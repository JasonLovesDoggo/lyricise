import AppKit
import Darwin

/// WindowServer backdrop blur, matching Ghostty's numeric macOS blur radius.
/// This private API is resolved at runtime so a future macOS removal does not
/// prevent the application from launching. It never blurs the app's text.
/// Reference: ghostty-org/ghostty v1.2.3, src/apprt/embedded.zig:2016–2044.
@MainActor final class WindowBlur {
    private typealias ConnectionFunction = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias BlurFunction = @convention(c) (UnsafeMutableRawPointer, UInt, Int32) -> Int32

    // Keep the handle alive for as long as the resolved function pointers live.
    private static let framework = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        RTLD_LAZY | RTLD_LOCAL
    )
    private static let connection: ConnectionFunction? = {
        guard let framework, let symbol = dlsym(framework, "CGSDefaultConnectionForThread") else { return nil }
        return unsafeBitCast(symbol, to: ConnectionFunction.self)
    }()
    private static let setRadius: BlurFunction? = {
        guard let framework, let symbol = dlsym(framework, "CGSSetWindowBackgroundBlurRadius") else { return nil }
        return unsafeBitCast(symbol, to: BlurFunction.self)
    }()

    /// Call after creating/showing the window and after radius changes.
    /// Zero removes an existing blur. False means unavailable or rejected;
    /// leave the ordinary transparent background in place in that case.
    @discardableResult static func apply(radius: Int, window: NSWindow) -> Bool {
        guard (0...100).contains(radius), window.windowNumber > 0,
              let connection, let setRadius, let connectionID = connection()
        else { return false }
        let effectiveRadius = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 0 : radius
        return setRadius(connectionID, UInt(window.windowNumber), Int32(effectiveRadius)) == 0
    }
}
