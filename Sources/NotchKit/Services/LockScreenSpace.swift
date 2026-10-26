import AppKit

/// Puts a window on the Lock Screen. macOS draws the Lock Screen above every normal window, so the
/// only way in is a private window-server space set to the Lock Screen's level (the approach used
/// by SkyLightWindow and LockWidget). The functions are looked up at run time: if a future macOS
/// removes one, `make()` returns nil and the feature simply isn't offered.
@MainActor
final class LockScreenSpace {
    private typealias MainConnection = @convention(c) () -> Int32
    // Signatures as SkyLightWindow declares them, which is known to work on current macOS.
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceDestroy = @convention(c) (Int32, Int32) -> Int32
    private typealias SpaceSetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias Spaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    /// The window server's level for things drawn over the Lock Screen (notifications there).
    /// 100 is Setup Assistant's and sits under the Lock Screen; 300 is the Lock Screen itself.
    private static let lockScreenLevel: Int32 = 400

    private let connection: Int32
    private let create: SpaceCreate
    private let destroy: SpaceDestroy
    private let setLevel: SpaceSetLevel
    private let show: Spaces
    private let hide: Spaces
    private let addWindows: AddWindows
    private var space: Int32?

    /// Nil when this macOS doesn't have the functions.
    static func make() -> LockScreenSpace? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else { return nil }
        func load<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let connection = load("SLSMainConnectionID", as: MainConnection.self),
              let create = load("SLSSpaceCreate", as: SpaceCreate.self),
              let destroy = load("SLSSpaceDestroy", as: SpaceDestroy.self),
              let setLevel = load("SLSSpaceSetAbsoluteLevel", as: SpaceSetLevel.self),
              let show = load("SLSShowSpaces", as: Spaces.self),
              let hide = load("SLSHideSpaces", as: Spaces.self),
              let addWindows = load("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindows.self) else { return nil }
        return LockScreenSpace(connection: connection(), create: create, destroy: destroy, setLevel: setLevel,
                               show: show, hide: hide, addWindows: addWindows)
    }

    private init(connection: Int32, create: @escaping SpaceCreate, destroy: @escaping SpaceDestroy, setLevel: @escaping SpaceSetLevel,
                 show: @escaping Spaces, hide: @escaping Spaces, addWindows: @escaping AddWindows) {
        self.connection = connection
        self.create = create
        self.destroy = destroy
        self.setLevel = setLevel
        self.show = show
        self.hide = hide
        self.addWindows = addWindows
    }

    /// Moves the window into the Lock Screen space, creating the space the first time. Call it
    /// before ordering the window in.
    @discardableResult
    func place(_ window: NSWindow) -> Bool {
        let space = space ?? makeSpace()
        guard space != 0 else { return false }
        // Results aren't checked: on macOS 27 SLSShowSpaces no longer returns 0 even when it works.
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
        return true
    }

    /// Removes the space; its windows go with it.
    func tearDown() {
        guard let space else { return }
        _ = hide(connection, [NSNumber(value: space)] as CFArray)
        _ = destroy(connection, space)
        self.space = nil
    }

    private func makeSpace() -> Int32 {
        let space = create(connection, 1, 0)
        guard space != 0 else { return 0 }
        _ = setLevel(connection, space, Self.lockScreenLevel)
        _ = show(connection, [NSNumber(value: space)] as CFArray)
        self.space = space
        return space
    }
}
