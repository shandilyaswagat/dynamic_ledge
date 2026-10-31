import AppKit
import Testing
import SwiftUI
@testable import NotchKit

@MainActor
@Suite("Scrolling media title")
struct ScrollingTitleTests {
    @Test func scrollsOnlyWhenLongAndPlaying() {
        let view = ScrollingTitleView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        view.layoutSubtreeIfNeeded()
        let track = view.layer!.sublayers!.first!
        view.update(title: "A song title much too long to fit in the available space", isPlaying: true, fontSize: 15)
        #expect(track.animation(forKey: "scroll") != nil)
        view.update(title: "A song title much too long to fit in the available space", isPlaying: false, fontSize: 15)
        #expect(track.animation(forKey: "scroll") == nil)
        view.update(title: "Short", isPlaying: true, fontSize: 15)
        #expect(track.animation(forKey: "scroll") == nil)
    }

    @Test func pausedTitleDrawsVisibleText() throws {
        let title = MediaTitle(title: "A song title that is longer than the available space", isPlaying: false, fontSize: 15)
            .frame(width: 150)
        let image = try #require(ImageRenderer(content: title).nsImage)
        let data = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        var rowsWithText = Set<Int>()
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let pixel = bitmap.colorAt(x: x, y: y), pixel.alphaComponent > 0.1 {
                    rowsWithText.insert(y)
                }
            }
        }
        // An almost-empty stripe is the reported regression; letters need real height.
        #expect(rowsWithText.count >= 8)
    }

    @Test func titleChangeAndResizeUpdateTheAnimation() {
        let view = ScrollingTitleView(frame: NSRect(x: 0, y: 0, width: 500, height: 20))
        view.update(title: "An example song title", isPlaying: true, fontSize: 15)
        let track = view.layer!.sublayers!.first!
        #expect(track.animation(forKey: "scroll") == nil)
        view.setFrameSize(NSSize(width: 50, height: 20))
        view.layout()
        #expect(track.animation(forKey: "scroll") != nil)
        view.update(title: "New", isPlaying: true, fontSize: 15)
        #expect(track.animation(forKey: "scroll") == nil)
        #expect(view.accessibilityLabel() == "New")
    }
}
