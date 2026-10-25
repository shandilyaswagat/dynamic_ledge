import CoreGraphics

/// Every size used by the shape. DESIGN.md documents these numbers; keep the two in sync.
public enum IslandMetrics {
    /// Width of each leading/trailing slot in island style.
    public static func slotWidth(height: CGFloat) -> CGFloat {
        (height * 1.15).rounded()
    }

    /// Notch style: width of each region beside the camera ("ear"). The width setting widens it.
    public static func earWidth(_ appearance: NotchAppearance, height: CGFloat) -> CGFloat {
        let slot = slotWidth(height: height)
        return max((slot * 0.8).rounded(), (slot + (appearance.width - 180) / 2).rounded())
    }

    /// Island style compact size.
    public static func compactSize(_ appearance: NotchAppearance) -> CGSize {
        let height = appearance.height
        return CGSize(width: appearance.width + 2 * slotWidth(height: height), height: height)
    }

    public static func idleSize(_ appearance: NotchAppearance) -> CGSize {
        CGSize(width: appearance.width, height: appearance.height)
    }

    public static func bubbleGap(_ appearance: NotchAppearance) -> CGFloat {
        max(6, (appearance.height * 0.24).rounded())
    }

    /// Island style alert size.
    public static func alertSize(_ appearance: NotchAppearance) -> CGSize {
        CGSize(
            width: max(compactSize(appearance).width + 70, 300),
            height: appearance.height + 16
        )
    }

    public static func expandedWidth(_ appearance: NotchAppearance) -> CGFloat {
        min(max(appearance.width + 190, 360), 560)
    }

    /// Height of the content area of each expanded view. The shape adds padding (island) or the
    /// notch strip (notch) around it.
    public enum ContentHeight {
        public static let nowPlaying: CGFloat = 140
        public static let timer: CGFloat = 76
        public static let call: CGFloat = 72
        public static let drop: CGFloat = 100
        public static let timerFinished: CGFloat = 72
        /// Floating pill style: the Home/Tray/Mirror nook (header row plus body).
        public static let nook: CGFloat = 154
        /// The row of app buttons in the music view when several apps are playing.
        public static let mediaSwitcher: CGFloat = 38
        /// Tallest expanded content in either style; sizes the window.
        public static let maximum: CGFloat = nowPlaying + mediaSwitcher
    }

    /// The Home, Tray and Mirror tabs share one fixed-size "nook", like the paid notch apps:
    /// wide and short, with widgets side by side rather than stacked.
    public enum Nook {
        public static let width: CGFloat = 560
        /// Area below the tab header.
        public static let body: CGFloat = 120
        /// Floating pill style only; in notch style the header sits beside the camera.
        public static let header: CGFloat = 24
        public static let headerGap: CGFloat = 10
        /// Notch style: extra room between the strip and the body, so the body sits as far below
        /// the strip as it does above the bottom edge.
        public static let bodyTopInset: CGFloat = 10
        public static let row: CGFloat = 30
        public static let rowGap: CGFloat = 8
        public static let mediaCardWidth: CGFloat = 210
        /// The grid of features gets more height than the other views, so its tiles can breathe.
        public static let launcherBody: CGFloat = 170
        public static let launcherTile: CGFloat = 76
        public static let launcherGap: CGFloat = 10
    }

    /// Island style: vertical padding above and below expanded content.
    public static let islandExpandedPadding: CGFloat = 14
    /// Island style: the row above an open activity that holds the back button and its name.
    /// (Notch style puts it in the strip beside the camera instead.)
    public static let activityHeader: CGFloat = 26
    public static let islandExpandedRadius: CGFloat = 28
    /// Island style: corner radius of the small shapes as a share of their height.
    public static let islandCornerRatio: CGFloat = 0.38
    /// Notch style: space between the notch strip and the content, and below the content.
    public static let notchContentGap: CGFloat = 2
    public static let notchBottomPadding: CGFloat = 14
    public static let notchExpandedRadius: CGFloat = 30
    /// Concave shoulders where the shape meets the top edge, like the real notch.
    public static let compactFlare: CGFloat = 6
    public static let expandedFlare: CGFloat = 10
    /// Notch style: minimum width of each alert ear, so "Low Battery" fits beside the camera.
    public static let alertEarWidth: CGFloat = 128
    /// Notch style: ear width for alerts that show a name (calendar events, shortcuts).
    public static let namedAlertEarWidth: CGFloat = 156
    /// Notch style: ear width for the volume and brightness indicator.
    public static let levelEarWidth: CGFloat = 96
    /// Island style: width of the volume and brightness pill.
    public static let levelPillWidth: CGFloat = 240

    /// Room around the content for the shadow.
    public static let windowMargin: CGFloat = 48
    /// Closest the widest view may come to a screen edge.
    public static let screenEdgeInset: CGFloat = 8
    /// How much a hovered compact shape grows (horizontal each side, vertical).
    public static let hoverGrowth = CGSize(width: 3, height: 2)
    /// Extra hit area around the shape so the pointer doesn't have to be pixel-perfect.
    public static let hitSlop: CGFloat = 4
    /// Width of the virtual notch on displays without one.
    public static let virtualNotchWidth: CGFloat = 180
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
