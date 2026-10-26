import CoreGraphics

/// Every size used by the shape. DESIGN.md documents these numbers; keep the two in sync.
public enum IslandMetrics {
    /// Width of each leading/trailing slot beside the camera, before the width setting.
    public static func slotWidth(height: CGFloat) -> CGFloat {
        (height * 1.15).rounded()
    }

    /// Width of each region beside the camera ("ear"). The width setting widens it.
    public static func earWidth(_ appearance: NotchAppearance, height: CGFloat) -> CGFloat {
        let slot = slotWidth(height: height)
        return max((slot * 0.8).rounded(), (slot + (appearance.width - 180) / 2).rounded())
    }

    public static func expandedWidth(_ appearance: NotchAppearance) -> CGFloat {
        min(max(appearance.width + 190, 360), 560)
    }

    /// Height of the content area of each expanded view. The shape adds the notch strip above it
    /// and padding below.
    public enum ContentHeight {
        public static let nowPlaying: CGFloat = 140
        public static let timer: CGFloat = 76
        public static let call: CGFloat = 72
        public static let drop: CGFloat = 100
        public static let timerFinished: CGFloat = 72
        /// The row of app buttons in the music view when several apps are playing.
        public static let mediaSwitcher: CGFloat = 38
        /// Tallest expanded content; sizes the window.
        public static let maximum: CGFloat = max(nowPlaying + mediaSwitcher, Nook.launcherBody + Nook.bodyTopInset)
    }

    /// The Home, Tray and Mirror tabs share one fixed-size "nook", like the paid notch apps:
    /// wide and short, with widgets side by side rather than stacked.
    public enum Nook {
        public static let width: CGFloat = 560
        /// Area below the tab header, which sits in the strip beside the camera.
        public static let body: CGFloat = 120
        /// Extra room between the strip and the body, so the body sits as far below
        /// the strip as it does above the bottom edge.
        public static let bodyTopInset: CGFloat = 10
        public static let row: CGFloat = 30
        public static let rowGap: CGFloat = 8
        public static let mediaCardWidth: CGFloat = 210
        /// The grid of features gets more height than the other views, so its tiles can breathe.
        public static let launcherBody: CGFloat = 170
        public static let launcherTile: CGFloat = 76
        public static let launcherGap: CGFloat = 10
        /// Elongated layout: Home, Tray, Clipboard and the grid stretch across the top of the
        /// screen, this wide at most, and never closer than `elongatedEdge` to either side.
        public static let elongatedMaxWidth: CGFloat = 1240
        public static let elongatedEdge: CGFloat = 40
    }

    /// Space between the notch strip and the content, and below the content.
    public static let notchContentGap: CGFloat = 2
    public static let notchBottomPadding: CGFloat = 14
    public static let notchExpandedRadius: CGFloat = 30
    /// Concave shoulders where the shape meets the top edge, like the real notch.
    public static let compactFlare: CGFloat = 6
    public static let expandedFlare: CGFloat = 10
    /// Minimum width of each alert ear, so "Low Battery" fits beside the camera.
    public static let alertEarWidth: CGFloat = 128
    /// Ear width for alerts that show a name (calendar events, shortcuts).
    public static let namedAlertEarWidth: CGFloat = 156
    /// Ear width for the volume and brightness indicator.
    public static let levelEarWidth: CGFloat = 96

    /// Room around the content for the shadow.
    public static let windowMargin: CGFloat = 48
    /// Closest the widest view may come to a screen edge.
    public static let screenEdgeInset: CGFloat = 8
    /// How much a hovered compact shape grows (horizontal each side, vertical).
    public static let hoverGrowth = CGSize(width: 3, height: 2)
    /// Extra hit area around the shape so the pointer doesn't have to be pixel-perfect.
    public static let hitSlop: CGFloat = 4
    /// Displays without a notch get a virtual one at the top centre, the size of a MacBook's.
    /// It's only drawn while something is showing, or once the pointer rests on its spot.
    public static let virtualNotchWidth: CGFloat = 180
    /// Never shorter than this, so the tabs and content beside it fit as they do on a MacBook.
    public static let virtualNotchMinHeight: CGFloat = 32
}

/// Which widgets the Home tab shows.
public struct HomeContent: Equatable, Sendable {
    public var hasMedia: Bool
    public var hasEvent: Bool
    public var hasTimer: Bool
    public var hasShortcuts: Bool
    /// More than one app is playing, so the music view shows a row to switch between them.
    public var hasMediaSwitcher: Bool

    public init(hasMedia: Bool = false, hasEvent: Bool = false, hasTimer: Bool = true, hasShortcuts: Bool = false, hasMediaSwitcher: Bool = false) {
        self.hasMedia = hasMedia
        self.hasEvent = hasEvent
        self.hasTimer = hasTimer
        self.hasShortcuts = hasShortcuts
        self.hasMediaSwitcher = hasMediaSwitcher
    }

    /// Rows in the widget column (calendar, timer, shortcuts).
    public var rowCount: Int {
        [hasEvent, hasTimer, hasShortcuts].filter { $0 }.count
    }

    /// Every row fits beside the media card without scrolling.
    public var fitsInNook: Bool {
        typealias Nook = IslandMetrics.Nook
        let rows = CGFloat(rowCount)
        return rows * Nook.row + max(0, rows - 1) * Nook.rowGap <= Nook.body
    }
}
