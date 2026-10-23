import AppKit
import Combine

/// Publishes which displays are showing a full-screen app (a full-screen video in the
/// browser, a game, a full-screen window), so the island can step out of the way there.
/// macOS gives every display a current space, and full-screen spaces have their own type;
/// the private SkyLight call is resolved at runtime, and without it nothing is ever hidden.
@MainActor
final class FullScreenMonitor: ObservableObject {
    /// Frames of the screens whose current space is a full-screen one.
    @Published private(set) var fullScreenFrames: [CGRect] = []

    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias CopySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let api: (connection: Int32, copySpaces: CopySpacesFn)? = {
        guard let sl = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let connection = dlsym(sl, "SLSMainConnectionID").map({ unsafeBitCast($0, to: MainConnectionFn.self) }),
              let copySpaces = dlsym(sl, "SLSCopyManagedDisplaySpaces").map({ unsafeBitCast($0, to: CopySpacesFn.self) })
        else { return nil }
        return (connection(), copySpaces)
    }()

    /// The space type macOS uses for full-screen apps.
    private static let fullScreenSpaceType = 4

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSoon() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSoon() }
        }
        refresh()
    }

    /// Spaces switch with an animation; look again once it has settled.
    private func refreshSoon() {
        refresh()
        for delay in [0.4, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh() }
        }
    }

    private func refresh() {
        guard let api = Self.api,
              let displays = api.copySpaces(api.connection)?.takeRetainedValue() as? [[String: Any]] else { return }
        var frames: [CGRect] = []
        for display in displays {
            let current = display["Current Space"] as? [String: Any]
            guard current?["type"] as? Int == Self.fullScreenSpaceType else { continue }
            let id = display["Display Identifier"] as? String ?? ""
            // "Main" means all displays share one set of spaces.
            let screens = id == "Main" ? NSScreen.screens : NSScreen.screens.filter { $0.uuidString == id }
            frames += screens.map(\.frame)
        }
        if frames != fullScreenFrames { fullScreenFrames = frames }
    }
}

private extension NSScreen {
    /// The display's UUID, as space listings name it.
    var uuidString: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
