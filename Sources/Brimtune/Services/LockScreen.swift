import AppKit
import Combine

/// Publishes whether the session is locked, from the system's lock notifications.
@MainActor
final class LockMonitor: ObservableObject {
    @Published private(set) var isLocked = false

    init() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            brimtuneLog("screen locked")
            MainActor.assumeIsolated { self?.isLocked = true }
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            brimtuneLog("screen unlocked")
            MainActor.assumeIsolated { self?.isLocked = false }
        }
    }
}

/// Ordinary windows can't appear above the lock screen. The window server does
/// render "spaces" with a high absolute level there, so windows that should stay
/// visible while locked are moved into one such space (the technique used by
/// notch utilities). The private calls are resolved at runtime; if any is missing
/// the window simply stays a normal window.
enum LockScreenSpace {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias SpaceCreateFn = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetLevelFn = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpacesFn = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsFn = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private static let api: (connection: Int32, space: Int32, add: AddWindowsFn)? = {
        guard let sl = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let mainConnection = dlsym(sl, "SLSMainConnectionID").map({ unsafeBitCast($0, to: MainConnectionFn.self) }),
              let create = dlsym(sl, "SLSSpaceCreate").map({ unsafeBitCast($0, to: SpaceCreateFn.self) }),
              let setLevel = dlsym(sl, "SLSSpaceSetAbsoluteLevel").map({ unsafeBitCast($0, to: SpaceSetLevelFn.self) }),
              let show = dlsym(sl, "SLSShowSpaces").map({ unsafeBitCast($0, to: ShowSpacesFn.self) }),
              let add = dlsym(sl, "SLSSpaceAddWindowsAndRemoveFromSpaces").map({ unsafeBitCast($0, to: AddWindowsFn.self) })
        else { return nil }
        let cid = mainConnection()
        let space = create(cid, 1, 0)
        // 400 is the level lock-screen notifications use; lower levels sit under the lock shield.
        _ = setLevel(cid, space, 400)
        _ = show(cid, [space] as CFArray)
        return (cid, space, add)
    }()

    @discardableResult
    static func adopt(_ window: NSWindow) -> Bool {
        guard let api, window.windowNumber > 0 else {
            brimtuneLog("lock-screen space unavailable")
            return false
        }
        let ok = api.add(api.connection, api.space, [window.windowNumber] as CFArray, 7) == 0
        if !ok { brimtuneLog("could not move window %d to lock-screen space", window.windowNumber) }
        return ok
    }
}
