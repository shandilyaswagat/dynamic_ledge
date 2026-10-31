import AppKit
import SwiftUI

/// Keep the still title in SwiftUI so pausing never clips Core Animation's text layer.
struct MediaTitle: View {
    let title: String
    let isPlaying: Bool
    let fontSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isPlaying && !reduceMotion {
                ScrollingTitle(title: title, isPlaying: true, fontSize: fontSize)
            } else {
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: fontSize * 19 / 15, alignment: .leading)
    }
}

/// Long titles travel through the available space only during playback. The render server
/// animates the text, so no timer runs in the app while the title is moving.
struct ScrollingTitle: NSViewRepresentable {
    let title: String
    let isPlaying: Bool
    let fontSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> ScrollingTitleView { ScrollingTitleView() }

    func updateNSView(_ view: ScrollingTitleView, context: Context) {
        view.update(title: title, isPlaying: isPlaying && !reduceMotion, fontSize: fontSize)
    }
}

final class ScrollingTitleView: NSView {
    private let track = CALayer()
    private let first = CATextLayer()
    private let second = CATextLayer()
    private var title = ""
    private var isPlaying = false
    private var fontSize: CGFloat = 15
    private var lastSize = CGSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = true
        layer?.addSublayer(track)
        track.addSublayer(first)
        track.addSublayer(second)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        render()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        render()
    }

    func update(title: String, isPlaying: Bool, fontSize: CGFloat) {
        guard self.title != title || self.isPlaying != isPlaying || self.fontSize != fontSize else { return }
        self.title = title
        self.isPlaying = isPlaying
        self.fontSize = fontSize
        setAccessibilityLabel(title)
        render()
    }

    private func render() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let attributed = NSAttributedString(string: title, attributes: attributes)
        let textWidth = ceil(attributed.size().width) + 2
        let scrolling = isPlaying && textWidth > size.width
        let gap = 32 * fontSize / 15
        let distance = textWidth + gap

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.removeAnimation(forKey: "scroll")
        track.frame = CGRect(origin: .zero, size: size)
        for text in [first, second] {
            text.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            text.string = attributed
            text.isWrapped = false
            text.alignmentMode = .left
            text.truncationMode = scrolling ? .none : .end
        }
        first.frame = CGRect(x: 0, y: 0, width: scrolling ? textWidth : size.width, height: size.height)
        second.frame = CGRect(x: distance, y: 0, width: textWidth, height: size.height)
        second.isHidden = !scrolling
        if scrolling {
            let animation = CABasicAnimation(keyPath: "sublayerTransform.translation.x")
            animation.fromValue = 0
            animation.toValue = -distance
            animation.duration = CFTimeInterval(distance / (25 * fontSize / 15))
            animation.repeatCount = .infinity
            track.add(animation, forKey: "scroll")
        }
        CATransaction.commit()
    }
}
