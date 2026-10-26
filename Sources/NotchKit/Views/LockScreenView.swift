import SwiftUI

/// The notch on the Lock Screen, drawn exactly as it is when the Mac is unlocked: the same
/// shape, the same compact activity beside the camera, the same springs. It grows out of the
/// notch when the Lock Screen appears and changes as the activity does.
struct LockScreenView: View {
    let model: IslandModel
    let metrics: ScreenMetrics
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let presentation = shown ? (model.lockScreenContent?.presentation ?? .hidden(peek: false)) : .hidden(peek: false)
        let layout = model.engine(for: metrics).layout(for: presentation, home: model.homeContent, hovering: false)
        ZStack(alignment: .topLeading) {
            IslandSurface(layout: layout, pulse: 0, liquid: false)
                .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
            IslandContentLayer(model: model, presentation: presentation, layout: layout)
                .allowsHitTesting(false)
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height, alignment: .topLeading)
        .animation(Motion.shape(to: presentation, reduceMotion: reduceMotion), value: presentation)
        .environment(\.colorScheme, .dark)
        .onAppear { shown = true }
    }
}
